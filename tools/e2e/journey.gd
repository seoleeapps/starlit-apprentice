extends SceneTree
## 실제 main.tscn과 게임 로직을 좌표 입력으로 실행한다.
## 저장 디렉터리, 시계, 난수와 광고 SDK 경계만 주입한다.
const Driver := preload("res://tools/e2e/e2e_driver.gd")
const FakeClock := preload("res://tools/e2e/fakes/clock.gd")
const AdPolicyCases := preload("res://tools/e2e/ad_policy_cases.gd")
const FakeAd := preload("res://tools/e2e/fakes/ad_adapter.gd")
const FakeAge := preload("res://tools/e2e/fakes/age_signals.gd")
const AgeAccessCases := preload("res://tools/e2e/age_access_cases.gd")
const TestStorage := preload("res://tools/e2e/fakes/storage.gd")
const RatingEventFixture := preload("res://tools/e2e/fakes/rating_event_fixture.gd")

# 직접 캡처도 같은 검사 경계를 거친다. 입력과 캡처는 기존 도우미가 실행한다.
class FontCheckingDriver extends Driver:
	var check_fonts: Callable

	func _init(p_tree: SceneTree, size: Vector2i, directory: String, capture_enabled: bool, checker: Callable) -> void:
		super(p_tree, size, directory, capture_enabled)
		check_fonts = checker

	func shot(name: String) -> void:
		check_fonts.call(name)
		await super.shot(name)

var e2e: RefCounted
var clock := FakeClock.new()
var ad: SaAdAdapter
var storage: SaFileStorage
var profile: Node
var main: Control
var locale := "ko"
var out := ""
var event_count := 0
var month_count := 0
var tuition_count := 0
var _event_shot := false
var _settlement_shot := false
var _rating_fixture_records: Array = []

func _initialize() -> void:
	profile = root.get_node(^"Profile")
	var save_dir := OS.get_environment("STARLIT_SAVE_DIR")
	if save_dir.is_empty():
		save_dir = "user://e2e/%d" % OS.get_process_id()
	DirAccess.make_dir_recursive_absolute(save_dir)
	storage = TestStorage.new(save_dir.path_join("journey-run.json"), save_dir.path_join("journey-meta.json"))
	profile.use_storage(storage)
	call_deferred("_run")

func _arg(key: String, fallback: String) -> String:
	var args := OS.get_cmdline_user_args()
	var index := args.find(key)
	return args[index + 1] if index >= 0 and index + 1 < args.size() else fallback

func _run() -> void:
	locale = _arg("--locale", "ko")
	out = _arg("--out", "res://build/e2e/%s" % locale)
	var width := int(_arg("--width", "720"))
	var height := int(_arg("--height", "1280"))
	e2e = FontCheckingDriver.new(self, Vector2i(width, height), out, OS.get_cmdline_user_args().has("--capture"), _check_visible_fonts)
	profile.set_language(locale)
	AdPolicyCases.new().run(e2e)
	await _first_session()
	await _settings_restore()
	await _full_run()
	await _pending_event_restore()
	await _corrupt_save()
	await _write_failure()
	await _rating_event_copies()
	await AgeAccessCases.new().run(self)
	if main != null and is_instance_valid(main):
		await e2e.unmount(main)
	var audio := root.get_node_or_null(^"Audio")
	if audio != null:
		audio.release()
	var status: int = e2e.finish({"sourceSha": OS.get_environment("GITHUB_SHA"), "locale": locale,
		"seed": 4242, "clockStart": 1792540800, "dataIsolation": "temporary-file-storage",
		"ratingEventFixtures": _rating_fixture_records})
	print("E2E %s: %s, events=%d, months=%d" % [locale, "PASS" if status == 0 else "FAIL", event_count, month_count])
	e2e.viewport.queue_free()
	await e2e.frames(3)
	quit(status)

