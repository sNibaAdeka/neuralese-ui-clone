extends Node

var failures: Array[String] = []
var theme_changes := 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	# Tabs re-run their layout from _process every frame. Anything in that path that requests
	# a redraw (a theme override write, an instance shader parameter, a size that flips
	# between two values) keeps the whole editor drawing at full frame rate while idle.
	for i in 30:
		await get_tree().process_frame
	var tab: Node = glob.tree_windows.get("env")
	_expect(tab != null, "simulation tab exists")
	if tab == null:
		_finish()
		return
	glob.go_window("env")
	for i in 5:
		await get_tree().process_frame

	# The engine turns camera polling back on inside make_current(); the tab must undo that.
	var camera: Camera2D = tab.camera
	_expect(camera.enabled, "simulation camera is enabled after window_show")
	_expect(not camera.is_processing_internal(), "simulation camera does not poll in its internal process")

	var controls: Control = tab.editor.runtime_controls
	controls.set_script(load("res://tests/godot/support/theme_change_counter.gd"))
	controls.set("owner_test", self)
	for i in 5:
		await get_tree().process_frame
	theme_changes = 0
	for i in 30:
		tab.editor.set_content_top(48.0)
		await get_tree().process_frame
	_expect(theme_changes == 0, "repeated layout with unchanged values sends no theme-change notifications (%d)" % theme_changes)

	# Dataset workspace: its root, canvas and side panels must settle after layout.
	glob.go_window("ds")
	for i in 10:
		await get_tree().process_frame
	var workspace = glob.tree_windows["ds"]
	var rect_changes := [0]
	for control in [workspace._root, workspace._canvas, workspace._palette, workspace._inspector]:
		control.item_rect_changed.connect(func(): rect_changes[0] += 1)
	for i in 30:
		await get_tree().process_frame
	_expect(rect_changes[0] == 0, "an idle dataset workspace does not resize its panels (%d changes in 30 frames)" % rect_changes[0])
	_finish()


func _finish() -> void:
	if failures.is_empty():
		print("PASS test_tabs_idle")
		get_tree().quit(0)
	else:
		for f in failures:
			printerr("FAIL: ", f)
		get_tree().quit(1)


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		failures.append(msg)
