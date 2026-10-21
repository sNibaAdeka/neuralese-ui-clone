extends SceneTree
## Production importer regressions for the 2026-10-21 audit fixtures.
const IO = preload("res://scripts/data_workspace/import_export.gd")
const Doc = preload("res://scripts/data_workspace/document.gd")
var _paths: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _read(name: String, contents: String, options: Dictionary = {}) -> Dictionary:
	var path := "user://csv-integrity-" + name
	var file := FileAccess.open(path, FileAccess.WRITE)
	assert(file != null)
	file.store_string(contents)
	file.close()
	_paths.append(path)
	return IO.read_table(path, options)

func _document(result: Dictionary):
	assert(not result.has("error"), str(result))
	var doc = Doc.new()
	doc.attach(result.dataset)
	return doc

func _run() -> void:
	# Audit: numeric header name must not become a training sample or label.
	var mixed := _read("mixed-numeric-header.csv", "x,2024,y\n1,2,3\n4,5,6\n")
	var doc = _document(mixed)
	assert(doc.row_count() == 2 and doc.column_count() == 3)
	assert(doc.field_name(1) == "2024" and doc.field_type(0) == "float")
	assert(doc.values(0) == [1.0, 2.0, 3.0] and doc.values(1) == [4.0, 5.0, 6.0])
	assert(doc.studio().classes.is_empty())
	assert(mixed.csv.has_header and not mixed.csv.header_ambiguous)
	assert(mixed.csv.source_row_count == 3 and mixed.csv.data_row_count == 2)
	# Audit: retain all twelve source columns, including the final answer.
	var wide := _read("twelve-columns.csv", "field01,field02,field03,field04,field05,field06,field07,field08,field09,field10,field11,target\n101,102,103,104,105,106,107,108,109,110,111,112\n201,202,203,204,205,206,207,208,209,210,211,212\n")
	doc = _document(wide)
	assert(doc.row_count() == 2 and doc.column_count() == 12)
	assert(doc.data.outputs_from == 11 and doc.value(1, 11) == 212.0)
	assert(doc.field_name(11) == "target")
	# Audit: quoted semicolons must not win over real comma separators.
	var quoted := _read("quoted-other-delimiter.csv", '"x;y;z",target\n"one;two;three",1\n"four;five;six",2\n')
	doc = _document(quoted)
	assert(quoted.csv.delimiter == "," and doc.row_count() == 2)
	assert(doc.field_name(0) == "x;y;z" and doc.value(0, 0) == "one;two;three")
	# Audit: categorical rows are inherently ambiguous. Explicit absence retains all.
	var categorical_text := "red,cat\nblue,dog\ngreen,cat\n"
	var inferred := _read("categorical-auto.csv", categorical_text)
	assert(inferred.csv.header_ambiguous and inferred.csv.header_inferred)
	var categorical := _read("headerless-categorical.csv", categorical_text, {"header": "absent"})
	doc = _document(categorical)
	assert(doc.row_count() == 3 and doc.value(0, 0) == "red")
	assert(doc.group_for(0) == "cat" and doc.group_for(1) == "dog")
	assert(not categorical.csv.has_header and not categorical.csv.header_inferred)
	assert(categorical.csv.first_row == ["red", "cat"])
	# Ordinary numeric files retain their first sample automatically.
	var numeric := _read("numeric.csv", "1,2,3\n4,5,6\n")
	doc = _document(numeric)
	assert(doc.row_count() == 2 and doc.values(0) == [1.0, 2.0, 3.0])
	assert(not numeric.csv.has_header)
	var mixed_data := _read("mixed-data.csv", "1,cat\n2,dog\n")
	doc = _document(mixed_data)
	assert(doc.row_count() == 2 and not mixed_data.csv.has_header)
	assert(mixed_data.csv.header_ambiguous)
	# Explicit presence can interpret entirely numeric column names.
	var numeric_names := _read("numeric-names.csv", "2023,2024\n1,2\n", {"header": "present"})
	doc = _document(numeric_names)
	assert(doc.row_count() == 1 and doc.field_name(0) == "2023")
	# Real semicolon, tab and pipe files; quoted candidates and escaped quotes.
	for delimiter in [";", "\t", "|"]:
		var text := 'feature%starget\n"one, two; three|four\tand ""five"""%s1\n"six\nseven"%s2\n' % [delimiter, delimiter, delimiter]
		var result := _read("escaped-" + str(delimiter.unicode_at(0)) + ".csv", text)
		doc = _document(result)
		assert(result.csv.delimiter == delimiter and doc.row_count() == 2)
		assert(doc.value(0, 0) == 'one, two; three|four\tand "five"')
		assert(doc.value(1, 0) == "six\nseven")
	var tsv := _read("table.tsv", "a\tb\n1\t2\n")
	assert(tsv.csv.delimiter == "\t" and _document(tsv).row_count() == 1)
	# Preview can override a tied/ambiguous delimiter deliberately.
	var explicit := _read("explicit.csv", "name;target\nleft,right;1\n", {"delimiter": ";", "header": "present"})
	doc = _document(explicit)
	assert(doc.value(0, 0) == "left,right" and not explicit.csv.delimiter_inferred)
	# A stray malformed width must not choose the delimiter or contaminate rows.
	var malformed := _read("width.csv", "x,y,target\n1,2,3\n4,5\n6,7,8\n9,10,11,12\n")
	doc = _document(malformed)
	assert(malformed.csv.delimiter == "," and doc.row_count() == 2)
	assert(malformed.errors.size() == 2 and doc.values(1) == [6.0, 7.0, 8.0])
	var invalid := _read("all-bad.csv", "x,y,target\n1,2\n3,4\n", {"header": "present"})
	assert(invalid.has("error") and invalid.errors.size() == 2 and invalid.has("csv"))
	assert(_read("option.csv", "1,2\n", {"delimiter": "invalid"}).has("error"))
	assert(_read("option-header.csv", "1,2\n", {"header": "invalid"}).has("error"))
	# Existing JSON path is independent of CSV options.
	var json := _read("table.json", '[{"x":1,"y":2},{"x":3,"y":4}]')
	assert(_document(json).row_count() == 2 and not json.has("csv"))
	for path in _paths:
		DirAccess.remove_absolute(path)
	print("PASS test_csv_import_integrity")
	quit(0)
