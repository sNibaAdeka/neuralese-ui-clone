extends SceneTree
## Native compact cards retain real values, selectors and model coordinates.

var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	await process_frame
	var app = root.get_node("glob")
	app.tree = self
	root.content_scale_factor = 1.0
	root.size = Vector2i(1440, 900)
	var project = load("res://scenes/project.tscn").instantiate()
	root.add_child(project)
	await _frames(3)
	app.main_cam.restore_view(1.0, Vector2.ZERO)
	app.main_cam.set_process(false)
	var gm = root.get_node("graphs")
	var nodes := {}
	for type_id in [&"layer", &"neuron", &"flatten", &"softmax"]:
		var graph = gm.get_graph(type_id)
		graph.position = Vector2(100, -100)
		nodes[type_id] = graph
	await _frames(5)
	for type_id in nodes:
		var graph = nodes[type_id]
		var title: Label = graph.get_node("ColorRect/root/Label")
		_expect(graph.position == Vector2(100, -100), "%s preserves model position" % type_id)
		_expect(graph.scale == Vector2.ONE, "%s uses authored geometry without shrinking controls" % type_id)
		_expect(graph.rect.size.x <= 108.1, "%s fits compact card width" % type_id)
		_expect(title.get_theme_font_size("font_size") == 14, "%s has a real 14px title" % type_id)
		_expect(graph.rect.get_global_rect().encloses(title.get_global_rect()), "%s title remains in card" % type_id)
		for port in graph.input_keys.values() + graph.output_keys.values():
			_expect(port.gradient_color == graph._reference_connection_accent(), "%s wire endpoint uses its semantic family" % type_id)

	# Saved legacy TrainInput nodes may have no server type. Use presentation
	# identity only, preserving the empty type and the stored model settings.
	var legacy_train = load("res://scenes/train_input.tscn").instantiate()
	legacy_train.server_typename = &""
	legacy_train.is_train_graph = false
	var legacy_config = legacy_train.base_config.duplicate(true)
	_expect(legacy_train._claude_node_colors()[0] == Color("94d6ff"), "legacy training scene remains blue without a server type")
	_expect(legacy_train._reference_connection_accent() == Color("279ed9"), "legacy training wire retains its blue family")
	_expect(legacy_train.server_typename == &"" and legacy_train.base_config == legacy_config, "family fallback does not rewrite runtime identity or config")
	legacy_train.free()
	var legacy_base = load("res://scripts/base_graph.gd").new()
	legacy_base.set_meta(&"created_with", &"train_input")
	_expect(legacy_base._claude_node_colors()[0] == Color("94d6ff"), "restored training metadata selects blue without a scene path")
	_expect(legacy_base._reference_connection_accent() == Color("279ed9"), "restored training metadata selects its real wire family")
	legacy_base.set_meta(&"created_with", &"input")
	_expect(not legacy_base._reference_is_training_node(), "drawing input is not classified as training")
	legacy_base.free()

	var dense = nodes[&"layer"]
	dense.update_config({"neuron_count": 128})
	await create_timer(0.3).timeout
	_expect(dense.rect.size.y <= 190.1 and dense._get_x() == 128, "dense compact geometry retains real width")
	var field: Control = dense.get_node("LineEdit")
	for path in ["DecreaseCount", "IncreaseCount"]:
		var button: Control = dense.get_node(path)
		_expect(not button.get_global_rect().intersects(field.get_global_rect()), "count buttons do not overlap numeric field")
		_expect(button.size.x >= 24 and button.size.y >= 24, "count actions retain real hit areas")

	var activation = nodes[&"neuron"]
	var selector = activation.get_node("ColorRect2")
	for choice in [&"relu", &"sigmoid", &"tanh", &"none"]:
		selector.child_button_release.emit(selector.button_by_hint[choice])
		await _frames(2)
		_expect(activation.cfg.activ == choice, "activation selector updates the model: %s" % choice)
		_expect(activation.rect.get_global_rect().encloses(selector.get_global_rect()), "closed selector stays in activation card")
	activation.update_config({"activ": &"relu"})
	var plot = activation.get_node("plot/plot")
	_expect(plot.function.call(-1.0) == 0.0 and plot.function.call(1.0) == 1.0, "activation graph draws the chosen real function")
	_expect(plot.color == Color.WHITE and plot.grid_step == 0, "activation graph has the reference white display")
	_expect(plot.samples_per_pixel >= 1.0, "compact graph keeps enough samples to draw its actual curve")

	var flatten = nodes[&"flatten"]
	flatten.set_count(784)
	_expect(flatten.get_node("display_count").text == "784" and flatten._get_x() == 784, "flatten chip displays the real propagated dimension")
	nodes[&"softmax"].upd(10)
	_expect(nodes[&"softmax"]._get_x() == 10, "softmax preserves the real output dimension")
	app.undo_redo.clear_history()
	project.queue_free()
	await _frames(3)
	if failures.is_empty():
		print("PASS test_reference_model_card_geometry")
		quit(0)
	else:
		for message in failures:
			push_error(message)
		quit(1)

func _frames(count: int) -> void:
	for index in count:
		await process_frame

func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
