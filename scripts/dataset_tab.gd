extends TabWindow
## Visual data workspace; no dependency on the old table or console UI.
const Document = preload("res://scripts/data_workspace/document.gd")
const IO = preload("res://scripts/data_workspace/import_export.gd")
const Canvas = preload("res://scripts/data_workspace/canvas.gd")
const PaletteItem = preload("res://scripts/data_workspace/palette_item.gd")
const ImageEditor = preload("res://scripts/data_workspace/image_editor.gd")
const WorkspaceStyle = preload("res://scripts/data_workspace/workspace_style.gd")

var document
var documents: Dictionary = {}
var selection: Array = []
var _names: Array = []
var _pending: Dictionary = {}
var _saving := false
var _busy := false
var _cancel_requested := false
var _staged: Array = []
var _selected_group := ""
var _page := 0
var _palette_visible := true
var _last_compact := false
var _inspector_requested := false
var _inspector_closed := false
var _layer: CanvasLayer
var _root: Control
var _palette: PanelContainer
var _inspector: PanelContainer
var _inspector_body: VBoxContainer
var _toolbar: Control
var _title: Label
var _subtitle: Label
var _footer: Control
var _status: Label
var _page_label: Label
var _quality_label: Label
var _group_count_labels: Dictionary = {}
var _dataset_picker: OptionButton
var _canvas
var _file_dialog: FileDialog
var _folder_dialog: FileDialog
var _export_dialog: FileDialog
var _save_timer: Timer
var _reopen: Button
var _view_buttons: Dictionary = {}
var _sample_button: Button
var _history_buttons: Dictionary = {}
var _page_buttons: Dictionary = {}
var _actions_menu: MenuButton
var _csv_previews: Array[Dictionary] = []
var _import_errors: Array = []
var _import_report: Dictionary = {}

func _enter_tree() -> void:
	super()
	set_meta("claude_design_owned", true)

func _ready() -> void:
	_build()
	_save_timer = Timer.new()
	_save_timer.one_shot = true
	_save_timer.wait_time = 1.2
	_save_timer.timeout.connect(flush_pending_changes)
	add_child(_save_timer)
	get_viewport().size_changed.connect(_layout)
	get_window().files_dropped.connect(_on_files_dropped)
	glob.project_opened.connect(func(_id): documents.clear(); document = null; reload_scenes())
	_layout()
	_window_hide()

