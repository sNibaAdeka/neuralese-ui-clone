extends RefCounted
class_name NodePaletteCatalog

const DRAG_KIND: StringName = &"neuralese_node_palette"


static func icon_path(type_id: StringName, language: String = "en") -> String:
	return "res://node_icons/%s/%s" % [language, icon_filename(type_id)]


static func icon_filename(type_id: StringName) -> String:
	return "Icon%s.png" % str(type_id).to_pascal_case()


static func build_entries(
	definitions: Array,
	preferred_order: Array,
	hidden_types: Array,
	language: String
) -> Array[Dictionary]:
	var definitions_by_name: Dictionary = {}
	for definition in definitions:
		var type_id := StringName(definition.get("name", ""))
		if not type_id.is_empty():
			definitions_by_name[type_id] = definition

	var hidden: Dictionary = {}
	for type_name in hidden_types:
		hidden[StringName(type_name)] = true

	var entries: Array[Dictionary] = []
	var added: Dictionary = {}
	for type_name in preferred_order:
		_append_entry(
			entries,
			added,
			definitions_by_name,
			StringName(type_name),
			hidden,
			language
		)
	return entries


static func filter_entries(entries: Array[Dictionary], query: String) -> Array[Dictionary]:
	var normalized_query := query.strip_edges().to_lower()
	if normalized_query.is_empty():
		return entries.duplicate()

	var filtered: Array[Dictionary] = []
	for entry in entries:
		var searchable := "%s %s" % [
			str(entry.get("title", "")),
			str(entry.get("type_id", "")),
		]
		if normalized_query in searchable.to_lower():
			filtered.append(entry)
	return filtered


static func drag_payload(type_id: StringName) -> Dictionary:
	return {
		"kind": DRAG_KIND,
		"type_id": type_id,
	}


static func drag_type(data: Variant, known_types: Array) -> StringName:
	if not data is Dictionary or data.get("kind") != DRAG_KIND:
		return StringName()
	var type_id := StringName(data.get("type_id", ""))
	if type_id.is_empty() or not known_types.has(type_id):
		return StringName()
	return type_id


static func is_workspace_drop(
	screen_position: Vector2,
	viewport_size: Vector2,
	panel_width: float,
	top_inset: float
) -> bool:
	return Rect2(
		Vector2(panel_width, top_inset),
		Vector2(maxf(0.0, viewport_size.x - panel_width), maxf(0.0, viewport_size.y - top_inset))
	).has_point(screen_position)


static func _append_entry(
	entries: Array[Dictionary],
	added: Dictionary,
	definitions_by_name: Dictionary,
	type_id: StringName,
	hidden: Dictionary,
	language: String
) -> void:
	if type_id.is_empty() or added.has(type_id) or hidden.has(type_id):
		return
	if not definitions_by_name.has(type_id):
		return

	var definition: Dictionary = definitions_by_name[type_id]
	entries.append({
		"type_id": type_id,
		"title": _localized_title(definition, language),
		"icon_path": icon_path(type_id, language),
		"outline_color": definition.get("outline_color", Color("6aa7ff")),
	})
	added[type_id] = true


static func _localized_title(definition: Dictionary, language: String) -> String:
	var localized_key := "title_%s" % language
	var localized := str(definition.get(localized_key, "")).strip_edges()
	if not localized.is_empty():
		return localized
	var fallback := str(definition.get("title", "")).strip_edges()
	if not fallback.is_empty():
		return fallback
	return str(definition.get("name", ""))
