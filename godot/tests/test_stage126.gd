extends SceneTree
## 第126段: #list パネルの位置の保存・復元。
## リスト (アイテム/Analyze/魔法) のパネルは、見出しのドラッグで
## 動かせても位置が設定に保存されず、再起動で左上 (8, 8) に
## 戻っていた。ツールバーの位置 (Disp/ToolbarX/Y) と同じ流儀で、
## ドラッグの終わりに設定 (Disp/ListX/Y) へ覚え、構築時に
## 戻すことを確認する。大きさは行数で決まるので保存しない。
##
## 使い方: godot --headless --path . -s tests/test_stage126.gd
## 終了コード 0 = 全一致、1 = 不一致あり。

var _failures := 0
var _checks := 0
var _tab: PhiCharacter = null
var _config: PhiConfig = null
var _tab2: PhiCharacter = null
var _tab3: PhiCharacter = null
var _saved_pos := Vector2(-1, -1)
var _frames := 0

const CFG_PATH := "user://stage126_cfg.ini"
const CFG_UNSET_PATH := "user://stage126_cfg_unset.ini"


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
	return tab


func _initialize() -> void:
	_config = PhiConfig.new()
	_config.log_auto_save = false
	_config.ui_style = "old"
	_tab = _make_tab(_config)
	process_frame.connect(_on_frame)


func _open_list(tab: PhiCharacter) -> void:
	var lines: Array[String] = ["[ 1] apple", "[ 2] banana", "[ 3] cherry"]
	tab.set("_list_lines", lines)
	tab.set("_list_active", true)
	tab._show_list_overlay()


func _on_frame() -> void:
	_frames += 1
	if _frames == 3:
		_test_drag_saves()
		_test_round_trip()
		_make_restored_tabs()
	elif _frames == 8:
		_test_restored()
		print("test_stage126: ", _checks, " checks, ", _failures, " failures")
		quit(1 if _failures > 0 else 0)


# -- ドラッグで設定へ残る -------------------------------------------------------

func _test_drag_saves() -> void:
	var tab := _tab
	var panel := tab.get("_list_panel") as PanelContainer
	check(panel != null, "s126 list panel exists")
	if panel == null:
		return
	check_eq(_config.list_pos, Vector2(-1, -1), "s126 list pos unset at first")
	_open_list(tab)
	check(panel.visible, "s126 list shown")
	check_eq(panel.position, Vector2(8, 8), "s126 default position is top-left")
	# 見出しを押してドラッグし、離す (実際の入力経路を通す)。
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = panel.global_position + Vector2(10, 4)
	press.global_position = press.position
	tab._on_list_header_gui_input(press)
	check(bool(tab.get("_list_dragging")), "s126 drag started")
	var motion := InputEventMouseMotion.new()
	motion.position = tab.map_view.get_global_position() + Vector2(150, 110) + Vector2(10, 4)
	tab.handle_mouse_motion(motion)
	check(panel.position != Vector2(8, 8), "s126 panel moved by drag")
	# ドラッグの途中では、まだ設定へ書かない。
	check_eq(_config.list_pos, Vector2(-1, -1), "s126 not saved during drag")
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.position = motion.position
	release.global_position = motion.position
	tab.handle_mouse_button(release)
	check(not bool(tab.get("_list_dragging")), "s126 drag ended")
	check_eq(_config.list_pos, panel.position, "s126 drag end saves position")
	_saved_pos = panel.position


# -- 設定ファイルへの往復 --------------------------------------------------------

func _test_round_trip() -> void:
	check(_config.save_file(CFG_PATH), "s126 config save")
	var loaded := PhiConfig.new()
	check(loaded.load_file(CFG_PATH), "s126 config load")
	check_eq(loaded.list_pos, _saved_pos, "s126 list pos round trip")
	# 未設定のまま保存した設定は、読み直しても未設定のまま。
	var fresh := PhiConfig.new()
	fresh.log_auto_save = false
	check(fresh.save_file(CFG_UNSET_PATH), "s126 unset config save")
	var loaded_unset := PhiConfig.new()
	check(loaded_unset.load_file(CFG_UNSET_PATH), "s126 unset config load")
	check_eq(loaded_unset.list_pos, Vector2(-1, -1), "s126 unset stays unset")


# -- 新しいタブ (再起動相当) での復元 ----------------------------------------------

func _make_restored_tabs() -> void:
	var loaded := PhiConfig.new()
	loaded.log_auto_save = false
	loaded.load_file(CFG_PATH)
	_tab2 = _make_tab(loaded)
	var far := PhiConfig.new()
	far.log_auto_save = false
	far.ui_style = "old"
	far.list_pos = Vector2(100000, 100000)
	_tab3 = _make_tab(far)


func _test_restored() -> void:
	# 保存した位置が、新しいタブのパネルに復元される。
	var panel2 := _tab2.get("_list_panel") as PanelContainer
	check(panel2 != null, "s126 restored panel exists")
	if panel2 != null:
		_open_list(_tab2)
		check_eq(panel2.position, _saved_pos, "s126 position restored in new tab")
	# 地図の外の位置が保存されていたら、表示時に地図の中へ戻る。
	var panel3 := _tab3.get("_list_panel") as PanelContainer
	check(panel3 != null, "s126 far panel exists")
	if panel3 != null:
		_open_list(_tab3)
		var mv_size := _tab3.map_view.size
		check(panel3.position.x >= 0.0 and panel3.position.y >= 0.0, "s126 far position clamped to origin side")
		check(panel3.position.x + panel3.size.x <= mv_size.x + 1.0, "s126 far position clamped horizontally")
		check(panel3.position.y + panel3.size.y <= mv_size.y + 1.0, "s126 far position clamped vertically")
