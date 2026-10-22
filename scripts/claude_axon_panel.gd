extends PanelContainer
## Reference-inspired dock. Local explanations use the existing node catalog;
## questions go to the existing authenticated Axon dialog only on user action.

signal layout_changed

const Design = preload("res://scripts/claude_design_theme.gd")
const Catalog = preload("res://scripts/node_info_catalog.gd")
const NodeLabels = preload("res://scripts/claude_node_labels.gd")
const WorkspaceGeometry = preload("res://scripts/claude_workspace_geometry.gd")
const PANEL_FONT = preload("res://game_assets/fonts/Nunito[wght].ttf")
const DOCK_BREAKPOINT := 1000.0
const DOCK_GAP := 13.0
const PANEL_WIDTH := 377.0

var mascot: TextureRect
var host: Control
var is_open := false
var _overlay_requested := false
var context_label: Label
var context_lead: Label
var context_dot: Panel
var intro: Label
var explanation: RichTextLabel
var explain_button: Button
var next_button: Button
var quiz_button: Button
var login_button: Button
var question: LineEdit
var send_button: Button
var state_label: Label
var _info: Dictionary = {}
var _selection_key := ""
var _current_title := ""
var _busy := false
var _last_session := false
var _last_visibility := false
var _last_reserved := -1.0
var _workspace_top := 82.0
var _bottom_margin := 16.0
var _bold_font: FontVariation
var _strong_font: FontVariation
var _login_requested := false


func configure(top_bar: Control) -> void:
	host = top_bar


func _enter_tree() -> void:
	set_meta("claude_design_owned", true)
	set_meta("claude_styled", true)


