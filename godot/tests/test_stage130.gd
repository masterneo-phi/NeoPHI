extends SceneTree
## 第130段: フロート窓 (チャット/ログ)・Talk ボタン・リスト
## パネルの位置が、タブを切り替えると他のタブで動かした最新の
## 位置にそろわない問題の再現と修正の確認。
##
## 設定 (PhiConfig) は全タブで 1 つを共有し、ドラッグの終わりに
## 各タブがそこへ書き戻す。ツールバーはタブ有効化のたびに保持値
## へ置き直す (set_active → _apply_toolbar_home) ので全タブで
## そろうが、フロート窓・Talk・リストは構築時にしか保持値を
## 読まないため、タブ 2 で動かしてもタブ 1 は古い位置のままに
## なり、「1 つ目のタブの位置に戻った」ように見えた。
## 有効化のたびに保持値へそろえ直すことを確認する。
##
## 使い方: godot --headless --path . -s tests/test_stage130.gd
## 終了コード 0 = 全一致、1 = 不一致あり。

var _failures := 0
var _checks := 0
var _config: PhiConfig = null
var _tab1: PhiCharacter = null
var _tab2: PhiCharacter = null
var _frames := 0


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


func _make_tab(config: PhiConfig) -> PhiCharacter:
	var font := PhiFont.make_ui_font()
	var bold := PhiFont.make_bold_font()
	var tab := PhiCharacter.new()
	tab.setup(GameAssets.new(), config, font, bold, PhiLogFilter.new(), PhiTagMenu.parse(PhiTagMenu.DEFAULT_XML))
	root.add_child(tab)
	tab.position = Vector2.ZERO
	tab.size = Vector2(1280, 1024)
	tab.map_view.size = Vector2(1200, 900)
	tab.apply_ui_style()
	return tab


func _initialize() -> void:
	_config = PhiConfig.new()
	_config.log_auto_save = false
	_config.ui_style = "new"
	_tab1 = _make_tab(_config)
	_tab2 = _make_tab(_config)
	process_frame.connect(_on_frame)


func _press(at: Vector2) -> InputEventMouseButton:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = at
	ev.global_position = at
	return ev


func _release(at: Vector2) -> InputEventMouseButton:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = false
	ev.position = at
	ev.global_position = at
	return ev


func _motion(at: Vector2) -> InputEventMouseMotion:
	var ev := InputEventMouseMotion.new()
	ev.position = at
	ev.global_position = at
	return ev


## パネルを (地図内の) 目標左上へ、実際の入力経路でドラッグする。
func _drag_float(tab: PhiCharacter, panel: PanelContainer, target: Vector2) -> void:
	var grab := panel.global_position + Vector2(10, 4)
	tab._on_float_band_gui_input(_press(grab), panel)
	var dest := tab.map_view.get_global_position() + target + Vector2(10, 4)
	tab.handle_mouse_motion(_motion(dest))
	tab.handle_mouse_button(_release(dest))


func _on_frame() -> void:
	_frames += 1
	if _frames == 3:
		_run_checks()
		print("test_stage130: ", _checks, " checks, ", _failures, " failures")
		quit(1 if _failures > 0 else 0)


func _run_checks() -> void:
	var input1 := _tab1.get("_input_float") as PanelContainer
	var log1 := _tab1.get("_log_float") as PanelContainer
	var input2 := _tab2.get("_input_float") as PanelContainer
	var log2 := _tab2.get("_log_float") as PanelContainer
	check(input1 != null and log1 != null and input2 != null and log2 != null, "s130 float panels exist")
	if input1 == null or log1 == null or input2 == null or log2 == null:
		return
	# 初期状態: 両タブとも既定配置でそろっている。
	check_eq(input2.position, input1.position, "s130 input float starts aligned")
	check_eq(log2.position, log1.position, "s130 log float starts aligned")

	# -- タブ 2 でチャット窓とログ窓を動かす (実入力経路) --
	_drag_float(_tab2, input2, Vector2(200, 300))
	check_eq(_config.input_float_rect.position, input2.position, "s130 chat drag saved to config")
	check_eq(input2.position, Vector2(200, 300), "s130 chat window moved in tab2")
	_drag_float(_tab2, log2, Vector2(150, 60))
	check_eq(_config.log_float_rect.position, log2.position, "s130 log drag saved to config")
	check_eq(log2.position, Vector2(150, 60), "s130 log window moved in tab2")

	# -- タブ 2 で Talk ボタンを動かす --
	var talk2 := _tab2.get("_talk_button") as Button
	check(talk2 != null, "s130 talk button exists")
	if talk2 != null:
		var grab := talk2.global_position + Vector2(5, 5)
		_tab2._on_talk_button_gui_input(_press(grab))
		var dest := _tab2.map_view.get_global_position() + Vector2(300, 500) + Vector2(5, 5)
		_tab2.handle_mouse_motion(_motion(dest))
		_tab2.handle_mouse_button(_release(dest))
		check_eq(_config.talk_button_pos, talk2.position, "s130 talk drag saved to config")

	# -- タブ 2 でリストパネルを動かす --
	var lines: Array[String] = ["[ 1] apple", "[ 2] banana", "[ 3] cherry"]
	_tab2.set("_list_lines", lines)
	_tab2.set("_list_active", true)
	_tab2._show_list_overlay()
	var list2 := _tab2.get("_list_panel") as PanelContainer
	check(list2 != null, "s130 list panel exists")
	if list2 != null:
		var grab := list2.global_position + Vector2(10, 4)
		_tab2._on_list_header_gui_input(_press(grab))
		var dest := _tab2.map_view.get_global_position() + Vector2(150, 110) + Vector2(10, 4)
		_tab2.handle_mouse_motion(_motion(dest))
		_tab2.handle_mouse_button(_release(dest))
		check_eq(_config.list_pos, list2.position, "s130 list drag saved to config")

	# -- ツールバー (対照: 従来から有効化でそろう) --
	_config.toolbar_pos = Vector2(333, 222)

	# -- タブ 1 へ切り替える (main の _activate_tab と同じ入口) --
	_tab2.set_active(false)
	_tab1.set_active(true)

	# フロート窓: タブ 1 も最新の位置にそろう。
	check_eq(input1.position, _config.input_float_rect.position, "s130 chat window follows latest position in tab1")
	check_eq(log1.position, _config.log_float_rect.position, "s130 log window follows latest position in tab1")
	check_eq(input1.size, _config.input_float_rect.size, "s130 chat window size follows in tab1")
	# Talk: 置き直し (地図リサイズ時と同じ) で最新位置になる。
	var talk1 := _tab1.get("_talk_button") as Button
	check(talk1 != null, "s130 tab1 talk button exists")
	if talk1 != null:
		_tab1._place_talk_button()
		check_eq(talk1.position, _config.talk_button_pos, "s130 talk button follows latest position in tab1")
	# リスト: タブ 1 で開いたら最新位置に出る。
	_tab1.set("_list_lines", lines)
	_tab1.set("_list_active", true)
	_tab1._show_list_overlay()
	var list1 := _tab1.get("_list_panel") as PanelContainer
	check(list1 != null, "s130 tab1 list panel exists")
	if list1 != null:
		check_eq(list1.position, _config.list_pos, "s130 list panel follows latest position in tab1")
	# ツールバーは従来どおりそろう (対照)。
	var toolbar1 := _tab1.get("_toolbar_panel") as PanelContainer
	check(toolbar1 != null, "s130 toolbar panel exists")
	if toolbar1 != null:
		check_eq(toolbar1.position, _config.toolbar_pos, "s130 toolbar follows config on activation (control)")
