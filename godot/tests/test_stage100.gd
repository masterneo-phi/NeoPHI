extends SceneTree
## 第100段のテスト: コマンドパレットの自動整列。列数を
## 指定するとグループを詰めて (大きなグループは折って)
## その列数に収め、右下の隅のドラッグで幅から列数を
## 変えられ、ダブルクリックで既定の並びに戻る。列数は
## 設定 [Disp] ToolbarCols に残る (利用者の要望)。
##
## 使い方: godot --headless --path . -s tests/test_stage100.gd
## 終了コード 0 = 全一致、1 = 不一致あり。

const Main := preload("res://scripts/main.gd")

var _failures := 0
var _checks := 0
var _main: Node = null
var _tab: PhiCharacter = null


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


func _row_sizes() -> Array:
	var rows := _tab.get("_toolbar_rows_box") as VBoxContainer
	var sizes: Array = []
	for i in range(1, rows.get_child_count()):
		sizes.append(rows.get_child(i).get_child_count())
	return sizes


func _total_buttons() -> int:
	var n := 0
	for s in _row_sizes():
		n += int(s)
	return n


func _press(local: Vector2, double_click: bool = false) -> InputEventMouseButton:
	var panel := _tab.get("_toolbar_panel") as Control
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.double_click = double_click
	ev.position = local
	ev.global_position = panel.global_position + local
	return ev


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var main = Main.new()
	for p in ["user://stage100_tabs.ini", "user://stage100_cfg.ini"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	main.set("_tab_session_path", "user://stage100_tabs.ini")
	main.set("_config_path", "user://stage100_cfg.ini")
	root.add_child(main)
	_main = main
	await process_frame
	await process_frame
	_tab = main.call("_active_tab")
	await process_frame
	var panel := _tab.get("_toolbar_panel") as PanelContainer
	check(panel != null, "s100 panel exists")
	var config = main.get("_config")
	# (1) 既定は従来どおりグループごとに1段。
	check_eq(_row_sizes(), [2, 8, 5, 6, 1, 3], "s100 default rows")
	var w0 := panel.size.x
	var h0 := panel.size.y
	# (2) 3列にすると全段が3以下になり、横は狭く縦は長く。
	config.toolbar_cols = 3
	_tab._layout_toolbar()
	_tab._fit_toolbar_panel()
	var sizes3 := _row_sizes()
	check(sizes3.all(func(s): return int(s) <= 3), "s100 3col rows <= 3: " + str(sizes3))
	check_eq(_total_buttons(), 25, "s100 3col keeps all buttons")
	check(panel.size.x < w0, "s100 3col narrower")
	check(panel.size.y > h0, "s100 3col taller")
	# (3) 24列 (横長)。最後のグループは丸ごと次の段へ。
	config.toolbar_cols = 24
	_tab._layout_toolbar()
	_tab._fit_toolbar_panel()
	check_eq(_row_sizes(), [22, 3], "s100 24col rows keep last group whole")
	check(panel.size.y < h0, "s100 24col shorter")
	# (4) 0 に戻すと従来の並び。
	config.toolbar_cols = 0
	_tab._layout_toolbar()
	_tab._fit_toolbar_panel()
	check_eq(_row_sizes(), [2, 8, 5, 6, 1, 3], "s100 reset rows")
	# (5) 右下の隅を左へドラッグすると列数が減る。
	var grip := panel.size - Vector2(4, 4)
	_tab._on_toolbar_panel_gui_input(_press(grip))
	check(bool(_tab.get("_toolbar_resizing")), "s100 grip starts resize")
	var pitch := _tab._toolbar_button_pitch()
	var motion := InputEventMouseMotion.new()
	motion.position = panel.global_position + grip - Vector2(pitch * 3.0, 0)
	_tab.handle_mouse_motion(motion)
	var cols: int = config.toolbar_cols
	check(cols >= 1 and cols < 8, "s100 drag narrows cols: " + str(cols))
	check(_row_sizes().all(func(s): return int(s) <= cols), "s100 drag rows fit cols")
	_tab._end_toolbar_drag()
	check(not bool(_tab.get("_toolbar_resizing")), "s100 resize ends")
	# (6) 隅のダブルクリックで既定に戻る。
	_tab._on_toolbar_panel_gui_input(_press(panel.size - Vector2(4, 4), true))
	check_eq(config.toolbar_cols, 0, "s100 double click resets cols")
	check_eq(_row_sizes(), [2, 8, 5, 6, 1, 3], "s100 double click rows")
	# (7) 列数は ini に残る。
	config.toolbar_cols = 5
	config.save_file("user://stage100_cfg.ini")
	var loaded := PhiConfig.new()
	loaded.load_file("user://stage100_cfg.ini")
	check_eq(loaded.toolbar_cols, 5, "s100 cols roundtrip")
	print("test_stage100: ", _checks, " checks, ", _failures, " failures")
	quit(1 if _failures > 0 else 0)
