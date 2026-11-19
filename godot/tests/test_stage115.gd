extends SceneTree
## 第115段: キャラクター作成の完了時に、発行 ID がセッションへ
## 残ること。以前は session.char_id が "newuser" のままになり、
## そのタブを再接続すると #open newuser が送られ、サーバが
## 新規登録ダイアログを始めて接続できなくなった (実地報告)。
## あわせて、char_id == "newuser" のタブは再接続対象から
## 外れることも確かめる。

const Main := preload("res://scripts/main.gd")

var _checks := 0
var _failures := 0


func check(cond: bool, label: String) -> void:
	_checks += 1
	if not cond:
		_failures += 1
		print("FAIL: ", label)


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var main: Node = Main.new()
	for f in ["stage115_tabs.ini", "stage115_config.ini"]:
		OS.execute("rm", ["-f", ProjectSettings.globalize_path("user://" + f)])
	main.set("_tab_session_path", "user://stage115_tabs.ini")
	main.set("_config_path", "user://stage115_config.ini")
	root.add_child(main)
	var tab: Variant = main.call("_active_tab")
	check(tab != null, "active tab exists")

	# 作成セッションの完了直前を再現する: char_id は "newuser"、
	# レジスタには発行 ID が入っている。
	tab.host = "127.0.0.1"
	tab.port = 20093
	tab.session.char_id = "newuser"
	var reg := PhiRegister.new("Tester", "test", "a@b.c")
	reg.issued_id = "CUBE00001test"
	reg.done = true
	tab.set("_register", reg)
	tab.set("_register_display_name", "01_Tester")
	tab.set("_register_root", ProjectSettings.globalize_path("user://"))
	tab.call("_finish_register")
	check(tab.session.char_id == "CUBE00001test",
		"issued id stored in session (got %s)" % tab.session.char_id)
	check(tab.get("_register") == null, "register state cleared")
	check(tab.can_reconnect(), "reconnect possible with issued id")

	# 作成に失敗した等で "newuser" が残ったタブは再接続対象外。
	tab.session.char_id = "newuser"
	check(not tab.can_reconnect(), "newuser tab is not reconnectable")
	tab.session.char_id = "CUBE00001test"
	check(tab.can_reconnect(), "real id tab is reconnectable again")

	main.queue_free()
	print("stage115: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)
