extends RefCounted
## Editable dataset model, independent of the workspace and the legacy table UI.

signal changed
const Packed = preload("res://scripts/packed_numeric_dataset.gd")
const HISTORY_LIMIT := 12
var data: Dictionary = {}
var _undo: Array[Dictionary] = []
var _redo: Array[Dictionary] = []

func create(title: String, kind: String = "numeric") -> void:
	data = {"name": title, "arr": [], "col_names": [], "outputs_from": 2, "col_args": [], "cache": {}, "metadata": {"studio": {"kind": kind, "classes": [], "image_width": 28, "image_height": 28, "split_seed": 42, "validation_ratio": 0.2}}}
	match kind:
		"images":
			data.col_names = ["Изображение:image", "Круги:num", "Квадраты:num", "Треугольники:num"]
			data.outputs_from = 1
			studio().classes = ["Круги", "Квадраты", "Треугольники"]
			studio()["rule_shapes"] = true
		"text":
			data.col_names = ["Текст:text", "Класс 1:num", "Класс 2:num"]
			data.outputs_from = 1
			studio().classes = ["Класс 1", "Класс 2"]
		"car":
			data.col_names = ["x:float", "y:float", "heading:float", "goal_x:float", "goal_y:float", "steer:float", "throttle:float"]
			data.outputs_from = 5
		_:
			data.col_names = ["x:float", "y:float", "Класс 1:num", "Класс 2:num"]
			studio().classes = ["Класс 1", "Класс 2"]
	refresh_cache()

func attach(dataset: Dictionary) -> void:
	data = dataset
	if not data.has("metadata"): data.metadata = {}
	if not data.metadata.has("studio"):
		var kind := "numeric"
		for column in data.get("col_names", []):
			if str(column).ends_with(":image"): kind = "images"
			elif str(column).ends_with(":text") and kind != "images": kind = "text"
		if data.metadata.has("binding"): kind = "simulation"
		data.metadata.studio = {"kind": kind, "classes": [], "split_seed": 42, "validation_ratio": 0.2}
	if not data.has("col_args"): data.col_args = []
	if not data.has("cache"): data.cache = {}
	if kind() == "images" and row_count() > 0:
		var first: Variant = value(0, 0)
		if first is Texture2D:
			studio()["image_width"] = first.get_width()
			studio()["image_height"] = first.get_height()

func studio() -> Dictionary:
	return data.metadata.studio

func kind() -> String:
	return str(studio().get("kind", "numeric"))

func row_count() -> int:
	return Packed.row_count(data)

func column_count() -> int:
	return data.get("col_names", []).size()

func field_name(column: int) -> String:
	return str(data.col_names[column]).rsplit(":", true, 1)[0]

func field_type(column: int) -> String:
	var parts := str(data.col_names[column]).rsplit(":", true, 1)
	return parts[1] if parts.size() > 1 else "text"

func value(row: int, column: int) -> Variant:
	if row < 0 or row >= row_count() or column < 0 or column >= column_count(): return null
	if Packed.is_packed(data): return Packed.value(data, row, column)
	var cells: Array = data.get("arr", [])[row]
	if column >= cells.size(): return null
	var cell: Variant = cells[column]
	if not cell is Dictionary: return cell
	match str(cell.get("type", field_type(column))):
		"num": return cell.get("num", 0)
		"float": return cell.get("val", 0.0)
		"image": return cell.get("img")
		_: return cell.get("text", "")

func values(row: int) -> Array:
	var result: Array = []
	for column in column_count(): result.append(value(row, column))
	return result

func classes() -> Array:
	var named: Array = studio().get("classes", [])
	if not named.is_empty(): return named.duplicate()
	if kind() in ["car", "simulation"]: return ["Влево", "Прямо", "Вправо"]
	return ["Примеры"]

func group_for(row: int) -> String:
	var groups: Array = studio().get("classes", [])
	var start: int = int(data.get("outputs_from", 1))
	if not groups.is_empty():
		var best := 0
		for index in groups.size():
			if float(value(row, start + index)) > float(value(row, start + best)): best = index
		return str(groups[best])
	if kind() in ["car", "simulation"]:
		var steer: float = float(value(row, start)) if value(row, start) != null else 0.0
		return "Влево" if steer < -0.15 else ("Вправо" if steer > 0.15 else "Прямо")
	return "Примеры"

