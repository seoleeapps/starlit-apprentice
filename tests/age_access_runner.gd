extends SceneTree

const Access = preload("res://src/game/age_access.gd")
const Port = preload("res://src/platform/age_signals_adapter.gd")

class FakePort extends Port:
	var ids: Array[int] = []
	var releases := 0
	func request(request_id: int) -> void:
		ids.append(request_id)
	func release() -> void:
		releases += 1
	func respond(value: String, lower: int = -1, upper: int = -1, index: int = -1) -> void:
		completed.emit(ids[index], value, lower, upper)

var _checks := 0
var _failures := 0

func _initialize() -> void:
	for value in ["not_shared", "unknown", "offline", "unavailable", "error", "unsupported"]:
		var port := FakePort.new()
		var access := Access.new(port)
		access.refresh()
		_expect(not access.can_play(), "확인 중 접근을 보류한다: " + value)
		port.respond(value)
		_expect(access.can_play(), "초기 정보 미수신은 원래 게임을 허용한다: " + value)
		_expect(access.status == value, "실패 상태를 구분한다: " + value)
		access.release()
	for pair in [[0, 12], [10, 12], [-1, 12], [12, 15]]:
		var port := FakePort.new()
		var access := Access.new(port)
		access.refresh()
		port.respond("shared", pair[0], pair[1])
		_expect(not access.can_play() and access.block_reason == "under13", "공유된 13세 미만 보호: " + str(pair))
		access.release()
	for value in ["approval_pending", "approval_denied"]:
		var port := FakePort.new()
		var access := Access.new(port)
		access.refresh()
		port.respond(value)
		_expect(not access.can_play() and access.block_reason == value, "보호자 상태: " + value)
		for failure in ["not_shared", "unknown", "offline", "unavailable", "error", "unsupported"]:
			access.refresh()
			port.respond(failure)
			_expect(not access.can_play() and access.block_reason == value, "재시도 오류로 보호를 우회하지 않는다: " + failure)
		access.refresh()
		port.respond("shared", 13, 15)
		_expect(access.can_play() and access.block_reason.is_empty(), "새 공유 응답으로 보호를 해제한다")
		access.release()
	for pair in [[13, 15], [16, 17], [18, -1]]:
		var port := FakePort.new()
		var access := Access.new(port)
		access.refresh()
		port.respond("shared", pair[0], pair[1])
		_expect(access.can_play(), "허용 범위: " + str(pair))
		access.release()
	var port := FakePort.new()
	var access := Access.new(port)
	access.refresh()
	access.refresh()
	_expect(port.ids.size() == 1, "진행 중 요청은 합친다")
	access.advance(4.99)
	_expect(access.checking, "5초 전까지 기다린다")
	access.advance(0.02)
	_expect(not access.checking and access.status == "error" and access.can_play(), "5초 제한 후 원래 게임에 복귀한다")
	port.respond("shared", 0, 12, 0)
	_expect(access.can_play() and access.status == "error", "시간 초과 응답을 무시한다")
	access.refresh()
	_expect(port.ids.size() == 2 and port.ids[1] > port.ids[0], "새 재시도 식별자")
	port.respond("shared", 0, 12, 0)
	_expect(access.checking, "이전 응답이 새 요청을 끝내지 않는다")
	port.respond("shared", 18, -1)
	port.respond("approval_denied")
	_expect(access.can_play() and access.status == "shared", "중복 콜백은 한 번만 처리한다")
	access.refresh()
	port.respond("shared", 18, 12)
	_expect(access.status == "error", "잘못된 범위를 명시 오류로 처리한다")
	access.refresh()
	port.respond("future_status")
	_expect(access.status == "error", "미래 상태를 추측하지 않는다")
	access.release()
	access.release()
	access.refresh()
	_expect(port.releases == 1 and port.ids.size() == 4, "해제 뒤 요청과 중복 해제 없음")
	var next_port := FakePort.new()
	var next_access := Access.new(next_port)
	next_access.refresh()
	_expect(next_port.ids[0] > port.ids[-1], "장면을 다시 만들어도 native 요청 식별자를 재사용하지 않는다")
	next_access.release()
	print("연령 접근 검사 %d개, 실패 %d개" % [_checks, _failures])
	quit(1 if _failures else 0)

func _expect(ok: bool, description: String) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		print("FAIL: " + description)