func _ready() -> void:
	theme = Design.create_theme()
	theme.default_font = _weighted_font(600)
	_bold_font = _weighted_font(700)
	_strong_font = _weighted_font(800)
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_theme_stylebox_override("panel", Design.box(Design.CANVAS, Design.LINE, Design.CARD_RADIUS, Vector2.ZERO))
	clip_contents = true
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 0)
	add_child(column)
	var header := PanelContainer.new()
	header.name = "Crown"
	header.add_theme_stylebox_override("panel", Design.box(Color.TRANSPARENT, Color.TRANSPARENT, Design.CARD_RADIUS, Vector2.ZERO, 0))
	column.add_child(header)
	var header_margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		header_margin.add_theme_constant_override("margin_" + side, 21)
	header.add_child(header_margin)
	var header_rows := VBoxContainer.new()
	header_rows.add_theme_constant_override("separation", 8)
	header_margin.add_child(header_rows)
	var title_row := HBoxContainer.new()
	header_rows.add_child(title_row)
	var title := _label("Аксон", 24, Design.INK)
	title.add_theme_font_override("font", _strong_font)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(title)
	var close_button := Button.new()
	close_button.icon = Design._icon("M6 6l12 12M18 6L6 18", Design.INK)
	close_button.focus_mode = Control.FOCUS_ALL
	close_button.tooltip_text = "Закрыть панель Аксона"
	close_button.custom_minimum_size = Vector2(44, 44)
	close_button.add_theme_stylebox_override("normal", Design.box(Color(1, 1, 1, 0.55), Color.TRANSPARENT, Design.CONTROL_RADIUS, Vector2(10, 10), 0))
	close_button.add_theme_stylebox_override("hover", Design.box(Color.WHITE, Color.TRANSPARENT, Design.CONTROL_RADIUS, Vector2(10, 10), 0))
	close_button.pressed.connect(close_panel)
	title_row.add_child(close_button)
	var context_row := HBoxContainer.new()
	context_row.add_theme_constant_override("separation", 8)
	header_rows.add_child(context_row)
	context_lead = _label("Говорим про", 14, Design.INK_SECONDARY)
	context_lead.add_theme_font_override("font", _bold_font)
	context_row.add_child(context_lead)
	var dot_center := CenterContainer.new()
	context_row.add_child(dot_center)
	context_dot = Panel.new()
	context_dot.custom_minimum_size = Vector2(12, 12)
	var dot_style := Design.box(Design.LAYER_WIRE, Color.TRANSPARENT, 6, Vector2.ZERO, 0)
	dot_style.shadow_color = Color(1, 1, 1, 0.55)
	dot_style.shadow_size = 4
	context_dot.add_theme_stylebox_override("panel", dot_style)
	dot_center.add_child(context_dot)
	context_label = _label("выберите узел", 17, Design.INK)
	context_label.add_theme_font_override("font", _strong_font)
	context_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	context_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	context_label.custom_minimum_size.x = 0
	context_row.add_child(context_label)
	var fade_space := Control.new()
	fade_space.custom_minimum_size.y = 10
	header_rows.add_child(fade_space)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	var body_margin := MarginContainer.new()
	body_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["left", "right", "top", "bottom"]:
		body_margin.add_theme_constant_override("margin_" + side, 21)
	scroll.add_child(body_margin)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 10)
	body_margin.add_child(body)
	mascot = preload("res://scripts/axon_mascot.gd").new()
	mascot.name = "AxonMascot"
	mascot.custom_minimum_size = Vector2(0, 136)
	mascot.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	mascot.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	mascot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(mascot)
	var greeting := _label("Чем помочь?", 24, Design.INK)
	greeting.add_theme_font_override("font", _strong_font)
	body.add_child(greeting)
	intro = _label("Я Аксон, помощник по нейросетям. Выбери узел на схеме, и мы разберём его.", Design.UI_FONT_SIZE, Design.INK_SECONDARY)
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.add_theme_constant_override("line_spacing", 3)
	body.add_child(intro)
	var action_gap := Control.new()
	action_gap.custom_minimum_size.y = 3
	body.add_child(action_gap)
	explain_button = _action("Справка об узле", "На устройстве · без входа", "help", _show_explanation)
	body.add_child(explain_button)
	next_button = _action("Что делать дальше?", "Онлайн-диалог · нужен вход", "next", _ask_next)
	body.add_child(next_button)
	quiz_button = _action("Проверь меня", "Онлайн-диалог · нужен вход", "target", _ask_quiz)
	body.add_child(quiz_button)
	explanation = RichTextLabel.new()
	explanation.bbcode_enabled = true
	explanation.fit_content = true
	explanation.scroll_active = false
	explanation.selection_enabled = true
	explanation.add_theme_color_override("default_color", Design.INK_SECONDARY)
	explanation.add_theme_font_size_override("normal_font_size", 14)
	explanation.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	explanation.hide()
	body.add_child(explanation)
	var footer := MarginContainer.new()
	footer.add_theme_constant_override("margin_left", 13)
	footer.add_theme_constant_override("margin_right", 13)
	footer.add_theme_constant_override("margin_top", 8)
	footer.add_theme_constant_override("margin_bottom", 14)
	column.add_child(footer)
	var footer_rows := VBoxContainer.new()
	footer_rows.add_theme_constant_override("separation", 6)
	footer.add_child(footer_rows)
	var online_hint := _label("Онлайн: нужны интернет и вход. Ответ — в отдельном диалоге Аксона.", Design.CAPTION_FONT_SIZE, Design.INK_SECONDARY)
	online_hint.name = "OnlineContract"
	online_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	footer_rows.add_child(online_hint)
	state_label = _label("", Design.CAPTION_FONT_SIZE, Design.INK_SECONDARY)
	state_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	state_label.hide()
	footer_rows.add_child(state_label)
	login_button = Button.new()
	login_button.text = "Войти в аккаунт"
	login_button.custom_minimum_size.y = 44
	login_button.pressed.connect(_open_profile)
	login_button.hide()
	footer_rows.add_child(login_button)
	var compose := PanelContainer.new()
	var compose_style := Design.box(Design.CANVAS, Design.LINE_STRONG, Design.CONTROL_RADIUS, Vector2(5, 5), 2)
	compose_style.content_margin_left = 16
	compose_style.shadow_color = Color(0.10, 0.72, 0.61, 0.15)
	compose_style.shadow_size = 0
	compose.add_theme_stylebox_override("panel", compose_style)
	footer_rows.add_child(compose)
	var input_row := HBoxContainer.new()
	compose.add_child(input_row)
	question = LineEdit.new()
	question.placeholder_text = "Вопрос для онлайн-диалога…"
	question.tooltip_text = "Нужны интернет и вход. Ответ появится в отдельном диалоге Аксона."
	question.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	question.custom_minimum_size = Vector2(0, 44)
	question.expand_to_text_length = false
	question.add_theme_font_size_override("font_size", Design.UI_FONT_SIZE)
	question.add_theme_stylebox_override("normal", Design.box(Design.CANVAS, Color.TRANSPARENT, Design.CONTROL_RADIUS, Vector2(0, 6), 0))
	question.text_submitted.connect(_send_question)
	question.text_changed.connect(func(_value: String): _sync_actions())
	input_row.add_child(question)
	send_button = Button.new()
	send_button.focus_mode = Control.FOCUS_ALL
	send_button.accessibility_name = "Отправить вопрос в онлайн-диалог Аксона"
	send_button.icon = Design._icon("M5 12h14M13 6l6 6-6 6", Color.WHITE)
	send_button.tooltip_text = "Открыть диалог и отправить вопрос"
	send_button.custom_minimum_size = Vector2(46, 46)
	send_button.add_theme_stylebox_override("normal", Design.box(Design.INK, Color.TRANSPARENT, Design.CONTROL_RADIUS, Vector2(13, 13), 0))
	send_button.add_theme_stylebox_override("hover", Design.box(Design.PRIMARY, Color.TRANSPARENT, Design.CONTROL_RADIUS, Vector2(13, 13), 0))
	send_button.add_theme_stylebox_override("disabled", Design.box(Design.FILL, Color.TRANSPARENT, Design.CONTROL_RADIUS, Vector2(13, 13), 0))
	send_button.add_theme_color_override("icon_disabled_color", Design.INK_MUTED)
	send_button.pressed.connect(func(): _send_question(question.text))
	input_row.add_child(send_button)
	var disclaimer := _label("Аксон может ошибаться. Проверяй ответ по настройкам и данным модели.", Design.CAPTION_FONT_SIZE, Design.INK_MUTED)
	disclaimer.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	disclaimer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	footer_rows.add_child(disclaimer)
	_sync_context(true)
	_sync_session(true)
	_update_visibility()
	layout_for_workspace(_workspace_top, _bottom_margin)


