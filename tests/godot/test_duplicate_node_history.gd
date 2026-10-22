extends SceneTree
## Production copy action must retain configured Dense state through history/load.

var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var app = root.get_node("glob")
	var manager = root.get_node("graphs")
	app.tree = self
	var project = load("res://scenes/project.tscn").instantiate()
	root.add_child(project)
	app.splines_layer = CanvasLayer.new()
	app.top_splines_layer = CanvasLayer.new()
	project.get_node("WIN_GRAPH").add_child(app.splines_layer)
	project.get_node("WIN_GRAPH").add_child(app.top_splines_layer)
	await _frames(5)
	var source = manager.get_graph(&"layer")
	var target = manager.get_graph(&"layer")
	source.update_config({"neuron_count": 17})
	source.position = Vector2(-321.25, 187.5)
	target.update_config({"neuron_count": 5})
	target.position = Vector2(234.5, -124.25)
	var source_id: int = source.graph_id
	var target_id: int = target.graph_id
	var output = source.output_keys.values()[0]
	var input = target.input_keys.values()[0]
	_expect(output.connect_to(input, true), "source connection exists before copy")
	await _frames(4)
	app.undo_redo.clear_history()
	var expected_position: Vector2 = source.position + source.rect.size / 2
	await source.copy()
	await _frames(4)
	var duplicate_id := -1
	for node_id in manager._graphs:
		if node_id != source_id and node_id != target_id: duplicate_id = node_id
	_expect(duplicate_id != -1, "copy creates a distinct graph identity")
	for cycle in 3:
		var duplicate = manager._graphs.get(duplicate_id)
		_expect(_matches(duplicate, expected_position), "copy/redo retains configured17 units and offset position")
		_expect(_edge_count(duplicate) == 0, "copy remains an independent node")
		_expect(source.cfg.neuron_count == 17 and source.position == Vector2(-321.25, 187.5), "copy/history preserves source configuration and position")
		_expect(output.get_target() == input and output.outputs.size() == 1 and input.inputs.size() == 1, "copy/history preserves source edge")
		app.undo_redo.undo()
		await _frames(4)
		_expect(not manager._graphs.has(duplicate_id) and manager._graphs.size() == 2, "one undo removes only duplicate")
		app.undo_redo.redo()
		await _frames(4)
		_expect(_matches(manager._graphs.get(duplicate_id), expected_position) and manager._graphs.size() == 3, "one redo restores exact duplicate identity and state")
	# Exercise production graph serialization/loading after repeated history.
	var packed := {}
	for node_id in manager._graphs: packed[node_id] = manager._graphs[node_id].get_info()
	var serialized: PackedByteArray = var_to_bytes(packed)
	app.undo_redo.clear_history()
	await manager.delete_all()
	var loaded: bool = await manager.load_graph(bytes_to_var(serialized), {})
	_expect(loaded, "production graph loader accepts serialized duplicate")
	await _frames(4)
	_expect(_matches(manager._graphs.get(duplicate_id), expected_position), "serialized duplicate restores configured units and position")
	var reloaded_source = manager._graphs.get(source_id)
	var reloaded_target = manager._graphs.get(target_id)
	_expect(reloaded_source.cfg.neuron_count == 17 and reloaded_target.cfg.neuron_count == 5, "serialized source and target configurations are preserved")
	var restored_output = reloaded_source.output_keys.values()[0]
	_expect(restored_output.outputs.size() == 1 and restored_output.get_target().parent_graph == reloaded_target, "serialization preserves original connection")
	app.undo_redo.clear_history()
	project.queue_free()
	await _frames(4)
	root.get_node("nn").close_all(true)
	if failures.is_empty():
		print("PASS test_duplicate_node_history")
		quit(0)
	else:
		for failure in failures: push_error(failure)
		quit(1)

func _matches(node, expected_position: Vector2) -> bool:
	return is_instance_valid(node) and node.cfg.get("neuron_count", -1) == 17 and node.position.is_equal_approx(expected_position)

func _edge_count(node) -> int:
	if not is_instance_valid(node): return -1
	var count := 0
	for port in node.output_keys.values(): count += port.outputs.size()
	for port in node.input_keys.values(): count += port.inputs.size()
	return count

func _frames(count: int) -> void:
	for index in count: await process_frame

func _expect(condition: bool, message: String) -> void:
	if not condition: failures.append(message)
