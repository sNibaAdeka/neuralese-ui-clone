extends CanvasLayer
class_name NodePalette

const NodePaletteCatalog = preload("res://scripts/node_palette_catalog.gd")
const GraphCreationCatalog = preload("res://scripts/graph_creation_catalog.gd")
const Design = preload("res://scripts/claude_design_theme.gd")
const WorkspaceGeometry = preload("res://scripts/claude_workspace_geometry.gd")
const VisualFamily = preload("res://scripts/node_visual_family.gd")
const DISPLAY_GROUPS: Array[StringName] = [&"input", &"layers", &"operations", &"shape", &"output", &"training", &"other"]
const PRIMARY_TYPES: Array[StringName] = [&"input_1d", &"input", &"dataset", &"conv2d", &"maxpool", &"layer", &"dropout", &"neuron", &"flatten", &"reshape2d", &"concat", &"softmax", &"classifier"]
const DOCK_HEIGHT := 160.0
const DOCK_BOTTOM_MARGIN := 16.0
const DOCK_CANVAS_GAP := 12.0
const SEARCH_HEIGHT := 68.0
const TUTORIAL_CARD_ANCHOR_GROUP := &"tutorial_node_palette_anchor"
const CATEGORY_TITLES := {
	&"inputs_outputs": {"ru": "Ввод и вывод", "en": "Inputs & outputs", "kz": "Кіріс және шығыс"},
	&"shape_output": {"ru": "Форма и вывод", "en": "Shape & output", "kz": "Пішін және шығыс"},
	&"layers": {"ru": "Слои", "en": "Layers", "kz": "Қабаттар"},
	&"data_context": {"ru": "Данные", "en": "Data", "kz": "Деректер"},
	&"training": {"ru": "Обучение и запуск", "en": "Training & execution", "kz": "Оқыту және іске қосу"},
	&"composition": {"ru": "Объединение", "en": "Composition", "kz": "Біріктіру"},
	&"other": {"ru": "Другие узлы", "en": "Other nodes", "kz": "Басқа түйіндер"},
}

@export var panel_width := 224.0
@export var top_inset := 52.0
@export var search_corner_radius := 6
@export var toggle_duration := 0.22
@export var hidden_types: Array[StringName] = []
@export var item_scene: PackedScene = preload("res://scenes/node_palette_item.tscn")

@onready var drop_surface: Control = $Root/DropSurface
@onready var panel: PanelContainer = $Root/Panel
@onready var panel_background: ColorRect = $Root/Panel/Background
@onready var items: HBoxContainer = $Root/Panel/Content/Scroll/Items
@onready var scroll: ScrollContainer = $Root/Panel/Content/Scroll
@onready var search: LineEdit = $Root/Panel/Content/Header/Controls/Search
@onready var collapse_button: Button = $Root/Panel/Content/Categories/Collapse
@onready var search_button: Button = $Root/Panel/Content/Categories/SearchToggle
@onready var actions: HBoxContainer = $Root/Panel/Content/Categories
@onready var category_selector: OptionButton = $Root/Panel/Content/Categories/Category
@onready var search_header: Control = $Root/Panel/Content/Header
@onready var reopen_button: Button = $Root/Reopen

var _entries: Array[Dictionary] = []
var _unavailable_entries: Array[Dictionary] = []
var _collapsed := false
var _toggle_tween: Tween = null
var _lesson_header: Control = null
var _compact := false
var _last_viewport_width := -1.0
var _last_reserved_top := -1.0
var _last_workspace_right := -1.0
var _last_viewport_height := -1.0
var _search_open := false
var _rendered_language := ""
var _selected_category: StringName = &"input"


func _enter_tree() -> void:
	set_meta("claude_design_owned", true)


