extends SceneTree
## Presentation must preserve input tensors, classifier labels and real scores.

var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await process_frame
	var app = root.get_node("glob")
	app.tree = self
	var project = load("res://scenes/project.tscn").instantiate()
	root.add_child(project)
	await _frames(3)
	var manager = root.get_node("graphs")
	var input_graph = manager.get_graph(&"input")
	var classifier = manager.get_graph(&"classifier")
	input_graph.position = Vector2(-100, 30)
	classifier.position = Vector2(180, 30)
	await _frames(3)
	for graph in [input_graph, classifier]:
		var title_font = graph.get_node("ColorRect/root/Label").get_theme_font("font")
		_expect(title_font is FontVariation and title_font.base_font.resource_path.contains("GolosText"), "input and output titles use the reference Golos font")
		_expect(title_font is FontVariation and title_font.variation_opentype.get(0x77676874) == 600, "card title weight uses a numeric OpenType tag")
	var canvas = input_graph.get_node("TextureRect")
	_expect(canvas.image.get_pixel(5, 5).r == 0.0, "empty input tensor remains zero")
	_expect(canvas.texture.get_image().get_pixel(5, 5).r > 0.9, "empty input is displayed on a light canvas")
	canvas.put_pixel(Vector2i(5, 5), Color.WHITE)
	_expect(input_graph.get_raw_values()[5 * 28 + 5] == 1.0, "drawing retains the model's original pixel polarity")
	# The headless dummy renderer does not read back ImageTexture updates.
	_expect(canvas._display_image().get_pixel(5, 5).r < 0.2, "actual drawn pixels produce dark display ink")
	input_graph.get_node("ClearDrawing").pressed.emit()
	_expect(input_graph.get_raw_values().all(func(value): return value == 0.0), "clear action clears the real tensor")
	_expect(canvas.change_version > 0, "clear notifies the existing inference update mechanism")
	_expect(input_graph.rect.size == Vector2(108, 186), "input card uses reference proportions")
	for child_name in ["TextureRect", "ClearDrawing", "ImageDimensions"]:
		_expect(input_graph.rect.get_global_rect().encloses(input_graph.get_node(child_name).get_global_rect()), child_name + " is inside the input card")

	var names: Array = []
	for index in 10:
		names.append(str(index))
	classifier.update_config({"label_names": names})
	await create_timer(0.4).timeout
	_expect(classifier.units.size() == 10, "all ten real labels remain present")
	_expect(classifier.rect.size == Vector2(176, 208), "ten real probability rows fit in the compact card")
	_expect(not classifier.get_node("input").visible, "label editor begins collapsed")
	for row in classifier.units:
		_expect(row.get_node("Label2").text == "—", "no inference result is not fabricated as a probability")
		_expect(classifier.get_node("ProbabilityPanel").get_global_rect().encloses(row.get_global_rect()), "probability row stays inside shared panel")
		_expect(row.get_node("Label").size.y <= 16.1 and row.get_node("Label2").size.y <= 16.1, "class labels and scores fit their row without overlap")
	var scores := [0.7, 0.1, 0.05, 0.04, 0.03, 0.02, 0.02, 0.02, 0.01, 0.01]
	classifier.push_values(scores, true)
	_expect(classifier.units[0].get_node("Label2").text == "70%", "real probability is displayed")
	_expect(classifier.units[9].get_node("Label2").text == "1%", "last class retains its real probability")
	_expect(classifier.value_cache == scores, "display remembers the last received result")
	classifier.get_node("EditLabels").pressed.emit()
	_expect(classifier.get_node("input").visible, "add-class editor opens with its real action")
	classifier.line_edit.set_line("other", true)
	classifier.add_button.pressed.emit()
	await _frames(8)
	_expect(classifier.units.size() == 11 and classifier.units[10].get_node("Label").text == "other", "add action adds a real classifier label")
	_expect(classifier.units[0].get_node("Label2").text == "70%", "adding labels preserves received probabilities")
	_expect(classifier.units[10].get_node("Label2").text == "—", "new label has no invented inference result")
	classifier._request_save()
	_expect(classifier.cfg.label_names == names + ["other"], "saved label configuration remains complete")
	classifier.get_node("ColorRect/root/Label").set_line("Digits", true)
	_expect(classifier.get_title() == "Digits" and classifier.cfg.title == "Digits", "group title remains editable and saved")
	classifier.get_node("EditLabels").pressed.emit()
	_expect(not classifier.get_node("input").visible, "editor collapses again")
	_expect(input_graph.position == Vector2(-100, 30) and classifier.position == Vector2(180, 30), "display changes preserve authored graph positions")
	app.undo_redo.clear_history()
	project.queue_free()
	await _frames(3)
	if failures.is_empty():
		print("PASS test_input_classifier_reference")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)


func _frames(count: int) -> void:
	for frame in count:
		await process_frame


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
