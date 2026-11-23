extends SceneTree
## 第105段のテスト: 窓のドラッグ/大きさ変更の間は、後ろの地図の
## キャラがマウス長押し移動しない。フロート窓の上の押しは
## 長押し移動を始めず、ドラッグ中は繰り返し送信も止まる。
##
## 使い方: godot --headless --path . -s tests/test_stage105.gd
## 終了コード 0 = 全一致、1 = 不一致あり。

const Main := preload("res://scripts/main.gd")

var _failures := 0
var _checks := 0


func check(cond: bool, label: String) -> void:
	_checks += 1
	if not cond:
		_failures += 1
		printerr("FAIL: ", label)


func check_eq(a: Variant, b: Variant, label: String) -> void:
	_checks += 1
	if a != b:
		_failures += 1
		printerr("FAIL: ", label, " (got ", a, ", want ", b, ")")


func _press(pos: Vector2) -> InputEventMouseButton:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = pos
	ev.global_position = pos
	return ev


func _initialize() -> void:
	_run()


func _run() -> void:
	var dir := DirAccess.open("user://")
	if dir != null:
		for f in ["stage105_tabs.ini", "stage105_main.ini"]:
			if dir.file_exists(f):
				dir.remove(f)
	var main: Node = Main.new()
	main.set("_tab_session_path", "user://stage105_tabs.ini")
	main.set("_config_path", "user://stage105_main.ini")
	root.add_child(main)
	await process_frame
	await process_frame
	var tab: PhiCharacter = main.call("_active_tab")
	main.call("_activate_tab", tab)
	var config: PhiConfig = main.get("_config")
	tab.map_view.size = Vector2(1380, 700)
	config.ui_style = "new"
	tab.apply_ui_style()
	var log_float := tab.get("_log_float") as PanelContainer
	var input_float := tab.get("_input_float") as PanelContainer
	# (1) フロート窓の上は「窓の上」、地図の開けた場所は違う
	var in_log := log_float.global_position + log_float.size * 0.5
	var in_input := input_float.global_position + input_float.size * 0.5
	check(bool(tab.call("_over_float_panel", in_log)), "s105 over log float")
	check(bool(tab.call("_over_float_panel", in_input)), "s105 over input float")
	check(not bool(tab.call("_over_float_panel", Vector2(30, 300))), "s105 open map is not float")
	# (2) フロート窓の上の押しでは長押し移動が始まらない
	tab.handle_mouse_button(_press(in_log))
	check(not bool(tab.get("_mouse_held")), "s105 press on log float starts no hold")
	tab.handle_mouse_button(_press(in_input))
	check(not bool(tab.get("_mouse_held")), "s105 press on input float starts no hold")
	# (3) ドラッグ中は繰り返し送信が止まる (last_repeat が進まない)
	tab.set("_mouse_held", true)
	tab.set("_float_drag_panel", log_float)
	tab.call("_mouse_repeat_send_if_ready")
	check_eq(int(tab.get("_mouse_last_repeat")), 0, "s105 no repeat during float drag")
	tab.set("_float_drag_panel", null)
	tab.set("_float_resize_panel", input_float)
	tab.call("_mouse_repeat_send_if_ready")
	check_eq(int(tab.get("_mouse_last_repeat")), 0, "s105 no repeat during float resize")
	tab.set("_float_resize_panel", null)
	# (4) ドラッグ開始で長押しは解除される (帯のプレス)
	tab.set("_mouse_held", true)
	var band := tab.get("_log_float_band") as PanelContainer
	var bev := InputEventMouseButton.new()
	bev.button_index = MOUSE_BUTTON_LEFT
	bev.pressed = true
	bev.position = Vector2(20, 5)
	bev.global_position = band.global_position + Vector2(20, 5)
	tab.call("_on_float_band_gui_input", bev, log_float)
	check(not bool(tab.get("_mouse_held")), "s105 band press clears hold")
	check(tab.get("_float_drag_panel") == log_float, "s105 band press starts drag")
	tab.call("_end_float_drag")
	# (4b) Talk ボタンの上の押しでも長押し移動は始まらない
	var talk := tab.get("_talk_button") as Button
	check(talk != null, "s105 talk button exists")
	if talk != null:
		var on_talk := talk.global_position + talk.size * 0.5
		check(bool(tab.call("_over_talk_button", on_talk)), "s105 over talk button")
		tab.handle_mouse_button(_press(on_talk))
		check(not bool(tab.get("_mouse_held")), "s105 press on talk starts no hold")
	# (5) 旧スタイルではフロート判定は効かない
	config.ui_style = "old"
	tab.apply_ui_style()
	check(not bool(tab.call("_over_float_panel", in_log)), "s105 old style no float hit")

	print("test_stage105: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)
