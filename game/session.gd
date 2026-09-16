extends Node
## One authority; every front end sees an observation, never the full state.

signal view_changed
signal notice(message: String)
signal lobby_changed

const Storage = preload("res://storage.gd")
const AgentService = preload("res://agent_service.gd")
const PROTOCOL = 1
var view: Dictionary = {}
var scenarios: Array = []
var mode = "ai"
var player_side = 0
var pending_handoff = false
var connected = false
var rooms: Array = []
var replay_active = false
var _engine: Script
var _state: Dictionary = {}
var _history: Array = []
var _replay_index = -1
var _busy = false
var _roles: Dictionary = {}
var _guest_token = ""
var _resume_token = ""
var _host_address = ""
var _host_port = 24680
var _is_host = false
var _discovery: PacketPeerUDP
var _agent: Node
var _observer_timer = 0.0
var _observer_paused = false
var ai_difficulty: String = "normal"

func _ready() -> void:
	_engine = load("res://core/engine.gd")
	var folder = DirAccess.open("res://data/scenarios")
	if folder:
		var names = folder.get_files()
		names.sort()
		for name in names:
			if name.ends_with(".json"):
				var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://data/scenarios/" + name))
				if parsed is Dictionary and parsed.has("id"):
					scenarios.append(parsed)
	scenarios.sort_custom(func(a, b): return str(a.id) == "tutorial" or (str(b.id) != "tutorial" and str(a.id) < str(b.id)))
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	_agent = AgentService.new()
	add_child(_agent)
	_agent.set_process(false)
	lobby_changed.emit()

func _process(delta: float) -> void:
	if _discovery:
		while _discovery.get_available_packet_count() > 0:
			var raw = _discovery.get_packet()
			var ip = _discovery.get_packet_ip()
			var port = _discovery.get_packet_port()
			if raw.size() > 2048:
				continue
			var data = JSON.parse_string(raw.get_string_from_utf8())
			if not data is Dictionary or int(data.get("version", 0)) != PROTOCOL:
				continue
			if _is_host and data.get("ewargame") == "discover":
				_discovery.set_dest_address(ip, port)
				_discovery.put_packet(JSON.stringify({"ewargame": "room", "version": PROTOCOL, "title": _state.get("scenario", {}).get("title", "战役房间"), "port": _host_port}).to_utf8_buffer())
			elif not _is_host and data.get("ewargame") == "room":
				data["address"] = ip
				var found = false
				for room in rooms:
					if room.address == ip and room.port == data.get("port"):
						found = true
				if not found:
					rooms.append(data)
					lobby_changed.emit()
	if mode == "observer" and not _state.is_empty() and not _busy and not _observer_paused and not replay_active and _state.get("phase") != "finished":
		_observer_timer += delta
		if _observer_timer >= 2.5:
			_observer_timer = 0.0
			for side in [0, 1]:
				_apply_ai(side)
			_state.ready = [true, true]
			_resolve_turn()

func start_game(id: String, play_mode: String = "ai", side: int = 0) -> void:
	var scenario = _find_scenario(id)
	if scenario.is_empty() or not side in [0, 1] or not play_mode in ["ai", "hotseat", "observer", "agent", "lan"]:
		notice.emit("无法开始：剧本或对局模式无效")
		return
	close_game()
	mode = play_mode
	player_side = side
	_state = _engine.new_game(scenario, int(scenario.get("seed", 42)))
	_state["ready"] = [false, false]
	_history = [_state.duplicate(true)]
	if mode == "agent":
		_start_agent_service()
	_publish()

func _find_scenario(id: String) -> Dictionary:
	for scenario in scenarios:
		if str(scenario.id) == id:
			return scenario
	return {}

func preview_move(unit_id: String, target: Array) -> Dictionary:
	if _state.is_empty():
		return {"ok": false}
	return _engine.preview_move(_state, unit_id, target)

func estimate_combat(attacker_id: String, defender_id: String) -> Dictionary:
	if _state.is_empty():
		return {"ok": false}
	return _engine.estimate_combat(_state, attacker_id, defender_id)

