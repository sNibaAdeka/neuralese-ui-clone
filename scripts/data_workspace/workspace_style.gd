extends RefCounted
## Local skin for the supplied dataset mockups, using the project's native widgets.
const Design = preload("res://scripts/claude_design_theme.gd")
const FONT = preload("res://game_assets/fonts/GolosText[wght].ttf")
const BASE_THEME = preload("res://resources/theme_base.tres")
const BUTTON_MATERIAL = preload("res://resources/add_button.tres")
const TEXT := Design.INK
const MUTED := Design.INK_SECONDARY
const ACCENT := Design.PRIMARY

static func box(fill: Color, border: Color, radius: int = Design.CONTROL_RADIUS) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(radius)
	return style

static func make_theme() -> Theme:
	var result: Theme = Design.create_theme()
	result.default_font = FONT
	result.default_font_size = Design.UI_FONT_SIZE
	result.set_font("font", "Label", FONT)
	result.set_color("font_color", "Label", TEXT)
	for type in ["LineEdit", "TextEdit", "OptionButton", "Button"]:
		result.set_font("font", type, FONT)
		result.set_font_size("font_size", type, Design.CAPTION_FONT_SIZE)
		result.set_color("font_color", type, TEXT)
		result.set_color("font_placeholder_color", type, MUTED)
		for state in ["normal", "hover", "pressed", "focus", "read_only"]:
			var panel := box(Color("ffffff"), ACCENT if state == "focus" else Design.LINE_STRONG, Design.CONTROL_RADIUS)
			panel.content_margin_left = 10; panel.content_margin_right = 10
			panel.content_margin_top = 6; panel.content_margin_bottom = 6
			result.set_stylebox(state, type, panel)
	result.set_font("font", "PopupMenu", FONT)
	result.set_font_size("font_size", "PopupMenu", Design.CAPTION_FONT_SIZE)
	result.set_stylebox("panel", "PopupMenu", box(Color("ffffff"), Design.LINE_STRONG, Design.CONTROL_RADIUS))
	return result

static func button_material() -> ShaderMaterial:
	var material: ShaderMaterial = BUTTON_MATERIAL.duplicate()
	material.set_shader_parameter("blurred_background", false)
	material.set_shader_parameter("mult_tuning", Color.WHITE)
	material.set_shader_parameter("corner_radius", 13.8)
	material.set_shader_parameter("outline_width", 1.0)
	return material

static func skin_button(button: BlockComponent, primary: bool = false) -> void:
	button.material = button_material()
	var danger := button.text == "Удалить"
	var fill := Color("fff0f2") if danger else Design.PRIMARY if primary else Design.FILL
	var border := Color("e2a0ac") if danger else Design.PRIMARY if primary else Design.LINE_STRONG
	# Compensate the existing canvas shader's conversion of instance colors.
	button.set_instance_shader_parameter("tuning", fill.linear_to_srgb())
	button.set_instance_shader_parameter("outline_color", border.linear_to_srgb())
	button.label.add_theme_font_override("font", FONT)
	button.label.add_theme_font_size_override("font_size", 34)
	button.label.add_theme_color_override("font_color", Color.WHITE)
	button.text_color = Color("aa2845") if danger else Color.WHITE if primary else TEXT
