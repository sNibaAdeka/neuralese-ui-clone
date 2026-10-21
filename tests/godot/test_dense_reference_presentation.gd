extends SceneTree
## Compact markers must never change the model's numeric width or saved layout.

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
	var dense = gm.get_graph(&"layer")
	var authored_position := Vector2(127, -111)
	dense.position = authored_position
	await _frames(2)

	for count in [128, 2048, 10, 3, 2, 1, 0, 128]:
		dense.update_config({"neuron_count": count})
		await create_timer(0.4).timeout
		_expect(dense.cfg.neuron_count == count, "config retains %d neurons" % count)
		_expect(dense._useful_properties().neuron_count == count, "runtime contract retains %d neurons" % count)
		_expect(dense._get_x() == count, "outgoing dimension retains %d neurons" % count)
		_expect(dense.get_info().neuron_count == count, "serialized count retains %d neurons" % count)
		_expect(dense.units.size() == mini(count, 3), "at most three markers represent %d neurons" % count)
		_expect(dense.rect.size.y <= 190.5 and dense.rect.size.x <= 108.5, "card stays compact for %d neurons" % count)
		_expect(dense.position == authored_position, "count edits preserve authored graph coordinates")
		for marker in dense.units:
			_expect(not marker.label.visible, "representative circles do not claim a different numeric count")
			_expect(dense.rect.get_global_rect().grow(0.2).encloses(marker.get_node("ColorRect5").get_global_rect()), "marker remains inside the card")

	# Round-trip the real serialized configuration through the existing load path.
	var saved: Dictionary = dense.get_info().duplicate(true)
	var restored = gm.get_graph(&"layer")
	restored.map_properties(saved)
	await create_timer(0.4).timeout
	_expect(restored.position == authored_position, "load preserves authored coordinates")
	_expect(restored.cfg.neuron_count == 128 and restored._get_x() == 128, "load preserves numeric width 128")
	_expect(restored.units.size() == 3, "loaded width 128 uses three representative circles")

	# Exercise real control signals, including the existing graph undo history.
	app.undo_redo.clear_history()
	dense.get_node("IncreaseCount").pressed.emit()
	_expect(dense.cfg.neuron_count == 129, "plus button changes the real model")
	app.undo_redo.undo()
	await _frames(2)
	_expect(dense.cfg.neuron_count == 128, "plus change can be undone")
	app.undo_redo.redo()
	await _frames(2)
	_expect(dense.cfg.neuron_count == 129, "plus change can be redone")
	dense.get_node("DecreaseCount").pressed.emit()
	_expect(dense.cfg.neuron_count == 128, "minus button changes the real model")
	dense.neurons_fixed = true
	_expect(dense.get_node("IncreaseCount").disabled and dense.get_node("DecreaseCount").disabled, "locked count disables both controls")
	dense.get_node("IncreaseCount").pressed.emit()
	_expect(dense.cfg.neuron_count == 128, "locked count cannot be changed by the action")
	dense.neurons_fixed = false
	dense.get_node("LineEdit").set_line("64", true)
	await _frames(3)
	_expect(dense.cfg.neuron_count == 64 and dense.units.size() == 3, "direct numeric editing retains the compact representation")
	_expect(dense.position == authored_position, "all controls preserve graph coordinates")
	app.undo_redo.clear_history()
	project.queue_free()
	await _frames(3)
	if failures.is_empty():
		print("PASS test_dense_reference_presentation")
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
