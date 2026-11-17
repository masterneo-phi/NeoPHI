extends SceneTree
## 第70段: キャラタブをドラッグで並べ替える (Philly 仕様)。
## _move_tab の並び替えそのものと、ボタンへのマウス入力から
## ドラッグが始まって並びが変わること、少しの動きでは
## 並べ替えないことを見る。

const Main := preload("res://scripts/main.gd")

var _checks := 0
var _failures := 0


func check(cond: bool, label: String) -> void:
	_checks += 1
	if not cond:
		_failures += 1
		print("FAIL: ", label)


func _press(x: float, y: float) -> InputEventMouseButton:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.global_position = Vector2(x, y)
	return ev


func _release(x: float, y: float) -> InputEventMouseButton:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = false
	ev.global_position = Vector2(x, y)
	return ev


func _motion(x: float, y: float) -> InputEventMouseMotion:
	var ev := InputEventMouseMotion.new()
	ev.button_mask = MOUSE_BUTTON_MASK_LEFT
	ev.global_position = Vector2(x, y)
	return ev


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var main: Node = Main.new()
	var iso := ProjectSettings.globalize_path("user://stage70_tabs.ini")
	OS.execute("rm", ["-f", iso])
	main.set("_tab_session_path", "user://stage70_tabs.ini")
	root.add_child(main)
	await process_frame
	await process_frame
	var tab_a: Variant = main.call("_active_tab")
	var tab_b: Variant = main.call("_create_tab")
	var tab_c: Variant = main.call("_create_tab")
	main.call("_activate_tab", tab_a)
	await process_frame
	await process_frame
	var tabs: Array = main.get("_tabs")
	check(tabs.size() == 3 and tabs[0] == tab_a and tabs[2] == tab_c, "three tabs in order")

	# --- _move_tab の並び替え ---
	main.call("_move_tab", tab_c, 0)
	tabs = main.get("_tabs")
	check(tabs[0] == tab_c and tabs[1] == tab_a and tabs[2] == tab_b, "move C to front")
	var entries: Array = main.get("_tab_buttons")
	check(entries[0]["tab"] == tab_c and entries[2]["tab"] == tab_b, "button entries follow")
	var row: Control = main.get("_tab_row")
	check(row.get_child(row.get_child_count() - 1) == main.get("_plus_button"), "plus button stays last")
	check(main.call("_active_tab") == tab_a, "active tab unchanged by reorder")
	check(int(main.get("_active_index")) == 1, "active index follows its tab")
	main.call("_move_tab", tab_c, 2)
	tabs = main.get("_tabs")
	check(tabs[0] == tab_a and tabs[2] == tab_c, "move C back to end")

	# --- ドラッグ操作: C を A の左へ ---
	var buttons: Array = main.get("_tab_buttons")
	var center_a: Vector2 = (buttons[0]["button"] as Button).get_global_rect().get_center()
	var center_c: Vector2 = (buttons[2]["button"] as Button).get_global_rect().get_center()
	main.call("_on_tab_button_gui_input", _press(center_c.x, center_c.y), tab_c)
	main.call("_on_tab_button_gui_input", _motion(center_c.x - 3.0, center_c.y), tab_c)
	tabs = main.get("_tabs")
	check(tabs[2] == tab_c, "small motion does not start a drag")
	main.call("_on_tab_button_gui_input", _motion(center_a.x - 4.0, center_c.y), tab_c)
	tabs = main.get("_tabs")
	check(tabs[0] == tab_c, "drag moves C to the front")
	check(bool(main.get("_tab_dragging")) == true, "drag state on")
	main.call("_on_tab_button_gui_input", _release(center_a.x - 4.0, center_c.y), tab_c)
	check(main.get("_tab_drag_tab") == null, "drag ends on release")
	check((buttons[0]["button"] as Button).modulate.a == 1.0, "drag visual restored")

	print("test_stage70: ", _checks, " checks, ", _failures, " failures")
	quit(1 if _failures > 0 else 0)
