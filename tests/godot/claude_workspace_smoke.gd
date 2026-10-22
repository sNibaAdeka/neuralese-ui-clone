extends RefCounted
## Integration/render check using real project actions. No input injection or
## fabricated accuracy: the fixture is the bundled Digits example.
var failures: Array[String] = []
var output := "res://design-check"
var render_scale := 2.0
func run(tree: SceneTree) -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--design-output="): output = arg.trim_prefix("--design-output=")
	DirAccess.make_dir_recursive_absolute(output)
	OS.low_processor_usage_mode = false
	# Exercise logical layout widths independent of this Mac's Retina scale.
	# Production display scaling stays in PlatformInput and is tested separately.
	tree.root.content_scale_factor = render_scale
	tree.root.size = Vector2i(Vector2(1440, 900) * render_scale)
	var app = tree.root.get_node("glob")
	var gm = tree.root.get_node("graphs")
	var interface = tree.root.get_node("ui")
	var shell = app.fg.claude_shell
	await tree.process_frame
	_expect(is_instance_valid(shell), "native shell exists")
	await app.get_loaded_datasets()
	var copy: Dictionary = await app.create_builtin_project_copy("digits", "res://built_in_projects/Digits.scn", "Распознаватель цифр")
	_expect(copy.get("ok", false), "built-in project copied locally")
	if copy.get("ok", false):
		var loaded = await app.load_scene(str(copy.project_id))
		_expect(loaded == true and app.loaded_project_once, "real project opened")
	await tree.create_timer(0.5).timeout
	_expect(gm._graphs.size() > 0, "real graph nodes loaded")
	var original_count: int = gm._graphs.size()
	var added = gm.create_graph_at_screen_position(&"layer", Vector2(720, 400))
	await tree.create_timer(0.1).timeout
	_expect(is_instance_valid(added) and gm._graphs.size() == original_count + 1, "palette action creates a real graph node")
	app.fg._on_undo_pressed()
	await tree.create_timer(0.1).timeout
	_expect(gm._graphs.size() == original_count, "undo removes created node")
	app.fg._on_redo_pressed()
	await tree.create_timer(0.1).timeout
	_expect(gm._graphs.size() == original_count + 1, "redo restores created node")
	app.fg._on_undo_pressed()
	await tree.create_timer(0.1).timeout
	# The reference view is an explicit layout action on the disposable built-in copy.
	# Production project loading continues to preserve authored coordinates.
	shell.overflow.get_popup().id_pressed.emit(7)
	await tree.create_timer(0.8).timeout
	for node in gm._graphs.values():
		if String(node.server_typename).to_lower().contains("neuron"):
			node.select()
			break
	# Exercise the real drawing buffer on this disposable project. These strokes
	# remain input tensor data; no predictions or training metrics are fabricated.
	for node in gm._graphs.values():
		if node.is_input and node.has_node("TextureRect"):
			var drawing = node.get_node("TextureRect")
			if drawing.has_method("_draw_segment"):
				drawing._draw_segment(Vector2(6, 6), Vector2(21, 6), 3.0)
				drawing._draw_segment(Vector2(21, 6), Vector2(10, 24), 3.0)
				_expect(node.get_raw_values().max() > 0.0, "drawing produces real nonzero model input")
	await tree.create_timer(0.2).timeout
	await _shot(tree, "graph-1440.png")
	for node in gm._graphs.values():
		if node.get_script() == load("res://scripts/train_input.gd"):
			node._advanced_toggle.pressed.emit()
			await tree.create_timer(0.5).timeout
			_expect(node.optimizer.visible and node.lr.visible, "training settings expand through the real button")
			await _shot(tree, "training-settings-1440.png")
			node._advanced_toggle.pressed.emit()
			await tree.create_timer(0.5).timeout
			_expect(not node.optimizer.visible and not node.lr.visible, "training settings collapse without losing controls")
			break
	await tree.create_timer(0.8).timeout
	shell.axon_panel.open_panel()
	await tree.create_timer(0.8).timeout
	shell.axon_panel._show_explanation()
	await _shot(tree, "axon-reaction.png")
	await tree.create_timer(0.8).timeout
	_expect(shell.axon_panel.mascot.frame_index == 0, "mascot reaction stops at rest")
	shell.axon_panel.explanation.hide()
	shell.axon_panel.close_panel()
	await tree.create_timer(0.3).timeout
	shell._fit_model()
	await _settle_fit(tree, app, gm)
	await _shot(tree, "graph-1440.png")
	for item in [[1280,900],[1180,900],[1024,768],[768,900],[375,812]]:
		tree.root.size = Vector2i(Vector2(item[0],item[1]) * render_scale)
		await tree.create_timer(0.25).timeout
		_expect(is_equal_approx(shell.get_viewport_rect().size.x, float(item[0])), "logical viewport width " + str(item[0]))
		_expect(shell.get_combined_minimum_size().x <= float(item[0])+1, "shell fits width " + str(item[0]))
		_expect(shell.get_global_rect().end.y <= app.space_begin.y + 1, "workspace clears shell at " + str(item[0]))
		# Explicit Fit demonstrates the available whole-model action at each size.
		shell._fit_model()
		await _settle_fit(tree, app, gm)
		await _shot(tree, "graph-" + str(item[0]) + ".png")
		if int(item[0]) == 375:
			shell.overflow.grab_focus()
			for pressed in [true, false]:
				var key := InputEventKey.new()
				key.keycode = KEY_ENTER; key.pressed = pressed
				tree.root.push_input(key, true)
			await tree.process_frame
			_expect(shell.overflow.get_popup().visible, "keyboard opens compact actions menu")
			await _shot(tree, "actions-menu-375.png")
			var escape := InputEventKey.new()
			escape.keycode = KEY_ESCAPE; escape.pressed = true
			# Route to the focused popup window through the engine input dispatcher.
			Input.parse_input_event(escape)
			await tree.process_frame
			await tree.process_frame
			_expect(not shell.overflow.get_popup().visible, "Escape closes compact actions menu")
			shell.axon_panel.open_panel()
			await tree.create_timer(0.2).timeout
			_expect(shell.axon_panel.is_overlay_open(), "mobile Axon opens explicitly")
			_expect(not app.base_node.get_node("WIN_GRAPH/NodePalette").visible, "mobile Axon input is not covered by palette")
			await _shot(tree, "axon-375.png")
			shell.axon_panel.close_panel()
	tree.root.size = Vector2i(Vector2(1440,900) * render_scale)
	shell._navigate("ds")
	await tree.create_timer(0.3).timeout
	_expect(app.curr_window == "ds", "dataset navigation routes to real window")
	await _shot(tree, "datasets-empty-1440.png")
	var empty_canvas = app.tree_windows["ds"]._canvas
	empty_canvas.render(null, [])
	tree.root.size = Vector2i(Vector2(375,812) * render_scale)
	await tree.create_timer(0.2).timeout
	_expect(empty_canvas._empty_state.visible, "empty workspace guidance visible")
	_expect(app.tree_windows["ds"]._root.position.y >= app.space_begin.y, "dataset header clears reflowed navigation")
	_expect(empty_canvas._empty_state.get_combined_minimum_size().x <= empty_canvas.size.x, "empty guidance wraps at 375px")
	await _shot(tree, "datasets-empty-375.png")
	tree.root.size = Vector2i(Vector2(1440,900) * render_scale)
	await tree.create_timer(0.2).timeout
	# Import a clearly identified local CSV fixture through the production parser,
	# select it through the production list, edit a real cell, and persist it.
	var csv_path: String = output.path_join("dataset-check.csv")
	var csv := FileAccess.open(csv_path, FileAccess.WRITE)
	csv.store_string("distance,speed,brake\n1,2,0\n3,4,1\n5,6,0\n7,8,1\n")
	csv.close()
	var dataset_name := "Проверка CSV"
	var dataset_window = app.tree_windows["ds"]
	await dataset_window.import_paths([csv_path])
	_expect(dataset_window._staged.size() == 1, "CSV parsed into one staged document")
	if dataset_window._staged.is_empty():
		tree.quit(1)
		return
	dataset_window._staged[0].data.name = dataset_name
	dataset_window._apply_import()
	_expect(dataset_window.document.row_count() == 4, "CSV imports four real rows")
	dataset_window.document.set_value(0, 0, 9.0)
	await dataset_window.flush_pending_changes()
	_expect(float(dataset_window.document.value(0, 0)) == 9.0, "document edits actual numeric value")
	dataset_window._set_view("table")
	await _shot(tree, "datasets-table-1440.png")
	dataset_window._set_view("plot")
	_expect(dataset_window._canvas._points.size() == 4, "plot uses the four imported rows")
	await _shot(tree, "datasets-plot-1440.png")
	# Wide table keeps target columns reachable through normal horizontal browsing.
	var wide_path: String = output.path_join("twelve-columns.csv")
	var wide_file := FileAccess.open(wide_path, FileAccess.WRITE)
	wide_file.store_string("a,b,c,d,e,f,g,h,i,j,k,target\n101,102,103,104,105,106,107,108,109,110,111,112\n")
	wide_file.close()
	await dataset_window.import_paths([wide_path])
	dataset_window._apply_import()
	dataset_window._set_view("table")
	_expect(dataset_window.document.column_count() == 12, "all twelve imported columns retained")
	await _shot(tree, "table-twelve-columns-left.png")
	var pan_event := InputEventPanGesture.new()
	pan_event.delta = Vector2(55, 0)
	dataset_window._canvas._gui_input(pan_event)
	await _shot(tree, "table-twelve-columns-target.png")
	_expect(dataset_window._canvas.pan.x < -1000, "trackpad reaches target columns without zooming")
	var ambiguous_path: String = output.path_join("categorical.csv")
	var ambiguous_file := FileAccess.open(ambiguous_path, FileAccess.WRITE)
	ambiguous_file.store_string("red,small,yes\nblue,large,no\n")
	ambiguous_file.close()
	await dataset_window.import_paths([ambiguous_path])
	_expect(dataset_window._csv_needs_header_choice(), "ambiguous CSV visibly requires a first-row choice")
	await _shot(tree, "csv-preview-1440.png")
	tree.root.size = Vector2i(Vector2(375,812) * render_scale)
	await tree.create_timer(0.2).timeout
	await _shot(tree, "csv-preview-375.png")
	dataset_window._set_csv_option(dataset_window._csv_previews[0], "header", "absent")
	await tree.process_frame
	await tree.process_frame
	_expect(tree.root.gui_get_focus_owner() is OptionButton, "CSV selection preserves keyboard focus")
	dataset_window._apply_import()
	_expect(dataset_window.document.row_count() == 2, "headerless categorical CSV preserves first example")
	tree.root.size = Vector2i(Vector2(1440,900) * render_scale)
	await tree.create_timer(0.2).timeout
	dataset_window.activate_tool("car")
	dataset_window.document.generate(12, 42)
	_expect(dataset_window.document.row_count() == 12, "seeded car samples generated")
	dataset_window._inspector_requested = false
	dataset_window._layout()
	await _shot(tree, "datasets-1440.png")

	shell._navigate("env")
	await tree.create_timer(0.3).timeout
	_expect(app.curr_window == "env", "simulation navigation routes to real window")
	var editor = app.tree_windows["env"].editor
	editor.runtime.play()
	await tree.create_timer(0.1).timeout
	_expect(editor.runtime.current_state() == &"running", "simulation physics runs")
	editor._on_pause_requested()
	_expect(editor.runtime.current_state() == &"paused", "simulation pause action pauses runtime")
	editor.runtime.stop()
	_expect(editor.runtime.current_state() == &"stopped", "simulation runtime stops")
	await _shot(tree, "simulation-1440.png")
	for item in [[1024,768],[768,900],[375,812]]:
		tree.root.size = Vector2i(Vector2(item[0],item[1]) * render_scale)
		for window in ["ds", "env"]:
			shell._navigate(window)
			if window == "ds":
				dataset_window._inspector_requested = false
				dataset_window._layout()
			await tree.create_timer(0.3).timeout
			await _shot(tree, window + "-" + str(item[0]) + ".png")
	tree.root.size = Vector2i(Vector2(1440,900) * render_scale)
	shell._navigate("graph")
	var requested_name := "Digits · сохранённая проверка"
	var expected_name: String = requested_name.substr(0, shell.title.max_length)
	_expect(shell.title.max_length == app.fg.get_node("Label").max_length, "visible name uses canonical length limit")
	shell._rename(requested_name)
	_expect(shell.title.text == expected_name, "visible title shows the accepted name")
	await shell._save()
	_expect(shell.save_message == "Сохранено на этом компьютере", "save reports actual success")
	var projects = await app.request_projects()
	_expect(projects.has(str(app.get_project_id())), "saved project is in local project list")
	var saved_id := str(app.get_project_id())
	var saved_node_count: int = gm._graphs.size()
	var previous_plot_templates: Array = []
	for graph in gm._graphs.values():
		_collect_plot_templates(graph, previous_plot_templates)
	_expect(not previous_plot_templates.is_empty(), "loaded graph owns reusable training plot templates")
	await app.load_scene(saved_id)
	for template in previous_plot_templates:
		_expect(not is_instance_valid(template), "project reload releases the old training plot template")
	_expect(app.fg.get_scene_name() == expected_name, "saved title survives reload")
	_expect(gm._graphs.size() == saved_node_count, "saved real graph survives reload")
	_expect(app.ds_dump.has(dataset_name), "imported CSV remains in saved project")
	var saved_dataset: Dictionary = app.get_dataset_at(dataset_name)
	var restored_document = load("res://scripts/data_workspace/document.gd").new()
	restored_document.attach(saved_dataset)
	_expect(restored_document.row_count() == 4 and float(restored_document.value(0, 0)) == 9.0, "edited CSV cell survives project save and reload")
	var exported: PackedByteArray = await app.export_project()
	_expect(not exported.is_empty(), "real project export contains data")
	interface.splash("model_export", null)
	await tree.create_timer(0.4).timeout
	var export_dialog = interface.get_splash("model_export")
	export_dialog._on_linux_released()
	_expect(export_dialog.type == "linux", "export format action still selects Linux")
	export_dialog._on_onnx_released()
	_expect(export_dialog.type == "onnx", "export format action still selects ONNX")
	await _shot(tree, "export-1440.png")
	tree.root.size = Vector2i(Vector2(375,812) * render_scale)
	await tree.create_timer(0.3).timeout
	var export_panel: Control = interface.get_splash("model_export").get_node("ColorRect")
	_expect(Rect2(Vector2.ZERO, Vector2(375,812)).encloses(export_panel.get_global_rect()), "export dialog fits compact viewport")
	await _shot(tree, "export-375.png")
	interface.hide_splash()
	if failures.is_empty(): print("PASS claude_workspace_smoke: graph, responsive shell, datasets, simulation, save, export")
	else:
		for failure in failures: push_error("CLAUDE_CHECK: " + failure)
	tree.quit(0 if failures.is_empty() else 1)
