class_name MetalHSlit
extends Control
## 横向きの金属スリットの帯。タブ行と地図・ログの領域の
## 境界に置く。見た目は分割の境目の溝と揃える。
## マウスは通し、タブの操作には影響しない。

const HEIGHT := 8.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(0, HEIGHT)


func _ready() -> void:
	resized.connect(queue_redraw)
	queue_redraw()


func _draw() -> void:
	UiStyle.draw_groove(self, Rect2(Vector2.ZERO, size), false)
