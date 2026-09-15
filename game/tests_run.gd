extends SceneTree

const EngineRules = preload("res://core/engine.gd")
var checks = 0

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		push_error("FAIL: " + message)
		quit(1)
		assert(value, message)

func scenario(width: int = 9, height: int = 5) -> Dictionary:
	var tiles = []
	for r in range(height):
		for q in range(width):
			tiles.append({"q": q, "r": r, "terrain": "plains", "road": false, "rail": false, "river": false, "bridge": false, "elevation": 0})
	return {"id": "synthetic", "title": "Synthetic regression", "era": "ww2", "width": width, "height": height, "hex_km": 5, "turn_hours": 6, "max_turns": 8, "sides": [{"name": "Blue"}, {"name": "Red"}], "tiles": tiles, "units": [u("a", 0, 0, 2), u("b", 1, width - 1, 2)], "depots": [{"q": 0, "r": 2, "side": 0, "capacity": 100}, {"q": width - 1, "r": 2, "side": 1, "capacity": 100}], "objectives": [{"q": width / 2, "r": 2, "value": 5, "name": "Center", "owner": -1}], "reinforcements": []}

func u(id: String, side: int, q: int, r: int, type: String = "infantry") -> Dictionary:
	return {"id": id, "name": id, "side": side, "q": q, "r": r, "type": type, "strength": 100.0, "organization": 90.0, "quality": 1.0, "fuel": 70.0, "ammo": 70.0, "fatigue": 0.0}

func order(id: String, kind: String, target: Array = [], stance: String = "balanced") -> Dictionary:
	return {"unit_id": id, "kind": kind, "target": target, "stance": stance}

