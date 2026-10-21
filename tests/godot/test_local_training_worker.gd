extends Node

const WorkerScript := preload("res://scripts/local_training_worker.gd")

var packets: Array[Dictionary] = []
var prepared_handles: Array[Dictionary] = []


func _ready() -> void:
	var worker = WorkerScript.new()
	worker.packet_received.connect(func(packet: Dictionary): packets.append(packet))
	worker.prepared.connect(func(handle: Dictionary): prepared_handles.append(handle))

	var first := {"request_id": 1, "event": "PONG", "data": {"ready": true}}
	var second := {
		"request_id": 2,
		"event": "PREPARED",
		"data": {"prepared_id": "p-1", "graph_generation": 9},
	}
	var bytes: PackedByteArray = WorkerScript.encode_frame(first)
	bytes.append_array(WorkerScript.encode_frame(second))
	worker._feed_bytes(bytes.slice(0, 3))
	assert(packets.is_empty())
	worker._feed_bytes(bytes.slice(3, 11))
	assert(packets.is_empty())
	worker._feed_bytes(bytes.slice(11))
	assert(packets.size() == 2)
	assert(packets[0].event == "PONG" and int(packets[0].request_id) == 1)
	assert(packets[1].event == "PREPARED" and int(packets[1].request_id) == 2)
	assert(prepared_handles.size() == 1)
	assert(prepared_handles[0].prepared_id == "p-1" and int(prepared_handles[0].graph_generation) == 9)

	var oversized := PackedByteArray([0, 128, 0, 1])
	worker._feed_bytes(oversized)
	assert(worker.state == "failed")

	print("PASS test_local_training_worker")
	get_tree().quit()
