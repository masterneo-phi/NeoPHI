class_name UiStyle
extends RefCounted
## UI の見た目の共通部品。角丸の半径、金属テクスチャの
## 読み込み、金属の溝(スリット)の描画をここに集める。
##
## 金属テクスチャは assets/metal.png(tools/make_metal_texture.py
## で生成)。壁紙やロゴと同じ流儀で、無ければ無いなりに
## (単色の地で)動くよう、防御的に読み込む。

## 枠の角丸の半径。全体でこの値に統一する。
const CORNER_RADIUS := 6
const METAL_PATH := "res://assets/metal.png"

static var _metal_tex: Texture2D = null
static var _metal_tried := false


static func metal_texture() -> Texture2D:
	## 金属テクスチャ。ファイルが無ければ null(呼び出し側で
	## 単色にフォールバックする)。
	if not _metal_tried:
		_metal_tried = true
		if ResourceLoader.exists(METAL_PATH):
			_metal_tex = load(METAL_PATH) as Texture2D
	return _metal_tex


static func round_box(box: StyleBoxFlat) -> StyleBoxFlat:
	## StyleBoxFlat の四隅を共通の半径で丸める。
	box.set_corner_radius_all(CORNER_RADIUS)
	return box


static func draw_groove(ci: CanvasItem, rect: Rect2, vertical: bool) -> void:
	## 細い金属の溝。地を少し沈ませ、影の線と光の線を並べて
	## 溝らしく見せる。vertical=true は縦の溝(横分割の境目)、
	## false は横の溝(縦分割の境目)。
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return
	ci.draw_rect(rect, Color(0.105, 0.11, 0.12))
	if vertical:
		var cx := rect.position.x + rect.size.x * 0.5
		ci.draw_rect(Rect2(cx - 1.0, rect.position.y, 1.0, rect.size.y), Color(0.04, 0.04, 0.05))
		ci.draw_rect(Rect2(cx, rect.position.y, 1.0, rect.size.y), Color(0.42, 0.45, 0.50))
	else:
		var cy := rect.position.y + rect.size.y * 0.5
		ci.draw_rect(Rect2(rect.position.x, cy - 1.0, rect.size.x, 1.0), Color(0.04, 0.04, 0.05))
		ci.draw_rect(Rect2(rect.position.x, cy, rect.size.x, 1.0), Color(0.42, 0.45, 0.50))
