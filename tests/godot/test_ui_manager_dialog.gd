extends SceneTree

var failures: Array[String] = []
var close_wait_finished := false
var close_wait_result: Dictionary = {}
var tutorial_close_wait_finished := false
var tutorial_close_wait_result := false


class AxonVisibilityFixture:
	extends Control
	var overlay_open := false
	func layout_for_workspace(_top: float, _bottom: float) -> void:
		pass
	func is_overlay_open() -> bool:
		return overlay_open


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var manager = root.get_node_or_null("ui")
	var global_state = root.get_node_or_null("glob")
	if manager == null or global_state == null:
		push_error("required autoloads are unavailable")
		quit(1)
		return
	if not manager.has_method("show_dialog"):
		push_error("UIManager.show_dialog is missing")
		quit(1)
		return

	_prepare_minimal_ui(manager, global_state)
	var previous_base_node: Node2D = global_state.base_node
	var fixture := Node2D.new()
	var graph_window := Node2D.new()
	graph_window.name = "WIN_GRAPH"
	var palette := CanvasLayer.new()
	palette.name = "NodePalette"
	graph_window.add_child(palette)
	fixture.add_child(graph_window)
	root.add_child(fixture)
	global_state.base_node = fixture
	var spec := {
		"id": "duplicate_test",
		"title": "One",
		"body": "Body",
		"size": {"width": 1200, "height": 900},
		"appearance": {"hide_node_palette": true},
		"buttons": [{"id": "ok", "text": "OK", "style": "primary"}]
	}
	var first = manager.show_dialog(spec)
	var second = manager.show_dialog(spec)
	_expect_equal(first, second, "duplicate id returns active instance")
	_expect_equal(manager.active_dialogs.size(), 1, "one active dialog")
	_expect_equal(palette.visible, false, "active dialog hides the node palette")
	_expect_equal(palette.has_meta("dialog_palette_hidden"), true, "workspace controllers can observe dialog suppression")
	_expect_equal(first.get_node("ColorRect").size, Vector2(752, 552), "dialog uses logical window dimensions")

	first.process_mode = Node.PROCESS_MODE_DISABLED
	first.queue_free()
	await process_frame
	_expect_equal(manager.active_dialogs.size(), 0, "registry cleanup")
	_expect_equal(palette.visible, true, "duplicate lookup does not retain a palette visibility claim")
	_expect_equal(palette.has_meta("dialog_palette_hidden"), false, "last dialog releases suppression for workspace controllers")

	var close_spec := {
		"id": "close_wait_test",
		"title": "Wait for close",
		"body": "",
		"dismiss_on_outside_click": true,
		"appearance": {"hide_node_palette": true},
		"buttons": [{"id": "open", "text": "Open", "style": "primary"}],
	}
	var closing_dialog = manager.show_dialog(close_spec)
	closing_dialog.process_mode = Node.PROCESS_MODE_DISABLED
	_capture_result_after_close(manager, close_spec)
	await process_frame
	closing_dialog.choose_action("open")
	await process_frame
	_expect_equal(close_wait_finished, false, "result waits while the selected dialog is still closing")
	_expect_equal(palette.visible, false, "palette remains hidden while the selected dialog is still closing")
	closing_dialog.queue_free()
	await process_frame
	await process_frame
	_expect_equal(close_wait_finished, true, "result resumes after the selected dialog exits")
	_expect_equal(close_wait_result.get("action"), "open", "result survives the close wait")
	_expect_equal(palette.visible, true, "palette returns after the selected dialog exits")

	var handoff_spec := {
		"id": "startup_handoff_test",
		"title": "Next startup step",
		"body": "",
		"appearance": {"hide_node_palette": true},
		"buttons": [{
			"id": "next",
			"text": "Next",
			"style": "primary",
			"can_go": false,
			"close_mode": "handoff",
		}],
	}
	var handoff_dialog = manager.show_dialog(handoff_spec)
	handoff_dialog.process_mode = Node.PROCESS_MODE_DISABLED
	var handoff_successors: Array = []
	_continue_palette_handoff(manager, handoff_spec, handoff_successors)
	handoff_dialog.choose_action("next")
	await process_frame
	await process_frame
	_expect_equal(
		is_instance_valid(handoff_dialog),
		false,
		"handoff dialog exits in the action frame without waiting for fade processing"
	)
	_expect_equal(
		manager.active_dialogs.has("startup_handoff_test"),
		false,
		"handoff dialog releases its registry slot before the next startup dialog"
	)
	if is_instance_valid(handoff_dialog):
		handoff_dialog.queue_free()
		await process_frame
	_expect_equal(handoff_successors.size(), 1, "handoff opens its successor after the first dialog exits")
	_expect_equal(palette.visible, false, "handoff successor keeps the palette hidden")
	_expect_equal(palette.has_meta("dialog_palette_hidden"), true, "handoff successor owns workspace suppression")
	for successor in handoff_successors:
		if is_instance_valid(successor):
			successor.queue_free()
	await process_frame
	_expect_equal(palette.visible, true, "final handoff step restores the original palette visibility")
	await _test_palette_ownership(manager, palette, graph_window)
	await _test_shell_respects_tour_visibility(manager, global_state, palette)
	var splash_count_before: int = manager.splashed.size()
	var directly_freed := _open_palette_dialog(manager, "direct_dialog_destruction", false)
	_expect_equal(manager.splashed.size(), splash_count_before + 1, "shown dialog is registered in splash lookup")
	directly_freed.free()
	_expect_equal(manager.splashed.size(), splash_count_before, "tree exit removes splash lookup immediately without a process frame")
	_expect_equal(manager.get_splash("dialog:direct_dialog_destruction"), null, "synchronous lookup after direct destruction is safe")
	_expect_equal(manager.is_splashed("dialog:direct_dialog_destruction"), false, "synchronous visibility query after direct destruction is safe")

	var legacy_splash = load("res://scripts/splash_menu.gd").new()
	legacy_splash.typename = "workslist"
	legacy_splash.show_on_ready = false
	legacy_splash.process_mode = Node.PROCESS_MODE_DISABLED
	var legacy_content := ColorRect.new()
	legacy_content.name = "ColorRect"
	legacy_content.size = Vector2(320, 240)
	legacy_splash.add_child(legacy_content)
	root.add_child(legacy_splash)
	manager.splashed[legacy_splash] = true
	_capture_tutorial_close(manager, "workslist")
	await process_frame
	_expect_equal(tutorial_close_wait_finished, false, "tutorial waits while the legacy project list is open")
	manager.splashed.erase(legacy_splash)
	legacy_splash.free()
	for _frame in 5:
		await process_frame
	_expect_equal(tutorial_close_wait_finished, true, "tutorial resumes after the legacy project list closes")
	_expect_equal(tutorial_close_wait_result, true, "legacy project list closure is accepted")
	global_state.base_node = previous_base_node
	fixture.queue_free()
	await process_frame

	if failures.is_empty():
		print("PASS test_ui_manager_dialog: duplicate and cleanup")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func _capture_result_after_close(manager: Node, spec: Dictionary) -> void:
	close_wait_result = await manager.show_dialog_and_get_result(spec, true)
	close_wait_finished = true


