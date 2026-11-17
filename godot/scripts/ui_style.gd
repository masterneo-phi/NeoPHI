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
## フロートパネル(ツールバー/リスト)の角丸半径。目立つように
## 通常より大きめ(ユーザーの要望)。
const FLOAT_RADIUS := 12
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


static func round_box(box: StyleBoxFlat, radius: int = CORNER_RADIUS) -> StyleBoxFlat:
	## StyleBoxFlat の四隅を丸める。半径は既定で共通の値。
	box.set_corner_radius_all(radius)
	return box


static func metal_button_stylebox(state: String) -> StyleBox:
	## ボタン用の金属プレート。世界名ヘッダーと同じ銀板
	## (plate_texture)を九分割で貼る。状態で明るさを変える。
	## テクスチャが作れない時は銀色の単色で代用する。
	var modulate := Color(1, 1, 1)
	var font_color := Color(0.13, 0.13, 0.14)
	match state:
		"hover":
			modulate = Color(1.13, 1.13, 1.13)
		"pressed":
			modulate = Color(0.80, 0.80, 0.82)
		"disabled":
			modulate = Color(0.72, 0.72, 0.72, 0.65)
			font_color = Color(0.38, 0.38, 0.38)
	var tex := plate_texture(Vector2i(48, 28))
	if tex == null:
		var flat := StyleBoxFlat.new()
		flat.bg_color = Color(0.72, 0.73, 0.75) * modulate
		flat.set_corner_radius_all(CORNER_RADIUS)
		flat.content_margin_left = 10
		flat.content_margin_right = 10
		flat.content_margin_top = 4
		flat.content_margin_bottom = 4
		return flat
	var sb := StyleBoxTexture.new()
	sb.texture = tex
	sb.texture_margin_left = 12
	sb.texture_margin_right = 12
	sb.texture_margin_top = 10
	sb.texture_margin_bottom = 10
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	sb.modulate_color = modulate
	return sb


static func apply_metal_button(button: Button) -> void:
	## ボタン1個に金属プレートの見た目を付ける(テーマ側でなく
	## 個別に付ける版)。フロートパネル(リスト/ツールバー)など、
	## ダイアログテーマの外にあるボタン用。
	for state_name in ["normal", "hover", "pressed", "disabled", "focus"]:
		button.add_theme_stylebox_override(state_name, metal_button_stylebox(state_name))
	button.add_theme_color_override("font_color", metal_button_font_color("normal"))
	button.add_theme_color_override("font_hover_color", metal_button_font_color("hover"))
	button.add_theme_color_override("font_pressed_color", metal_button_font_color("pressed"))
	button.add_theme_color_override("font_disabled_color", metal_button_font_color("disabled"))
	button.add_theme_color_override("font_focus_color", metal_button_font_color("normal"))


static func metal_button_font_color(state: String) -> Color:
	## metal_button_stylebox と対になる文字色。
	return Color(0.38, 0.38, 0.38) if state == "disabled" else Color(0.13, 0.13, 0.14)


static func window_plate_stylebox() -> StyleBoxFlat:
	## ウィンドウ/ダイアログの土台プレート。フロート窓と同じ
	## 半透過の暗い板(角丸12+細い縁)。
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.15, 0.15, 0.16, 0.88)
	sb.set_corner_radius_all(FLOAT_RADIUS)
	sb.set_border_width_all(1)
	sb.border_color = Color(0.55, 0.55, 0.55, 0.8)
	return sb


static func window_frame() -> PanelContainer:
	## 窓の中身を包む枠プレート。土台を中身側で描くことで、
	## タイトル帯の地が描かれない環境(Mac)でも、題名や×ボタンが
	## 枠の外に浮かず枠の中に収まる(ユーザーの指定)。
	var frame := PanelContainer.new()
	var sb := window_plate_stylebox()
	sb.content_margin_left = 10
	sb.content_margin_top = 8
	sb.content_margin_right = 10
	sb.content_margin_bottom = 8
	frame.add_theme_stylebox_override("panel", sb)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return frame


## 窓のタイトル色 (濃紺)。タイトル行の地は黒ではなく濃紺にする
## (ユーザーの指定 2026-11-16。最初の色は濃すぎたので明るめに調整)。
const TITLE_NAVY := Color(0.13, 0.22, 0.52, 0.97)


