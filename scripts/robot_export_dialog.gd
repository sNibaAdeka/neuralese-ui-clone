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

var _step := 0
var _pages: Array[VBoxContainer] = []
var _step_labels: Array[Label] = []
var _primary: Button
var _back: Button
var _review: Label
var _overview: Label
var _heading: Label
var _intro: Label
var _validated := false
var _finished := false
var _drawing := false
var _card_grids: Array[GridContainer] = []
var _export_form: VBoxContainer
var _success_box: VBoxContainer
var _success: Label

# An original diagram: a plan of configured ports, never a live hardware status.
class PortDiagram extends Control:
	var inputs: Array = []
	var outputs: Array = []
	func _draw() -> void:
		var font := get_theme_default_font()
		var center := size.x / 2.0
		var body := Rect2(center - 49, 12, 98, 136)
		var style := StyleBoxFlat.new()
		style.bg_color = Color("edf0f3")
		style.border_color = Color("cbd1d8")
		style.set_border_width_all(2)
		style.set_corner_radius_all(12)
		draw_style_box(style, body)
		draw_rect(Rect2(center - 31, 33, 62, 34), Color("cbd7cf"))
		draw_string(font, Vector2(center - 15, 56), "EV3", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("34453b"))
		draw_circle(Vector2(center, 108), 17, Color("c4cbd2"))
		draw_circle(Vector2(center, 108), 9, Color("fafbfc"))
		for i in range(4):
			var y := 22.0 + i * 36.0
			for left in [true, false]:
				var port_name: String = str(i + 1) if left else ["A", "B", "C", "D"][i]
				var used := false
				for item in (inputs if left else inputs + outputs):
					var channel := str(item.get("channel", ""))
					if (left and channel.ends_with("_" + port_name)) or (not left and channel.begins_with("motor_" + port_name.to_lower() + "_")): used = true
				var x := center - 91 if left else center + 69
				var feedback := false
				var command := false
				if not left:
					for item in inputs:
						if str(item.get("channel", "")).begins_with("motor_" + port_name.to_lower() + "_"): feedback = true
					for item in outputs:
						if str(item.get("channel", "")).begins_with("motor_" + port_name.to_lower() + "_"): command = true
				var color := Color("f5d546") if left or (feedback and not command) else Color("f5a461")
				draw_line(Vector2(center - 49 if left else center + 49, y + 11), Vector2(x + 11, y + 11), Color("cbd1d8"), 2)
				draw_circle(Vector2(x + 11, y + 11), 13, color if used else Color("e4e8ed"))
				if feedback and command: draw_circle(Vector2(x + 23, y + 1), 5, Color("f5d546"))
				draw_string(font, Vector2(x + 6, y + 16), port_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("343a43"))
		draw_string(font, Vector2(center - 139, 170), "Датчики", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("69717b"))
		draw_string(font, Vector2(center + 68, 170), "Моторы", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("69717b"))
var _diagram: PortDiagram

