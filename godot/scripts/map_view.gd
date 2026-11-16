class_name MapView
extends Control
## 地図を BMP の絵で描く Control。Python 版 map_graphics.py の移植。
##
## 描く順序は行ごと: ベースチップ → 水縁 → 看板 → アイテム → キャラ。
## 1マス 32px、チップシートの1セルは 32x48px、マップ上部に 16px の余白。
## `zoom` 倍で拡大して描く(ニアレストネイバー)。

## チップ画面セルサイズ(px)。
const CHIP_SIZE := 32
## チップシート1セルの高さ(px)。上16px透過。
const CHIP_HEIGHT := 48
## マップの上の余白(px)。一番上の行のチップのはみ出しの分。
const MAP_TOP := CHIP_HEIGHT - CHIP_SIZE
## チップ総数。
const CHIP_COUNT := 32
## チップシート1行あたりの列数。
const CHIPS_PER_ROW := 16

## 看板overlay用チップ。
const BOARD_CHIP_SOFT := 18
const BOARD_CHIP_HARD := 20
const _HARD_BOARD_CHIPS := [0x40, 0x23, 0x48, 0x3D, 0x5B, 0x7B, 0x7C, 0x25] # @#H=[{|%

## アイテムスプライト1枚サイズ(px)。
const ITEM_SPRITE_SIZE := 32
## 防御円チップbyte('x'=14, '%'=15)。
const _CIRCLE_CHIPS := [0x78, 0x25] # x %
## アイテムを床の上端から上げる量(px)。
const ITEM_Y_ABOVE_FLOOR := 8
## キャラを床の上端から上げる量(px)。
const CHARA_Y_ABOVE_FLOOR := 11
## アイテムクリップ高(円内に収める可視高 = 32-11)。
const ITEM_CLIP_H := ITEM_SPRITE_SIZE - 11

## キャラ通常フレーム幅(px)。
const CHARA_W_NORMAL := 16
## キャラ巨大フレーム幅(px)。
const CHARA_W_GIANT := 32
## キャラ1フレーム高(px)。
const CHARA_H := 32

const _DIR_TO_ROW := {"B": 0, "R": 1, "F": 2, "L": 3}
const _DIR_NUM_TO_CHAR := {0: "B", 1: "B", 2: "R", 3: "F", 4: "F", 5: "F", 6: "L", 7: "B"}

## 水縁チップのベースindex。
const WATER_CHIP_BASE := 23
## 水チップのbyte('_')。
const WATER_BYTE := 0x5F

## チップの文字 → チップの絵の番号(wphi の CHIP_BYTE_TO_INDEX と同じ)。
const CHIP_BYTE_TO_INDEX := {
	0x20: [0], # space
	0x3A: [1], # :
	0x2B: [2], # +
	0x54: [1, 3], # T
	0x5F: [4], # _
	0x6F: [5], # o
	0x40: [6], # @
	0x23: [7], # #
	0x48: [8], # H
	0x49: [9], # I
	0x3D: [10], # =
	0x5B: [11], # [
	0x7B: [12], # {
	0x7C: [13], # |
	0x78: [14], # x
	0x25: [15], # %
	0x2F: [16], # /
	0x3E: [17], # >
	0x3F: [31], # ?
	0x73: [0], # s
}

## 絵が無い時にマスを塗る色(チップindexごと)。
const FALLBACK_CHIP_COLORS := {
	0: Color(0.157, 0.157, 0.157),
	1: Color(0.337, 0.478, 0.227),
	2: Color(0.431, 0.549, 0.275),
	3: Color(0.204, 0.361, 0.157),
	4: Color(0.188, 0.376, 0.627),
	5: Color(0.471, 0.376, 0.251),
	6: Color(0.588, 0.588, 0.588),
	7: Color(0.376, 0.376, 0.376),
	8: Color(0.549, 0.314, 0.235),
	9: Color(0.627, 0.549, 0.353),
	10: Color(0.706, 0.627, 0.471),
	11: Color(0.353, 0.431, 0.510),
	12: Color(0.510, 0.353, 0.431),
	13: Color(0.667, 0.667, 0.667),
	14: Color(0.275, 0.510, 0.510),
	15: Color(0.510, 0.275, 0.510),
	16: Color(0.745, 0.706, 0.549),
	17: Color(0.588, 0.431, 0.275),
	31: Color(0.078, 0.078, 0.078),
}
const FALLBACK_CHIP_DEFAULT := Color(0.251, 0.251, 0.251)

## 浮き数字の色(種類ごと)。Python 版 gui.py の _FLOAT_COLORS と同じ。
const FLOAT_COLORS := {
	"dealt": Color(1.0, 0.824, 0.247),
	"taken": Color(1.0, 0.322, 0.322),
	"heal": Color(0.412, 0.941, 0.682),
	"mp": Color(0.310, 0.765, 0.969),
	"mpdmg": Color(0.310, 0.765, 0.969),
}
## 浮き数字が上がり切るまでの時間(秒)。30コマ × 30ms。
const FLOAT_DURATION := 0.9
## 点滅の1コマの時間(秒)。60ms × 6コマ。
const FLASH_STEP := 0.06
const FLASH_STEPS := 6
## 地図の揺れのパターン。50ms × 6コマ、最後は元に戻ります。
const SHAKE_PATTERN := [Vector2(3, 0), Vector2(-3, 1), Vector2(2, -2), Vector2(-2, 0), Vector2(1, 1), Vector2(0, 0)]
const SHAKE_STEP := 0.05
## 剣の軌跡(対象のみ)のコマ数と間隔、色。
const SLASH_FRAMES := 5
const SLASH_FRAME := 0.036
const SLASH_COLORS := [Color.WHITE, Color.WHITE, Color(0.890, 0.949, 0.992), Color(0.733, 0.871, 0.984), Color(0.565, 0.792, 0.976)]
## 斬撃の軌跡のコマ数と間隔、振り始めの向きと振る角度、色。
const SWING_FRAMES := 6
const SWING_FRAME := 0.03
const SWING_COLORS := [Color.WHITE, Color(0.890, 0.949, 0.992), Color(0.733, 0.871, 0.984), Color(0.565, 0.792, 0.976), Color(0.392, 0.710, 0.965), Color(0.259, 0.647, 0.961)]
const SWING_START := -1.9
const SWING_SWEEP := 2.6
## 風切りの線(円の半径、後れ、太さ)。白い主線の後を、青い線が追います。
const SWING_STREAKS := [[21.0, 0.0, 3.0], [16.0, 0.3, 2.0], [25.0, 0.55, 1.5]]
## 倒れたキャラの消滅: 段階の数と間隔(壁時計ベース)。
const GHOST_STEPS := 8
const GHOST_STEP := 0.08
## `#ex-disp-magic` の1段階の長さ(秒)。Philly は 20ms だが、
## 見えるように少し長くする。3段階で 0.24 秒。
const DISP_MAGIC_PHASE := 0.08
const DISP_MAGIC_PHASES := 3
## サーバー駆動の魔法表示が出たマスで、自前の魔法弾を抑える時間。
const DISP_MAGIC_SUPPRESS_WINDOW := 1.0
## 魔法弾の歩数と間隔、尾の長さと太さ、回る火花の軌道。
const BOLT_STEPS := 10
const BOLT_STEP := 0.028
const BOLT_COLOR := Color(0.310, 0.765, 0.969)
const BOLT_TAIL_LEN := 42.0
const BOLT_TAIL_WIDTH := 7.0
const BOLT_ORBIT_R := 7.0
const BOLT_ORBIT_STEP := 1.1
## 着弾: コマ数と間隔、火花の数、色。
const IMPACT_FRAMES := 6
const IMPACT_FRAME := 0.03
const IMPACT_COLORS := [Color.WHITE, Color(0.882, 0.961, 0.996), Color(0.702, 0.898, 0.988), Color(0.506, 0.831, 0.980), Color(0.310, 0.765, 0.969), Color(0.161, 0.714, 0.965)]
const IMPACT_SPARKS := 8
## 吹き出し: 本文の幅(地図の絵の座標)、行数、表示時間。
const BUBBLE_MAX_WIDTH := 132.0
const BUBBLE_MAX_LINES := 3
const BUBBLE_BASE_MS := 2500.0
const BUBBLE_PER_CHAR_MS := 60.0
const BUBBLE_MAX_MS := 8000.0