func _build() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 20
	add_child(_layer)
	_root = Control.new()
	_root.theme = WorkspaceStyle.make_theme()
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(_root)
	var backdrop := ColorRect.new()
	backdrop.color = WorkspaceStyle.Design.PAGE
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(backdrop)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_palette = _panel(_root)
	var left := _column(_palette)
	var heading := HBoxContainer.new()
	left.add_child(heading)
	_label(heading, "Датасеты", 19).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_button(heading, "Скрыть", Vector2(72, 28), func(): _palette_visible = false; _layout())
	_label(left, "Мои датасеты", 11, WorkspaceStyle.MUTED)
	_dataset_picker = OptionButton.new()
	_dataset_picker.custom_minimum_size.y = 34
	_dataset_picker.focus_mode = Control.FOCUS_ALL
	_dataset_picker.clip_text = true
	_dataset_picker.fit_to_longest_item = false
	_dataset_picker.custom_minimum_size.x = 190
	_dataset_picker.add_theme_font_size_override("font_size", 13)
	_dataset_picker.item_selected.connect(func(index): open_dataset(str(_names[index])))
	left.add_child(_dataset_picker)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left.add_child(scroll)
	var tools := VBoxContainer.new()
	tools.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tools.add_theme_constant_override("separation", 8)
	scroll.add_child(tools)
	for section in [
		["СОЗДАТЬ", [["numeric", "Числа\nполя и ответы"], ["images", "Изображения\nклассы и кадры"], ["text", "Текст\nпримеры и метки"], ["car", "Машинка\nсостояния и действия"]]],
		["РАЗМЕТКА", [["sample", "Пример\nдобавить на поле"], ["class", "Класс\nновая группа"]]],
		["РАСШИРИТЬ", [["folder", "Папка\nфайлы с ПК"], ["import", "CSV / JSON\nтаблицы и дампы"], ["generate", "Синтетика\nмного примеров"], ["augment", "Аугментация\nновые вариации"]]]
	]:
		_label(tools, str(section[0]), 11, WorkspaceStyle.MUTED)
		var grid := GridContainer.new()
		grid.columns = 1
		grid.add_theme_constant_override("h_separation", 4)
		grid.add_theme_constant_override("v_separation", 4)
		tools.add_child(grid)
		for entry in section[1]:
			var item: Control = PaletteItem.new()
			item.hover_scale = 1.0
			item.custom_minimum_size = Vector2(196, 40)
			item.setup({"type_id": entry[0], "title": entry[1], "outline_color": Color("8cc7f0"), "icon_path": ""})
			var icon_names := {"numeric": "bars", "images": "image", "text": "quote", "car": "car", "sample": "plus", "class": "grid", "folder": "folder", "import": "upload", "generate": "spark", "augment": "copy"}
			item.action_icon = load("res://scripts/data_workspace/icons/%s.svg" % icon_names[entry[0]])
			item.activated.connect(func(tool): activate_tool(tool))
			grid.add_child(item)
	_label(left, "Перетащите объект на рабочую область", 11, WorkspaceStyle.MUTED).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_canvas = Canvas.new()
	_canvas.theme = _root.theme
	_root.add_child(_canvas)
	_canvas.tool_dropped.connect(activate_tool)
	_canvas.row_selected.connect(_select_row)
	_canvas.group_relocated.connect(_move_group)
	_canvas.row_reclassified.connect(func(row, group): document.assign_class([row], group))
	_canvas.files_requested.connect(import_paths)
	_canvas.resized.connect(func():
		if document != null: _refresh()
	)
	_toolbar = Control.new()
	_root.add_child(_toolbar)
	_title = _label(_toolbar, "Мастерская данных", 22)
	_title.clip_text = true
	_title.position = Vector2(12, 7)
	_subtitle = _label(_toolbar, "Примеры, классы и подготовка к обучению", 12, WorkspaceStyle.MUTED)
	_subtitle.position = Vector2(12, 35)
	var header_actions := HBoxContainer.new()
	header_actions.name = "HeaderActions"
	_toolbar.add_child(header_actions)
	header_actions.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	header_actions.offset_left = -242; header_actions.offset_right = -12
	header_actions.offset_top = 8; header_actions.offset_bottom = 44
	header_actions.add_theme_constant_override("separation", 8)
	_button(header_actions, "Импорт", Vector2(92, 34), func(): activate_tool("import"))
	_sample_button = _button(header_actions, "Создать набор", Vector2(130, 34), _primary_dataset_action)
	var tool_scroll := ScrollContainer.new()
	tool_scroll.name = "ViewActions"
	_toolbar.add_child(tool_scroll)
	tool_scroll.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	tool_scroll.offset_left = 12; tool_scroll.offset_top = 57; tool_scroll.offset_bottom = 94
	tool_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	tool_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 6)
	tool_scroll.add_child(actions)
	for view in [["Карточки", "cards", 84], ["Таблица", "table", 78], ["График", "plot", 76]]:
		_view_buttons[view[1]] = _button(actions, view[0], Vector2(view[2], 29), _set_view.bind(view[1]))
	_history_buttons.undo = _button(actions, "Отменить", Vector2(88, 29), undo)
	_history_buttons.redo = _button(actions, "Повторить", Vector2(94, 29), redo)
	_history_buttons.reset = _button(actions, "В начало", Vector2(94, 29), func(): _canvas.reset_view())
	_actions_menu = MenuButton.new()
	_actions_menu.text = "Ещё"
	_actions_menu.focus_mode = Control.FOCUS_ALL
	_actions_menu.custom_minimum_size = Vector2(52, 34)
	_actions_menu.tooltip_text = "Команды набора данных"
	actions.add_child(_actions_menu)
	var menu := _actions_menu.get_popup()
	menu.add_item("Отменить", 0)
	menu.add_item("Повторить", 1)
	menu.add_separator()
	menu.add_item("В начало данных", 2)
	menu.add_item("Параметры набора", 3)
	menu.id_pressed.connect(func(id):
		match id:
			0: undo()
			1: redo()
			2: _canvas.reset_view()
			3: _inspector_requested = true; _show_overview(); _layout()
	)
	_inspector = _panel(_root)
	var inspector_scroll := ScrollContainer.new()
	inspector_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_inspector.add_child(inspector_scroll)
	_inspector_body = _column(inspector_scroll)
	_inspector_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_inspector_body.add_theme_constant_override("separation", 10)
	_footer = Control.new()
	_root.add_child(_footer)
	var paging := HBoxContainer.new()
	_footer.add_child(paging)
	_page_buttons.previous = _button(paging, "Назад", Vector2(76, 28), func(): _page = maxi(0, _page - 1); _refresh())
	_page_label = _label(paging, "0 / 0", 12, WorkspaceStyle.MUTED)
	_page_label.custom_minimum_size.x = 100
	_page_buttons.next = _button(paging, "Далее", Vector2(76, 28), func():
		if document != null and (_page + 1) * _canvas.page_size < document.row_count(): _page += 1; _refresh()
	)
	_status = _label(_footer, "Колесо — прокрутка · Ctrl/Cmd + колесо — масштаб", 11, WorkspaceStyle.MUTED)
	_status.position = Vector2(8, 34)
	_reopen = _button(_root, "Палитра", Vector2(98, 30), func(): _palette_visible = true; _layout())
	_file_dialog = _file_picker(FileDialog.FILE_MODE_OPEN_FILES, ["*.csv,*.tsv,*.json,*.png,*.jpg,*.jpeg,*.webp,*.bmp,*.txt,*.md; Данные"])
	_file_dialog.files_selected.connect(func(paths): import_paths(Array(paths)))
	_folder_dialog = _file_picker(FileDialog.FILE_MODE_OPEN_DIR, [])
	_folder_dialog.dir_selected.connect(func(path): import_paths([path]))
	_export_dialog = _file_picker(FileDialog.FILE_MODE_SAVE_FILE, ["*.json; Датасет Neuralese (с изображениями)", "*.csv; CSV (числа и текст)"])
	_export_dialog.file_selected.connect(_export_file)
	_show_overview()
	_sync_actions()

func _process(_delta: float) -> void:
	# The shell can reflow after the viewport's resize signal. Follow its final
	# height once, without continuously resizing the canvas while it is idle.
	if _root != null and not is_equal_approx(_root.position.y, maxf(52, float(glob.space_begin.y))):
		_layout()

