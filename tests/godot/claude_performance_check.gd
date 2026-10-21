extends RefCounted
## Opt-in rendered editor benchmark. Invoked from the normal app only after
## glob has constructed its workspace, before the interactive startup flow.
## No project is saved, no user project is loaded, and no setting is persisted.

const FIXTURE_SEED := 20261015
const VIEWPORT_SIZE := Vector2i(1440, 900)
const COLUMNS := 20
const SPACING := Vector2(280, 220)
const SETTLE_SECONDS := 2.0

var output_path := ""
var node_count := 300
var duration_seconds := 8.0
var failures: Array[String] = []
var result: Dictionary = {}

func run(tree: SceneTree) -> void:
	var hook_usec := Time.get_ticks_usec()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--performance-output="):
			output_path = arg.trim_prefix("--performance-output=")
		elif arg.begins_with("--performance-nodes="):
			node_count = int(arg.trim_prefix("--performance-nodes="))
		elif arg.begins_with("--performance-seconds="):
			duration_seconds = float(arg.trim_prefix("--performance-seconds="))
	result = {
		"schema_version": 1,
		"status": "running",
		"fixture": {"kind": "native_layer_nodes_without_edges", "seed": FIXTURE_SEED,
			"requested_node_count": node_count, "columns": COLUMNS,
			"spacing": [SPACING.x, SPACING.y], "settle_seconds": SETTLE_SECONDS,
			"phase_seconds": duration_seconds},
		"launch": {"hook_entry_engine_ms": float(hook_usec) / 1000.0},
		"environment": {"godot": Engine.get_version_info(), "os": OS.get_name(),
			"renderer": RenderingServer.get_current_rendering_method(),
			"rendering_device": RenderingServer.get_video_adapter_name(),
			"display_server": DisplayServer.get_name(), "logical_viewport": [1440, 900],
			"content_scale_factor": 1.0, "vsync": "disabled", "fps_cap": 0,
			"low_processor_usage": false},
		"phases": {},
	}
	_event("hook_ready", hook_usec)
	if output_path.is_empty() or node_count < 20 or node_count > 2000 or duration_seconds < 2.0:
		failures.append("Explicit output, 20–2000 nodes, and at least 2 seconds per phase are required.")
		_finish(tree)
		return
	if DisplayServer.get_name() == "headless":
		failures.append("Frame benchmark requires native rendering; headless data is not comparable.")
		_finish(tree)
		return
	var app = tree.root.get_node_or_null("glob")
	var gm = tree.root.get_node_or_null("graphs")
	if app == null or gm == null or not is_instance_valid(app.fg) or not is_instance_valid(app.main_cam):
		failures.append("Normal native workspace and graph camera must exist before the probe.")
		_finish(tree)
		return
	if not gm._graphs.is_empty() or app.loaded_project_once:
		failures.append("Refusing to replace a loaded project; probe must run before startup project loading.")
		_finish(tree)
		return
	OS.low_processor_usage_mode = false
	Engine.max_fps = 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	tree.root.content_scale_factor = 1.0
	tree.root.size = VIEWPORT_SIZE
	app.go_window("graph")
	tree.root.get_node("ui").hide_splash()
	await tree.process_frame
	await RenderingServer.frame_post_draw
	result.launch["first_workspace_draw_engine_ms"] = float(Time.get_ticks_usec()) / 1000.0
	_event("first_workspace_draw", Time.get_ticks_usec())
	result["memory_before_fixture"] = _memory()
	var build_started := Time.get_ticks_usec()
	var rng := RandomNumberGenerator.new()
	rng.seed = FIXTURE_SEED
	var layout: Array = []
	for index in node_count:
		# Use the real node factory with NONE: constructing a benchmark fixture
		# must not create Undo actions or schedule a project autosave.
		var graph = gm.get_graph(&"layer", Graph.Flags.NONE)
		if not is_instance_valid(graph):
			failures.append("Native layer factory failed at node %d." % index)
			break
		var point := Vector2(index % COLUMNS, floori(float(index) / COLUMNS)) * SPACING
		point += Vector2(rng.randf_range(-12, 12), rng.randf_range(-12, 12))
		graph.position = point
		layout.append([point.x, point.y])
		if index % 25 == 24:
			await tree.process_frame
	result.fixture["actual_node_count"] = gm._graphs.size()
	result.fixture["layout_sha256"] = JSON.stringify(layout).sha256_text()
	result["fixture_build_ms"] = float(Time.get_ticks_usec() - build_started) / 1000.0
	if gm._graphs.size() != node_count:
		failures.append("Actual graph size must match the requested fixture size.")
		_finish(tree)
		return
	# Show the usual loaded-workspace shell state without saving this fixture.
	app.fg.set_scene_name("Performance fixture")
	app.loaded_project_once = true
	var camera = app.main_cam
	var center := Vector2(560, 330)
	camera.restore_view(0.6, center)
	await tree.create_timer(SETTLE_SECONDS).timeout
	result["memory_after_settle"] = _memory()
	result.environment["actual_logical_viewport"] = [tree.root.get_visible_rect().size.x, tree.root.get_visible_rect().size.y]
	result.environment["actual_window_pixels"] = [tree.root.size.x, tree.root.size.y]
	if tree.root.get_visible_rect().size != Vector2(VIEWPORT_SIZE):
		failures.append("Actual logical viewport must be exactly 1440×900.")
		_finish(tree)
		return
	_event("fixture_ready", Time.get_ticks_usec())
	result.phases["stationary"] = await _sample(tree, camera, center, false)
	await tree.create_timer(0.5).timeout
	result.phases["pan"] = await _sample(tree, camera, center, true)
	result["memory_after_measurement"] = _memory()
	result.fixture["final_node_count"] = gm._graphs.size()
	if gm._graphs.size() != node_count:
		failures.append("Graph count changed during measurement.")
	_finish(tree)

