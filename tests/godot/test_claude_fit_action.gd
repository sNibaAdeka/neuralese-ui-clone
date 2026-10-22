extends SceneTree
## Headless action/layout integration. This does not establish visual quality.

var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var app = root.get_node("glob")
	app.tree = self
	root.content_scale_factor = 1.0
	root.size = Vector2i(1440, 900)
	var project = load("res://scenes/project.tscn").instantiate()
	root.add_child(project)
	await process_frame
	await process_frame
	var gm = root.get_node("graphs")
	var shell = app.fg.claude_shell
	var camera = app.main_cam
	var geometry = load("res://scripts/claude_workspace_geometry.gd")
	app.curr_window = "graph"
	shell._sync()
	_expect(shell.buttons.fit.disabled, "empty model disables toolbar fit")
	var menu: PopupMenu = shell.overflow.get_popup()
	var fit_index := menu.get_item_index(4)
	_expect(fit_index == -1 or menu.is_item_disabled(fit_index), "empty model has no enabled menu fit")
	# Hidden primary actions retain their IDs and disabled state in the fallback.
	shell.buttons.fit.hide()
	shell._sync_overflow_menu()
	fit_index = menu.get_item_index(4)
	_expect(fit_index >= 0 and menu.is_item_disabled(fit_index), "empty model disables hidden fit fallback")
	shell.buttons.fit.show()
	shell._sync_overflow_menu()
	var original_target: Vector2 = camera.target_position
	shell._fit_model()
	_expect(camera.target_position == original_target, "empty model fit does not move camera")

	# The factory defaults to NONE: no undo entry or autosave for test fixtures.
	var left = gm.get_graph(&"layer")
	var right = gm.get_graph(&"layer")
	left.position = Vector2(-400, -180)
	right.position = Vector2(1000, 600)
	await process_frame
	var left_position: Vector2 = left.position
	var right_position: Vector2 = right.position
	for width in [375, 768, 1024, 1440, 1920]:
		root.size = Vector2i(width, 900)
		await process_frame
		await process_frame
		await process_frame
		shell._sync()
		_expect(not shell.buttons.fit.disabled, "populated graph enables fit at %d" % width)
		_expect(shell.get_combined_minimum_size().x <= width + 1, "headless shell minimum width fits %d" % width)
		fit_index = menu.get_item_index(4)
		_expect(shell.buttons.fit.is_visible_in_tree() or (shell.overflow.is_visible_in_tree() and fit_index >= 0), "fit has a real visible entry point at %d" % width)
		if shell.buttons.fit.is_visible_in_tree():
			_expect(fit_index == -1, "visible fit is not duplicated in overflow at %d" % width)
		else:
			_expect(fit_index >= 0 and not menu.is_item_disabled(fit_index), "hidden fit has an enabled fallback at %d" % width)
		# The headless DisplayServer has no native window size; supply the same
		# logical occupied boundary the desktop frame normally publishes.
		app.space_end = Vector2(width, 900)
		# Activate the actual visible route instead of emitting an absent menu ID.
		if shell.buttons.fit.is_visible_in_tree(): shell.buttons.fit.pressed.emit()
		else: menu.id_pressed.emit(4)
		_expect(camera._go_active and camera._go_to_zoom > 0.0 and is_finite(camera._go_to_zoom), "fit schedules a finite camera target at %d" % width)
		var bounds: Rect2 = left.rect.get_global_rect().merge(right.rect.get_global_rect())
		var projected := Rect2((bounds.position - camera._go_to_pos) * camera._go_to_zoom + Vector2(width, 900) * 0.5, bounds.size * camera._go_to_zoom)
		var canvas: Rect2 = geometry.graph_rect(Vector2(width, 900), app.space_begin, app.space_end).grow(-camera.FIT_PADDING)
		_expect(canvas.grow(0.01).encloses(projected), "real fit target encloses both nodes inside the framed canvas at %d" % width)
		_expect(left.position == left_position and right.position == right_position, "fit preserves node positions at %d" % width)
		# The same production command must still work if responsive layout hides it.
		var direct_fit_position: Vector2 = camera._go_to_pos
		var direct_fit_zoom: float = camera._go_to_zoom
		shell.buttons.fit.hide()
		shell._sync_overflow_menu()
		fit_index = menu.get_item_index(4)
		_expect(fit_index >= 0 and not menu.is_item_disabled(fit_index), "populated model enables hidden fit fallback at %d" % width)
		menu.id_pressed.emit(4)
		_expect(camera._go_to_pos.is_equal_approx(direct_fit_position) and is_equal_approx(camera._go_to_zoom, direct_fit_zoom), "menu fallback computes the same real fit target at %d" % width)
		shell.buttons.fit.show()
		shell._sync_overflow_menu()

	await _test_real_wide_builtin(project, app, gm, shell, camera, geometry)
	app.curr_window = "env"
	shell._sync()
	await process_frame
	await process_frame
	_expect(shell.buttons.fit.disabled and not shell.buttons.fit.is_visible_in_tree(), "simulation tab hides and disables graph fit")
	_expect(menu.get_item_index(4) == -1, "simulation menu omits irrelevant graph fit")
	original_target = camera.target_position
	shell._fit_model()
	_expect(camera.target_position == original_target, "graph fit cannot move the simulation camera")
	app.curr_window = "graph"
	project.queue_free()
	await process_frame
	await process_frame
	if failures.is_empty():
		print("PASS test_claude_fit_action")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)

