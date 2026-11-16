class_name MetalHSplit
extends HSplitContainer
## 地図列とログ列の境目に、細い金属の溝を描く横分割。
## ドラッグ(比率の変更)の振る舞いは HSplitContainer のまま。


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
	var x0 := a.position.x + a.size.x
	var rect := Rect2(x0, 0.0, b.position.x - x0, size.y)
	UiStyle.draw_groove(self, rect, true)
