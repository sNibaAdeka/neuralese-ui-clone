extends SceneTree

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	# A Camera2D polling in its internal process keeps the whole editor redrawing at full
	# frame rate even when nothing changes (defeats OS.low_processor_usage_mode).
	var cam := Camera2D.new()
	root.add_child(cam)
	cam.make_current()
	_expect(cam.is_processing_internal(), "precondition: a plain Camera2D polls in its internal process")

	IdleCamera.apply(cam)
	_expect(not cam.is_processing_internal(), "IdleCamera turns internal polling off")
	_expect(not cam.is_physics_processing_internal(), "IdleCamera leaves physics polling off")

	# ...but the camera must still follow assignments (that is how graph cameras move).
	var half := Vector2(root.get_visible_rect().size) * 0.5
	cam.position = Vector2(100.0, 40.0)
	await process_frame
	_expect(root.canvas_transform.origin.is_equal_approx(half - Vector2(100.0, 40.0)), "position change still updates the canvas transform (%s)" % root.canvas_transform.origin)
	cam.zoom = Vector2(2.0, 2.0)
	await process_frame
	_expect(root.canvas_transform.get_scale().is_equal_approx(Vector2(2.0, 2.0)), "zoom change still updates the canvas transform (%s)" % root.canvas_transform.get_scale())

	# Entering the tree re-enables polling in Camera2D itself; the hook must turn it off again.
	root.remove_child(cam)
	root.add_child(cam)
	_expect(not cam.is_processing_internal(), "polling stays off after re-entering the tree")

	# Calling apply twice must not stack duplicate hooks.
	IdleCamera.apply(cam)
	IdleCamera.apply(cam)
	_expect(cam.tree_entered.get_connections().size() == 1, "apply() is idempotent (%d tree_entered connections)" % cam.tree_entered.get_connections().size())

	# The graph tab cameras are re-enabled on every tab show: that path must re-apply it.
	var win_graph := (load("res://scripts/win_graph.gd") as GDScript).source_code
	_expect(win_graph.contains("IdleCamera.apply(camera)"), "TabWindow re-applies IdleCamera when a tab camera is enabled")

	cam.queue_free()
	if failures.is_empty():
		print("PASS test_idle_camera")
		quit(0)
	else:
		for f in failures:
			printerr("FAIL: ", f)
		quit(1)


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		failures.append(msg)
