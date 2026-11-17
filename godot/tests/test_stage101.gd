extends SceneTree
## 第101段＋第103段のテスト: 0.5.0 の新スタイル。表示スタイルの切替
## (旧=従来の分割配置 / 新=ログと入力欄のフロート窓) が1つで
## 両窓まとめて切り替わり、既定は新スタイル。フロート窓は
## 黒透過地に白文字、角丸で、枠はログ=金・入力=赤。上部に題名帯
## (ログ="Log Window" / 入力="Chat Window") があり、移動はその帯の
## ドラッグ、大きさ変更は右下の隅で、位置と大きさは設定に残る。
## 文字サイズは窓の大きさから窓ごとに独立に決まる。
## マップ配置は中央 (既定) /左寄せ/右寄せを切り替えられる。
##
## 使い方: godot --headless --path . -s tests/test_stage101.gd
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


func _press(panel: Control, local: Vector2) -> InputEventMouseButton:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = local
	ev.global_position = panel.global_position + local
	return ev


func _release() -> InputEventMouseButton:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = false
	return ev


func _motion(global_pos: Vector2) -> InputEventMouseMotion:
	var ev := InputEventMouseMotion.new()
	ev.position = global_pos
	return ev


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	# (1) 設定の既定と往復。
	var fresh := PhiConfig.new()
	check_eq(fresh.ui_style, "new", "s101 default style is new")
	check_eq(fresh.map_align, 0, "s101 default align center")
	check_eq(fresh.log_float_rect.size, Vector2.ZERO, "s101 log rect unset")
	fresh.ui_style = "old"
	fresh.map_align = 2
	fresh.log_float_rect = Rect2(10, 20, 300, 200)
	fresh.input_float_rect = Rect2(30, 40, 320, 110)
	fresh.save_file("user://stage101_cfg2.ini")
	var loaded := PhiConfig.new()
	loaded.load_file("user://stage101_cfg2.ini")
	check_eq(loaded.ui_style, "old", "s101 style roundtrip")
	check_eq(loaded.map_align, 2, "s101 align roundtrip")
	check_eq(loaded.log_float_rect, Rect2(10, 20, 300, 200), "s101 log rect roundtrip")
	check_eq(loaded.input_float_rect, Rect2(30, 40, 320, 110), "s101 input rect roundtrip")
	# (2) アクション定義。
	check_eq(str(PhiActions.get_action("UiStyleFloat").get("kind", "")), "ui-style-toggle", "s101 style action kind")
	for pair in [["MapAlignCenter", 0], ["MapAlignLeft", 1], ["MapAlignRight", 2]]:
		var act := PhiActions.get_action(str(pair[0]))
		check_eq(str(act.get("kind", "")), "map-align", "s101 align kind " + str(pair[0]))
		check_eq(int(act.get("align", -1)), int(pair[1]), "s101 align value " + str(pair[0]))
	# (3) 文字サイズの式 (両窓共通、窓ごとに独立)。
	check_eq(PhiCharacter.float_font_for(Vector2(340, 100)), 11, "s101 font min clamp")
	check_eq(PhiCharacter.float_font_for(Vector2(680, 100)), 20, "s101 font mid")
	check_eq(PhiCharacter.float_font_for(Vector2(2000, 100)), 30, "s101 font max clamp")

	var main = Main.new()
	for p in ["user://stage101_tabs.ini", "user://stage101_cfg.ini"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	main.set("_tab_session_path", "user://stage101_tabs.ini")
	main.set("_config_path", "user://stage101_cfg.ini")
	root.add_child(main)
	root.size = Vector2i(1400, 900)
	_main = main
	await process_frame
	await process_frame
	_tab = main.call("_active_tab")
	main.call("_activate_tab", _tab)
	await process_frame
	await process_frame
	# ヘッドレスでは Main の窓レイアウトが最小サイズに縮むので、
	# 地図の大きさを明示して配置し直し、形状の確認はレイアウトが
	# 戻る前の同期のうちに行う (他の形状テストと同じ流儀)。
	_tab.map_view.size = Vector2(1380, 700)
	_tab.apply_ui_style()
	var config = main.get("_config")
	var log_float := _tab.get("_log_float") as PanelContainer
	var input_float := _tab.get("_input_float") as PanelContainer
	check(log_float != null and input_float != null, "s101 float panels exist")
	# (4) 既定は新スタイル: 中身はフロート窓の中、右列は畳まれる。
	check(bool(_tab.get("_float_mode")), "s101 starts in float mode")
	check(_tab.log_view.get_parent() == _tab.get("_log_float_content"), "s101 log inside log float")
	check(_tab.input_box.get_parent() == _tab.get("_input_float_content"), "s101 input inside input float")
	check(not (_tab.get("_right_col") as Control).visible, "s101 right column hidden")
	check(log_float.visible and input_float.visible, "s101 floats visible")
	check(log_float.size.x > 0.0 and log_float.size.y > 0.0, "s101 log float placed")
	check(input_float.size.x > 0.0 and input_float.size.y > 0.0, "s101 input float placed")
	check(log_float.position.x > _tab.map_view.size.x * 0.5, "s101 log float defaults right")
	check(input_float.position.y > _tab.map_view.size.y * 0.5, "s101 input float defaults bottom")
	# (5) 窓の見た目: 黒透過、角丸、枠色 (ログ=金、入力=赤)。
	var lbox := log_float.get_theme_stylebox("panel") as StyleBoxFlat
	check(lbox != null and absf(lbox.bg_color.a - 0.62) < 0.01 and lbox.bg_color.r < 0.05, "s101 log float translucent black")
	check_eq(lbox.border_color, PhiCharacter.FLOAT_LOG_BORDER, "s101 log frame gold")
	check(lbox.corner_radius_top_left >= 8, "s101 log frame rounded")
	var ibox := input_float.get_theme_stylebox("panel") as StyleBoxFlat
	check_eq(ibox.border_color, PhiCharacter.FLOAT_INPUT_BORDER, "s101 input frame red")
	# (5b) 題名帯: ログは "Log Window"、入力は "Chat Window"。
	check_eq(str((_tab.get("_log_float_title") as Label).text), "Log Window", "s101 log band title")
	check_eq(str((_tab.get("_input_float_title") as Label).text), "Chat Window", "s101 input band title")
	# (5c) Talk ボタンは新スタイルで 1.5 倍 (第106段)。
	var talk_base := clampi(PhiFont.ui_size_for_zoom(_tab.map_view.zoom) * 2 + 40, 68, 100)
	check_eq(int(_tab.get("_talk_d")), int(round(float(talk_base) * 1.5)), "s101 talk button 1.5x in new style")
	# (6) 文字は白。ログの既定色と入力欄の文字色。
	check_eq(_tab.log_view.get_theme_color("default_color"), Color.WHITE, "s101 log text white")
	check_eq(_tab.input_box.get_theme_color("font_color"), Color.WHITE, "s101 input text white")
	# (7) 文字サイズは窓の大きさから。入力窓だけ広げると
	# 入力の文字だけ大きくなる (独立)。
	var log_font0: int = _tab.log_view.get_theme_font_size("font_size")
	check_eq(log_font0, PhiCharacter.float_font_for(log_float.size), "s101 log font from window size")
	var input_font0: int = _tab.input_box.get_theme_font_size("font_size")
	check_eq(input_font0, PhiCharacter.float_font_for(input_float.size), "s101 input font from window size")
	input_float.size = input_float.size + Vector2(170, 0)
	_tab.call("_apply_float_fonts")
	check_eq(_tab.input_box.get_theme_font_size("font_size"), input_font0 + 5, "s101 input font grows alone")
	check_eq(_tab.log_view.get_theme_font_size("font_size"), log_font0, "s101 log font unchanged")
	# (8) 題名帯のドラッグで移動し、離すと設定に残る。
	# (既定位置は右端なので、左と下へ動かして確かめる)
	var log_band := _tab.get("_log_float_band") as PanelContainer
	var start_pos := log_float.position
	_tab.call("_on_float_band_gui_input", _press(log_band, Vector2(20, 5)), log_float)
	check(_tab.get("_float_drag_panel") == log_float, "s101 band drag starts")
	_tab.handle_mouse_motion(_motion(log_band.global_position + Vector2(20, 5) + Vector2(-60, 30)))
	check_eq(log_float.position, start_pos + Vector2(-60, 30), "s101 drag moves window")
	_tab.handle_mouse_button(_release())
	check(_tab.get("_float_drag_panel") == null, "s101 drag ends")
	check_eq(config.log_float_rect.position, log_float.position, "s101 drag saved to config")
	# 枠の帯 (題名帯の外) ではドラッグは始まらない
	_tab.call("_on_float_gui_input", _press(log_float, Vector2(log_float.size.x * 0.5, log_float.size.y - 4)), log_float)
	check(_tab.get("_float_drag_panel") == null, "s101 frame no longer drags")
	# (9) 右下の隅のドラッグで大きさ変更。
	# (既定位置は右下の隅で広げられないので、空いた場所へ移してから)
	input_float.position = Vector2(100, 100)
	var start_size := input_float.size
	_tab.call("_on_float_gui_input", _press(input_float, input_float.size - Vector2(4, 4)), input_float)
	check(_tab.get("_float_resize_panel") == input_float, "s101 grip starts resize")
	_tab.handle_mouse_motion(_motion(input_float.global_position + input_float.size - Vector2(4, 4) + Vector2(80, 20)))
	check_eq(input_float.size, start_size + Vector2(80, 20), "s101 resize grows window")
	_tab.handle_mouse_button(_release())
	check_eq(config.input_float_rect.size, input_float.size, "s101 resize saved to config")
	# (10) 旧スタイルへ: 中身は分割配置へ戻り、右列が戻る。
	config.ui_style = "old"
	_tab.apply_ui_style()
	check(not bool(_tab.get("_float_mode")), "s101 old style flag")
	check(_tab.log_view.get_parent() == _tab.input_split, "s101 log back in split")
	check(_tab.input_box.get_parent() == _tab.input_split, "s101 input back in split")
	check_eq(_tab.input_split.get_child(0), _tab.log_view, "s101 log first in split")
	check_eq(_tab.input_split.get_child(1), _tab.input_box, "s101 input second in split")
	check((_tab.get("_right_col") as Control).visible, "s101 right column back")
	check(not log_float.visible and not input_float.visible, "s101 floats hidden")
	check_eq(int(_tab.get("_talk_d")), talk_base, "s101 talk button base size in old style")
	check(not _tab.log_view.has_theme_color_override("default_color") or _tab.log_view.get_theme_color("default_color") != Color.WHITE, "s101 log color restored")
	# (11) 新スタイルへ戻すと、保存した位置と大きさで復元する。
	_tab.map_view.size = Vector2(1380, 700)
	config.ui_style = "new"
	_tab.apply_ui_style()
	check(bool(_tab.get("_float_mode")), "s101 back to float")
	check_eq(log_float.position, config.log_float_rect.position, "s101 log position restored")
	check_eq(input_float.size, config.input_float_rect.size, "s101 input size restored")
	# (12) マップ配置: 描画範囲の横位置が変わる。
	_tab.map_view.size = Vector2(1000, 800)
	_tab.map_view.zoom = 1
	config.map_align = 0
	_tab.apply_map_align()
	check_eq(_tab.map_view.drawn_map_rect().position.x, 388.0, "s101 align center")
	config.map_align = 1
	_tab.apply_map_align()
	check_eq(_tab.map_view.drawn_map_rect().position.x, 0.0, "s101 align left")
	config.map_align = 2
	_tab.apply_map_align()
	check_eq(_tab.map_view.drawn_map_rect().position.x, 776.0, "s101 align right")
	print("test_stage101: ", _checks, " checks, ", _failures, " failures")
	quit(1 if _failures > 0 else 0)
