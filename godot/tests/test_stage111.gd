extends SceneTree
## 第111段のテスト: 実物の Main に本物のキーイベントを流す。
## 元々の不具合は「入力中に回転マップが発動する」ことだけ
## で、犯人は閉じたメニューのアクセラレータ (MTurn = T 等)
## だった (macOS では IME の変換開始キーが TextEdit に
## 受け取られずアクセラレータに届く)。対策はアクセラレータ
## を Alt 組み合わせだけにすること (test_stage1 で監査)。
## 1文字コマンド自体は当初の割り当てのまま。回転 (T) は
## 後付けなので Option+T のトグルへ移した: T 単独では
## フォーカスの有無によらず何も送らず、フォーカスがあれば
## 文字として入力欄に入る。ここではその両方と Option+T
## トグルの通り道を固定する。
##
## 使い方: godot --headless --path . -s tests/test_stage111.gd
## 終了コード 0 = 全一致、1 = 不一致あり。

var _frames := 0
var _main: Node = null
var _tab: PhiCharacter = null
var _phase := 0
var _failures := 0
var _checks := 0


func _check(cond: bool, label: String) -> void:
	_checks += 1
	if not cond:
		_failures += 1
		printerr("FAIL: ", label)


func _initialize() -> void:
	var ps := load("res://main.tscn") as PackedScene
	_main = ps.instantiate()
	_main.set("_tab_session_path", "user://stage111_tabs.ini")
	_main.set("_config_path", "user://stage111_config.ini")
	root.add_child(_main)
	process_frame.connect(_on_frame)


func _feed(keycode: Key, unicode: int = 0, shift: bool = false, alt: bool = false) -> void:
	var ev := InputEventKey.new()
	ev.pressed = true
	ev.keycode = keycode
	ev.physical_keycode = keycode
	ev.unicode = unicode
	ev.shift_pressed = shift
	ev.alt_pressed = alt
	Input.parse_input_event(ev)
	var up := InputEventKey.new()
	up.pressed = false
	up.keycode = keycode
	up.physical_keycode = keycode
	Input.parse_input_event(up)


func _on_frame() -> void:
	_frames += 1
	match _phase:
		0:
			if _frames >= 5:
				_tab = _main.call("_create_tab")
				_main.call("_activate_tab", _tab)
				_phase = 1
				_frames = 0
		1:
			if _frames >= 3:
				root.gui_release_focus()
				var queue: Array = _tab.session.get("_send_queue")
				queue.clear()
				_feed(KEY_T, "t".unicode_at(0))
				_phase = 2
				_frames = 0
		2:
			if _frames >= 3:
				# フォーカスなしの T でも何も送らない (回転
				# キーは Option+T のトグルへ移した)。
				var queue: Array = _tab.session.get("_send_queue")
				_check(queue.is_empty(), "s111 unfocused T sends nothing (got %s)" % [queue])
				queue.clear()
				_tab.input_box.grab_focus()
				_phase = 3
				_frames = 0
		3:
			if _frames >= 3:
				_feed(KEY_T, "t".unicode_at(0))
				_phase = 4
				_frames = 0
		4:
			if _frames >= 3:
				# フォーカスありの T は文字として入り、何も
				# 送らない (アクセラレータが無いことの確認)。
				var queue2: Array = _tab.session.get("_send_queue")
				_check(queue2.is_empty(), "s111 focused T sends nothing (got %s)" % [queue2])
				_check(_tab.input_box.text.contains("t"), "s111 T reached the input box")
				queue2.clear()
				_tab.input_box.release_focus()
				_phase = 5
				_frames = 0
		5:
			if _frames >= 3:
				# Option+T はトグル: 今が北固定なので回転へ。
				_feed(KEY_T, 0, false, true)
				_phase = 6
				_frames = 0
		6:
			if _frames >= 3:
				var queue3: Array = _tab.session.get("_send_queue")
				_check(queue3 == ["#ex-map style=turn"], "s111 Alt+T toggles to turn (got %s)" % [queue3])
				print("test_stage111: ", _checks, " checks, ", _failures, " failures")
				quit(1 if _failures > 0 else 0)