## 水縁 quarter 描画テーブル。添字 = quarter(0=TL,1=TR,2=BL,3=BR)。
## 各 quarter で 3bit パターン → [chip_offset, src_quarter]。
const Q_TABLE := [
	{0x00: [1, 0], 0x01: [1, 0], 0x02: [0, 0], 0x03: [0, 0], 0x04: [0, 2], 0x05: [0, 2], 0x06: [2, 3]},
	{0x00: [1, 1], 0x01: [1, 1], 0x02: [0, 1], 0x03: [0, 1], 0x04: [0, 2], 0x05: [0, 2], 0x06: [2, 2]},
	{0x00: [1, 2], 0x01: [1, 2], 0x02: [0, 0], 0x03: [0, 0], 0x04: [0, 3], 0x05: [0, 3], 0x06: [2, 1]},
	{0x00: [1, 3], 0x01: [1, 3], 0x02: [0, 1], 0x03: [0, 1], 0x04: [0, 3], 0x05: [0, 3], 0x06: [2, 0]},
]

## 地図の倍率が変わったことを知らせます。UIの文字サイズの連動に使います。
signal zoom_changed(new_zoom: int)

var zoom := 4
var assets: GameAssets = null
var label_font: Font = null
var mapset := ""
## 自分のキャラの名前。浮き数字の位置決めと詠唱の取り消しに使います。
var player_name := ""
## 拡大の要求フラグ。窓のリサイズと境目のドラッグと地図の大きさの
## 変化(外部からのサイズ変更)でのみ立て、`_update_zoom` が1段階の
## 拡大に使う。レイアウトのフィードバック(文字サイズの変化)では立て
## ないので、拡大→行が伸びる→縮小→行が縮む→拡大、の無限反転は
## 起きない。
var _grow_requested := false
## 前に受けた地図の一辺のマス数。地図の大きさの変化を検知する。
var _last_dim := 0


## 外部からのサイズ変更があったことを知らせる。次の `_update_zoom` で、
## 収まるなら1段階だけ拡大する。テストからも呼べる。
func request_zoom_growth() -> void:
	_grow_requested = true

var _event: Dictionary = {}
var _chip_tex: Texture2D = null
var _items_tex: Texture2D = null

## 浮き数字などの基準点。名前 → 地図の絵の中の座標(中心x、頭の上y)。
var _anchors: Dictionary = {}
var _center_anchor: Variant = null
var _last_charas: Dictionary = {}
var _prev_charas: Dictionary = {}
var _caster_tracker: PhiCombatFx.CasterTracker = null
var _float_seq := 0
var _floats: Array = []
var _flashes: Array = []
var _swings: Array = []
var _slashes: Array = []
var _bolts: Array = []
var _impacts: Array = []
var _ghosts: Array = []
var _bubbles: Dictionary = {}
var _disp_magics: Array = []
var _recent_disp_hits: Array = []
var _shake_active := false
var _shake_started := 0.0

## 地図がまだ届いていない間に地図欄へ出すタイトルロゴ。
const LOGO_PATH := "res://assets/logo.png"
const TITLE_BG := Color(0.06, 0.05, 0.05)
var _title_rect: TextureRect = null

## 地図の周りの余白に出すモノグラム壁紙。タイル状に並べる。
## 絵はタイルの大きさ(512x384)と一致させてあるので、NEAREST の
## まま1:1で描けて補間が要らない。ファイルが無ければ黒い余白。
const WALLPAPER_PATH := "res://assets/wallpaper.png"
const WALLPAPER_TILE := Vector2(512.0, 384.0)
const WALLPAPER_MODULATE := Color(0.8, 0.8, 0.8)
## 壁紙の下地。タイルの暗部の色に合わせた濃紺。
const WALLPAPER_BG := Color(0.075, 0.13, 0.22)
var _wallpaper: Texture2D = null

## 地図の右下に浮かせるコンパスの透け具合と、端からの余白。
## 下の地図が見えて、針の向きも読み取れる程度。
## 大きさはマップチップ1マス分(32px×ズーム)に追従させる。
const COMPASS_ALPHA := 0.6
const COMPASS_MARGIN := 8.0
var compass: CompassView = null


func _init() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	_caster_tracker = PhiCombatFx.CasterTracker.new()
	_title_rect = TextureRect.new()
	_title_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_title_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_title_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_title_rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_title_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title_rect.texture = title_texture()
	add_child(_title_rect)
	_wallpaper = wallpaper_texture()
	# コンパスは地図の右下に半透明で浮かせる。マウスは通す
	# (CompassView 側で MOUSE_FILTER_IGNORE)。地図が届くまで隠す。
	compass = CompassView.new()
	compass.modulate = Color(1.0, 1.0, 1.0, COMPASS_ALPHA)
	compass.visible = false
	add_child(compass)
	_layout_compass(_compass_px())


func _compass_px() -> float:
	## コンパスの大きさ。マップチップ1マス分(32px×ズーム)。
	return float(CHIP_SIZE * zoom)


func _layout_compass(px: float) -> void:
	## コンパスを地図の右下に置く。アンカーを右下に固定し、
	## 大きさと余白ぶんだけ内側へずらす。最小サイズも同じ値に
	## しないと、最小サイズに引っ張られて隅からはみ出す。
	compass.custom_minimum_size = Vector2(px, px)
	compass.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	compass.offset_left = -(px + COMPASS_MARGIN)
	compass.offset_top = -(px + COMPASS_MARGIN)
	compass.offset_right = -COMPASS_MARGIN
	compass.offset_bottom = -COMPASS_MARGIN


func _sync_compass_size() -> void:
	## コンパスの大きさを、今のズームのマップチップ1マス分に
	## 合わせ直す。ズームが変わった時に呼ぶ。
	if compass != null:
		_layout_compass(_compass_px())


func set_compass_texture(tex: Texture2D) -> void:
	if compass != null:
		compass.direction_tex = tex
		compass.queue_redraw()


func set_compass_direction(dir_num: int, p_north_fix: bool) -> void:
	if compass != null:
		compass.set_direction(dir_num, p_north_fix)


## モノグラム壁紙の絵を返す。ファイルが無い場合は null。
func wallpaper_texture() -> Texture2D:
	if ResourceLoader.exists(WALLPAPER_PATH):
		return load(WALLPAPER_PATH) as Texture2D
	return null


## タイトルロゴの絵を返す。ファイルが無い(リポジトリの写しなど)場合は null。
func title_texture() -> Texture2D:
	if ResourceLoader.exists(LOGO_PATH):
		return load(LOGO_PATH) as Texture2D
	return null