func _mount(age_override: SaAgeSignalsAdapter = null) -> void:
	main = load("res://scenes/main.tscn").instantiate()
	main.set("age_adapter", age_override if age_override != null else FakeAge.new())
	main.set("clock", Callable(clock, "now"))
	main.set("seed_provider", Callable(clock, "seed_value"))
	ad = FakeAd.new()
	ad.set("before_show", func() -> Dictionary:
		var run := _controller()
		return {"played_turn": int(run.last_result.get("played_turn", 0)),
			"events_left": run.pending_events.size(),
			"saved_turn": int((profile.load_run().get("state", {}) as Dictionary).get("turn", -1)),
			"turn": run.turn()})
	var service := SaInterstitialService.new(ad)
	service.clock = Callable(clock, "now")
	main.set("ad_service", service)
	await e2e.mount(main)

func _first_session() -> void:
	e2e.begin("first-session-%s" % locale, ["core-loop", "card-scroll", "settings"])
	await _mount()
	e2e.expect_equal("지정 언어로 타이틀 표시", main.get("_locale"), locale)
	await _shot("01-title")
	e2e.step("이어할 저장이 없는 타이틀", _find("resume") == null)
	await _tap("start")
	var turn: Control = main.get("_turn_screen")
	e2e.step("실제 턴 화면 표시", is_instance_valid(turn))
	e2e.step("논리 화면이 viewport를 채움", main.size == Vector2(e2e.viewport.size))
	var scroll := main.find_child("ActionScroll", true, false) as ScrollContainer
	e2e.step("행동 목록 존재", scroll != null)
	if scroll != null:
		var view := scroll.get_global_rect()
		var pos := view.position + Vector2(view.size.x * 0.7, 20)
		for card in _all_with_prefix(main, "action-card:"):
			var rect: Rect2 = card.get_global_rect()
			if view.encloses(rect):
				pos = Vector2(rect.get_center().x, rect.position.y + 16)
		await e2e.drag(pos, pos - Vector2(270, 0), 12, 0.25)
		e2e.step("카드 위 가로 드래그가 스크롤됨", scroll.scroll_horizontal > 0, str(scroll.scroll_horizontal))
	await _shot("02-action-scroll")
	await _tap("portrait")
	e2e.step("스탯 화면 닫기 표시", _find("close") != null)
	await _shot("03-constellation")
	await _tap("close")
	await _play_one()
	e2e.expect_equal("첫 행동 뒤 턴 증가", _controller().turn(), 2)
	e2e.end()

func _settings_restore() -> void:
	e2e.begin("settings-and-restart-%s" % locale, ["settings", "localization", "audio", "save"])
	var before: Dictionary = _controller().to_save().duplicate(true)
	await _tap("menu")
	var audio := root.get_node(^"Audio")
	var original_sound: bool = audio.sound_enabled
	await _tap("sound")
	e2e.expect_equal("사운드 설정 변경", audio.sound_enabled, not original_sound)
	await _tap("sound")
	e2e.expect_equal("사운드 설정 복귀", audio.sound_enabled, original_sound)
	await _tap("language")
	var other := "en" if locale == "ko" else "ko"
	e2e.expect_equal("언어 변경이 메타에 저장됨", profile.language(), other)
	await _tap("language")
	e2e.expect_equal("원래 언어로 복귀", profile.language(), locale)
	for band in ["under13", "13-15", "16-17", "adult"]:
		await _tap("age")
		await _shot("04-age-%s" % band)
		await _tap("age:%s" % band)
		e2e.expect_equal("연령대 로컬 저장 %s" % band, profile.meta().get("age_band", "unknown"), band)
	await _tap("age")
	await _tap("close")
	e2e.step("연령창 닫기 뒤 타이틀 복귀", _find("resume") != null)
	await _tap("privacy")
	# SDK 미지원 개발환경의 개인정보 요청은 타이틀을 차단하지 않는다.
	e2e.step("개인정보 요청 뒤 타이틀 사용 가능", _find("resume") != null)
	await e2e.unmount(main)
	await _mount()
	e2e.expect_equal("재실행 언어 복원", main.get("_locale"), locale)
	await _tap("resume")
	await _drain_results()
	e2e.expect_equal("이어하기 턴 복원", _controller().turn(), int((before["state"] as Dictionary)["turn"]))
	e2e.expect_equal("이어하기 RNG 복원", _controller().rng.state(), int(before["rng"]))
	e2e.expect_equal("이어하기 스탯 복원", _controller().state.get("stats"), (before["state"] as Dictionary).get("stats"))
	e2e.end()