func run() -> void:
	var s = EngineRules.new_game(scenario(), 713)
	check(s.turn == 1 and s.phase == "planning", "initial state")
	check(not EngineRules.submit_order(s, 0, order("b", "move", [2, 2])).ok, "foreign unit rejection")
	check(not EngineRules.submit_order(s, 0, order("a", "move", [-1, 0])).ok, "out of bounds")
	check(not EngineRules.submit_order(s, 0, order("a", "move", [1.5, 0])).ok, "fractional coordinate rejection")
	check(not EngineRules.submit_order(s, 0, order("a", "engineer", [1, 0])).ok, "engineering capability")
	check(EngineRules.submit_order(s, 0, order("a", "move", [4, 2])).ok, "legal order")
	check(EngineRules.submit_order(s, 1, order("b", "attack", [4, 2])).ok, "enemy legal order")
	var view = EngineRules.observe(s, 0)
	check(view.units.size() == 1 and not view.orders.has("b"), "fog excludes enemy and orders")
	check(not view.has("seed") and not view.has("scenario"), "no hidden authority state")
	view.units[0].strength = 0
	check(s.units[0].strength == 100, "observation does not mutate authority")
	var before = JSON.stringify(s)
	var next = EngineRules.resolve(s)
	check(before == JSON.stringify(s), "resolve immutable")
	check(JSON.stringify(next) == JSON.stringify(EngineRules.resolve(s)), "seeded deterministic adjudication")
	check(next.units[0].q > 0 and next.orders.has("a"), "movement and persistent orders")
	check(next.units[0].fuel < 100, "finite movement fuel")
	s.ready[0] = true
	check(not EngineRules.submit_order(s, 0, order("a", "rest")).ok, "locked turn")
	check(not EngineRules.submit_support(s, 0, "recon", [2, 2]).ok, "locked support")

	var meet = scenario(5, 3)
	meet.units = [u("a", 0, 1, 1, "armor"), u("b", 1, 3, 1, "armor")]
	meet.era = "modern"
	meet.era_rules = {"command_delay": 0}
	meet.units.append(u("ha", 0, 0, 0, "hq"))
	meet.units.append(u("hb", 1, 4, 0, "hq"))
	s = EngineRules.new_game(meet, 123)
	EngineRules.submit_order(s, 0, order("a", "move", [2, 1]))
	EngineRules.submit_order(s, 1, order("b", "move", [2, 1]))
	next = EngineRules.resolve(s)
	check(next.units[0].strength < 100 and next.units[1].strength < 100, "simultaneous meeting creates two-sided casualties")
	check([next.units[0].q, next.units[0].r] != [next.units[1].q, next.units[1].r], "no hostile coexistence")
	view = EngineRules.observe(s, 0)
	var seen = view.units.filter(func(unit): return unit.side == 1)
	check(not seen.is_empty() and not seen[0].has("strength") and not seen[0].has("ammo"), "visible enemies masked")
	var swapped = s.duplicate(true)
	swapped.units.reverse()
	var a = EngineRules.resolve(s)
	var b = EngineRules.resolve(swapped)
	# Unit ordering must not grant a movement initiative. Compare survivors' locations.
	check(EngineRules._find_unit(a, "a").q == EngineRules._find_unit(b, "a").q, "same contested movement regardless array order")

	var cut = scenario(7, 1)
	cut.units = [u("a", 0, 4, 0), u("b", 1, 2, 0)]
	cut.depots = [{"q": 0, "r": 0, "side": 0, "capacity": 100}, {"q": 6, "r": 0, "side": 1, "capacity": 100}]
	s = EngineRules.new_game(cut)
	check(s.units[0].supply == 0, "enemy cuts supply corridor")
	next = EngineRules.resolve(s)
	check(next.units[0].organization < s.units[0].organization and next.units[0].strength < s.units[0].strength, "isolation attrition")
	s.units[1].strength = 0
	EngineRules._supply(s, true)
	check(s.units[0].supply > 0.5 and s.units[0].ammo > 70, "supply restoration replenishes stores")
	var limited = scenario()
	limited.units = [u("a", 0, 0, 2), u("a2", 0, 0, 2), u("b", 1, 8, 2)]
	limited.depots[0].capacity = 10
	s = EngineRules.new_game(limited)
	check(s.units[0].supply + s.units[1].supply <= 0.86, "shared depot throughput enforced")

	var road = scenario(5, 1)
	road.units = [u("a", 0, 0, 0, "armor"), u("b", 1, 4, 0)]
	road.tiles[2].terrain = "water"
	s = EngineRules.new_game(road)
	check(EngineRules._path(s, s.units[0], [3, 0]).is_empty(), "water blocks path")
	s.scenario.tiles[2].bridge = true
	check(not EngineRules._path(s, s.units[0], [3, 0]).is_empty(), "bridge restores path")
	var cost = EngineRules._move_cost(s, s.units[0], [0, 0], [1, 0])
	s.scenario.tiles[0].road = true
	s.scenario.tiles[1].road = true
	check(EngineRules._move_cost(s, s.units[0], [0, 0], [1, 0]) < cost, "road movement benefit")

	var retreat_case = scenario(5, 3)
	retreat_case.units = [u("a", 0, 1, 1), u("b", 1, 2, 1, "armor")]
	retreat_case.units[0].organization = 15
	s = EngineRules.new_game(retreat_case)
	EngineRules.submit_order(s, 1, order("b", "attack", [1, 1], "aggressive"))
	next = EngineRules.resolve(s)
	check(next.units[0].q != 1 or next.units[0].r != 1, "broken unit retreats")
	check(next.units[0].q != next.units[1].q or next.units[0].r != next.units[1].r, "retreat collision protection")

	var reinforcement = scenario()
	reinforcement.reinforcements = [{"turn": 2, "unit": u("reinforcement", 0, 0, 0)}]
	s = EngineRules.new_game(reinforcement)
	s = EngineRules.resolve(s)
	check(s.units.size() == 2, "reinforcement not early")
	s = EngineRules.resolve(s)
	check(s.units.size() == 3, "reinforcement arrives on turn")
	s = EngineRules.resolve(s)
	check(s.units.size() == 3, "reinforcement once only")

	var old = EngineRules.new_game(scenario())
	var modern_scenario = scenario()
	modern_scenario.era = "modern"
	var modern = EngineRules.new_game(modern_scenario)
	check(EngineRules._command_delay(old, old.units[0]) > EngineRules._command_delay(modern, modern.units[0]), "era command difference")
	check(EngineRules._rules(modern).antitank > EngineRules._rules(old).antitank, "era anti-armor difference")
	check(EngineRules.submit_support(modern, 0, "recon", [7, 2]).ok, "recon allocation")
	check(EngineRules.observe(modern, 0).units.size() == 2, "recon reveals target area")
	check(EngineRules.observe(modern, 1).support.is_empty(), "support hidden from enemy")
	check(not EngineRules.submit_support(modern, 0, "artillery", [7, 2]).ok, "no artillery without battery")

	s = EngineRules.new_game(scenario())
	var hidden_change = s.duplicate(true)
	hidden_change.units[1].strength = 1
	hidden_change.units[1].q = 7
	hidden_change.orders.b = order("b", "rest")
	check(JSON.stringify(EngineRules.ai_orders(s, 0)) == JSON.stringify(EngineRules.ai_orders(hidden_change, 0)), "AI independent of hidden enemy data")
	for turn in range(12):
		if s.phase == "finished":
			break
		for side in [0, 1]:
			for request in EngineRules.ai_orders(s, side):
				check(EngineRules.submit_order(s, side, request).ok, "AI legal orders")
		s = EngineRules.resolve(s)
	check(s.phase == "finished" and s.result.has("winner"), "full match ends with result")
	print("CORE PASS: %d assertions" % checks)
	quit(0)
