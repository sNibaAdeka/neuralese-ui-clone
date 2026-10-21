extends PanelContainer
class_name NodePaletteItem

const NodePaletteCatalog = preload("res://scripts/node_palette_catalog.gd")
const Design = preload("res://scripts/claude_design_theme.gd")
const UI_FONT = preload("res://game_assets/fonts/GolosText[wght].ttf")
const VisualFamily = preload("res://scripts/node_visual_family.gd")

signal drag_started(type_id: StringName)
signal drag_finished
signal activated(type_id: StringName)

var type_id: StringName = StringName()
var _title := ""
var _colors: Array[Color] = [Design.ACTIVATION_SOFT, Design.ACTIVATION_WIRE]
var _hovered := false
var _dragging := false
var _pressed := false
var _press_position := Vector2.ZERO
var _moved_since_press := false
var disabled := false
var _symbol: PaletteNodePreview

@export var hover_scale := 1.04
@export var hover_lerp_speed := 14.0


func _ready() -> void:
	set_meta("claude_design_owned", true)
	set_meta("claude_styled", true)
	mouse_entered.connect(set_hovered.bind(true))
	mouse_exited.connect(set_hovered.bind(false))
	focus_entered.connect(_apply_surface)
	focus_exited.connect(_apply_surface)
	resized.connect(_sync_pivot)
	_sync_pivot()
	set_process(false)


func setup(entry: Dictionary) -> void:
	type_id = StringName(entry.get("type_id", ""))
	_title = str(entry.get("title", type_id))
	_colors = _category_colors(type_id)
	disabled = bool(entry.get("disabled", false))
	mouse_default_cursor_shape = Control.CURSOR_FORBIDDEN if disabled else Control.CURSOR_POINTING_HAND
	tooltip_text = _title + ("\n" + str(entry.get("disabled_reason", "")) if disabled else "")
	var title: Label = get_node("Margin/Content/Title")
	title.text = _title
	title.add_theme_font_override("font", UI_FONT)
	title.add_theme_font_size_override("font_size", Design.CAPTION_FONT_SIZE)
	title.add_theme_color_override("font_color", Design.INK_SECONDARY)
	# The vector miniature shares the authored card shape and internal widgets;
	# catalog IDs and creation availability are independent of the illustration.
	if not is_instance_valid(_symbol):
		_symbol = PaletteNodePreview.new()
		_symbol.mouse_filter = Control.MOUSE_FILTER_IGNORE
		get_node("Margin/Content/Icon").add_child(_symbol)
		_symbol.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_symbol.type_id = type_id
	_symbol.title = _title
	_symbol.modulate.a = 0.58 if disabled else 1.0
	_symbol.fill = _colors[0]
	_symbol.ink = _colors[1]
	_symbol.queue_redraw()
	_apply_surface()


func minimum_slot_width() -> float:
	var longest_word := 0.0
	for word in _title.split(" "):
		longest_word = maxf(longest_word, UI_FONT.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, Design.CAPTION_FONT_SIZE).x)
	return maxf(62.0, ceilf(longest_word) + 8.0)


func set_slot_width(width: float) -> void:
	custom_minimum_size.x = width
	get_node("Margin/Content/Title").custom_minimum_size.x = maxf(0.0, width - 6.0)


static func _category_colors(id: StringName) -> Array[Color]:
	var colors := VisualFamily.colors(VisualFamily.family([id]))
	return [colors[1], colors[2]]


func _apply_surface() -> void:
	var fill := Color.TRANSPARENT
	if not disabled:
		fill = Design.FILL_HOVER if _pressed else Design.FILL if _hovered else Color.TRANSPARENT
	var edge := Design.PRIMARY if has_focus() else Color.TRANSPARENT
	add_theme_stylebox_override("panel", Design.box(fill, edge, 12, Vector2.ZERO, 2))


func set_hovered(value: bool) -> void:
	_hovered = value
	_apply_surface()
	set_process(true)


func _process(delta: float) -> void:
	var target_scale := Vector2.ONE * (hover_scale if _hovered and not _dragging and not disabled else 1.0)
	var weight := 1.0 - exp(-hover_lerp_speed * delta)
	scale = scale.lerp(target_scale, weight)
	if scale.distance_to(target_scale) < 0.001:
		scale = target_scale
		set_process(false)


func _sync_pivot() -> void:
	pivot_offset = size * 0.5


func _gui_input(event: InputEvent) -> void:
	if disabled:
		accept_event()
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_pressed = true
			_moved_since_press = false
			_press_position = event.position
			grab_focus()
			_apply_surface()
		elif _pressed:
			_pressed = false
			_apply_surface()
			if not _dragging and not _moved_since_press and Rect2(Vector2.ZERO, size).has_point(event.position):
				activated.emit(type_id)
		accept_event()
	elif event is InputEventMouseMotion and _pressed:
		_moved_since_press = _moved_since_press or event.position.distance_to(_press_position) > 5.0
	elif event.is_action_pressed("ui_accept") and not event.is_echo():
		activated.emit(type_id)
		accept_event()


