class_name PhiCombatFx
extends RefCounted
## 戦闘の演出のもとになる、ログの読み取りと形の計算。
##
## Python 版 neophi/combat_fx.py の移植。攻撃の行から攻撃者と対象を
## 抜き、詠唱の行を覚えて、物理攻撃か魔法攻撃かを見分けます。剣の軌跡
## の形もここで作ります。

const _NUM := "([\\d,]+)"
# 名前は、文の区切りと、行頭の「DM > 」の区切りを含まない範囲にします
# (float_text.gd と同じ決め方です)。
const _NAME := "([^\\s。！!、,\\n>][^。！!、,\\n>]*?)"

const _FULLWIDTH := ["０", "１", "２", "３", "４", "５", "６", "７", "８", "９", "，"]
const _HALFWIDTH := ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9", ","]

static var _attack_rx: RegEx = null
static var _chant_rx: RegEx = null
static var _chant_stop_rx: RegEx = null
static var _kill_by_other_rx: RegEx = null
static var _kill_self_rx: RegEx = null
static var _dead_self_rx: RegEx = null


static func _compile(pattern: String) -> RegEx:
	var rx := RegEx.new()
	var err := rx.compile(pattern)
	if err != OK:
		printerr("combat pattern compile failed: ", pattern)
	return rx


static func _attack_pattern() -> RegEx:
	if _attack_rx == null:
		_attack_rx = _compile(_NAME + " は " + _NAME + " を (.+?)で攻撃した\\. \\[" + _NUM + " (?:hp|mp)\\]")
	return _attack_rx


static func _chant_pattern() -> RegEx:
	if _chant_rx == null:
		_chant_rx = _compile(_NAME + " は(?:魔法を唱えている|力を集中している)")
	return _chant_rx


static func _chant_stop_pattern() -> RegEx:
	if _chant_stop_rx == null:
		_chant_stop_rx = _compile("詠唱を止めました|詠唱は完了しなかった")
	return _chant_stop_rx


static func _kill_by_other_pattern() -> RegEx:
	if _kill_by_other_rx == null:
		_kill_by_other_rx = _compile("^DM > ([^>\\s][^>]*?) は .+? に殺された\\.")
	return _kill_by_other_rx


static func _kill_self_pattern() -> RegEx:
	if _kill_self_rx == null:
		_kill_self_rx = _compile("^DM > ([^>\\s][^>]*?) は .+で死んだ\\.")
	return _kill_self_rx


static func _dead_self_pattern() -> RegEx:
	if _dead_self_rx == null:
		_dead_self_rx = _compile("^DM > あなたは死にました")
	return _dead_self_rx


static func _normalize(text: String) -> String:
	var out := text
	for i in _FULLWIDTH.size():
		out = out.replace(_FULLWIDTH[i], _HALFWIDTH[i])
	return out


## 攻撃の行から、攻撃者・対象・武器(魔法名)を抜きます。
## 戻り値は {"attacker": 攻撃者, "target": 対象, "weapon": 武器} か null です。
static func parse_attack(text: String) -> Variant:
	var hit := _attack_pattern().search(_normalize(text))
	if hit == null:
		return null
	var attacker := hit.get_string(1).strip_edges()
	var target := hit.get_string(2).strip_edges()
	var weapon := hit.get_string(3).strip_edges()
	if attacker.is_empty() or target.is_empty():
		return null
	return {"attacker": attacker, "target": target, "weapon": weapon}


## 詠唱を始めた行から、唱えた人の名前を抜きます。
static func parse_chant(text: String) -> Variant:
	var hit := _chant_pattern().search(text)
	if hit == null:
		return null
	var chanter := hit.get_string(1).strip_edges()
	return chanter if not chanter.is_empty() else null


## 詠唱を止めた・失敗した行かどうかを返します。
static func parse_chant_stop(text: String) -> bool:
	return _chant_stop_pattern().search(text) != null


## 死亡の行から、倒れた人の名前を返します。
##
## 自分の死亡の行は、名前の代わりに ``あなた`` を返します。
static func parse_kill(text: String) -> Variant:
	var stripped := text.strip_edges()
	if _dead_self_pattern().search(stripped) != null:
		return "あなた"
	var hit := _kill_by_other_pattern().search(stripped)
	if hit != null:
		return hit.get_string(1).strip_edges()
	hit = _kill_self_pattern().search(stripped)
	if hit != null:
		return hit.get_string(1).strip_edges()
	return null


