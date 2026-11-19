extends SceneTree
## 第112段のテスト: リストをテンキーで選んだ後にフォーカスが
## 入力欄へ移らないこと (第81段・第90段の保証を、実キー経路
## handle_key とフロートスタイルで固定する)。選択前の
## フォーカス状態を変えて Numpad2 を押し、閉じた直後と
## 次フレームのフォーカス所有者を見る。
##
## 使い方: godot --headless --path . -s tests/test_stage112.gd

var _failures := 0
var _checks := 0
var _tab: PhiCharacter = null
var _frames := 0
var _case := 0


func _check(cond: bool, label: String) -> void:
	_checks += 1
	if not cond:
		_failures += 1
		printerr("FAIL: ", label)


func _show() -> void:
	var lines: Array[String] = ["[ 1] wizard eye", "[ 2] cure", "[ 3] harm"]
	_tab.set("_list_lines", lines)
	_tab.set("_list_active", true)
	_tab._show_list_overlay()


func _key(keycode: Key) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.pressed = true
	ev.keycode = keycode
	ev.physical_keycode = keycode
	ev.unicode = 0
	return ev


func _owner_name() -> String:
	var owner := root.gui_get_focus_owner()
	if owner == null:
		return "<null>"
	return owner.get_path()


var _pending_pre := ""


func _run_case(pre: String) -> void:
	_show()
	match pre:
		"none":
			root.gui_release_focus()
		"map":
			_tab.map_view.grab_focus()
		"listbox":
			(_tab.get("_list_box") as Control).grab_focus()
		"cancel":
			(_tab.get("_list_cancel_button") as Control).grab_focus()
		"input":
			_tab.input_box.grab_focus()
	_pending_pre = pre
	var before := _owner_name()
	var handled: bool = _tab.handle_key(_key(KEY_KP_2))
	print("case ", pre, ": before=", before, " handled=", handled, " (focus checked next frame)")


func _check_case(pre: String) -> void:
	var after := _owner_name()
	print("case ", pre, ": after=", after, " input_focused=", _tab.input_box.has_focus())
	_check(not _tab.get("_list_active"), "s112 list closed (" + pre + ")")
	if pre == "input":
		_check(_tab.input_box.has_focus(), "s112 input focus kept (input)")
	else:
		_check(not _tab.input_box.has_focus(), "s112 focus must not move to input (" + pre + ")")


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
	_tab.map_view.size = Vector2(1280, 1024)
	_tab.apply_ui_style()
	print("float_mode=", _tab.get("_float_mode"))
	process_frame.connect(_on_frame)


func _on_frame() -> void:
	_frames += 1
	if _frames < 3:
		return
	var cases: Array[String] = ["none", "map", "listbox", "cancel", "input"]
	if _pending_pre != "":
		_check_case(_pending_pre)
		_pending_pre = ""
		_case += 1
		return
	if _case < cases.size():
		_run_case(cases[_case])
	else:
		print("test_stage112: ", _checks, " checks, ", _failures, " failures")
		quit(1 if _failures > 0 else 0)
