extends SceneTree
## 第51段: 起動時の自動接続をやめ、「接続」メニューはそのタブの
## キャラで直接つなぎ直す (Philly の仕様)。
## - 引数で ID が明示された時だけ起動時に接続する。
## - タブセッションの復元は、接続先が設定と重なっても省かない。
## - 「接続」は、再接続できるタブではダイアログを出さずに
##   直接つなぎ直し、キャラの無いタブではダイアログを出す。

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
	# 空のセッションファイルを使う (手動復元の分は後で差し替える)。
	var iso := ProjectSettings.globalize_path("user://stage51_start.ini")
	OS.execute("rm", ["-f", iso])
	main.set("_tab_session_path", "user://stage51_start.ini")
	root.add_child(main)
	await process_frame
	await process_frame
	# 起動時: 自動接続しない (接続待ち)。
	check(main.get("_startup_connect") == false, "no startup connect without explicit id")
	var first_tab: Variant = main.call("_active_tab")
	check(not first_tab.is_session_open(), "startup tab is not connected")
	check(first_tab.host.is_empty(), "startup tab has no host")
	var has_wait_line := false
	for entry in first_tab.get("_log_lines"):
		if str(entry["display"]).contains("接続待ち"):
			has_wait_line = true
	check(has_wait_line, "waiting message logged")
	# 復元: 設定の接続先と重なる保存項目も省かない。
	var session_path := "user://stage51_tabs.ini"
	PhiTabSession.save_file([{"host": "127.0.0.1", "port": 20017, "name": "META"}], session_path)
	main.set("_tab_session_path", session_path)
	main.call("_restore_tabs")
	await process_frame
	var meta_tab: Variant = null
	for t in main.get("_tabs"):
		if t.restored_name == "META":
			meta_tab = t
	check(meta_tab != null, "session entry matching config is restored too")
	# 「接続」メニュー: キャラの無いタブではダイアログ。
	main.call("_activate_tab", first_tab)
	main.call("_do_action", "Open")
	await process_frame
	var dialog: Variant = main.get("_connect_dialog")
	check(dialog != null and dialog.visible, "connect on empty tab opens the dialog")
	if dialog != null:
		dialog.hide()
	# 「接続」メニュー: 再接続できるタブでは直接つなぎ直す。
	var root_dir := "user://stage51_root"
	OS.execute("rm", ["-rf", ProjectSettings.globalize_path(root_dir)])
	var chara_dir := root_dir + "/01_KURO.chara"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(chara_dir))
	var f := FileAccess.open(chara_dir + "/.phirc", FileAccess.WRITE)
	f.store_string("TESTID1\n127.0.0.1 20019\n")
	f.close()
	(main.get("_assets") as GameAssets).philly_roots = [ProjectSettings.globalize_path(root_dir)]
	PhiTabSession.save_file([{"host": "127.0.0.1", "port": 20019, "name": "KURO"}], session_path)
	main.call("_restore_tabs")
	await process_frame
	var kuro: Variant = null
	for t in main.get("_tabs"):
		if t.restored_name == "KURO":
			kuro = t
	check(kuro != null, "kuro tab restored")
	if kuro != null:
		check(kuro.session.char_id == "TESTID1", "kuro tab resolved id")
		main.call("_activate_tab", kuro)
		var tabs_before: int = main.get("_tabs").size()
		var lines_before: int = kuro.get("_log_lines").size()
		main.call("_do_action", "Open")
		await process_frame
		check(main.get("_tabs").size() == tabs_before, "connect menu creates no tab")
		check(dialog == null or not dialog.visible, "connect menu opens no dialog")
		var connect_logged := false
		var lines: Array = kuro.get("_log_lines")
		for i in range(lines_before, lines.size()):
			if str(lines[i]["display"]).contains("に接続します"):
				connect_logged = true
		check(connect_logged, "connect menu reconnects the tab character directly")
	print("stage51: ", _checks, " checks, ", _failures, " failures")
	quit(1 if _failures > 0 else 0)