func _ready() -> void:
	add_to_group(TUTORIAL_CARD_ANCHOR_GROUP)
	$Root.set_meta("claude_design_owned", true)
	$Root.set_meta("claude_styled", true)
	$Root.theme = Design.create_theme()
	panel.custom_minimum_size.x = 0.0
	set_collapsed(false, false)
	reuse_project_styles()
	reuse_project_styles.call_deferred()
	drop_surface.node_type_dropped.connect(_on_node_type_dropped)
	search.text_changed.connect(_on_search_changed)
	collapse_button.pressed.connect(set_collapsed.bind(true))
	search_button.pressed.connect(_toggle_search)
	category_selector.item_selected.connect(_on_category_selected)
	_refresh_category_selector()
	reopen_button.pressed.connect(set_collapsed.bind(false))
	panel.mouse_entered.connect(_occupy_palette_input.bind(panel))
	panel.mouse_exited.connect(_release_palette_input.bind(panel))
	reopen_button.mouse_entered.connect(_occupy_palette_input.bind(reopen_button))
	reopen_button.mouse_exited.connect(_release_palette_input.bind(reopen_button))
	get_viewport().size_changed.connect(_on_viewport_size_changed)
	_on_viewport_size_changed()
	_connect_tutorial_progress_panel()
	_connect_tutorial_progress_panel.call_deferred()
	if not glob.language_changed.is_connected(rebuild):
		glob.language_changed.connect(rebuild)

	if not glob.project_opened.is_connected(rebuild):
		glob.project_opened.connect(rebuild)
	if not glob.project_opening.is_connected(rebuild):
		glob.project_opening.connect(rebuild)
	if not graphs.node_added.is_connected(_on_graph_changed):
		graphs.node_added.connect(_on_graph_changed)
	if not graphs.model_updated.is_connected(_on_model_updated):
		graphs.model_updated.connect(_on_model_updated)
	if is_instance_valid(graphs.storage) and not graphs.storage.child_exiting_tree.is_connected(_on_graph_removed):
		graphs.storage.child_exiting_tree.connect(_on_graph_removed)
	rebuild()


func rebuild(...args) -> void:
	_refresh_category_selector()
	if is_instance_valid(reopen_button):
		reopen_button.text = "+ Узлы" if glob.get_lang() == "ru" else ("+ Түйіндер" if glob.get_lang() == "kz" else "+ Nodes")
		search_button.tooltip_text = "Все узлы и поиск" if glob.get_lang() == "ru" else "All nodes and search"
	search.placeholder_text = "Найти узел…" if glob.get_lang() == "ru" else ("Түйінді іздеу…" if glob.get_lang() == "kz" else "Find a node…")
	var available_ids := _add_graph_type_ids()
	var next_entries: Array[Dictionary] = NodePaletteCatalog.build_entries(
		graphs.graph_buttons,
		available_ids,
		hidden_types,
		glob.curr_lang
	)
	next_entries = categorized_entries(next_entries, graphs.graph_buttons, glob.curr_lang)
	var next_unavailable: Array[Dictionary] = []
	if not glob.multi_input and graphs.has_input():
		next_unavailable = unavailable_input_entries(graphs.graph_buttons, available_ids, hidden_types, glob.curr_lang)
	if glob.get_lang() == "ru":
		for entry in next_entries + next_unavailable:
			entry["title"] = preload("res://scripts/claude_node_labels.gd").title(str(entry.get("type_id", "")), str(entry.get("title", "")))
	if _rendered_language == glob.curr_lang and _entry_signature(next_entries + next_unavailable) == _entry_signature(_entries + _unavailable_entries):
		return

	var previous_scroll := scroll.scroll_horizontal
	_entries = next_entries
	_unavailable_entries = next_unavailable
	_render_entries(previous_scroll)


