extends Control

const MapCanvas = preload("res://ui/hex_map.gd")
const BG = Color("152c2c")
const PANEL = Color("203838")
const PAPER = Color("ece8d9")
const MUTED = Color("a3b5aa")
const GOLD = Color("c6aa6d")
const ORDERS = {"move":"机动", "attack":"进攻", "defend":"固守", "rest":"休整", "recon":"侦察", "reserve":"预备", "retreat":"撤退", "engineer":"工程"}
const TYPES = {"infantry":"步兵", "armor":"装甲", "mechanized":"机械化", "motorized":"摩托化", "recon":"侦察", "artillery":"炮兵", "engineer":"工兵", "airborne":"空降兵", "hq":"指挥部", "logistics":"后勤", "air_defense":"防空"}
var selected_id: String = ""
var pending_order: String = ""
var stance: String = "balanced"
var selected_scenario: String = ""
var selected_mode: String = "ai"
var selected_side: int = 0
var selected_difficulty: String = "normal"
var ui_scale: float = 1.0
var canvas
var shell: VBoxContainer
var inspector: VBoxContainer
var roster: VBoxContainer
var order_hint: Label
var status: Label
var scenario_detail: Label
var side_choice: OptionButton
var notice_text: String = "指挥官，选择一场战役开始。"
var overlay_mode: String = "terrain"
var saved_pan: Vector2 = Vector2.ZERO
var saved_zoom: float = 1.0
var was_game: bool = false
var smoke_done: bool = false
var last_turn: int = -1
var lan_window: AcceptDialog
var room_list: VBoxContainer
var hovered_hex: Array = []
var preview_path: Array = []
var turn_label: Label
var score_label: Label
var commit_button: Button
var commit_note: Label
var commit_summary: Label

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_setup_theme()
	GameSession.view_changed.connect(_refresh)
	GameSession.notice.connect(_notice)
	GameSession.lobby_changed.connect(_lobby_refresh)
	_refresh()
	call_deferred("_smoke")

func _setup_theme() -> void:
	var t = Theme.new()
	t.default_font_size = int(14 * ui_scale)
	for path in ["res://assets/fonts/NotoSansSC-Regular.ttf", "res://assets/fonts/NotoSansSC.ttf", "res://assets/fonts/NotoSansSC-Regular.otf"]:
		if ResourceLoader.exists(path):
			t.default_font = load(path)
			break
	t.set_color("font_color","Label",PAPER)
	t.set_color("font_color","Button",PAPER)
	t.set_color("font_hover_color","Button",Color("ffffff"))
	t.set_color("font_disabled_color","Button",Color("6c817b"))
	t.set_stylebox("normal","Button",_box(Color("2a4441"),5,Color("47605a")))
	t.set_stylebox("hover","Button",_box(Color("39554c"),5,GOLD))
	t.set_stylebox("pressed","Button",_box(Color("536348"),5,GOLD))
	t.set_stylebox("disabled","Button",_box(Color("203633"),5,Color("2b4540")))
	t.set_stylebox("focus","Button",_box(Color(0,0,0,0),5,GOLD))
	t.set_stylebox("normal","LineEdit",_box(Color("142b29"),5,Color("4a635a")))
	t.set_color("font_color","LineEdit",PAPER)
	t.set_color("font_placeholder_color","LineEdit",MUTED)
	t.set_stylebox("panel","PopupMenu",_box(PANEL,6,Color("4b6158")))
	t.set_color("font_color","PopupMenu",PAPER)
	t.set_stylebox("panel","TooltipPanel",_box(Color("142b29"),4,GOLD))
	t.set_color("font_color","TooltipLabel",PAPER)
	t.set_constant("separation","VBoxContainer",10)
	t.set_constant("separation","HBoxContainer",10)
	t.set_stylebox("background","ProgressBar",_box(Color("132927"),2))
	t.set_stylebox("fill","ProgressBar",_box(Color("8a9f7b"),2))
	t.set_stylebox("panel","AcceptDialog",_box(PANEL,8,Color("4b6158")))
	t.set_color("font_color","RichTextLabel",PAPER)
	t.set_color("font_color","OptionButton",PAPER)
	t.set_stylebox("normal","OptionButton",_box(Color("2a4441"),5,Color("47605a")))
	t.set_stylebox("hover","OptionButton",_box(Color("39554c"),5,GOLD))
	t.set_stylebox("pressed","OptionButton",_box(Color("536348"),5,GOLD))
	theme = t

func _box(color: Color, radius: int = 0, border: Color = Color.TRANSPARENT) -> StyleBoxFlat:
	var b = StyleBoxFlat.new()
	b.bg_color = color
	b.set_corner_radius_all(radius)
	b.set_border_width_all(1 if border.a > 0 else 0)
	b.border_color = border
	b.content_margin_left = 12
	b.content_margin_right = 12
	b.content_margin_top = 8
	b.content_margin_bottom = 8
	return b

func _label(text: String, size_px: int = 14, color: Color = PAPER) -> Label:
	var l = Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size",size_px)
	l.add_theme_color_override("font_color",color)
	return l

func _button(text: String, action: Callable, tip: String = "") -> Button:
	var b = Button.new()
	b.text = text
	b.custom_minimum_size.y = 34
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.tooltip_text = tip
	b.pressed.connect(func():
		if Engine.has_singleton("GameAudio") or true:
			if has_node("/root/GameAudio"):
				get_node("/root/GameAudio").play("click")
		action.call())
	return b

func _panel(parent: Node, color: Color = PANEL, padding: int = 20) -> VBoxContainer:
	var p = PanelContainer.new()
	var style = _box(color,7)
	style.content_margin_left = padding
	style.content_margin_right = padding
	style.content_margin_top = padding
	style.content_margin_bottom = padding
	p.add_theme_stylebox_override("panel",style)
	parent.add_child(p)
	var content = VBoxContainer.new()
	p.add_child(content)
	return content

func _spacer(parent: Node) -> Control:
	var c = Control.new()
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(c)
	return c

func _clear_children(node: Node) -> void:
	if not is_instance_valid(node):
		return
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()

func _update_live_header() -> void:
	var view: Dictionary = GameSession.view
	if is_instance_valid(turn_label):
		turn_label.text = "回合  %02d / %02d" % [view.get("turn",1),view.get("max_turns",12)]
	var weather_names = {"clear":"晴朗","rain":"降雨","snow":"降雪","fog":"浓雾","overcast":"阴天","storm":"风暴","night":"夜暗"}
	var weather = str(view.get("weather","clear"))
	if is_instance_valid(score_label):
		score_label.text = "%s  ·  积分 %s : %s" % [weather_names.get(weather,weather),view.get("scores",[0,0])[0],view.get("scores",[0,0])[1]]
	var is_finished = str(view.get("phase","")) in ["finished","complete","ended"]
	if is_instance_valid(commit_button):
		if is_finished:
			commit_button.text = "战役结束 · 查看战报"
		elif GameSession.mode == "observer":
			commit_button.text = "继续推演" if GameSession.observer_paused() else "暂停推演"
		else:
			commit_button.text = "锁定命令 · 结束回合   →"
		commit_button.disabled = bool(view.get("replay_active",false))
	var ready: Array = view.get("ready",[false,false])
	var own_units = []
	for unit in view.get("units", []):
		if int(unit.get("side",-1)) == int(view.get("side",0)) and float(unit.get("strength",0)) > 0:
			own_units.append(unit)
	var ordered = view.get("orders", {})
	var n_ordered = 0
	var missing = []
	for unit in own_units:
		var uid = str(unit.get("id",""))
		if ordered is Dictionary and ordered.has(uid):
			n_ordered += 1
		else:
			missing.append(str(unit.get("name", uid)))
	if is_instance_valid(commit_note):
		if GameSession.mode == "observer":
			commit_note.text = "双方 AI 持续推演 · 可随时暂停"
		else:
			commit_note.text = "双方命令同时结算 · 六个战术时段" if not (true in ready) else "命令已锁定 · 等待另一方"
	if is_instance_valid(commit_summary):
		var summary = "已下令 %d / %d" % [n_ordered, own_units.size()]
		if not missing.is_empty() and not (true in ready):
			summary += " · 未下令：" + ("、".join(missing.slice(0, 4))) + ("…" if missing.size() > 4 else "")
		commit_summary.text = summary