## 詠唱を始めた人を、しばらく覚えておきます。
##
## 攻撃の行が来た時、唱えたばかりの人なら魔法攻撃と分かります。
class CasterTracker extends RefCounted:
	var _window: float
	var _noted: Dictionary = {}

	func _init(window: float = 5.0) -> void:
		_window = window

	## 詠唱を始めたことを覚えます。古い記録は捨てます。
	func note(chara_name: String, now: float) -> void:
		var kept := {}
		for n in _noted:
			if now - float(_noted[n]) <= _window:
				kept[n] = _noted[n]
		_noted = kept
		_noted[chara_name] = now

	## その人の詠唱の記録を消します。
	func clear(chara_name: Variant) -> void:
		if chara_name != null:
			_noted.erase(chara_name)

	## 唱えたばかりなら true を返し、記録を使い切ります。
	func consume(chara_name: String, now: float) -> bool:
		if not _noted.has(chara_name):
			return false
		var noted := float(_noted[chara_name])
		_noted.erase(chara_name)
		return now - noted <= _window


## 剣の軌跡の多角形を、点の並びで返します。
##
## 右上から左下へ、少し弓なりに曲がり、先へいくほど細くなる形です。
## ``(cx, cy)`` は対象の中心、``z`` は拡大率です。
static func slash_points(cx: float, cy: float, z: float, scale: float = 1.0) -> PackedVector2Array:
	# 対角線の方向と、その垂直方向
	var dx := -32.0
	var dy := 36.0
	var length := Vector2(dx, dy).length()
	var nx := -dy / length
	var ny := dx / length
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	var steps := 6
	for i in range(steps + 1):
		var t := float(i) / steps
		# 中心線: 右上から左下へ
		var x := 16.0 - 32.0 * t
		var y := -18.0 + 36.0 * t
		# 弓なり
		var bow := sin(PI * t) * 4.0
		x += nx * bow
		y += ny * bow
		# 先へいくほど細く
		var half := (6.0 * (1.0 - t) + 1.5) / 2.0
		left.append(Vector2(cx + (x + nx * half) * z * scale, cy + (y + ny * half) * z * scale))
		right.append(Vector2(cx + (x - nx * half) * z * scale, cy + (y - ny * half) * z * scale))
	var points := PackedVector2Array(left)
	for i in range(right.size() - 1, -1, -1):
		points.append(right[i])
	return points


## 風切りの線を、点の並びで返します。
##
## ``radius`` の円弧に沿う、両端の細い線です。真ん中が一番太く、
## 両端へ向けて細くなります。角度の決め方は、0が右・正が下向きです。
static func streak_points(cx: float, cy: float, z: float, radius: float, start_rad: float, end_rad: float, thickness: float) -> PackedVector2Array:
	var span := absf(end_rad - start_rad)
	var steps := maxi(2, int(span / 0.12))
	var outer := PackedVector2Array()
	var inner := PackedVector2Array()
	for i in range(steps + 1):
		var u := float(i) / steps
		var angle := start_rad + (end_rad - start_rad) * u
		var half := thickness * z * 0.5 * sin(PI * u)
		var cos_a := cos(angle)
		var sin_a := sin(angle)
		outer.append(Vector2(cx + (radius * z + half) * cos_a, cy + (radius * z + half) * sin_a))
		inner.append(Vector2(cx + (radius * z - half) * cos_a, cy + (radius * z - half) * sin_a))
	var points := PackedVector2Array(outer)
	for i in range(inner.size() - 1, -1, -1):
		points.append(inner[i])
	return points


## 彗星の尾を、点の並びで返します。
##
## ``(hx, hy)`` が頭、``(tx, ty)`` が尾の先です。頭が太く、
## 尾の先へ向けて細くなる三角形です。
static func comet_tail_points(hx: float, hy: float, tx: float, ty: float, z: float, head_width: float) -> PackedVector2Array:
	var dx := tx - hx
	var dy := ty - hy
	var length := Vector2(dx, dy).length()
	if length < 0.000001:
		return PackedVector2Array([Vector2(hx, hy), Vector2(hx, hy), Vector2(hx, hy)])
	var nx := -dy / length
	var ny := dx / length
	var half := head_width * z * 0.5
	return PackedVector2Array([
		Vector2(hx + half * nx, hy + half * ny),
		Vector2(tx, ty),
		Vector2(hx - half * nx, hy - half * ny),
	])


## 放射状の火花を、点の並びで返します。
##
## 中心から ``angle_rad`` の向きへ伸びる、両端の細いひし形です。
## 角度の決め方は :func:`streak_points` と同じです。
static func radial_spark_points(cx: float, cy: float, z: float, angle_rad: float, length: float, half_width: float) -> PackedVector2Array:
	var dx := cos(angle_rad)
	var dy := sin(angle_rad)
	var nx := -dy
	var ny := dx
	var mid := 0.45
	var mx := cx + length * z * mid * dx
	var my := cy + length * z * mid * dy
	var tip_x := cx + length * z * dx
	var tip_y := cy + length * z * dy
	return PackedVector2Array([
		Vector2(cx, cy),
		Vector2(mx + half_width * z * nx, my + half_width * z * ny),
		Vector2(tip_x, tip_y),
		Vector2(mx - half_width * z * nx, my - half_width * z * ny),
	])
