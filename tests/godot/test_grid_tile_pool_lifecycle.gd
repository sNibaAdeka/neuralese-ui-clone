extends SceneTree

func _initialize() -> void:
	var failures: Array[String] = []
	for path in ["res://scripts/grid_vis.gd", "res://scripts/file_grid_extender.gd"]:
		var grid = load(path).new()
		var tile: PanelContainer = grid._get_tile()
		var child := Label.new()
		tile.add_child(child)
		grid.add_child(tile)
		var tile_ref: WeakRef = weakref(tile)
		var child_ref: WeakRef = weakref(child)
		grid._recycle_tile(tile)
		assert(tile.get_parent() == null, "recycled tile is detached from the tree")
		var reused: PanelContainer = grid._get_tile()
		assert(reused == tile, "recycling preserves tile reuse while grid is alive")
		grid.add_child(reused)
		grid._recycle_tile(reused)
		grid.free()
		var retained: bool = tile_ref.get_ref() != null
		print("TILE_POOL_LIFETIME ", path, " retained_after_owner_free=", retained)
		if retained:
			failures.append(path + ": detached tile survives its owner")
			# A failing regression must clean its own leaked fixture.
			tile_ref.get_ref().free()
		if child_ref.get_ref() != null:
			failures.append(path + ": tile child survives its owner")
	for failure in failures:
		push_error(failure)
	if failures.is_empty():
		print("PASS test_grid_tile_pool_lifecycle")
	quit(0 if failures.is_empty() else 1)
