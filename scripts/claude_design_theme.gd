class_name ClaudeDesignTheme
extends RefCounted
## Native control theme translated from Claude's v23 light workspace.
## This factory is presentation-only: it does not read or change app state.

const PAGE := Color("f5f6f3")
const WASH := Color("f5f6f3")
const WASH_SOFT := Color("f0f3ef")
const CANVAS := Color("ffffff")
const DOT := Color("e1e6df")
const INK := Color("16161b")
const INK_SECONDARY := Color("565663")
const INK_MUTED := Color("6f6f7d")
const LINE := Color("e1e5df")
const LINE_STRONG := Color("ccd4cb")
const FILL := Color("f0f3ef")
const FILL_HOVER := Color("e7ece5")
const PRIMARY := Color("306b59")
const PRIMARY_SOFT := Color("e9f1eb")
const PRIMARY_EDGE := Color("245444")
const AXON := Color("306b59")
const AXON_DEEP := Color("306b59")
const AXON_SOFT := Color("e9f1eb")
const AXON_HOVER := Color("e0ebe2")
const SUCCESS := Color("075c3f")
const SUCCESS_SOFT := Color("dcf4ea")
const DANGER := Color("9d1f34")
const DANGER_SOFT := Color("fde4e8")
const WARNING := Color("a85f00")
const WARNING_SOFT := Color("fff0d4")

# Top, body, connector, and text colours are distinct so pastel nodes stay legible.
const INPUT_TOP := Color("fbe96b")
const INPUT_SOFT := Color("fff2b6")
const INPUT_WIRE := Color("e9b816")
const INPUT_INK := Color("6f5400")
const LAYER_TOP := Color("8fe0c8")
const LAYER_SOFT := Color("d2f3e8")
const LAYER_WIRE := Color("19b79a")
const LAYER_INK := Color("07665a")
const ACTIVATION_TOP := Color("a3b0ff")
const ACTIVATION_SOFT := Color("dde2ff")
const ACTIVATION_WIRE := Color("6a7cf5")
const ACTIVATION_INK := Color("3340b8")
const SHAPE_TOP := Color("f5a9e0")
const SHAPE_SOFT := Color("fbd8f1")
const SHAPE_WIRE := Color("de5fbd")
const SHAPE_INK := Color("94227c")
const OUTPUT_TOP := Color("ffb783")
const OUTPUT_SOFT := Color("ffe0c6")
const OUTPUT_WIRE := Color("f08a2a")
const OUTPUT_INK := Color("a64300")
const DATASET_TOP := INPUT_TOP
const DATASET_SOFT := INPUT_SOFT
const DATASET_WIRE := INPUT_WIRE
const DATASET_INK := INPUT_INK
const TRAINING_TOP := Color("94d6ff")
const TRAINING_SOFT := Color("d0ebff")
const TRAINING_WIRE := Color("279ed9")
const TRAINING_INK := Color("0a5a9f")

const CONTROL_MIN_HEIGHT := 44
const CONTROL_RADIUS := 6
const CARD_RADIUS := 16
const PANEL_RADIUS := CARD_RADIUS
const CAPSULE_RADIUS := 48
const NODE_RADIUS := 34
const SPACE_SMALL := 8
const SPACE_MEDIUM := 13
const SPACE_LARGE := 21
const UI_FONT_SIZE := 14
const CAPTION_FONT_SIZE := 13
const UI_FONT_PATH := "res://game_assets/fonts/GolosText[wght].ttf"
const DISPLAY_FONT_PATH := "res://game_assets/fonts/Nunito[wght].ttf"
const MONO_FONT_PATH := "res://game_assets/fonts/JetBrainsMono-VariableFont_wght.ttf"


static func box(background: Color, border: Color = LINE, radius: int = CONTROL_RADIUS,
		padding: Vector2 = Vector2(14, 14), border_width: int = 1) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(radius)
	style.content_margin_left = padding.x
	style.content_margin_right = padding.x
	style.content_margin_top = padding.y
	style.content_margin_bottom = padding.y
	return style


static func focus_box(radius: int = CONTROL_RADIUS) -> StyleBoxFlat:
	var style := box(Color.TRANSPARENT, PRIMARY, radius, Vector2.ZERO, 2)
	style.draw_center = false
	style.set_expand_margin_all(3.0)
	return style


