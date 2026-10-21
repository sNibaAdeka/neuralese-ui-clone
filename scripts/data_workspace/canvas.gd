extends Control

signal tool_dropped(tool: String, group: String, at: Vector2)
signal row_selected(row: int, extend: bool)
signal group_relocated(group: String, at: Vector2)
signal row_reclassified(row: int, group: String)
signal viewport_changed
signal files_requested(paths: Array)
const WorkspaceStyle = preload("res://scripts/data_workspace/workspace_style.gd")
const Card = preload("res://scripts/data_workspace/sample_card.gd")
const SampleGrid = preload("res://scripts/data_workspace/sample_grid.gd")
const Group = preload("res://scripts/data_workspace/group_card.gd")
var document
var selected: Array = []
var page := 0
var page_size := 96
var filter := ""
var view := "cards"
var pan := Vector2(30, 28)
var zoom := 1.0
var world: Control
var _empty_state: VBoxContainer
var _panning := false
var _points: Array[Dictionary] = []
var _plot_min: Array[float] = [0.0, 0.0]
var _plot_max: Array[float] = [1.0, 1.0]
const PLOT_RECT := Rect2(76, 60, 560, 360)

func _ready() -> void:
	clip_contents = true
	focus_mode = Control.FOCUS_ALL
	world = Control.new()
	world.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(world)
	_empty_state = VBoxContainer.new()
	_empty_state.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_empty_state.add_theme_constant_override("separation", 12)
	add_child(_empty_state)
	_empty_state.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_empty_state.offset_left = 32
	_empty_state.offset_right = -32
	_empty_state.offset_top = 68
	for copy in [["Датасет начинается с примера", 22, Color("242a38")], ["Создайте набор в палитре или импортируйте файл. Папку с примерами можно перетащить сюда.", 14, Color("637087")]]:
		var label := Label.new()
		label.text = copy[0]
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.add_theme_font_size_override("font_size", copy[1])
		label.add_theme_color_override("font_color", copy[2])
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_empty_state.add_child(label)
	resized.connect(queue_redraw)

func render(model, rows_selected: Array, next_page: int = 0, query: String = "") -> void:
	document = model
	_empty_state.visible = document == null or document.row_count() == 0
	_empty_state.get_child(0).text = "Датасет начинается с примера" if document == null else "Набор создан. Добавьте пример или импортируйте данные."
	_empty_state.get_child(1).visible = document == null
	selected = rows_selected
	page = next_page
	filter = query.to_lower()
	_points.clear()
	if document == null or document.row_count() == 0 or (view == "plot" and document.kind() in ["numeric", "car", "simulation"]):
		_clear_groups()
		if document != null and document.row_count() > 0 and view == "plot": _build_plot()
		queue_redraw()
		return
	var groups: Dictionary = {}
	var rows_by_group: Dictionary = {}
	var counts: Dictionary = document.group_counts()
	var dataset_name := str(document.data.name)
	var section_width := maxf(250, size.x - 56)
	if view == "table": section_width = maxf(section_width, document.column_count() * Card.TABLE_COLUMN_WIDTH + 44)
	for child in world.get_children():
		if child.dataset_name != dataset_name or not document.classes().has(child.title):
			world.remove_child(child); child.queue_free()
	for name in document.classes():
		if not filter.is_empty() and not str(name).to_lower().contains(filter): continue
		var group = null
		for child in world.get_children():
			if child.title == str(name): group = child; break
		if group == null:
			group = Group.new()
			group.title = str(name)
			group.dataset_name = dataset_name
			group.moved.connect(func(title, at): group_relocated.emit(title, at))
			group.sample_dropped.connect(func(row, title): row_reclassified.emit(row, title))
			world.add_child(group)
			group.grid = SampleGrid.new()
			group.grid.position = Vector2(14, 46)
			group.grid.row_selected.connect(func(row, extend): row_selected.emit(row, extend))
			group.grid.focus_navigation.connect(_focus_sample)
			group.grid.sample_focused.connect(_reveal_sample)
			group.add_child(group.grid)
		group.count = int(counts.get(name, 0))
		group.accent = Card.ACCENTS[groups.size() % Card.ACCENTS.size()]
		groups[name] = group
		rows_by_group[name] = []
	var start := page * page_size
	var finish: int = mini(document.row_count(), start + page_size)
	for row in range(start, finish):
		var name: String = document.group_for(row)
		if rows_by_group.has(name): rows_by_group[name].append(row)
	var next_y := 0.0
	for name in groups:
		var group = groups[name]
		group.grid.position.y = 88 if view == "table" else 46
		group.grid.available_width = section_width - 28
		group.grid.set_samples(document, rows_by_group[name], selected, view == "table")
		group.size = Vector2(section_width, maxf(100, (102 if view == "table" else 60) + group.grid.content_height(rows_by_group[name].size())))
		var stored: Array = document.studio().get("group_positions", {}).get(name, [0, next_y])
		group.position = Vector2(float(stored[0]), float(stored[1]))
		next_y += group.size.y + 16
		group.queue_redraw()
	world.position = pan
	world.scale = Vector2.ONE * zoom
	queue_redraw()