func _layout() -> void:
	if _root == null: return
	var viewport_size := get_viewport().get_visible_rect().size
	var top: float = maxf(52, float(glob.space_begin.y))
	_root.position = Vector2(0, top)
	_root.size = viewport_size - Vector2(0, top)
	var compact := viewport_size.x < 960
	if compact != _last_compact:
		_palette_visible = not compact
		_last_compact = compact
	var gap := 12.0
	var palette_width := minf(224.0, _root.size.x - 24.0)
	var left := palette_width + gap * 2 if _palette_visible and not compact else gap
	if _inspector_requested: _inspector_closed = false
	var show_inspector := (viewport_size.x >= 1120 and not _inspector_closed) or _inspector_requested
	var inspector_width := minf(290.0, _root.size.x - 24.0)
	var right := inspector_width + gap if show_inspector and not compact else 0.0
	_palette.visible = _palette_visible
	_palette.position = Vector2(gap, gap)
	_palette.size = Vector2(palette_width, maxf(100, _root.size.y - 24))
	_palette.z_index = 2 if compact else 0
	_inspector.visible = show_inspector
	_inspector.z_index = 3 if compact else 0
	_inspector.position = Vector2(_root.size.x - inspector_width - gap, gap)
	_inspector.size = Vector2(inspector_width, maxf(100, _root.size.y - 24))
	_inspector_body.custom_minimum_size.x = inspector_width - 40
	var canvas_width := maxf(120, _root.size.x - left - right - gap)
	var stacked := canvas_width < 560
	var toolbar_height := 138.0 if stacked else 100.0
	_canvas.position = Vector2(left, toolbar_height)
	_canvas.size = Vector2(canvas_width, maxf(100, _root.size.y - toolbar_height - 76))
	_toolbar.position = Vector2(left, 0)
	_toolbar.size = Vector2(canvas_width, toolbar_height)
	_title.size.x = maxf(60, canvas_width - (24 if stacked else 260))
	_subtitle.size.x = maxf(60, canvas_width - 24)
	_subtitle.clip_text = true
	var header_actions: Control = _toolbar.get_node("HeaderActions")
	header_actions.position = Vector2(12 if stacked else canvas_width - 242, 55 if stacked else 8)
	var view_actions: Control = _toolbar.get_node("ViewActions")
	view_actions.offset_top = 98 if stacked else 57
	view_actions.offset_bottom = toolbar_height - 6
	view_actions.offset_right = -12
	for button in _history_buttons.values(): button.visible = canvas_width >= 680
	_footer.position = Vector2(left + 8, _root.size.y - 70)
	_footer.size = Vector2(canvas_width - 16, 66)
	_status.size.x = maxf(100, canvas_width - 16)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_reopen.visible = not _palette_visible
	_reopen.position = Vector2(16, toolbar_height + 6)
	if compact: _reopen.z_index = 2

func _panel(parent: Node) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", WorkspaceStyle.box(Color.WHITE, WorkspaceStyle.Design.LINE, 20))
	parent.add_child(panel)
	return panel

func _column(parent: Node) -> VBoxContainer:
	var margin := MarginContainer.new()
	for edge in ["left", "right", "top", "bottom"]: margin.add_theme_constant_override("margin_" + edge, 12)
	parent.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	margin.add_child(column)
	return column

func _label(parent: Node, text: String, font_size: int = 14, color := WorkspaceStyle.TEXT) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label

func _button(parent: Node, text: String, dimensions: Vector2, callback: Callable) -> Button:
	# Native buttons provide keyboard activation and focus without duplicating
	# the dataset action handlers or inheriting graph-control modulation.
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_ALL
	button.custom_minimum_size = Vector2(dimensions.x, maxf(34, dimensions.y))
	button.size = button.custom_minimum_size
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.pressed.connect(callback)
	parent.add_child(button)
	_style_button(button, text in ["+ Пример", "Создать набор", "Добавить пример", "Пример", "Применить", "Добавить в мастерскую", "Создать"])
	return button

func _style_button(button: Button, primary := false, selected := false) -> void:
	var design = WorkspaceStyle.Design
	for state in ["normal", "hover", "pressed", "disabled"]:
		var fill: Color = design.PRIMARY if primary else design.PRIMARY_SOFT if selected else design.CANVAS
		if state in ["hover", "pressed"]: fill = fill.darkened(0.08) if primary else design.FILL
		if state == "disabled": fill = design.FILL
		var style := WorkspaceStyle.box(fill, design.PRIMARY if primary or selected else design.LINE_STRONG, design.CONTROL_RADIUS)
		style.content_margin_left = 8; style.content_margin_right = 8
		style.content_margin_top = 4; style.content_margin_bottom = 4
		button.add_theme_stylebox_override(state, style)
		button.add_theme_color_override("font_" + ("color" if state == "normal" else state + "_color"), design.INK_SECONDARY if state == "disabled" else Color.WHITE if primary else design.INK)
	var focus := WorkspaceStyle.box(Color.TRANSPARENT, design.PRIMARY, design.CONTROL_RADIUS)
	focus.set_border_width_all(2)
	button.add_theme_stylebox_override("focus", focus)

func _primary_dataset_action() -> void:
	if document == null:
		activate_tool("numeric")
		_status.text = "Набор создан. Добавьте пример или настройте поля и ответы."
	else: activate_tool("sample")

func can_undo() -> bool: return document != null and document.can_undo()
func can_redo() -> bool: return document != null and document.can_redo()
func undo() -> void:
	if can_undo(): document.undo()
func redo() -> void:
	if can_redo(): document.redo()

func _sync_actions() -> void:
	if _sample_button == null: return
	_sample_button.text = "Создать набор" if document == null else "+ Пример"
	for view in _view_buttons:
		_view_buttons[view].disabled = document == null or (view == "plot" and document.kind() not in ["numeric", "car", "simulation"])
		_style_button(_view_buttons[view], false, _canvas.view == view and document != null)
	_history_buttons.undo.disabled = not can_undo()
	_history_buttons.redo.disabled = not can_redo()
	_history_buttons.reset.disabled = document == null
	var menu := _actions_menu.get_popup()
	menu.set_item_disabled(menu.get_item_index(0), not can_undo())
	menu.set_item_disabled(menu.get_item_index(1), not can_redo())
	menu.set_item_disabled(menu.get_item_index(2), document == null)
	menu.set_item_disabled(menu.get_item_index(3), document == null)
	_page_buttons.previous.disabled = document == null or _page == 0
	_page_buttons.next.disabled = document == null or (_page + 1) * _canvas.page_size >= document.row_count()

