extends SceneTree
## 第89段のテスト: 発言を送信しても入力欄のフォーカスは
## 残り、連続して発言できる (Philly と同じ)。移動モードへ
## 戻るのは Esc / Tab / 地図クリックの役割。
##
## 使い方: godot --headless --path . -s tests/test_stage89.gd
## 終了コード 0 = 全一致、1 = 不一致あり。

const Main := preload("res://scripts/main.gd")

var _checks := 0
var _failures := 0
var _tab: Variant = null


func check(cond: bool, label: String) -> void:
	_checks += 1
	if not cond:
		_failures += 1
		printerr("FAIL: ", label)


func _initialize() -> void:
	call_deferred("_run")


func _queue() -> Array:
	return _tab.session.get("_send_queue")


func _run() -> void:
	var main: Node = Main.new()
	var iso := ProjectSettings.globalize_path("user://stage89_tabs.ini")
	OS.execute("rm", ["-f", iso])
	main.set("_tab_session_path", "user://stage89_tabs.ini")
	var isoc := ProjectSettings.globalize_path("user://stage89_cfg.ini")
	OS.execute("rm", ["-f", isoc])
	main.set("_config_path", "user://stage89_cfg.ini")
	root.add_child(main)
	await process_frame
	await process_frame
	_tab = main.call("_active_tab")
	var tab: Variant = _tab
	tab.input_box.grab_focus()
	check(tab.input_box.has_focus(), "s89 input focused")
	tab.input_box.text = "こんにちは"
	tab.submit_input()
	check(_queue().size() == 1, "s89 first speech queued")
	check(tab.input_box.has_focus(), "s89 focus kept after first send")
	# 連続発言: そのまま次の文を打って送れる。
	tab.input_box.text = "こんにちは\nつづきです"
	tab.submit_input()
	check(_queue().size() == 2, "s89 second speech queued")
	check(tab.input_box.has_focus(), "s89 focus kept after second send")
	# Esc で移動モードへ戻れる (従来どおり)。
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.physical_keycode = KEY_ESCAPE
	esc.pressed = true
	check(tab.handle_key(esc), "s89 esc handled")
	check(not tab.input_box.has_focus(), "s89 esc releases focus")
	print("test_stage89: ", _checks, " checks, ", _failures, " failures")
	quit(1 if _failures > 0 else 0)
