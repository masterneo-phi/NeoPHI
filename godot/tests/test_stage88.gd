extends SceneTree
## 第88段のテスト: IME の確定文字は物理キー名より優先する。
## Windows の IME は全角スペースの確定を physical=Pause で
## 届けるため、物理キー優先だと強制切断と取り違えていた
## (実測: wire ログ KEY kc=8388607 phys=4194313 uni=12288)。
##
## 使い方: godot --headless --path . -s tests/test_stage88.gd
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


func _run() -> void:
	# 単位: コード名の決定。
	check(PhiKeys.code_name_for(KEY_NONE, KEY_PAUSE, 0x3000) == "Space", "s88 fullwidth space beats pause physical")
	check(PhiKeys.code_name_for(KEY_PAUSE, KEY_PAUSE, 0) == "Pause", "s88 real pause still pause")
	check(PhiKeys.code_name_for(KEY_NONE, KEY_PAUSE, 0x20) == "Space", "s88 ascii space char beats pause physical")
	check(PhiKeys.code_name_for(KEY_W, KEY_W, 0x77) == "KeyW", "s88 letter w")
	check(PhiKeys.code_name_for(KEY_NONE, KEY_NONE, 0x3042) == "", "s88 kana char has no key name (falls back, empty)")
	check(PhiKeys.code_name_for(KEY_UP, KEY_UP, 0) == "ArrowUp", "s88 arrow unaffected")
	# 統合: Main._input に実測イベントを通し、トレースの
	# code が Space になること (Pause なら切断経路に入る)。
	var main: Node = Main.new()
	var iso := ProjectSettings.globalize_path("user://stage88_tabs.ini")
	OS.execute("rm", ["-f", iso])
	main.set("_tab_session_path", "user://stage88_tabs.ini")
	var isoc := ProjectSettings.globalize_path("user://stage88_cfg.ini")
	OS.execute("rm", ["-f", isoc])
	main.set("_config_path", "user://stage88_cfg.ini")
	root.add_child(main)
	await process_frame
	await process_frame
	var tab: Variant = main.call("_active_tab")
	var session: PhiSession = tab.session
	session.wire_trace = true
	var ev := InputEventKey.new()
	ev.keycode = 8388607 as Key
	ev.physical_keycode = KEY_PAUSE
	ev.unicode = 0x3000
	ev.pressed = true
	main._input(ev)
	check(session.wire_trace_lines.size() == 1, "s88 key traced once")
	if session.wire_trace_lines.size() == 1:
		check(session.wire_trace_lines[0].contains("code=Space"), "s88 main resolves commit to Space")
	print("test_stage88: ", _checks, " checks, ", _failures, " failures")
	quit(1 if _failures > 0 else 0)
