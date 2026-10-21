#!/usr/bin/env python3
"""Inject app-specific production AdMob IDs for one Android export."""
import json
import os
from pathlib import Path
import re


def main():
    root = Path(__file__).resolve().parents[1]
    app_id = os.environ.get("ADMOB_APP_ID", "")
    ad_unit = os.environ.get("ADMOB_INTERSTITIAL_AD_UNIT_ID", "")
    for name, value, pattern in (
        ("ADMOB_APP_ID", app_id, r"ca-app-pub-\d{16}~\d{10}"),
        ("ADMOB_INTERSTITIAL_AD_UNIT_ID", ad_unit, r"ca-app-pub-\d{16}/\d{10}"),
    ):
        if not re.fullmatch(pattern, value) or "3940256099942544" in value:
            raise SystemExit(f"{name}: 앱별 운영 ID가 필요하다. 값은 출력하지 않는다.")
    if app_id.split("~")[0] != ad_unit.split("/")[0]:
        raise SystemExit("App ID와 전면광고 ID의 Publisher가 다르다. 값은 출력하지 않는다.")
    project = root / "project.godot"
    source = project.read_text()
    updated, count = re.subn(r'(?m)^general/android/app_id="[^"]*"$',
                             lambda _: f'general/android/app_id="{app_id}"', source)
    if count != 1:
        raise SystemExit("project.godot AdMob Android app_id 필드를 하나 찾을 수 없다.")
    runtime = root / "config/android_runtime.json"
    runtime.parent.mkdir(parents=True, exist_ok=True)
    project.write_text(updated)
    runtime.write_text(json.dumps({"interstitialAdUnitId": ad_unit}, indent=2) + "\n")
    print("[android-ads] 앱별 운영 광고 설정 주입 완료")


if __name__ == "__main__":
    main()
