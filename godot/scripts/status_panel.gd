class_name StatusPanel
extends Control
## HP/MP バー＋クラスレベル・Gold。Philly の classStatus の描画。
## 地図の列の下に置く。上に HP/MP のバーを2本、その下に
## F/W/M/C/EXP/GP を横に並べた行を出す。
##
## スキンの絵はバーの HpMpBar.bmp(100x15 のセルが 2行4列)だけ。
## 絵が無ければグラデーションのバーを描く。
## バーのセル: HP は通常 0・毒 3・減った分 1・空き 2。
## MP は通常 4・混乱 7・減った分 5・空き 6。
##
## バーの左の札と、ステータス行の見出しは、図形で描くアイコンに
## 文字ラベルを添えた形にした。HP＝赤いハート、MP＝青い雫、
## F＝剣、W＝杖、M＝天秤、C＝ハンマー、EXP＝星、GP＝金貨。
## ステータス行は項目ごとに枠を付け、行全体を中央寄せにする。
## 数字は4桁表示(満たない値は0埋め、9999超はそのまま)。
## Philly の Status.bmp は縦2列の枠なので使わない。

const BAR_CELL_W := 100.0
const BAR_CELL_H := 15.0
## バーとステータス行の間のすきま。
const ROW_GAP := 4.0
## バー同士のすきま。
const BAR_GAP := 4.0
## バーの高さは、数字の文字サイズ＋この余白。
const BAR_PAD := 6.0
## ステータス行の高さは、文字サイズ＋この余白。
const ROW_PAD := 10.0
## ステータス行の項目ごとの枠: 枠同士のすきま、枠の左右の余白、
## アイコンの上下の余白、アイコンと文字・文字と数字の間。
const BOX_GAP := 8.0
const BOX_PAD_X := 5.0
const BOX_INSET_Y := 3.0
const BOX_ICON_GAP := 4.0
const BOX_LABEL_GAP := 4.0
## 枠の地と境界線。パネルの地(0.16)に馴染む色。
const BOX_BG := Color(0.23, 0.23, 0.23)
const BOX_BORDER := Color(1, 1, 1, 0.35)

## ステータス行の項目: [文字ラベル, 値のキー]。
## 並び順は F/W/M/C/EXP/GP。アイコンは f=剣、w=杖、m=天秤、c=ハンマー、
## exp=星、gp=金貨を図形で描き、文字ラベルも添える。
const STATUS_ITEMS := [
	["F", "f"],
	["W", "w"],
	["M", "m"],
	["C", "c"],
	["EXP", "exp"],
	["GP", "gp"],
]

## ステータス行の文字ラベルの色(項目ごと)。金属地の上で
## 読みやすい明るさにしてある。F=赤、W=紫、M=黄緑、C=黄色、
## EXP=水色、GP=金色。アイコンと数字(白)は従来どおり。
const STATUS_LABEL_COLORS := {
	"f": Color(1.0, 0.38, 0.32),
	"w": Color(0.80, 0.50, 1.0),
	"m": Color(0.62, 0.95, 0.35),
	"c": Color(1.0, 0.88, 0.30),
	"exp": Color(0.45, 0.85, 1.0),
	"gp": Color(1.0, 0.76, 0.28),
}
const STATUS_LABEL_DEFAULT := Color(0.65, 0.65, 0.65)


static func status_label_color(key: String) -> Color:
	## ステータス行の文字ラベルの色。キーは f/w/m/c/exp/gp。
	return STATUS_LABEL_COLORS.get(key, STATUS_LABEL_DEFAULT)

var label_font: Font = null
var bold_font: Font = null
var hpmp_tex: Texture2D = null

## ゲージの数字の文字サイズ。全体のフォント設定 (MenuFontSize)
## で決める (付け替えは PhiCharacter.refresh_ui_font_size)。
var gauge_font_size := 14
## ステータス行の文字サイズ。ゲージと同じく MenuFontSize 由来。
var status_font_size := 14

var _hp := -1
var _max_hp := 0
var _mp := -1
var _max_mp := 0
var _f := 0
var _w := 0
var _m := 0
var _c := 0
var _exp := 0
var _gp := 0
var _poison := false
var _panic := false
## 状態異常7種 (#cond)。バーの色に使う毒・恐慌以外も名前で出す。
var _cond := {"poison": false, "palsy": false, "panic": false,
	"confuse": false, "berserk": false, "silence": false, "blind": false}
## モード (#attack / #magic)。状態行の右端に「戦闘」「魔法」と出す。
var _mode_attack := false
var _mode_magic := false
var _prev_hp := -1
var _prev_mp := -1
## ペット (PHIDM NEO v2.0 の #ex-pet self)。空なら表示なし。
## {"type","name","mp","st","active","mpMax","stMax"}。
var _pet: Dictionary = {}
## 自分の職業・性別 (PHIDM NEO v2.0 の #ex-job self)。
## phi.jb の無い世界・未設定では空文字列。
var _job := ""
var _sex := ""

