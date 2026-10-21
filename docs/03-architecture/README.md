# 런타임 구조

순수 코어는 `packages/product-core`에 두고, 파일과 JSON 처리는 `src/game/file_storage.gd`, 번역은 `src/content/localization.gd`가 맡는다. UI는 `src/ui`에 있다. 저장은 기기 안에서만 유지한다.

전면광고 시점과 횟수는 `src/game/interstitial_service.gd`, 로컬 상수는 `data/monetization/interstitial-policy.json`, 실제 Poing AdMob과 UMP 호출은 `src/platform/android_admob_adapter.gd`가 소유한다. 운영 공개 ID는 빌드 때 주입한다. Firebase, GA4 전송, 원격 설정과 서버 광고 검증을 런타임과 빌드에서 제거했다.

이전 작업 기록의 서버 계획은 과거 이력이다. 현재 Android 출시 범위는 [승인 설계](../design/2026-10-21-android-launch/design.md)를 따른다.
