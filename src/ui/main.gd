extends Control
## 화면 스택 루트.
##
## 화면은 .tscn 이 아니라 코드로 구성한다. .tscn 은 머지 충돌이 심하고,
## 이식 원본이 이미 명령형이라 화면당 .tscn 은 불필요한 번역 단계다.

const CONTENT := {
	"actions": "res://data/actions.json",
	"events": "res://data/events.json",
	"endings": "res://data/endings.json",
	"npcs": "res://data/npcs.json",
}

var _run := SaRunController.new()
var _content := {}
var _turn_screen: SaTurnScreen
var _overlay: Control
var clock: Callable = func() -> int: return int(Time.get_unix_time_from_system())
var seed_provider: Callable
var ad_service: SaInterstitialService
var age_adapter: SaAgeSignalsAdapter
var age_access: SaAgeAccess
var _age_overlay: Control
var _age_status_label: Label
var _age_retry_wrap: Control
var _age_notice_dismissed := false
var _services_ready := false
var _locale := "en"
var _last_save_ok := true
var _ending_recorded := false
var _boundary_turn := -1
var _input_locked := false

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = SaUiKit.BG_NIGHT
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	_content = _load_content()
	_locale = Profile.language()
	_content = SaLocalization.content(_content, _locale)
	if ad_service == null:
		var adapter := SaAdAdapter.new()
		if OS.get_name() == "Android":
			adapter = load("res://src/platform/android_admob_adapter.gd").new()
		ad_service = SaInterstitialService.new(adapter)
	ad_service.clock = clock
	ad_service.persist = Profile.save_ad_state
	ad_service.load_state(Profile.ad_state())
	ad_service.configure(Profile.age_band())
	if age_adapter == null:
		age_adapter = SaAndroidAgeSignalsAdapter.new() if OS.get_name() == "Android" else SaAgeSignalsAdapter.new()
	age_access = SaAgeAccess.new(age_adapter)
	age_access.changed.connect(_render_age_access)
	_show_title()
	_services_ready = true
	refresh_age_access()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_RESUMED and _services_ready:
		refresh_age_access()

func _process(delta: float) -> void:
	if age_access != null:
		age_access.advance(delta)

func refresh_age_access() -> void:
	if age_access != null:
		_age_notice_dismissed = false
		age_access.refresh()

func _load_content() -> Dictionary:
	var out := {}
	for key in CONTENT.keys():
		var path: String = CONTENT[key]
		if not FileAccess.file_exists(path):
			out[key] = []
			continue
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		var d: Dictionary = parsed as Dictionary if parsed is Dictionary else {}
		out[key] = d.get(key, [])
	return out