func _refresh() -> void:
	var in_game = not GameSession.view.is_empty()
	# Incremental path: keep map camera and shell when staying in a match.
	if in_game and was_game and is_instance_valid(canvas) and is_instance_valid(inspector) and is_instance_valid(roster):
		if GameSession.pending_handoff:
			_handoff()
			return
		canvas.update_view(GameSession.view, selected_id)
		_clear_children(inspector)
		_inspect_unit()
		_clear_children(roster)
		_build_roster()
		_update_live_header()
		if is_instance_valid(status):
			status.text = notice_text
		var turn_now = int(GameSession.view.get("turn", -1))
		if last_turn >= 0 and turn_now > last_turn and has_node("/root/GameAudio"):
			get_node("/root/GameAudio").play("turn")
		last_turn = turn_now
		return
	if is_instance_valid(canvas):
		saved_pan = canvas.pan
		saved_zoom = canvas.zoom_level
	for child in get_children():
		remove_child(child)
		child.queue_free()
	canvas = null
	var background = ColorRect.new()
	background.color = BG
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	var margin = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge in ["left","right","top","bottom"]: margin.add_theme_constant_override("margin_"+edge,18)
	add_child(margin)
	shell = VBoxContainer.new()
	shell.add_theme_constant_override("separation",12)
	margin.add_child(shell)
	if GameSession.view.is_empty():
		was_game = false
		_build_menu()
	else:
		if not was_game:
			saved_pan = Vector2.ZERO
			saved_zoom = 1.0
		was_game = true
		_build_game()
		var turn_now = int(GameSession.view.get("turn", -1))
		if last_turn >= 0 and turn_now > last_turn and has_node("/root/GameAudio"):
			get_node("/root/GameAudio").play("turn")
		last_turn = turn_now
	status = _label(notice_text,12,MUTED)
	status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	shell.add_child(status)
	if GameSession.pending_handoff: _handoff()

func _build_menu() -> void:
	var header = HBoxContainer.new()
	shell.add_child(header)
	var identity = VBoxContainer.new()
	identity.add_theme_constant_override("separation",2)
	header.add_child(identity)
	identity.add_child(_label("战线",38,PAPER))
	identity.add_child(_label("E W A R G A M E   /   战 役 指 挥",11,GOLD))
	_spacer(header)
	header.add_child(_button("载入存档",func(): GameSession.load_game()))
	header.add_child(_button("指挥手册",_rules))
	var intro = HBoxContainer.new()
	shell.add_child(intro)
	intro.add_child(_label("每一道命令，都将在同一时刻展开。",22))
	_spacer(intro)
	intro.add_child(_label("六角格兵棋  ·  同步回合  ·  不完全情报",12,MUTED))
	var body = HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	shell.add_child(body)
	var scroll = ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(scroll)
	var cards = VBoxContainer.new()
	cards.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(cards)
	cards.add_child(_label("选择战役   /   CAMPAIGN ARCHIVE",12,GOLD))
	var grid = GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation",12)
	grid.add_theme_constant_override("v_separation",12)
	cards.add_child(grid)
	var scenarios: Array = GameSession.scenarios
	if selected_scenario.is_empty() and not scenarios.is_empty(): selected_scenario = str(scenarios[0].get("id",""))
	for i in range(scenarios.size()):
		var scenario: Dictionary = scenarios[i]
		var card = PanelContainer.new()
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var active = str(scenario.get("id","")) == selected_scenario
		card.add_theme_stylebox_override("panel",_box(Color("2e4640") if active else Color("203735"),6,GOLD if active else Color("354c43")))
		grid.add_child(card)
		var inside = VBoxContainer.new()
		inside.add_theme_constant_override("separation",7)
		card.add_child(inside)
		var era = {"ww2":"第二次世界大战", "coldwar":"冷战时期", "modern":"现代战争"}.get(str(scenario.get("era","")),"指挥训练")
		inside.add_child(_label("%02d  /  %s" % [i+1,era],11,GOLD))
		inside.add_child(_label(str(scenario.get("title","战役")),21))
		var subtitle = _label(str(scenario.get("subtitle",scenario.get("date",""))),12,MUTED)
		subtitle.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		inside.add_child(subtitle)
		var facts = "%s km / 格   ·   %s 小时 / 回合   ·   %s 回合" % [scenario.get("hex_km","—"),scenario.get("turn_hours","—"),scenario.get("max_turns","—")]
		inside.add_child(_label(facts,11,MUTED))
		var meta = "%s 单位" % scenario.get("unit_count", scenario.get("units", []).size())
		var diff = str(scenario.get("difficulty", ""))
		if diff != "":
			meta += " · " + {"easy":"入门","standard":"标准","hard":"硬仗"}.get(diff, diff)
		inside.add_child(_label(meta,11,MUTED))
		var id = str(scenario.get("id",""))
		inside.add_child(_button("已选战役   →" if active else "查看部署   →",func(): selected_scenario = id; _refresh()))
	var config = _panel(body,PANEL,22)
	config.get_parent().custom_minimum_size.x = 310
	config.add_child(_label("行动准备",24))
	config.add_child(_label("OPERATION BRIEFING",10,GOLD))
	var chosen: Dictionary = {}
	for scenario in scenarios:
		if str(scenario.get("id","")) == selected_scenario: chosen = scenario
	scenario_detail = _label(str(chosen.get("description","选择战役，查看作战任务与部署。")),13,MUTED)
	scenario_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	scenario_detail.custom_minimum_size = Vector2(260,90)
	config.add_child(scenario_detail)
	config.add_child(_label("指挥方式",12,GOLD))
	var modes = OptionButton.new()
	var mode_ids = ["ai","hotseat","observer","agent"]
	for item in ["人机对战  /  离线 AI","同机轮换  /  双方隐蔽下令","观战推演  /  AI 对 AI","Agent 对战  /  MCP 接入"]: modes.add_item(item)
	modes.select(maxi(0,mode_ids.find(selected_mode)))
	modes.item_selected.connect(func(index): selected_mode = mode_ids[index])
	config.add_child(modes)
	config.add_child(_label("指挥阵营",12,GOLD))
	side_choice = OptionButton.new()
	var sides: Array = chosen.get("sides",[{"name":"蓝方"},{"name":"红方"}])
	for side in sides: side_choice.add_item(str(side.get("name","阵营")))
	side_choice.select(selected_side)
	side_choice.item_selected.connect(func(index): selected_side = index)
	config.add_child(side_choice)
	config.add_child(_label("AI 难度",12,GOLD))
	var diffs = OptionButton.new()
	var diff_ids = ["easy","normal","hard"]
	for item in ["简单 · 保守","标准","强硬 · 积极"]: diffs.add_item(item)
	diffs.select(maxi(0,diff_ids.find(selected_difficulty)))
	diffs.item_selected.connect(func(index): selected_difficulty = diff_ids[index])
	config.add_child(diffs)
	config.add_child(_label("界面缩放",12,GOLD))
	var scale_row = HBoxContainer.new()
	config.add_child(scale_row)
	scale_row.add_child(_button("−",func(): ui_scale = clampf(ui_scale - 0.1, 0.85, 1.4); _setup_theme(); _refresh(),"缩小界面文字"))
	scale_row.add_child(_label(str(snappedf(ui_scale, 0.05)),12,MUTED))
	scale_row.add_child(_button("+",func(): ui_scale = clampf(ui_scale + 0.1, 0.85, 1.4); _setup_theme(); _refresh(),"放大界面文字"))
	var begin = _button("开始战役    →",func(): selected_id = ""; pending_order = ""; GameSession.ai_difficulty = selected_difficulty; GameSession.start_game(selected_scenario,selected_mode,selected_side))
	begin.custom_minimum_size.y = 48
	begin.add_theme_stylebox_override("normal",_box(Color("a08954"),5,Color("d7bc7e")))
	begin.add_theme_color_override("font_color",Color("122c2b"))
	config.add_child(begin)
	var brief = str(chosen.get("brief_goals", ""))
	if brief != "":
		var brief_label = _label("简报：" + brief,11,MUTED)
		brief_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		config.add_child(brief_label)
	config.add_child(_button("局域网联机",_lan_dialog))
	config.add_child(_button("史料与设计说明",func(): _sources(chosen)))
	var note = _label("WEGO：双方锁定命令后统一结算。\n敌军强度与命令受战争迷雾限制。",11,MUTED)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	config.add_child(note)

