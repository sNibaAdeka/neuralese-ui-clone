extends TextureRect
## Event-driven hand-inked cels. No idle loop or per-frame processing.
const SHEET = preload("res://game_assets/axon/axon-handdrawn-sheet.png")
const SEQUENCES := {
	"blink": [1, 2, 3, 0],
	"wave": [4, 5, 4, 7, 0],
	"think": [6, 6, 7, 0],
}
var frame_index := 0
var reactions_enabled := true
var _sequence: Array = []
var _cursor := 0
var _atlas: AtlasTexture
var _timer: Timer
var _last_reaction := -1000

func _ready() -> void:
	# Gentle display gain brightens the cels while preserving their dark ink.
	self_modulate = Color(1.06, 1.06, 1.06, 1.0)
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_atlas = AtlasTexture.new()
	_atlas.atlas = SHEET
	_atlas.filter_clip = true
	texture = _atlas
	_timer = Timer.new()
	_timer.one_shot = true
	_timer.wait_time = 0.12
	_timer.timeout.connect(_advance)
	add_child(_timer)
	_show_frame(0)
	set_process(false)

func react(kind: String) -> void:
	if not reactions_enabled or not is_visible_in_tree() or not is_instance_valid(_timer):
		return
	var now := Time.get_ticks_msec()
	if now - _last_reaction < 700:
		return
	_last_reaction = now
	_sequence = SEQUENCES.get(kind, SEQUENCES.blink).duplicate()
	_cursor = 0
	_show_frame(int(_sequence[0]))
	_timer.start()

func rest() -> void:
	if not is_instance_valid(_timer): return
	_timer.stop()
	_sequence.clear()
	_show_frame(0)

func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and not is_visible_in_tree():
		rest()

func _advance() -> void:
	_cursor += 1
	if _cursor >= _sequence.size():
		rest()
		return
	_show_frame(int(_sequence[_cursor]))
	_timer.start()

func _show_frame(index: int) -> void:
	frame_index = index
	var cell := SHEET.get_size() / Vector2(4.0, 2.0)
	var origin := Vector2(index % 4, floori(index / 4.0)) * cell
	# Trim only the shared transparent gutters in the view, keeping every cel registered.
	_atlas.region = Rect2(origin + Vector2(0, cell.y * 0.16), Vector2(cell.x, cell.y * 0.78))
