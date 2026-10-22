extends Window
## Local EV3 bundle editor. Drafts are discarded on close; only validated Save persists.
const Design = preload("res://scripts/claude_design_theme.gd")
const STORE_PATH := "user://robot_export_mappings.json"
var runtime: Node
var storage_path := STORE_PATH
var _input: Node
var _scope := ""
var _generation := 0
var _busy := false
var _exporting := false
var _closed_frame := -100
var _config: Dictionary = {}
var _platform: Dictionary = {}
var _model: Dictionary = {}
var _ranges_confirmed: CheckBox
var _rows: Array[Dictionary] = []
var _scroll: ScrollContainer
var _body: VBoxContainer
var _mapping: VBoxContainer
var _settings: VBoxContainer
var _host: LineEdit
var _port: SpinBox
var _rate: SpinBox
var _watchdog: SpinBox
var _status: Label
var _meta: Label
var _folder: LineEdit
var _bundle_name: LineEdit
var _actions: Array[Button] = []
var _picker: FileDialog

func _ready() -> void:
	title = "EV3 · Экспорт модели"
	min_size = Vector2i(360, 420)
	size = Vector2i(700, 650)
	transient = true
	exclusive = true
	wrap_controls = false
	theme = Design.create_theme()
	close_requested.connect(_cancel)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 16)
	add_child(margin)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 10)
	margin.add_child(outer)
	_meta = _label(outer, "Проверяем локальную обученную модель…")
	_label(outer, "Пакет для ручного переноса на EV3. На устройстве не проверено. Подключение к роботу не выполняется.")
	var scroll := ScrollContainer.new()
	_scroll = scroll
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(scroll)
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 10)
	scroll.add_child(_body)
	_mapping = VBoxContainer.new()
	_body.add_child(_mapping)
	var advanced := CheckBox.new()
	advanced.text = "Параметры связи и тайм-аут"
	_body.add_child(advanced)
	_settings = VBoxContainer.new()
	_body.add_child(_settings)
	_settings.visible = false
	advanced.toggled.connect(func(enabled: bool): _settings.visible = enabled)
	_label(_settings, "Адрес EV3 для будущего ручного запуска. При экспорте соединение не создаётся.")
	_host = LineEdit.new()
	_host.placeholder_text = "ev3dev.local"
	_host.text_changed.connect(func(_text: String): _mapping_edited())
	_settings.add_child(_host)
	_port = _number(_settings, "Порт", 9999, true)
	_rate = _number(_settings, "Частота, Гц", 20, true)
	_watchdog = _number(_settings, "Остановка при потере связи, мс", 400, true)
	_label(_body, "Папка назначения → новая подпапка пакета (существующие папки не заменяются)")
	_folder = LineEdit.new()
	_folder.placeholder_text = "Выберите родительскую папку"
	_folder.editable = false
	_body.add_child(_folder)
	_button(_body, "Выбрать папку…", _choose_folder)
	_bundle_name = LineEdit.new()
	_bundle_name.text = "ev3_bundle"
	_body.add_child(_bundle_name)
	_ranges_confirmed = CheckBox.new()
	_ranges_confirmed.text = "Диапазоны и команды проверены"
	_body.add_child(_ranges_confirmed)
	_status = _label(_body, "")
	_status.custom_minimum_size.y = 58
	var buttons := HFlowContainer.new()
	outer.add_child(buttons)
	_button(buttons, "Проверить", _validate.bind("validate"))
	_button(buttons, "Сохранить настройки", _validate.bind("save"))
	_button(buttons, "Экспорт пакета", _validate.bind("export"))
	var cancel := Button.new()
	cancel.text = "Закрыть · отменить правки"
	cancel.pressed.connect(_cancel)
	buttons.add_child(cancel)
	_picker = FileDialog.new()
	_picker.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	_picker.access = FileDialog.ACCESS_FILESYSTEM
	_picker.use_native_dialog = true
	_picker.dir_selected.connect(func(path: String): _folder.text = path)
	add_child(_picker)