func _build_game() -> void:
	var view: Dictionary = GameSession.view
	var top = HBoxContainer.new()
	shell.add_child(top)
	var title = VBoxContainer.new()
	title.add_theme_constant_override("separation",2)
	top.add_child(title)
	title.add_child(_label("战线  /  " + str(view.get("title","战役指挥")),24))
	var side_name = "观察员"
	var sides: Array = view.get("sides",[])
	var side_index = int(view.get("side",0))
	if side_index >= 0 and side_index < sides.size(): side_name = str(sides[side_index].get("name","本方"))
	var mode_names = {"ai":"人机对战","hotseat":"同机轮换","lan":"局域网","observer":"观战","agent":"Agent 对战"}
	title.add_child(_label("%s  ·  %s  ·  每回合 %s 小时" % [side_name,mode_names.get(GameSession.mode,"推演"),view.get("turn_hours",6)],12,MUTED))
	_spacer(top)
	var turn_box = VBoxContainer.new()
	turn_box.add_theme_constant_override("separation",2)
	top.add_child(turn_box)
	turn_label = _label("回合  %02d / %02d" % [view.get("turn",1),view.get("max_turns",12)],21,GOLD)
	turn_box.add_child(turn_label)
	var weather_names = {"clear":"晴朗","rain":"降雨","snow":"降雪","fog":"浓雾","overcast":"阴天","storm":"风暴","night":"夜暗"}
	var weather = str(view.get("weather","clear"))
	score_label = _label("%s  ·  积分 %s : %s" % [weather_names.get(weather,weather),view.get("scores",[0,0])[0],view.get("scores",[0,0])[1]],12,MUTED)
	turn_box.add_child(score_label)
	top.add_child(_button("战报",_reports))
	top.add_child(_button("菜单",_game_menu))
	var middle = HBoxContainer.new()
	middle.size_flags_vertical = Control.SIZE_EXPAND_FILL
	middle.add_theme_constant_override("separation",12)
	shell.add_child(middle)
	var map_column = VBoxContainer.new()
	map_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map_column.add_theme_constant_override("separation",0)
	middle.add_child(map_column)
	var map_header = PanelContainer.new()
	map_header.add_theme_stylebox_override("panel",_box(Color("d7d6c6"),4))
	map_column.add_child(map_header)
	var filters = HBoxContainer.new()
	map_header.add_child(filters)
	filters.add_child(_label("态势",12,Color("47594d")))
	for entry in [["terrain","地形"],["control","控制"],["zoc","控制区"],["supply","补给"]]:
		var key = entry[0]
		var button = _button(entry[1],func(): overlay_mode = key; canvas.overlay = key; canvas.queue_redraw(); _refresh(), "切换地图图层：" + entry[1])
		button.custom_minimum_size.y = 28
		if overlay_mode == key:
			button.add_theme_stylebox_override("normal",_box(Color("a08954"),5,Color("d7bc7e")))
			button.add_theme_color_override("font_color",Color("122c2b"))
		filters.add_child(button)
	_spacer(filters)
	filters.add_child(_button("−",func(): canvas.zoom_level = maxf(0.65,canvas.zoom_level/1.15); canvas.queue_redraw(),"缩小地图"))
	filters.add_child(_button("适配",func(): canvas.fit_map(),"恢复地图居中与缩放"))
	filters.add_child(_button("+",func(): canvas.zoom_level = minf(3.0,canvas.zoom_level*1.15); canvas.queue_redraw(),"放大地图"))
	canvas = MapCanvas.new()
	canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	canvas.custom_minimum_size = Vector2(300,250)
	canvas.pan = saved_pan
	canvas.zoom_level = saved_zoom
	canvas.overlay = overlay_mode
	map_column.add_child(canvas)
	canvas.update_view(view,selected_id)
	canvas.unit_selected.connect(_select_unit)
	canvas.hex_selected.connect(_target_hex)
	canvas.hex_hovered.connect(_on_hex_hovered)
	var legend_bar = HBoxContainer.new()
	map_column.add_child(legend_bar)
	legend_bar.add_child(_label("蓝/红阵营 · 金环目标 · 虚线命令 · 红晕控制区 · ?接触 · 同格上限 3",11,MUTED))
	_spacer(legend_bar)
	legend_bar.add_child(_label("拖动平移 · 滚轮缩放",11,MUTED))
	var side_scroll = ScrollContainer.new()
	side_scroll.custom_minimum_size.x = 295
	middle.add_child(side_scroll)
	var sidebar = VBoxContainer.new()
	sidebar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	side_scroll.add_child(sidebar)
	inspector = _panel(sidebar,PANEL,16)
	_inspect_unit()
	roster = _panel(sidebar,PANEL,16)
	_build_roster()
	var commands = _panel(shell,Color("203936"),12)
	var command_row = HBoxContainer.new()
	commands.add_child(command_row)
	var command_left = VBoxContainer.new()
	command_left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	command_left.add_theme_constant_override("separation",8)
	command_row.add_child(command_left)
	var order_buttons = HBoxContainer.new()
	order_buttons.add_theme_constant_override("separation",5)
	command_left.add_child(order_buttons)
	for kind in ORDERS:
		var key = kind
		var b = _button(ORDERS[kind],func(): _choose_order(key),_order_tooltip(key))
		b.custom_minimum_size.x = 49
		b.disabled = selected_id.is_empty() or GameSession.mode == "observer" or bool(view.get("replay_active",false))
		order_buttons.add_child(b)
	order_buttons.add_child(_button("清空命令",func(): GameSession.clear_orders(); _refresh(),"清除本回合已下达但未锁定的全部命令（Shift+Backspace）"))
	var detail = HBoxContainer.new()
	command_left.add_child(detail)
	order_hint = _label(_command_hint(),12,GOLD)
	order_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	order_hint.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	detail.add_child(order_hint)
	var stances = OptionButton.new()
	for option in ["谨慎姿态","均衡姿态","积极姿态"]: stances.add_item(option)
	stances.select(["cautious","balanced","aggressive"].find(stance))
	stances.item_selected.connect(func(index): stance = ["cautious","balanced","aggressive"][index])
	detail.add_child(stances)
	var commit_box = VBoxContainer.new()
	commit_box.custom_minimum_size.x = 190
	commit_box.add_theme_constant_override("separation",4)
	command_row.add_child(commit_box)
	var is_finished = str(view.get("phase","")) in ["finished","complete","ended"]
	var commit_label = "战役结束 · 查看战报"
	if not is_finished:
		if GameSession.mode == "observer":
			commit_label = "继续推演" if GameSession.observer_paused() else "暂停推演"
		else:
			commit_label = "锁定命令 · 结束回合   →"
	commit_button = _button(commit_label,_reports if is_finished else _commit)
	commit_button.custom_minimum_size.y = 42
	commit_button.add_theme_stylebox_override("normal",_box(Color("a08954"),5,Color("d7bc7e")))
	commit_button.add_theme_color_override("font_color",Color("122c2b"))
	commit_button.disabled = bool(view.get("replay_active",false))
	commit_box.add_child(commit_button)
	var ready: Array = view.get("ready",[false,false])
	var own_units = []
	for unit in view.get("units", []):
		if int(unit.get("side",-1)) == int(view.get("side",0)) and float(unit.get("strength",0)) > 0:
			own_units.append(unit)
	var ordered = view.get("orders", {})
	var n_ordered = 0
	var missing = []
	for unit in own_units:
		var uid = str(unit.get("id",""))
		if ordered is Dictionary and ordered.has(uid):
			n_ordered += 1
		else:
			missing.append(str(unit.get("name", uid)))
	if GameSession.mode == "observer":
		commit_note = _label("双方 AI 持续推演 · 可随时暂停",10,MUTED)
		commit_box.add_child(commit_note)
	else:
		var base = "双方命令同时结算 · 六个战术时段" if not (true in ready) else "命令已锁定 · 等待另一方"
		commit_note = _label(base,10,MUTED)
		commit_box.add_child(commit_note)
		var summary = "已下令 %d / %d" % [n_ordered, own_units.size()]
		if not missing.is_empty() and not (true in ready):
			summary += " · 未下令：" + ("、".join(missing.slice(0, 4))) + ("…" if missing.size() > 4 else "")
		commit_summary = _label(summary,10,MUTED)
		commit_box.add_child(commit_summary)
	var upcoming: Array = view.get("upcoming_reinforcements", [])
	if upcoming is Array and not upcoming.is_empty():
		var rf = upcoming[0]
		commit_box.add_child(_label("增援预告：回合 %s %s" % [rf.get("turn"), rf.get("name")],10,MUTED))
	if bool(view.get("replay_active",false)):
		notice_text = "回放 %s / %s：只读快照。点击「回放 →」返回最新态势。" % [view.get("replay_index",0),view.get("replay_count",0)]

