class_name SimulationPalette
extends PanelContainer

const ClaudeDesign = preload("res://scripts/claude_design_theme.gd")
const ObjectCatalog = preload("res://scripts/simulations/simulation_object_catalog.gd")
const PaletteEntryScript = preload("res://scripts/simulations/simulation_palette_entry.gd")
const NodePaletteStyle = preload("res://scripts/node_palette.gd")
const ValidInputScript = preload("res://scripts/validate_line.gd")
const SearchTheme = preload("res://resources/theme_headers.tres")
const PaletteTitleFont = preload("res://game_assets/fonts/GolosText[wght].ttf")

signal object_requested(type_id: StringName)

var _search: ValidInput
var _entries: Array[Control] = []
@onready var _background: ColorRect = $Background


func _enter_tree() -> void:
	set_meta("claude_design_owned", true)

func _ready() -> void:
	theme = ClaudeDesign.create_theme()
	_reuse_blur_background()
	_reuse_blur_background.call_deferred()
	_build()
	add_theme_stylebox_override("panel", ClaudeDesign.box(ClaudeDesign.CANVAS, ClaudeDesign.LINE, 28, Vector2.ZERO))

func sync_perspective(current_mode: StringName) -> void:
	for button in _entries:
		var type_id = button.get_meta("type_id", &"")
		if type_id.is_empty(): continue
		var def = ObjectCatalog.definition(type_id)
		var obj_persp = StringName(def.get("compatible_perspective", &"any"))
		if obj_persp != &"any" and current_mode != &"auto" and obj_persp != current_mode:
			button.modulate.a = 0.4
		else:
			button.modulate.a = 1.0


func _reuse_blur_background() -> void:
	_background.hide()

func _process(_delta: float) -> void:
	if visible and get_global_rect().has_point(get_global_mouse_position()):
		glob.occupy(self, &"scroll")
	else:
		glob.un_occupy(self, &"scroll")


func displayed_groups() -> Dictionary:
	return ObjectCatalog.grouped_types()

