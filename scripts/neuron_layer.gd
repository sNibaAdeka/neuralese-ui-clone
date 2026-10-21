extends BaseNeuronLayer
class_name NeuronLayer


func _after_ready() -> void:
	super()
	var count_surface := Panel.new()
	count_surface.name = "CountSurface"
	count_surface.position = Vector2(-21, -13)
	count_surface.size = Vector2(92, 28)
	count_surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var count_style := StyleBoxFlat.new()
	count_style.bg_color = Color.WHITE
	count_style.set_corner_radius_all(14)
	count_surface.add_theme_stylebox_override("panel", count_style)
	add_child(count_surface)
	move_child(count_surface, get_node("LineEdit").get_index())
	line_edit.base_text_color = Color("147d71")
	line_edit.add_theme_color_override("font_color", Color("147d71"))
	line_edit.add_theme_color_override("font_uneditable_color", Color("147d71"))
	for state in ["normal", "read_only", "focus"]:
		var field_style := StyleBoxFlat.new()
		field_style.bg_color = Color.TRANSPARENT
		field_style.content_margin_left = 2
		field_style.content_margin_right = 2
		field_style.set_corner_radius_all(10)
		if state == "focus":
			field_style.set_border_width_all(1)
			field_style.border_color = Color("14b69b")
		line_edit.add_theme_stylebox_override(state, field_style)
	for action in [$DecreaseCount, $IncreaseCount]:
		action.add_theme_color_override("font_color", Color("158d7d"))
		action.add_theme_color_override("font_hover_color", Color("087464"))
		action.add_theme_color_override("font_pressed_color", Color("087464"))
		for state in ["normal", "hover", "pressed", "disabled", "focus"]:
			var style := StyleBoxFlat.new()
			style.bg_color = Color("e8fbf4") if state == "normal" else Color("cef2e6")
			style.set_corner_radius_all(14)
			style.set_border_width_all(2)
			style.border_color = Color("14b69b") if state == "focus" else Color.WHITE
			action.add_theme_stylebox_override(state, style)
	_neurons_fix_set(neurons_fixed)


func _useful_properties() -> Dictionary:
	#assert (input_keys[0].inputs, "no config. TODO: implement error handling")
	var conf = {"activation": "none"}
	if input_keys[0].inputs:
		conf["activation"] = input_keys[0].inputs.keys()[0].origin.parent_graph.selected_activation
	return {
	"neuron_count": _real_amount,
	"config": conf,
	"cache_tag": str(graph_id)
	}

func _neurons_fix_set(v: bool):
	for path in ["DecreaseCount", "IncreaseCount"]:
		var action := get_node_or_null(path) as Button
		if action:
			action.disabled = v
	if v:
		ui.line_block(line_edit)
	else:
		ui.line_unblock(line_edit)

func _layout_size():
	return Vector2(rect.size.x, target_size)

func push_neuron_count(parsed: int):
	update_config({"neuron_count": parsed})

@export var group_size: int = 1:
	set(value):
		group_size = max(1, value)
		_apply_grouping()

var _real_amount: int = 0
@onready var base_size_add: float = size_add

func _get_unit(kw: Dictionary) -> Control:
	var dup = _unit.duplicate()
	dup.modulate.a = 0.0
	dup.show()
	return dup

func _get_info() -> Dictionary:
	return {
		"position": position,
		"neuron_count": cfg.neuron_count,
	}

var last_resized: int = 0
func _size_changed():
	$ni.position.y = (rect.size.y) / 2 + rect.position.y - $ni.size.y / 2
	$o.position.y = (rect.size.y) / 2 + rect.position.y - $o.size.y / 2
	reposition_splines()
	last_resized = 0
	hold_for_frame()

func _dragged():
	last_resized = 0

func _after_process(delta:float):
	if _unit:
		super(delta)
	last_resized += 1
	if last_resized < 20:
		if len(units) > max_units:
			var extents = Vector4(rect.global_position.y, rect.global_position.y + rect.size.y, 0, 0)
			units[-1].set_extents(extents)
			units[0].set_extents(extents)
		elif units:
			units[0].set_extents(Vector4())

func _just_connected(who: Connection, to: Connection):
	graphs.push_1d(_real_amount, self)

func _just_disconnected(who: Connection, from: Connection):
	pass

func _unit_modulate_updated(of: Control, fin: bool = false, diss: bool = false):
	var extents
	var key = key_by_unit[of]
	if not fin or (len(units) > max_units-1 and key == max_units):
		extents = Vector4(rect.global_position.y, rect.global_position.y + rect.size.y, 0, 0)
	else:
		extents = Vector4()
	of.set_extents(extents)

@export var max_units = 20

# The card is a diagram of a dense layer, not a list of its model neurons.
# Keep the exact model width in cfg/_real_amount and show at most three markers,
# as in the supplied design. In particular, 128 neurons must never become 3.
const REPRESENTATIVE_UNIT_LIMIT := 3

func _apply_grouping() -> void:
	var visible_units := mini(_real_amount, REPRESENTATIVE_UNIT_LIMIT)
	size_add = base_size_add

	var length = len(units)
	if length > visible_units:
		for i in range(length - visible_units):
			remove_unit(length - i - 1)
	elif length < visible_units:
		for i in range(visible_units - length):
			add_unit({}, true)

	for marker in units:
		marker.set_text(1)
		marker.tooltip_text = "Условное изображение слоя. Число нейронов: %d" % _real_amount


func _change_neuron_count(amount: int) -> void:
	if neurons_fixed or is_blocked:
		return
	var next_count := clampi(_real_amount + amount, int(line_edit.min_value), int(line_edit.max_value))
	if next_count == _real_amount:
		return
	open_undo_redo(true)
	update_config({"neuron_count": next_count})
	close_undo_redo()

var neuron_count: int = 0
func _config_field(field: StringName, val: Variant):
	match field:
		"neuron_count":
			#(val)
			#val = int(val)
			if 1:#not neurons_fixed:
				neuron_count = val
				line_edit.set_line(str(val))
				_real_amount = max(0, val)
				_apply_grouping()
				for i in get_first_descendants():
					if i.server_typename == "Reshape2D":
						i.update_config({"rows": i.cfg.rows, "columns": i.cfg.columns})
				hold_for_frame()
				#await get_tree().process_frame
				graphs.push_1d(_real_amount, self)
		
			

func _get_x() -> Variant:
	return _real_amount

func re_upd():
	graphs.push_1d(_real_amount, self)

func _on_line_edit_changed() -> void:
	await get_tree().process_frame
	update_config({"neuron_count": int($LineEdit.get_value())})
	#_apply_grouping()


func _on_line_edit_submitted_1(new_text: String) -> void:
	await get_tree().process_frame
	open_undo_redo()
	update_config({"neuron_count": int($LineEdit.get_value())})
	close_undo_redo()
