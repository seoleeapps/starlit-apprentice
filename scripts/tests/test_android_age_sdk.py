"""광고 SDK만 있는 번들이 Play 연령 수신 검사를 통과하지 못하게 한다."""
import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location("android_release", Path(__file__).resolve().parents[2] / "tools/check_android_release.py")
release = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release)

PLUGIN = b"Lcom/seorilabs/starlit/agesignals/StarlitAgeSignals;"
FACTORY = b"Lcom/google/android/play/agesignals/AgeSignalsManagerFactory;"
ACCESS = b"Lcom/google/android/play/agesignals/AgeSignalsAccessRequest;"
ENTRY = {"org.godotengine.plugin.v2.StarlitAgeSignals": "com.seorilabs.starlit.agesignals.StarlitAgeSignals"}


class AndroidAgeSdkTest(unittest.TestCase):
    def inspect(self, classes, entry=ENTRY):
        errors = []
        release.check_age_sdk_classes(b"\0".join(classes), entry, errors)
        return errors

    def test_plugin_and_real_sdk_entrypoints_are_present(self):
        self.assertEqual(self.inspect([PLUGIN, FACTORY, ACCESS]), [])

    def test_plugin_without_sdk_does_not_pass(self):
        self.assertTrue(self.inspect([PLUGIN]))

    def test_sdk_without_godot_plugin_does_not_pass(self):
        self.assertTrue(self.inspect([FACTORY, ACCESS]))

    def test_classes_without_registered_manifest_do_not_pass(self):
        self.assertTrue(self.inspect([PLUGIN, FACTORY, ACCESS], {}))