func group_counts() -> Dictionary:
	var result := {}
	for group in classes(): result[group] = 0
	for row in row_count():
		var group := group_for(row)
		result[group] = int(result.get(group, 0)) + 1
	return result

func _capture() -> void:
	_undo.append(data.duplicate(true))
	if _undo.size() > HISTORY_LIMIT: _undo.pop_front()
	_redo.clear()

func can_undo() -> bool: return not _undo.is_empty()
func can_redo() -> bool: return not _redo.is_empty()

func undo() -> void:
	if _undo.is_empty(): return
	_redo.append(data.duplicate(true))
	_restore(_undo.pop_back())

func redo() -> void:
	if _redo.is_empty(): return
	_undo.append(data.duplicate(true))
	_restore(_redo.pop_back())

func _restore(snapshot: Dictionary) -> void:
	data.clear()
	data.merge(snapshot, true)
	_commit()

func _cell(column: int, raw: Variant) -> Dictionary:
	match field_type(column):
		"float": return {"type": "float", "val": float(raw) if raw != null else 0.0}
		"num": return {"type": "num", "num": int(raw) if raw != null else 0}
		"image": return {"type": "image", "img": raw, "id": randi(), "x": int(studio().get("image_width", 28)), "y": int(studio().get("image_height", 28))}
		_: return {"type": "text", "text": str(raw) if raw != null else ""}

func _family(row: int) -> int:
	var ids: Array = studio().get("family_ids", [])
	return int(ids[row]) if row < ids.size() else row

func _ensure_families() -> void:
	var ids: Array = studio().get_or_add("family_ids", [])
	while ids.size() < row_count(): ids.append(ids.size())
	studio()["next_family"] = maxi(int(studio().get("next_family", 0)), row_count())

func _append(raw: Array, family: int = -1) -> void:
	_ensure_families()
	if family < 0:
		family = int(studio().get("next_family", 0))
		studio()["next_family"] = family + 1
	studio().family_ids.append(family)
	if Packed.is_packed(data):
		var numbers: PackedFloat32Array = data["values"]
		for item in raw: numbers.append(float(item))
		data["values"] = numbers
		data["row_count"] = row_count() + 1
	else:
		var cells: Array = []
		for column in column_count(): cells.append(_cell(column, raw[column] if column < raw.size() else null))
		data.arr.append(cells)

func add_sample(group: String = "") -> int:
	_capture()
	var row: Array = []
	for column in column_count(): row.append(0.0 if field_type(column) in ["float", "num"] else null)
	if kind() == "images":
		var image := Image.create(int(studio().get("image_width", 28)), int(studio().get("image_height", 28)), false, Image.FORMAT_L8)
		image.fill(Color.BLACK)
		row[0] = ImageTexture.create_from_image(image)
	if kind() == "car": row[3] = 0.8
	var groups: Array = studio().get("classes", [])
	if not groups.is_empty():
		var index := maxi(0, groups.find(group))
		row[int(data.outputs_from) + index] = 1
	_append(row)
	_commit()
	return row_count() - 1

func set_value(row: int, column: int, raw: Variant) -> void:
	if row < 0 or row >= row_count(): return
	_capture()
	if Packed.is_packed(data):
		var numbers: PackedFloat32Array = data["values"]
		numbers[row * column_count() + column] = float(raw)
		data["values"] = numbers
	else:
		while data.arr[row].size() <= column: data.arr[row].append(_cell(data.arr[row].size(), null))
		data.arr[row][column] = _cell(column, raw)
	_commit()

func assign_class(rows: Array, group: String) -> void:
	var groups: Array = studio().get("classes", [])
	if not groups.has(group): return
	_capture()
	for row in rows:
		if int(row) < 0 or int(row) >= row_count(): continue
		for index in groups.size():
			var column: int = int(data.outputs_from) + index
			if Packed.is_packed(data):
				data["values"][int(row) * column_count() + column] = 1.0 if groups[index] == group else 0.0
			else: data.arr[int(row)][column] = _cell(column, 1 if groups[index] == group else 0)
	_commit()

