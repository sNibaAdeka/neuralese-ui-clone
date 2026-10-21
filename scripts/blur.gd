extends ColorRect

@onready var base_tuning = glob.inst_uniform_read(self, "tuning")


func _ready() -> void:
	RenderingServer.frame_pre_draw.connect(_sync_visibility)
	_sync_visibility()


func set_tuning(color_: Color):
	RenderingServer.canvas_item_set_instance_shader_parameter(get_canvas_item(), &"tuning", color_)


# PERF: ui.blur is a full-screen live-blur panel (block_screen) that splashes fade in through
# self_modulate.a. At alpha 0 it draws nothing visible, but the engine still copies the whole
# framebuffer, builds its mip chain and runs the shader over every pixel -- every frame, for
# the whole session, since ui.blur starts at alpha 0 and is only raised while a splash is
# open (26 ms of a 71 ms High frame and 5 ms of a 20 ms Medium frame on the low-end proxy).
# Synced from frame_pre_draw so it follows whatever this frame's scripts set, with no lag.
func _sync_visibility() -> void:
	var should_show := self_modulate.a > 0.001
	if should_show != visible:
		visible = should_show
