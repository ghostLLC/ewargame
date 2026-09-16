class_name WarEngine
extends RefCounted
## Pure deterministic WEGO adjudication. Only submit_order mutates caller state.
## Values are designed operational abstractions, not historical loss forecasts.

const DIRECTIONS = [[1, 0], [1, -1], [0, -1], [-1, 0], [-1, 1], [0, 1]]
const KINDS = ["move", "attack", "defend", "rest", "recon", "reserve", "retreat", "engineer"]
const STANCES = ["cautious", "balanced", "aggressive"]
const MOTOR = ["armor", "mechanized", "motorized", "recon", "hq", "logistics", "air_defense"]
const TERRAIN_COST = {"plains": 1.0, "forest": 2.0, "hills": 2.0, "mountain": 4.0, "desert": 1.5, "marsh": 3.5, "town": 1.5, "city": 2.0, "bocage": 2.5, "water": 999.0}
const DEFENSE = {"plains": 1.0, "forest": 1.35, "hills": 1.3, "mountain": 1.7, "desert": 0.95, "marsh": 1.2, "town": 1.5, "city": 1.8, "bocage": 1.5, "water": 1.0}
const POWER = {"infantry": 1.0, "armor": 1.55, "mechanized": 1.3, "motorized": 1.1, "recon": 0.65, "artillery": 0.65, "engineer": 0.8, "airborne": 1.05, "hq": 0.25, "logistics": 0.15, "air_defense": 0.65}
const ERA_DEFAULTS = {
	"ww2": {"recon_range": 2, "command_range": 4, "supply_range": 12, "air_power": 0.7, "air_defense": 0.3, "antitank": 0.25, "command_delay": 1, "supply_efficiency": 0.85},
	"coldwar": {"recon_range": 3, "command_range": 6, "supply_range": 16, "air_power": 1.0, "air_defense": 0.65, "antitank": 0.55, "command_delay": 0, "supply_efficiency": 1.0},
	"modern": {"recon_range": 4, "command_range": 8, "supply_range": 20, "air_power": 1.25, "air_defense": 0.9, "antitank": 0.8, "command_delay": 0, "supply_efficiency": 1.15}
}

static func new_game(scenario: Dictionary, seed: int = 42) -> Dictionary:
	var state = {"version": 1, "scenario": scenario.duplicate(true), "units": [], "turn": 1, "orders": {}, "ready": [false, false], "scores": [0, 0], "phase": "planning", "weather": str(scenario.get("weather", "clear")), "objectives": scenario.get("objectives", []).duplicate(true), "logs": [], "contacts": {"0": {}, "1": {}}, "seed": seed, "support": {}, "result": {}, "control": {}, "reinforced": [], "events": []}
	for raw in scenario.get("units", []):
		state.units.append(_unit(raw))
	for objective in state.objectives:
		objective["owner"] = int(objective.get("owner", -1))
		if objective.owner in [0, 1]:
			state.scores[objective.owner] += int(objective.get("value", 1))
	for tile in scenario.get("tiles", []):
		state.control[_key([tile.q, tile.r])] = int(tile.get("owner", -1))
	for unit in state.units:
		state.control[_key(_pos(unit))] = unit.side
	_supply(state, false)
	_update_contacts(state)
	return state

static func _unit(raw: Dictionary) -> Dictionary:
	var unit = raw.duplicate(true)
	var defaults = {"name": str(raw.get("id", "部队")), "type": "infantry", "size": "brigade", "formation": "", "strength": 100.0, "organization": 85.0, "fatigue": 0.0, "fuel": 100.0, "ammo": 100.0, "quality": 1.0, "entrenchment": 0.0, "supply": 1.0, "command_delay": 0, "status": "ready", "supply_path": [], "movement_remaining": 0.0}
	for key in defaults:
		if not unit.has(key):
			unit[key] = defaults[key]
	unit["side"] = int(unit.get("side", 0))
	unit["q"] = int(unit.get("q", 0))
	unit["r"] = int(unit.get("r", 0))
	unit["id"] = str(unit.id)
	unit["initial_strength"] = float(unit.strength)
	return unit

static func validate_order(state: Dictionary, side: int, order: Dictionary) -> Dictionary:
	if side not in [0, 1]:
		return _error("无效阵营")
	if state.get("phase", "planning") != "planning":
		return _error("战役已结束或正在结算")
	if state.get("ready", [false, false])[side]:
		return _error("本方已提交回合")
	var unit = _find_unit(state, str(order.get("unit_id", "")))
	if unit.is_empty() or int(unit.side) != side or float(unit.strength) <= 0:
		return _error("部队不存在或不属于本方")
	var kind = str(order.get("kind", ""))
	if kind not in KINDS:
		return _error("未知命令")
	if str(order.get("stance", "balanced")) not in STANCES:
		return _error("未知战术姿态")
	var target = order.get("target", [])
	if not target is Array:
		return _error("目标必须是坐标数组")
	if target.is_empty() and kind in ["move", "attack", "recon", "retreat", "engineer"]:
		return _error("此命令需要地图目标")
	if not target.is_empty():
		if target.size() != 2 or not _coordinate(target[0]) or not _coordinate(target[1]) or _tile(state, target).is_empty():
			return _error("目标不在地图内")
		if str(_tile(state, target).get("terrain", "plains")) == "water" and not _tile(state, target).get("bridge", false):
			return _error("目标为不可通行水域")
	if kind == "engineer" and unit.type != "engineer":
		return _error("仅工兵可以执行工程命令")
	return {"ok": true, "error": ""}

static func submit_order(state: Dictionary, side: int, order: Dictionary) -> Dictionary:
	var validation = validate_order(state, side, order)
	if not validation.ok:
		return validation
	var unit = _find_unit(state, str(order.unit_id))
	var accepted = {"unit_id": str(unit.id), "kind": str(order.kind), "target": order.get("target", []).duplicate(), "stance": str(order.get("stance", "balanced"))}
	var old = state.orders.get(unit.id, {})
	if old.get("kind") == accepted.kind and old.get("target") == accepted.target and old.get("stance") == accepted.stance:
		return validation
	accepted["delay"] = _command_delay(state, unit)
	state.orders[unit.id] = accepted
	unit.command_delay = accepted.delay
	return validation

