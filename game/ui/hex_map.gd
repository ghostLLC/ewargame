extends Control

signal unit_selected(unit_id: String)
signal hex_selected(q: int, r: int)
signal hex_hovered(q: int, r: int)

const PAPER = Color("e7e4d5")
const INK = Color("384944")
const BLUE = Color("31576b")
const RED = Color("aa5648")
var observation: Dictionary = {}
var selected_id: String = ""
var overlay: String = "terrain"
var zoom_level: float = 1.0
var pan: Vector2 = Vector2.ZERO
var radius: float = 31.0
var dragging: bool = false
var moved: bool = false
var press_position: Vector2 = Vector2.ZERO
var font: Font
var hovered: Vector2i = Vector2i(-99, -99)
var preview_path: Array = []

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	font = ThemeDB.fallback_font
	for path in ["res://assets/fonts/NotoSansSC-Regular.ttf", "res://assets/fonts/NotoSansSC.ttf", "res://assets/fonts/NotoSansSC-Regular.otf"]:
		if ResourceLoader.exists(path):
			font = load(path)
			break
	resized.connect(queue_redraw)
	mouse_exited.connect(func(): hovered = Vector2i(-99, -99); queue_redraw())

func update_view(value: Dictionary, unit_id: String = "") -> void:
	observation = value
	selected_id = unit_id
	queue_redraw()

func fit_map() -> void:
	zoom_level = 1.0
	pan = Vector2.ZERO
	queue_redraw()

func _base_radius() -> float:
	var map: Dictionary = observation.get("map", {})
	var w = float(map.get("width", 12))
	var h = float(map.get("height", 10))
	return min((size.x - 90.0) / (sqrt(3.0) * (w + h * 0.5)), (size.y - 100.0) / (1.5 * h + 0.5))

func _center(q: int, r: int) -> Vector2:
	var map: Dictionary = observation.get("map", {})
	var w = float(map.get("width", 12))
	var h = float(map.get("height", 10))
	var rad = _base_radius() * zoom_level
	var extent = Vector2(sqrt(3.0) * rad * (w - 1.0 + (h - 1.0) * 0.5), 1.5 * rad * (h - 1.0))
	return (size - extent) * 0.5 + pan + Vector2(sqrt(3.0) * rad * (float(q) + float(r) * 0.5), 1.5 * rad * float(r))

func _hex(center: Vector2, rad: float) -> PackedVector2Array:
	var points = PackedVector2Array()
	for i in range(6):
		points.append(center + Vector2.from_angle(deg_to_rad(60.0 * i - 30.0)) * rad)
	return points

