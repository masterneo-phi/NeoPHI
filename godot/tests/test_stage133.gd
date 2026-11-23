extends SceneTree
## 第133段: ユーザー報告 (2026-11-23)。新スタイル (フロート窓) で、
## タブを消して再接続 (タブを作り直し) すると、Log Window の
## フォントが小さいままになることがある。原因は、フロート窓の
## 既定配置が「最初に地図の大きさが決まった時点」の地図幅で
## 決まっていたこと。作り直した直後のタブはレイアウトの途中で
## 地図がまだ狭く、その幅で決めた既定 (最小幅 320 → 文字 11)
## が固定され、地図が本来の幅に広がっても窓も文字も小さい
## まま残っていた。クライアントを再起動すると直るのは、
## 起動時は配置が最終幅で決まるため。
##
## 修正: 設定に矩形が無い (自動配置の) 窓は、地図の大きさが
## 変わるたびに既定で置き直す。ユーザーが動かしたり大きさを
## 変えたりした窓は、離した時点で設定に矩形が残るので、
## そちらが優先されて置き直されない。
##
## 使い方: godot --headless --path . -s tests/test_stage133.gd
## 終了コード 0 = 全一致、1 = 不一致あり。

const Main := preload("res://scripts/main.gd")

var _failures := 0
var _checks := 0
var _main: Node = null


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
	call_deferred("_run")


func _run() -> void:
	var main = Main.new()
	for p in ["user://stage133_tabs.ini", "user://stage133_cfg.ini"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	main.set("_tab_session_path", "user://stage133_tabs.ini")
	main.set("_config_path", "user://stage133_cfg.ini")
	root.add_child(main)
	root.size = Vector2i(1600, 1000)
	_main = main
	await process_frame
	await process_frame
	var config = main.get("_config")
	config.ui_style = "new"
	config.log_font_size = 0
	config.input_font_size = 0
	config.log_float_rect = Rect2()
	config.input_float_rect = Rect2()

	# 報告の再現手順: タブを消して、作り直してアクティブにする。
	var tab0 = main.call("_active_tab")
	main.call("_close_tab", tab0)
	await process_frame
	var tab = main.call("_create_tab")
	main.call("_activate_tab", tab)
	await process_frame
	check(bool(tab.get("_float_mode")), "s133 recreated tab is float mode")
	var log_float := tab.get("_log_float") as PanelContainer
	var input_float := tab.get("_input_float") as PanelContainer
	check(log_float != null and input_float != null, "s133 float panels exist")

	# レイアウトの途中経過: まず地図が狭い幅で置かれる。
	# この時点では既定配置は狭い幅で決まる (ここまでは従来どおり)。
	tab.map_view.size = Vector2(420, 300)
	check_eq(log_float.size, Vector2(320, 200), "s133 narrow map places default small")
	check_eq(tab.log_view.get_theme_font_size("font_size"), 11, "s133 narrow map font is min")

	# 地図が本来の幅に広がったら、自動配置の窓は置き直され、
	# 文字も窓幅から決まる大きさに戻る (ここが直した所)。
	tab.map_view.size = Vector2(1100, 800)
	var want_w := clampf(1100.0 * 0.44, 320.0, 760.0)
	check_eq(log_float.size.x, want_w, "s133 log float re-placed on map grow")
	check_eq(input_float.size.x, want_w, "s133 input float re-placed on map grow")
	check_eq(tab.log_view.get_theme_font_size("font_size"),
		PhiCharacter.float_font_for(log_float.size), "s133 log font follows new width")
	check(tab.log_view.get_theme_font_size("font_size") > 11, "s133 log font recovered")

	# 設定に矩形がある窓は、地図の大きさが変わっても
	# 設定の矩形が優先され、既定で置き直されない。
	config.log_float_rect = Rect2(10, 10, 690, 560)
	tab.map_view.size = Vector2(900, 700)
	check_eq(log_float.size, Vector2(690, 560), "s133 config rect wins over default")
	check_eq(log_float.position, Vector2(10, 10), "s133 config rect position wins")
	check_eq(tab.log_view.get_theme_font_size("font_size"),
		PhiCharacter.float_font_for(Vector2(690, 560)), "s133 font from config width")

	print("test_stage133: ", _checks, " checks, ", _failures, " failures")
	quit(1 if _failures > 0 else 0)