static func submit_support(state: Dictionary, side: int, kind: String, target: Array = []) -> Dictionary:
	if side not in [0, 1] or state.get("phase", "") != "planning":
		return _error("当前不能分配支援")
	if state.ready[side]:
		return _error("本方已提交回合")
	if kind in ["none", "cancel", ""]:
		state.support.erase(str(side))
		return {"ok": true, "error": ""}
	if kind not in ["air", "artillery", "recon"]:
		return _error("未知支援类型")
	if target.size() != 2 or not _coordinate(target[0]) or not _coordinate(target[1]) or _tile(state, target).is_empty():
		return _error("支援目标不在地图内")
	if not _support_available(state, side, kind):
		return _error("天气或可用资源不支持此支援")
	if kind == "artillery":
		var in_range = false
		for unit in state.units:
			if unit.side == side and unit.type == "artillery" and unit.strength > 0 and unit.ammo >= 20 and _distance(_pos(unit), target) <= 4:
				in_range = true
		if not in_range:
			return _error("没有射程内且弹药充足的炮兵")
	state.support[str(side)] = {"kind": kind, "target": target.duplicate()}
	return {"ok": true, "error": ""}

static func observe(state: Dictionary, side: int) -> Dictionary:
	if side not in [0, 1]:
		return {}
	var scenario: Dictionary = state.scenario
	var result = {"scenario_id": scenario.get("id", ""), "title": scenario.get("title", ""), "era": scenario.get("era", "ww2"), "turn": int(state.turn), "max_turns": int(scenario.get("max_turns", 20)), "side": side, "phase": state.phase, "map": {"width": scenario.get("width", 0), "height": scenario.get("height", 0), "tiles": scenario.get("tiles", []).duplicate(true)}, "units": [], "sides": scenario.get("sides", []).duplicate(true), "objectives": state.objectives.duplicate(true), "depots": [], "weather": state.weather, "scores": state.scores.duplicate(), "ready": state.ready.duplicate(), "logs": [], "contacts": [], "orders": {}, "hex_km": scenario.get("hex_km", 5), "turn_hours": scenario.get("turn_hours", 6), "support": state.get("support", {}).get(str(side), {}).duplicate(true), "result": state.get("result", {}).duplicate(true), "date": scenario.get("date", ""), "description": scenario.get("description", ""), "design_notes": scenario.get("design_notes", ""), "sources": scenario.get("sources", []).duplicate(true), "weather_cycle": scenario.get("weather_cycle", false), "upcoming_reinforcements": [], "control": state.get("control", {}).duplicate()}
	var visible = _visible(state, side)
	for unit in state.units:
		if float(unit.strength) <= 0:
			continue
		if int(unit.side) == side:
			result.units.append(unit.duplicate(true))
			if state.orders.has(unit.id):
				result.orders[unit.id] = state.orders[unit.id].duplicate(true)
		elif visible.has(unit.id):
			result.units.append(_mask(unit, state.turn))
	for rf_index in range(scenario.get("reinforcements", []).size()):
		if state.reinforced.has(rf_index):
			continue
		var entry: Dictionary = scenario.reinforcements[rf_index]
		var ru = entry.get("unit", {})
		if int(ru.get("side", -1)) == side:
			result.upcoming_reinforcements.append({"turn": int(entry.get("turn", 1)), "name": str(ru.get("name", "增援")), "type": str(ru.get("type", "infantry")), "q": int(ru.get("q", 0)), "r": int(ru.get("r", 0))})
	for depot in scenario.get("depots", []):
		if int(depot.side) == side:
			result.depots.append(depot.duplicate(true))
	for contact in state.get("contacts", {}).get(str(side), {}).values():
		if not visible.has(contact.id) and int(state.turn) - int(contact.last_seen) <= 3:
			result.contacts.append(contact.duplicate(true))
	for event in state.get("events", []):
		if int(event.side) == side or int(event.side) == -1:
			result.logs.append(str(event.text))
	return result

static func resolve(original: Dictionary) -> Dictionary:
	var state = original.duplicate(true)
	if state.phase != "planning":
		return state
	state.events = []
	state.logs = []
	var rng = RandomNumberGenerator.new()
	rng.seed = int(state.seed) + int(state.turn) * 104729
	_reinforce(state)
	_advance_weather(state, rng)
	_supply(state, true)
	for unit in state.units:
		unit["moved"] = false
		unit["fought"] = false
		unit["retreated"] = false
		unit["movement_remaining"] = 0.0
		unit.status = "ready" if unit.supply >= 0.5 else "undersupplied"
		if not state.orders.has(unit.id):
			state.orders[unit.id] = {"unit_id": unit.id, "kind": "defend", "target": [], "stance": "balanced", "delay": 0}
	for step in range(6):
		_substep(state, rng, step)
	_finish_units(state)
	_score(state)
	state.turn = int(state.turn) + 1
	state.ready = [false, false]
	state.support = {}
	_update_contacts(state)
	for event in state.events:
		state.logs.append(event.text)
	return state