# ── 타이틀 ─────────────────────────────────────────────────────────
func _show_title() -> void:
	_clear()
	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_FULL_RECT)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 24)

	var title := SaUiKit.label(_tr("title"), SaUiKit.FONT_TITLE, SaUiKit.GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)

	var sub := SaUiKit.label(_tr("subtitle"), SaUiKit.FONT_BODY, SaUiKit.INK_DIM)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(sub)

	# 저장된 런이 있을 때만 이어하기를 연다. 빈 버튼을 눌러 아무 일도
	# 일어나지 않는 화면이 이어하기 없음보다 나쁘다.
	if Profile.has_saved_run():
		var resume := Button.new()
		resume.text = _tr("resume")
		_tag(resume, "resume")
		resume.custom_minimum_size = Vector2(280, SaUiKit.TOUCH_MIN)
		resume.add_theme_font_size_override("font_size", SaUiKit.FONT_HEAD)
		resume.pressed.connect(_continue_run)
		var resume_wrap := CenterContainer.new()
		resume_wrap.add_child(resume)
		col.add_child(resume_wrap)

	# SRC-001: 사운드 On/Off 는 사용자 설정 필수다.
	var sound := Button.new()
	sound.custom_minimum_size = Vector2(280, SaUiKit.TOUCH_MIN)
	sound.add_theme_font_size_override("font_size", SaUiKit.FONT_BODY)
	sound.text = _sound_label()
	_tag(sound, "sound")
	sound.pressed.connect(func():
		Audio.toggle_sound()
		sound.text = _sound_label())
	var sound_wrap := CenterContainer.new()
	sound_wrap.add_child(sound)

	var start := Button.new()
	start.text = _tr("start")
	_tag(start, "start")
	start.custom_minimum_size = Vector2(280, SaUiKit.TOUCH_MIN)
	start.add_theme_font_size_override("font_size", SaUiKit.FONT_HEAD)
	start.pressed.connect(_start_run)
	var wrap := CenterContainer.new()
	wrap.add_child(start)
	col.add_child(wrap)
	col.add_child(sound_wrap)
	col.add_child(_centered(_button(_tr("language") + ": " + ("한국어" if _locale == "ko" else "English"), "language", _change_language)))
	col.add_child(_centered(_button(_tr("age") + ": " + _age_label(Profile.age_band()), "age", _show_age)))
	col.add_child(_centered(_button(_tr("privacy"), "privacy", _privacy_options)))
	_age_status_label = SaUiKit.label("", SaUiKit.FONT_SMALL, SaUiKit.INK_DIM)
	_age_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_age_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_age_status_label)
	_age_retry_wrap = _centered(_button(_tr("age_access_retry"), "age-access:retry", refresh_age_access))
	col.add_child(_age_retry_wrap)
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.set_anchors_preset(Control.PRESET_TOP_LEFT)
	col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(col)
	add_child(scroll)
	Audio.play_bgm("bgm_main")
	_render_age_access()

func _sound_label() -> String:
	return _tr("sound_on") if Audio.sound_enabled else _tr("sound_off")

func _start_run() -> void:
	if not _age_permits_game():
		return
	# 코어는 Time 을 모른다. 시드는 여기서 만들어 주입한다.
	# 회차마다 다른 기회 덱을 연다. 덱 인덱스는 별빛 기록의 완주 회차에서
	# 유도하므로 앱을 껐다 켜도 0 으로 되돌아가지 않는다.
	_ending_recorded = false
	_boundary_turn = -1
	_run.start(int(seed_provider.call() if seed_provider.is_valid() else clock.call()) & 0x7FFFFFFF, _content, Profile.next_deck())
	_save_run()
	_show_turn()

func _continue_run() -> void:
	if not _age_permits_game():
		return
	if not _run.restore(Profile.load_run(), _content):
		# 저장이 깨졌으면 조용히 새 런으로 떨어지지 않는다. 타이틀로 돌려보내
		# 플레이어가 무엇을 시작하는지 알게 한다.
		_show_title()
		_show_message(_tr("save_corrupt"))
		return
	if not _run.pending_events.is_empty():
		_show_turn_base()
		_show_event()
	else:
		_show_turn()

func _save_run() -> bool:
	_last_save_ok = Profile.save_run(_run.to_save())
	return _last_save_ok

# ── 턴 ─────────────────────────────────────────────────────────────
func _show_turn() -> void:
	if _run.is_over():
		_show_ending()
		return
	_show_turn_base()

func _show_turn_base() -> void:
	Audio.play_bgm("bgm_main")
	_clear()
	_turn_screen = SaTurnScreen.new()
	_turn_screen.anchor_right = 1.0
	_turn_screen.anchor_bottom = 1.0
	add_child(_turn_screen)
	_turn_screen.setup(_run, _locale)
	_turn_screen.action_chosen.connect(_on_action)
	_turn_screen.portrait_tapped.connect(_show_constellation)
	var menu := _button(_tr("menu"), "menu", _show_title)
	menu.position = Vector2(16, size.y * SaUiKit.SCENE_RATIO - 104)
	menu.custom_minimum_size = Vector2(140, SaUiKit.TOUCH_MIN)
	add_child(menu)
	ad_service.activity()

func _on_action(action: Dictionary, together: String) -> void:
	if not _age_permits_game():
		return
	if _input_locked:
		return
	_input_locked = true
	Audio.play_sfx("sfx_confirm")
	var result := _run.resolve(action, together)
	_save_run()
	_show_resolution(action, result)