func _full_run() -> void:
	e2e.begin("thirty-six-turns-%s" % locale, ["core-loop", "events", "monthly-settlement", "endings", "save", "ads"])
	var guard := 0
	while _find("restart") == null and guard < 36:
		guard += 1
		clock.advance(60)
		if not await _play_one():
			break
	var ad_traces: Array = ad.get("trace")
	e2e.step("전체 여정에서 준비 광고가 표시됨", not ad_traces.is_empty())
	for trace in ad_traces:
		e2e.expect_equal("광고는 월말 턴에만 표시", int(trace["played_turn"]) % 3, 0)
		e2e.expect_equal("광고 전에 모든 이벤트 결과를 확인", int(trace["events_left"]), 0)
		e2e.expect_equal("광고 전에 최신 런 저장 성공", int(trace["saved_turn"]), int(trace["turn"]))
	e2e.expect_equal("36턴을 모두 끝냄", _controller().turn(), 37)
	e2e.expect_equal("월말 화면 경계 12회", month_count, 12)
	e2e.expect_equal("종료 월을 제외한 수업료 정산 11회", tuition_count, 11)
	e2e.step("선택 이벤트가 실제로 등장함", event_count > 0, str(event_count))
	e2e.step("엔딩 화면 다시 시작 버튼", _find("restart") != null)
	e2e.expect_equal("엔딩 완주 회수 저장", profile.runs_completed(), 1)
	e2e.step("엔딩 기록 보존", not (profile.meta().get("endings", []) as Array).is_empty())
	e2e.step("완주한 런은 이어하기에서 제거", not profile.has_saved_run())
	await _shot("08-ending")
	await _tap("restart")
	e2e.step("다시 시작이 타이틀로 복귀", _find("start") != null)
	await e2e.unmount(main)
	await _mount()
	e2e.expect_equal("재실행 엔딩 기록 보존", profile.runs_completed(), 1)
	e2e.end()

func _pending_event_restore() -> void:
	e2e.begin("pending-event-restart-%s" % locale, ["events", "save"])
	await _tap("start")
	var cards := _all_with_prefix(main, "action-card:")
	if e2e.step("재실행 검증을 위한 행동 존재", not cards.is_empty()):
		e2e.step("첫 행동 좌표 입력", await e2e.tap(cards[0]))
		await _tap("continue")
		var pending: Array = _controller().pending_events
		e2e.step("이벤트 선택 전 저장 큐가 남음", not pending.is_empty())
		var event_id := String((pending[0] as Dictionary).get("id", "")) if not pending.is_empty() else ""
		await e2e.unmount(main)
		await _mount()
		await _tap("resume")
		var restored: Array = _controller().pending_events
		e2e.step("이어하기가 미확인 이벤트를 먼저 보여줌", not _all_with_prefix(main, "event-choice:").is_empty())
		e2e.expect_equal("동일 미확인 이벤트 복원", String((restored[0] as Dictionary).get("id", "")) if not restored.is_empty() else "", event_id)
		await _drain_results()
		e2e.expect_equal("복원한 이벤트 확인 뒤 큐를 비움", _controller().pending_events.size(), 0)
	e2e.end()

