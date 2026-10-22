# Android 산출물 검사 도구 보완과 새 후보

현재 상태: 기존 후보의 개발 검수는 통과했고 첫 서명 AAB의 최종 검사는 실패했다. Play 업로드, 실제 Android SDK 검수, 심사 제출과 공개는 미실행이다. 사용자가 검사 도구 보완과 새 후보의 L3 개발 환경 전체 회귀1회 및1.0.1 재빌드를 승인했다. 새 versionCode는 아직 할당하지 않았다.

[승인 설계](../design/2026-10-22-android-inspector-repair/design.md), [테스트 계획](../design/2026-10-22-android-inspector-repair/test-plan.json), [실행 티켓#58](https://github.com/seoleeapps/starlit-apprentice/issues/58)을 따른다. 기기 사용과 추가 UI 회차는 포함하지 않는다.

## 기존 후보에서 완료한 개발 검수

후보 `8eafe3a41e71da87a3534a68fd71b72caf5168b8`의 UI12,13,14는 독립 검수자가 기능과 사용성을 각각 통과시켰다. 각 CI는220시나리오와390PNG,650폰트 단언을 실행했다. 실패한 UI11과 중단한 UI10의 원형 및 당시 승인도 보존했다. 이 결과를 새 SHA의 UI 검수로 고쳐 쓰지 않는다.

- [UI12 CI39703375013](https://github.com/seoleeapps/starlit-apprentice/actions/runs/39703375013), review SHA256 `939b36142323f943e56e7db4bc85ad7bf9f977c7589a232f11088033b43bbadc`.
- [UI13 CI39704999883](https://github.com/seoleeapps/starlit-apprentice/actions/runs/39704999883), review SHA256 `cbdcc278d97b25ce29cb57060959b8fe55ebe33f8c50ad8b96eaf3468b986ebd`.
- [UI14 CI39706391449](https://github.com/seoleeapps/starlit-apprentice/actions/runs/39706391449), review SHA256 `180d7f7720b9aec0f4e017eb71ee7b66992d96eb41666f83a41026bddf01ebdd`.

실제 중앙 before-build는2026-10-22T01:53:50.909619Z에 통과했다. receipt SHA256은 `e4a2da81c61d674f3f4a6bdc272eae021d590e447f9fde02c1a50d62bbd05f57`이다. 이 통과는 위8e 후보에만 적용한다.

## 원래 태그와 첫 빌드 실패

[태그 할당 CI39708708635](https://github.com/seoleeapps/starlit-apprentice/actions/runs/39708708635)가 `v1.0.0`, versionCode1을 할당했다. 태그 객체는 `200c6036952bea79072a628e5959d16473b17345`, 원장 commit은 `6514be25a266d09ac2dc4bd8c57908ab3f8304e9`다. 같은 태그를 이동하거나 code1을 덮어쓰지 않는다.

[GitHub Release](https://github.com/seoleeapps/starlit-apprentice/releases/tag/v1.0.0)에는 개발 근거와 검수 원본 및 해시를 보존했다. GitHub Release 게시를 Play 공개로 해석하지 않는다.

[서명 빌드39709196951](https://github.com/seoleeapps/starlit-apprentice/actions/runs/39709196951)은 Godot import와 export 뒤 `unexpected Firebase runtime dependency`, `production interstitial ID was not found in exported runtime config` 두 항목으로 실패했다. `upload:false`였으며 Play에 올리지 않았다.

로그에 기록된 AAB SHA256은 `97b8be6195939b5b67239f4f8f1571eaed9874e07953b532fb191f5a0989a677`이다. 원래 AAB는 Actions artifact로 보존되지 않았다. 따라서 그 파일을 직접 재검사했다거나 실제 Firebase 검출 클래스가 정확히3개였다고 주장하지 않는다. 원본 workflow 로그 ZIP SHA256은 `c46f602cf1860e5d7815de9ab48aeb5985b726954f44fb8839ab1f3cf9d5012d`이다.

## 승인한 보완과 검증 범위

Google 공통 라이브러리의 예외3개를 실제 Firebase 제품 타입과 구분하고, Godot의 설치 시점 asset pack에서 정확한 운영 JSON을 읽는 검사 도구와 회귀 테스트를 반영한다. 구현 전 제안의 독립12테스트와 기본 CI 검색 경로 검사는 통과했다. 실제 적용 뒤 일반 도구 테스트23개도 통과했다. 고정 입력 결과는 실제 AAB 검사와 구분한다.

기존 제품 파일560개의 작업 내용과8e 태그의 Git 객체가 일치했다. 승인한 변경은 검사 도구와 테스트, 설계 및 출시 문서에 한정한다. 새 후보가 정해지면 같은 비교를 다시 확인하고 GitHub-hosted CI1회로 전체 회귀를 실행한다. 중앙 보존 변경은 별도 PR을 거친다.

| 단계 | 현재 상태 |
|---|---|
| 새 후보의 L3 개발 전체 CI | 미실행 |
| 새 후보의 중앙 before-build | 미실행 |
|1.0.1 태그와 versionCode 할당 | 미실행 |
| 새 서명 AAB의 실제 최종 검사 | 미실행 |
| 내부 업로드와 처리 확인 | 미실행 |
| 실제 Android SDK와 동의 및 광고 복귀 | 미실행, 별도 기기 사용 승인 필요 |
| production 승격, 심사, 승인, 게시, 공개 버전 | 미실행 |

2026-10-22T02:05:24.778381Z Console 조회에서 Seolee Apps 개인 계정, 개발자 ID `5547060480954653351`, 앱 `4972457200651625275`와 패키지 `com.seorilabs.starlitapprentice`를 다시 확인했다. 국가177개 및 기타 국가, 한국어와 영어 등록 정보와 신고 저장 상태도 읽었다. AdMob는 스토어 미연결과 검토 필요 상태이며 app-ads.txt 응답 성공을 광고 준비 통과로 쓰지 않는다. 다음 외부 변경 전 대상과 공급자 상태를 다시 확인한다.
