extends RefCounted
class_name IdleCamera

## Lets an editor sit idle instead of redrawing at full frame rate.
##
## glob.gd turns on OS.low_processor_usage_mode, which skips drawing on frames where
## nothing changed. A Camera2D defeats that: while it is in the tree its internal
## process re-applies the viewport canvas transform every frame and requests a redraw
## each time, so the whole UI re-renders even when nothing moves (measured: drawn
## frames / process frames = 1.00 with an idle Camera2D, 0.00 without).
##
## With internal processing off, Camera2D still refreshes the canvas transform the
## moment its position, zoom or offset changes (setters and transform notifications
## call _update_scroll), so nothing stops working -- it just stops polling.
## Only cameras whose motion comes from assignments should use this; anything relying
## on Camera2D's built-in position smoothing needs the internal process.
##
## Re-entering the tree re-enables the internal process, hence the tree_entered hook.


static func apply(camera: Camera2D) -> void:
	if not is_instance_valid(camera):
		return
	if not camera.tree_entered.is_connected(_on_tree_entered.bind(camera)):
		camera.tree_entered.connect(_on_tree_entered.bind(camera))
	_disable_polling(camera)


static func _on_tree_entered(camera: Camera2D) -> void:
	# tree_entered fires after Camera2D's own enter-tree handling, which is what turns
	# the internal process back on, so this has to come after it.
	_disable_polling(camera)


static func _disable_polling(camera: Camera2D) -> void:
	if camera.is_inside_tree():
		camera.set_process_internal(false)
		camera.set_physics_process_internal(false)
		camera.force_update_scroll()
