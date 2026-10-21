"""Legacy 광고 ID 참조만 있는 번들을 Next-Gen 전면광고 SDK로 인정하지 않는다."""
import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location("android_release", Path(__file__).resolve().parents[2] / "tools/check_android_release.py")
release = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release)

MOBILE = b"Lcom/google/android/libraries/ads/mobile/sdk/MobileAds;"
INTERSTITIAL = b"Lcom/google/android/libraries/ads/mobile/sdk/interstitial/InterstitialAd;"
UMP = b"Lcom/google/android/ump/UserMessagingPlatform;"
LEGACY_ID = b"Lcom/google/android/gms/ads/identifier/AdvertisingIdClient;"


class AndroidReleaseSdkTest(unittest.TestCase):
    def inspect(self, *descriptors):
        errors = []
        release.check_ad_sdk_classes(b"\0".join(descriptors) + b"\0", errors)
        return errors

    def test_legacy_identifier_is_not_next_gen_ads(self):
        self.assertTrue(self.inspect(LEGACY_ID, UMP))

    def test_next_gen_ads_does_not_require_legacy_namespace(self):
        self.assertEqual(self.inspect(MOBILE, INTERSTITIAL, UMP), [])

    def test_interstitial_entrypoint_is_required(self):
        self.assertTrue(self.inspect(MOBILE, LEGACY_ID, UMP))

    def test_ump_entrypoint_is_required(self):
        self.assertTrue(self.inspect(MOBILE, INTERSTITIAL, LEGACY_ID))


if __name__ == "__main__":
    unittest.main()
