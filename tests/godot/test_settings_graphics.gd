extends Node

## The Graphics section of the Settings dialog: buttons cycle the options through their real
## `released` signal, apply them immediately, persist them, and the dialog is big enough to
## hold the section. The user's saved value is restored afterwards.

var failures: Array[String] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	for i in 20:
		await get_tree().process_frame
	var key: String = GraphicsQualityConfig.SAVE_KEY
	var saved_before = glob.get_var(key, {})
	var applied_before: Dictionary = glob.GRAPHICS_SETTINGS.duplicate()
	GraphicsQualityConfig.apply_settings(GraphicsQualityConfig.preset(GraphicsQualityConfig.Level.High))
	glob.GRAPHICS_SETTINGS = GraphicsQualityConfig.preset(GraphicsQualityConfig.Level.High)

	var menu = ui.splash("settings", null)
	_expect(menu != null, "the settings dialog opens")
	if menu != null:
		for i in 10:
			await get_tree().process_frame
		await _check(menu, key)
		await _check_languages(menu)
		menu.queue_free()

	# (language check runs on its own instance state below, before everything is restored)
	# Leave the machine exactly as found: nothing saved stays nothing saved.
	GraphicsQualityConfig.apply_settings(applied_before)
	glob.GRAPHICS_SETTINGS = applied_before
	glob.set_var(key, saved_before)

	if failures.is_empty():
		print("PASS test_settings_graphics")
		get_tree().quit(0)
	else:
		for f in failures:
			printerr("FAIL: ", f)
		get_tree().quit(1)


func _check(menu, key: String) -> void:
	var b: Dictionary = menu._gfx_buttons
	var Gq := GraphicsQualityConfig

	# Layout: the section sits inside the dialog, under the role content.
	var box: Control = menu.get_node("ColorRect")
	var section: Control = menu.get_node("ColorRect/graphics")
	_expect(section.position.y + section.size.y <= box.size.y + 0.5, "the Graphics section fits inside the dialog")
	_expect(box.size.y >= 259.0 + menu.GRAPHICS_H - 0.5, "the dialog grew by the section's height")

	# It opens showing the current state (High).
	_expect(b.preset.text == menu._GFX_TEXT[glob.get_lang()].preset[0], "shows the High preset")

	# Anti-aliasing cycles 4x -> Off -> 2x -> 4x, applies live and is saved.
	b.aa.released.emit()
	await get_tree().process_frame
	_expect(get_viewport().msaa_2d == Viewport.MSAA_DISABLED, "pressing anti-aliasing applies immediately (4x -> Off)")
	_expect(Gq.sanitize(glob.get_var(key, {})).get("msaa", -1) == 0, "the choice is saved")
	b.aa.released.emit()
	await get_tree().process_frame
	_expect(get_viewport().msaa_2d == Viewport.MSAA_2X, "Off -> 2x")
	_expect(b.preset.text == menu._GFX_TEXT[glob.get_lang()].preset[3], "a mixed set shows Custom")
	b.aa.released.emit()
	await get_tree().process_frame
	_expect(get_viewport().msaa_2d == Viewport.MSAA_4X, "2x -> 4x")
	_expect(b.preset.text == menu._GFX_TEXT[glob.get_lang()].preset[0], "back to the High preset")

	# Soft backdrop (part of High) toggles under Full blur.
	_expect(glob.GRAPHICS_SETTINGS.smoothing == true, "High has the soft backdrop on")
	b.smooth.released.emit()
	await get_tree().process_frame
	_expect(glob.GRAPHICS_SETTINGS.smoothing == false, "Soft backdrop turns off under Full blur")
	_expect(b.preset.text == menu._GFX_TEXT[glob.get_lang()].preset[3], "High without it shows Custom")
	b.smooth.released.emit()
	await get_tree().process_frame
	_expect(glob.GRAPHICS_SETTINGS.smoothing == true, "and back on")

	# Panel blur cycles Full -> Fast -> Off -> Full; Fast bakes; Soft backdrop is inert off Full.
	b.blur.released.emit()
	await get_tree().process_frame
	_expect(Gq.bakes_blur(), "Fast blur bakes the background")
	b.smooth.released.emit()
	await get_tree().process_frame
	_expect(glob.GRAPHICS_SETTINGS.smoothing == true, "Soft backdrop does nothing while blur is not Full (the choice is kept)")
	b.blur.released.emit()
	await get_tree().process_frame
	_expect(not Gq.bakes_blur() and glob.GRAPHICS_SETTINGS.blur == Gq.Blur.Off, "blur Off does not bake")
	b.blur.released.emit()
	await get_tree().process_frame
	_expect(glob.GRAPHICS_SETTINGS.blur == Gq.Blur.Live, "Off -> Full")

	# Quality presets cycle High -> Medium -> Low -> High.
	b.preset.released.emit()
	await get_tree().process_frame
	_expect(Gq.matching_level(glob.GRAPHICS_SETTINGS) == Gq.Level.Medium, "High -> Medium")
	_expect(get_viewport().msaa_2d == Viewport.MSAA_DISABLED and Gq.bakes_blur(), "Medium applies MSAA off + baked blur")
	b.preset.released.emit()
	await get_tree().process_frame
	_expect(Gq.matching_level(glob.GRAPHICS_SETTINGS) == Gq.Level.Low, "Medium -> Low")
	b.preset.released.emit()
	await get_tree().process_frame
	_expect(Gq.matching_level(glob.GRAPHICS_SETTINGS) == Gq.Level.High, "Low -> High")
	_expect(get_viewport().msaa_2d == Viewport.MSAA_4X and not Gq.bakes_blur(), "High is fully restored")


## The section follows the language while the dialog is open, in every language the app has.
func _check_languages(menu) -> void:
	var original_lang: String = glob.curr_lang
	var options: Dictionary = GraphicsQualityConfig.sanitize(glob.GRAPHICS_SETTINGS)
	var level := GraphicsQualityConfig.matching_level(options)
	for lang in glob.lang_wheel:
		glob.curr_lang = lang
		glob.language_changed.emit()
		await get_tree().process_frame
		var s: Dictionary = menu._GFX_TEXT[lang]
		_expect(menu._gfx_title.text == s.title, "%s: the section title is localized" % lang)
		_expect(menu._gfx_labels.preset.text == s.preset_l, "%s: the Quality label is localized" % lang)
		_expect(menu._gfx_labels.aa.text == s.aa_l, "%s: the Anti-aliasing label is localized" % lang)
		_expect(menu._gfx_labels.blur.text == s.blur_l, "%s: the Panel blur label is localized" % lang)
		_expect(menu._gfx_labels.smooth.text == s.smooth_l, "%s: the Soft backdrop label is localized" % lang)
		_expect(menu._gfx_buttons.preset.text == s.preset[level if level >= 0 else 3], "%s: the Quality value is localized" % lang)
		_expect(menu._gfx_buttons.aa.text == s.aa[int(options.msaa)], "%s: the Anti-aliasing value is localized" % lang)
		_expect(menu._gfx_buttons.blur.text == s.blur[int(options.blur)], "%s: the Panel blur value is localized" % lang)
	glob.curr_lang = original_lang
	glob.language_changed.emit()
	await get_tree().process_frame


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		failures.append(msg)
