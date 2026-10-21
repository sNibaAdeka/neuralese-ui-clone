extends PanelContainer
## Claude v23 navigation, backed by the existing TopBar and project state.
const Design = preload("res://scripts/claude_design_theme.gd")
var host: Control
var title: LineEdit
var status: Label
var tabs_panel: PanelContainer
var axon_panel: Control
var tabs: HBoxContainer
var actions: HBoxContainer
var navigation: Dictionary = {}
var buttons: Dictionary = {}
var rows: VBoxContainer
var top: HBoxContainer
var second: HBoxContainer
var status_row: HBoxContainer
var project_slot: HBoxContainer
var projects: MenuButton
var project_details: HBoxContainer
var project_done: Button
var _compact := false
var busy := false
var save_message := ""
var overflow: MenuButton
var _last_width := -1.0
var _last_window := ""
var _last_project_name := ""
var _layout_pending := false
var _geometry_pending := false

func _enter_tree() -> void:
	# This shell already owns its theme and spacing; the legacy-scene adapter
	# must not replace its panel while its children are being laid out.
	set_meta("claude_styled", true)
	set_meta("claude_design_owned", true)

func configure(top_bar: Control) -> void:
	host = top_bar

func _ready() -> void:
	theme = Design.create_theme()
	add_theme_stylebox_override("panel", Design.box(Design.CANVAS, Design.LINE, 0, Vector2(16, 4), 1))
	rows = VBoxContainer.new()
	rows.add_theme_constant_override("separation", 6)
	add_child(rows)
	top = HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	rows.add_child(top)
	projects = MenuButton.new()
	projects.flat = true
	projects.focus_mode = Control.FOCUS_ALL
	projects.custom_minimum_size = Vector2(88, Design.CONTROL_MIN_HEIGHT)
	projects.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	projects.add_theme_font_override("font", _weighted_font(600))
	projects.clip_text = true
	projects.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	projects.get_popup().add_item("Открыть проекты и готовые модели", 0)
	projects.get_popup().add_item("Переименовать проект", 1)
	projects.get_popup().add_separator("", 100)
	projects.get_popup().add_item("Сохранить проект", 2)
	projects.get_popup().add_item("Экспорт модели", 3)
	projects.icon = _project_icon()
	for state in ["normal", "hover", "pressed", "focus"]:
		projects.add_theme_color_override("icon_" + state + "_color", Design.INK_SECONDARY)
	projects.alignment = HORIZONTAL_ALIGNMENT_LEFT
	for state in ["normal", "hover", "pressed"]:
		projects.add_theme_stylebox_override(state, Design.box(Design.CANVAS, Color.TRANSPARENT, Design.CONTROL_RADIUS, Vector2(8, 4), 0))
	projects.get_popup().id_pressed.connect(_project_action)
	project_slot = HBoxContainer.new()
	project_slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(project_slot)
	project_slot.add_child(projects)
	project_details = HBoxContainer.new()
	project_details.visible = false
	rows.add_child(project_details)
	title = LineEdit.new()
	title.placeholder_text = "Безымянная модель"
	title.custom_minimum_size = Vector2(120, 44)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Keep the existing project-name contract, including its character limit.
	title.max_length = host.get_node("Label").max_length
	title.tooltip_text = "Название текущего проекта"
	title.text_submitted.connect(func(value: String):
		_rename(value)
		_set_project_details(false)
	)
	title.focus_exited.connect(func(): _rename(title.text))
	project_details.add_child(title)
	project_done = _button("Готово", "Применить название проекта", func():
		_rename(title.text)
		_set_project_details(false)
	)
	project_details.add_child(project_done)
	tabs_panel = PanelContainer.new()
	tabs_panel.add_theme_stylebox_override("panel", Design.box(Color.TRANSPARENT, Color.TRANSPARENT, 0, Vector2.ZERO, 0))
	tabs = HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 2)
	tabs_panel.add_child(tabs)
	var tab_icons := {"env": "M12 3l9 5v9l-9 5-9-5V8zM3 8l9 5 9-5M12 13v9", "graph": "M7 7l10 5-10 5M7 7a2 2 0 1 0 0.01 0M17 12a2 2 0 1 0 .01 0M7 17a2 2 0 1 0 .01 0", "ds": "M3 5h18v15H3zM3 10h18M9 10v10"}
	for item in [["env", "Симуляции"], ["graph", "Графы"], ["ds", "Датасеты"]]:
		var key: String = item[0]
		var button := _button(item[1], "Открыть: " + item[1], _navigate.bind(key))
		button.toggle_mode = true
		button.icon = Design._icon(tab_icons[key], Design.INK_SECONDARY)
		button.set_meta("reference_icon", button.icon)
		button.set_meta("reference_active_icon", Design._icon(tab_icons[key], Design.PRIMARY))
		button.theme_type_variation = &"ClaudeTabButton"
		button.add_theme_font_override("font", _weighted_font(500))
		for state in ["normal", "hover", "pressed", "disabled"]:
			var fill := Design.FILL if state == "hover" else Color.TRANSPARENT
			var tab_style := Design.box(fill, Color.TRANSPARENT, 0, Vector2(12, 4), 0)
			if state == "pressed":
				tab_style.border_color = Design.PRIMARY
				tab_style.border_width_bottom = 2
			button.add_theme_stylebox_override(state, tab_style)
		button.add_theme_color_override("font_pressed_color", Design.INK)
		tabs.add_child(button)
		navigation[key] = button
	top.add_child(tabs_panel)
	actions = HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_END
	actions.add_theme_constant_override("separation", 8)
	top.add_child(actions)
	buttons.undo = _button("Отменить", "Отменить последнее изменение", _history_action.bind(false))
	buttons.redo = _button("Повторить", "Повторить изменение", _history_action.bind(true))
	buttons.fit = _button("Вся модель", "Показать модель целиком, сохранив расположение узлов", _fit_model)
	buttons.save = _button("Сохранить", "Сохранить текущий проект локально", _save)
	buttons.axon = _button("Аксон", "Помощь по выбранному узлу и чат", _toggle_axon)
	buttons.export = _button("Экспорт", "Экспорт модели для устройства", host._on_export_released)
	buttons.profile = _button("", "Профиль: вход и настройки", host._on_login_released)
	buttons.fit.icon = Design._icon("M3 9V3h6M15 3h6v6M21 15v6h-6M9 21H3v-6", Design.INK_SECONDARY)
	buttons.save.icon = Design._icon("M5 3h12l4 4v14H3V3zM7 3v6h10V3M7 21v-8h10v8", Design.INK_SECONDARY)
	buttons.axon.icon = Design._icon("M5 17l-2 4 6-2h7a8 8 0 1 0-11-2", Design.PRIMARY)
	for button in buttons.values():
		actions.add_child(button)
	overflow = MenuButton.new()
	overflow.text = "Действия"
	overflow.focus_mode = Control.FOCUS_ALL
	overflow.accessibility_name = "Действия проекта"
	overflow.icon = Design._icon("M4 12h1M11 12h1M18 12h1", Design.INK_SECONDARY)
	overflow.tooltip_text = "Команды проекта"
	overflow.custom_minimum_size = Vector2(44, 44)
	for state in ["normal", "hover", "pressed", "disabled"]:
		overflow.add_theme_stylebox_override(state, Design.box(Design.CANVAS if state == "normal" else Design.FILL, Color.TRANSPARENT, Design.CONTROL_RADIUS, Vector2(10, 4), 0))
	var menu := overflow.get_popup()
	menu.add_item("Отменить", 0)
	menu.add_item("Повторить", 1)
	menu.add_separator("", 100)
	menu.add_item("Экспорт модели", 2)
	menu.add_item("Профиль и настройки", 3)
	menu.add_separator("", 101)
	menu.add_item("Показать модель целиком", 4)
	menu.add_item("Открыть Аксон", 5)
	menu.add_item("Сохранить проект", 6)
	menu.add_separator("", 102)
	menu.add_item("Упорядочить схему", 7)
	menu.id_pressed.connect(func(id: int):
		match id:
			0: _history_action(false)
			1: _history_action(true)
			2: host._on_export_released()
			3: host._on_login_released()
			4: _fit_model()
			5: _toggle_axon()
			6: _save()
			7: _arrange_model()
	)
	actions.add_child(overflow)
	second = HBoxContainer.new()
	rows.add_child(second)
	status_row = HBoxContainer.new()
	rows.add_child(status_row)
	status = Label.new()
	status.theme_type_variation = &"ClaudeMutedLabel"
	status.text = "Локальный проект"
	status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	status_row.add_child(status)
	rows.minimum_size_changed.connect(_request_layout)
	glob.autosave_status_changed.connect(_on_autosave_status_changed)
	_install_axon.call_deferred()
	_sync()

