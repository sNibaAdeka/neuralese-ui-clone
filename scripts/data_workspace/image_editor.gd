extends Control
## Inline sample editor; the dataset owns the pixel dimensions.
signal image_edited(image: Image)
var image: Image
var _texture: ImageTexture
var erase := false
var radius := 1
var _drawing := false
var _last := Vector2.ZERO

func setup(source: Image) -> void:
	image = source.duplicate()
	_texture = ImageTexture.create_from_image(image)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	mouse_default_cursor_shape = Control.CURSOR_CROSS
	queue_redraw()

func _rect() -> Rect2:
	if image == null: return Rect2()
	var factor: float = minf(size.x / image.get_width(), size.y / image.get_height())
	var dimensions := Vector2(image.get_width(), image.get_height()) * factor
	return Rect2((size - dimensions) * 0.5, dimensions)

func _pixel(at: Vector2) -> Vector2:
	var rect := _rect()
	return (at - rect.position) / rect.size * Vector2(image.get_width(), image.get_height())

func _stroke(at: Vector2) -> void:
	var steps := maxi(1, ceili(_last.distance_to(at)))
	for step in steps + 1:
		var point := _last.lerp(at, float(step) / steps)
		for y in range(-radius, radius + 1):
			for x in range(-radius, radius + 1):
				var pixel := Vector2i(point) + Vector2i(x, y)
				if x*x + y*y > radius*radius: continue
				if pixel.x >= 0 and pixel.y >= 0 and pixel.x < image.get_width() and pixel.y < image.get_height(): image.set_pixelv(pixel, Color.BLACK if erase else Color.WHITE)
	_last = at
	_texture.update(image)
	queue_redraw()

func _gui_input(event: InputEvent) -> void:
	if image == null: return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed and _rect().has_point(event.position):
			_drawing = true
			_last = _pixel(event.position)
			_stroke(_last)
		elif not event.pressed and _drawing:
			_drawing = false
			image_edited.emit(image.duplicate())
		accept_event()
	elif event is InputEventMouseMotion and _drawing:
		if not event.button_mask & MOUSE_BUTTON_MASK_LEFT:
			_drawing = false
			image_edited.emit(image.duplicate())
		else: _stroke(_pixel(event.position))
		accept_event()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("14171a"))
	if _texture != null: draw_texture_rect(_texture, _rect(), false)
