class_name PhiWindowDrag
extends RefCounted
## 埋め込み窓の中身の先頭行をドラッグハンドルにする。
##
## 埋め込み窓のタイトル帯(テーマの title_height)は 0 にしてあり、
## 掴む場所は枠より上の見えない帯ではなく、見えている題名行
## そのものにする。band_height > 0 の時は、ハンドルの上端から
## その高さの範囲で掴んだ時だけドラッグを始める(ダイアログの
## 枠全体をハンドルにする場合用)。

var _window: Window = null
var _band := 0.0
var _dragging := false


static func attach(handle: Control, window: Window, band_height: float = 0.0) -> void:
	var drag := PhiWindowDrag.new()
	drag._window = window
	drag._band = band_height
	handle.set_meta("phi_window_drag", drag)
	handle.mouse_filter = Control.MOUSE_FILTER_STOP
	_click_through(handle)
	handle.gui_input.connect(drag._on_gui_input)


static func _click_through(node: Node) -> void:
	# ハンドルの中でクリックを飲むだけの子は素通しにし、行の
	# どこを掴んでもドラッグが始まるようにする。
	# - ラベル: 文字の上からでも掴めるように。
	# - 余白用のただの Control (子なし・横に広がるもの):
	#   題名行の空白部分がこれに当たる。
	for child in node.get_children():
		if child is Label:
			(child as Label).mouse_filter = Control.MOUSE_FILTER_IGNORE
		elif child is Control and child.get_child_count() == 0 \
				and child.get_class() == "Control" \
				and ((child as Control).size_flags_horizontal & Control.SIZE_EXPAND_FILL) != 0:
			(child as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
		_click_through(child)


func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_dragging = mb.pressed and (_band <= 0.0 or mb.position.y <= _band)
	elif event is InputEventMouseMotion and _dragging:
		_window.position += Vector2i((event as InputEventMouseMotion).relative)