static func create_theme() -> Theme:
	var theme := Theme.new()
	theme.default_font_size = UI_FONT_SIZE
	var regular := _local_font(UI_FONT_PATH)
	var mono := _local_font(MONO_FONT_PATH)
	if regular != null:
		theme.default_font = regular
	var bold := FontVariation.new()
	bold.base_font = _local_font(DISPLAY_FONT_PATH)
	bold.variation_opentype = {0x77676874: 800.0}
	for control in ["Button", "OptionButton", "Label", "LineEdit", "TextEdit", "PopupMenu", "Tree", "TabContainer", "TabBar", "ProgressBar"]:
		theme.set_font_size("font_size", control, UI_FONT_SIZE)
		theme.set_color("font_color", control, INK)
		theme.set_color("font_outline_color", control, Color.TRANSPARENT)
		theme.set_constant("outline_size", control, 0)

	_buttons(theme)
	_fields(theme)
	_panels_and_text(theme, bold, mono)
	_tabs(theme)
	_popup(theme)
	_tree(theme)
	_scrollbars(theme)
	theme.set_stylebox("background", "ProgressBar", box(FILL, LINE, 8, Vector2(0, 4), 0))
	theme.set_stylebox("fill", "ProgressBar", box(PRIMARY, PRIMARY, 8, Vector2.ZERO, 0))
	theme.set_color("font_color", "ProgressBar", INK)
	theme.set_constant("separation", "HBoxContainer", SPACE_SMALL)
	theme.set_constant("separation", "VBoxContainer", SPACE_SMALL)
	theme.set_constant("h_separation", "GridContainer", SPACE_MEDIUM)
	theme.set_constant("v_separation", "GridContainer", SPACE_MEDIUM)
	return theme


static func _local_font(path: String) -> Font:
	if ResourceLoader.exists(path):
		return load(path) as Font
	return null


static func _button(theme: Theme, type: String, normal: Color, hover: Color,
		pressed: Color, foreground: Color, border: Color) -> void:
	theme.set_stylebox("normal", type, box(normal, border, CONTROL_RADIUS, Vector2(20, 14)))
	theme.set_stylebox("hover", type, box(hover, border, CONTROL_RADIUS, Vector2(20, 14)))
	theme.set_stylebox("pressed", type, box(pressed, border, CONTROL_RADIUS, Vector2(20, 14)))
	theme.set_stylebox("disabled", type, box(FILL, LINE, CONTROL_RADIUS, Vector2(20, 14)))
	theme.set_stylebox("focus", type, focus_box(CONTROL_RADIUS))
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color", "icon_normal_color", "icon_hover_color", "icon_pressed_color", "icon_hover_pressed_color", "icon_focus_color"]:
		theme.set_color(state, type, foreground)
	theme.set_color("font_disabled_color", type, INK_MUTED)
	theme.set_color("icon_disabled_color", type, INK_MUTED)
	theme.set_constant("h_separation", type, SPACE_SMALL)


static func _buttons(theme: Theme) -> void:
	_button(theme, "Button", CANVAS, FILL, FILL_HOVER, INK, LINE_STRONG)
	_button(theme, "OptionButton", FILL, FILL_HOVER, CANVAS, INK, LINE_STRONG)
	theme.set_icon("arrow", "OptionButton", _icon("M6 9l6 6 6-6", INK_SECONDARY))
	theme.set_constant("arrow_margin", "OptionButton", 14)
	theme.set_constant("modulate_arrow", "OptionButton", 0)
	for state in ["normal", "hover", "pressed", "disabled"]:
		theme.set_stylebox(state + "_mirrored", "OptionButton", theme.get_stylebox(state, "OptionButton"))
	for variant in ["ClaudePrimaryButton", "ClaudeAxonButton", "ClaudeDangerButton", "ClaudeTabButton"]:
		theme.set_type_variation(variant, "Button")
	_button(theme, "ClaudePrimaryButton", PRIMARY, Color("397d69"), PRIMARY_EDGE, CANVAS, PRIMARY_EDGE)
	var primary_normal := theme.get_stylebox("normal", "ClaudePrimaryButton") as StyleBoxFlat
	primary_normal.shadow_color = PRIMARY_EDGE
	primary_normal.shadow_size = 1
	primary_normal.shadow_offset = Vector2(0, 3)
	_button(theme, "ClaudeAxonButton", CANVAS, PRIMARY_SOFT, FILL_HOVER, PRIMARY, LINE)
	_button(theme, "ClaudeDangerButton", DANGER_SOFT, Color("fbd0d7"), Color("f6bdc7"), DANGER, DANGER_SOFT)
	_button(theme, "ClaudeTabButton", CANVAS, FILL, INK, INK_SECONDARY, Color.TRANSPARENT)
	theme.set_color("font_pressed_color", "ClaudeTabButton", CANVAS)
	theme.set_color("font_hover_pressed_color", "ClaudeTabButton", CANVAS)
	theme.set_color("icon_pressed_color", "ClaudeTabButton", CANVAS)
	theme.set_color("icon_hover_pressed_color", "ClaudeTabButton", CANVAS)