static func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_update_zoom()
		if _event.is_empty():
			queue_redraw()


func _update_zoom() -> void:
	## 割り当てられた大きさに収まる整数倍率にする。ドット絵が
	## 崩れないよう整数倍に限る。レイアウト前(サイズ0)は今の倍率を保つ。
	## 拡大は、外部からのサイズ変更で要求があった時だけ1段階ずつ。
	## 縮小は収まらなくなったら即座に。要求が無いときは拡大しないので、
	## 文字サイズの連動によるレイアウトのフィードバックでは発振しない。
	var dim := grid_dim(int(_event.get("size", 7)))
	var avail := size
	if avail.x < 1.0 or avail.y < 1.0:
		return
	var zw := int(avail.x / (dim * CHIP_SIZE))
	var zh := int(avail.y / (dim * CHIP_SIZE + MAP_TOP))
	var fit := clampi(mini(zw, zh), 1, 8)
	if fit > zoom:
		if _grow_requested:
			_grow_requested = false
			zoom = zoom + 1
			zoom_changed.emit(zoom)
			_sync_compass_size()
			queue_redraw()
	elif fit < zoom:
		# 縮小するとき、溜まっていた拡大要求は古いので捨てる。
		_grow_requested = false
		zoom = fit
		zoom_changed.emit(zoom)
		_sync_compass_size()
		queue_redraw()


func set_map(event: Dictionary, p_assets: GameAssets, p_mapset: String) -> void:
	_event = event
	_title_rect.visible = false
	if compass != null:
		compass.visible = true
	assets = p_assets
	mapset = p_mapset
	_chip_tex = null
	_items_tex = null
	if assets != null:
		_chip_tex = assets.chip(mapset)
		_items_tex = assets.items()
	var dim := grid_dim(int(event.get("size", 7)))
	custom_minimum_size = Vector2(dim * CHIP_SIZE, dim * CHIP_SIZE + MAP_TOP)
	if dim != _last_dim:
		_last_dim = dim
		# 地図の大きさの変化は配置の反動ではなく内容の変化なので、
		# 外部からのサイズ変更と同じく拡大を1段階だけ許します。
		request_zoom_growth()
	# フロート表示の基準点と、死亡の残像のもとになるキャラを覚えます。
	_prev_charas = _last_charas
	_last_charas = {}
	_anchors = {}
	_center_anchor = null
	var head_top := (CHIP_SIZE - CHARA_H) / 2 - CHARA_Y_ABOVE_FLOOR + MAP_TOP
	for ch in event.get("chars", []):
		var cd: Dictionary = ch
		var nm := PhiTags.strip_tags(str(cd.get("name", ""))).strip_edges()
		_last_charas[nm] = cd
		var cx := int(cd.get("x", -1))
		var cy := int(cd.get("y", -1))
		if not (0 <= cx and cx < dim and 0 <= cy and cy < dim):
			continue
		if nm.is_empty():
			continue
		var anchor := Vector2(cx * CHIP_SIZE + CHIP_SIZE / 2, cy * CHIP_SIZE + head_top)
		_anchors[nm] = anchor
		if cx == dim / 2 and cy == dim / 2:
			_center_anchor = anchor
	_update_zoom()
	queue_redraw()


## グラキャッシュ初期化の後、持っている絵を読み直す。
## _chip_tex/_items_tex は set_map の時だけ取り直すので、ここで
## 取り直さないと古いテクスチャのままになる。死亡の残像も古い
## テクスチャを持っているので捨てる(0.6秒の演出なので実害は無い)。
## 見えているキャラの絵は、再描画の「前に」作ってキャッシュを
## 温めておく。描画コールバックの中でテクスチャを作ると、Mac の
## Metal ではそのフレームにアップロードされず白く描かれ、次の
## 地図が届くまで白いまま残る(2026-11-15 の報告)。
func reload_cached_textures() -> void:
	_chip_tex = null
	_items_tex = null
	_ghosts.clear()
	if assets != null:
		_chip_tex = assets.chip(mapset)
		_items_tex = assets.items()
		for ch_name in _last_charas:
			var ch: Dictionary = _last_charas[ch_name]
			assets.chara(str(ch.get("name", "")), str(ch.get("gra", "")), int(ch.get("default", 0)))
	queue_redraw()


## テスト用: 基準点の表を返します。
func debug_anchors() -> Dictionary:
	return _anchors


## テスト用: 中心の基準点を返します。
func debug_center_anchor() -> Variant:
	return _center_anchor


## テスト用: 残像の数を返します。
func debug_event_empty() -> bool:
	return _event.is_empty()


func drawn_map_rect() -> Rect2:
	## 描いている地図の範囲(コントロール内の座標)。マウスの当たり判定用。
	var dim := grid_dim(int(_event.get("size", 7)))
	var z := float(zoom)
	var w := dim * CHIP_SIZE * z
	var h := (dim * CHIP_SIZE + MAP_TOP) * z
	var ox := floorf(maxf(0.0, (size.x - w) * 0.5))
	var oy := floorf(maxf(0.0, (size.y - h) * 0.5))
	return Rect2(ox, oy, w, h)


func debug_disp_magic_count() -> int:
	return _disp_magics.size()


func debug_recent_disp_hit_count() -> int:
	return _recent_disp_hits.size()


func debug_bolt_count() -> int:
	return _bolts.size()


func debug_impact_count() -> int:
	return _impacts.size()


func debug_ghost_count() -> int:
	return _ghosts.size()


static func grid_dim(size: int) -> int:
	return 5 if size == 5 else 7


static func chip_indices(chip_byte: int) -> Array:
	## チップのバイト → 描くチップの番号の配列。知らないバイトは 0。
	if CHIP_BYTE_TO_INDEX.has(chip_byte):
		return CHIP_BYTE_TO_INDEX[chip_byte]
	return [0]


static func chip_src_rect(index: int) -> Rect2:
	## チップシート上の index → 矩形。範囲外は空の矩形。
	if index < 0 or index >= CHIP_COUNT:
		return Rect2()
	var col := index % CHIPS_PER_ROW
	var row := index / CHIPS_PER_ROW
	return Rect2(col * CHIP_SIZE, row * CHIP_HEIGHT, CHIP_SIZE, CHIP_HEIGHT)


static func dir_to_row(dir_value: Variant) -> int:
	## キャラdir(文字/数値) → シート行(0-3)。既定は F(2, 正面)。
	if dir_value is int:
		var ch: String = _DIR_NUM_TO_CHAR.get(dir_value & 7, "F")
		return _DIR_TO_ROW[ch]
	return _DIR_TO_ROW.get(str(dir_value), _DIR_TO_ROW["F"])


static func is_giant(gigant: Variant) -> bool:
	return str(gigant) == "*"


static func arrange_row(chars: Array) -> Array:
	## 1行のキャラを描く順と、横にずらす量(px)。(x, layer) の順に描く。
	var ordered := chars.duplicate()
	ordered.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a.get("x", 0)) != int(b.get("x", 0)):
			return int(a.get("x", 0)) < int(b.get("x", 0))
		return int(a.get("layer", 0)) < int(b.get("layer", 0)))
	var out: Array = []
	var i := 0
	while i < ordered.size():
		var j := i
		while j < ordered.size() and int(ordered[j].get("x", 0)) == int(ordered[i].get("x", 0)):
			j += 1
		var cell := ordered.slice(i, j)
		i = j
		if cell.size() == 2:
			var a: Dictionary = cell[0]
			var b: Dictionary = cell[1]
			var ga := is_giant(a.get("gigant"))
			var gb := is_giant(b.get("gigant"))
			if not ga and not gb:
				out.append([a, -8])
				out.append([b, 8])
				continue
			if ga != gb:
				var big: Dictionary = a if ga else b
				var small: Dictionary = b if ga else a
				out.append([big, 0])
				out.append([small, 8])
				continue
		for ch in cell:
			out.append([ch, 0])
	return out


