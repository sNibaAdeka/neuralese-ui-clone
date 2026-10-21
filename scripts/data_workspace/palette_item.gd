extends "res://scripts/node_palette_item.gd"
## Data tools share focus, click and drag interactions with graph palette items.
var action_icon: Texture2D

func setup(entry: Dictionary) -> void:
	type_id = StringName(entry.get("type_id", ""))
	_title = str(entry.get("title", type_id))
	tooltip_text = _title
	focus_mode = Control.FOCUS_ALL
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

func _ready() -> void:
	super()
	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_right", 8)
	add_child(margin)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 10)
	margin.add_child(row)
	var icon := TextureRect.new()
	icon.texture = action_icon
	icon.custom_minimum_size = Vector2(20, 20)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.self_modulate = Design.INK_SECONDARY
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(icon)
	var label := Label.new()
	label.text = _title.get_slice("\n", 0)
	label.add_theme_font_override("font", preload("res://game_assets/fonts/GolosText[wght].ttf"))
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", Design.INK)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(label)
	_apply_surface()

func _get_drag_data(_at_position: Vector2) -> Variant:
	_dragging = true
	_pressed = false
	set_hovered(false)
	set_drag_preview(_build_drag_preview())
	return {"dataset_tool": str(type_id)}
