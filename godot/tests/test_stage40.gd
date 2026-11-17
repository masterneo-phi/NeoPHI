extends SceneTree
## 第40段: GitHub リリースの更新チェック。
## バージョン比較と API 応答の解釈 (ネットワークには出ない)、
## 新しい版があれば更新窓が出ること、メニュー項目の配線を見る。

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
	# (1) バージョン比較
	check(PhiUpdate.is_newer("v1.0", "0.4.0"), "v1.0 > 0.4.0")
	check(PhiUpdate.is_newer("0.4.1", "0.4.0"), "0.4.1 > 0.4.0")
	check(not PhiUpdate.is_newer("0.4.0", "0.4.0"), "0.4.0 == 0.4.0")
	check(not PhiUpdate.is_newer("0.3.9", "0.4.0"), "0.3.9 < 0.4.0")
	check(PhiUpdate.is_newer("v0.10.0", "0.9.9"), "0.10.0 > 0.9.9 (numeric)")
	check(not PhiUpdate.is_newer("1.0", "1.0.0"), "1.0 == 1.0.0")
	check(PhiUpdate.is_newer("2", "1.9.9"), "2 > 1.9.9")
	check(str(PhiUpdate.parse_version("v1.2.3")) == "[1, 2, 3]", "parse v1.2.3")

	# (2) API 応答の解釈
	var sample := "{\"tag_name\":\"v1.2.0\",\"name\":\"NeoPHI v1.2.0\",\"html_url\":\"https://github.com/masterneo-phi/NeoPHI/releases/tag/v1.2.0\"}"
	var info := PhiUpdate.parse_latest(sample)
	check(str(info.get("tag", "")) == "v1.2.0", "parse tag")
	check(str(info.get("name", "")) == "NeoPHI v1.2.0", "parse name")
	check(PhiUpdate.page_url(info).ends_with("/releases/tag/v1.2.0"), "page url from info")
	check(PhiUpdate.parse_latest("not json").is_empty(), "garbage -> empty")
	check(PhiUpdate.parse_latest("{\"message\":\"Not Found\"}").is_empty(), "404 body -> empty")
	check(PhiUpdate.page_url({}) == PhiUpdate.RELEASES_URL, "page url fallback")

	# (3) メニュー配線
	var action: Dictionary = PhiActions.get_action("CheckUpdate")
	check(str(action.get("kind", "")) == "update-check", "CheckUpdate kind")
	var tool_menu: Dictionary = {}
	for m in PhiActions.MENUS:
		if str(m.get("name", "")) == "ツール":
			tool_menu = m
	check((tool_menu.get("items", []) as Array).has("CheckUpdate"), "CheckUpdate in tool menu")

	# (4) 応答ハンドラ: 新しい版なら窓が出る
	var ps := load("res://main.tscn") as PackedScene
	var main: Node = ps.instantiate()
	root.add_child(main)
	await create_timer(1.5).timeout
	var body := sample.to_utf8_buffer()
	main.call("_on_update_response", HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(), body)
	await create_timer(0.3).timeout
	var dlg: Variant = main.get("_update_dialog")
	check(dlg != null, "update dialog created")
	if dlg != null:
		check(bool(dlg.get("visible")), "update dialog visible")
		var label: Variant = main.get("_update_label")
		check(label != null and str(label.get("text")).contains("v1.2.0"), "dialog shows new version")
		check(str(label.get("text")).contains(PhiVersion.VERSION), "dialog shows current version")
		dlg.call("hide")
	# 同じ版では窓は出ない
	main.set("_update_dialog", null)
	var same := "{\"tag_name\":\"v" + PhiVersion.VERSION + "\",\"name\":\"\",\"html_url\":\"\"}"
	main.call("_on_update_response", HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(), same.to_utf8_buffer())
	await create_timer(0.2).timeout
	check(main.get("_update_dialog") == null, "no dialog when up to date")
	# 失敗応答では窓は出ない
	main.call("_on_update_response", HTTPRequest.RESULT_SUCCESS, 404, PackedStringArray(), PackedByteArray())
	await create_timer(0.2).timeout
	check(main.get("_update_dialog") == null, "no dialog on 404")

	# (5) 自動チェックの失敗は一度だけ再試行する (第102段)
	main.set("_update_manual", false)
	main.set("_update_retried", false)
	main.call("_on_update_response", HTTPRequest.RESULT_CANT_CONNECT, 0, PackedStringArray(), PackedByteArray())
	check(bool(main.get("_update_retried")), "auto failure schedules one retry")
	main.call("_on_update_response", HTTPRequest.RESULT_CANT_CONNECT, 0, PackedStringArray(), PackedByteArray())
	check(bool(main.get("_update_retried")), "second failure keeps single retry")
	# 成功したら再試行フラグは戻る
	main.call("_on_update_response", HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(), same.to_utf8_buffer())
	check(not bool(main.get("_update_retried")), "success clears retry flag")

	print("stage40: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)