func _clear_groups() -> void:
	for child in world.get_children():
		world.remove_child(child)
		child.queue_free()

func _build_plot() -> void:
	if document.column_count() < 2: return
	_plot_min = [INF, INF]
	_plot_max = [-INF, -INF]
	for row in document.row_count():
		var x: Variant = document.value(row, 0)
		var y: Variant = document.value(row, 1)
		if not (x is float or x is int) or not (y is float or y is int): continue
		if not is_finite(float(x)) or not is_finite(float(y)): continue
		_plot_min[0] = minf(_plot_min[0], float(x))
		_plot_min[1] = minf(_plot_min[1], float(y))
		_plot_max[0] = maxf(_plot_max[0], float(x))
		_plot_max[1] = maxf(_plot_max[1], float(y))
	if not is_finite(_plot_min[0]): return
	for axis in 2:
		if _plot_min[axis] == _plot_max[axis]:
			var padding := maxf(absf(_plot_min[axis]) * 0.05, 0.5)
			_plot_min[axis] -= padding
			_plot_max[axis] += padding
	var counts: Array = document.classes()
	var stride: int = maxi(1, ceili(float(document.row_count()) / 5000))
	for row in range(0, document.row_count(), stride):
		var x: Variant = document.value(row, 0)
		var y: Variant = document.value(row, 1)
		if not (x is float or x is int) or not (y is float or y is int): continue
		if not is_finite(float(x)) or not is_finite(float(y)): continue
		var uv := Vector2(inverse_lerp(_plot_min[0], _plot_max[0], float(x)), inverse_lerp(_plot_min[1], _plot_max[1], float(y)))
		_points.append({"row": row, "at": PLOT_RECT.position + Vector2(uv.x, 1 - uv.y) * PLOT_RECT.size, "color": Card.ACCENTS[maxi(0, counts.find(document.group_for(row))) % Card.ACCENTS.size()]})

func reset_view() -> void:
	pan = Vector2(30, 28)
	zoom = 1
	world.position = pan
	world.scale = Vector2.ONE
	queue_redraw()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			_panning = event.pressed
			if not _panning: viewport_changed.emit()
			accept_event()
		elif event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_WHEEL_LEFT, MOUSE_BUTTON_WHEEL_RIGHT]:
			if event.ctrl_pressed or event.meta_pressed:
				var local: Vector2 = (event.position - pan) / zoom
				zoom = clampf(zoom * (1.12 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1 / 1.12), 0.35, 2.5)
				pan = event.position - local * zoom
			else:
				var amount := 48.0 * maxf(event.factor, 0.1)
				var direction := 1 if event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_LEFT] else -1
				if event.shift_pressed or event.button_index in [MOUSE_BUTTON_WHEEL_LEFT, MOUSE_BUTTON_WHEEL_RIGHT]: pan.x += amount * direction
				else: pan.y += amount * direction
			world.position = pan
			world.scale = Vector2.ONE * zoom
			queue_redraw()
			viewport_changed.emit()
			accept_event()
		elif event.button_index == MOUSE_BUTTON_LEFT and event.pressed and view == "plot":
			var point: Vector2 = (event.position - pan) / zoom
			var distance := 20.0 / zoom
			var found := -1
			for item in _points:
				var candidate: float = item.at.distance_to(point)
				if candidate < distance: distance = candidate; found = int(item.row)
			if found >= 0: row_selected.emit(found, event.ctrl_pressed)
			accept_event()
	elif event is InputEventPanGesture:
		pan -= event.delta * 24
		world.position = pan
		queue_redraw()
		viewport_changed.emit()
		accept_event()
	elif event is InputEventMouseMotion and _panning:
		pan += event.relative
		world.position = pan
		queue_redraw()
		accept_event()

func _can_drop_data(_at_position: Vector2, payload: Variant) -> bool:
	return payload is Dictionary and (payload.has("dataset_tool") or payload.has("files"))

func _drop_data(at_position: Vector2, payload: Variant) -> void:
	if payload.has("dataset_tool"):
		var world_position := (at_position - pan) / zoom
		var target := ""
		for group in world.get_children():
			if Rect2(group.position, group.size).has_point(world_position): target = group.title
		tool_dropped.emit(str(payload.dataset_tool), target, world_position)
	elif payload.has("files"): files_requested.emit(Array(payload.files))

