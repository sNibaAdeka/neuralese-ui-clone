extends Node2D

const TEX_WIDTH = 1920.0
const SCALE = 3.0
const REAL_WIDTH = TEX_WIDTH * SCALE
const CENTER_X = 578.75

var texture = preload("res://game_assets/backgrounds/sakura-fuji-pixeloe-natural-mild-1920x1080.png")
var sprites = []
# The tiles only depend on which repeat the camera is over, so skip the writes (each
# one redraws the whole canvas) until that changes.
var _last_center_idx := INF

func _ready():
	for i in range(3):
		var s = Sprite2D.new()
		s.texture = texture
		s.scale = Vector2(SCALE, SCALE)
		s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		s.modulate = Color(1.0, 0.51, 0.7794999, 1.0)
		s.self_modulate = Color(0.46, 0.46, 0.46, 1.0)
		s.z_index = -5
		# Keep Y at original position
		s.global_position.y = 325
		add_child(s)
		sprites.append(s)

func _process(_delta):
	var viewport = get_viewport()
	if not viewport: return
	var camera = viewport.get_camera_2d()
	if not camera: return

	var cam_x = camera.global_position.x

	var offset_x = cam_x - CENTER_X
	var center_idx = round(offset_x / REAL_WIDTH)
	if center_idx == _last_center_idx:
		return
	_last_center_idx = center_idx

	for i in range(3):
		var idx = center_idx + (i - 1)
		sprites[i].global_position.x = CENTER_X + idx * REAL_WIDTH
		sprites[i].flip_h = (int(abs(idx)) % 2 == 1)