func place_order(unit_id: String, kind: String, target: Array = [], stance: String = "balanced") -> Dictionary:
	if pending_handoff or replay_active or _busy:
		return _fail("当前不能下令")
	var order = {"unit_id": unit_id, "kind": kind, "target": target, "stance": stance}
	if mode == "lan" and not _is_host:
		if not connected:
			return _fail("连接已中断，请重新加入房间")
		_request_order.rpc_id(1, order, int(view.get("turn", -1)))
		return {"ok": true, "pending": true}
	return _apply_order(player_side, order)

func _apply_order(side: int, order: Dictionary) -> Dictionary:
	if _state.is_empty() or _state.get("phase") == "finished" or _state.ready[side] or JSON.stringify(order).length() > 4096:
		return _fail("回合已经锁定或战役已经结束")
	var result: Dictionary = _engine.submit_order(_state, side, order)
	if result.get("ok", false):
		_publish()
	else:
		notice.emit(str(result.get("error", "命令无效")))
	return result

func set_support(kind: String, target: Array = []) -> Dictionary:
	if pending_handoff or replay_active or _busy:
		return _fail("当前不能分配支援")
	if mode == "lan" and not _is_host:
		if not connected:
			return _fail("尚未连接")
		_request_support.rpc_id(1, kind, target, int(view.get("turn", -1)))
		return {"ok": true, "pending": true}
	return _apply_support(player_side, kind, target)

func _apply_support(side: int, kind: String, target: Array) -> Dictionary:
	if _state.is_empty() or _state.get("phase") == "finished" or _state.ready[side]:
		return _fail("当前回合已锁定")
	var result: Dictionary = _engine.submit_support(_state, side, kind, target)
	if result.get("ok", false):
		_publish()
	return result

func commit_turn() -> void:
	if pending_handoff or replay_active or _busy or view.is_empty():
		return
	if mode == "observer":
		_observer_paused = not _observer_paused
		notice.emit("观察赛已暂停" if _observer_paused else "观察赛继续")
		return
	if mode == "lan" and not _is_host:
		if connected:
			_request_commit.rpc_id(1, int(view.get("turn", -1)))
		return
	_lock_side(player_side)

func _lock_side(side: int) -> Dictionary:
	if _state.is_empty() or _state.get("phase") == "finished" or _state.ready[side]:
		return {"ok": false, "error": "回合已锁定"}
	_state.ready[side] = true
	if mode == "ai":
		_apply_ai(1 - player_side)
		_state.ready[1 - player_side] = true
	if _state.ready[0] and _state.ready[1]:
		if mode != "lan" or connected:
			_resolve_turn()
		else:
			_publish()
	elif mode == "hotseat":
		pending_handoff = true
		player_side = 1 - side
		view = {}
		view_changed.emit()
	else:
		_publish()
	return {"ok": true, "turn": _state.get("turn", 0)}

func accept_handoff() -> void:
	if mode == "hotseat" and pending_handoff:
		pending_handoff = false
		_publish()

func set_ai_difficulty(level: String) -> void:
	if level not in ["easy", "normal", "hard"]:
		notice.emit("难度应为 easy/normal/hard")
		return
	ai_difficulty = level
	notice.emit("AI 难度：" + level)

func _apply_ai(side: int) -> void:
	if not _state.is_empty():
		_state["ai_difficulty"] = ai_difficulty
	for order in _engine.ai_orders(_state, side):
		_engine.submit_order(_state, side, order)

func _resolve_turn() -> void:
	if _busy:
		return
	_busy = true
	_state = _engine.resolve(_state)
	_state["ready"] = [false, false]
	_history.append(_state.duplicate(true))
	_busy = false
	_replay_index = -1
	Storage.write_save("autosave", _save_payload())
	if mode == "hotseat":
		pending_handoff = true
		player_side = 1 - player_side
		view = {}
		view_changed.emit()
	else:
		_publish()

