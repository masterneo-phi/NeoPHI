class_name PhiDispMagic
extends RefCounted
## `#ex-disp-magic` の解析と描画の段取り。Philly の classDispMagic の移植。
##
## 行の形(Philly MakeMap.h の sscanf `"%x %x %x %x %x %c%x %x %x %c%x"`):
##   #ex-disp-magic <Effect> <Fn> <Power> <始点x> <始点y>
##                  <始点効果><始点引数> <終点x> <終点y> <終点効果><終点引数>
## 数値は16進、効果は1文字。`C0` のように文字と数値がくっついていても、
## `C 0` のように離れていても読める。区切りは空白かタブ。
##
## 描画は3段階(Philly の MagicAction0/1/2)。始点の効果で1段目、
## 終点の効果で2・3段目を決める。効果の文字:
##   `-` 通過 / `C` 発射 / `P` 発射・通過(1段目)・通過・命中(2段目)
##   `H` 命中 / `D` 射程で消滅 / `E` 通過・命中・爆発 / `S` 命中・爆発
## 絵は Items.bmp の 32x32 セル(9=発射、20=通過・命中、21〜29=爆発)。

## 始点・終点の効果文字。
const EFFECT_PASS := "-"
const EFFECT_CAST := "C"
const EFFECT_CAST_PASS := "P"
const EFFECT_HIT := "H"
const EFFECT_DISAPPEAR := "D"
const EFFECT_EXPLODE_PASS := "E"
const EFFECT_EXPLODE := "S"

## Items.bmp のセル番号。
const CELL_CAST := 9
const CELL_PASS := 20
const CELL_EXPLODE_CENTER := 25
## 爆発の周り8マス: [dx, dy, 引数のビット, セル]。
const EXPLODE_NEIGHBORS := [
	[-1, -1, 0x01, 21],
	[0, -1, 0x02, 22],
	[1, -1, 0x04, 23],
	[-1, 0, 0x08, 24],
	[1, 0, 0x10, 26],
	[-1, 1, 0x20, 27],
	[0, 1, 0x40, 28],
	[1, 1, 0x80, 29],
]


static func _hex_digit(c: int) -> int:
	if 0x30 <= c and c <= 0x39:
		return c - 0x30
	if 0x61 <= c and c <= 0x66:
		return c - 0x61 + 10
	if 0x41 <= c and c <= 0x46:
		return c - 0x41 + 10
	return -1


static func _skip_ws(text: String, pos: int) -> int:
	while pos < text.length():
		var c := text.unicode_at(pos)
		if c == 0x20 or c == 0x09:
			pos += 1
		else:
			break
	return pos


static func _read_hex(text: String, pos: int) -> Array:
	## 16進数を1つ読む。`[値, 次の位置]`、読めなければ []。
	## C の %x と同じく、符号と 0x を受け付ける。
	var i := pos
	var neg := false
	if i < text.length() and (text.unicode_at(i) == 0x2B or text.unicode_at(i) == 0x2D):
		neg = text.unicode_at(i) == 0x2D
		i += 1
	if i + 1 < text.length() and text.unicode_at(i) == 0x30 and (text.unicode_at(i + 1) == 0x78 or text.unicode_at(i + 1) == 0x58):
		i += 2
	var start := i
	var value := 0
	while i < text.length():
		var d := _hex_digit(text.unicode_at(i))
		if d < 0:
			break
		value = value * 16 + d
		i += 1
	if i == start:
		return []
	return [-value if neg else value, i]


static func parse(text: String) -> Variant:
	## `#ex-disp-magic` の行を辞書にする。読めなければ null。
	## 辞書: {effect, fn, power, start: {x, y, effect, param},
	##        end: {x, y, effect, param}}。
	if not text.begins_with("#ex-disp-magic"):
		return null
	if text.length() < 15:
		return null
	var sep := text.unicode_at(14)
	if sep != 0x20 and sep != 0x09:
		return null
	var pos := 15
	var head: Array = []
	for k in range(5):
		pos = _skip_ws(text, pos)
		var r := _read_hex(text, pos)
		if r.is_empty():
			return null
		head.append(r[0])
		pos = r[1]
	pos = _skip_ws(text, pos)
	if pos >= text.length():
		return null
	var start_effect := text.substr(pos, 1)
	pos += 1
	pos = _skip_ws(text, pos)
	var sp := _read_hex(text, pos)
	if sp.is_empty():
		return null
	pos = sp[1]
	var tail: Array = []
	for k in range(2):
		pos = _skip_ws(text, pos)
		var r2 := _read_hex(text, pos)
		if r2.is_empty():
			return null
		tail.append(r2[0])
		pos = r2[1]
	pos = _skip_ws(text, pos)
	if pos >= text.length():
		return null
	var end_effect := text.substr(pos, 1)
	pos += 1
	pos = _skip_ws(text, pos)
	var ep := _read_hex(text, pos)
	if ep.is_empty():
		return null
	return {
		"effect": head[0],
		"fn": head[1],
		"power": head[2],
		"start": {"x": head[3], "y": head[4], "effect": start_effect, "param": sp[0]},
		"end": {"x": tail[0], "y": tail[1], "effect": end_effect, "param": ep[0]},
	}


