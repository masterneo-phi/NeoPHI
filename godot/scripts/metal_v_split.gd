class_name MetalVSplit
extends VSplitContainer
## ログと入力欄の境目に、細い金属の溝を描く縦分割。
## ドラッグ(入力欄の高さの変更)の振る舞いは
## VSplitContainer のまま。


func _init() -> void:
	resized.connect(queue_redraw)
	dragged.connect(func(_offset: int) -> void: queue_redraw())


func _ready() -> void:
	queue_redraw()


func _draw() -> void:
	if get_child_count() < 2:
		return
	var a := get_child(0) as Control
	var b := get_child(1) as Control
	if a == null or b == null:
		return
	var y0 := a.position.y + a.size.y
	var rect := Rect2(0.0, y0, size.x, b.position.y - y0)
	UiStyle.draw_groove(self, rect, false)