func _label(at: Vector2, text: String, color: Color, font_size: int = 12, centered: bool = true) -> void:
	var width = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	draw_string(font, at - Vector2(width * 0.5 if centered else 0.0, 0.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), PAPER)
	if observation.is_empty():
		return
	var rad = _base_radius() * zoom_level
	var tiles: Array = observation.get("map", {}).get("tiles", [])
	for tile in tiles:
		var q = int(tile.get("q", 0))
		var r = int(tile.get("r", 0))
		var center = _center(q, r)
		if not Rect2(Vector2(-rad * 2, -rad * 2), size + Vector2(rad * 4, rad * 4)).has_point(center):
			continue
		var terrain = str(tile.get("terrain", "plains"))
		var colors = {"plains":"e6e5d7", "forest":"b7c6b0", "hills":"d0cbb0", "mountain":"b6b4a3", "desert":"e4d2a7", "marsh":"baccc1", "town":"d2cabc", "city":"c1bbaf", "bocage":"c6cdb3", "water":"a9c8ce"}
		var fill = Color(colors.get(terrain, "e6e5d7"))
		var poly = _hex(center, rad - 0.6)
		draw_colored_polygon(poly, fill)
		var border = _hex(center, rad)
		border.append(border[0])
		draw_polyline(border, Color(0.32, 0.38, 0.32, 0.17), 1.0, true)
		if terrain in ["forest", "bocage"]:
			for i in range(4):
				var at = center + Vector2((i % 2 - 0.5) * rad * 0.65, (i / 2 - 0.5) * rad * 0.56)
				var tree = PackedVector2Array([at + Vector2(0,-rad*0.17),at+Vector2(rad*0.13,rad*0.12),at+Vector2(-rad*0.13,rad*0.12)])
				draw_colored_polygon(tree, Color(0.23,0.38,0.28,0.3))
		elif terrain in ["hills", "mountain"]:
			for i in range(2):
				var at = center + Vector2((i - 0.5)*rad*0.6, rad*0.1)
				draw_polyline(PackedVector2Array([at+Vector2(-rad*0.22,rad*0.15),at+Vector2(0,-rad*0.23),at+Vector2(rad*0.22,rad*0.15)]), Color(0.35,0.36,0.29,0.35), 1.1, true)
		elif terrain in ["town", "city"]:
			for i in range(4 if terrain == "city" else 2):
				draw_rect(Rect2(center+Vector2((i%2-0.5)*rad*0.4,(i/2-0.5)*rad*0.4),Vector2(rad*0.22,rad*0.24)),Color(0.37,0.35,0.30,0.4))
		elif terrain == "marsh":
			for i in range(3):
				var at = center+Vector2(-rad*0.25,(i-1)*rad*0.23)
				draw_line(at,at+Vector2(rad*0.5,0),Color(0.25,0.43,0.40,0.24),1.0,true)
		if tile.get("river", false):
			draw_polyline(PackedVector2Array([center+Vector2(-rad*0.7,-rad*0.25),center+Vector2(0,rad*0.05),center+Vector2(rad*0.75,rad*0.38)]),Color("86afb8"),max(2.0,rad*0.10),true)
		if tile.get("road", false):
			draw_line(center+Vector2(-rad*0.85,0),center+Vector2(rad*0.85,0),Color("b8a78a"),max(1.0,rad*0.065),true)
		if tile.get("rail", false):
			draw_dashed_line(center+Vector2(-rad*0.75,rad*0.19),center+Vector2(rad*0.75,rad*0.19),Color("8c8878"),1.2,4.0,true)
		if tile.get("bridge", false):
			draw_line(center+Vector2(-rad*0.19,0),center+Vector2(rad*0.19,0),INK,3.0,true)
		if overlay == "control":
			var ckey = "%d,%d" % [q, r]
			var live = observation.get("control", {})
			var owner = int(live.get(ckey, tile.get("control", tile.get("owner", -1))))
			if owner >= 0:
				draw_colored_polygon(poly,Color(0.17,0.35,0.48,0.19) if owner == 0 else Color(0.65,0.28,0.22,0.19))
		if str(tile.get("label", "")) != "" and zoom_level >= 0.85:
			_label(center+Vector2(0,-rad*0.55), str(tile.get("label")), Color(0.25,0.32,0.28,0.85), clampi(int(rad*0.28),9,12))
		if hovered == Vector2i(q,r):
			draw_polyline(border,Color("a18a51"),2.0,true)
		if zoom_level > 1.65:
			_label(center+Vector2(0,rad*0.76), "%d·%d" % [q,r],Color(0.3,0.36,0.32,0.45),10)
	# Objectives are deliberately drawn before counters; place names sit below the hex.
	for objective in observation.get("objectives", []):
		var at = _center(int(objective.get("q",0)),int(objective.get("r",0)))
		draw_arc(at,rad*0.78,0,TAU,32,Color("b39a5e"),2.0,true)
		_label(at+Vector2(0,rad+12),str(objective.get("name","目标")),INK,clampi(int(rad*0.35),11,16))
		_label(at+Vector2(rad*0.76,-rad*0.47),str(objective.get("value",1)),Color("8b713c"),11)
	if overlay == "supply":
		for depot in observation.get("depots", []):
			var at = _center(int(depot.get("q",0)),int(depot.get("r",0)))
			draw_arc(at,rad*1.7,0,TAU,40,Color(0.22,0.48,0.41,0.45),2.0,true)
			_label(at+Vector2(0,-rad),"补给枢纽",Color("2b6b57"),12)
	_draw_orders(rad)
	var stacks: Dictionary = {}
	for unit in observation.get("units", []):
		var key = "%s,%s" % [unit.get("q",0),unit.get("r",0)]
		if not stacks.has(key): stacks[key] = []
		stacks[key].append(unit)
	for stack in stacks.values():
		var chosen: Dictionary = stack[0]
		for unit in stack:
			if str(unit.get("id","")) == selected_id: chosen = unit
		_draw_counter(chosen,rad,stack.size())
	for contact in observation.get("contacts", []):
		if not contact is Dictionary: continue
		var at = _center(int(contact.get("q",0)),int(contact.get("r",0)))
		draw_arc(at,rad*0.48,0,TAU,20,Color(0.6,0.30,0.25,0.5),1.0,true)
		_label(at+Vector2(0,5),"?",Color("a56a5c"),18)
	# Atlas marginalia.
	_label(Vector2(24,29),"战区态势图  /  OPERATIONAL THEATRE",Color("778277"),11,false)
	var scale_length = max(28.0, rad * sqrt(3.0))
	draw_line(Vector2(25,size.y-33),Vector2(25+scale_length,size.y-33),INK,2.0)
	draw_line(Vector2(25,size.y-37),Vector2(25,size.y-29),INK,1.0)
	draw_line(Vector2(25+scale_length,size.y-37),Vector2(25+scale_length,size.y-29),INK,1.0)
	_label(Vector2(25,size.y-14),"%s km / 格" % observation.get("hex_km",5),INK,11,false)
	_label(Vector2(size.x-33,35),"N",INK,13)
	draw_line(Vector2(size.x-33,44),Vector2(size.x-33,72),INK,1.0)
	draw_colored_polygon(PackedVector2Array([Vector2(size.x-33,40),Vector2(size.x-37,51),Vector2(size.x-29,51)]),INK)