func _capture_tutorial_close(manager: Node, dialog_id: String) -> void:
	tutorial_close_wait_result = await manager.wait_for_tutorial_dialog_closed(dialog_id)
	tutorial_close_wait_finished = true


func _palette_spec(dialog_id: String, hide_palette: bool = true) -> Dictionary:
	return {
		"id": dialog_id,
		"title": "Palette ownership",
		"appearance": {"hide_node_palette": hide_palette},
		"buttons": [{"id": "ok", "text": "OK"}],
	}


func _open_palette_dialog(manager: Node, dialog_id: String, hide_palette: bool = true) -> Node:
	var dialog = manager.show_dialog(_palette_spec(dialog_id, hide_palette))
	dialog.process_mode = Node.PROCESS_MODE_DISABLED
	return dialog


func _continue_palette_handoff(manager: Node, spec: Dictionary, successors: Array) -> void:
	await manager.show_dialog_and_get_result(spec, true)
	successors.append(_open_palette_dialog(manager, "palette_handoff_successor"))


func _test_palette_ownership(manager: Node, palette: CanvasLayer, graph_window: Node2D) -> void:
	palette.visible = false
	var hidden_dialog := _open_palette_dialog(manager, "palette_initially_hidden")
	hidden_dialog.queue_free()
	await process_frame
	_expect_equal(palette.visible, false, "dialog preserves an initially hidden palette")
	palette.visible = true

	for first_owner_closes_first in [true, false]:
		var outer := _open_palette_dialog(manager, "palette_outer")
		var inner := _open_palette_dialog(manager, "palette_inner")
		_expect_equal(palette.visible, false, "overlapping dialogs hide the palette")
		var closing: Node = outer if first_owner_closes_first else inner
		var remaining: Node = inner if first_owner_closes_first else outer
		closing.queue_free()
		await process_frame
		_expect_equal(palette.visible, false, "one closing owner cannot reveal the palette beneath another dialog")
		remaining.queue_free()
		await process_frame
		_expect_equal(palette.visible, true, "last owner restores visibility in either close order")
		_expect_equal(palette.has_meta("dialog_palette_hidden"), false, "last nested owner removes workspace suppression")

	var reconfigured := _open_palette_dialog(manager, "palette_reconfigured")
	reconfigured.configure(_palette_spec("palette_reconfigured"), "en", Vector2(800, 600))
	_expect_equal(palette.visible, false, "same-dialog reconfiguration retains its hidden palette")
	var passive := _open_palette_dialog(manager, "palette_passive", false)
	passive.queue_free()
	await process_frame
	_expect_equal(palette.visible, false, "a non-hiding dialog cannot release another dialog's claim")
	reconfigured.configure(_palette_spec("palette_reconfigured", false), "en", Vector2(800, 600))
	_expect_equal(palette.visible, true, "reconfiguration can release its own palette claim")
	reconfigured.configure(_palette_spec("palette_reconfigured"), "en", Vector2(800, 600))
	reconfigured.queue_free()
	await process_frame
	_expect_equal(palette.visible, true, "reacquiring does not replace the original visibility with hidden")

	var leaving_graph := _open_palette_dialog(manager, "palette_leaving_graph")
	graph_window.hide()
	leaving_graph.queue_free()
	await process_frame
	_expect_equal(palette.visible, false, "dialog exit does not resurrect the palette on a hidden graph tab")
	graph_window.show()
	palette.visible = true