static func _substep(state: Dictionary, rng: RandomNumberGenerator, step: int) -> void:
	var intents = {}
	var active = []
	for unit in state.units:
		if float(unit.strength) <= 0:
			continue
		active.append(unit)
		var order: Dictionary = state.orders.get(unit.id, {})
		if int(order.get("delay", 0)) > 0:
			order.delay = int(order.delay) - 1
			unit.command_delay = order.delay
			continue
		if unit.get("zoc_stop", false):
			continue
		var kind = str(order.get("kind", "defend"))
		var target: Array = order.get("target", [])
		if unit.retreated or kind not in ["move", "attack", "recon", "retreat", "engineer"] or target.is_empty() or _pos(unit) == target:
			continue
		if float(unit.organization) < 8 or (unit.type in MOTOR and float(unit.fuel) < 2):
			continue
		unit.movement_remaining += _speed(state, unit, order) / 6.0
		var path = _path(state, unit, target)
		if path.size() < 2:
			continue
		var next: Array = path[1]
		var cost = _move_cost(state, unit, _pos(unit), next)
		if unit.movement_remaining >= cost:
			intents[unit.id] = next
	# Build encounter graph from the same pre-movement positions. Crossing edges
	# and meeting on an empty cell are both battles; no first-side movement advantage.
	var edges = []
	var engaged = {}
	for a_index in range(active.size()):
		var a: Dictionary = active[a_index]
		for b_index in range(a_index + 1, active.size()):
			var b: Dictionary = active[b_index]
			if a.side == b.side:
				continue
			var ap = _pos(a)
			var bp = _pos(b)
			var an: Array = intents.get(a.id, ap)
			var bn: Array = intents.get(b.id, bp)
			var encounter = (an == bn) or (an == bp and bn == ap) or (an == bp) or (bn == ap)
			var a_order: Dictionary = state.orders.get(a.id, {})
			var b_order: Dictionary = state.orders.get(b.id, {})
			var a_attack = a_order.get("kind") == "attack" and int(a_order.get("delay", 0)) == 0 and a_order.get("target", []) == bp
			var b_attack = b_order.get("kind") == "attack" and int(b_order.get("delay", 0)) == 0 and b_order.get("target", []) == ap
			if _distance(ap, bp) <= 1 and (a_attack or b_attack):
				encounter = true
			if encounter and not a.retreated and not b.retreated:
				edges.append([a, b])
				engaged[a.id] = true
				engaged[b.id] = true
	var losses = {}
	var shocks = {}
	var frontage = {}
	for edge in edges:
		for unit in edge:
			frontage[unit.id] = int(frontage.get(unit.id, 0)) + 1
	for edge in edges:
		var a: Dictionary = edge[0]
		var b: Dictionary = edge[1]
		var pa = _combat_power(state, a, b, intents.has(a.id), step) / sqrt(float(frontage[a.id]))
		var pb = _combat_power(state, b, a, intents.has(b.id), step) / sqrt(float(frontage[b.id]))
		var total = maxf(0.1, pa + pb)
		var loss_a = clampf(pb / total * 7.0 * rng.randf_range(0.8, 1.2), 0.15, 9.0)
		var loss_b = clampf(pa / total * 7.0 * rng.randf_range(0.8, 1.2), 0.15, 9.0)
		losses[a.id] = float(losses.get(a.id, 0.0)) + loss_a
		losses[b.id] = float(losses.get(b.id, 0.0)) + loss_b
		shocks[a.id] = float(shocks.get(a.id, 0.0)) + loss_a * 1.5
		shocks[b.id] = float(shocks.get(b.id, 0.0)) + loss_b * 1.5
	for unit in active:
		if not engaged.has(unit.id):
			continue
		unit.strength = maxf(0, float(unit.strength) - float(losses.get(unit.id, 0)))
		unit.organization = maxf(0, float(unit.organization) - float(shocks.get(unit.id, 0)))
		unit.ammo = maxf(0, float(unit.ammo) - 5.0)
		unit.fatigue = minf(100, float(unit.fatigue) + 4.0)
		unit.entrenchment = maxf(0, float(unit.entrenchment) - 0.08)
		unit.fought = true
		unit.status = "engaged"
		if step == 0 or float(unit.strength) <= 0:
			_event(state, unit.side, "%s：交战损失 %.1f，组织 %.0f" % [unit.name, losses[unit.id], unit.organization])
	# Retreats resolve in a stable ID order, with reservations preventing collisions.
	var retreating = active.filter(func(u): return engaged.has(u.id) and u.strength > 0 and (u.organization < _retreat_threshold(state, u) or u.strength < 15))
	retreating.sort_custom(func(a, b): return str(a.id) < str(b.id))
	for unit in retreating:
		_retreat(state, unit)
	# Friendly capacity is decided collectively. Existing positions remain reserved
	# unless the unit has an accepted destination, avoiding overstacking cascades.
	var accepted = {}
	var counts = {}
	for unit in active:
		if unit.strength <= 0:
			continue
		var key = _key(_pos(unit)) + ":" + str(unit.side)
		counts[key] = int(counts.get(key, 0)) + 1
	var movers = active.filter(func(u): return intents.has(u.id) and not engaged.has(u.id) and not u.retreated and u.strength > 0)
	movers.sort_custom(func(a, b): return str(a.id) < str(b.id))
	for unit in movers:
		var next: Array = intents[unit.id]
		var key = _key(next) + ":" + str(unit.side)
		if int(counts.get(key, 0)) >= 3 or _enemy_at(state, next, unit.side):
			continue
		accepted[unit.id] = next
		counts[key] = int(counts.get(key, 0)) + 1
		var old_key = _key(_pos(unit)) + ":" + str(unit.side)
		counts[old_key] = int(counts.get(old_key, 1)) - 1
		# Entering an enemy zone of control ends movement for combat formations.
		if unit.type not in ["hq", "logistics", "air_defense"] and _enemy_zoc(state, next, unit.side):
			intents.erase(unit.id)
			unit.movement_remaining = 0.0
			unit["zoc_stop"] = true
	for unit in movers:
		if not accepted.has(unit.id):
			continue
		var next: Array = accepted[unit.id]
		var cost = _move_cost(state, unit, _pos(unit), next)
		unit.q = int(next[0])
		unit.r = int(next[1])
		unit.movement_remaining = maxf(0, unit.movement_remaining - cost)
		unit.fuel = maxf(0, unit.fuel - cost * (3.0 if unit.type in MOTOR else 0.2))
		unit.fatigue = minf(100, unit.fatigue + cost * 1.5)
		unit.entrenchment = 0.0
		unit.moved = true
		unit.status = "moving"
		state.control[_key(next)] = unit.side
	# Successful assault can seize the defender hex if it is now empty.
	for unit in active:
		if not intents.has(unit.id) and not unit.fought:
			continue
		if float(unit.strength) <= 0:
			continue
		var order: Dictionary = state.orders.get(unit.id, {})
		if str(order.get("kind", "")) != "attack" or order.get("delay", 0) > 0:
			continue
		var target: Array = order.get("target", [])
		if target.size() != 2:
			continue
		if _enemy_at(state, target, unit.side) or _stack(state, target, unit.side) >= 3:
			continue
		if _distance(_pos(unit), target) == 1 and unit.organization >= 20 and not unit.retreated:
			# only advance if adjacent after this turn's fights
			var can_step = true
			for other in state.units:
				if other.side != unit.side and other.strength > 0 and _pos(other) == target:
					can_step = false
					break
			if can_step and float(unit.movement_remaining) >= 0.1:
				var cost = _move_cost(state, unit, _pos(unit), target)
				if unit.movement_remaining >= cost and not _enemy_at(state, target, unit.side):
					unit.q = int(target[0])
					unit.r = int(target[1])
					unit.movement_remaining = maxf(0.0, unit.movement_remaining - cost)
					unit.entrenchment = 0.0
					unit.moved = true
					state.control[_key(target)] = unit.side
					_event(state, unit.side, "%s：突破占领目标格" % unit.name)
	# Artillery/air is a once-per-turn allocation, requiring a current sighting.
	if step == 2:
		_apply_support(state, rng)

