@tool
extends EditorExportPlugin

const LIBRARY := "res://addons/starlit_age_signals/bin/starlit-age-signals-release.aar"

func _get_name() -> String:
	return "StarlitAgeSignalsAndroid"

func _supports_platform(platform: EditorExportPlatform) -> bool:
	return platform is EditorExportPlatformAndroid

func _get_android_libraries(_platform: EditorExportPlatform, _debug: bool) -> PackedStringArray:
	# This hook only runs on export. Editor and CI import do not need the AAR.
	if not FileAccess.file_exists(LIBRARY):
		push_error("Age Signals AAR missing: run bash scripts/build-age-signals.sh before Android export")
	return PackedStringArray([LIBRARY])

func _get_android_dependencies(_platform: EditorExportPlatform, _debug: bool) -> PackedStringArray:
	return PackedStringArray(["com.google.android.play:age-signals:0.0.4"])

func _get_android_dependencies_maven_repos(_platform: EditorExportPlatform, _debug: bool) -> PackedStringArray:
	return PackedStringArray(["https://dl.google.com/dl/android/maven2/"])
