extends SceneTree
## Guest: connect, lock, disconnect, reconnect with saved ticket.

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	await process_frame
	await process_frame
	var session = get_root().get_node_or_null("GameSession")
	if session == null:
		print("LAN_REGUEST_FAIL no session")
		quit(1)
		return
	session.join_host("127.0.0.1", 24691)
	var frames = 0
	while frames < 700:
		await process_frame
		frames += 1
		if session.connected:
			break
	if not session.connected:
		print("LAN_REGUEST_FAIL first connect")
		quit(2)
		return
	print("LAN_REGUEST_CONNECTED first")
	session.commit_turn()
	session.close_game()
	print("LAN_REGUEST_DROPPED")
	# Brief pause so host observes disconnect, then rejoin with ticket.
	for i in range(60):
		await process_frame
	session.join_host("127.0.0.1", 24691)
	frames = 0
	while frames < 800:
		await process_frame
		frames += 1
		if session.connected and not session.view.is_empty():
			print("LAN_REGUEST_OK reconnect side=%s turn=%s" % [session.view.get("side"), session.view.get("turn")])
			quit(0)
			return
	print("LAN_REGUEST_TIMEOUT reconnect connected=%s" % session.connected)
	quit(3)