func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

func _test_real_wide_builtin(project, app, gm, shell, camera, geometry) -> void:
	# Preserve the actual legacy authored positions: Fit must also work for
	# existing projects, without relying on the new-copy gallery arrangement.
	if not is_instance_valid(app.splines_layer):
		app.splines_layer = CanvasLayer.new()
		app.top_splines_layer = CanvasLayer.new()
		project.get_node("WIN_GRAPH").add_child(app.splines_layer)
		project.get_node("WIN_GRAPH").add_child(app.top_splines_layer)
	await gm.delete_all()
	var raw: Variant = app._read_var_abs("res://built_in_projects/Digits.scn")
	var saved: Dictionary = bytes_to_var(raw)
	_expect(await gm.load_graph(saved.graphs, saved.get("registry", {}).get("subgraph_registry", {})), "real Digits graph loads for narrow Fit regression")
	var positions := {}
	for node in gm._graphs.values(): positions[node.graph_id] = node.position
	_expect(positions.size() == 11, "narrow Fit fixture exercises all 11 real Digits nodes")
	for width in [375, 768]:
		root.size = Vector2i(width, 900)
		for frame in 6: await process_frame
		shell._sync()
		app.space_end = Vector2(width, 900)
		camera.restore_view(1.0, Vector2.ZERO)
		shell._fit_model()
		var bounds: Rect2 = camera._bbox_of(gm._graphs.values())
		var canvas: Rect2 = geometry.graph_rect(Vector2(width, 900), app.space_begin, app.space_end).grow(-camera.FIT_PADDING)
		var required_zoom: float = minf(canvas.size.x / bounds.size.x, canvas.size.y / bounds.size.y)
		print("FIT_REAL_DIGITS width=", width, " bounds=", bounds, " canvas=", canvas, " required_zoom=", required_zoom, " target_zoom=", camera._go_to_zoom)
		var projected := Rect2((bounds.position - camera._go_to_pos) * camera._go_to_zoom + Vector2(width, 900) * 0.5, bounds.size * camera._go_to_zoom)
		_expect(canvas.grow(0.01).encloses(projected), "Fit encloses all 11 real Digits nodes at %d without moving nodes" % width)
		_expect(camera._valid_zoom(camera._go_to_zoom) <= required_zoom + 0.000001, "frame validation preserves the real narrow fitted zoom")
		# Advance the real smooth transition deterministically. A capture at
		# 0.4s is still inside its 0.55s emphasis, before final Fit.
		var was_processing: bool = camera.is_processing()
		camera.set_process(false)
		for frame in 144: camera._process(1.0 / 60.0)
		var rendered := Rect2((bounds.position - camera.position) * camera.zoom.x + Vector2(width, 900) * 0.5, bounds.size * camera.zoom.x)
		_expect(canvas.grow(0.01).encloses(rendered), "settled production camera encloses all 11 Digits nodes at %d" % width)
		camera.set_process(was_processing)
		for node in gm._graphs.values():
			_expect(node.position == positions[node.graph_id], "real Digits Fit preserves every authored coordinate")