static func _combat_power(state: Dictionary, unit: Dictionary, enemy: Dictionary, advancing: bool, _step: int) -> float:
	var order: Dictionary = state.orders.get(unit.id, {})
	var terrain = str(_tile(state, _pos(unit)).get("terrain", "plains"))
	var quality = float(unit.quality)
	if quality > 2.0:
		quality /= 100.0
	quality = clampf(quality, 0.4, 1.5)
	var power = float(POWER.get(unit.type, 1.0)) * float(unit.strength) * maxf(0.1, float(unit.organization) / 100.0) * quality
	power *= (1.0 - float(unit.fatigue) * 0.006) * (0.25 + minf(1.0, float(unit.ammo) / 20.0) * 0.75)
	power *= 0.6 + float(unit.supply) * 0.4
	if not advancing:
		power *= float(DEFENSE.get(terrain, 1.0)) * (1.0 + float(unit.entrenchment) * 0.25)
	else:
		var target = _tile(state, _pos(enemy))
		if target.get("river", false) and not target.get("bridge", false):
			power *= 0.6
	var stance = str(order.get("stance", "balanced"))
	if stance == "aggressive":
		power *= 1.15 if advancing else 0.9
	elif stance == "cautious":
		power *= 0.85 if advancing else 1.1
	if unit.type == "armor" and terrain in ["city", "forest", "mountain", "bocage"]:
		power *= 0.7
	if enemy.type == "armor" and unit.type in ["infantry", "mechanized", "airborne"]:
		power *= 1.0 + float(_rules(state).antitank)
	var infantry = false
	var armor = false
	var support = false
	for ally in state.units:
		if ally.side != unit.side or ally.strength <= 0 or _distance(_pos(unit), _pos(ally)) > 1:
			continue
		infantry = infantry or ally.type in ["infantry", "mechanized", "motorized"]
		armor = armor or ally.type == "armor"
		support = support or (ally.type == "artillery" and ally.ammo > 10)
	if infantry and armor:
		power *= 1.2
	if support:
		power *= 1.1
	if state.weather in ["rain", "snow", "storm"] and unit.type in MOTOR:
		power *= 0.85
	if _night(state):
		power *= 0.85 if state.scenario.get("era", "ww2") != "modern" else 1.0
	return maxf(0.1, power)

static func _finish_units(state: Dictionary) -> void:
	for unit in state.units:
		if unit.strength <= 0:
			unit.status = "destroyed"
			state.orders.erase(unit.id)
			continue
		var order: Dictionary = state.orders.get(unit.id, {})
		var kind = str(order.get("kind", "defend"))
		if not unit.fought and not unit.moved:
			var resting = kind in ["rest", "reserve"]
			unit.organization = minf(100, unit.organization + (12.0 if resting else 5.0) * unit.supply)
			unit.fatigue = maxf(0, unit.fatigue - (18.0 if resting else 8.0) * (0.3 + 0.7 * unit.supply))
			if kind in ["defend", "reserve", "engineer"]:
				unit.entrenchment = minf(3.0, unit.entrenchment + (0.65 if unit.type == "engineer" else 0.35))
		if kind == "engineer" and unit.type == "engineer" and not unit.fought and unit.supply >= 0.3:
			var spots = [_pos(unit)]
			var tpos = order.get("target", [])
			if tpos is Array and tpos.size() == 2 and _distance(_pos(unit), tpos) <= 1:
				spots.append(tpos)
			for spot in spots:
				var tile = _tile(state, spot)
				if tile.get("river", false) and not tile.get("bridge", false):
					tile.bridge = true
					_event(state, unit.side, "%s：在 %s,%s 架设渡河桥梁" % [unit.name, spot[0], spot[1]])
					break
		unit.erase("moved")
		unit.erase("fought")
		unit.erase("retreated")
		unit.erase("zoc_stop")

static func _retreat_threshold(state: Dictionary, unit: Dictionary) -> float:
	var stance = state.orders.get(unit.id, {}).get("stance", "balanced")
	return 35.0 if stance == "cautious" else (15.0 if stance == "aggressive" else 25.0)

static func _retreat(state: Dictionary, unit: Dictionary) -> void:
	var candidates = []
	for next in _neighbors(_pos(unit)):
		if _move_cost(state, unit, _pos(unit), next) >= 999 or _enemy_at(state, next, unit.side) or _stack(state, next, unit.side) >= 3:
			continue
		var safety = 0.0
		for enemy in state.units:
			if enemy.side != unit.side and enemy.strength > 0:
				safety += minf(5, _distance(next, _pos(enemy)))
		if int(state.control.get(_key(next), -1)) == unit.side:
			safety += 3.0
		candidates.append({"pos": next, "score": safety})
	candidates.sort_custom(func(a, b): return a.score > b.score)
	if candidates.is_empty():
		unit.strength = maxf(0, unit.strength - 12)
		unit.organization = maxf(0, unit.organization - 5)
		unit.status = "surrounded"
		_event(state, unit.side, "%s：退路被截断，额外损失" % unit.name)
		return
	unit.q = int(candidates[0].pos[0])
	unit.r = int(candidates[0].pos[1])
	unit.retreated = true
	unit.entrenchment = 0.0
	unit.organization = minf(100, unit.organization + 8)
	unit.status = "retreating"
	state.orders[unit.id] = {"unit_id": unit.id, "kind": "defend", "target": [], "stance": "cautious", "delay": 0}
	_event(state, unit.side, "%s：撤退至 %d,%d" % [unit.name, unit.q, unit.r])

static func _supply(state: Dictionary, replenish: bool) -> void:
	var used = {}
	var ordered = state.units.duplicate()
	ordered.sort_custom(func(a, b): return str(a.id) < str(b.id))
	for unit in ordered:
		if unit.strength <= 0:
			continue
		var best = []
		var chosen = -1
		var best_cost = INF
		var depots: Array = state.scenario.get("depots", [])
		for index in range(depots.size()):
			var depot: Dictionary = depots[index]
			if int(depot.side) != unit.side or _enemy_at(state, [depot.q, depot.r], unit.side):
				continue
			var path = _supply_path(state, unit, [depot.q, depot.r])
			if path.is_empty():
				continue
			var cost = _route_cost(state, path)
			if cost < best_cost and float(used.get(index, 0)) < float(depot.get("capacity", 100)):
				best = path
				best_cost = cost
				chosen = index
		unit.supply_path = best
		var ratio = 0.0
		if chosen >= 0:
			var capacity = float(depots[chosen].get("capacity", 100)) * float(_rules(state).supply_efficiency)
			var need = (14.0 if unit.type in MOTOR else 10.0) * maxf(0.25, float(unit.strength) / 100.0)
			var bottleneck = 1.0
			for pos in best:
				var tile = _tile(state, pos)
				if tile.get("river", false) and not tile.get("bridge", false):
					bottleneck = minf(bottleneck, 0.4)
				elif tile.get("terrain", "") in ["mountain", "marsh"] and not tile.get("road", false):
					bottleneck = minf(bottleneck, 0.55)
			if state.weather in ["rain", "snow", "storm"]:
				bottleneck *= 0.75
			ratio = clampf((capacity - float(used.get(chosen, 0))) / need, 0, 1) * bottleneck
			used[chosen] = float(used.get(chosen, 0)) + need * ratio
		unit.supply = ratio
		if not replenish:
			continue
		unit.ammo = clampf(unit.ammo + 22.0 * ratio - 2.0, 0, 100)
		unit.fuel = clampf(unit.fuel + 24.0 * ratio - (3.0 if unit.type in MOTOR else 0.5), 0, 100)
		if ratio < 0.25:
			unit.strength = maxf(0, unit.strength - 1.5)
			unit.organization = maxf(0, unit.organization - 7.0)
			unit.fatigue = minf(100, unit.fatigue + 6.0)
			_event(state, unit.side, "%s：补给中断，发生消耗与疲劳" % unit.name)