func _draw_orders(rad: float) -> void:
	var orders = observation.get("orders", {})
	var values: Array = orders.values() if orders is Dictionary else orders
	for order in values:
		if not order is Dictionary: continue
		var target = order.get("target", [])
		if not target is Array or target.size() < 2: continue
		for unit in observation.get("units", []):
			if str(unit.get("id","")) != str(order.get("unit_id","")): continue
			var a = _center(int(unit.get("q",0)),int(unit.get("r",0)))
			var b = _center(int(target[0]),int(target[1]))
			if a.distance_to(b) < 2.0: continue
			var color = Color("a35745") if order.get("kind","") == "attack" else Color("576f6a")
			draw_dashed_line(a,b,color,2.3,7.0,true)
			var direction = (a-b).normalized()
			draw_colored_polygon(PackedVector2Array([b,b+direction.rotated(0.42)*rad*0.42,b+direction.rotated(-0.42)*rad*0.42]),color)
	if preview_path is Array and preview_path.size() >= 2:
		var pts = PackedVector2Array()
		for cell in preview_path:
			pts.append(_center(int(cell[0]), int(cell[1])))
		for i in range(1, pts.size()):
			draw_line(pts[i-1], pts[i], Color("b79953"), 2.8, true)
		var last = pts[pts.size()-1]
		var dir = (pts[pts.size()-1]-pts[pts.size()-2]).normalized()
		draw_colored_polygon(PackedVector2Array([last,last+dir.rotated(0.42)*rad*0.42,last+dir.rotated(-0.42)*rad*0.42]),Color("b79953"))
	# supply paths when overlay supply
	if overlay == "supply":
		for unit in observation.get("units", []):
			var sp = unit.get("supply_path", [])
			if not sp is Array or sp.size() < 2: continue
			if int(unit.get("side", -1)) != int(observation.get("side", 0)): continue
			var pts = PackedVector2Array()
			for cell in sp:
				pts.append(_center(int(cell[0]), int(cell[1])))
			var col = Color(0.18,0.45,0.38,0.55) if float(unit.get("supply",1.0)) >= 0.5 else Color(0.72,0.32,0.22,0.65)
			for i in range(1, pts.size()):
				draw_dashed_line(pts[i-1], pts[i], col, 1.6, 4.0, true)
		for unit in observation.get("units", []):
			if int(unit.get("side",-1)) != int(observation.get("side",0)): continue
			if float(unit.get("supply",1.0)) >= 0.5: continue
			var at = _center(int(unit.get("q",0)),int(unit.get("r",0)))
			draw_arc(at, rad*0.92, 0, TAU, 24, Color(0.75,0.28,0.2,0.8), 2.0, true)

