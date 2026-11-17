class_name PhiEagleView
extends Control
## Eagle Eye の広域マップを描くコントロール (Python 版
## map_graphics.eagle_board + render_map_image(eagle_eye=True) 相当)。
##
## 盤面は正方形 (dim = max(width, height)) にし、外側は「不明な場所」
## のチップ '?' で埋める。人のいるマス (attr == 0x58) は地形を残し、
## 既定グラの人を上に描く。チップの並び・水際・看板・アイテムの
## 描き方は MapView と同じ静的ヘルパを使う。

const PERSON_ATTR := 0x58
const PERSON_GRA := "t_man"
const PERSON_DEFAULT := 0x40
const UNKNOWN_CHIP := 0x3F # '?'
## 盤面の表示上限 (px)。盤全体がこの大きさに収まるよう、
## 大きい盤だけ縮める (第87段で 1120 から引き下げ)。
const MAX_BOARD_PX := 560.0

var _dim := 0
var _cells: Array = [] # 正方形に整えた {chip, attr}
var _persons: Array = [] # {x, y}
var _scale := 1.0
var _chip_texs: Array = [null, null, null, null]
var _items_tex: Texture2D = null
var _person_tex: Texture2D = null
## 人の歩行アニメーションのフレーム (0/1、500ms 切替)。
var _anim_frame := 0


func set_event(event: Dictionary, assets: GameAssets, mapset: String, zoom: float, defines: Dictionary = {}) -> void:
	## イベントを取り込む。テクスチャの用意は描画の前に済ませる
	## (描画中に作ると Mac で白く出ることがある)。
	var w := int(event.get("width", 0))
	var h := int(event.get("height", 0))
	_dim = maxi(maxi(w, h), 1)
	_cells = []
	_persons = []
	var src: Array = event.get("cells", [])
	for y in range(_dim):
		for x in range(_dim):
			var cell := {"chip": UNKNOWN_CHIP, "attr": 0}
			if x < w and y < h:
				var idx := y * w + x
				if idx < src.size():
					var c: Dictionary = src[idx]
					cell = {"chip": int(c.get("chip", 0)), "attr": int(c.get("attr", 0))}
			if int(cell["attr"]) == PERSON_ATTR:
				cell = {"chip": int(cell["chip"]), "attr": 0}
				_persons.append({"x": x, "y": y})
			_cells.append(cell)
	_chip_texs = [null, null, null, null]
	_items_tex = null
	_person_tex = null
	_anim_frame = int(Time.get_ticks_msec() / 500) % 2
	if assets != null:
		var ms := mapset
		if ms.is_empty():
			ms = str(event.get("mapset", ""))
		_chip_texs[0] = assets.chip(ms)
		for slot in range(1, 4):
			_chip_texs[slot] = assets.chip(str(defines.get(slot, "")))
		_items_tex = assets.items()
		if not _persons.is_empty():
			_person_tex = assets.chara("", PERSON_GRA, PERSON_DEFAULT)
	# 広域図は俯瞰用なので、地図の倍率には連動させない
	# (第87段。倍率 4 の地図だと盤が 1000px を超えて邪魔に
	# なっていた)。チップ実寸 (32px) を上限に、盤全体が
	# MAX_BOARD_PX に収まるよう必要なら縮めるだけにする。
	_scale = clampf(MAX_BOARD_PX / float(_dim * MapView.CHIP_SIZE), 0.25, 1.0)
	custom_minimum_size = board_pixel_size()
	queue_redraw()


func board_dim() -> int:
	return _dim


func board_pixel_size() -> Vector2:
	return Vector2(_dim * MapView.CHIP_SIZE, _dim * MapView.CHIP_SIZE + MapView.MAP_TOP) * _scale


func _process(_delta: float) -> void:
	# 表示中は 500ms ごとのフレーム切替に合わせて描き直す
	# (Python 版は Eagle 窓も _anim_tick で再描画する)。
	if _dim <= 0 or not is_visible_in_tree():
		return
	var frame := int(Time.get_ticks_msec() / 500) % 2
	if frame != _anim_frame:
		_anim_frame = frame
		queue_redraw()


## セルの属性下位2ビットが指すシート。無ければ null。
func _sheet_for(cell: Dictionary) -> Texture2D:
	return _chip_texs[int(cell["attr"]) & 0x03] as Texture2D


