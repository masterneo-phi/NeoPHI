class_name OuterFrame
extends Control
## 画面の外周の金属の外枠。ウインドウの四辺の内側に、
## ベベルの光と影で縁らしく見せる。質感は金属テクスチャや
## スリットと揃えたガンメタル系。
##
## 中身はこの幅ぶん内側に置く(メイン画面が MarginContainer で
## 下げる)。マウスは通すので、枠の内側の操作を妨げない。

const WIDTH := 6.0

const _FILL := Color(0.20, 0.215, 0.235)
const _LIGHT := Color(0.55, 0.58, 0.63)
const _DARK := Color(0.05, 0.05, 0.06)
const _INNER_LIGHT := Color(0.45, 0.48, 0.53)
const _INNER_DARK := Color(0.08, 0.08, 0.09)


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	resized.connect(queue_redraw)
	queue_redraw()


func _draw() -> void:
	var w := size.x
	var h := size.y
	if w <= WIDTH * 2.0 or h <= WIDTH * 2.0:
		return
	# 地(四辺の帯)。
	draw_rect(Rect2(0, 0, w, WIDTH), _FILL)
	draw_rect(Rect2(0, h - WIDTH, w, WIDTH), _FILL)
	draw_rect(Rect2(0, WIDTH, WIDTH, h - WIDTH * 2.0), _FILL)
	draw_rect(Rect2(w - WIDTH, WIDTH, WIDTH, h - WIDTH * 2.0), _FILL)
	# 外周のベベル: 上と左に光、下と右に影。
	draw_rect(Rect2(0, 0, w, 1), _LIGHT)
	draw_rect(Rect2(0, 0, 1, h), _LIGHT)
	draw_rect(Rect2(0, h - 1, w, 1), _DARK)
	draw_rect(Rect2(w - 1, 0, 1, h), _DARK)
	# 内周のベベル: 外周と逆(上と左に影、下と右に光)にして、
	# 帯が浮き出た縁に見えるようにする。
	var i := WIDTH - 1.0
	draw_rect(Rect2(i, i, w - i * 2.0, 1), _INNER_DARK)
	draw_rect(Rect2(i, i, 1, h - i * 2.0), _INNER_DARK)
	draw_rect(Rect2(i, h - WIDTH, w - i * 2.0, 1), _INNER_LIGHT)
	draw_rect(Rect2(w - WIDTH, i, 1, h - i * 2.0), _INNER_LIGHT)
