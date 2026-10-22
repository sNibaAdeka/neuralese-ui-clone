extends RefCounted
## Portable, data-only import/export. Never deserialize executable Godot objects.

const Document = preload("res://scripts/data_workspace/document.gd")
const IMAGE_EXTENSIONS := ["png", "jpg", "jpeg", "webp", "bmp"]
const MAX_FILES := 20000
const MAX_TABLE_BYTES := 64 * 1024 * 1024

static func scan_paths(paths: Array) -> Dictionary:
	var result := {"images": [], "tables": [], "texts": [], "ignored": [], "errors": [], "limited": false}
	for raw in paths:
		var path := str(raw).replace("\\", "/")
		if DirAccess.dir_exists_absolute(path): _scan_directory(path, path, result, 0)
		elif FileAccess.file_exists(path): _classify(path, path.get_base_dir(), result)
		else: result.errors.append("Не найдено: " + path)
	return result

static func _scan_directory(path: String, root: String, result: Dictionary, depth: int) -> void:
	if depth > 24:
		result.errors.append("Слишком глубокая папка: " + path)
		return
	var directory := DirAccess.open(path)
	if directory == null:
		result.errors.append("Не удалось открыть папку: " + path)
		return
	var names := directory.get_files()
	names.sort()
	for name in names:
		if _file_count(result) >= MAX_FILES:
			result.limited = true
			return
		if not name.begins_with("."): _classify(path.path_join(name), root, result)
	var children := directory.get_directories()
	children.sort()
	for name in children:
		if result.limited: return
		if name.begins_with(".") or directory.is_link(name): continue
		_scan_directory(path.path_join(name), root, result, depth + 1)

static func _file_count(result: Dictionary) -> int:
	return result.images.size() + result.tables.size() + result.texts.size() + result.ignored.size()

static func _classify(path: String, root: String, result: Dictionary) -> void:
	var relative := path.trim_prefix(root.path_join(""))
	var group := relative.get_slice("/", 0) if relative.contains("/") else root.get_file()
	var entry := {"path": path, "class": group if not group.is_empty() else "Без класса"}
	var extension := path.get_extension().to_lower()
	if extension in IMAGE_EXTENSIONS: result.images.append(entry)
	elif extension in ["csv", "tsv", "json"]: result.tables.append(entry)
	elif extension in ["txt", "md"]: result.texts.append(entry)
	else: result.ignored.append(path)

## CSV options: delimiter = auto/comma/semicolon/tab/pipe character;
## header = auto/present/absent. Existing callers retain automatic inference.
## The result's `csv` metadata makes ambiguous inference visible to a preview.
static func read_table(path: String, options: Dictionary = {}) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return {"error": "Не удалось открыть " + path.get_file()}
	if file.get_length() > MAX_TABLE_BYTES: return {"error": "Таблица больше 64 МБ: " + path.get_file()}
	if path.get_extension().to_lower() == "json":
		var parser := JSON.new()
		if parser.parse(file.get_as_text()) != OK: return {"error": "JSON, строка %d: %s" % [parser.get_error_line(), parser.get_error_message()]}
		return _json_dataset(parser.data, path.get_file().get_basename())
	var delimiter_option := str(options.get("delimiter", "auto"))
	var header_mode := str(options.get("header", "auto"))
	if delimiter_option not in ["auto", ",", ";", "\t", "|"]:
		return {"error": "Неизвестный разделитель CSV"}
	if header_mode not in ["auto", "present", "absent"]:
		return {"error": "Заголовок CSV: auto, present или absent"}
	var delimiter := delimiter_option
	if delimiter == "auto":
		delimiter = _csv_delimiter(file, "\t" if path.get_extension().to_lower() == "tsv" else ",")
	file.seek(0)
	var rows: Array = []
	while file.get_position() < file.get_length():
		var line := file.get_csv_line(delimiter)
		if line.size() == 1 and line[0].strip_edges().is_empty(): continue
		rows.append(Array(line))
	if rows.is_empty(): return {"error": "Файл пуст"}
	var inference := _csv_header(rows)
	var has_header: bool = inference.has_header if header_mode == "auto" else header_mode == "present"
	var metadata := {
		"delimiter": delimiter, "delimiter_inferred": delimiter_option == "auto",
		"header_mode": header_mode, "has_header": has_header,
		"header_inferred": header_mode == "auto", "header_ambiguous": inference.ambiguous,
		"header_reason": inference.reason, "first_row": rows[0].duplicate(),
		"source_row_count": rows.size(), "data_row_count": rows.size() - (1 if has_header else 0),
	}
	var headers: Array = []
	if has_header: headers = rows.pop_front()
	else:
		for column in rows[0].size(): headers.append("Поле %d" % (column + 1))
	var result := from_rows(headers, rows, path.get_file().get_basename())
	result["csv"] = metadata
	return result