func _corrupt_save() -> void:
	e2e.begin("corrupt-save-recovery-%s" % locale, ["save"])
	await _tap("menu")
	await _tap("start")
	await _play_one()
	await _play_one()
	var path := String(storage.get("_run_path"))
	var backup := JSON.new()
	e2e.step("직전 저장 백업이 존재함", FileAccess.file_exists(path + ".bak"))
	var expected_turn := 0
	if backup.parse(FileAccess.get_file_as_string(path + ".bak")) == OK:
		expected_turn = int(((backup.data as Dictionary).get("state", {}) as Dictionary).get("turn", 0))
	await e2e.unmount(main)
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string("{damaged save")
	file.close()
	await _mount()
	await _tap("resume")
	e2e.expect_equal("손상된 본체 대신 백업 턴 복원", _controller().turn(), expected_turn)
	await _drain_results()
	e2e.expect_equal("손상 복원 뒤 엔딩 메타 보존", profile.runs_completed(), 1)
	await e2e.unmount(main)
	for target in [path, path + ".bak"]:
		file = FileAccess.open(target, FileAccess.WRITE)
		file.store_string("{invalid")
		file.close()
	await _mount()
	e2e.step("모든 런 저장 손상 시 이어하기 숨김", _find("resume") == null)
	e2e.expect_equal("구문 손상 원본을 자동 삭제하지 않음", FileAccess.get_file_as_string(path), "{invalid")
	await e2e.unmount(main)
	var invalid_payload := {"schema": 1, "state": {}}
	file = FileAccess.open(path, FileAccess.WRITE)
	var invalid_text := JSON.stringify(invalid_payload)
	file.store_string(invalid_text)
	file.close()
	await _mount()
	await _tap("resume")
	e2e.step("의미상 손상 저장은 실패 안내를 표시", _find("close") != null)
	e2e.expect_equal("이어하기 실패도 원본 저장을 보존", FileAccess.get_file_as_string(path), invalid_text)
	await _shot("09-corrupt-save")
	await _tap("close")
	await _tap("start")
	e2e.expect_equal("손상 뒤 새 게임 가능", _controller().turn(), 1)
	e2e.end()

func _write_failure() -> void:
	e2e.begin("save-failure-%s" % locale, ["save", "ads"])
	var before: Dictionary = profile.load_run().duplicate(true)
	storage.set("fail_writes", true)
	clock.advance(180)
	var shows_before := int(ad.get("show_calls"))
	for i in 3:
		await _play_one()
	e2e.expect_equal("월말 저장 실패 시 광고 차단", int(ad.get("show_calls")), shows_before)
	e2e.step("저장 실패 시도 실행", int(storage.get("write_attempts")) > 0)
	e2e.expect_equal("저장 실패가 직전 정상 저장을 보존", profile.load_run(), before)
	var cards := _all_with_prefix(main, "action-card:")
	if not cards.is_empty():
		e2e.step("저장 재시도 검증을 위한 다음 행동", await e2e.tap(cards[0]))
		e2e.step("저장 실패 재시도 버튼 표시", _find("retry") != null)
		await _shot("10-save-retry")
		storage.set("fail_writes", false)
		await _tap("retry")
		e2e.expect_equal("사용자 재시도로 최신 턴 저장 복구", int((profile.load_run().get("state", {}) as Dictionary).get("turn", -1)), _controller().turn())
		await _drain_results()
	storage.set("fail_writes", false)
	e2e.end()

func _rating_event_copies() -> void:
	# 앞의 9개 여정과 저장을 분리한다. 이후에는 합성 fixture의 실제 파일만 읽고 쓴다.
	if main != null and is_instance_valid(main):
		await e2e.unmount(main)
		main = null
	var original_storage := storage
	var source := _rating_source_content()
	var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tools/e2e/fixtures/rating-events.json"))
	var builder := RatingEventFixture.new()
	var save_dir := String(original_storage.get("_run_path")).get_base_dir()
	for entry in (catalog.get("events", []) as Array):
		var group: Dictionary = entry
		var event_id := String(group.get("id", ""))
		e2e.begin("rating-copy-%s-%s" % [event_id, locale], ["events", "localization", "save"])
		for row in (group.get("cases", []) as Array):
			var test_case: Dictionary = row
			var case_id := "%s-%s" % [event_id.replace(".", "-"), String(test_case.get("id", ""))]
			var fixture := builder.build(group, test_case, source)
			if not e2e.step("%s: 실제 컨트롤러로 pending 저장 생성" % case_id, bool(fixture.get("ok", false)), String(fixture.get("reason", ""))):
				continue
			storage = TestStorage.new(save_dir.path_join("rating-%s-run.json" % case_id), save_dir.path_join("rating-%s-meta.json" % case_id))
			profile.use_storage(storage)
			profile.set_language(locale)
			if not e2e.step("%s: 별도 파일에 fixture 저장" % case_id, profile.save_run(fixture["payload"])):
				continue
			_record_rating_fixture(case_id, event_id, test_case, fixture)
			await _mount()
			await _exercise_rating_copy(group, test_case, fixture, case_id)
			await e2e.unmount(main)
			main = null
		e2e.end()
	storage = original_storage
	profile.use_storage(original_storage)

