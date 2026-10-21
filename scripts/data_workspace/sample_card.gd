extends PanelContainer

signal selected(row: int, extend: bool)
signal focus_requested(row: int, direction: int)
const TABLE_COLUMN_WIDTH := 160.0
var document
var row_index := 0
var highlighted := false
var table_mode := false
var _had_drag := false
var _focus_style: StyleBoxFlat
const WorkspaceStyle = preload("res://scripts/data_workspace/workspace_style.gd")
const ACCENTS := [Color("8cc7f0"), Color("a9daa0"), Color("f4c384"), Color("c7aff0"), Color("efa8bc"), Color("8bd7cf")]

func _make_custom_tooltip(text: String) -> Object:
	var label := Label.new()
	label.custom_minimum_size.x = 260
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 12)
	label.text = text
	return label

func _ready() -> void:
	_focus_style = WorkspaceStyle.box(Color.TRANSPARENT, WorkspaceStyle.ACCENT, 9)
	_focus_style.set_border_width_all(2)
	focus_mode = Control.FOCUS_ALL
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	tooltip_text = "Нажмите, чтобы изменить. Ctrl — выбрать несколько. Перетащите в другой класс."

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_had_drag = false
			grab_focus()
		elif not _had_drag: selected.emit(row_index, event.ctrl_pressed or event.meta_pressed or event.shift_pressed)
		accept_event()
	elif event is InputEventKey and event.pressed:
		if event.keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]:
			selected.emit(row_index, event.ctrl_pressed or event.meta_pressed or event.shift_pressed)
			accept_event()
		elif event.keycode in [KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN]:
			focus_requested.emit(row_index, -1 if event.keycode in [KEY_LEFT, KEY_UP] else 1)
			accept_event()

func table_cell_text(column: int) -> String:
	return str(document.value(row_index, column))

func _get_tooltip(at_position: Vector2) -> String:
	if document == null: return ""
	if table_mode:
		var column := clampi(int((at_position.x - 8) / TABLE_COLUMN_WIDTH), 0, document.column_count() - 1)
		return "%s · %s\n%s\nEnter — изменить пример" % [document.field_name(column), "Вход" if column < int(document.data.outputs_from) else "Ответ", table_cell_text(column)]
	var details: Array[String] = ["Enter — изменить пример. Ctrl/Cmd — выбрать несколько."]
	for column in document.column_count():
		details.append("%s: %s" % [document.field_name(column), table_cell_text(column)])
	return "\n".join(details)

