extends SceneTree
## 第17段のテスト: 窓ドラッグの残件。
## - 確認ダイアログの題名行にドラッグが付き、合成入力で動く。
## - 題名行の余白 (spacer) がクリック素通しになる (ボタンは残る)。
##
## 使い方: godot --headless --path . -s tests/test_stage17.gd
## 終了コード 0 = 全一致、1 = 不一致あり。

var _failures := 0
var _checks := 0
var _main: Node = null


func _check(cond: bool, label: String) -> void:
	_checks += 1
	if not cond:
		_failures_add(label)


func _failures_add(label: String) -> void:
	_failures += 1
	printerr("FAIL: ", label)


func _initialize() -> void:
	_run()


func _wait(sec: float) -> void:
	var until := Time.get_ticks_msec() + int(sec * 1000.0)
	while Time.get_ticks_msec() < until:
		await process_frame


func _find_drag_handle(node: Node) -> Control:
	if node is Control and (node as Control).has_meta("phi_window_drag"):
		return node as Control
	for child in node.get_children():
		var found := _find_drag_handle(child)
		if found != null:
			return found
	return null


func _drag_by(control: Control, delta: Vector2) -> void:
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = Vector2(4, 4)
	control.gui_input.emit(press)
	var motion := InputEventMouseMotion.new()
	motion.relative = delta
	control.gui_input.emit(motion)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	control.gui_input.emit(release)


func _test_spacer_rule() -> void:
	var win := Window.new()
	win.size = Vector2i(300, 100)
	root.add_child(win)
	var head := HBoxContainer.new()
	var label := Label.new()
	label.text = "題名"
	head.add_child(label)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(spacer)
	var button := Button.new()
	button.text = "×"
	head.add_child(button)
	win.add_child(head)
	PhiWindowDrag.attach(head, win)
	_check(label.mouse_filter == Control.MOUSE_FILTER_IGNORE, "ラベルは素通し")
	_check(spacer.mouse_filter == Control.MOUSE_FILTER_IGNORE, "余白は素通し")
	_check(button.mouse_filter == Control.MOUSE_FILTER_STOP, "ボタンは素通しにしない")
	win.queue_free()


func _run() -> void:
	_test_spacer_rule()
	var ps := load("res://main.tscn") as PackedScene
	_main = ps.instantiate()
	root.add_child(_main)
	await _wait(1.5)
	_main.call("_ask_text", "Pay")
	await _wait(0.3)
	var ask: Window = _main.get("_ask_dialog")
	_check(ask != null, "ask ダイアログが作られる")
	if ask != null:
		var handle := _find_drag_handle(ask)
		_check(handle != null, "ask ダイアログにドラッグが付く")
		if handle != null:
			var before := ask.position
			_drag_by(handle, Vector2(18, 9))
			_check(ask.position == before + Vector2i(18, 9), "ask ダイアログがドラッグで動く")
		ask.hide()
	print("test_stage17: ", _checks, " checks, ", _failures, " failures")
	quit(1 if _failures > 0 else 0)