func _exercise_rating_copy(group: Dictionary, test_case: Dictionary, fixture: Dictionary, case_id: String) -> void:
	if not await _tap("resume"):
		return
	var pending: Array = _controller().pending_events
	var event_id := String(group.get("id", ""))
	var actual_id := String((pending[0] as Dictionary).get("id", "")) if not pending.is_empty() else ""
	if not e2e.expect_equal("%s: 이어하기가 대상 이벤트를 먼저 표시" % case_id, actual_id, event_id):
		return
	var localized := SaLocalization.content({"events": [fixture["event"]]}, locale)
	var event: Dictionary = (localized["events"] as Array)[0]
	var choice_id := String(test_case.get("choice", ""))
	var choice := _rating_find(event.get("choices", []), choice_id)
	e2e.step("%s: 실제 이벤트 제목 표시" % case_id, _overlay_has_text(String(event.get("title", ""))))
	e2e.step("%s: 실제 이벤트 본문 표시" % case_id, _overlay_has_text(String(event.get("body", ""))))
	_rating_fragment(case_id + ": 본문 수정 문구", String(event.get("body", "")), group.get("bodyContains", {}))
	var button := _find("event-choice:" + choice_id) as BaseButton
	if not e2e.step("%s: 수정된 선택지를 실제로 누를 수 있음" % case_id, button != null and not button.disabled):
		return
	e2e.expect_equal("%s: 선택 문구 표시" % case_id, String(button.get("text")), String(choice.get("label", "")))
	_rating_fragment(case_id + ": 선택 수정 문구", String(button.get("text")), test_case.get("labelContains", {}))
	e2e.expect_equal("%s: 이벤트 직전 금화 fixture" % case_id, int(_controller().state.get("gold", -1)), int(fixture["eventGold"]))
	await _shot("11-rating-%s-before" % case_id)
	if not await _tap("event-choice:" + choice_id):
		return
	var outcome := _rating_find_kind(choice.get("outcomes", []), String(fixture["expectedKind"]))
	e2e.step("%s: 선택 결과를 실제 화면에 표시" % case_id, not outcome.is_empty() and _overlay_has_text(String(outcome.get("result_text", ""))))
	_rating_fragment(case_id + ": 결과 수정 문구", String(outcome.get("result_text", "")), test_case.get("resultContains", {}))
	e2e.expect_equal("%s: 실제 선택 결과 금화" % case_id, int(_controller().state.get("gold", -1)), int(fixture["expectedGold"]))
	e2e.expect_equal("%s: 실제 선택 결과 턴" % case_id, _controller().turn(), int(fixture["expectedTurn"]))
	for stat in (fixture["expectedStats"] as Dictionary):
		e2e.expect_equal("%s: 선택 결과 %s" % [case_id, stat], int((_controller().state.get("stats", {}) as Dictionary).get(stat, -1)), int(fixture["expectedStats"][stat]))
	if event_id == "opp.wager-table" and choice_id == "a":
		var fee := 200 if String(test_case.get("outcome", "")) == "success" else 0
		e2e.expect_equal("%s: 참가비 없이 성공 사례금만 반영" % case_id, int(_controller().state.get("gold", -1)), int(fixture["eventGold"]) + fee)
	e2e.expect_equal("%s: 선택 결과가 파일에 저장됨" % case_id, int((profile.load_run().get("state", {}) as Dictionary).get("gold", -1)), int(fixture["expectedGold"]))
	await _shot("11-rating-%s-after" % case_id)
	if not await _tap("continue"):
		return
	await _drain_results()
	e2e.step("%s: 결과 확인 뒤 행동 화면으로 복귀" % case_id, not _all_with_prefix(main, "action-card:").is_empty())

