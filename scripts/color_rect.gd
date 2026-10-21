extends ColorRect

@export var rect: TextureRect
@export var offset_mult: float = 1.0

func process(_delta: float) -> void:
	var cam: Camera2D = glob.cam
	if not is_instance_valid(cam):
		return

	var active_zoom := cam.zoom
	if is_zero_approx(active_zoom.x) or is_zero_approx(active_zoom.y):
		return

	# Only write on change: Camera2D/Control setters redraw even for identical values.
	var bg_cam: Camera2D = $"../../Camera2D"
	if bg_cam.position != cam.position:
		bg_cam.position = cam.position
	if bg_cam.zoom != active_zoom:
		bg_cam.zoom = active_zoom
	# NOTE: the SubViewport size is owned by sub_viewport.gd (tracks the parent viewport).
	# This used to also set `size = window_size + 20` here, which fought sub_viewport.gd:
	# the two writes alternated every frame, recreating the render target twice per frame,
	# and the final size at draw time was always sub_viewport.gd's anyway.
	var next_position := cam.get_screen_center_position() - glob.window_size/2.0/active_zoom*offset_mult
	if next_position != position:
		position = next_position
	#rect.position = ( cam.position- get_viewport_rect().size/2/cam.zoom)
