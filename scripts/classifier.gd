extends DynamicGraph
class_name OutputGraph

var value_cache: Array = []
var manually: bool = false
var _labels_expanded := false
var _reference_panel: Panel
var _labels_toggle: Button
var _empty_labels: Label


func _after_ready() -> void:
	super()
	_reference_panel = Panel.new()
	_reference_panel.name = "ProbabilityPanel"
	_reference_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_reference_panel.z_index = 1
	var surface := StyleBoxFlat.new()
	surface.bg_color = Color.WHITE
	surface.set_corner_radius_all(14)
	_reference_panel.add_theme_stylebox_override("panel", surface)
	add_child(_reference_panel)
	move_child(_reference_panel, 1)
	_labels_toggle = Button.new()
	_labels_toggle.name = "EditLabels"
	_labels_toggle.text = "+"
	_labels_toggle.tooltip_text = "Добавить класс" if glob.get_lang() == "ru" else "Add a class"
	_labels_toggle.z_index = 2
	_labels_toggle.add_theme_font_size_override("font_size", 14)
	_labels_toggle.add_theme_font_override("font", _CLAUDE_SANS)
	_labels_toggle.add_theme_color_override("font_color", Color("b96325"))
	for state in ["normal", "hover", "pressed", "focus"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color("fff4e9") if state == "normal" else Color.WHITE
		style.set_corner_radius_all(11)
		_labels_toggle.add_theme_stylebox_override(state, style)
	_labels_toggle.pressed.connect(_toggle_label_editor)
	add_child(_labels_toggle)
	_empty_labels = Label.new()
	_empty_labels.name = "EmptyLabels"
	_empty_labels.text = "Добавьте классы" if glob.get_lang() == "ru" else "Add classes"
	_empty_labels.add_theme_font_size_override("font_size", 12)
	_empty_labels.add_theme_font_override("font", _CLAUDE_SANS)
	_empty_labels.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty_labels.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_reference_panel.add_child(_empty_labels)
	_layout_reference_rows()


func _toggle_label_editor() -> void:
	_labels_expanded = not _labels_expanded
	_labels_toggle.text = "−" if _labels_expanded else "+"
	if not _labels_expanded:
		line_edit.release_focus()
	_layout_reference_rows()
	hold_for_frame()


func _layout_reference_rows() -> void:
	if not is_instance_valid(_reference_panel):
		return
	var list_height := maxf(36.0, units.size() * 16.0 + 8.0)
	_reference_panel.position = rect.position + Vector2(8, 32)
	_reference_panel.size = Vector2(160, list_height)
	_empty_labels.visible = units.is_empty()
	_empty_labels.position = Vector2(4, 8)
	_empty_labels.size = Vector2(152, 20)
	for index in units.size():
		units[index].position = rect.position + Vector2(8, 36 + index * 16)
		units[index].connect_position = units[index].position.y
	_labels_toggle.position = rect.position + Vector2(147, 6)
	_labels_toggle.size = Vector2(22, 22)
	input.visible = _labels_expanded
	input.position = rect.position + Vector2(8, 40 + list_height)
	var height := 40.0 + list_height + (58.0 if _labels_expanded else 0.0)
	var new_size := Vector2(176, height)
	if not rect.size.is_equal_approx(new_size):
		rect.size = new_size
		size_changed()
		$ni.position.y = rect.position.y + height * 0.5 - $ni.size.y * 0.5
		reposition_splines()

func unit_set(unit, value, text):
	units[unit].set_weight(value, text)

func _request_save():
	var res = []
	for i in units:
		res.append(i.get_node("Label").text)
	cfg["label_names"] = res

func set_names(names: Array):
	glob.open_action_batch(true)
	_config_field("label_names", names)
	await get_tree().process_frame
	await get_tree().process_frame
	glob.close_action_batch()
	if not glob.is_auto_action():
		glob.add_action(set_names.bind([]), func():
			#("ff")
			set_names(names.duplicate()))

func _config_field(field: StringName, value: Variant):
	if not manually and field == "label_names" and not trigger:
		#_stack()
		#_applying_labels += 1
		if units: return
		for i in len(units):
			remove_unit(0)
		for i in len(value):
			add_unit({"text": value[i]}, true)
		push_values(value_cache, per)
		#_applying_labels -= 1
		hold_for_frame()

	if not upd and field == "title":
		$ColorRect/root/Label.set_line(value)
		ch()


func _can_drag() -> bool:
	return super() and not ui.is_focus($ColorRect/root/Label) and not (
		is_instance_valid(_labels_toggle) and _labels_toggle.get_global_rect().has_point(get_global_mouse_position()))

func _proceed_hold() -> bool:
	return ui.is_focus($ColorRect/root/Label)


func get_title() -> String:
	return $ColorRect/root/Label.text if $ColorRect/root/Label.text else "LabelGroup"

var per: bool = false
func push_values(values: Array, percent: bool = false):
	value_cache = values.duplicate()
	per = percent
	var minimal = values.min() if !percent and not values.is_empty() else 0.0
	var maximal = values.max() if !percent and not values.is_empty() else 1.0
	var add = "%" if percent else ""
	for unit in len(values):
		var value = clampf(values[unit], 0.0, 1.0) if percent else clampf(float(values[unit]), 0.0, 1.0)
		if not percent and not is_equal_approx(float(maximal - minimal), 0.0):
			value = (values[unit] - minimal) / float(maximal - minimal)
		var capped = glob.cap(values[unit], 2) if !percent else roundi(values[unit]*100.0)
		if unit >= len(units): continue
		if percent:
			unit_set(unit, value, str(capped)+"%")
		else:
			unit_set(unit, value, str(capped))
	for unit in range(len(values), len(units)):
		# No inference result is different from a measured zero probability.
		unit_set(unit, 0.0, "—")

var _applying_labels: int = 0


func _get_unit(kw: Dictionary) -> Control: #virtual
	var dup = _unit.duplicate()
	dup.get_node("Label").text = kw["text"]
	dup.show()
	dup.modulate.a = 0.0
	appear_units[dup] = true
	#dup.size.y = randi_range(10,60)
#	dup.server_name = 
	return dup



func _unit_just_added() -> void:
#	if 1:#_applying_labels > 0:
#		var ancestor = get_first_ancestors()
#		push_values(value_cache, ancestor and ancestor[0].server_typename == "SoftmaxNode")
#		return

	var ancestor = get_first_ancestors()
	push_values(value_cache, per if ancestor.is_empty() else ancestor[0].server_typename == "SoftmaxNode")

	if not undo_redo_opened and not manually:
		glob.add_action(remove_unit.bind(len(units)-1), add_unit.bind(units[-1].get_meta("keyw")))
		#var res: Array = []
		#for i in units:
			#res.append(i.get_node("Label").text)
		#open_undo_redo(true)
		#manually = true
		#update_config({"label_names": res})
		#manually = false
		#close_undo_redo()
	for i in 3:
		await get_tree().process_frame
	var res = []
	for i in units:
		res.append(i.get_node("Label").text)
	cfg["label_names"] = res
	learner.notify_update()



	
func _deattaching(other_conn: Connection, my_conn: Connection):
	var ancestor = get_first_ancestors()
	if ancestor: 
		if ancestor[0].server_typename == "SoftmaxNode":
			push_values(value_cache, false)

var trigger: bool = false
func _unit_removal(id: int):
	#await get_tree().process_frame

	# Do not echo changes while we’re applying cfg→UI
	#if _applying_labels > 0:
	#	return

	if not glob.is_auto_action():
		var txt = units[id].get_node("Label").text
		var res = []
		for i in units:
			res.append(i.get_node("Label").text)
		cfg["label_names"] = res
		glob.add_action((
			func():
				var l = len(units)
				for i in l:
					remove_unit(0)
				for i in res:
					add_unit({"text": i}))
			, remove_unit.bind(id))
		#open_undo_redo(true)
		#trigger = true
		#update_config({"label_names": next})
		#(next)
		#trigger = false
		#close_undo_redo()




func _just_attached(other_conn: Connection, my_conn: Connection):
	graphs.push_1d(other_conn.parent_graph.get_x(), other_conn.parent_graph)
	if other_conn.parent_graph.server_typename == "SoftmaxNode":
		push_values(value_cache, true)
	else:
		push_values(value_cache, false)

var res_meta: Dictionary = {}
func push_result_meta(meta: Dictionary):
	res_meta = meta
	ch()


func _after_process(delta: float):
	super(delta)
	_layout_reference_rows()

func ch():
	var target = graphs._reach_input(self)
	if !target: return
	var got = graphs.get_input_name_by_graph(target)
	if got:
		graphs.model_updated.emit(got)

var upd = false
signal label_changed(text: String)
func _on_label_changed() -> void:
	ch()
	upd = true
	open_undo_redo(true)
	update_config({"title": $ColorRect/root/Label.text})
	close_undo_redo()
	upd = false
	#var netname = target.get_netname()
	#if netname:
	#	netname.reload()
	#label_changed.emit($ColorRect/root/Label.text)