func _render_entries(previous_scroll: int = -1) -> void:
	for child in items.get_children():
		items.remove_child(child)
		child.queue_free()

	_rendered_language = glob.get_lang()
	var filtered := NodePaletteCatalog.filter_entries(_entries + _unavailable_entries, search.text)
	if not _search_open and search.text.strip_edges().is_empty():
		filtered = filtered.filter(func(entry: Dictionary) -> bool: return display_category(entry) == _selected_category)
	filtered.sort_custom(_reference_order)
	for display_group in DISPLAY_GROUPS:
		var group_entries: Array[Dictionary] = []
		for entry in filtered:
			if display_category(entry) == display_group:
				group_entries.append(entry)
		if group_entries.is_empty():
			continue
		var group := VBoxContainer.new()
		group.set_meta("node_palette_display_category", display_group)
		group.add_theme_constant_override("separation", 2)
		items.add_child(group)
		if _search_open:
			var heading := Label.new()
			heading.text = display_category_title(display_group, _rendered_language)
			heading.add_theme_color_override("font_color", display_category_color(display_group).darkened(0.25))
			heading.add_theme_font_size_override("font_size", Design.CAPTION_FONT_SIZE)
			heading.mouse_filter = Control.MOUSE_FILTER_IGNORE
			group.add_child(heading)
		var cards := HBoxContainer.new()
		cards.name = "Cards"
		cards.add_theme_constant_override("separation", 0)
		group.add_child(cards)
		for entry in group_entries:
			var item: Control = item_scene.instantiate()
			item.setup(entry)
			item.drag_started.connect(_on_item_drag_started)
			item.drag_finished.connect(_on_item_drag_finished)
			item.activated.connect(_on_item_activated)
			cards.add_child(item)
	if filtered.is_empty():
		var empty := Label.new()
		var has_query := not search.text.strip_edges().is_empty()
		match _rendered_language:
			"ru": empty.text = "Узлы не найдены.\nПопробуйте другое название." if has_query else "Нет доступных узлов."
			"kz": empty.text = "Түйіндер табылмады.\nБасқа атауды енгізіңіз." if has_query else "Қолжетімді түйіндер жоқ."
			_: empty.text = "No nodes found.\nTry another name." if has_query else "No nodes available."
		empty.add_theme_color_override("font_color", Design.INK_SECONDARY)
		empty.add_theme_font_size_override("font_size", 13)
		empty.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		empty.mouse_filter = Control.MOUSE_FILTER_IGNORE
		items.add_child(empty)
		if has_query:
			var clear := Button.new()
			clear.name = "ClearSearch"
			clear.text = "Очистить поиск" if _rendered_language == "ru" else ("Іздеуді тазарту" if _rendered_language == "kz" else "Clear search")
			clear.custom_minimum_size.y = Design.CONTROL_MIN_HEIGHT
			clear.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			clear.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
			clear.pressed.connect(_clear_search)
			items.add_child(clear)
	_fit_thumbnail_slots()
	if previous_scroll >= 0:
		_restore_scroll_position.call_deferred(previous_scroll)


static func unavailable_input_entries(definitions: Array, available_ids: Array, hidden: Array, language: String) -> Array[Dictionary]:
	var candidates := NodePaletteCatalog.build_entries(definitions, [&"input_1d", &"input"], hidden, language)
	var unavailable: Array[Dictionary] = []
	for entry in candidates:
		if available_ids.has(entry.type_id):
			continue
		entry["disabled"] = true
		entry["disabled_reason"] = "В модели уже есть вход. Удалите его, чтобы добавить другой." if language == "ru" else ("Модельде кіріс бар. Басқасын қосу үшін оны жойыңыз." if language == "kz" else "This model already has an input. Remove it to add another.")
		unavailable.append(entry)
	return categorized_entries(unavailable, definitions, language)


static func _reference_order(a: Dictionary, b: Dictionary) -> bool:
	var a_index := PRIMARY_TYPES.find(StringName(a.get("type_id", "")))
	var b_index := PRIMARY_TYPES.find(StringName(b.get("type_id", "")))
	if a_index < 0:
		a_index = PRIMARY_TYPES.size()
	if b_index < 0:
		b_index = PRIMARY_TYPES.size()
	return a_index < b_index