func _label(caption: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = caption
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


func _weighted_font(weight: int) -> FontVariation:
	var font := FontVariation.new()
	font.base_font = PANEL_FONT
	# Godot's TextServer expects the numeric OpenType tag; a string key is
	# ignored and leaves this variable font at its thin default master.
	font.variation_opentype = {0x77676874: weight}
	return font


func _action(caption: String, subtitle: String, icon_kind: String, callback: Callable) -> Button:
	var button := Button.new()
	button.name = "Action_" + icon_kind
	button.focus_mode = Control.FOCUS_ALL
	button.tooltip_text = caption + ": " + subtitle
	button.accessibility_name = caption
	button.custom_minimum_size = Vector2(0, 66)
	for state in ["normal", "hover", "pressed", "disabled"]:
		var fill := Design.FILL
		if state == "hover": fill = Design.PRIMARY_SOFT
		if state == "pressed": fill = Design.FILL_HOVER
		button.add_theme_stylebox_override(state, Design.box(fill, Color.TRANSPARENT, Design.CARD_RADIUS, Vector2.ZERO, 0))
	var margin := MarginContainer.new()
	margin.name = "Contents"
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	button.add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 13)
	margin.add_child(row)
	var square := PanelContainer.new()
	square.name = "IconSquare"
	square.custom_minimum_size = Vector2(46, 46)
	square.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	square.add_theme_stylebox_override("panel", Design.box(Design.CANVAS, Color.TRANSPARENT, Design.CONTROL_RADIUS, Vector2(13, 13), 0))
	row.add_child(square)
	var icon := TextureRect.new()
	icon.texture = _action_icon(icon_kind)
	icon.custom_minimum_size = Vector2(20, 20)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	square.add_child(icon)
	var text_rows := VBoxContainer.new()
	text_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_rows.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	text_rows.add_theme_constant_override("separation", 3)
	row.add_child(text_rows)
	var action_title := _label(caption, Design.UI_FONT_SIZE, Design.INK)
	action_title.add_theme_font_override("font", _bold_font)
	action_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_rows.add_child(action_title)
	var action_caption := _label(subtitle, Design.CAPTION_FONT_SIZE, Design.INK_SECONDARY)
	action_caption.add_theme_font_override("font", _bold_font)
	action_caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_rows.add_child(action_caption)
	var arrow := TextureRect.new()
	arrow.texture = Design._icon("M5 12h14M13 6l6 6-6 6", Design.PRIMARY)
	arrow.custom_minimum_size = Vector2(16, 16)
	arrow.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	arrow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	arrow.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	row.add_child(arrow)
	_ignore_child_pointer(margin)
	button.pressed.connect(callback)
	return button


func _action_icon(kind: String) -> Texture2D:
	match kind:
		"help":
			return Design._icon("M21 12a9 9 0 1 1-18 0 9 9 0 0 1 18 0M9.5 9a2.5 2.5 0 1 1 4.1 1.9c-1.1.7-1.6 1.1-1.6 2.1M12 16h.01", Design.PRIMARY)
		"target":
			return Design._icon("M21 12a9 9 0 1 1-18 0 9 9 0 0 1 18 0M17 12a5 5 0 1 1-10 0 5 5 0 0 1 10 0M13 12a1 1 0 1 1-2 0 1 1 0 0 1 2 0", Design.PRIMARY)
	return Design._icon("M5 12h14M13 6l6 6-6 6", Design.PRIMARY)