func _project_action(id: int) -> void:
	if id == 0:
		host._on_workslist()
	elif id == 1 and glob.loaded_project_once:
		_set_project_details(true)
		title.grab_focus.call_deferred()
		title.select_all.call_deferred()
	elif id == 2:
		_save()
	elif id == 3 and glob.loaded_project_once:
		host._on_export_released()

func _set_project_details(expanded: bool) -> void:
	project_details.visible = expanded
	if not expanded:
		title.release_focus()
	_request_layout()

func _button(caption: String, hint: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = caption
	button.accessibility_name = caption
	button.focus_mode = Control.FOCUS_ALL
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	button.tooltip_text = hint
	button.custom_minimum_size.y = Design.CONTROL_MIN_HEIGHT
	for state in ["normal", "hover", "pressed", "disabled"]:
		button.add_theme_stylebox_override(state, Design.box(Design.CANVAS if state == "normal" else Design.FILL, Color.TRANSPARENT, Design.CONTROL_RADIUS, Vector2(10, 4), 0))
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.pressed.connect(action)
	return button

func _navigate(key: String) -> void:
	ui.hide_splash()
	match key:
		"graph": host._on_minigames_released()
		"ds": host._on_datasets_released()
		"env": host._on_graphs_released()
	_sync()

func _fit_model() -> void:
	if glob.curr_window != "graph" or graphs._graphs.is_empty() or not is_instance_valid(glob.main_cam):
		return
	glob.main_cam.emp_node(graphs._graphs.values())

func _rename(value: String) -> void:
	var name_field := host.get_node("Label") as LineEdit
	var next := value.strip_edges()
	if name_field.max_length > 0:
		next = next.substr(0, name_field.max_length)
	if next.is_empty():
		title.text = host.get_scene_name()
		return
	if next != host.get_scene_name():
		name_field.text = next
		# LineEdit assignment does not emit text_changed. Emit once to preserve
		# the original ValidInput validation/resizing, then read the accepted name.
		name_field.text_changed.emit(name_field.text)
		_last_project_name = host.get_scene_name()
		title.text = _last_project_name
		save_message = ""
		glob.request_autosave("project_name")
	else:
		title.text = host.get_scene_name()
		_last_project_name = title.text

func _save() -> void:
	if busy:
		return
	if title.has_focus():
		_rename(title.text)
	busy = true
	buttons.save.disabled = true
	buttons.save.text = "" if get_viewport_rect().size.x < 550.0 else "Сохранение…"
	var result = await host._on__released()
	if result is Dictionary and str(result.get("status", "")) == "ok":
		save_message = "Сохранено на этом компьютере"
	else:
		save_message = "Не удалось сохранить. Повторите попытку."
		ui.error(save_message)
	buttons.save.text = "" if get_viewport_rect().size.x < 550.0 else "Сохранить"
	busy = false
	_sync()

func _process(_delta: float) -> void:
	_sync()
	if is_instance_valid(axon_panel):
		axon_panel.layout_for_workspace(glob.space_begin.y, 14.0)
		var palette := glob.base_node.get_node_or_null("WIN_GRAPH/NodePalette") if is_instance_valid(glob.base_node) else null
		if is_instance_valid(palette) and axon_panel.has_method("is_overlay_open"):
			palette.visible = glob.curr_window == "graph" and not axon_panel.is_overlay_open()

func _on_autosave_status_changed(state: StringName, _revision: int, _reason: String) -> void:
	match state:
		&"queued", &"deferred": save_message = "Есть несохранённые изменения"
		&"saving": save_message = "Автосохранение…"
		&"saved": save_message = "Сохранено на этом компьютере"
		&"failed": save_message = "Не удалось сохранить. Повторите попытку."
	_sync()

func _sync() -> void:
	if not is_instance_valid(host) or not is_instance_valid(title):
		return
	var project_name: String = host.get_scene_name()
	if project_name != _last_project_name:
		save_message = ""
		_last_project_name = project_name
	if not title.has_focus() and title.text != project_name:
		title.text = project_name
	var dirty_mark := " •" if save_message in ["Есть несохранённые изменения", "Автосохранение…"] else ""
	projects.text = (project_name if not project_name.is_empty() else "Проект") + dirty_mark + "  ⌄"
	projects.tooltip_text = projects.text + " · открыть проекты или изменить название"
	if not save_message.is_empty(): projects.tooltip_text += "\n" + save_message
	projects.get_popup().set_item_disabled(1, not glob.loaded_project_once)
	projects.get_popup().set_item_disabled(projects.get_popup().get_item_index(2), busy or not glob.loaded_project_once)
	projects.get_popup().set_item_disabled(projects.get_popup().get_item_index(3), not glob.loaded_project_once)
	for key in navigation:
		navigation[key].set_pressed_no_signal(glob.curr_window == key)
		navigation[key].icon = null if get_viewport_rect().size.x < 550.0 else navigation[key].get_meta("reference_active_icon" if glob.curr_window == key else "reference_icon")
	var dataset = _active_dataset()
	buttons.undo.disabled = not dataset.can_undo() if dataset != null else (true if glob.curr_window == "ds" else host.get_node("HistoryControls/Undo").disabled)
	buttons.redo.disabled = not dataset.can_redo() if dataset != null else (true if glob.curr_window == "ds" else host.get_node("HistoryControls/Redo").disabled)
	buttons.fit.disabled = glob.curr_window != "graph" or graphs._graphs.is_empty() or not is_instance_valid(glob.main_cam)
	buttons.save.disabled = busy or not glob.loaded_project_once
	buttons.export.disabled = not glob.loaded_project_once
	status.text = "Сохранение…" if busy else ("Локальный проект · " + str(graphs._graphs.size()) + " узлов" if glob.loaded_project_once else "Откройте проект или создайте новую модель")
	if not save_message.is_empty() and not busy: status.text = save_message
	status.tooltip_text = status.text
	status.add_theme_color_override("font_color", Design.DANGER if save_message.begins_with("Не удалось") else Design.INK_SECONDARY)
	# Compact mode keeps transient save/error feedback visible, without a
	# permanent third row for the idle node count.
	var show_status := busy or save_message == "Автосохранение…" or save_message.begins_with("Не удалось")
	if status_row.visible != show_status:
		status_row.visible = show_status
		_request_layout()
	overflow.get_popup().set_item_disabled(overflow.get_popup().get_item_index(0), buttons.undo.disabled)
	overflow.get_popup().set_item_disabled(overflow.get_popup().get_item_index(1), buttons.redo.disabled)
	overflow.get_popup().set_item_disabled(overflow.get_popup().get_item_index(2), not glob.loaded_project_once)
	overflow.get_popup().set_item_disabled(overflow.get_popup().get_item_index(4), buttons.fit.disabled)
	overflow.get_popup().set_item_disabled(overflow.get_popup().get_item_index(6), buttons.save.disabled)
	overflow.get_popup().set_item_disabled(overflow.get_popup().get_item_index(7), buttons.fit.disabled)
	var width: float = get_viewport_rect().size.x
	if is_equal_approx(width, _last_width) and _last_window == glob.curr_window:
		return
	_last_window = glob.curr_window
	_last_width = width
	_request_layout()

func _request_layout() -> void:
	if _layout_pending or not is_instance_valid(rows):
		return
	_layout_pending = true
	_layout_rows.call_deferred()

func _width_of(controls: Array, separation: float) -> float:
	var total := 0.0
	for control in controls:
		total += control.get_combined_minimum_size().x
	return total + maxf(0.0, controls.size() - 1) * separation

func _layout_rows() -> void:
	_layout_pending = false
	if not is_instance_valid(host) or not is_instance_valid(rows):
		return
	var width := get_viewport_rect().size.x
	var panel_size := get_theme_stylebox("panel").get_minimum_size()
	var margin := 12.0 if width <= 860.0 else 16.0
	var background := get_theme_stylebox("panel") as StyleBoxFlat
	background.content_margin_left = margin
	background.content_margin_right = margin
	var available := maxf(1.0, width - margin * 2.0)
	var gap := float(top.get_theme_constant("separation"))
	var action_gap := float(actions.get_theme_constant("separation"))
	var desktop_actions := _width_of([buttons.fit, buttons.save, buttons.axon, overflow], action_gap)
	var desktop_width := 128.0 + desktop_actions + tabs_panel.get_combined_minimum_size().x + gap * 2.0
	_compact = width <= 860.0 or desktop_width > available
	background.content_margin_top = 4.0
	background.content_margin_bottom = 4.0
	for key in ["undo", "redo", "export", "profile"]:
		buttons[key].hide()
	buttons.fit.visible = glob.curr_window == "graph"
	buttons.save.show()
	buttons.axon.show()
	overflow.show()
	var icon_only := width < 550.0
	buttons.fit.text = "" if icon_only else "Вся модель"
	buttons.save.text = "" if icon_only else ("Сохранение…" if busy else "Сохранить")
	buttons.axon.text = "" if icon_only else "Аксон"
	overflow.text = "" if icon_only else "Действия"
	for control in [buttons.fit, buttons.save, buttons.axon, overflow]:
		control.custom_minimum_size = Vector2(44, 44)
	project_slot.custom_minimum_size.x = 88.0 if _compact else 128.0
	projects.custom_minimum_size.x = 88.0 if _compact else 128.0
	projects.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.size_flags_horizontal = Control.SIZE_SHRINK_END
	if _compact and tabs_panel.get_parent() == top:
		tabs_panel.reparent(second)
	elif not _compact and tabs_panel.get_parent() == second:
		tabs_panel.reparent(top)
		top.move_child(tabs_panel, 1)
	second.visible = _compact
	tabs_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL if _compact else Control.SIZE_SHRINK_CENTER
	tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for button in navigation.values():
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL if _compact else Control.SIZE_SHRINK_CENTER
		button.expand_icon = width < 550.0
		button.icon = null if width < 550.0 else button.get_meta("reference_active_icon" if button.button_pressed else "reference_icon", button.icon)
	status_row.visible = busy or save_message == "Автосохранение…" or save_message.begins_with("Не удалось")
	rows.queue_sort()
	if not _geometry_pending:
		_geometry_pending = true
		_apply_geometry.call_deferred()

func _apply_geometry() -> void:
	_geometry_pending = false
	if not is_instance_valid(host):
		return
	# Use native minimum sizes, including font metrics, busy captions, and the
	# panel's real margins. A fixed header height can cover the workspace.
	var height := ceilf(rows.get_combined_minimum_size().y + get_theme_stylebox("panel").get_minimum_size().y)
	custom_minimum_size.y = height
	host.size = Vector2(get_viewport_rect().size.x, height)
	glob.space_begin.y = host.position.y + height
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _install_axon() -> void:
	if is_instance_valid(axon_panel) or not is_instance_valid(host):
		return
	axon_panel = load("res://scripts/claude_axon_panel.gd").new()
	axon_panel.name = "ClaudeAxonPanel"
	axon_panel.configure(host)
	host.get_parent().add_child(axon_panel)
	axon_panel.layout_changed.connect(_request_layout)
	axon_panel.layout_for_workspace(glob.space_begin.y, 14.0)


func _toggle_axon() -> void:
	if is_instance_valid(axon_panel):
		axon_panel.toggle_panel()


func get_workspace_end(viewport_size: Vector2) -> Vector2:
	if glob.curr_window != "graph":
		return viewport_size
	var end := viewport_size
	if is_instance_valid(axon_panel):
		end.x -= axon_panel.get_reserved_width()
	var palette := glob.base_node.get_node_or_null("WIN_GRAPH/NodePalette") if is_instance_valid(glob.base_node) else null
	if is_instance_valid(palette) and palette.has_method("get_reserved_bottom"):
		end.y -= palette.get_reserved_bottom()
	return Vector2(maxf(160.0, end.x), maxf(glob.space_begin.y + 120.0, end.y))


func _arrange_model() -> void:
	if glob.curr_window != "graph" or graphs._graphs.is_empty():
		return
	var layout = load("res://scripts/claude_graph_layout.gd")
	layout.apply(graphs._graphs.values(), glob)
	_fit_model.call_deferred()


func _weighted_font(weight: int) -> FontVariation:
	var font := FontVariation.new()
	font.base_font = load(Design.UI_FONT_PATH)
	font.variation_opentype = {0x77676874: float(weight)}
	return font


func _project_icon() -> Texture2D:
	return Design._icon("M3 7h6l2 2h10v11H3zM3 7V4h6l2 3", Design.INK_SECONDARY)


func _active_dataset() -> Object:
	if glob.curr_window != "ds":
		return null
	var dataset = glob.tree_windows.get("ds")
	return dataset if is_instance_valid(dataset) and dataset.has_method("can_undo") else null


func _history_action(redo_action: bool) -> void:
	var dataset = _active_dataset()
	if glob.curr_window == "ds" and dataset == null:
		return
	if dataset != null:
		if redo_action: dataset.redo()
		else: dataset.undo()
	else:
		if redo_action: host._on_redo_pressed()
		else: host._on_undo_pressed()
	_sync()