static func _fields(theme: Theme) -> void:
	for type in ["LineEdit", "TextEdit"]:
		theme.set_stylebox("normal", type, box(FILL, LINE_STRONG))
		theme.set_stylebox("read_only", type, box(PAGE, LINE))
		theme.set_stylebox("focus", type, focus_box())
		theme.set_color("font_color", type, INK)
		theme.set_color("font_placeholder_color", type, INK_MUTED)
		theme.set_color("font_selected_color", type, INK)
		theme.set_color("selection_color", type, PRIMARY_SOFT)
		theme.set_color("caret_color", type, PRIMARY)
		theme.set_constant("caret_width", type, 2)
	theme.set_color("font_uneditable_color", "LineEdit", INK_SECONDARY)
	theme.set_color("clear_button_color", "LineEdit", INK_SECONDARY)
	theme.set_color("clear_button_color_pressed", "LineEdit", PRIMARY)
	theme.set_constant("minimum_character_width", "LineEdit", 3)
	theme.set_icon("clear", "LineEdit", _icon("M6 6l12 12M18 6L6 18", CANVAS))
	theme.set_color("background_color", "TextEdit", Color.TRANSPARENT)
	theme.set_color("font_readonly_color", "TextEdit", INK_SECONDARY)
	theme.set_color("current_line_color", "TextEdit", WASH_SOFT)
	theme.set_color("caret_background_color", "TextEdit", CANVAS)
	theme.set_color("word_highlighted_color", "TextEdit", ACTIVATION_SOFT)
	theme.set_color("search_result_color", "TextEdit", INPUT_SOFT)
	theme.set_color("search_result_border_color", "TextEdit", INPUT_INK)
	theme.set_constant("line_spacing", "TextEdit", 4)


static func _panels_and_text(theme: Theme, bold: Font, mono: Font) -> void:
	theme.set_stylebox("panel", "PanelContainer", box(CANVAS, LINE, PANEL_RADIUS, Vector2(21, 21)))
	theme.set_stylebox("panel", "Panel", box(CANVAS, LINE, PANEL_RADIUS, Vector2.ZERO))
	for variant in ["ClaudeCard", "ClaudeSoftPanel", "ClaudeTransparentPanel"]:
		theme.set_type_variation(variant, "PanelContainer")
	theme.set_stylebox("panel", "ClaudeCard", box(CANVAS, LINE, PANEL_RADIUS, Vector2(21, 21)))
	theme.set_stylebox("panel", "ClaudeSoftPanel", box(FILL, FILL, 21, Vector2(13, 13), 0))
	theme.set_stylebox("panel", "ClaudeTransparentPanel", box(Color.TRANSPARENT, Color.TRANSPARENT, 0, Vector2.ZERO, 0))
	for variant in ["ClaudeHeading", "ClaudeMutedLabel", "ClaudeMonoLabel"]:
		theme.set_type_variation(variant, "Label")
	theme.set_font("font", "ClaudeHeading", bold)
	theme.set_font_size("font_size", "ClaudeHeading", 24)
	theme.set_color("font_color", "ClaudeMutedLabel", INK_SECONDARY)
	if mono != null:
		theme.set_font("font", "ClaudeMonoLabel", mono)
		theme.set_font("mono_font", "RichTextLabel", mono)
	theme.set_color("default_color", "RichTextLabel", INK)
	theme.set_color("font_selected_color", "RichTextLabel", INK)
	theme.set_color("selection_color", "RichTextLabel", TRAINING_SOFT)
	theme.set_color("font_outline_color", "RichTextLabel", Color.TRANSPARENT)
	theme.set_font("bold_font", "RichTextLabel", bold)
	theme.set_font_size("normal_font_size", "RichTextLabel", UI_FONT_SIZE)
	theme.set_font_size("bold_font_size", "RichTextLabel", UI_FONT_SIZE)
	theme.set_font_size("mono_font_size", "RichTextLabel", UI_FONT_SIZE)
	theme.set_constant("outline_size", "RichTextLabel", 0)
	theme.set_constant("line_separation", "RichTextLabel", 4)
	theme.set_stylebox("normal", "RichTextLabel", box(Color.TRANSPARENT, Color.TRANSPARENT, 0, Vector2.ZERO, 0))
	theme.set_stylebox("focus", "RichTextLabel", focus_box())