func add_class(title: String) -> bool:
	title = title.strip_edges()
	if title.is_empty() or kind() in ["car", "simulation"]: return false
	var groups: Array = studio().get("classes", [])
	if groups.has(title): return false
	if groups.is_empty() and row_count() > 0: return false
	_capture()
	if groups.is_empty(): data.col_names.resize(int(data.outputs_from))
	if kind() == "images": studio()["rule_shapes"] = false
	groups.append(title)
	studio()["classes"] = groups
	data.col_names.append(title + ":num")
	if Packed.is_packed(data):
		var old: PackedFloat32Array = data["values"]
		var width := column_count() - 1
		var resized := PackedFloat32Array()
		for row in row_count():
			resized.append_array(old.slice(row * width, (row + 1) * width))
			resized.append(0)
		data["values"] = resized
		data.column_count = column_count()
	else:
		for cells in data.arr: cells.append({"type": "num", "num": 0})
	_commit()
	return true

func rename_class(old: String, title: String) -> bool:
	title = title.strip_edges()
	var groups: Array = studio().get("classes", [])
	if title.is_empty() or groups.has(title) or not groups.has(old): return false
	_capture()
	if kind() == "images": studio()["rule_shapes"] = false
	var index := groups.find(old)
	groups[index] = title
	data.col_names[int(data.outputs_from) + index] = title + ":num"
	_commit()
	return true

func add_input(title: String) -> bool:
	title = title.strip_edges()
	if title.is_empty() or kind() not in ["numeric", "text"]: return false
	for column in column_count():
		if field_name(column) == title: return false
	_capture()
	var at: int = int(data.outputs_from)
	var old_width := column_count()
	data.col_names.insert(at, title + ":float")
	data.outputs_from = at + 1
	if Packed.is_packed(data):
		var old: PackedFloat32Array = data["values"]
		var next := PackedFloat32Array()
		for row in row_count():
			next.append_array(old.slice(row * old_width, row * old_width + at))
			next.append(0)
			next.append_array(old.slice(row * old_width + at, (row + 1) * old_width))
		data["values"] = next; data.column_count = old_width + 1
	else:
		for row in data.arr: row.insert(at, {"type": "float", "val": 0.0})
	_commit()
	return true

func rename_input(column: int, title: String) -> bool:
	title = title.strip_edges()
	if column < 0 or column >= int(data.outputs_from) or title.is_empty(): return false
	for index in column_count():
		if index != column and field_name(index) == title: return false
	_capture()
	data.col_names[column] = title + ":" + field_type(column)
	_commit()
	return true

func numeric_answers() -> void:
	if kind() != "numeric" or studio().get("classes", []).is_empty(): return
	_capture()
	var groups: Array = studio().classes.duplicate()
	var rows: Array = []
	for row in row_count():
		var raw := values(row).slice(0, int(data.outputs_from))
		raw.append(float(groups.find(group_for(row))))
		rows.append(raw)
	data.col_names.resize(int(data.outputs_from))
	data.col_names.append("Ответ:float")
	studio().classes = []
	data["storage"] = "legacy_rows"; data["arr"] = []
	data.erase("values"); data.erase("row_count"); data.erase("column_count")
	# Keep stable split families while replacing the encoded output columns.
	var families: Array = studio().get("family_ids", []).duplicate()
	studio()["family_ids"] = []
	for index in rows.size(): _append(rows[index], int(families[index]) if index < families.size() else index)
	_commit()

func delete_rows(rows: Array) -> void:
	var selected: Array = []
	for raw in rows:
		var row := int(raw)
		if row >= 0 and row < row_count() and not selected.has(row): selected.append(row)
	if selected.is_empty(): return
	_capture()
	_ensure_families()
	selected.sort()
	selected.reverse()
	for row in selected:
		studio().family_ids.remove_at(row)
		if Packed.is_packed(data):
			var old: PackedFloat32Array = data["values"]
			var width := column_count()
			var next: PackedFloat32Array = old.slice(0, row * width)
			next.append_array(old.slice((row + 1) * width))
			data["values"] = next
			data.row_count = row_count() - 1
		else: data.arr.remove_at(row)
	_commit()

func duplicate_rows(rows: Array) -> void:
	if rows.is_empty(): return
	_capture()
	var original_count := row_count()
	for row in rows:
		if int(row) >= 0 and int(row) < original_count: _append(values(int(row)), _family(int(row)))
	_commit()

