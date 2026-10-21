extends SceneTree
## Native control/state checks only; this is not a rendered visual review.

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
	await _settle()
	var shell = app.fg.claude_shell
	var geometry = load("res://scripts/claude_workspace_geometry.gd")
	var catalog = load("res://scripts/node_palette_catalog.gd")
	var drop = load("res://scripts/node_palette_drop_surface.gd").new()
	root.add_child(drop)
	drop.set_drag_active(true)
	var received: Array = []
	drop.node_type_dropped.connect(func(type_id: StringName, point: Vector2): received.append([type_id, point]))
	var old_name: String = shell.host.get_scene_name()
	var name_field: LineEdit = shell.host.get_node("Label")
	name_field.text = "Очень длинное название проекта для проверки узкого окна"
	app.loaded_project_once = true
	app.curr_window = "graph"
	for width in [320, 375, 768, 1024, 1280, 1440]:
		root.size = Vector2i(width, 900)
		shell.save_message = ""
		shell._sync()
		await _settle()
		var compact: bool = shell._compact
		var idle_height: float = shell.host.size.y
		print("COMPACT_GEOMETRY width=%d idle_header=%.0f" % [width, idle_height])
		_expect(shell.get_combined_minimum_size().x <= width, "long project name must fit width %d" % width)
		_expect(shell.second.visible == compact, "compact tabs use their own row at %d" % width)
		if not compact:
			_expect(idle_height <= 64.0, "compact white toolbar releases desktop canvas space")
			_expect(shell.buttons.save.visible, "desktop save remains directly accessible")
		if compact:
			_expect(idle_height <= 120.0 and not shell.status_row.visible, "compact idle header has only two rows at %d" % width)
		for control in [shell.projects, shell.buttons.fit, shell.buttons.save, shell.buttons.axon, shell.overflow] + shell.navigation.values():
			_expect(control.is_visible_in_tree(), "primary control remains visible at %d: %s" % [width, control.text])
			_expect(control.size.x >= 44.0 and control.size.y >= 44.0, "primary hit rectangle is at least 44px at %d: %s" % [width, control.text])
			var rect: Rect2 = control.get_global_rect()
			_expect(rect.position.x >= 0 and rect.end.x <= width + 1, "primary control stays within viewport at %d: %s" % [width, control.text])
		var menu: PopupMenu = shell.overflow.get_popup()
		for id in range(8):
			_expect(menu.get_item_index(id) >= 0 and not menu.is_item_separator(menu.get_item_index(id)), "secondary command ID %d survives grouping" % id)
		_expect(menu.get_item_index(2) > 2 and menu.get_item_index(7) > 7, "secondary commands have visual groups")
		for control in [shell.projects, shell.buttons.fit, shell.buttons.save, shell.buttons.axon, shell.overflow] + shell.navigation.values():
			_expect(control.focus_mode == Control.FOCUS_ALL, "toolbar control supports keyboard focus")
			var focus: StyleBoxFlat = control.get_theme_stylebox("focus")
			_expect(focus.border_width_left > 0, "toolbar control has a visible focus outline")
		var primary := [shell.projects, shell.buttons.fit, shell.buttons.save, shell.buttons.axon, shell.overflow]
		for index in range(primary.size() - 1):
			var current: Rect2 = primary[index].get_global_rect()
			var following: Rect2 = primary[index + 1].get_global_rect()
			_expect(current.end.x <= following.position.x, "primary actions do not overlap at %d" % width)
			_expect(is_equal_approx(current.position.y, following.position.y) and is_equal_approx(current.size.y, following.size.y), "primary actions share height and baseline at %d" % width)
		var active: StyleBoxFlat = shell.navigation.graph.get_theme_stylebox("pressed")
		_expect(active.corner_radius_top_left == 0 and active.border_width_bottom == 2, "active navigation is flat with underline")
		_expect(not shell.buttons.undo.visible and not shell.buttons.profile.visible, "secondary controls stay in the grouped menu")
		shell.projects.get_popup().id_pressed.emit(1)
		await _settle()
		_expect(shell.project_details.is_visible_in_tree() and shell.title.is_visible_in_tree(), "rename opens from project menu at %d" % width)
		_expect(shell.title.size.y >= 44 and shell.project_done.size.y >= 44, "rename controls preserve touch height")
		_expect(shell.host.size.y >= idle_height + 44, "expanded rename reserves space above canvas")
		# Apply the existing name: exercises the real callback without saving a fixture project.
		shell.project_done.pressed.emit()
		await _settle()
		_expect(not shell.project_details.visible and shell.host.size.y == idle_height, "rename collapses and releases canvas space")
		shell._on_autosave_status_changed(&"queued", 0, "fixture")
		_expect("•" in shell.projects.text and "несохранённые" in shell.projects.tooltip_text, "dirty project is visibly marked")
		shell._on_autosave_status_changed(&"saving", 0, "fixture")
		_expect(shell.status_row.visible, "automatic saving feedback is visible")
		shell._on_autosave_status_changed(&"failed", 0, "fixture")
		await _settle()
		_expect(shell.status_row.is_visible_in_tree() and "Не удалось сохранить" in shell.status.text, "save failure is visible at %d" % width)
		_expect(shell.status.get_theme_color("font_color") == load("res://scripts/claude_design_theme.gd").DANGER, "save failure uses shared error color")
		_expect(shell.status.tooltip_text == shell.status.text, "truncated status retains complete accessible text")
		shell.save_message = ""
		shell.busy = true
		shell._sync()
		await _settle()
		_expect(shell.status_row.visible and shell.buttons.save.disabled, "busy state stays visible and prevents duplicate save")
		shell.busy = false
		shell._sync()
		await _settle()
		drop.size = Vector2(width, 900)
		# DisplayServer.window_get_size() is empty in the headless driver. Match
		# its native window boundary explicitly before testing the real drop path.
		app.space_end = Vector2(width, 900)
		drop.configure(app.space_begin.x, app.space_begin.y)
		var canvas: Rect2 = geometry.graph_rect(drop.size, app.space_begin, app.space_end)
		var payload: Dictionary = catalog.drag_payload(&"layer")
		_expect(canvas.has_area(), "canvas retains usable area at %d" % width)
		_expect(drop._can_drop_data(canvas.get_center(), payload), "real node drag accepted inside canvas at %d" % width)
		_expect(not drop._can_drop_data(canvas.position - Vector2(1, 1), payload), "header/palette gutter rejects drops at %d" % width)
		_expect(not drop._can_drop_data(Vector2(width - 1, 899), payload), "outer canvas gutter rejects drops at %d" % width)
		_expect(not drop._can_drop_data(canvas.get_center(), {"kind": &"neuralese_node_palette", "type_id": &"missing"}), "unknown node cannot enter workspace")
		drop._drop_data(canvas.get_center(), payload)
		_expect(received.back() == [&"layer", canvas.get_center()], "drop keeps the real node type and position")
	# A dataset edit and graph history coexist: shell history must follow the active surface.
	var old_dataset = app.tree_windows.get("ds")
	var dataset = load("res://scripts/dataset_tab.gd").new()
	app.tree_windows["ds"] = dataset
	var document = load("res://scripts/data_workspace/document.gd").new()
	document.create("Shell history fixture")
	dataset.document = document
	document.add_sample()
	app.curr_window = "ds"
	shell._sync()
	_expect(not shell.buttons.undo.disabled and shell.buttons.redo.disabled, "dataset history drives menu state")
	shell.overflow.get_popup().id_pressed.emit(0)
	_expect(shell.overflow.get_popup().is_item_disabled(shell.overflow.get_popup().get_item_index(0)), "dataset undo disables actual menu command")
	_expect(document.row_count() == 0, "shell undo applies to the active dataset")
	_expect(shell.buttons.undo.disabled and not shell.buttons.redo.disabled, "dataset undo updates shell redo state")
	shell.overflow.get_popup().id_pressed.emit(1)
	_expect(document.row_count() == 1, "shell redo restores the dataset edit")
	dataset.document = null
	shell._sync()
	_expect(shell.buttons.undo.disabled and shell.buttons.redo.disabled, "missing dataset disables history instead of reaching hidden graph")
	app.tree_windows.erase("ds")
	if is_instance_valid(old_dataset): app.tree_windows["ds"] = old_dataset
	dataset.free()
	app.curr_window = "graph"
	app.loaded_project_once = false
	shell._sync()
	_expect(shell.buttons.save.disabled and shell.projects.get_popup().is_item_disabled(1), "unloaded project disables save and rename")
	name_field.text = old_name
	drop.queue_free()
	project.queue_free()
	await _settle()
	if failures.is_empty():
		print("PASS test_claude_compact_shell")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)

func _settle() -> void:
	for frame in range(5):
		await process_frame

func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