func _find_selected() -> Dictionary:
	for unit in GameSession.view.get("units",[]):
		if str(unit.get("id","")) == selected_id: return unit
	return {}

func _inspect_unit() -> void:
	for child in inspector.get_children():
		inspector.remove_child(child)
		child.queue_free()
	inspector.add_child(_label("单位档案  /  INSPECTOR",10,GOLD))
	var unit = _find_selected()
	if unit.is_empty():
		inspector.add_child(_label("等待指令",23))
		var text = _label("在地图或战斗序列中选择单位。\n选择行动后，点击六角格下达目标。\n同格多单位可重复点击切换。",13,MUTED)
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		inspector.add_child(text)
		_add_objectives(inspector)
		return
	var name_label = _label(str(unit.get("name",selected_id)),21)
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	inspector.add_child(name_label)
	var own = int(unit.get("side",-1)) == int(GameSession.view.get("side",0))
	inspector.add_child(_label("%s  ·  坐标 %s, %s" % [TYPES.get(str(unit.get("type","")),"未识别单位"),unit.get("q","?"),unit.get("r","?")],12,MUTED))
	if not own:
		inspector.add_child(_label("敌军情报 · 仅展示已侦察信息",12,GOLD))
		var band = str(unit.get("strength_band", ""))
		var band_cn = {"strong":"较强", "medium":"中等", "weak":"较弱"}.get(band, "不明")
		inspector.add_child(_label("兵力判断  %s" % band_cn,14))
		inspector.add_child(_label("%s · %s" % [TYPES.get(str(unit.get("type","")),"未识别"), str(unit.get("size",""))],12,MUTED))
		if unit.has("last_seen"):
			inspector.add_child(_label("最后目击  第 %s 回合" % str(unit.get("last_seen")),11,MUTED))
		var etext = _label("敌军后勤与精确兵力不公开。\n问号接触可能已经过时。",12,MUTED)
		etext.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		inspector.add_child(etext)
		return
	inspector.add_child(_label("兵力  %s" % unit.get("strength","—"),17))
	for entry in [["organization","组织"],["fatigue","疲劳"],["fuel","燃料"],["ammo","弹药"]]:
		var row = HBoxContainer.new()
		inspector.add_child(row)
		row.add_child(_label(entry[1],12,MUTED))
		var bar = ProgressBar.new()
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.custom_minimum_size.y = 8
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bar.show_percentage = false
		bar.value = float(unit.get(entry[0],0))
		row.add_child(bar)
		row.add_child(_label(str(int(unit.get(entry[0],0))),12))
	var orders = GameSession.view.get("orders",{})
	var current: Dictionary = orders.get(selected_id,{}) if orders is Dictionary else {}
	inspector.add_child(_label("当前命令  " + str(ORDERS.get(str(current.get("kind","defend")),"固守")),12,GOLD))
	if not current.is_empty() and not GameSession.view.get("ready",[false,false])[int(GameSession.view.get("side",0))]:
		inspector.add_child(_button("撤销本单位命令",func(): GameSession.clear_unit_order(selected_id); _refresh(),"仅清除选中单位本回合命令（Backspace）"))
	if unit.has("supply"):
		var supply = float(unit.get("supply", 1.0))
		var supply_cn = "充足" if supply >= 0.7 else ("紧张" if supply >= 0.4 else "断绝")
		inspector.add_child(_label("补给状态  %s（%.0f%%）" % [supply_cn, supply * 100.0],12,MUTED))
	var status_en = str(unit.get("status","ready"))
	var status_cn = {"ready":"待命","moving":"机动中","engaged":"交战中","undersupplied":"补给不足","destroyed":"已损失"}.get(status_en, status_en)
	var org = float(unit.get("organization", 100.0))
	if org <= 1.0: org *= 100.0
	var morale = "士气稳定"
	if org < 25: morale = "接近溃退"
	elif org < 45: morale = "动摇"
	inspector.add_child(_label("状态  %s · %s · 筑城 %.1f · 延迟 %s" % [status_cn, morale, float(unit.get("entrenchment",0.0)), str(unit.get("command_delay",0))],11,MUTED))
	if str(current.get("kind","")) == "attack" and current.get("target",[]) is Array and not current.get("target",[]).is_empty() and GameSession.has_method("estimate_combat"):
		var tid = ""
		var tx = int(current["target"][0])
		var ty = int(current["target"][1])
		for other in GameSession.view.get("units", []):
			if int(other.get("q",-1))==tx and int(other.get("r",-1))==ty and int(other.get("side",-1))!=int(GameSession.view.get("side",0)):
				tid = str(other.get("id",""))
				break
		if not tid.is_empty():
			var est = GameSession.estimate_combat(selected_id, tid)
			if est is Dictionary and est.get("ok", false):
				inspector.add_child(_label("交战预估  %s  约 %.1f:1" % [str(est.get("label","均势")), float(est.get("ratio",1.0))],12,GOLD))
				inspector.add_child(_label("预计本方约 −%.1f · 敌方约 −%.1f" % [float(est.get("my_loss",0)), float(est.get("their_loss",0))],11,MUTED))
				var reasons = est.get("reasons", [])
				if reasons is Array and not reasons.is_empty():
					inspector.add_child(_label("要点：" + "、".join(reasons),11,MUTED))
	if pending_order in ["move","attack","recon","retreat"] and not hovered_hex.is_empty() and GameSession.has_method("preview_move"):
		var pv = GameSession.preview_move(selected_id, hovered_hex)
		if pv is Dictionary and pv.get("ok", false):
			var extra = ""
			if not pv.get("zoc_stop_hex", []).is_empty():
				extra += " · 进入控制区将停止机动"
			if pv.get("blocked_by_stack", false):
				extra += " · 目标格己方已满"
			var turns = pv.get("effective_turns", pv.get("turns", 1))
			inspector.add_child(_label("路径预估  %s 格 · 约 %s 回合%s%s" % [int(pv.get("path",[]).size())-1, turns, "" if pv.get("fuel_ok", true) else " · 燃料可能不足", extra],11,GOLD))
	var stack = []
	for other in GameSession.view.get("units", []):
		if int(other.get("q",-1))==int(unit.get("q",-1)) and int(other.get("r",-1))==int(unit.get("r",-1)) and float(other.get("strength",0))>0:
			stack.append(other)
	if stack.size() > 1:
		inspector.add_child(HSeparator.new())
		inspector.add_child(_label("同格部队 %d" % stack.size(),11,GOLD))
		for other in stack:
			var oid = str(other.get("id",""))
			inspector.add_child(_button("%s %s" % ["›" if oid==selected_id else "·", str(other.get("name",oid))],func(): _select_unit(oid)))
	var support = HBoxContainer.new()
	inspector.add_child(support)
	for entry in [["artillery","炮火"],["air","空援"],["recon","侦察"]]:
		var key = entry[0]
		support.add_child(_button(entry[1],func(): pending_order = "support:"+key; _update_hint(),"分配战役支援：点击地图目标格。时代与可用资源限制由规则校验。"))

