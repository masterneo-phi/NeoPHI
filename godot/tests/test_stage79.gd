extends SceneTree
## 第79段のテスト: IME 変換中はキーを横取りしない。Windows では
## 変換確定の Enter が通常キーとして届き、送信と取り違えて
## 日本語が発言できなかった。実 IME は headless で再現できない
## ため、_ime_test_forced で状態を固定して振る舞いを見る。
##
## 使い方: godot --headless --path . -s tests/test_stage79.gd
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


func _key(keycode: Key, physical: Key = KEY_NONE) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.pressed = true
	ev.keycode = keycode
	ev.physical_keycode = physical if physical != KEY_NONE else keycode
	return ev


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
		_test_ime_guard()
		print("test_stage79: ", _checks, " checks, ", _failures, " failures")
		quit(1 if _failures > 0 else 0)


func _test_ime_guard() -> void:
	var tab := _tab
	var queue: Array = tab.session.get("_send_queue")
	# headless では実 IME は常に変換中でない。
	_check(not tab.ime_composing(), "s79 headless is not composing")
	tab.input_box.grab_focus()
	tab.input_box.text = "こんにちは"
	# (1) 変換中を固定すると、Enter は送信にならない。
	tab.set("_ime_test_forced", 1)
	_check(tab.ime_composing(), "s79 forced composing")
	_check(not tab.handle_key(_key(KEY_ENTER)), "s79 enter passes while composing")
	_check_eq(queue, [], "s79 nothing sent while composing")
	_check_eq(tab.input_box.text, "こんにちは", "s79 text untouched while composing")
	# (2) 変換中は Tab (フォーカス切替) も移動キーも横取りしない。
	_check(not tab.handle_key(_key(KEY_TAB)), "s79 tab passes while composing")
	_check(tab.input_box.has_focus(), "s79 focus kept while composing")
	_check(not tab.handle_key(_key(KEY_UP, KEY_UP)), "s79 move passes while composing")
	_check(not tab.handle_key(_key(KEY_W, KEY_W)), "s79 W passes while composing")
	_check_eq(queue, [], "s79 still nothing sent")
	# (3) 変換が終われば、Enter でそのまま送信できる。
	tab.set("_ime_test_forced", 0)
	_check(tab.handle_key(_key(KEY_ENTER)), "s79 enter submits after compose")
	_check_eq(queue, ["こんにちは"], "s79 japanese sent after compose")
