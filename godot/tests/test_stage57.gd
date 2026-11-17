extends SceneTree
## 第57段: 起動時のタブが増えないこと。
## (1) 保存タブがある時は復元タブだけが開き、空の未接続タブは
##     増えない (復元が無ければ空タブ 1 つ)。
## (2) ID を引き直せていない復元タブでも、キャラ一覧から
##     同じ名前のキャラを選べば、そのタブを使い回して ID を
##     付け直す (タブが増えない)。

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
	var ps := load("res://main.tscn") as PackedScene
	var main: Node = ps.instantiate()
	root.add_child(main)
	await create_timer(1.0).timeout
	var base_count: int = (main.get("_tabs") as Array).size()
	# (1) 保存タブ 1 件を復元 → タブは 1 つだけ増え、返り値は
	# 復元タブ (空タブではない)。
	var session_path := "user://stage57_tabs.ini"
	PhiTabSession.save_file([{"host": "127.0.0.1", "port": 20019, "name": "KURO57"}], session_path)
	main.set("_tab_session_path", session_path)
	var returned: Variant = main.call("_restore_tabs")
	await process_frame
	check((main.get("_tabs") as Array).size() == base_count + 1, "restore adds exactly one tab (got %d -> %d)" % [base_count, (main.get("_tabs") as Array).size()])
	check(returned != null and returned.restored_name == "KURO57", "restore returns the restored tab")
	check(returned != null and returned.host == "127.0.0.1", "returned tab is not the empty tab")
	# (2) そのタブは ID 未解決 (登録キャラが無い環境) でも、
	# 名前が一致すれば _connect_character が使い回す。
	var kuro: Variant = returned
	check(kuro.session.char_id.is_empty(), "id unresolved in this env")
	var before: int = (main.get("_tabs") as Array).size()
	var used: Variant = main.call("_connect_character", "127.0.0.1", 20019, "TESTID9", "KURO57")
	await process_frame
	check(used == kuro, "connect reuses the restored tab by name")
	check((main.get("_tabs") as Array).size() == before, "no new tab created")
	check(kuro.session.char_id == "TESTID9", "id attached on reuse")
	# 別の名前では使い回さない (新しいタブになる)。
	var other: Variant = main.call("_connect_character", "127.0.0.1", 20019, "TESTID8", "OTHER")
	check(other != kuro, "different name gets its own tab")
	main.queue_free()

	print("stage57: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)
