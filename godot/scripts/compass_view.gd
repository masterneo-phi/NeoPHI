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
## 地図の様式("turn"=回転 / "solid"=北固定)。文字の描画は MapView 側の
## オーバーレイが行う(本体は半透明で文字が薄れて読みにくいため)。
## ここは状態と文言だけを持つ。
var mode_style := "solid"


func mode_text() -> String:
	## 様式の表示文言(MapView のオーバーレイが使う)。
	return "回転" if mode_style == "turn" else "北固定"


func set_mode_style(p_style: String) -> void:
	if p_style == mode_style:
		return
	mode_style = p_style
	queue_redraw()


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


const CELL := 50
const CELL_RADIUS := 10.0

static var _rounded_cache: Dictionary = {}


static func rounded_direction_texture(tex: Texture2D) -> Texture2D:
	## Direction.bmp(50x50 のセルが横に並ぶ)の各セルの角を
	## 丸めたテクスチャを返す。角の外側を透明にする
	## (ユーザーの要望)。結果はキャッシュする。
	if tex == null:
		return null
	var rid := tex.get_rid()
	if _rounded_cache.has(rid):
		return _rounded_cache[rid]
	var img := tex.get_image()
	if img == null or img.get_height() != CELL or img.get_width() % CELL != 0:
		_rounded_cache[rid] = tex
		return tex
	img = img.duplicate()
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	var center := Vector2(CELL, CELL) * 0.5
	for cx in range(0, img.get_width(), CELL):
		for y in CELL:
			for x in CELL:
				var p := Vector2(x + 0.5, y + 0.5) - center
				var q := Vector2(absf(p.x), absf(p.y)) - (center - Vector2(CELL_RADIUS, CELL_RADIUS))
				var dist := Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length() + minf(maxf(q.x, q.y), 0.0) - CELL_RADIUS
				var alpha := clampf(0.5 - dist, 0.0, 1.0)
				if alpha < 1.0:
					var col := img.get_pixel(cx + x, y)
					col.a *= alpha
					img.set_pixel(cx + x, y, col)
	var out := ImageTexture.create_from_image(img)
	_rounded_cache[rid] = out
	return out


func _draw() -> void:
	var idx := cell_index(dir_num, north_fix)
	if direction_tex != null and direction_tex.get_width() >= (idx + 1) * 50 and direction_tex.get_height() >= 50:
		draw_texture_rect_region(direction_tex, Rect2(Vector2.ZERO, size), Rect2(idx * 50, 0, 50, 50))
	else:
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
