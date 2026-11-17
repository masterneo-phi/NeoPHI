extends SceneTree
## 第85段のテスト: 送受信トレースが有効な間、届いたキー
## イベントも wire ログへ残ること (Windows の IME 経由の
## キーが、実際には何として届いているかを切り分けるため)。
##
## 使い方: godot --headless --path . -s tests/test_stage85.gd
## 終了コード 0 = 全一致、1 = 不一致あり。

const Main := preload("res://scripts/main.gd")

var _checks := 0
var _failures := 0


func check(cond: bool, label: String) -> void:
	_checks += 1
	if not cond:
		_failures += 1
		printerr("FAIL: ", label)


func _initialize() -> void:
	call_deferred("_run")


func _key(keycode: Key) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.keycode = keycode
	ev.physical_keycode = keycode
	ev.pressed = true
	return ev


func _run() -> void:
	var main: Node = Main.new()
	var iso := ProjectSettings.globalize_path("user://stage85_tabs.ini")
	OS.execute("rm", ["-f", iso])
	main.set("_tab_session_path", "user://stage85_tabs.ini")
	var isoc := ProjectSettings.globalize_path("user://stage85_cfg.ini")
	OS.execute("rm", ["-f", isoc])
	main.set("_config_path", "user://stage85_cfg.ini")
	root.add_child(main)
	await process_frame
	await process_frame
	var tab: Variant = main.call("_active_tab")
	var session: PhiSession = tab.session
	# トレース off の間は記録されない。
	main._input(_key(KEY_SPACE))
	check(session.wire_trace_lines.is_empty(), "s85 no key trace when disabled")
	session.wire_trace = true
	main._input(_key(KEY_SPACE))
	check(session.wire_trace_lines.size() == 1, "s85 one key traced")
	if session.wire_trace_lines.size() == 1:
		check(session.wire_trace_lines[0].contains("KEY"), "s85 key line kind")
		check(session.wire_trace_lines[0].contains("code=Space"), "s85 space code recorded")
	main._input(_key(KEY_PAUSE))
	check(session.wire_trace_lines.size() == 2, "s85 second key traced")
	if session.wire_trace_lines.size() == 2:
		check(session.wire_trace_lines[1].contains("code=Pause"), "s85 pause code recorded")
	print("test_stage85: ", _checks, " checks, ", _failures, " failures")
	quit(1 if _failures > 0 else 0)