func _add_objectives(parent: Node) -> void:
	parent.add_child(HSeparator.new())
	parent.add_child(_label("战略目标",13,GOLD))
	var side = int(GameSession.view.get("side", 0))
	for objective in GameSession.view.get("objectives",[]):
		var owner = int(objective.get("owner", -1))
		var mark = "○"
		if owner == side:
			mark = "●"
		elif owner in [0, 1]:
			mark = "◎"
		parent.add_child(_label("%s  %s     %s 分" % [mark, objective.get("name","目标"), objective.get("value",1)],12,MUTED))

func view_orders() -> Dictionary:
	var orders = GameSession.view.get("orders", {})
	return orders if orders is Dictionary else {}

func _build_roster() -> void:
	var units: Array = []
	for unit in GameSession.view.get("units",[]):
		if int(unit.get("side",-1)) == int(GameSession.view.get("side",0)): units.append(unit)
	roster.add_child(_label("战斗序列   /   %02d 支单位" % units.size(),11,GOLD))
	var orders_map = view_orders()
	for unit in units:
		var id = str(unit.get("id",""))
		var kind = str(orders_map.get(id, {}).get("kind", ""))
		var kind_short = {"move":"机动","attack":"进攻","defend":"固守","rest":"休整","recon":"侦察","reserve":"预备","retreat":"撤退","engineer":"工程"}.get(kind, "")
		var mark = "›" if id == selected_id else "·"
		var supply = float(unit.get("supply", 1.0))
		var warn = "△" if supply < 0.45 else ""
		var label = "%s %s%s%s" % [mark, unit.get("name", id), (" · " + kind_short) if kind_short != "" else "", warn]
		var b = _button(label,func(): _select_unit(id))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		b.custom_minimum_size.y = 31
		b.tooltip_text = "%s · %s · 兵力 %s · 补给 %s%s" % [unit.get("name",id),TYPES.get(str(unit.get("type","")),""),unit.get("strength","—"),supply,(" · " + kind_short) if kind_short != "" else ""]
		roster.add_child(b)
	var replay = HBoxContainer.new()
	roster.add_child(replay)
	replay.add_child(_button("← 回放",func(): GameSession.replay_step(-1)))
	replay.add_child(_button("回放 →",func(): GameSession.replay_step(1)))
	var count = int(GameSession.view.get("replay_count", 1))
	var index = int(GameSession.view.get("replay_index", maxi(count - 1, 0)))
	var slider = HSlider.new()
	slider.min_value = 0
	slider.max_value = maxi(count - 1, 0)
	slider.value = index
	slider.step = 1
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.value_changed.connect(func(v): GameSession.replay_goto(int(v)))
	roster.add_child(slider)
	roster.add_child(_label("%s/%s" % [index + 1, count],11,MUTED))
	roster.add_child(_button("导出战报",func(): GameSession.export_after_action()))

func _select_unit(id: String) -> void:
	if not pending_order.is_empty(): return
	selected_id = id
	preview_path = []
	if is_instance_valid(canvas):
		canvas.preview_path = []
		for unit in GameSession.view.get("units", []):
			if str(unit.get("id","")) == id:
				var rad = canvas._base_radius() * canvas.zoom_level
				var at = canvas._center(int(unit.get("q",0)), int(unit.get("r",0)))
				canvas.pan = canvas.size * 0.5 - at
				saved_pan = canvas.pan
				break
	_refresh()

