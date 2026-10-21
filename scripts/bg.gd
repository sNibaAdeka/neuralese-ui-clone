extends CanvasLayer

@export var register_global := true

func _enter_tree():
	if register_global:
		glob.bg_trect = self

@onready var base_bgcol =  ui.get_uni($SubViewport/bg/ColorRect, "bg_color")
@onready var base_grcol =  ui.get_uni($SubViewport/bg/ColorRect, "grid_color")
var active_texture: Texture2D

# PERF: the background is a pure function of (camera, window size, colors), so it is
# re-rendered only when one of those changes instead of every frame. While the camera
# is still (the common case) the SubViewport costs nothing and the last texture stays.
# Any other change to what the SubViewport draws must call mark_dirty().
const _BLUR_DOWNSCALE := 4
const _SAFETY_REFRESH_FRAMES := 120 # cheap insurance against a missed mark_dirty()
const _BlurShader := preload("res://shaders/bg_blur.gdshader")
const _CanvasShader := preload("res://shaders/claude_canvas.gdshader")
const _Design := preload("res://scripts/claude_design_theme.gd")
const _WorkspaceGeometry := preload("res://scripts/claude_workspace_geometry.gd")
var _active := false
var _last_signature: Array = []
var _workspace_rect := Rect2()
var _workspace_framed := false
var _frames_since_render := 0
var _bake_blur := false
var _blur_viewport: SubViewport
var _blur_pending := false
# Frames left before the baked texture replaces the raw one as the global `bg` after Settings
# switched the blur to Baked at runtime (-1 = nothing pending). The bake needs a couple of
# frames to render, and publishing it earlier would show black panels.
var _publish_baked_in := -1


func _ready() -> void:
	_apply_claude_canvas_design()
	# Screen-space coverage has one owner; camera movement changes only the grid
	# phase. The legacy world/parallax bounds can leave gaps on narrow windows.
	$TextureRect.set_process(false)
	$SubViewport.set_process(false)
	$TextureRect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	$TextureRect.stretch_mode = TextureRect.STRETCH_SCALE
	$ColorRect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	$SubViewport/bg.follow_viewport_enabled = false
	add_to_group(&"graphics_bg")
	# Runs last of this frame's _process callbacks' consumers: signal fires just before
	# drawing, after camera/parallax scripts updated this frame (no one-frame lag).
	RenderingServer.frame_pre_draw.connect(_on_frame_pre_draw)
	IdleCamera.apply($SubViewport/Camera2D)


func _apply_claude_canvas_design() -> void:
	# Display the opaque grid directly, while keeping the cached SubViewport for
	# the application's shared `bg` texture and optional blur bake consumers.
	var grid := $SubViewport/bg/ColorRect as ColorRect
	var canvas_material := ShaderMaterial.new()
	canvas_material.shader = _CanvasShader
	grid.material = canvas_material
	$TextureRect.material = canvas_material
	base_bgcol = _Design.CANVAS
	base_grcol = _Design.DOT
	ui.set_uni(grid, "bg_color", base_bgcol)
	ui.set_uni(grid, "grid_color", base_grcol)
	ui.set_uni(grid, "page_color", _Design.PAGE)
	ui.set_uni(grid, "wash_color", _Design.WASH)
	ui.set_uni(grid, "wash_soft_color", _Design.WASH_SOFT)
	ui.set_uni(grid, "border_color", _Design.LINE)
	ui.set_uni(grid, "panel_radius", float(_Design.PANEL_RADIUS))
	ui.set_uni(grid, "spacing", 26.0)
	ui.set_uni(grid, "width", 2.6)
	$ColorRect.color = _Design.PAGE
	var wallpaper := get_node_or_null("SubViewport/bg/Ffff") as CanvasItem
	if is_instance_valid(wallpaper):
		wallpaper.hide()
		wallpaper.set_process(false)
	mark_dirty()


func activate() -> void:
	visible = true
	var background_texture: Texture2D = $SubViewport.get_texture()
	active_texture = background_texture
	$TextureRect.texture = background_texture
	$TextureRect.show()
	_active = true
	_bake_blur = GraphicsQualityConfig.bakes_blur()
	_publish_baked_in = -1
	mark_dirty()
	$SubViewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	RenderingServer.global_shader_parameter_set("bg", background_texture)
	if _bake_blur:
		_ensure_blur_viewport()
		RenderingServer.global_shader_parameter_set("bg", _blur_viewport.get_texture())


func deactivate() -> void:
	_active = false
	$TextureRect.hide()
	$SubViewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	if is_instance_valid(_blur_viewport):
		_blur_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	visible = false


## Forces the next frame to re-render the background (and re-bake its blur).
func mark_dirty() -> void:
	_last_signature = []


## Called (group "graphics_bg") when Settings changed the graphics options at runtime.
## Inactive tabs only note the new value; activate() applies it when they are shown.
func apply_quality() -> void:
	var bake := GraphicsQualityConfig.bakes_blur()
	if bake == _bake_blur:
		return
	_bake_blur = bake
	if not _active:
		return
	if bake:
		_ensure_blur_viewport()
		_publish_baked_in = 4
	else:
		_publish_baked_in = -1
		RenderingServer.global_shader_parameter_set("bg", active_texture)
		if is_instance_valid(_blur_viewport):
			_blur_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	mark_dirty()


