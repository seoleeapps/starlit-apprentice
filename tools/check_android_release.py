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
        runtime = bytearray()
        for name in archive.namelist():
            if name.endswith(".so"):
                try:
                    native[name] = elf_alignment(archive.read(name))
                except ValueError as error:
                    errors.append(f"{name}: {error}")
            if re.fullmatch(r"base/dex/classes\d*\.dex", name):
                dex.extend(archive.read(name))
            if name.startswith("base/assets/") and name.endswith((".json", ".pck", ".gd", ".gdc")):
                runtime.extend(archive.read(name))
        if not native:
            errors.append("Godot AAB has no native libraries to inspect")
        for sdk in (b"com/google/android/gms/ads/", b"com/google/android/ump/"):
            if sdk not in dex:
                errors.append("required AdMob or UMP SDK classes missing from AAB")
        if b"com/google/firebase/" in dex or any(
                "firebase" in str(attrs.get((ANDROID_NS, "name"), "")).lower() for _, attrs in manifest):
            errors.append("unexpected Firebase runtime dependency")
        if ad_unit and ad_unit.encode() not in runtime:
            errors.append("production interstitial ID was not found in exported runtime config")
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
