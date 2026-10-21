# Android 첫 공개 출시 준비

현재는 구현과 개발 환경 검증 단계다. 서명 AAB, Play 업로드와 공개 출시는 완료하지 않았다. 이 문서는 개발 환경 실행 결과나 Console 조회를 대신하지 않는다.

## 승인 범위

Google Play의 `com.seorilabs.starlitapprentice`를 무료로 공개한다. 기본 표시 버전은 `1.0.0`이며 한국어와 영어, 한국을 포함한 배포 가능 국가 전체, 13세 이상이 대상이다. 내부 테스트를 거친 같은 AAB를 production에 100% 승격한다. Firebase, 서버 저장과 결제는 사용하지 않으며 전면광고만 포함한다.

2026-10-21 담당 에이전트의 인증된 Console 조회에서 `Seolee Apps` 개인 개발자 계정, ID `5547060480954653351`을 확인했다. 기존 앱 10개 목록에는 대상 패키지가 없었으며 이후 앱 shell `4972457200651625275`를 만들었다. 후속 live 조회에서 대상 패키지 등록 가능 상태, 버전 없음과 번들 없음을 확인했다. Publisher 접근 확인은 아직 필요하며 앱 shell을 공개 출시로 표시하지 않는다.

같은 세션에서 다음 공급자와 자격증명 상태를 확인했다. 실제 값이 포함된 비밀 파일은 이 원장에 저장하지 않는다.

| 대상 | 확인한 상태 |
|---|---|
| 앱 전용 업로드 키 | 새 키 생성. 인증서 SHA-256 `96:C4:E2:82:2B:0A:1B:DB:18:71:94:54:EF:79:83:9A:B4:72:C3:60:EC:B3:10:F5:E4:C4:15:A3:06:B0:45:A8`. Play 등록 인증서와의 일치 증거는 아직 없음 |
| 백업과 복원 | 로컬과 BeeStation 해시 `b4416f99c65ed86413348ddbdc4bf78824bce46e311664b3d423a535521a7d0b` 일치와 복원 검증 통과 |
| GitHub `google-play` Environment | 업로드 keystore base64, store password와 key password의 signing Secret 3개, alias와 기존 Publisher service account 변수 설정 완료. 값은 기록하지 않음 |
| AdMob | 앱 ID `ca-app-pub-9932778305312246~5434157983`, 전면광고 unit `ca-app-pub-9932778305312246/5426594130` 생성과 live 조회 완료. 광고 준비, Play 연결과 app-ads.txt는 별도 확인 필요 |
| WIF | 등록된 provisioner로 `iam.serviceAccounts.getIamPolicy` 조회 시 `PERMISSION_DENIED`. repository binding 존재와 적합성을 확인하지 못했으며 권한을 확대하지 않음. WIF 업로드 경로는 차단 상태 |

## 구현된 출시 경로

| 진입점 | 실행과 게이트 |
|---|---|
| `godot-checks.yml` | main과 PR에서 정적 검사, 서로 다른 캐시 초기화 2회와 실제 입력 E2E. public 러너 `ubuntu-latest`, 실행 로그와 여정 결과 보존 3일 |
| `init-release-version-ledger.yml` | 중앙 원장 초기화. 기본 dry run이며 관측한 최대 versionCode 없이 기준값을 추정하지 않음 |
| `release-tag.yml` | 운영자가 고른 후보에 중앙 원장 번호와 태그를 함께 할당. 첫 태그 `v1.0.0`, 기본 dry run |
| `deploy-google-play.yml` | 명시적 출시 태그와 수동 실행만. 중앙 `before-build`, 서명 AAB 검사, `before-deploy`, internal completed 업로드 |
| `promote-google-play.yml` | 수동 실행. 중앙 `before-release`를 통과한 태그의 같은 versionCode를 production completed, 비율 1로 승격 |
| `deploy-all.yml` | 현재 승인된 Google Play internal 업로드만 연결 |
| `check-web-budget.yml` | 수동 Web export와 기존 전송량 검사. main에서는 export하지 않음 |
| `cleanup-actions-storage.yml` | 운영자 수동 실행. 기본 조회만 수행 |

모든 중앙 workflow는 `seorilabs/.github`의 `@main`을 사용한다. 원장 초기화, 태그 생성과 업로드 작업을 아직 실행하지 않았다. 비밀값은 caller에 필요한 이름만 명시하며 Firebase와 분석 자격증명을 넘기지 않는다.