static func _tabs(theme: Theme) -> void:
	for type in ["TabBar", "TabContainer"]:
		theme.set_stylebox("tab_selected", type, box(INK, INK, 22, Vector2(18, 14), 0))
		theme.set_stylebox("tab_unselected", type, box(CANVAS, CANVAS, 22, Vector2(18, 14), 0))
		theme.set_stylebox("tab_hovered", type, box(FILL, FILL, 22, Vector2(18, 14), 0))
		theme.set_stylebox("tab_disabled", type, box(PAGE, PAGE, 22, Vector2(18, 14), 0))
		theme.set_stylebox("tab_focus", type, focus_box(22))
		for prefix in ["font_", "icon_"]:
			theme.set_color(prefix + "selected_color", type, CANVAS)
			theme.set_color(prefix + "unselected_color", type, INK_SECONDARY)
			theme.set_color(prefix + "hovered_color", type, INK)
			theme.set_color(prefix + "disabled_color", type, INK_MUTED)
		for suffix in ["", "_highlight"]:
			theme.set_icon("increment" + suffix, type, _icon("M9 6l6 6-6 6", INK_SECONDARY))
			theme.set_icon("decrement" + suffix, type, _icon("M15 6l-6 6 6 6", INK_SECONDARY))
	theme.set_stylebox("panel", "TabContainer", box(CANVAS, LINE, PANEL_RADIUS, Vector2(13, 13)))
	theme.set_stylebox("tabbar_background", "TabContainer", box(CANVAS, LINE, 24, Vector2(4, 4)))
	theme.set_constant("side_margin", "TabContainer", SPACE_SMALL)
	theme.set_constant("icon_separation", "TabContainer", SPACE_SMALL)


static func _popup(theme: Theme) -> void:
	theme.set_stylebox("panel", "PopupMenu", box(CANVAS, LINE_STRONG, CARD_RADIUS, Vector2(8, 8)))
	theme.set_stylebox("hover", "PopupMenu", box(FILL, FILL, CONTROL_RADIUS, Vector2(8, 8), 0))
	theme.set_stylebox("separator", "PopupMenu", box(LINE, LINE, 0, Vector2(0, 1), 0))
	theme.set_color("font_hover_color", "PopupMenu", INK)
	theme.set_color("font_disabled_color", "PopupMenu", INK_MUTED)
	theme.set_color("font_accelerator_color", "PopupMenu", INK_SECONDARY)
	theme.set_color("font_separator_color", "PopupMenu", INK_SECONDARY)
	theme.set_constant("v_separation", "PopupMenu", 24)
	theme.set_constant("h_separation", "PopupMenu", SPACE_SMALL)
	theme.set_constant("item_start_padding", "PopupMenu", SPACE_SMALL)
	theme.set_constant("item_end_padding", "PopupMenu", SPACE_SMALL)
	theme.set_icon("submenu", "PopupMenu", _icon("M9 6l6 6-6 6", INK_SECONDARY))
	theme.set_icon("submenu_mirrored", "PopupMenu", _icon("M15 6l-6 6 6 6", INK_SECONDARY))
	_check_icons(theme, "PopupMenu")


