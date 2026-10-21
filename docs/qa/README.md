# 개발 환경 검증

`feature-inventory.json`은 구현된 기능과 실제 시작 장면을 실행하는 여정을 연결한다. 광고 SDK 호출과 Android export 설정은 `platformPaths`로 구분한다. 개발 환경의 가짜 광고 어댑터는 실제 Android SDK 검증 근거가 아니다.

```bash
GODOT_BIN=/opt/homebrew/bin/godot bash scripts/test_all.sh
GODOT_BIN=/opt/homebrew/bin/godot bash scripts/godot_quality_gate.sh --project .
```

`test_all.sh`는 첫 import, 코어, 콘텐츠와 밸런스, 시뮬레이션, 시작 장면, 저장, 오디오, 레이아웃과 한국어 및 영어 전체 여정을 실행한다. 각 Godot 프로세스의 저장은 별도 임시 디렉터리에 격리한다. 로그와 오류 판정에 사용한 ANSI 제거 로그는 `build/qa/regression-*`에 보존한다. CI에서는 `GODOT_TEST_LOG_DIR=build/e2e/<회차>`로 지정한다.

```bash
python3 scripts/run_godot.py --log build/qa/render-ko.log -- \
  godot --path . --script res://tools/e2e/journey.gd -- \
  --out build/qa/render-ko --locale ko --width 640 --height 1136 --capture
```

Linux의 렌더링 실행은 같은 명령의 `godot` 앞에 `xvfb-run -a`를 두고 `--rendering-driver opengl3`를 추가한다. PNG를 실제로 열어 글자, 버튼, 본문과 스크롤을 확인한다. `--headless`는 렌더링을 하지 않으며 PNG 검수를 대신하지 않는다.

실제 장면과 게임 규칙을 그대로 실행하고 저장 경로, 시계, 난수와 광고 SDK 경계만 주입한다. 탭과 드래그는 `SubViewport.push_input`에 좌표를 넣으며 신호를 직접 발생시켜 화면을 건너뛰지 않는다. 여정은 시작, 카드 가로 스크롤, 스탯 화면, 언어와 연령 설정, 사운드, 재실행과 이어하기, 36턴, 이벤트 선택, 월말, 엔딩 기록, 미확인 이벤트 복원, 손상 저장 복구, 저장 실패와 재시도를 확인한다.

광고 정책 검사는 실제 service에 가짜 SDK를 연결한다. 첫 179초와 180초, 튜토리얼, 종료 후 119초와 120초, 세션 6회, UTC 하루 20회, 30분 비활동, 날짜 변경, 재실행, 중복 콜백, 미준비, 늦은 준비, 표시 실패와 저장 실패를 검사한다. 전체 게임 여정에서도 광고 표시 직전에 월말 여부, 미확인 이벤트 없음과 최신 저장 성공을 읽어 확인한다.

`native_ad_adapter_runner.gd`는 실제 Poing GDScript와 Android 어댑터에 가짜 native singleton을 주입한다. 연령 변경과 개인정보 재선택, 동의 요청 직렬화, 이전 응답 무시, 청소년 요청의 연령 태그와 비개인맞춤 인자를 확인한다. 실제 Android SDK나 동의 화면을 실행한 증거로 쓰지 않는다.

완료되지 않은 `journey.json`은 통과 근거가 아니다. 시나리오가 모두 통과하고 기능 목록 커버리지 검사가 성공한 실행만 사용한다. 후보 SHA와 다른 소스에서 실행한 사전 개발검사는 최종 출시 검증으로 옮겨 적지 않는다.
