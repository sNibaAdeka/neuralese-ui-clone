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
	var validated_hash := "hash-one"
	var model_hash := "hash-one"
	func robot_model_meta(_input) -> Dictionary:
		if delay_meta: await get_tree().create_timer(0.05).timeout
		return {"status": "ok", "model": {"input_size": 1, "output_size": 2, "model_sha256": model_hash}}
	func robot_platforms() -> Dictionary:
		return {"status": "ok", "platforms": [{"id": "ev3", "sensors": [{"id": "ultrasonic_4", "label": "Distance"}], "actuators": [{"id": "motor_a_speed", "label": "Motor A"}]}]}
	func robot_default_config(_input, _platform) -> Dictionary:
		return {"status": "ok", "config": fixture(), "validation": {"ok": true, "warnings": [{"code": "unscaled_input", "field": "inputs[0]", "message": "No training range is known for this sensor"}]}}
	static func fixture() -> Dictionary:
		return {"schema_version": 1, "platform": "ev3", "transport": {"kind": "tcp", "host": "ev3dev.local", "port": 9999}, "rate_hz": 20, "watchdog_ms": 400, "future_top": "keep", "inputs": [{"channel": "ultrasonic_4", "future_input": 7, "scale": {"kind": "linear", "in_min": 0, "in_max": 100, "out_min": -1, "out_max": 1}}], "outputs": [{"channel": "motor_a_speed", "mode": "argmax", "classes": {"0": 60, "1": -60}, "future_output": "keep"}]}
	func robot_validate_config(_config, _input) -> Dictionary:
		validation_calls += 1
		await get_tree().process_frame
		return {"status": "ok", "model": {"model_sha256": validated_hash}, "validation": {"ok": not invalid, "errors": [{"field": "inputs[0].scale", "message": "Empty range"}] if invalid else []}}
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
func check_narrow(dialog: Window, stage_name: String) -> void:
	dialog.size = Vector2i(375, 600)
	await process_frame
	await process_frame
	check(dialog.size.x == 375 and dialog._body.size.x <= dialog._scroll.size.x, stage_name + ": 375px responsive scroll geometry")
	check(dialog._scroll.get_global_rect().end.x <= 359, stage_name + ": scroll respects narrow window right margin")
	for field in dialog._body.find_children("*", "Control", true, false):
		if field.is_visible_in_tree():
			check(field.get_global_rect().end.x <= 359, stage_name + ": visible field fits narrow window: " + str(field.name))
	check(dialog._actions.all(func(button): return not is_instance_valid(button) or button.size.x <= 343), stage_name + ": footer actions fit narrow dialog")
	check(dialog._primary.get_global_rect().end.x <= 359 and dialog._primary.get_global_rect().position.x >= 16, stage_name + ": primary action stays within narrow footer")