static func title_band(content: Control) -> PanelContainer:
	## タイトル行を濃紺の帯で包む。全ての窓・ダイアログの題名行は
	## これを通す。
	var band := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = TITLE_NAVY
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 10
	sb.content_margin_right = 6
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	band.add_theme_stylebox_override("panel", sb)
	band.add_child(content)
	return band


static func fit_popup_size(want: Vector2i, root_size: Vector2i) -> Vector2i:
	## ポップアップ窓の大きさを親窓に収まる範囲に丸める。窓が親より
	## 大きいと中央寄せではみ出し、右端の × ボタンが見えなくなる
	## (ユーザーの報告)。余白は左右・上下に少し取る。
	return Vector2i(
		mini(want.x, maxi(280, root_size.x - 24)),
		mini(want.y, maxi(200, root_size.y - 24)))


static var _plate_cache: Dictionary = {}


static func plate_texture(size: Vector2i) -> Texture2D:
	## 世界名ヘッダー用の金属プレート。大きさに合わせて、
	## ブラシ目入りの銀板を画像で作る(角丸+上下の縁の
	## ハイライト/影付き)。質感は決定的な疑似ノイズで作る。
	## 大きさごとにキャッシュする(上限を超えたら捨てる)。
	if size.x < 8 or size.y < 8:
		return null
	if _plate_cache.has(size):
		return _plate_cache[size]
	if _plate_cache.size() > 24:
		_plate_cache.clear()
	var img := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	var radius := 6.0
	var center := Vector2(size) * 0.5
	for y in size.y:
		var v := float(y) / float(maxi(size.y - 1, 1))
		var base := 0.88 - 0.20 * v + 0.05 * exp(-pow((v - 0.30) * 4.0, 2.0))
		var row_jitter := 0.03 * (absf(fmod(sin(float(y) * 12.9898) * 43758.5453, 1.0)) - 0.5)
		for x in size.x:
			var p := Vector2(x + 0.5, y + 0.5) - center
			var q := Vector2(absf(p.x), absf(p.y)) - (center - Vector2(radius, radius))
			var dist := Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length() + minf(maxf(q.x, q.y), 0.0) - radius
			var alpha := clampf(0.5 - dist, 0.0, 1.0)
			var brush := 0.020 * sin(float(x) * 0.11 + float(y) * 1.7) + 0.014 * sin(float(x) * 0.031 - float(y) * 0.7)
			var lum := base + brush + row_jitter
			# 縁: 上端は明るく、下端は暗く(プレートの厚み)。
			if y == 0:
				lum += 0.10
			elif y == size.y - 1:
				lum -= 0.14
			# 外周1pxは輪郭として少し暗くする。
			if dist > -1.5:
				lum -= 0.18
			lum = clampf(lum, 0.0, 1.0)
			img.set_pixel(x, y, Color(lum * 0.97, lum * 0.99, lum * 1.03, alpha))
	var tex := ImageTexture.create_from_image(img)
	_plate_cache[size] = tex
	return tex


static var _dialog_cache: Dictionary = {}


