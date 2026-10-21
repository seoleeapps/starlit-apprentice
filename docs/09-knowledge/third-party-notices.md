# Third-party notices

## 폰트

### Pretendard

- 버전: 1.3.9
- 출처: https://github.com/orioncactus/pretendard
- 라이선스: SIL Open Font License 1.1
- 번들 파일: `assets/fonts/Pretendard-Regular.ttf`
- 라이선스 원문: `assets/fonts/Pretendard-LICENSE.txt`
- 저작자: Kil Hyung-jin, Reserved Font Name "Pretendard"

정적 Regular 한 벌만 번들하며 볼드는 `FontVariation` 으로 합성한다. 근거는 `docs/02-decisions/0007-font-budget.md`.

## 엔진

### Godot Engine

- 버전: 4.7.2.stable
- 라이선스: MIT
- 출처: https://godotengine.org

## Poing Godot AdMob

Android 전면광고와 UMP 연결에는 Poing Godot AdMob v5.1.0을 사용한다. MIT 라이선스와 각 파일의 저작권 표시를 보존했다. 원본 archive SHA-256, 포함 범위와 iOS 자동 다운로드를 막는 로컬 변경은 `addons/admob/SOURCE.json`에 기록했다. Android에는 ads/core AAR만 포함하고 미디에이션 모듈과 iOS 바이너리는 포함하지 않는다. 앱은 배너, 보상형과 결제를 사용하지 않는다.

https://github.com/poingstudios/godot-admob-plugin/releases/tag/v5.1.0
