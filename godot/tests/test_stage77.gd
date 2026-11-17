extends SceneTree
## 第77段のテスト: (1) 同時押し (斜め) の合体待ち。最初の方向キーを
## 少し保留し、相方が来たら斜めとして送る (従来は単独の1歩が
## 先に出て ↑→ が ↑↑→ になっていた)。(2) リスト表示中は入力欄に
## フォーカスがあってもテンキーで直接選べる。
##
## 使い方: godot --headless --path . -s tests/test_stage77.gd
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


func _key(keycode: Key) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.keycode = keycode
	ev.physical_keycode = keycode
	ev.pressed = true
	return ev


func _queue() -> Array:
	return _tab.session.get("_send_queue")


func _reset_keys() -> void:
	_tab.clear_held_input()
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
	process_frame.connect(_on_frame)


func _on_frame() -> void:
	_frames += 1
	if _frames == 2:
		_test_chord()
		_tab.input_box.grab_focus()
	elif _frames == 4:
		_test_list_focus()
		print("test_stage77: ", _checks, " checks, ", _failures, " failures")
		quit(1 if _failures > 0 else 0)


func _test_chord() -> void:
	var tab := _tab
	if tab.input_box.has_focus():
		tab.input_box.release_focus()
	# (1) 最初の方向キーは保留され、まだ何も送らない。
	_reset_keys()
	_check(tab.handle_key(_key(KEY_UP)), "s77 up handled")
	_check_eq(_queue(), [], "s77 first key waits")
	_check(int(tab.get("_held_step_pending_until")) > 0, "s77 pending armed")
	# (2) 相方が来たら斜めとして2行だけ送る (3歩目が出ない)。
	_check(tab.handle_key(_key(KEY_RIGHT)), "s77 right handled")
	_check_eq(_queue(), ["go N", "go E"], "s77 chord is one diagonal")
	_check_eq(int(tab.get("_held_step_pending_until")), 0, "s77 pending cleared")
	# (3) 短いタップは、離した時点で1歩送る (消えない)。
	_reset_keys()
	_check(tab.handle_key(_key(KEY_UP)), "s77 tap up handled")
	tab.release_held_move(_key(KEY_UP))
	_check_eq(_queue(), ["go N"], "s77 tap sends on release")
	# (4) 期限が来たら、その時点の合成で1歩送る。
	_reset_keys()
	_check(tab.handle_key(_key(KEY_UP)), "s77 hold up handled")
	tab.set("_held_step_pending_until", 1)
	tab._held_step_pending_tick()
	_check_eq(_queue(), ["go N"], "s77 deadline sends one step")
	# (5) 保持が流れた後の追加キーは即座に斜めを送る。
	_check(tab.handle_key(_key(KEY_RIGHT)), "s77 late right handled")
	_check_eq(_queue(), ["go N", "go N", "go E"], "s77 late chord sends at once")
	# (6) 回転キーのタップも離した時点で送る。
	_reset_keys()
	_check(tab.handle_key(_key(KEY_9)), "s77 nine handled")
	tab.release_held_move(_key(KEY_9))
	_check_eq(_queue(), ["turn r"], "s77 turn tap sends on release")
	_reset_keys()


func _test_list_focus() -> void:
	var tab := _tab
	_check(tab.input_box.has_focus(), "s77 input focused")
	var lines: Array[String] = ["[ 1] wizard eye", "[ 2] cure", "[ 3] harm"]
	tab.set("_list_lines", lines)
	tab.set("_list_active", true)
	tab._show_list_overlay()
	_queue().clear()
	# (7) フォーカスが入力欄にあっても、テンキーで直接選べる。
	_check(tab.handle_key(_key(KEY_KP_3)), "s77 kp3 handled in list")
	_check_eq(_queue(), ["3"], "s77 kp3 sends row 3")
	_check_eq(tab.input_box.text, "", "s77 kp3 not typed")
	# (8) リストを出し直し、↓ はリストの選択移動になる。
	tab.set("_list_active", true)
	tab._show_list_overlay()
	var box: ItemList = tab.get("_list_box")
	box.select(0)
	_check(tab.handle_key(_key(KEY_DOWN)), "s77 down handled in list")
	_check_eq(Array(box.get_selected_items()), [1], "s77 down moves list selection")
	# (9) リストが扱わない文字キーは入力欄へ流れる (消費しない)。
	_check(not tab.handle_key(_key(KEY_H)), "s77 letter passes to input")
	tab.set("_list_active", false)
	tab._hide_list_overlay()
