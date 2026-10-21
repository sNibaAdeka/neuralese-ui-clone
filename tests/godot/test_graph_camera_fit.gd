extends SceneTree

const UIContext = preload("res://tests/godot/fixtures/simulation_ui_context.gd")
var camera_script: Script
var graph_script: Script

var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await process_frame
	# Production scripts reference autoloads, so load them after initialization.
	camera_script = load("res://scripts/camera_2d.gd")
	graph_script = load("res://scripts/base_graph.gd")
	if camera_script == null or not camera_script.can_instantiate() or graph_script == null or not graph_script.can_instantiate():
		push_error("FAIL test_graph_camera_fit: camera/graph scripts did not load")
		quit(1)
		return
	_test_fitted_rectangles()
	_test_limits_and_empty_regions()
	_test_empty_selection()
	_test_fit_range_transition()
	_test_emphasis_and_manual_view()
	if failures.is_empty():
		print("PASS test_graph_camera_fit")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		push_error("FAIL test_graph_camera_fit: %d failure(s)" % failures.size())
		quit(1)


func _test_fitted_rectangles() -> void:
	_assert_fits(Rect2(-400, -100, 1200, 600), Vector2(1440, 900), Rect2(224, 88, 1216, 812), "wide canvas")
	var narrow := _assert_fits(Rect2(0, 0, 1263, 798), Vector2(375, 812), Rect2(0, 196, 375, 616), "narrow canvas")
	if not narrow.is_empty():
		_expect(float(narrow["zoom"]) < camera_script.MIN_ZOOM, "narrow framing must be able to fit below the ordinary wheel minimum")
	_assert_fits(Rect2(120, -900, 200, 1500), Vector2(1024, 768), Rect2(224, 88, 800, 680), "tall graph")
	_assert_fits(Rect2(0, 0, 400, 200), Vector2(1000, 700), Rect2(240, 100, 600, 550), "asymmetric canvas")
	_assert_fits(Rect2(-100, -300, 1000, 700), Vector2(1000, 700), Rect2(-50, -80, 2200, 1600), "clipped stale viewport bounds")


func _assert_fits(bounds: Rect2, viewport_size: Vector2, available: Rect2, label: String) -> Dictionary:
	var fitted: Dictionary = camera_script.fit_bounds_to_viewport(bounds, viewport_size, available)
	_expect(not fitted.is_empty(), label + ": a usable canvas must produce a camera target")
	if fitted.is_empty():
		return fitted
	var inner: Rect2 = available.intersection(Rect2(Vector2.ZERO, viewport_size)).grow(-camera_script.FIT_PADDING)
	var z := float(fitted["zoom"])
	var position: Vector2 = fitted["position"]
	var projected_center := (bounds.get_center() - position) * z + viewport_size * 0.5
	_expect(projected_center.is_equal_approx(inner.get_center()), label + ": graph center must land in the free canvas, not the whole-window center")
	var projected_begin := (bounds.position - position) * z + viewport_size * 0.5
	var projected_end := (bounds.end - position) * z + viewport_size * 0.5
	var tolerance := 0.001
	_expect(projected_begin.x >= inner.position.x - tolerance and projected_begin.y >= inner.position.y - tolerance,
		label + ": the graph must clear the left/header inset")
	_expect(projected_end.x <= inner.end.x + tolerance and projected_end.y <= inner.end.y + tolerance,
		label + ": the graph must clear the right/bottom inset")
	return fitted


func _test_limits_and_empty_regions() -> void:
	var viewport_size := Vector2(1000, 700)
	var available := Rect2(Vector2.ZERO, viewport_size)
	var tiny: Dictionary = camera_script.fit_bounds_to_viewport(Rect2(0, 0, 1, 1), viewport_size, available)
	_expect(is_equal_approx(float(tiny.get("zoom", 0)), camera_script.MAX_ZOOM), "tiny bounds must respect maximum zoom")
	var huge: Dictionary = camera_script.fit_bounds_to_viewport(Rect2(0, 0, 100000, 100000), viewport_size, available)
	_expect(is_equal_approx(float(huge.get("zoom", 0)), camera_script.MIN_FIT_ZOOM), "extreme graphs must respect the explicit fit floor, even when full enclosure is impossible")
	_expect(camera_script.fit_bounds_to_viewport(Rect2(), viewport_size, available).is_empty(), "empty bounds must not move the camera")
	_expect(camera_script.fit_bounds_to_viewport(Rect2(0, 0, 100, 100), Vector2.ZERO, available).is_empty(), "zero viewport must not divide by zero")
	_expect(camera_script.fit_bounds_to_viewport(Rect2(0, 0, 100, 100), viewport_size, Rect2(1200, 0, 50, 50)).is_empty(), "an unavailable canvas must not move the camera")
	_expect(camera_script.fit_bounds_to_viewport(Rect2(0, 0, 100, 100), viewport_size, Rect2(0, 0, 40, 40)).is_empty(), "padding that consumes the canvas must not create a negative zoom")
	_expect(camera_script.fit_bounds_to_viewport(Rect2(Vector2(NAN, 0), Vector2(100, 100)), viewport_size, available).is_empty(), "non-finite bounds must not reach camera transforms")


func _test_empty_selection() -> void:
	var camera = camera_script.new()
	camera.go_camera(1.5, Vector2(9, 17))
	camera.emp_node([])
	camera.emp_node([-987654321])
	_expect(camera._go_active and is_equal_approx(camera._go_to_zoom, 1.5) and camera._go_to_pos == Vector2(9, 17),
		"empty or missing targets must preserve an existing camera movement")
	camera.free()


