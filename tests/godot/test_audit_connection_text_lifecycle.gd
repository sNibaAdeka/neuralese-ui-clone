extends SceneTree
## Production connection/text lifecycle checks; no backend calls.

var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var app = root.get_node("glob")
	app.tree = self
	var project = load("res://scenes/project.tscn").instantiate()
	root.add_child(project)
	await _frames(4)
	var manager = root.get_node("graphs")
	app.splines_layer = CanvasLayer.new()
	app.top_splines_layer = CanvasLayer.new()
	project.get_node("WIN_GRAPH").add_child(app.splines_layer)
	project.get_node("WIN_GRAPH").add_child(app.top_splines_layer)
	manager.spline_connected.connect(app.connect_action)
	var source = manager.get_graph(&"layer")
	var first = manager.get_graph(&"layer")
	var second = manager.get_graph(&"layer")
	await _frames(3)
	var output = source.output_keys.values()[0]
	var input = first.input_keys.values()[0]
	var other = second.input_keys.values()[0]
	app.undo_redo.clear_history()
	var version: int = app.undo_redo.get_version()
	var slot: int = output.add_spline()
	var cancelled = output.outputs[slot]
	output.start_spline(slot)
	output.end_spline(slot)
	_expect(output.outputs.is_empty() and output.active_outputs.is_empty(), "new cancellation removes output slots")
	_expect(cancelled.is_queued_for_deletion(), "new cancellation disposes temporary spline")
	_expect(app.undo_redo.get_version() == version, "new cancellation does not alter undo history")
	_expect(not manager.conns_active.has(output) and not source.active_output_connections.has(output), "cancel clears active tracking immediately")
	slot = output.add_spline()
	output.start_spline(slot)
	_expect(not output.is_suitable(output), "same output is an incompatible drop target")
	output.end_spline(slot)
	_expect(output.outputs.is_empty() and app.undo_redo.get_version() == version, "incompatible drop cancels without changing history")
	# A slot may exist without ever having entered active_outputs.
	slot = output.add_spline()
	output.end_spline(slot)
	_expect(output.outputs.is_empty(), "inactive temporary slot can be removed safely")
	# Deleting an output while dragging a new wire must not dereference a null target.
	slot = output.add_spline()
	output.start_spline(slot)
	output.delete()
	_expect(output.outputs.is_empty() and output.active_outputs.is_empty(), "delete during drag disposes temporary edge")
	_expect(output.connect_to(input, true), "new edge attaches")
	_expect(input.inputs.size() == 1 and input.connected.has(output), "new edge registers both endpoints")
	app.undo_redo.undo()
	_expect(output.outputs.is_empty() and output.active_outputs.is_empty(), "undo of a new edge completes synchronously")
	await _frames(3)
	_expect(app.undo_redo.has_redo(), "deferred cleanup does not overwrite redo history")
	app.undo_redo.redo()
	await _frames(3)
	_expect(output.outputs.size() == 1 and input.inputs.size() == 1, "redo restores a normal new edge")
	app.undo_redo.clear_history()
	slot = output.outputs.keys()[0]
	input.detatch_spline(output.outputs[slot])
	output.end_spline(slot)
	_expect(input.inputs.is_empty() and output.outputs.is_empty(), "cancel existing edge disconnects it")
	app.undo_redo.undo()
	await _frames(2)
	_expect(output.outputs.size() == 1 and input.inputs.size() == 1, "undo restores cancelled existing edge")
	app.undo_redo.redo()
	await _frames(3)
	_expect(output.outputs.is_empty() and input.inputs.is_empty(), "redo removes restored edge")
	_expect(output.connect_to(input, true), "edge exists before reconnect")
	app.undo_redo.clear_history()
	slot = output.outputs.keys()[0]
	input.detatch_spline(output.outputs[slot])
	output.attach_spline(slot, other)
	_expect(output.outputs.size() == 1 and other.inputs.size() == 1 and input.inputs.is_empty(), "reconnect keeps exactly one edge at new target")
	_expect(output.active_outputs.is_empty(), "reconnect finalizes drag state")
	app.undo_redo.undo()
	_expect(output.outputs.size() == 1 and output.active_outputs.is_empty() and output.get_target() == input, "reconnect undo completes atomically")
	await _frames(3)
	_expect(output.outputs.size() == 1 and output.get_target() == input and input.inputs.size() == 1 and other.inputs.is_empty(), "one undo restores previous reconnect target")
	_expect(app.undo_redo.has_redo() and input.connected.has(output) and not other.connected.has(output), "reconnect undo preserves redo and endpoint registrations")
	app.undo_redo.redo()
	await _frames(3)
	_expect(output.outputs.size() == 1 and output.get_target() == other and other.inputs.size() == 1 and input.inputs.is_empty(), "one redo restores new reconnect target")
	output.delete()
	_expect(other.inputs.is_empty() and not other.connected.has(output), "delete finalized reconnected edge removes new endpoint")
	# Use the exact serialized Axon TextEdit, whose signal is connected before _ready.
	var axon_scene = load("res://scenes/ai_help.tscn").instantiate()
	var editor = axon_scene.get_node("ColorRect/Label2")
	editor.enter_event = null
	editor.owner = null
	editor.reparent(root)
	axon_scene.free()
	await _frames(2)
	var callback_count := 0
	for binding in editor.text_changed.get_connections():
		if binding.callable == Callable(editor, "_on_text_changed"):
			callback_count += 1
	_expect(callback_count == 1, "serialized text handler connects exactly once")
	editor.max_length = 8
	editor.insert_text_at_caret("abcdefghijkl")
	await _frames(2)
	_expect(editor.text == "abcdefgh", "single text handler retains length limit")
	editor.text = "draft"
	editor.hide()
	editor.show()
	_expect(editor.text == "draft", "close and reopen retain draft")
	editor.set_caret_column(5)
	editor._insert_newline_at_caret()
	_expect(editor.text == "draft\n", "newline action preserves Shift+Enter behavior")
	editor.queue_free()
	app.undo_redo.clear_history()
	project.queue_free()
	await _frames(4)
	if failures.is_empty():
		print("PASS test_audit_connection_text_lifecycle")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)

func _frames(count: int) -> void:
	for index in count:
		await process_frame

func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
