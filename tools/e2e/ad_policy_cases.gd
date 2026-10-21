extends RefCounted
const FakeAd := preload("res://tools/e2e/fakes/ad_adapter.gd")
const FakeClock := preload("res://tools/e2e/fakes/clock.gd")
const Service := preload("res://src/game/interstitial_service.gd")
var e2e: RefCounted

func run(driver: RefCounted) -> void:
	e2e = driver
	_age_and_time()
	_failure()
	_caps()

func _service(clock: RefCounted, ad: SaAdAdapter) -> SaInterstitialService:
	var service := Service.new(ad)
	service.clock = Callable(clock, "now")
	service.persist = func(_state: Dictionary) -> bool: return true
	service.load_state({})
	return service

func _age_and_time() -> void:
	e2e.begin("ad-age-time-and-duplicate-callback", ["ads"])
	var clock := FakeClock.new()
	var ad := FakeAd.new()
	var service := _service(clock, ad)
	var calls := {"done": 0}
	var done := func(): calls["done"] += 1
	service.configure("unknown")
	service.consider_month_end(true, false, done)
	e2e.expect_equal("미확정 연령은 준비 요청 없음", ad.prepare_calls, 0)
	service.configure("under13")
	service.consider_month_end(true, false, done)
	e2e.expect_equal("13세 미만은 준비 요청 없음", ad.prepare_calls, 0)
	service.configure("13-15")
	e2e.expect_equal("청소년 연령이 어댑터에 전달됨", ad.age, "13-15")
	clock.advance(179)
	service.consider_month_end(true, false, done)
	e2e.expect_equal("첫 179초 광고 금지", ad.show_calls, 0)
	clock.advance(1)
	service.consider_month_end(true, true, done)
	e2e.expect_equal("180초 이후에도 튜토리얼 광고 금지", ad.show_calls, 0)
	ad.mode = "hold"
	service.consider_month_end(true, false, done)
	e2e.expect_equal("180초 경계에서 준비 광고 표시", ad.show_calls, 1)
	e2e.expect_equal("노출 콜백 이전 실제 횟수는 0", service.state.get("daily_count", 0), 0)
	var before := int(calls["done"])
	service.consider_month_end(true, false, done)
	e2e.expect_equal("표시 중 중복 요청 없음", ad.show_calls, 1)
	ad.finish_twice()
	e2e.expect_equal("중복 impression은 한 번 기록", service.state.get("daily_count", 0), 1)
	e2e.expect_equal("중복 close는 한 번 복귀", int(calls["done"]) - before, 1)
	clock.advance(119)
	service.consider_month_end(true, false, done)
	e2e.expect_equal("광고 종료 후 119초 금지", ad.show_calls, 1)
	clock.advance(1)
	ad.mode = "duplicate"
	service.consider_month_end(true, false, done)
	e2e.expect_equal("광고 종료 후 120초 허용", ad.show_calls, 2)
	e2e.expect_equal("실제 표시 횟수 2", service.state.get("daily_count", 0), 2)
	var restart_ad := FakeAd.new()
	var restored := Service.new(restart_ad)
	restored.clock = Callable(clock, "now")
	restored.load_state(service.state)
	restored.configure("adult")
	restored.consider_month_end(true, false, done)
	e2e.expect_equal("재실행도 120초 제한 유지", restart_ad.show_calls, 0)
	e2e.expect_equal("재실행도 노출 횟수 유지", restored.state.get("daily_count", 0), 2)
	var midnight_clock := FakeClock.new()
	midnight_clock.unix_seconds = float((int(floor(midnight_clock.unix_seconds / 86400.0)) + 1) * 86400 - 181)
	var midnight_ad := FakeAd.new()
	midnight_ad.mode = "hold"
	var midnight := _service(midnight_clock, midnight_ad)
	midnight.configure("adult")
	var previous_day := int(midnight.state["day"])
	midnight_clock.advance(180)
	midnight.consider_month_end(true, false, done)
	midnight_clock.advance(2)
	midnight_ad.finish_twice()
	e2e.expect_equal("자정을 넘은 실제 impression은 새 UTC 날짜", midnight.state.get("day"), previous_day + 1)
	e2e.expect_equal("새 날짜 impression 중복은 한 번", midnight.state.get("daily_count"), 1)
	e2e.end()

