extends Node

signal gift_requested(seat: int, recipient: int, amount: int)
signal gift_result(status: String)
signal paired()
signal lobby_changed()
signal connection_lost(reason: String)
signal action_received(seat: int, action: String, session_id: int)
signal frame_received(frame: Dictionary)

const PORT := 24731
const SERVER_ID := 1
const MAX_FRAME_BYTES := 32768
const CONNECT_TIMEOUT := 8.0

var _peer: ENetMultiplayerPeer
var _is_host := false
var local_seat := -1
var target_count := 0
var connected_count := 0
var _started := false
var _gift_pending := false
var _seats: Dictionary = {}
var _connect_seconds := 0.0


func _ready() -> void:
	# All traffic is host-authoritative and clients never send packets to one another.
	if multiplayer is SceneMultiplayer:
		multiplayer.server_relay = false
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	set_process(false)


func host_room(count: int = 2) -> Error:
	if count < 2 or count > 4:
		return ERR_INVALID_PARAMETER
	leave_room()
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_server(PORT, count-1)
	if error != OK:
		return error
	_peer = peer
	_is_host = true
	local_seat = 0
	target_count = count
	connected_count = 1
	_seats[SERVER_ID] = 0
	multiplayer.multiplayer_peer = peer
	return OK


func join_room(address: String) -> Error:
	leave_room()
	var target := address.strip_edges()
	if target.to_lower() == "localhost":
		target = "127.0.0.1"
	if not target.is_valid_ip_address():
		return ERR_INVALID_PARAMETER
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_client(target, PORT)
	if error != OK:
		return error
	_peer = peer
	multiplayer.multiplayer_peer = peer
	_connect_seconds = CONNECT_TIMEOUT
	set_process(true)
	return OK


func leave_room() -> void:
	set_process(false)
	var previous := _peer
	_peer = null
	_seats.clear()
	_gift_pending = false
	local_seat = -1
	target_count = 0
	connected_count = 0
	_started = false
	_is_host = false
	if previous != null:
		multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
		previous.close()


func _process(delta: float) -> void:
	_connect_seconds -= delta
	if _connect_seconds <= 0.0:
		_fail(_peer, "连接超时。请检查房主地址、房间人数和局域网连接。")


func _on_peer_connected(id: int) -> void:
	if _peer == null or not _is_host or _started or _seats.has(id):
		return
	_seats[id] = _seats.size()
	connected_count = _seats.size()
	_started = connected_count == target_count
	_peer.refuse_new_connections = _started
	for remote_id: int in _seats:
		if remote_id != SERVER_ID:
			_sync_lobby.rpc_id(remote_id, _seats[remote_id], target_count, connected_count)
	lobby_changed.emit()
	if _started:
		paired.emit()


func _on_connected_to_server() -> void:
	set_process(false)


@rpc("authority", "call_remote", "reliable")
func _sync_lobby(seat: int, capacity: int, joined: int) -> void:
	if _peer == null or _is_host or _started:
		return
	local_seat = seat
	target_count = capacity
	connected_count = joined
	_started = joined == capacity
	lobby_changed.emit()
	if _started:
		paired.emit()


func _on_peer_disconnected(id: int) -> void:
	if _is_host and _seats.has(id):
		_started = false
		_fail.call_deferred(_peer, "有矿工离开，房间已关闭。")


func _on_connection_failed() -> void:
	_fail.call_deferred(_peer, "加入失败。请检查房间是否已满，以及房主地址。")


func _on_server_disconnected() -> void:
	_fail.call_deferred(_peer, "与房主的连接已断开。")


func _fail(expected: ENetMultiplayerPeer, reason: String) -> void:
	# A deferred event from a closed room must not close the next room.
	if expected == null or expected != _peer:
		return
	leave_room()
	connection_lost.emit(reason)


func send_action(action: String, session_id: int) -> void:
	if _peer != null and not _is_host and _started:
		_submit.rpc_id(SERVER_ID, action, session_id)


@rpc("any_peer", "call_remote", "reliable")
func _submit(action: String, session_id: int) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if _is_host and _started and sender != SERVER_ID and _seats.has(sender):
		if action in ["fire", "winch", "drill", "invest", "launch", "market", "move_left", "move_right", "move_stop", "inspect", "open", "sell", "build_cutter", "cut"]:
			action_received.emit(_seats[sender], action, session_id)


func send_gift(recipient: int, amount: int) -> bool:
	if _peer == null or _is_host or not _started or _gift_pending:
		return false
	_gift_pending = true
	if rpc_id(SERVER_ID, &"_request_gift", recipient, amount) != OK:
		_gift_pending = false
		return false
	return true


@rpc("any_peer", "call_remote", "reliable")
func _request_gift(recipient: int, amount: int) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if _is_host and _started and sender != SERVER_ID and _seats.has(sender):
		gift_requested.emit(_seats[sender], recipient, amount)


func reply_gift(seat: int, status: String) -> void:
	if _is_host and _started and seat > 0:
		var recipient_id: Variant = _seats.find_key(seat)
		if recipient_id != null:
			_gift_reply.rpc_id(recipient_id, status)


@rpc("authority", "call_remote", "reliable")
func _gift_reply(status: String) -> void:
	if _peer != null and not _is_host and _started and _gift_pending:
		_gift_pending = false
		gift_result.emit(status)


func publish(frame: Dictionary) -> void:
	if _peer != null and _is_host and _started:
		# The host saves frozen maps locally. Peers only render the active map.
		var visible := frame.duplicate()
		visible.erase("map_cache")
		var raw := var_to_bytes(visible)
		if raw.size() <= MAX_FRAME_BYTES:
			var payload := raw.compress(FileAccess.COMPRESSION_ZSTD)
			_snapshot.rpc(raw.size(), payload)


@rpc("authority", "call_remote", "unreliable_ordered")
func _snapshot(raw_size: int, payload: PackedByteArray) -> void:
	if _peer == null or _is_host or not _started:
		return
	if raw_size <= 0 or raw_size > MAX_FRAME_BYTES or payload.is_empty() or payload.size() > MAX_FRAME_BYTES * 2:
		return
	var raw := payload.decompress(raw_size, FileAccess.COMPRESSION_ZSTD)
	if raw.size() == raw_size:
		var frame: Variant = bytes_to_var(raw)
		if frame is Dictionary:
			frame_received.emit(frame)
