extends RefCounted
## Export validation and checked disk publication. No network or UI side effects.

static func save_remote(response: Variant, output_path: String, opener: Callable = Callable()) -> Dictionary:
	if not response is Dictionary:
		return _failure("Export returned no response. Please retry.")
	if response.get("cancelled", false):
		return _failure("Export cancelled. Please retry when ready.")
	var code := int(response.get("code", 0))
	var transport_error: Variant = response.get("error", OK)
	if not response.get("ok", false) or code < 200 or code >= 300 or str(transport_error) not in ["0", "", "<null>"]:
		var detail := str(response.get("error_code", response.get("error", "")))
		var status := "HTTP %d" % code if code > 0 else "connection failed"
		return _failure("Export failed (%s)%s. Please retry; check your session or connection if this continues." % [status, ": " + detail if not detail.is_empty() else ""])
	var body: Variant = response.get("body")
	if body is PackedByteArray and not body.is_empty() and body[0] == 123:
		var payload: Variant = JSON.parse_string(body.get_string_from_utf8())
		if payload is Dictionary and (payload.has("error") or payload.get("status", "") == "error"):
			return _failure("Export failed: %s. Please retry." % str(payload.get("error", "server returned an error")))
	return write_bytes(body, output_path, opener)


static func write_bytes(bytes: Variant, output_path: String, opener: Callable = Callable()) -> Dictionary:
	if not bytes is PackedByteArray or bytes.is_empty():
		return _failure("Export returned an empty or invalid file. Please retry.")
	# Stage beside the target so failed writes preserve any earlier export.
	var temp_path := output_path + ".export-%d.tmp" % Time.get_ticks_usec()
	var file = opener.call(temp_path) if opener.is_valid() else FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		return _failure("Cannot write export to %s (%s). Check the folder and available space, then retry." % [output_path, error_string(FileAccess.get_open_error())])
	file.store_buffer(bytes)
	file.flush()
	var write_error: int = file.get_error()
	file.close()
	if write_error != OK:
		DirAccess.remove_absolute(temp_path)
		return _failure("Could not finish writing export to %s (%s). Check available space and retry." % [output_path, error_string(write_error)])
	var publish_error := DirAccess.rename_absolute(temp_path, output_path)
	if publish_error != OK:
		DirAccess.remove_absolute(temp_path)
		return _failure("Cannot save export as %s (%s). Check folder permissions and retry." % [output_path, error_string(publish_error)])
	return {"ok": true, "output_path": output_path}


static func _failure(message: String) -> Dictionary:
	return {"ok": false, "error": message}
