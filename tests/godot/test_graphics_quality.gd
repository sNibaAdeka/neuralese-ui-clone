extends SceneTree

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var Gq := load("res://scripts/graphics_quality.gd")
	_expect(Gq.resolve(PackedStringArray(["--graphics=low"])) == Gq.Level.Low, "--graphics=low selects Low")
	_expect(Gq.resolve(PackedStringArray(["--graphics=medium"])) == Gq.Level.Medium, "--graphics=medium selects Medium")
	_expect(Gq.resolve(PackedStringArray(["--graphics=high"])) == Gq.Level.High, "--graphics=high selects High even on weak GPUs")
	_expect(Gq.resolve(PackedStringArray([])) == Gq.auto_level(), "no argument falls back to the GPU-derived level")

	# PERF regression guard: declaring a hint_screen_texture sampler makes the engine copy the
	# framebuffer for every draw of the material, so the default glass shaders must not have one.
	for path in ["res://shaders/block.gdshader", "res://shaders/block_body.gdshaderinc", "res://shaders/fork.gdshader"]:
		var code := FileAccess.get_file_as_string(path)
		var live_lines := PackedStringArray()
		for line in code.split("\n"):
			if line.contains("hint_screen_texture") and not line.strip_edges().begins_with("//"):
				live_lines.append(line)
		# block_body only declares it behind BLOCK_SAMPLE_SCREEN_TEXTURE (opt-in via block_screen).
		var allowed := 1 if path.ends_with("block_body.gdshaderinc") else 0
		_expect(live_lines.size() == allowed, "%s must not unconditionally declare hint_screen_texture" % path)
	_expect(
		FileAccess.get_file_as_string("res://shaders/block_screen.gdshader").contains("#define BLOCK_SAMPLE_SCREEN_TEXTURE"),
		"block_screen.gdshader is the opt-in live-screen variant"
	)

	# Medium/Low swap the live-screen shader for the bg-only source (no framebuffer copy).
	Gq.apply(Gq.Level.Medium)
	_expect(Gq.bakes_blur(), "Medium bakes the blurred background")
	var screen_shader := load("res://shaders/block_screen.gdshader") as Shader
	_expect(not screen_shader.code.contains("BLOCK_SAMPLE_SCREEN_TEXTURE"), "Medium drops the screen-copy shader variant")
	Gq.apply(Gq.Level.Low)
	_expect(not Gq.bakes_blur(), "Low does not bake blur")

	if failures.is_empty():
		print("PASS test_graphics_quality")
		quit(0)
	else:
		for f in failures:
			printerr("FAIL: ", f)
		quit(1)


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		failures.append(msg)
