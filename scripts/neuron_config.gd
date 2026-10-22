extends Graph

@onready var dropout = $ColorRect2

func _after_ready():
	super()
	var inner := Panel.new()
	inner.name = "ActivationSurface"
	inner.position = Vector2(-35, -62)
	inner.size = Vector2(92, 78)
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var white_surface := StyleBoxFlat.new()
	white_surface.bg_color = Color.WHITE
	white_surface.set_corner_radius_all(18)
	inner.add_theme_stylebox_override("panel", white_surface)
	add_child(inner)
	move_child(inner, dropout.get_index())
	dropout.set_meta(&"reference_preserve_style", true)
	dropout.material = dropout.material.duplicate()
	dropout.material.set_shader_parameter("blurred_background", false)
	dropout.material.set_shader_parameter("corner_radius", 12.0)
	dropout.material.set_shader_parameter("outline_width", 0.0)
	dropout.material.set_shader_parameter("mult_tuning", Color.WHITE)
	dropout.material.set_shader_parameter("color_mult", Color.WHITE)
	dropout.set_instance_shader_parameter("tuning", Color("e2e0ff"))
	dropout.base_tuning = Color("e2e0ff")
	dropout.color = Color.WHITE
	dropout.text_color = Color.WHITE
	dropout.label.set_meta(&"reference_preserve_style", true)
	dropout.label.add_theme_color_override("font_color", _DESIGN.ACTIVATION_INK)
	activ_show("none")

func _config_field(field: StringName, value: Variant):
	if field == "activ":
		selected_activation = value
		activ_show(selected_activation)
		if value in dropout.button_by_hint:
			dropout.text = dropout.button_by_hint[value].text

var selected_activation: StringName = &"none"

func activ_show(hint: String):
	match hint:
		"none":
			$plot/plot.load_dump(func(x): return x, Vector2(0.0, 20.0), 1)
		"relu":
			$plot/plot.load_dump(func(x): return max(x,0.0), Vector2(0.35, 20.0), 1)
		"sigmoid":
			$plot/plot.load_dump(
				func(x): return 1.0 / (1.0 + exp(-5.0 * x)),
				Vector2(0.5, 22.0),
				1
			)
		"tanh":
			$plot/plot.load_dump(
				func(x):
					var s = 1.0 / (1.0 + exp(-2.0 * x))
					return 2.0 * s - 1.0,
				Vector2(0.0, 18.0),
				1
			)

func _on_color_rect_2_child_button_release(button: BlockComponent) -> void:
	#button.is_contained.text = button.text
	open_undo_redo()
	update_config({"activ": button.hint})
	close_undo_redo()
	#selected_activation = button.hint
	button.is_contained.menu_hide()

@onready var list = $ColorRect2
func _proceed_hold() -> bool:
	return list.current_type == BlockComponent.ButtonType.CONTEXT_MENU