func _publish() -> void:
	if _state.is_empty():
		return
	if not pending_handoff:
		var source = _history[_replay_index] if replay_active and _replay_index >= 0 else _state
		view = _engine.observe(source, player_side)
		view["replay_active"] = replay_active
		view["replay_index"] = _replay_index if replay_active else _history.size() - 1
		view["replay_count"] = _history.size()
		view["connection_status"] = "已连接" if connected else "等待对方" if mode == "lan" else "本地对局"
		view_changed.emit()
	if mode == "lan" and _is_host:
		for peer in _roles:
			if multiplayer.get_peers().has(int(peer)):
				_receive_view.rpc_id(int(peer), _engine.observe(_state, int(_roles[peer])))

func replay_goto(index: int) -> void:
	if mode == "lan" and not _is_host:
		notice.emit("联网客户端使用战报查看历史；完整回放保存在房主端")
		return
	if _history.is_empty() or pending_handoff:
		return
	_replay_index = clampi(index, 0, _history.size() - 1)
	replay_active = _replay_index < _history.size() - 1
	_publish()

func export_after_action() -> String:
	var scenario_title = str(_state.get("scenario", {}).get("title", "战役")) if not _state.is_empty() else "战役"
	var lines = ["战线 · 战役指挥 — 战后报告", "剧本：" + scenario_title, ""]
	if not _state.is_empty():
		lines.append("最终回合：%s / %s" % [_state.get("turn"), _state.get("scenario", {}).get("max_turns", "?")])
		lines.append("积分：%s : %s" % [_state.get("scores", [0, 0])[0], _state.get("scores", [0, 0])[1]])
		var result = _state.get("result", {})
		if result is Dictionary and not result.is_empty():
			lines.append("结果：winner=%s  %s" % [result.get("winner", "-"), result.get("reason", "")])
		lines.append("天气：%s" % _state.get("weather", "clear"))
		lines.append("")
		lines.append("单位存续：")
		for unit in _state.get("units", []):
			if float(unit.get("strength", 0)) > 0:
				lines.append("- [%s] %s 兵力%s 组织%s @(%s,%s)" % [unit.get("side"), unit.get("name"), int(unit.get("strength", 0)), int(unit.get("organization", 0)), unit.get("q"), unit.get("r")])
		lines.append("")
	lines.append("逐回合战报：")
	var index = 0
	for snapshot in _history:
		index += 1
		lines.append("-- 回合 %s | 分 %s:%s | 天气 %s --" % [snapshot.get("turn", index), snapshot.get("scores", [0, 0])[0], snapshot.get("scores", [0, 0])[1], snapshot.get("weather", "?")])
		for event in snapshot.get("events", snapshot.get("logs", [])):
			var message = event
			if event is Dictionary:
				message = event.get("text", str(event))
			lines.append("  " + str(message))
	var path = "user://after_action_report.txt"
	var file = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		notice.emit("无法写入战后报告")
		return ""
	file.store_string("\n".join(lines) + "\n")
	file.close()
	var absolute = ProjectSettings.globalize_path(path)
	notice.emit("战后报告已导出：" + absolute)
	return absolute

func replay_step(offset: int) -> void:
	if mode == "lan" and not _is_host:
		notice.emit("联网客户端使用战报查看历史；完整回放保存在房主端")
		return
	if _history.is_empty() or pending_handoff:
		return
	if not replay_active:
		_replay_index = _history.size() - 1
	_replay_index = clampi(_replay_index + offset, 0, _history.size() - 1)
	replay_active = _replay_index < _history.size() - 1
	_publish()

func _save_payload() -> Dictionary:
	return {"state": _state, "history": _history, "mode": mode, "player_side": player_side, "guest_token": _guest_token, "port": _host_port, "handoff": pending_handoff, "ai_difficulty": ai_difficulty}

func list_save_slots() -> Array:
	return Storage.list_saves()

