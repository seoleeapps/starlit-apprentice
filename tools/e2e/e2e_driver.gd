extends RefCounted

# Godot headless E2E 여정 도우미. 게임 저장소의 tools/e2e/로 복사해 preload해서 쓴다.
#   const E2EDriver := preload("res://tools/e2e/e2e_driver.gd")
# 입력은 SubViewport.push_input으로 화면 좌표에 넣는다. headless에서 목록 드래그 스크롤이 실제 기기처럼
# 동작하도록 Input.emulate_touch_from_mouse를 켠다(꺼져 있으면 ScrollContainer가 드래그로 움직이지 않는다).
# 화면 저장(shot)은 렌더링 모드에서만 한다. headless에서 RenderingServer.frame_post_draw를 기다리면 멈춘다.

var tree: SceneTree
var viewport: SubViewport
var out_dir := ""
var capture := false
var scenarios: Array = []
var _current: Dictionary = {}
var _evidence_ok := true


func _init(p_tree: SceneTree, view_size: Vector2i, p_out_dir: String, p_capture: bool) -> void:
	tree = p_tree
	out_dir = p_out_dir
	capture = p_capture and DisplayServer.get_name() != "headless"
	Input.emulate_touch_from_mouse = true
	DirAccess.make_dir_recursive_absolute(out_dir)
	viewport = SubViewport.new()
	viewport.size = view_size
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	tree.root.add_child(viewport)
	_write_report()


# 실제 시작 장면을 viewport 안에 띄운다. 대체 구현 주입은 호출하는 쪽이 장면을 넣기 전에 한다.
func mount(node: Node) -> Node:
	viewport.add_child(node)
	await frames(3)
	return node


func unmount(node: Node) -> void:
	node.queue_free()
	await frames(2)


func begin(id: String, feature_ids: Array) -> void:
	_fail_unfinished()
	_current = {"id": id, "featureIds": feature_ids, "steps": [], "screenshots": []}
	_write_report()


func step(name: String, ok: bool, detail := "") -> bool:
	return _record_step(name, ok, detail)


# JSON으로 표현할 수 있는 테스트 값만 받는다. 실제 계정·사용자 저장 전체를 수집하지 않는다.
func expect_equal(name: String, actual: Variant, expected: Variant) -> bool:
	var ok: bool = actual == expected
	var detail := "" if ok else "expected=%s, actual=%s" % [str(expected), str(actual)]
	return _record_step(name, ok, detail, {"expected": expected, "actual": actual})


func _record_step(name: String, ok: bool, detail: String, values := {}) -> bool:
	var entry := {"name": name, "ok": ok, "detail": detail}
	entry.merge(values.duplicate(true))
	_current.steps.append(entry)
	_write_report()
	if not ok:
		push_error("E2E step failed: %s / %s %s" % [_current.id, name, detail])
	return ok


func end() -> void:
	var passed: bool = not _current.steps.is_empty() and _current.steps.all(func(s): return s.ok)
	_current["status"] = "passed" if passed else "failed"
	scenarios.append(_current)
	_current = {}
	# finish() 전의 파일은 진행 중으로 남긴다. 다음 시나리오 전 중단도 통과가 아니다.


func frames(count := 2) -> void:
	for i in count:
		await tree.process_frame


# 조건이 참이 될 때까지 프레임을 넘긴다. 시간 제한을 넘기면 false.
func wait_for(predicate: Callable, max_frames := 300) -> bool:
	for i in max_frames:
		if predicate.call():
			return true
		await tree.process_frame
	return predicate.call()


# 화면에 보이고 입력을 받는 컨트롤의 중심을 누르고 뗀다. 숨김·비활성 컨트롤은 실패로 남긴다.
# 스크롤 목록 안에서 가려져 있으면 사람처럼 목록을 끌어 보이게 한 뒤 누른다.
func tap(control: Control) -> bool:
	if control == null or not control.is_visible_in_tree():
		return false
	if control is BaseButton and (control as BaseButton).disabled:
		return false
	if not await scroll_into_view(control):
		return false
	var pos := control.get_global_rect().get_center()
	_push_button(pos, true)
	await frames()
	_push_button(pos, false)
	await frames()
	return true


# 손가락으로 끄는 동작. 목록·카드 위에서 시작해도 실제 기기처럼 스크롤되는지 확인한다.
# hold(초)만큼 멈췄다 떼면 관성 없이 그 자리에 멈춘다. 0이면 놓는 순간의 속도로 미끄러진다(렌더링 모드에서 특히 크다).
func drag(from: Vector2, to: Vector2, steps := 10, hold := 0.0) -> void:
	_push_button(from, true)
	await frames()
	var previous := from
	for i in range(1, steps + 1):
		var point := from.lerp(to, float(i) / steps)
		var motion := InputEventMouseMotion.new()
		motion.button_mask = MOUSE_BUTTON_MASK_LEFT
		motion.position = point
		motion.global_position = point
		motion.relative = point - previous
		viewport.push_input(motion)
		previous = point
		await frames(1)
	if hold > 0.0:
		await tree.create_timer(hold).timeout
	_push_button(to, false)
	await frames()