func _draw_counter(unit: Dictionary, rad: float, count: int) -> void:
	var at = _center(int(unit.get("q",0)),int(unit.get("r",0)))
	var width = clampf(rad*1.38,21.0,62.0)
	var height = width*0.73
	var rect = Rect2(at-Vector2(width,height)*0.5,Vector2(width,height))
	var side = int(unit.get("side",0))
	var own = side == int(observation.get("side",0))
	var color = BLUE if side == 0 else RED
	if count > 1:
		draw_rect(Rect2(rect.position+Vector2(4,4),rect.size),Color("f0ecd9"))
		draw_rect(Rect2(rect.position+Vector2(3,3),rect.size),color.darkened(0.2),false,1.5)
	draw_rect(Rect2(rect.position+Vector2(1,2),rect.size),Color(0.14,0.19,0.17,0.24))
	draw_rect(rect,color)
	draw_rect(Rect2(rect.position+Vector2(2,2),rect.size-Vector2(4,4)),Color(0.92,0.92,0.84,0.45),false,0.8)
	if str(unit.get("id","")) == selected_id:
		draw_rect(Rect2(rect.position-Vector2(4,4),rect.size+Vector2(8,8)),Color("b79953"),false,2.5)
	var ink = Color("f3eddd")
	var symbol = Rect2(at-Vector2(width*0.21,height*0.20),Vector2(width*0.42,height*0.34))
	var kind = str(unit.get("type","infantry"))
	if kind in ["armor","mechanized"]:
		draw_arc(at+Vector2(0,-height*0.03),width*0.15,0,TAU,20,ink,1.2,true)
		if kind == "mechanized": draw_line(symbol.position,symbol.end,ink,1.0,true)
	elif kind in ["artillery", "air_defense"]:
		draw_circle(at+Vector2(0,-height*0.02),width*0.055,ink)
		if kind == "air_defense": draw_arc(at,width*0.20,PI,TAU,12,ink,1.0,true)
	elif kind == "hq":
		_label(at+Vector2(0,height*0.11),"HQ",ink,clampi(int(width*0.24),8,15))
	elif kind == "logistics":
		_label(at+Vector2(0,height*0.11),"S",ink,clampi(int(width*0.24),8,15))
	else:
		draw_rect(symbol,ink,false,1.0)
		draw_line(symbol.position,symbol.end,ink,1.0,true)
		if kind != "recon": draw_line(Vector2(symbol.end.x,symbol.position.y),Vector2(symbol.position.x,symbol.end.y),ink,1.0,true)
		if kind == "engineer": draw_line(symbol.position-Vector2(0,2),Vector2(symbol.end.x,symbol.position.y-2),ink,2.0)
	if width > 30:
		var designation = str(unit.get("size",""))
		var markers = {"regiment":"III","brigade":"X","division":"XX","battalion":"II"}
		_label(at+Vector2(0,-height*0.28),markers.get(designation, "X"),ink,8)
		var enemy_label = "识别"
		var band = str(unit.get("strength_band", ""))
		if band == "strong": enemy_label = "强"
		elif band == "medium": enemy_label = "中"
		elif band == "weak": enemy_label = "弱"
		_label(at+Vector2(0,height*0.35),str(int(unit.get("strength",0))) if own else enemy_label,ink,9)
	if own:
		var organization = float(unit.get("organization",100.0))
		if organization <= 1.0: organization *= 100.0
		draw_rect(Rect2(rect.position+Vector2(0,height+2),Vector2(width,height*0.06)),Color(0.2,0.3,0.25,0.2))
		draw_rect(Rect2(rect.position+Vector2(0,height+2),Vector2(width*clampf(organization/100.0,0,1),height*0.06)),Color("8fa378"))
	if count > 1: _label(at+Vector2(width*0.58,-height*0.3),str(count),INK,10)