## Evaluate several parsed records for each candidate. Godot's CSV parser already
## handles quoted separators, doubled quotes and multiline fields; counting raw
## characters would mistake quoted content for column separators.
static func _csv_delimiter(file: FileAccess, preferred: String) -> String:
	var best := preferred
	var best_matches := 0
	var best_ratio := 0.0
	var best_width := 0
	var candidates := [preferred]
	for candidate in [",", ";", "\t", "|"]:
		if not candidates.has(candidate): candidates.append(candidate)
	for candidate in candidates:
		file.seek(0)
		var widths: Dictionary = {}
		var count := 0
		while file.get_position() < file.get_length() and count < 32:
			var row := file.get_csv_line(candidate)
			if row.size() == 1 and row[0].strip_edges().is_empty(): continue
			count += 1
			if row.size() > 1: widths[row.size()] = int(widths.get(row.size(), 0)) + 1
		for width in widths:
			var matches := int(widths[width])
			var ratio := float(matches) / maxi(count, 1)
			if matches > best_matches or (matches == best_matches and ratio > best_ratio) or (matches == best_matches and is_equal_approx(ratio, best_ratio) and int(width) > best_width):
				best = candidate
				best_matches = matches
				best_ratio = ratio
				best_width = int(width)
	return best

static func _csv_header(rows: Array) -> Dictionary:
	var first: Array = rows[0]
	var numeric_count := 0
	for cell in first:
		if str(cell).strip_edges().is_valid_float(): numeric_count += 1
	if numeric_count == first.size():
		return {"has_header": false, "ambiguous": false, "reason": "numeric_first_row"}
	# A text name above a consistently numeric column is evidence of a header,
	# including mixed names such as x,2024,y. Ignore malformed rows as evidence.
	for column in first.size():
		if str(first[column]).strip_edges().is_valid_float(): continue
		var numeric_below := 0
		var text_below := 0
		for index in range(1, mini(rows.size(), 33)):
			var row: Array = rows[index]
			if row.size() != first.size(): continue
			var cell := str(row[column]).strip_edges()
			if cell.is_empty(): continue
			if cell.is_valid_float(): numeric_below += 1
			else: text_below += 1
		if numeric_below > 0 and text_below == 0:
			return {"has_header": true, "ambiguous": false, "reason": "column_type_change"}
	# Categorical values cannot be distinguished from names without user input.
	# Retain the old all-text default, but report the ambiguity for explicit choice.
	return {"has_header": numeric_count == 0, "ambiguous": true, "reason": "ambiguous_first_row"}

static func from_rows(headers: Array, rows: Array, title: String) -> Dictionary:
	if headers.size() < 2: return {"error": "Нужны входные поля и хотя бы один ответ"}
	var errors: Array[String] = []
	var good: Array = []
	for index in rows.size():
		if not rows[index] is Array or rows[index].size() != headers.size():
			errors.append("Строка %d: другое число столбцов" % (index + 1))
		else: good.append(rows[index])
	if good.is_empty(): return {"error": "Нет корректных строк", "errors": errors}
	var numeric: Array[bool] = []
	for column in headers.size():
		var is_number := true
		for row in good:
			if not str(row[column]).strip_edges().is_empty() and not str(row[column]).is_valid_float(): is_number = false
		numeric.append(is_number)
	var labels: Array = []
	if not numeric.back():
		for row in good:
			var label := str(row.back()).strip_edges()
			if label.is_empty(): label = "Без класса"
			if not labels.has(label): labels.append(label)
	var document = Document.new()
	document.create(title, "numeric")
	document.data.col_names = []
	document.data.outputs_from = headers.size() - 1
	document.studio()["classes"] = labels
	for column in headers.size() - (1 if not labels.is_empty() else 0):
		document.data.col_names.append(str(headers[column]).strip_edges() + (":float" if numeric[column] else ":text"))
	for label in labels: document.data.col_names.append(str(label) + ":num")
	for row in good:
		var raw: Array = []
		for column in headers.size() - (1 if not labels.is_empty() else 0):
			raw.append(float(row[column]) if numeric[column] and not str(row[column]).strip_edges().is_empty() else (NAN if numeric[column] else str(row[column])))
		if not labels.is_empty():
			var label := str(row.back()).strip_edges()
			if label.is_empty(): label = "Без класса"
			for target in labels: raw.append(1 if target == label else 0)
		document._append(raw)
	document.refresh_cache()
	return {"dataset": document.data, "errors": errors}

