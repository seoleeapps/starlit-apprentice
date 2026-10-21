# Android 개인정보와 데이터 보안 신고 근거

2026-10-21에 제품 소스와 Google 공식 안내를 대조했다. 이 문서는 Console 저장, 최종 AAB 의존성 검사와 실제 SDK 검수를 각각 대신하지 않는다. Console의 실제 저장 상태는 `docs/06-release/evidence/`의 관측 원장에 남긴다.

게임 진행, 엔딩, 선택 언어, 연령대와 광고 횟수는 기기에 저장한다. 로그인, Firebase, 서버 저장과 자체 분석 전송은 없다. 연령 미확정과 13세 미만에서는 광고 SDK 요청을 시작하지 않는다. 사용자는 타이틀에서 연령과 광고 개인정보 설정을 바꿀 수 있다.

광고 경로는 Poing AdMob 5.1.0에 포함된 Google GMA Next-Gen 1.4.0과 UMP다. [Google 데이터 공개 안내](https://developers.google.com/admob/android/next-gen/privacy/play-data-disclosure)는 광고, 분석과 부정행위 방지 목적으로 IP 기반 대략적 위치, 앱 상호작용, 진단 정보, 기기 식별자와 기기에 로그인된 계정 관련 식별자를 자동 수집하고 공유하며 TLS로 전송한다고 설명한다. 따라서 게임 자체 서버가 없다는 이유로 수집 없음으로 신고하지 않는다.

Console에는 대략적 위치, 앱 상호작용, 진단, 기기 또는 기타 ID, 사용자 ID를 수집과 공유로 신고한다. 계정 관련 식별자는 Google SDK의 조건부 수집을 포함하며 게임이 계정을 생성한다는 뜻은 아니다. 정확한 위치, 주소록, 결제와 게임 저장은 전송하지 않는다.

연령대 원문을 전송하지 않지만 13~17세는 `tag_for_under_age_of_consent` 보호 신호를 UMP와 광고 설정 양쪽에 전달한다. [UMP 안내](https://developers.google.com/admob/android/privacy/gdpr)는 두 경로에 각각 적용할 것을 요구한다. 이 파생 연령 보호 신호는 다른 개인 정보로 추가 신고하며, 광고 목적의 수집과 공유에 포함한다. 청소년은 개인맞춤을 제한하고 동의 또는 지역 조건을 충족하지 못하면 광고를 생략한다.

앱 기능은 광고 동의나 광고 제공 없이도 사용할 수 있어 광고 데이터 수집은 선택 사항으로 신고한다. 앱에는 계정 생성과 계정 삭제 대상이 없다. Google 광고 식별자와 SDK 측 데이터 처리는 Google의 정책과 이용자 제어를 따르며, 기기 저장 삭제를 원격 SDK 데이터 삭제로 설명하지 않는다.

공개 개인정보처리방침은 [한국어](https://www.seorilabs.com/apps/starlit-apprentice/privacy/)와 [영어](https://www.seorilabs.com/en/apps/starlit-apprentice/privacy/)다. 최종 배포 전 같은 AAB에서 실제 SDK, Firebase 부재와 운영 광고 설정을 검사하고 실제 UMP와 광고 표시 검수는 별도 승인된 범위에서만 수행한다.
