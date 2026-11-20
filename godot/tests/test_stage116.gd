extends SceneTree
## 第116段: 手入力でつないだキャラのタブが、再起動後も
## キャラ名で表示され、再接続できること。
## - TabSession は ID を第4フィールドに保存し、旧形式も読める。
## - 登録ファイルが無い手入力キャラでも、復元タブに ID が残り
##   can_reconnect() が真になる。
## - 名前が空でも、ID が一致する登録済みキャラの表示名で
##   題名を補える (同じ接続先に複数キャラがいても取り違えない)。

const Main := preload("res://scripts/main.gd")

var _checks := 0
var _failures := 0


func check(cond: bool, label: String) -> void:
	_checks += 1
	if not cond:
		_failures += 1
		print("FAIL: ", label)


func _write_chara(root_dir: String, folder: String, id: String, host: String, port: int) -> void:
	var chara_dir := root_dir.path_join(folder)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(chara_dir))
	var f := FileAccess.open(chara_dir.path_join(".phirc"), FileAccess.WRITE)
	f.store_string("%s\n%s %d\n" % [id, host, port])
	f.close()


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	# --- A) TabSession の往復と旧形式互換 ---
	var tabs := [{"host": "59.106.178.128", "port": 20020, "name": "Master", "id": "master1970"},
		{"host": "10.0.0.1", "port": 20019, "name": "Ring"}]
	var text := PhiTabSession.serialize(tabs)
	check(text.split("\n")[0].split("\t").size() == 4, "serialize writes id as 4th field")
	check(text.split("\n")[1].split("\t").size() == 3, "serialize omits empty id")
	var back := PhiTabSession.parse(text)
	check(back.size() == 2, "round trip keeps both tabs")
	check(str(back[0].get("id", "")) == "master1970", "round trip keeps id")
	check(str(back[1].get("id", "")) == "", "missing id parses as empty")
	var legacy := PhiTabSession.parse("10.0.0.1\t20019\tRing\n")
	check(legacy.size() == 1 and str(legacy[0].get("id", "")) == "", "legacy 3-field line parses")

	# --- Main を隔離して用意 ---
	var root_dir := "user://stage116_root"
	OS.execute("rm", ["-rf", ProjectSettings.globalize_path(root_dir)])
	_write_chara(root_dir, "07_Boss.chara", "BOSSID1", "10.0.0.9", 20030)
	_write_chara(root_dir, "08_Sub.chara", "SUBID2", "10.0.0.9", 20030)
	var main: Node = Main.new()
	main.set("_tab_session_path", "user://stage116_tabs.ini")
	main.set("_config_path", "user://stage116_cfg.ini")
	for p in ["user://stage116_tabs.ini", "user://stage116_cfg.ini"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	root.add_child(main)
	await process_frame
	await process_frame
	(main.get("_assets") as GameAssets).philly_roots = [ProjectSettings.globalize_path(root_dir)]
	var session_path := "user://stage116_tabs.ini"
	main.set("_tab_session_path", session_path)

	# --- B) 手入力キャラ (登録ファイルなし) の復元 ---
	PhiTabSession.save_file([{"host": "59.106.178.128", "port": 20020, "name": "Master", "id": "master1970"}], session_path)
	main.call("_restore_tabs")
	await process_frame
	var manual: Variant = null
	for t in main.get("_tabs"):
		if t.host == "59.106.178.128" and t.port == 20020:
			manual = t
	check(manual != null, "manual tab restored")
	if manual != null:
		check(manual.session.char_id == "master1970", "manual tab keeps its id")
		check(manual.restored_name == "Master", "manual tab keeps its name")
		check(manual.tab_title() == "Master", "manual tab title is the character name")
		check(manual.can_reconnect(), "manual tab can reconnect")
		check(str(manual.session_state().get("id", "")) == "master1970", "session_state carries the id")

	# --- C) 名前が空でも ID 一致の登録名で題名を補う ---
	PhiTabSession.save_file([{"host": "10.0.0.9", "port": 20030, "name": "", "id": "BOSSID1"}], session_path)
	main.call("_restore_tabs")
	await process_frame
	var healed: Variant = null
	for t in main.get("_tabs"):
		if t.host == "10.0.0.9" and t.port == 20030 and t.session.char_id == "BOSSID1":
			healed = t
	check(healed != null, "id-only tab restored")
	if healed != null:
		check(healed.tab_title() == "Boss", "title healed from the registered name matching the id")
	print("stage116: ", _checks, " checks, ", _failures, " failures")
	quit(1 if _failures > 0 else 0)
