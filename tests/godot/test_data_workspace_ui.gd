extends "res://scripts/generated/node_sources.gd"

func _ready() -> void:
	super()
	_run.call_deferred()

func _run() -> void:
	await get_tree().create_timer(0.8).timeout
	get_tree().root.size = Vector2i(1440, 900)
	ui.close_top_level_splashes()
	await get_tree().process_frame
	glob.loaded_project_once = false
	var tab = glob.tree_windows.get("ds")
	assert(tab != null and tab.has_method("activate_tool"))
	tab._save_timer.wait_time = 3600
	glob.go_window("ds")
	assert(tab._layer.visible)
	assert(not tab.has_node("Control/CodeEdit"), "Legacy UI was removed")
	tab.activate_tool("car")
	tab.document.generate(18, 42)
	assert(tab._canvas.world.get_child_count() == 3)
	tab._select_row(0, false)
	assert(tab.selection == [0])
	tab._set_view("plot")
	assert(tab._canvas._points.size() == 18)
	tab.activate_tool("images")
	tab.document.generate(8, 13)
	assert(tab.document.row_count() == 8)
	var grid: GridVisualiser = tab._canvas.world.get_child(0).grid
	assert(grid is GridVisualiser and grid.get_tile("0") is PanelContainer)
	var tile_ids: Array = []
	for child in grid.get_children():
		if child is PanelContainer: tile_ids.append(child.get_instance_id())
	tab._refresh()
	assert(tab._canvas.world.get_child(0).grid == grid, "Refresh keeps the native grid")
	for child in grid.get_children():
		if child is PanelContainer: assert(tile_ids.has(child.get_instance_id()), "Refresh reuses pooled grid tiles")
	tab._set_view("table")
	await get_tree().process_frame
	tab._set_view("cards")
	await get_tree().process_frame
	assert(grid.columns > 1 and grid.size.x <= tab._canvas.size.x, "Native grid returns to responsive cards after table view")
	var training: Dictionary = nn._local_dataset_to_training_json(str(tab.document.data.name))
	assert(training.get("ok", false))
	assert(training.x.size() + training.get("val_x", []).size() == 8)
	assert(training.x[0].size() == 28 * 28)
	assert(training.meta.preview.inputs.datatype == "2d" and training.meta.preview.inputs.x == 28)
	await get_tree().process_frame
	# Startup authentication is outside this workspace integration test.
	for dialog in get_tree().root.find_children("*", "MultipurposeDialog", true, false):
		dialog.process_mode = Node.PROCESS_MODE_DISABLED
		dialog.hide()
	var card: Control = tab._canvas.world.get_child(0).grid.get_tile("0")
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	wheel.ctrl_pressed = true
	wheel.position = card.get_global_rect().get_center()
	wheel.global_position = wheel.position
	var zoom_before: float = tab._canvas.zoom
	get_tree().root.push_input(wheel, true)
	assert(tab._canvas.zoom > zoom_before, "Wheel zoom propagates through native grid cards")
	_click(card.get_global_rect().get_center())
	assert(tab.selection == [0], "Pointer clicks reach the canvas sample")
	await get_tree().process_frame
	assert(tab._inspector_body.get_child_count() > 3)
	var editor: Control
	for child in tab._inspector_body.get_children():
		if child.has_signal("image_edited"): editor = child
	assert(editor != null)
	var rect: Rect2 = editor._rect()
	var at: Vector2 = editor.global_position + rect.position + rect.size * 0.08
	_click(at)
	assert(tab.document.value(0, 0).get_image().get_pixel(2, 2).r > 0.9, "Pointer drawing changes dataset pixels")
	var folder := "user://workspace-import-images-" + str(Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(folder.path_join("circles"))
	DirAccess.make_dir_recursive_absolute(folder.path_join("squares"))
	var image := Image.create(12, 8, false, Image.FORMAT_RGB8)
	image.fill(Color.RED)
	image.save_png(folder.path_join("circles/red.png"))
	image.save_png(folder.path_join("squares/red.png"))
	var count_before: int = glob.dataset_datas.size()
	await tab.import_paths([folder])
	assert(glob.dataset_datas.size() == count_before, "Preview does not import until applied")
	assert(tab._staged.size() == 1 and tab._staged[0].row_count() == 2)
	assert(tab._staged[0].classes().has("circles") and tab._staged[0].classes().has("squares"))
	var imported: Image = tab._staged[0].value(0, 0).get_image()
	assert(imported.get_size() == Vector2i(28, 28) and imported.get_format() == Image.FORMAT_L8)
	tab._apply_import()
	assert(glob.dataset_datas.size() == count_before + 1)
	var before_create: int = glob.dataset_datas.size()
	for item in tab._palette.find_children("*", "NodePaletteItem", true, false):
		if str(item.type_id) == "numeric":
			_click(item.get_global_rect().get_center())
			break
	assert(glob.dataset_datas.size() == before_create + 1, "Palette responds to pointer clicks")
	# Import choices preserve categorical first rows and never mutate live data in preview.
	var csv_path := "user://workspace-ambiguous.csv"
	var csv_file := FileAccess.open(csv_path, FileAccess.WRITE)
	csv_file.store_string("red,small,yes\nblue,large,no\ngreen,small,yes\n")
	csv_file.close()
	var datasets_before_csv: int = glob.dataset_datas.size()
	await tab.import_paths([csv_path])
	assert(tab._csv_needs_header_choice(), "Ambiguous categorical CSV requires a visible choice")
	tab._apply_import()
	assert(glob.dataset_datas.size() == datasets_before_csv, "Ambiguous import cannot silently lose its first row")
	tab._set_csv_option(tab._csv_previews[0], "header", "absent")
	await get_tree().process_frame
	await get_tree().process_frame
	assert(get_viewport().gui_get_focus_owner() is OptionButton, "CSV option retains keyboard focus after preview refresh")
	assert(not tab._csv_needs_header_choice() and tab._staged[0].row_count() == 3)
	assert(glob.dataset_datas.size() == datasets_before_csv)
	tab._apply_import()
	assert(glob.dataset_datas.size() == datasets_before_csv + 1 and tab.document.row_count() == 3)
	assert(tab._sample_button is Button and tab._sample_button.focus_mode == Control.FOCUS_ALL)
	assert(tab._page_buttons.previous.disabled and tab._page_buttons.next.disabled)
	assert(tab._view_buttons.plot.disabled == (tab.document.kind() not in ["numeric", "car", "simulation"]))
	var current_document = tab.document
	tab.document = null
	tab._sync_actions()
	assert(tab._sample_button.text == "Создать набор" and tab._view_buttons.table.disabled)
	tab._primary_dataset_action()
	assert(tab.document != null and tab.document != current_document, "Empty primary action creates a dataset")
	# Native control activation and document-scoped undo/redo.
	tab._sample_button.grab_focus()
	var rows_before: int = tab.document.row_count()
	for pressed in [true, false]:
		var enter := InputEventKey.new()
		enter.keycode = KEY_ENTER
		enter.pressed = pressed
		get_tree().root.push_input(enter, true)
	assert(tab.document.row_count() == rows_before + 1, "Enter activates the focused Add sample button")
	tab.undo()
	assert(tab.document.row_count() == rows_before)
	tab.redo()
	assert(tab.document.row_count() == rows_before + 1)
	var invalid_file := FileAccess.open("user://workspace-invalid.csv", FileAccess.WRITE)
	invalid_file.store_string("word\n"); invalid_file.close()
	var valid_file := FileAccess.open("user://workspace-valid.csv", FileAccess.WRITE)
	valid_file.store_string("1,2\n3,4\n"); valid_file.close()
	await tab.import_paths(["user://workspace-invalid.csv", "user://workspace-valid.csv"])
	assert(tab._staged.size() == 1 and not tab._csv_needs_header_choice(), "Invalid files do not block valid members of a batch")
	tab._apply_import()
	assert(tab.document.row_count() == 2)
	tab.document.studio().validation_ratio = 1.0
	tab._refresh()
	assert(tab._quality_color() == Color("aa2845"), "Blocking data issues cannot display success green")
	tab._pending.clear()
	tab._save_timer.stop()
	print("PASS test_data_workspace_ui")
	get_tree().quit(0)

func _click(at: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = at
	motion.global_position = at
	get_tree().root.push_input(motion, true)
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = at
		event.global_position = at
		get_tree().root.push_input(event, true)
