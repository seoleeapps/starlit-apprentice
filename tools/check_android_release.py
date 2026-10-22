#!/usr/bin/env python3
"""Read release inputs and the final AAB without contacting Play or a device."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import struct
import subprocess
import zipfile


ANDROID_NS = "http://schemas.android.com/apk/res/android"
PACKAGE = "com.seorilabs.starlitapprentice"
# These three exception types are defined by play-services-basement:18.9.0,
# required by the pinned Next-Gen Ads, UMP and Play Age Signals SDKs.
# They do not permit FirebaseApp, product SDKs, encoders or future namespaces.
GOOGLE_COMMON_EXCEPTIONS = frozenset({
    "Lcom/google/firebase/FirebaseException;",
    "Lcom/google/firebase/FirebaseApiNotAvailableException;",
    "Lcom/google/firebase/FirebaseExceptionMapper;",
})
RUNTIME_CONFIG = "assetPackInstallTime/assets/config/android_runtime.json"


def dex_firebase_types(data):
    # Android's standard DEX type_ids include both defined and referenced types.
    # Reject unsupported/container formats instead of silently inspecting part.
    if (len(data) < 112 or not re.fullmatch(rb"dex\n(?:035|037|038|039|040)\x00", data[:8])
            or struct.unpack_from("<III", data, 32) != (len(data), 112, 0x12345678)):
        raise ValueError("unsupported or malformed DEX header")

    def table(header_offset, stride):
        count, offset = struct.unpack_from("<II", data, header_offset)
        if count and (offset < 112 or offset + count * stride > len(data)):
            raise ValueError("DEX table outside file")
        return count, offset

    string_count, strings = table(56, 4)
    type_count, types = table(64, 4)
    class_count, classes = table(96, 32)
    descriptors = []
    for index in range(type_count):
        string_index = struct.unpack_from("<I", data, types + index * 4)[0]
        if string_index >= string_count:
            raise ValueError("invalid DEX descriptor index")
        offset = struct.unpack_from("<I", data, strings + string_index * 4)[0]
        if offset < 112 or offset >= len(data):
            raise ValueError("invalid DEX string offset")
        for shift in range(0, 35, 7):
            if offset >= len(data):
                raise ValueError("truncated DEX string length")
            byte = data[offset]
            offset += 1
            if byte < 128:
                break
        else:
            raise ValueError("invalid DEX string length")
        end = data.find(b"\0", offset)
        if end < 0:
            raise ValueError("unterminated DEX descriptor")
        # Other class names may use modified UTF-8. Firebase names are ASCII.
        value = data[offset:end].lstrip(b"[")
        descriptors.append(value.decode("ascii") if value.startswith(b"Lcom/google/firebase/") else None)
    defined = set()
    for index in range(class_count):
        type_index = struct.unpack_from("<I", data, classes + index * 32)[0]
        if type_index >= type_count:
            raise ValueError("invalid DEX class index")
        if descriptors[type_index]:
            defined.add(descriptors[type_index])
    return set(filter(None, descriptors)), defined


def check_firebase_runtime(dex_entries, manifest_names, errors):
    types, defined, per_dex = set(), set(), {}
    if not dex_entries:
        errors.append("AAB has no DEX entries to inspect for Firebase dependencies")
    for name, data in sorted(dex_entries.items()):
        try:
            references, definitions = dex_firebase_types(data)
        except (ValueError, IndexError, struct.error) as error:
            errors.append(f"{name}: {error}")
            continue
        types.update(references)
        defined.update(definitions)
        per_dex[name] = {"firebaseTypes": sorted(references), "definedFirebaseTypes": sorted(definitions)}
    unexpected = types - GOOGLE_COMMON_EXCEPTIONS
    manifest_matches = sorted(name for name in manifest_names if "firebase" in str(name).lower())
    if unexpected or manifest_matches:
        errors.append("unexpected Firebase runtime dependency")
    return {"commonExceptionTypes": sorted(types & GOOGLE_COMMON_EXCEPTIONS),
            "definedFirebaseTypes": sorted(defined), "unexpectedTypes": sorted(unexpected),
            "manifestMatches": manifest_matches, "dexEntries": per_dex}


def check_runtime_config(archive, ad_unit, errors):
    report = {"path": RUNTIME_CONFIG, "interstitialAdUnitIdMatches": False}
    try:
        if archive.namelist().count(RUNTIME_CONFIG) != 1:
            raise ValueError("exactly one install-time Android runtime config is required")
        content = archive.read(RUNTIME_CONFIG)
        config = json.loads(content)
        if not ad_unit or not isinstance(config, dict) or config.get("interstitialAdUnitId") != ad_unit:
            raise ValueError("production interstitial ID differs from exported runtime config")
        report.update(interstitialAdUnitIdMatches=True, sha256=hashlib.sha256(content).hexdigest())
    except (ValueError, UnicodeError, KeyError) as error:
        errors.append(f"Android runtime config: {error}")
    return report


def check_age_sdk_classes(dex, metadata, errors):
    required = {
        "StarlitAgeSignals plugin": b"Lcom/seorilabs/starlit/agesignals/StarlitAgeSignals;",
        "Play Age Signals factory": b"Lcom/google/android/play/agesignals/AgeSignalsManagerFactory;",
        "Play Age Signals access request": b"Lcom/google/android/play/agesignals/AgeSignalsAccessRequest;",
    }
    for label, descriptor in required.items():
        if descriptor not in dex:
            errors.append(f"required {label} class missing from AAB")
    if metadata.get("org.godotengine.plugin.v2.StarlitAgeSignals") != "com.seorilabs.starlit.agesignals.StarlitAgeSignals":
        errors.append("Godot v2 Age Signals plugin entry missing from AAB manifest")


def check_ad_sdk_classes(dex, errors):
    required = {
        "GMA Next-Gen MobileAds": b"Lcom/google/android/libraries/ads/mobile/sdk/MobileAds;",
        "GMA Next-Gen InterstitialAd": b"Lcom/google/android/libraries/ads/mobile/sdk/interstitial/InterstitialAd;",
        "UMP UserMessagingPlatform": b"Lcom/google/android/ump/UserMessagingPlatform;",
    }
    for label, descriptor in required.items():
        if descriptor not in dex:
            errors.append(f"required {label} SDK class missing from AAB")


def varint(data, offset):
    value = 0
    for shift in range(0, 70, 7):
        byte = data[offset]
        offset += 1
        value |= (byte & 127) << shift
        if byte < 128:
            return value, offset
    raise ValueError("invalid protobuf varint")


def fields(data):
    result = {}
    offset = 0
    while offset < len(data):
        key, offset = varint(data, offset)
        number, wire = key >> 3, key & 7
        if number == 0:
            raise ValueError("invalid protobuf field number")
        if wire == 0:
            value, offset = varint(data, offset)
        elif wire == 2:
            length, offset = varint(data, offset)
            end = offset + length
            if end > len(data):
                raise ValueError("truncated protobuf")
            value, offset = data[offset:end], end
        elif wire in (1, 5):
            length = 8 if wire == 1 else 4
            if offset + length > len(data):
                raise ValueError("truncated protobuf fixed field")
            value, offset = data[offset:offset + length], offset + length
        else:
            raise ValueError(f"unsupported protobuf wire type {wire}")
        result.setdefault(number, []).append(value)
    return result


def one(data, key, default=b""):
    return data.get(key, [default])[0]


def text(data):
    return data.decode("utf-8")


def attribute(data):
    item = fields(data)
    value = text(one(item, 3))
    if not value and 6 in item:
        compiled = fields(one(item, 6))
        for key in (2, 3):
            if key in compiled:
                value = text(one(fields(one(compiled, key)), 1))
        if 7 in compiled:
            primitive = fields(one(compiled, 7))
            for key in (6, 7, 8):
                if key in primitive:
                    value = str(one(primitive, key))
    return (text(one(item, 1)), text(one(item, 2))), value


def elements(data):
    # aapt.pb XmlNode.element=1, XmlElement name=3, attribute=4, child=5.
    node = fields(data)
    if 1 not in node:
        return
    element = fields(one(node, 1))
    yield text(one(element, 3)), dict(attribute(item) for item in element.get(4, []))
    for child in element.get(5, []):
        yield from elements(child)


def elf_alignment(data):
    if data[:4] != b"\x7fELF" or data[4] not in (1, 2) or data[5] not in (1, 2):
        raise ValueError("invalid ELF header")
    endian = "<" if data[5] == 1 else ">"
    is64 = data[4] == 2
    offset = struct.unpack_from(endian + ("Q" if is64 else "I"), data, 32 if is64 else 28)[0]
    stride, count = struct.unpack_from(endian + "HH", data, 54 if is64 else 42)
    segments = []
    for index in range(count):
        start = offset + index * stride
        kind = struct.unpack_from(endian + "I", data, start)[0]
        if kind == 1:
            align = struct.unpack_from(endian + ("Q" if is64 else "I"), data, start + (48 if is64 else 28))[0]
            segments.append(align)
    if not segments or any(value < 16384 or value & (value - 1) for value in segments):
        raise ValueError(f"ELF PT_LOAD alignment is below 16KiB: {segments}")
    return segments


def source_checks(root, errors):
    presets = (root / "export_presets.cfg").read_text()
    android_preset = presets.split('[preset.1]', 1)[1].split('[preset.1.options]', 1)[0]
    for pattern in ("data/*.json", "data/i18n/*.json", "data/monetization/*.json", "config/android_runtime.json"):
        if pattern not in android_preset:
            errors.append(f"Android export must explicitly include {pattern}")
    android = presets.split("[preset.1.options]", 1)[1].split("[preset.2]", 1)[0]
    if f'package/unique_name="{PACKAGE}"' not in android:
        errors.append("Android package identity mismatch")
    match = re.search(r"(?m)^gradle_build/target_sdk=(\d+)$", android)
    if not match or int(match[1]) < 36:
        errors.append("Android target SDK must be at least 36")
    if "gradle_build/compress_native_libraries=false" not in android:
        errors.append("native library compression must be disabled for alignment inspection")
    config = json.loads((root / "play-store/google-play.config.json").read_text())
    if config["packageName"] != PACKAGE or config["freeOrPaid"] != "free":
        errors.append("Play package or price does not match approved release")
    if config["contentDeclarations"].get("ads") != "yes":
        errors.append("Play listing must declare ads")
    if set(config["storeListing"]["appName"]) != {"ko-KR", "en-US"}:
        errors.append("Play listing must include Korean and English")
    plugin = (root / "addons/starlit_age_signals/android_export.gd").read_text()
    native_build = (root / "native/age_signals/build.gradle").read_text()
    for label, source in (("Godot export", plugin), ("native library", native_build)):
        if "com.google.android.play:age-signals:0.0.4" not in source:
            errors.append(f"{label} must pin Play Age Signals 0.0.4")
    if '"res://addons/starlit_age_signals/plugin.cfg"' not in (root / "project.godot").read_text():
        errors.append("Godot Age Signals export plugin is not enabled")
    return {"packageName": PACKAGE, "minimumTargetSdk": 36, "sourceOnly": True}


def inspect_aab(path, args, errors):
    app_id = os.environ.get("ADMOB_APP_ID", "")
    ad_unit = os.environ.get("ADMOB_INTERSTITIAL_AD_UNIT_ID", "")
    for label, value, pattern in (
        ("ADMOB_APP_ID", app_id, r"ca-app-pub-\d{16}~\d{10}"),
        ("ADMOB_INTERSTITIAL_AD_UNIT_ID", ad_unit, r"ca-app-pub-\d{16}/\d{10}"),
    ):
        if not re.fullmatch(pattern, value) or "3940256099942544" in value:
            errors.append(f"{label} must be an app-specific production ID")
    if app_id.split("~")[0] != ad_unit.split("/")[0]:
        errors.append("AdMob App ID and interstitial ID publisher do not match")
    if not args.version_name or not args.version_code:
        errors.append("exact ledger version name and code are required for AAB inspection")
    native = {}
    with zipfile.ZipFile(path) as archive:
        bundle = fields(archive.read("BundleConfig.pb"))
        optimizations = fields(one(bundle, 2))
        native_config = fields(one(optimizations, 2))
        packaging_alignment = one(native_config, 2, 0)
        if packaging_alignment not in (2, 3):
            errors.append("BundleConfig must request at least 16KiB APK native library alignment")
        manifest = list(elements(archive.read("base/manifest/AndroidManifest.xml")))
        top = manifest[0][1]
        actual = {"packageName": top.get(("", "package")),
                  "versionName": top.get((ANDROID_NS, "versionName")),
                  "versionCode": top.get((ANDROID_NS, "versionCode"))}
        if actual != {"packageName": PACKAGE, "versionName": args.version_name, "versionCode": args.version_code}:
            errors.append("AAB package/version does not match exact release inputs")
        uses_sdk = [attrs for name, attrs in manifest if name == "uses-sdk"]
        target = uses_sdk[0].get((ANDROID_NS, "targetSdkVersion"), "0") if uses_sdk else "0"
        if not target.isdigit() or int(target) < 36:
            errors.append("AAB target SDK is below 36")
        metadata = {attrs.get((ANDROID_NS, "name")): attrs.get((ANDROID_NS, "value"))
                    for name, attrs in manifest if name == "meta-data"}
        for name, attrs in manifest:
            if name == "application" and attrs.get((ANDROID_NS, "debuggable"), "0") not in ("0", "false"):
                errors.append("release AAB is debuggable")
        if not app_id or metadata.get("com.google.android.gms.ads.APPLICATION_ID") != app_id:
            errors.append("AAB AdMob application ID differs from production input")
        dex = bytearray()
        dex_entries = {}
        runtime = bytearray()
        for name in archive.namelist():
            if name.endswith(".so"):
                try:
                    native[name] = elf_alignment(archive.read(name))
                except ValueError as error:
                    errors.append(f"{name}: {error}")
            if re.fullmatch(r"base/dex/classes\d*\.dex", name):
                dex_entries[name] = archive.read(name)
                dex.extend(dex_entries[name])
            if name.startswith(("base/assets/", "assetPackInstallTime/assets/")) and name.endswith((".json", ".pck", ".gd", ".gdc")):
                runtime.extend(archive.read(name))
        if not native:
            errors.append("Godot AAB has no native libraries to inspect")
        check_ad_sdk_classes(dex, errors)
        check_age_sdk_classes(dex, metadata, errors)
        firebase = check_firebase_runtime(dex_entries,
            [attrs.get((ANDROID_NS, "name"), "") for _, attrs in manifest], errors)
        runtime_config = check_runtime_config(archive, ad_unit, errors)
        for resource in ("data/actions.json", "data/events.json", "data/endings.json", "data/npcs.json",
                         "data/i18n/ko.json", "data/i18n/en.json", "data/monetization/interstitial-policy.json"):
            if not any(name.endswith("/" + resource) for name in archive.namelist()) and resource.encode() not in runtime:
                errors.append(f"required game resource missing from AAB: {resource}")
    result = subprocess.run(["jarsigner", "-verify", str(path)], text=True, capture_output=True, timeout=90,
                            env={**os.environ, "LC_ALL": "C"})
    if result.returncode or "jar verified." not in result.stdout:
        errors.append("AAB signature verification failed")
    certificate = subprocess.run(["keytool", "-printcert", "-jarfile", str(path)], text=True, capture_output=True,
                                 timeout=90, env={**os.environ, "LC_ALL": "C"})
    match = re.search(r"SHA256:\s*([0-9A-Fa-f:]{95})", certificate.stdout)
    fingerprint = match[1].replace(":", "").upper() if match else None
    if certificate.returncode or not fingerprint:
        errors.append("AAB signing certificate fingerprint could not be read")
    expected = os.environ.get("SEORI_EXPECTED_UPLOAD_CERTIFICATE_SHA256", "").replace(":", "").upper()
    if expected and expected != fingerprint:
        errors.append("AAB signing certificate differs from the approved upload certificate")
    return {**actual, "targetSdk": target, "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
            "nativeLoadAlignments": native, "sourceOnly": False,
            "firebaseInspection": firebase, "androidRuntimeConfig": runtime_config,
            "certificateSha256": fingerprint,
            "expectedCertificateComparison": ("matched" if expected == fingerprint else "mismatch") if expected else "not-provided",
            "signing": "verified" if not result.returncode and "jar verified." in result.stdout else "failed",
            "bundleNativePageAlignment": packaging_alignment}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--source-only", action="store_true")
    parser.add_argument("--aab", type=Path)
    parser.add_argument("--version-name")
    parser.add_argument("--version-code")
    parser.add_argument("--report", type=Path)
    args = parser.parse_args()
    if not args.source_only and args.aab is None:
        parser.error("--source-only or --aab is required")
    errors = []
    try:
        report = source_checks(args.root, errors)
        if args.aab:
            report.update(inspect_aab(args.aab, args, errors))
    except (ValueError, KeyError, IndexError, OSError, zipfile.BadZipFile, struct.error, subprocess.TimeoutExpired) as error:
        report = {"sourceOnly": args.aab is None}
        errors.append(str(error))
    report.update(status="failed" if errors else "passed", errors=errors)
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps(report, ensure_ascii=False, indent=2))
    return bool(errors)


if __name__ == "__main__":
    raise SystemExit(main())
