@tool
extends EditorPlugin

const AndroidExport = preload("res://addons/starlit_age_signals/android_export.gd")
var _exporter: EditorExportPlugin

func _enter_tree() -> void:
	_exporter = AndroidExport.new()
	add_export_plugin(_exporter)

func _exit_tree() -> void:
	remove_export_plugin(_exporter)
	_exporter = null
