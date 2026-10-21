extends RefCounted
## Logical canvas bounds shared by camera framing and the visible background.

static func horizontal_margin(viewport_width: float) -> float:
	return 13.0 if viewport_width <= 860.0 else (21.0 if viewport_width <= 1100.0 else 34.0)

static func graph_rect(viewport_size: Vector2, occupied_begin: Vector2, occupied_end: Vector2) -> Rect2:
	if not viewport_size.is_finite() or not occupied_begin.is_finite() or not occupied_end.is_finite():
		return Rect2()
	var viewport := Rect2(Vector2.ZERO, viewport_size)
	var available := Rect2(occupied_begin, occupied_end - occupied_begin)
	if not viewport.has_area() or not available.has_area():
		return Rect2()
	var clipped := available.intersection(viewport)
	var inset := Vector2(horizontal_margin(viewport_size.x), 0.0)
	if clipped.size.x <= inset.x * 2.0 or clipped.size.y <= inset.y * 2.0:
		return Rect2()
	return Rect2(clipped.position + inset, clipped.size - inset * 2.0)
