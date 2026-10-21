extends SceneTree
## 실제 시작 화면에 좌표 입력을 넣어 레이아웃과 가로 스크롤을 확인한다.
const Driver := preload("res://tools/e2e/e2e_driver.gd")
var e2e: RefCounted

func _initialize() -> void:
	var base := _isolated_output().get_base_dir()
	DirAccess.make_dir_recursive_absolute(base)
	root.get_node(^"Profile").use_storage(SaFileStorage.new(base.path_join("layout-run.json"), base.path_join("layout-meta.json")))
	call_deferred("_run")

func _run() -> void:
	e2e = Driver.new(self, Vector2i(720, 1280), _isolated_output(), false)
	e2e.begin("turn-layout", ["core-loop", "card-scroll"])
	var main: Control = load("res://scenes/main.tscn").instantiate()
	await e2e.mount(main)
	e2e.step("실제 시작 버튼 좌표 입력", await e2e.tap(_find(main, "start")))
	await e2e.frames(3)
	var turn: Control = main.get("_turn_screen")
	e2e.step("턴 화면이 생성됨", is_instance_valid(turn))
	if is_instance_valid(turn):
		e2e.step("루트가 viewport를 채움", main.size == Vector2(720, 1280), str(main.size))
		e2e.step("턴 화면이 부모를 채움", turn.size.x >= main.size.x * 0.95 and turn.size.y >= main.size.y * 0.95, str(turn.size))
		var scroll := main.find_child("ActionScroll", true, false) as ScrollContainer
		e2e.step("가로 목록이 존재함", scroll != null)
		if scroll != null:
			var view := scroll.get_global_rect()
			var pos := view.position + Vector2(view.size.x * 0.7, 20)
			for card in scroll.get_child(0).get_children():
				if card is Control and view.encloses(card.get_global_rect()):
					pos = Vector2(card.get_global_rect().get_center().x, card.get_global_rect().position.y + 16)
			await e2e.drag(pos, pos - Vector2(270, 0), 12, 0.25)
			e2e.step("카드에서 시작한 드래그가 목록을 이동함", scroll.scroll_horizontal > 0, str(scroll.scroll_horizontal))
		var small: Array[String] = []
		_check_touch(turn, small)
		e2e.step("주요 터치 영역 높이 88 이상", small.is_empty(), str(small))
	e2e.end()
	await e2e.unmount(main)
	var audio := root.get_node_or_null(^"Audio")
	if audio != null:
		audio.release()
	quit(e2e.finish())

func _isolated_output() -> String:
	var base := OS.get_environment("STARLIT_SAVE_DIR")
	if base.is_empty():
		base = "user://e2e/layout-%d" % OS.get_process_id()
	return base.path_join("layout")

func _find(node: Node, id: String) -> Control:
	if node is Control and String(node.get_meta("e2e_id", "")) == id:
		return node as Control
	for child in node.get_children():
		var found := _find(child, id)
		if found != null:
			return found
	return null

func _check_touch(node: Node, out: Array[String]) -> void:
	for child in node.get_children():
		if child is BaseButton:
			var button := child as BaseButton
			var id := String(button.get_meta("e2e_id", ""))
			if button.is_visible_in_tree() and not button.disabled and not id.begins_with("together:") and button.size.y > 0.0 and button.size.y < 88.0:
				out.append("%s(%.0f)" % [button.name, button.size.y])
		_check_touch(child, out)
