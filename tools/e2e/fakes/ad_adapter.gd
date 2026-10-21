extends "res://src/platform/ad_adapter.gd"
## SDK의 로드, 표시와 콜백만 대체한다. 광고 정책은 실제 service가 계산한다.
var available := true
var mode := "complete"
var show_calls := 0
var prepare_calls := 0
var privacy_calls := 0
var age := "unknown"
var before_show: Callable
var trace: Array = []

func configure(value: String) -> void:
	age = value

func prepare() -> void:
	prepare_calls += 1

func ready() -> bool:
	return available

func show() -> bool:
	show_calls += 1
	if before_show.is_valid():
		trace.append(before_show.call())
	match mode:
		"reject":
			return false
		"fail":
			failed.emit()
		"complete":
			impression.emit()
			closed.emit()
		"duplicate":
			impression.emit()
			impression.emit()
			closed.emit()
			closed.emit()
	return true

func finish_twice() -> void:
	impression.emit()
	impression.emit()
	closed.emit()
	closed.emit()

func privacy_options() -> bool:
	privacy_calls += 1
	return true