func _choose_order(kind: String) -> void:
	var unit = _find_selected()
	if unit.is_empty() or int(unit.get("side",-1)) != int(GameSession.view.get("side",0)):
		_notice("请先选择本方单位。")
		return
	if kind in ["defend","rest","reserve"]:
		var result = GameSession.place_order(selected_id,kind,[int(unit.get("q",0)),int(unit.get("r",0))],stance)
		if not result.get("ok",false): _notice(str(result.get("error","命令无法下达")))
		else: _notice("已下达「%s」；锁定回合前可继续修改。" % ORDERS[kind])
		pending_order = ""
	else:
		pending_order = kind
		_update_hint()


func _on_hex_hovered(q: int, r: int) -> void:
	hovered_hex = [] if q < -50 else [q, r]
	if pending_order in ["move","attack","recon","retreat"] and not selected_id.is_empty() and GameSession.has_method("preview_move") and not hovered_hex.is_empty():
		var pv = GameSession.preview_move(selected_id, hovered_hex)
		preview_path = pv.get("path", []) if pv is Dictionary and pv.get("ok", false) else []
		if is_instance_valid(canvas):
			canvas.preview_path = preview_path
			canvas.queue_redraw()
		if pending_order == "attack" and GameSession.has_method("estimate_combat"):
			for other in GameSession.view.get("units", []):
				if int(other.get("q",-1))==q and int(other.get("r",-1))==r and int(other.get("side",-1))!=int(GameSession.view.get("side",0)):
					var est = GameSession.estimate_combat(selected_id, str(other.get("id","")))
					if est is Dictionary and est.get("ok", false) and is_instance_valid(order_hint):
						order_hint.text = "进攻预估 %s（约 %.1f:1）· 点击目标格确认" % [est.get("label"), float(est.get("ratio",1.0))]
					break
	elif is_instance_valid(canvas) and not preview_path.is_empty():
		preview_path = []
		canvas.preview_path = []
		canvas.queue_redraw()

func _target_hex(q: int, r: int) -> void:
	if pending_order.is_empty(): return
	var result: Dictionary
	if pending_order.begins_with("support:"):
		result = GameSession.set_support(pending_order.trim_prefix("support:"),[q,r])
	else:
		result = GameSession.place_order(selected_id,pending_order,[q,r],stance)
	if result.get("ok",false):
		pending_order = ""
		preview_path = []
		if is_instance_valid(canvas):
			canvas.preview_path = []
		_notice("命令已记录，目标 %d, %d。锁定前可重新下令。" % [q,r])
		_refresh()
	else:
		_notice(str(result.get("error","无法执行该命令。")))

func _command_hint() -> String:
	if pending_order.begins_with("support:"): return "选择支援目标格  ·  Esc 取消"
	if not pending_order.is_empty(): return "「%s」选择目标格  ·  Esc 取消" % ORDERS.get(pending_order,pending_order)
	return "选择行动，然后点击地图目标格。" if not selected_id.is_empty() else "请选择本方单位以编排行动。"

func _update_hint() -> void:
	if is_instance_valid(order_hint): order_hint.text = _command_hint()

func _order_tooltip(kind: String) -> String:
	return {"move":"向指定格机动；地形、道路、燃料与疲劳影响速度。","attack":"进攻指定目标；双方命令会同时展开。","defend":"原地固守、构筑阵地，保持防御。","rest":"停止机动恢复组织与疲劳；靠近补给更有效。","recon":"向目标侦察，改善敌情识别。","reserve":"保持预备状态，应对战线变化。","retreat":"向目标格撤离，脱离接触。","engineer":"工兵向指定格执行工程作业。"}.get(kind,"")

func _commit() -> void:
	pending_order = ""
	if has_node("/root/GameAudio"):
		get_node("/root/GameAudio").play("confirm")
	GameSession.commit_turn()

func _notice(message: String) -> void:
	notice_text = message
	if is_instance_valid(status): status.text = message
	if has_node("/root/GameAudio"):
		var bad = message.contains("无效") or message.contains("失败") or message.contains("不能") or message.contains("无法") or message.contains("已锁定") or message.contains("中断")
		get_node("/root/GameAudio").play("alert" if bad else "click")

func _dialog(title_text: String, body_text: String, min_size: Vector2i = Vector2i(700,500)) -> AcceptDialog:
	var dialog = AcceptDialog.new()
	dialog.title = title_text
	dialog.ok_button_text = "返回"
	add_child(dialog)
	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(min_size.x-50,min_size.y-90)
	dialog.add_child(scroll)
	var text = RichTextLabel.new()
	text.bbcode_enabled = true
	text.text = body_text
	text.fit_content = true
	text.selection_enabled = true
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_font_size_override("normal_font_size",15)
	text.meta_clicked.connect(func(meta): OS.shell_open(str(meta)))
	scroll.add_child(text)
	dialog.popup_centered(min_size)
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)
	return dialog

func _reports() -> void:
	var text = "[color=#c6aa6d]战役态势与行动记录[/color]\n\n"
	var view: Dictionary = GameSession.view
	text += "当前回合：%s   积分：%s · %s\n" % [view.get("turn",1), view.get("scores",[0,0])[0], view.get("scores",[0,0])[1]]
	text += "模式 %s · 难度 %s · 剧本 %s\n" % [GameSession.mode, GameSession.ai_difficulty, view.get("scenario_id", view.get("title",""))]
	var sides = view.get("sides", [])
	if sides is Array and sides.size() >= 2:
		text += "%s vs %s\n\n" % [sides[0].get("name","蓝"), sides[1].get("name","红")]
	else:
		text += "\n"
	text += "[color=#c6aa6d]战略目标[/color]\n"
	var side_names = ["蓝方", "红方"]
	if sides is Array and sides.size() >= 2:
		side_names = [str(sides[0].get("name","蓝")), str(sides[1].get("name","红"))]
	for objective in view.get("objectives",[]):
		var owner = int(objective.get("owner", -1))
		var owner_txt = "中立" if owner < 0 else side_names[owner]
		text += "· %s  %s 分  ·  控制：%s\n" % [objective.get("name",""), objective.get("value",0), owner_txt]
	text += "\n[color=#c6aa6d]目标易手[/color]\n"
	var flips = []
	for event in view.get("logs", []):
		var line = str(event)
		if line.contains("控制") and line.contains("由"):
			flips.append(line)
	if flips.is_empty():
		text += "暂无易手记录。\n"
	else:
		for line in flips.slice(maxi(0, flips.size() - 12)):
			text += "· " + line + "\n"
	var alive = [0, 0]
	var org_sum = [0.0, 0.0]
	for unit in view.get("units", []):
		var s = int(unit.get("side", -1))
		if s in [0, 1] and float(unit.get("strength", 0)) > 0:
			alive[s] += 1
			org_sum[s] += float(unit.get("organization", 0)) if s == int(view.get("side", 0)) else 50.0
	text += "\n[color=#c6aa6d]兵力概览[/color]\n本方可战单位 %d" % alive[int(view.get("side", 0))]
	if int(view.get("side", 0)) == 0:
		text += " · 敌方可见 %d" % alive[1]
	else:
		text += " · 敌方可见 %d" % alive[0]
	text += "\n"
	text += "\n[color=#c6aa6d]积分时间线[/color]\n"
	if GameSession.has_method("score_timeline"):
		var timeline = GameSession.score_timeline()
		if timeline is Array and not timeline.is_empty():
			var parts = []
			for row in timeline:
				parts.append("T%s %s:%s" % [row.get("turn"), row.get("a"), row.get("b")])
			text += " · ".join(parts) + "\n"
		else:
			text += "开局 " + str(view.get("scores", [0, 0])) + "\n"
	text += "\n[color=#c6aa6d]本方损耗榜[/color]\n"
	var losses = []
	for unit in view.get("units", []):
		if int(unit.get("side", -1)) != int(view.get("side", 0)):
			continue
		var init = float(unit.get("initial_strength", unit.get("strength", 0)))
		var now = float(unit.get("strength", 0))
		if init > 0 and init - now > 1.0:
			losses.append({"name": str(unit.get("name", unit.get("id"))), "delta": init - now, "now": now})
	losses.sort_custom(func(a, b): return float(a.delta) > float(b.delta))
	if losses.is_empty():
		text += "本方暂无明显损耗。\n"
	else:
		for row in losses.slice(0, 8):
			text += "· %s  −%.1f（现存 %.1f）\n" % [row.name, row.delta, row.now]
	var upcoming: Array = view.get("upcoming_reinforcements", [])
	if upcoming is Array and not upcoming.is_empty():
		text += "\n[color=#c6aa6d]增援预告[/color]\n"
		for rf in upcoming:
			text += "· 第 %s 回合  %s @(%s,%s)\n" % [rf.get("turn"), rf.get("name"), rf.get("q"), rf.get("r")]
	text += "\n[color=#c6aa6d]最近行动[/color]\n"
	var logs: Array = view.get("logs",[])
	if logs.is_empty(): text += "尚无结算记录。双方锁定命令后，行动将在六个时段内同时展开。"
	for event in logs.slice(maxi(0,logs.size()-80)):
		if event is Dictionary: text += "• " + str(event.get("text",event.get("message",JSON.stringify(event)))) + "\n"
		else: text += "• " + str(event) + "\n"
	_dialog("战报 / AFTER ACTION REPORT",text)