## ペットのタイプ表示名。
const PET_TYPE_NAMES := {"fairy": "妖精", "cat": "猫", "dog": "犬", "bird": "鳥"}


func _init() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(0, panel_height(gauge_font_size, status_font_size))


## 文字サイズからパネルの高さを決める。配置側はこの値を
## custom_minimum_size に使う。
static func panel_height(gauge_size: int, status_size: int) -> float:
	var bar_h := float(gauge_size) + BAR_PAD
	var row_h := float(status_size) + ROW_PAD
	return bar_h * 2.0 + BAR_GAP + ROW_GAP + row_h


## 文字サイズを付け直し、高さも合わせる。
func set_ui_sizes(gauge_size: int, status_size: int) -> void:
	gauge_font_size = gauge_size
	status_font_size = status_size
	_refresh_min_size()
	queue_redraw()


## ペット行・職業行 (追加行) が要るか。
func extra_row_visible() -> bool:
	return not _pet.is_empty() or not _job.is_empty() or not _sex.is_empty()


## 追加行の高さ。表示が無ければ 0。
func _extra_height() -> float:
	return (float(status_font_size) + ROW_PAD) if extra_row_visible() else 0.0


func _refresh_min_size() -> void:
	custom_minimum_size = Vector2(0,
		panel_height(gauge_font_size, status_font_size) + _extra_height())


## 自分のペットを反映する。空の辞書で表示を消す。
func set_pet(pet: Dictionary) -> void:
	_pet = pet.duplicate()
	_refresh_min_size()
	queue_redraw()


## 自分の職業・性別を反映する。
func set_job(p_job: String, p_sex: String) -> void:
	_job = p_job
	_sex = p_sex
	_refresh_min_size()
	queue_redraw()


static func pet_head_text_for(pet: Dictionary) -> String:
	## ペット行の見出し。「名前 (タイプ)」、休止中は末尾に足す。
	if pet.is_empty():
		return ""
	var tname: String = PET_TYPE_NAMES.get(str(pet.get("type", "")), "")
	var head := str(pet.get("name", ""))
	if not tname.is_empty():
		head += " (" + tname + ")"
	if int(pet.get("active", 1)) == 0:
		head += " 休止中"
	return head


static func job_text_for(p_job: String, p_sex: String) -> String:
	## 職業・性別の併記。ある方だけでも出す。
	var parts: Array[String] = []
	if not p_job.is_empty():
		parts.append(p_job)
	if not p_sex.is_empty():
		parts.append(p_sex)
	return " ".join(parts)


func debug_pet() -> Dictionary:
	return {"pet": _pet.duplicate(), "job": _job, "sex": _sex,
		"extra": extra_row_visible()}


func set_status(event: Dictionary) -> void:
	## `#status` のイベントを反映する。無い項目は前の値を保つ。
	## HP/MP が減った時は、前の値を減った分の表示に残す。
	if event.has("hp"):
		if _hp >= 0:
			_prev_hp = _hp
		_hp = int(event["hp"])
	if event.has("maxHp"):
		_max_hp = int(event["maxHp"])
	if event.has("mp"):
		if _mp >= 0:
			_prev_mp = _mp
		_mp = int(event["mp"])
	if event.has("maxMp"):
		_max_mp = int(event["maxMp"])
	if event.has("f"):
		_f = int(event["f"])
	if event.has("w"):
		_w = int(event["w"])
	if event.has("m"):
		_m = int(event["m"])
	if event.has("c"):
		_c = int(event["c"])
	if event.has("exp"):
		_exp = int(event["exp"])
	if event.has("gp"):
		_gp = int(event["gp"])
	queue_redraw()


func set_conditions(poison: bool, panic: bool) -> void:
	if poison == _poison and panic == _panic:
		return
	_poison = poison
	_panic = panic
	_cond["poison"] = poison
	_cond["panic"] = panic
	queue_redraw()


## 状態異常の名前 (Python 版 gui.py と同じ並び・名前)。
const CONDITION_NAMES := [["poison", "毒"], ["palsy", "麻痺"], ["panic", "恐慌"],
	["confuse", "混乱"], ["berserk", "狂戦士"], ["silence", "沈黙"], ["blind", "盲目"]]


static func condition_names(cond: Dictionary) -> Array:
	var out: Array = []
	for pair in CONDITION_NAMES:
		if bool(cond.get(pair[0], false)):
			out.append(pair[1])
	return out


static func mode_tags(attack: bool, magic: bool) -> Array:
	var out: Array = []
	if attack:
		out.append("戦闘")
	if magic:
		out.append("魔法")
	return out


