extends RefCounted
var unix_seconds := 1792540800.0

func now() -> float:
	return unix_seconds

func advance(seconds: float) -> void:
	unix_seconds += seconds

func seed_value() -> int:
	return 4242