func clear_orders() -> Dictionary:
	if pending_handoff or replay_active or _busy or _state.is_empty():
		return _fail("当前不能清空命令")
	if _state.ready[player_side]:
		return _fail("回合已锁定")
	if mode == "lan" and not _is_host:
		# Client-side clear is local-only until host ack; use agent path via RPC if needed.
		if connected:
			# reuse commit-style RPC: send empty batch by clearing on host through orders erase is not exposed; clear locally after refresh is wrong.
			# Fall through: host-only clear via apply.
			pass
	var cleared = 0
	for unit in _state.units:
		if int(unit.side) == player_side and _state.orders.has(str(unit.id)):
			_state.orders.erase(str(unit.id))
			cleared += 1
	_publish()
	notice.emit("已清空本回合 %d 条命令" % cleared)
	return {"ok": true, "cleared": cleared}

func delete_save(slot: String) -> bool:
	var result = Storage.delete_save(slot)
	notice.emit("存档已删除" if result.ok else str(result.error))
	return result.ok

func save_game(slot: String = "quicksave") -> bool:
	if _state.is_empty() or (mode == "lan" and not _is_host):
		notice.emit("此对局由房主保存")
		return false
	var result = Storage.write_save(slot, _save_payload())
	notice.emit("战役已保存" if result.ok else str(result.error))
	return result.ok

func load_game(slot: String = "quicksave") -> bool:
	var result = Storage.read_save(slot)
	if not result.ok:
		notice.emit(str(result.error))
		return false
	var data: Dictionary = result.data
	var saved: Dictionary = data.state
	if not saved.get("units") is Array or not saved.get("scenario") is Dictionary or not saved.get("orders") is Dictionary:
		notice.emit("存档缺少必要战役数据")
		return false
	close_game()
	_state = saved
	_history = data.get("history", [_state.duplicate(true)])
	if _history.is_empty():
		_history = [_state.duplicate(true)]
	mode = str(data.get("mode", "ai"))
	player_side = clampi(int(data.get("player_side", 0)), 0, 1)
	pending_handoff = bool(data.get("handoff", false))
	ai_difficulty = str(data.get("ai_difficulty", "normal"))
	_guest_token = str(data.get("guest_token", ""))
	if mode == "lan":
		_open_host(int(data.get("port", 24680)))
	elif mode == "agent":
		_start_agent_service()
	_publish()
	if pending_handoff:
		view_changed.emit()
	notice.emit("战役已恢复")
	return true

func observer_paused() -> bool:
	return _observer_paused

func close_game() -> void:
	if is_instance_valid(_agent):
		_agent.stop()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	_roles.clear()
	_guest_token = ""
	_is_host = false
	connected = false
	if _discovery:
		_discovery.close()
		_discovery = null
	_state = {}
	_history = []
	view = {}
	pending_handoff = false
	replay_active = false
	_replay_index = -1
	_busy = false
	_observer_paused = false
	view_changed.emit()

func _fail(message: String) -> Dictionary:
	notice.emit(message)
	return {"ok": false, "error": message}

func start_host(id: String, port: int = 24680, side: int = 0) -> void:
	start_game(id, "hotseat", side)
	if not _state.is_empty():
		_open_host(port)
		_publish()

func _open_host(port: int) -> void:
	if port < 1024 or port > 65535:
		notice.emit("端口应介于 1024–65535")
		return
	var peer = ENetMultiplayerPeer.new()
	var error = peer.create_server(port, 4)
	if error != OK:
		notice.emit("无法创建房间，端口可能已占用")
		return
	multiplayer.multiplayer_peer = peer
	mode = "lan"
	_is_host = true
	_host_port = port
	connected = false
	_discovery = PacketPeerUDP.new()
	if _discovery.bind(24679) != OK:
		_discovery = null
	lobby_changed.emit()
	notice.emit("房间已创建，等待对方加入 · 端口 " + str(port))

func join_host(address: String, port: int = 24680) -> void:
	if address.strip_edges().is_empty() or port < 1024 or port > 65535:
		notice.emit("请输入有效 IP 与端口")
		return
	close_game()
	mode = "lan"
	_host_address = address.strip_edges()
	_host_port = port
	_resume_token = ""
	if FileAccess.file_exists("user://room-ticket.json"):
		var ticket = JSON.parse_string(FileAccess.get_file_as_string("user://room-ticket.json"))
		if ticket is Dictionary and ticket.get("address") == _host_address and int(ticket.get("port", 0)) == port:
			_resume_token = str(ticket.get("token", ""))
	var peer = ENetMultiplayerPeer.new()
	var error = peer.create_client(_host_address, port)
	if error != OK:
		notice.emit("无法发起连接")
		return
	multiplayer.multiplayer_peer = peer
	notice.emit("正在连接 " + address)

