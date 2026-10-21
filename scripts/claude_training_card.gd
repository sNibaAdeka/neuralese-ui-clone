extends RefCounted
## Small native controls shared by the four training cards. Data stays with each graph.
const FONT = preload("res://game_assets/fonts/GolosText[wght].ttf")
const INK = Color("252832")
const MUTED = Color("686c7c")
const BLUE = Color("247ec1")

static func panel(parent: Node, title: String, bounds: Rect2, tint: Color = Color.WHITE, radius: int = 16) -> Panel:
	var item := Panel.new()
	item.name = title
	item.position = bounds.position
	item.size = bounds.size
	item.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = tint
	style.set_corner_radius_all(radius)
	item.add_theme_stylebox_override("panel", style)
	parent.add_child(item)
	return item

static func label(parent: Node, title: String, bounds: Rect2, text: String, font_size: int = 12) -> Label:
	var item := Label.new()
	item.name = title
	item.position = bounds.position
	item.size = bounds.size
	item.text = text
	item.mouse_filter = Control.MOUSE_FILTER_IGNORE
	item.add_theme_font_override("font", FONT)
	item.add_theme_font_size_override("font_size", font_size)
	item.add_theme_color_override("font_color", MUTED)
	item.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	parent.add_child(item)
	return item

static func button(parent: Node, title: String, bounds: Rect2, text: String, action: Callable) -> Button:
	var item := Button.new()
	item.name = title
	item.position = bounds.position
	item.size = bounds.size
	item.text = text
	item.add_theme_font_override("font", FONT)
	item.add_theme_font_size_override("font_size", 16)
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color.WHITE if state != "disabled" else Color("e8edf3")
		style.set_corner_radius_all(12)
		if state == "focus":
			style.border_color = BLUE
			style.set_border_width_all(2)
		item.add_theme_stylebox_override(state, style)
	item.add_theme_color_override("font_color", BLUE)
	item.add_theme_color_override("font_hover_color", BLUE)
	item.add_theme_color_override("font_pressed_color", BLUE)
	item.pressed.connect(action)
	parent.add_child(item)
	return item

static func tint_button(item: BlockComponent, color: Color, ink: Color) -> void:
	# Keep the real BlockComponent event/menu machinery. A native surface avoids
	# the legacy glass shader's instance-color transform and preserves this color.
	item.material = null
	item.color = Color.TRANSPARENT
	item.set_meta(&"claude_node_surface", true)
	var surface := item.get_node_or_null("ReferenceButtonSurface") as Panel
	if not is_instance_valid(surface):
		surface = panel(item, "ReferenceButtonSurface", Rect2(Vector2.ZERO, item.base_size), color, mini(18, int(item.base_size.y / 2)))
		item.move_child(surface, 0)
	var style := surface.get_theme_stylebox("panel") as StyleBoxFlat
	style.bg_color = color
	surface.size = item.base_size
	item.label.material = null
	item.label.add_theme_color_override("font_color", ink)
	item.label.add_theme_font_override("font", FONT)
	item._align_label()

static func dots_icon() -> Texture2D:
	var source := '<svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 18 18"><g fill="#247ec1"><circle cx="4" cy="9" r="1.5"/><circle cx="9" cy="9" r="1.5"/><circle cx="14" cy="9" r="1.5"/></g></svg>'
	var drawing := Image.new()
	drawing.load_svg_from_string(source)
	return ImageTexture.create_from_image(drawing)

static func title_font(item: Label) -> void:
	var face := FontVariation.new()
	face.base_font = FONT
	face.variation_opentype = {0x77676874: 600.0}
	item.add_theme_font_override("font", face)