func condition_text() -> String:
	return " ".join(condition_names(_cond))


func mode_text() -> String:
	return " ".join(mode_tags(_mode_attack, _mode_magic))


## #cond イベントを丸ごと反映する (7種すべて)。
func set_conditions_all(event: Dictionary) -> void:
	var changed := false
	for pair in CONDITION_NAMES:
		var v := bool(event.get(pair[0], false))
		if bool(_cond[pair[0]]) != v:
			_cond[pair[0]] = v
			changed = true
	_poison = bool(_cond["poison"])
	_panic = bool(_cond["panic"])
	if changed:
		queue_redraw()


## #attack / #magic のモードを反映する。
func set_mode(attack: bool, magic: bool) -> void:
	if attack == _mode_attack and magic == _mode_magic:
		return
	_mode_attack = attack
	_mode_magic = magic
	queue_redraw()


func debug_values() -> Dictionary:
	return {"hp": _hp, "maxHp": _max_hp, "mp": _mp, "maxMp": _max_mp, "f": _f, "w": _w, "m": _m, "c": _c, "exp": _exp, "gp": _gp, "prevHp": _prev_hp, "prevMp": _prev_mp}


static func bar_segments(value: int, max_value: int, prev_value: int, width_px: float, fill_cell: int, trail_cell: int, empty_cell: int) -> Array:
	## Philly の DrawStatusContents の区間分け。
	## [[x0, 幅, セル番号], ...] を返す。値は最大値で割って幅にする。
	if max_value <= 0 or width_px <= 0.0:
		return []
	var ratio := width_px / float(max_value)
	var fill_w := minf(floorf(float(value) * ratio + 0.5), width_px)
	var segs: Array = []
	var x := 0.0
	if fill_w > 0.0:
		segs.append([x, fill_w, fill_cell])
		x += fill_w
	if prev_value >= 0 and value < prev_value:
		var trail_w := minf(floorf(float(mini(prev_value, max_value) - value) * ratio + 0.5), width_px - x)
		if trail_w > 0.0:
			segs.append([x, trail_w, trail_cell])
			x += trail_w
	if width_px - x > 0.0:
		segs.append([x, width_px - x, empty_cell])
	return segs


static func bar_cells(poisoned: bool, panicked: bool) -> Array:
	## バーのセル番号 [HP通常, HP減分, HP空き, MP通常, MP減分, MP空き]。
	## 毒の時は HP が 3、混乱の時は MP が 7 になる(Philly)。
	return [3 if poisoned else 0, 1, 2, 7 if panicked else 4, 5, 6]


static func format_status_value(value: int) -> String:
	## ステータス行の数字は4桁表示。満たない値は0埋めし、
	## 9999を超える値はそのまま出す(切り捨てない)。
	return "%04d" % value


static func format_value_for(key: String, value: int) -> String:
	## 項目ごとの桁数。EXP は大きくなるので8桁表示にする
	## (ユーザーの指定)。それ以外は4桁。
	if key == "exp":
		return "%08d" % value
	return format_status_value(value)


static func format_bar_text(value: int, max_value: int) -> String:
	## バーの数字は「現在値/最大値」で、両方とも4桁表示にする。
	## HP 行と MP 行で幅がそろい、数字が縦に整列して見える。
	## 9999を超える値はそのまま出す(切り捨てない)。
	return "%04d/%04d" % [value, max_value]


func _status_value(key: String) -> int:
	match key:
		"f":
			return _f
		"w":
			return _w
		"m":
			return _m
		"c":
			return _c
		"exp":
			return _exp
		"gp":
			return _gp
	return 0


