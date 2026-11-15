class_name PhiBubbles
extends RefCounted
## 吹き出しの本文と折り返し、置く場所、輪郭。
##
## Python 版 neophi/bubbles.py の移植。発言の行から吹き出しに出す本文を
## 抜き、幅に収まる行に分け、他の吹き出しと重ならない場所を決め、角の
## 丸い輪郭を作ります。NPCの発言や action の行から、話し手と本文を抜く
## こともします。

static var _speech_rx: RegEx = null


static func _speech_pattern() -> RegEx:
	if _speech_rx == null:
		_speech_rx = RegEx.new()
		var err := _speech_rx.compile("^(?:\\(([^)]+)\\)|\\{([^}]+)\\}|\"([^\"]+)\"|([^>]+?)) > (.+)$")
		if err != OK:
			printerr("speech pattern compile failed")
	return _speech_rx


## 発言の行から本文だけを抜きます。
##
## talk の ``名前 > 本文`` と priv の ``[送り主] > 本文`` のどちらも、
## 最初の ``> `` の後ろが本文です。本文に ``> `` があっても、最初の
## 区切りだけを使います。
static func bubble_body(text: String) -> String:
	var idx := text.find("> ")
	if idx < 0:
		return ""
	return text.substr(idx + 2).strip_edges()


## logの行から、地図に見えるキャラの発言を抜きます。
##
## ``text`` はタグを除いた後の行、``names`` は見えるキャラの名前です。
## 話し手が ``names`` に無ければ、発言とは見なしません。
## 戻り値は [話し手, 本文] か null です。
static func bubble_from_log_line(text: String, names: Array) -> Variant:
	var hit := _speech_pattern().search(text.strip_edges())
	if hit == null:
		return null
	var speaker := ""
	for i in range(1, 5):
		if hit.get_start(i) >= 0:
			speaker = hit.get_string(i).strip_edges()
			break
	var body := hit.get_string(5).strip_edges()
	if speaker in names and not body.is_empty():
		return [speaker, body]
	return null


## action の行から、地図に見えるキャラの動作を抜きます。
##
## ``text`` はタグを除いた後の ``DM > 名前 本文`` の行です。名前は
## 長いものから当てはめます(「案内」と「案内人」の取り違えを防ぎます)。
## 戻り値は [話し手, 本文] か null です。
static func bubble_from_action_line(text: String, names: Array) -> Variant:
	var stripped := text.strip_edges()
	if not stripped.begins_with("DM > "):
		return null
	var rest := stripped.substr(5)
	var ordered := names.duplicate()
	ordered.sort_custom(func(a: String, b: String) -> bool: return a.length() > b.length())
	for n in ordered:
		var nm: String = n
		if rest.begins_with(nm + " "):
			var body := rest.substr(nm.length() + 1).strip_edges()
			if not body.is_empty():
				return [nm, body]
	return null


## 本文を幅に収まる行に分けます。
##
## ``measure`` は文字列を受けて幅を返す Callable です。1文字ずつ足して
## 幅を超えたら改行します。行数が ``max_lines`` を超えたら、最後の
## 行の末尾を ``…`` にして、はみ出した分がある事を示します。
static func wrap_bubble_lines(text: String, measure: Callable, max_width: float, max_lines: int = 3) -> Array[String]:
	if max_lines < 1 or text.strip_edges().is_empty():
		return []
	var lines: Array[String] = []
	for part in text.split("\n"):
		var current := ""
		for i in part.length():
			var ch := part.substr(i, 1)
			if not current.is_empty() and float(measure.call(current + ch)) > max_width:
				lines.append(current)
				current = ch
			else:
				current += ch
		if not current.is_empty() or part.is_empty():
			lines.append(current)
	if lines.size() > max_lines:
		lines = lines.slice(0, max_lines)
		var last: String = lines[lines.size() - 1]
		while not last.is_empty() and float(measure.call(last + "…")) > max_width:
			last = last.substr(0, last.length() - 1)
		lines[lines.size() - 1] = last + "…"
	return lines


## 吹き出しの箱の場所を決めます。
##
## ``cx`` は話し手の頭の中心、``tip_y`` はしっぽの先の位置です。
## 箱は頭の上に置き、左右は画面の中に収めます。他の吹き出しの箱
## (``occupied`` は ``[x0, y0, w, h]`` の並び)と重なれば、上へ
## ずらします。戻り値は ``[x0, y0, stacked]`` で、``stacked`` は
## 上にずらしたかどうかです。
static func place_bubble_rect(cx: float, tip_y: float, w: float, h: float, canvas_width: float, tail_h: float, occupied: Array) -> Array:
	var x0 := minf(maxf(cx - floorf(w / 2.0), 0.0), maxf(canvas_width - w, 0.0))
	var y0 := tip_y - tail_h - h
	if y0 < 0.0:
		y0 = 0.0
	var stacked := false
	for _i in range(5):
		var clash := false
		var clash_y := 0.0
		for o in occupied:
			var ox0 := float(o[0])
			var oy0 := float(o[1])
			var ow := float(o[2])
			var oh := float(o[3])
			if x0 < ox0 + ow and ox0 < x0 + w and y0 < oy0 + oh and oy0 < y0 + h:
				clash = true
				clash_y = oy0
				break
		if not clash or y0 <= 0.0:
			break
		y0 = maxf(0.0, clash_y - h - tail_h)
		stacked = true
	return [x0, y0, stacked]


## 角の丸い吹き出しの輪郭を、点の並びで返します。
##
## 箱の四隅を半径 ``radius`` の円弧にし、下の辺の途中にしっぽの
## 三角を付けます。点は時計回りで、左上の円弧から始まります。
## 箱が狭い時は、円弧が収まるよう半径を小さくします。
static func bubble_outline(x0: float, y0: float, x1: float, y1: float, radius: float, base_x: float, tail_w: float, tip_x: float, tip_y: float) -> PackedVector2Array:
	var w := x1 - x0
	var h := y1 - y0
	var r := maxf(1.0, minf(radius, minf(floorf(w / 2.0) - tail_w - 1.0, floorf(h / 2.0) - 1.0)))
	# しっぽの付け根は、下の辺の円弧の間に収めます
	var right := minf(maxf(base_x + tail_w, x0 + r), x1 - r)
	var left := minf(maxf(base_x - tail_w, x0 + r), x1 - r)
	if left > right:
		left = right
	tip_x = minf(maxf(tip_x, x0), x1)
	var points := PackedVector2Array()
	_append_arc(points, x0 + r, y0 + r, r, 180.0) # 左上
	_append_arc(points, x1 - r, y0 + r, r, 270.0) # 右上
	_append_arc(points, x1 - r, y1 - r, r, 0.0) # 右下
	points.append(Vector2(right, y1))
	points.append(Vector2(tip_x, tip_y))
	points.append(Vector2(left, y1))
	_append_arc(points, x0 + r, y1 - r, r, 90.0) # 左下
	return points


static func _append_arc(points: PackedVector2Array, cx: float, cy: float, r: float, start_deg: float) -> void:
	for step in range(5):
		var angle := deg_to_rad(start_deg + 90.0 * step / 4.0)
		points.append(Vector2(cx + r * cos(angle), cy + r * sin(angle)))
