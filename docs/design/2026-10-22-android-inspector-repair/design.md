# Android 산출물 검사 도구 보완 설계

상태: 사용자가 이 보완안과 L3 개발 환경 전체 회귀1회 및1.0.1 재빌드를 승인했다. 승인 최초 관측 시각은2026-10-22T03:35:24Z다. 대화 원문은 `승인`이며 정확한 메시지 전송 시각은 제공되지 않았다. 승인한 원안 design SHA256은 `66057047b5bfb765e36cf9d818a9138bd815202b584220008a02f0db7790612a`, test-plan SHA256은 `4af6835b647629134b163b7c0c362f6a9d209e52c4c628dcefc7bbd116c55344`이다. 원안과 실패 원본은 저장소 밖에도 해시 대조해 보존했다. 기존 `v1.0.0`은 `8eafe3a41e71da87a3534a68fd71b72caf5168b8` 그대로 유지한다. 이 승인은 기기 사용이나 UI15를 포함하지 않는다.

## 현재 결과와 목적

실행 티켓은 [#58](https://github.com/seoleeapps/starlit-apprentice/issues/58)이며 단계별 결과는 [출시 원장](../../06-release/2026-10-22-android-inspector-repair.md)에 연결한다.

기존 후보의 UI12,13,14와 중앙 before-build는 통과했다. versionName1.0.0, versionCode1을 원장에서 할당하고 태그를 고정했다. 첫 서명 빌드 [39709196951](https://github.com/seoleeapps/starlit-apprentice/actions/runs/39709196951)은 AAB 생성 뒤 검사에서 실패했고 Play 업로드를 하지 않았다. 실패 로그와 원래 판정을 보존한다. 원래 AAB는 CI에 보존되지 않아 직접 재검사했다고 쓰지 않는다.

검사 코드를 실제 패키지 구조에 맞추고, 이후 실패한 AAB를 진단용으로 보존한다. 게임과 화면, 광고 정책, 연령과 동의 처리, 저장, 콘텐츠, 번들 폰트, SDK 버전, export 설정은 변경 대상이 아니다. 적용 전후 해당 파일들의 바이트 동일성을 목록과 해시로 대조한다.

## 확인한 검사 결함

1. 기존 검사는 DEX 전체에 `com/google/firebase/`가 있으면 실패한다. 공식 Google Maven의 `play-services-basement:18.9.0`은 `FirebaseException`, `FirebaseApiNotAvailableException`, `FirebaseExceptionMapper` 3개를 정의한다. 승인된 Next-Gen Ads1.4.0, UMP4.0.0과 Play Age Signals0.0.4가 이 라이브러리를 요구한다. 각 공식 POM과 AAR, 클래스 해시 및 바이트코드를 보존했다. 이 사실만으로 첫 AAB의 유일한 실패 원인이 그 3개였다고 단정하지 않는다.
2. 기존 광고 ID 검사는 `base/assets`에서만 바이트를 찾는다. [Godot4.7.2 공식 소스](https://github.com/godotengine/godot/blob/4.7.2-stable/platform/android/export/export_plugin.cpp)는 AAB 파일을 `assetPackInstallTime/src/main/assets`로 내보낸다. 기존 검사 함수의 고정 AAB 입력에서 정상 설치 시점 JSON과 Google 공통 클래스가 위 두 오류로 실패했다. 반대로 unrelated JSON에 광고 ID만 넣으면 실제 설정이 없어도 통과했다. 이 재현은 원래 실패 AAB의 재검사가 아니다.
3. 중앙 workflow의 일반 AAB 보존 단계는 앞 검사가 실패하면 실행되지 않는다. 첫 실행의 artifacts API 결과는0개였다.

## 변경 파일과 동작

앱 저장소:

- `tools/check_android_release.py`: 각 DEX의 표준 타입과 클래스 정의 표를 읽어 위 3개만 Google 공통 예외로 구분한다. 다른 Firebase 타입이나 참조, manifest의 Firebase 항목은 계속 실패시킨다. DEX별 실제 타입과 정의, 구분 결과를 보고한다. 지원하지 않는 header, 조회하는 표의 범위와 index 및 문자열 종료 오류를 차단한다. checksum, map과 모든 UTF16 길이를 검사하는 전체 DEX 유효성 검증기는 아니다. 공식 문서는 [Android DEX 형식](https://source.android.com/docs/core/runtime/dex-format)이다.
- 같은 도구에서 `assetPackInstallTime/assets/config/android_runtime.json`을 정확히 하나 읽고 JSON의 `interstitialAdUnitId`가 운영 입력과 같은지 확인한다. 다른 파일의 우연한 문자열로 통과시키지 않는다.
- `scripts/tests/test_android_bundle_inspection.py`: 위 회귀 입력과 다중 DEX, 제품 Firebase, 알 수 없는 타입, manifest, 손상 DEX, 잘못된 광고 설정을 검사한다. 기존 SDK 필수 항목, 서명, 패키지, 버전, API36과16KB 검사는 유지한다.
- 승인 후 이 설계와 테스트 계획, 실제 출시 원장을 `docs/design/2026-10-22-android-inspector-repair/` 및 `docs/06-release/`에 반영한다.

중앙 `seorilabs/.github`:

- `godot-deploy-google-play.yml`의 마지막에 실패할 때만 정확한 AAB 경로를 3일 보존하는 단계를 추가한다. 진단용 이름에 실행 ID와 attempt를 넣는다. job의 실패 판정, 검증, 업로드 조건과 권한을 바꾸지 않는다. 파일이 생성되지 않았다면 무시하며 키와 임시 디렉터리를 올리지 않는다. 중앙 변경은 별도 PR과 기존 필수 검사 및 리뷰를 거친다.

## 테스트와 인수조건

제안용 테스트12개가 통과했다. 그중2개는 기존 `inspect_aab` 전체 호출에서 서명과 ELF 및 manifest 입력만 고정하여 정상 거절과 잘못된 통과를 재현했다. 이 고정 입력은 실제 최종 AAB 검사, Android SDK 실행과 구분한다. 제안 workflow는 actionlint를 통과했다. 원래 실패 출력과 첫 통과 출력을 각각 보존한다.

검수 원장의 단계도 분리한다. before-build에는 AI-01의 고정 입력 검사, AI-02의 동일성, AI-03의 실제 새 후보 CI, AI-04의 workflow 정적 검토만 완료 조건으로 사용한다. AI-01의 실제 AAB와 AI-04의 다음 빌드 관측, AI-05의 태그와 내부 업로드 및 후속 승격은 그 시점에는 미실행으로 남긴다. 실제 빌드 뒤 산출물 결과를, 업로드 뒤 실제 트랙 결과를 추가한다. 실패 보존 경로가 실제 실행되지 않았다면 정적 검토와 구분해 미실행으로 기록한다. 이후 단계를 앞 단계의 통과로 미리 채우지 않는다.

승인 후 L3 전체 회귀를 **개발 환경**에서 새 후보의 GitHub-hosted CI1회로 실행한다. 깨끗한 첫 import와 캐시를 분리한 재실행, 실제 장면 좌표 입력, 양언어와 세 크기 렌더링, 전체220시나리오와650폰트 단언,390PNG를 기존 CI 그대로 실행한다. 일반 도구 테스트와 새12개도 실행한다. 이 실행이 실패하면 원본을 남기고 원인을 판정한다. 무제한 재실행을 허용하지 않는다.

이번 변경은 화면이나 제품 코드 변경이 없어 `redesign:false`로 계획한다. 기존 UI12~14는 이전8e 후보에서 완료된 사실과 해시를 그대로 보존하며 새 SHA의 검수로 고쳐 쓰지 않는다. UI15와 추가 UI3회를 시작하지 않는다. 다른 제품 파일을 바꿔야 하거나 게임 및 화면 실패가 발견되면 이 보완 범위에서 멈춘다. 전체 회귀와 첫 출시 플랫폼 하한은 유지한다. 실행 계획은 같은 폴더의 `test-plan.json`이다.

| ID | 합격 조건 | 실제 근거 |
|---|---|---|
| AI-01 | 정상 공통 예외3개와 실제 설치 시점 설정을 인식하며 실제 Firebase 서비스와 잘못된 설정은 계속 차단 | 기존 검사 red, 제안 검사 green, 실제 최종 AAB의 타입 목록과 JSON 경로 및 해시 |
| AI-02 | 게임, UI, 데이터, 폰트, SDK와 export 파일이8e와 같음 | 적용 전후 파일 목록 및 바이트 해시, 새 SHA의 전체 CI |
| AI-03 | 새 후보의 L3 dev 전체 회귀 통과 | 독립 CI run,220시나리오와390PNG, 시간 제한과 오류 로그 판정 |
| AI-04 | 실패 원본과 이후 진단용 AAB 보존, 실패 판정을 통과로 바꾸지 않음 | 첫 run 원본, 중앙 PR 검사, 실패 조건과 경로 검토, 다음 빌드 결과 |
| AI-05 | 태그와 버전을 덮어쓰지 않고 중앙 검증 뒤 같은 최종 AAB만 내부 업로드 및 후속 승격 | 새 원장 할당, 태그 결속, before-build/deploy/release, AAB 해시와 Play readback |

## 버전과 실행 순서

실패한 `v1.0.0`과 code1은 보존한다. 다음 표시 버전은 `1.0.1`을 제안하며 versionCode는 기존 업로드 최댓값과 원장을 다시 조회해 새로 할당한다. code2를 미리 확정하거나 기존 tag를 이동하지 않는다. GitHub Release는 Play 공개와 구분한다.

1. 승인 범위와 시각을 기록하고 중앙 진단 보존 PR을 정상 경로로 병합한다.
2. 검사 도구와 테스트 및 승인 설계만 반영하고 제품 파일의 동일성을 확인한다. 새 후보에서 전체 CI1회를 실행한다.
3. 최신 중앙 before-build를 통과한 뒤 새 태그를 할당하고 서명 빌드를1회 실행한다. 실제 최종 AAB 검사에서 두 결함이 해소됐는지 확인한다.
4. before-deploy 뒤 기존 공통 Publisher와 앱 전용 키로 내부 테스트에 올리고 실제 등록 버전과 트랙을 다시 읽는다. IAM, 계정 권한, 키를 바꾸지 않는다.
5. 기존 한국어와 영어, 무료,13세 이상, 전 국가,100% 공개 승인 범위를 이어간다. 실제 Android SDK와 동의 및 광고 복귀처럼 개발 환경으로 확인할 수 없는 항목은 미실행으로 남기며, 필요성이 구체화된 시점에 별도 기기 승인을 받는다. 이번 보완 승인은 기기 사용을 포함하지 않는다.

예상 개발 검증과 재빌드 시간은45~60분이다. 중앙 PR 대기와 Play 처리 및 심사 시간은 별도다. 추가 UI 회차와 과금 도구, 기기 사용, 저장 초기화와 광고 클릭을 이 시간에 포함해 승인받은 것으로 해석하지 않는다.

## 승인 근거와 복구

[폰트 보완 승인 설계](https://github.com/seoleeapps/starlit-apprentice/blob/8eafe3a41e71da87a3534a68fd71b72caf5168b8/docs/design/2026-10-22-font-inheritance-recovery/design.md)는 두 파일만 바꾸고 같은 후보에서 UI12~14회를 끝내도록 제한하며, 코드가 다시 바뀌어 같은 후보3회 조건을 채울 수 없으면 멈추도록 정했다. 완료된 화면 작업과 분리된 이번 검사 도구 보완 설계 및 L3 계획을 별도로 승인받았다. 새 후보에서는 이 도구 전용 계획을 적용하고 기존 설계의 완료된 개발 검수와 미실행 출시 의무를 별도 원장에 보존한다. 기존 계획을 몰래 고치거나 중앙 검증기를 완화해 통과시키지 않는다.

복구 시 기존 태그와 실패 로그 및 검수 원본을 유지하고 진단 파일로 원인을 비교한다. 중앙 진단 보존 단계는 독립 PR로 되돌릴 수 있다. 기존 키, 사용자 저장과 `.serena/`는 건드리지 않는다.
