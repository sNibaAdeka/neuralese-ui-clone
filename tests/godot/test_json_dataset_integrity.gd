extends SceneTree
## Exercise the production JSON importer/exporter using synthetic data only.
const IO = preload("res://scripts/data_workspace/import_export.gd")
const Randomization = preload("res://scripts/simulations/simulation_randomization_profile.gd")
const Binding = preload("res://scripts/simulations/simulation_model_binding.gd")
const Doc = preload("res://scripts/data_workspace/document.gd")
var _paths: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _read(payload: Dictionary) -> Dictionary:
	var path := "user://json-integrity-input.json"
	_paths.append(path)
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(payload))
	file.close()
	return IO.read_table(path)

func _schema(value: Variant, kind: String = "float") -> Dictionary:
	return {"columns": ["sensor:" + kind, "target:float"], "outputs_from": 1, "rows": [[1, 2], [value, 3]]}

func _run() -> void:
	for value in ["not-a-number", "12px", "", " ", true, false, null, [], {}, {"value": 4}, {"val": "bad"}, {"num": true}, {"text": "bad"}, {"val": null}, "NaN", "INF"]:
		var rejected := _read(_schema(value))
		assert(rejected.has("error") and not rejected.has("dataset"), "Invalid numeric value must never produce a dataset")
		assert(rejected.get("row") == 2 and rejected.get("column") == 1, "Report exact 1-based cell coordinates")
		assert(str(rejected.error).contains("Строка 2, столбец 1"))
	for value in [NAN, INF, -INF]:
		var rejected := IO._json_dataset(_schema(value), "Synthetic nonfinite")
		assert(rejected.has("error") and rejected.get("row") == 2 and rejected.get("column") == 1)
	for value in [0, -3, 2.5, " 3.25 ", "2e-3", {"val": "4.5"}, {"num": 7}, {"text": "9.0"}]:
		var accepted := _read(_schema(value))
		assert(not accepted.has("error"), str(accepted))
		var doc = Doc.new(); doc.attach(accepted.dataset)
		var expected: Variant = value.get("val", value.get("num", value.get("text", null))) if value is Dictionary else value
		assert(doc.value(1, 0) == float(expected), "Valid numeric values retain their value")
	for value in [3.5, "3.5", "1e30", {"num": "bad"}, null, true]:
		var rejected := _read(_schema(value, "num"))
		assert(rejected.has("error") and rejected.get("row") == 2 and rejected.get("column") == 1)
	var accepted_integer := _read(_schema({"num": "3"}, "num"))
	assert(not accepted_integer.has("error"))
	for integer_text in ["9007199254740993", "9223372036854775807", "-9223372036854775808"]:
		var large := _read(_schema(integer_text, "num"))
		assert(not large.has("error"), str(large))
		var large_doc = Doc.new(); large_doc.attach(large.dataset)
		assert(large_doc.value(1, 0) == integer_text.to_int(), "Integer strings cannot round through float")
	for integer_text in ["9223372036854775808", "-9223372036854775809", "9999999999999999999999999999"]:
		assert(_read(_schema(integer_text, "num")).has("error"))
	for bad_output in ["1", true, null, 1.5, -1, 3]:
		var schema := _schema(3)
		schema.outputs_from = bad_output
		assert(_read(schema).has("error"), "Invalid role boundary must not be silently coerced")
	var malformed := _schema(4)
	malformed.rows[1] = [4]
	assert(_read(malformed).has("error"))

	var original = Doc.new()
	original.create("Synthetic simulation metadata")
	original._append([1.0, 2.0, 1, 0])
	original._append([3.0, 4.0, 0, 1])
	original.augment([0], 1, 7)
	original.studio()["kind"] = "simulation"
	original.data.metadata.merge({
		"binding": {"synthetic": true, "schema_version": 1, "input_width": 2, "output_width": 2, "inputs": ["x", "y"]},
		"episodes": [{"episode": 0, "sample_start": 0, "sample_count": 3, "success": true}],
		"randomization": {"enabled": true, "seed": 17, "ranges": {"speed": [0.25, 1.5]}},
		"quality_status": "warning", "quality_warning": "Synthetic warning",
		"output_statistics": [{"minimum": 0, "maximum": 1}],
		"collapsed_outputs": ["synthetic"], "partial": false, "notes": null,
	})
	original.refresh_cache()
	var snapshot: Dictionary = original.data.metadata.duplicate(true)
	# Godot JSON decodes every number as float; compare in the JSON domain.
	var json_snapshot: Dictionary = JSON.parse_string(JSON.stringify(snapshot))
	var path := "user://json-integrity-roundtrip.json"
	_paths.append(path)
	assert(IO.export_file(original, path) == OK)
	var imported := IO.read_table(path)
	assert(not imported.has("error"), str(imported))
	var restored = Doc.new(); restored.attach(imported.dataset)
	assert(restored.data.metadata == json_snapshot, "All JSON-safe metadata and studio family state survive exactly")
	assert(original.data.metadata == snapshot, "Export must not mutate the source metadata")
	assert(restored.data.col_names == original.data.col_names and restored.data.outputs_from == original.data.outputs_from)
	for row in original.row_count():
		assert(restored.values(row) == original.values(row))
		assert(restored.split_for(row) == original.split_for(row), "Round trips cannot split augmentation families")
	assert(restored.studio().family_ids.size() == original.row_count(), "No duplicate IDs appended during import")
	assert(restored.studio().family_ids[0] == restored.studio().family_ids[2])
	# The portable return value must not alias the document's nested metadata.
	var portable := IO.portable(original)
	portable.metadata.binding.synthetic = false
	assert(original.data.metadata.binding.synthetic)
	# Old v1 top-level studio and metadata-only schemas remain readable.
	var old := _schema(3)
	old["studio"] = {"kind": "numeric", "classes": [], "split_seed": 9}
	var old_result := _read(old)
	assert(not old_result.has("error") and old_result.dataset.metadata.studio.split_seed == 9)
	var metadata_only := _schema(3)
	metadata_only["metadata"] = {"binding": {"input_width": 1, "output_width": 1}, "episodes": []}
	var inferred := _read(metadata_only)
	assert(not inferred.has("error") and inferred.dataset.metadata.studio.kind == "simulation")
	assert(inferred.dataset.metadata.binding == JSON.parse_string(JSON.stringify(metadata_only.metadata.binding)))
	# Data shaped like an object stays plain data; never instantiate it.
	metadata_only.metadata["custom"] = {"__class__": "Resource", "script": "res://does-not-exist.gd"}
	var inert := _read(metadata_only)
	assert(inert.dataset.metadata.custom is Dictionary)
	assert(_read({"columns": ["x:float", "y:float"], "rows": [[1, 2]], "metadata": []}).has("error"))
	# Real simulation schemas contain Vector2 ranges, path points and StringNames.
	var simulation = Doc.new(); simulation.create("Simulation value metadata")
	simulation._append([1, 2, 1, 0])
	simulation.data.metadata["binding"] = Binding.create_default(&"side_view_car")
	simulation.data.metadata["randomization"] = Randomization.active_config({"start_position": true, "initial_speed": {"enabled": true, "range": Vector2(0.25, 1.5)}})
	simulation.data.metadata["episodes"] = [{"expert_path_positions": [Vector2(1.25, 2.5), Vector2(3, 4)], "randomization": {"start_position": Vector2(1, 2)}}]
	var simulation_path := "user://json-integrity-simulation.json"
	_paths.append(simulation_path)
	assert(IO.export_file(simulation, simulation_path) == OK)
	var sim_import := IO.read_table(simulation_path)
	assert(not sim_import.has("error"), str(sim_import))
	var sim_meta: Dictionary = sim_import.dataset.metadata
	assert(Binding.validate(sim_meta.binding).valid, "Data-only binding still validates")
	assert(Randomization.validate(sim_meta.randomization).valid)
	assert(Randomization.vector_value(sim_meta.randomization, "initial_speed") == Vector2(0.25, 1.5))
	assert(sim_meta.episodes[0].expert_path_positions[0] == [1.25, 2.5])
	assert(simulation.data.metadata.randomization.initial_speed.range is Vector2, "Export does not mutate Godot value metadata")
	# Arbitrary in-memory Godot values cannot be silently stringified as metadata.
	var unsafe = Doc.new(); unsafe.create("Unsafe metadata"); unsafe._append([1, 2, 1, 0])
	var resource := Resource.new()
	for value in [resource, Vector3(1, 2, 3), NAN, INF, {1: "non-string key"}]:
		unsafe.data.metadata["custom"] = value
		assert(IO.portable(unsafe).has("error"))
		assert(IO.export_file(unsafe, path) == ERR_INVALID_DATA)
		assert(IO.read_table(path).dataset.metadata == json_snapshot, "Invalid export must leave existing files intact")
	unsafe.data.metadata.erase("custom")
	unsafe.set_value(0, 0, INF)
	assert(IO.portable(unsafe).has("error"), "Nonfinite samples must not silently become JSON null")
	assert(IO.export_file(unsafe, path) == ERR_INVALID_DATA)
	assert(IO.read_table(path).dataset.metadata == json_snapshot)
	for path_to_remove in _paths:
		DirAccess.remove_absolute(path_to_remove)
	print("PASS test_json_dataset_integrity")
	quit(0)
