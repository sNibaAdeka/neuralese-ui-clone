extends Node
## Applies the v23 palette to native screens as they are created. Business logic
## remains in the existing dialogs, dataset editor and simulation editor.
const Design = preload("res://scripts/claude_design_theme.gd")
var native_theme: Theme

func _ready() -> void:
	native_theme = Design.create_theme()
	get_tree().node_added.connect(_queue_style)
	_style_branch.call_deferred(get_tree().root)

func _queue_style(node: Node) -> void:
	_style_later.call_deferred(node.get_instance_id())

func _style_later(instance_id: int) -> void:
	# A project reload can free temporary controls before the deferred call.
	var node = instance_from_id(instance_id)
	if not is_instance_valid(node): return
	if not node.is_node_ready(): await node.ready
	if is_instance_valid(node): _style(node)

func _style_branch(node: Node) -> void:
	_style(node)
	for child in node.get_children(): _style_branch(child)

func _style(node: Node) -> void:
	if not node is Control or node.has_meta("claude_styled"): return
	# Graph nodes own their semantic colours; leave their native sizing intact.
	var ancestor := node.get_parent()
	while ancestor != null:
		if ancestor is Graph or ancestor.has_meta("claude_design_owned"): return
		ancestor = ancestor.get_parent()
	var control := node as Control
	if str(control.theme_type_variation).begins_with("Claude"): return
	control.set_meta("claude_styled", true)
	var old_font_size := control.get_theme_font_size("font_size")
	control.theme = native_theme
	if old_font_size > 0:
		control.add_theme_font_size_override("font_size", old_font_size)
	if control is Label or control is LineEdit or control is TextEdit or control is Button:
		control.add_theme_color_override("font_color", Design.INK)
		control.add_theme_color_override("font_outline_color", Color.TRANSPARENT)
		control.add_theme_constant_override("outline_size", 0)
	if control is RichTextLabel:
		control.add_theme_color_override("default_color", Design.INK)
		for state in ["normal", "focus"]:
			var rich_style := control.get_theme_stylebox(state)
			if rich_style is StyleBoxFlat:
				var light_style := rich_style.duplicate() as StyleBoxFlat
				light_style.bg_color = Design.CANVAS
				light_style.border_color = Design.LINE
				control.add_theme_stylebox_override(state, light_style)
	if control is Label and control.modulate.r > 0.65 and control.modulate.g > 0.65:
		control.modulate = Color(1, 1, 1, control.modulate.a)
	if control is LineEdit or control is TextEdit:
		for style in ["normal", "focus", "read_only"]:
			control.remove_theme_stylebox_override(style)
	if control is PanelContainer:
		control.add_theme_stylebox_override("panel", Design.box(Design.CANVAS, Design.LINE, Design.CARD_RADIUS, Vector2(13, 13)))
	if control is BlockComponent:
		control.text_color = control.get_meta("claude_text_color", Design.INK)
		control.base_tuning = Design.CANVAS
	if control is ColorRect and control.material is ShaderMaterial:
		var shader_path: String = control.material.shader.resource_path if control.material.shader != null else ""
		if shader_path in ["res://shaders/block.gdshader", "res://shaders/block_screen.gdshader"]:
			var material := control.material.duplicate() as ShaderMaterial
			material.set_shader_parameter("blurred_background", false)
			material.set_shader_parameter("mult_tuning", Color.WHITE)
			material.set_shader_parameter("color_mult", Color.WHITE)
			material.set_shader_parameter("outline_width", 1.0)
			material.set_shader_parameter("corner_radius", 14.0)
			control.material = material
			control.set_instance_shader_parameter("tuning", Design.CANVAS)
			control.set_instance_shader_parameter("outline_color", Design.LINE_STRONG)
			# Authored semantic accents (for example Skip tutorial) remain legible
			# against the light shader surface instead of being erased by the theme.
			if not bool(control.get_meta("claude_preserve_accent", false)):
				control.color = Color.WHITE
	if control is TextureButton:
		control.self_modulate = Design.INK_SECONDARY