func _test_fit_range_transition() -> void:
	var camera = camera_script.new()
	camera.restore_view(0.1, Vector2.ZERO)
	camera._set_user_zoom(0.5)
	var next: float = camera._interpolated_zoom(1.0 / 60.0)
	_expect(next > 0.1 and next < camera_script.MIN_ZOOM,
		"crossing the ordinary input minimum must not snap the rendered zoom to 0.4")
	for frame in 120:
		var previous: float = camera.zoom.x
		next = camera._interpolated_zoom(1.0 / 60.0)
		_expect(next >= previous and next <= 0.5, "returning from fit range must converge monotonically without overshoot")
		camera.zoom = Vector2.ONE * next
	_expect(is_equal_approx(camera.zoom.x, 0.5), "the extended interpolation floor must not prevent reaching ordinary zoom")
	camera._set_user_zoom(0.1)
	_expect(is_equal_approx(camera.target_zoom, camera_script.MIN_ZOOM), "after crossing, ordinary manual minimum must still apply")
	camera.free()


func _test_emphasis_and_manual_view() -> void:
	var global_state = get_root().get_node("glob")
	var old_begin: Vector2 = global_state.space_begin
	var old_end: Vector2 = global_state.space_end
	var old_hide_menus: bool = global_state.hide_menus
	var old_menu_canvas: CanvasLayer = global_state.menu_canvas
	var menu_canvas := UIContext.install(self)
	global_state.space_begin = Vector2(0, 196)
	global_state.space_end = Vector2(375, 812)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(375, 812)
	get_root().add_child(viewport)
	var camera = camera_script.new()
	camera.set_process(false)
	camera.set_process_input(false)
	viewport.add_child(camera)
	camera.set_process(false)
	camera.set_process_input(false)
	var first = _graph_rect(Vector2(-100, -50), Vector2(144, 244))
	var second = _graph_rect(Vector2(800, 350), Vector2(233, 244))
	var first_position: Vector2 = first.rect.position
	var second_position: Vector2 = second.rect.position
	camera.emp_node([first, second])
	_expect(camera._go_active, "emphasis must schedule the existing smooth camera movement")
	var fitted_zoom: float = camera._go_to_zoom
	var fitted_position: Vector2 = camera._go_to_pos
	_expect(fitted_zoom < camera_script.MIN_ZOOM, "real emphasis must enter the wider fit range on a narrow viewport")
	_expect(is_equal_approx(camera._valid_zoom(fitted_zoom), fitted_zoom), "the ordinary frame validator must preserve fitted zoom")
	var bounds: Rect2 = first.rect.get_global_rect().merge(second.rect.get_global_rect())
	var projected_center := (bounds.get_center() - fitted_position) * fitted_zoom + Vector2(viewport.size) * 0.5
	_expect(projected_center.is_equal_approx(Vector2(187.5, 504)), "emphasis must use live header/palette space bounds")
	_expect(first.rect.position == first_position and second.rect.position == second_position, "framing must never rearrange graph nodes")
	camera.restore_view(fitted_zoom, fitted_position)
	camera.emp_node([first])
	camera.target_zoom = camera._go_to_zoom
	var closer_zoom: float = camera._interpolated_zoom(1.0 / 60.0)
	_expect(closer_zoom > fitted_zoom and closer_zoom < camera.target_zoom,
		"framing a small node from a wide fitted view must keep the existing smooth transition")

	camera.restore_view(fitted_zoom, fitted_position)
	_expect(not camera._go_active, "restoring a saved view during emphasis must cancel the old model's camera movement")
	camera.reset() # Also used when switching workspace tabs.
	viewport.size = Vector2i(1000, 700)
	_expect(is_equal_approx(camera.target_zoom, fitted_zoom) and camera.target_position.is_equal_approx(fitted_position) and not camera._go_active,
		"resizing must retain the saved/manual view rather than trigger another fit")
	_expect(is_equal_approx(camera._valid_zoom(camera.target_zoom), fitted_zoom), "saved below-minimum framing must survive restoring and resetting tab state")
	camera._set_user_zoom(fitted_zoom + 0.03)
	_expect(is_equal_approx(camera.target_zoom, fitted_zoom + 0.03), "zooming from a fitted view must not jump directly to 0.4")
	camera._set_user_zoom(0.5)
	camera._set_user_zoom(0.1)
	_expect(is_equal_approx(camera.target_zoom, camera_script.MIN_ZOOM), "after returning to ordinary zoom, wheel navigation must regain its original minimum")
	camera._set_user_zoom(8.0)
	_expect(is_equal_approx(camera.target_zoom, camera_script.MAX_ZOOM), "wheel navigation must retain its maximum")
	var ordinary = camera_script.new()
	ordinary._set_user_zoom(0.1)
	_expect(is_equal_approx(ordinary.target_zoom, camera_script.MIN_ZOOM), "ordinary sessions must not acquire the framing-only lower bound")
	ordinary.free()
	first.free()
	second.free()
	viewport.free()
	global_state.space_begin = old_begin
	global_state.space_end = old_end
	global_state.hide_menus = old_hide_menus
	if menu_canvas != old_menu_canvas:
		global_state.menu_canvas = old_menu_canvas
		menu_canvas.free()


func _graph_rect(at: Vector2, dimensions: Vector2):
	# Detached graph fixtures exercise real bounding boxes without loading node UI.
	var graph = graph_script.new()
	var rectangle := Control.new()
	graph.add_child(rectangle)
	rectangle.position = at
	rectangle.size = dimensions
	graph.rect = rectangle
	return graph


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
