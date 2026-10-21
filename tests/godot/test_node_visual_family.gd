extends SceneTree

const Visual = preload("res://scripts/node_visual_family.gd")
const Design = preload("res://scripts/claude_design_theme.gd")
const Palette = preload("res://scripts/node_palette_item.gd")
const Catalog = preload("res://scripts/generated/node_catalog.gd")
var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var expected := {
		"input": &"data", "input_1d": &"data", "dataset": &"data",
		"layer": &"layer", "conv2d": &"layer", "gru_cell": &"layer",
		"neuron": &"operation", "maxpool": &"operation", "dropout": &"operation", "augment_tf": &"operation",
		"flatten": &"shape", "reshape2d": &"shape", "concat": &"shape",
		"softmax": &"output", "classifier": &"output",
		"train_begin": &"training", "train_input": &"training", "train_rl": &"training", "run_model": &"training",
		"model_name": &"neutral", "lua_env": &"neutral",
	}
	_expect(Catalog.DEFINITIONS.size() == expected.size(), "every registered type has an explicit expected family")
	for id in Catalog.DEFINITIONS:
		var definition: Dictionary = Catalog.DEFINITIONS[id]
		var graph = load(definition["source_path"]).instantiate()
		var contract: StringName = graph.server_typename
		var role: StringName = expected.get(String(id), &"missing")
		var colors := Visual.colors(role)
		_expect(graph._reference_visual_family() == role, "%s live family" % id)
		_expect(graph._claude_node_colors() == [colors[0], colors[1]], "%s card colors" % id)
		_expect(graph._reference_connection_accent() == colors[2], "%s connector accent" % id)
		_expect(Palette._category_colors(id) == [colors[1], colors[2]], "%s palette matches live family" % id)
		graph.server_typename = &""
		_expect(graph._reference_visual_family() == role, "%s legacy scene identity" % id)
		graph.server_typename = contract
		graph.free()
	var legacy = load("res://scripts/base_graph.gd").new()
	for id in expected:
		legacy.set_meta(&"created_with", StringName(id))
		_expect(legacy._reference_visual_family() == expected[id], "%s legacy saved metadata" % id)
	legacy.free()
	var flatten = load("res://scenes/flatten.tscn").instantiate()
	flatten.rect = flatten.get_node("ColorRect")
	flatten.set_count(784)
	var pill: Label = flatten.get_node("display_count")
	var ink := pill.get_theme_color("font_color")
	flatten.modulate = Color(0.7, 0.7, 0.7, 1)
	flatten._apply_claude_node_design()
	_expect(flatten.modulate == Color(0.7, 0.7, 0.7, 1), "styling preserves functional root darkening")
	_expect(pill.self_modulate == Color.WHITE and pill.text == "784", "Flatten idle value is unmodulated and unchanged")
	_expect(pill.get_theme_color("font_color") == ink and pill.get_meta("reference_preserve_style"), "preserved pill retains its authored ink")
	var surface: ShaderMaterial = flatten.rect.material
	var shadow: StyleBoxFlat = flatten.rect.get_node("ClaudeCardShadow").get_theme_stylebox("panel")
	_expect(surface.get_shader_parameter("corner_radius") == shadow.corner_radius_top_left, "capsule surface and shadow share radius")
	flatten.block()
	_expect(flatten.is_blocked and flatten.modulate == Color(0.7, 0.7, 0.7, 1), "blocked cue remains active")
	flatten.unblock()
	_expect(not flatten.is_blocked and flatten.modulate == Color.WHITE, "unblocked state restores normal color")
	flatten._apply_claude_node_design()
	_expect(pill.self_modulate == Color.WHITE and pill.text == "784", "restyling after state changes preserves Flatten value")
	flatten.free()
	await _test_ready_dataset_selector()
	var theme := Design.create_theme()
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		var style: StyleBoxFlat = theme.get_stylebox(state, "Button")
		_expect(style.corner_radius_top_left == Design.CONTROL_RADIUS, "native button radius: %s" % state)
	var popup_panel: StyleBoxFlat = theme.get_stylebox("panel", "PopupMenu")
	var popup_item: StyleBoxFlat = theme.get_stylebox("hover", "PopupMenu")
	_expect(popup_panel.corner_radius_top_left == Design.CARD_RADIUS, "popup container uses card radius")
	_expect(popup_item.corner_radius_top_left == Design.CONTROL_RADIUS, "popup highlighted item uses control radius for pointer and keyboard focus")
	_expect(popup_item.bg_color == Design.FILL and theme.get_color("font_disabled_color", "PopupMenu") == Design.INK_MUTED, "popup highlight and disabled colors remain distinct")
	if failures.is_empty():
		print("PASS test_node_visual_family")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _test_ready_dataset_selector() -> void:
	# Exercise the deferred tint that runs after the graph adapter. Checking only
	# scene/card tokens misses a late component-owned fill override.
	var app = root.get_node("glob")
	app.tree = self
	var project = load("res://scenes/project.tscn").instantiate()
	root.add_child(project)
	for frame in 4:
		await process_frame
	var dataset = root.get_node("graphs").get_graph(&"dataset")
	for frame in 4:
		await process_frame
	dataset.update_config({"name": "mnist"})
	for frame in 3:
		await process_frame
	var selector = dataset.run
	var panel: Panel = selector.get_node("ReferenceButtonSurface")
	var style: StyleBoxFlat = panel.get_theme_stylebox("panel")
	_expect(selector.text.contains("mnist"), "selected dataset remains visible in the semantic selector")
	_expect(style.bg_color == Design.DATASET_SOFT, "ready dataset selector uses data-family fill after deferred tint")
	_expect(selector.label.get_theme_color("font_color") == Design.DATASET_INK, "ready dataset selector uses readable data-family ink")
	_expect(selector.released.is_connected(dataset._on_run_released), "semantic tint preserves actual dataset picker callback")
	dataset.block()
	_expect(dataset.is_blocked and dataset.modulate == Color(0.7, 0.7, 0.7, 1), "dataset selector retains blocked parent cue")
	dataset.unblock()
	_expect(style.bg_color == Design.DATASET_SOFT and dataset.modulate == Color.WHITE, "dataset selector returns to data family after unblock")
	await _test_palette_states()
	app.undo_redo.clear_history()
	project.queue_free()
	for frame in 3:
		await process_frame