func check_owned_style(dialog: Window) -> void:
	# Exercise the production autoload, including its deferred node-added styling.
	await process_frame
	await process_frame
	root.get_node("ClaudeDesign")._style_branch(dialog)
	await process_frame
	for row in dialog._rows:
		var card := row.channel.get_parent().get_parent().get_parent() as PanelContainer
		var style := card.get_theme_stylebox("panel") as StyleBoxFlat
		var expected := Color("fff8d6") if row.section == "inputs" else Color("fff0e4")
		check(style.bg_color.is_equal_approx(expected), row.section + ": global styling preserves semantic card tint")
		var option_style: StyleBox = row.channel.get_theme_stylebox("normal")
		check(is_equal_approx(option_style.content_margin_top, 8) and is_equal_approx(option_style.content_margin_left, 10), row.section + ": global styling preserves compact select theme")

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
	check(dialog._status.text.contains("Вход 1: сверьте диапазон") and dialog._status.tooltip_text.contains("No training range"), "known warning is concise Russian and retains diagnostic detail")
	check(dialog._mapping.get_child_count() > 0, "mapping exists")
	await check_owned_style(dialog)
	await check_narrow(dialog, "device")
	check(dialog.get_node("Background").color.get_luminance() > 0.9, "native window explicitly paints readable light background")
	check(dialog._step == 0 and dialog._pages.size() == 4, "open starts four-stage wizard at device overview")
	check(dialog._primary.visible and not dialog._back.visible, "first stage has one primary action and no back action")
	check(not dialog._folder.is_visible_in_tree() and not dialog._ranges_confirmed.is_visible_in_tree(), "first stage defers review and destination controls")
	dialog._next_step()
	check(dialog._step == 1 and dialog._mapping.is_visible_in_tree(), "primary advances to mapping cards")
	await check_narrow(dialog, "mapping collapsed")
	var action_count := dialog._actions.size()
	dialog._draw_mapping()
	dialog._draw_mapping()
	check(dialog._actions.size() == action_count, "redraw prunes stale action controls")
	check(dialog._status.text.is_empty(), "rebuilt mapping clears stale validation report")
	await check_owned_style(dialog)
	for mapping_row in dialog._rows:
		check(not mapping_row.details.visible, "numeric details start collapsed")
		mapping_row.disclosure.pressed.emit()
		check(mapping_row.details.visible, "disclosure opens numeric tuning")
	await check_narrow(dialog, "mapping expanded")
	var row: Dictionary = dialog._rows[1]
	row.mode.select(2)
	row.mode.item_selected.emit(2)
	row.threshold.value = 0.7
	row.on_value.value = 70
	row.off_value.value = -20
	var threshold: Dictionary = dialog.collect_config().config.outputs[0]
	check(threshold.mode == "threshold" and is_equal_approx(threshold.threshold, 0.7) and threshold.on_value == 70 and threshold.off_value == -20, "threshold structured fields")
	row.mode.select(0)
	row.mode.item_selected.emit(0)
	row.direct_index.value = 1
	row.scale.kind.select(1)
	row.scale.in_max.value = 2
	check(dialog.collect_config().config.outputs[0].index == 1, "direct structured fields")
	row.mode.select(1)
	row.mode.item_selected.emit(1)
	dialog._next_step()
	check(dialog._step == 2 and dialog._review.text.contains("Мотор A"), "review summarizes mapping")
	await check_narrow(dialog, "review")
	check(not dialog._settings.visible, "manual transport settings start collapsed")
	for button in dialog._pages[2].find_children("*", "Button", true, false):
		if button.text.begins_with("Параметры ручного запуска"):
			button.pressed.emit()
	check(dialog._settings.visible, "review disclosure reveals manual transport settings")
	await check_narrow(dialog, "review expanded")
	var calls_before := runtime.validation_calls
	await dialog._validate("continue")
	check(dialog._step == 2 and runtime.validation_calls == calls_before and not dialog._validated, "review confirmation gates validation and export stage")
	dialog._ranges_confirmed.button_pressed = true
	runtime.invalid = true
	await dialog._validate("save")
	check(not FileAccess.file_exists(dialog.storage_path), "invalid changes never saved")
	check(not dialog._busy and dialog._status.text.contains("inputs[0].scale"), "validation recovery with field detail")
	await dialog._validate("continue")
	check(dialog._step == 2 and not dialog._validated and runtime.exports == 0, "invalid review cannot advance or export")
	runtime.invalid = false
	dialog._rows[0].scale.in_min.value = 1e-8
	dialog._rows[0].scale.out_min.value = 0.123456789012345
	await dialog._validate("save")
	check(dialog.load_mapping(dialog._scope).get("future_top") == "keep", "valid save succeeds")
	check(dialog.load_mapping("other-project").is_empty(), "scope isolation")
	dialog._ranges_confirmed.button_pressed = true
	await dialog._validate("continue")
	check(dialog._step == 3 and dialog._validated, "valid confirmed review advances to destination")
	await check_narrow(dialog, "export")
	dialog._back.pressed.emit()
	check(dialog._step == 2, "back returns to review")
	dialog._back.pressed.emit()
	check(dialog._step == 1, "back returns to mapping")
	dialog._rows[0].scale.out_max.value = 9
	check(not dialog._validated and not dialog._ranges_confirmed.button_pressed, "re-edit invalidates review and explicit confirmation")
	dialog._next_step()
	await dialog._validate("continue")
	check(dialog._step == 2 and not dialog._validated, "re-edited draft cannot reuse earlier approval")
	var cancel_event := InputEventAction.new()
	cancel_event.action = "ui_cancel"
	cancel_event.pressed = true
	dialog._unhandled_key_input(cancel_event)
	await dialog.open_for(input, "project-a", runtime)
	check(dialog._rows[0].scale.out_max.value == 1, "cancel discards unsaved changes on reopen")
	check(dialog._step == 0 and not dialog._validated and not dialog._ranges_confirmed.button_pressed, "keyboard cancel/reopen resets stage and review state")
	check(dialog._rows[0].scale.in_min.value == 1e-8 and dialog._rows[0].scale.out_min.value == 0.123456789012345, "saved ranges retain full float precision")
	dialog._next_step()
	dialog._next_step()
	dialog._folder.text = test_dir
	dialog._bundle_name.text = "ev3-test-%s" % Time.get_ticks_usec()
	await dialog._validate("export")
	check(runtime.exports == 0, "explicit training range confirmation required")
	dialog._ranges_confirmed.button_pressed = true
	runtime.validated_hash = "changed-hash"
	await dialog._validate("continue")
	check(dialog._step == 2 and not dialog._validated and dialog._status.text.contains("модель изменилась"), "changed model hash blocks stage advancement")
	runtime.validated_hash = "hash-one"
	await dialog._validate("continue")
	check(dialog._step == 3 and dialog._validated, "review recovers after validation hash error")
	runtime.fail_export = true
	await dialog._validate("export")
	check(runtime.exports == 1 and not dialog._busy and dialog._status.text.contains("Disk full"), "export error recoverable")
	check(dialog._step == 3 and not dialog._primary.disabled and not dialog._finished, "failed export stays at destination with retry available")
	runtime.fail_export = false
	await dialog._validate("export")
	check(runtime.exports == 2 and dialog._status.text.contains("Пакет создан"), "retry export succeeds")
	check(dialog._finished and dialog._primary.text == "Готово", "successful export changes primary action to done")
	check(dialog._success_box.is_visible_in_tree() and not dialog._export_form.visible and dialog._success.text.contains(test_dir), "success replaces destination form with transfer instructions and actual path")
	for button in dialog._success_box.find_children("*", "Button", true, false):
		if button.text == "Создать ещё": button.pressed.emit()
	check(dialog._export_form.is_visible_in_tree() and not dialog._success_box.visible and not dialog._finished, "create another returns to editable destination")
	dialog._bundle_name.text += "-new"
	dialog._bundle_name.text_changed.emit(dialog._bundle_name.text)
	check(not dialog._finished and dialog._primary.text == "Создать пакет" and dialog._validated, "editing destination name resets done action while preserving validated mapping")
	await dialog._next_step()
	check(runtime.exports == 3 and dialog._finished and dialog._primary.text == "Готово", "primary exports edited destination instead of closing success state")
	dialog._picker.dir_selected.emit(test_dir)
	check(not dialog._finished and dialog._primary.text == "Создать пакет", "choosing destination folder resets done action")
	await dialog._next_step()
	check(runtime.exports == 4 and dialog._finished and dialog._success_box.visible and not dialog._export_form.visible, "primary can export after choosing folder again")
	await dialog._next_step()
	check(not dialog.visible, "done primary closes completed wizard")
	await dialog.open_for(input, "project-a", runtime)
	check(not Dialog.bundle_destination(test_dir, "../unsafe").ok, "path traversal refused")
	check(not Dialog.bundle_destination(test_dir.get_base_dir(), test_dir.get_file()).ok, "existing folder refused")
	var escape := InputEventAction.new()
	escape.action = "ui_cancel"
	escape.pressed = true
	dialog._unhandled_key_input(escape)
	check(not dialog.visible and dialog.blocks_parent_input(), "Escape closes child and suppresses parent polling same frame")
	await process_frame
	check(dialog.blocks_parent_input(), "parent polling suppressed following close frame")
	runtime.model_hash = "hash-two"
	await dialog.open_for(input, "project-a", runtime)
	check(dialog._rows[0].scale.in_min.value == 0 and dialog._rows[0].scale.out_min.value == -1, "new model weights do not reuse saved mapping from older hash")
	dialog._cancel()
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
