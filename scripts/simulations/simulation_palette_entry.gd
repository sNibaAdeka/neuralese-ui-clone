class_name SimulationPaletteEntry
extends Button

const PerformanceProbe = preload("res://scripts/simulations/simulation_performance_probe.gd")

var _definition: Dictionary = {}


func configure(definition: Dictionary) -> void:
	_definition = definition.duplicate(true)
	# Text uses the stylebox's fixed left inset, so it never overlaps the drawn
	# icon when the font or translated label changes.
	text = str(_definition.get("label", "Object"))
	queue_redraw()


func _get_drag_data(_at_position: Vector2) -> Variant:
	var type_id := StringName(get_meta("type_id", &""))
	if type_id.is_empty():
		return null
	var preview := Label.new()
	preview.text = "  %s  " % str(_definition.get("label", "Object"))
	preview.modulate = Color(1.0, 1.0, 1.0, 0.9)
	preview.add_theme_font_size_override("font_size", 14)
	set_drag_preview(preview)
	return {"simulation_type_id": str(type_id)}


func _draw() -> void:
	var perf_token: int = PerformanceProbe.begin_scope(&"ui.palette_entry_draw")
	_profiled_draw()
	PerformanceProbe.end_scope(&"ui.palette_entry_draw", perf_token)


func _profiled_draw() -> void:
	if _definition.is_empty():
		return
	var color: Color = _definition.get("color", Color.WHITE)
	var center := Vector2(size.x * 0.5, 24.0)
	var kind := StringName(get_meta("type_id", &""))
	if kind in [&"car", &"rover"]:
		var body := Rect2(center - Vector2(21, 7), Vector2(42, 14))
		draw_rect(body, Color(color, 0.4))
		draw_rect(body, color.darkened(0.25), false, 1.5)
		for x in [-13, 13]:
			draw_circle(center + Vector2(x, 9), 5, color.darkened(0.4))
		return
	if kind == &"flying_agent":
		draw_line(center - Vector2(18, 0), center + Vector2(18, 0), color, 3)
		for x in [-18, 18]: draw_arc(center + Vector2(x, 0), 8, 0, TAU, 24, color.darkened(0.2), 2)
		draw_circle(center, 6, color)
		return
	var shape_kind := str(_definition.get("shape_kind", "rectangle"))
	match shape_kind:
		"circle":
			draw_circle(center, 12.0, Color(color, 0.13))
			draw_arc(center, 12.0, 0.0, TAU, 18, color.darkened(0.12), 1.25)
		"slope":
			var points := PackedVector2Array([
				center + Vector2(-7.0, 12.0),
				center + Vector2(7.0, 12.0),
				center + Vector2(7.0, -12.0),
			])
			draw_colored_polygon(points, Color(color, 0.13))
			draw_polyline(points, color.darkened(0.12), 1.25)
		_:
			var icon_rect := Rect2(center - Vector2(20.0, 10.0), Vector2(40.0, 20.0))
			draw_rect(icon_rect, Color(color, 0.12))
			draw_rect(icon_rect, color.darkened(0.12), false, 1.25)
