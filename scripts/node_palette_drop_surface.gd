extends Control
class_name NodePaletteDropSurface

const NodePaletteCatalog = preload("res://scripts/node_palette_catalog.gd")
const WorkspaceGeometry = preload("res://scripts/claude_workspace_geometry.gd")

signal node_type_dropped(type_id: StringName, screen_position: Vector2)

var panel_width := 248.0
var top_inset := 52.0
var _active := false


func configure(new_panel_width: float, new_top_inset: float) -> void:
	panel_width = new_panel_width
	top_inset = new_top_inset


func set_drag_active(value: bool) -> void:
	_active = value
	mouse_filter = Control.MOUSE_FILTER_STOP if value else Control.MOUSE_FILTER_IGNORE


func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	if not _active:
		return false
	var type_id := NodePaletteCatalog.drag_type(data, graphs.graph_types.keys())
	var occupied_begin := Vector2(maxf(panel_width, glob.space_begin.x), maxf(top_inset, glob.space_begin.y))
	var canvas := WorkspaceGeometry.graph_rect(size, occupied_begin, glob.space_end)
	return not type_id.is_empty() and canvas.has_point(at_position)


func _drop_data(at_position: Vector2, data: Variant) -> void:
	var type_id := NodePaletteCatalog.drag_type(data, graphs.graph_types.keys())
	if type_id.is_empty():
		return
	node_type_dropped.emit(type_id, at_position)