func _fit_thumbnail_slots() -> void:
	if not is_instance_valid(items):
		return
	var cards: Array[Control] = []
	for group in items.get_children():
		var row := group.get_node_or_null("Cards")
		if row != null:
			for card in row.get_children():
				cards.append(card)
	if cards.is_empty():
		return
	var spare_per_card := 0.0
	if is_instance_valid(panel) and not _search_open:
		var usable := panel.size.x - 28.0 - maxf(0.0, items.get_child_count() - 1) * 10.0
		var minimum_sum := 0.0
		for card in cards:
			minimum_sum += card.minimum_slot_width()
		spare_per_card = maxf(0.0, floorf((usable - minimum_sum) / cards.size()))
	for card in cards:
		var minimum: float = card.minimum_slot_width()
		var width := maxf(minimum, 80.0) if _search_open else maxf(minimum, minf(80.0, minimum + spare_per_card))
		card.set_slot_width(width)


static func display_category(entry: Dictionary) -> StringName:
	match VisualFamily.family([entry.get("type_id", "")]):
		&"data": return &"input"
		&"layer": return &"layers"
		&"operation": return &"operations"
		&"shape": return &"shape"
		&"output": return &"output"
		&"training": return &"training"
	return &"other"


static func display_category_color(category: StringName) -> Color:
	match category:
		&"input": return Design.INPUT_WIRE
		&"layers": return Design.LAYER_WIRE
		&"operations": return Design.ACTIVATION_WIRE
		&"shape": return Design.SHAPE_WIRE
		&"output": return Design.OUTPUT_WIRE
		&"training": return Design.TRAINING_WIRE
	return Design.INK_MUTED


static func display_category_title(category: StringName, language: String) -> String:
	var titles := {
		&"input": {"ru": "Данные", "en": "Data", "kz": "Деректер"},
		&"operations": {"ru": "Операции", "en": "Operations", "kz": "Операциялар"},
		&"layers": {"ru": "Слои", "en": "Layers", "kz": "Қабаттар"},
		&"shape": {"ru": "Форма", "en": "Shape", "kz": "Пішін"},
		&"output": {"ru": "Вывод", "en": "Output", "kz": "Шығыс"},
		&"training": {"ru": "Обучение", "en": "Training", "kz": "Оқыту"},
		&"other": {"ru": "Другие узлы", "en": "Other nodes", "kz": "Басқа түйіндер"},
	}
	var localized: Dictionary = titles.get(category, titles[&"other"])
	return str(localized.get(language, localized["en"]))


static func categorized_entries(entries: Array[Dictionary], definitions: Array, language: String) -> Array[Dictionary]:
	# Availability and ordering have already been decided by Add Graph. Only
	# annotate those entries using the registry's real menu-section metadata.
	var categories := {}
	for definition in definitions:
		categories[StringName(definition.get("name", ""))] = StringName(definition.get("menu_section", &"other"))
	var result: Array[Dictionary] = []
	for entry in entries:
		var annotated := entry.duplicate()
		var category := StringName(categories.get(StringName(entry.get("type_id", "")), &"other"))
		annotated["category_id"] = category
		annotated["category_title"] = category_title(category, language)
		result.append(annotated)
	return result


static func category_title(category: StringName, language: String) -> String:
	var titles: Dictionary = CATEGORY_TITLES.get(category, CATEGORY_TITLES[&"other"])
	return str(titles.get(language, titles["en"]))


func _clear_search() -> void:
	search.text = ""
	_on_search_changed("")
	if search.is_inside_tree():
		search.grab_focus()


func entry_type_ids() -> Array[StringName]:
	var result: Array[StringName] = []
	for entry in _entries:
		result.append(StringName(entry.get("type_id", "")))
	return result


