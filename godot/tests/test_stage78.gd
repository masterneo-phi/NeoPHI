extends SceneTree
## 第78段のテスト: フロートの選択リストで、行の本体をシングル
## クリックしたらそのまま決定する。チェック欄のクリックは
## 従来どおりチェック切替。決定直後の地図クリック (ダブル
## クリックの2打目) は移動にしない。
##
## 使い方: godot --headless --path . -s tests/test_stage78.gd
## 終了コード 0 = 全一致、1 = 不一致あり。

var _failures := 0
var _checks := 0
var _tab: PhiCharacter = null
var _frames := 0


func _check(cond: bool, label: String) -> void:
	_checks += 1
	if not cond:
		_failures += 1
		printerr("FAIL: ", label)


func _check_eq(a: Variant, b: Variant, label: String) -> void:
	_checks += 1
	if a != b:
		_failures += 1
		printerr("FAIL: ", label, " (got ", a, ", want ", b, ")")


func _queue() -> Array:
	return _tab.session.get("_send_queue")


func _click(pos: Vector2) -> InputEventMouseButton:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = pos
	return ev


func _show() -> void:
	var lines: Array[String] = ["[ 1] wizard eye", "[ 2] cure", "[ 3] harm"]
	_tab.set("_list_lines", lines)
	_tab.set("_list_active", true)
	_tab._show_list_overlay()


func _initialize() -> void:
	var config := PhiConfig.new()
	config.log_auto_save = false
	var font := PhiFont.make_ui_font()
	var bold := PhiFont.make_bold_font()
	_tab = PhiCharacter.new()
	_tab.setup(GameAssets.new(), config, font, bold, PhiLogFilter.new(), PhiTagMenu.parse(PhiTagMenu.DEFAULT_XML))
	root.add_child(_tab)
	_tab.position = Vector2.ZERO
	_tab.size = Vector2(1280, 1024)
	process_frame.connect(_on_frame)


func _on_frame() -> void:
	_frames += 1
	if _frames == 3:
		_show()
	elif _frames == 5:
		_test_click_decide()
		_show()
	elif _frames == 7:
		_test_click_checks()
		print("test_stage78: ", _checks, " checks, ", _failures, " failures")
		quit(1 if _failures > 0 else 0)


func _test_click_decide() -> void:
	var tab := _tab
	var box: ItemList = tab.get("_list_box")
	_queue().clear()
	# (1) 行の本体をクリック → そのまま決定する。
	var rect1 := box.get_item_rect(1)
	tab._on_list_box_gui_input(_click(rect1.get_center()))
	_check_eq(_queue(), ["2"], "s78 body click decides row")
	_check(not bool(tab.get("_list_active")), "s78 list closed after click")
	_check(int(tab.get("_list_click_decided_at")) > 0, "s78 decided stamp set")
	# (2) 閉じた後のダブルクリック側の経路は何も送らない。
	tab._on_list_row_activated(0)
	_check_eq(_queue(), ["2"], "s78 activation after close sends nothing")
	# (3) 決定直後の地図クリックは移動にしない。
	var map_center: Vector2 = tab.map_view.get_global_rect().get_center()
	tab._start_mouse_hold(_click(map_center))
	_check_eq(_queue(), ["2"], "s78 map click after decide swallowed")
	_check(not bool(tab.get("_mouse_held")), "s78 mouse hold not started")
func _test_click_checks() -> void:
	var tab := _tab
	var box: ItemList = tab.get("_list_box")
	# (4) チェック欄のクリックは従来どおりチェック切替だけ。
	_queue().clear()
	var rect0 := box.get_item_rect(0)
	tab._on_list_box_gui_input(_click(Vector2(5, rect0.get_center().y)))
	_check_eq(tab.list_checked_indices(), [0], "s78 check area toggles")
	_check_eq(_queue(), [], "s78 check area sends nothing")
	_check(bool(tab.get("_list_active")), "s78 list stays open after check")
	# (5) チェックがある状態で本体をクリックすると、チェックした
	# 項目への答えが優先される (ダブルクリック時と同じ)。
	var rect2 := box.get_item_rect(2)
	tab._on_list_box_gui_input(_click(rect2.get_center()))
	_check_eq(_queue(), ["1"], "s78 checked answer wins on click")
	_check(not bool(tab.get("_list_active")), "s78 list closed after checked click")