func _on_connected() -> void:
	_hello.rpc_id(1, PROTOCOL, _resume_token)

func _on_peer_connected(_peer: int) -> void:
	pass

func _on_connection_failed() -> void:
	connected = false
	notice.emit("连接失败，请检查 IP、端口及局域网防火墙设置")
	lobby_changed.emit()

func _on_server_disconnected() -> void:
	connected = false
	notice.emit("与房主断开连接，重新加入可恢复对局")
	lobby_changed.emit()

func _on_peer_disconnected(peer: int) -> void:
	if _roles.has(peer):
		_roles.erase(peer)
		connected = false
		notice.emit("对方离线，房间和命令已保留")
		_publish()
		lobby_changed.emit()

@rpc("any_peer", "call_remote", "reliable")
func _hello(version: int, resume: String) -> void:
	if not _is_host:
		return
	var peer = multiplayer.get_remote_sender_id()
	if version != PROTOCOL or not _roles.is_empty() or (not _guest_token.is_empty() and resume != _guest_token):
		_network_notice.rpc_id(peer, "房间已占用、恢复凭证无效或协议不兼容")
		return
	if _guest_token.is_empty():
		_guest_token = Crypto.new().generate_random_bytes(24).hex_encode()
	_roles[peer] = 1 - player_side
	connected = true
	_welcome.rpc_id(peer, 1 - player_side, _guest_token)
	_publish()
	lobby_changed.emit()
	if _state.ready[0] and _state.ready[1]:
		_resolve_turn()

@rpc("authority", "call_remote", "reliable")
func _welcome(side: int, token: String) -> void:
	player_side = side
	_resume_token = token
	connected = true
	var file = FileAccess.open("user://room-ticket.json", FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify({"address": _host_address, "port": _host_port, "token": token}))
	lobby_changed.emit()

@rpc("authority", "call_remote", "reliable")
func _receive_view(observation: Dictionary) -> void:
	if _is_host:
		return
	view = observation
	view["connection_status"] = "已连接"
	view["replay_active"] = false
	view_changed.emit()

@rpc("authority", "call_remote", "reliable")
func _network_notice(message: String) -> void:
	notice.emit(message)

func _authorized_peer(turn: int) -> int:
	if not _is_host or _state.is_empty() or turn != int(_state.turn):
		return -1
	return int(_roles.get(multiplayer.get_remote_sender_id(), -1))

@rpc("any_peer", "call_remote", "reliable")
func _request_order(order: Dictionary, turn: int) -> void:
	var side = _authorized_peer(turn)
	if side < 0:
		return
	var result = _apply_order(side, order)
	if not result.ok:
		_network_notice.rpc_id(multiplayer.get_remote_sender_id(), str(result.error))

@rpc("any_peer", "call_remote", "reliable")
func _request_support(kind: String, target: Array, turn: int) -> void:
	var side = _authorized_peer(turn)
	if side >= 0:
		var result = _apply_support(side, kind, target)
		if not result.ok:
			_network_notice.rpc_id(multiplayer.get_remote_sender_id(), str(result.error))

@rpc("any_peer", "call_remote", "reliable")
func _request_commit(turn: int) -> void:
	var side = _authorized_peer(turn)
	if side >= 0:
		_lock_side(side)

func discover_rooms() -> void:
	if _is_host:
		return
	if _discovery:
		_discovery.close()
	_discovery = PacketPeerUDP.new()
	if _discovery.bind(0) != OK:
		_discovery = null
		return
	rooms.clear()
	_discovery.set_broadcast_enabled(true)
	for address in ["255.255.255.255", "127.0.0.1"]:
		_discovery.set_dest_address(address, 24679)
		_discovery.put_packet(JSON.stringify({"ewargame": "discover", "version": PROTOCOL}).to_utf8_buffer())
	lobby_changed.emit()