# ── 해석 비트: 화면 전환 없이 장면 위에 겹친다 ──────────────────────
func _show_resolution(action: Dictionary, result: Dictionary) -> void:
	var col := _panel_overlay()

	var outcome := String(result.get("outcome", ""))
	var head: String = SaLocalization.text("ui.outcome_" + outcome, _locale)
	var color: Color = SaUiKit.ROSE if outcome == "fail" else (SaUiKit.GOLD if outcome != "ok" else SaUiKit.TEAL)
	var outcome_label := SaUiKit.label("%s — %s" % [String(action.get("label","")), head], SaUiKit.FONT_HEAD, color)
	outcome_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(outcome_label)

	var gains: Dictionary = result.get("gains", {})
	for k in gains.keys():
		var v := int(gains[k])
		if v == 0:
			continue
		col.add_child(SaUiKit.label("%s %s" % [_stat_name(String(k)), SaUiKit.format_delta(v)],
			SaUiKit.FONT_BODY, SaUiKit.delta_color(v)))

	# 각성은 런당 1회다. 등급이 올랐다는 사실을 그 자리에서 보여주지 않으면
	# 플레이어에게는 조금 큰 대성공과 구분되지 않는다.
	if bool(result.get("promoted_talent", false)):
		var stat_key := String(action.get("stat", "")) if action.get("stat") != null else ""
		col.add_child(SaUiKit.label(_tr("awaken")
			% [_stat_name(stat_key), String(_run.aptitude.get(stat_key, "B"))],
			SaUiKit.FONT_HEAD, SaUiKit.GOLD))

	# 분기가 바뀌는 턴에는 적립된 숙련도가 함께 들어온다. 표시하지 않으면
	# 플레이어에게는 상한에서 사라진 성장이 영영 돌아오지 않은 것처럼 보인다.
	var released: Dictionary = result.get("mastery_released", {})
	for k in released.keys():
		var rv := int(released[k])
		if rv == 0:
			continue
		col.add_child(SaUiKit.label(_tr("mastery") % [_stat_name(String(k)), SaUiKit.format_delta(rv)],
			SaUiKit.FONT_BODY, SaUiKit.GOLD))

	for c in (result.get("entered_conditions", []) as Array):
		col.add_child(SaUiKit.label("· %s" % _condition_name(String(c)), SaUiKit.FONT_BODY, SaUiKit.ROSE))
	if bool(result.get("tuition_charged", false)):
		# 밀린 금액이 있으면 청구액도 실제 납부액도 월 수업료와 다르다.
		col.add_child(SaUiKit.label(_tr("tuition") % int(result.get("tuition_paid", 0)),
			SaUiKit.FONT_SMALL, SaUiKit.INK_DIM))
	var owed := int(result.get("debt_amount", 0))
	if owed > 0:
		col.add_child(SaUiKit.label(_tr("debt")
			% [owed, SaResources.DEBT_REPUTATION_PENALTY], SaUiKit.FONT_SMALL, SaUiKit.ROSE))

	_save_notice(col)
	col.add_child(_next_button(_tr("continue"), func():
		if not _run.pending_events.is_empty():
			_show_event()
		else:
			_finish_turn()))

