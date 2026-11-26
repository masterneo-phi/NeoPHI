extends SceneTree
## 第134段: ユーザー報告 (2026-11-23)。タブを開いて ID を手入力
## して接続したキャラクターが、キャラクター一覧に出ない。
## タブを閉じると、再接続の手段が無くなる。
##
## 原因: 手入力の ID は「保存しない」設計で、接続に成功しても
## `.phirc` が書かれなかった。一覧は `*.chara/.phirc` の走査
## なので出てこず、ID はタブセッションに残るだけだった。
##
## 修正: 登録ファイルの無い接続 (同じ接続先+ID の登録が無い)
## では、接続時にタブへ印を立て、サーバから名前が届いた時点
## (接続成功) で、Main がその名前から表示名を作って `.phirc`
## を書く。同じ接続先+ID の登録が既にある場合は既存を尊重し、
## 何も書かない。保存するのは従来の `.phirc` の範囲だけ。
##
## 使い方: godot --headless --path . -s tests/test_stage134.gd
## 終了コード 0 = 全一致、1 = 不一致あり。

const Main := preload("res://scripts/main.gd")

var _checks := 0
var _failures := 0


func check(cond: bool, label: String) -> void:
	_checks += 1
	if not cond:
		_failures += 1
		printerr("FAIL: ", label)


func check_eq(a: Variant, b: Variant, label: String) -> void:
	_checks += 1
	if a != b:
		_failures += 1
		printerr("FAIL: ", label, " (got ", a, ", want ", b, ")")


func _write_chara(root_dir: String, folder: String, id: String, host: String, port: int) -> void:
	var chara_dir := root_dir.path_join(folder)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(chara_dir))
	var f := FileAccess.open(chara_dir.path_join(".phirc"), FileAccess.WRITE)
	f.store_string("%s\n%s %d\n" % [id, host, port])
	f.close()