# 컨트롤이 가장 가까운 ScrollContainer 안에서 보일 때까지 가려진 축(가로·세로)으로 목록을 끌어 움직인다.
# 목록보다 큰 축은 중심이 보이면 된다. 끌어도 움직이지 않으면(끝에 닿음·드래그 미수신) 바로 false.
func scroll_into_view(control: Control, max_drags := 30) -> bool:
	var scroll := _scroll_parent(control)
	if scroll == null:
		return true
	for i in max_drags:
		var view := scroll.get_global_rect()
		var rect := control.get_global_rect()
		var move := Vector2(_axis_move(view.position.x, view.size.x, rect.position.x, rect.size.x),
			_axis_move(view.position.y, view.size.y, rect.position.y, rect.size.y))
		if move == Vector2.ZERO:
			return true
		var before := Vector2(scroll.scroll_horizontal, scroll.scroll_vertical)
		var center := view.get_center()
		await drag(center, center - move, 10, 0.25)
		await _settle(scroll)
		if Vector2(scroll.scroll_horizontal, scroll.scroll_vertical) == before:
			return false
	var view_end := scroll.get_global_rect()
	var rect_end := control.get_global_rect()
	return _axis_move(view_end.position.x, view_end.size.x, rect_end.position.x, rect_end.size.x) == 0.0 \
		and _axis_move(view_end.position.y, view_end.size.y, rect_end.position.y, rect_end.size.y) == 0.0


# 렌더링 모드에서만 장면을 PNG로 남긴다. headless에서는 아무것도 하지 않는다.
func shot(name: String) -> void:
	if not capture:
		return
	await RenderingServer.frame_post_draw
	var path := out_dir.path_join("%s.png" % name)
	viewport.get_texture().get_image().save_png(path)
	_current.screenshots.append(path.get_file())


# 종료하지 않은 시나리오와 결과 저장 실패도 통과시키지 않는다.
func finish(meta := {}) -> int:
	_fail_unfinished()
	_write_report(meta)
	var failed := scenarios.filter(func(s): return s.status != "passed")
	return 1 if not _evidence_ok or scenarios.is_empty() or not failed.is_empty() else 0


func _fail_unfinished() -> void:
	if _current.is_empty():
		return
	step("scenario closed", false, "end() was not called")
	end()


# 시작·단계마다 덮어써 이전 실행의 통과를 재사용하지 않고 중단 위치를 보존한다.
func _write_report(meta := {}) -> void:
	var recorded := scenarios.duplicate(true)
	if not _current.is_empty():
		var pending := _current.duplicate(true)
		pending["status"] = "failed" if pending.steps.any(func(s): return not s.ok) else "running"
		recorded.append(pending)
	var report := {
		"schemaVersion": 1,
		"mode": "rendered" if capture else "headless",
		"godotVersion": Engine.get_version_info().string,
		"viewport": [viewport.size.x, viewport.size.y],
		"scenarios": recorded,
	}
	report.merge(meta)
	var file := FileAccess.open(out_dir.path_join("journey.json"), FileAccess.WRITE)
	if file == null:
		_evidence_ok = false
		push_error("E2E report could not be opened: %s" % error_string(FileAccess.get_open_error()))
		return
	file.store_string(JSON.stringify(report, "  "))
	file.flush()
	var write_error := file.get_error()
	file.close()
	if write_error != OK:
		_evidence_ok = false
		push_error("E2E report could not be saved: %s" % error_string(write_error))


# 한 축에서 더 끌어야 할 거리(0이면 보임). 멈췄다 놓아 관성이 없으므로 한 번에 목록 크기의 80%까지 움직인다.
func _axis_move(view_start: float, view_size: float, start: float, size: float) -> float:
	var center := start + size / 2.0
	var hidden: bool
	if size <= view_size:
		hidden = start < view_start or start + size > view_start + view_size
	else:
		# 끝 경계는 입력 영역에 들지 않는다(Rect2.has_point). 중심이 끝 경계에 있으면 아직 가려진 것으로 본다.
		hidden = center < view_start or center >= view_start + view_size
	if not hidden:
		return 0.0
	var offset := center - (view_start + view_size / 2.0)
	if absf(offset) < 1.0:
		offset = 1.0 if offset >= 0.0 else -1.0
	return clampf(offset, -view_size * 0.8, view_size * 0.8)


func _scroll_parent(control: Control) -> ScrollContainer:
	var node := control.get_parent()
	while node != null and not node is ScrollContainer:
		node = node.get_parent()
	return node as ScrollContainer


func _settle(scroll: ScrollContainer, max_frames := 120) -> void:
	var previous := Vector2i(-1, -1)
	for i in max_frames:
		var now := Vector2i(scroll.scroll_horizontal, scroll.scroll_vertical)
		if now == previous:
			return
		previous = now
		await frames(2)


func _push_button(pos: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	event.pressed = pressed
	event.position = pos
	event.global_position = pos
	viewport.push_input(event)