static func _supply_path(state: Dictionary, unit: Dictionary, target: Array) -> Array:
	return _search(state, unit, target, true)

static func _path(state: Dictionary, unit: Dictionary, target: Array) -> Array:
	return _search(state, unit, target, false)

static func _search(state: Dictionary, unit: Dictionary, target: Array, supply: bool) -> Array:
	var start = _pos(unit)
	var frontier = [start]
	var costs = {_key(start): 0.0}
	var previous = {}
	var max_range = float(_rules(state).supply_range)
	while not frontier.is_empty():
		var best_index = 0
		var best_value = INF
		for index in range(frontier.size()):
			var value = float(costs[_key(frontier[index])])
			if not supply:
				value += _distance(frontier[index], target) * 0.6
			if value < best_value:
				best_value = value
				best_index = index
		var current: Array = frontier.pop_at(best_index)
		if current == target:
			var route = [current]
			while previous.has(_key(current)):
				current = previous[_key(current)]
				route.push_front(current)
			return route
		for next in _neighbors(current):
			var cost = _move_cost(state, unit, current, next)
			if cost >= 999:
				continue
			if supply:
				if _enemy_at(state, next, unit.side) or _enemy_zoc(state, next, unit.side):
					continue
				var tile = _tile(state, next)
				cost = 0.5 if tile.get("rail", false) else (0.7 if tile.get("road", false) else cost)
			var total = float(costs[_key(current)]) + cost
			if supply and total > max_range:
				continue
			if total < float(costs.get(_key(next), INF)):
				costs[_key(next)] = total
				previous[_key(next)] = current
				if not frontier.has(next):
					frontier.append(next)
	return []

static func _route_cost(state: Dictionary, path: Array) -> float:
	var result = 0.0
	for pos in path:
		var tile = _tile(state, pos)
		result += 0.5 if tile.get("rail", false) else (0.7 if tile.get("road", false) else float(TERRAIN_COST.get(tile.get("terrain", "plains"), 1)))
	return result

static func _move_cost(state: Dictionary, unit: Dictionary, from: Array, to: Array) -> float:
	var tile = _tile(state, to)
	if tile.is_empty():
		return 999.0
	var terrain = str(tile.get("terrain", "plains"))
	var cost = float(TERRAIN_COST.get(terrain, 1.0))
	if terrain == "water":
		return 1.0 if tile.get("bridge", false) else 999.0
	var origin = _tile(state, from)
	if tile.get("road", false) and origin.get("road", false):
		cost = 0.65
	elif unit.type in MOTOR and terrain in ["forest", "marsh", "mountain", "bocage"]:
		cost *= 1.5
	if tile.get("river", false) and not tile.get("bridge", false):
		cost += 1.0 if unit.type == "engineer" else 2.0
	if int(tile.get("elevation", 0)) > int(origin.get("elevation", 0)):
		cost += 0.3 * (int(tile.get("elevation", 0)) - int(origin.get("elevation", 0)))
	if state.weather in ["rain", "snow", "storm"] and not tile.get("road", false):
		cost *= 1.35
	return cost

static func _speed(state: Dictionary, unit: Dictionary, order: Dictionary) -> float:
	var speed = 4.0 if unit.type in MOTOR else 2.5
	if unit.type == "artillery":
		speed = 2.0
	# Scale operations to scenario geography and duration, with playable bounds.
	speed *= clampf(float(state.scenario.get("turn_hours", 6)) / 6.0 * 5.0 / maxf(1, float(state.scenario.get("hex_km", 5))), 0.65, 2.0)
	speed *= (1.0 - unit.fatigue * 0.004) * (0.65 + unit.organization * 0.0035)
	if order.get("stance") == "cautious":
		speed *= 0.8
	if order.get("kind") == "retreat":
		speed *= 1.25
	if _night(state):
		speed *= 0.8
	return speed

static func _visible(state: Dictionary, side: int) -> Dictionary:
	var visible = {}
	var rules = _rules(state)
	for unit in state.units:
		if unit.side != side or unit.strength <= 0:
			continue
		var radius = int(rules.recon_range) if unit.type == "recon" else 2
		if state.orders.get(unit.id, {}).get("kind") == "recon":
			radius += 1
		if state.weather in ["rain", "snow", "storm", "fog"] or _night(state):
			radius = maxi(1, radius - 1)
		for enemy in state.units:
			if enemy.side == side or enemy.strength <= 0:
				continue
			var distance = _distance(_pos(unit), _pos(enemy))
			var cover = str(_tile(state, _pos(enemy)).get("terrain", "plains")) in ["forest", "city", "bocage", "mountain"]
			if distance <= maxi(1, radius - (1 if cover else 0)) and _line_of_sight(state, _pos(unit), _pos(enemy)):
				visible[enemy.id] = true
	var support = state.get("support", {}).get(str(side), {})
	if support.get("kind") == "recon" and _support_available(state, side, "recon"):
		for enemy in state.units:
			if enemy.side != side and enemy.strength > 0 and support.get("target", []).size() == 2 and _distance(_pos(enemy), support.target) <= 2:
				visible[enemy.id] = true
	return visible

static func _line_of_sight(state: Dictionary, from: Array, to: Array) -> bool:
	var distance = _distance(from, to)
	if distance <= 1:
		return true
	var height = maxi(int(_tile(state, from).get("elevation", 0)), int(_tile(state, to).get("elevation", 0)))
	for step in range(1, distance):
		var t = float(step) / float(distance)
		var x = lerpf(float(from[0]), float(to[0]), t)
		var z = lerpf(float(from[1]), float(to[1]), t)
		var y = -x - z
		var rx = roundf(x)
		var ry = roundf(y)
		var rz = roundf(z)
		var dx = absf(rx - x)
		var dy = absf(ry - y)
		var dz = absf(rz - z)
		if dx > dy and dx > dz:
			rx = -ry - rz
		elif dz >= dy:
			rz = -rx - ry
		var tile = _tile(state, [int(rx), int(rz)])
		if int(tile.get("elevation", 0)) > height or str(tile.get("terrain", "")) in ["mountain", "forest", "city", "bocage"]:
			return false
	return true

