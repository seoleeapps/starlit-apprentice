class_name SaInterstitialService
extends RefCounted
## 월말 화면 경계에서만 표시한다. 로드 완료 콜백은 표시 요청을 만들지 않는다.

var clock: Callable = func() -> int: return int(Time.get_unix_time_from_system())
var persist: Callable
var adapter: SaAdAdapter
var policy: Dictionary
var state: Dictionary = {}
var _age := "unknown"
var _showing := false
var _counted := false
var _writable := true
var _done: Callable

func _init(port: SaAdAdapter = null, rules: Dictionary = {}) -> void:
	adapter = port if port != null else SaAdAdapter.new()
	policy = rules
	if policy.is_empty():
		policy = JSON.parse_string(FileAccess.get_file_as_string("res://data/monetization/interstitial-policy.json"))
	adapter.impression.connect(_impression)
	adapter.closed.connect(_closed)
	adapter.failed.connect(_closed)

func load_state(saved: Dictionary) -> void:
	state = saved.duplicate(true)
	# 이전 프로세스가 표시 도중 종료됐으면 예약은 상한에 계속 포함한다.
	state["reserved"] = maxi(0, int(state.get("reserved", 0)))
	_touch()

func configure(age: String) -> void:
	_age = age
	adapter.configure(age)
	if age in ["13-15", "16-17", "adult"] and bool(policy.get("enabled", false)):
		adapter.prepare()

func activity() -> void:
	_touch()
	_store()

func _touch() -> void:
	var now := int(clock.call())
	if not state.has("session_started") or now - int(state.get("last_activity", now)) >= int(policy["sessionInactivitySeconds"]):
		state["session_started"] = now
		state["session_count"] = 0
		state["reserved_session"] = 0
	var today := int(floor(float(now) / 86400.0))
	# 시계를 과거로 돌려 상한을 초기화하지 않는다.
	if today > int(state.get("day", -1)):
		state["day"] = today
		state["daily_count"] = 0
		state["reserved"] = 0
	state["last_activity"] = now

func consider_month_end(saved: bool, tutorial: bool, done: Callable) -> void:
	if _showing:
		return
	_touch()
	var now := int(clock.call())
	var allowed := saved and _writable and not tutorial and bool(policy.get("enabled", false)) \
		and _age in ["13-15", "16-17", "adult"] \
		and now - int(state.get("session_started", now)) >= int(policy["firstEligibleSeconds"]) \
		and now - int(state.get("last_closed", -1000000000)) >= int(policy["cooldownSeconds"]) \
		and int(state.get("session_count", 0)) + int(state.get("reserved_session", 0)) < int(policy["sessionCap"]) \
		and int(state.get("daily_count", 0)) + int(state.get("reserved", 0)) < int(policy["dailyCap"])
	if not allowed or not adapter.ready():
		_store()
		done.call()
		if _age in ["13-15", "16-17", "adult"] and bool(policy.get("enabled", false)):
			adapter.prepare()
		return
	# 쓰기 가능 여부를 먼저 확인하고 프로세스 종료에 대비해 예약한다.
	state["reserved"] = int(state.get("reserved", 0)) + 1
	state["reserved_session"] = int(state.get("reserved_session", 0)) + 1
	if not _store():
		done.call()
		return
	_showing = true
	_counted = false
	_done = done
	if not adapter.show():
		_closed()

func _impression() -> void:
	if not _showing or _counted:
		return
	_counted = true
	_touch()
	state["session_count"] = int(state.get("session_count", 0)) + 1
	state["daily_count"] = int(state.get("daily_count", 0)) + 1
	state["reserved"] = maxi(0, int(state.get("reserved", 0)) - 1)
	state["reserved_session"] = maxi(0, int(state.get("reserved_session", 0)) - 1)
	_store()

func _closed() -> void:
	if not _showing:
		return
	_showing = false
	if not _counted:
		state["reserved"] = maxi(0, int(state.get("reserved", 0)) - 1)
		state["reserved_session"] = maxi(0, int(state.get("reserved_session", 0)) - 1)
	state["last_closed"] = int(clock.call())
	state["last_activity"] = int(clock.call())
	_store()
	var callback := _done
	_done = Callable()
	if callback.is_valid():
		callback.call()
	adapter.prepare()

func _store() -> bool:
	if not persist.is_valid():
		return _writable
	_writable = bool(persist.call(state.duplicate(true)))
	return _writable

func release() -> void:
	_done = Callable()
	adapter.release()
