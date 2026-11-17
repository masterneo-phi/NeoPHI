extends SceneTree
## 第107段のテスト: 「窓配置を全タブにそろえる」。アクティブな
## タブのフロート窓の位置・大きさを正として、全タブへ一発で
## 適用する。入口はコマンドパレットのボタンと表示メニュー。
##
## 使い方: godot --headless --path . -s tests/test_stage107.gd
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
	# (1) アクションの配線: パレットと表示メニューにいる
	var action: Dictionary = PhiActions.get_action("LayoutToAllTabs")
	check_eq(str(action.get("kind", "")), "layout-to-all-tabs", "s107 action kind")
	check(PhiActions.TOOLBAR.has("LayoutToAllTabs"), "s107 in toolbar")
	var in_menu := false
	for m in PhiActions.MENUS:
		if str(m.get("name", "")) == "表示" and (m.get("items", []) as Array).has("LayoutToAllTabs"):
			in_menu = true
	check(in_menu, "s107 in view menu")

	# (2) 2つのタブで配置をそろえる
	var dir := DirAccess.open("user://")
	if dir != null:
		for f in ["stage107_tabs.ini", "stage107_main.ini"]:
			if dir.file_exists(f):
				dir.remove(f)
	var main: Node = Main.new()
	main.set("_tab_session_path", "user://stage107_tabs.ini")
	main.set("_config_path", "user://stage107_main.ini")
	root.add_child(main)
	await process_frame
	await process_frame
	var config: PhiConfig = main.get("_config")
	config.ui_style = "new"
	var tab1: PhiCharacter = main.call("_active_tab")
	main.call("_activate_tab", tab1)
	tab1.map_view.size = Vector2(1380, 700)
	tab1.apply_ui_style()
	var tab2: PhiCharacter = main.call("_create_tab")
	tab2.map_view.size = Vector2(1380, 700)
	tab2.apply_ui_style()
	# タブ1の窓を好みの配置にする
	var log1 := tab1.get("_log_float") as PanelContainer
	var input1 := tab1.get("_input_float") as PanelContainer
	log1.position = Vector2(120, 40)
	log1.size = Vector2(500, 300)
	input1.position = Vector2(120, 400)
	input1.size = Vector2(500, 120)
	tab1.sync_float_rects_to_config()
	# タブ2は違う配置のまま
	var log2 := tab2.get("_log_float") as PanelContainer
	var input2 := tab2.get("_input_float") as PanelContainer
	log2.position = Vector2(700, 200)
	log2.size = Vector2(300, 200)
	# アクティブをタブ1に戻して実行する
	main.call("_activate_tab", tab1)
	main.call("_do_action", "LayoutToAllTabs")
	check_eq(log2.position, Vector2(120, 40), "s107 log position copied")
	check_eq(log2.size, Vector2(500, 300), "s107 log size copied")
	check_eq(input2.position, Vector2(120, 400), "s107 input position copied")
	check_eq(input2.size, Vector2(500, 120), "s107 input size copied")
	check_eq(config.log_float_rect, Rect2(Vector2(120, 40), Vector2(500, 300)), "s107 config holds source layout")
	# フォント: 共通設定がタブ2にも付け直される
	config.log_font_size = 21
	main.call("_do_action", "LayoutToAllTabs")
	check_eq(tab2.log_view.get_theme_font_size("font_size"), 21, "s107 font applied to other tab")

	print("test_stage107: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)