func _test_palette_states() -> void:
	var card = load("res://scenes/node_palette_item.tscn").instantiate()
	card.setup({"type_id": &"classifier", "title": "Классификатор"})
	root.add_child(card)
	await process_frame
	card.set_hovered(true)
	var style: StyleBoxFlat = card.get_theme_stylebox("panel")
	_expect(style.bg_color == Design.FILL, "palette hover uses neutral control fill")
	var pressed := InputEventMouseButton.new()
	pressed.button_index = MOUSE_BUTTON_LEFT
	pressed.position = Vector2(5, 5)
	pressed.pressed = true
	card._gui_input(pressed)
	style = card.get_theme_stylebox("panel")
	_expect(style.bg_color == Design.FILL_HOVER, "palette press has visible feedback distinct from hover")
	_expect(style.border_color == Design.PRIMARY and card.has_focus(), "palette pressed control retains keyboard focus edge")
	var released := InputEventMouseButton.new()
	released.button_index = MOUSE_BUTTON_LEFT
	released.position = Vector2(-5, -5)
	released.pressed = false
	card._gui_input(released)
	style = card.get_theme_stylebox("panel")
	_expect(style.bg_color == Design.FILL and not card._pressed, "palette release restores hover fill")
	card.set_hovered(false)
	style = card.get_theme_stylebox("panel")
	_expect(style.bg_color == Color.TRANSPARENT and style.border_color == Design.PRIMARY, "palette focus remains visible after pointer leaves")
	card.setup({"type_id": &"input", "title": "Ввод 2D", "disabled": true, "disabled_reason": "Ввод уже добавлен"})
	card.set_hovered(true)
	card._gui_input(pressed)
	style = card.get_theme_stylebox("panel")
	_expect(style.bg_color == Color.TRANSPARENT and not card._pressed, "disabled palette item does not show active hover or press")
	_expect(card._symbol.modulate.a < 1 and card.tooltip_text.contains("Ввод уже добавлен"), "disabled cue and availability reason remain")
	card.queue_free()
	await process_frame