static func _json_dataset(parsed: Variant, title: String) -> Dictionary:
	if parsed is Array:
		if parsed.is_empty() or not parsed[0] is Dictionary: return {"error": "Ожидается массив объектов с одинаковыми полями"}
		var headers: Array = parsed[0].keys()
		var rows: Array = []
		for item in parsed:
			if not item is Dictionary: return {"error": "Все записи должны быть объектами"}
			var row: Array = []
			for column in headers: row.append(item.get(column, ""))
			rows.append(row)
		return from_rows(headers, rows, title)
	if not parsed is Dictionary: return {"error": "Неизвестный формат JSON"}
	var names: Variant = parsed.get("columns", parsed.get("col_names", []))
	var rows: Variant = parsed.get("rows", parsed.get("arr", []))
	if not names is Array or not rows is Array or names.size() < 2: return {"error": "Нет схемы columns/col_names и rows/arr"}
	var output_value: Variant = parsed.get("outputs_from", names.size() - 1)
	if not (output_value is int or output_value is float) or not is_finite(float(output_value)) or float(output_value) != floor(float(output_value)):
		return {"error": "outputs_from должен быть целым числом"}
	if float(output_value) < 1 or float(output_value) >= names.size(): return {"error": "outputs_from должен разделять входы и ответы"}
	var outputs := int(output_value)
	var document = Document.new()
	var metadata: Variant = parsed.get("metadata", {})
	if not metadata is Dictionary or not _is_json_data(metadata): return {"error": "metadata должен содержать только данные JSON"}
	var studio: Variant = parsed.get("studio", metadata.get("studio", {}))
	if not studio is Dictionary or not _is_json_data(studio) or not studio.get("classes", []) is Array: return {"error": "Некорректные параметры набора"}
	for name in names:
		if not name is String: return {"error": "Названия полей должны быть строками"}
	if not studio.get("classes", []).is_empty() and studio.classes.size() != names.size() - outputs: return {"error": "Количество классов не совпадает с выходами"}
	var restored_metadata: Dictionary = metadata.duplicate(true)
	restored_metadata["studio"] = studio.duplicate(true)
	document.attach({"name": str(parsed.get("name", title)), "arr": [], "col_names": names.duplicate(), "outputs_from": outputs, "cache": {}, "col_args": [], "metadata": restored_metadata})
	if document.studio().is_empty(): document.data.metadata.erase("studio"); document.attach(document.data)
	# _append creates local family IDs. Restore the exported IDs after loading so
	# round trips retain augmentation families and their train/validation split.
	var restored_studio := document.studio().duplicate(true)
	for index in rows.size():
		var row: Variant = rows[index]
		if not row is Array or row.size() != names.size(): return {"error": "Некорректная ширина строки %d" % (index + 1)}
		var raw: Array = []
		for column in names.size():
			var item: Variant = row[column]
			if document.field_type(column) == "image":
				if not item is Dictionary or not item.get("png", "") is String: return {"error": "Ожидаются PNG-данные изображения"}
				var image := Image.new()
				if image.load_png_from_buffer(Marshalls.base64_to_raw(item.get("png", ""))) != OK: return {"error": "Повреждённое изображение в строке %d" % (index + 1)}
				if image.get_width() > 4096 or image.get_height() > 4096: return {"error": "Изображение больше 4096 пикселей"}
				raw.append(ImageTexture.create_from_image(image))
			else:
				var value: Variant = item.get("num", item.get("val", item.get("text", null))) if item is Dictionary else item
				if document.field_type(column) in ["float", "num"]:
					var validated := _json_number(value, document.field_type(column) == "num")
					if validated.has("error"):
						return {"error": "Строка %d, столбец %d (%s): %s" % [index + 1, column + 1, names[column], validated.error], "row": index + 1, "column": column + 1}
					value = validated.value
				raw.append(value)
		document._append(raw)
	for key in ["family_ids", "next_family"]:
		if restored_studio.has(key): document.studio()[key] = restored_studio[key]
	document.refresh_cache()
	return {"dataset": document.data, "errors": []}

