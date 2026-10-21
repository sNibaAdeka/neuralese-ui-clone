extends Control

const WorkspaceStyle = preload("res://scripts/data_workspace/workspace_style.gd")

signal moved(group: String, at: Vector2)
signal sample_dropped(row: int, group: String)
var title := ""
var count := 0
var dataset_name := ""
var accent := Color("8cc7f0")
var _dragging := false
var grid: GridVisualiser

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS

func _get_tooltip(at_position: Vector2) -> String:
	if grid != null and grid.get("table_mode") == true and at_position.y >= 42 and at_position.y < grid.position.y:
		var model = grid.table_document
		var column := clampi(int((at_position.x - grid.position.x - 8) / 160.0), 0, model.column_count() - 1)
		return "%s · %s" % [model.field_name(column), "Вход" if column < int(model.data.outputs_from) else "Ответ"]
	return "Перетащите заголовок, чтобы переместить группу"

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed and event.position.y < 42: _dragging = true
		elif not event.pressed and _dragging:
			_dragging = false
			moved.emit(title, position)
		accept_event()
	elif event is InputEventMouseMotion and _dragging:
		if not event.button_mask & MOUSE_BUTTON_MASK_LEFT:
			_dragging = false
			moved.emit(title, position)
		else: position += event.relative / get_global_transform().get_scale()
		accept_event()

func _can_drop_data(_at_position: Vector2, payload: Variant) -> bool:
	return payload is Dictionary and payload.has("dataset_sample") and payload.get("dataset", "") == dataset_name

func _drop_data(_at_position: Vector2, payload: Variant) -> void:
	if _can_drop_data(_at_position, payload): sample_dropped.emit(int(payload.dataset_sample), title)

func _draw() -> void:
	var box := StyleBoxFlat.new()
	box.bg_color = Color.TRANSPARENT
	box.set_border_width_all(0)
	box.set_corner_radius_all(10)
	draw_style_box(box, Rect2(Vector2.ZERO, size))
	draw_circle(Vector2(18, 22), 4, accent)
	draw_string(get_theme_default_font(), Vector2(32, 27), title, HORIZONTAL_ALIGNMENT_LEFT, size.x - 95, 15, WorkspaceStyle.TEXT)
	draw_string(get_theme_default_font(), Vector2(size.x - 55, 27), str(count), HORIZONTAL_ALIGNMENT_RIGHT, 36, 13, WorkspaceStyle.MUTED)
	if count == 0:
		draw_string(get_theme_default_font(), Vector2(18, grid.position.y + 24 if grid != null else 80), "Добавьте пример", HORIZONTAL_ALIGNMENT_LEFT, size.x - 30, 13, WorkspaceStyle.MUTED)
