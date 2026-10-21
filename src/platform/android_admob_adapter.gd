class_name SaAndroidAdMobAdapter
extends SaAdAdapter
## Poing v5.1.0 전면광고와 UMP. 실제 SDK 호출은 이 파일에만 둔다.

const CONFIG := "res://config/android_runtime.json"
var _unit := ""
var _age := "unknown"
var _generation := 0
var _consented := false
var _initialized := false
var _initializing := false
var _consent_inflight := false
var _consent_form_open := false
var _released := false
var _loading := false
var _showing := false
var _ad: InterstitialAd

func _init() -> void:
	if FileAccess.file_exists(CONFIG):
		var reader := JSON.new()
		if reader.parse(FileAccess.get_file_as_string(CONFIG)) == OK and reader.data is Dictionary:
			_unit = String(reader.data.get("interstitialAdUnitId", ""))

func _available() -> bool:
	return OS.get_name() == "Android" and Engine.has_singleton("PoingGodotAdMob") \
		and Engine.has_singleton("PoingGodotAdMobConsentInformation") \
		and Engine.has_singleton("PoingGodotAdMobUserMessagingPlatform") \
		and _unit.begins_with("ca-app-pub-")

func configure(age: String) -> void:
	_generation += 1
	_age = age
	_consented = false
	_loading = false
	_discard()
	_request_consent()

func _age_allowed() -> bool:
	return _age in ["13-15", "16-17", "adult"]

func _request_consent() -> void:
	# Poing의 UMP callback 슬롯은 하나라 이전 요청이 끝나기 전에 덮어쓰지 않는다.
	if _released or not _available() or not _age_allowed() or _consent_inflight or _consent_form_open:
		return
	var request := RequestConfiguration.new()
	request.tag_for_child_directed_treatment = RequestConfiguration.TagForChildDirectedTreatment.FALSE
	request.tag_for_under_age_of_consent = RequestConfiguration.TagForUnderAgeOfConsent.TRUE if _age != "adult" else RequestConfiguration.TagForUnderAgeOfConsent.FALSE
	request.max_ad_content_rating = RequestConfiguration.MAX_AD_CONTENT_RATING_PG
	MobileAds.set_request_configuration(request)
	var params := ConsentRequestParameters.new()
	params.tag_for_under_age_of_consent = _age != "adult"
	var generation := _generation
	_consent_inflight = true
	UserMessagingPlatform.consent_information.update(params,
		func(): _consent_updated(generation, true),
		func(_error): _consent_updated(generation, false))

func _consent_updated(generation: int, success: bool) -> void:
	_consent_inflight = false
	if _released:
		return
	if generation != _generation:
		_request_consent()
	elif success:
		_resolve_consent(generation)

func _resolve_consent(generation: int) -> void:
	var status := UserMessagingPlatform.consent_information.get_consent_status()
	if status == ConsentInformation.ConsentStatus.REQUIRED:
		# 연령 제한 상태에서 추가 동의를 추측하지 않는다.
		if _age != "adult":
			return
		_consent_form_open = true
		UserMessagingPlatform.load_consent_form(
			func(form):
				if generation != _generation or _released:
					_consent_form_open = false
					_request_consent()
					return
				form.show(func(error): _form_closed(generation, error)),
			func(error): _form_closed(generation, error))
	else:
		_complete_consent()

func _form_closed(generation: int, error: Variant) -> void:
	_consent_form_open = false
	if _released:
		return
	if generation != _generation:
		_request_consent()
	elif error == null:
		_complete_consent()

func _complete_consent() -> void:
	if _released or not _age_allowed():
		return
	var status := UserMessagingPlatform.consent_information.get_consent_status()
	_consented = status in [ConsentInformation.ConsentStatus.NOT_REQUIRED, ConsentInformation.ConsentStatus.OBTAINED]
	if not _consented:
		return
	if _initialized:
		prepare()
	elif not _initializing:
		_initializing = true
		var listener := OnInitializationCompleteListener.new()
		listener.on_initialization_complete = func(_status):
			_initializing = false
			_initialized = true
			prepare()
		MobileAds.initialize(listener)

func prepare() -> void:
	if _released or not _age_allowed() or not _available() or not _consented or not _initialized or _loading or _ad != null or _showing:
		return
	_loading = true
	var generation := _generation
	var callback := InterstitialAdLoadCallback.new()
	callback.on_ad_loaded = func(ad: InterstitialAd):
		if generation != _generation:
			ad.destroy()
			return
		_loading = false
		_ad = ad
	callback.on_ad_failed_to_load = func(_error):
		if generation == _generation:
			_loading = false
	var request := AdRequest.new()
	if _age != "adult":
		request.extras = {"npa": "1"}
	InterstitialAdLoader.new().load(_unit, request, callback)

func ready() -> bool:
	return not _released and _age_allowed() and _consented and _ad != null and not _showing

func show() -> bool:
	if not ready():
		return false
	_showing = true
	var generation := _generation
	var callbacks := FullScreenContentCallback.new()
	callbacks.on_ad_impression = func():
		if generation == _generation and _showing:
			impression.emit()
	callbacks.on_ad_dismissed_full_screen_content = func():
		if generation == _generation and _showing:
			_discard()
			closed.emit()
	callbacks.on_ad_failed_to_show_full_screen_content = func(_error):
		if generation == _generation and _showing:
			_discard()
			failed.emit()
	_ad.full_screen_content_callback = callbacks
	_ad.show()
	return true

func privacy_options() -> bool:
	if _released or not _available() or _consent_inflight or _consent_form_open:
		return false
	if UserMessagingPlatform.consent_information.get_privacy_options_requirement_status() != ConsentInformation.PrivacyOptionsRequirementStatus.REQUIRED:
		return false
	_generation += 1
	_consented = false
	_loading = false
	_discard()
	var generation := _generation
	_consent_form_open = true
	UserMessagingPlatform.show_privacy_options_form(func(error): _form_closed(generation, error))
	return true

func _discard() -> void:
	_showing = false
	if _ad != null:
		_ad.destroy()
		_ad = null

func release() -> void:
	_released = true
	_generation += 1
	_consented = false
	_discard()
