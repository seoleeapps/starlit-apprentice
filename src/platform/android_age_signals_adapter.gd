class_name SaAndroidAgeSignalsAdapter
extends "res://src/platform/age_signals_adapter.gd"
## Native plugin은 이 어댑터에만 연결한다.

var _native: Object
var _request_id := -1
var _waiting := false
var _released := false

func _init(native_override: Object = null) -> void:
	_native = native_override
	if _native == null and Engine.has_singleton("StarlitAgeSignals"):
		_native = Engine.get_singleton("StarlitAgeSignals")
	if _native != null and _native.has_signal("age_signals_result") and _native.has_method("requestAgeSignals"):
		_native.connect("age_signals_result", _on_result)
	else:
		_native = null

func request(request_id: int) -> void:
	if _released:
		return
	_request_id = request_id
	_waiting = true
	if _native == null:
		_on_result(request_id, "unavailable", -1, -1)
	else:
		_native.call("requestAgeSignals", request_id)

func _on_result(request_id: int, status: String, lower: int, upper: int) -> void:
	if _released or not _waiting or request_id != _request_id:
		return
	_waiting = false
	completed.emit(request_id, status, lower, upper)

func release() -> void:
	if _released:
		return
	_released = true
	_waiting = false
	if _native != null:
		_native.disconnect("age_signals_result", _on_result)
		_native = null
