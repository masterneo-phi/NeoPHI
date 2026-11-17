extends SceneTree
## 第50段: 復元タブの ID 引き直し。タブセッションには ID を
## 保存しない方針のまま、復元時に登録済みキャラ (`.phirc`) と
## 接続先+名前が一致すれば ID をメモリに引き直し、再接続や
## 「全キャラを接続」の対象になるようにする。接続ダイアログ
## (タブ指定) でも、引き直せる ID は入力欄に入れておく。

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
	var root_dir := "user://stage50_root"
	OS.execute("rm", ["-rf", ProjectSettings.globalize_path(root_dir)])
	var chara_dir := root_dir + "/01_KURO.chara"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(chara_dir))
	var f := FileAccess.open(chara_dir + "/.phirc", FileAccess.WRITE)
	f.store_string("TESTID1\n127.0.0.1 20019\n")
	f.close()
	var main: Node = Main.new()
	root.add_child(main)
	await process_frame
	await process_frame
	(main.get("_assets") as GameAssets).philly_roots = [ProjectSettings.globalize_path(root_dir)]
	# 引き直しの基本動作。
	check(main.call("_registered_id_for", "127.0.0.1", 20019, "KURO") == "TESTID1", "resolve by name")
	check(main.call("_registered_id_for", "127.0.0.1", 20019, "01_KURO") == "TESTID1", "resolve by display name")
	check(main.call("_registered_id_for", "127.0.0.1", 20018, "KURO") == "", "wrong port does not resolve")
	check(main.call("_registered_id_for", "127.0.0.1", 20019, "OTHER") == "", "wrong name does not resolve")
	check(main.call("_registered_id_for", "127.0.0.1", 20019, "") == "", "empty name does not resolve")
	check(Main._display_name_body("01_KURO") == "KURO", "display body strips number")
	check(Main._display_name_body("KURO") == "KURO", "display body keeps plain name")
	# 復元: セッションファイル (ID なし) から作ったタブに ID が付く。
	var session_path := "user://stage50_tabs.ini"
	PhiTabSession.save_file([{"host": "127.0.0.1", "port": 20019, "name": "KURO"}], session_path)
	main.set("_tab_session_path", session_path)
	var before: int = main.get("_tabs").size()
	main.call("_restore_tabs")
	await process_frame
	var restored: Variant = null
	for t in main.get("_tabs"):
		if t.host == "127.0.0.1" and t.port == 20019 and t.restored_name == "KURO":
			restored = t
	check(restored != null, "tab restored from session file")
	check(main.get("_tabs").size() > before, "restore added tabs")
	if restored != null:
		check(restored.session.char_id == "TESTID1", "restored tab resolved its id")
		check(restored.can_reconnect(), "restored tab can reconnect")
		check(main.call("_find_tab_for_character", "127.0.0.1", 20019, "TESTID1") == restored, "restored tab found by character lookup")
		# 接続ダイアログ (タブ指定) で ID が入っている。
		main.call("_show_connect_dialog", restored)
		check((main.get("_connect_id_edit") as LineEdit).text == "TESTID1", "connect dialog prefills resolved id")
		(main.get("_connect_dialog") as Window).hide()
	print("stage50: ", _checks, " checks, ", _failures, " failures")
	quit(1 if _failures > 0 else 0)
