extends SceneTree
## Headless AI-vs-AI acceptance: load each scenario, resolve until finished.

const EngineRules = preload("res://core/engine.gd")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var dir = DirAccess.open("res://data/scenarios")
	if dir == null:
		push_error("FAIL: cannot open scenarios")
		quit(1)
		return
	var names: Array = dir.get_files()
	names.sort()
	var failed = 0
	var passed = 0
	for name in names:
		if not str(name).ends_with(".json"):
			continue
		var text = FileAccess.get_file_as_string("res://data/scenarios/" + name)
		var scenario = JSON.parse_string(text)
		if not scenario is Dictionary or not scenario.has("id"):
			push_error("FAIL: invalid scenario " + name)
			failed += 1
			continue
		var result = _simulate(scenario)
		if result.ok:
			print("AI_OK %s turns=%s winner=%s scores=%s" % [scenario.id, result.turn, result.winner, result.scores])
			passed += 1
		else:
			push_error("FAIL: %s — %s" % [scenario.id, result.error])
			print("AI_FAIL %s error=%s" % [scenario.id, result.error])
			failed += 1
	print("AI_SUMMARY pass=%d fail=%d" % [passed, failed])
	quit(1 if failed > 0 else 0)

func _simulate(scenario: Dictionary) -> Dictionary:
	var seed = int(scenario.get("seed", 42))
	var state = EngineRules.new_game(scenario, seed)
	var max_turns = int(scenario.get("max_turns", 20)) + 2
	var guard = 0
	while state.get("phase") == "planning" and guard < max_turns:
		guard += 1
		for side in [0, 1]:
			var orders = EngineRules.ai_orders(state, side)
			for order in orders:
				var r = EngineRules.submit_order(state, side, order)
				if not r.get("ok", false):
					return {"ok": false, "error": "illegal AI order turn=%s side=%s unit=%s: %s" % [state.turn, side, order.get("unit_id"), r.get("error")]}
			state.ready[side] = true
		if state.ready[0] and state.ready[1]:
			state = EngineRules.resolve(state)
		else:
			return {"ok": false, "error": "sides did not lock"}
		if guard > int(scenario.get("max_turns", 20)) + 1 and state.get("phase") == "planning":
			return {"ok": false, "error": "exceeded max turns without finish"}
	if state.get("phase") != "finished":
		return {"ok": false, "error": "phase=%s after %s resolves" % [state.get("phase"), guard]}
	var units_alive = 0
	for unit in state.units:
		if float(unit.strength) > 0:
			units_alive += 1
	if units_alive < 1:
		return {"ok": false, "error": "no surviving units"}
	var obs0 = EngineRules.observe(state, 0)
	if obs0.has("seed") or obs0.has("scenario"):
		return {"ok": false, "error": "observation leaked authority"}
	return {
		"ok": true,
		"turn": state.turn,
		"winner": state.result.get("winner"),
		"scores": state.scores,
		"alive": units_alive,
	}
