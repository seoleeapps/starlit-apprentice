extends RefCounted
## OS 복귀와 네이티브 연령 SDK 응답만 대체하고 게임 접근은 실제 좌표 입력으로 확인한다.
const FakeAge := preload("res://tools/e2e/fakes/age_signals.gd")
const TestStorage := preload("res://tools/e2e/fakes/storage.gd")
var ctx
var _original_storage: SaFileStorage
var _meta_seed: Dictionary
var _pending_fixture: Dictionary
var _save_dir := ""
var _case_number := 0

func run(journey) -> void:
	ctx = journey
	_original_storage = ctx.storage
	_meta_seed = ctx.profile.meta().duplicate(true)
	_meta_seed["age_band"] = "13-15"
	_meta_seed["language"] = ctx.locale
	_meta_seed.erase("ad_state")
	_save_dir = String(_original_storage.get("_run_path")).get_base_dir()
	var source: Dictionary = ctx._rating_source_content()
	var controller := SaRunController.new()
	controller.start(4242, source, 0)
	controller.resolve(ctx._rating_find(source["actions"], "work.chores"), "")
	_pending_fixture = controller.to_save().duplicate(true)
	await _shared_allowed()
	await _unshared_fallback()
	await _restricted_preserves()
	await _pending_timeout()
	await _stale_duplicate_and_retry()
	await _lifecycle_and_release()
	await _unmount()
	ctx.storage = _original_storage
	ctx.profile.use_storage(_original_storage)

func _fake(value: String, lower: int = -1, upper: int = -1, automatic: bool = true) -> FakeAge:
	var adapter := FakeAge.new()
	adapter.supported = value != "unsupported"
	adapter.status = value
	adapter.age_lower = lower
	adapter.age_upper = upper
	adapter.auto_complete = automatic
	return adapter

func _prepare(adapter: FakeAge, pending: bool = true) -> void:
	await _unmount()
	_case_number += 1
	var suffix := "%s-%d" % [ctx.locale, _case_number]
	ctx.storage = TestStorage.new(_save_dir.path_join("age-%s-run.json" % suffix), _save_dir.path_join("age-%s-meta.json" % suffix))
	ctx.profile.use_storage(ctx.storage)
	ctx.e2e.step("연령 보호용 격리 메타 파일 준비", ctx.storage.write_meta(_meta_seed.duplicate(true)))
	if pending:
		ctx.e2e.step("실제 컨트롤러가 생성한 pending 저장 fixture", not (_pending_fixture.get("pending_events", []) as Array).is_empty())
		ctx.e2e.step("연령 보호용 pending 저장 파일 준비", ctx.profile.save_run(_pending_fixture.duplicate(true)))
	await ctx._mount(adapter)
	ctx.e2e.expect_equal("시작 시 네이티브 연령 조회는 한 번", int(adapter.request_calls), 1)

func _unmount() -> void:
	if ctx.main != null and is_instance_valid(ctx.main):
		await ctx.e2e.unmount(ctx.main)
		ctx.main = null

func _begin(name: String, extra: Array = []) -> void:
	var features: Array = ["age-protection", "save", "ads"]
	for feature in extra:
		if not features.has(feature):
			features.append(feature)
	ctx.e2e.begin("age-%s-%s" % [name, ctx.locale], features)

func _files() -> Dictionary:
	var state := {}
	for key in ["_run_path", "_meta_path"]:
		var path := String(ctx.storage.get(key))
		for suffix in ["", ".bak", ".tmp"]:
			var file: String = path + String(suffix)
			state[key + suffix] = {"exists": FileAccess.file_exists(file), "sha256": FileAccess.get_sha256(file) if FileAccess.file_exists(file) else ""}
	return state

func _ad_trace() -> Dictionary:
	return {"manualAge": ctx.ad.age, "prepare": ctx.ad.prepare_calls, "show": ctx.ad.show_calls,
		"privacy": ctx.ad.privacy_calls, "trace": ctx.ad.trace.duplicate(true)}

func _boundary_snapshot() -> Dictionary:
	return {"files": _files(), "ads": _ad_trace()}

func _unchanged(name: String, before: Dictionary) -> void:
	ctx.e2e.expect_equal(name + ": 런/메타/백업 바이트 보존", _files(), before["files"])
	ctx.e2e.expect_equal(name + ": Play 응답이 광고 입력과 호출에 섞이지 않음", _ad_trace(), before["ads"])
	ctx.e2e.expect_equal(name + ": 수동 연령대를 덮어쓰지 않음", ctx.profile.age_band(), "13-15")

