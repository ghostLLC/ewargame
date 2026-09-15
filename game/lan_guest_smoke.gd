extends SceneTree
## Guest-side LAN smoke. Launch with -- --lan=guest --host=127.0.0.1 --port=24690

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	await process_frame
	await process_frame
	var session = get_root().get_node_or_null("GameSession")
	if session == null:
		print("LAN_GUEST_FAIL no session")
		quit(1)
		return
	session.join_host("127.0.0.1", 24690)
	print("LAN_GUEST_JOINING")
	var frames = 0
	while frames < 600:
		await process_frame
		frames += 1
		if session.connected and not session.view.is_empty():
			break
	if not session.connected:
		print("LAN_GUEST_FAIL not connected")
		quit(2)
		return
	print("LAN_GUEST_CONNECTED side=%s turn=%s" % [session.view.get("side"), session.view.get("turn")])
	# Lock an empty commit (no orders) so host can resolve once host also locks.
	# Host auto-AIs? No - host is human side 0. Host script must commit.
	session.commit_turn()
	print("LAN_GUEST_LOCKED")
	frames = 0
	while frames < 800:
		await process_frame
		frames += 1
		if int(session.view.get("turn", 0)) >= 2:
			print("LAN_GUEST_OK turn=%s" % session.view.get("turn"))
			quit(0)
			return
	print("LAN_GUEST_TIMEOUT turn=%s ready=%s" % [session.view.get("turn"), session.view.get("ready")])
	quit(3)