func _add_graph_type_ids() -> Array[StringName]:
	var add_graph := glob.base_node.get_node_or_null("WIN_GRAPH/menus/add_graph")
	if is_instance_valid(add_graph) and add_graph.has_method("ordered_creation_type_ids"):
		return add_graph.ordered_creation_type_ids()

	var ordered_definitions := GraphCreationCatalog.ordered_definitions(
		graphs.graph_buttons,
		[],
		[],
		[],
		not glob.multi_input and graphs.has_input()
	)
	return GraphCreationCatalog.type_ids(ordered_definitions)


static func _entry_signature(entries: Array[Dictionary]) -> Array:
	var signature: Array = []
	for entry in entries:
		signature.append([
			entry.get("type_id", StringName()),
			entry.get("title", ""),
			entry.get("icon_path", ""),
			entry.get("outline_color", Color.WHITE),
			entry.get("category_id", &"other"),
			entry.get("category_title", ""),
			entry.get("disabled", false),
			entry.get("disabled_reason", ""),
		])
	return signature


func _restore_scroll_position(value: int) -> void:
	await get_tree().process_frame
	if is_instance_valid(scroll):
		scroll.scroll_horizontal = value


static func toggle_offset(collapsed: bool, width: float) -> float:
	return width if collapsed else 0.0


static func palette_search_style(source: StyleBox, radius: int) -> StyleBox:
	var copied := source.duplicate() as StyleBox
	if copied is StyleBoxFlat:
		copied.corner_radius_top_left = radius
		copied.corner_radius_top_right = radius
		copied.corner_radius_bottom_right = radius
		copied.corner_radius_bottom_left = radius
	return copied


static func top_bar_bottom(top_bar: Control, fallback: float) -> float:
	if is_instance_valid(top_bar):
		return top_bar.get_global_rect().end.y
	return fallback


static func effective_top_inset(
	top_bar_inset: float,
	progress_panel_visible: bool,
	progress_panel_bottom: float
) -> float:
	return maxf(top_bar_inset, progress_panel_bottom) if progress_panel_visible else top_bar_inset


func get_reserved_bottom() -> float:
	if not visible:
		return 0.0
	if _collapsed:
		return DOCK_BOTTOM_MARGIN + 44.0
	return DOCK_BOTTOM_MARGIN + DOCK_CANVAS_GAP + DOCK_HEIGHT + (SEARCH_HEIGHT if _search_open else 0.0)


func _panel_height() -> float:
	return DOCK_HEIGHT + (SEARCH_HEIGHT if _search_open else 0.0)


func _sync_geometry(_preserve_position := false) -> void:
	if not is_instance_valid(panel):
		return
	var viewport_size := get_viewport().get_visible_rect().size
	var margin := WorkspaceGeometry.horizontal_margin(viewport_size.x)
	var right_edge := glob.space_end.x if glob.space_end.x > margin * 2.0 else viewport_size.x
	right_edge = minf(right_edge, viewport_size.x)
	var height := _panel_height()
	panel.position = Vector2(margin, viewport_size.y - DOCK_BOTTOM_MARGIN - height)
	panel.size = Vector2(maxf(160.0, right_edge - margin * 2.0), height)
	actions.visible = not _collapsed and visible
	reopen_button.position = Vector2(margin, viewport_size.y - DOCK_BOTTOM_MARGIN - 44.0)
	reopen_button.size = Vector2(150, 44)
	drop_surface.configure(0.0, glob.space_begin.y)
	_last_reserved_top = glob.space_begin.y
	_last_workspace_right = glob.space_end.x
	_last_viewport_height = viewport_size.y
	_fit_thumbnail_slots()


func _effective_width() -> float:
	return panel.size.x if is_instance_valid(panel) else panel_width


func _on_viewport_size_changed() -> void:
	_last_viewport_width = get_viewport().get_visible_rect().size.x
	_compact = _last_viewport_width < 670.0
	# Resizing never discards the user's explicit expanded/collapsed choice.
	_sync_geometry()