func _build() -> void:
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 9)
	margin.add_theme_constant_override("margin_bottom", 10)
	add_child(margin)

	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 8)
	margin.add_child(layout)

	var header := HBoxContainer.new()
	header.custom_minimum_size.y = 39.0
	layout.add_child(header)
	var title := Label.new()
	title.text = "Objects"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_override("font", PaletteTitleFont)
	title.add_theme_font_size_override("font_size", 20)
	var title_loc := Loc.new()
	title_loc.auto = true
	title_loc.localizations_ru = {"objects": "Объекты"}
	title_loc.localizations_kz = {"objects": "Нысандар"}
	title.add_child(title_loc)
	header.add_child(title)

	_search = ValidInputScript.new()
	_search.theme = ClaudeDesign.create_theme()
	_search.placeholder_text = "Find an object..."
	_search.clear_button_enabled = true
	# Keep the search field full-width in the palette, while making its visual
	# scale 70% of the old control: 48 px → 34 px and 15 pt → 11 pt.
	_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search.custom_minimum_size.y = 44.0
	_search.add_theme_font_size_override("font_size", 14)

	_search.expand_to_text_length = false
	_search.resize_after = 175
	_search.monospaced = false
	var search_loc := Loc.new()
	search_loc.auto = true
	search_loc.localizations_ru = {"find an object": "Найти объект..."}
	search_loc.localizations_kz = {"find an object": "Нысанды табу..."}
	_search.add_child(search_loc)
	_search.text_changed.connect(_filter)
	var search_margin := MarginContainer.new()
	search_margin.add_theme_constant_override("margin_left", 2)
	search_margin.add_theme_constant_override("margin_right", 4)
	layout.add_child(search_margin)

	search_margin.add_child(_search)

	var scroll := ScrollContainer.new()
	scroll.name = "ObjectScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	layout.add_child(scroll)

	var groups := VBoxContainer.new()
	groups.name = "Groups"
	groups.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	groups.add_theme_constant_override("separation", 8)
	scroll.add_child(groups)

	var group_locs_ru := {
		"geometry": "Геометрия",
		"materials": "Материалы",
		"hazards": "Опасности",
		"dynamics": "Динамика",
		"agents": "Агенты",
	}
	var group_locs_kz := {
		"geometry": "Геометрия",
		"materials": "Материалдар",
		"hazards": "Қауіптер",
		"dynamics": "Динамика",
		"agents": "Агенттер",
	}

	for group_name in ObjectCatalog.grouped_types():
		var group := VBoxContainer.new()
		group.set_meta("group_name", group_name)
		group.add_theme_constant_override("separation", 8)
		groups.add_child(group)

		var group_header := HBoxContainer.new()
		group_header.add_theme_constant_override("separation", 7)
		group.add_child(group_header)
		var accent := ColorRect.new()
		var type_ids: Array = ObjectCatalog.grouped_types()[group_name]
		var group_color: Color = (
			ObjectCatalog.definition(type_ids[0]).get("color", Color.WHITE)
			if not type_ids.is_empty()
			else Color.WHITE
		)
		accent.color = group_color.lightened(0.12)
		accent.custom_minimum_size = Vector2(3.0, 14.0)
		accent.mouse_filter = Control.MOUSE_FILTER_IGNORE
		group_header.add_child(accent)
		var group_label := Label.new()
		group_label.text = group_name
		group_label.modulate = Color.WHITE
		group_label.add_theme_color_override("font_color", ClaudeDesign.INK_SECONDARY)
		group_label.add_theme_font_size_override("font_size", 14)
		var gloc := Loc.new()
		gloc.auto = true
		gloc.localizations_ru = {group_name.to_lower(): group_locs_ru.get(group_name.to_lower(), group_name)}
		gloc.localizations_kz = {group_name.to_lower(): group_locs_kz.get(group_name.to_lower(), group_name)}
		group_label.add_child(gloc)
		group_header.add_child(group_label)

		var tiles := GridContainer.new()
		tiles.columns = 2
		tiles.add_theme_constant_override("h_separation", 8)
		tiles.add_theme_constant_override("v_separation", 8)
		group.add_child(tiles)

		for type_id in type_ids:
			var definition: Dictionary = ObjectCatalog.definition(type_id)
			var button: Button = PaletteEntryScript.new()
			button.configure(definition)
			button.alignment = HORIZONTAL_ALIGNMENT_CENTER
			button.custom_minimum_size = Vector2(96.0, 78.0)
			button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			button.focus_mode = Control.FOCUS_ALL
			button.set_meta("type_id", type_id)
			button.set_meta("search_text", str(definition["label"]).to_lower())
			button.add_theme_font_size_override("font_size", 12)
			var normal := StyleBoxFlat.new()
			normal.bg_color = Color(group_color, 0.10)
			normal.set_corner_radius_all(12)
			normal.content_margin_left = 4
			normal.content_margin_right = 4
			normal.content_margin_top = 42
			normal.content_margin_bottom = 8
			var hover := normal.duplicate()
			hover.bg_color = Color(group_color, 0.20)
			button.add_theme_stylebox_override("normal", normal)
			button.add_theme_stylebox_override("hover", hover)
			button.add_theme_stylebox_override("pressed", hover)
			button.pressed.connect(_request.bind(type_id))

			button.set_meta("loc_prefix", "")
			button.set_meta("original_loc_text", str(definition["label"]))
			var bloc := Loc.new()
			bloc.auto = true
			var dlabel := str(definition["label"]).to_lower()

			var obj_locs_ru := {
				"block": "Блок", "circle": "Круг", "slope": "Склон",
				"ice": "Лёд", "sand": "Песок", "trampoline": "Батут", "finish": "Финиш",
				"spikes": "Шипы", "lava": "Лава", "water": "Вода",
				"crate": "Ящик", "ball": "Мяч",
				"car": "Машина", "side-view car": "Машина", "top-down rover": "Ровер", "flying agent": "Дрон",
			}
			var obj_locs_kz := {
				"block": "Блок", "circle": "Шеңбер", "slope": "Беткей",
				"ice": "Мұз", "sand": "Құм", "trampoline": "Батут", "finish": "Мәре",
				"spikes": "Тікенектер", "lava": "Лава", "water": "Су",
				"crate": "Жәшік", "ball": "Доп",
				"car": "Көлік", "side-view car": "Көлік", "top-down rover": "Ровер", "flying agent": "Дрон",
			}

			bloc.localizations_ru = {dlabel: obj_locs_ru.get(dlabel, str(definition["label"]))}
			bloc.localizations_kz = {dlabel: obj_locs_kz.get(dlabel, str(definition["label"]))}
			button.add_child(bloc)

			tiles.add_child(button)
			_entries.append(button)

		if group_name != ObjectCatalog.grouped_types().keys()[-1]:
			var divider := HSeparator.new()
			divider.modulate = Color.WHITE
			group.add_child(divider)


func _request(type_id: StringName) -> void:
	object_requested.emit(type_id)


func _filter(query: String) -> void:
	var normalized := query.strip_edges().to_lower()
	for entry in _entries:
		entry.visible = normalized.is_empty() or str(entry.get_meta("search_text", "")).contains(normalized)
