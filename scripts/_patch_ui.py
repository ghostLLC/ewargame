from pathlib import Path

p = Path(r"C:\Users\LLC\.codex\worktrees\ewargame-content\game\ui\main.gd")
text = p.read_text(encoding="utf-8")

old_commit = '''\tvar commit = _button("战役结束 · 查看战报" if is_finished else ("推进一回合   →" if GameSession.mode == "observer" else "锁定命令 · 结束回合   →"),_reports if is_finished else _commit)
\tcommit.custom_minimum_size.y = 42
\tcommit.add_theme_stylebox_override("normal",_box(Color("a08954"),5,Color("d7bc7e")))
\tcommit.add_theme_color_override("font_color",Color("122c2b"))
\tcommit.disabled = bool(view.get("replay_active",false))
\tcommit_box.add_child(commit)
\tvar ready: Array = view.get("ready",[false,false])
\tcommit_box.add_child(_label("双方命令同时结算 · 六个战术时段" if not (true in ready) else "命令已锁定 · 等待另一方",10,MUTED))
'''
new_commit = '''\tvar commit_label = "战役结束 · 查看战报"
\tif not is_finished:
\t\tif GameSession.mode == "observer":
\t\t\tcommit_label = "继续推演" if GameSession.observer_paused() else "暂停推演"
\t\telse:
\t\t\tcommit_label = "锁定命令 · 结束回合   →"
\tvar commit = _button(commit_label,_reports if is_finished else _commit)
\tcommit.custom_minimum_size.y = 42
\tcommit.add_theme_stylebox_override("normal",_box(Color("a08954"),5,Color("d7bc7e")))
\tcommit.add_theme_color_override("font_color",Color("122c2b"))
\tcommit.disabled = bool(view.get("replay_active",false))
\tcommit_box.add_child(commit)
\tvar ready: Array = view.get("ready",[false,false])
\tif GameSession.mode == "observer":
\t\tcommit_box.add_child(_label("双方 AI 持续推演 · 可随时暂停",10,MUTED))
\telse:
\t\tcommit_box.add_child(_label("双方命令同时结算 · 六个战术时段" if not (true in ready) else "命令已锁定 · 等待另一方",10,MUTED))
'''
if old_commit not in text:
    raise SystemExit("commit block not found")
text = text.replace(old_commit, new_commit, 1)

old_menu = '''\tlist.add_child(_button("保存战役",func(): GameSession.save_game(); dialog.queue_free()))
\tlist.add_child(_button("载入战役",func(): GameSession.load_game(); dialog.queue_free()))
\tlist.add_child(_button("指挥手册",func(): dialog.queue_free(); _rules()))
'''
new_menu = '''\tlist.add_child(_label("存档槽位",12,GOLD))
\tfor slot in ["slot1", "slot2", "slot3"]:
\t\tvar row = HBoxContainer.new()
\t\tlist.add_child(row)
\t\tvar slot_name = slot
\t\trow.add_child(_button("存 " + slot_name,func(): GameSession.save_game(slot_name)))
\t\trow.add_child(_button("读 " + slot_name,func(): GameSession.load_game(slot_name); dialog.queue_free()))
\tlist.add_child(_button("保存战役",func(): GameSession.save_game(); dialog.queue_free()))
\tlist.add_child(_button("载入战役",func(): GameSession.load_game(); dialog.queue_free()))
\tif GameSession.mode == "observer":
\t\tlist.add_child(_button("暂停/继续推演",func(): GameSession.commit_turn(); dialog.queue_free()))
\tlist.add_child(_button("指挥手册",func(): dialog.queue_free(); _rules()))
'''
if old_menu not in text:
    raise SystemExit("menu block not found")
text = text.replace(old_menu, new_menu, 1)
p.write_text(text, encoding="utf-8")
print("main.gd patched ok")
