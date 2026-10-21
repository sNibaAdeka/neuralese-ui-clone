extends SceneTree
## Real scene geometry/state checks at camera zoom 1; this is not visual QA.

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
	var positions := {}
	for type_id in [&"train_begin", &"layer", &"conv2d", &"maxpool", &"run_model", &"flatten", &"softmax"]:
		var graph = gm.get_graph(type_id)
		nodes[type_id] = graph
		graph.position = Vector2(100, -180) # Keep animated fixtures inside the live viewport.
		positions[type_id] = graph.position
	await _frames(8)
	for type_id in nodes:
		var graph = nodes[type_id]
		var title := graph.get_node("ColorRect/root/Label") as Label
		_expect(_effective_font_size(title) >= 14.0 - 0.01, str(type_id) + ": readable title at zoom 1")
		_expect(_is_local_sans(title.get_theme_font("font")), str(type_id) + ": local sans title font")
		_expect(graph.scale.is_equal_approx(Vector2.ONE), str(type_id) + ": graph scale must remain unchanged")
		_expect(graph.position == positions[type_id], str(type_id) + ": initialization/layout must preserve model position")
		_expect(graph.rect.get_global_rect().encloses(title.get_global_rect()), str(type_id) + ": title stays inside its card")
		_check_declared_captions(title, title, str(type_id) + " localized title")

	var train = nodes[&"train_begin"]
	var dense = nodes[&"layer"]
	var conv = nodes[&"conv2d"]
	var pool = nodes[&"maxpool"]
	var run = nodes[&"run_model"]
	_check_control(train.train, "Train action", train.rect, 24.0)
	_check_control(train.clearbut, "Clear action", train.rect, 24.0)
	_check_control(train.get_node("YY"), "Epoch count", train.rect, 24.0)
	_check_control(dense.get_node("LineEdit"), "Neuron count", dense.rect, 24.0)
	_check_control(dense.get_node("DecreaseCount"), "Decrease neuron count", dense.rect, 24.0)
	_check_control(dense.get_node("IncreaseCount"), "Increase neuron count", dense.rect, 24.0)
	_check_control(conv.get_node("Y"), "Filter count", conv.rect)
	_check_control(conv.get_node("Label/HSlider"), "Kernel slider", conv.rect)
	_check_control(conv.get_node("Label2/HSlider2"), "Stride slider", conv.rect)
	_check_control(pool.get_node("YY"), "Pool group", pool.rect)
	_expect(train.train.released.is_connected(train._on_train_released), "Train keeps its real action callback")
	_expect(train.clearbut.released.is_connected(train._on_train_2_released), "Clear keeps its real action callback")
	_check_declared_captions(train.train, train.train.label, "Localized Train action")
	_check_declared_captions(train.clearbut, train.clearbut.label, "Localized Clear action")
	for caption in ["Stop", "Стоп", "Тоқта"]:
		_check_text_fits(train.train, train.train.label, caption, "Localized Stop action")
	var initial_text: String = train.train.text
	train._show_training_progress({"stage": "epoch_start", "epoch": 0, "epochs": 3})
	_expect(train.train.text == train._stop_label(), "Training progress switches the real action to Stop")
	_check_caption(train.train, "Stop caption")
	train.train.text = initial_text

	# Exercise the existing signals and numeric validation without starting training.
	dense.get_node("LineEdit").set_line("64", true)
	conv.get_node("Label/HSlider").value = 3
	conv.get_node("Label2/HSlider2").value = 2
	conv.get_node("Y").submitted.emit("32")
	pool.get_node("YY").set_line("4", true)
	await _frames(3)
	_expect(dense.cfg.neuron_count == 64, "Neuron field still updates the real config")
	_expect(conv.cfg.window == 3 and conv.cfg.stride == 2 and conv.cfg.filters == 32, "Conv controls still update the real config")
	_expect(pool.cfg.group == 4, "Pool field still updates the real config")
	for control in [dense.get_node("LineEdit"), conv.get_node("Y"), pool.get_node("YY"), train.get_node("YY")]:
		_expect(_effective_font_size(control) >= 12.0 - 0.01, "Numeric edits preserve the authored readable font")

	# Dataset rows are cloned and resized by the existing metadata renderer.
	train.get_node("ColorRect2/Control").push_cfg({"name": "Image dataset", "size": 64,
		"input_hints": [{"name": "image_pixels", "dtype": "float32", "value": "0"}]})
	await _frames(3)
	var rows = train.get_node("ColorRect2/Control/ScrollContainer/VBoxContainer")
	_expect(rows.get_child_count() == 1, "Metadata uses one real renderer row")
	if rows.get_child_count() == 1:
		var row = rows.get_child(0)
		var name_rect: Rect2 = row.get_node("name").get_global_rect()
		var dtype_rect: Rect2 = row.get_node("dtype").get_global_rect()
		var value_rect: Rect2 = row.get_node("value").get_global_rect()
		var scroll_rect: Rect2 = train.get_node("ColorRect2/Control/ScrollContainer").get_global_rect()
		_expect(not name_rect.intersects(dtype_rect) and not name_rect.intersects(value_rect) and not dtype_rect.intersects(value_rect),
			"Metadata name, type and value must not overlap after renderer positioning")
		for bounds in [name_rect, dtype_rect, value_rect]:
			_expect(row.get_global_rect().grow(0.1).encloses(bounds), "Metadata text must remain inside its row")
			_expect(scroll_rect.grow(0.1).encloses(bounds), "First metadata row must not be clipped by the scroll viewport")

	# The real RunModel row factory enables cloned loss menus and connects callbacks.
	for count in [1, 3]:
		while run.units.size() < count:
			run.add_unit({"text": "Output " + str(run.units.size() + 1)}, true)
			var added = run.units[-1]
			added.set_meta("points_to", dense)
		await create_timer(0.8).timeout
		await _frames(2)
		for unit in run.units:
			var loss = unit.get_node("loss")
			_check_control(loss, "Loss selector with %d rows" % count, run.rect, 24.0)
			_expect(loss.child_button_release.is_connected(run.loss_button), "Loss selector keeps its real callback")
			_expect(loss.button_by_hint.has(&"mse") and loss.button_by_hint.has(&"cross_entropy"), "Real loss choices remain available")
			for choice in loss.button_by_hint.values():
				_check_control(choice, "Loss menu choice", null, 24.0)
			loss.child_button_release.emit(loss.button_by_hint[&"cross_entropy"])
			_expect(run.cfg.branches[str(dense.graph_id)] == "cross_entropy", "Loss selection updates the real branch config")
			_check_caption(loss, "Selected loss caption")
	for type_id in nodes:
		_expect(nodes[type_id].position == positions[type_id], str(type_id) + ": editing controls must not rearrange the graph")
	project.queue_free()
	await _frames(3)
	if failures.is_empty():
		print("PASS test_learning_node_geometry")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)