func _get_drag_data(_at_position: Vector2) -> Variant:
	if type_id.is_empty() or disabled:
		return null
	_dragging = true
	_pressed = false
	set_hovered(false)
	drag_started.emit(type_id)
	set_drag_preview(_build_drag_preview())
	return NodePaletteCatalog.drag_payload(type_id)


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END:
		_dragging = false
		_pressed = false
		_hovered = get_global_rect().has_point(get_global_mouse_position())
		set_process(true)
		drag_finished.emit()


func _build_drag_preview() -> Control:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(180, 60)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_theme_stylebox_override("panel", Design.box(_colors[0], _colors[1], 18, Vector2(13, 10)))
	var label := Label.new()
	label.text = _title
	label.add_theme_font_override("font", UI_FONT)
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", Design.INK)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(label)
	return card


class PaletteNodePreview extends Control:
	## Vector miniatures follow the authored Claude node proportions and widgets.
	## They are catalog illustrations, never a snapshot of the current model.
	var type_id: StringName
	var title := ""
	var fill := Color.WHITE
	var ink := Color.BLACK

	func _draw() -> void:
		var id := String(type_id)
		var dimensions := Vector2(144, 244)
		if id in ["conv2d", "classifier", "train_begin", "run_model", "train_input"]:
			dimensions.x = 233
		elif id in ["maxpool", "reshape2d"]:
			dimensions.y = 150
		elif id == "neuron":
			dimensions.y = 176
		elif id in ["flatten", "concat", "softmax"]:
			dimensions.y = 89
		var miniature_scale := 56.0 / 244.0
		var origin := (size - dimensions * miniature_scale) / 2.0
		draw_set_transform(origin, 0.0, Vector2.ONE * miniature_scale)
		var surface := Design.box(fill, ink.lightened(0.70), 32, Vector2.ZERO, 1)
		surface.shadow_color = Color(0.12, 0.15, 0.22, 0.14)
		surface.shadow_size = 5
		surface.shadow_offset = Vector2(0, 4)
		draw_style_box(surface, Rect2(Vector2.ZERO, dimensions))
		var heading := title
		if id == "layer":
			heading = "Плотный\nслой" if "слой" in title else title
		for line_index in heading.split("\n").size():
			_text(heading.split("\n")[line_index], Vector2(16, 27 + line_index * 17), 16, Design.INK)
		if dimensions.y > 89:
			draw_circle(Vector2(dimensions.x - 22, 21), 11, Color(1, 1, 1, 0.78))
			draw_arc(Vector2(dimensions.x - 22, 21), 4.5, 0, TAU, 16, ink, 1.4, true)
		match id:
			"input_1d": _input_1d()
			"input": _input_2d()
			"dataset": _dataset()
			"conv2d": _convolution()
			"maxpool": _pool()
			"layer", "dropout", "gru_cell": _dense(id)
			"neuron": _activation()
			"reshape2d":
				_box(Rect2(12, 53, 120, 82), Color.WHITE, 20)
				_chip(Rect2(20, 73, 43, 36), "28", 17)
				_text("×", Vector2(67, 98), 16, ink)
				_chip(Rect2(84, 73, 40, 36), "28", 17)
			"flatten": _chip(Rect2(43, 46, 58, 25), "784", 16)
			"concat": _chip(Rect2(30, 46, 84, 25), "2 в 1", 16)
			"softmax": _chip(Rect2(29, 46, 86, 25), "в доли", 15)
			"classifier": _classifier()
			_: _training(id)

	func _box(rect: Rect2, color: Color, radius: int = 10, border: Color = Color.TRANSPARENT) -> void:
		draw_style_box(Design.box(color, border, radius, Vector2.ZERO, 1 if border.a > 0 else 0), rect)

	func _text(value: String, position: Vector2, font_size: int = 14, color: Color = Design.INK_SECONDARY) -> void:
		draw_string(UI_FONT, position, value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)

	func _chip(rect: Rect2, value: String, font_size: int = 14) -> void:
		_box(rect, Color(1, 1, 1, 0.85), 14)
		var text_size := UI_FONT.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
		_text(value, Vector2(rect.position.x + (rect.size.x - text_size.x) / 2.0, rect.position.y + rect.size.y / 2.0 + font_size * 0.35), font_size, ink.darkened(0.25))

	func _input_1d() -> void:
		_box(Rect2(12, 67, 120, 128), Color.WHITE, 20)
		for i in 3:
			var y := 84.0 + i * 34
			_text("признак", Vector2(22, y), 12)
			_box(Rect2(22, y + 6, 97, 6), Color("eceef2"), 3)
			_box(Rect2(22, y + 6, 34 + i * 16, 6), ink.lightened(0.3), 3)

	func _input_2d() -> void:
		_box(Rect2(12, 47, 120, 183), Color.WHITE, 22)
		_box(Rect2(22, 60, 100, 112), Color("f6f7fa"), 14, Color("e4e6ed"))
		for x in [52.0, 92.0]:
			draw_circle(Vector2(x, 192), 13, fill)
			draw_line(Vector2(x - 4, 192), Vector2(x + 4, 192), ink, 2, true)
		_text("28×28", Vector2(48, 219), 12)

	func _dataset() -> void:
		_box(Rect2(12, 47, 120, 183), Color.WHITE, 22)
		_chip(Rect2(22, 58, 100, 32), "mnist", 15)
		var digits := ["3", "7", "1", "9"]
		for i in 4:
			var position := Vector2(22 + (i % 2) * 52, 99 + (i / 2) * 51)
			_box(Rect2(position, Vector2(47, 46)), Color("f1f2f6"), 9)
			_text(digits[i], position + Vector2(13, 36), 34, Design.INK)
		_text("примеры", Vector2(43, 219), 12)

	func _convolution() -> void:
		for i in 2:
			var y := 72.0 + i * 30
			_text("Окно" if i == 0 else "Шаг", Vector2(17, y), 12)
			draw_line(Vector2(62, y - 4), Vector2(192, y - 4), ink.lightened(0.4), 4, true)
			draw_circle(Vector2(110 + i * 45, y - 4), 6, ink)
		_box(Rect2(14, 129, 92, 92), Color.WHITE, 14)
		_text("7", Vector2(40, 200), 70, Design.INK)
		draw_rect(Rect2(34, 148, 35, 35), ink, false, 3)
		_text("›", Vector2(114, 183), 24, ink)
		_box(Rect2(141, 129, 78, 92), Color.WHITE, 14)
		_tensor(Vector2(151, 144), 4, 4, 13, false)

	func _pool() -> void:
		_box(Rect2(12, 37, 120, 99), Color.WHITE, 22)
		_tensor(Vector2(38, 47), 4, 4, 17, true)
		_text("окно 2×2", Vector2(43, 128), 11)

	func _tensor(origin: Vector2, columns: int, rows: int, step: float, highlight: bool) -> void:
		for row in rows:
			for col in columns:
				var bright := (row + col) % 3 == 0
				var cell_color := ink if bright else ink.lightened(0.60)
				_box(Rect2(origin + Vector2(col, row) * step, Vector2.ONE * (step - 2)), cell_color, 3)
		if highlight:
			draw_rect(Rect2(origin - Vector2.ONE * 2, Vector2.ONE * step * 2 + Vector2.ONE * 2), ink, false, 2)

	func _dense(id: String) -> void:
		_chip(Rect2(13, 62, 118, 28), "−   128   +" if id == "layer" else ("20%" if id == "dropout" else "GRU"), 14)
		for i in 3:
			var center := Vector2(72, 119 + i * 42)
			var off := id == "dropout" and i == 1
			draw_circle(center, 14, fill.lightened(0.15) if off else Color.WHITE)
			draw_arc(center, 14, 0, TAU, 28, ink.lightened(0.6) if off else ink, 3, true)

	func _activation() -> void:
		_box(Rect2(12, 39, 120, 124), Color.WHITE, 22)
		draw_line(Vector2(22, 101), Vector2(122, 101), Color("dfe2eb"), 2, true)
		draw_line(Vector2(72, 48), Vector2(72, 119), Color("dfe2eb"), 2, true)
		draw_polyline(PackedVector2Array([Vector2(23, 101), Vector2(72, 101), Vector2(93, 64)]), ink, 3, true)
		_chip(Rect2(43, 128, 58, 23), "ReLU", 14)

	func _classifier() -> void:
		_box(Rect2(12, 46, 209, 185), Color.WHITE, 22)
		for i in 10:
			var y := 62.0 + i * 16
			_text(str(i), Vector2(24, y + 2), 10)
			_box(Rect2(43, y - 6, 133, 8), Color("eeeeef"), 4)
			_box(Rect2(43, y - 6, 13, 8), ink, 4)
			_text("%", Vector2(192, y + 2), 10)

	func _training(id: String) -> void:
		_box(Rect2(13, 63, 207, 118), Color.WHITE, 22)
		_text("Датасет" if id == "train_begin" else "Модель", Vector2(24, 89), 14)
		_chip(Rect2(24, 108, 185, 40), "−     1     +", 18)
		_box(Rect2(14, 194, 166, 36), Design.PRIMARY, 18)
		_text("Учись!" if id == "train_begin" else "Запуск", Vector2(70, 219), 15, Color.WHITE)