func _nearest(position: Vector2) -> Vector2i:
	var best = Vector2i(-99,-99)
	var distance = INF
	for tile in observation.get("map",{}).get("tiles",[]):
		var q = int(tile.get("q",0))
		var r = int(tile.get("r",0))
		var d = position.distance_to(_center(q,r))
		if d < distance:
			distance = d
			best = Vector2i(q,r)
	return best if distance < _base_radius()*zoom_level else Vector2i(-99,-99)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN] and event.pressed:
			var old_zoom = zoom_level
			zoom_level = clampf(zoom_level*(1.15 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0/1.15),0.65,3.0)
			pan = (pan + size*0.5-event.position)*(zoom_level/old_zoom) - size*0.5+event.position
			queue_redraw()
		elif event.button_index in [MOUSE_BUTTON_LEFT,MOUSE_BUTTON_MIDDLE,MOUSE_BUTTON_RIGHT]:
			if event.pressed:
				dragging = true
				moved = false
				press_position = event.position
			else:
				dragging = false
				if not moved and event.button_index == MOUSE_BUTTON_LEFT:
					var cell = _nearest(event.position)
					if cell.x == -99: return
					var candidates: Array = []
					for unit in observation.get("units",[]):
						if int(unit.get("q",-1)) == cell.x and int(unit.get("r",-1)) == cell.y:
							candidates.append(str(unit.get("id","")))
					if not candidates.is_empty():
						var index = candidates.find(selected_id)
						unit_selected.emit(candidates[(index+1)%candidates.size()])
					hex_selected.emit(cell.x,cell.y)
	elif event is InputEventMouseMotion:
		if dragging:
			if event.position.distance_to(press_position) > 4: moved = true
			if moved: pan += event.relative
		else:
			hovered = _nearest(event.position)
			if hovered.x != -99:
				hex_hovered.emit(hovered.x, hovered.y)
				var tip = "坐标 %d, %d" % [hovered.x, hovered.y]
				for tile in observation.get("map", {}).get("tiles", []):
					if int(tile.get("q", -1)) == hovered.x and int(tile.get("r", -1)) == hovered.y:
						var terrain = str(tile.get("terrain", "?"))
						var extras = []
						if tile.get("road", false): extras.append("道路")
						if tile.get("rail", false): extras.append("铁路")
						if tile.get("river", false): extras.append("河流")
						if tile.get("bridge", false): extras.append("桥梁")
						if str(tile.get("label", "")) != "": extras.append(str(tile.get("label")))
						tip = "%s · %s%s" % [tip, terrain, (" · " + " · ".join(extras)) if extras else ""]
						tip += "\n左键选择 / 下达目标 · 拖动平移 · 滚轮缩放"
						break
				tooltip_text = tip
			else:
				hex_hovered.emit(-99, -99)
		queue_redraw()


func handle_key(event: InputEventKey) -> bool:
	if not event.pressed:
		return false
	var step = 36.0
	match event.keycode:
		KEY_LEFT, KEY_A:
			pan.x += step
			queue_redraw()
			return true
		KEY_RIGHT, KEY_D:
			pan.x -= step
			queue_redraw()
			return true
		KEY_UP, KEY_W:
			pan.y += step
			queue_redraw()
			return true
		KEY_DOWN, KEY_S:
			pan.y -= step
			queue_redraw()
			return true
		KEY_EQUAL, KEY_KP_ADD:
			zoom_level = minf(3.0, zoom_level * 1.12)
			queue_redraw()
			return true
		KEY_MINUS, KEY_KP_SUBTRACT:
			zoom_level = maxf(0.65, zoom_level / 1.12)
			queue_redraw()
			return true
	return false
