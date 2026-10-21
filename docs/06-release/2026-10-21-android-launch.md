# Android 첫 공개 출시 준비

로컬 저장, 한국어와 영어, 전면광고와 출시용 Actions 구현을 main에 반영했다. 개발 환경 후보 `123f271136a9406d8390df8d17090a6a97b248c4`의 전체 회귀와 최종 화면 검수는 통과했지만, 초기 두 검수의 근거 누락과 WIF 인증, 국가별 등급 조건으로 출시 준비가 차단됐다. 서명 AAB, Play 업로드, 심사 접수와 공개 출시는 미실행이다.

## 승인 범위

Google Play의 `com.seorilabs.starlitapprentice`를 무료로 공개한다. 기본 표시 버전은 `1.0.0`이며 한국어와 영어, 한국을 포함한 배포 가능 국가 전체, 13세 이상이 대상이다. 내부 테스트를 거친 같은 AAB를 production에 100% 승격한다. Firebase, 서버 저장과 결제는 사용하지 않으며 전면광고만 포함한다.

2026-10-21 담당 에이전트의 인증된 Console 조회에서 `Seolee Apps` 개인 개발자 계정, ID `5547060480954653351`을 확인했다. 기존 앱 10개 목록에는 대상 패키지가 없었으며 이후 앱 shell `4972457200651625275`를 만들었다. 후속 live 조회에서 대상 패키지 등록 가능 상태, 버전 없음과 번들 없음을 확인했다. 앱 shell을 공개 출시로 표시하지 않는다.

2026-10-21 10:06:58 UTC에 등록된 `shared/google-play/publisher`로 중앙 조회 스크립트를 한 번 실행했다. 임시 edit 생성, bundle과 APK 및 track 목록 조회, edit 삭제가 성공했고 게시 commit은 하지 않았다. [원본 API 관측](evidence/2026-10-21-play-version-readback.json)은 READY이며 bundle과 APK, production, beta, alpha, internal의 versionCodes가 모두 비어 있다. API의 `maxVersionCode: null`을 중앙 원장 판정기가 baseline 0으로 정규화해 READY를 반환했다. 이는 로컬 준비 판정이며 원격 원장 생성과 versionCode 할당은 미실행이다. human-attestation을 사용하지 않았다.

같은 세션에서 다음 공급자와 자격증명 상태를 확인했다. 실제 값이 포함된 비밀 파일은 이 원장에 저장하지 않는다.

| 대상 | 확인한 상태 |
|---|---|
| 앱 전용 업로드 키 | 새 키 생성. 인증서 SHA-256 `96:C4:E2:82:2B:0A:1B:DB:18:71:94:54:EF:79:83:9A:B4:72:C3:60:EC:B3:10:F5:E4:C4:15:A3:06:B0:45:A8`. Play 등록 인증서와의 일치 증거는 아직 없음 |
| 백업과 복원 | 최종 카탈로그 반영 뒤 로컬과 BeeStation 해시 `22bda217a54d82366d43eacab2d4eb5d8659738f84ea41bc8e7a45db8211d6a0` 일치, 양쪽 5,982개 파일 복원 검증 통과 |
| GitHub `google-play` Environment | 업로드 keystore base64, store password와 key password의 signing Secret 3개, alias와 기존 Publisher service account 변수 설정 완료. 값은 기록하지 않음 |
| AdMob | 앱 ID `ca-app-pub-9932778305312246~5434157983`, 전면광고 unit `ca-app-pub-9932778305312246/5426594130` 생성과 live 조회 완료. 공식 사이트의 app-ads.txt 게시자 일치 확인. 광고 준비와 Play 연결은 미완료 |
| WIF | 등록된 provisioner로 `iam.serviceAccounts.getIamPolicy` 조회 시 `PERMISSION_DENIED`. repository binding 존재와 적합성을 확인하지 못했으며 권한을 확대하지 않음. 공통 Publisher의 직접 API 조회 성공과 별개로 WIF 업로드 경로는 차단 상태 |

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
| 개발 검증 | `123f271`의 깨끗한 캐시 전체 회귀 2회, quality gate 2회와 UI3의 ko/en 각 세 크기 실제 입력 여정 통과. UI1/2의 SHA와 계획 시각 결손으로 정상 출시 근거 구성은 차단 |
| Play 계정과 패키지 | 계정과 shell 생성, 공통 Publisher의 해당 package 조회 확인 완료. 이 결과는 production 권한과 공개 상태를 증명하지 않음 |
| 버전 원장 | 실제 Publisher API의 빈 업로드 이력으로 로컬 중앙 init 판정 READY, baseline 0 확인. 중앙 원장 초기화와 `v1.0.0` 할당은 아직 미실행. `version/code=1`은 export 기본값이며 출시 번호 증거가 아님 |
| 업로드 서명 | 앱 전용 키, 백업과 복원 검증, GitHub signing 설정 완료. Play App Signing과 등록 인증서 확인, 최종 AAB 서명 검사는 미실행 |
| WIF | IAM 정책 조회 권한 부족으로 repository binding 확인 차단. 공통 Publisher의 해당 앱 조회는 통과했으며 GitHub WIF 인증과 업로드는 미실행 |
| 광고 운영 | 앱과 전면광고 운영 ID 생성, GitHub 변수 주입과 app-ads.txt 게시자 일치 확인. AdMob Play 연결, 앱 검토와 실제 SDK 표시 및 동의는 미확인 |
| 정책과 등록 | 두 언어 개인정보처리방침 공개. Console 개인정보 URL, 광고 포함과 로그인 불필요 저장 확인. IARC 설문 초안 결과 호주18+, 한국15+로 승인 대상과 충돌. Data safety와 나머지 등록 상태는 별도 관측 원장 참고 |
| 스토어 화면 | 현재 Godot ko/en 실제 전화 화면 각5개와 기존 아트 및 실제 화면 합성의 1024x500 큰 이미지 준비. 이전 전화 및 태블릿 이미지는 활성 등록 목록에서 제외. Console 등록 저장은 별도 확인 |
| Android SDK 검수 | 미실행. 실제 UMP 양식, 광고 표시와 닫기 후 복귀는 데스크톱 대역으로 확인할 수 없음. 대상 기기와 최소 실행 항목을 소명한 별도 명시적 승인 전에는 접근하지 않음 |
| 업로드부터 공개 | 서명 AAB 내부 업로드, 같은 AAB 승격, 심사 접수, 승인, 게시, 공개 스토어와 버전 readback 각각 필요 |

