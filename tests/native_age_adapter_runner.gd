extends SceneTree

const Adapter = preload("res://src/platform/android_age_signals_adapter.gd")

class FakeNative extends RefCounted:
	signal age_signals_result(request_id: int, status: String, lower: int, upper: int)
	var calls: Array[int] = []
	func requestAgeSignals(request_id: int) -> void:
		calls.append(request_id)

var _results: Array = []
var _failures := 0

func _initialize() -> void:
	var native := FakeNative.new()
	var adapter := Adapter.new(native)
	adapter.completed.connect(func(id: int, value: String, lower: int, upper: int): _results.append([id, value, lower, upper]))
	adapter.request(10)
	adapter.request(11)
	native.age_signals_result.emit(10, "approval_denied", -1, -1)
	_expect(_results.is_empty(), "이전 요청의 응답은 무시한다")
	native.age_signals_result.emit(11, "shared", 13, 15)
	native.age_signals_result.emit(11, "approval_denied", -1, -1)
	_expect(_results == [[11, "shared", 13, 15]], "현재 요청의 콜백 1회만 전달한다")
	_expect(native.calls == [10, 11], "실제 native 메서드와 요청 식별자를 사용한다")
	adapter.request(12)
	adapter.release()
	adapter.release()
	native.age_signals_result.emit(12, "approval_denied", -1, -1)
	adapter.request(13)
	_expect(_results.size() == 1 and native.calls == [10, 11, 12], "해제 후 전달 및 요청 없음")
	_expect(native.get_signal_connection_list("age_signals_result").is_empty(), "해제 후 연결 없음")
	var missing := Adapter.new()
	missing.completed.connect(func(id: int, value: String, lower: int, upper: int): _results.append([id, value, lower, upper]))
	missing.request(14)
	_expect(_results[-1] == [14, "unavailable", -1, -1], "플러그인 부재는 적용 대상 아님으로 추측하지 않는다")
	missing.release()
	print("Native 연령 어댑터 검사 6개, 실패 %d개" % _failures)
	quit(1 if _failures else 0)

func _expect(ok: bool, description: String) -> void:
	if not ok:
		_failures += 1
		print("FAIL: " + description)