func _ready() -> void:
	set_meta("claude_design_owned", true)
	title = "EV3 · Подготовка модели"
	min_size = Vector2i(360, 420)
	size = Vector2i(700, 450)
	transient = true
	exclusive = true
	wrap_controls = false
	theme = Design.create_theme()
	# Compact controls belong to this dialog; the workspace theme stays intact.
	for type in ["Button", "OptionButton", "LineEdit", "SpinBox"]:
		for state in ["normal", "hover", "pressed", "disabled"]:
			if theme.has_stylebox(state, type):
				var style := theme.get_stylebox(state, type).duplicate() as StyleBox
				style.content_margin_top = 8
				style.content_margin_bottom = 8
				style.content_margin_left = 10
				style.content_margin_right = 10
				theme.set_stylebox(state, type, style)
	close_requested.connect(_cancel)
	size_changed.connect(_resize_cards)
	var background := ColorRect.new()
	background.name = "Background"
	background.color = Color("fafbfc")
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge in ["left", "right", "top", "bottom"]: margin.add_theme_constant_override("margin_" + edge, 16)
	add_child(margin)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 10)
	margin.add_child(outer)
	var header := HBoxContainer.new()
	outer.add_child(header)
	_heading = _label(header, "Подготовим EV3")
	_heading.add_theme_font_size_override("font_size", 22)
	_heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var close := Button.new()
	close.text = "Закрыть"
	close.flat = true
	close.pressed.connect(_cancel)
	header.add_child(close)
	var steps := HBoxContainer.new()
	steps.add_theme_constant_override("separation", 4)
	outer.add_child(steps)
	for caption in ["1  Робот", "2  Сигналы", "3  Проверка", "4  Пакет"]:
		var label := _label(steps, caption)
		label.add_theme_font_size_override("font_size", 12)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_step_labels.append(label)
	_meta = _label(outer, "Читаем обученную модель…")
	_meta.add_theme_font_size_override("font_size", 12)
	_meta.add_theme_color_override("font_color", Design.INK_SECONDARY)
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(_scroll)
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 10)
	_scroll.add_child(_body)
	for i in range(4):
		var page := VBoxContainer.new()
		page.add_theme_constant_override("separation", 10)
		page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_body.add_child(page)
		_pages.append(page)
	_intro = _label(_pages[0], "")
	_intro.visible = false
	_diagram = PortDiagram.new()
	_diagram.custom_minimum_size.y = 178
	_diagram.resized.connect(_diagram.queue_redraw)
	_pages[0].add_child(_diagram)
	_overview = _label(_pages[0], "")
	_label(_pages[0], "Схема настроек. Перенос на EV3 — вручную.").add_theme_color_override("font_color", Design.INK_SECONDARY)
	_mapping = VBoxContainer.new()
	_mapping.add_theme_constant_override("separation", 10)
	_pages[1].add_child(_mapping)
	_review = _label(_pages[2], "")
	_ranges_confirmed = CheckBox.new()
	_ranges_confirmed.text = "Диапазоны и команды проверены"
	_ranges_confirmed.add_theme_font_size_override("font_size", 13)
	_ranges_confirmed.tooltip_text = "Сверьте диапазоны датчиков и команды моторов с обучающими данными"
	_pages[2].add_child(_ranges_confirmed)
	_label(_pages[2], "Сверьте диапазоны с обучающими данными, а команды — с поведением робота.").add_theme_color_override("font_color", Design.INK_SECONDARY)
	var advanced := Button.new()
	advanced.text = "Параметры ручного запуска ▸"
	advanced.flat = true
	advanced.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_pages[2].add_child(advanced)
	_settings = VBoxContainer.new()
	_pages[2].add_child(_settings)
	_settings.visible = false
	advanced.pressed.connect(func():
		_settings.visible = not _settings.visible
		advanced.text = "Параметры ручного запуска ▾" if _settings.visible else "Параметры ручного запуска ▸")
	_label(_settings, "Адрес для будущего запуска. Экспорт не подключается к роботу.")
	_host = LineEdit.new()
	_host.placeholder_text = "ev3dev.local"
	_host.text_changed.connect(func(_text: String): _mapping_edited())
	_settings.add_child(_host)
	_port = _number(_settings, "Порт", 9999, true)
	_rate = _number(_settings, "Частота, Гц", 20, true)
	_watchdog = _number(_settings, "Тайм-аут, мс", 400, true)
	var save := _button(_pages[2], "Сохранить настройки", _validate.bind("save"))
	save.flat = true
	save.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_success_box = VBoxContainer.new()
	_pages[3].add_child(_success_box)
	_success_box.visible = false
	_success = _label(_success_box, "")
	var another := _button(_success_box, "Создать ещё", func():
		_destination_edited()
		_status.text = ""
		_status.visible = false)
	another.flat = true
	_export_form = VBoxContainer.new()
	_export_form.add_theme_constant_override("separation", 10)
	_pages[3].add_child(_export_form)
	_label(_export_form, "Выберите, куда положить файлы для EV3.")
	_folder = LineEdit.new()
	_folder.placeholder_text = "Папка назначения"
	_folder.editable = false
	_export_form.add_child(_folder)
	_button(_export_form, "Выбрать папку…", _choose_folder)
	_label(_export_form, "Имя новой папки пакета")
	_bundle_name = LineEdit.new()
	_bundle_name.text = "ev3_bundle"
	_bundle_name.text_changed.connect(func(_text: String): _destination_edited())
	_export_form.add_child(_bundle_name)
	_label(_export_form, "Внутри будут модель, настройки и инструкция по переносу.").add_theme_color_override("font_color", Design.INK_SECONDARY)
	_status = _label(_body, "")
	_status.add_theme_font_size_override("font_size", 13)
	_status.visible = false
	var footer := HBoxContainer.new()
	outer.add_child(footer)
	_back = _button(footer, "Назад", func(): _go_step(_step - 1))
	_back.flat = true
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(spacer)
	_primary = _button(footer, "Настроить сигналы", _next_step)
	_primary.theme_type_variation = "ClaudePrimaryButton"
	_primary.custom_minimum_size.y = 40
	_picker = FileDialog.new()
	_picker.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	_picker.access = FileDialog.ACCESS_FILESYSTEM
	_picker.use_native_dialog = true
	_picker.dir_selected.connect(func(path: String):
		_folder.text = path
		_destination_edited())
	add_child(_picker)
	_go_step(0)

