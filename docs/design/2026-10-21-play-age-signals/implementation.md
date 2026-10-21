# Play 연령 정보 수신 구현 기록

실행 티켓은 [56](https://github.com/seoleeapps/starlit-apprentice/issues/56)이다. 설계 승인 관측은 2026-10-21T12:23:30Z이며 승인 커밋은 dc7fc9787f9875a58aa0f198d24c38e9c0194879다. 이 문서의 작성자 사전 검사는 정식 후보의 L3 통과나 UI5~7 근거로 세지 않는다.

## 책임과 데이터

`native/age_signals/`는 Godot 4.7.2 v2 플러그인과 Play Age Signals 0.0.4에만 의존한다. 공유 접근 요청 뒤 SHARED일 때 연령 응답을 읽는다. 공유 선택과 보호자 승인을 구분하며 범위와 고정 상태 외의 정보는 신호에 넣지 않는다. 원시 응답, 설치 식별자, 날짜, 예외 본문을 저장하거나 기록하지 않는다. `addons/starlit_age_signals/`는 Android export 때만 AAR와 Maven 의존성을 넣는다. 일반 import에는 빌드한 AAR가 필요 없다.

`src/platform/age_signals_adapter.gd`가 수신 경계, `android_age_signals_adapter.gd`가 native 연결, `src/game/age_access.gd`가 메모리의 접근 상태를 소유한다. 확인은 한 번에 하나만 하며 앱 내 대기는 5초다. 자동 재시도는 없고 명시적 재시도와 OS 재활성화만 새 조회를 만든다. 요청 ID는 장면을 다시 만들어도 재사용하지 않으며 늦거나 중복된 결과와 해제 뒤 결과를 무시한다. Play의 공유 선택 화면과 task는 취소할 수 없고 타이머가 닫지 않는다.

이미 확인한 13세 미만과 보호자 승인 대기 또는 거절은 일시 실패로 해제하지 않는다. 새로운 공유 범위가 13세 이상이며 승인 문제가 없을 때 해제한다. 최초 미공유나 API 실패는 기존 전체이용가 게임을 이용한다. 0.0.4는 지역 비적용을 명시하는 응답이 없으므로 미공유나 오류를 지역 비적용으로 추측하지 않는다. 비Android는 unsupported다. 이 차이는 [실제 0.0.4 문서](https://developer.android.com/google/play/age-signals/request-age-signals)와 SDK AAR의 API를 대조한 구현 사실이며 새 지역 제한을 만들지 않는다.

`src/ui/main.gd`는 기존 이벤트 위에 별도 확인 창을 겹친다. 확인과 보호 상태에서 시작, 이어하기, 행동, 이벤트와 계속 입력을 막는다. 안내를 닫으면 설정을 이용할 수 있는 타이틀로 돌아가며 보호 사유와 다시 확인을 남긴다. 실행 중 확인에 성공하면 원래 이벤트로 돌아온다. 기존 저장, 난수 상태와 엔딩을 바꾸지 않는다.

광고와 Profile은 Play 정보를 받지 않는다. 광고 초기화와 수동 연령 변경은 기존 `Profile.age_band()` 입력을 유지하고 Play 상태에 따른 광고 입력이나 빈도 정책을 추가하지 않는다. 따라서 Play 정보로 광고를 개인화하거나 광고 연령 태그를 만들지 않는다. 실제 입력 E2E가 조회, 보호, 재시도, 중복, 언어 변경과 재활성화에서 저장 바이트와 광고 대역의 전체 호출 기록을 비교한다.

## 작성자 검증과 출시 구분

- 요구사항 때문에 실패한 접근 정책 검사 27건을 보존한 뒤 정책 52건이 통과했다. Android GDScript 경계 검사 6건, AAB의 native 클래스와 manifest 등록을 확인하는 검사 4건도 통과했다. 기존 Python 검사 포함 11건이 통과했다.
- native는 JVM 경계 검사, Android lint와 clean AAR 재현 빌드를 수행한다. 입력 파일과 SDK AAR 해시는 `build/age-signals/provenance.json`에 남긴다. 실제 Android 실행의 증거는 아니다.
- 실제 main 장면에 플랫폼 대역만 넣은 한국어와 영어 22시나리오가 작성 중 사전 검사에서 통과했다. 시험 코드의 String 타입 추론 오류가 난 최초 로그를 보존하고 수정 후 결과를 별도 경로에 남겼다.
- 작성자 렌더링의 한국어와 영어 720x1280 보호 안내, 승인 대기, 확인 중과 실행 중 보호 상태를 직접 확인했다. 기존 색과 서체를 쓰며 안내 본문과 다시 확인, 닫기 버튼이 보인다. 독립 UI5~7과 세 화면 크기 검수는 최종 후보에서 별도로 수행한다.
- `scripts/build-android.sh`는 중앙 before-build 검증 뒤에만 라이브러리를 빌드하고 기존 서명 AAB 흐름을 실행한다. 최종 AAB 검사에는 Age Signals SDK 진입점과 Godot v2 manifest 등록도 포함한다.

서명 AAB, 실제 SDK 공유 화면, UMP와 광고 표시, Play 업로드, 심사 제출과 공개 확인은 이 문서의 작성자 사전 검사로 통과 처리하지 않는다. 기기 사용 승인과 기존 WIF 연결 차단도 별도 조건이다.