static func _mask(unit: Dictionary, turn: int) -> Dictionary:
	return {"id": unit.id, "name": unit.name, "side": unit.side, "q": unit.q, "r": unit.r, "type": unit.type, "size": unit.size, "formation": unit.formation, "strength_band": "strong" if unit.strength >= 65 else ("medium" if unit.strength >= 30 else "weak"), "visible": true, "last_seen": turn}

static func _update_contacts(state: Dictionary) -> void:
	for side in [0, 1]:
		var seen = _visible(state, side)
		var contacts: Dictionary = state.contacts[str(side)]
		for unit in state.units:
			if seen.has(unit.id):
				contacts[unit.id] = _mask(unit, int(state.turn))
		for id in contacts.keys():
			if int(state.turn) - int(contacts[id].last_seen) > 3:
				contacts.erase(id)

static func _command_delay(state: Dictionary, unit: Dictionary) -> int:
	var nearest = 999
	var has_hq = false
	for hq in state.units:
		if hq.side == unit.side and hq.type == "hq" and hq.strength > 0:
			has_hq = true
			nearest = mini(nearest, _distance(_pos(unit), _pos(hq)))
	var rules = _rules(state)
	# Scenarios without HQ counters represent command at their off-map echelon.
	if not has_hq:
		return int(rules.command_delay) + 1
	return int(rules.command_delay) + maxi(0, int(ceil(float(nearest - int(rules.command_range)) / 3.0)))

static func _support_available(state: Dictionary, side: int, kind: String) -> bool:
	if kind == "air":
		return float(_rules(state).air_power) > 0 and state.weather not in ["storm", "fog"]
	if kind == "recon":
		return true
	for unit in state.units:
		if unit.side == side and unit.type == "artillery" and unit.strength > 0 and unit.ammo >= 20:
			return true
	return false

static func _apply_support(state: Dictionary, rng: RandomNumberGenerator) -> void:
	var impacts = []
	for side in [0, 1]:
		var request: Dictionary = state.get("support", {}).get(str(side), {})
		var kind = str(request.get("kind", ""))
		var target: Array = request.get("target", [])
		if kind not in ["air", "artillery"] or target.size() != 2 or not _support_available(state, side, kind):
			continue
		var visible = _visible(state, side)
		var battery = {}
		if kind == "artillery":
			for unit in state.units:
				if unit.side == side and unit.type == "artillery" and unit.strength > 0 and unit.ammo >= 20 and _distance(_pos(unit), target) <= 4:
					battery = unit
					break
			if battery.is_empty():
				continue
			battery.ammo -= 20
		for enemy in state.units:
			if enemy.side == side or enemy.strength <= 0 or _pos(enemy) != target or not visible.has(enemy.id):
				continue
			var damage = rng.randf_range(5, 9)
			if kind == "air":
				damage *= float(_rules(state).air_power)
				for aa in state.units:
					if aa.side == enemy.side and aa.type == "air_defense" and aa.strength > 0 and aa.ammo >= 5 and _distance(_pos(aa), target) <= 2:
						damage *= 1.0 - float(_rules(state).air_defense) * 0.65
						aa.ammo -= 5
			impacts.append({"unit": enemy, "damage": damage})
			_event(state, side, "支援打击 %d,%d 的已侦察目标" % [target[0], target[1]])
	for impact in impacts:
		impact.unit.strength = maxf(0, impact.unit.strength - impact.damage)
		impact.unit.organization = maxf(0, impact.unit.organization - impact.damage * 1.5)
		impact.unit.fought = true
		_event(state, impact.unit.side, "%s：遭受火力支援打击" % impact.unit.name)

static func _reinforce(state: Dictionary) -> void:
	var entries: Array = state.scenario.get("reinforcements", [])
	for index in range(entries.size()):
		var entry: Dictionary = entries[index]
		if int(entry.get("turn", 1)) > int(state.turn) or state.reinforced.has(index):
			continue
		var unit = _unit(entry.unit)
		if _enemy_at(state, _pos(unit), unit.side) or _stack(state, _pos(unit), unit.side) >= 3:
			continue
		state.units.append(unit)
		state.reinforced.append(index)
		_event(state, unit.side, "增援抵达：%s" % unit.name)


static func _advance_weather(state: Dictionary, rng: RandomNumberGenerator) -> void:
	var schedule = state.scenario.get("weather_schedule", [])
	if schedule is Array and not schedule.is_empty():
		var turn = int(state.turn)
		var pick = schedule[(turn - 1) % schedule.size()]
		state.weather = str(pick)
		return
	if not state.scenario.get("weather_cycle", false):
		return
	# Light Markov-ish rotation so long battles feel less static.
	var roll = rng.randf()
	var current = str(state.weather)
	var table = {
		"clear": ["clear", "clear", "overcast", "fog"],
		"overcast": ["overcast", "clear", "rain", "fog"],
		"rain": ["rain", "overcast", "clear", "storm"],
		"fog": ["fog", "clear", "overcast", "rain"],
		"storm": ["storm", "rain", "overcast"],
		"snow": ["snow", "overcast", "fog"],
	}
	var options = table.get(current, ["clear", "overcast", "rain", "fog"])
	state.weather = options[int(floor(roll * options.size())) % options.size()]

static func _score(state: Dictionary) -> void:
	for objective in state.objectives:
		var present = [false, false]
		for unit in state.units:
			if unit.strength > 0 and _pos(unit) == [objective.q, objective.r]:
				present[unit.side] = true
		if present[0] != present[1]:
			var owner = 0 if present[0] else 1
			var previous = int(objective.get("owner", -1))
			if previous != owner:
				objective.owner = owner
				_event(state, -1, "%s由%s控制" % [objective.get("name", "目标"), state.scenario.get("sides", [{"name": "蓝方"}, {"name": "红方"}])[owner].name])
				if previous in [0, 1] and previous != owner:
					state.scores[previous] = maxi(0, state.scores[previous] - int(objective.get("value", 1)))
				if owner in [0, 1]:
					state.scores[owner] += int(objective.get("value", 1))
	# Holding an objective no longer stacks score every turn; capture/loss moves the point once.
	var alive = [0, 0]
	for unit in state.units:
		if unit.strength > 0:
			alive[unit.side] += 1
	var future = [false, false]
	for index in range(state.scenario.get("reinforcements", []).size()):
		if not state.reinforced.has(index):
			future[int(state.scenario.reinforcements[index].unit.side)] = true
	var finished = int(state.turn) >= int(state.scenario.get("max_turns", 20))
	var winner = -1
	var reason = "达到战役时限，按目标积分结算"
	if (alive[0] == 0 and not future[0]) or (alive[1] == 0 and not future[1]):
		finished = true
		winner = 0 if alive[0] > 0 else (1 if alive[1] > 0 else -1)
		reason = "一方已无可用部队"
	elif finished:
		winner = 0 if state.scores[0] > state.scores[1] else (1 if state.scores[1] > state.scores[0] else -1)
	if finished:
		state.phase = "finished"
		state.result = {"winner": winner, "reason": reason, "scores": state.scores.duplicate()}
		_event(state, -1, "战役结束：%s；积分 %d : %d" % [reason, state.scores[0], state.scores[1]])


