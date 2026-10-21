class_name SaLocalization
extends RefCounted
## 표시 문자열만 번역한다. 콘텐츠 ID와 수치, 조건, 효과는 원본을 유지한다.

static var _catalogs: Dictionary = {}

static func text(key: String, locale: String) -> String:
	var selected := "ko" if locale.to_lower().begins_with("ko") else "en"
	var catalog := _catalog(selected)
	return String(catalog.get(key, key))

static func stat(key: String, locale: String) -> String:
	return _named("stats", key, locale)

static func condition(key: String, locale: String) -> String:
	return _named("conditions", key, locale)

static func phase(index: int, locale: String) -> String:
	return text("phases.%d" % posmod(index, 3), locale)

static func _named(group: String, key: String, locale: String) -> String:
	var full_key := group + "." + key
	var translated := text(full_key, locale)
	return key if translated == full_key else translated

static func _catalog(locale: String) -> Dictionary:
	if not _catalogs.has(locale):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/i18n/%s.json" % locale))
		_catalogs[locale] = parsed if parsed is Dictionary else {}
	return _catalogs[locale]

static func content(source: Dictionary, locale: String) -> Dictionary:
	var result: Dictionary = source.duplicate(true)
	var catalog := _catalog("ko" if locale.to_lower().begins_with("ko") else "en")
	for group in ["actions", "events", "endings", "npcs", "paths", "affinity_bands"]:
		var identifier: String = "code" if group == "endings" else "id"
		var rows: Array = result.get(group, [])
		for row in rows:
			var item: Dictionary = row
			var base := "%s.%s" % [group, String(item.get(identifier, ""))]
			_replace_fields(item, base, catalog)
			for req in (item.get("requirements", []) as Array):
				var requirement: Dictionary = req
				var req_id := String(requirement.get("flag", requirement.get("type", "")))
				_replace_fields(requirement, base + ".requirements." + req_id, catalog)
			for choice in (item.get("choices", []) as Array):
				var c: Dictionary = choice
				var choice_base := base + ".choices." + String(c.get("id", ""))
				_replace_fields(c, choice_base, catalog)
				for outcome in (c.get("outcomes", []) as Array):
					var o: Dictionary = outcome
					_replace_fields(o, choice_base + ".outcomes." + String(o.get("kind", "")), catalog)
	if result.get("bands") is Dictionary:
		var bands: Dictionary = result["bands"]
		for key in bands:
			var translation_key := "bands." + String(key)
			if catalog.has(translation_key):
				bands[key] = catalog[translation_key]
	return result

static func _replace_fields(item: Dictionary, base: String, catalog: Dictionary) -> void:
	for field in ["label", "place", "description", "title", "body", "locked_reason", "result_text", "summary", "shareText", "hint", "name", "role", "look", "blurb"]:
		var key := base + "." + String(field)
		if item.has(field) and catalog.has(key):
			item[field] = catalog[key]
