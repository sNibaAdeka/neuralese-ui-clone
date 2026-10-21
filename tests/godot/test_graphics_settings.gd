extends SceneTree

## Graphics options (msaa / blur / smoothing): the settings model, startup precedence, and that
## every option can be applied at runtime and switched back.

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var Gq := load("res://scripts/graphics_quality.gd")

	# --- presets are just named combinations of the options -------------------------------
	_expect(Gq.preset(Gq.Level.High) == {"msaa": 2, "blur": Gq.Blur.Live, "smoothing": true}, "High = 4x MSAA, Live blur, soft backdrop")
	_expect(Gq.preset(Gq.Level.Medium) == {"msaa": 0, "blur": Gq.Blur.Baked, "smoothing": false}, "Medium = MSAA off, Baked blur")
	_expect(Gq.preset(Gq.Level.Low) == {"msaa": 0, "blur": Gq.Blur.Off, "smoothing": false}, "Low = MSAA off, blur Off")
	for level in [Gq.Level.High, Gq.Level.Medium, Gq.Level.Low]:
		_expect(Gq.matching_level(Gq.preset(level)) == level, "preset %d maps back to its own level" % level)

	# --- sanitize: untrusted saved data ---------------------------------------------------
	_expect(Gq.sanitize({}).is_empty(), "an empty save (the default for a missing key) means nothing is saved")
	_expect(Gq.sanitize("high").is_empty(), "a non-dictionary save is ignored")
	_expect(Gq.sanitize(null).is_empty(), "a null save is ignored")
	var wild: Dictionary = Gq.sanitize({"msaa": 99, "blur": -5, "smoothing": "yes"})
	_expect(wild == {"msaa": 2, "blur": 0, "smoothing": false}, "out-of-range / wrong-typed values are clamped, not trusted")
	_expect(Gq.sanitize({"msaa": 1.0, "blur": 1.0}).msaa == 1, "floats from a stored variant are accepted")
	_expect(Gq.sanitize({"msaa": 1}).blur == Gq.Blur.Live, "a missing blur option falls back to High's")
	_expect(Gq.sanitize({"msaa": 1}).smoothing == false, "a missing smoothing option is off, not assumed on")

	# --- matching_level: presets vs custom mixes -----------------------------------------
	_expect(Gq.matching_level({"msaa": 1, "blur": Gq.Blur.Live, "smoothing": false}) == -1, "2x MSAA + Live blur is Custom")
	_expect(Gq.matching_level({"msaa": 2, "blur": Gq.Blur.Live, "smoothing": false}) == -1, "High without the soft backdrop is Custom")
	_expect(
		Gq.matching_level({"msaa": 0, "blur": Gq.Blur.Baked, "smoothing": true}) == Gq.Level.Medium,
		"smoothing is ignored (not Custom) when blur is not Live"
	)

	# --- startup precedence: launch argument > saved options > GPU level ------------------
	var saved := {"msaa": 1, "blur": Gq.Blur.Baked, "smoothing": false}
	_expect(Gq.startup_settings(PackedStringArray(["--graphics=low"]), saved) == Gq.preset(Gq.Level.Low), "--graphics= beats saved options")
	_expect(Gq.startup_settings(PackedStringArray([]), saved) == saved, "saved options beat the GPU level")
	_expect(Gq.startup_settings(PackedStringArray(["--graphics=bogus"]), saved) == saved, "an unrecognised argument is ignored, saved options still apply")
	_expect(Gq.startup_settings(PackedStringArray([]), {}) == Gq.preset(Gq.auto_level()), "with nothing saved the GPU level is used")
	_expect(Gq.startup_settings(PackedStringArray([]), "junk") == Gq.preset(Gq.auto_level()), "an unusable save falls back to the GPU level")
	_expect(Gq.arg_level(PackedStringArray([])) == -1, "no argument means no override")

	# --- apply_settings is reversible ----------------------------------------------------
	var screen_shader := load("res://shaders/block_screen.gdshader") as Shader
	var live_code := screen_shader.code
	_expect(live_code.contains("BLOCK_SAMPLE_SCREEN_TEXTURE"), "block_screen starts as the live-screen variant")

	Gq.apply_settings(Gq.preset(Gq.Level.Medium))
	_expect(root.msaa_2d == Viewport.MSAA_DISABLED, "Medium turns MSAA off")
	_expect(Gq.bakes_blur(), "Medium bakes the blurred background")
	_expect(not screen_shader.code.contains("BLOCK_SAMPLE_SCREEN_TEXTURE"), "Medium drops the framebuffer-copy shader variant")

	Gq.apply_settings(Gq.preset(Gq.Level.High))
	_expect(root.msaa_2d == Viewport.MSAA_4X, "switching back to High restores 4x MSAA")
	_expect(not Gq.bakes_blur(), "switching back to High stops baking")
	_expect(screen_shader.code == live_code, "switching back to High restores the live-screen shader source exactly")

	Gq.apply_settings(Gq.preset(Gq.Level.Low))
	_expect(not Gq.bakes_blur(), "Low does not bake")
	_expect(not screen_shader.code.contains("BLOCK_SAMPLE_SCREEN_TEXTURE"), "Low also avoids the framebuffer copy")
	Gq.apply_settings(Gq.preset(Gq.Level.High))
	_expect(screen_shader.code == live_code, "Low -> High restores the live-screen shader source exactly")

	Gq.apply_settings({"msaa": 1, "blur": Gq.Blur.Live, "smoothing": true})
	_expect(root.msaa_2d == Viewport.MSAA_2X, "2x MSAA applies")
	_expect(Gq.current().smoothing == true, "current() reports the applied options")

	# A smoothing choice made under Live blur survives a detour through Baked blur.
	Gq.apply_settings({"msaa": 1, "blur": Gq.Blur.Baked, "smoothing": true})
	_expect(Gq.current().smoothing == true, "the remembered smoothing choice is kept while blur is Baked")
	_expect(Gq.matching_level(Gq.current()) == -1, "2x MSAA + Baked blur is Custom")
	Gq.apply_settings(Gq.preset(Gq.Level.High))

	# --- shader / project wiring ----------------------------------------------------------
	var body := FileAccess.get_file_as_string("res://shaders/block_body.gdshaderinc")
	_expect(body.contains("global uniform bool _quality_bg_smoothing"), "block_body declares the smoothing global")
	_expect(body.contains("_quality_bg_smoothing && from_bg"), "smoothing only affects panels that read the bg texture")
	_expect(
		FileAccess.get_file_as_string("res://project.godot").contains("_quality_bg_smoothing={"),
		"project.godot registers the smoothing global (otherwise global_shader_parameter_set no-ops)"
	)

	# --- Settings strings: every language has every entry the UI indexes -----------------
	var strings: Dictionary = (load("res://scripts/settings.gd") as GDScript).get_script_constant_map().get("_GFX_TEXT", {})
	# The app's own language list is the source of truth: adding a language there without graphics
	# strings must fail here, not show up as blank buttons.
	var wheel: Array = root.get_node("/root/glob").lang_wheel
	_expect(wheel.size() >= 3, "the app has its three languages")
	for lang in wheel:
		_expect(strings.has(lang), "Settings has %s graphics strings (every language in glob.lang_wheel needs them)" % lang)
	for lang in strings:
		_expect(wheel.has(lang), "%s graphics strings belong to a language the app has" % lang)
	for lang in ["ru", "kz"]:
		if not strings.has(lang) or not strings.has("en"):
			continue
		# Guard against copy-pasted English: every label and named value must be translated.
		for key in ["title", "preset_l", "aa_l", "blur_l", "smooth_l"]:
			_expect(strings[lang][key] != strings["en"][key], "%s: %s is translated, not English" % [lang, key])
		for key in ["preset", "blur"]:
			for i in strings["en"][key].size():
				_expect(strings[lang][key][i] != strings["en"][key][i], "%s: %s[%d] is translated, not English" % [lang, key, i])
	for lang in ["en", "ru", "kz"]:
		_expect(strings.has(lang), "Settings has %s graphics strings" % lang)
		if not strings.has(lang):
			continue
		var s: Dictionary = strings[lang]
		for key in ["title", "preset_l", "aa_l", "blur_l", "smooth_l"]:
			_expect(s.get(key, "") != "", "%s: %s is not empty" % [lang, key])
		_expect(s.get("preset", []).size() == 4, "%s: 3 presets + Custom" % lang)
		_expect(s.get("aa", []).size() == 3, "%s: 3 anti-aliasing values" % lang)
		_expect(s.get("blur", []).size() == 3, "%s: 3 blur values" % lang)
		_expect(s.get("smooth", []).size() == 2, "%s: 2 smoothing values" % lang)

	if failures.is_empty():
		print("PASS test_graphics_settings")
		quit(0)
	else:
		for f in failures:
			printerr("FAIL: ", f)
		quit(1)


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		failures.append(msg)
