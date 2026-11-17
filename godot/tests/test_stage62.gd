extends SceneTree
## 第62段: 掲示板フラッド対策の第3弾と、フロート窓の初期位置。
## (1) 表示はキュー制にし、1回のフラッシュは行数 (40) と
##     時間 (6ms) で区切る。残りは次のフレームで出す。
## (2) 表示待ちがある間は、後から来た行も順番どおり後ろに
##     並ぶ。(3) drain_socket は未接続でも安全な無動作。
## (4) 描き直しで表示行数カウンタが記録の行数に戻り、
##     表示待ちは二重に出ない。(5) コマンドパレットの初期
##     位置は右上 (保持値があればそちら)。リストは左上のまま。

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
	await create_timer(0.6).timeout
	var tab: Variant = main.call("_active_tab")
	main.call("_activate_tab", tab)

	# (1) 300 行をバッチで入れる → 全部キューに入り、未表示。
	tab.set("_log_batching", true)
	for i in range(300):
		tab.log_message("log", "フラッド行 %d" % i)
	tab.set("_log_batching", false)
	check(int(tab.call("log_display_backlog")) == 300, "all 300 lines queued")
	check(not tab.log_view.get_parsed_text().contains("フラッド行 0"), "nothing shown before flush")
	# 1 回のフラッシュでは上限 (40 行) までしか出ない。
	tab.call("_flush_log_batch")
	var shown: String = tab.log_view.get_parsed_text()
	check(shown.contains("フラッド行 0"), "first line shown after one flush")
	check(not shown.contains("フラッド行 299"), "last line not shown yet")
	check(int(tab.call("log_display_backlog")) == 260, "backlog reduced by cap")
	# (2) 表示待ちがある間は、バッチ外の行も後ろに並ぶ。
	tab.log_message("log", "割り込み行")
	check(int(tab.call("log_display_backlog")) == 261, "unbatched line queues behind backlog")
	check(not tab.log_view.get_parsed_text().contains("割り込み行"), "queued line not shown early")
	# 全部出し切ると、順番どおり最後に割り込み行が来る。
	while int(tab.call("log_display_backlog")) > 0:
		tab.call("_flush_log_batch")
	var full: String = tab.log_view.get_parsed_text()
	check(full.contains("フラッド行 299"), "last flood line shown after drain")
	check(full.find("フラッド行 299") < full.find("割り込み行"), "order preserved")
	check(full.count("フラッド行 150") == 1, "no duplicated lines")

	# (3) drain_socket は未接続 (idle) でも安全。
	var session := PhiSession.new()
	session.drain_socket()
	check(session.pending_line_count() == 0, "drain_socket no-op when idle")

	# (4) 描き直し: カウンタが記録の行数に戻る。
	var view_lines: int = int(tab.get("_log_view_lines"))
	check(view_lines > 0, "view line counter tracks renders (%d)" % view_lines)
	tab.call("_rebuild_log_view")
	check(int(tab.get("_log_view_lines")) == (tab.get("_log_lines") as Array).size(),
		"counter reset to record size after rebuild")
	check(int(tab.call("log_display_backlog")) == 0, "backlog cleared by rebuild")
	check(tab.log_view.get_parsed_text().count("フラッド行 150") == 1, "no duplication after rebuild")

	# (5) ツールバーの初期位置: 保持値なしなら右上。
	var cfg: Variant = tab.get("_config")
	cfg.toolbar_pos = Vector2(-1, -1)
	tab.map_view.size = Vector2(800, 600)
	tab.call("_fit_toolbar_panel")
	var home: Vector2 = tab.call("_toolbar_home_position")
	var panel_w: float = (tab.get("_toolbar_panel") as Control).size.x
	check(home.y == 8.0, "toolbar home is top (y=8)")
	check(home.x == 800.0 - panel_w - 8.0,
		"toolbar home is right (x=%f panel %f)" % [home.x, panel_w])
	# 保持値があればそちらが優先。
	cfg.toolbar_pos = Vector2(100, 50)
	check((tab.call("_toolbar_home_position") as Vector2) == Vector2(100, 50),
		"saved toolbar position wins")
	cfg.toolbar_pos = Vector2(-1, -1)
	# リストパネルの初期位置は左上のまま。
	check((tab.get("_list_panel") as Control).position == Vector2(8, 8),
		"list panel stays top-left")
	main.queue_free()

	print("stage62: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)