static func _json_number(value: Variant, integer: bool) -> Dictionary:
	if integer and value is int: return {"value": value}
	if value is String:
		value = value.strip_edges()
		if value.is_empty() or not value.is_valid_float(): return {"error": "Ожидается число"}
		# Parse integer strings directly: passing through float would round valid
		# 64-bit values above 2^53 before the document stores them as integers.
		if integer and value.is_valid_int():
			var negative: bool = value.begins_with("-")
			var digits: String = value.trim_prefix("-").trim_prefix("+").lstrip("0")
			var limit := "9223372036854775808" if negative else "9223372036854775807"
			if digits.length() > limit.length() or (digits.length() == limit.length() and digits > limit):
				return {"error": "Ожидается целое число в допустимом диапазоне"}
			return {"value": value.to_int()}
	elif not (value is int or value is float):
		return {"error": "Ожидается число"}
	var number := float(value)
	if not is_finite(number): return {"error": "Число должно быть конечным"}
	if integer and (number != floor(number) or number < -9223372036854775808.0 or number >= 9223372036854775808.0):
		return {"error": "Ожидается целое число в допустимом диапазоне"}
	return {"value": int(number) if integer else number}

## Accept data containers only; never encode Resources, Objects or Godot values
## as strings. The depth guard also rejects cyclic in-memory metadata on export.
static func _is_json_data(value: Variant, depth: int = 0) -> bool:
	if depth > 64: return false
	if value == null or value is bool or value is int or value is String: return true
	if value is float: return is_finite(value)
	if value is Array:
		for item in value:
			if not _is_json_data(item, depth + 1): return false
		return true
	if value is Dictionary:
		for key in value:
			if not key is String or not _is_json_data(value[key], depth + 1): return false
		return true
	return false

## Explicit data-only encodings for the primitive values used by simulation
## bindings, ranges and episode paths. Readers receive ordinary JSON arrays and
## strings, which simulation schemas already accept; no objects are recreated.
static func _metadata_json_value(value: Variant, depth: int = 0) -> Dictionary:
	if depth > 64: return {"error": "Слишком глубокая структура параметров"}
	if value is StringName: return {"value": str(value)}
	if value is Vector2:
		if not value.is_finite(): return {"error": "Неконечные координаты"}
		return {"value": [value.x, value.y]}
	if value is Array or value is PackedStringArray or value is PackedInt32Array or value is PackedInt64Array or value is PackedFloat32Array or value is PackedFloat64Array or value is PackedVector2Array:
		var result: Array = []
		for item in value:
			var converted := _metadata_json_value(item, depth + 1)
			if converted.has("error"): return converted
			result.append(converted.value)
		return {"value": result}
	if value is Dictionary:
		var result: Dictionary = {}
		for key in value:
			if not (key is String or key is StringName): return {"error": "Ключ параметра должен быть строкой"}
			var converted := _metadata_json_value(value[key], depth + 1)
			if converted.has("error"): return converted
			result[str(key)] = converted.value
		return {"value": result}
	if _is_json_data(value): return {"value": value}
	return {"error": "Значение несовместимо с JSON"}

static func portable(document) -> Dictionary:
	var source_metadata: Variant = document.data.get("metadata", {})
	if not source_metadata is Dictionary: return {"error": "Параметры набора должны быть объектом"}
	var converted := _metadata_json_value(source_metadata)
	if converted.has("error"): return converted
	var metadata: Dictionary = converted.value
	var rows: Array = []
	for row in document.row_count():
		var values: Array = []
		for column in document.column_count():
			var item: Variant = document.value(row, column)
			if document.field_type(column) in ["float", "num"]:
				var validated := _json_number(item, document.field_type(column) == "num")
				if validated.has("error"):
					return {"error": "Строка %d, столбец %d: %s" % [row + 1, column + 1, validated.error]}
				values.append(validated.value)
			elif item is Texture2D: values.append({"png": Marshalls.raw_to_base64(item.get_image().save_png_to_buffer())})
			else: values.append(item)
		rows.append(values)
	return {"format": "neuralese.dataset.v1", "name": document.data.name, "columns": document.data.col_names, "outputs_from": document.data.outputs_from, "studio": metadata.get("studio", {}).duplicate(true), "metadata": metadata, "rows": rows}

static func export_file(document, path: String) -> Error:
	if path.get_extension().to_lower() == "csv" and document.kind() == "images": return ERR_UNAVAILABLE
	var payload: Dictionary = {}
	if path.get_extension().to_lower() != "csv":
		payload = portable(document)
		if payload.has("error"): return ERR_INVALID_DATA
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null: return FileAccess.get_open_error()
	if path.get_extension().to_lower() == "csv":
		var headers := PackedStringArray()
		for column in document.column_count(): headers.append(document.field_name(column))
		file.store_csv_line(headers)
		for row in document.row_count():
			var cells := PackedStringArray()
			for item in document.values(row): cells.append(str(item))
			file.store_csv_line(cells)
	else: file.store_string(JSON.stringify(payload, "\t", true, true))
	return OK
