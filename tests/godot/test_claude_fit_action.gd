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
	_expect(shell.overflow.get_popup().is_item_disabled(shell.overflow.get_popup().get_item_index(4)), "empty model disables menu fit")
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
		_expect(shell.buttons.fit.is_visible_in_tree() or shell.overflow.is_visible_in_tree(), "fit has a visible entry point at %d" % width)
		_expect(not shell.overflow.get_popup().is_item_disabled(shell.overflow.get_popup().get_item_index(4)), "populated graph enables menu fit at %d" % width)
		# The headless DisplayServer has no native window size; supply the same
		# logical occupied boundary the desktop frame normally publishes.
		app.space_end = Vector2(width, 900)
		# Use the real menu signal, not a duplicate test implementation.
		shell.overflow.get_popup().id_pressed.emit(4)
		_expect(camera._go_active and camera._go_to_zoom > 0.0 and is_finite(camera._go_to_zoom), "fit schedules a finite camera target at %d" % width)
		var bounds: Rect2 = left.rect.get_global_rect().merge(right.rect.get_global_rect())
		var projected := Rect2((bounds.position - camera._go_to_pos) * camera._go_to_zoom + Vector2(width, 900) * 0.5, bounds.size * camera._go_to_zoom)
		var canvas: Rect2 = geometry.graph_rect(Vector2(width, 900), app.space_begin, app.space_end).grow(-camera.FIT_PADDING)
		_expect(canvas.grow(0.01).encloses(projected), "real fit target encloses both nodes inside the framed canvas at %d" % width)
		_expect(left.position == left_position and right.position == right_position, "fit preserves node positions at %d" % width)

	app.curr_window = "env"
	shell._sync()
	_expect(shell.buttons.fit.disabled and shell.overflow.get_popup().is_item_disabled(shell.overflow.get_popup().get_item_index(4)), "simulation tab disables graph fit")
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
