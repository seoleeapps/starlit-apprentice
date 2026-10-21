# Play Age Signals Android 경계

Godot 4.7.2의 v2 플러그인이다. `StarlitAgeSignals.requestAgeSignals(requestId)`는
양수이며 증가하는 ID를 받고 `age_signals_result(id, status, lower, upper)`를 한 번 보낸다.
`lower`와 `upper`의 `-1`은 미공유 또는 열린 상한을 나타낸다. `lower >= 0`과
`upper == -1`은 최상위 열린 범위다. `lower == -1`이고 유효한 상한만 있으면 그 상한은
보존한다. SDK 문서는 nullable 하한에 대해 유효한 상한과 항상 함께 존재한다는 보장을
명시하지 않는다. 실제 제공자가 상한만 반환했다고 검증한 것은 아니다.
양쪽 `-1`은 연령 범위를 받지 못했다는 뜻이다.

## 실제 SDK 0.0.4

[공식 요청 흐름](https://developer.android.com/google/play/age-signals/request-age-signals)은
`requestAgeSignalsAccess(AgeSignalsAccessRequest)`로 공유 상태를 확인한 뒤,
`SHARED`일 때만 `checkAgeSignals(AgeSignalsRequest)`를 호출한다. 접근 요청은 필요한
경우 Google의 공유 선택 화면을 열 수 있다. `VERIFICATION_REQUIRED`는 제공자가 나이를
알 수 없으며 Play에서 확인이 필요하다고 정의한 상태이므로 `unknown`으로 보낸다.
`NOT_SHARED`와 null 응답은 `not_shared`이며 보호자 승인 거절과 다르다.

[응답 문서](https://developer.android.com/google/play/age-signals/understand-age-signals-responses)에
맞춰 정상 범위와 승인 또는 변경 없음은 `shared`, 유의미한 변경의 보호자 승인 대기는
`approval_pending`, 거절은 `approval_denied`로 축약한다.
승인 대기와 거절은 연령 범위와 독립해 우선 보존하고 나이 경계는 양쪽 모두 `-1`로 보낸다.
이 경우 잘못된 범위가 와도 보호 상태를 일반 오류로 덮어쓰지 않는다.
사용자 출처를 의미하는 TIER와 구버전 `userStatus`를 흉내 내지 않는다.
0.0.4가 지역 비적용을 명시하는 응답을 제공하지
않으므로 `not_applicable`을 추정해 보내지 않는다. 알 수 없는 enum이나 잘못된 범위는
`error`다. 네트워크 오류는 `offline`, SDK나 스토어와 서비스 사용 불가는 `unavailable`,
나머지 실패는 `error`이며 오류 메시지를 읽거나 기록하지 않는다.

설치 ID, 승인 날짜와 원시 응답은 보존하지 않는다. SDK 응답에서 범위와 승인 상태
getter만 읽는다. 연령 신호를 파일, 광고, 분석 또는 다른 SDK로 전달하는 코드가 없다.
[이용 조건](https://developer.android.com/google/play/age-signals/overview#terms-service)은
광고 목적 사용을 금지한다.

## 비동기 요청 수명

SDK 요청과 완료 분류는 Android UI 스레드에서만 수행한다. 하나의 SDK task가 끝나기
전에 다른 접근 UI를 열지 않는다. 새 요청이 들어오면 대기 ID는 최신 하나만 남기고,
기존 응답은 버린 뒤 그 최신 요청을 수행한다. 요청 ID 재사용, 오래된 ID와 같은 task의
중복 완료는 버린다. Godot 렌더 스레드에 신호를 보낼 때도 최신 ID와 종료 상태를 다시
검사한다. 앱 종료 뒤 callback은 신호를 보내지 않는다.

SDK 공유 UI가 열린 동안 앱의 pause와 resume이 발생할 수 있다. 네이티브 플러그인은
자동 재시도나 자체 타임아웃으로 두 번째 UI를 열지 않는다. 게임 측 5초 타이머와 복귀
처리는 별도 서비스 책임이다. 타이머가 끝나도 SDK task는 취소되지 않으며, 늦은 ID를
게임 측에서도 거부해야 한다. 제공자 UI가 실제로 열리고 닫히는 동작은 기기에서
실행하지 않았으므로 이 JVM 검사로 검증됐다고 볼 수 없다.

## 빌드와 검증

```bash
bash scripts/build-age-signals.sh
```

기존 JDK 17, Android SDK 36을 사용한다. 시스템 설정, SDK 설치나 기기 호출을 하지 않는다.
Gradle 8.14.3 배포 체크섬, AGP 8.13.2, Godot 4.7.2.stable, Age Signals 0.0.4와 의존성
lock을 고정했다. Google Maven 원본 AAR의 SHA256은
`0f47c1dcef35feb637d879cd7fffff555a19398b850b2cc9814f61f54876e989`이며 빌드 전 검사한다.
공식 Maven의 sources.jar는 404였으므로 SDK API는 원본 AAR의 `classes.jar`에 `javap`를
실행해 확인했다.

빌드는 JVM 경계 검사와 서명 없는 플러그인 AAR만 만든다. 산출물은
`addons/starlit_age_signals/bin/starlit-age-signals-release.aar`로 복사하며 버전 관리에서
제외한다. Godot export 플러그인은 이 AAR와 Maven SDK 의존성을 Android에 포함한다.
일반 Editor와 깨끗한 CI import는 AAR 없이 가능하며 누락 검사는 Android export에서만 한다.
`scripts/build-android.sh`는 중앙 before-build 검증을 통과한 뒤 이 라이브러리를 먼저
만든다. 최종 게임 AAB 빌드나 기기 실행을 이 스크립트가 허용하지 않는다.

`build/age-signals/provenance.json`은 빌드 입력별 해시, SDK 원본과 플러그인 AAR 해시를
담는다. `native/age_signals/build/test-results/testReleaseUnitTest/`에는 비동기 대역과
범위 및 오류 분류의 JUnit 결과가 있다. 라이브러리 컴파일과 대역 검사는 실제 Android
SDK, 공유 UI 또는 Play 서버 응답 실행과 별개다.