func _line(parent: Node, placeholder: String, text := "") -> LineEdit:
	var line := LineEdit.new()
	line.placeholder_text = placeholder; line.text = text
	line.custom_minimum_size.y = 32
	line.add_theme_font_size_override("font_size", 13)
	parent.add_child(line)
	return line

func _spin(parent: Node, initial: float, minimum: float, maximum: float, step: float = 1.0) -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value = minimum; spin.max_value = maximum; spin.step = step; spin.value = initial
	spin.custom_minimum_size = Vector2(110, 32)
	spin.add_theme_font_size_override("font_size", 13)
	spin.get_line_edit().add_theme_font_size_override("font_size", 13)
	parent.add_child(spin)
	return spin

func _file_picker(mode: FileDialog.FileMode, filters: Array) -> FileDialog:
	var dialog := FileDialog.new()
	dialog.file_mode = mode; dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.filters = PackedStringArray(filters); dialog.theme = _root.theme
	add_child(dialog)
	return dialog

func _clear_inspector() -> void:
	_quality_label = null
	_group_count_labels.clear()
	for child in _inspector_body.get_children():
		_inspector_body.remove_child(child); child.queue_free()
	var heading := HBoxContainer.new()
	_inspector_body.add_child(heading)
	_label(heading, "СВОЙСТВА", 14).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_button(heading, "×", Vector2(28, 28), func(): _inspector_requested = false; _inspector_closed = true; _layout())

func _window_show() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS; show()
	$bg.activate()
	if _layer != null: _layer.show(); _layout(); reload_scenes()
	if is_instance_valid(glob.fg): glob.fg.show_back()

func _window_hide() -> void:
	if is_inside_tree() and not _pending.is_empty(): flush_pending_changes()
	if _layer != null: _layer.hide()
	$bg.deactivate()
	hide(); process_mode = Node.PROCESS_MODE_DISABLED

func request_texts() -> Dictionary: return glob.ds_dump

func reload_scenes() -> void:
	if _dataset_picker == null: return
	var previous := str(document.data.name) if document != null else ""
	_names = glob.dataset_datas.keys(); _names.sort()
	_dataset_picker.clear()
	for name in _names: _dataset_picker.add_item(str(name))
	if _names.is_empty():
		document = null; _canvas.render(null, []); _show_overview()
	elif _names.has(previous): _dataset_picker.select(_names.find(previous))
	else: open_dataset(str(_names[0]))
	_sync_actions()

func open_dataset(name: String) -> void:
	if not glob.dataset_datas.has(name): return
	if not documents.has(name):
		var model = Document.new()
		model.attach(glob.dataset_datas[name]); model.changed.connect(_document_changed.bind(model))
		documents[name] = model
	document = documents[name]; selection.clear(); _page = 0
	if _names.has(name): _dataset_picker.select(_names.find(name))
	_selected_group = str(document.classes()[0]); _canvas.view = "cards"; _canvas.reset_view()
	_refresh(); _show_overview()

func _register(model) -> void:
	var title := _unique_name(str(model.data.name))
	model.data.name = title
	glob.dataset_datas[title] = model.data
	glob.ds_dump[title] = glob.create_dataset(randi_range(1, 999999999), title, model.data)
	model.changed.connect(_document_changed.bind(model)); documents[title] = model
	_pending[title] = true; reload_scenes(); open_dataset(title); _document_changed(model)

func _unique_name(base: String) -> String:
	var title := base.strip_edges().replace("/", "_").replace("\\", "_")
	if title.is_empty(): title = "Новый набор"
	var candidate := title; var index := 2
	while glob.dataset_datas.has(candidate): candidate = title + " " + str(index); index += 1
	return candidate

func activate_tool(tool: String, group: String = "", _at: Vector2 = Vector2.ZERO) -> void:
	if _busy: return
	if tool in ["numeric", "images", "text", "car"]:
		var titles := {"numeric": "Числа", "images": "Изображения", "text": "Тексты", "car": "Управление машинкой"}
		var model = Document.new(); model.create(_unique_name(titles[tool]), tool); _register(model)
	elif tool == "folder": _folder_dialog.popup_centered_ratio(0.65)
	elif tool == "import": _file_dialog.popup_centered_ratio(0.65)
	elif document == null: _status.text = "Сначала создайте или импортируйте набор данных"
	elif tool == "sample":
		var row: int = document.add_sample(group if not group.is_empty() else _selected_group)
		_page = floori(float(row) / _canvas.page_size); _select_row(row, false)
	elif tool == "class": _show_class_form()
	elif tool in ["generate", "augment"]: _show_batch_form(tool)

func _document_changed(model) -> void:
	var name := str(model.data.name)
	if not documents.has(name) or documents[name] != model: return
	_pending[name] = true
	var quality: Dictionary = model.quality()
	var preview: Dictionary = DsObjRLE.get_preview(model.data)
	if not quality.errors.is_empty(): preview = {"name": name, "fail": "invalid_values", "fatal": "invalid_values"}
	glob.previewed[name] = preview; glob.rle_cache.erase(name); glob.dirtify_dataset(name)
	if preview.has("fail"): glob.invalidate_local_ds(name)
	else: glob.change_local_ds(name)
	if _save_timer != null: _save_timer.start()
	if model == document: _refresh()

func flush_pending_changes() -> void:
	if _saving or _pending.is_empty(): return
	_saving = true
	var names := _pending.keys(); _pending.clear()
	for name in names:
		if not glob.dataset_datas.has(name): continue
		glob.cache_rle_compress(name, null, "thread"); await glob.join_ds_processing()
		await glob.save_godot_dataset(glob.dataset_datas[name]); await glob.join_ds_save()
		glob.dirty_datasets.erase(name)
	_saving = false
	if not _pending.is_empty(): _save_timer.start()