static func preview_move(state: Dictionary, unit_id: String, target: Array) -> Dictionary:
	var unit = _find_unit(state, unit_id)
	if unit.is_empty() or target.size() != 2 or _tile(state, target).is_empty():
		return {"ok": false, "error": "invalid"}
	var path = _path(state, unit, target)
	if path.is_empty():
		return {"ok": false, "error": "no_path", "path": []}
	var cost = 0.0
	for i in range(1, path.size()):
		cost += _move_cost(state, unit, path[i - 1], path[i])
	var speed = maxf(0.2, _speed(state, unit, state.orders.get(unit_id, {"kind": "move"})))
	var turns = ceili(cost / maxf(0.5, speed))
	var delay = int(state.orders.get(unit_id, {}).get("delay", unit.get("command_delay", 0)))
	var zoc_hex = []
	var stacked = false
	if path.size() >= 2 and unit.type not in ["hq", "logistics", "air_defense"] and _enemy_zoc(state, path[1], unit.side):
		zoc_hex = path[1]
	if _stack(state, target, unit.side) >= 3:
		stacked = true
	return {"ok": true, "path": path, "cost": cost, "turns": turns, "effective_turns": delay + turns, "fuel_ok": (not unit.type in MOTOR) or unit.fuel >= cost * 3.0, "zoc_stop_hex": zoc_hex, "blocked_by_stack": stacked, "command_delay": delay}

static func estimate_combat(state: Dictionary, attacker_id: String, defender_id: String) -> Dictionary:
	var a = _find_unit(state, attacker_id)
	var d = _find_unit(state, defender_id)
	if a.is_empty() or d.is_empty() or a.side == d.side:
		return {"ok": false}
	var my_frontage = 0
	var their_frontage = 0
	var dpos = _pos(d)
	var apos = _pos(a)
	for unit in state.units:
		if float(unit.strength) <= 0 or unit.type in ["hq", "logistics"]:
			continue
		if unit.side == a.side and _distance(_pos(unit), dpos) <= 1:
			my_frontage += 1
		if unit.side == d.side and _distance(_pos(unit), apos) <= 1:
			their_frontage += 1
	my_frontage = maxi(1, my_frontage)
	their_frontage = maxi(1, their_frontage)
	var pa = _combat_power(state, a, d, true, 0) / sqrt(float(my_frontage))
	var pb = _combat_power(state, d, a, false, 0) / sqrt(float(their_frontage))
	var total = maxf(0.1, pa + pb)
	var my_loss = clampf(pb / total * 7.0, 0.15, 9.0)
	var their_loss = clampf(pa / total * 7.0, 0.15, 9.0)
	var ratio = pa / maxf(0.1, pb)
	var label = "均势"
	if ratio >= 2.2:
		label = "优势明显"
	elif ratio >= 1.4:
		label = "略占优势"
	elif ratio <= 0.45:
		label = "明显劣势"
	elif ratio <= 0.72:
		label = "略处下风"
	var terrain = str(_tile(state, dpos).get("terrain", "plains"))
	var reasons = []
	if their_frontage > my_frontage:
		reasons.append("敌方接触面更宽")
	if my_frontage > 1:
		reasons.append("我方多路 %d" % my_frontage)
	if float(DEFENSE.get(terrain, 1.0)) >= 1.5:
		reasons.append(terrain + "有利防守")
	if str(d.get("strength_band", "")) == "weak":
		reasons.append("敌军较弱")
	return {"ok": true, "ratio": ratio, "label": label, "my_loss": my_loss, "their_loss": their_loss, "attacker_power": pa, "defender_power": pb, "my_frontage": my_frontage, "their_frontage": their_frontage, "terrain": terrain, "reasons": reasons}