func get_local_addresses() -> Array:
	var result: Array = []
	for address in IP.get_local_addresses():
		if address.contains(".") and address != "127.0.0.1" and not address.begins_with("169.254"):
			result.append(address)
	return result

func _start_agent_service() -> void:
	var port = 24681
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--bridge-port="):
			port = int(argument.get_slice("=", 1))
	if _agent.start(self, port) != OK:
		notice.emit("Agent 接口端口已占用，可暂停后改用 --bridge-port")
		return
	var file = FileAccess.open(agent_config_path(), FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(_agent.config_for(1 - player_side), "\t"))

func agent_config_path() -> String:
	return ProjectSettings.globalize_path("user://agent-connection.json")

func agent_command(side: int, method: String, params: Dictionary) -> Dictionary:
	if mode != "agent" or _state.is_empty() or side == player_side:
		return {"ok": false, "error": "This seat is not assigned to an external agent"}
	match method:
		"observe":
			return {"ok": true, "data": _engine.observe(_state, side)}
		"rules":
			return {"ok": true, "data": {
				"orders": ["move", "attack", "defend", "rest", "recon", "reserve", "retreat", "engineer"],
				"stances": ["cautious", "balanced", "aggressive"],
				"supports": ["artillery", "air", "recon"],
				"turn_hours": _state.scenario.get("turn_hours", 6),
				"hex_km": _state.scenario.get("hex_km", 5),
				"terrain_cost_note": "plains 1, desert 1.5, town 1.5, forest/hills 2, city 2, bocage 2.5, marsh 3.5, mountain 4; water impassable unless bridge",
				"fog": "You only receive your own full units, visible/masked enemies (no exact strength), own depots, dated contacts, and your orders. Never query seed, enemy orders, or hidden strength.",
				"wego": "Both sides lock orders, then six simultaneous substeps resolve. Orders persist until changed.",
				"support": "One operational support per side per turn (artillery needs in-range battery; recon reveals a radius; air depends on era/weather).",
				"zoc": "Combat formations entering an enemy zone of control stop movement for the turn.",
				"clear_orders": "game_clear_orders removes your unlocked orders for the current turn.",
				"instruction": "Use only your observation. Submit unit_id, kind, target [q,r], stance. Orders persist. Submit once per turn. Await a higher turn number after commit."
			}}
		"clear_orders":
			if int(params.get("turn", -1)) != int(_state.turn):
				return {"ok": false, "error": "stale_turn"}
			if _state.ready[side]:
				return {"ok": false, "error": "turn_locked"}
			var cleared = 0
			for unit in _state.units:
				if int(unit.side) == side and _state.orders.has(str(unit.id)):
					_state.orders.erase(str(unit.id))
					cleared += 1
			_publish()
			return {"ok": true, "cleared": cleared}
		"orders":
			if int(params.get("turn", -1)) != int(_state.turn):
				return {"ok": false, "error": "stale_turn"}
			var orders = params.get("orders", [])
			if not orders is Array or orders.size() > 128:
				return {"ok": false, "error": "Expected at most 128 orders"}
			# Validate an entire batch on a copy; partial application is never hidden.
			var copy = _state.duplicate(true)
			if copy.ready[side]:
				return {"ok": false, "error": "turn_locked"}
			for order in orders:
				if not order is Dictionary:
					return {"ok": false, "error": "Invalid order object"}
				var result: Dictionary = _engine.submit_order(copy, side, order)
				if not result.get("ok", false):
					return result
			_state = copy
			_publish()
			return {"ok": true, "count": orders.size()}
		"support":
			if int(params.get("turn", -1)) != int(_state.turn):
				return {"ok": false, "error": "stale_turn"}
			return _apply_support(side, str(params.get("kind", "")), params.get("target", []))
		"commit":
			if int(params.get("turn", -1)) != int(_state.turn):
				return {"ok": false, "error": "stale_turn"}
			return _lock_side(side)
	return {"ok": false, "error": "unknown_method"}
