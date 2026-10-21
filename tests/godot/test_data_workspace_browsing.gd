extends Node

const Document = preload("res://scripts/data_workspace/document.gd")
const Canvas = preload("res://scripts/data_workspace/canvas.gd")

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var model = Document.new()
	model.create("Twelve columns")
	model.data.col_names = []
	for index in 12: model.data.col_names.append("Field %d:float" % index)
	model.data.outputs_from = 11
	model.studio().classes = []
	model.add_sample()
	model.add_sample()
	model.set_value(0, 0, 123456789.123456)
	model.set_value(0, 1, -20.0)
	model.set_value(1, 0, 123456799.123456)
	model.set_value(1, 1, 80.0)
	var canvas = Canvas.new()
	canvas.size = Vector2(760, 600)
	add_child(canvas)
	canvas.view = "table"
	canvas.render(model, [])
	await get_tree().process_frame
	var grid = canvas.world.get_child(0).grid
	assert(grid.table_mode and grid.available_width >= 12 * 160)
	assert(grid.table_document.column_count() == 12)
	var card = grid.get_tile("0")
	assert(card.table_cell_text(0) == str(model.value(0, 0)), "Full float text is preserved")
	assert(card._get_tooltip(Vector2(160 * 11 + 10, 12)).contains("Ответ"))
	assert(card._get_tooltip(Vector2(10, 12)).contains(str(model.value(0, 0))))
	grid._on_sample_hover(card, false)
	assert(card.get_theme_stylebox("panel").border_color == card.WorkspaceStyle.Design.LINE_STRONG, "Data tiles use the shared neutral border")
	grid._on_sample_hover(card, true)
	assert(card.get_theme_stylebox("panel").border_color == card.WorkspaceStyle.ACCENT, "Hover is distinct from neutral and keeps the accent")
	grid._on_sample_hover(card, false)
	assert(card._focus_style.border_color == card.WorkspaceStyle.ACCENT and card._focus_style.border_width_left == 2, "Keyboard focus has a dedicated visible outline")
	card.grab_focus()
	var arrow := InputEventKey.new()
	arrow.pressed = true
	arrow.keycode = KEY_DOWN
	card._gui_input(arrow)
	assert(grid.get_tile("1").has_focus(), "Arrows move sample focus")
	var activated: Array = []
	canvas.row_selected.connect(func(row, _extend): activated.append(row))
	var enter := InputEventKey.new()
	enter.pressed = true
	enter.keycode = KEY_ENTER
	grid.get_tile("1")._gui_input(enter)
	assert(activated == [1], "Enter activates the focused sample")
	canvas.render(model, [1])
	assert(canvas.world.get_child(0).grid.get_tile("1").has_focus(), "Refresh retains focused row")
	assert(canvas._axis_tick(0.0000003).contains("e"), "Tiny axes use readable exponents")
	var wheel := InputEventMouseButton.new()
	wheel.pressed = true
	wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wheel.position = Vector2(400, 200)
	var previous_pan: Vector2 = canvas.pan
	canvas._gui_input(wheel)
	assert(canvas.zoom == 1.0 and canvas.pan.y < previous_pan.y)
	wheel.ctrl_pressed = true
	canvas._gui_input(wheel)
	assert(canvas.zoom < 1.0, "Ctrl wheel explicitly zooms")
	canvas.reset_view()
	canvas.view = "plot"
	canvas.render(model, [0])
	await get_tree().process_frame
	await get_tree().process_frame
	assert(canvas._points.size() == 2)
	assert(canvas._plot_min[1] == -20.0 and canvas._plot_max[1] == 80.0)
	assert(is_equal_approx(canvas._points[0].at.x, canvas.PLOT_RECT.position.x))
	assert(is_equal_approx(canvas._points[1].at.y, canvas.PLOT_RECT.position.y))
	assert(model.value(0, 0) == 123456789.123456, "Views do not mutate data")
	var empty = Document.new()
	empty.create("Empty")
	canvas.view = "cards"
	canvas.render(empty, [])
	assert(canvas._empty_state.visible and canvas.world.get_child_count() == 0)
	canvas.queue_free()
	await get_tree().process_frame
	print("PASS test_data_workspace_browsing")
	get_tree().quit()