static func _tree(theme: Theme) -> void:
	theme.set_stylebox("panel", "Tree", box(CANVAS, LINE, 14, Vector2(8, 8)))
	theme.set_stylebox("focus", "Tree", focus_box())
	for name in ["selected", "selected_focus", "hovered_selected", "hovered_selected_focus"]:
		theme.set_stylebox(name, "Tree", box(PRIMARY_SOFT, PRIMARY, 10, Vector2(8, 6)))
	for name in ["hovered", "hovered_dimmed", "button_hover", "custom_button_hover", "title_button_hover"]:
		theme.set_stylebox(name, "Tree", box(FILL, FILL, 10, Vector2(8, 6), 0))
	for name in ["button_pressed", "custom_button_pressed", "title_button_pressed"]:
		theme.set_stylebox(name, "Tree", box(FILL_HOVER, LINE, 10, Vector2(8, 6)))
	theme.set_stylebox("title_button_normal", "Tree", box(PAGE, LINE, 10, Vector2(8, 14)))
	theme.set_stylebox("custom_button", "Tree", box(CANVAS, LINE, 10, Vector2(8, 6)))
	for name in ["font_selected_color", "font_hovered_color", "font_hovered_selected_color", "title_button_color", "custom_button_font_highlight"]:
		theme.set_color(name, "Tree", INK)
	theme.set_color("font_hovered_dimmed_color", "Tree", INK_SECONDARY)
	theme.set_color("font_disabled_color", "Tree", INK_MUTED)
	theme.set_color("guide_color", "Tree", LINE)
	theme.set_color("relationship_line_color", "Tree", LINE_STRONG)
	theme.set_color("drop_position_color", "Tree", PRIMARY)
	theme.set_color("drop_on_item_color", "Tree", PRIMARY)
	theme.set_constant("v_separation", "Tree", 24)
	theme.set_constant("h_separation", "Tree", SPACE_SMALL)
	theme.set_icon("arrow", "Tree", _icon("M6 9l6 6 6-6", INK_SECONDARY))
	theme.set_icon("arrow_collapsed", "Tree", _icon("M9 6l6 6-6 6", INK_SECONDARY))
	theme.set_icon("arrow_collapsed_mirrored", "Tree", _icon("M15 6l-6 6 6 6", INK_SECONDARY))
	theme.set_icon("select_arrow", "Tree", _icon("M6 9l6 6 6-6", INK_SECONDARY))
	_check_icons(theme, "Tree")


static func _check_icons(theme: Theme, type: String) -> void:
	for suffix in ["", "_disabled"]:
		var color := INK_MUTED if not suffix.is_empty() else PRIMARY
		theme.set_icon("checked" + suffix, type, _icon("M4 4h16v16H4zM7 12l3 3 7-7", color))
		theme.set_icon("unchecked" + suffix, type, _icon("M4 4h16v16H4z", INK_MUTED))
		if type == "Tree":
			theme.set_icon("indeterminate" + suffix, type, _icon("M4 4h16v16H4zM8 12h8", color))
		else:
			theme.set_icon("radio_checked" + suffix, type, _icon("M12 4a8 8 0 1 0 0 16a8 8 0 1 0 0-16M9 12h6", color))
			theme.set_icon("radio_unchecked" + suffix, type, _icon("M12 4a8 8 0 1 0 0 16a8 8 0 1 0 0-16", INK_MUTED))


static func _scrollbars(theme: Theme) -> void:
	var empty_icon := ImageTexture.create_from_image(Image.create(1, 1, false, Image.FORMAT_RGBA8))
	for type in ["HScrollBar", "VScrollBar"]:
		theme.set_stylebox("scroll", type, box(PAGE, PAGE, 6, Vector2(6, 6), 0))
		theme.set_stylebox("scroll_focus", type, focus_box(6))
		theme.set_stylebox("grabber", type, box(LINE_STRONG, LINE_STRONG, 6, Vector2(6, 6), 0))
		theme.set_stylebox("grabber_highlight", type, box(INK_MUTED, INK_MUTED, 6, Vector2(6, 6), 0))
		theme.set_stylebox("grabber_pressed", type, box(PRIMARY, PRIMARY, 6, Vector2(6, 6), 0))
		for name in ["increment", "decrement", "increment_highlight", "decrement_highlight", "increment_pressed", "decrement_pressed"]:
			theme.set_icon(name, type, empty_icon)


static func _icon(path_data: String, color: Color) -> Texture2D:
	var svg := '<svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24"><path d="%s" fill="none" stroke="#%s" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/></svg>' % [path_data, color.to_html(false)]
	var image := Image.new()
	if image.load_svg_from_string(svg) != OK:
		return null
	return ImageTexture.create_from_image(image)
