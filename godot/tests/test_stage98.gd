extends SceneTree
## 第98段のテスト: アイテム・魔法リスト表示中に、リストに
## 無い数字キーを押したらキャンセル扱いでリストを閉じる
## (利用者の要望)。テンキーは移動キーでもあるため、無反応
## だと前進や横向きができなくなる。キャンセルの送り方は
## 0 やキャンセルボタンと同じ "."。リストにある数字は
## 従来どおりその行を送る。閉じた後は移動キーが効く。
##
## 使い方: godot --headless --path . -s tests/test_stage98.gd
## 終了コード 0 = 全一致、1 = 不一致あり。

var _failures := 0
var _checks := 0
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


func _key(keycode: Key) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.keycode = keycode
	ev.physical_keycode = keycode
	ev.pressed = true
	return ev


func _queue() -> Array:
	return _tab.session.get("_send_queue")


func _open_list() -> void:
	var lines: Array[String] = ["[ 1] wizard eye", "[ 2] cure", "[ 3] harm"]
	_tab.set("_list_lines", lines)
	_tab.set("_list_active", true)
	_tab._show_list_overlay()
	_queue().clear()


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
	call_deferred("_run")


func _run() -> void:
	await process_frame
	await process_frame
	# (1) リストにある数字は従来どおりその行を送る。
	_open_list()
	check(_tab.handle_key(_key(KEY_KP_2)), "s98 kp2 handled")
	check_eq(_queue(), ["2"], "s98 kp2 sends row 2")
	check(not _tab.get("_list_active"), "s98 list closed after select")
	# (2) リストに無い数字 (テンキー5) はキャンセル扱い。
	_open_list()
	check(_tab.handle_key(_key(KEY_KP_5)), "s98 kp5 handled")
	check_eq(_queue(), ["."], "s98 kp5 cancels with dot")
	check(not _tab.get("_list_active"), "s98 list closed after cancel")
	check(not (_tab.get("_list_panel") as Control).visible, "s98 panel hidden after cancel")
	# (3) 数字行の 9 でも同じ (3項目しかない)。
	_open_list()
	check(_tab.handle_key(_key(KEY_9)), "s98 digit9 handled")
	check_eq(_queue(), ["."], "s98 digit9 cancels with dot")
	check(not _tab.get("_list_active"), "s98 list closed after digit9")
	# (4) 0 のキャンセルは従来どおり。
	_open_list()
	check(_tab.handle_key(_key(KEY_KP_0)), "s98 kp0 handled")
	check_eq(_queue(), ["."], "s98 kp0 cancels with dot")
	# (5) キャンセルで閉じた後は、移動キーが効く。
	_open_list()
	_tab.handle_key(_key(KEY_KP_5))
	_queue().clear()
	check(_tab.handle_key(_key(KEY_9)), "s98 nine handled after cancel")
	_tab.release_held_move(_key(KEY_9))
	check_eq(_queue(), ["turn r"], "s98 movement works after cancel")
	# (6) handle_list_key 直: 範囲外は true を返して "." を送る。
	_open_list()
	check(_tab.handle_list_key("Numpad7", false, false, false), "s98 direct np7 handled")
	check_eq(_queue(), ["."], "s98 direct np7 cancels")
	_open_list()
	check(_tab.handle_list_key("Numpad1", false, false, false), "s98 direct np1 handled")
	check_eq(_queue(), ["1"], "s98 direct np1 sends row 1")
	print("test_stage98: ", _checks, " checks, ", _failures, " failures")
	quit(1 if _failures > 0 else 0)