static func chara_src_rect(dir_value: Variant, gigant: Variant, anim_frame: int = 0, large: bool = false) -> Rect2:
	## キャラスプライトのソース矩形。
	## 96px幅レイアウト: [小frame0=16][小frame1=16][大frame0=32][大frame1=32]。
	var row := dir_to_row(dir_value)
	var frame := anim_frame & 1
	var sy := row * CHARA_H
	if large or is_giant(gigant):
		return Rect2(CHARA_W_NORMAL * 2 + frame * CHARA_W_GIANT, sy, CHARA_W_GIANT, CHARA_H)
	return Rect2(frame * CHARA_W_NORMAL, sy, CHARA_W_NORMAL, CHARA_H)


static func water_quarter_patterns(water: Array, wy: int, wx: int) -> Array[int]:
	## 水セルの周りの水有無から各 quarter の3bitパターンを計算する。
	return [
		water[wy][wx] | (water[wy][wx + 1] << 1) | (water[wy + 1][wx] << 2),
		water[wy][wx + 2] | (water[wy][wx + 1] << 1) | (water[wy + 1][wx + 2] << 2),
		water[wy + 2][wx] | (water[wy + 2][wx + 1] << 1) | (water[wy + 1][wx] << 2),
		water[wy + 2][wx + 2] | (water[wy + 2][wx + 1] << 1) | (water[wy + 1][wx + 2] << 2),
	]


static func water_quarter_chip(q_index: int, pattern: int) -> Variant:
	## quarter のパターンから描画する水縁チップを解決する。
	## [chipIndex, srcQuarter] か、overlay不要なら null。
	var entry: Variant = (Q_TABLE[q_index] as Dictionary).get(pattern)
	if entry == null:
		return null
	return [WATER_CHIP_BASE + entry[0], entry[1]]


static func chip_quarter_src_rect(chip_index: int, quarter: int) -> Rect2:
	## チップindex + quarter(0=TL,1=TR,2=BL,3=BR) → シート上の16×16矩形。
	var base := chip_src_rect(chip_index)
	if base.size.x <= 0:
		return Rect2()
	var half := CHIP_SIZE / 2
	return Rect2(
		base.position.x + (quarter & 1) * half,
		base.position.y + (CHIP_HEIGHT - CHIP_SIZE) + ((quarter >> 1) & 1) * half,
		half, half)


static func build_water_grid(cells: Array, dim: int) -> Array:
	## 水有無の (dim+2)×(dim+2) 配列を作る(枠=0)。
	var water: Array = []
	for r in range(dim + 2):
		var row: Array = []
		for c in range(dim + 2):
			row.append(0)
		water.append(row)
	for r in range(dim):
		for c in range(dim):
			var idx := r * dim + c
			if idx < cells.size() and int(cells[idx].get("chip", 0)) == WATER_BYTE:
				water[r + 1][c + 1] = 1
	return water


## 余白全体を濃紺で塗り、壁紙があればタイル状に並べる。
func _draw_wallpaper() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), WALLPAPER_BG)
	if _wallpaper == null:
		return
	var y := 0.0
	while y < size.y:
		var x := 0.0
		while x < size.x:
			draw_texture_rect(_wallpaper, Rect2(x, y, WALLPAPER_TILE.x, WALLPAPER_TILE.y), false, WALLPAPER_MODULATE)
			x += WALLPAPER_TILE.x
		y += WALLPAPER_TILE.y


func _draw() -> void:
	if _event.is_empty():
		draw_rect(Rect2(Vector2.ZERO, size), TITLE_BG)
		return
	var dim := grid_dim(int(_event.get("size", 7)))
	var cells: Array = _event.get("cells", [])
	var chars: Array = _event.get("chars", [])
	var z := float(zoom)
	# 割り当てより小さく描けるときは中央に寄せる。揺れは全体に掛けます。
	# 配置は整数ピクセルに丸める。小数位置だと線形補間でチップの
	# 端が隣の絵と混ざり、セルの境に黒い線が出ることがある。
	var shake := _shake_offset(z)
	var ox := floorf(maxf(0.0, (size.x - dim * CHIP_SIZE * z) * 0.5) + shake.x)
	var oy := floorf(maxf(0.0, (size.y - (dim * CHIP_SIZE + MAP_TOP) * z) * 0.5) + shake.y)
	# 地図の周りの余白にはモノグラム壁紙を敷く(無ければ黒)。
	_draw_wallpaper()
	draw_set_transform(Vector2(ox, oy), 0.0, Vector2.ONE)
	# 地図の背景は塗らない。セルの絵が全面を覆い、上の張り出しの
	# 隙間からは後ろの壁紙が見える(黒く塗ると帯になって目立つ)。
	var water: Variant = null
	if _chip_tex != null:
		water = build_water_grid(cells, dim)
	var half := CHIP_SIZE / 2

	for row in range(dim):
		# 1. ベースチップ
		for col in range(dim):
			var idx := row * dim + col
			if idx >= cells.size():
				continue
			var cell: Dictionary = cells[idx]
			if _chip_tex == null:
				_fallback_cell(cell, col, row, z)
				continue
			for chip_index in chip_indices(int(cell.get("chip", 0))):
				_draw_chip(_chip_tex, chip_index, col, row, z)
		# 1.5 水縁overlay
		if water != null:
			for col in range(dim):
				var idx := row * dim + col
				if idx >= cells.size():
					continue
				var cell: Dictionary = cells[idx]
				if int(cell.get("chip", 0)) != WATER_BYTE:
					continue
				var patterns := water_quarter_patterns(water, row, col)
				var cell_x := col * CHIP_SIZE
				var cell_y := row * CHIP_SIZE + MAP_TOP
				for q in range(4):
					var hit: Variant = water_quarter_chip(q, patterns[q])
					if hit == null:
						continue
					var rect := chip_quarter_src_rect(hit[0], hit[1])
					if rect.size.x <= 0:
						continue
					var dx := (cell_x + (q & 1) * half) * z
					var dy := (cell_y + ((q >> 1) & 1) * half) * z
					draw_texture_rect_region(_chip_tex, Rect2(dx, dy, half * z, half * z), rect)
		# 2. 看板overlay
		for col in range(dim):
			var idx := row * dim + col
			if idx >= cells.size():
				continue
			var cell: Dictionary = cells[idx]
			if (int(cell.get("attr", 0)) & 0x08) == 0:
				continue
			if _chip_tex != null:
				_draw_chip(_chip_tex, _board_chip_index(int(cell.get("chip", 0))), col, row, z)
		# 3. アイテムoverlay
		for col in range(dim):
			var idx := row * dim + col
			if idx >= cells.size():
				continue
			var cell: Dictionary = cells[idx]
			if (int(cell.get("attr", 0)) & 0x70) == 0:
				continue
			_draw_item(cell, col, row, z)
		# 4. キャラ(この行)
		var row_chars: Array = []
		for ch in chars:
			if int(ch.get("y", -1)) == row and 0 <= int(ch.get("x", -1)) and int(ch.get("x", -1)) < dim:
				row_chars.append(ch)
		for pair in arrange_row(row_chars):
			_draw_state_icon(pair[0], pair[1], z, true)
			_draw_chara(pair[0], pair[1], z)
			_draw_state_icon(pair[0], pair[1], z, false)
		# 4.5 残像(この行)。ずらさず、この行のキャラの上に重ねます。
		_draw_ghosts(row, dim, z)
	# 5. キャラ名ラベル(中心の自キャラは除外)。同じマスは後勝ち。
	_draw_labels(chars, dim, z)
	# 6. 戦闘の演出(点滅・斬撃・魔法弾・着弾・浮き数字・吹き出し)。
	_draw_effects(dim, z)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_chip(tex: Texture2D, index: int, col: int, row: int, z: float) -> void:
	var rect := chip_src_rect(index)
	if rect.size.x <= 0:
		return
	var overhang := CHIP_HEIGHT - CHIP_SIZE
	var dx := col * CHIP_SIZE * z
	var dy := (row * CHIP_SIZE - overhang + MAP_TOP) * z
	draw_texture_rect_region(tex, Rect2(dx, dy, rect.size.x * z, rect.size.y * z), rect)


