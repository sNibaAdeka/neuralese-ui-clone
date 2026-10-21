extends SceneTree
## Reference-size training cards must retain real dataset/configuration bindings.
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
	await _frames(4)
	app.main_cam.restore_view(1.0, Vector2.ZERO)
	app.main_cam.set_process(false)
	var manager = root.get_node("graphs")
	var dataset = manager.get_graph(&"dataset")
	var begin = manager.get_graph(&"train_begin")
	var run = manager.get_graph(&"run_model")
	var step = manager.get_graph(&"train_input")
	_expect(step.server_typename == &"TrainInput", "Training step retains execution server typename")
	_expect(step.base_config.has("optimizer") and step.base_config.has("lr") and step.base_config.has("momentum") and step.base_config.has("weight_decay"), "Training step scene retains all original configuration keys")
	var nodes := [dataset, begin, run, step]
	for index in range(nodes.size()):
		nodes[index].position = Vector2(100 + index * 200, -160)
	await _frames(5)
	var expected := [Vector2(108, 184), Vector2(176, 184), Vector2(176, 128), Vector2(176, 184)]
	for index in range(nodes.size()):
		_expect(nodes[index].rect.size.is_equal_approx(expected[index]), "Reference dimensions for " + str(nodes[index].server_typename) + ": " + str(nodes[index].rect.size))
		_expect(nodes[index].scale.is_equal_approx(Vector2.ONE), "Graph camera scale stays unchanged")
		var title = nodes[index].get_node("ColorRect/root/Label")
		_expect(title.get_theme_font_size("font_size") * title.scale.y >= 13.9, "Readable native title")

	# A bundled dataset must survive loading before a network catalog has arrived.
	app._load.clear()
	dataset.update_config({"name": "mnist"})
	await _frames(4)
	_expect(dataset.cfg.name == "mnist", "Known bundled dataset is not reset before remote catalog load")
	_expect(app.load_dataset("mnist").size == 70000, "Metadata comes from the existing bundled registry")
	_expect(dataset.get_node("DatasetCount").text == "70000 записей", "Real row count is shown")
	var preview_count := 0
	for sample in dataset._preview_images:
		if sample.visible and sample.texture:
			preview_count += 1
	_expect(preview_count == 4, "Four previews come from bundled image samples")
	_expect(dataset.run.released.is_connected(dataset._on_run_released), "Dataset picker retains real callback")

	begin.set_dataset_meta(app.load_dataset("mnist"))
	await _frames(3)
	_expect(begin.get_node("DatasetValue").text == "mnist", "Training card shows actual dataset")
	begin.get_node("IncreaseEpochs").pressed.emit()
	_expect(int(begin.get_node("YY").text) == 2, "Plus changes real validated epoch input")
	begin.get_node("DecreaseEpochs").pressed.emit()
	_expect(int(begin.get_node("YY").text) == 1, "Minus changes real validated epoch input")
	begin.training = true
	begin._update_epoch_actions()
	begin.get_node("IncreaseEpochs").pressed.emit()
	_expect(int(begin.get_node("YY").text) == 1, "Epoch editing is blocked during training")
	begin._show_training_progress({"stage": "epoch_start", "epoch": 1, "epochs": 3})
	_expect(begin.get_node("TrainingStatus").text == "Эпоха 2 из 3", "Progress is sourced from real event payload")
	begin.training = false
	_expect(begin.train.released.is_connected(begin._on_train_released), "Real start/stop callback retained")
	_expect(begin.clearbut.released.is_connected(begin._on_train_2_released), "Real reset callback retained")

	step.update_config({"optimizer": "adam", "lr": 1})
	app.undo_redo.clear_history()
	step.get_node("DecreaseRate").pressed.emit()
	_expect(step.cfg.lr == 2 and step._useful_properties().config.lr == "1e-3", "Rate action changes actual optimizer config")
	app.undo_redo.undo()
	await _frames(2)
	_expect(step.cfg.lr == 1, "Rate action can be undone")
	step.get_node("TrainingOptions").pressed.emit()
	await create_timer(0.6).timeout
	_expect(step.get_node("switch").visible, "Weight decay remains accessible")
	step._on_switch_released()
	_expect(step.cfg.weight_decay, "Weight decay still changes actual config")
	step.update_config({"optimizer": "sgd"})
	await create_timer(0.6).timeout
	_expect(step.get_node("sgd_tab").visible, "SGD momentum remains accessible")
	step.get_node("sgd_tab/Label4/HSlider").value = 50
	_expect(is_equal_approx(float(step.cfg.momentum), 0.45), "Momentum slider still changes actual config")
	step.get_node("TrainingOptions").pressed.emit()
	await create_timer(0.6).timeout
	_expect(absf(step.rect.size.y - 184) < 1, "Advanced settings collapse to reference card size")
	step.clear()
	await _frames(2)
	_expect(step.get_node("ColorRect2/acc").text == "—", "Empty chart does not claim 100 percent accuracy")
	step.train_start()
	step.push_acceptance(0.75, 0.4)
	await _frames(3)
	_expect(step._has_samples and not step.get_node("ColorRect2/NoMeasurements").visible, "Chart reflects actual supplied measurements")
	step.train_stop()

	# Dynamic output units retain their original menu construction and callback.
	run.add_unit({"text": "Actual output"}, true)
	await create_timer(0.6).timeout
	var output = run.units[0]
	output.set_meta("points_to", begin)
	var loss = output.get_node("loss")
	_expect(loss.child_button_release.is_connected(run.loss_button), "Loss selection retains native callback")
	loss.child_button_release.emit(loss.button_by_hint[&"cross_entropy"])
	_expect(run.cfg.branches[str(begin.graph_id)] == "cross_entropy", "Loss action changes real branch config")
	_expect(run.rect.get_global_rect().grow(0.1).encloses(loss.get_global_rect()), "Loss selector remains within compact RunModel card")
	app.undo_redo.clear_history()
	project.queue_free()
	await _frames(3)
	if failures.is_empty():
		print("PASS test_reference_training_cards")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)

func _frames(count: int) -> void:
	for index in range(count):
		await process_frame

func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
