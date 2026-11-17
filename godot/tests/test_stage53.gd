extends SceneTree
## 第53段: タブのキャラ名が消えないようにする。
## - session_state はログイン名が無ければ復元名を保存する。
## - 名前が空で保存されていたタブは、接続先が一致する登録済み
##   キャラが1つだけなら、その名前と ID で補って復元する
##   (題名が「ホスト:ポート」のままにならない)。

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
	var root_dir := "user://stage53_root"
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
	# session_state の名前フォールバック。
	var tab: Variant = main.call("_active_tab")
	tab.host = "127.0.0.1"
	tab.port = 20019
	tab.set_restored_name("01_KURO")
	check(str(tab.session_state()["name"]) == "01_KURO", "session state falls back to restored name")
	tab.call("_on_event", {"type": "notice", "name": "KURO"})
	check(str(tab.session_state()["name"]) == "KURO", "session state prefers player name")
	# 名前が空の保存項目は、登録キャラから補って復元する。
	var session_path := "user://stage53_tabs.ini"
	PhiTabSession.save_file([{"host": "127.0.0.1", "port": 20019, "name": ""}], session_path)
	main.set("_tab_session_path", session_path)
	main.call("_restore_tabs")
	await process_frame
	var healed: Variant = null
	for t in main.get("_tabs"):
		if t.port == 20019 and t.restored_name == "KURO":
			healed = t
	check(healed != null, "nameless entry healed from registered characters")
	if healed != null:
		check(healed.session.char_id == "TESTID1", "healed tab also gets the id")
		check(healed.tab_title() == "KURO", "healed tab title is the character name")
		check(healed.can_reconnect(), "healed tab can reconnect")
	print("stage53: ", _checks, " checks, ", _failures, " failures")
	quit(1 if _failures > 0 else 0)