func _refresh_category_selector() -> void:
	if not is_instance_valid(category_selector):
		return
	category_selector.clear()
	for category in DISPLAY_GROUPS:
		if category == &"other":
			continue
		var icon := Design._icon("M12 5a7 7 0 1 0 0 14a7 7 0 0 0 0-14", display_category_color(category))
		category_selector.add_icon_item(icon, display_category_title(category, glob.get_lang()))
		if category == _selected_category:
			category_selector.select(category_selector.item_count - 1)
	category_selector.tooltip_text = "Группа узлов" if glob.get_lang() == "ru" else ("Түйіндер тобы" if glob.get_lang() == "kz" else "Node category")
	search_button.text = "Все узлы" if glob.get_lang() == "ru" else ("Барлық түйіндер" if glob.get_lang() == "kz" else "All nodes")
	search_button.icon = null
	search_button.set_pressed_no_signal(_search_open)


func _on_category_selected(index: int) -> void:
	_selected_category = DISPLAY_GROUPS[index]
	_search_open = false
	search_header.hide()
	search.text = ""
	_refresh_category_selector()
	_render_entries()
	scroll.scroll_horizontal = 0
	_sync_geometry()


func _toggle_search() -> void:
	_search_open = not _search_open
	_refresh_category_selector()
	search_header.visible = _search_open
	if _search_open:
		search.grab_focus()
		_render_entries()
	else:
		search.release_focus()
		search.text = ""
		_on_search_changed("")
	_sync_geometry()


func _connect_tutorial_progress_panel() -> void:
	if is_instance_valid(_lesson_header) or not is_instance_valid(glob.base_node):
		return
	var header := glob.base_node.get_node_or_null("fg/ColorRect/ColorRect") as Control
	if not is_instance_valid(header):
		return
	if not header.has_method("is_progress_panel_visible") or not header.has_method("get_progress_panel_bottom"):
		return
	_lesson_header = header
	if not _lesson_header.progress_panel_layout_changed.is_connected(_on_progress_panel_layout_changed):
		_lesson_header.progress_panel_layout_changed.connect(_on_progress_panel_layout_changed)
	_sync_geometry(true)


func _on_progress_panel_layout_changed(_visible: bool, _bottom: float) -> void:
	_sync_geometry(true)


func set_collapsed(value: bool, animated: bool = true) -> void:
	_collapsed = value
	if value:
		search.release_focus()
	if _toggle_tween != null:
		_toggle_tween.kill()
		_toggle_tween = null
	reopen_button.visible = value
	panel.visible = true
	actions.visible = not value
	_sync_geometry()
	_update_selection_blocker(get_viewport().get_mouse_position())
	var target_alpha := 0.0 if value else 1.0
	if not animated or not is_inside_tree():
		_apply_toggle_endpoint(value, 0.0, target_alpha)
		return
	_toggle_tween = create_tween()
	var easing := Tween.EASE_OUT if not value else Tween.EASE_IN
	_toggle_tween.tween_property(panel, "modulate:a", target_alpha, toggle_duration).set_trans(Tween.TRANS_CUBIC).set_ease(easing)
	_toggle_tween.tween_callback(_finish_toggle.bind(value, _toggle_tween))


func _finish_toggle(value: bool, tween: Tween) -> void:
	if tween != _toggle_tween:
		return
	_toggle_tween = null
	_apply_toggle_endpoint(value, 0.0, 0.0 if value else 1.0)


func _apply_toggle_endpoint(value: bool, _offset: float, target_alpha: float) -> void:
	panel.modulate.a = target_alpha
	panel.visible = not value
	actions.visible = not value
	reopen_button.visible = value
	_update_selection_blocker(get_viewport().get_mouse_position())


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion or event is InputEventMouseButton:
		_update_selection_blocker(event.position)