func _fit_text(text: String, width: float, font: Font) -> String:
	text = text.replace("\n", " ↵ ").replace("\t", " → ")
	if font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x <= width: return text
	var low := 0
	var high := text.length()
	while low < high:
		var middle: int = (low + high + 1) / 2
		if font.get_string_size(text.left(middle) + "…", HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x <= width: low = middle
		else: high = middle - 1
	return text.left(low) + "…"

func _get_drag_data(_at_position: Vector2) -> Variant:
	_had_drag = true
	var label := Label.new()
	label.text = "Пример %d → другой класс" % (row_index + 1)
	set_drag_preview(label)
	return {"dataset_sample": row_index, "dataset": str(document.data.name)}

func _draw() -> void:
	if document == null or row_index >= document.row_count(): return
	var font := get_theme_default_font()
	if has_focus():
		draw_style_box(_focus_style, Rect2(Vector2(3, 3), size - Vector2(6, 6)))
	if table_mode:
		for column in document.column_count():
			var x: float = 8 + TABLE_COLUMN_WIDTH * column
			var text := _fit_text(table_cell_text(column), TABLE_COLUMN_WIDTH - 16, font)
			draw_string(font, Vector2(x, 24), text, HORIZONTAL_ALIGNMENT_LEFT, TABLE_COLUMN_WIDTH - 16, 12, WorkspaceStyle.TEXT)
			if column > 0: draw_line(Vector2(x - 8, 4), Vector2(x - 8, size.y - 4), WorkspaceStyle.Design.LINE)
		return
	var preview := Rect2(10, 10, size.x - 20, size.y - 58)
	draw_style_box(WorkspaceStyle.box(WorkspaceStyle.Design.FILL, Color.TRANSPARENT, 7), preview)
	if document.kind() == "images":
		var texture: Variant = document.value(row_index, 0)
		draw_rect(preview, Color("141619"))
		if texture is Texture2D:
			var scale_factor: float = minf(preview.size.x / texture.get_width(), preview.size.y / texture.get_height())
			var fitted := Vector2(texture.get_width(), texture.get_height()) * scale_factor
			draw_texture_rect(texture, Rect2(preview.get_center() - fitted * 0.5, fitted), false)
	elif document.kind() in ["car", "simulation"]:
		_draw_car(preview)
	elif document.kind() == "text":
		var text := str(document.value(row_index, 0))
		var lines := mini(4, ceili(float(text.length()) / 17.0))
		for line in lines: draw_string(font, preview.position + Vector2(0, 17 + line * 17), text.substr(line * 17, 17).replace("\n", " "), HORIZONTAL_ALIGNMENT_LEFT, preview.size.x, 12, WorkspaceStyle.TEXT)
	else:
		for column in mini(4, document.column_count()):
			var raw: Variant = document.value(row_index, column)
			var line := "%s  %s" % [document.field_name(column), "%.2f" % float(raw) if raw is float or raw is int else str(raw).left(8)]
			draw_string(font, preview.position + Vector2(0, 17 + column * 19), line, HORIZONTAL_ALIGNMENT_LEFT, preview.size.x, 12, WorkspaceStyle.TEXT)
	draw_string(font, Vector2(11, size.y - 28), "Пример #%03d" % (row_index + 1), HORIZONTAL_ALIGNMENT_LEFT, size.x - 24, 13, WorkspaceStyle.TEXT)
	var detail: String = document.group_for(row_index)
	if document.kind() == "car": detail = "Руль  %.2f" % float(document.value(row_index, 5))
	draw_string(font, Vector2(11, size.y - 11), detail, HORIZONTAL_ALIGNMENT_LEFT, size.x - 35, 11, Color("287962") if document.kind() == "car" else WorkspaceStyle.MUTED)
	var split: String = document.split_for(row_index)
	draw_circle(Vector2(size.x - 16, size.y - 16), 3, Color("a9daa0") if split == "train" else Color("f4c384"))

func _draw_car(rect: Rect2) -> void:
	var center := rect.get_center()
	var angle := -PI * 0.5
	var steer: float = float(document.value(row_index, int(document.data.outputs_from)))
	if document.kind() == "car":
		var x: float = float(document.value(row_index, 0))
		var y: float = float(document.value(row_index, 1))
		center = rect.position + (Vector2(x, y) + Vector2.ONE) * 0.5 * (rect.size - Vector2(26, 26)) + Vector2(13, 13)
		angle = float(document.value(row_index, 2))
		var goal := Vector2(float(document.value(row_index, 3)), float(document.value(row_index, 4)))
		goal = rect.position + (goal + Vector2.ONE) * 0.5 * (rect.size - Vector2(26, 26)) + Vector2(13, 13)
		draw_line(center, goal, Color("596964"), 1, true)
		draw_circle(goal, 5, Color("a9daa0"))
	else:
		for index in mini(5, int(document.data.outputs_from)):
			var length: float = clampf(absf(float(document.value(row_index, index))), 0.05, 1) * 38
			draw_line(center, center + Vector2.from_angle(-PI + index * PI / 4) * length, Color("4c6569"), 1, true)
	draw_set_transform(center, angle)
	draw_style_box(WorkspaceStyle.box(Color("9e63cf"), Color("d6a3f8"), 4), Rect2(-11, -7, 22, 14))
	draw_rect(Rect2(3, -5, 5, 10), Color("46315c"))
	draw_line(Vector2(9, 0), Vector2(24, steer * 12), Color("f4c384"), 3, true)
	draw_set_transform(Vector2.ZERO)
