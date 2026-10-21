extends "res://src/game/file_storage.gd"
## 저장 실패만 대체한다. 성공 경로는 실제 파일 저장과 백업을 그대로 쓴다.
var fail_writes := false
var write_attempts := 0

func _init(run_path: String, meta_path: String) -> void:
	super(run_path, meta_path)

func write_run(data: Dictionary) -> bool:
	write_attempts += 1
	return false if fail_writes else super.write_run(data)