static func _grid_pos(x: int, y: int) -> Vector2:
	## マスの座標 → 地図の絵の中の座標。キャラの基準点と同じ +5。
	return Vector2(x * 32.0, y * 32.0 + 5.0)


static func _pass_cells(out: Array, data: Dictionary, action: int, print_start_end: bool) -> void:
	## 通過の線を、32x32 セルの描画位置の列で足す。
	## Philly の Pass: 全長の半分だけを、始点側(0段目)か終点側(1段目)に描く。
	var start: Dictionary = data["start"]
	var end: Dictionary = data["end"]
	var length_x := int(end["x"]) - int(start["x"])
	var length_y := int(end["y"]) - int(start["y"])
	var length_all := maxi(absi(length_x), absi(length_y))
	var length_now := length_all / 2
	if length_all == 0:
		length_all = 1
	var delta_x := 32.0 * length_x / length_all
	var delta_y := 32.0 * length_y / length_all
	var sx := float(int(start["x"]) * 32) if action == 0 else float(int(end["x"]) * 32) - length_now * delta_x
	var sy := float(int(start["y"]) * 32) if action == 0 else float(int(end["y"]) * 32) - length_now * delta_y
	sy += 5.0
	for i in range(length_now + 1):
		if not print_start_end and ((action == 0 and i == 0) or (action == 1 and i == length_now)):
			continue
		out.append([Vector2(sx + i * delta_x, sy + i * delta_y), CELL_PASS])


static func _explode_cells(out: Array, data: Dictionary) -> void:
	## 爆発: 中心と、引数のビットが立っている周りのマス。
	var end: Dictionary = data["end"]
	var param := int(end["param"])
	var ex := int(end["x"])
	var ey := int(end["y"])
	for n in EXPLODE_NEIGHBORS:
		if param & int(n[2]) != 0:
			out.append([_grid_pos(ex + int(n[0]), ey + int(n[1])), int(n[3])])
	out.append([_grid_pos(ex, ey), CELL_EXPLODE_CENTER])


static func phase_cells(data: Dictionary, phase: int) -> Array:
	## 段階(0/1/2)で描く [[位置, セル番号], ...]。位置は地図の絵の中の座標。
	var out: Array = []
	var start: Dictionary = data["start"]
	var end: Dictionary = data["end"]
	match phase:
		0:
			match str(start["effect"]):
				EFFECT_PASS:
					_pass_cells(out, data, 0, true)
				EFFECT_CAST:
					out.append([_grid_pos(int(start["x"]), int(start["y"])), CELL_CAST])
				EFFECT_CAST_PASS:
					_pass_cells(out, data, 0, false)
					out.append([_grid_pos(int(start["x"]), int(start["y"])), CELL_CAST])
		1:
			match str(end["effect"]):
				EFFECT_PASS:
					_pass_cells(out, data, 1, true)
				EFFECT_HIT, EFFECT_EXPLODE:
					out.append([_grid_pos(int(end["x"]), int(end["y"])), CELL_PASS])
				EFFECT_CAST_PASS, EFFECT_DISAPPEAR, EFFECT_EXPLODE_PASS:
					_pass_cells(out, data, 1, false)
					out.append([_grid_pos(int(end["x"]), int(end["y"])), CELL_PASS])
		2:
			match str(end["effect"]):
				EFFECT_HIT, EFFECT_CAST_PASS:
					out.append([_grid_pos(int(end["x"]), int(end["y"])), CELL_PASS])
				EFFECT_EXPLODE_PASS, EFFECT_EXPLODE:
					_explode_cells(out, data)
	return out


static func bolt_suppressed(recent_hits: Array, cell: Vector2i, now: float, window_sec: float) -> bool:
	## サーバー駆動の魔法表示が、同じマスを最近出したか。
	## 出していれば自前の魔法弾は出さず、二重表示を避ける。
	for hit in recent_hits:
		if hit["cell"] == cell and now - float(hit["spawned"]) < window_sec:
			return true
	return false
