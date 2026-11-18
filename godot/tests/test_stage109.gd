extends SceneTree
## 第109段のテスト: 入力中にショートカットが誤爆する不具合の修正。
## 新スタイル (フロート窓) では、帯のクリックやタブ切替で
## 入力欄のフォーカスが外れたまま打ち始めることがあり、T
## (回転マップ) などの送信キーが発言の代わりに効いていた
## (ユーザー報告)。下書きが残っている間は文字キーを入力の
## 続きとみなしてフォーカスを戻し、ショートカットにしない。
## 下書きが無い時の T は従来どおり回転マップのキーとして効く。
##
## 使い方: godot --headless --path . -s tests/test_stage109.gd
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


func _key(keycode: Key, unicode: int = 0, shift: bool = false) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.pressed = true
	ev.keycode = keycode
	ev.physical_keycode = keycode
	ev.unicode = unicode
	ev.shift_pressed = shift
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
		_test_shortcut_guard()
		_test_band_click_focus()
		print("test_stage109: ", _checks, " checks, ", _failures, " failures")
		quit(1 if _failures > 0 else 0)


func _test_shortcut_guard() -> void:
	var tab := _tab
	var queue: Array = tab.session.get("_send_queue")
	# (1) 下書きあり + フォーカス喪失 + T (unicode 付き):
	# 送信キーにせず、フォーカスを戻す。
	tab.input_box.grab_focus()
	tab.input_box.text = "hello"
	tab.input_box.release_focus()
	_check(not tab.input_box.has_focus(), "s109 focus lost setup")
	_check(not tab.handle_key(_key(KEY_T, "t".unicode_at(0))), "s109 T with draft not a shortcut")
	_check_eq(queue, [], "s109 nothing sent with draft")
	_check(tab.input_box.has_focus(), "s109 focus restored by draft rescue")
	_check_eq(tab.input_box.text, "hello", "s109 draft untouched")
	# (2) 下書きあり + フォーカス喪失 + T (unicode 無し。
	# IME の変換開始と競合して文字なしで届く形): 同じく救済。
	tab.input_box.release_focus()
	_check(not tab.handle_key(_key(KEY_T, 0)), "s109 T unicode0 with draft not a shortcut")
	_check_eq(queue, [], "s109 nothing sent unicode0")
	_check(tab.input_box.has_focus(), "s109 focus restored unicode0")
	# (3) 下書きあり + Shift+T: solid への切替もしない。
	tab.input_box.release_focus()
	_check(not tab.handle_key(_key(KEY_T, "T".unicode_at(0), true)), "s109 Shift+T with draft not a shortcut")
	_check_eq(queue, [], "s109 nothing sent shift+T")
	# (4) 下書きなし + フォーカスなし + T: 従来どおり
	# 回転マップのショートカットとして効く。
	tab.input_box.text = ""
	tab.input_box.release_focus()
	_check(tab.handle_key(_key(KEY_T, 0)), "s109 T without draft is a shortcut")
	_check_eq(queue, ["#ex-map style=turn"], "s109 turn sent without draft")
	queue.clear()
	# (5) 下書きあり + 移動キー (↑): 救済対象ではなく移動する。
	tab.input_box.text = "hello"
	tab.input_box.release_focus()
	_check(tab.handle_key(_key(KEY_UP)), "s109 Up with draft still moves")
	_check_eq(queue, [], "s109 move sends nothing immediately")
	tab.input_box.text = ""
	# (6) フォーカスあり + T: 従来どおり TextEdit 任せ。
	tab.input_box.grab_focus()
	_check(not tab.handle_key(_key(KEY_T, "t".unicode_at(0))), "s109 T focused passes")
	_check_eq(queue, [], "s109 nothing sent focused")


func _test_band_click_focus() -> void:
	var tab := _tab
	var panel: Control = tab.get("_input_float")
	_check(panel != null, "s109 input float exists")
	if panel == null:
		return
	tab.input_box.release_focus()
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.global_position = Vector2(120, 120)
	tab.call("_on_float_band_gui_input", ev, panel)
	_check(tab.input_box.has_focus(), "s109 band click focuses input")
	# 帯のドラッグ自体は始まっている (窓も動かせる)。
	_check(tab.get("_float_drag_panel") == panel, "s109 band click still starts drag")
	tab.call("_end_float_drag")