func _fallback_cell(cell: Dictionary, col: int, row: int, z: float) -> void:
	var indices := chip_indices(int(cell.get("chip", 0)))
	var color: Color = FALLBACK_CHIP_COLORS.get(indices[0], FALLBACK_CHIP_DEFAULT)
	draw_rect(Rect2(col * CHIP_SIZE * z, (row * CHIP_SIZE + MAP_TOP) * z, CHIP_SIZE * z, CHIP_SIZE * z), color)


func _board_chip_index(chip_byte: int) -> int:
	return BOARD_CHIP_HARD if chip_byte in _HARD_BOARD_CHIPS else BOARD_CHIP_SOFT


func _draw_item(cell: Dictionary, col: int, row: int, z: float) -> void:
	var no := (int(cell.get("attr", 0)) & 0x70) >> 4
	var dst_x := col * CHIP_SIZE
	var dst_y := row * CHIP_SIZE + MAP_TOP
	if _items_tex == null:
		draw_rect(Rect2((dst_x + 8) * z, (dst_y + 8) * z, 16 * z, 16 * z), Color(1.0, 1.0, 0.78))
		return
	var s := ITEM_SPRITE_SIZE
	var src_x := no * s
	var draw_y := dst_y - ITEM_Y_ABOVE_FLOOR
	if int(cell.get("chip", 0)) in _CIRCLE_CHIPS:
		var src_y := 5 if no == 5 or no == 6 else 0
		draw_texture_rect_region(_items_tex,
			Rect2(dst_x * z, draw_y * z, s * z, ITEM_CLIP_H * z),
			Rect2(src_x, src_y, s, ITEM_CLIP_H))
	else:
		draw_texture_rect_region(_items_tex,
			Rect2(dst_x * z, draw_y * z, s * z, s * z),
			Rect2(src_x, 0, s, s))


func _draw_chara(ch: Dictionary, dx: int, z: float, tex_override: Texture2D = null, modulate := Color.WHITE) -> void:
	var rect := chara_src_rect(ch.get("dir", "F"), ch.get("gigant", "#"), 0)
	var sw := rect.size.x
	var sh := rect.size.y
	var base_x := int(ch.get("x", 0)) * CHIP_SIZE + (CHIP_SIZE - int(sw)) / 2 + dx
	var base_y := int(ch.get("y", 0)) * CHIP_SIZE + (CHIP_SIZE - CHARA_H) / 2 - CHARA_Y_ABOVE_FLOOR + MAP_TOP
	var tex: Texture2D = tex_override
	if tex == null and assets != null:
		tex = assets.chara(str(ch.get("name", "")), str(ch.get("gra", "")), int(ch.get("default", 0)))
	if tex == null:
		draw_rect(Rect2(base_x * z, base_y * z, sw * z, sh * z), Color.YELLOW)
		_draw_placeholder_initial(ch, base_x, base_y, sw, sh, z)
		return
	var magnify: Variant = ch.get("magnify")
	if magnify != null:
		var m: Dictionary = magnify
		var d := _magnified_dst(base_x, base_y, m)
		draw_texture_rect_region(tex, Rect2(d[0] * z, d[1] * z, d[2] * z, d[3] * z), rect, modulate)
		return
	draw_texture_rect_region(tex, Rect2(base_x * z, base_y * z, sw * z, sh * z), rect, modulate)


func _magnified_dst(base_x: int, base_y: int, m: Dictionary) -> Array[int]:
	var dx := base_x - (int(m.get("w", 0)) - CHARA_H) / 2
	var dy := base_y - (((int(m.get("h", 0)) - CHARA_H) * 5) / 6 + int(m.get("z", 0)))
	return [dx, dy, int(m.get("w", 0)), int(m.get("h", 0))]


