extends RefCounted
## Explicit layout only: preserve project loading, graph data, and exact undo.

static func apply(nodes: Array, app: Node) -> void:
	var training: Array[Graph] = []
	var model: Array[Graph] = []
	var attachments: Array[Graph] = []
	var before := {}
	for node in nodes:
		if not is_instance_valid(node) or not node is Graph:
			continue
		before[node.get_instance_id()] = node.position
		var kind := String(node.server_typename).to_lower()
		if kind == "layerconfig" or kind.contains("activation"):
			attachments.append(node)
		elif node.is_train_graph or kind.contains("dataset") or kind.contains("train") or kind == "runmodel":
			training.append(node)
		else:
			model.append(node)
	training = _ordered(training)
	model = _ordered(model)
	var after := {}
	var gap := 42.0
	var model_width := _row_width(model, gap)
	var training_width := _row_width(training, gap)
	var width := maxf(model_width, training_width)
	var training_height := _row_height(training)
	var model_height := _row_height(model)
	var attachment_height := _row_height(attachments)
	var model_center := training_height + (attachment_height + 78.0 if not attachments.is_empty() else 116.0) + model_height * 0.5
	_place_row(training, Vector2((width - training_width) * 0.5, training_height * 0.5), gap, after)
	_place_row(model, Vector2((width - model_width) * 0.5, model_center), gap, after)
	var unattached_x := width + gap
	var stacked := {}
	for node in attachments:
		var target: Graph = null
		for descendant in node.get_first_descendants():
			if model.has(descendant):
				target = descendant
				break
		var bounds: Rect2 = node.rect.get_rect()
		var position := Vector2(unattached_x, model_center - bounds.size.y * 0.5)
		if target != null:
			var target_bounds: Rect2 = target.rect.get_rect()
			var target_position: Vector2 = after[target.get_instance_id()] + target_bounds.position
			var level: int = stacked.get(target.get_instance_id(), 0)
			position = Vector2(target_position.x + (target_bounds.size.x - bounds.size.x) * 0.5, target_position.y - bounds.size.y - 42.0 - level * (bounds.size.y + 26.0))
			stacked[target.get_instance_id()] = level + 1
		else:
			unattached_x += bounds.size.x + gap
		after[node.get_instance_id()] = position - bounds.position
	if after.is_empty():
		return
	_restore(after)
	app.add_action(_restore.bind(before), _restore.bind(after))
	app.request_autosave("arrange_graph")


static func _ordered(nodes: Array[Graph]) -> Array[Graph]:
	var pending := nodes.duplicate()
	pending.sort_custom(func(a: Graph, b: Graph):
		if _rank(a) != _rank(b): return _rank(a) < _rank(b)
		if not is_equal_approx(a.position.x, b.position.x): return a.position.x < b.position.x
		return a.graph_id < b.graph_id
	)
	var ordered: Array[Graph] = []
	while not pending.is_empty():
		var next: Graph = null
		for candidate in pending:
			var blocked := false
			for ancestor in candidate.get_first_ancestors():
				if pending.has(ancestor): blocked = true
			if not blocked:
				next = candidate
				break
		if next == null: next = pending[0] # Cycles stay deterministic, never drop data.
		ordered.append(next)
		pending.erase(next)
	return ordered


static func _place_row(nodes: Array[Graph], start: Vector2, gap: float, positions: Dictionary) -> void:
	var x := start.x
	for node in nodes:
		var bounds: Rect2 = node.rect.get_rect()
		positions[node.get_instance_id()] = Vector2(x, start.y - bounds.size.y * 0.5) - bounds.position
		x += bounds.size.x + gap


static func _row_width(nodes: Array[Graph], gap: float) -> float:
	var result := maxf(0.0, nodes.size() - 1) * gap
	for node in nodes: result += node.rect.size.x
	return result


static func _row_height(nodes: Array[Graph]) -> float:
	var result := 0.0
	for node in nodes: result = maxf(result, node.rect.size.y)
	return result


static func _rank(node: Graph) -> int:
	var kind := String(node.server_typename).to_lower()
	if kind.contains("dataset") or node.is_input: return 0
	if kind.contains("trainbegin") or kind.contains("flatten"): return 1
	if kind == "runmodel": return 2
	if kind.contains("train"): return 3
	if kind.contains("softmax"): return 7
	if kind.contains("classifier") or kind.contains("labelgroup"): return 8
	return 4


static func _restore(positions: Dictionary) -> void:
	for id in positions:
		var node = instance_from_id(id)
		if is_instance_valid(node) and node is Graph:
			node.push_position(positions[id])