# ── 이벤트 ─────────────────────────────────────────────────────────
func _show_event() -> void:
	var ev: Dictionary = _run.pending_events[0]
	# 계절 심사는 장면이 다르다. 배경음도 따라간다.
	Audio.play_bgm("bgm_milestone" if String(ev.get("category", "")) == "milestone" else "bgm_event")
	Audio.play_sfx("sfx_page")
	var col := _panel_overlay()
	var event_title := SaUiKit.heading(String(ev.get("title", "")))
	event_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(event_title)
	var body := SaUiKit.label(String(ev.get("body", "")), SaUiKit.FONT_BODY)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size = Vector2(0, 0)
	col.add_child(body)

	for c in (ev.get("choices", []) as Array):
		var choice: Dictionary = c
		var avail := SaEventResolution.choice_availability(_run.beat, choice)
		var btn := Button.new()
		btn.mouse_filter = Control.MOUSE_FILTER_PASS
		btn.custom_minimum_size = Vector2(0, SaUiKit.TOUCH_MIN)
		btn.add_theme_font_size_override("font_size", SaUiKit.FONT_BODY)
		btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_tag(btn, "event-choice:" + String(choice.get("id", "")))
		if bool(avail["ok"]):
			btn.text = String(choice.get("label", ""))
			btn.pressed.connect(func(): _on_event_choice(choice))
		else:
			# 미충족 선택지는 숨기지 않는다. 사유를 보여줘야 임계값을 학습한다.
			var reason := String(choice.get("locked_reason", _tr("locked")))
			if String(avail.get("reason_code", "")) != "requirements":
				reason = _tr("need_" + String(avail.get("reason_code", "")))
			btn.text = "%s  (%s)" % [String(choice.get("label", "")), reason]
			btn.disabled = true
		col.add_child(btn)

func _on_event_choice(choice: Dictionary) -> void:
	if not _age_permits_game():
		return
	Audio.play_sfx("sfx_tap")
	var outcome := _run.apply_event_choice(choice)
	_save_run()
	var col := _panel_overlay()
	var text := SaUiKit.label(String(outcome.get("result_text", "")), SaUiKit.FONT_BODY)
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.custom_minimum_size = Vector2(0, 0)
	col.add_child(text)
	_save_notice(col)
	col.add_child(_next_button(_tr("continue"), func():
		if not _run.pending_events.is_empty():
			_show_event()
		else:
			_finish_turn()))

# ── 별자리 (스탯 시트) ──────────────────────────────────────────────
func _show_constellation() -> void:
	var col := _panel_overlay()
	col.add_child(SaUiKit.heading(_tr("constellation")))
	var stats: Dictionary = _run.state.get("stats", {})
	for key in SaStatKeys.ALL:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		row.add_child(SaUiKit.label("%s  %s" % [_stat_name(key), _run.aptitude.get(key, "B")],
			SaUiKit.FONT_SMALL, SaUiKit.INK_DIM))
		var bar := ProgressBar.new()
		bar.max_value = 100
		bar.value = int(stats.get(key, 0))
		bar.custom_minimum_size = Vector2(360, 22)
		bar.show_percentage = false
		row.add_child(bar)
		row.add_child(SaUiKit.label(str(int(stats.get(key, 0))), SaUiKit.FONT_SMALL))
		col.add_child(row)
	col.add_child(SaUiKit.label(_tr("reputation") % int(_run.state.get("reputation", 0)),
		SaUiKit.FONT_BODY, SaUiKit.GOLD))
	col.add_child(_next_button(_tr("close"), _show_turn))

# ── 엔딩 ───────────────────────────────────────────────────────────
func _show_ending() -> void:
	_clear()
	var ending := _run.judge()
	# 완주한 런은 이어할 것이 없다. 회차를 올리고 저장을 지운다 —
	# 지우지 않으면 타이틀의 이어하기가 끝난 런을 계속 되살린다.
	if not _ending_recorded:
		_ending_recorded = Profile.record_completion(String(ending.get("code", "")))
	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_FULL_RECT)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 20)
	col.add_child(_centered(SaUiKit.label(String(ending.get("title", "조용한 일상")),
		SaUiKit.FONT_TITLE, SaUiKit.GOLD)))
	var summary := SaUiKit.label(String(ending.get("summary", "")), SaUiKit.FONT_BODY)
	summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	summary.custom_minimum_size = Vector2(560, 0)
	summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_centered(summary))
	col.add_child(_centered(SaUiKit.label(_tr("band") % int(ending.get("band", 0)),
		SaUiKit.FONT_SMALL, SaUiKit.INK_DIM)))
	var again := Button.new()
	again.text = _tr("restart")
	_tag(again, "restart")
	again.disabled = not _ending_recorded
	again.custom_minimum_size = Vector2(280, SaUiKit.TOUCH_MIN)
	again.pressed.connect(_show_title)
	if not _ending_recorded:
		col.add_child(SaUiKit.label(_tr("save_failed"), SaUiKit.FONT_SMALL, SaUiKit.ROSE))
		col.add_child(_button(_tr("retry"), "retry", _show_ending))
	col.add_child(_centered(again))
	add_child(col)