func _go_step(index: int) -> void:
	_step = clampi(index, 0, 3)
	if _step == 3 and not _validated: _step = 2
	for i in range(_pages.size()):
		_pages[i].visible = i == _step
		_step_labels[i].add_theme_color_override("font_color", Design.INK if i == _step else Color("8c929c"))
	_heading.text = ["Подготовим EV3", "Датчики и моторы", "Всё настроено верно?", "Соберём пакет"][ _step ]
	# The long signals title wraps naturally on a narrow native window.
	_heading.add_theme_font_size_override("font_size", 20)
	_primary.text = ["Настроить сигналы", "Проверить настройки", "Проверить и продолжить", "Создать пакет"][_step]
	if _finished and _step == 3:
		_primary.text = "Готово"
		_heading.text = "Пакет готов"
	_export_form.visible = not _finished
	_success_box.visible = _finished
	_back.visible = _step > 0
	_status.visible = _step >= 2 and not _status.text.is_empty()
	_scroll.scroll_vertical = 0
	_reset_scroll.call_deferred()
	if _step == 0 and is_instance_valid(_diagram):
		var draft := collect_config() if not _rows.is_empty() else {"config": _config}
		_diagram.inputs = draft.config.get("inputs", [])
		_diagram.outputs = draft.config.get("outputs", [])
		_overview.text = "Входов модели: %d · Моторов: %d" % [int(_model.get("input_size", 0)), _diagram.outputs.size()]
		_diagram.queue_redraw()
	if _step == 2: _refresh_review()
	if is_instance_valid(_primary) and visible: _primary.grab_focus.call_deferred()

func _reset_scroll() -> void:
	_scroll.scroll_vertical = 0

func _next_step() -> void:
	if _busy: return
	if _step < 2: _go_step(_step + 1)
	elif _step == 2: await _validate("continue")
	elif _finished: _cancel()
	else: await _validate("export")

func _refresh_review() -> void:
	var lines: PackedStringArray = []
	for row in _rows:
		var name: String = row.channel.get_item_text(row.channel.selected)
		if row.section == "inputs":
			lines.append("Вход %d  ←  %s" % [lines.size() + 1, name])
		else:
			lines.append("%s  ←  %s" % [name, row.mode.get_item_text(row.mode.selected)])
	_review.text = "\n".join(lines)

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
	_finished = false
	_validated = false
	_go_step(0)
	_status.visible = false
	_ranges_confirmed.button_pressed = false
	_clear_rows()
	_host.text = ""
	_meta.text = "Проверяем локальную обученную модель…"
	var available := get_tree().root.get_visible_rect().size
	popup_centered(Vector2i(mini(700, int(available.x)), mini(450, int(available.y))))
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
	_meta.text = "EV3 · Входы: %d · Выходы: %d" % [int(_model.get("input_size", 0)), int(_model.get("output_size", 0))]
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
		_status.text = _report(defaults.get("validation", {}))
	_draw_mapping(true)
	_set_busy(false)
	_overview.text = "Входов модели: %d · Моторов: %d" % [int(_model.get("input_size", 0)), _config.get("outputs", []).size()]
	_go_step(0)
	_primary.grab_focus()

func _clear_rows() -> void:
	_actions = _actions.filter(func(button): return is_instance_valid(button) and not _mapping.is_ancestor_of(button))
	_rows.clear()
	for child in _mapping.get_children():
		_mapping.remove_child(child)
		child.queue_free()

func _draw_mapping(preserve_notice: bool = false) -> void:
	var notice := _status.text
	var notice_details := _status.tooltip_text
	_mapping_edited()
	if preserve_notice:
		_status.text = notice
		_status.tooltip_text = notice_details
	_drawing = true
	_clear_rows()
	_card_grids.clear()
	for section in ["inputs", "outputs"]:
		_label(_mapping, "Датчики · входы модели" if section == "inputs" else "Моторы · действия робота")
		var grid := GridContainer.new()
		grid.columns = 2 if size.x >= 560 else 1
		grid.add_theme_constant_override("h_separation", 8)
		grid.add_theme_constant_override("v_separation", 8)
		_mapping.add_child(grid)
		_card_grids.append(grid)
		for index in range(_config.get(section, []).size()):
			_add_row(section, index, _config[section][index], grid)
		if section == "outputs":
			_button(_mapping, "+ Мотор", _append_output)
		else:
			_button(_mapping, "+ Датчик", _append_input)
	_host.text = str(_config.get("transport", {}).get("host", "ev3dev.local"))
	_port.value = float(_config.get("transport", {}).get("port", 9999))
	_rate.value = float(_config.get("rate_hz", 20))
	_watchdog.value = float(_config.get("watchdog_ms", 400))
	_drawing = false


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
	value.custom_minimum_size.x = 100
	row.add_child(value)
	return value

