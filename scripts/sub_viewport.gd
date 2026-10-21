extends SubViewport


func _ready() -> void:
	_sync_to_parent_viewport()


func _process(_delta: float) -> void:
	_sync_to_parent_viewport()


func _sync_to_parent_viewport() -> void:
	var parent_viewport := get_parent().get_viewport()
	if parent_viewport != null and parent_viewport != self:
		var target_size := Vector2i(parent_viewport.get_visible_rect().size)
		if target_size.x > 0 and target_size.y > 0 and target_size != size:
			size = target_size
	var fill_size := Vector2(size) * 5.0
	if $"bg/ColorRect".size != fill_size:
		$"bg/ColorRect".size = fill_size