func _shot(tree: SceneTree, filename: String) -> void:
	await tree.process_frame
	# Idle rendering may legitimately skip a frame after a resize. Force the
	# test capture's frame instead of waiting for a signal that may not fire.
	RenderingServer.force_draw(false)
	var err := tree.root.get_texture().get_image().save_png(output.path_join(filename))
	_expect(err == OK, "screenshot saved: " + filename)
func _expect(condition: bool, message: String) -> void:
	print("CHECK ", message, ": ", condition)
	if not condition: failures.append(message)


func _collect_plot_templates(node: Node, output_templates: Array) -> void:
	if node is MovingAnalytics and is_instance_valid(node.line):
		output_templates.append(node.line)
	for child in node.get_children():
		_collect_plot_templates(child, output_templates)

func _settle_fit(tree: SceneTree, app, gm) -> void:
	# Fit animates for 0.55s and then eases the remaining position/zoom. Capture
	# the final real camera state rather than mistaking an intermediate frame
	# for clipped layout. A deadline also catches a stalled transition.
	var camera = app.main_cam
	for step in 60:
		await tree.create_timer(0.05).timeout
		if not camera._go_active and absf(camera.zoom.x - camera.target_zoom) < 0.0001 and camera.position.distance_to(camera.target_position) < 0.2:
			break
	var bounds: Rect2 = camera._bbox_of(gm._graphs.values())
	var projected := Rect2(camera.get_canvas_transform() * bounds.position, bounds.size * camera.zoom)
	var geometry = load("res://scripts/claude_workspace_geometry.gd")
	var canvas: Rect2 = geometry.graph_rect(camera.get_viewport_rect().size, app.space_begin, app.space_end)
	_expect(canvas.grow(2).encloses(projected), "settled native Fit contains every graph card at " + str(int(camera.get_viewport_rect().size.x)))