func _on_frame_pre_draw() -> void:
	if not _active:
		return
	_sync_canvas_geometry()
	if _publish_baked_in >= 0:
		if _publish_baked_in == 0:
			_publish_baked_in = -1
			RenderingServer.global_shader_parameter_set("bg", _blur_viewport.get_texture())
		else:
			_publish_baked_in -= 1
			$TextureRect.queue_redraw() # keep frames coming while idle so the bake can finish
	if _blur_pending:
		_blur_pending = false
		_blur_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	_frames_since_render += 1
	var signature := _signature()
	if signature == _last_signature and _frames_since_render < _SAFETY_REFRESH_FRAMES:
		return
	_last_signature = signature
	_frames_since_render = 0
	$SubViewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	if _bake_blur:
		# The blur samples the sharp texture, so bake it the frame after it renders.
		_blur_pending = true


func _sync_canvas_geometry() -> void:
	var viewport_size := Vector2i(get_viewport().get_visible_rect().size)
	viewport_size.x = maxi(viewport_size.x, 1)
	viewport_size.y = maxi(viewport_size.y, 1)
	var source := $SubViewport as SubViewport
	if source.size != viewport_size:
		source.size = viewport_size
	var grid := $SubViewport/bg/ColorRect as ColorRect
	if grid.position != Vector2.ZERO:
		grid.position = Vector2.ZERO
	if grid.size != Vector2(viewport_size):
		grid.size = Vector2(viewport_size)
	var material := grid.material as ShaderMaterial
	if material.get_shader_parameter("canvas_size") != Vector2(viewport_size):
		material.set_shader_parameter("canvas_size", Vector2(viewport_size))
	# Only the main graph owns the rounded workspace. Simulation has its own
	# background instance (register_global = false) and keeps its full canvas.
	_workspace_framed = register_global and glob.curr_window == "graph"
	if _workspace_framed:
		_workspace_rect = _WorkspaceGeometry.graph_rect(Vector2(viewport_size), glob.space_begin, glob.space_end)
	else:
		_workspace_rect = Rect2(Vector2.ZERO, Vector2(viewport_size))
	var shader_rect := Vector4(_workspace_rect.position.x, _workspace_rect.position.y, _workspace_rect.size.x, _workspace_rect.size.y)
	if material.get_shader_parameter("workspace_rect") != shader_rect:
		material.set_shader_parameter("workspace_rect", shader_rect)
	if material.get_shader_parameter("framed_workspace") != _workspace_framed:
		material.set_shader_parameter("framed_workspace", _workspace_framed)
	var camera: Camera2D = glob.cam
	if is_instance_valid(camera):
		var phase := (camera.position + camera.offset) * camera.zoom * 0.7
		if material.get_shader_parameter("camera_offset") != phase:
			material.set_shader_parameter("camera_offset", phase)
		if material.get_shader_parameter("grid_zoom") != camera.zoom.x:
			material.set_shader_parameter("grid_zoom", camera.zoom.x)


func _signature() -> Array:
	# Header/palette layout can change while the camera and window stay still.
	# Include the frame geometry so shared `bg` and its baked blur refresh too.
	var result: Array = [$SubViewport.size, glob.window_size, _workspace_rect, _workspace_framed]
	var cam: Camera2D = glob.cam
	if is_instance_valid(cam):
		result.append_array([cam.position, cam.offset, cam.zoom, cam.get_screen_center_position(),
			$SubViewport/bg.get_final_transform()])
	return result


func _ensure_blur_viewport() -> void:
	if is_instance_valid(_blur_viewport):
		return
	_blur_viewport = SubViewport.new()
	_blur_viewport.name = "BlurBake"
	_blur_viewport.disable_3d = true
	_blur_viewport.transparent_bg = true
	_blur_viewport.gui_disable_input = true
	_blur_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_blur_viewport.size = _blur_size()
	var source := TextureRect.new()
	source.texture = $SubViewport.get_texture()
	source.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	source.stretch_mode = TextureRect.STRETCH_SCALE
	source.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	source.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var material := ShaderMaterial.new()
	material.shader = _BlurShader
	source.material = material
	_blur_viewport.add_child(source)
	add_child(_blur_viewport)
	$SubViewport.size_changed.connect(func() -> void: _blur_viewport.size = _blur_size())


func _blur_size() -> Vector2i:
	return Vector2i(maxi($SubViewport.size.x / _BLUR_DOWNSCALE, 1), maxi($SubViewport.size.y / _BLUR_DOWNSCALE, 1))


func set_screenshotting():
	ui.set_uni($SubViewport/bg/ColorRect, "bg_color", Color.GRAY)
	ui.set_uni($SubViewport/bg/ColorRect, "grid_color", Color.GRAY)
	mark_dirty()

func set_not_screenshotting():
	ui.set_uni($SubViewport/bg/ColorRect, "bg_color", base_bgcol)
	ui.set_uni($SubViewport/bg/ColorRect, "grid_color", base_grcol)
	mark_dirty()


func hide_for_capture() -> Dictionary:
	var background_image := get_node_or_null("SubViewport/bg/Ffff") as CanvasItem
	var state := {
		"layer_visible": visible,
		"background_image": background_image,
		"background_image_visible": background_image.visible if is_instance_valid(background_image) else false,
	}
	if is_instance_valid(background_image):
		background_image.visible = false
	visible = false
	return state


func restore_after_capture(state: Dictionary) -> void:
	var background_image: CanvasItem = state.get("background_image")
	if is_instance_valid(background_image):
		background_image.visible = bool(state.get("background_image_visible", true))
	visible = bool(state.get("layer_visible", true))


func is_hidden_for_capture() -> bool:
	var background_image := get_node_or_null("SubViewport/bg/Ffff") as CanvasItem
	return not visible and (
		not is_instance_valid(background_image) or not background_image.visible
	)