func _sample(tree: SceneTree, camera: GraphViewport, center: Vector2, pan: bool) -> Dictionary:
	var intervals: Array[float] = []
	var process_times: Array[float] = []
	var physics_times: Array[float] = []
	var draw_calls: Array[float] = []
	var static_bytes: Array[float] = []
	await tree.process_frame
	var started := Time.get_ticks_usec()
	var previous := started
	_event("phase_pan" if pan else "phase_stationary", started)
	while float(Time.get_ticks_usec() - started) / 1000000.0 < duration_seconds:
		if pan:
			# Same wall-clock path across runs, irrespective of achieved FPS.
			# Exercise the native camera interpolation rather than disabling it.
			var fraction := float(Time.get_ticks_usec() - started) / (duration_seconds * 1000000.0)
			var extent := Vector2((COLUMNS - 3) * SPACING.x, (ceilf(float(node_count) / COLUMNS) - 2) * SPACING.y)
			camera.target_position = center + Vector2(extent.x * (0.5 - 0.5 * cos(TAU * fraction)), extent.y * (0.5 - 0.5 * cos(TAU * fraction)))
		await tree.process_frame
		var now := Time.get_ticks_usec()
		intervals.append(float(now - previous) / 1000.0)
		previous = now
		process_times.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
		physics_times.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
		draw_calls.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		static_bytes.append(Performance.get_monitor(Performance.MEMORY_STATIC))
	if intervals.size() <= 30:
		failures.append("Each phase requires more than 30 measured frames; received %d." % intervals.size())
	var frame_summary := _summary(intervals)
	frame_summary["over_16_67_ms"] = intervals.filter(func(value): return value > 1000.0 / 60.0).size()
	frame_summary["over_33_33_ms"] = intervals.filter(func(value): return value > 1000.0 / 30.0).size()
	return {"duration_ms": float(Time.get_ticks_usec() - started) / 1000.0,
		"frames": intervals.size(), "frame_interval_ms": frame_summary,
		"engine_process_ms": _summary(process_times), "engine_physics_ms": _summary(physics_times),
		"draw_calls": _summary(draw_calls), "static_memory_bytes": _summary(static_bytes),
		"raw_frame_interval_ms": intervals, "raw_engine_process_ms": process_times}

func _summary(values: Array[float]) -> Dictionary:
	if values.is_empty():
		return {"count": 0}
	var sorted := values.duplicate()
	sorted.sort()
	var total := 0.0
	for value in sorted:
		total += value
	return {"count": sorted.size(), "median": _percentile(sorted, 0.5),
		"p95": _percentile(sorted, 0.95), "mean": total / sorted.size(),
		"min": sorted[0], "max": sorted[-1]}

func _percentile(sorted: Array[float], fraction: float) -> float:
	var rank := (sorted.size() - 1) * fraction
	var lower := floori(rank)
	return lerpf(sorted[lower], sorted[mini(lower + 1, sorted.size() - 1)], rank - lower)

func _memory() -> Dictionary:
	return {"engine_static_bytes": int(Performance.get_monitor(Performance.MEMORY_STATIC)),
		"engine_static_peak_bytes": int(Performance.get_monitor(Performance.MEMORY_STATIC_MAX)),
		"engine_video_bytes": int(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)),
		"objects": int(Performance.get_monitor(Performance.OBJECT_COUNT)),
		"nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"resources": int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT))}

func _event(phase: String, engine_usec: int) -> void:
	print("PERF_EVENT ", JSON.stringify({"phase": phase, "engine_ms": float(engine_usec) / 1000.0}))

func _finish(tree: SceneTree) -> void:
	if failures.is_empty():
		for phase in ["stationary", "pan"]:
			if not result.phases.has(phase) or result.phases[phase].get("frames", 0) <= 30:
				failures.append("Missing or insufficient measurement phase: " + phase)
	result["failures"] = failures
	result["status"] = "pass" if failures.is_empty() else "fail"
	if not output_path.is_empty():
		DirAccess.make_dir_recursive_absolute(output_path.get_base_dir())
		var file := FileAccess.open(output_path, FileAccess.WRITE)
		if file:
			file.store_string(JSON.stringify(result, "\t"))
			file.close()
		else:
			failures.append("Could not write performance result.")
	if failures.is_empty():
		print("PASS claude_performance_check")
	else:
		for failure in failures:
			push_error("PERFORMANCE_CHECK: " + failure)
	tree.quit(0 if failures.is_empty() else 1)
