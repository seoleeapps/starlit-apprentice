"""AAB 검사 수정 제안용 고정 입력. 실제 서명 빌드나 기기 검수가 아니다."""
import importlib.util
import io
import json
import os
from pathlib import Path
import struct
import unittest
import zipfile
from types import SimpleNamespace
from unittest.mock import patch
from tempfile import TemporaryDirectory

spec = importlib.util.spec_from_file_location("release", os.environ.get(
    "INSPECTOR_UNDER_TEST", str(Path(__file__).resolve().parents[2] / "tools/check_android_release.py")))
release = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release)

COMMON = {
    b"Lcom/google/firebase/FirebaseException;",
    b"Lcom/google/firebase/FirebaseApiNotAvailableException;",
    b"Lcom/google/firebase/FirebaseExceptionMapper;",
}
UNIT = "ca-app-pub-9932778305312246/5426594130"
CONFIG = "assetPackInstallTime/assets/config/android_runtime.json"


def dex_fixture(defined=(), references=(), constants=()):
    """Only the standard DEX tables consumed by the inspector are populated."""
    types = sorted(set(defined) | set(references))
    strings = sorted(set(types) | set(constants))
    string_table = 112
    type_table = string_table + len(strings) * 4
    class_table = type_table + len(types) * 4
    data = bytearray(class_table + len(defined) * 32)
    data[:8] = b"dex\n039\0"
    struct.pack_into("<II", data, 36, 112, 0x12345678)
    struct.pack_into("<II", data, 56, len(strings), string_table)
    struct.pack_into("<II", data, 64, len(types), type_table)
    struct.pack_into("<II", data, 96, len(defined), class_table)
    for index, value in enumerate(strings):
        struct.pack_into("<I", data, string_table + index * 4, len(data))
        size = len(value)
        while size >= 128:
            data.append((size & 127) | 128)
            size >>= 7
        data.extend(bytes([size]) + value + b"\0")
    for index, value in enumerate(types):
        struct.pack_into("<I", data, type_table + index * 4, strings.index(value))
    for index, value in enumerate(defined):
        struct.pack_into("<I", data, class_table + index * 32, types.index(value))
    struct.pack_into("<I", data, 32, len(data))
    return bytes(data)


class FirebaseInspectionTest(unittest.TestCase):
    def check(self, entries, metadata=None):
        errors = []
        report = release.check_firebase_runtime(entries, metadata or {}, errors)
        return errors, report

    def test_required_google_common_exceptions_are_identified(self):
        errors, report = self.check({"base/dex/classes.dex": dex_fixture(COMMON)})
        self.assertEqual(errors, [])
        self.assertEqual(set(report["commonExceptionTypes"]), {d.decode() for d in COMMON})

    def test_every_other_firebase_product_and_unknown_type_is_rejected(self):
        for name in ("FirebaseApp", "analytics/FirebaseAnalytics", "auth/FirebaseAuth",
                     "firestore/FirebaseFirestore", "remoteconfig/FirebaseRemoteConfig",
                     "encoders/SomeEncoder", "UnknownFutureService"):
            descriptor = f"Lcom/google/firebase/{name};".encode()
            with self.subTest(name=name):
                errors, report = self.check({"base/dex/classes.dex": dex_fixture([descriptor])})
                self.assertTrue(errors)
                self.assertIn(descriptor.decode(), report["unexpectedTypes"])

    def test_multidex_does_not_hide_a_product_in_second_dex(self):
        errors, _ = self.check({"base/dex/classes.dex": dex_fixture(COMMON),
                               "base/dex/classes2.dex": dex_fixture([b"Lcom/google/firebase/FirebaseApp;"])})
        self.assertTrue(errors)

    def test_external_product_reference_is_also_rejected(self):
        errors, report = self.check({"base/dex/classes.dex": dex_fixture(
            COMMON, references=[b"Lcom/google/firebase/auth/FirebaseAuth;"])})
        self.assertTrue(errors)
        self.assertEqual(report["definedFirebaseTypes"], sorted(d.decode() for d in COMMON))
        self.assertIn("Lcom/google/firebase/auth/FirebaseAuth;", report["unexpectedTypes"])

    def test_string_constant_is_not_reported_as_a_defined_class(self):
        errors, report = self.check({"base/dex/classes.dex": dex_fixture(
            COMMON, constants=[b"Lcom/google/firebase/FirebaseApp;"])})
        self.assertEqual(errors, [])
        self.assertEqual(report["definedFirebaseTypes"], sorted(d.decode() for d in COMMON))

    def test_firebase_manifest_is_rejected_even_with_common_types_only(self):
        for name in ("com.google.firebase.provider.FirebaseInitProvider",
                     "com.google.firebase.components.ComponentDiscoveryService",
                     "com.google.firebase.components:registrar"):
            with self.subTest(name=name):
                errors, _ = self.check({"base/dex/classes.dex": dex_fixture(COMMON)}, {name: "present"})
                self.assertTrue(errors)

    def test_empty_missing_truncated_unsupported_and_bad_offsets_fail_closed(self):
        corrupt = bytearray(dex_fixture(COMMON))
        struct.pack_into("<I", corrupt, 68, len(corrupt) + 1)
        unsupported = b"dex\n041\0" + dex_fixture(COMMON)[8:]
        for entries in ({}, {"base/dex/classes.dex": b""},
                        {"base/dex/classes.dex": dex_fixture(COMMON)[:-1]},
                        {"base/dex/classes.dex": unsupported},
                        {"base/dex/classes.dex": bytes(corrupt)}):
            with self.subTest(entries=list(entries)):
                errors, _ = self.check(entries)
                self.assertTrue(errors)