func _ignore_child_pointer(node: Control) -> void:
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in node.get_children():
		if child is Control:
			_ignore_child_pointer(child)


func open_panel() -> void:
	if get_viewport_rect().size.x < DOCK_BREAKPOINT:
		_overlay_requested = true
	else:
		is_open = true
	_update_visibility()
	layout_for_workspace(_workspace_top, _bottom_margin)
	mascot.react("wave")


func close_panel() -> void:
	if get_viewport_rect().size.x < DOCK_BREAKPOINT:
		_overlay_requested = false
	else:
		is_open = false
	_update_visibility()
	_release_pointer_block()


func toggle_panel() -> void:
	if visible:
		close_panel()
	else:
		open_panel()


func is_overlay_open() -> bool:
	return get_viewport_rect().size.x < DOCK_BREAKPOINT and _overlay_requested and glob.curr_window == "graph"


func get_reserved_width() -> float:
	var width := get_viewport_rect().size.x
	if not is_open or glob.curr_window != "graph" or width < DOCK_BREAKPOINT:
		return 0.0
	return _panel_width(width) + DOCK_GAP


static func _panel_width(viewport_width: float) -> float:
	return PANEL_WIDTH if viewport_width >= DOCK_BREAKPOINT else maxf(0.0, minf(PANEL_WIDTH, viewport_width - 24.0))


func layout_for_workspace(top_y: float, bottom_margin: float = 16.0) -> void:
	_workspace_top = top_y
	_bottom_margin = bottom_margin
	var viewport_size := get_viewport_rect().size
	var margin := WorkspaceGeometry.horizontal_margin(viewport_size.x) if viewport_size.x >= DOCK_BREAKPOINT else 12.0
	var width := _panel_width(viewport_size.x)
	position = Vector2(maxf(margin, viewport_size.x - width - margin), top_y)
	size = Vector2(width, maxf(0.0, viewport_size.y - position.y - bottom_margin))
	for action in [explain_button, next_button, quiz_button]:
		if is_instance_valid(action):
			action.custom_minimum_size.y = 82 if width < 345 else 66
	var reserved := get_reserved_width()
	if not is_equal_approx(reserved, _last_reserved):
		_last_reserved = reserved
		layout_changed.emit()


func _process(_delta: float) -> void:
	_update_visibility()
	_update_pointer_block()
	if not visible:
		return
	_sync_context()
	_sync_session()
	layout_for_workspace(_workspace_top, _bottom_margin)


func _update_visibility() -> void:
	visible = is_overlay_open() if get_viewport_rect().size.x < DOCK_BREAKPOINT else is_open and glob.curr_window == "graph"
	if visible != _last_visibility:
		_last_visibility = visible
		layout_changed.emit()


func _sync_context(force: bool = false) -> void:
	var selected: Array = []
	for node in graphs.selected_nodes.keys():
		if is_instance_valid(node):
			selected.append(node)
	var key := str(glob.get_lang()) + ":"
	for node in selected:
		key += str(node.get_instance_id()) + ","
	if not force and key == _selection_key:
		return
	if not force and selected.size() == 1:
		mascot.react("blink")
	_selection_key = key
	_info = {}
	_current_title = ""
	explanation.hide()
	if selected.size() == 1:
		var type_id := str(selected[0].get_meta("created_with", ""))
		_info = Catalog.get_info(type_id, glob.get_lang())
		_current_title = _localized_node_title(type_id)
		_info["title"] = _current_title
		context_lead.text = "Говорим про"
		context_label.text = _current_title
		intro.text = "Разберём, как этот узел работает в твоей модели."
	elif selected.size() > 1:
		context_lead.text = "Выбрано"
		context_label.text = "%d узлов" % selected.size()
		intro.text = "Выбери один узел, чтобы открыть его описание и задать вопрос о нём."
	else:
		context_lead.text = "Говорим про"
		context_label.text = "выбери узел"
		intro.text = "Я Аксон, помощник по нейросетям. Выбери узел на схеме, и мы разберём его."
	context_label.tooltip_text = context_label.text
	_sync_actions()


func _localized_node_title(type_id: String) -> String:
	var fallback := str(_info.get("title", type_id))
	for definition in graphs.graph_buttons:
		if str(definition.get("name", "")) == type_id:
			fallback = str(definition.get("title_" + glob.get_lang(), definition.get("title", type_id)))
			break
	return NodeLabels.title(type_id, fallback) if glob.get_lang() == "ru" else fallback


