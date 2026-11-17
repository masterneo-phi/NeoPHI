extends SceneTree
## 第81段のテスト: リストがフォーカスを持ったまま閉じると、
## Godot が入力欄へフォーカスを移してしまう。閉じる前に
## リスト側のフォーカスを外し、キー操作をゲーム側に戻す。
## 入力欄にフォーカスがあった場合は、そのまま残す。
##
## 使い方: godot --headless --path . -s tests/test_stage81.gd
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
		_test_list_focus()
		_show()
	elif _frames == 7:
		_test_input_focus_kept()
		print("test_stage81: ", _checks, " checks, ", _failures, " failures")
		quit(1 if _failures > 0 else 0)


func _test_list_focus() -> void:
	var tab := _tab
	var box: ItemList = tab.get("_list_box")
	box.grab_focus()
	_check(box.has_focus(), "s81 list has focus before decide")
	tab._send_list_row(1)
	_check(not tab.get("_list_active"), "s81 list closed")
	_check(not box.has_focus(), "s81 list focus released")
	_check(not tab.input_box.has_focus(), "s81 focus did not move to input")
	_check(root.gui_get_focus_owner() == null, "s81 no focus owner")


func _test_input_focus_kept() -> void:
	var tab := _tab
	tab.input_box.grab_focus()
	_check(tab.input_box.has_focus(), "s81 input has focus before decide")
	tab._send_list_row(0)
	_check(not tab.get("_list_active"), "s81 list closed again")
	_check(tab.input_box.has_focus(), "s81 input focus kept")