class RuntimeConfigInspectionTest(unittest.TestCase):
    def check(self, entries):
        buffer = io.BytesIO()
        with zipfile.ZipFile(buffer, "w") as archive:
            for name, value in entries.items():
                archive.writestr(name, value)
        errors = []
        with zipfile.ZipFile(buffer) as archive:
            report = release.check_runtime_config(archive, UNIT, errors)
        return errors, report

    def test_godot_install_time_asset_json_is_read_and_reported(self):
        errors, report = self.check({CONFIG: json.dumps({"interstitialAdUnitId": UNIT})})
        self.assertEqual(errors, [])
        self.assertEqual(report["path"], CONFIG)
        self.assertEqual(report["interstitialAdUnitIdMatches"], True)

    def test_wrong_or_missing_config_cannot_be_masked_by_incidental_id(self):
        for config in (None, "{}", "[]", "not json", json.dumps({"other": UNIT}),
                       json.dumps({"interstitialAdUnitId": "wrong"}),
                       json.dumps({"interstitialAdUnitId": [UNIT]})):
            entries = {"base/assets/unrelated.json": json.dumps({"text": UNIT})}
            if config is not None:
                entries[CONFIG] = config
            with self.subTest(config=config):
                errors, report = self.check(entries)
                self.assertTrue(errors)
                self.assertFalse(report["interstitialAdUnitIdMatches"])

    def test_wrong_delivery_module_is_rejected(self):
        errors, _ = self.check({"onDemand/assets/config/android_runtime.json":
                                json.dumps({"interstitialAdUnitId": UNIT})})
        self.assertTrue(errors)


class CompleteInspectorRegressionTest(unittest.TestCase):
    def inspect(self, common, has_config, incidental=False):
        required = [b"Lcom/google/android/libraries/ads/mobile/sdk/MobileAds;",
                    b"Lcom/google/android/libraries/ads/mobile/sdk/interstitial/InterstitialAd;",
                    b"Lcom/google/android/ump/UserMessagingPlatform;",
                    b"Lcom/seorilabs/starlit/agesignals/StarlitAgeSignals;",
                    b"Lcom/google/android/play/agesignals/AgeSignalsManagerFactory;",
                    b"Lcom/google/android/play/agesignals/AgeSignalsAccessRequest;"]
        manifest = [
            ("manifest", {("", "package"): release.PACKAGE,
                           (release.ANDROID_NS, "versionName"): "1.0.0",
                           (release.ANDROID_NS, "versionCode"): "1"}),
            ("uses-sdk", {(release.ANDROID_NS, "targetSdkVersion"): "36"}),
            ("meta-data", {(release.ANDROID_NS, "name"): "com.google.android.gms.ads.APPLICATION_ID",
                            (release.ANDROID_NS, "value"): "ca-app-pub-9932778305312246~5434157983"}),
            ("meta-data", {(release.ANDROID_NS, "name"): "org.godotengine.plugin.v2.StarlitAgeSignals",
                            (release.ANDROID_NS, "value"): "com.seorilabs.starlit.agesignals.StarlitAgeSignals"})]
        environment = {"ADMOB_APP_ID": "ca-app-pub-9932778305312246~5434157983",
                       "ADMOB_INTERSTITIAL_AD_UNIT_ID": UNIT}
        with TemporaryDirectory() as directory:
            path = Path(directory) / "fixture.aab"
            with zipfile.ZipFile(path, "w") as archive:
                archive.writestr("BundleConfig.pb", b"\x12\x04\x12\x02\x10\x02")
                archive.writestr("base/manifest/AndroidManifest.xml", b"manifest-fixture")
                archive.writestr("base/lib/arm64-v8a/libfixture.so", b"elf-fixture")
                archive.writestr("base/dex/classes.dex", dex_fixture(required + list(common)))
                for resource in ("data/actions.json", "data/events.json", "data/endings.json", "data/npcs.json",
                                 "data/i18n/ko.json", "data/i18n/en.json", "data/monetization/interstitial-policy.json"):
                    archive.writestr("assetPackInstallTime/assets/" + resource, "{}")
                if has_config:
                    archive.writestr(CONFIG, json.dumps({"interstitialAdUnitId": UNIT}))
                if incidental:
                    archive.writestr("base/assets/unrelated.json", json.dumps({"unrelated": UNIT}))
            with patch.object(release, "elements", return_value=manifest), \
                    patch.object(release, "elf_alignment", return_value=[16384]), \
                    patch.object(release.subprocess, "run", side_effect=[
                        SimpleNamespace(returncode=0, stdout="jar verified."),
                        SimpleNamespace(returncode=0, stdout="SHA256: " + ":".join(["AB"] * 32))]), \
                    patch.dict(os.environ, environment):
                errors = []
                release.inspect_aab(path, SimpleNamespace(version_name="1.0.0", version_code="1"), errors)
                return errors

    def test_actual_inspector_accepts_required_common_exceptions_and_install_time_config(self):
        self.assertEqual(self.inspect(COMMON, has_config=True), [])

    def test_actual_inspector_rejects_missing_config_despite_incidental_matching_string(self):
        self.assertTrue(self.inspect([], has_config=False, incidental=True))


if __name__ == "__main__":
    unittest.main()
