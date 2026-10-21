#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
native_root="$repo_root/native/age_signals"
fail() { echo "[age-signals-build] $1" >&2; exit 1; }

# Reuse the installed toolchain. Do not install SDK packages or change host settings.
if [ -z "${JAVA_HOME:-}" ] && [ "$(uname -s)" = Darwin ]; then
  export JAVA_HOME="$(/usr/libexec/java_home -v 17)"
fi
java_bin="${JAVA_HOME:+$JAVA_HOME/bin/}java"
command -v "$java_bin" >/dev/null || fail "JDK 17이 필요하다."
java_version="$("$java_bin" -version 2>&1 | sed -n '1p')"
[[ "$java_version" = *'"17.'* ]] || fail "기존 JDK 17을 JAVA_HOME으로 지정해야 한다."
if [ -z "${ANDROID_HOME:-}" ]; then
  if [ -n "${ANDROID_SDK_ROOT:-}" ]; then
    export ANDROID_HOME="$ANDROID_SDK_ROOT"
  elif [ -d "$HOME/Library/Android/sdk" ]; then
    export ANDROID_HOME="$HOME/Library/Android/sdk"
  fi
fi
[ -f "${ANDROID_HOME:-}/platforms/android-36/android.jar" ] || fail "설치된 Android SDK 36이 필요하다."

# This builds an unsigned library and JVM tests only; never an APK/AAB or device run.
bash "$native_root/gradlew" -p "$native_root" --no-daemon --console=plain \
  testReleaseUnitTest assembleRelease

library="$native_root/build/outputs/aar/starlit-age-signals-release.aar"
[ -s "$library" ] || fail "Age Signals AAR가 생성되지 않았다."
mkdir -p "$repo_root/addons/starlit_age_signals/bin" "$repo_root/build/age-signals"
cp "$library" "$repo_root/addons/starlit_age_signals/bin/starlit-age-signals-release.aar"
python3 - "$repo_root" "$library" <<'PY'
import hashlib
import json
import sys
import zipfile
from pathlib import Path

root = Path(sys.argv[1])
library = Path(sys.argv[2])
native = root / "native/age_signals"
sources = sorted(p for p in native.rglob("*") if p.is_file()
                 and not any(part in {"build", ".gradle"} for part in p.relative_to(native).parts)
                 and p.name != "local.properties")
sources += [root / "scripts/build-age-signals.sh"]
sources += sorted(p for p in (root / "addons/starlit_age_signals").rglob("*")
                  if p.is_file() and p.suffix in {".gd", ".cfg"})
digest = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
with zipfile.ZipFile(library) as archive:
    if "classes.jar" not in archive.namelist():
        raise SystemExit("Age Signals plugin AAR has no classes.jar")
report = {
    "kind": "library-compile-and-jvm-contract-only",
    "godot": "4.7.2.stable",
    "sdk": "com.google.android.play:age-signals:0.0.4",
    "sdkAarSha256": "0f47c1dcef35feb637d879cd7fffff555a19398b850b2cc9814f61f54876e989",
    "sdkSource": "https://dl.google.com/dl/android/maven2/com/google/android/play/age-signals/0.0.4/age-signals-0.0.4.aar",
    "aarSha256": digest(library),
    "sourceFiles": {str(p.relative_to(root)): digest(p) for p in sources},
    "deviceRuntimeVerified": False,
    "finalAabBuilt": False,
}
(root / "build/age-signals/provenance.json").write_text(json.dumps(report, indent=2) + "\n")
print("[age-signals-build] library SHA256 " + report["aarSha256"])
PY
