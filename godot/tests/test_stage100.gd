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
	check_eq(_row_sizes(), [2, 8, 5, 6, 1, 3, 7], "s100 default rows")
	var w0 := panel.size.x
	var h0 := panel.size.y
	# (2) 3列にすると全段が3以下になり、横は狭く縦は長く。
	config.toolbar_cols = 3
	_tab._layout_toolbar()
	_tab._fit_toolbar_panel()
	var sizes3 := _row_sizes()
	check(sizes3.all(func(s): return int(s) <= 3), "s100 3col rows <= 3: " + str(sizes3))
	check_eq(_total_buttons(), 32, "s100 3col keeps all buttons")
	check(panel.size.x < w0, "s100 3col narrower")
	check(panel.size.y > h0, "s100 3col taller")
	# (3) 24列 (横長)。最後のグループは丸ごと次の段へ。
	config.toolbar_cols = 24
	_tab._layout_toolbar()
	_tab._fit_toolbar_panel()
	check_eq(_row_sizes(), [22, 10], "s100 24col rows keep last group whole")
	check(panel.size.y < h0, "s100 24col shorter")
	# (4) 0 に戻すと従来の並び。
	config.toolbar_cols = 0
	_tab._layout_toolbar()
	_tab._fit_toolbar_panel()
	check_eq(_row_sizes(), [2, 8, 5, 6, 1, 3, 7], "s100 reset rows")
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
	check_eq(_row_sizes(), [2, 8, 5, 6, 1, 3, 7], "s100 double click rows")
	# (7) 列数は ini に残る。
	config.toolbar_cols = 5
	config.save_file("user://stage100_cfg.ini")
	var loaded := PhiConfig.new()
	loaded.load_file("user://stage100_cfg.ini")
	check_eq(loaded.toolbar_cols, 5, "s100 cols roundtrip")
	# (8) アイコンサイズの設定がボタンへ反映され、ini に残る。
	# メニューフォントサイズも ini に残る。アイコンはボタンの
	# 大きさに伸縮するので、絵だけでなくボタンの最小サイズと
	# パネルも大きくならなければならない (0.5.20 の実機報告)。
	# (7) で列数を変えただけの状態ではレイアウトと設定が
	# ずれていて大きさの比較ができないので、一度そろえる。
	config.toolbar_cols = 0
	_tab._layout_toolbar()
	_tab._fit_toolbar_panel()
	var panel_before := panel.size
	var btn_before := 0.0
	for b in _tab.get("_toolbar_buttons"):
		var btn0 := b as Button
		if btn0.icon != null:
			btn_before = btn0.get_combined_minimum_size().x
			break
	config.toolbar_icon_size = 48
	_tab.refresh_toolbar_icon_size()
	var icon_checked := false
	for b in _tab.get("_toolbar_buttons"):
		var btn := b as Button
		if btn.icon != null:
			check_eq(btn.icon.get_width(), 48, "s100 icon size 48")
			check(btn.get_combined_minimum_size().x >= 48.0, "s100 button grows with icon")
			icon_checked = true
			break
	check(icon_checked, "s100 icon button exists")
	check(panel.size.x > panel_before.x, "s100 panel grows with icon")
	config.toolbar_icon_size = 0
	_tab.refresh_toolbar_icon_size()
	for b in _tab.get("_toolbar_buttons"):
		var btn := b as Button
		if btn.icon != null:
			check_eq(btn.get_combined_minimum_size().x, btn_before, "s100 button size restored")
			break
	config.menu_font_size = 30
	config.toolbar_icon_size = 40
	config.save_file("user://stage100_cfg.ini")
	var loaded2 := PhiConfig.new()
	loaded2.load_file("user://stage100_cfg.ini")
	check_eq(loaded2.menu_font_size, 30, "s100 menu font roundtrip")
	check_eq(loaded2.toolbar_icon_size, 40, "s100 icon size roundtrip")
	# (9) アイコンを最大にすると既定の並びでは地図より広く
	# なるが、収まる列数へ組み直されて地図の幅に収まり、
	# 移動も形変え (縦長横長) もできる (0.5.21 の実機報告)。
	var map_view := _tab.get("map_view") as Control
	config.toolbar_cols = 0
	config.toolbar_icon_size = 64
	_tab.refresh_toolbar_icon_size()
	check(panel.size.x <= map_view.size.x, "s100 big icon panel fits map width")
	var pos_before := panel.position
	_tab._on_toolbar_panel_gui_input(_press(Vector2(6, 6)))
	check(bool(_tab.get("_toolbar_dragging")), "s100 big icon move starts")
	var dx := -24.0 if pos_before.x >= 24.0 else 24.0
	var motion9 := InputEventMouseMotion.new()
	motion9.position = panel.global_position + Vector2(6, 6) + Vector2(dx, 0)
	_tab.handle_mouse_motion(motion9)
	check(panel.position.x != pos_before.x, "s100 big icon panel moves")
	_tab._end_toolbar_drag()
	_tab._on_toolbar_panel_gui_input(_press(panel.size - Vector2(4, 4)))
	check(bool(_tab.get("_toolbar_resizing")), "s100 big icon grip starts")
	var pitch2: float = _tab._toolbar_button_pitch()
	var motion9b := InputEventMouseMotion.new()
	motion9b.position = panel.global_position + panel.size - Vector2(4, 4) - Vector2(pitch2 * 2.0, 0)
	_tab.handle_mouse_motion(motion9b)
	check(int(config.toolbar_cols) >= 1, "s100 big icon grip reshapes")
	_tab._end_toolbar_drag()
	# 地図より縦に長い状態では、上へドラッグして下端
	# (グリップ) を見せられる。
	var y_before := panel.position.y
	_tab._on_toolbar_panel_gui_input(_press(Vector2(6, 6)))
	var motion9c := InputEventMouseMotion.new()
	motion9c.position = panel.global_position + Vector2(6, 6) + Vector2(0, -200)
	_tab.handle_mouse_motion(motion9c)
	check(panel.position.y < y_before, "s100 tall panel slides up")
	_tab._end_toolbar_drag()
	config.toolbar_icon_size = 0
	config.toolbar_cols = 0
	_tab.refresh_toolbar_icon_size()
	print("test_stage100: ", _checks, " checks, ", _failures, " failures")
	quit(1 if _failures > 0 else 0)
