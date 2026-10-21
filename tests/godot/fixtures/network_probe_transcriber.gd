extends "res://scripts/transcriber.gd"

# Exercise send_recording() without microphone setup, credentials, or HTTP.
var captured_request: Dictionary = {}


func get_headers(_json = true) -> PackedStringArray:
	return PackedStringArray(["Content-Type: application/json"])


func _request_raw(address: String, body: PackedByteArray, headers: PackedStringArray) -> RequestHandle:
	captured_request = {"address": address, "body": body, "headers": headers}
	return RequestHandle.new()