func _record_rating_fixture(case_id: String, event_id: String, test_case: Dictionary, fixture: Dictionary) -> void:
	var folder := out.path_join("fixture-inputs")
	DirAccess.make_dir_recursive_absolute(folder)
	var path := folder.path_join(case_id + ".json")
	var file := FileAccess.open(path, FileAccess.WRITE)
	if not e2e.step("%s: 합성 입력 fixture 근거 파일 열기" % case_id, file != null):
		return
	file.store_string(FileAccess.get_file_as_string(String(storage.get("_run_path"))))
	file.flush()
	var write_error := file.get_error()
	file.close()
	e2e.step("%s: 합성 입력 fixture 근거 저장" % case_id, write_error == OK)
	_rating_fixture_records.append({"id": case_id, "sourceSha": OS.get_environment("GITHUB_SHA"),
		"locale": locale, "eventId": event_id, "choiceId": test_case.get("choice", ""),
		"expectedOutcome": fixture["expectedKind"], "seed": fixture["seed"], "seedAttempts": fixture["attempts"],
		"eventGold": fixture["eventGold"], "input": "fixture-inputs/" + case_id + ".json", "sha256": FileAccess.get_sha256(path)})

func _rating_source_content() -> Dictionary:
	var source := {}
	for key in ["actions", "events", "endings", "npcs"]:
		var parsed: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/%s.json" % key))
		source[key] = parsed.get(key, [])
	return source

func _rating_find(rows: Array, id: String) -> Dictionary:
	for row in rows:
		if String((row as Dictionary).get("id", "")) == id:
			return row as Dictionary
	return {}

func _rating_find_kind(rows: Array, kind: String) -> Dictionary:
	for row in rows:
		if String((row as Dictionary).get("kind", "")) == kind:
			return row as Dictionary
	return {}

func _rating_fragment(name: String, actual: String, markers: Dictionary) -> void:
	if markers.has(locale):
		e2e.step(name, actual.contains(String(markers[locale])), actual)

func _overlay_has_text(expected: String) -> bool:
	var overlay: Control = main.get("_overlay")
	return not expected.is_empty() and is_instance_valid(overlay) and _node_has_text(overlay, expected)

func _node_has_text(node: Node, expected: String) -> bool:
	if node.is_queued_for_deletion():
		return false
	if node is Control and node.is_visible_in_tree() and (node is Label or node is Button) and String(node.get("text")) == expected:
		return true
	for child in node.get_children():
		if _node_has_text(child, expected):
			return true
	return false

func _play_one() -> bool:
	var cards := _all_with_prefix(main, "action-card:")
	if not e2e.step("고를 행동 카드가 있음", not cards.is_empty()):
		return false
	var card := cards[0] as Control
	var state := _controller().state
	var wanted := "rest.home" if int(state.get("energy", 0)) < 40 or int(state.get("stress", 0)) > 40 else ("work.chores" if int(state.get("gold", 0)) < 80 else "")
	for candidate in cards:
		if String(candidate.get_meta("action_id", "")) == wanted:
			card = candidate
			break
	var turn_before := _controller().turn()
	if not e2e.step("행동 카드 좌표 입력", await e2e.tap(card), String(card.get_meta("e2e_id", ""))):
		return false
	var result: Dictionary = _controller().last_result
	e2e.expect_equal("행동은 한 턴 진행", _controller().turn(), turn_before + 1)
	if int(result.get("played_turn", 0)) % 3 == 0:
		month_count += 1
	if bool(result.get("tuition_charged", false)):
		tuition_count += 1
		if not _settlement_shot:
			await _shot("05-month-end")
			_settlement_shot = true
	await _drain_results()
	return true

