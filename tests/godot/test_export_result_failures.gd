extends SceneTree
## Mocked transport payloads only; no network, login, or model-runtime validation.
const ExportResult = preload("res://scripts/export_result.gd")
var failures: Array[String] = []

class FailedWriter extends RefCounted:
	func store_buffer(_bytes: PackedByteArray) -> void:
		pass
	func flush() -> void:
		pass
	func get_error() -> int:
		return ERR_FILE_CANT_WRITE
	func close() -> void:
		pass

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var export_script = load("res://scripts/model_export.gd")
	_expect(export_script != null and export_script.can_instantiate(), "export handler compiles with project autoloads")
	var folder := "user://export-result-test-%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(folder)
	var path := folder.path_join("model.onnx")
	var bytes := PackedByteArray([8, 1, 18, 2, 3, 4])
	var success := {"ok": true, "code": 200, "body": bytes, "result": OK}
	_expect(ExportResult.save_remote(success, path).ok, "mock HTTP 200 writes payload")
	_expect(FileAccess.get_file_as_bytes(path) == bytes, "saved bytes match exactly")
	for code in [403, 500]:
		var denied := {"ok": false, "code": code, "body": '{"error":"denied"}'.to_utf8_buffer()}
		var result := ExportResult.save_remote(denied, path)
		_expect(not result.ok and str(result.error).contains(str(code)), "HTTP %d has actionable failure" % code)
		_expect(FileAccess.get_file_as_bytes(path) == bytes, "HTTP error preserves earlier file")
		var absent_path := folder.path_join("failed-%d.onnx" % code)
		_expect(not ExportResult.save_remote(denied, absent_path).ok and not FileAccess.file_exists(absent_path), "HTTP error creates no model")
	for response in [null, {}, {"ok": true, "code": 200, "body": PackedByteArray()}, {"ok": true, "code": 200, "body": bytes, "cancelled": true}, {"ok": false, "code": 200, "body": bytes}, {"ok": true, "code": 200, "body": bytes, "error": ERR_TIMEOUT}, {"ok": true, "code": 200, "body": '{"error":"export failed"}'.to_utf8_buffer()}]:
		_expect(not ExportResult.save_remote(response, path).ok, "invalid, empty, cancelled, or failed response is rejected")
		_expect(FileAccess.get_file_as_bytes(path) == bytes, "failed response preserves earlier file")
	var missing_path := folder.path_join("missing/model.onnx")
	var open_failure := ExportResult.save_remote(success, missing_path)
	_expect(not open_failure.ok and str(open_failure.error).contains(missing_path), "open failure includes destination")
	var failed_write := ExportResult.write_bytes(bytes, path, func(_path: String): return FailedWriter.new())
	_expect(not failed_write.ok, "injected store/flush failure is rejected")
	_expect(FileAccess.get_file_as_bytes(path) == bytes, "store failure preserves earlier file")
	# Publishing over a directory must fail after a successful staged write.
	var directory_path := folder.path_join("blocked.nls")
	DirAccess.make_dir_absolute(directory_path)
	_expect(not ExportResult.write_bytes(bytes, directory_path).ok, "publish failure is rejected")
	var project_path := folder.path_join("project.nls")
	_expect(not ExportResult.write_bytes(PackedByteArray(), project_path).ok, "empty project export rejected")
	_expect(ExportResult.write_bytes(bytes, project_path).ok, "project retries after failure")
	_expect(ExportResult.save_remote(success, path).ok, "model retries after failure")
	DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(project_path)
	DirAccess.remove_absolute(directory_path)
	_expect(DirAccess.get_files_at(folder).is_empty(), "failed stages cleaned up")
	DirAccess.remove_absolute(folder)
	if failures.is_empty():
		print("PASS test_export_result_failures")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)

func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