func import_image(image: Image, group: String) -> bool:
	if kind() != "images" or image == null: return false
	if not classes().has(group): add_class(group)
	var fitted := fit_image(image)
	var raw: Array = [ImageTexture.create_from_image(fitted)]
	for name in studio().classes: raw.append(1 if str(name) == group else 0)
	_append(raw)
	return true

func fit_image(source: Image) -> Image:
	var image: Image = source.duplicate()
	image.resize(int(studio().get("image_width", 28)), int(studio().get("image_height", 28)), Image.INTERPOLATE_LANCZOS)
	image.convert(Image.FORMAT_L8)
	return image

func begin_batch() -> void: _capture()
func end_batch() -> void: _commit()

func augment(rows: Array, copies: int = 1, seed_value: int = 42, strength: float = 0.08) -> int:
	if kind() in ["simulation", "text"]: return 0
	var selected: Array = rows.duplicate()
	if selected.is_empty():
		for row in row_count(): selected.append(row)
	var limit := mini(10000, selected.size() * clampi(copies, 1, 20))
	if limit == 0: return 0
	_capture()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	for index in limit:
		var row := int(selected[index % selected.size()])
		var raw := values(row)
		if kind() == "images" and raw[0] is Texture2D:
			var source: Image = raw[0].get_image()
			var image := Image.create(source.get_width(), source.get_height(), false, Image.FORMAT_L8)
			image.fill(Color.BLACK)
			var shift := Vector2i(rng.randi_range(-2, 2), rng.randi_range(-2, 2))
			for y in source.get_height():
				for x in source.get_width():
					var point := Vector2i(x, y) + shift
					if point.x >= 0 and point.y >= 0 and point.x < image.get_width() and point.y < image.get_height():
						var luminance := clampf(source.get_pixel(x, y).r + rng.randfn(0.0, strength), 0, 1)
						image.set_pixelv(point, Color(luminance, luminance, luminance))
			raw[0] = ImageTexture.create_from_image(image)
		elif kind() == "car":
			# Mirror the full state and its steering target together.
			raw[0] = -float(raw[0]); raw[3] = -float(raw[3])
			raw[2] = wrapf(PI - float(raw[2]), -PI, PI)
			raw[5] = -float(raw[5])
		elif kind() == "simulation": continue
		else:
			for column in int(data.outputs_from):
				if field_type(column) in ["num", "float"]: raw[column] = float(raw[column]) + rng.randfn(0, strength)
		_append(raw, _family(row))
	_commit()
	return limit

func generate(count: int, seed_value: int = 42) -> int:
	if kind() in ["text", "simulation"]: return 0
	if kind() == "images" and not studio().get("rule_shapes", false): return 0
	_capture()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	count = clampi(count, 1, 10000)
	for index in count:
		var raw: Array = []
		for column in column_count(): raw.append(0.0)
		if kind() == "car":
			for column in [0, 1, 3, 4]: raw[column] = rng.randf_range(-1, 1)
			var delta := Vector2(float(raw[3]) - float(raw[0]), float(raw[4]) - float(raw[1]))
			var error := rng.randf_range(-PI, -0.2 * PI) if index % 3 == 0 else rng.randf_range(-0.1 * PI, 0.1 * PI) if index % 3 == 1 else rng.randf_range(0.2 * PI, PI)
			raw[2] = wrapf(delta.angle() - error, -PI, PI)
			raw[5] = clampf(wrapf(delta.angle() - float(raw[2]), -PI, PI) / PI, -1, 1)
			raw[6] = clampf(delta.length(), 0, 1) * (1.0 - absf(float(raw[5])) * 0.7)
		else:
			var group: int = index % maxi(1, studio().get("classes", []).size())
			if kind() == "images":
				var image := _shape_image(group, rng)
				raw[0] = ImageTexture.create_from_image(image)
			else:
				var center := Vector2.from_angle(TAU * group / maxi(1, studio().classes.size())) * 0.65
				for column in int(data.outputs_from): raw[column] = (center.x if column % 2 == 0 else center.y) + rng.randfn(0, 0.12)
				if studio().get("classes", []).is_empty():
					for column in int(data.outputs_from): raw[column] = rng.randf_range(-1, 1)
					for column in range(int(data.outputs_from), column_count()): raw[column] = sin(float(raw[0]) * (column - int(data.outputs_from) + 1)) + (float(raw[1]) * 0.5 if int(data.outputs_from) > 1 else 0)
			if not studio().get("classes", []).is_empty(): raw[int(data.outputs_from) + group] = 1
		_append(raw)
	studio()["last_generation"] = {"seed": seed_value, "count": count, "rule": "steer_to_goal" if kind() == "car" else "labelled_shapes" if kind() == "images" else "separated_clusters"}
	_commit()
	return count