func _sync_session(force: bool = false) -> void:
	var ready: bool = glob.remote_session_ready()
	if force or ready != _last_session:
		_last_session = ready
		login_button.visible = _login_requested and not ready
		if ready and _login_requested:
			_show_status("Ты вошёл в аккаунт. Нажми стрелку, чтобы отправить подготовленный вопрос.")
			_login_requested = false
		_sync_actions()


func _sync_actions() -> void:
	explain_button.disabled = _busy
	next_button.disabled = _busy
	quiz_button.disabled = _busy
	send_button.disabled = _busy or question.text.strip_edges().is_empty()
	# Native Button disabled colors do not reach the custom child labels/icons.
	for action in [explain_button, next_button, quiz_button]:
		action.get_node("Contents").modulate.a = 0.5 if _busy else 1.0
	question.editable = not _busy
	login_button.disabled = _busy


func _show_explanation() -> void:
	if not bool(_info.get("available", false)):
		_show_status("Выбери один узел на схеме, чтобы открыть его описание.")
		return
	explanation.text = Catalog.render_bbcode(_info).replace("[font_size=30]", "[font_size=20]")
	explanation.show()
	mascot.react("think")
	# The action subtitle already states that bundled help needs no login.
	# Keep the narrow footer for actionable feedback and online drafts.
	if not _login_requested:
		_show_status("")


func _ask_next() -> void:
	if not _require_node_context():
		return
	_send_question("Какой следующий шаг с узлом «%s» в текущей модели? Опирайся на доступный контекст и уточни недостающие данные." % _current_title)


func _ask_quiz() -> void:
	if not _require_node_context():
		return
	_send_question("Задай мне один вопрос, чтобы проверить понимание узла «%s». Дождись моего ответа перед объяснением." % _current_title)


func _open_profile() -> void:
	if is_instance_valid(host):
		_show_status("Открываем вход в аккаунт…")
		await host._on_login_released()
		_sync_session(true)
		if not glob.remote_session_ready():
			_show_status("Вход не завершён. Вопрос сохранён в поле; можно попробовать ещё раз.")
	else:
		_show_status("Не удалось открыть вход. Закрой панель и попробуй снова.", true)


func _require_node_context() -> bool:
	if bool(_info.get("available", false)):
		return true
	_show_status("Сначала выбери один узел на схеме — вопрос будет о нём.")
	return false


func _show_status(message: String, failed: bool = false) -> void:
	state_label.add_theme_color_override("font_color", Design.DANGER if failed else Design.INK_SECONDARY)
	state_label.text = message
	state_label.visible = not message.is_empty()


func _send_question(value: String) -> void:
	var text := value.strip_edges()
	if text.is_empty() or _busy:
		return
	# Keep the actual submitted draft through login, cancelled dialogs and retries.
	question.text = text
	if not glob.remote_session_ready():
		_login_requested = true
		login_button.show()
		_show_status("Для ответа Аксона нужен вход. Вопрос сохранён в поле — после входа нажми стрелку.")
		_sync_actions()
		return
	if not is_instance_valid(host):
		_show_status("Не удалось открыть диалог. Закрой панель и попробуй снова.", true)
		return
	mascot.react("think")
	_busy = true
	_show_status("Открываем диалог…")
	_sync_actions()
	await host._on_ai_released()
	var menu = glob.ai_help_menu
	if not glob.remote_session_ready() or not is_instance_valid(menu) or not menu.visible:
		_show_status("Диалог не открылся. Проверь вход и попробуй ещё раз.", true)
	else:
		var request := {
			"request_id": "workspace-%s" % Time.get_ticks_usec(),
			"question": text,
			"source_label": "Из панели: " + _current_title if not _current_title.is_empty() else "Из панели Аксона",
		}
		if menu.queue_context_request(request):
			question.clear()
			_show_status("Вопрос передан в диалог Аксона. Ответ появится там.")
		else:
			_show_status("Не удалось передать вопрос. Попробуй ещё раз.", true)
	_busy = false
	_sync_actions()


func _update_pointer_block() -> void:
	if visible and get_global_rect().has_point(get_global_mouse_position()):
		glob.occupy(self, &"menu_inside")
		glob.set_scroll_impossible(self)
	else:
		_release_pointer_block()


func _release_pointer_block() -> void:
	glob.un_occupy(self, &"menu_inside")
	glob.set_scroll_possible(self)


func _exit_tree() -> void:
	_release_pointer_block()