static func ai_orders(state: Dictionary, side: int) -> Array:
	# Decisions use the exact public view; never read enemy authority data or orders.
	var difficulty = str(state.get("ai_difficulty", "normal"))
	var view = observe(state, side)
	if view.is_empty() or view.phase != "planning" or view.ready[side]:
		return []
	var orders = []
	var assigned = {}
	for unit in view.units:
		if unit.side != side:
			continue
		var kind = "defend"
		var target = []
		var stance = "balanced"
		var rest_org = 35 if difficulty == "easy" else 30 if difficulty == "hard" else 35
		var rest_fatigue = 55 if difficulty == "easy" else 70 if difficulty == "hard" else 65
		var supply = float(unit.get("supply", 1.0))
		var fuel = float(unit.get("fuel", 100.0))
		if unit.organization < rest_org or unit.fatigue > rest_fatigue or unit.ammo < 10 or supply < 0.28 or (unit.type in MOTOR and fuel < 12.0):
			kind = "rest"
			# Severely cut-off formations fall back toward own depot if possible.
			if (supply < 0.2 or (unit.type in MOTOR and fuel < 8.0)) and unit.type not in ["hq", "logistics"]:
				var home = {}
				var home_d = 999
				for depot in view.get("depots", []):
					var dp = [int(depot.get("q", 0)), int(depot.get("r", 0))]
					var dd = _distance(_pos(unit), dp)
					if dd < home_d:
						home_d = dd
						home = depot
				if not home.is_empty() and home_d > 1:
					kind = "retreat"
					target = [int(home.q), int(home.r)]
		elif unit.type == "engineer":
			# Try to bridge an adjacent or on-hex river.
			var spots = [_pos(unit)]
			for objective in view.objectives:
				if _distance(_pos(unit), [objective.q, objective.r]) <= 2:
					spots.append([objective.q, objective.r])
			for npos in _neighbors(_pos(unit)):
				spots.append(npos)
			for spot in spots:
				# Use authority map for river check (static terrain, fair).
				var tile = _tile(state, spot)
				if tile.get("river", false) and not tile.get("bridge", false) and _distance(_pos(unit), spot) <= 1:
					kind = "engineer"
					target = spot
					break
			if kind == "defend" and target.is_empty():
				pass
			elif kind != "engineer":
				kind = "defend"
				target = []
				# fall through to normal objective logic below by resetting
		if kind not in ["rest", "retreat", "engineer"]:
			var best = {}
			var best_score = INF
			for objective in view.objectives:
				var pos = [objective.q, objective.r]
				var score = float(_distance(_pos(unit), pos)) + float(assigned.get(_key(pos), 0)) * (6.0 if difficulty == "hard" else 3.0) - float(objective.get("value", 1)) * 0.45
				if int(objective.get("owner", -1)) == side:
					score += 5.0
				if score < best_score:
					best_score = score
					best = objective
			var nearest = {}
			var enemy_distance = 999
			var weak = {}
			var weak_d = 999
			for enemy in view.units:
				if enemy.side == side:
					continue
				var ed = _distance(_pos(unit), _pos(enemy))
				if ed < enemy_distance:
					enemy_distance = ed
					nearest = enemy
				if str(enemy.get("strength_band", "")) == "weak" and ed < weak_d:
					weak_d = ed
					weak = enemy
			if difficulty == "easy" and not nearest.is_empty() and enemy_distance <= 2 and unit.type not in ["hq", "logistics", "artillery"]:
				kind = "defend"
			elif not nearest.is_empty() and enemy_distance <= 1 and unit.type not in ["hq", "logistics", "artillery", "air_defense"]:
				kind = "attack"
				if difficulty == "hard" and not weak.is_empty() and weak_d <= 2:
					target = _pos(weak)
				else:
					target = _pos(nearest)
				var aggro = 60 if difficulty == "hard" else 80 if difficulty == "easy" else 70
				stance = "aggressive" if unit.organization > aggro else "balanced"
			elif difficulty == "hard" and not weak.is_empty() and weak_d <= 3 and unit.type in ["armor", "mechanized", "infantry", "motorized"]:
				kind = "attack"
				target = _pos(weak)
				stance = "aggressive"
			elif not best.is_empty():
				target = [best.q, best.r]
				assigned[_key(target)] = int(assigned.get(_key(target), 0)) + 1
				if unit.type in ["hq", "artillery", "logistics", "air_defense"] and _distance(_pos(unit), target) <= 3:
					kind = "reserve"
					target = []
				elif target != _pos(unit):
					kind = "recon" if unit.type == "recon" else "move"
				else:
					kind = "defend"
			elif not nearest.is_empty():
				kind = "attack"
				target = _pos(nearest)
		orders.append({"unit_id": unit.id, "kind": kind, "target": target, "stance": stance})
	# One operational support toward the densest visible enemy cluster.
	var cluster = []
	var best_n = 0
	for enemy in view.units:
		if int(enemy.get("side", -1)) == side:
			continue
		var epos = [int(enemy.get("q", 0)), int(enemy.get("r", 0))]
		var n = 0
		for other in view.units:
			if int(other.get("side", -1)) != side and _distance(epos, [int(other.get("q", 0)), int(other.get("r", 0))]) <= 1:
				n += 1
		if n > best_n:
			best_n = n
			cluster = epos
	if best_n > 0 and not state.ready[side]:
		for kind in ["artillery", "recon", "air"]:
			if _support_available(state, side, kind):
				if kind == "artillery":
					var in_range = false
					for unit in state.units:
						if unit.side == side and unit.type == "artillery" and unit.strength > 0 and unit.ammo >= 20 and _distance(_pos(unit), cluster) <= 4:
							in_range = true
					if not in_range:
						continue
				submit_support(state, side, kind, cluster)
				break
	return orders

static func _rules(state: Dictionary) -> Dictionary:
	var rules: Dictionary = ERA_DEFAULTS.get(state.scenario.get("era", "ww2"), ERA_DEFAULTS.ww2).duplicate()
	for key in state.scenario.get("era_rules", {}):
		rules[key] = state.scenario.era_rules[key]
	if rules.has("air_support"):
		rules.air_power = rules.air_support
	if rules.has("supply_factor"):
		rules.supply_efficiency = rules.supply_factor
	return rules

static func _night(state: Dictionary) -> bool:
	if not state.scenario.get("night_cycle", false):
		return state.weather == "night"
	var hour = (int(state.scenario.get("start_hour", 6)) + (int(state.turn) - 1) * int(state.scenario.get("turn_hours", 6))) % 24
	return hour >= 21 or hour < 6

static func _tile(state: Dictionary, pos: Array) -> Dictionary:
	if pos.size() != 2:
		return {}
	# Rectangular scenario arrays are row-major, with sparse-map fallback.
	var width = int(state.scenario.get("width", 0))
	if int(pos[0]) < 0 or int(pos[1]) < 0 or int(pos[0]) >= width or int(pos[1]) >= int(state.scenario.get("height", 0)):
		return {}
	var index = int(pos[1]) * width + int(pos[0])
	var tiles: Array = state.scenario.get("tiles", [])
	if index >= 0 and index < tiles.size() and int(tiles[index].q) == int(pos[0]) and int(tiles[index].r) == int(pos[1]):
		return tiles[index]
	for tile in tiles:
		if int(tile.q) == int(pos[0]) and int(tile.r) == int(pos[1]):
			return tile
	return {}

static func _find_unit(state: Dictionary, id: String) -> Dictionary:
	for unit in state.units:
		if str(unit.id) == id:
			return unit
	return {}

static func _enemy_at(state: Dictionary, pos: Array, side: int) -> bool:
	for unit in state.units:
		if int(unit.side) != side and float(unit.strength) > 0 and _pos(unit) == pos:
			return true
	return false

static func _enemy_zoc(state: Dictionary, pos: Array, side: int) -> bool:
	# Friendly occupation screens a supply route against adjacent enemy zones.
	if _stack(state, pos, side) > 0:
		return false
	for unit in state.units:
		if unit.side != side and unit.strength > 10 and unit.organization > 15 and unit.type not in ["hq", "logistics", "artillery"] and _distance(_pos(unit), pos) <= 1:
			return true
	return false

static func _stack(state: Dictionary, pos: Array, side: int) -> int:
	var count = 0
	for unit in state.units:
		if unit.side == side and unit.strength > 0 and _pos(unit) == pos:
			count += 1
	return count

static func _pos(unit: Dictionary) -> Array:
	return [int(unit.q), int(unit.r)]

static func _key(pos: Array) -> String:
	return "%d,%d" % [int(pos[0]), int(pos[1])]

static func _distance(a: Array, b: Array) -> int:
	return maxi(maxi(absi(int(a[0]) - int(b[0])), absi(int(a[1]) - int(b[1]))), absi(int(a[0]) + int(a[1]) - int(b[0]) - int(b[1])))

static func _neighbors(pos: Array) -> Array:
	var neighbors = []
	for direction in DIRECTIONS:
		neighbors.append([int(pos[0]) + direction[0], int(pos[1]) + direction[1]])
	return neighbors

static func _coordinate(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floorf(float(value))

static func _error(message: String) -> Dictionary:
	return {"ok": false, "error": message}

static func _event(state: Dictionary, side: int, message: String) -> void:
	state.events.append({"side": side, "text": message})