func _process(_delta: float) -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	if not is_equal_approx(_last_viewport_width, viewport_size.x):
		_on_viewport_size_changed()
	if not is_equal_approx(_last_reserved_top, glob.space_begin.y) or not is_equal_approx(_last_workspace_right, glob.space_end.x) or not is_equal_approx(_last_viewport_height, viewport_size.y):
		_sync_geometry(true)
	_update_selection_blocker(get_viewport().get_mouse_position())


## The dock occupies the bottom edge; tutorial cards no longer need a left inset.
func tutorial_card_anchor_x() -> float:
	return 0.0


func _exit_tree() -> void:
	if _toggle_tween != null:
		_toggle_tween.kill()
		_toggle_tween = null
	_release_palette_input(panel)
	_release_palette_input(reopen_button)


func _update_selection_blocker(pointer_position: Vector2) -> void:
	var blocker: Control = panel
	if _collapsed:
		blocker = reopen_button
	if visible and blocker.visible and blocker.get_global_rect().has_point(pointer_position):
		_occupy_palette_input(blocker)
	else:
		_release_palette_input(panel)
		_release_palette_input(reopen_button)


func _occupy_palette_input(control: Control) -> void:
	glob.occupy(control, &"menu_inside")
	glob.set_scroll_impossible(control)


func _release_palette_input(control: Control) -> void:
	if is_instance_valid(control):
		glob.un_occupy(control, &"menu_inside")
		glob.set_scroll_possible(control)


func reuse_project_styles() -> void:
	if not is_instance_valid(glob.base_node):
		return
	# Baked node thumbnails and the old dark blur belong to the previous theme.
	# Native controls share the Claude palette and retain the original drag API.
	panel_background.material = null
	panel_background.color = Color.TRANSPARENT
	var surface := Design.box(Design.CANVAS, Design.LINE, Design.CARD_RADIUS, Vector2(14, 8))
	surface.shadow_color = Color(0.10, 0.14, 0.24, 0.04)
	surface.shadow_size = 3
	panel.add_theme_stylebox_override("panel", surface)
	items.add_theme_constant_override("separation", 10)
	var bar := scroll.get_h_scroll_bar()
	bar.custom_minimum_size.y = 4
	for style_name in [&"scroll", &"scroll_focus", &"grabber", &"grabber_highlight", &"grabber_pressed"]:
		var color := Color(0.66, 0.69, 0.75, 0.28) if str(style_name).begins_with("grabber") else Color.TRANSPARENT
		var style := Design.box(color, Color.TRANSPARENT, 2, Vector2.ZERO, 0)
		style.content_margin_top = 2
		style.content_margin_bottom = 2
		bar.add_theme_stylebox_override(style_name, style)
	search.add_theme_font_size_override("font_size", 13)
	search.add_theme_color_override("font_color", Design.INK)
	search.add_theme_color_override("font_placeholder_color", Design.INK_MUTED)
	search.add_theme_color_override("caret_color", Design.PRIMARY)
	search.add_theme_stylebox_override("normal", Design.box(Design.FILL, Design.FILL, Design.CONTROL_RADIUS, Vector2(10, 8), 0))
	search.add_theme_stylebox_override("focus", Design.focus_box(Design.CONTROL_RADIUS))
	search.placeholder_text = "Найти узел…" if glob.get_lang() == "ru" else ("Түйінді іздеу…" if glob.get_lang() == "kz" else "Find a node…")
	_refresh_category_selector()
	for button in [collapse_button, reopen_button, search_button, category_selector]:
		button.add_theme_color_override("font_color", Design.INK_SECONDARY)
		button.add_theme_stylebox_override("normal", Design.box(Color.TRANSPARENT, Color.TRANSPARENT, Design.CONTROL_RADIUS, Vector2(8, 8), 0))
		button.add_theme_stylebox_override("hover", Design.box(Design.FILL, Design.LINE_STRONG, Design.CONTROL_RADIUS, Vector2(8, 8)))
		button.add_theme_stylebox_override("pressed", Design.box(Design.FILL_HOVER, Design.LINE_STRONG, Design.CONTROL_RADIUS, Vector2(8, 8)))
		button.add_theme_stylebox_override("focus", Design.focus_box(Design.CONTROL_RADIUS))
	category_selector.add_theme_color_override("icon_normal_color", Color.WHITE)
	category_selector.add_theme_color_override("icon_hover_color", Color.WHITE)
	category_selector.add_theme_color_override("icon_pressed_color", Color.WHITE)
	category_selector.add_theme_font_size_override("font_size", Design.CAPTION_FONT_SIZE)
	search_button.add_theme_font_size_override("font_size", Design.CAPTION_FONT_SIZE)
	search_button.add_theme_stylebox_override("pressed", Design.box(Design.PRIMARY_SOFT, Design.PRIMARY, Design.CONTROL_RADIUS, Vector2(8, 8)))
	collapse_button.tooltip_text = "Скрыть узлы" if glob.get_lang() == "ru" else "Hide nodes"
	reopen_button.tooltip_text = "Добавить узел" if glob.get_lang() == "ru" else "Add a node"
	reopen_button.text = "+ Узлы" if glob.get_lang() == "ru" else ("+ Түйіндер" if glob.get_lang() == "kz" else "+ Nodes")
	search_button.tooltip_text = "Все узлы и поиск" if glob.get_lang() == "ru" else "All nodes and search"
	_sync_geometry(true)


