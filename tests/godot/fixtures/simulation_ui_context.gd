extends RefCounted
## Real UI-coordinate context omitted by NEURALESE_ISOLATED_TEST startup.
class MenuCanvas extends CanvasLayer:
	var root := Control.new()

	func _init() -> void:
		add_child(root)


static func install(tree: SceneTree) -> CanvasLayer:
	var app: Node = tree.root.get_node("glob")
	app.tree = tree
	if is_instance_valid(app.menu_canvas):
		return app.menu_canvas
	var canvas := MenuCanvas.new()
	tree.root.add_child(canvas)
	app.menu_canvas = canvas
	return canvas