func _scale_controls(parent: Node, entry: Dictionary, native: Dictionary = {}, sensor: bool = false) -> Dictionary:
	var scale: Dictionary = entry.get("scale", {"kind": "identity"}).duplicate(true)
	var kind := OptionButton.new()
	kind.fit_to_longest_item = false
	kind.clip_text = true
	kind.add_item("Без преобразования")
	kind.add_item("Изменить диапазон")
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

func _resize_cards() -> void:
	for grid in _card_grids:
		if is_instance_valid(grid): grid.columns = 2 if size.x >= 560 else 1

func _add_row(section: String, index: int, entry: Dictionary, parent: Node = null) -> void:
	var card := PanelContainer.new()
	var tint := Color("fff8d6") if section == "inputs" else Color("fff0e4")
	card.add_theme_stylebox_override("panel", Design.box(tint, tint, 10, Vector2(12, 10), 0))
	(parent if parent != null else _mapping).add_child(card)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	card.add_child(box)
	var top := HBoxContainer.new()
	box.add_child(top)
	var ordinal := Label.new()
	ordinal.text = ("Вход " if section == "inputs" else "Действие ") + str(index + 1)
	ordinal.add_theme_font_size_override("font_size", 12)
	top.add_child(ordinal)
	var channel := OptionButton.new()
	channel.fit_to_longest_item = false
	channel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	channel.clip_text = true
	channel.custom_minimum_size.y = 34
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
	var disclosure := Button.new()
	disclosure.text = "Диапазон и настройки ▸"
	disclosure.flat = true
	disclosure.alignment = HORIZONTAL_ALIGNMENT_LEFT
	disclosure.add_theme_font_size_override("font_size", 12)
	box.add_child(disclosure)
	var details := VBoxContainer.new()
	details.visible = false
	box.add_child(details)
	disclosure.pressed.connect(func():
		details.visible = not details.visible
		disclosure.text = "Диапазон и настройки ▾" if details.visible else "Диапазон и настройки ▸")
	var native_hint := _label(details, "")
	var update_hint := func(_idx: int):
		var channel_id: String = str(channel.get_item_metadata(channel.selected))
		channel.tooltip_text = channel.get_item_text(channel.selected)
		channel.text = _compact_channel_label(channel_id, channel.tooltip_text)
		for item in channels:
			if str(item.id) == channel_id:
				native_hint.text = ("Диапазон датчика: %s…%s %s" if section == "inputs" else "Диапазон команды: %s…%s %s") % [item.get("native_min", "?"), item.get("native_max", "?"), item.get("unit", "")]
	channel.item_selected.connect(update_hint)
	update_hint.call(selected)
	channel.item_selected.connect(func(_index: int): _mapping_edited())
	var remove := Button.new()
	remove.text = "×"
	remove.flat = true
	remove.add_theme_font_size_override("font_size", 12)
	remove.tooltip_text = "Удалить строку"
	top.add_child(remove)
	remove.pressed.connect(_remove_row.bind(section, index))
	var row := {"section": section, "channel": channel, "entry": entry.duplicate(true), "mode": null, "details": details, "disclosure": disclosure}
	var native: Dictionary = {}
	for item in channels:
		if str(item.id) == str(entry.get("channel", "")): native = item
	if section == "inputs":
		row["scale"] = _scale_controls(details, entry, native, true)
	else:
		var mode := OptionButton.new()
		mode.fit_to_longest_item = false
		mode.clip_text = true
		for value in ["Выход модели", "Наиболее вероятный класс", "Порог"]: mode.add_item(value)
		var selected_mode := ["direct", "argmax", "threshold"].find(entry.get("mode", "direct"))
		if selected_mode < 0:
			mode.add_item(str(entry.mode))
			selected_mode = 3
		mode.select(selected_mode)
		# Mode is a semantic choice and stays visible; details hold numeric tuning.
		box.add_child(mode)
		box.move_child(mode, 1)
		row["mode"] = mode
		var direct := VBoxContainer.new()
		details.add_child(direct)
		row["direct_index"] = _number(direct, "Индекс выхода модели (с 0)", entry.get("index", 0), true)
		row["scale"] = _scale_controls(direct, entry, native)
		var classes := VBoxContainer.new()
		details.add_child(classes)
		row["classes"] = {}
		var class_values: Dictionary = entry.get("classes", {}).duplicate(true)
		for i in range(int(_model.get("output_size", 1))):
			if not class_values.has(str(i)): class_values[str(i)] = 0
		for key in class_values:
			row.classes[key] = _number(classes, "Класс %s → команда мотора" % key, float(class_values[key]))
		var threshold := VBoxContainer.new()
		details.add_child(threshold)
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
	if action in ["export", "continue"] and not _ranges_confirmed.button_pressed:
		_status.text = "Перед экспортом подтвердите проверку диапазонов по обучающим данным."
		_reveal_status()
		return
	var generation := _generation
	var selected_parent := _folder.text
	var selected_leaf := _bundle_name.text
	_validated = false
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
	if action != "continue" or not report.get("ok", false): _reveal_status()
	if not report.get("ok", false):
		_go_step(2)
		_reveal_status()
		_set_busy(false)
		return
	_validated = true
	if action == "continue":
		_go_step(3)
	elif action == "save":
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
			_finished = true
			_primary.text = "Готово"
			_heading.text = "Пакет готов"
			_export_form.visible = false
			_success_box.visible = true
			_success.text = "Перенесите файлы на EV3 по инструкции HOW_TO_USE.txt.\n\n" + destination.path
			_status.text = "Пакет создан. На EV3 не проверено."
			_status.visible = true
			_reset_scroll.call_deferred()
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
	var details: PackedStringArray = []
	for kind in ["errors", "warnings"]:
		for issue in report.get(kind, []):
			var field := str(issue.get("field", ""))
			var message := str(issue.get("message", ""))
			details.append(field + ": " + message)
			if kind == "warnings" and (issue.get("code") == "unscaled_input" or message.begins_with("No training range is known")):
				var ordinal := int(field.get_slice("[", 1).get_slice("]", 0)) + 1
				lines.append("Вход %d: сверьте диапазон с данными обучения." % ordinal)
			else:
				lines.append(("Ошибка " if kind == "errors" else "Внимание ") + field + ": " + message)
	if report.get("ok", false): lines.insert(0, "Настройки проверены. На EV3 ещё не проверено.")
	_status.tooltip_text = "\n".join(details)
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

