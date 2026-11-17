extends SceneTree
## 第61段: 大量行バーストでも切断されないための強化。
## (1) 行処理は時間でも区切る (重い表示で行数が少なくても
##     フレームが伸びない)。(2) 受信中のログ行はまとめて
##     1 回で表示する。(3) 未処理行が多い間はログ全体の
##     描き直しを後回しにする。

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
	# (1) 時間予算 0 では、16 行ごとの確認で必ず止まる。
	var session := PhiSession.new()
	session.process_budget_msec = 0
	var pending: Array[PackedByteArray] = []
	for i in range(100):
		pending.append(Cp932.encode("バースト行 %d" % i))
	session.set("_pending_lines", pending)
	session.call("_process_pending_lines")
	var left: int = session.pending_line_count()
	check(left >= 84, "time budget stops processing (left %d)" % left)
	check(left < 100, "some lines processed")
	# 予算を戻せば全部捌ける。
	session.process_budget_msec = 60000
	while session.has_pending_lines():
		session.call("_process_pending_lines")
	check(not session.has_pending_lines(), "queue drains with budget restored")
	# (2)+(3) タブ側: バッチ蓄積と描き直しの後回し。
	var ps := load("res://main.tscn") as PackedScene
	var main: Node = ps.instantiate()
	root.add_child(main)
	await create_timer(0.6).timeout
	var tab: Variant = main.call("_active_tab")
	tab.set("_log_batching", true)
	tab.log_message("log", "バッチ行その1")
	tab.log_message("system", "バッチ行その2")
	tab.set("_log_batching", false)
	check(not tab.log_view.get_parsed_text().contains("バッチ行その1"), "batched lines not shown yet")
	tab.call("_flush_log_batch")
	check(tab.log_view.get_parsed_text().contains("バッチ行その1"), "batch flushed line 1")
	check(tab.log_view.get_parsed_text().contains("バッチ行その2"), "batch flushed line 2")
	# (3) 未処理行が 200 を超えたら描き直しは後回しになる。
	var backlog: Array[PackedByteArray] = []
	for i in range(300):
		backlog.append(Cp932.encode("滞留行 %d" % i))
	tab.session.set("_pending_lines", backlog)
	tab.call("_queue_log_rebuild")
	await process_frame
	await process_frame
	check(bool(tab.get("_img_rebuild_queued")), "rebuild deferred while flooded")
	var empty_backlog: Array[PackedByteArray] = []
	tab.session.set("_pending_lines", empty_backlog)
	await create_timer(0.7).timeout
	check(not bool(tab.get("_img_rebuild_queued")), "rebuild runs after drain")
	main.queue_free()

	print("stage61: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)
