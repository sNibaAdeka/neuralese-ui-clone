extends SceneTree
const Dialog = preload("res://scripts/robot_export_dialog.gd")
class InputModel extends Node:
	var context_id := "test-model"
class Runtime extends Node:
	var invalid := false
	var fail_export := false
	var validation_calls := 0
	var exports := 0
	var delay_meta := false
	func robot_model_meta(_input) -> Dictionary:
		if delay_meta: await get_tree().create_timer(0.05).timeout
		return {"status": "ok", "model": {"input_size": 1, "output_size": 2, "model_sha256": "hash-one"}}
	func robot_platforms() -> Dictionary:
		return {"status": "ok", "platforms": [{"id": "ev3", "sensors": [{"id": "ultrasonic_4", "label": "Distance"}], "actuators": [{"id": "motor_a_speed", "label": "Motor A"}]}]}
	func robot_default_config(_input, _platform) -> Dictionary:
		return {"status": "ok", "config": fixture(), "validation": {"ok": true, "warnings": [{"field": "inputs[0]", "message": "Training range unknown"}]}}
	static func fixture() -> Dictionary:
		return {"schema_version": 1, "platform": "ev3", "transport": {"kind": "tcp", "host": "ev3dev.local", "port": 9999}, "rate_hz": 20, "watchdog_ms": 400, "future_top": "keep", "inputs": [{"channel": "ultrasonic_4", "future_input": 7, "scale": {"kind": "linear", "in_min": 0, "in_max": 100, "out_min": -1, "out_max": 1}}], "outputs": [{"channel": "motor_a_speed", "mode": "argmax", "classes": {"0": 60, "1": -60}, "future_output": "keep"}]}
	func robot_validate_config(_config, _input) -> Dictionary:
		validation_calls += 1
		await get_tree().process_frame
		return {"status": "ok", "model": {"model_sha256": "hash-one"}, "validation": {"ok": not invalid, "errors": [{"field": "inputs[0].scale", "message": "Empty range"}] if invalid else []}}
	func export_robot_bundle(_input, _platform, _path, _config, _lang, _signature, hash_value) -> Dictionary:
		assert(hash_value == "hash-one")
		exports += 1
		await get_tree().process_frame
		return {"status": "error", "error": "Disk full"} if fail_export else {"status": "ok"}
var failures := 0
func _initialize() -> void:
	call_deferred("_run")
func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		printerr("FAIL: ", message)
func _run() -> void:
	var input := InputModel.new()
	root.add_child(input)
	var runtime := Runtime.new()
	root.add_child(runtime)
	var dialog := Dialog.new()
	var test_dir := ProjectSettings.globalize_path("user://ev3-ui-test-%s" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(test_dir)
	dialog.storage_path = test_dir.path_join("mapping.json")
	root.add_child(dialog)
	await dialog.open_for(input, "project-a", runtime)
	check(dialog.collect_config().config.future_top == "keep" and dialog.collect_config().config.inputs[0].future_input == 7 and dialog.collect_config().config.outputs[0].future_output == "keep", "structured controls preserve unknown fields")
	check(dialog._status.text.contains("Training range unknown"), "default warnings shown")
	check(dialog._mapping.get_child_count() > 0, "mapping exists")
	dialog.size = Vector2i(375, 600)
	await process_frame
	await process_frame
	check(dialog.size.x == 375 and dialog._body.size.x <= dialog._scroll.size.x, "375px responsive scroll geometry")
	check(dialog._actions.all(func(button): return not is_instance_valid(button) or button.size.x <= 343), "footer actions fit narrow dialog")
	var action_count := dialog._actions.size()
	dialog._draw_mapping()
	dialog._draw_mapping()
	check(dialog._actions.size() == action_count, "redraw prunes stale action controls")
	var row: Dictionary = dialog._rows[1]
	row.mode.select(2)
	row.threshold.value = 0.7
	row.on_value.value = 70
	row.off_value.value = -20
	var threshold: Dictionary = dialog.collect_config().config.outputs[0]
	check(threshold.mode == "threshold" and is_equal_approx(threshold.threshold, 0.7) and threshold.on_value == 70 and threshold.off_value == -20, "threshold structured fields")
	row.mode.select(0)
	row.direct_index.value = 1
	row.scale.kind.select(1)
	row.scale.in_max.value = 2
	check(dialog.collect_config().config.outputs[0].index == 1, "direct structured fields")
	row.mode.select(1)
	runtime.invalid = true
	await dialog._validate("save")
	check(not FileAccess.file_exists(dialog.storage_path), "invalid changes never saved")
	check(not dialog._busy and dialog._status.text.contains("inputs[0].scale"), "validation recovery with field detail")
	runtime.invalid = false
	dialog._rows[0].scale.in_min.value = 1e-8
	dialog._rows[0].scale.out_min.value = 0.123456789012345
	await dialog._validate("save")
	check(dialog.load_mapping(dialog._scope).get("future_top") == "keep", "valid save succeeds")
	check(dialog.load_mapping("other-project").is_empty(), "scope isolation")
	dialog._rows[0].scale.out_max.value = 9
	dialog._cancel()
	await dialog.open_for(input, "project-a", runtime)
	check(dialog._rows[0].scale.out_max.value == 1, "cancel discards unsaved changes on reopen")
	check(dialog._rows[0].scale.in_min.value == 1e-8 and dialog._rows[0].scale.out_min.value == 0.123456789012345, "saved ranges retain full float precision")
	dialog._folder.text = test_dir
	dialog._bundle_name.text = "ev3-test-%s" % Time.get_ticks_usec()
	await dialog._validate("export")
	check(runtime.exports == 0, "explicit training range confirmation required")
	dialog._ranges_confirmed.button_pressed = true
	runtime.fail_export = true
	await dialog._validate("export")
	check(runtime.exports == 1 and not dialog._busy and dialog._status.text.contains("Disk full"), "export error recoverable")
	runtime.fail_export = false
	await dialog._validate("export")
	check(runtime.exports == 2 and dialog._status.text.contains("Пакет создан"), "retry export succeeds")
	check(not Dialog.bundle_destination(test_dir, "../unsafe").ok, "path traversal refused")
	check(not Dialog.bundle_destination(test_dir.get_base_dir(), test_dir.get_file()).ok, "existing folder refused")
	var escape := InputEventAction.new()
	escape.action = "ui_cancel"
	escape.pressed = true
	dialog._unhandled_key_input(escape)
	check(not dialog.visible and dialog.blocks_parent_input(), "Escape closes child and suppresses parent polling same frame")
	await process_frame
	check(dialog.blocks_parent_input(), "parent polling suppressed following close frame")
	runtime.delay_meta = true
	dialog.open_for(input, "stale-project", runtime)
	dialog._cancel()
	await create_timer(0.1).timeout
	check(not dialog.visible and dialog._config.is_empty(), "closed load result ignored")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(dialog.storage_path))
	DirAccess.remove_absolute(test_dir)
	dialog.queue_free()
	runtime.queue_free()
	input.queue_free()
	await process_frame
	if failures == 0: print("PASS test_robot_export_dialog")
	quit(0 if failures == 0 else 1)
