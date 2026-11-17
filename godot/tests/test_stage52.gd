extends SceneTree
## 第52段: priv 宛先の材料になる #user 行の解釈を、サーバの
## 実バイト列 (``#user %04d %-31s``) で確認する。パーサ →
## キャラクタの _users → priv ウィンドウの宛先チェックまで。

const Main := preload("res://scripts/main.gd")

var _checks := 0
var _failures := 0


func check(cond: bool, label: String) -> void:
	_checks += 1
	if not cond:
		_failures += 1
		print("FAIL: ", label)


func _user_line(no: int, name: String) -> PackedByteArray:
	var text := "#user %04d %-31s" % [no, name]
	return Cp932.encode(text)


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var parser := PhiParser.new()
	var events: Array = parser.feed(_user_line(1, "KURO"))
	check(events.size() == 1 and str(events[0].get("type", "")) == "userList", "user line parses")
	events = parser.feed(_user_line(7, "Taro"))
	check(events.size() == 1, "second user line parses")
	var users: Array = events[0].get("users", [])
	check(users.size() == 2, "users accumulate")
	check(str(users[0]["name"]) == "KURO" and str(users[0]["key"]) == "u1", "first user kept")
	check(str(users[1]["name"]) == "Taro" and str(users[1]["key"]) == "u7", "second user added")
	# キャラクタへ流すと宛先の材料になる。
	var main: Node = Main.new()
	root.add_child(main)
	await process_frame
	await process_frame
	var tab: Variant = main.call("_active_tab")
	tab.call("_on_event", {"type": "notice", "name": "KURO"})
	for line_events in [parser.feed(_user_line(1, "KURO")), parser.feed(_user_line(7, "Taro"))]:
		for ev in line_events:
			tab.call("_on_event", ev)
	check(tab.users().size() == 2, "tab holds both users")
	# priv ウィンドウ: 自分 (KURO) は宛先から除かれ、Taro が残る。
	main.call("_show_priv_window")
	await process_frame
	var win: Variant = main.get("_priv_window")
	var names: Array = win.recipient_names()
	check(names.size() == 1 and names[0] == "Taro", "priv recipients exclude self")
	print("stage52: ", _checks, " checks, ", _failures, " failures")
	quit(1 if _failures > 0 else 0)
