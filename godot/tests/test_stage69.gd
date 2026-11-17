extends SceneTree
## 第69段: 洪水時の表示の間引き。ログ欄が育ちすぎると表示が
## 重くなって受信が滞り、サーバ側の都合で切断される。そこで
## (1) 表示欄が上限を超えたら表示待ちの古い行を表示から
## 間引く (記録と自動保存には全行残る)、(2) 捌けた後に記録
## から描き直して表示を揃える、(3) 自動保存の書き出しを
## 洪水中は大きめにまとめる。

const Main := preload("res://scripts/main.gd")

var _checks := 0
var _failures := 0


func check(cond: bool, label: String) -> void:
	_checks += 1
	if not cond:
		_failures += 1
		print("FAIL: ", label)


func _entry(text: String) -> Dictionary:
	return {"display": text, "raw": text, "prefix": "",
		"channel": "log", "time": "", "imgs": []}


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var main: Node = Main.new()
	var iso := ProjectSettings.globalize_path("user://stage69_tabs.ini")
	OS.execute("rm", ["-f", iso])
	main.set("_tab_session_path", "user://stage69_tabs.ini")
	var isoc := ProjectSettings.globalize_path("user://stage69_cfg.ini")
	OS.execute("rm", ["-f", isoc])
	main.set("_config_path", "user://stage69_cfg.ini")
	root.add_child(main)
	await process_frame
	await process_frame
	var tab: Variant = main.call("_active_tab")
	var tsession: Variant = tab.get("session")
	var log_view: Variant = tab.get("log_view")

	# --- (1b) 表示待ち自体の上限: 最新側だけ残す ---
	var big: Array = []
	for i in range(1, 4501):
		big.append(_entry("H%04d" % i))
	tab.set("_log_batch", big)
	tab.set("_log_view_lines", 0)
	tab.call("_flush_log_batch")
	check(int(tab.call("log_display_backlog")) == 1800, "hard cap keeps newest 2000, flushes 200")
	check(bool(tab.get("_view_gap")) == true, "hard cap marks the gap")
	tab.set("_log_batch", [])
	tab.set("_view_gap", false)

	# --- (1a) 表示欄が上限超えなら古い表示待ちを間引く ---
	# 受信中 (_log_batching) と同じ条件で entry を溜める。
	tab.set("_log_view_lines", 2600)
	var base_lines := (tab.get("_log_lines") as Array).size()
	tab.set("_log_batching", true)
	for i in range(1, 901):
		tab.call("log_message", "log", "L%04d" % i)
	tab.set("_log_batching", false)
	check((tab.get("_log_lines") as Array).size() == base_lines + 900, "record keeps all lines")
	tab.call("_flush_log_batch")
	check(bool(tab.get("_view_gap")) == true, "view cap marks the gap")
	check(int(tab.call("log_display_backlog")) == 360, "batch thinned to newest 400, 40 flushed")
	check(not log_view.get_parsed_text().contains("L0450"), "dropped line not in view yet")
	# 残りを全部出す
	for k in 40:
		if int(tab.call("log_display_backlog")) == 0:
			break
		tab.call("_flush_log_batch")
	check(int(tab.call("log_display_backlog")) == 0, "batch drained")

	# --- (2) 捌けたら記録から描き直して揃う ---
	await process_frame
	await process_frame
	check(bool(tab.get("_view_gap")) == false, "gap healed after flood")
	check(log_view.get_parsed_text().contains("L0450"), "healed view has the dropped line")
	check(log_view.get_parsed_text().contains("L0900"), "healed view has the last line")

	# --- (3) 自動保存は洪水中 100 行で書き出さない ---
	var cfg: Variant = tab.get("_config")
	cfg.log_auto_save = true
	var pending: Array[PackedByteArray] = []
	for i in 400:
		pending.append("dummy".to_ascii_buffer())
	tsession.set("_pending_lines", pending)
	check(bool(tab.call("_flooding")) == true, "flooding detected")
	for i in 150:
		tab.call("log_message", "log", "S%03d" % i)
	check((tab.get("_save_pending") as Array).size() == 150, "no autosave flush at 100 while flooding")
	var empty_pending: Array[PackedByteArray] = []
	tsession.set("_pending_lines", empty_pending)
	tab.call("log_message", "log", "S-end")
	check((tab.get("_save_pending") as Array).size() == 0, "autosave flushes once flood ends")

	print("test_stage69: ", _checks, " checks, ", _failures, " failures")
	quit(1 if _failures > 0 else 0)
