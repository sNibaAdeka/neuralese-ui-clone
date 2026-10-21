extends SceneTree
## Checks the real background's geometry/cache contract. Headless rendering does
## not establish the visual appearance of rounded edges, wash, or grid pixels.

var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var app = root.get_node("glob")
	var old_camera = app.cam
	var old_window: String = app.curr_window
	var old_begin: Vector2 = app.space_begin
	var old_end: Vector2 = app.space_end
	root.content_scale_factor = 1.0
	root.size = Vector2i(1440, 900)
	var camera := Camera2D.new()
	camera.enabled = false
	root.add_child(camera)
	app.cam = camera
	# Defer scene loading until autoload names have registered. No full project or
	# user project data is needed for this background integration fixture.
	var background = load("res://scenes/bg.tscn").instantiate()
	background.register_global = false
	root.add_child(background)
	await process_frame
	var viewport: SubViewport = background.get_node("SubViewport")
	var display: TextureRect = background.get_node("TextureRect")
	var material: ShaderMaterial = background.get_node("SubViewport/bg/ColorRect").material
	_expect(display.material == material, "display and cached background share one frame material")
	_expect(material.get_shader_parameter("panel_radius") == float(preload("res://scripts/claude_design_theme.gd").PANEL_RADIUS), "frame uses shared panel radius")
	background.register_global = true
	app.curr_window = "graph"
	background.activate()
	var source_texture: Texture2D = background.active_texture
	_expect(source_texture == viewport.get_texture(), "shared background retains source viewport texture")
	var cases := [
		[375, Vector2(0, 96), Rect2(13, 96, 349, 804)],
		[768, Vector2(0, 96), Rect2(13, 96, 742, 804)],
		[1024, Vector2(275, 100), Rect2(296, 100, 707, 800)],
		[1440, Vector2(275, 100), Rect2(309, 100, 1097, 800)],
	]
	for test_case in cases:
		var width: int = test_case[0]
		root.size = Vector2i(width, 900)
		await process_frame
		app.space_begin = test_case[1]
		app.space_end = Vector2(width, 900)
		background._on_frame_pre_draw()
		var expected: Rect2 = test_case[2]
		_expect(material.get_shader_parameter("framed_workspace"), "graph framing enabled at %d" % width)
		_expect(_shader_rect(material).is_equal_approx(expected), "frame respects occupied bounds and responsive margins at %d" % width)
		_expect(viewport.size == Vector2i(width, 900), "cached texture retains full viewport coordinates at %d" % width)
		_expect(background.active_texture == source_texture and display.texture == source_texture, "resize preserves shared texture identity at %d" % width)

	var still_signature: Array = background._last_signature.duplicate()
	background._on_frame_pre_draw()
	_expect(background._last_signature == still_signature and background._frames_since_render == 1, "unchanged geometry uses cached background")
	app.space_begin.y += 48.0
	background._on_frame_pre_draw()
	_expect(background._last_signature != still_signature and background._frames_since_render == 0, "header height invalidates background cache with a still camera")
	_expect(is_equal_approx(_shader_rect(material).position.y, 148.0), "frame follows new header edge")
	still_signature = background._last_signature.duplicate()
	app.space_begin.x = 0.0
	background._on_frame_pre_draw()
	_expect(background._last_signature != still_signature, "palette collapse invalidates background cache")
	_expect(is_equal_approx(_shader_rect(material).position.x, 34.0), "collapsed palette releases canvas width")

	var fixed_frame := _shader_rect(material)
	camera.position = Vector2(120, -80)
	camera.offset = Vector2(7, 11)
	camera.zoom = Vector2(0.5, 0.5)
	background._on_frame_pre_draw()
	_expect(_shader_rect(material) == fixed_frame, "camera motion does not move the frame")
	_expect(material.get_shader_parameter("grid_zoom") == 0.5, "grid still follows camera zoom")
	var expected_phase := (camera.position + camera.offset) * camera.zoom * 0.7
	_expect(material.get_shader_parameter("camera_offset") == expected_phase, "grid still follows camera position and offset")
	still_signature = background._last_signature.duplicate()
	camera.offset += Vector2(13, 0)
	background._on_frame_pre_draw()
	_expect(background._last_signature != still_signature, "camera offset alone invalidates cached grid")
	_expect(_shader_rect(material) == fixed_frame, "offset alone leaves workspace frame fixed")

	app.curr_window = "env"
	background._on_frame_pre_draw()
	_expect(not material.get_shader_parameter("framed_workspace"), "other tabs do not inherit graph framing")
	_expect(_shader_rect(material) == Rect2(0, 0, 1440, 900), "other tabs retain full canvas")
	background.register_global = false
	app.curr_window = "graph"
	background._on_frame_pre_draw()
	_expect(not material.get_shader_parameter("framed_workspace"), "independent simulation background is never framed as graph")
	background.register_global = true
	app.space_begin = Vector2(1440, 900)
	background._on_frame_pre_draw()
	_expect(not _shader_rect(material).has_area(), "fully occupied viewport produces no invalid canvas size")
	background.deactivate()
	_expect(not background.visible and viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED, "inactive background stops rendering")
	app.cam = old_camera
	app.curr_window = old_window
	app.space_begin = old_begin
	app.space_end = old_end
	background.queue_free()
	camera.queue_free()
	await process_frame
	await process_frame
	if failures.is_empty():
		print("PASS test_claude_canvas_geometry")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)

func _shader_rect(material: ShaderMaterial) -> Rect2:
	var value: Vector4 = material.get_shader_parameter("workspace_rect")
	return Rect2(value.x, value.y, value.z, value.w)

func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