func _restricted(name: String, title_only: bool = true) -> void:
	ctx.e2e.step(name + ": 연령 재확인 안내", ctx._find("age-access:retry") != null)
	ctx.e2e.step(name + ": 보호 안내 닫기", ctx._find("age-access:close") != null)
	_visible_locale(name)
	ctx.e2e.step(name + ": 실제 접근 판단 차단", not ctx.main.age_access.can_play())
	ctx.e2e.step(name + ": 보호 사유 메모리 유지", not String(ctx.main.age_access.block_reason).is_empty())
	if title_only:
		ctx.e2e.step(name + ": 행동 화면 진입 차단", ctx._all_with_prefix(ctx.main, "action-card:").is_empty())

func _visible_locale(name: String) -> void:
	if String(ctx.main.get("_locale")) == "en":
		var pattern := RegEx.new()
		pattern.compile("[가-힣]")
		var untranslated: Array[String] = []
		ctx._find_korean(ctx.main, pattern, untranslated)
		ctx.e2e.step(name + ": 실제 영어 보호 화면 번역", untranslated.is_empty(), str(untranslated))

func _shared_allowed() -> void:
	_begin("shared-allowed", ["core-loop"])
	for band in [[13, 15], [16, 17], [18, -1]]:
		var adapter := _fake("shared", int(band[0]), int(band[1]))
		await _prepare(adapter)
		ctx.e2e.step("공유된 13세 이상은 보호 안내 없음", ctx._find("age-access:retry") == null)
		ctx.e2e.expect_equal("공유 연령은 수동 연령과 분리", String(ctx.ad.age), "13-15")
		var before := _boundary_snapshot()
		# 같은 완료 ID의 중복 응답은 이미 소비된 응답이다.
		adapter.respond(0, "shared", 10, 12)
		await ctx.e2e.frames(3)
		_unchanged("허용 완료 뒤 중복", before)
		ctx.e2e.step("중복 응답이 접근 결정을 되돌리지 않음", ctx._find("age-access:retry") == null)
		await ctx._shot("12-age-shared-%d" % int(band[0]))
		await ctx._tap("start")
		ctx.e2e.expect_equal("허용 상태의 실제 새 게임 시작", ctx._controller().turn(), 1)
		ctx.e2e.step("허용 상태의 실제 행동 카드", not ctx._all_with_prefix(ctx.main, "action-card:").is_empty())
	ctx.e2e.end()

func _unshared_fallback() -> void:
	_begin("unshared-fallback", ["core-loop"])
	for value in ["not_shared", "unknown", "offline", "unavailable", "error", "unsupported"]:
		var adapter := _fake(value)
		await _prepare(adapter)
		ctx.e2e.expect_equal("%s: 네이티브 상태를 구분해 메모리에 유지" % value, String(ctx.main.age_access.status), value)
		ctx.e2e.step("%s: 미공유/일시 실패는 기존 게임 허용" % value, ctx._find("age-access:retry") == null)
		var before := _boundary_snapshot()
		adapter.respond(0, "approval_denied", 10, 12)
		await ctx.e2e.frames(3)
		_unchanged(value + " 뒤 중복", before)
		await ctx._shot("12-age-fallback-%s" % value)
		await ctx._tap("resume")
		ctx.e2e.step("%s: 실제 이어하기로 pending 이벤트 표시" % value, not ctx._all_with_prefix(ctx.main, "event-choice:").is_empty())
		ctx.e2e.expect_equal("%s: 원래 저장의 턴 복원" % value, ctx._controller().turn(), int((_pending_fixture["state"] as Dictionary)["turn"]))
	ctx.e2e.end()

func _restricted_preserves() -> void:
	_begin("restricted-preserves", ["localization", "settings", "events"])
	for value in ["shared", "approval_pending", "approval_denied"]:
		var adapter := _fake(value, 10, 12)
		await _prepare(adapter)
		var before := _boundary_snapshot()
		# 시작 때의 보호 안내가 열려 있으면 닫고 실제 시작 버튼으로 다시 검사한다.
		if ctx._find("age-access:close") != null:
			await ctx._tap("age-access:close")
		await ctx._tap("start")
		_restricted(value + " 새 게임")
		_unchanged(value + " 새 게임 차단", before)
		await ctx._shot("12-age-blocked-%s" % value)
		await ctx._tap("age-access:close")
		await ctx._tap("resume")
		_restricted(value + " 이어하기")
		_unchanged(value + " 이어하기 차단", before)
		await ctx._tap("age-access:close")
		await ctx._tap("language")
		var changed := _files()
		ctx.e2e.expect_equal("보호 안내 밖 언어 변경 반영", ctx.profile.language(), "en" if ctx.locale == "ko" else "ko")
		await ctx._tap("resume")
		_restricted(value + " 언어 변경")
		ctx.e2e.expect_equal("언어 변경 뒤 제한 안내가 저장을 바꾸지 않음", _files(), changed)
		await ctx.e2e.shot("12-age-blocked-%s-other-language" % value)
		await ctx._tap("age-access:close")
		await ctx._tap("language")
		ctx.e2e.expect_equal("원래 표시 언어로 복귀", ctx.profile.language(), ctx.locale)
	ctx.e2e.end()

