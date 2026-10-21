extends SceneTree
## 번역의 원본 보호와 수치 보존을 엔진에서 확인한다. 저장 경로는 접근하지 않는다.

var _checks := 0
var _failures := 0

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var source := {}
	for group in ["actions", "events", "endings", "npcs"]:
		var parsed: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/%s.json" % group))
		source[group] = parsed[group]
		for metadata in ["paths", "affinity_bands", "bands"]:
			if parsed.has(metadata):
				source[metadata] = parsed[metadata]
	var before := JSON.stringify(source)
	var english := SaLocalization.content(source, "en")
	var korean := SaLocalization.content(english, "ko")
	_check(JSON.stringify(source) == before, "translation must not mutate source")
	_check(JSON.stringify(korean) == before, "English to Korean must restore every display field")
	_check(english["actions"].size() == 38, "all 38 actions survive")
	_check(english["events"].size() == 106, "all 106 events survive")
	_check(english["endings"].size() == 30, "all 30 endings survive")
	_check(english["npcs"].size() == 6, "all 6 NPCs survive")
	_check(english["actions"][0]["label"] == "Letters", "action label translated")
	_check(english["npcs"][0]["name"] == "Sera", "NPC name translated")
	_check(english["events"][0]["choices"][2]["locked_reason"] == "Requires at least 120 gold", "locked threshold retained")
	_check(english["events"][0]["choices"][2]["outcomes"][0]["result_text"].begins_with("The medicine"), "outcome translated")
	_check(english["endings"][1]["requirements"][0]["label"] == "Debt", "requirement label translated")
	_check(english["paths"][0]["label"] == "Path of Stars", "path metadata translated")
	_check(english["affinity_bands"][0]["name"] == "Stranger", "affinity metadata translated")
	_check(english["bands"]["0"] == "Failure", "ending bands translated")
	_compare_mechanics(source, english, "root")
	english["actions"][0]["cost"]["gold"] = -99999
	_check(JSON.stringify(source) == before, "nested mechanics also deep copied")
	for locale in ["ko", "ko_KR", "en", "fr_FR"]:
		_check(not SaLocalization.stat("intellect", locale).contains("stats."), "known stat translated: " + locale)
		for status in ["good", "normal", "slump_light", "slump", "injury", "burnout", "disgrace", "failed"]:
			_check(not SaLocalization.condition(status, locale).contains("conditions."), "known condition translated: " + status)
	_check(SaLocalization.text("ui.title", "fr_FR") == "Star Apprentice", "non-Korean locale uses English")
	_check(SaLocalization.text("ui.title", "ko_KR") == "별빛 견습생", "Korean locale uses Korean")
	_check(SaLocalization.text("missing.key", "en") == "missing.key", "missing key remains visible")
	_check(SaLocalization.stat("unknown", "en") == "unknown", "unknown stat preserved")
	_check(SaLocalization.phase(0, "ko") == "상순", "early phase Korean")
	_check(SaLocalization.phase(4, "en") == "Mid", "phase wraps to month")
	print("LOCALIZATION checks=%d failures=%d" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)

func _compare_mechanics(original: Variant, localized: Variant, path: String) -> void:
	if original is Dictionary:
		_check((original as Dictionary).keys() == (localized as Dictionary).keys(), "dictionary keys preserved: " + path)
		for key in (original as Dictionary):
			_compare_mechanics(original[key], localized[key], path + "." + String(key))
	elif original is Array:
		_check((original as Array).size() == (localized as Array).size(), "array length preserved: " + path)
		for index in (original as Array).size():
			_compare_mechanics(original[index], localized[index], path + ".%d" % index)
	elif original is String:
		# Display fields may differ; stable IDs, enums and flag names must not.
		var field := path.get_slice(".", path.get_slice_count(".") - 1)
		if field not in ["label", "place", "description", "title", "body", "locked_reason", "result_text", "summary", "shareText", "hint", "name", "role", "look", "blurb"] and not path.begins_with("root.bands."):
			_check(original == localized, "stable string preserved: " + path)
	else:
		_check(original == localized, "mechanic preserved: " + path)

func _check(ok: bool, description: String) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		push_error(description)