func _rules() -> void:
	_dialog("指挥手册", "[font_size=25]在不确定中作出决定[/font_size]\n\n[color=#c6aa6d]01  阅读战场[/color]\n六角格代表固定公里数，每回合代表战役设定的小时数。地形、道路、河流和桥梁影响通行与战斗。金色圆环是计分目标；蓝、红算子代表不同阵营。\n\n[color=#c6aa6d]02  编排命令[/color]\n点击本方单位，选择机动、进攻或侦察，再点击目标格。固守、休整和预备直接作用于当前格。可选择谨慎、均衡或积极姿态。命令会持续执行，可在锁定前修改。同格堆叠单位可重复点击切换，也可从战斗序列选择。\n\n[color=#c6aa6d]03  同时结算 / WEGO[/color]\n双方分别下令并锁定，随后统一推进六个战术时段。敌军不会等待你的单位行动完毕。交战、退却、疲劳、弹药与燃料消耗均在结算中处理。\n\n[color=#c6aa6d]04  指挥与补给[/color]\n不要只看兵力。组织度、疲劳、燃料和弹药决定部队能否继续作战。总部距离、补给路线、补给吞吐量与时代能力会影响执行。使用补给图层查看本方枢纽，保护道路与后勤。\n\n[color=#c6aa6d]05  不完全情报[/color]\n只能查询本方详细状态及已观察到的敌军。问号是历史接触，未必代表敌军仍在原地。炮火、空援与战役侦察通过单位档案中的支援按钮指定目标。\n\n[color=#c6aa6d]06  操作与模式[/color]\n拖动地图平移，滚轮缩放；Esc 取消正在指定的命令。同机轮换时由交接遮罩保护双方信息。局域网由主机裁定状态。观战模式点击推进回合观看双方 AI。回放箭头读取历史快照。\n\n[color=#c6aa6d]07  键盘操作[/color]\n1–8：机动/进攻/固守/休整/侦察/预备/撤退/工程；C：锁定回合；Tab：下一单位；Shift+Tab：下一未下令单位；Backspace：撤销选中单位命令；Shift+Backspace：清空本回合命令；WASD/方向键：平移地图；+ / −：缩放。\n\n[color=#c6aa6d]08  控制区与预估[/color]\n敌方战斗单位周围一格为控制区（「控制区」图层红晕），进入后本回合停止机动。进攻悬停会给出赔率与接触面提示；路径预估会标明控制区停步与堆叠已满。\n\n每个剧本含独立史料与设计说明；地图、兵力强度和计分机制属于可玩性设计，不等同于历史统计。",Vector2i(780,680))

func _sources(scenario: Dictionary) -> void:
	var text = "[font_size=23]%s[/font_size]\n\n" % scenario.get("title","")
	text += str(scenario.get("design_notes","地图、数值与计分为战役模拟设计。")) + "\n\n[color=#c6aa6d]参考资料[/color]\n"
	for source in scenario.get("sources",[]):
		text += "\n[url=%s]%s[/url]\n%s\n" % [source.get("url",""),source.get("title","资料"),source.get("note","")]
	_dialog("史料与设计说明",text)

func _game_menu() -> void:
	var dialog = AcceptDialog.new()
	dialog.title = "战役菜单"
	dialog.ok_button_text = "继续指挥"
	add_child(dialog)
	var list = VBoxContainer.new()
	list.custom_minimum_size = Vector2(320,0)
	dialog.add_child(list)
	list.add_child(_label("存档槽位",12,GOLD))
	for slot in ["slot1", "slot2", "slot3"]:
		var row = HBoxContainer.new()
		list.add_child(row)
		var slot_name = slot
		row.add_child(_button("存 " + slot_name,func(): GameSession.save_game(slot_name)))
		row.add_child(_button("读 " + slot_name,func(): GameSession.load_game(slot_name); dialog.queue_free()))
		row.add_child(_button("删",func(): GameSession.delete_save(slot_name)))
	list.add_child(_button("存档管理…",func(): dialog.queue_free(); _save_manager()))
	list.add_child(_button("保存战役",func(): GameSession.save_game(); dialog.queue_free()))
	list.add_child(_button("载入战役",func(): GameSession.load_game(); dialog.queue_free()))
	var diff_row = HBoxContainer.new()
	list.add_child(diff_row)
	diff_row.add_child(_label("难度",12,MUTED))
	for level in ["easy","normal","hard"]:
		var lv = level
		diff_row.add_child(_button(str(lv),func(): GameSession.set_ai_difficulty(lv)))
	if GameSession.mode == "observer":
		list.add_child(_button("暂停/继续推演",func(): GameSession.commit_turn(); dialog.queue_free()))
	list.add_child(_button("指挥手册",func(): dialog.queue_free(); _rules()))
	if GameSession.has_method("agent_config_path"):
		list.add_child(_button("Agent 连接配置",func(): _dialog("Agent 接入", "连接配置保存在本机文件，供受信任的 MCP 客户端使用：\n\n" + str(GameSession.agent_config_path()) + "\n\nAgent 对战模式：本地指挥一方，外部 Agent 控制另一方。实际 Agent 对局需要单独接入客户端。")))
	list.add_child(_button("返回战役档案",func(): selected_id = ""; pending_order = ""; GameSession.close_game()))
	dialog.popup_centered()
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)