func _refresh() -> void:
	if document == null:
		_sync_actions()
		return
	selection = selection.filter(func(row): return int(row) < document.row_count())
	_page = mini(_page, maxi(0, ceili(float(document.row_count()) / _canvas.page_size) - 1))
	_canvas.render(document, selection, _page)
	_title.text = str(document.data.name)
	_subtitle.text = "Примеры: %d · входы: %d → ответы: %d" % [document.row_count(), int(document.data.outputs_from), document.column_count() - int(document.data.outputs_from)]
	_page_label.text = "%d / %d" % [_page + 1 if document.row_count() > 0 else 0, maxi(0, ceili(float(document.row_count()) / _canvas.page_size))]
	if is_instance_valid(_quality_label):
		_quality_label.text = _quality_text()
		_quality_label.add_theme_color_override("font_color", _quality_color())
	var counts: Dictionary = document.group_counts()
	for group in _group_count_labels:
		if is_instance_valid(_group_count_labels[group]):
			_group_count_labels[group].text = "%s — %d" % [group, int(counts.get(group, 0))]
	_sync_actions()

func _quality_text() -> String:
	var quality: Dictionary = document.quality(); var lines: Array[String] = []
	for error in quality.errors: lines.append("! " + str(error))
	for warning in quality.warnings: lines.append("• " + str(warning))
	if lines.is_empty(): lines.append("Данные проверены")
	lines.append("Обучение: %d · проверка: %d" % [quality.train, quality.validation])
	return "\n".join(lines)

func _quality_color() -> Color:
	var quality: Dictionary = document.quality()
	return Color("aa2845") if not quality.errors.is_empty() else Color("9b5c10") if not quality.warnings.is_empty() else Color("287962")

func _set_view(view: String) -> void:
	if document == null: return
	if view == "plot" and document.kind() not in ["numeric", "car", "simulation"]:
		_status.text = "График доступен для числовых признаков"; return
	_canvas.view = view; _refresh()

func _select_row(row: int, extend: bool) -> void:
	if document == null: return
	if extend:
		if selection.has(row): selection.erase(row)
		else: selection.append(row)
	else: selection = [row]
	_selected_group = document.group_for(row); _inspector_requested = true
	_layout(); _refresh(); _show_sample()

func _show_overview() -> void:
	_clear_inspector(); _label(_inspector_body, "Набор данных", 20)
	if document == null:
		_label(_inspector_body, "Создайте набор в палитре слева. Можно сразу перетащить папку с изображениями, CSV, JSON или текстами.", 14, WorkspaceStyle.MUTED).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		return
	var model = document
	_label(_inspector_body, str(model.data.name), 16).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label(_inspector_body, "Классы и количество", 13, WorkspaceStyle.MUTED)
	var counts: Dictionary = model.group_counts()
	for group in counts:
		_group_count_labels[group] = _label(_inspector_body, "%s — %d" % [group, int(counts[group])], 13)
	if model.kind() in ["numeric", "text"]: _button(_inspector_body, "Поля и ответы", Vector2(246, 30), _show_schema)
	if model.kind() == "images":
		_label(_inspector_body, "Подготовка изображений", 14)
		_label(_inspector_body, "%d × %d · оттенки серого\nИмпорт растягивается до этого размера" % [int(model.studio().get("image_width", 28)), int(model.studio().get("image_height", 28))], 12, WorkspaceStyle.MUTED).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var sizes := HBoxContainer.new(); _inspector_body.add_child(sizes)
		var width := _spin(sizes, model.studio().get("image_width", 28), 4, 256)
		var height := _spin(sizes, model.studio().get("image_height", 28), 4, 256)
		_button(_inspector_body, "Изменить размер всех", Vector2(246, 30), func(): _resize_images(int(width.value), int(height.value)))
	_label(_inspector_body, "Разделение для локального обучения", 13).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label(_inspector_body, "Доля проверочных данных, %", 12, WorkspaceStyle.MUTED)
	var fraction := _spin(_inspector_body, float(model.studio().get("validation_ratio", 0.2)) * 100, 0, 50)
	fraction.value_changed.connect(func(value): model.studio().validation_ratio = value / 100.0; _document_changed(model))
	_label(_inspector_body, "Зерно разделения", 12, WorkspaceStyle.MUTED)
	var seed_field := _spin(_inspector_body, model.studio().get("split_seed", 42), 0, 999999)
	seed_field.value_changed.connect(func(value): model.studio().split_seed = int(value); _document_changed(model))
	_quality_label = _label(_inspector_body, _quality_text(), 12, _quality_color())
	_quality_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_button(_inspector_body, "Экспортировать набор", Vector2(246, 32), func(): _export_dialog.current_file = str(model.data.name) + ".json"; _export_dialog.popup_centered_ratio(0.65))
	_label(_inspector_body, "На карточках: зелёная точка — обучение, жёлтая — проверка.\nГруппы карточек можно двигать за заголовок.", 11, WorkspaceStyle.MUTED).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

