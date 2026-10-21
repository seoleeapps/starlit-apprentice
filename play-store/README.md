# Google Play 등록 자료

`com.seorilabs.starlitapprentice`의 Godot Android 출시 자료다. 한국어와 영어, 무료 배포, 로컬 저장과 전면광고만 사용한다. 로그인, Firebase, 서버 저장과 앱 내 결제는 없다. 실제 SDK가 수집하는 정보는 [개인정보와 Data safety 검토](../docs/privacy-and-data-safety.md)에 적는다.

- 등록 문구와 자산 목록: [google-play.config.json](google-play.config.json)
- 실제 Godot 전화 화면: `screenshots/phone/ko/`, `screenshots/phone/en/`
- 큰 이미지: [feature-graphic-1024x500.png](assets/feature-graphic-1024x500.png)
- 자산 규격과 제작 방향: [registration-manifest.json](assets/registration-manifest.json)
- 출시 상태와 남은 조건: [출시 원장](../docs/06-release/2026-10-21-android-launch.md)

과거 웹 버전의 상위 `phone/` 및 `tablet-*` 이미지는 등록 목록에서 제외했다. 태블릿 캡처와 태블릿 화면 검수는 하지 않았다.

큰 이미지는 게임의 방 배경과 견습생 아트, 현재 영어 행동 화면을 HTML로 합성한다. Playwright가 준비된 Python으로 다음 명령을 실행한다. 생성한 PNG는 1024x500이며 불투명 배경이어야 한다. 원본은 `assets/source/feature-graphic.html`이다.

```bash
python tools/render_play_feature.py
# 설치된 Edge를 사용할 때는 --browser-channel msedge 추가
```

등록 문구와 이미지 준비는 Console 저장, 정책 설문 완료, 심사 접수와 공개 출시를 증명하지 않는다. 실제 상태는 출시 원장에 각각 기록한다.