func _failure() -> void:
	e2e.begin("ad-failure-save-failure-and-late-load", ["ads", "save"])
	var clock := FakeClock.new()
	var ad := FakeAd.new()
	var service := _service(clock, ad)
	var calls := {"done": 0}
	var done := func(): calls["done"] += 1
	service.configure("adult")
	clock.advance(180)
	ad.available = false
	service.consider_month_end(true, false, done)
	e2e.expect_equal("미준비 광고는 즉시 복귀", int(calls["done"]), 1)
	ad.available = true
	e2e.expect_equal("늦은 준비는 표시 요청이 아님", ad.show_calls, 0)
	service.consider_month_end(false, false, done)
	e2e.expect_equal("런 저장 실패 시 표시 금지", ad.show_calls, 0)
	service.persist = func(_state: Dictionary) -> bool: return false
	service.consider_month_end(true, false, done)
	e2e.expect_equal("광고 예약 저장 실패 시 표시 금지", ad.show_calls, 0)
	for failure_mode in ["reject", "fail"]:
		var failed_ad := FakeAd.new()
		failed_ad.mode = failure_mode
		var fresh := _service(clock, failed_ad)
		fresh.configure("adult")
		clock.advance(180)
		var before := int(calls["done"])
		fresh.consider_month_end(true, false, done)
		e2e.expect_equal("광고 %s 뒤 즉시 복귀" % failure_mode, int(calls["done"]) - before, 1)
		e2e.expect_equal("광고 %s는 실제 노출 0" % failure_mode, fresh.state.get("daily_count", 0), 0)
		e2e.expect_equal("광고 %s 예약 해제" % failure_mode, fresh.state.get("reserved", 0), 0)
	e2e.end()

func _caps() -> void:
	e2e.begin("ad-session-day-caps-and-utc-rollover", ["ads"])
	var clock := FakeClock.new()
	var ad := FakeAd.new()
	var service := _service(clock, ad)
	service.configure("adult")
	clock.advance(180)
	var done := func(): pass
	for i in 6:
		service.consider_month_end(true, false, done)
		clock.advance(120)
	e2e.expect_equal("세션 6회 노출", ad.show_calls, 6)
	service.consider_month_end(true, false, done)
	e2e.expect_equal("세션 7번째 표시 금지", ad.show_calls, 6)
	clock.advance(1800)
	service.activity()
	service.consider_month_end(true, false, done)
	e2e.expect_equal("새 세션 시작 180초 전 금지", ad.show_calls, 6)
	clock.advance(180)
	service.consider_month_end(true, false, done)
	e2e.expect_equal("30분 비활동 뒤 새 세션", ad.show_calls, 7)
	for i in 25:
		if int(service.state.get("session_count", 0)) >= 6:
			clock.advance(1800)
			service.activity()
			clock.advance(180)
		else:
			clock.advance(120)
		service.consider_month_end(true, false, done)
	e2e.expect_equal("UTC 하루 20회 상한", ad.show_calls, 20)
	e2e.expect_equal("하루 실제 노출 20 저장", service.state.get("daily_count", 0), 20)
	var day: int = int(service.state["day"])
	clock.unix_seconds = float((day + 1) * 86400)
	service.activity()
	e2e.expect_equal("UTC 날짜 변경 시 일 횟수 0", service.state.get("daily_count", 0), 0)
	clock.advance(180)
	service.consider_month_end(true, false, done)
	e2e.expect_equal("새 날짜 새 세션 광고 허용", ad.show_calls, 21)
	e2e.end()