func _show_sample() -> void:
	_clear_inspector()
	if selection.is_empty(): _show_overview(); return
	var model = document
	var row: int = int(selection.back())
	_label(_inspector_body, "Пример #%d" % (row + 1), 20)
	_label(_inspector_body, "Выбрано: %d · %s" % [selection.size(), "проверка" if model.split_for(row) == "validation" else "обучение"], 12, WorkspaceStyle.MUTED)
	if not model.studio().get("classes", []).is_empty():
		var picker := OptionButton.new(); picker.add_theme_font_size_override("font_size", 13); picker.custom_minimum_size.y = 32
		var groups: Array = model.classes()
		for group in groups: picker.add_item(str(group))
		picker.select(maxi(0, groups.find(model.group_for(row))))
		picker.item_selected.connect(func(index): model.assign_class(selection, str(groups[index])))
		_inspector_body.add_child(picker)
	if model.kind() == "images":
		var texture: Variant = model.value(row, 0)
		if texture is Texture2D:
			var editor = ImageEditor.new(); editor.custom_minimum_size = Vector2(250, 220)
			_inspector_body.add_child(editor); editor.setup(texture.get_image())
			editor.image_edited.connect(func(image): model.set_value(row, 0, ImageTexture.create_from_image(image)))
			var tools := HBoxContainer.new(); _inspector_body.add_child(tools)
			_button(tools, "Кисть", Vector2(80, 30), func(): editor.erase = false)
			_button(tools, "Ластик", Vector2(88, 30), func(): editor.erase = true)
			_label(_inspector_body, "Рисуйте прямо здесь", 11, WorkspaceStyle.MUTED)
	else:
		for column in model.column_count():
			if column >= int(model.data.outputs_from) and not model.studio().get("classes", []).is_empty(): continue
			_label(_inspector_body, model.field_name(column) + (" → ответ" if column >= int(model.data.outputs_from) else ""), 12, WorkspaceStyle.MUTED)
			var raw: Variant = model.value(row, column)
			if model.field_type(column) in ["num", "float"]:
				var numeric := float(raw) if raw != null and is_finite(float(raw)) else 0.0
				var spin := _spin(_inspector_body, numeric, -1000000000, 1000000000, 1 if model.field_type(column) == "num" else 0.01)
				spin.value_changed.connect(func(value): model.set_value(row, column, value))
			else:
				var input := TextEdit.new(); input.custom_minimum_size.y = 140; input.text = str(raw); input.add_theme_font_size_override("font_size", 13)
				_inspector_body.add_child(input)
				input.focus_exited.connect(func():
					if model.value(row, column) != input.text: model.set_value(row, column, input.text)
				)
	var operations := HBoxContainer.new(); _inspector_body.add_child(operations)
	_button(operations, "Копия", Vector2(90, 30), func(): model.duplicate_rows(selection))
	_button(operations, "Удалить", Vector2(100, 30), _delete_selection)
	_button(_inspector_body, "Параметры набора", Vector2(246, 30), _show_overview)

func _delete_selection() -> void:
	if document == null or selection.is_empty(): return
	var rows := selection.duplicate(); selection.clear(); document.delete_rows(rows); _show_overview()

func _show_class_form() -> void:
	_clear_inspector(); _inspector_requested = true; _layout(); _label(_inspector_body, "Классы", 20)
	if document.kind() in ["car", "simulation"]:
		_label(_inspector_body, "Здесь группы определяются направлением поворота. Ответы остаются числами, а не названиями классов.", 13).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		return
	if document.studio().get("classes", []).is_empty() and document.row_count() > 0:
		_label(_inspector_body, "Этот набор содержит числовые ответы. Классы создаются в наборах классификации; при импорте CSV строковая метка последнего столбца автоматически становится классом.", 13).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		return
	var model = document
	var input := _line(_inspector_body, "Название нового класса")
	_button(_inspector_body, "Добавить класс", Vector2(246, 32), func():
		if model.add_class(input.text): _selected_group = input.text; _show_overview()
		else: _status.text = "Название должно быть непустым и уникальным"
	)
	for group in model.studio().get("classes", []):
		var rename := _line(_inspector_body, "Название класса", str(group))
		rename.text_submitted.connect(func(text): model.rename_class(str(group), text))
	_label(_inspector_body, "Enter — переименовать. Перетащите пример на другую группу, чтобы изменить метку.", 12, WorkspaceStyle.MUTED).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

func _show_batch_form(operation: String) -> void:
	_clear_inspector(); _inspector_requested = true; _layout()
	_label(_inspector_body, "Синтетика" if operation == "generate" else "Аугментация", 20)
	if document.kind() in ["text", "simulation"]:
		_label(_inspector_body, "Для физических симуляций используйте генератор во вкладке сцен. Текстовые примеры добавляются вручную или из файлов.", 13).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		return
	if operation == "generate" and document.kind() == "images" and not document.studio().get("rule_shapes", false):
		_label(_inspector_body, "Генератор фигур работает с кругами, квадратами и треугольниками в новом наборе изображений. Для ваших изображений используйте аугментацию: метки сохранятся.", 13).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		return
	var model = document
	var rule := "Положение и направление машинки → поворот к цели и скорость" if model.kind() == "car" else "Фигуры с правильными метками: круг, квадрат, треугольник" if model.kind() == "images" else "Числовые кластеры: отдельный центр для каждого класса"
	if model.kind() == "numeric" and model.studio().get("classes", []).is_empty(): rule = "Числовая зависимость: ответ k = sin(k·x) + 0.5·y"
	if operation == "augment": rule = "Небольшие сдвиги и шум с сохранением метки" if model.kind() == "images" else "Зеркальное состояние и обратный поворот" if model.kind() == "car" else "Небольшой шум только во входных признаках"
	_label(_inspector_body, rule, 13, WorkspaceStyle.MUTED).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label(_inspector_body, "Новых примеров" if operation == "generate" else "Вариаций на пример", 13)
	var count := _spin(_inspector_body, 100 if operation == "generate" else 1, 1, 10000 if operation == "generate" else 20)
	_label(_inspector_body, "Зерно — одинаковый результат при повторе", 12, WorkspaceStyle.MUTED).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var seed_field := _spin(_inspector_body, 42, 0, 999999)
	if operation == "augment": _label(_inspector_body, "Выбранных: %d. Без выделения — весь набор." % selection.size(), 12).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_button(_inspector_body, "Создать примеры", Vector2(246, 34), func():
		var added: int = model.generate(int(count.value), int(seed_field.value)) if operation == "generate" else model.augment(selection, int(count.value), int(seed_field.value))
		_status.text = "Добавлено %d примеров. Отмена доступна в верхней панели." % added
		_show_overview()
	)

