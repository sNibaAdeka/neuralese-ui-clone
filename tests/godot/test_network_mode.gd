extends SceneTree

const NetworkModeConfig = preload("res://scripts/network_mode.gd")

var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_expect_equal(
		NetworkModeConfig.resolve(PackedStringArray()),
		NetworkModeConfig.Mode.Remote,
		"remote API is the safe default"
	)
	_expect_equal(
		NetworkModeConfig.resolve(PackedStringArray(["--local-api"])),
		NetworkModeConfig.Mode.Localhost,
		"local API requires an explicit flag"
	)
	_expect_equal(
		NetworkModeConfig.resolve(PackedStringArray(["--lan-api"])),
		NetworkModeConfig.Mode.LAN,
		"LAN API requires an explicit flag"
	)
	_expect_equal(
		NetworkModeConfig.http_root(NetworkModeConfig.Mode.Remote),
		"https://neuralese.asia/",
		"remote HTTP root"
	)
	_expect_equal(
		NetworkModeConfig.ws_root(NetworkModeConfig.Mode.Remote),
		"wss://neuralese.asia/",
		"remote websocket root"
	)
	_expect_equal(
		NetworkModeConfig.http_root(NetworkModeConfig.Mode.Localhost),
		"http://127.0.0.1:8081/",
		"local HTTP root"
	)
	_expect_equal(
		NetworkModeConfig.ws_root(NetworkModeConfig.Mode.Localhost),
		"ws://127.0.0.1:8081/",
		"local websocket root"
	)
	_expect_equal(
		NetworkModeConfig.http_root(NetworkModeConfig.Mode.LAN, "192.168.1.20"),
		"http://192.168.1.20:8081/",
		"LAN HTTP root"
	)
	_test_transcription_upload_urls()

	if failures == 0:
		print("PASS test_network_mode")
	quit(failures)


func _test_transcription_upload_urls() -> void:
	# Load after autoload setup; never add the probe to the tree, because that
	# would run Transcriber's microphone warm-up in _ready().
	var probe_script = load("res://tests/godot/fixtures/network_probe_transcriber.gd")
	var cases := [
		[NetworkModeConfig.Mode.Remote, "", "https://neuralese.asia/transcribe_file"],
		[NetworkModeConfig.Mode.Localhost, "", "http://127.0.0.1:8081/transcribe_file"],
		[NetworkModeConfig.Mode.LAN, "192.168.1.20", "http://192.168.1.20:8081/transcribe_file"],
	]
	for entry in cases:
		var probe = probe_script.new()
		probe.api_url = NetworkModeConfig.http_root(entry[0], entry[1])
		probe.buf = PackedByteArray([82, 73, 70, 70, 1, 2])
		probe.send_recording()
		_expect_equal(probe.captured_request.get("address"), entry[2], "transcription sends to the selected API endpoint")
		_expect_equal(probe.captured_request.get("body"), PackedByteArray([82, 73, 70, 70, 1, 2]), "transcription preserves the captured WAV bytes")
		var headers: PackedStringArray = probe.captured_request.get("headers", PackedStringArray())
		_expect_equal(headers.has("Content-Type: audio/wav"), true, "transcription declares a WAV body")
		_expect_equal(headers.has("Content-Type: application/json"), false, "transcription removes the JSON content type")
		probe.free()


func _expect_equal(actual, expected, message: String) -> void:
	if actual == expected:
		return
	push_error("%s: expected %s, got %s" % [message, expected, actual])
	failures += 1
