extends SceneTree
## Host-side LAN reconnect smoke: host, guest joins, guest drops, guest rejoins with ticket.

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	await process_frame
	await process_frame
	var session = get_root().get_node_or_null("GameSession")
	if session == null:
		print("LAN_REHOST_FAIL no session")
		quit(1)
		return
	session.start_host("tutorial", 24691, 0)
	print("LAN_REHOST_READY")
	var frames = 0
	while frames < 800:
		await process_frame
		frames += 1
		if session.connected:
			break
	if not session.connected:
		print("LAN_REHOST_FAIL first guest")
		quit(2)
		return
	print("LAN_REHOST_GUEST1 connected=%s" % session.connected)
	# Guest will disconnect; keep host alive and accept reconnect.
	frames = 0
	var saw_disconnect = false
	while frames < 1200:
		await process_frame
		frames += 1
		if not session.connected:
			saw_disconnect = true
		if saw_disconnect and session.connected:
			print("LAN_REHOST_OK reconnect_connected=%s turn=%s" % [session.connected, session.view.get("turn")])
			for i in range(90):
				await process_frame
			quit(0)
			return
	print("LAN_REHOST_TIMEOUT saw_disconnect=%s connected=%s" % [saw_disconnect, session.connected])
	quit(3)