func _destination_edited() -> void:
	_finished = false
	if is_instance_valid(_export_form): _export_form.visible = true
	if is_instance_valid(_success_box): _success_box.visible = false
	if is_instance_valid(_primary) and _step == 3:
		_primary.text = "Создать пакет"
		_heading.text = "Соберём пакет"

func _mapping_edited() -> void:
	if _drawing: return
	if is_instance_valid(_status):
		_status.text = ""
		_status.tooltip_text = ""
		_status.visible = false
	_validated = false
	_finished = false
	if is_instance_valid(_primary) and _step == 3: _primary.text = "Создать пакет"
	if is_instance_valid(_ranges_confirmed): _ranges_confirmed.button_pressed = false

func _channel_label(item: Dictionary) -> String:
	var labels := {"ultrasonic_4": "Расстояние · порт 4", "touch_1": "Касание · порт 1", "touch_2": "Касание · порт 2", "color_id_3": "Цвет · порт 3", "color_reflect_3": "Отражённый свет · порт 3", "color_ambient_3": "Внешний свет · порт 3", "infrared_4": "ИК-расстояние · порт 4", "motor_a_position": "Положение мотора A", "motor_b_position": "Положение мотора B", "gyro_angle_2": "Угол гироскопа · порт 2", "gyro_rate_2": "Скорость поворота · порт 2", "motor_a_speed": "Мотор A", "motor_b_speed": "Мотор B", "motor_c_speed": "Мотор C", "motor_d_speed": "Мотор D"}
	return str(labels.get(str(item.id), item.get("label", item.id)))

func _compact_channel_label(channel_id: String, fallback: String) -> String:
	var labels := {"ultrasonic_4": "Расстояние · 4", "touch_1": "Касание · 1", "touch_2": "Касание · 2", "color_id_3": "Цвет · 3", "color_reflect_3": "Отражение · 3", "color_ambient_3": "Внешний свет · 3", "infrared_4": "ИК-расстояние · 4", "motor_a_position": "Положение · A", "motor_b_position": "Положение · B", "gyro_angle_2": "Угол · 2", "gyro_rate_2": "Поворот · 2"}
	return str(labels.get(channel_id, fallback))

func blocks_parent_input() -> bool:
	return visible or Engine.get_process_frames() <= _closed_frame + 1

func _reveal_status() -> void:
	_status.visible = true
	_scroll.ensure_control_visible.call_deferred(_status)