func _label(parent: Node, text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(label)
	return label

func _button(parent: Node, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(action)
	parent.add_child(button)
	_actions.append(button)
	return button

func open_for(input: Node, project_key: String, provider: Node = null) -> void:
	_generation += 1
	var generation := _generation
	_input = input
	runtime = provider if provider != null else get_node("/root/nn")
	_scope = JSON.stringify([project_key, str(input.get("context_id"))]) if is_instance_valid(input) else ""
	_config = {}
	_platform = {}
	_ranges_confirmed.button_pressed = false
	_clear_rows()
	_host.text = ""
	_meta.text = "Проверяем локальную обученную модель…"
	var available := get_tree().root.get_visible_rect().size
	popup_centered(Vector2i(mini(700, int(available.x)), mini(650, int(available.y))))
	if not is_instance_valid(input):
		_failed({"error": "Выберите входной узел модели и обучите её локально перед экспортом."})
		return
	_set_busy(true)
	var meta: Dictionary = await runtime.robot_model_meta(input)
	if not _current(generation): return
	if meta.get("status") != "ok":
		_failed(meta)
		return
	_model = meta.get("model", {}).duplicate(true)
	_scope = JSON.stringify([project_key, str(input.get("context_id")), str(_model.get("model_sha256", ""))])
	_meta.text = "EV3 · %s входов → %s выходов" % [meta.get("model", {}).get("input_size", "?"), meta.get("model", {}).get("output_size", "?")]
	var registry: Dictionary = await runtime.robot_platforms()
	if not _current(generation): return
	if registry.get("status") != "ok":
		_failed(registry)
		return
	for platform in registry.get("platforms", []):
		if platform.get("id") == "ev3": _platform = platform
	if _platform.is_empty():
		_failed({"error": "Платформа EV3 недоступна."})
		return
	var saved := load_mapping(_scope)
	if not saved.is_empty():
		_config = saved
		_status.text = "Загружены сохранённые настройки. Закрытие отменяет несохранённые правки."
	else:
		var defaults: Dictionary = await runtime.robot_default_config(input, "ev3")
		if not _current(generation): return
		if defaults.get("status") != "ok":
			_failed(defaults)
			return
		_config = defaults.get("config", {}).duplicate(true)
		_status.text = "Проверьте диапазоны датчиков по обучающим данным. Автоматические значения — только начальная настройка.\n" + _report(defaults.get("validation", {}))
	_draw_mapping()
	_set_busy(false)
	_ranges_confirmed.grab_focus()

func _clear_rows() -> void:
	_actions = _actions.filter(func(button): return is_instance_valid(button) and not _mapping.is_ancestor_of(button))
	_rows.clear()
	for child in _mapping.get_children():
		_mapping.remove_child(child)
		child.queue_free()

func _draw_mapping() -> void:
	_clear_rows()
	for section in ["inputs", "outputs"]:
		_label(_mapping, "Датчики → входы модели (по порядку)" if section == "inputs" else "Выходы модели → моторы")
		for index in range(_config.get(section, []).size()):
			_add_row(section, index, _config[section][index])
		if section == "outputs":
			_button(_mapping, "+ Мотор", _append_output)
		else:
			_button(_mapping, "+ Датчик", _append_input)
	_host.text = str(_config.get("transport", {}).get("host", "ev3dev.local"))
	_port.value = float(_config.get("transport", {}).get("port", 9999))
	_rate.value = float(_config.get("rate_hz", 20))
	_watchdog.value = float(_config.get("watchdog_ms", 400))
	_label(_mapping, "Диапазоны обучения неизвестны: проверьте их по данным обучения. Для нескольких выходов argmax — предположение; выберите режим.")

func _number(parent: Node, caption: String, initial: float, integer: bool = false) -> SpinBox:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var label := Label.new()
	label.text = caption
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = 80
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var value := SpinBox.new()
	value.value_changed.connect(func(_v: float): _mapping_edited())
	value.update_on_text_changed = true
	value.allow_greater = true
	value.allow_lesser = true
	value.step = 1.0 if integer else 0.0
	value.value = initial
	value.custom_minimum_size.x = 120
	row.add_child(value)
	return value

func _scale_controls(parent: Node, entry: Dictionary, native: Dictionary = {}, sensor: bool = false) -> Dictionary:
	var scale: Dictionary = entry.get("scale", {"kind": "identity"}).duplicate(true)
	var kind := OptionButton.new()
	kind.add_item("Как есть (identity)")
	kind.add_item("Диапазон → диапазон (linear)")
	if scale.get("kind", "identity") not in ["identity", "linear"]:
		kind.add_item("Неизвестный тип: " + str(scale.kind))
		kind.select(2)
	else:
		kind.select(1 if scale.get("kind") == "linear" else 0)
	parent.add_child(kind)
	var fields := VBoxContainer.new()
	parent.add_child(fields)
	fields.visible = kind.selected == 1
	kind.item_selected.connect(func(index: int): fields.visible = index == 1)
	kind.item_selected.connect(func(_index: int): _mapping_edited())
	return {"original": scale, "kind": kind,
		"in_min": _number(fields, "Из: минимум", scale.get("in_min", native.get("native_min", 0) if sensor else 0)),
		"in_max": _number(fields, "Из: максимум", scale.get("in_max", native.get("native_max", 1) if sensor else 1)),
		"out_min": _number(fields, "В: минимум", scale.get("out_min", 0 if sensor else native.get("native_min", 0))),
		"out_max": _number(fields, "В: максимум", scale.get("out_max", 1 if sensor else native.get("native_max", 1)))}

func _read_scale(controls: Dictionary) -> Dictionary:
	var scale: Dictionary = controls.original.duplicate(true)
	if controls.kind.selected == 2: return scale
	scale["kind"] = "identity" if controls.kind.selected == 0 else "linear"
	if scale.kind == "linear":
		for key in ["in_min", "in_max", "out_min", "out_max"]: scale[key] = controls[key].value
	return scale

func _add_row(section: String, index: int, entry: Dictionary) -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	_mapping.add_child(box)
	var top := HBoxContainer.new()
	box.add_child(top)
	var ordinal := Label.new()
	ordinal.text = ("Вход " if section == "inputs" else "Мотор ") + str(index + 1)
	top.add_child(ordinal)
	var channel := OptionButton.new()
	channel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	channel.clip_text = true
	top.add_child(channel)
	var channels: Array = _platform.get("sensors" if section == "inputs" else "actuators", [])
	var selected := -1
	for item in channels:
		channel.add_item(_channel_label(item))
		channel.set_item_metadata(channel.item_count - 1, str(item.id))
		if str(item.id) == str(entry.get("channel", "")): selected = channel.item_count - 1
	if selected < 0:
		channel.add_item(str(entry.get("channel", "Неизвестный канал")))
		selected = channel.item_count - 1
		channel.set_item_metadata(selected, entry.get("channel", ""))
	channel.select(selected)
	var native_hint := _label(box, "")
	var update_hint := func(_idx: int):
		var channel_id: String = str(channel.get_item_metadata(channel.selected))
		for item in channels:
			if str(item.id) == channel_id:
				native_hint.text = "На устройстве: %s…%s %s" % [item.get("native_min", "?"), item.get("native_max", "?"), item.get("unit", "")]
	channel.item_selected.connect(update_hint)
	update_hint.call(selected)
	channel.item_selected.connect(func(_index: int): _mapping_edited())
	var remove := Button.new()
	remove.text = "−"
	remove.tooltip_text = "Удалить строку"
	top.add_child(remove)
	remove.pressed.connect(_remove_row.bind(section, index))
	var row := {"section": section, "channel": channel, "entry": entry.duplicate(true), "mode": null}
	var native: Dictionary = {}
	for item in channels:
		if str(item.id) == str(entry.get("channel", "")): native = item
	if section == "inputs":
		row["scale"] = _scale_controls(box, entry, native, true)
	else:
		var mode := OptionButton.new()
		for value in ["Выход модели", "Наиболее вероятный класс", "Порог"]: mode.add_item(value)
		var selected_mode := ["direct", "argmax", "threshold"].find(entry.get("mode", "direct"))
		if selected_mode < 0:
			mode.add_item(str(entry.mode))
			selected_mode = 3
		mode.select(selected_mode)
		box.add_child(mode)
		row["mode"] = mode
		var direct := VBoxContainer.new()
		box.add_child(direct)
		row["direct_index"] = _number(direct, "Индекс выхода модели (с 0)", entry.get("index", 0), true)
		row["scale"] = _scale_controls(direct, entry, native)
		var classes := VBoxContainer.new()
		box.add_child(classes)
		row["classes"] = {}
		var class_values: Dictionary = entry.get("classes", {}).duplicate(true)
		for i in range(int(_model.get("output_size", 1))):
			if not class_values.has(str(i)): class_values[str(i)] = 0
		for key in class_values:
			row.classes[key] = _number(classes, "Класс %s → команда мотора" % key, float(class_values[key]))
		var threshold := VBoxContainer.new()
		box.add_child(threshold)
		row["threshold_index"] = _number(threshold, "Индекс выхода модели (с 0)", entry.get("index", 0), true)
		row["threshold"] = _number(threshold, "Порог", entry.get("threshold", 0.5))
		row["on_value"] = _number(threshold, "Выше или равно → команда", entry.get("on_value", 100))
		row["off_value"] = _number(threshold, "Ниже → команда", entry.get("off_value", 0))
		var update := func(choice: int):
			direct.visible = choice == 0
			classes.visible = choice == 1
			threshold.visible = choice == 2
		mode.item_selected.connect(update)
		mode.item_selected.connect(func(_index: int): _mapping_edited())
		update.call(mode.selected)
	channel.item_selected.connect(func(_index: int):
		if row.scale.kind.selected != 0: return
		for item in channels:
			if str(item.id) == str(channel.get_item_metadata(channel.selected)):
				if section == "inputs":
					row.scale.in_min.value = float(item.get("native_min", 0))
					row.scale.in_max.value = float(item.get("native_max", 1))
				else:
					row.scale.out_min.value = float(item.get("native_min", 0))
					row.scale.out_max.value = float(item.get("native_max", 1)))
	_rows.append(row)

func _remove_row(section: String, index: int) -> void:
	if _busy: return
	var draft := collect_config()
	if not draft.ok:
		_status.text = draft.error
		return
	_config = draft.config
	_config[section].remove_at(index)
	_draw_mapping()

func _append_input() -> void:
	var draft := collect_config()
	if not draft.ok:
		_status.text = draft.error
		return
	_config = draft.config
	_config.inputs.append({"channel": "ultrasonic_4", "scale": {"kind": "identity"}})
	_draw_mapping()

func _append_output() -> void:
	var current := collect_config()
	if not current.get("ok", false):
		_status.text = current.error
		return
	_config = current.config
	_config.outputs.append({"channel": "motor_a_speed", "mode": "direct", "index": 0, "scale": {"kind": "identity"}})
	_draw_mapping()

func collect_config() -> Dictionary:
	var config: Dictionary = _config.duplicate(true)
	var transport: Dictionary = config.get("transport", {}).duplicate(true)
	transport["host"] = _host.text
	transport["port"] = int(_port.value)
	config["transport"] = transport
	config["rate_hz"] = int(_rate.value)
	config["watchdog_ms"] = int(_watchdog.value)
	config["platform"] = "ev3"
	config["inputs"] = []
	config["outputs"] = []
	for row in _rows:
		var options: Dictionary = row.entry.duplicate(true)
		options["channel"] = row.channel.get_item_metadata(row.channel.selected)
		if row.mode == null:
			options["scale"] = _read_scale(row.scale)
		else:
			options["mode"] = ["direct", "argmax", "threshold"][row.mode.selected] if row.mode.selected < 3 else str(row.entry.get("mode", ""))
			match options.mode:
				"direct":
					options["index"] = int(row.direct_index.value)
					options["scale"] = _read_scale(row.scale)
				"argmax":
					options["classes"] = {}
					for key in row.classes: options.classes[key] = row.classes[key].value
				"threshold":
					options["index"] = int(row.threshold_index.value)
					for key in ["threshold", "on_value", "off_value"]: options[key] = row[key].value
		config[row.section].append(options)
	return {"ok": true, "config": config}

func _validate(action: String) -> void:
	if _busy or _config.is_empty(): return
	var draft := collect_config()
	if not draft.ok:
		_status.text = draft.error
		_reveal_status()
		return
	if action == "export" and not _ranges_confirmed.button_pressed:
		_status.text = "Перед экспортом подтвердите проверку диапазонов по обучающим данным."
		_reveal_status()
		return
	var generation := _generation
	var selected_parent := _folder.text
	var selected_leaf := _bundle_name.text
	_set_busy(true)
	_status.text = "Проверка…"
	_reveal_status()
	var result: Dictionary = await runtime.robot_validate_config(draft.config, _input)
	if not _current(generation): return
	if result.get("status") != "ok":
		_failed(result)
		return
	if str(result.get("model", {}).get("model_sha256", "")) != str(_model.get("model_sha256", "")):
		_failed({"error": "Обученная модель изменилась. Откройте окно заново и проверьте соответствие входов и выходов."})
		return
	var report: Dictionary = result.get("validation", {})
	_status.text = _report(report)
	_reveal_status()
	if not report.get("ok", false):
		_set_busy(false)
		return
	if action == "save":
		if save_mapping(_scope, draft.config): _status.text = "Настройки сохранены.\n" + _report(report)
		else: _status.text = "Не удалось сохранить настройки. Правки остаются в форме; повторите сохранение."
	elif action == "export":
		var destination := bundle_destination(selected_parent, selected_leaf)
		if not destination.ok:
			_status.text = destination.error
			_reveal_status()
			_set_busy(false)
			return
		_exporting = true
		_status.text = "Создаём пакет… Дождитесь завершения."
		_reveal_status()
		var exported: Dictionary = await runtime.export_robot_bundle(_input, "ev3", destination.path, draft.config, "", {}, str(_model.get("model_sha256", "")))
		_exporting = false
		if not _current(generation): return
		if exported.get("status") == "ok":
			_status.text = "Пакет создан: " + destination.path + "\nПеренесите файлы вручную по README пакета. На EV3 не проверено.\n" + _report(report)
			_reveal_status()
		else:
			_status.text = "Экспорт не завершён: " + str(exported.get("error", "Неизвестная ошибка")) + "\nПроверьте доступ к папке и выберите новое имя пакета."
			_reveal_status()
	_set_busy(false)

static func bundle_destination(parent: String, leaf: String) -> Dictionary:
	if parent.is_empty() or not DirAccess.dir_exists_absolute(parent):
		return {"ok": false, "error": "Выберите существующую родительскую папку."}
	if leaf.strip_edges().is_empty() or leaf != leaf.get_file() or leaf in [".", ".."] or "/" in leaf or "\\" in leaf:
		return {"ok": false, "error": "Укажите имя новой подпапки без разделителей пути."}
	var path := parent.path_join(leaf)
	if DirAccess.dir_exists_absolute(path) or FileAccess.file_exists(path):
		return {"ok": false, "error": "Это имя уже занято. Введите другое имя; существующие файлы сохраняются."}
	return {"ok": true, "path": path}

func load_mapping(scope: String) -> Dictionary:
	var data = JSON.parse_string(FileAccess.get_file_as_string(storage_path)) if FileAccess.file_exists(storage_path) else {}
	if data is Dictionary and data.get(scope) is Dictionary: return data[scope].duplicate(true)
	return {}

func save_mapping(scope: String, config: Dictionary) -> bool:
	var data = JSON.parse_string(FileAccess.get_file_as_string(storage_path)) if FileAccess.file_exists(storage_path) else {}
	if not data is Dictionary: return false # Preserve an unreadable existing store.
	data[scope] = config.duplicate(true)
	var temp := storage_path + ".tmp"
	var file := FileAccess.open(temp, FileAccess.WRITE)
	if file == null: return false
	file.store_string(JSON.stringify(data, "", true, true))
	file.flush()
	var error := file.get_error()
	file.close()
	if error != OK: return false
	return DirAccess.rename_absolute(ProjectSettings.globalize_path(temp), ProjectSettings.globalize_path(storage_path)) == OK

func _report(report: Dictionary) -> String:
	var lines: PackedStringArray = []
	for kind in ["errors", "warnings"]:
		for issue in report.get(kind, []):
			lines.append(("Ошибка " if kind == "errors" else "Внимание ") + str(issue.get("field", "")) + ": " + str(issue.get("message", "")))
	if report.get("ok", false): lines.insert(0, "Проверка конфигурации пройдена. На устройстве не проверено.")
	return "\n".join(lines)

func _failed(result: Dictionary) -> void:
	_status.text = str(result.get("error", "Локальный runtime недоступен. Закройте и откройте окно, чтобы повторить."))
	_set_busy(false)
	_reveal_status()

func _set_busy(value: bool) -> void:
	_busy = value
	for button in _actions:
		if is_instance_valid(button): button.disabled = value or _config.is_empty()
	if is_instance_valid(_body):
		for control in _body.find_children("*", "Button", true, false): control.disabled = value
		for control in _body.find_children("*", "TextEdit", true, false): control.editable = not value
		for control in _body.find_children("*", "OptionButton", true, false): control.disabled = value
		for control in _body.find_children("*", "SpinBox", true, false): control.editable = not value
		_host.editable = not value
		_bundle_name.editable = not value
		_ranges_confirmed.disabled = value

func _current(generation: int) -> bool:
	return generation == _generation and visible and is_instance_valid(_input)

func _choose_folder() -> void:
	if not _busy: _picker.popup_centered_ratio(0.8)

func _cancel() -> void:
	if _exporting: return
	_generation += 1
	_closed_frame = Engine.get_process_frames()
	hide()

func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_cancel()
		set_input_as_handled()

func _mapping_edited() -> void:
	if is_instance_valid(_ranges_confirmed): _ranges_confirmed.button_pressed = false

func _channel_label(item: Dictionary) -> String:
	var labels := {"ultrasonic_4": "Расстояние · порт 4", "touch_1": "Касание · порт 1", "touch_2": "Касание · порт 2", "color_id_3": "Цвет · порт 3", "color_reflect_3": "Отражённый свет · порт 3", "color_ambient_3": "Внешний свет · порт 3", "infrared_4": "ИК-расстояние · порт 4", "motor_a_position": "Положение мотора A", "motor_b_position": "Положение мотора B", "gyro_angle_2": "Угол гироскопа · порт 2", "gyro_rate_2": "Скорость поворота · порт 2", "motor_a_speed": "Мотор A", "motor_b_speed": "Мотор B", "motor_c_speed": "Мотор C", "motor_d_speed": "Мотор D"}
	return str(labels.get(str(item.id), item.get("label", item.id)))

func blocks_parent_input() -> bool:
	return visible or Engine.get_process_frames() <= _closed_frame + 1

func _reveal_status() -> void:
	_scroll.ensure_control_visible.call_deferred(_status)
