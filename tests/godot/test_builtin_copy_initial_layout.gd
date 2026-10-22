extends Node
## Real new-copy gallery path, local persistence and controlled failure branches.

class FailedLoadRepository:
	extends "res://scripts/builtin_projects_repository.gd"
	func create_user_copy(_id: StringName, _language: String) -> Dictionary:
		return {"ok": true, "project_id": "-987654321", "already_loaded": false}

var failures: Array[String] = []

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	glob.tree = get_tree()
	get_tree().root.content_scale_factor = 1.0
	get_tree().root.size = Vector2i(1440, 900)
	glob.splines_layer = CanvasLayer.new()
	glob.top_splines_layer = CanvasLayer.new()
	get_parent().get_node("WIN_GRAPH").add_child(glob.splines_layer)
	get_parent().get_node("WIN_GRAPH").add_child(glob.top_splines_layer)
	get_parent().add_child(load("res://scenes/simulations/simulation_tab.tscn").instantiate())
	await _frames(12)
	var gallery = await _gallery()
	# No previous project exists; thumbnail capture must not await a rendered
	# frame in this headless test. All copy/load/layout/save handlers are real.
	glob.loaded_project_once = false
	await gallery._open_project(&"digits")
	await _frames(12)
	var copy_id := str(glob.get_project_id())
	_expect(int(copy_id) >= 0 and glob.loaded_project_once, "gallery successfully opens a new local copy")
	var arranged := _positions()
	var raw: Variant = glob._read_var_abs("res://built_in_projects/Digits.scn")
	var original: Dictionary = bytes_to_var(raw)
	var changed := false
	for node_id in graphs._graphs:
		if original.graphs.has(node_id) and graphs._graphs[node_id].position != original.graphs[node_id].position:
			changed = true
	_expect(changed, "new gallery copy arranges legacy authored coordinates")
	var nodes: Array = graphs._graphs.values()
	for index in nodes.size():
		for other in range(index + 1, nodes.size()):
			_expect(not nodes[index].rect.get_global_rect().intersects(nodes[other].rect.get_global_rect()), "arranged copy has no overlapping node cards")
	_expect(glob.main_cam._fit_zoom_active or glob.main_cam._go_active or glob.main_cam.target_zoom != 1.0, "new gallery copy requests camera fit")
	var saved: Dictionary = await glob.save(copy_id)
	_expect(saved.get("status", "") == "ok", "arranged copy saves through production writer")
	_expect(await glob.load_scene(copy_id), "arranged copy reopens through ordinary project loader")
	await _frames(8)
	_expect(_positions() == arranged, "ordinary reopen preserves saved arranged coordinates")
	# User-authored positions must survive the same normal save/reopen path.
	var first = graphs._graphs.values()[0]
	first.position = Vector2(-777.25, 456.5)
	var authored := _positions()
	await glob.save(copy_id)
	_expect(await glob.load_scene(copy_id), "user-edited copy reopens")
	await _frames(8)
	_expect(_positions() == authored, "ordinary reopen never rearranges user-authored coordinates")
	var failed_create = await _gallery()
	glob.loaded_project_once = false # Skip unavailable headless thumbnail only.
	await failed_create._open_project(&"missing-project-for-layout-regression")
	await _frames(6)
	_expect(_positions() == authored, "failed copy creation does not arrange current graph")
	if is_instance_valid(failed_create): failed_create.queue_free()
	await _frames(3)
	var failed_load = await _gallery()
	failed_load.repository = FailedLoadRepository.new()
	glob.loaded_project_once = false
	await failed_load._open_project(&"digits")
	await _frames(6)
	_expect(_positions() == authored, "failed copy load does not arrange current graph")
	if is_instance_valid(failed_load): failed_load.queue_free()
	glob.undo_redo.clear_history()
	glob._local_delete_project(copy_id)
	nn.close_all(true)
	if failures.is_empty():
		print("PASS test_builtin_copy_initial_layout")
		get_tree().quit(0)
	else:
		for failure in failures: push_error(failure)
		get_tree().quit(1)

func _gallery():
	var gallery = load("res://scenes/builtin_projects_window.tscn").instantiate()
	gallery.emitter = ui.ResultEmitter.new()
	ui.cl.add_child(gallery)
	await _frames(20)
	return gallery

func _positions() -> Dictionary:
	var result := {}
	for node_id in graphs._graphs: result[node_id] = graphs._graphs[node_id].position
	return result

func _frames(count: int) -> void:
	for index in count: await get_tree().process_frame

func _expect(condition: bool, message: String) -> void:
	if not condition: failures.append(message)