func _pending_timeout() -> void:
	_begin("pending-timeout", ["core-loop"])
	var adapter := _fake("shared", 18, -1, false)
	await _prepare(adapter)
	var before := _boundary_snapshot()
	await ctx._tap("start")
	ctx.e2e.step("연령 응답 대기 중 새 게임을 열지 않음", ctx._all_with_prefix(ctx.main, "action-card:").is_empty())
	ctx.e2e.step("실제 비동기 확인중 안내 표시", ctx._find("age-access:checking") != null)
	ctx.e2e.expect_equal("대기 화면 클릭이 중복 SDK 조회를 만들지 않음", int(adapter.request_calls), 1)
	await ctx._shot("12-age-checking")
	# 제품의 실제 5초 비동기 상한을 기다린다. 게임/화면 콜백은 직접 호출하지 않는다.
	await ctx.create_timer(5.25).timeout
	ctx.e2e.step("5초 실패 뒤 기존 게임 진행 가능", ctx._find("age-access:retry") == null)
	ctx.e2e.expect_equal("시간 초과가 SDK를 자동 반복하지 않음", int(adapter.request_calls), 1)
	ctx.e2e.step("5초 시간 초과 상태 구분", String(ctx.main.age_access.status) in ["unavailable", "error"])
	var timed_out := _boundary_snapshot()
	# 시간 초과 뒤의 늦은 결과는 이미 끝난 조회에 속한다.
	adapter.respond(0, "approval_denied", 10, 12)
	await ctx.e2e.frames(3)
	ctx.e2e.step("시간 초과 뒤 늦은 응답 무시", ctx._find("age-access:retry") == null)
	_unchanged("시간 초과 뒤 늦은 응답", timed_out)
	# 대기 중 시작 의도를 이어 실행했는지는 제품 UX에 따라 확인한다.
	if ctx._find("start") != null:
		_unchanged("시간 초과가 저장을 수정하지 않음", before)
		await ctx._tap("start")
	ctx.e2e.expect_equal("시간 초과 뒤 실제 새 게임 진입", ctx._controller().turn(), 1)
	ctx.e2e.end()

func _stale_duplicate_and_retry() -> void:
	_begin("retry-and-stale", ["core-loop", "events"])
	var adapter := _fake("shared", 10, 12)
	await _prepare(adapter)
	var before := _boundary_snapshot()
	if ctx._find("age-access:retry") == null:
		await ctx._tap("start")
	adapter.auto_complete = false
	ctx.clock.advance(31)
	await ctx._tap("age-access:retry")
	ctx.e2e.expect_equal("명시적 재확인은 SDK 조회 한 번", int(adapter.request_calls), 2)
	for i in 3:
		# 실제 OS 복귀 경계의 중복 알림만 주입한다.
		ctx.main.refresh_age_access()
	await ctx.e2e.frames(3)
	ctx.e2e.expect_equal("조회 중 OS 복귀 알림은 중복 요청 없음", int(adapter.request_calls), 2)
	adapter.respond(0, "shared", 18, -1)
	await ctx.e2e.frames(3)
	ctx.e2e.step("이전 ID의 늦은 허용은 대기를 해제하지 않음", ctx._all_with_prefix(ctx.main, "action-card:").is_empty())
	adapter.respond(1, "error")
	await ctx.e2e.frames(3)
	_restricted("재확인 실패가 이미 확인된 보호를 우회하지 않음")
	ctx.e2e.expect_equal("보호 이후 API 실패 상태도 구분", String(ctx.main.age_access.status), "error")
	ctx.clock.advance(31)
	await ctx._tap("age-access:retry")
	ctx.e2e.expect_equal("거절 검증 재확인은 새 조회 한 번", int(adapter.request_calls), 3)
	adapter.respond(2, "approval_denied", 10, 12)
	await ctx.e2e.frames(3)
	_restricted("현재 ID 거절")
	adapter.respond(2, "shared", 18, -1)
	await ctx.e2e.frames(3)
	_restricted("동일 ID 중복 허용 무시")
	_unchanged("재확인/늦은/중복 SDK 응답", before)
	ctx.clock.advance(31)
	await ctx._tap("age-access:retry")
	ctx.e2e.expect_equal("다음 명시적 재확인은 새 조회 한 번", int(adapter.request_calls), 4)
	adapter.respond(3, "shared", 16, 17)
	await ctx.e2e.frames(3)
	ctx.e2e.step("현재 새 ID의 허용만 보호 안내를 해제", ctx._find("age-access:retry") == null)
	_unchanged("허용 복구 응답", before)
	if ctx._find("resume") != null:
		await ctx._tap("resume")
	ctx.e2e.step("재확인 허용 뒤 원래 pending 이벤트 복구", not ctx._all_with_prefix(ctx.main, "event-choice:").is_empty())
	await ctx._shot("12-age-retry-restored")
	ctx.e2e.end()