func status_box_rects(row_y: float, row_h: float) -> Array:
	## ステータス行の項目ごとの枠の矩形を、並び順に返す。
	## 行全体がパネルの幅の中央に来るよう、合計幅から開始位置を決める。
	## 枠の幅は、アイコン＋文字ラベル＋4桁の数字が入る幅。
	var value_font := bold_font if bold_font != null else label_font
	var icon_w := row_h - BOX_INSET_Y * 2.0
	var widths: Array = []
	var total := 0.0
	for item in STATUS_ITEMS:
		var label_w := 0.0
		if label_font != null:
			label_w = label_font.get_string_size(str(item[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, status_font_size).x
		var num_w := 0.0
		if value_font != null:
			var text := format_value_for(str(item[1]), _status_value(str(item[1])))
			num_w = value_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, status_font_size).x
		var bw := BOX_PAD_X * 2.0 + icon_w + BOX_ICON_GAP + label_w + BOX_LABEL_GAP + num_w
		widths.append(bw)
		total += bw
	total += BOX_GAP * float(maxi(widths.size() - 1, 0))
	var x := maxf(0.0, (size.x - total) * 0.5)
	var rects: Array = []
	for bw in widths:
		rects.append(Rect2(x, row_y, bw, row_h))
		x += bw + BOX_GAP
	return rects


func _bar_height() -> float:
	## 1本のバーの高さ。パネルの高さからステータス行と追加行を
	## 引いた残りを、すきまを挟んで2等分する。
	var row_h := float(status_font_size) + ROW_PAD
	var bars_h := maxf(0.0, size.y - _extra_height() - row_h - ROW_GAP)
	return maxf(1.0, (bars_h - BAR_GAP) * 0.5)


func bar_rects() -> Array:
	## [HPバーの矩形, MPバーの矩形]。左端と幅は両行で完全に同じ。
	## 左端は、両行共通の札幅(広い方に合わせた固定幅)から決める。
	## 行ごとに札幅が変わると、バーの始まる位置がずれて見える。
	var bar_h := _bar_height()
	var scale := bar_h / BAR_CELL_H
	var left := plate_width(bar_h) + 4.0 * scale
	var w := maxf(0.0, size.x - left)
	return [Rect2(left, 0.0, w, bar_h), Rect2(left, bar_h + BAR_GAP, w, bar_h)]


func _draw() -> void:
	if size.y <= 0.0 or size.x <= 0.0:
		return
	# 地は金属テクスチャ(無ければ従来の単色)。枠やバーは
	# この上にそのまま重ねて描く。
	var metal := UiStyle.metal_texture()
	if metal != null:
		draw_texture_rect(metal, Rect2(Vector2.ZERO, size), true)
	else:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.16, 0.16, 0.16))
	var row_h := float(status_font_size) + ROW_PAD
	var bars_h := maxf(0.0, size.y - _extra_height() - row_h - ROW_GAP)
	var bar_h := _bar_height()
	var scale := bar_h / BAR_CELL_H
	var rects := bar_rects()
	var hp_rect: Rect2 = rects[0]
	var mp_rect: Rect2 = rects[1]
	# バーの左の札は、図形で描くアイコン＋文字(HP=ハート+「HP」、
	# MP=雫+「MP」)。大きさはバーの高さに合わせる。
	_draw_hpmp_icons(bar_h)
	# バー。
	var cells := bar_cells(_poison, _panic)
	_draw_bar(bar_segments(_hp, _max_hp, _prev_hp, hp_rect.size.x, cells[0], cells[1], cells[2]), hp_rect.position.x, hp_rect.position.y, scale, Color(0.35, 0.95, 0.45), Color(0.05, 0.55, 0.15))
	_draw_bar(bar_segments(_mp, _max_mp, _prev_mp, mp_rect.size.x, cells[3], cells[4], cells[5]), mp_rect.position.x, mp_rect.position.y, scale, Color(0.35, 0.8, 1.0), Color(0.05, 0.35, 0.9))
	# バーの数字(白太字、中央)。まだ状態が届いていない時は出さない。
	if _hp >= 0:
		_draw_bar_number(format_bar_text(_hp, _max_hp), hp_rect)
	if _mp >= 0:
		_draw_bar_number(format_bar_text(_mp, _max_mp), mp_rect)
	# ステータス行。バーと区切る細い線を入れて、横に並べる。
	var row_y := bars_h + ROW_GAP
	draw_rect(Rect2(0, row_y, size.x, 1.0), Color(1, 1, 1, 0.15))
	_draw_status_row(row_y + 1.0, row_h - 1.0)
	# 追加行 (ペット・職業)。ある時だけ、ステータス行の下に出す。
	if extra_row_visible():
		var ey := row_y + row_h
		draw_rect(Rect2(0, ey, size.x, 1.0), Color(1, 1, 1, 0.15))
		_draw_extra_row(ey + 1.0, row_h - 1.0)


