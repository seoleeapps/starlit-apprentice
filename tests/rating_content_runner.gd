extends SceneTree
## 실제 이벤트와 코어에서 참가비 없는 예보 의뢰의 성공/실패를 검사한다.
var failures: Array[String] = []
func _initialize() -> void:
	call_deferred("_run")
func _run() -> void:
	var source: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/events.json"))
	var outcomes := {}
	for locale in ["ko", "en"]:
		var content := SaLocalization.content({"events": source.events}, locale)
		var event: Dictionary = (content.events as Array).filter(func(e): return e.id == "opp.wager-table")[0]
		var choice: Dictionary = event.choices[0]
		for gold in [0, 120]:
			var state := SaResources.new_state(1, 2)
			state["turn"] = 12
			state["gold"] = gold
			state.stats["intellect"] = 50
			_check(bool(SaEventResolution.choice_availability(state, choice).ok), "%s: gold%d can accept commission" % [locale, gold])
			for seed_value in [1, 123456789, 42424242, 2147483647, 2654435769]:
				var result := SaEventResolution.apply(state, event, choice, SaRng.new(seed_value))
				outcomes[result.kind] = true
				var expected: int = gold + (200 if result.kind == "success" else 0)
				_check(int(result.state.gold) == expected, "%s: %s keeps gold%d, actual%d" % [locale, result.kind, expected, result.state.gold])
	_check(outcomes.has("success") and outcomes.has("failure"), "both real core outcomes exercised")
	for failure in failures:
		push_error(failure)
	print("RATING CONTENT checks=25 failures=%d" % failures.size())
	quit(0 if failures.is_empty() else 1)
func _check(ok: bool, text: String) -> void:
	if not ok:
		failures.append(text)
