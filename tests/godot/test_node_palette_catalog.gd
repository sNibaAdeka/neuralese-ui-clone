extends SceneTree

const NodePaletteCatalog = preload("res://scripts/node_palette_catalog.gd")
const GraphCreationCatalog = preload("res://scripts/graph_creation_catalog.gd")

var failures: Array[String] = []


func _initialize() -> void:
	_test_icon_paths_are_derived_from_type_ids()
	_test_graph_creation_catalog_matches_add_graph_rules()
	_test_entries_follow_the_canonical_add_graph_order()
	_test_entries_are_filtered_by_title_and_type_id()
	_test_drag_payload_validation()
	_test_workspace_bounds()
	_test_graph_creation_api_rejects_unknown_types()

	if failures.is_empty():
		print("PASS test_node_palette_catalog: 7 cases")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func _test_icon_paths_are_derived_from_type_ids() -> void:
	_expect_equal(
		NodePaletteCatalog.icon_filename(&"input_1d"),
		"IconInput1d.png",
		"preview generator and palette must share one filename convention"
	)
	_expect_equal(
		NodePaletteCatalog.icon_path(&"input_1d"),
		"res://node_icons/en/IconInput1d.png",
		"snake-case type id must use the existing PascalCase icon convention"
	)
	_expect_equal(
		NodePaletteCatalog.icon_path(&"future_graph"),
		"res://node_icons/en/IconFutureGraph.png",
		"new graph types must not require an icon mapping"
	)

	for language in ["en", "ru", "kz"]:
		_expect_equal(
			NodePaletteCatalog.icon_path(&"input_1d", language),
			"res://node_icons/%s/IconInput1d.png" % language,
			"icon paths must use the requested language without reading app globals"
		)


func _test_graph_creation_catalog_matches_add_graph_rules() -> void:
	var definitions: Array[Dictionary] = [
		{"name": &"layer"},
		{"name": &"test_node"},
		{"name": &"input"},
		{"name": &"future_allowed"},
		{"name": &"dropout"},
	]
	var ordered := GraphCreationCatalog.ordered_definitions(
		definitions,
		[&"input", &"layer", &"dropout", &"future_allowed"],
		[&"dropout"],
		[[&"layer", &"input"]],
		true
	)
	_expect_equal(
		GraphCreationCatalog.type_ids(ordered),
		[&"layer", &"future_allowed"],
		"catalog must apply Add Graph allowlist, skip, input suppression, groups, and fallback order"
	)


func _test_entries_follow_the_canonical_add_graph_order() -> void:
	var definitions: Array[Dictionary] = [
		{
			"name": &"layer",
			"title": "Dense Layer",
			"title_ru": "Плотный слой",
			"title_kz": "Тығыз қабат",
			"outline_color": Color("65d8aa"),
		},
		{
			"name": &"hidden_node",
			"title": "Hidden",
			"title_ru": "Скрытый",
			"title_kz": "Жасырын",
			"outline_color": Color.WHITE,
		},
		{
			"name": &"future_graph",
			"title": "Future Graph",
			"title_ru": "Новая нода",
			"title_kz": "Жаңа нод",
			"outline_color": Color("6aa7ff"),
		},
	]
	var entries: Array[Dictionary] = NodePaletteCatalog.build_entries(
		definitions,
		[&"layer"],
		[&"hidden_node"],
		"ru"
	)

	_expect_equal(entries.size(), 1, "types outside the Add Graph order must be omitted")
	_expect_equal(entries[0].type_id, &"layer", "preferred type must be first")
	_expect_equal(entries[0].title, "Плотный слой", "active language title must be selected")
	_expect_equal(
		entries[0].icon_path,
		"res://node_icons/ru/IconLayer.png",
		"entry icon must use the same explicit language as its title"
	)


func _test_entries_are_filtered_by_title_and_type_id() -> void:
	var entries: Array[Dictionary] = [
		{"type_id": &"layer", "title": "Dense Layer"},
		{"type_id": &"input_1d", "title": "Feature Input"},
	]
	_expect_equal(
		NodePaletteCatalog.filter_entries(entries, "dense").map(func(entry): return entry.type_id),
		[&"layer"],
		"search must match localized display titles case-insensitively"
	)
	_expect_equal(
		NodePaletteCatalog.filter_entries(entries, "input_1").map(func(entry): return entry.type_id),
		[&"input_1d"],
		"search must also match stable type ids"
	)
	_expect_equal(
		NodePaletteCatalog.filter_entries(entries, "  ").size(),
		2,
		"blank search must preserve the full generated catalog"
	)


func _test_drag_payload_validation() -> void:
	var payload := NodePaletteCatalog.drag_payload(&"layer")
	_expect_equal(
		NodePaletteCatalog.drag_type(payload, [&"layer", &"input"]),
		&"layer",
		"known palette payload must resolve its type"
	)
	_expect_equal(
		NodePaletteCatalog.drag_type(payload, [&"input"]),
		StringName(),
		"unknown type must be rejected"
	)
	_expect_equal(
		NodePaletteCatalog.drag_type({"type_id": &"layer"}, [&"layer"]),
		StringName(),
		"foreign dictionary must not be accepted as a palette drag"
	)


func _test_workspace_bounds() -> void:
	var viewport_size := Vector2(1280, 720)
	_expect_equal(
		NodePaletteCatalog.is_workspace_drop(Vector2(400, 300), viewport_size, 240.0, 52.0),
		true,
		"graph workspace position must be accepted"
	)
	_expect_equal(
		NodePaletteCatalog.is_workspace_drop(Vector2(120, 300), viewport_size, 240.0, 52.0),
		false,
		"palette position must be rejected"
	)
	_expect_equal(
		NodePaletteCatalog.is_workspace_drop(Vector2(400, 20), viewport_size, 240.0, 52.0),
		false,
		"top bar position must be rejected"
	)


func _test_graph_creation_api_rejects_unknown_types() -> void:
	var graph_manager := root.get_node_or_null("graphs")
	_expect_equal(graph_manager != null, true, "graph manager autoload must exist")
	if graph_manager == null:
		return
	_expect_equal(
		graph_manager.has_method("create_graph_at_screen_position"),
		true,
		"graph manager must expose the palette creation API"
	)
	if graph_manager.has_method("create_graph_at_screen_position"):
		_expect_equal(
			graph_manager.create_graph_at_screen_position(&"missing_node_type", Vector2(400, 300)),
			null,
			"unknown drag type must not create a graph"
		)


func _expect_equal(actual: Variant, expected: Variant, label: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [label, str(expected), str(actual)])