# ── 헬퍼 ───────────────────────────────────────────────────────────
func _panel_overlay() -> VBoxContainer:
	_input_locked = false
	if _overlay != null and is_instance_valid(_overlay):
		_overlay.hide()
		_overlay.queue_free()
	var scrim := ColorRect.new()
	scrim.color = Color(0, 0, 0, 0.55)
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(scrim)
	_overlay = scrim
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	scrim.add_child(margin)
	var center := CenterContainer.new()
	margin.add_child(center)
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(minf(size.x - 48, 624), 0)
	card.add_theme_stylebox_override("panel", SaUiKit.panel())
	center.add_child(card)
	var scroll := ScrollContainer.new()
	scroll.name = "OverlayScroll"
	scroll.custom_minimum_size = Vector2(0, minf(size.y - 96, 640))
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	card.add_child(scroll)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 14)
	scroll.add_child(col)
	return col

func _next_button(text: String, action: Callable) -> Control:
	var b := Button.new()
	b.mouse_filter = Control.MOUSE_FILTER_PASS
	b.text = text
	_tag(b, "continue" if text == _tr("continue") else "close")
	b.custom_minimum_size = Vector2(240, SaUiKit.TOUCH_MIN)
	b.add_theme_font_size_override("font_size", SaUiKit.FONT_BODY)
	b.pressed.connect(func():
		if not _age_permits_game():
			return
		if _overlay != null and is_instance_valid(_overlay):
			_overlay.hide()
			_overlay.queue_free()
			_overlay = null
		b.disabled = true
		action.call())
	return _centered(b)

func _centered(node: Control) -> Control:
	var c := CenterContainer.new()
	c.add_child(node)
	return c

func _clear() -> void:
	for c in get_children():
		if c == _age_overlay:
			continue
		if c is ColorRect and c.get_index() == 0:
			continue
		if c is Control:
			(c as Control).hide()
		c.queue_free()
	_overlay = null
	_age_status_label = null
	_age_retry_wrap = null
	_input_locked = false
	_raise_age_overlay.call_deferred()

func _raise_age_overlay() -> void:
	if is_instance_valid(_age_overlay):
		move_child(_age_overlay, -1)

func _stat_name(key: String) -> String:
	return SaLocalization.stat(key, _locale)

func _condition_name(key: String) -> String:
	return SaLocalization.condition(key, _locale)

func _tr(key: String) -> String:
	return SaLocalization.text("ui." + key, _locale)

func _tag(control: Control, id: String) -> void:
	control.set_meta("e2e_id", id)

func _button(text: String, id: String, callback: Callable) -> Button:
	var button := Button.new()
	button.mouse_filter = Control.MOUSE_FILTER_PASS
	button.text = text
	button.custom_minimum_size = Vector2(280, SaUiKit.TOUCH_MIN)
	button.add_theme_font_size_override("font_size", SaUiKit.FONT_BODY)
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tag(button, id)
	button.pressed.connect(func():
		button.disabled = true
		callback.call())
	return button

func _change_language() -> void:
	var next := "en" if _locale == "ko" else "ko"
	if not Profile.set_language(next):
		_show_message(_tr("save_failed"))
		return
	_locale = next
	_content = SaLocalization.content(_load_content(), _locale)
	_show_title()

func _age_label(value: String) -> String:
	return _tr({"under13":"age_under13", "13-15":"age_13_15", "16-17":"age_16_17", "adult":"age_adult"}.get(value, "age_unknown"))

