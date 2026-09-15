extends SceneTree
## Session-level integration smoke: orders, resolve, save/load, observer pause, support.

const SessionScript = preload("res://session.gd")

var checks = 0

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		push_error("FAIL: " + message)
		print("FAIL: " + message)
		quit(1)
		assert(value, message)

func run() -> void:
	var session = SessionScript.new()
	get_root().add_child(session)
	# Wait one frame so _ready loads scenarios.
	await process_frame
	await process_frame
	check(session.scenarios.size() >= 7, "scenarios loaded")
	session.start_game("tutorial", "ai", 0)
	check(session.mode == "ai" and session.view.get("turn") == 1, "game started")
	var units: Array = session.view.get("units", [])
	check(units.size() > 0, "own units visible")
	var unit_id = ""
	for unit in units:
		if int(unit.get("side", -1)) == 0:
			unit_id = str(unit.id)
			break
	check(not unit_id.is_empty(), "found own unit")
	var order = session.place_order(unit_id, "defend")
	check(order.get("ok", false), "defend order accepted")
	session.commit_turn()
	check(int(session.view.get("turn", 0)) == 2, "turn advanced after lock")

	session.start_game("tutorial", "observer", 0)
	check(session.mode == "observer", "observer mode")
	session.commit_turn()
	check(session.observer_paused(), "observer paused")
	session.commit_turn()
	check(not session.observer_paused(), "observer resumed")

	session.start_game("tutorial", "ai", 0)
	check(session.save_game("slot1"), "save slot1")
	session.close_game()
	check(session.load_game("slot1"), "load slot1")
	check(session.view.get("turn") == 1 and session.mode == "ai", "restored turn and mode")

	# LAN mode flag accepted by start_game even before host/join.
	session.start_game("tutorial", "lan", 0)
	check(session.mode == "lan", "lan play_mode accepted")
	session.close_game()

	print("SESSION PASS: %d assertions" % checks)
	quit(0)
