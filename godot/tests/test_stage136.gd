extends SceneTree
## 第136段のテスト: Talk ボタンの大きさが、コマンドパレットの
## アイコンサイズ設定 (ToolbarIconSize) に連動する (利用者の要望)。
## 設定が 0 のときは従来どおりの大きさで、値を入れるとパレットの
## ボタンが大きくなるのと同じ比率で Talk ボタンも大きくなり、
## 表示サイズ設定の変更経路 (refresh_toolbar_icon_size) で
## 即時に反映される。0 に戻すと従来の大きさへ完全に戻る。
##
## 使い方: godot --headless --path . -s tests/test_stage136.gd
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


func _palette_icon_height() -> float:
	## パレットのアイコン付きボタンの最小の高さ (パレット側の
	## 大きさの決め方そのもの)。無ければ -1。
	for b in _tab.get("_toolbar_buttons"):
		var btn := b as Button
		if btn.icon != null:
			return btn.custom_minimum_size.y
	return -1.0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var main = Main.new()
	for p in ["user://stage136_tabs.ini", "user://stage136_cfg.ini"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	main.set("_tab_session_path", "user://stage136_tabs.ini")
	main.set("_config_path", "user://stage136_cfg.ini")
	root.add_child(main)
	_main = main
	await process_frame
	await process_frame
	_tab = main.call("_active_tab")
	await process_frame
	var talk := _tab.get("_talk_button") as Button
	check(talk != null, "s136 talk button exists")
	var config = main.get("_config")
	var map_view := _tab.get("map_view") as Control
	var ui_size := PhiFont.ui_size_for_zoom(_tab.map_view.zoom)
	# 起動直後は表示スタイルの反映 (フロート化) が Talk ボタンの
	# 大きさにまだ伝わっていないことがあるので、通常の経路で
	# 一度そろえてから基準を取る。
	_tab.refresh_ui_font_size()
	_tab.refresh_toolbar_icon_size()
	await process_frame
	# (1) 設定 0 (既定) では従来どおりの大きさ。
	check_eq(int(config.toolbar_icon_size), 0, "s136 icon size default 0")
	var d0 := int(_tab.get("_talk_d"))
	var want0 := clampi(ui_size * 2 + 40, 68, 100)
	if bool(_tab.get("_float_mode")):
		want0 = int(round(float(want0) * 1.5))
	check_eq(d0, want0, "s136 default diameter")
	check_eq(talk.size, Vector2(d0, d0), "s136 default button size")
	var font0 := talk.get_theme_font_size("font_size")
	check_eq(font0, ui_size, "s136 default font size")
	check_eq(_tab._toolbar_icon_scale(ui_size), 1.0, "s136 scale is 1 at 0")
	var pal0 := _palette_icon_height()
	check(pal0 > 0.0, "s136 palette icon button exists")
	# (2) 値を入れると、refresh の経路で即時に大きくなる。
	# 比率はパレットのボタンが大きくなる比率と一致する。
	config.toolbar_icon_size = 64
	_tab.refresh_toolbar_icon_size()
	var d64 := int(_tab.get("_talk_d"))
	check(d64 > d0, "s136 grows at 64: %d -> %d" % [d0, d64])
	check_eq(talk.size, Vector2(d64, d64), "s136 button size at 64")
	check(talk.get_theme_font_size("font_size") > font0, "s136 font grows at 64")
	var scale64 := _tab._toolbar_icon_scale(ui_size)
	check(scale64 > 1.0, "s136 scale > 1 at 64")
	check_eq(d64, int(round(float(d0) * scale64)), "s136 diameter follows scale")
	if pal0 > 0.0:
		var pal64 := _palette_icon_height()
		check(pal64 > pal0, "s136 palette grows at 64")
		check(absf(float(d64) / float(d0) - pal64 / pal0) < 0.02, "s136 same ratio as palette")
	# 大きくなっても地図の中に収まる (位置のクランプが効く)。
	if map_view.size.x > 0.0 and map_view.size.y > 0.0:
		check(talk.position.x >= 0.0 and talk.position.y >= 0.0, "s136 position in map at 64")
		check(talk.position.x + talk.size.x <= map_view.size.x + 0.5, "s136 right edge in map at 64")
		check(talk.position.y + talk.size.y <= map_view.size.y + 0.5, "s136 bottom edge in map at 64")
	# (3) 中間の値では比率も 64 のとき以下になり、大きさも追随する。
	config.toolbar_icon_size = 32
	_tab.refresh_toolbar_icon_size()
	var scale32 := _tab._toolbar_icon_scale(ui_size)
	check(scale32 > 0.0 and scale32 <= scale64, "s136 scale at 32 in between")
	check_eq(int(_tab.get("_talk_d")), int(round(float(d0) * scale32)), "s136 diameter at 32 follows scale")
	# (4) 0 に戻すと従来の大きさへ完全に戻る。
	config.toolbar_icon_size = 0
	_tab.refresh_toolbar_icon_size()
	check_eq(int(_tab.get("_talk_d")), d0, "s136 restored diameter")
	check_eq(talk.size, Vector2(d0, d0), "s136 restored button size")
	check_eq(talk.get_theme_font_size("font_size"), font0, "s136 restored font size")
	print("test_stage136: ", _checks, " checks, ", _failures, " failures")
	quit(1 if _failures > 0 else 0)