func _drain_results() -> void:
	for i in 24:
		var overlay: Control = main.get("_overlay")
		if overlay == null or not is_instance_valid(overlay):
			return
		_check_locale("결과 또는 이벤트")
		var choices := _all_with_prefix(overlay, "event-choice:")
		var available: Array = choices.filter(func(b): return b is BaseButton and not b.disabled)
		if not available.is_empty():
			event_count += 1
			if not _event_shot:
				await _shot("06-event")
				_event_shot = true
			e2e.step("이벤트 선택 좌표 입력", await e2e.tap(available[0]))
			continue
		var next := _find("continue")
		if next != null:
			e2e.step("결과 확인 좌표 입력", await e2e.tap(next))
			continue
		e2e.step("화면에 진행 가능한 선택이 있음", false, "overlay without enabled choice or continue")
		return
	e2e.step("모든 이벤트 결과가 닫힘", false, "24 overlay steps exceeded")

func _tap(id: String) -> bool:
	var control := _find(id)
	return e2e.step("화면 입력 %s" % id, await e2e.tap(control), "missing or unavailable" if control == null else "")

func _find(id: String) -> Control:
	var found := _all_with_prefix(main, id, true)
	return found[0] as Control if not found.is_empty() else null

func _all_with_prefix(node: Node, id: String, exact := false) -> Array:
	var found: Array = []
	if node == null or not is_instance_valid(node) or node.is_queued_for_deletion():
		return found
	if node is Control and node.is_visible_in_tree():
		var value := String(node.get_meta("e2e_id", ""))
		if (value == id if exact else value.begins_with(id)):
			found.append(node)
	for child in node.get_children():
		found.append_array(_all_with_prefix(child, id, exact))
	return found

func _controller() -> SaRunController:
	return main.get("_run") as SaRunController

func _shot(name: String) -> void:
	_check_locale(name)
	await e2e.shot(name)

func _check_visible_fonts(context: String) -> void:
	var faults: Array[String] = []
	var ui := root.get_node("Ui")
	var expected: Font = (ui.get("theme") as Theme).default_font
	_find_font_faults(main, expected, faults)
	e2e.step("실제 화면의 번들 폰트와 한글 글리프 %s" % context, faults.is_empty(), str(faults))

func _find_font_faults(node: Node, expected: Font, faults: Array[String]) -> void:
	if node == null or node.is_queued_for_deletion():
		return
	if node is Control and node.is_visible_in_tree() and (node is Label or node is Button):
		var control := node as Control
		var font := control.get_theme_font("font")
		if font == null or font != expected:
			faults.append("%s: bundled font is not effective" % node.name)
		else:
			var text := String(node.get("text"))
			for index in text.length():
				var codepoint := text.unicode_at(index)
				if codepoint >= 0xAC00 and codepoint <= 0xD7A3 and not font.has_char(codepoint):
					faults.append("%s: missing Hangul U+%04X" % [node.name, codepoint])
	for child in node.get_children():
		_find_font_faults(child, expected, faults)

func _check_locale(context: String) -> void:
	if locale != "en" or main == null:
		return
	var pattern := RegEx.new()
	pattern.compile("[가-힣]")
	var untranslated: Array[String] = []
	_find_korean(main, pattern, untranslated)
	e2e.step("영어 화면 번역 %s" % context, untranslated.is_empty(), str(untranslated))

func _find_korean(node: Node, pattern: RegEx, found: Array[String]) -> void:
	if node.is_queued_for_deletion():
		return
	if node is Control and node.is_visible_in_tree() and (node is Label or node is Button):
		var text := String(node.get("text"))
		if String(node.get_meta("e2e_id", "")) != "language" and pattern.search(text) != null:
			found.append(text.substr(0, 90))
	for child in node.get_children():
		_find_korean(child, pattern, found)