func _test_shell_respects_tour_visibility(manager: Node, global_state: Node, palette: CanvasLayer) -> void:
	# Exercise the real per-frame writer that used to reveal the palette again.
	# The Axon fixture isolates only its unrelated geometry/overlay dependency.
	var shell = load("res://scripts/claude_workspace_shell.gd").new()
	var axon := AxonVisibilityFixture.new()
	shell.axon_panel = axon
	var previous_window: String = global_state.curr_window
	global_state.curr_window = "graph"
	var prompt = load("res://scripts/startup/startup_tutorial_prompt.gd")
	var dialog = manager.show_dialog(prompt.dialog_spec())
	dialog.process_mode = Node.PROCESS_MODE_DISABLED
	for _frame in 2:
		shell._process(0.0)
		await process_frame
		_expect_equal(palette.visible, false, "real shell processing respects the optional tour's palette suppression")
	dialog.queue_free()
	await process_frame
	shell._process(0.0)
	_expect_equal(palette.visible, true, "real shell restores the graph palette after the optional tour closes")
	axon.overlay_open = true
	shell._process(0.0)
	_expect_equal(palette.visible, false, "Axon overlay still suppresses the palette after the tour")
	axon.overlay_open = false
	global_state.curr_window = "ds"
	shell._process(0.0)
	_expect_equal(palette.visible, false, "other workspaces still suppress the palette after the tour")
	global_state.curr_window = previous_window
	shell.axon_panel = null
	axon.free()
	shell.free()


func _prepare_minimal_ui(manager: Node, global_state: Node) -> void:
	if manager.topr == null:
		manager.topr = Control.new()
		manager.add_child(manager.topr)
	global_state.tree_windows.erase("env")
	global_state.window_size = Vector2(800, 600)


func _expect_equal(actual: Variant, expected: Variant, label: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [label, str(expected), str(actual)])