func _check_control(control: Control, label: String, card: Control, minimum_hit_size: float = 44.0) -> void:
	var bounds := control.get_global_rect()
	_expect(bounds.size.x >= minimum_hit_size - 0.01 and bounds.size.y >= minimum_hit_size - 0.01, label + ": actual hit rectangle fits the authored compact control at zoom 1")
	if card != null:
		_expect(card.get_global_rect().grow(0.1).encloses(bounds), label + ": control must remain inside the card")
	if control.has_method("_align_label"):
		_check_caption(control, label)


func _check_caption(control, label: String) -> void:
	_expect(_effective_font_size(control.label) >= 12.0 - 0.01, label + ": state changes retain readable button text")
	_check_text_fits(control, control.label, control.label.text, label)


func _check_declared_captions(control: Control, label: Label, description: String) -> void:
	_check_text_fits(control, label, label.text, description)
	var localization := control.get_node_or_null("Loc")
	if localization == null:
		return
	for language in ["ru", "kz"]:
		var entries: Dictionary = localization.get("localizations_" + language)
		for caption in entries.values():
			_check_text_fits(control, label, str(caption), description + " " + language)


func _check_text_fits(control: Control, label: Label, caption: String, description: String) -> void:
	var font := label.get_theme_font("font")
	var measured := font.get_multiline_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, label.size.x if label.autowrap_mode != TextServer.AUTOWRAP_OFF else -1, label.get_theme_font_size("font_size"))
	var transform := label.get_global_transform()
	var rendered := measured * Vector2(transform.x.length(), transform.y.length())
	var available := control.get_global_rect().size
	_expect(rendered.x <= available.x + 0.1 and rendered.y <= available.y + 0.1, description + ": full caption fits without shrinking")


func _effective_font_size(control: Control) -> float:
	return control.get_theme_font_size("font_size") * control.get_global_transform().y.length()


func _frames(count: int) -> void:
	for frame in count:
		await process_frame


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _is_local_sans(font: Font) -> bool:
	if font is FontVariation:
		return _is_local_sans(font.base_font)
	return font.resource_path.contains("GolosText") or font.resource_path.contains("JetBrainsSans")
