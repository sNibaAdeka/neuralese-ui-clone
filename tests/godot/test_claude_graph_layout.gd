extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var app = root.get_node("glob")
	app.tree = self
	root.content_scale_factor = 1.0
	root.size = Vector2i(1440, 900)
	var project = load("res://scenes/project.tscn").instantiate()
	root.add_child(project)
	await process_frame
	var gm = root.get_node("graphs")
	var nodes: Array = [gm.get_graph(&"layer"), gm.get_graph(&"layer"), gm.get_graph(&"softmax")]
	var original: Array = []
	for i in nodes.size():
		nodes[i].position = Vector2(23 + i * 3, 41 + i * 4)
		original.append(nodes[i].position)
	await process_frame
	assert(nodes[0].position == original[0], "loading nodes does not trigger layout")
	var shell = app.fg.claude_shell
	app.curr_window = "graph"
	shell.overflow.get_popup().id_pressed.emit(7)
	await process_frame
	for a in nodes:
		for b in nodes:
			if a != b: assert(not a.rect.get_global_rect().intersects(b.rect.get_global_rect()), "explicit layout separates actual card bounds")
	var arranged: Array = nodes.map(func(n): return n.position)
	app.undo_redo.undo()
	await process_frame
	for i in nodes.size(): assert(nodes[i].position == original[i], "single undo restores exact authored coordinates")
	app.undo_redo.redo()
	await process_frame
	for i in nodes.size(): assert(nodes[i].position == arranged[i], "redo restores layout")
	project.queue_free()
	await process_frame
	await process_frame
	print("PASS test_claude_graph_layout")
	quit(0)
