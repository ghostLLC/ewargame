extends SceneTree
## Host-side LAN smoke. Waits for guest, then locks its turn.

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	await process_frame
	await process_frame
	var session = get_root().get_node_or_null("GameSession")
	if session == null:
		print("LAN_HOST_FAIL no session")
		quit(1)
		return
	session.start_host("tutorial", 24690, 0)
	print("LAN_HOST_READY port=24690 mode=%s" % session.mode)
	var frames = 0
	while frames < 600:
		await process_frame
		frames += 1
		if session.connected:
			break
	if not session.connected:
		print("LAN_HOST_FAIL no guest connected")
		quit(2)
		return
	print("LAN_HOST_GUEST_JOINED")
	session.commit_turn()
	frames = 0
	while frames < 500:
		await process_frame
		frames += 1
		if int(session.view.get("turn", 1)) >= 2:
			print("LAN_HOST_OK turn=%s" % session.view.get("turn"))
			# Give guest time to receive the post-resolve observation RPC.
			for i in range(120):
				await process_frame
			quit(0)
			return
	print("LAN_HOST_TIMEOUT turn=%s ready=%s" % [session.view.get("turn"), session.view.get("ready")])
	quit(3)
