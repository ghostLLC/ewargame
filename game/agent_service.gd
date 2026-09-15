extends Node
## Bounded newline-JSON command bridge; MCP adapter is an independent stdio process.
## Only loopback binds; tokens scoped to a single side and replaced for each match.

var server = TCPServer.new()
var clients: Array = []
var tokens: Dictionary = {}
var bound_port = 0
var session: Node
const MAX_FRAME = 262144
const MAX_CLIENTS = 8

func start(owner_session: Node, port: int = 24681) -> Error:
	stop()
	session = owner_session
	var error = server.listen(port, "127.0.0.1")
	if error != OK:
		return error
	bound_port = port
	var crypto = Crypto.new()
	tokens = {"0": crypto.generate_random_bytes(24).hex_encode(), "1": crypto.generate_random_bytes(24).hex_encode()}
	set_process(true)
	return OK

func stop() -> void:
	for client in clients:
		client.peer.disconnect_from_host()
	clients.clear()
	server.stop()
	tokens.clear()
	bound_port = 0
	set_process(false)

func config_for(side: int) -> Dictionary:
	return {"host": "127.0.0.1", "port": bound_port, "token": tokens.get(str(side), ""), "side": side, "protocol": 1}

func _process(_delta: float) -> void:
	while server.is_connection_available():
		var peer = server.take_connection()
		if clients.size() >= MAX_CLIENTS:
			peer.disconnect_from_host()
		else:
			clients.append({"peer": peer, "buffer": PackedByteArray(), "since": Time.get_ticks_msec()})
	for i in range(clients.size() - 1, -1, -1):
		var c = clients[i]
		var peer: StreamPeerTCP = c.peer
		peer.poll()
		if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED or Time.get_ticks_msec() - int(c.since) > 30000:
			peer.disconnect_from_host()
			clients.remove_at(i)
			continue
		var size = peer.get_available_bytes()
		if size > 0:
			if c.buffer.size() + size > MAX_FRAME:
				peer.disconnect_from_host()
				clients.remove_at(i)
				continue
			var packet = peer.get_data(size)
			if packet[0] == OK:
				c.buffer.append_array(packet[1])
		var newline = c.buffer.find(10)
		if newline >= 0:
			var request = JSON.parse_string(c.buffer.slice(0, newline).get_string_from_utf8())
			var reply: Dictionary = {"ok": false, "error": "invalid_request"}
			if request is Dictionary:
				var side = -1
				for key in tokens:
					if request.get("token", "") == tokens[key]:
						side = int(key)
				if side >= 0:
					reply = session.agent_command(side, str(request.get("method", "")), request.get("params", {}))
				else:
					reply = {"ok": false, "error": "unauthorized"}
			peer.put_data((JSON.stringify(reply) + "\n").to_utf8_buffer())
			c.buffer = c.buffer.slice(newline + 1)
			c.since = Time.get_ticks_msec()
