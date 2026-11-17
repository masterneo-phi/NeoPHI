extends SceneTree
## 第71段: 洪水の間はログ表示を凍結する。間引き (第69段) でも
## 表示欄は育ち続け、切り詰めの描き直しが繰り返し走って受信を
## 滞らせていた。受信中はログ欄へ出さず記録と自動保存だけに
## 残し、進捗を 1 秒に 1 行だけ出す。捌けた後に記録から
## 描き直して揃える。

const Main := preload("res://scripts/main.gd")

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
	var main: Node = Main.new()
	var iso := ProjectSettings.globalize_path("user://stage71_tabs.ini")
	OS.execute("rm", ["-f", iso])
	main.set("_tab_session_path", "user://stage71_tabs.ini")
	var isoc := ProjectSettings.globalize_path("user://stage71_cfg.ini")
	OS.execute("rm", ["-f", isoc])
	main.set("_config_path", "user://stage71_cfg.ini")
	root.add_child(main)
	await process_frame
	await process_frame
	var tab: Variant = main.call("_active_tab")
	var tsession: Variant = tab.get("session")
	var log_view: Variant = tab.get("log_view")

	# --- (1) 洪水中は表示が凍結し、記録にだけ残る ---
	var pending: Array[PackedByteArray] = []
	for i in 400:
		pending.append("dummy".to_ascii_buffer())
	tsession.set("_pending_lines", pending)
	check(bool(tab.call("_flooding")) == true, "flooding detected")
	var rec_base := (tab.get("_log_lines") as Array).size()
	var view_base := int(tab.get("_log_view_lines"))
	tab.set("_log_batching", true)
	for i in range(1, 51):
		tab.call("log_message", "log", "F%04d" % i)
	tab.set("_log_batching", false)
	tab.call("_flush_log_batch")
	check((tab.get("_log_lines") as Array).size() == rec_base + 50,
		"record keeps flood lines")
	check(int(tab.call("log_display_backlog")) == 0, "batch discarded while flooding")
	check(bool(tab.get("_view_gap")) == true, "freeze marks the gap")
	check(int(tab.get("_flood_received")) == 50, "flood counter counts discarded lines")
	check(not log_view.get_parsed_text().contains("F0050"),
		"flood lines not rendered during flood")
	check(log_view.get_parsed_text().contains("受信中"), "progress line shown")
	check(int(tab.get("_log_view_lines")) == view_base + 1,
		"only the progress line was added")

	# --- (2) 進捗行は 1 秒に 1 行まで ---
	tab.call("_flush_log_batch")
	check(int(tab.get("_log_view_lines")) == view_base + 1,
		"progress line throttled")
	tab.set("_flood_progress_at", 0)
	tab.call("_flush_log_batch")
	check(int(tab.get("_log_view_lines")) == view_base + 2,
		"progress line again after 1s")

	# --- (3) 捌けたら記録から描き直して揃う ---
	var empty_pending: Array[PackedByteArray] = []
	tsession.set("_pending_lines", empty_pending)
	await process_frame
	await process_frame
	check(bool(tab.get("_view_gap")) == false, "gap healed after flood")
	check(log_view.get_parsed_text().contains("F0001"), "healed view has first flood line")
	check(log_view.get_parsed_text().contains("F0050"), "healed view has last flood line")
	check(not log_view.get_parsed_text().contains("受信中"),
		"progress lines gone after heal")

	# --- (4) 通常時は従来どおりすぐ表示される ---
	tab.set("_log_batching", true)
	for i in range(1, 6):
		tab.call("log_message", "log", "N%d" % i)
	tab.set("_log_batching", false)
	tab.call("_flush_log_batch")
	check(log_view.get_parsed_text().contains("N5"), "normal lines render at once")
	check(int(tab.get("_flood_received")) == 0, "flood counter reset")

	print("test_stage71: ", _checks, " checks, ", _failures, " failures")
	quit(1 if _failures > 0 else 0)
