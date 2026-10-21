extends Node

var failures: Array[String] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	# ui.blur is a full-screen live-blur panel. At self_modulate.a == 0 it draws nothing, but
	# the engine still copies the framebuffer and shades every pixel for it, every frame. It must
	# therefore be hidden whenever its alpha is zero and shown as soon as a splash raises it.
	for i in 20:
		await get_tree().process_frame
	# Headless never renders, so the engine never emits frame_pre_draw; emit it by hand.
	var blur: CanvasItem = ui.blur
	blur.self_modulate.a = 0.0
	RenderingServer.frame_pre_draw.emit()
	_expect(not blur.visible, "ui.blur is hidden while its alpha is 0")

	blur.self_modulate.a = 0.6
	RenderingServer.frame_pre_draw.emit()
	_expect(blur.visible, "ui.blur is shown once a splash raises its alpha")

	blur.self_modulate.a = 0.0
	RenderingServer.frame_pre_draw.emit()
	_expect(not blur.visible, "ui.blur is hidden again when the splash fades out")

	if failures.is_empty():
		print("PASS test_ui_blur_visibility")
		get_tree().quit(0)
	else:
		for f in failures:
			printerr("FAIL: ", f)
		get_tree().quit(1)


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		failures.append(msg)
