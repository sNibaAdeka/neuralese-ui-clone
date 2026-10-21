extends SceneTree

const Catalog = preload("res://scripts/node_palette_catalog.gd")
const Creation = preload("res://scripts/graph_creation_catalog.gd")
const Registry = preload("res://scripts/generated/node_catalog.gd")

var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	# NodePalette references project autoloads. Compile it only after those
	# names are registered by the standalone SceneTree test bootstrap.
	await process_frame
	var palette_script: GDScript = load("res://scripts/node_palette.gd")
	_expect(palette_script != null, "Native palette script must load after autoload initialization")
	if palette_script == null:
		_finish()
		return
	var definitions := Registry.button_definitions()
	var ordered := Creation.type_ids(Creation.ordered_definitions(definitions, [], [], [], false))
	var entries := Catalog.build_entries(definitions, ordered, [], "ru")
	var annotated: Array[Dictionary] = palette_script.call("categorized_entries", entries, definitions, "ru")
	_expect(_type_ids(annotated) == ordered, "Categories must preserve the actual Add Graph order and availability")
	_expect(not entries[0].has("category_id"), "Presentation annotations must not mutate the catalog entries")
	for entry in annotated:
		var source: Dictionary = Registry.DEFINITIONS[entry.type_id]
		_expect(entry.category_id == source.menu_section, "Category must match real registry metadata: " + str(entry.type_id))
		_expect(entry.category_title != "Другие узлы", "All current registered categories must have readable Russian labels")
		_expect(Catalog.drag_type(Catalog.drag_payload(entry.type_id), ordered) == entry.type_id,
			"Categorization must preserve the real drag payload: " + str(entry.type_id))
	var without_inputs := Creation.type_ids(Creation.ordered_definitions(definitions, [], [], [], true))
	var limited: Array[Dictionary] = palette_script.call("categorized_entries", Catalog.build_entries(definitions, without_inputs, [], "ru"), definitions, "ru")
	_expect(_type_ids(limited) == without_inputs, "Categories must not reintroduce unavailable single-input node types")
	for language in ["en", "ru", "kz"]:
		for definition in definitions:
			_expect(not str(palette_script.call("category_title", definition.menu_section, language)).is_empty(), "Every available section must have a localized heading")
	var translated: Array[Dictionary] = palette_script.call("categorized_entries", entries, definitions, "en")
	_expect(palette_script.call("_entry_signature", annotated) != palette_script.call("_entry_signature", translated),
		"A heading language change must invalidate rendering even when node titles do not change")

	# Render real cards in a detached native scene: no app boot or project data
	# is needed to verify ordering, filtering and the real clear-search action.
	var palette = load("res://scenes/node_palette.tscn").instantiate()
	palette.items = palette.get_node("Root/Panel/Content/Scroll/Items")
	palette.scroll = palette.get_node("Root/Panel/Content/Scroll")
	palette.search = palette.get_node("Root/Panel/Content/Header/Controls/Search")
	palette._entries = annotated
	palette._render_entries()
	_expect(_rendered_ids(palette.items) == palette.PRIMARY_TYPES, "Main dock must follow the reference order for all 13 real primary node types")
	_expect(_rendered_categories(palette.items) == [&"input", &"layers", &"shape", &"output"], "Main dock must keep its four reference headings")
	palette._search_open = true
	palette._render_entries()
	_expect(_same_ids(_rendered_ids(palette.items), ordered), "All nodes view must include all and only the available real cards")
	_expect(_rendered_categories(palette.items) == [&"input", &"layers", &"shape", &"output", &"training"], "All nodes must expose the real training group")
	palette.search.text = "conv2d"
	palette._on_search_changed("conv2d")
	_expect(_rendered_ids(palette.items) == [&"conv2d"], "Search by stable id must keep the real matching node")
	_expect(_rendered_categories(palette.items) == [&"layers"], "Search must not leave empty category headings")
	palette.search.text = "no_matching_node_20261015"
	palette._on_search_changed(palette.search.text)
	_expect(_rendered_ids(palette.items).is_empty(), "Unmatched search must not display fabricated nodes")
	_expect(_rendered_categories(palette.items).is_empty(), "Unmatched search must not display empty categories")
	var clear := palette.items.get_node_or_null("ClearSearch") as Button
	_expect(clear != null and clear.pressed.is_connected(palette._clear_search), "Empty search must expose a connected Clear search action")
	if clear != null:
		clear.pressed.emit()
		_expect(palette.search.text.is_empty() and _same_ids(_rendered_ids(palette.items), ordered),
			"Clear search must restore all and only the available real cards")
	palette._entries.clear()
	palette._render_entries()
	_expect(palette.items.get_node_or_null("ClearSearch") == null, "Empty availability without a query must not offer a useless reset")
	var disabled_inputs: Array[Dictionary] = palette_script.unavailable_input_entries(definitions, without_inputs, [], "ru")
	_expect(_type_ids(disabled_inputs) == [&"input_1d", &"input"], "Single-input mode may show exactly the two registered input alternatives disabled")
	for entry in disabled_inputs:
		_expect(entry.disabled and not str(entry.disabled_reason).is_empty(), "Unavailable input must explain why it cannot be added")
	_expect(palette_script.unavailable_input_entries(definitions, without_inputs, [&"input", &"input_1d"], "ru").is_empty(), "Explicitly hidden input types must not reappear as disabled previews")
	var disabled_card = load("res://scenes/node_palette_item.tscn").instantiate()
	disabled_card.setup(disabled_inputs[0])
	root.add_child(disabled_card)
	var activation_count := [0]
	disabled_card.activated.connect(func(_id: StringName): activation_count[0] += 1)
	var activate := InputEventAction.new()
	activate.action = "ui_accept"
	activate.pressed = true
	disabled_card._gui_input(activate)
	_expect(activation_count[0] == 0 and disabled_card._get_drag_data(Vector2.ZERO) == null, "Disabled input preview must reject both keyboard creation and drag payload")
	_expect(disabled_card.tooltip_text.contains(disabled_inputs[0].disabled_reason), "Disabled preview must expose its actual availability explanation")
	disabled_card.queue_free()
	palette.free()
	await process_frame
	_finish()

func _finish() -> void:
	if failures.is_empty():
		print("PASS test_node_palette_categories")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)

func _type_ids(entries: Array[Dictionary]) -> Array[StringName]:
	var ids: Array[StringName] = []
	for entry in entries:
		ids.append(entry.type_id)
	return ids

func _rendered_ids(items: Control) -> Array[StringName]:
	var ids: Array[StringName] = []
	for group in items.get_children():
		var cards = group.get_node_or_null("Cards")
		if cards == null:
			continue
		for child in cards.get_children():
			if child is NodePaletteItem:
				ids.append(child.type_id)
	return ids

func _same_ids(actual: Array[StringName], expected: Array[StringName]) -> bool:
	var sorted_actual := actual.duplicate()
	var sorted_expected := expected.duplicate()
	sorted_actual.sort()
	sorted_expected.sort()
	return sorted_actual == sorted_expected

func _rendered_categories(items: Control) -> Array[StringName]:
	var categories: Array[StringName] = []
	for child in items.get_children():
		if child.has_meta("node_palette_display_category"):
			categories.append(child.get_meta("node_palette_display_category"))
	return categories

func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