`scripts/build-android.sh`를 직접 실행하거나 build-only 모드를 사용해도 최신 중앙 checkout의 `before-build` 검증을 먼저 수행한다. 중앙 checkout이 없거나 오래됐거나 수정됐으면 빌드 전에 중단한다. 운영 키를 읽기 전 검증하므로 임시 서명 AAB로 이 조건을 우회하지 않는다.

중앙 Godot Play workflow의 caller build step에 `GH_TOKEN`이 없어 저장소의 중앙 재검증이 중단되는 결함을 확인했다. [중앙 PR #293](https://github.com/seorilabs/.github/pull/293)에서 기존 `${{ github.token }}` 전달과 회귀 assertion을 추가했고, 2026-10-21 09:57:38 UTC에 `a6dc6937f37eb5783ae249cfc315ba00f11fabfc`로 squash 병합한 뒤 원격 main 반영을 확인했다. 권한과 기존 검증 순서는 유지했다.

중앙 변경은 기존 누락 실패 재현, 1,630개 테스트, actionlint와 배포 패키지 검사를 통과했다. [PR의 Contract Checks](https://github.com/seorilabs/.github/actions/runs/39580876088) 성공과 미해결 리뷰 thread 0개를 확인한 뒤 병합했으며, [병합 SHA의 main CI](https://github.com/seorilabs/.github/actions/runs/39580988262)도 통과했다. 로컬 mcode 리뷰는 실행 step 한도로 결과를 받지 못해 작업 트리 전후 일치를 확인하고 자체 점검으로 진행했으며, 이 사유를 PR에 기록했다. 실제 Android 마켓 빌드나 업로드를 검증한 결과는 아니다.

## 산출물 검사

`tools/check_android_release.py --source-only`는 패키지, 무료 배포, 두 언어, 광고 포함 신고와 target SDK 36 이상을 검사한다. 운영 광고 ID나 Console 신고 완료를 확인하는 검사는 아니므로 main에서 미확정 운영값을 통과로 바꾸지 않는다.

`scripts/validate-android-artifact.sh`는 중앙 버전 검증 뒤 같은 AAB를 읽는다. package, versionName과 원장 versionCode, target API, AdMob과 UMP 클래스, Firebase 부재, 운영 광고 ID 주입, 서명 검증, 인증서 SHA-256, 모든 native ELF `PT_LOAD` 16KiB 정렬과 BundleConfig의 APK native page alignment를 검사한다. 업로드용 인증서가 Play에 등록된 인증서와 일치하는지는 Console 조회 근거가 별도로 필요하다. `SEORI_EXPECTED_UPLOAD_CERTIFICATE_SHA256`를 제공하면 해당 값과도 대조한다. 이 검사는 기기 SDK 동작을 증명하지 않는다.

빌드 단계의 로그, 검사 JSON과 AAB 해시는 `build/qa/android/<UTC-pid>/`에 남긴다. 키스토어의 임시 디렉터리와 분리하며 실패 시에도 로그를 삭제하지 않는다. 운영 광고 설정은 export에만 주입하고 `project.godot`과 로컬 runtime 설정의 기존 바이트를 종료 시 복구한다. Android와 iOS export의 `runnable`을 꺼 Editor one-click 실행의 자동 기기 조회를 비활성화하며 명시적 export 경로는 유지한다.

## 확인한 계약과 제약

2026-10-21에 중앙 main `e7f433c071cf5d3ad4434c02ddf6a12164749489`의 개발, 테스트 계획, 릴리스 정책과 재사용 workflow를 읽었다. 공개 저장소와 Android build는 GitHub-hosted `ubuntu-latest`로 실행한다. 일반 실행 근거는 같은 최종 후보 SHA에서 168시간 이내여야 한다.

중앙 `godot-checks.yml`에는 caller 검사 전에 검사되지 않은 import가 남아 있다. 저장소 caller는 그 뒤 자체 `.godot` 캐시를 지우고 첫 import부터 검사하는 실행을 두 번 수행한다. 첫 실행이 실패하면 두 번째 실행으로 덮지 않는다. 중앙 import 단계는 이번 수정에 포함하지 않았다.

중앙 Play reusable는 내부 업로드 성공 경로에서 caller의 `build/android/release-inspection.json`을 Actions artifact로 내보내는 입력이 없다. AAB의 최종 digest와 provenance는 중앙 artifact authority와 업로드 영수증으로 남고, 저장소 검사 결과는 job 로그에도 출력된다. 보고서 파일의 별도 장기 보존을 완료했다고 주장하지 않는다. 개발 E2E 로그와 캡처는 3일 보존 경로에 둔다.

## 남은 출시 조건

| 항목 | 상태와 필요한 근거 |
|---|---|
| 최종 후보와 개발 검증 | 승인 계획 커밋, 최종 SHA, 확인된 CI URL, 두 언어 E2E, 화면 크기별 렌더링과 독립 UI 검수 3회 필요 |
| Play 계정과 패키지 | 계정과 shell 생성 확인 완료. Publisher의 대상 앱 접근과 실제 패키지 소유 상태 후속 조회 필요 |
| 버전 원장 | Console에 버전과 번들이 없음을 관측. 중앙 원장 초기화와 `v1.0.0` 할당은 아직 미실행. `version/code=1`은 export 기본값이며 출시 번호 증거가 아님 |
| 업로드 서명 | 앱 전용 키, 백업과 복원 검증, GitHub signing 설정 완료. Play App Signing과 등록 인증서 확인, 최종 AAB 서명 검사는 미실행 |
| WIF | IAM 정책 조회 권한 부족으로 repository binding 확인 차단. 기존 공통 Publisher identity의 해당 앱 접근도 확인 필요 |
| 광고 운영 | 앱별 운영 ID 생성 확인 완료. GitHub 운영 변수 주입, AdMob 앱 연결과 준비 상태, app-ads.txt 확인 필요 |
| 정책과 등록 | SDK 기준 Data safety, 광고 포함, 개인정보처리방침 공개 URL, IARC와 한국 등급, 13세 이상 대상 설정 필요 |
| 스토어 화면 | 기존 스크린샷은 이전 화면 자료. 현재 Godot 화면의 한국어와 영어 실제 캡처로 교체 필요 |
| Android SDK 검수 | 계획의 기기 승인 범위 안에서 독립 검수 필요. 개발 E2E나 AAB 정적 검사로 통과 표시하지 않음 |
| 업로드부터 공개 | 서명 AAB 내부 업로드, 같은 AAB 승격, 심사 접수, 승인, 게시, 공개 스토어와 버전 readback 각각 필요 |

근거가 없는 단계는 미실행 또는 차단으로 기록한다. 위 표는 완료 증거가 아니다.

## 2026-10-21 추가 확인

- 개인정보처리방침: [한국어](https://www.seorilabs.com/apps/starlit-apprentice/privacy/), [영어](https://www.seorilabs.com/en/apps/starlit-apprentice/privacy/) 모두 200과 Next-Gen SDK 1.4.0 본문을 확인했다. [official PR85](https://github.com/seorilabs/seorilabs-official/pull/85), Pages 실행 39582055303 성공, 배포 SHA `9e1185c2f649b09bee3e0d4d379a3cdea527748d`다. Play Console 입력 완료와는 별도다.
- 기존 app-ads.txt의 게시자 `pub-9932778305312246`이 live에 있어 중복 추가하지 않았다. 신규 AdMob 앱의 스토어 연결과 앱 검토는 아직 필요하다.
- 공통 Publisher의 중앙 API 조회가 2026-10-21T10:06:58Z에 `READY`를 반환했다. bundle/apk 이력과 모든 track versionCodes가 비어 있었다. 임시 edit만 만들고 삭제했으며 게시 commit은 하지 않았다. 원본 조회 digest는 `cedb35e45b345537932012a60b27132fe9337be2350d8e281e02507463508bdd`다. 사람의 attestation으로 바꾸지 않고 이 실제 provider 조회를 원장 초기화에 사용한다.
- 현재 등록 이미지는 Godot 실제 720x1280 ko/en 화면이다. 과거 웹 UI의 태블릿 이미지는 제외했고 태블릿 등록 화면은 미실행이다. 등록 검증기의 `--allow-missing-tablet`는 해당 없는 선택 자산을 구분할 때만 사용하며 다른 정책 검사를 면제하지 않는다.

최종 후보 이후의 실행 근거는 SHA를 바꾸지 않도록 소스 밖의 실행 원장과 GitHub 검수 자산에 남긴다. 이 문서의 미실행 상태를 자동으로 통과로 해석하지 않는다.