근거가 없는 단계는 미실행 또는 차단으로 기록한다. 위 표는 완료 증거가 아니다.

## 2026-10-21 추가 확인

- 개인정보처리방침: [한국어](https://www.seorilabs.com/apps/starlit-apprentice/privacy/), [영어](https://www.seorilabs.com/en/apps/starlit-apprentice/privacy/) 모두 200과 Next-Gen SDK 1.4.0 본문을 확인했다. [official PR85](https://github.com/seorilabs/seorilabs-official/pull/85), Pages 실행 39582055303 성공, 배포 SHA `9e1185c2f649b09bee3e0d4d379a3cdea527748d`다. Play Console 입력 완료와는 별도다.
- 기존 app-ads.txt의 게시자 `pub-9932778305312246`이 live에 있어 중복 추가하지 않았다. 신규 AdMob 앱의 스토어 연결과 앱 검토는 아직 필요하다.
- 공통 Publisher의 중앙 API 조회가 2026-10-21T10:06:58Z에 `READY`를 반환했다. bundle/apk 이력과 모든 track versionCodes가 비어 있었다. 임시 edit만 만들고 삭제했으며 게시 commit은 하지 않았다. 원본 조회 digest는 `cedb35e45b345537932012a60b27132fe9337be2350d8e281e02507463508bdd`다. 사람의 attestation으로 바꾸지 않고 이 실제 provider 조회를 원장 초기화에 사용한다.
- 현재 등록 이미지는 Godot 실제 720x1280 ko/en 화면이다. 과거 웹 UI의 태블릿 이미지는 제외했고 태블릿 등록 화면은 미실행이다. 등록 검증기의 `--allow-missing-tablet`는 해당 없는 선택 자산을 구분할 때만 사용하며 다른 정책 검사를 면제하지 않는다.

검증 결과는 실행한 SHA의 근거로만 사용한다. 이 원장이나 이후 CI 수정 커밋에 과거 실행을 소급 결속하지 않는다. 미실행과 차단을 통과로 해석하지 않는다.


## 개발 실행과 근거 결손

[개발 실행 요약](evidence/2026-10-21-dev-summary.json)은 정확한 `123f271` archive 입력에 결속됐다. 독립 검수자가 임시 저장 경로와 고정 난수, 시계, 광고 경계 대역을 사용해 ko/en, 640x1136과 720x1280, 720x1600을 순차 실행했다. 각 여정의 9개 시나리오가 10개 기능을 덮는다. 번역 검사 8,324개와 실제 vendor GDScript의 native 대역 계약 검사 15개도 통과했다. PNG72개를 보존하고 대표54개를 직접 검수했으며 해당 macOS 실행의 Godot 오류와 누수 로그는 0개다. 이는 Android SDK 실제 노출의 증거가 아니다.

초기 UI1은 영어 카드 잘림으로 UX 실패, UI2는 영어 가로 드래그 실패로 기능 실패였다. UI3에서 두 문제의 해결을 확인했다. 다만 구현 중인 dirty tree에서 UI1/2를 실행할 때 후보 snapshot/SHA와 계획 시각을 남기지 못했다. 당시 HEAD는 승인 문서 커밋이어서 제품 소스의 SHA로 사용할 수 없다. 원본 실패 기록을 보존하며 과거 계획과 SHA를 만들어 채우지 않는다. 3회 검수 요건의 근거가 불충분하므로 `before-build` 통과 자료를 만들거나 검증기를 우회하지 않았다.

Linux CI [39582734964](https://github.com/seoleeapps/starlit-apprentice/actions/runs/39582734964)는 headless 전체 회귀와 quality gate를 두 번 통과했지만 렌더링에서 ALSA 장치 초기화와 오디오 참조 누수 오류로 실패했다. `b990a27`에서 Dummy 드라이버를 명시한 뒤 [39584182229](https://github.com/seoleeapps/starlit-apprentice/actions/runs/39584182229)에서는 장치 오류가 없어지고 같은 누수만 남았다. 작은 렌더링 재현에서 `AudioStreamPlaybackOggVorbis`, `OggPacketSequencePlayback`, BGM 리소스가 남는 것을 확인했다. `264893f`는 실제 오디오 드라이버가 Dummy이면 재생을 시작하지 않게 고쳤다. 같은 재현과 기존 오디오 검사가 오류 없이 통과했으며 Linux 전체 CI의 별도 결과가 필요하다. 로그 오류 검사를 완화하지 않았다.

Godot이 첫 import에서 자동 보정한 vendor CSV 번역 목적지 경로도 실제 addon 경로로 고쳤다. API와 vendor 바이너리는 바꾸지 않았고 `addons/admob/SOURCE.json`에 이 차이를 기록했다. UI3 원본은 그 자동 보정 차이를 별도 기록한 상태로 보존했다.

## 추가 결정이 필요한 항목

[후속 변경 제안](2026-10-21-launch-blockers.md)은 미승인 제안이다. 승인 전 UI 추가 검수, 내용 변경이나 대상 연령 및 국가 변경을 시작하지 않는다. WIF는 현재 등록 identity의 정책 조회 권한 부족으로 차단됐으며 다른 identity로 바꾸거나 권한을 넓히지 않았다. 최종 AAB 검사, 내부 업로드, 실제 SDK 검수, production 승격과 심사 및 공개 확인은 이 조건들이 풀린 뒤 별도 실제 근거를 남긴다.


## Console 등록 관측

[Console 관측 원장](evidence/2026-10-21-console-registration.json)의 마지막 재확인은 2026-10-21T10:34:46Z다. Dashboard는11항목 중8항목 완료였고 개인정보 URL, 광고 포함, 로그인 제한 없음, 정부 앱 아님, 금융 및 건강 기능 없음, 시뮬레이션 분류와 연락처 저장을 재확인했다. IARC 설문은 게시 개요에 저장했고 Google 심사 전송은 하지 않았다. 한국15+와 호주18+는 설문 요약의 관측값이며 최종 심사나 국가별 배포 허가로 표시하지 않는다.

한국어 등록 문구는 Console 임시보관함에 저장한 뒤 reload로 유지됨을 확인했다. 영어 문구와 모든 이미지는 아직 Console에 저장하지 않았다. Publisher API에서 두 언어와12개 이미지를 임시 edit에 준비했으나 `changesNotSentForReview` 플래그를 사용할 수 없다는400응답을 받았다. 자동 심사로 이어질 수 있는 재시도 대신 edit를 삭제했으며 원격 등록으로 반영되지 않았다. 수동 이미지 입력 UI의 존재만 확인했다. 타겟층과 Data safety, 국가 및 가격 최종 readback, AdMob 스토어 연결과 UMP 메시지는 미완료다. 원본 API응답과 설문 화면, 한국어 draft 화면을 소스 밖에 보존하고 관측 원장에 해시를 남겼다. 해당 브라우저 세션은 정상 종료했다.
