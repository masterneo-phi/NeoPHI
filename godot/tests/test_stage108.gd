extends SceneTree
## 第108段: 復元タブの ID 引き直しの受け皿。
## - セッション保存名 (ログイン名) が登録表示名と食い違っても、
##   接続先の登録済みキャラが1つだけなら引き直せる。
## - ホスト表記が `.phirc` と食い違っても、名前+ポートが
##   1つだけなら引き直せる。
## - 候補が複数ある時は引き直さない (取り違え防止)。

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
	var root_dir := "user://stage108_root"
	OS.execute("rm", ["-rf", ProjectSettings.globalize_path(root_dir)])
	_write_chara(root_dir, "03_Ring.chara", "TESTID9", "10.0.0.1", 20019)
	var main: Node = Main.new()
	main.set("_tab_session_path", "user://stage108_tabs.ini")
	main.set("_config_path", "user://stage108_cfg.ini")
	for p in ["user://stage108_tabs.ini", "user://stage108_cfg.ini"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	root.add_child(main)
	await process_frame
	await process_frame
	(main.get("_assets") as GameAssets).philly_roots = [ProjectSettings.globalize_path(root_dir)]
	# 1) 名前が食い違う復元 (ログイン名 Ring material vs 表示名 03_Ring)
	var session_path := "user://stage108_tabs.ini"
	PhiTabSession.save_file([{"host": "10.0.0.1", "port": 20019, "name": "Ring material"}], session_path)
	main.set("_tab_session_path", session_path)
	main.call("_restore_tabs")
	await process_frame
	var healed: Variant = null
	for t in main.get("_tabs"):
		if t.port == 20019 and t.restored_name == "Ring material":
			healed = t
	check(healed != null, "mismatched-name tab restored")
	if healed != null:
		check(healed.session.char_id == "TESTID9", "unique host+port resolves despite name mismatch")
		check(healed.can_reconnect(), "healed tab can reconnect")
	# 2) ホスト表記が食い違う復元 (セッションはホスト名、.phirc は IP)
	PhiTabSession.save_file([{"host": "example.com", "port": 20019, "name": "Ring"}], session_path)
	main.call("_restore_tabs")
	await process_frame
	var healed2: Variant = null
	for t in main.get("_tabs"):
		if t.host == "example.com" and t.restored_name == "Ring":
			healed2 = t
	check(healed2 != null, "host-form-mismatch tab restored")
	if healed2 != null:
		check(healed2.session.char_id == "TESTID9", "unique name+port resolves despite host form")
	# 3) 候補が2つある接続先では、食い違う名前を引き直さない
	_write_chara(root_dir, "04_Other.chara", "TESTID7", "10.0.0.1", 20019)
	PhiTabSession.save_file([{"host": "10.0.0.1", "port": 20019, "name": "Ring material"}], session_path)
	main.call("_restore_tabs")
	await process_frame
	var ambiguous: Variant = null
	for t in main.get("_tabs"):
		if t.port == 20019 and t.restored_name == "Ring material" and t.session.char_id.is_empty():
			ambiguous = t
	check(ambiguous != null, "ambiguous host+port does not resolve a mismatched name")
	print("stage108: ", _checks, " checks, ", _failures, " failures")
	quit(1 if _failures > 0 else 0)