func _save_manager() -> void:
	var dialog = AcceptDialog.new()
	dialog.title = "存档管理"
	dialog.ok_button_text = "关闭"
	add_child(dialog)
	var list = VBoxContainer.new()
	list.custom_minimum_size = Vector2(420,0)
	dialog.add_child(list)
	var entries: Array = GameSession.list_save_slots()
	if entries.is_empty():
		list.add_child(_label("尚无本地存档",13,MUTED))
	for entry in entries:
		var row = HBoxContainer.new()
		list.add_child(row)
		var stamp = Time.get_datetime_dict_from_unix_time(int(entry.get("modified",0)))
		var label = "%s  ·  %04d-%02d-%02d %02d:%02d  ·  %s KB" % [entry.get("slot"), stamp.year, stamp.month, stamp.day, stamp.hour, stamp.minute, int(entry.get("bytes",0))/1024]
		var slot_name = str(entry.get("slot"))
		row.add_child(_button("读取",func(): GameSession.load_game(slot_name); dialog.queue_free()))
		row.add_child(_button("覆盖保存",func(): GameSession.save_game(slot_name)))
		row.add_child(_button("删除",func(): GameSession.delete_save(slot_name); dialog.queue_free(); _save_manager()))
		var info = _label(label,11,MUTED)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(info)
	dialog.popup_centered()
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)

func _lan_dialog() -> void:
	var dialog = AcceptDialog.new()
	lan_window = dialog
	dialog.title = "局域网作战室"
	dialog.ok_button_text = "返回"
	add_child(dialog)
	var list = VBoxContainer.new()
	list.custom_minimum_size = Vector2(430,0)
	dialog.add_child(list)
	var text = _label("主机创建当前所选战役，另一位指挥官输入主机地址加入。",13,MUTED)
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	list.add_child(text)
	if GameSession.has_method("get_local_addresses"):
		var addresses = _label("本机地址：" + ", ".join(GameSession.get_local_addresses()),12,GOLD)
		addresses.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		list.add_child(addresses)
	var address = LineEdit.new()
	address.placeholder_text = "主机 IP 地址，例如 192.168.1.10"
	address.text = "127.0.0.1"
	list.add_child(address)
	var port = SpinBox.new()
	port.min_value = 1024
	port.max_value = 65535
	port.value = 24680
	port.prefix = "端口 "
	list.add_child(port)
	var buttons = HBoxContainer.new()
	list.add_child(buttons)
	buttons.add_child(_button("创建主机",func(): GameSession.start_host(selected_scenario,int(port.value),selected_side)))
	buttons.add_child(_button("加入主机",func(): GameSession.join_host(address.text.strip_edges(),int(port.value))))
	list.add_child(_label("同一局域网使用主机内网 IP；默认端口 24680。",11,MUTED))
	if GameSession.has_method("discover_rooms"):
		list.add_child(_button("搜索局域网房间",func(): GameSession.discover_rooms()))
	room_list = VBoxContainer.new()
	list.add_child(room_list)
	_update_rooms()
	dialog.popup_centered()
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)

func _handoff() -> void:
	var curtain = PanelContainer.new()
	curtain.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	curtain.add_theme_stylebox_override("panel",_box(Color("102725")))
	add_child(curtain)
	var center = CenterContainer.new()
	curtain.add_child(center)
	var list = VBoxContainer.new()
	list.add_theme_constant_override("separation",24)
	center.add_child(list)
	list.add_child(_label("指挥权交接",38,GOLD))
	list.add_child(_label("本方命令已封存。请将设备交给另一位指挥官。",17))
	list.add_child(_label("准备就绪后打开战场，查看你的阵营态势。",13,MUTED))
	list.add_child(_button("我已接手 · 打开战场   →",func(): selected_id = ""; GameSession.accept_handoff()))

func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed:
		return
	if event.keycode == KEY_ESCAPE:
		pending_order = ""
		preview_path = []
		if is_instance_valid(canvas):
			if canvas.has_method("update_view"):
				var v = GameSession.view.duplicate(true)
				v["preview_path"] = []
				canvas.update_view(v, selected_id)
		_update_hint()
		_notice("目标选择已取消。")
		return
	if GameSession.view.is_empty() or GameSession.mode == "observer" or bool(GameSession.view.get("replay_active", false)):
		if is_instance_valid(canvas) and canvas.has_method("handle_key"):
			canvas.handle_key(event)
		return
	var kinds = ["move","attack","defend","rest","recon","reserve","retreat","engineer"]
	var idx = event.keycode - KEY_1
	if idx >= 0 and idx < kinds.size() and not selected_id.is_empty():
		_choose_order(kinds[idx])
		return
	if event.keycode == KEY_C:
		_commit()
		return
	if event.keycode == KEY_BACKSPACE and event.shift_pressed:
		GameSession.clear_orders()
		_refresh()
		return
	if event.keycode == KEY_BACKSPACE and not selected_id.is_empty():
		GameSession.clear_unit_order(selected_id)
		_refresh()
		return
	if event.keycode == KEY_TAB:
		var units = []
		for unit in GameSession.view.get("units", []):
			if int(unit.get("side",-1)) == int(GameSession.view.get("side",0)):
				units.append(str(unit.get("id","")))
		if event.shift_pressed:
			var orders = view_orders()
			var pending_units = []
			for uid in units:
				if not orders.has(uid):
					pending_units.append(uid)
			if not pending_units.is_empty():
				var cur = pending_units.find(selected_id)
				_select_unit(pending_units[(cur + 1) % pending_units.size()])
				return
		if not units.is_empty():
			var cur = units.find(selected_id)
			_select_unit(units[(cur + 1) % units.size()])
		return
	if is_instance_valid(canvas) and canvas.has_method("handle_key"):
		canvas.handle_key(event)

func _smoke() -> void:
	var args = OS.get_cmdline_user_args()
	if (not "--ui-smoke" in args and not "--ui-menu-smoke" in args) or smoke_done: return
	smoke_done = true
	var scenario_id = selected_scenario
	var capture = "user://ui-smoke.png"
	for arg in args:
		if arg.begins_with("--scenario="): scenario_id = arg.trim_prefix("--scenario=")
		if arg.begins_with("--capture="): capture = arg.trim_prefix("--capture=")
	if not "--ui-menu-smoke" in args: GameSession.start_game(scenario_id,"ai",0)
	await get_tree().process_frame
	for unit in GameSession.view.get("units",[]):
		if int(unit.get("side",-1)) == 0:
			selected_id = str(unit.get("id",""))
			break
	_refresh()
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image = get_viewport().get_texture().get_image()
	var result = image.save_png(capture)
	print("UI_SMOKE capture=",capture," result=",result," units=",GameSession.view.get("units",[]).size())
	get_tree().quit(0 if result == OK else 1)

func _lobby_refresh() -> void:
	if is_instance_valid(lan_window) and lan_window.visible:
		_update_rooms()
	else:
		_refresh()

func _update_rooms() -> void:
	if not is_instance_valid(room_list): return
	for child in room_list.get_children():
		room_list.remove_child(child)
		child.queue_free()
	for room in GameSession.rooms:
		var address = str(room.get("address",""))
		var port = int(room.get("port",24680))
		room_list.add_child(_button("%s · %s:%s" % [room.get("title","房间"),address,port],func(): GameSession.join_host(address,port)))