func _show_schema() -> void:
	if document == null: return
	var model = document
	_clear_inspector(); _inspector_requested = true; _layout()
	_label(_inspector_body, "Поля и ответы", 20)
	_label(_inspector_body, "Входные признаки", 13, WorkspaceStyle.MUTED)
	for column in int(model.data.outputs_from):
		var field := _line(_inspector_body, "Название поля", model.field_name(column))
		field.text_submitted.connect(func(text): model.rename_input(column, text))
	var name := _line(_inspector_body, "Например: температура")
	_button(_inspector_body, "Добавить числовое поле", Vector2(246, 30), func():
		if model.add_input(name.text): _show_schema()
		else: _status.text = "Укажите уникальное название поля"
	)
	_label(_inspector_body, "Enter — переименовать поле. Новое поле появится у всех примеров.", 12, WorkspaceStyle.MUTED).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if model.kind() == "numeric" and not model.studio().get("classes", []).is_empty():
		_label(_inspector_body, "Сейчас ответ — класс. Для числовой задачи можно заменить метку её номером; действие можно отменить.", 12).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_button(_inspector_body, "Сделать ответ числом", Vector2(246, 30), func(): model.numeric_answers(); _show_overview())
	_button(_inspector_body, "К параметрам набора", Vector2(246, 30), _show_overview)

func _resize_images(width: int, height: int) -> void:
	document.begin_batch(); document.studio().image_width = width; document.studio().image_height = height
	for row in document.row_count():
		var old: Variant = document.value(row, 0)
		if old is Texture2D: document.data.arr[row][0] = document._cell(0, ImageTexture.create_from_image(document.fit_image(old.get_image())))
	document.end_batch(); _show_overview()

func _move_group(group: String, at: Vector2) -> void:
	if document == null: return
	var positions: Dictionary = document.studio().get_or_add("group_positions", {})
	positions[group] = [at.x, at.y]; _pending[str(document.data.name)] = true; _save_timer.start()

func _on_files_dropped(paths: PackedStringArray) -> void:
	if _layer != null and _layer.visible and glob.curr_window == "ds": import_paths(Array(paths))

func import_paths(paths: Array) -> void:
	if _busy: return
	_busy = true; _cancel_requested = false; _staged.clear(); _csv_previews.clear(); _clear_inspector()
	_inspector_requested = true; _layout(); _label(_inspector_body, "Импорт данных", 20)
	var progress := _label(_inspector_body, "Поиск файлов…", 13)
	_button(_inspector_body, "Отмена импорта", Vector2(246, 30), func(): _cancel_requested = true)
	await get_tree().process_frame
	var report := IO.scan_paths(paths)
	var errors: Array = report.errors
	if not report.images.is_empty():
		var model = Document.new(); model.create("Изображения из папки", "images")
		model.data.col_names = ["Изображение:image"]; model.studio().classes = []
		for entry in report.images:
			if not model.studio().classes.has(entry["class"]): model.add_class(str(entry["class"]))
		var index := 0
		for entry in report.images:
			if _cancel_requested: break
			var image := Image.load_from_file(entry.path)
			if image == null: errors.append("Не читается: " + str(entry.path).get_file())
			else: model.import_image(image, str(entry["class"]))
			index += 1
			if index % 16 == 0: progress.text = "Изображения: %d / %d" % [index, report.images.size()]; await get_tree().process_frame
		model.refresh_cache()
		if model.row_count() > 0: _staged.append(model)
	for entry in report.tables:
		if _cancel_requested: break
		progress.text = str(entry.path).get_file(); await get_tree().process_frame
		var result: Dictionary = IO.read_table(str(entry.path))
		if str(entry.path).get_extension().to_lower() in ["csv", "tsv"]:
			var preview := {"path": str(entry.path), "options": {"header": "auto", "delimiter": "auto"}, "result": result, "model": null}
			if result.has("dataset"):
				var csv_model = Document.new(); csv_model.attach(result.dataset)
				preview.model = csv_model; _staged.append(csv_model)
			_csv_previews.append(preview)
			continue
		if result.has("error"): errors.append(str(entry.path).get_file() + ": " + str(result.error)); continue
		var model = Document.new(); model.attach(result.dataset); _staged.append(model)
		errors.append_array(result.get("errors", []))
	if not report.texts.is_empty() and not _cancel_requested:
		var model = Document.new(); model.create("Тексты из папки", "text")
		model.data.col_names = ["Текст:text"]; model.studio().classes = []
		for entry in report.texts:
			if not model.studio().classes.has(entry["class"]): model.add_class(str(entry["class"]))
		for entry in report.texts:
			var file := FileAccess.open(str(entry.path), FileAccess.READ)
			if file == null or file.get_length() > 1024 * 1024: errors.append("Текст не читается или больше 1 МБ: " + str(entry.path).get_file()); continue
			var raw: Array = [file.get_as_text()]
			for group in model.studio().classes: raw.append(1 if group == entry["class"] else 0)
			model._append(raw)
		model.refresh_cache()
		if model.row_count() > 0: _staged.append(model)
	_busy = false
	if _cancel_requested:
		_staged.clear(); _csv_previews.clear(); _clear_inspector()
		_label(_inspector_body, "Импорт отменён. Данные не изменены.", 13).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		return
	_import_errors = errors; _import_report = report
	_show_import_preview()

