extends SceneTree
## 第38段: ログ行頭の時刻 [HH:MM] を Philly 風に色付きで出す。
## 色はスキンの Log.css の .class_time (無ければ teal #008080)、
## 大きさは本文の 90%。記録 (コピー・保存用) の display は従来どおり
## 時刻なしのまま。

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
	await create_timer(1.5).timeout
	var tab: Node = main.call("_create_tab")
	main.call("_activate_tab", tab)
	await create_timer(0.3).timeout

	# (1) 既定 (teal) の接頭辞 BBCode
	var seg := str(tab.call("time_prefix_bbcode", "21:41"))
	check(seg.contains("[color=#008080]"), "time prefix uses teal by default: " + seg)
	check(seg.contains("[lb]21:41[rb] "), "time prefix keeps [HH:MM] text")
	check(seg.ends_with("[/color]") or seg.ends_with("[/font_size]"), "time prefix closes tags")

	# (2) スキン色があればそれを使う
	tab.set("_time_color", Color(1, 0, 0))
	var seg2 := str(tab.call("time_prefix_bbcode", "09:05"))
	check(seg2.contains("[color=#ff0000]"), "time prefix uses skin color: " + seg2)
	tab.set("_time_color", null)

	# (3) 本文 20px なら時刻は 90% の 18px
	tab.log_view.add_theme_font_size_override("font_size", 20)
	var seg3 := str(tab.call("time_prefix_bbcode", "21:41"))
	check(seg3.contains("[font_size=18]"), "time prefix is 90% size: " + seg3)

	# (4) 実ログ: 表示には色付き時刻、記録には入らない
	var cfg = tab.get("_config")
	cfg.log_disp_time = true
	tab.call("log_message", "log", "DM > テスト行です")
	await create_timer(0.2).timeout
	var parsed: String = tab.log_view.get_parsed_text()
	check(parsed.contains("] DM > テスト行です"), "parsed log shows [HH:MM] prefix")
	check(parsed.begins_with("[") or parsed.contains("\n["), "parsed log starts with bracket")
	# 色タグは書式として消費され、時刻の文字だけが残る (タグが壊れて
	# いれば [color=...] が文字として見えてしまう)。
	check(not parsed.contains("[color="), "color tag consumed as formatting")
	var lines: Array = tab.get("_log_lines")
	check(not lines.is_empty(), "log line recorded")
	if not lines.is_empty():
		check(not str(lines[lines.size() - 1].get("display", "")).contains(":4"), "recorded display has no time")
		check(str(lines[lines.size() - 1].get("display", "")).contains("テスト行です"), "recorded display keeps body")

	# (5) 時刻 off のときは接頭辞なし
	cfg.log_disp_time = false
	tab.call("log_message", "log", "DM > 時刻なし行")
	await create_timer(0.2).timeout
	var parsed2: String = tab.log_view.get_parsed_text()
	check(parsed2.contains("DM > 時刻なし行"), "log appended without time")
	check(not parsed2.contains("] DM > 時刻なし行"), "no [HH:MM] when disabled")

	print("test_stage38: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)