func _draw_placeholder_initial(ch: Dictionary, base_x: int, base_y: int, sw: float, sh: float, z: float) -> void:
	if label_font == null:
		return
	var chara_name := PhiTags.strip_tags(str(ch.get("name", ""))).strip_edges()
	if chara_name.is_empty():
		return
	var initial := chara_name.substr(0, 1)
	var font_size := int(12 * z)
	var ts := label_font.get_string_size(initial, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var cx := (base_x + sw / 2.0) * z - ts.x / 2.0
	var cy := (base_y + sh / 2.0) * z + (label_font.get_ascent(font_size) - label_font.get_descent(font_size)) / 2.0
	draw_string(label_font, Vector2(cx, cy), initial, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.BLACK)


func _draw_state_icon(ch: Dictionary, dx: int, z: float, under: bool) -> void:
	## キャラの状態アイコン(第3段)。Philly はキャラの下→本体→上の順に描く。
	var status := int(ch.get("status", 0))
	var icon: Variant
	if under:
		icon = PhiCharaState.under_icon(status)
	else:
		var anim := int(_now() * 2.0) % 2
		icon = PhiCharaState.over_icon(status, str(ch.get("dir", "F")), anim)
	if icon == null:
		return
	var cell: int = icon[0]
	var ix := (int(ch.get("x", 0)) * CHIP_SIZE + dx + int(icon[1])) * z
	var iy := (int(ch.get("y", 0)) * CHIP_SIZE + 5 + int(icon[2])) * z
	if _items_tex != null and cell * 32 + 32 <= _items_tex.get_width():
		draw_texture_rect_region(_items_tex, Rect2(ix, iy, 32.0 * z, 32.0 * z), Rect2(cell * 32, 0, 32, 32))
	else:
		# 絵が無ければ小さな枠で代用する
		draw_rect(Rect2(ix + 6.0 * z, iy + 6.0 * z, 20.0 * z, 20.0 * z), Color(1, 1, 1, 0.25), false, maxf(1.0, z))


func _draw_labels(chars: Array, dim: int, z: float) -> void:
	if label_font == null:
		return
	var cx := dim / 2
	var cy := dim / 2
	var per_cell := {}
	for ch in chars:
		var x := int(ch.get("x", -1))
		var y := int(ch.get("y", -1))
		if not (0 <= x and x < dim and 0 <= y and y < dim):
			continue
		if x == cx and y == cy:
			continue
		var chara_name := PhiTags.strip_tags(str(ch.get("name", ""))).strip_edges()
		if chara_name.is_empty():
			continue
		per_cell[Vector2i(x, y)] = chara_name
	var font_size := int(6 * z)
	for cell_key in per_cell:
		var cell_pos: Vector2i = cell_key
		var chara_name: String = per_cell[cell_key]
		var x := (cell_pos.x * CHIP_SIZE + CHIP_SIZE / 2) * z
		var y := (cell_pos.y * CHIP_SIZE + int(CHIP_SIZE * 0.6) + MAP_TOP) * z
		var ts := label_font.get_string_size(chara_name, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
		var pos := Vector2(x - ts.x / 2.0, y + label_font.get_ascent(font_size))
		draw_string_outline(label_font, pos, chara_name, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 3, Color.BLACK)
		draw_string(label_font, pos, chara_name, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.WHITE)


# -- 戦闘の演出 ---------------------------------------------------------------

func _process(_delta: float) -> void:
	if _floats.is_empty() and _flashes.is_empty() and _swings.is_empty() and _slashes.is_empty() and _bolts.is_empty() and _impacts.is_empty() and _ghosts.is_empty() and _bubbles.is_empty() and _disp_magics.is_empty() and not _shake_active:
		return
	_expire_effects()
	queue_redraw()


func _expire_effects() -> void:
	var now := _now()
	_floats = _floats.filter(func(f: Dictionary) -> bool: return now - float(f["spawned"]) < FLOAT_DURATION)
	_flashes = _flashes.filter(func(f: Dictionary) -> bool: return now - float(f["spawned"]) < FLASH_STEP * FLASH_STEPS)
	_swings = _swings.filter(func(f: Dictionary) -> bool: return now - float(f["spawned"]) < SWING_FRAME * SWING_FRAMES)
	_slashes = _slashes.filter(func(f: Dictionary) -> bool: return now - float(f["spawned"]) < SLASH_FRAME * SLASH_FRAMES)
	var kept_bolts: Array = []
	for b in _bolts:
		if now - float(b["spawned"]) >= BOLT_STEP * BOLT_STEPS:
			_impacts.append({"center": b["end"], "spawned": now})
		else:
			kept_bolts.append(b)
	_bolts = kept_bolts
	_impacts = _impacts.filter(func(f: Dictionary) -> bool: return now - float(f["spawned"]) < IMPACT_FRAME * IMPACT_FRAMES)
	_ghosts = _ghosts.filter(func(g: Dictionary) -> bool: return int((now - float(g["spawned"])) / GHOST_STEP) < GHOST_STEPS)
	_disp_magics = _disp_magics.filter(func(d: Dictionary) -> bool: return now - float(d["spawned"]) < DISP_MAGIC_PHASE * DISP_MAGIC_PHASES)
	_recent_disp_hits = _recent_disp_hits.filter(func(h: Dictionary) -> bool: return now - float(h["spawned"]) < DISP_MAGIC_SUPPRESS_WINDOW)
	var expired: Array = []
	for speaker in _bubbles:
		if now >= float(_bubbles[speaker]["expire"]):
			expired.append(speaker)
	for speaker in expired:
		_bubbles.erase(speaker)
	if _shake_active and now - _shake_started >= SHAKE_STEP * SHAKE_PATTERN.size():
		_shake_active = false


func _shake_offset(z: float) -> Vector2:
	if not _shake_active:
		return Vector2.ZERO
	var step := int((_now() - _shake_started) / SHAKE_STEP)
	if step >= SHAKE_PATTERN.size():
		return Vector2.ZERO
	var p: Vector2 = SHAKE_PATTERN[step]
	return p * z


func _float_position(target: Variant) -> Variant:
	## フロートを出す位置(地図の絵の中の座標)を決めます。
	if target == null or str(target) == player_name or target == "あなた" or target == "自分":
		return _center_anchor
	return _anchors.get(str(target))


static func _sprite_center(anchor: Vector2) -> Vector2:
	## キャラの絵の中心を、地図の絵の中の座標で返します。
	return Vector2(anchor.x, anchor.y + 16.0)


func spawn_floats(text: String) -> void:
	## ログの行から数字を抜き、地図に浮かべます。
	var now := _now()
	for line in text.split("\n"):
		for ev in PhiFloatText.parse_floats(line):
			var pos: Variant = _float_position(ev["target"])
			if pos == null:
				continue
			_float_seq += 1
			var kind: String = ev["kind"]
			# 攻撃の数字でも、自分が受けた時は赤にします
			if kind == "dealt" and _center_anchor != null and pos == _center_anchor:
				kind = "taken"
			var label := "+%d" % int(ev["amount"]) if kind in ["heal", "mp"] else str(ev["amount"])
			_floats.append({
				"pos": pos, "label": label, "color": FLOAT_COLORS[kind],
				"xoff": float((_float_seq % 3) - 1) * 4.0, "spawned": now,
			})
			if kind in ["dealt", "taken", "mpdmg"]:
				_flashes.append({"pos": pos, "color": _flash_color(kind), "spawned": now})
				if kind == "taken":
					_shake_active = true
					_shake_started = now


static func _flash_color(kind: String) -> Color:
	match kind:
		"taken":
			return Color(1.0, 0.322, 0.322)
		"mpdmg":
			return BOLT_COLOR
	return Color.WHITE


func spawn_combat_fx(text: String) -> void:
	## 戦闘の演出を出します。詠唱の行は、魔法の見分けに覚えます。
	var now := _now()
	for line in text.split("\n"):
		var chant: Variant = PhiCombatFx.parse_chant(line)
		if chant != null:
			_caster_tracker.note(chant, now)
			continue
		if PhiCombatFx.parse_chant_stop(line):
			_caster_tracker.clear(player_name)
			continue
		var attack: Variant = PhiCombatFx.parse_attack(line)
		if attack != null:
			_combat_fx(attack, now)


func _combat_fx(attack: Dictionary, now: float) -> void:
	## 攻撃1回に、斬撃の軌跡か魔法弾の演出を出します。
	var target_pos: Variant = _float_position(attack["target"])
	if target_pos == null:
		return
	if _caster_tracker.consume(str(attack["attacker"]), now):
		# サーバー駆動の魔法表示が同じマスを直前に出した時は、
		# 自前の魔法弾は出さない(Philly の表示と二重になるため)。
		if _disp_magic_covers_target(str(attack["target"]), now):
			return
		var attacker_pos: Variant = _float_position(attack["attacker"])
		if attacker_pos != null and attacker_pos != target_pos:
			_bolts.append({"start": _sprite_center(attacker_pos), "end": _sprite_center(target_pos), "spawned": now})
		else:
			_impacts.append({"center": _sprite_center(target_pos), "spawned": now})
	else:
		var attacker_pos2: Variant = _float_position(attack["attacker"])
		if attacker_pos2 != null:
			_swings.append({"from": _sprite_center(attacker_pos2), "to": _sprite_center(target_pos), "spawned": now})
		else:
			# 攻撃する人が見えなければ、対象に軌跡だけ出します
			_slashes.append({"center": _sprite_center(target_pos), "spawned": now})


func spawn_disp_magic(data: Dictionary) -> void:
	## `#ex-disp-magic` の表示を出す(第3段)。終点のマスを覚え、
	## 直後の自前の魔法弾を抑えるのにも使う。
	var now := _now()
	_disp_magics.append({"data": data, "spawned": now})
	var end: Dictionary = data["end"]
	_recent_disp_hits.append({"cell": Vector2i(int(end["x"]), int(end["y"])), "spawned": now})
	queue_redraw()


func _disp_magic_covers_target(target: String, now: float) -> bool:
	## 対象のいるマスを、サーバー駆動の魔法表示が最近出したか。
	var cell := Vector2i(-1, -1)
	var dim := grid_dim(int(_event.get("size", 7)))
	if target == player_name or target == "あなた" or target == "自分":
		cell = Vector2i(dim / 2, dim / 2)
	else:
		var ch: Variant = _last_charas.get(target)
		if ch == null:
			return false
		cell = Vector2i(int(ch.get("x", -1)), int(ch.get("y", -1)))
	return PhiDispMagic.bolt_suppressed(_recent_disp_hits, cell, now, DISP_MAGIC_SUPPRESS_WINDOW)


func _draw_disp_magic(dm: Dictionary, z: float, now: float) -> void:
	var age := now - float(dm["spawned"])
	var phase := int(age / DISP_MAGIC_PHASE)
	if phase >= DISP_MAGIC_PHASES:
		return
	var cells := PhiDispMagic.phase_cells(dm["data"], phase)
	for c in cells:
		var at: Vector2 = c[0]
		var cell: int = c[1]
		if _items_tex != null and cell * 32 + 32 <= _items_tex.get_width():
			draw_texture_rect_region(_items_tex, Rect2(at.x * z, at.y * z, 32.0 * z, 32.0 * z), Rect2(cell * 32, 0, 32, 32))
		else:
			draw_circle(Vector2(at.x + 16.0, at.y + 16.0) * z, 12.0 * z, Color(0.4, 0.8, 1.0, 0.7))


func spawn_death_fx(text: String) -> void:
	## 死亡の行から、倒れたキャラのゆっくり消える演出を出します。
	var victim: Variant = PhiCombatFx.parse_kill(text)
	if victim == null:
		return
	if victim == "あなた" and not player_name.is_empty():
		victim = player_name
	var ch: Variant = _last_charas.get(victim)
	if ch == null:
		ch = _prev_charas.get(victim)
	if ch == null or assets == null:
		return
	var tex: Variant = assets.chara(str(ch.get("name", "")), str(ch.get("gra", "")), int(ch.get("default", 0)))
	if tex == null:
		return
	_ghosts = _ghosts.filter(func(g: Dictionary) -> bool: return g["name"] != victim)
	_ghosts.append({"name": victim, "chara": ch, "tex": tex, "spawned": _now()})
	queue_redraw()


func show_log_bubble(raw_text: String, plain: String) -> void:
	## NPCの発言や action の行を、吹き出しで出します。
	var names: Array = _anchors.keys()
	if not player_name.is_empty():
		names.append(player_name)
	var found: Variant = null
	if "/*act*/" in raw_text:
		found = PhiBubbles.bubble_from_action_line(plain, names)
	if found == null:
		found = PhiBubbles.bubble_from_log_line(plain, names)
	if found != null:
		show_bubble(found[0], found[1])


func show_bubble(speaker: String, body: String) -> void:
	## 話し手の頭の上に、発言の吹き出しを出します。
	var ms := minf(BUBBLE_MAX_MS, BUBBLE_BASE_MS + BUBBLE_PER_CHAR_MS * body.length())
	_bubbles[speaker] = {"text": body, "expire": _now() + ms / 1000.0}
	queue_redraw()


func _draw_ghosts(row: int, dim: int, z: float) -> void:
	if _ghosts.is_empty():
		return
	var now := _now()
	for g in _ghosts:
		var gch: Dictionary = g["chara"]
		if int(gch.get("y", -1)) != row:
			continue
		var gx := int(gch.get("x", -1))
		if not (0 <= gx and gx < dim):
			continue
		# 描き直しが重くても、壁時計どおりの速さで薄くします
		var step := int((now - float(g["spawned"])) / GHOST_STEP)
		if step >= GHOST_STEPS:
			continue
		var alpha := 1.0 - float(step) / GHOST_STEPS
		_draw_chara(gch, 0, z, g["tex"], Color(1, 1, 1, alpha))


func _draw_effects(dim: int, z: float) -> void:
	var now := _now()
	for f in _flashes:
		_draw_flash(f, z, now)
	for s in _swings:
		_draw_swing(s, z, now)
	for s in _slashes:
		_draw_slash(s, z, now)
	for b in _bolts:
		_draw_bolt(b, z, now)
	for im in _impacts:
		_draw_impact(im, z, now)
	for dm in _disp_magics:
		_draw_disp_magic(dm, z, now)
	for f in _floats:
		_draw_float(f, z, now)
	_draw_bubbles(dim, z)


func _draw_flash(f: Dictionary, z: float, now: float) -> void:
	var step := int((now - float(f["spawned"])) / FLASH_STEP)
	if step >= FLASH_STEPS or step % 2 == 1:
		return
	var pos: Vector2 = f["pos"]
	var c: Color = f["color"]
	# stipple の代わりに、半透明で塗ります
	draw_rect(Rect2((pos.x - 16.0) * z, pos.y * z, 32.0 * z, 32.0 * z), Color(c.r, c.g, c.b, 0.5))


func _draw_swing(s: Dictionary, z: float, now: float) -> void:
	## 攻撃する人から、対象の向きへ斬撃の軌跡を走らせます。
	var step := int((now - float(s["spawned"])) / SWING_FRAME)
	if step >= SWING_FRAMES:
		return
	var from_c: Vector2 = s["from"]
	var to_c: Vector2 = s["to"]
	var facing := -PI / 2.0
	if to_c != from_c:
		facing = atan2(to_c.y - from_c.y, to_c.x - from_c.x)
	# 軌跡の中心は、体の中心から対象の向きへ少し寄せます
	var pivot := from_c + Vector2(6.0 * cos(facing), 6.0 * sin(facing))
	var start := facing + SWING_START
	var front := start + SWING_SWEEP * step / float(SWING_FRAMES - 1)
	var px := pivot.x * z
	var py := pivot.y * z
	for i in SWING_STREAKS.size():
		var st: Array = SWING_STREAKS[i]
		var end := maxf(front - float(st[1]), start + 0.12)
		var pts := PhiCombatFx.streak_points(px, py, z, float(st[0]), start, end, float(st[2]))
		var color_step := mini(step + (0 if i == 0 else 1), SWING_FRAMES - 1)
		draw_colored_polygon(pts, SWING_COLORS[color_step])


func _draw_slash(s: Dictionary, z: float, now: float) -> void:
	## 対象のキャラに、剣の軌跡を重ねます。
	var step := int((now - float(s["spawned"])) / SLASH_FRAME)
	if step >= SLASH_FRAMES:
		return
	var c: Vector2 = s["center"]
	var cx := c.x * z
	var cy := c.y * z
	var scale := pow(1.04, step)
	var main := PhiCombatFx.slash_points(cx, cy, z)
	var echo := PhiCombatFx.slash_points(cx + 3.0 * z, cy - 3.0 * z, z, 0.7)
	draw_colored_polygon(_scaled_points(main, cx, cy, scale), SLASH_COLORS[step])
	draw_colored_polygon(_scaled_points(echo, cx, cy, scale), SLASH_COLORS[mini(step + 1, SLASH_FRAMES - 1)])


static func _scaled_points(pts: PackedVector2Array, cx: float, cy: float, scale: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in pts:
		out.append(Vector2(cx + (p.x - cx) * scale, cy + (p.y - cy) * scale))
	return out


func _draw_bolt(b: Dictionary, z: float, now: float) -> void:
	## 術師から対象へ、尾を引く魔法弾を飛ばします。
	var step := int((now - float(b["spawned"])) / BOLT_STEP)
	if step >= BOLT_STEPS:
		return
	var start: Vector2 = b["start"]
	var end: Vector2 = b["end"]
	var x0 := start.x * z
	var y0 := start.y * z
	var x1 := end.x * z
	var y1 := end.y * z
	var dx := (x1 - x0) / BOLT_STEPS
	var dy := (y1 - y0) / BOLT_STEPS
	var hx := x0 + dx * (step + 1)
	var hy := y0 + dy * (step + 1)
	var dist := Vector2(dx, dy).length()
	var ux := 1.0
	var uy := 0.0
	if dist > 0.000001:
		ux = dx / dist
		uy = dy / dist
	# 尾は、進んだ分だけ後ろへ伸ばし、長さに上限を付けます
	var traveled := Vector2(hx - x0, hy - y0).length()
	var tail_len := minf(traveled, BOLT_TAIL_LEN * z)
	var tx := hx - ux * tail_len
	var ty := hy - uy * tail_len
	draw_colored_polygon(PhiCombatFx.comet_tail_points(hx, hy, tx, ty, z, BOLT_TAIL_WIDTH), BOLT_COLOR)
	var inner_len := tail_len * 0.55
	draw_colored_polygon(PhiCombatFx.comet_tail_points(hx, hy, hx - ux * inner_len, hy - uy * inner_len, z, BOLT_TAIL_WIDTH * 0.45), Color.WHITE)
	draw_circle(Vector2(hx, hy), 5.0 * z, BOLT_COLOR)
	draw_circle(Vector2(hx, hy), 2.0 * z, Color.WHITE)
	# 火花は、弾の周りを回ります
	var phases := [0.0, PI]
	var spark_colors := [Color.WHITE, Color(0.702, 0.898, 0.988)]
	for i in 2:
		var angle: float = step * BOLT_ORBIT_STEP + phases[i]
		var sx := hx + BOLT_ORBIT_R * z * cos(angle)
		var sy := hy + BOLT_ORBIT_R * z * sin(angle)
		draw_circle(Vector2(sx, sy), 1.5 * z, spark_colors[i])


func _draw_impact(im: Dictionary, z: float, now: float) -> void:
	## 着弾の閃光をしぼめ、輪を広げ、火花を散らして消します。
	var step := int((now - float(im["spawned"])) / IMPACT_FRAME)
	if step >= IMPACT_FRAMES:
		return
	var c: Vector2 = im["center"]
	var cx := c.x * z
	var cy := c.y * z
	var color: Color = IMPACT_COLORS[step]
	if step < 3:
		var r := (9.0 - 2.0 * step) * z
		draw_circle(Vector2(cx, cy), r, color)
	var r1 := (4.0 + 4.0 * step) * z
	var width1 := maxf(1.0, 2.0 * z - floorf(step * z / 2.0))
	draw_arc(Vector2(cx, cy), r1, 0.0, TAU, 64, color, width1, true)
	if step >= 1:
		var r2 := (4.0 + 3.0 * (step - 1)) * z
		draw_arc(Vector2(cx, cy), r2, 0.0, TAU, 64, color, z, true)
	for i in IMPACT_SPARKS:
		var angle := i * PI * 2.0 / IMPACT_SPARKS
		draw_colored_polygon(PhiCombatFx.radial_spark_points(cx, cy, z, angle, 6.0 + 3.0 * step, 1.2), color)


func _draw_float(f: Dictionary, z: float, now: float) -> void:
	if label_font == null:
		return
	var age := now - float(f["spawned"])
	if age >= FLOAT_DURATION:
		return
	var pos: Vector2 = f["pos"]
	var label: String = f["label"]
	# 浮き数字は地図の倍率に比例させる。Python 版の 7pt 相当
	# (28*z/3)より一回り大きくし、読み取りやすくする。
	# 第4段で 12*zoom から 11*zoom に、レイアウト変更で
	# 10*zoom に少しずつ小さくした。
	var font_size := int(round(10.0 * z))
	var rise := age * z / 0.03
	var x := pos.x * z + float(f["xoff"]) * z
	var y := pos.y * z + 4.0 * z - rise
	var ts := label_font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var bx := x - ts.x / 2.0
	var c: Color = f["color"]
	for off in [Vector2(-z, 0), Vector2(z, 0), Vector2(0, -z), Vector2(0, z)]:
		draw_string(label_font, Vector2(bx, y) + off, label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.BLACK)
	draw_string(label_font, Vector2(bx, y), label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, c)


func _draw_bubbles(dim: int, z: float) -> void:
	if label_font == null or _bubbles.is_empty():
		return
	# Tk のポイント数(6pt)をピクセル数に直します(96dpi で ×4/3)。
	var font_size := int(round(8.0 * z))
	var pad := 4.0 * z
	var map_w := dim * CHIP_SIZE * z
	var max_text := minf(BUBBLE_MAX_WIDTH * z, map_w - 2.0 * pad)
	if max_text <= 0.0:
		return
	var line_height := label_font.get_height(font_size)
	var ascent := label_font.get_ascent(font_size)
	var occupied: Array = []
	for speaker in _bubbles:
		var state: Dictionary = _bubbles[speaker]
		var body: String = state["text"]
		var pos: Variant = _float_position(speaker)
		if pos == null:
			continue
		var measure := func(t: String) -> float:
			return label_font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		var lines := PhiBubbles.wrap_bubble_lines(body, measure, max_text, BUBBLE_MAX_LINES)
		if lines.is_empty():
			continue
		var text_w := 0.0
		for ln in lines:
			text_w = maxf(text_w, float(measure.call(ln)))
		var w := text_w + 2.0 * pad
		var h := line_height * lines.size() + 2.0 * pad
		var cx: float = pos.x * z
		var tail_h := 6.0 * z
		var tail_w := 5.0 * z
		# しっぽの先は頭の少し上、箱はその上に置きます
		var tip_y: float = pos.y * z - z
		var placed: Array = PhiBubbles.place_bubble_rect(cx, tip_y, w, h, map_w, tail_h, occupied)
		var x0: float = placed[0]
		var y0: float = placed[1]
		var stacked: bool = placed[2]
		var y1 := y0 + h
		var tip_x := minf(maxf(cx, x0 + 1.0), x0 + w - 1.0)
		var base_x := minf(maxf(cx, x0 + tail_w), x0 + w - tail_w)
		# 上にずらした時は、しっぽは短く下向きにだけ出します
		var tail_tip_y := y1 + tail_h if stacked else tip_y
		var outline := PhiBubbles.bubble_outline(x0, y0, x0 + w, y1, 6.0 * z, base_x, tail_w, tip_x, tail_tip_y)
		draw_colored_polygon(outline, Color.WHITE)
		var border := PackedVector2Array(outline)
		border.append(outline[0])
		draw_polyline(border, Color.BLACK, z, true)
		for i in lines.size():
			var by := y0 + pad + ascent + i * line_height
			draw_string(label_font, Vector2(x0 + pad, by), lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.BLACK)
		if stacked:
			occupied.append([x0, y0, w, h + tail_h])
		else:
			occupied.append([x0, y0, w, h])
