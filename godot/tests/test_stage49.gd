extends SceneTree
## 第49段: 同じキャラは同じタブで接続し直す (Philly の挙動)。
## キャラメニューの登録キャラ選択と、行き先未指定の接続
## ダイアログの両方で、接続先+ID が一致するタブがあれば
## 使い回し、無ければ作る。接続中なら切り替えるだけ。

const Main := preload("res://scripts/main.gd")

var _checks := 0
var _failures := 0


func check(cond: bool, label: String) -> void:
	_checks += 1
	if not cond:
		_failures += 1
		print("FAIL: ", label)


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var main: Node = Main.new()
	# 起動時の復元が他テストの保存に影響されないよう、専用の
	# 空のセッションファイルを使う。
	var iso := ProjectSettings.globalize_path("user://stage49_tabs.ini")
	OS.execute("rm", ["-f", iso])
	main.set("_tab_session_path", "user://stage49_tabs.ini")
	root.add_child(main)
	await process_frame
	await process_frame
	var tab_a: Variant = main.call("_active_tab")
	# タブ A にキャラの identity を持たせる (接続そのものの
	# 成否は見ない)。
	main.call("_connect_tab", tab_a, "127.0.0.1", 20017, "TESTID1")
	await process_frame
	check(tab_a.host == "127.0.0.1" and tab_a.port == 20017, "identity host/port recorded")
	check(tab_a.session.char_id == "TESTID1", "identity id recorded")
	var count0: int = main.get("_tabs").size()
	# 同じキャラ: 同じタブが返り、タブは増えない。
	var reused: Variant = main.call("_connect_character", "127.0.0.1", 20017, "TESTID1", "01_テスト")
	check(reused == tab_a, "same character reuses the tab")
	check(main.get("_tabs").size() == count0, "no new tab for same character")
	check(main.call("_active_tab") == tab_a, "reused tab is active")
	# 違うキャラ: 新しいタブができる。
	var tab_b: Variant = main.call("_connect_character", "127.0.0.1", 20017, "TESTID2", "02_テスト")
	check(tab_b != tab_a, "different character gets a new tab")
	check(main.get("_tabs").size() == count0 + 1, "new tab created for different character")
	# ポートが違えば別キャラ扱い。
	check(main.call("_find_tab_for_character", "127.0.0.1", 20018, "TESTID1") == null, "different port is a different character")
	check(main.call("_find_tab_for_character", "127.0.0.1", 20017, "") == null, "empty id never matches")
	# キャラメニューの登録キャラ選択でも使い回す。
	main.set("_chara_menu_entries", [{"display_name": "01_テスト", "host": "127.0.0.1", "port": 20017, "id": "TESTID1"}])
	var count1: int = main.get("_tabs").size()
	main.call("_on_character_menu_pressed", Main.CHARA_MENU_ENTRY_BASE)
	await process_frame
	check(main.get("_tabs").size() == count1, "character menu reuses the tab")
	check(main.call("_active_tab") == tab_a, "character menu activates the existing tab")
	# 行き先未指定の接続ダイアログでも使い回す。
	main.call("_show_connect_dialog", null)
	(main.get("_connect_host_edit") as LineEdit).text = "127.0.0.1"
	(main.get("_connect_port_edit") as LineEdit).text = "20017"
	(main.get("_connect_id_edit") as LineEdit).text = "TESTID2"
	main.call("_on_connect_confirmed")
	await process_frame
	check(main.get("_tabs").size() == count1, "connect dialog reuses the tab")
	check(main.call("_active_tab") == tab_b, "connect dialog activates the existing tab")
	print("stage49: ", _checks, " checks, ", _failures, " failures")
	quit(1 if _failures > 0 else 0)