func _draw() -> void:
	if document == null: return
	if view == "plot":
		if _points.is_empty(): return
		draw_set_transform(pan, 0, Vector2.ONE * zoom)
		var font := get_theme_default_font()
		var ink := WorkspaceStyle.TEXT
		for tick in 5:
			var fraction := tick / 4.0
			var x := PLOT_RECT.position.x + fraction * PLOT_RECT.size.x
			var y := PLOT_RECT.end.y - fraction * PLOT_RECT.size.y
			draw_line(Vector2(x, PLOT_RECT.position.y), Vector2(x, PLOT_RECT.end.y), WorkspaceStyle.Design.LINE)
			draw_line(Vector2(PLOT_RECT.position.x, y), Vector2(PLOT_RECT.end.x, y), WorkspaceStyle.Design.LINE)
			draw_string(font, Vector2(x - 56, PLOT_RECT.end.y + 20), _axis_tick(lerpf(_plot_min[0], _plot_max[0], fraction)), HORIZONTAL_ALIGNMENT_CENTER, 112, 11, ink)
			draw_string(font, Vector2(0, y + 4), _axis_tick(lerpf(_plot_min[1], _plot_max[1], fraction)), HORIZONTAL_ALIGNMENT_RIGHT, PLOT_RECT.position.x - 10, 11, ink)
		draw_line(PLOT_RECT.position, Vector2(PLOT_RECT.position.x, PLOT_RECT.end.y), WorkspaceStyle.MUTED)
		draw_line(Vector2(PLOT_RECT.position.x, PLOT_RECT.end.y), PLOT_RECT.end, WorkspaceStyle.MUTED)
		for item in _points:
			var radius := 5.0 if selected.has(item.row) else 3.5
			# An ink outline keeps pastel class colors visible on the canvas.
			draw_circle(item.at, radius + 1.0, WorkspaceStyle.MUTED, true, -1, true)
			draw_circle(item.at, radius, item.color, true, -1, true)
			if selected.has(item.row): draw_circle(item.at, 8.0, WorkspaceStyle.ACCENT, false, 2.0, true)
		draw_string(font, Vector2(PLOT_RECT.position.x, 34), "Y: " + document.field_name(1), HORIZONTAL_ALIGNMENT_LEFT, 560, 15, ink)
		draw_string(font, Vector2(PLOT_RECT.position.x, PLOT_RECT.end.y + 44), "X: " + document.field_name(0), HORIZONTAL_ALIGNMENT_LEFT, 560, 15, ink)
		if not selected.is_empty():
			var row := int(selected.back())
			if row >= 0 and row < document.row_count():
				var detail := "Пример %d · %s = %s · %s = %s" % [row + 1, document.field_name(0), str(document.value(row, 0)), document.field_name(1), str(document.value(row, 1))]
				draw_string(font, Vector2(PLOT_RECT.position.x, PLOT_RECT.end.y + 70), detail, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, ink)
		draw_set_transform(Vector2.ZERO)

func _focus_sample(row: int, direction: int) -> void:
	var cards: Array = []
	for group in world.get_children():
		for card in group.grid.get_children():
			if card is PanelContainer: cards.append(card)
	cards.sort_custom(func(a, b): return a.row_index < b.row_index)
	for index in cards.size():
		if cards[index].row_index == row:
			cards[clampi(index + direction, 0, cards.size() - 1)].grab_focus()
			return

func _reveal_sample(card: Control) -> void:
	var bounds := card.get_global_rect()
	var visible_bounds := get_global_rect().grow(-12)
	var delta := Vector2.ZERO
	if bounds.position.y < visible_bounds.position.y: delta.y = visible_bounds.position.y - bounds.position.y
	elif bounds.end.y > visible_bounds.end.y: delta.y = visible_bounds.end.y - bounds.end.y
	if bounds.position.x < visible_bounds.position.x: delta.x = visible_bounds.position.x - bounds.position.x
	elif bounds.end.x > visible_bounds.end.x and bounds.size.x <= visible_bounds.size.x: delta.x = visible_bounds.end.x - bounds.end.x
	pan += delta
	world.position = pan
	queue_redraw()

func _axis_tick(value: float) -> String:
	if value != 0 and (absf(value) < 0.001 or absf(value) >= 10000000000): return String.num_scientific(value)
	return String.num(value, 4)

func _get_tooltip(at_position: Vector2) -> String:
	if view != "plot" or document == null: return "Колесо — прокрутка · Shift + колесо — по горизонтали · Ctrl/Cmd + колесо — масштаб"
	var at := (at_position - pan) / zoom
	for item in _points:
		if item.at.distance_to(at) <= 10 / zoom:
			return "Пример %d\n%s = %s\n%s = %s\nEnter в таблице — изменить пример" % [int(item.row) + 1, document.field_name(0), str(document.value(item.row, 0)), document.field_name(1), str(document.value(item.row, 1))]
	return "Колесо — прокрутка · Ctrl/Cmd + колесо — масштаб"