func _shape_image(group: int, rng: RandomNumberGenerator) -> Image:
	var width: int = int(studio().get("image_width", 28))
	var height: int = int(studio().get("image_height", 28))
	var image := Image.create(width, height, false, Image.FORMAT_L8)
	image.fill(Color.BLACK)
	var center := Vector2(width, height) * 0.5 + Vector2(rng.randf_range(-2, 2), rng.randf_range(-2, 2))
	var radius: float = minf(width, height) * rng.randf_range(0.2, 0.32)
	for y in height:
		for x in width:
			var point := Vector2(x, y) - center
			var inside := point.length() < radius if group % 3 == 0 else (maxf(absf(point.x), absf(point.y)) < radius if group % 3 == 1 else point.y > -radius and point.y < radius and absf(point.x) < (point.y + radius) * 0.5)
			if inside: image.set_pixel(x, y, Color.WHITE)
	return image

func refresh_cache() -> void:
	var columns: Array = []
	var args: Array = []
	for column in column_count():
		var entry := {}
		var minimum := INF
		var maximum := -INF
		for row in row_count():
			var item: Variant = value(row, column)
			if field_type(column) == "image" and item is Texture2D:
				var size_key: int = int(item.get_width()) << 16 | int(item.get_height())
				if not entry.has(size_key): entry[size_key] = {}
				entry[size_key][row] = true
			elif item is float or item is int:
				minimum = minf(minimum, float(item)); maximum = maxf(maximum, float(item))
		columns.append(entry)
		args.append({"min": minimum if is_finite(minimum) else 0, "max": maximum if is_finite(maximum) else 1})
	data.cache = {"cols": columns}
	data.col_args = args
	data.erase("col_dtypes")

func _commit() -> void:
	refresh_cache()
	changed.emit()

func quality() -> Dictionary:
	var errors: Array[String] = []
	var warnings: Array[String] = []
	var counts := group_counts()
	if row_count() == 0: errors.append("Добавьте примеры")
	if int(data.get("outputs_from", 0)) < 1 or int(data.get("outputs_from", 0)) >= column_count(): errors.append("Укажите входы и ответы")
	for row in row_count():
		for column in column_count():
			var item: Variant = value(row, column)
			if item == null or (item is float and not is_finite(item)):
				errors.append("Есть пустые или некорректные значения")
				break
			if field_type(column) == "image":
				if not item is Texture2D or item.get_width() <= 0 or item.get_height() <= 0:
					errors.append("Есть некорректное изображение"); break
				if item.get_width() != int(studio().get("image_width", item.get_width())) or item.get_height() != int(studio().get("image_height", item.get_height())):
					errors.append("Изображения разных размеров: примените общий размер набора"); break
		if not errors.is_empty(): break
		if not studio().get("classes", []).is_empty():
			var sum := 0.0
			for column in range(int(data.outputs_from), column_count()): sum += float(value(row, column))
			if not is_equal_approx(sum, 1.0): errors.append("Пример без однозначной метки класса"); break
	if kind() == "text": warnings.append("Текст нужно токенизировать перед обучением")
	for group in counts:
		if int(counts[group]) == 0: warnings.append("Нет примеров: " + str(group))
	var maximum := 0
	var minimum := 2147483647
	for count in counts.values(): maximum = maxi(maximum, int(count)); minimum = mini(minimum, int(count))
	if maximum > maxi(1, minimum) * 4: warnings.append("Классы несбалансированы")
	var train := 0
	for row in row_count():
		if split_for(row) == "train": train += 1
	if train == 0 and row_count() > 0: errors.append("Нет обучающих примеров: измените долю или seed")
	return {"errors": errors, "warnings": warnings, "counts": counts, "train": train, "validation": row_count() - train}

func split_for(row: int) -> String:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(studio().get("split_seed", 42)) + _family(row) * 7919
	return "validation" if rng.randf() < float(studio().get("validation_ratio", 0.2)) else "train"