func _show_import_preview(focus_path := "", focus_option := "") -> void:
	_clear_inspector()
	var restore_focus: Control
	_label(_inspector_body, "Предпросмотр импорта", 20)
	var errors: Array = _import_errors.duplicate()
	for entry in _csv_previews:
		_label(_inspector_body, str(entry.path).get_file(), 14).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_label(_inspector_body, "Первая строка", 12, WorkspaceStyle.MUTED)
		var header := OptionButton.new()
		header.focus_mode = Control.FOCUS_ALL
		header.fit_to_longest_item = false; header.custom_minimum_size = Vector2(220, 36)
		for caption in ["Определить автоматически", "Названия полей (заголовок)", "Данные (без заголовка)"]: header.add_item(caption)
		var header_modes := ["auto", "present", "absent"]
		header.select(header_modes.find(str(entry.options.header)))
		_inspector_body.add_child(header)
		if str(entry.path) == focus_path and focus_option == "header": restore_focus = header
		header.item_selected.connect(func(index): _set_csv_option(entry, "header", header_modes[index]))
		_label(_inspector_body, "Разделитель", 12, WorkspaceStyle.MUTED)
		var delimiter := OptionButton.new()
		delimiter.focus_mode = Control.FOCUS_ALL
		delimiter.fit_to_longest_item = false; delimiter.custom_minimum_size = Vector2(220, 36)
		for caption in ["Автоматически", "Запятая ,", "Точка с запятой ;", "Табуляция", "Вертикальная черта |"]: delimiter.add_item(caption)
		var delimiters := ["auto", ",", ";", "\t", "|"]
		delimiter.select(delimiters.find(str(entry.options.delimiter)))
		_inspector_body.add_child(delimiter)
		if str(entry.path) == focus_path and focus_option == "delimiter": restore_focus = delimiter
		delimiter.item_selected.connect(func(index): _set_csv_option(entry, "delimiter", delimiters[index]))
		var result: Dictionary = entry.result
		if result.has("error"): errors.append(str(entry.path).get_file() + ": " + str(result.error))
		else:
			var csv: Dictionary = result.get("csv", {})
			var first := " · ".join(PackedStringArray(csv.get("first_row", [])))
			_label(_inspector_body, "В файле: " + first, 12, WorkspaceStyle.MUTED).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			if bool(csv.get("header_ambiguous", false)) and str(entry.options.header) == "auto":
				_label(_inspector_body, "Неясно, содержит ли первая строка данные. Выберите её назначение выше.", 12, Color("9b5c10")).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			errors.append_array(result.get("errors", []))
	for model in _staged:
		_label(_inspector_body, "%s\n%d примеров · %d полей" % [model.data.name, model.row_count(), model.column_count()], 13).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var fields: Array[String] = []
		for column in mini(model.column_count(), 6): fields.append(model.field_name(column))
		_label(_inspector_body, "Поля: " + ", ".join(fields) + ("…" if model.column_count() > 6 else ""), 12, WorkspaceStyle.MUTED).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label(_inspector_body, "Пропущено файлов: %d · ошибок: %d" % [_import_report.get("ignored", []).size(), errors.size()], 12, Color("9b5c10"))
	for error in errors.slice(0, 5): _label(_inspector_body, str(error), 12, Color("9b5c10")).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if _import_report.get("limited", false): _label(_inspector_body, "Найдено больше 20 000 файлов. Импортируйте следующую папку отдельно.", 12, Color("9b5c10")).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if not _import_report.get("images", []).is_empty():
		_label(_inspector_body, "Подпапки становятся классами. Изображения растягиваются до 28 × 28 и преобразуются в серые.", 12, WorkspaceStyle.MUTED).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if not _staged.is_empty():
		var apply := _button(_inspector_body, "Добавить в мастерскую", Vector2(246, 34), _apply_import)
		apply.disabled = _csv_needs_header_choice()
	_button(_inspector_body, "Не добавлять", Vector2(246, 30), func(): _staged.clear(); _csv_previews.clear(); _show_overview())
	if restore_focus != null: restore_focus.grab_focus.call_deferred()

func _set_csv_option(entry: Dictionary, key: String, value: String) -> void:
	entry.options[key] = value
	if entry.model != null: _staged.erase(entry.model)
	entry.model = null
	entry.result = IO.read_table(str(entry.path), entry.options)
	if entry.result.has("dataset"):
		var model = Document.new(); model.attach(entry.result.dataset)
		entry.model = model; _staged.append(model)
	_show_import_preview.call_deferred(str(entry.path), key)

func _csv_needs_header_choice() -> bool:
	for entry in _csv_previews:
		if entry.model != null and str(entry.options.header) == "auto" and bool(entry.result.get("csv", {}).get("header_ambiguous", false)): return true
	return false

func _apply_import() -> void:
	if _csv_needs_header_choice():
		_status.text = "Сначала укажите, является ли первая строка CSV заголовком."
		return
	var ready := _staged.duplicate(); _staged.clear(); _csv_previews.clear()
	for model in ready: _register(model)
	_status.text = "Импортировано наборов: %d" % ready.size()

func _export_file(path: String) -> void:
	if document == null: return
	var error := IO.export_file(document, path)
	_status.text = "Набор экспортирован: " + path.get_file() if error == OK else "Не удалось экспортировать: " + error_string(error)

func _unhandled_key_input(event: InputEvent) -> void:
	if not _layer.visible or not event is InputEventKey or not event.pressed or event.echo: return
	var focused := get_viewport().gui_get_focus_owner()
	if focused is LineEdit or focused is TextEdit: return
	if event.keycode == KEY_DELETE: _delete_selection(); get_viewport().set_input_as_handled()
	elif (event.ctrl_pressed or event.meta_pressed) and event.keycode == KEY_Z and document != null:
		if event.shift_pressed: redo()
		else: undo()
		get_viewport().set_input_as_handled()
	elif (event.ctrl_pressed or event.meta_pressed) and event.keycode == KEY_Y and document != null: redo(); get_viewport().set_input_as_handled()