func _lifecycle_and_release() -> void:
	_begin("lifecycle-and-release", ["core-loop", "events"])
	var adapter := _fake("shared", 18, -1)
	await _prepare(adapter)
	await ctx._tap("resume")
	ctx.e2e.step("복귀 전 pending 이벤트 화면", not ctx._all_with_prefix(ctx.main, "event-choice:").is_empty())
	var before := _boundary_snapshot()
	var run_before: Dictionary = ctx._controller().to_save().duplicate(true)
	adapter.auto_complete = false
	ctx.clock.advance(31)
	ctx.main.refresh_age_access()
	await ctx.e2e.frames(3)
	ctx.e2e.expect_equal("OS 재활성화에서 연령 다시 확인", int(adapter.request_calls), 2)
	ctx.e2e.step("OS 재활성화의 확인중 안내", ctx._find("age-access:checking") != null)
	var choices: Array = ctx._all_with_prefix(ctx.main, "event-choice:")
	if not choices.is_empty():
		# 화면의 실제 좌표로 원래 이벤트를 누르지만 위의 보호창이 입력을 받아야 한다.
		await ctx.e2e.tap(choices[0])
		ctx.e2e.expect_equal("확인중 화면이 원래 이벤트 입력을 막음", ctx._controller().to_save(), run_before)
	adapter.respond(1, "shared", 16, 17)
	await ctx.e2e.frames(3)
	ctx.e2e.step("OS 재확인 허용은 원래 이벤트 화면으로 복귀", not ctx._all_with_prefix(ctx.main, "event-choice:").is_empty() and ctx.main.age_access.can_play())
	_unchanged("OS 복귀 허용 응답", before)
	ctx.e2e.expect_equal("허용 복귀도 기존 RNG와 pending 그대로 유지", ctx._controller().to_save(), run_before)
	ctx.clock.advance(31)
	ctx.main.refresh_age_access()
	await ctx.e2e.frames(3)
	ctx.e2e.expect_equal("다음 OS 복귀에서 새 조회 한 번", int(adapter.request_calls), 3)
	adapter.respond(2, "shared", 10, 12)
	await ctx.e2e.frames(3)
	_restricted("OS 복귀 뒤 보호 필요", false)
	_unchanged("OS 복귀가 미확인 이벤트 저장을 보존", before)
	ctx.e2e.expect_equal("OS 복귀 보호가 인메모리 게임 상태를 바꾸지 않음", ctx._controller().to_save(), run_before)
	await ctx._shot("12-age-reactivated-blocked")
	await _unmount()
	ctx.e2e.expect_equal("장면 해제는 연령 SDK 연결 해제", int(adapter.release_calls), 1)
	adapter.respond(2, "shared", 18, -1)
	await ctx.e2e.frames(3)
	ctx.e2e.expect_equal("장면 해제 뒤 응답도 저장을 보존", _files(), before["files"])
	var fresh := _fake("shared", 13, 15)
	await ctx._mount(fresh)
	ctx.e2e.step("새 장면이 이전 native 요청 ID를 재사용하지 않음", not adapter.request_ids.has(fresh.request_ids[0]))
	adapter.respond(2, "approval_denied", 10, 12)
	await ctx.e2e.frames(3)
	ctx.e2e.step("이전 장면의 늦은 응답이 새 장면을 제한하지 않음", ctx.main.age_access.can_play())
	await ctx._tap("resume")
	ctx.e2e.expect_equal("새 장면에서 같은 저장의 턴 복구", ctx._controller().turn(), int((run_before["state"] as Dictionary)["turn"]))
	ctx.e2e.step("새 장면에서 같은 미확인 이벤트 복구", not ctx._all_with_prefix(ctx.main, "event-choice:").is_empty())
	await ctx._shot("12-age-reactivated-restored")
	ctx.e2e.end()
