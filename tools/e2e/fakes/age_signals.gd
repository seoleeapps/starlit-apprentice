extends "res://src/platform/age_signals_adapter.gd"
## 네이티브 연령 SDK 응답 경계만 대체한다. 제품 접근 판단과 UI는 실제 장면을 쓴다.
var supported := false
var status := "unsupported"
var age_lower := -1
var age_upper := -1
var auto_complete := true
var request_calls := 0
var release_calls := 0
var request_ids: Array[int] = []

func request(request_id: int) -> void:
	request_calls += 1
	request_ids.append(request_id)
	if auto_complete:
		completed.emit(request_id, status if supported else "unsupported", age_lower, age_upper)

func respond(index: int, value: String, lower: int = -1, upper: int = -1) -> void:
	assert(index >= 0 and index < request_ids.size())
	completed.emit(request_ids[index], value, lower, upper)

func release() -> void:
	release_calls += 1
	# SDK가 해제 뒤 늦게 보낸 응답도 재현할 수 있도록 요청 ID는 보존한다.
