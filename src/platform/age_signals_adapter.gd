class_name SaAgeSignalsAdapter
extends RefCounted
## Play 연령 정보만 받는 경계. 광고와 저장에는 연결하지 않는다.

signal completed(request_id: int, status: String, age_lower: int, age_upper: int)

func request(request_id: int) -> void:
	completed.emit(request_id, "unsupported", -1, -1)

func release() -> void:
	pass