func _draw_extra_row(y: float, row_h: float) -> void:
	## 追加行。左にペット (名前と MP/体力の小バー)、右端に
	## 職業・性別 (ステータス行のモード表示と同じ流儀で、
	## 重なる時は出さない)。
	if label_font == null:
		return
	var font_size := status_font_size
	var value_font := bold_font if bold_font != null else label_font
	var baseline := y + row_h * 0.5 + value_font.get_ascent(font_size) * 0.5
	var x := 4.0
	if not _pet.is_empty():
		var head := pet_head_text_for(_pet)
		if not head.is_empty():
			draw_string(value_font, Vector2(x, baseline), head, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(1.0, 0.9, 0.6))
			x += value_font.get_string_size(head, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x + 8.0
		x = _draw_pet_pool(x, y, row_h, "MP", int(_pet.get("mp", 0)),
			int(_pet.get("mpMax", 100)), Color(0.35, 0.8, 1.0), font_size, baseline)
		x = _draw_pet_pool(x, y, row_h, "体力", int(_pet.get("st", 0)),
			int(_pet.get("stMax", 100)), Color(0.45, 0.95, 0.5), font_size, baseline)
	var job_text := job_text_for(_job, _sex)
	if not job_text.is_empty():
		var w := label_font.get_string_size(job_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		var jx := size.x - 4.0 - w
		if jx > x + 6.0:
			draw_string(label_font, Vector2(jx, baseline), job_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(0.85, 0.9, 1.0))


func _draw_pet_pool(x: float, y: float, row_h: float, label: String, value: int, max_value: int, color: Color, font_size: int, baseline: float) -> float:
	## ペットのプール1つ分 (札 + 小バー + 数字)。次の x を返す。
	var num_font := bold_font if bold_font != null else label_font
	draw_string(label_font, Vector2(x, baseline), label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(0.75, 0.75, 0.75))
	x += label_font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x + 3.0
	var bar_w := 44.0
	var bar_h := maxf(5.0, row_h * 0.34)
	var bar_y := y + (row_h - bar_h) * 0.5
	draw_rect(Rect2(x, bar_y, bar_w, bar_h), Color(0.1, 0.1, 0.1))
	if max_value > 0:
		var frac := clampf(float(value) / float(max_value), 0.0, 1.0)
		if frac > 0.0:
			draw_rect(Rect2(x, bar_y, bar_w * frac, bar_h), color)
	draw_rect(Rect2(x, bar_y, bar_w, bar_h), Color(0, 0, 0, 0.6), false, 1.0)
	x += bar_w + 3.0
	var num := "%d/%d" % [value, max_value]
	draw_string(num_font, Vector2(x, baseline), num, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.WHITE)
	x += num_font.get_string_size(num, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x + 8.0
	return x


var _box_style: StyleBoxFlat = null


func _status_box_style() -> StyleBoxFlat:
	## ステータス行の項目の枠。角丸の StyleBox として描く。
	if _box_style == null:
		_box_style = StyleBoxFlat.new()
		_box_style.bg_color = BOX_BG
		_box_style.border_color = BOX_BORDER
		_box_style.set_border_width_all(1)
		UiStyle.round_box(_box_style)
	return _box_style


func _draw_bar(segs: Array, x: float, y: float, scale: float, light: Color, dark: Color) -> void:
	if segs.is_empty():
		return
	var use_skin := hpmp_tex != null and hpmp_tex.get_width() >= 400 and hpmp_tex.get_height() >= 31
	for seg in segs:
		var sx: float = x + float(seg[0])
		var sw: float = seg[1]
		var cell: int = seg[2]
		if use_skin:
			_draw_bar_segment_skin(cell, sx, y, sw, scale)
		else:
			_draw_bar_segment_gradient(cell, sx, y, sw, scale, light, dark)


func _draw_bar_segment_skin(cell: int, x: float, y: float, w: float, scale: float) -> void:
	## Philly の HpMpBarPartWrite: 100px ごとに並べ、余りを部分描画する。
	var col := cell % 4
	var row := cell / 4
	var src := Rect2(col * BAR_CELL_W, row * 16.0, BAR_CELL_W, BAR_CELL_H)
	var left := x
	var remain := w
	var chunk := BAR_CELL_W * scale
	while remain >= chunk:
		draw_texture_rect_region(hpmp_tex, Rect2(left, y, chunk, BAR_CELL_H * scale), src)
		left += chunk
		remain -= chunk
	if remain > 0.0:
		var part := Rect2(src.position, Vector2(remain / scale, BAR_CELL_H))
		draw_texture_rect_region(hpmp_tex, Rect2(left, y, remain, BAR_CELL_H * scale), part)


func _draw_bar_segment_gradient(cell: int, x: float, y: float, w: float, scale: float, light: Color, dark: Color) -> void:
	## 代用のグラデーション。減った分は赤、空きは暗い色。
	var h := BAR_CELL_H * scale
	if cell == 1 or cell == 5:
		draw_rect(Rect2(x, y, w, h), Color(0.85, 0.25, 0.20))
	elif cell == 2 or cell == 6:
		draw_rect(Rect2(x, y, w, h), Color(0.12, 0.12, 0.12))
	else:
		var steps := 8
		for i in range(steps):
			var t := float(i) / float(steps - 1)
			var c := light.lerp(dark, t)
			draw_rect(Rect2(x, y + h * i / steps, w, h / steps + 1.0), c)
	draw_rect(Rect2(x, y, w, h), Color(0, 0, 0, 0.6), false, 1.0)


static func bar_number_layout(cur_w: float, slash_w: float, rect: Rect2) -> Array:
	## バーの数字の描画位置 [現在値の左端, スラッシュの左端,
	## 最大値の左端]。スラッシュをバーの中央に固定し、現在値は
	## その左へ右寄せ、最大値は右へ左寄せで置く。フォントの
	## 数字幅が等幅でなくても、HP 行と MP 行でスラッシュと
	## 値の端が縦にそろう (従来は文字列全体を中央寄せしていた
	## ため、数字の形で幅が変わり行ごとにずれていた)。
	var cx := rect.position.x + rect.size.x * 0.5
	var gap := slash_w * 0.35
	return [cx - slash_w * 0.5 - gap - cur_w, cx - slash_w * 0.5, cx + slash_w * 0.5 + gap]


func _draw_bar_number(text: String, rect: Rect2) -> void:
	if bold_font == null or rect.size.x <= 0.0:
		return
	var font_size := gauge_font_size
	var h := bold_font.get_height(font_size)
	var baseline := rect.position.y + (rect.size.y + h * 0.7) * 0.5
	var parts := text.split("/")
	if parts.size() != 2:
		var w := bold_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		_draw_number_part(text, Vector2(rect.position.x + (rect.size.x - w) * 0.5, baseline), font_size)
		return
	var slash_w := bold_font.get_string_size("/", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var cur_w := bold_font.get_string_size(parts[0], HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var xs := bar_number_layout(cur_w, slash_w, rect)
	_draw_number_part(parts[0], Vector2(xs[0], baseline), font_size)
	_draw_number_part("/", Vector2(xs[1], baseline), font_size)
	_draw_number_part(parts[1], Vector2(xs[2], baseline), font_size)


func _draw_number_part(text: String, at: Vector2, font_size: int) -> void:
	draw_string_outline(bold_font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 3, Color(0, 0, 0))
	draw_string(bold_font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.WHITE)


func _draw_status_row(row_y: float, row_h: float) -> void:
	## F/W/M/C/EXP/GP を、項目ごとの枠で横に並べ、行全体を中央寄せ。
	## 枠の中は、左から図形のアイコン・文字ラベル(灰色)・
	## 4桁表示の数字(白太字)。
	if label_font == null:
		return
	var value_font := bold_font if bold_font != null else label_font
	var font_size := status_font_size
	var baseline := row_y + row_h * 0.5 + value_font.get_ascent(font_size) * 0.5
	var rects := status_box_rects(row_y, row_h)
	for i in STATUS_ITEMS.size():
		var rect: Rect2 = rects[i]
		draw_style_box(_status_box_style(), rect)
		var icon_side := row_h - BOX_INSET_Y * 2.0
		var icon_rect := Rect2(rect.position + Vector2(BOX_PAD_X, BOX_INSET_Y), Vector2(icon_side, icon_side))
		_draw_status_icon(str(STATUS_ITEMS[i][1]), icon_rect)
		var label_text := str(STATUS_ITEMS[i][0])
		var lx := icon_rect.end.x + BOX_ICON_GAP
		draw_string(label_font, Vector2(lx, baseline), label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, status_label_color(str(STATUS_ITEMS[i][1])))
		var label_w := label_font.get_string_size(label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		var text := format_value_for(str(STATUS_ITEMS[i][1]), _status_value(str(STATUS_ITEMS[i][1])))
		draw_string(value_font, Vector2(lx + label_w + BOX_LABEL_GAP, baseline), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.WHITE)
	# 状態異常は行の左端、モード (戦闘/魔法) は右端に出す。
	# 中央の枠と重なる時は出さない。
	if not rects.is_empty():
		var boxes_left := (rects[0] as Rect2).position.x
		var boxes_right := (rects[rects.size() - 1] as Rect2).end.x
		var cond_text := condition_text()
		if not cond_text.is_empty():
			var w := label_font.get_string_size(cond_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
			if 4.0 + w < boxes_left - 6.0:
				draw_string(label_font, Vector2(4, baseline), cond_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(1.0, 0.78, 0.35))
		var mtext := mode_text()
		if not mtext.is_empty():
			var w := label_font.get_string_size(mtext, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
			if size.x - 4.0 - w > boxes_right + 6.0:
				draw_string(label_font, Vector2(size.x - 4.0 - w, baseline), mtext, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(1.0, 0.62, 0.62) if _mode_attack else Color(0.65, 0.85, 1.0))


# -- アイコン(図形で描く) -----------------------------------------------------

func _plate_font_size(bar_h: float) -> int:
	## バーの左の札の文字(HP/MP)の大きさ。バーの高さに合わせる。
	return maxi(int(bar_h * 0.52), 8)


func plate_width(bar_h: float) -> float:
	## バーの左の札(アイコン＋HP/MP の文字)の幅。両行で共通の
	## 固定幅にするため、文字幅は HP と MP の広い方に合わせる。
	## 行ごとに幅を決めると、バーの左端がずれて見える。
	var font := bold_font if bold_font != null else label_font
	var w := bar_h * 0.94 + 4.0
	if font != null:
		var fs := _plate_font_size(bar_h)
		w += maxf(
			font.get_string_size("HP", HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x,
			font.get_string_size("MP", HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x) + 2.0
	return w


func _draw_hpmp_icons(bar_h: float) -> void:
	## バーの左に置く HP/MP の札。HP=赤いハート+「HP」、
	## MP=青い雫+「MP」。アイコンの大きさはバーの高さに合わせる。
	var side := bar_h * 0.94
	var y0 := (bar_h - side) * 0.5
	_draw_heart(Rect2(0.0, y0, side, side))
	_draw_droplet(Rect2(0.0, bar_h + BAR_GAP + y0, side, side))
	var font := bold_font if bold_font != null else label_font
	if font == null:
		return
	var fs := _plate_font_size(bar_h)
	var tx := side + 4.0
	draw_string(font, Vector2(tx, bar_h * 0.5 + font.get_ascent(fs) * 0.5), "HP", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1.0, 0.50, 0.50))
	draw_string(font, Vector2(tx, bar_h + BAR_GAP + bar_h * 0.5 + font.get_ascent(fs) * 0.5), "MP", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.55, 0.80, 1.0))


func _draw_heart(r: Rect2) -> void:
	## 赤いハート。丸2つと下向きの三角で作る。
	var s := r.size.x
	var cx := r.position.x + s * 0.5
	var red := Color(0.93, 0.24, 0.28)
	var cr := s * 0.175
	draw_circle(Vector2(cx - s * 0.165, r.position.y + s * 0.36), cr, red)
	draw_circle(Vector2(cx + s * 0.165, r.position.y + s * 0.36), cr, red)
	var tri := PackedVector2Array([
		Vector2(cx - s * 0.335, r.position.y + s * 0.40),
		Vector2(cx + s * 0.335, r.position.y + s * 0.40),
		Vector2(cx, r.position.y + s * 0.90)])
	draw_colored_polygon(tri, red)
	# 左上の光。
	draw_circle(Vector2(cx - s * 0.19, r.position.y + s * 0.31), s * 0.055, Color(1, 1, 1, 0.55))


func _draw_droplet(r: Rect2) -> void:
	## 青い雫。丸と上向きの三角で作る。ハートと同じ枠いっぱいに
	## 対称に描く (以前は中心を左へ寄せていたため、ハートより
	## 小さく・左寄りに見えて札の並びがずれて見えた)。
	var s := r.size.x
	var cx := r.position.x + s * 0.5
	var blue := Color(0.30, 0.65, 1.0)
	var tri := PackedVector2Array([
		Vector2(cx - s * 0.26, r.position.y + s * 0.58),
		Vector2(cx + s * 0.26, r.position.y + s * 0.58),
		Vector2(cx, r.position.y + s * 0.06)])
	draw_colored_polygon(tri, blue)
	draw_circle(Vector2(cx, r.position.y + s * 0.62), s * 0.30, blue)
	# 左の光。
	draw_circle(Vector2(cx - s * 0.11, r.position.y + s * 0.68), s * 0.06, Color(1, 1, 1, 0.6))


func _draw_status_icon(kind: String, r: Rect2) -> void:
	## ステータス行の見出しの代わりの小さい絵。外部素材は使わず
	## 図形で描く。f=剣、w=杖、m=天秤、c=ハンマー、exp=星、gp=金貨。
	var w := maxf(2.0, r.size.x * 0.10)
	match kind:
		"f":
			_draw_icon_sword(r, w)
		"w":
			_draw_icon_wand(r, w)
		"m":
			_draw_icon_scales(r, w)
		"c":
			_draw_icon_hammer(r, w)
		"exp":
			_draw_icon_star(r)
		"gp":
			_draw_icon_coin(r)


func _draw_icon_sword(r: Rect2, w: float) -> void:
	## 剣。右上を向いた刃、鍔、柄。
	var s := r.size.x
	var tip := r.position + Vector2(0.82, 0.06) * s
	var base := r.position + Vector2(0.40, 0.48) * s
	var dirv := (base - tip).normalized()
	var perp := Vector2(-dirv.y, dirv.x)
	draw_line(tip, base, Color(0.88, 0.91, 0.95), w)
	draw_line(base - perp * s * 0.17, base + perp * s * 0.17, Color(0.85, 0.65, 0.25), w)
	var pommel := base + dirv * s * 0.30
	draw_line(base, pommel, Color(0.45, 0.30, 0.16), w)
	draw_circle(pommel, w * 0.75, Color(0.85, 0.65, 0.25))


func _draw_icon_wand(r: Rect2, w: float) -> void:
	## 杖。斜めの棒と、先端の星。
	var s := r.size.x
	draw_line(r.position + Vector2(0.18, 0.90) * s, r.position + Vector2(0.62, 0.34) * s, Color(0.55, 0.38, 0.20), w)
	var c := r.position + Vector2(0.70, 0.24) * s
	var rr := s * 0.17
	var pts := PackedVector2Array()
	for i in range(8):
		var ang := -PI * 0.5 + float(i) * PI / 4.0
		var rad := rr if i % 2 == 0 else rr * 0.38
		pts.append(c + Vector2(cos(ang), sin(ang)) * rad)
	draw_colored_polygon(pts, Color(1.0, 0.85, 0.30))
	draw_circle(c, rr * 0.22, Color(1.0, 0.98, 0.90))


func _draw_icon_scales(r: Rect2, w: float) -> void:
	## 天秤。柱と梁、左右の皿、台。
	var s := r.size.x
	var cx := r.position.x + s * 0.5
	var gold := Color(0.85, 0.68, 0.30)
	draw_line(Vector2(cx, r.position.y + s * 0.16), Vector2(cx, r.position.y + s * 0.78), gold, w * 0.8)
	draw_line(Vector2(r.position.x + s * 0.14, r.position.y + s * 0.26), Vector2(r.position.x + s * 0.86, r.position.y + s * 0.26), gold, w * 0.8)
	draw_circle(Vector2(cx, r.position.y + s * 0.13), w * 0.6, gold)
	draw_line(Vector2(cx - s * 0.18, r.position.y + s * 0.82), Vector2(cx + s * 0.18, r.position.y + s * 0.82), gold, w * 0.8)
	_draw_scale_pan(r, 0.20)
	_draw_scale_pan(r, 0.80)


func _draw_scale_pan(r: Rect2, center_frac: float) -> void:
	## 天秤の皿。吊り紐2本と、浅い器。
	var s := r.size.x
	var top := Vector2(r.position.x + s * center_frac, r.position.y + s * 0.26)
	var left := Vector2(r.position.x + s * (center_frac - 0.13), r.position.y + s * 0.54)
	var right := Vector2(r.position.x + s * (center_frac + 0.13), r.position.y + s * 0.54)
	draw_line(top, left, Color(0.75, 0.75, 0.75), 1.0)
	draw_line(top, right, Color(0.75, 0.75, 0.75), 1.0)
	var bowl := PackedVector2Array([
		left, right,
		Vector2(right.x - s * 0.05, r.position.y + s * 0.68),
		Vector2(left.x + s * 0.05, r.position.y + s * 0.68)])
	draw_colored_polygon(bowl, Color(0.85, 0.68, 0.30))


func _draw_icon_hammer(r: Rect2, w: float) -> void:
	## ハンマー。斜めの柄と、直交する頭。
	var s := r.size.x
	draw_line(r.position + Vector2(0.28, 0.90) * s, r.position + Vector2(0.58, 0.44) * s, Color(0.55, 0.38, 0.20), w * 1.1)
	var head_c := r.position + Vector2(0.62, 0.30) * s
	var axis := Vector2(0.7071, -0.7071)
	var perp := Vector2(0.7071, 0.7071)
	var hl := s * 0.27
	var hw := s * 0.12
	var pts := PackedVector2Array([
		head_c - axis * hl - perp * hw,
		head_c + axis * hl - perp * hw,
		head_c + axis * hl + perp * hw,
		head_c - axis * hl + perp * hw])
	draw_colored_polygon(pts, Color(0.75, 0.78, 0.82))


func _draw_icon_star(r: Rect2) -> void:
	## 経験値の星。水色の5角星と、白い芯。
	var c := r.get_center()
	var rr := r.size.x * 0.40
	var pts := PackedVector2Array()
	for i in range(10):
		var ang := -PI * 0.5 + float(i) * PI / 5.0
		var rad := rr if i % 2 == 0 else rr * 0.45
		pts.append(c + Vector2(cos(ang), sin(ang)) * rad)
	draw_colored_polygon(pts, Color(0.55, 0.85, 1.0))
	draw_circle(c, rr * 0.20, Color(0.95, 0.99, 1.0))


func _draw_icon_coin(r: Rect2) -> void:
	## 金貨。丸と内側の輪と芯。
	var c := r.get_center()
	var rad := r.size.x * 0.36
	draw_circle(c, rad, Color(0.98, 0.78, 0.25))
	draw_arc(c, rad * 0.68, 0.0, TAU, 32, Color(0.80, 0.58, 0.12), 2.0)
	draw_circle(c, rad * 0.20, Color(0.90, 0.66, 0.18))