func _draw() -> void:
	if _dim <= 0:
		return
	var z := _scale
	var cs := float(MapView.CHIP_SIZE)
	draw_rect(Rect2(Vector2.ZERO, size), Color.BLACK)
	var water: Variant = null
	var any_sheet := false
	for tex in _chip_texs:
		if tex != null:
			any_sheet = true
	if any_sheet:
		water = MapView.build_water_grid(_cells, _dim)
	var half := cs / 2.0
	for row in range(_dim):
		# 1. ベースチップ
		for col in range(_dim):
			var cell: Dictionary = _cells[row * _dim + col]
			var sheet := _sheet_for(cell)
			if sheet == null:
				var indices := MapView.chip_indices(int(cell["chip"]))
				var color: Color = MapView.FALLBACK_CHIP_COLORS.get(indices[0], MapView.FALLBACK_CHIP_DEFAULT)
				draw_rect(Rect2(col * cs * z, (row * cs + MapView.MAP_TOP) * z, cs * z, cs * z), color)
				continue
			for chip_index in MapView.chip_indices(int(cell["chip"])):
				_draw_chip(sheet, chip_index, col, row, z)
		# 1.5 水際 overlay
		if water != null:
			for col in range(_dim):
				var cell: Dictionary = _cells[row * _dim + col]
				if int(cell["chip"]) != MapView.WATER_BYTE:
					continue
				var sheet := _sheet_for(cell)
				if sheet == null:
					continue
				var patterns := MapView.water_quarter_patterns(water, row, col)
				for q in range(4):
					var hit: Variant = MapView.water_quarter_chip(q, patterns[q])
					if hit == null:
						continue
					var rect := MapView.chip_quarter_src_rect(hit[0], hit[1])
					if rect.size.x <= 0:
						continue
					var dx := (col * cs + (q & 1) * half) * z
					var dy := (row * cs + MapView.MAP_TOP + ((q >> 1) & 1) * half) * z
					draw_texture_rect_region(sheet, Rect2(dx, dy, half * z, half * z), rect)
		# 2. 看板 overlay
		for col in range(_dim):
			var cell: Dictionary = _cells[row * _dim + col]
			var sheet := _sheet_for(cell)
			if (int(cell["attr"]) & 0x08) == 0 or sheet == null:
				continue
			var board_index := MapView.BOARD_CHIP_HARD if int(cell["chip"]) in MapView._HARD_BOARD_CHIPS else MapView.BOARD_CHIP_SOFT
			_draw_chip(sheet, board_index, col, row, z)
		# 3. アイテム overlay
		for col in range(_dim):
			var cell: Dictionary = _cells[row * _dim + col]
			if (int(cell["attr"]) & 0x70) == 0:
				continue
			_draw_item(cell, col, row, z)
	# 4. 人 (既定グラ)
	if _person_tex != null:
		var rect := MapView.chara_src_rect("F", "*", _anim_frame)
		for p in _persons:
			var base_x := int(p["x"]) * cs + (cs - rect.size.x) / 2.0
			var base_y := int(p["y"]) * cs + (cs - MapView.CHARA_H) / 2.0 - MapView.CHARA_Y_ABOVE_FLOOR + MapView.MAP_TOP
			draw_texture_rect_region(_person_tex,
				Rect2(base_x * z, base_y * z, rect.size.x * z, rect.size.y * z), rect)


func _draw_chip(tex: Texture2D, index: int, col: int, row: int, z: float) -> void:
	var rect := MapView.chip_src_rect(index)
	if rect.size.x <= 0:
		return
	var overhang := MapView.CHIP_HEIGHT - MapView.CHIP_SIZE
	var dx := col * MapView.CHIP_SIZE * z
	var dy := (row * MapView.CHIP_SIZE - overhang + MapView.MAP_TOP) * z
	draw_texture_rect_region(tex, Rect2(dx, dy, rect.size.x * z, rect.size.y * z), rect)


func _draw_item(cell: Dictionary, col: int, row: int, z: float) -> void:
	var no := (int(cell["attr"]) & 0x70) >> 4
	var dst_x := col * MapView.CHIP_SIZE
	var dst_y := row * MapView.CHIP_SIZE + MapView.MAP_TOP
	var s := MapView.ITEM_SPRITE_SIZE
	if _items_tex == null:
		draw_rect(Rect2((dst_x + 8) * z, (dst_y + 8) * z, 16 * z, 16 * z), Color(1.0, 1.0, 0.78))
		return
	var draw_y := dst_y - MapView.ITEM_Y_ABOVE_FLOOR
	if int(cell["chip"]) in MapView._CIRCLE_CHIPS:
		var src_y := 5 if no == 5 or no == 6 else 0
		draw_texture_rect_region(_items_tex,
			Rect2(dst_x * z, draw_y * z, s * z, MapView.ITEM_CLIP_H * z),
			Rect2(no * s, src_y, s, MapView.ITEM_CLIP_H))
	else:
		draw_texture_rect_region(_items_tex,
			Rect2(dst_x * z, draw_y * z, s * z, s * z),
			Rect2(no * s, 0, s, s))
