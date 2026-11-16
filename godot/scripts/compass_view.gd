class_name CompassView
extends Control
## 方角コンパス。スキンの `Images/Direction.bmp`(50x50 が8つ並ぶ)の
## セルを出す。無ければ円＋方角文字＋針を描く。
## Philly の DrawDirection: セルは N=0, W=2, S=4, E=6(奇数は半分の絵)。
## 北固定の時はつねに N のセル。

var direction_tex: Texture2D = null
var label_font: Font = null
var dir_num := 0
var north_fix := true


func _init() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(50, 50)


static func cell_index(p_dir_num: int, p_north_fix: bool) -> int:
	## 地図イベントの dir(N=0, E=2, S=4, W=6、時計回り)→ Direction.bmp のセル。
	if p_north_fix:
		return 0
	return (8 - (p_dir_num & 7)) % 8


func set_direction(p_dir_num: int, p_north_fix: bool) -> void:
	if p_dir_num == dir_num and p_north_fix == north_fix:
		return
	dir_num = p_dir_num
	north_fix = p_north_fix
	queue_redraw()


func _draw() -> void:
	var idx := cell_index(dir_num, north_fix)
	if direction_tex != null and direction_tex.get_width() >= (idx + 1) * 50 and direction_tex.get_height() >= 50:
		draw_texture_rect_region(direction_tex, Rect2(Vector2.ZERO, size), Rect2(idx * 50, 0, 50, 50))
		return
	_draw_fallback(idx)


func _draw_fallback(idx: int) -> void:
	## 代用のコンパス: 丸い盤＋方角文字＋針。
	var center := size * 0.5
	var radius := minf(size.x, size.y) * 0.5
	draw_circle(center, radius, Color(0.92, 0.89, 0.80))
	draw_arc(center, radius - 1.0, 0.0, TAU, 48, Color(0.25, 0.20, 0.15), 2.0)
	draw_arc(center, radius * 0.62, 0.0, TAU, 48, Color(0.25, 0.20, 0.15, 0.4), 1.0)
	if label_font != null:
		var font_size := int(maxf(8.0, size.x * 0.18))
		var letter_color := Color(0.2, 0.16, 0.12)
		var inset := radius * 0.72
		var letters := {"N": Vector2(0, -inset), "E": Vector2(inset, 0), "S": Vector2(0, inset), "W": Vector2(-inset, 0)}
		for letter in letters:
			var at: Vector2 = letters[letter]
			var w := label_font.get_string_size(letter, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
			var h := label_font.get_height(font_size)
			draw_string(label_font, center + at + Vector2(-w * 0.5, h * 0.35), letter, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, letter_color)
	# 針: セル番号の反時計回りの角度に向ける(0=N, 2=W, 4=S, 6=E)。
	var angle := -float(idx) * PI / 4.0
	var dir_vec := Vector2(sin(angle), -cos(angle))
	var side := Vector2(-dir_vec.y, dir_vec.x)
	var tip := center + dir_vec * radius * 0.82
	var tail := center - dir_vec * radius * 0.55
	var half := side * radius * 0.16
	draw_colored_polygon(PackedVector2Array([tip, center + half, center - half]), Color(0.85, 0.20, 0.15))
	draw_colored_polygon(PackedVector2Array([tail, center + half, center - half]), Color(0.95, 0.95, 0.95))
	draw_circle(center, radius * 0.10, Color(0.25, 0.20, 0.15))
