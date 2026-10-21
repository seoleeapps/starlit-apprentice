class_name SaAdAdapter
extends RefCounted
## 게임이 의존하는 광고 경계. 표준 구현은 광고를 요청하지 않는다.

signal impression
signal closed
signal failed

func configure(_age: String) -> void:
	pass

func prepare() -> void:
	pass

func ready() -> bool:
	return false

func show() -> bool:
	return false

func privacy_options() -> bool:
	return false

func release() -> void:
	pass
