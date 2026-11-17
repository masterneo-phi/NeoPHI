extends SceneTree
## 第104段のテスト: フロート窓のフォントサイズ変更。各窓の
## 題名帯の「フォントサイズ変更」ボタンからミニ窓を開くと、
## 数値欄には現在のサイズが入っている。数値を変えて OK すると
## その窓の文字がその大きさに固定される。0 (または「自動に
## 戻す」) は自動 (窓の大きさから決める)。設定は ini に残る。
## 設定メニューには増やさない (帯のボタンが入口)。
##
## 使い方: godot --headless --path . -s tests/test_stage104.gd
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


func _initialize() -> void:
	_run()


func _run() -> void:
	# (1) 設定の既定と往復
	var cfg := PhiConfig.new()
	check_eq(cfg.log_font_size, 0, "s104 log font default auto")
	check_eq(cfg.input_font_size, 0, "s104 input font default auto")
	cfg.log_font_size = 24
	cfg.input_font_size = 18
	var path := "user://stage104_cfg.ini"
	cfg.save_file(path)
	var cfg2 := PhiConfig.new()
	cfg2.load_file(path)
	check_eq(cfg2.log_font_size, 24, "s104 log font roundtrip")
	check_eq(cfg2.input_font_size, 18, "s104 input font roundtrip")

	# (2) メニューには増えていない (入口は帯のボタン)
	check(PhiActions.get_action("FontSizeSettings").is_empty(), "s104 no settings menu action")

	# (3) タブ側: 帯のボタンとミニ窓、数値の即反映
	var dir := DirAccess.open("user://")
	if dir != null:
		for f in ["stage104_tabs.ini", "stage104_main.ini"]:
			if dir.file_exists(f):
				dir.remove(f)
	var main: Node = Main.new()
	main.set("_tab_session_path", "user://stage104_tabs.ini")
	main.set("_config_path", "user://stage104_main.ini")
	root.add_child(main)
	await process_frame
	await process_frame
	var tab: PhiCharacter = main.call("_active_tab")
	main.call("_activate_tab", tab)
	var config: PhiConfig = main.get("_config")
	tab.map_view.size = Vector2(1380, 700)
	config.ui_style = "new"
	tab.apply_ui_style()
	var log_button := tab.get("_log_band_button") as Button
	var input_button := tab.get("_input_band_button") as Button
	check(log_button != null and input_button != null, "s104 band buttons exist")
	check_eq(str(log_button.text), "フォントサイズ変更", "s104 band button label")
	# 自動の間は窓の大きさから
	var auto_log := PhiCharacter.float_font_for((tab.get("_log_float") as Control).size)
	check_eq(tab.log_view.get_theme_font_size("font_size"), auto_log, "s104 auto log font")
	# ミニ窓を開く (ログ側): 数値欄には現在のサイズが入っている
	tab.call("_show_font_window", true)
	var win := tab.get("_font_window") as Window
	check(win != null and win.visible, "s104 font window opens")
	check(str((tab.get("_font_win_title") as Label).text).contains("Log Window"), "s104 font window title log")
	var spin := tab.get("_font_spin") as SpinBox
	check_eq(int(spin.value), auto_log, "s104 spin prefilled with current size")
	# 数値を変えただけでは反映されず、OK で確定する
	spin.value = 26
	check_eq(tab.log_view.get_theme_font_size("font_size"), auto_log, "s104 no apply before OK")
	tab.call("_on_font_ok")
	check(not win.visible, "s104 OK closes window")
	check_eq(config.log_font_size, 26, "s104 OK writes config")
	check_eq(tab.log_view.get_theme_font_size("font_size"), 26, "s104 log font fixed 26")
	check_eq(tab.input_box.get_theme_font_size("font_size"), PhiCharacter.float_font_for((tab.get("_input_float") as Control).size), "s104 input still auto")
	check_eq((tab.get("_log_float_title") as Label).get_theme_font_size("font_size"), 26, "s104 log band title follows")
	# 再度開くと、固定した数値が入っている
	tab.call("_show_font_window", true)
	check_eq(int(spin.value), 26, "s104 spin prefilled with fixed size")
	win.hide()
	# 入力側のミニ窓
	tab.call("_show_font_window", false)
	check(str((tab.get("_font_win_title") as Label).text).contains("Chat Window"), "s104 font window title chat")
	spin.value = 13
	tab.call("_on_font_ok")
	check_eq(config.input_font_size, 13, "s104 input OK writes config")
	check_eq(tab.input_box.get_theme_font_size("font_size"), 13, "s104 input font fixed 13")
	# 「自動に戻す」で自動へ
	tab.call("_show_font_window", true)
	tab.call("_on_font_auto")
	check_eq(config.log_font_size, 0, "s104 auto button clears config")
	check_eq(tab.log_view.get_theme_font_size("font_size"), auto_log, "s104 back to auto font")

	print("test_stage104: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)
