extends GridVisualiser
## Dataset equivalent of ProjectGrid: native layout, tile pooling and shared styles.

signal row_selected(row: int, extend: bool)
signal focus_navigation(row: int, direction: int)
signal sample_focused(card: Control)
const Card = preload("res://scripts/data_workspace/sample_card.gd")
const WorkspaceStyle = preload("res://scripts/data_workspace/workspace_style.gd")
var available_width := 760.0
var table_document
var table_mode := false

func _ready() -> void:
	super()
	mouse_filter = Control.MOUSE_FILTER_PASS
	add_theme_constant_override("h_separation", 12)
	add_theme_constant_override("v_separation", 12)
	_sb_default = WorkspaceStyle.box(WorkspaceStyle.Design.CANVAS, WorkspaceStyle.Design.LINE_STRONG, 11)
	_sb_hover = WorkspaceStyle.box(WorkspaceStyle.Design.FILL, WorkspaceStyle.Design.PRIMARY, 11)
	_sb_selected = WorkspaceStyle.box(WorkspaceStyle.Design.PRIMARY_SOFT, WorkspaceStyle.Design.PRIMARY, 11)

func set_samples(model, rows: Array, selected_rows: Array, table: bool) -> void:
	var focused_row := -1
	for child in get_children():
		if child is PanelContainer and child.has_focus(): focused_row = child.row_index
	table_document = model
	table_mode = table
	_tile_index.clear()
	_clear_selection()
	for child in get_children():
		if child is PanelContainer: _recycle_tile(child)
	columns = 1 if table else clampi(floori((available_width + 12) / 196), 1, 6)
	cell_size = Vector2(available_width, 36) if table else Vector2((available_width - 12 * (columns - 1)) / columns, 174)
	for row in rows:
		var card = _tile_pool.pop_back() if not _tile_pool.is_empty() else Card.new()
		card.document = model
		card.mouse_filter = Control.MOUSE_FILTER_PASS
		card.row_index = int(row)
		card.table_mode = table
		card.highlighted = selected_rows.has(row)
		card.custom_minimum_size = cell_size
		card.set_meta("key", str(row))
		card.set_meta("meta", {"row": int(row)})
		card.add_theme_stylebox_override("panel", _sb_selected if card.highlighted else _sb_default)
		if not card.focus_requested.is_connected(_on_focus_requested): card.focus_requested.connect(_on_focus_requested)
		if not card.selected.is_connected(_on_row_selected): card.selected.connect(_on_row_selected)
		if not card.mouse_entered.is_connected(_on_sample_hover):
			card.mouse_entered.connect(_on_sample_hover.bind(card, true))
			card.mouse_exited.connect(_on_sample_hover.bind(card, false))
		if not card.focus_entered.is_connected(_on_sample_focused.bind(card)): card.focus_entered.connect(_on_sample_focused.bind(card))
		add_child(card)
		card.show()
		card.queue_redraw()
		_tile_index[str(row)] = card
		if row == focused_row: card.grab_focus()
	size = Vector2(available_width, content_height(rows.size()))
	queue_sort()
	refreshed.emit()

func _on_row_selected(row: int, extend: bool) -> void:
	row_selected.emit(row, extend)

func _on_sample_hover(card: PanelContainer, entered: bool) -> void:
	if card.highlighted: return
	_on_tile_hover_meta(card, entered)

func content_height(count: int) -> float:
	return ceili(float(count) / columns) * (cell_size.y + 12) - (12 if count > 0 else 0)

func _exit_tree() -> void:
	for card in _tile_pool:
		if is_instance_valid(card): card.free()
	_tile_pool.clear()

func _on_focus_requested(row: int, direction: int) -> void:
	focus_navigation.emit(row, direction)

func _on_sample_focused(card: Control) -> void:
	sample_focused.emit(card)

func _draw() -> void:
	if not table_mode or table_document == null: return
	var font := get_theme_default_font()
	for column in table_document.column_count():
		var x: float = 8 + Card.TABLE_COLUMN_WIDTH * column
		var title: String = table_document.field_name(column)
		var width := Card.TABLE_COLUMN_WIDTH - 16
		if font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x > width:
			while not title.is_empty() and font.get_string_size(title + "…", HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x > width: title = title.left(title.length() - 1)
			title += "…"
		var role := "Вход" if column < int(table_document.data.outputs_from) else "Ответ"
		draw_string(font, Vector2(x, -25), title, HORIZONTAL_ALIGNMENT_LEFT, Card.TABLE_COLUMN_WIDTH - 16, 12, WorkspaceStyle.TEXT)
		draw_string(font, Vector2(x, -9), role, HORIZONTAL_ALIGNMENT_LEFT, Card.TABLE_COLUMN_WIDTH - 16, 11, WorkspaceStyle.MUTED)