static func apply_project_blur_background(target: ColorRect) -> bool:
	if not is_instance_valid(target):
		return false
	# Kept as the shared palette surface API for graph and simulation tools.
	# The light workspace uses opaque native surfaces, without shader buffers.
	target.material = null
	target.color = Design.CANVAS
	return true


func _copy_search_style(source: LineEdit) -> void:
	search.theme = source.theme
	for style_name in [&"normal", &"focus", &"read_only"]:
		var source_style := source.get_theme_stylebox(style_name)
		if source_style != null:
			search.add_theme_stylebox_override(
				style_name,
				palette_search_style(source_style, search_corner_radius)
			)

	for color_name in [
		&"font_color",
		&"font_placeholder_color",
		&"font_selected_color",
		&"caret_color",
		&"selection_color",
	]:
		if source.has_theme_color(color_name):
			search.add_theme_color_override(color_name, source.get_theme_color(color_name))

	if source.has_theme_font(&"font"):
		search.add_theme_font_override(&"font", source.get_theme_font(&"font"))
	var source_font_size := source.get_theme_font_size(&"font_size")
	var visual_font_size := maxi(12, roundi(source_font_size * absf(source.scale.x)))
	search.add_theme_font_size_override(&"font_size", visual_font_size)


func _on_search_changed(_query: String) -> void:
	_render_entries()
	scroll.scroll_horizontal = 0


func _on_item_drag_started(_type_id: StringName) -> void:
	drop_surface.set_drag_active(true)


func _on_item_drag_finished() -> void:
	drop_surface.set_drag_active.call_deferred(false)


func _on_node_type_dropped(type_id: StringName, screen_position: Vector2) -> void:
	drop_surface.set_drag_active(false)
	if not _creation_available(type_id):
		return
	graphs.create_graph_at_screen_position(type_id, screen_position)


func _creation_available(type_id: StringName) -> bool:
	return visible and not _collapsed and not hidden_types.has(type_id) and _add_graph_type_ids().has(type_id)


func _on_item_activated(type_id: StringName) -> void:
	if not _creation_available(type_id):
		return
	var bounds := WorkspaceGeometry.graph_rect(get_viewport().get_visible_rect().size, glob.space_begin, glob.space_end)
	if bounds.has_area():
		graphs.create_graph_at_screen_position(type_id, bounds.get_center())


func _on_graph_changed(_graph: Graph) -> void:
	rebuild.call_deferred()


func _on_model_updated(_model_name: String) -> void:
	rebuild.call_deferred()


func _on_graph_removed(_graph: Node) -> void:
	rebuild.call_deferred()
