class_name SaAgeAccess
extends RefCounted
## 앱 접근 상태만 관리한다. 원시 연령 범위는 보관하지 않는다.

signal changed

const TIMEOUT_SECONDS := 5.0
const STATES := ["shared", "approval_pending", "approval_denied", "not_shared", "unknown", "offline", "unavailable", "error", "unsupported"]
static var _sequence := 0

var status := "unknown"
var block_reason := ""
var checking := false
var _adapter: RefCounted
var _request_id := 0
var _remaining := 0.0
var _released := false

func _init(adapter: RefCounted) -> void:
	_adapter = adapter
	_adapter.completed.connect(_on_completed)

func refresh() -> void:
	if _released or checking:
		return
	_sequence += 1
	_request_id = _sequence
	checking = true
	_remaining = TIMEOUT_SECONDS
	changed.emit()
	_adapter.request(_request_id)

func advance(delta: float) -> void:
	if _released or not checking:
		return
	_remaining -= maxf(delta, 0.0)
	if _remaining <= 0.0:
		_on_completed(_request_id, "error", -1, -1)

func can_play() -> bool:
	return not checking and block_reason.is_empty()

func release() -> void:
	if _released:
		return
	_released = true
	checking = false
	_adapter.completed.disconnect(_on_completed)
	_adapter.release()

func _on_completed(request_id: int, value: String, lower: int, upper: int) -> void:
	if _released or not checking or request_id != _request_id:
		return
	status = value if value in STATES else "error"
	if status == "shared":
		if lower < -1 or upper < -1 or lower > 130 or upper > 130 or (upper >= 0 and lower > upper) or (lower == -1 and upper == -1):
			status = "error"
		elif (lower >= 0 and lower < 13) or (upper >= 0 and upper < 13):
			block_reason = "under13"
		elif lower >= 13:
			block_reason = ""
	elif status in ["approval_pending", "approval_denied"]:
		block_reason = status
	# 미수신/일시 실패는 기존 보호를 풀지 않는다. 처음부터 미수신이면
	# 전체이용가 콘텐츠를 계속 이용한다. 광고에는 이 판단을 전달하지 않는다.
	checking = false
	changed.emit()
