extends RefCounted
## 저장 경계용 합성 fixture를 실제 컨트롤러로 만든다.
## 장면에 붙은 컨트롤러, 콘텐츠 풀, pending 큐와 결과 콜백은 바꾸지 않는다.

const MAX_SEED_ATTEMPTS := 4096

func build(group: Dictionary, test_case: Dictionary, source: Dictionary) -> Dictionary:
	var event_id := String(group.get("id", ""))
	var config: Dictionary = group.get("fixture", {})
	var action := _find(source.get("actions", []), String(config.get("action", "")))
	var event := _find(source.get("events", []), event_id)
	var choice := _find(event.get("choices", []), String(test_case.get("choice", "")))
	if action.is_empty() or event.is_empty() or choice.is_empty():
		return {"ok": false, "reason": "fixture의 행동, 이벤트 또는 선택 ID가 실제 콘텐츠에 없다"}

	for attempt in MAX_SEED_ATTEMPTS:
		var seed_value: int = ((attempt + 1) * 1103515245 + 12345) & 0x7FFFFFFF
		var controller := SaRunController.new()
		controller.start(seed_value, source, int(config.get("deck", 0)))
		# 새 런에서 얻은 저장본만 고친다. 실행 중인 게임 객체의 필드를 바꾸지 않는다.
		var initial_save := controller.to_save().duplicate(true)
		var state: Dictionary = initial_save["state"]
		state["turn"] = int(config.get("turn", 12))
		state["energy"] = 80
		state["stress"] = int(config.get("stress", SaResources.START_STRESS))
		state["reputation"] = int(config.get("reputation", 20))
		state["reputation_peak"] = state["reputation"]
		state["flags"] = (config.get("flags", {}) as Dictionary).duplicate(true)
		state["affinity"] = (config.get("affinity", {}) as Dictionary).duplicate(true)
		state["seen_events"] = (config.get("seenEvents", {}) as Dictionary).duplicate(true)
		var event_gold := int(test_case.get("eventGold", config.get("eventGold", 120)))
		var tuition := SaResources.MONTHLY_TUITION if SaResources.is_month_end(int(state["turn"])) and int(state["turn"]) < SaGrowthCurve.TURNS_TOTAL else 0
		state["gold"] = event_gold + tuition - int((action.get("cost", {}) as Dictionary).get("gold", 0))
		for stat in (config.get("stats", {}) as Dictionary):
			(state["stats"] as Dictionary)[stat] = int(config["stats"][stat])
		if not controller.restore(initial_save, source):
			return {"ok": false, "reason": "컨트롤러가 합성 시작 저장을 복원하지 못했다"}
		if not bool(SaResources.affordability(controller.state, action).get("ok", false)):
			return {"ok": false, "reason": "합성 시작 저장에서 fixture 행동을 고를 수 없다"}

		controller.resolve(action)
		if controller.pending_events.is_empty() or String((controller.pending_events[0] as Dictionary).get("id", "")) != event_id:
			continue
		if not bool(SaEventResolution.choice_availability(controller.beat, choice).get("ok", false)):
			return {"ok": false, "reason": "실제 판정으로 생성한 이벤트에서 fixture 선택을 고를 수 없다"}
		var pending_save := controller.to_save().duplicate(true)
		# 결과를 저장에 주입하지 않는다. 분기를 재현하는 RNG 상태를 고르기 위한 별도 모델이다.
		var prediction := SaRunController.new()
		if not prediction.restore(pending_save, source):
			return {"ok": false, "reason": "컨트롤러가 만든 pending 저장을 다시 복원하지 못했다"}
		var result := prediction.apply_event_choice(choice)
		if String(result.get("kind", "")) != String(test_case.get("outcome", "only")):
			continue
		return {"ok": true, "seed": seed_value, "attempts": attempt + 1,
			"payload": pending_save, "event": event, "choice": choice,
			"expectedKind": result["kind"], "expectedGold": int(prediction.state.get("gold", 0)),
			"expectedTurn": prediction.turn(), "expectedStats": (prediction.state.get("stats", {}) as Dictionary).duplicate(true),
			"eventGold": event_gold}
	return {"ok": false, "reason": "4096개의 실제 컨트롤러 seed에서 요청한 pending/결과 분기를 찾지 못했다"}

func _find(rows: Array, id: String) -> Dictionary:
	for row in rows:
		if String((row as Dictionary).get("id", "")) == id:
			return row as Dictionary
	return {}