static func dialog_texture(size: Vector2i) -> Texture2D:
	## 新規作成ダイアログ用の、豪華な金属板テクスチャ。
	## 暗めのブラシ目金属に金の縁取りと内側の彫り込み線を入れ、
	## 角丸(半径 FLOAT_RADIUS)のアルファを焼き込む。
	## 大きさごとにキャッシュする(上限を超えたら捨てる)。
	if size.x < 32 or size.y < 32:
		return null
	if _dialog_cache.has(size):
		return _dialog_cache[size]
	if _dialog_cache.size() > 8:
		_dialog_cache.clear()
	var img := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	var radius := float(FLOAT_RADIUS)
	var center := Vector2(size) * 0.5
	# ブラシ目は列ごとに先に計算する(全ピクセルでの sin を避ける)。
	var col_brush := PackedFloat32Array()
	col_brush.resize(size.x)
	for x in size.x:
		col_brush[x] = 0.016 * sin(float(x) * 0.11) + 0.011 * sin(float(x) * 0.031 + 1.3)
	for y in size.y:
		var v := float(y) / float(maxi(size.y - 1, 1))
		var base := 0.34 - 0.13 * v + 0.05 * exp(-pow((v - 0.22) * 4.0, 2.0))
		var row_jitter := 0.02 * (absf(fmod(sin(float(y) * 12.9898) * 43758.5453, 1.0)) - 0.5)
		for x in size.x:
			var p := Vector2(x + 0.5, y + 0.5) - center
			var q := Vector2(absf(p.x), absf(p.y)) - (center - Vector2(radius, radius))
			var dist := Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length() + minf(maxf(q.x, q.y), 0.0) - radius
			var alpha := clampf(0.5 - dist, 0.0, 1.0)
			var lum := base + col_brush[x] * (0.6 + 0.4 * sin(float(y) * 1.7)) + row_jitter
			var col := Color(lum * 1.02, lum * 0.99, lum * 0.94, alpha)
			# 金の縁取り: 外周から約4px、dist=-2 あたりで最も濃い。
			if dist > -4.5:
				var gold_t := clampf(1.0 - absf(dist + 2.0) / 2.5, 0.0, 1.0)
				var gold := Color(0.62 + 0.25 * gold_t, 0.45 + 0.20 * gold_t, 0.16 + 0.10 * gold_t, alpha)
				col = col.lerp(gold, 0.35 + 0.65 * gold_t)
			# 縁の内側に彫り込みの線(暗)と、その内側に細い光の線。
			if dist >= -6.5 and dist < -5.5:
				col = Color(col.r * 0.55, col.g * 0.55, col.b * 0.55, alpha)
			elif dist >= -7.5 and dist < -6.5:
				col = Color(minf(col.r + 0.13, 1.0), minf(col.g + 0.13, 1.0), minf(col.b + 0.12, 1.0), alpha)
			# 最外周は輪郭として少し暗くする。
			if dist > -1.0:
				col = Color(col.r * 0.7, col.g * 0.7, col.b * 0.7, alpha)
			img.set_pixel(x, y, col)
	var tex := ImageTexture.create_from_image(img)
	_dialog_cache[size] = tex
	return tex


static var _check_cache: Dictionary = {}


static func check_texture(px: int) -> Texture2D:
	## メニューのチェック項目の印。テーマ標準の印が小さくて
	## 見づらいので、文字の大きさに合わせた太いチェックを
	## 描いて返す。大きさごとにキャッシュする。
	if px <= 0:
		return null
	if _check_cache.has(px):
		return _check_cache[px]
	var img := Image.create(px, px, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var a := Vector2(px * 0.16, px * 0.54)
	var b := Vector2(px * 0.40, px * 0.78)
	var c := Vector2(px * 0.86, px * 0.24)
	var half := px * 0.085
	for y in px:
		for x in px:
			var p := Vector2(x + 0.5, y + 0.5)
			var d: float = minf(_seg_dist(p, a, b), _seg_dist(p, b, c))
			var alpha: float = clampf(half + 0.75 - d, 0.0, 1.0)
			if alpha > 0.0:
				img.set_pixel(x, y, Color(1, 1, 1, alpha))
	var tex: Texture2D = ImageTexture.create_from_image(img)
	_check_cache[px] = tex
	return tex


static func _seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	## 点 p と線分 a-b の距離。
	var ab := b - a
	var t := 0.0
	var len2 := ab.length_squared()
	if len2 > 0.0:
		t = clampf((p - a).dot(ab) / len2, 0.0, 1.0)
	return (a + ab * t - p).length()


static func viewport_region(img_size: Vector2i, vp_size: Vector2, rect: Rect2) -> Rect2i:
	## ビューポート画像(実ピクセル)の中での、コントロールの
	## 矩形(論理座標)の位置。Retina など表示倍率が1でない
	## 環境でも合うよう、画像サイズとビューポートサイズの
	## 比で拡縮して画像の範囲内に収める。
	if vp_size.x <= 0.0 or vp_size.y <= 0.0:
		return Rect2i()
	var scale := Vector2(float(img_size.x) / vp_size.x, float(img_size.y) / vp_size.y)
	var scaled := Rect2(rect.position * scale, rect.size * scale)
	var region := Rect2i(scaled).intersection(Rect2i(0, 0, img_size.x, img_size.y))
	return region


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