func _entry_for_id(entries: Array, id: String) -> Dictionary:
	for entry in entries:
		if str(entry["id"]) == id:
			return entry
	return {}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	# --- 隔離した置き場と、登録済みキャラを1件用意 ---
	var root_dir := "user://stage134_root"
	OS.execute("rm", ["-rf", ProjectSettings.globalize_path(root_dir)])
	_write_chara(root_dir, "01_Known.chara", "KNOWNID1", "10.0.0.9", 20030)
	var root_abs := ProjectSettings.globalize_path(root_dir)
	var known_phirc_path := root_abs.path_join("01_Known.chara").path_join(".phirc")
	var known_phirc_before := FileAccess.get_file_as_string(known_phirc_path)

	var main: Node = Main.new()
	for p in ["user://stage134_tabs.ini", "user://stage134_cfg.ini"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	main.set("_tab_session_path", "user://stage134_tabs.ini")
	main.set("_config_path", "user://stage134_cfg.ini")
	root.add_child(main)
	await process_frame
	await process_frame
	(main.get("_assets") as GameAssets).philly_roots = [root_abs]
	main.set("_tab_session_path", "user://stage134_tabs.ini")

	# --- A) 手入力で接続し、名前が届いたら一覧へ登録される ---
	var tab = main.call("_create_tab")
	main.call("_connect_tab", tab, "10.0.0.9", 20031, "MANUALID1")
	check(bool(tab.get("auto_register_pending")), "s134 manual connect is pending registration")
	tab.call("_accept_player_name", "Manual Hero")
	check(not bool(tab.get("auto_register_pending")), "s134 pending cleared once the name arrives")
	var entries := PhiCharacters.scan_root(root_abs)
	check_eq(entries.size(), 2, "s134 manual character is registered")
	var manual_entry := _entry_for_id(entries, "MANUALID1")
	check(not manual_entry.is_empty(), "s134 manual entry exists")
	if not manual_entry.is_empty():
		check_eq(str(manual_entry["display_name"]), "02_Manual-Hero", "s134 display name comes from the server name")
		check_eq(str(manual_entry["host"]), "10.0.0.9", "s134 registered host")
		check_eq(int(manual_entry["port"]), 20031, "s134 registered port")
	check_eq(str(tab.get("restored_name")), "02_Manual-Hero", "s134 tab takes the display name")
	# `.phirc` の中身は ID と接続先だけ (パスワード等は無い)。
	var manual_text := FileAccess.get_file_as_string(
		root_abs.path_join("02_Manual-Hero.chara").path_join(".phirc"))
	var parsed := PhiCharacters.parse_phirc_text(manual_text)
	check_eq(str(parsed.get("id", "")), "MANUALID1", "s134 phirc holds the id")
	check_eq(str(parsed.get("host", "")), "10.0.0.9", "s134 phirc holds the host")
	check_eq(int(parsed.get("port", 0)), 20031, "s134 phirc holds the port")
	# Main の一覧 (キャラメニューや接続ダイアログの元) にも出る。
	check(not _entry_for_id(main.call("_registered_characters"), "MANUALID1").is_empty(),
		"s134 manual character appears in the character list")

	# --- B) 同じキャラの再接続では重複登録しない ---
	var tab2 = main.call("_create_tab")
	main.call("_connect_tab", tab2, "10.0.0.9", 20031, "MANUALID1")
	check(not bool(tab2.get("auto_register_pending")), "s134 registered character is not pending again")
	tab2.call("_accept_player_name", "Manual Hero")
	check_eq(PhiCharacters.scan_root(root_abs).size(), 2, "s134 no duplicate registration")

	# --- C) 登録済みキャラの接続では何も書かない ---
	var tab3 = main.call("_create_tab")
	main.call("_connect_tab", tab3, "10.0.0.9", 20030, "KNOWNID1")
	check(not bool(tab3.get("auto_register_pending")), "s134 known character is not pending")
	tab3.call("_accept_player_name", "Known")
	check_eq(PhiCharacters.scan_root(root_abs).size(), 2, "s134 known character adds nothing")
	check_eq(FileAccess.get_file_as_string(known_phirc_path), known_phirc_before,
		"s134 existing phirc is left untouched")

	# --- D) 接続を経ていないタブは、名前が届いても登録しない ---
	var tab4 = main.call("_create_tab")
	tab4.call("_accept_player_name", "Stray")
	check_eq(PhiCharacters.scan_root(root_abs).size(), 2, "s134 no registration without a connect")

	# --- E) 世界移動の追随完了で .phirc が移動先へ書き換わる ---
	var tab5 = main.call("_create_tab")
	main.call("_connect_tab", tab5, "10.0.0.9", 20030, "KNOWNID1")
	var sess5 = tab5.get("session")
	sess5.set("host", "10.0.0.10")
	sess5.set("port", 20096)
	sess5.emit_signal("transfer_completed")
	check_eq(str(tab5.get("host")), "10.0.0.10", "s134 tab host follows destination")
	check_eq(int(tab5.get("port")), 20096, "s134 tab port follows destination")
	var known_after := _entry_for_id(PhiCharacters.scan_root(root_abs), "KNOWNID1")
	check_eq(str(known_after.get("host", "")), "10.0.0.10", "s134 phirc host rewritten to destination")
	check_eq(int(known_after.get("port", 0)), 20096, "s134 phirc port rewritten to destination")
	var manual_after := _entry_for_id(PhiCharacters.scan_root(root_abs), "MANUALID1")
	check_eq(str(manual_after.get("host", "")), "10.0.0.9", "s134 other character's phirc untouched")
	check_eq(int(manual_after.get("port", 0)), 20031, "s134 other character's port untouched")
	# 移動元が登録内容と食い違うタブの追随では書き換えない
	var tab6 = main.call("_create_tab")
	main.call("_connect_tab", tab6, "10.9.9.9", 20099, "MANUALID1")
	var sess6 = tab6.get("session")
	sess6.set("host", "10.0.0.11")
	sess6.set("port", 20097)
	sess6.emit_signal("transfer_completed")
	var manual_after2 := _entry_for_id(PhiCharacters.scan_root(root_abs), "MANUALID1")
	check_eq(str(manual_after2.get("host", "")), "10.0.0.9", "s134 phirc kept when origin differs")
	check_eq(int(manual_after2.get("port", 0)), 20031, "s134 phirc port kept when origin differs")

	print("test_stage134: ", _checks, " checks, ", _failures, " failures")
	quit(1 if _failures > 0 else 0)