func _show_age() -> void:
	var col := _panel_overlay()
	col.add_child(SaUiKit.heading(_tr("age")))
	var explanation := SaUiKit.label(_tr("age_prompt"), SaUiKit.FONT_BODY)
	explanation.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(explanation)
	for value in ["under13", "13-15", "16-17", "adult"]:
		col.add_child(_button(_age_label(value), "age:" + value, func():
			if Profile.set_age_band(value):
				ad_service.configure(value)
				_show_title()
			else:
				_show_message(_tr("save_failed"))))
	col.add_child(_next_button(_tr("close"), _show_title))

func _privacy_options() -> void:
	if not ad_service.adapter.privacy_options():
		_show_message(_tr("privacy_unavailable"))
	else:
		_show_title()

func _show_message(message: String) -> void:
	var col := _panel_overlay()
	var label := SaUiKit.label(message, SaUiKit.FONT_BODY)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(label)
	col.add_child(_next_button(_tr("close"), _show_title))

func _save_notice(col: VBoxContainer) -> void:
	if _last_save_ok:
		return
	var label := SaUiKit.label(_tr("save_failed"), SaUiKit.FONT_SMALL, SaUiKit.ROSE)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(label)
	var retry := _button(_tr("retry"), "retry", func():
		if _save_run():
			label.text = _tr("saved"))
	col.add_child(retry)

func _finish_turn() -> void:
	if not _age_permits_game():
		return
	var played := int(_run.last_result.get("played_turn", 0))
	if not _run.is_over() and played > 0 and played % 3 == 0 and played != _boundary_turn:
		_boundary_turn = played
		ad_service.consider_month_end(_save_run(), played <= 3, _show_turn)
	else:
		_show_turn()

func _exit_tree() -> void:
	if age_access != null:
		age_access.release()
	if ad_service != null:
		ad_service.release()

func _age_permits_game() -> bool:
	if age_access == null or age_access.can_play():
		return true
	_age_notice_dismissed = false
	_render_age_access()
	return false

func _render_age_access() -> void:
	if age_access == null:
		return
	var blocked := not age_access.block_reason.is_empty()
	if is_instance_valid(_age_status_label):
		_age_status_label.text = _tr("age_access_" + age_access.block_reason) if blocked else ""
		_age_status_label.visible = blocked and _age_notice_dismissed
	if is_instance_valid(_age_retry_wrap):
		_age_retry_wrap.visible = blocked and not age_access.checking and _age_notice_dismissed
	if is_instance_valid(_age_overlay):
		_age_overlay.hide()
		_age_overlay.queue_free()
		_age_overlay = null
	if not age_access.checking and (not blocked or _age_notice_dismissed):
		return
	# 게임 이벤트와 별도의 겹침 화면이다. OS 확인 중에도 기존 선택과
	# 결과 화면, 메모리의 진행 상태를 건드리지 않는다.
	var scrim := ColorRect.new()
	scrim.color = Color(0, 0, 0, 0.75)
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	scrim.z_index = 100
	add_child(scrim)
	_age_overlay = scrim
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 32)
	scrim.add_child(margin)
	var center := CenterContainer.new()
	margin.add_child(center)
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(minf(size.x - 64, 600), 0)
	card.add_theme_stylebox_override("panel", SaUiKit.panel())
	center.add_child(card)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(0, minf(size.y - 128, 640))
	card.add_child(scroll)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 20)
	scroll.add_child(col)
	var title := SaUiKit.heading(_tr("age_access_title"))
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(title)
	var text := _tr("age_access_checking") if age_access.checking else _tr("age_access_" + age_access.block_reason)
	var body := SaUiKit.label(text, SaUiKit.FONT_BODY)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(body)
	if age_access.checking:
		_tag(body, "age-access:checking")
	else:
		var saved := SaUiKit.label(_tr("age_access_saved"), SaUiKit.FONT_SMALL, SaUiKit.INK_DIM)
		saved.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		col.add_child(saved)
		col.add_child(_button(_tr("age_access_retry"), "age-access:retry", refresh_age_access))
		col.add_child(_button(_tr("close"), "age-access:close", func():
			_age_notice_dismissed = true
			_show_title()))
