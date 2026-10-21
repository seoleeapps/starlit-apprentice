extends SceneTree
## 실제 Poing GDScript와 Android 어댑터의 계약 회귀.
## native singleton만 가짜로 넣는다. Android SDK 실행 근거는 아니다.

class NativeConsent:
	extends RefCounted
	signal on_consent_info_updated_success
	signal on_consent_info_updated_failure(error: Dictionary)
	var status := ConsentInformation.ConsentStatus.OBTAINED
	var requests: Array = []
	func update(params: Dictionary) -> void:
		requests.append(params)
	func get_consent_status() -> int:
		return status
	func get_privacy_options_requirement_status() -> int:
		return ConsentInformation.PrivacyOptionsRequirementStatus.REQUIRED

class NativeUmp:
	extends RefCounted
	signal on_privacy_options_form_dismissed_listener(error: Dictionary)
	var privacy_calls := 0
	func show_privacy_options_form() -> void:
		privacy_calls += 1

class NativeLoader:
	extends RefCounted
	signal on_interstitial_ad_loaded(uid: int)
	signal on_interstitial_ad_failed_to_load(uid: int, error: Dictionary)
	var loads: Array = []
	func create() -> int:
		return loads.size() + 1
	func load(unit: String, request: Dictionary, _keywords: Array, uid: int) -> void:
		loads.append({"unit": unit, "request": request, "uid": uid})

class NativeMobile:
	extends RefCounted
	var configurations: Array = []
	func set_request_configuration(request: Dictionary, _test_devices: Array) -> void:
		configurations.append(request)

class Adapter:
	extends SaAndroidAdMobAdapter
	func _available() -> bool:
		return true

var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _expect(name: String, actual: Variant, expected: Variant) -> void:
	checks += 1
	print(JSON.stringify({"name": name, "actual": actual, "expected": expected, "ok": actual == expected}))
	if actual != expected:
		failures += 1
		printerr("FAIL: %s" % name)

func _run() -> void:
	var consent := NativeConsent.new()
	var ump := NativeUmp.new()
	var mobile := NativeMobile.new()
	var loader := NativeLoader.new()
	ConsentInformation._plugin = consent
	UserMessagingPlatform._plugin = ump
	MobileAds._plugin = mobile
	InterstitialAdLoader._plugin = loader
	var adapter := Adapter.new()
	adapter._initialized = true
	adapter.configure("under13")
	_expect("13세 미만 광고 요청 없음", loader.loads.size(), 0)
	_expect("13세 미만 UMP update 요청 없음", consent.requests.size(), 0)
	_expect("13세 미만도 기존 개인정보 설정을 열 수 있음", adapter.privacy_options(), true)
	ump.on_privacy_options_form_dismissed_listener.emit({})
	await process_frame
	await process_frame
	_expect("13세 미만 개인정보 재선택 뒤 광고 요청 없음", loader.loads.size(), 0)
	_expect("13세 미만 개인정보 재선택이 광고 동의로 변하지 않음", adapter._consented, false)

	var second := Adapter.new()
	second._initialized = true
	consent.status = ConsentInformation.ConsentStatus.UNKNOWN
	second.configure("13-15")
	second.configure("adult")
	_expect("UMP 이전 update 대기 중 새 update는 직렬화", consent.requests.size(), 1)
	consent.status = ConsentInformation.ConsentStatus.NOT_REQUIRED
	consent.on_consent_info_updated_success.emit()
	await process_frame
	await process_frame
	_expect("이전 청소년 응답은 현재 성인 광고를 요청하지 않음", loader.loads.size(), 0)
	_expect("이전 요청 완료 뒤 현재 연령 update 실행", consent.requests.size(), 2)
	_expect("현재 성인 UMP 인자", (consent.requests[-1] as Dictionary).get("tag_for_under_age_of_consent"), false)
	consent.on_consent_info_updated_success.emit()
	await process_frame
	await process_frame
	_expect("현재 연령 동의 결과 이후에만 광고 요청", loader.loads.size(), 1)
	await _finish_loads(loader)
	second.release()

	var teen := Adapter.new()
	teen._initialized = true
	teen.configure("16-17")
	_expect("청소년 UMP 연령 제한", (consent.requests[-1] as Dictionary).get("tag_for_under_age_of_consent"), true)
	_expect("청소년 AdMob 연령 제한", (mobile.configurations[-1] as Dictionary).get("tag_for_under_age_of_consent"), RequestConfiguration.TagForUnderAgeOfConsent.TRUE)
	_expect("광고 콘텐츠 등급 PG 제한", (mobile.configurations[-1] as Dictionary).get("max_ad_content_rating"), "PG")
	consent.on_consent_info_updated_success.emit()
	await process_frame
	await process_frame
	_expect("청소년 동의 완료 후 광고 요청", loader.loads.size(), 2)
	if loader.loads.size() >= 2:
		var request: Dictionary = (loader.loads[-1] as Dictionary)["request"]
		_expect("청소년 실제 광고 요청은 비개인맞춤", (request.get("extras", {}) as Dictionary).get("npa"), "1")
	await _finish_loads(loader, 1)
	adapter.release()
	teen.release()

	# Poing static 초기화 때 만든 에디터 mock 노드도 이 테스트에서 소유한다.
	UserMessagingPlatform._on_privacy_options_form_dismissed_callback = Callable()
	UserMessagingPlatform.consent_information._on_consent_info_updated_success_callback = Callable()
	UserMessagingPlatform.consent_information._on_consent_info_updated_failure_callback = Callable()
	MobileAds._plugin = null
	InterstitialAd._plugin = null
	InterstitialAdLoader._plugin = null
	UserMessagingPlatform._plugin = null
	ConsentInformation._plugin = null
	adapter = null
	second = null
	teen = null
	loader = null
	consent = null
	ump = null
	mobile = null
	await process_frame
	await process_frame
	var factory := load("res://addons/admob/internal/mock/mock_admob_factory.gd")
	for mock in factory._mocks.values():
		if mock is Node and is_instance_valid(mock):
			mock.free()
	factory._mocks.clear()
	print("ADAPTER CONTRACT checks=%d failures=%d (native singleton fake)" % [checks, failures])
	quit(0 if failures == 0 else 1)

func _finish_loads(loader: RefCounted, start := 0) -> void:
	# vendor가 수동 reference/unreference를 쓰므로 테스트가 콜백 대상의 마지막 참조를 소유한다.
	var callbacks: Array = []
	for link in loader.get_signal_connection_list("on_interstitial_ad_failed_to_load"):
		var target: Object = link.callable.get_object()
		if target != null and is_instance_valid(target):
			callbacks.append(target)
	for request in loader.loads.slice(start):
		loader.on_interstitial_ad_failed_to_load.emit(int(request["uid"]), {"code": 1, "domain": "test", "message": "fake failure", "response_info": {}, "cause": {}})
	await process_frame
	await process_frame
	await process_frame
	callbacks.clear()
