class_name PhiParser
extends RefCounted
## 受信行を解析してイベントにする。仕様書 §3・§5・§8.3。
##
## Python 版 neophi/parser.py (wphi の parser.rs の移植)の GDScript 移植。
## イベントは Dictionary で、形は Python 版の `to_json` と同じにする。
## `tests/fixtures/parser.json` (wphi の golden データ)で出力を比べる。
##
## マップは `M`(地形)・`O`(キャラ)・`.`(確定)の複数行に分かれて届くので、
## 確定行が来るまでパーサがフレームを溜める。

const _MAP_CELLS := 49
const _M57_DIRECTION_OFFSET := 7
const _M57_CHIP_OFFSET := 18
const _MAP_CHIP_BYTES := _MAP_CELLS * 2
## Eagle Eye の最大辺。従来サーバは 25、phidm-v6 は 65x49 まで送る。
const _MAX_EAGLE_EYE := 65
const _MAX_LIST_LINES := 1000
const _MAX_MAP_CHARS := 1000
const _I64_MIN := -9223372036854775808
const _I64_MAX := 9223372036854775807

## マップの高さ (起伏) の印 (1段 = 8px)。'1'=+1段 '2'=+2段
## '3'=+3段 '9'=-1段 (窪地)。届き方は経路で異なる: 従来 #map
## (5x5) ではセル対の2バイト目、#m57/#m121 では `#ex-switch
## height=1` 申告時に M 行の直後へ来る専用の H 行の文字。
const HEIGHT_MARKERS := {0x31: 1, 0x32: 2, 0x33: 3, 0x39: -1}


static func height_for_marker(byte: int) -> int:
	## 高さの印 → 段数。印でなければ 0 ('0' も通常 = 0)。
	return int(HEIGHT_MARKERS.get(byte, 0))


static func _is_digit(ch: int) -> bool:
	return 0x30 <= ch and ch <= 0x39


static func _py_int(s: String) -> Variant:
	## Python の `int(s)` 相当。Rust の `i64` の parse に合わせる。
	var t := s.strip_edges()
	if t.is_empty():
		return null
	var i := 0
	var first := t.unicode_at(0)
	var negative := false
	if first == 0x2B or first == 0x2D: # + -
		negative = first == 0x2D
		i = 1
	if i >= t.length():
		return null
	for j in range(i, t.length()):
		if not _is_digit(t.unicode_at(j)):
			return null
	var digits := t.substr(i)
	# 先行ゼロを除く
	var k := 0
	while k < digits.length() and digits.unicode_at(k) == 0x30:
		k += 1
	var stripped := digits.substr(k)
	if stripped.is_empty():
		return 0
	if stripped.length() > 19:
		return null
	if stripped.length() == 19:
		# i64 の範囲を文字列で比べる(変換時の丸めを避ける)
		var limit := "9223372036854775808" if negative else "9223372036854775807"
		if stripped > limit:
			return null
	return int(t)


static func _ascii_uint(s: String) -> Variant:
	## ASCII の数字だけの時だけ数値にする。
	if s.is_empty():
		return null
	for i in s.length():
		if not _is_digit(s.unicode_at(i)):
			return null
	return _py_int(s)


static func _hex_u32(raw: PackedByteArray) -> Variant:
	## ASCII の16進文字列を数値にする。読めなければ null。
	for b in raw:
		if b >= 128:
			return null
	var t := raw.get_string_from_ascii().strip_edges()
	if t.is_empty():
		return null
	var i := 0
	if t.unicode_at(0) == 0x2B: # +
		i = 1
	if i >= t.length():
		return null
	var value := 0
	for j in range(i, t.length()):
		var c := t.unicode_at(j)
		var d := -1
		if 0x30 <= c and c <= 0x39:
			d = c - 0x30
		elif 0x61 <= c and c <= 0x66:
			d = c - 0x61 + 10
		elif 0x41 <= c and c <= 0x46:
			d = c - 0x41 + 10
		else:
			return null
		value = value * 16 + d
		if value > 0xFFFFFFFF:
			return null
	return value


static func _hex_digit(b: int) -> int:
	## 16進の1バイト → 数値。違えば -1。
	if 0x30 <= b and b <= 0x39:
		return b - 0x30
	if 0x61 <= b and b <= 0x66:
		return b - 0x61 + 10
	if 0x41 <= b and b <= 0x46:
		return b - 0x41 + 10
	return -1


static func _dir_to_num(b: int) -> int:
	## 自キャラの向きの文字を N=0 から時計回りの数値にする。知らない文字は 0。
	if b == 0x45: # E
		return 2
	if b == 0x53: # S
		return 4
	if b == 0x57: # W
		return 6
	return 0


static func _is_space_char(c: int) -> bool:
	return c == 0x20 or c == 0x09 or c == 0x0A or c == 0x0D or c == 0x0B or c == 0x0C


static func _split_ws(text: String) -> Array[String]:
	## 空白(の並び)で分ける。Python の `str.split()` 相当。
	var out: Array[String] = []
	var i := 0
	var n := text.length()
	while i < n:
		while i < n and _is_space_char(text.unicode_at(i)):
			i += 1
		if i >= n:
			break
		var start := i
		while i < n and not _is_space_char(text.unicode_at(i)):
			i += 1
		out.append(text.substr(start, i - start))
	return out


static func _split_quoted(text: String) -> Array[String]:
	## 空白区切り。ただし `"..."` の中は1トークンとして扱い、
	## 引用符は外す (#ex-pet / #ex-job の名前欄用)。
	var out: Array[String] = []
	var i := 0
	var n := text.length()
	while i < n:
		var c := text.unicode_at(i)
		if _is_space_char(c):
			i += 1
			continue
		if c == 0x22: # "
			var j := text.find("\"", i + 1)
			if j < 0:
				out.append(text.substr(i + 1))
				break
			out.append(text.substr(i + 1, j - i - 1))
			i = j + 1
		else:
			var j := i
			while j < n and not _is_space_char(text.unicode_at(j)):
				j += 1
			out.append(text.substr(i, j - i))
			i = j
	return out


static func _split_ws_max(text: String, max_splits: int) -> Array[String]:
	## 空白で最大 `max_splits` 回だけ分ける。最後の要素は残りそのまま。
	var out: Array[String] = []
	var i := 0
	var n := text.length()
	var splits := 0
	while i < n and splits < max_splits:
		while i < n and _is_space_char(text.unicode_at(i)):
			i += 1
		if i >= n:
			break
		var start := i
		while i < n and not _is_space_char(text.unicode_at(i)):
			i += 1
		out.append(text.substr(start, i - start))
		splits += 1
	while i < n and _is_space_char(text.unicode_at(i)):
		i += 1
	if i < n:
		out.append(text.substr(i))
	return out


static func _starts_with_bytes(raw: PackedByteArray, prefix: String) -> bool:
	var p := prefix.to_ascii_buffer()
	if raw.size() < p.size():
		return false
	for i in p.size():
		if raw[i] != p[i]:
			return false
	return true


static func _starts_with_at(raw: PackedByteArray, offset: int, prefix: String) -> bool:
	var p := prefix.to_ascii_buffer()
	if raw.size() < offset + p.size():
		return false
	for i in p.size():
		if raw[offset + i] != p[i]:
			return false
	return true


static func _message(channel: String, text: String, from_: Variant) -> Dictionary:
	var out := {"type": "message", "channel": channel, "text": text}
	if from_ != null:
		out["from"] = from_
	out["markup"] = text.contains("/*")
	return out


static func _parse_status(text: String) -> Dictionary:
	var body := text.substr(7).strip_edges(true, false)
	var parts := body.split(":")
	var nums: Array = []
	for i in range(10):
		nums.append(_py_int(parts[i + 1]) if i + 1 < parts.size() else null)
	var out := {"type": "status"}
	var name := parts[0].strip_edges() if not parts.is_empty() else ""
	if name != "":
		out["name"] = name
	var keys := ["hp", "maxHp", "mp", "maxMp", "exp", "gp", "f", "w", "m", "c"]
	for i in range(10):
		if nums[i] != null:
			out[keys[i]] = nums[i]
	return out


static func _parse_cond(text: String) -> Dictionary:
	var flags: Array[bool] = []
	for i in range(7):
		var idx := 6 + i
		flags.append(idx < text.length() and text.unicode_at(idx) == 0x2A)
	return {
		"type": "cond",
		"poison": flags[0],
		"palsy": flags[1],
		"panic": flags[2],
		"confuse": flags[3],
		"berserk": flags[4],
		"silence": flags[5],
		"blind": flags[6],
	}


# -- パーサ本体 -------------------------------------------------------------

var _mode := {"attack": false, "magic": false, "list": false, "more": false}
var _in_more := false
var _in_list := false
var _list_lines: Array[String] = []
var _map_size := 7
## 直前の地図フレームの大きさ。大きさが変わったらキャラ行は
## 座標系が違うので引き継がない (モード切替時の残像防止)。
var _last_frame_size := 0
var _map_dir := 0
var _map_cells: Variant = null # Array[Dictionary] か null
var _map_chars: Array[Dictionary] = []
## 次フレームの最初の O 行で map_chars を空にする
var _chara_clear_pending := false
var _name_magnify: Array = [] # [名前, magnify辞書]
## #user の名前 → 番号。届いた順を保つ
var _ulist: Array = [] # [名前, 番号]
var _eagle_grid: Array = []
var _eagle_size_x := 0
var _eagle_size_y := 0
var _eagle_pos := {"x": 0, "y": 0}
var _mapset: Variant = null
var _map_style: Variant = null
var _abs_pos: Variant = null # {"x":..,"y":..} か null

# -- phidm-v6 拡張 (段階0+1) -------------------------------------------------
## `#ex-map view=` が受理されたか (サーバが v6 フレームを送る状態)。
var _v6_active := false
var _v6_view := Vector2i.ZERO
## 構築中の v6 フレーム。R 行は (chip, attr) の生バイト列で保持する。
var _v6_frame := false
var _v6_w := 0
var _v6_h := 0
var _v6_dir := 0
var _v6_rows: Dictionary = {} # 行番号 -> PackedByteArray
var _v6_arows: Dictionary = {} # 行番号 -> 16進文字列 (マップセット枠)
var _v6_xrows: Dictionary = {} # 行番号 -> 通行可否の文字列
var _v6_chars: Array[Dictionary] = []
## マップセット16枠の定義 (枠番号 -> 名前)。接続中は保持される。
var _v6_defines: Dictionary = {}
## S/I/B/P/L/Q/K のブロック蓄積 (頭文字 -> エントリの配列)。
var _v6_blocks: Dictionary = {}
## `#v6 T` のタグ。次の発言メッセージに付けてから消す。
var _v6_tag: Variant = null
## `#ex-inv` の蓄積 (カバン I / 足元 F)。行は I/F 混在しない。
var _inv_bag: Array = []
var _inv_floor: Array = []
## `#v6 Y` の提示ブロック蓄積 (with の相手と両側の提示)。
var _trade_with: Dictionary = {}
var _trade_me: Dictionary = {}
var _trade_you: Dictionary = {}


func _init() -> void:
	_eagle_reset()


func in_more() -> bool:
	## `#more` 〜 `#end-more` の中か。
	return _in_more


func clear_users() -> void:
	## `#ulist` を送る時に呼ぶ。届き直す `#user` だけの一覧にする。
	_ulist.clear()


func user_no(name: String) -> Variant:
	## `#user` で届いた名前のユーザ番号。priv の宛先を決める為に使う。
	for pair in _ulist:
		if pair[0] == name:
			return pair[1]
	return null


func feed(raw: PackedByteArray) -> Array[Dictionary]:
	if raw.is_empty():
		return []
	# #more 〜 #end-more は #end-more 以外をログにする。看板に #ch-srv など
	# が書かれても、コマンドとして実行しない為である。
	if _in_more:
		if _starts_with_bytes(raw, "#end-more"):
			_in_more = false
			return _mode_change(-1, -1, -1, 0)
		return [_message("log", Cp932.decode(raw), null)]

	var is_command := raw[0] == 0x23 and raw.size() > 1 and raw[1] != 0x23 and raw[1] != 0x20
	if is_command:
		# 地形はバイナリなのでデコードしない
		if _starts_with_bytes(raw, "#m57 M"):
			_parse_m57_m(raw)
			return []
		if _starts_with_bytes(raw, "#m81 M"):
			_parse_m81_m(raw)
			return []
		if _starts_with_bytes(raw, "#m121 M"):
			_parse_m121_m(raw)
			return []
		if _starts_with_bytes(raw, "#m57 H"):
			_parse_mx_h(raw, 7, 7)
			return []
		if _starts_with_bytes(raw, "#m121 H"):
			_parse_mx_h(raw, 11, 8)
			return []
		if _starts_with_bytes(raw, "#map M"):
			_parse_map_m(raw)
			return []
		if _starts_with_bytes(raw, "#map C"):
			_parse_map_c(raw)
			return []
		if _starts_with_bytes(raw, "#v6 "):
			return _feed_v6(raw)
		return _dispatch_command(Cp932.decode(raw), raw)

	if _in_list:
		if _list_lines.size() < _MAX_LIST_LINES:
			_list_lines.append(Cp932.decode(raw))
		return []

	var text := Cp932.decode(raw)
	# "[送り主] > 本文" は priv
	if raw[0] == 0x5B: # [
		var end := text.find("]")
		if end > 0 and text.substr(end + 1).strip_edges(true, false).begins_with(">"):
			return [_tag_message(_message("priv", text, text.substr(1, end - 1)))]
	# 行頭の /**/ は何もしないタグです。実サーバは発言の行の頭に
	# /**/ を付けるので、分類の時だけ取り除きます。
	var classify := text.substr(4) if text.begins_with("/**/") else text
	# "名前 > 本文" で名前が #user にあればプレイヤーの発言
	var idx := classify.find(" > ")
	if idx > 0 and user_no(classify.substr(0, idx)) != null:
		return [_tag_message(_message("talk", text, classify.substr(0, idx)))]
	return [_tag_message(_message("log", text, null))]


func _tag_message(ev: Dictionary) -> Dictionary:
	## `#v6 T` のタグを次の発言メッセージへ付ける (1回だけ)。
	if _v6_tag != null and ev.get("type") == "message":
		ev["v6tag"] = _v6_tag
		_v6_tag = null
	return ev


func end_list() -> Array[Dictionary]:
	## リストを閉じる。選択・取消の送信時にも呼ぶ。
	_in_list = false
	_list_lines = []
	var events: Array[Dictionary] = [{"type": "list", "active": false}]
	events.append_array(_mode_change(-1, -1, 0, -1))
	return events


# -- 内部処理 ---------------------------------------------------------------
#
# _mode_change の引数は (attack, magic, list, more) で、-1 = 変えない、
# 0 = false、1 = true。Python 版のキーワード引数 (None = 変えない)の代わり。
func _mode_change(attack: int, magic: int, list_: int, more: int) -> Array[Dictionary]:
	## 引数が -1 の項目は変えない。それ以外は 0/1 を真偽値にする。
	var before := _mode.duplicate()
	if attack != -1:
		_mode["attack"] = attack == 1
	if magic != -1:
		_mode["magic"] = magic == 1
	if list_ != -1:
		_mode["list"] = list_ == 1
	if more != -1:
		_mode["more"] = more == 1
	if before == _mode:
		return []
	return [{
		"type": "mode",
		"attack": _mode["attack"],
		"magic": _mode["magic"],
		"list": _mode["list"],
		"more": _mode["more"],
	}]


func _dispatch_command(text: String, raw: PackedByteArray) -> Array[Dictionary]:
	if text.begins_with("#name "):
		return [{"type": "notice", "name": text.substr(6)}]
	if text.begins_with("#status ") or text == "#status":
		return [_parse_status(text)]
	if text.begins_with("#cond "):
		return [_parse_cond(text)]
	if text == "#close" or text == "#x":
		return [{"type": "connection", "state": "closed"}]
	if text == "#lag":
		return [{"type": "_internal", "action": "lag"}]
	if text == "#remap":
		return [{"type": "_internal", "action": "remap"}]
	if text == "#more":
		_in_more = true
		return _mode_change(-1, -1, -1, 1)
	if text == "#end-more":
		_in_more = false
		return _mode_change(-1, -1, -1, 0)
	if text == "#list":
		_in_list = true
		_list_lines = []
		var events := _mode_change(-1, -1, 1, -1)
		events.append({"type": "list", "active": true, "lines": []})
		return events
	if text == "#attack":
		return _mode_change(1, -1, -1, -1)
	if text == "#end-at":
		return _mode_change(0, -1, -1, -1)
	if text == "#magic":
		return _mode_change(-1, 1, -1, -1)
	if text == "#end-mg":
		return _mode_change(-1, 0, -1, -1)
	if text == "#ex-list-mode-end":
		return end_list()
	if text == "#m57 .":
		_map_size = 7
		return _finish_map()
	if text == "#m81 .":
		_map_size = 9
		return _finish_map()
	if text == "#m121 .":
		_map_size = 11
		return _finish_map()
	if text == "#map .":
		_map_size = 5
		return _finish_map()
	if text == "#ex-eagleeye end":
		return [_eagle_build(_mapset)]
	if text == "#m-edit":
		return [{"type": "edit", "mode": "multi"}]
	if text == "#s-edit":
		return [{"type": "edit", "mode": "single"}]
	if text == "#.":
		return [{"type": "edit", "mode": "end"}]
	if text == "#ex-map style=turn" or text == "#ex-map style=solid":
		_map_style = text.substr(14)
		return []
	if text.begins_with("#end-list"):
		_in_list = false
		var lines := _list_lines
		_list_lines = []
		return [{"type": "list", "active": true, "lines": lines}]
	if _starts_with_bytes(raw, "#m57 O "):
		_parse_m57_o(raw)
		return []
	if _starts_with_bytes(raw, "#m81 O "):
		# O 行の欄の並びは #m57 と同じ (接頭辞だけが違う)。
		_parse_m57_o(raw)
		return []
	if _starts_with_bytes(raw, "#m121 O "):
		_parse_m121_o(raw)
		return []
	if _starts_with_bytes(raw, "#m57 W "):
		for span in [[7, 74], [75, 142]]:
			if raw.size() >= span[1]:
				var rebuilt := PackedByteArray()
				rebuilt.append_array("#m57 O ".to_ascii_buffer())
				rebuilt.append_array(raw.slice(span[0], span[1]))
				_parse_m57_o(rebuilt)
		return []
	if _starts_with_bytes(raw, "#m81 W "):
		for span in [[7, 74], [75, 142]]:
			if raw.size() >= span[1]:
				var rebuilt := PackedByteArray()
				rebuilt.append_array("#m81 O ".to_ascii_buffer())
				rebuilt.append_array(raw.slice(span[0], span[1]))
				_parse_m57_o(rebuilt)
		return []
	if text.begins_with("#ex-eagleeye "):
		_eagle_feed_line(raw)
		return []
	if text.begins_with("#ex-obj S "):
		_parse_ex_obj(text)
		return []
	if text.begins_with("#user "):
		var event: Variant = _parse_user(raw)
		return [event] if event != null else []
	if text.begins_with("#ex-chr-conflict"):
		return [_message("system", "3重状態で消えています。移動してください", null)]
	if text.begins_with("#mapset "):
		var mapset := text.substr(8).strip_edges()
		_mapset = mapset
		return [{"type": "notice", "mapset": mapset}]
	if text.begins_with("#mapset-define "):
		var parts := _split_ws(text.substr(15))
		if parts.size() >= 2:
			var no: Variant = _py_int(parts[0])
			if no != null and 0 <= no and no <= 255:
				return [{"type": "notice", "mapsetDefine": [no % 4, parts[1]]}]
		return []
	if text.begins_with("#ex-notice land="):
		return [{"type": "notice", "world": text.substr(16)}]
	if text.begins_with("#ex-notice area="):
		return [{"type": "notice", "area": text.substr(16)}]
	if text.begins_with("#ex-pos "):
		var parts := _split_ws(text)
		if parts.size() >= 3:
			var x: Variant = _ascii_uint(parts[1])
			var y: Variant = _ascii_uint(parts[2])
			if x != null and y != null:
				_abs_pos = {"x": x, "y": y}
		return []
	if text.begins_with("#ex-disp-magic"):
		# サーバーからの魔法表示(第3段)。読めなければ無視する。
		var dm: Variant = PhiDispMagic.parse(text)
		if dm != null:
			return [{"type": "dispMagic", "data": dm}]
		return []
	if text.begins_with("#ex-pet "):
		# ペット表示 (PHIDM NEO v2.0)。読めなければ無視する。
		var pet_ev: Variant = _parse_ex_pet(text)
		return [pet_ev] if pet_ev != null else []
	if text.begins_with("#ex-job "):
		# 職業・性別表示 (PHIDM NEO v2.0)。読めなければ無視する。
		var job_ev: Variant = _parse_ex_job(text)
		return [job_ev] if job_ev != null else []
	if text.begins_with("#fx "):
		# DM 演出拡張 (FX)。未知の kind は無視する (前方互換)。
		# FX 行はログに出さない。
		var fx_ev: Variant = _parse_fx(text)
		if fx_ev == null:
			return []
		var fx_out: Array[Dictionary] = [fx_ev]
		return fx_out
	if text.begins_with("#ch-srv "):
		var parts := _split_ws(text)
		if parts.size() >= 3:
			var port: Variant = _py_int(parts[2])
			if port != null:
				return [{"type": "worldTransfer", "state": "start", "server": "%s:%d" % [parts[1], port]}]
		return []
	if text.begins_with("#ex-map view="):
		# phidm-v6 の視界申告への返事。受理なら v6 フレームが届く。
		return _parse_v6_view(text.substr(13))
	if text == "#ex-switch move=diag":
		return [{"type": "v6move", "diag": true}]
	if text == "#ex-switch move=no":
		return [{"type": "v6move", "diag": false}]
	if text == "#ex-switch compress=deflate":
		# 圧縮の開始はセッションがバイト境界で処理する。これは通知のみ。
		return [{"type": "v6compress", "accepted": true}]
	if text == "#ex-switch compress=no":
		return [{"type": "v6compress", "accepted": false}]
	if text.begins_with("#ex-inv"):
		return _parse_ex_inv(text)
	if text.begins_with("#ex-trade"):
		var tparts := _split_ws(text)
		if tparts.size() >= 3 and tparts[1] == "no":
			return [{"type": "v6tradeno", "reason": tparts[2]}]
		return []
	# #bgm と #ex-bgm-speed は wphi のパーサと同じく無視する
	# (golden の notice シナリオに `#bgm Seiju` → イベント無しがある)。
	# BGM の解釈はセッションが bgm_event_for_line() で行う(第5段)。
	# #ex-map size= などの既知の行も、未知の行も無視する
	return []


func _parse_fx(text: String) -> Variant:
	## `#fx <kind> <args...>` (DM 演出拡張) をイベントにする。
	## 読めない・未知の kind は null (無視される)。
	var rest := text.substr(4)
	var sp := rest.find(" ")
	var kind := rest if sp < 0 else rest.substr(0, sp)
	var args := "" if sp < 0 else rest.substr(sp + 1)
	match kind:
		"text":
			var p := _split_ws_max(args, 3)
			if p.size() < 4:
				return null
			var size_v: Variant = _py_int(p[1])
			var dur_v: Variant = _py_int(p[2])
			if size_v == null or dur_v == null:
				return null
			return {"type": "fx", "kind": "text", "pos": p[0],
				"size": int(size_v), "dur": int(dur_v), "text": p[3]}
		"textoff":
			return {"type": "fx", "kind": "textoff", "pos": args.strip_edges()}
		"dark":
			var p := _split_ws(args)
			if p.size() < 3:
				return null
			var lv: Variant = _py_int(p[0])
			var du: Variant = _py_int(p[1])
			var mo: Variant = _py_int(p[2])
			if lv == null or du == null or mo == null:
				return null
			return {"type": "fx", "kind": "dark", "level": int(lv),
				"dur": int(du), "mode": int(mo)}
		"wipe":
			var p := _split_ws(args)
			if p.size() < 2:
				return null
			return {"type": "fx", "kind": "wipe", "pattern": p[0], "dir": p[1]}
		"img":
			var p := _split_ws(args)
			if p.size() < 4:
				return null
			var du2: Variant = _py_int(p[3])
			if du2 == null:
				return null
			return {"type": "fx", "kind": "img", "where": p[0], "name": p[1],
				"hash": p[2], "dur": int(du2)}
		"imgdata":
			var p := _split_ws(args)
			if p.size() < 3:
				return null
			var tot: Variant = _py_int(p[1])
			if tot == null:
				return null
			return {"type": "fx", "kind": "imgdata", "name": p[0],
				"total": int(tot), "hash": p[2]}
		"imgchunk":
			var p := _split_ws(args)
			if p.size() < 3:
				return null
			var seq: Variant = _py_int(p[1])
			if seq == null:
				return null
			return {"type": "fx", "kind": "imgchunk", "name": p[0],
				"seq": int(seq), "data": p[2]}
		"imgend":
			return {"type": "fx", "kind": "imgend", "name": args.strip_edges()}
		"shake":
			var p := _split_ws(args)
			if p.size() < 2:
				return null
			var amp: Variant = _py_int(p[0])
			var du3: Variant = _py_int(p[1])
			if amp == null or du3 == null:
				return null
			return {"type": "fx", "kind": "shake", "amp": int(amp), "dur": int(du3)}
		"glow":
			var du4: Variant = _py_int(args.strip_edges())
			if du4 == null:
				return null
			return {"type": "fx", "kind": "glow", "dur": int(du4)}
		"clear":
			return {"type": "fx", "kind": "clear"}
	return null


static func _cn_mask(raw: PackedByteArray) -> Variant:
	## ちょうど6文字の16進文字列を数値にする。それ以外は null。
	if raw.size() != 6:
		return null
	for b in raw:
		if not ((0x30 <= b and b <= 0x39) or (0x41 <= b and b <= 0x46) or (0x61 <= b and b <= 0x66)):
			return null
	return _hex_u32(raw)


static func bgm_event_for_line(text: String) -> Dictionary:
	## BGM 通知の行をイベントにする(第5段)。対象外なら空辞書。
	##
	## `#bgm <ファイル名>`: Philly の SharpBgm と同じく、最初の空白の
	## 後ろ全体をファイル名とし、`.` が無ければ `.mid` を付ける。
	## `#ex-bgm-speed <数字>`: Philly の SharpExBgmSpeed と同じく、
	## 数字(%)だけを受ける(数字が無ければ無効)。
	if text.begins_with("#ex-bgm-speed"):
		var rest := text.substr(13).strip_edges(true, false)
		var digits := ""
		for i in range(rest.length()):
			var ch := rest[i]
			if ch >= "0" and ch <= "9":
				digits += ch
			else:
				break
		if digits.is_empty():
			return {}
		return {"type": "bgmSpeed", "speed": int(digits)}
	if text.begins_with("#bgm"):
		var rest := text.substr(4).strip_edges(true, false)
		if rest.is_empty():
			return {}
		var bgm_name := rest.strip_edges()
		if not bgm_name.contains("."):
			bgm_name += ".mid"
		return {"type": "bgm", "name": bgm_name}
	return {}


func _parse_user(raw: PackedByteArray) -> Variant:
	# raw[6..10] = 4桁の番号、raw[11..42] = 31バイトの名前
	if raw.size() < 42:
		return null
	var no_text_bytes := raw.slice(6, 10)
	for b in no_text_bytes:
		if b >= 128:
			return null
	var no: Variant = _py_int(no_text_bytes.get_string_from_ascii())
	if no == null:
		return null
	var name := Cp932.decode(raw.slice(11, 42)).strip_edges(false, true)
	if name.is_empty():
		return null
	var found := false
	for i in _ulist.size():
		if _ulist[i][0] == name:
			_ulist[i] = [name, no]
			found = true
			break
	if not found:
		_ulist.append([name, no])
	var users: Array[Dictionary] = []
	for pair in _ulist:
		users.append({"key": "u%d" % pair[1], "name": pair[0]})
	return {"type": "userList", "users": users}


## ペットのタイプ識別子 (#ex-pet の type 欄)。
const PET_TYPE_IDS := ["fairy", "cat", "dog", "bird"]


static func _pet_from_frame(type_id: String, pet_name: String, active: Variant) -> Variant:
	## #ex-pet の1ペット分の欄 → 辞書。`none` は空の辞書 (ペット
	## 無し)、知らないタイプは null (行全体を無視する)。
	if type_id == "none":
		return {}
	if not PET_TYPE_IDS.has(type_id):
		return null
	if active == null:
		return null
	return {"type": type_id, "name": pet_name, "active": int(active)}


func _parse_ex_pet(text: String) -> Variant:
	## `#ex-pet self <type> <名前> <mp> <st> <active> [<mp最大> <st最大>]`
	## `#ex-pet chr "<キャラ名>" <type> <名前> <active>`
	## (PHIDM NEO v2.0)。読めない形は null。ペット無しは pet={}。
	var parts := _split_quoted(text)
	if parts.size() < 3:
		return null
	if parts[1] == "self":
		if parts.size() < 7:
			return null
		var pet: Variant = _pet_from_frame(parts[2], parts[3], _ascii_uint(parts[6]))
		if pet == null:
			return null
		var mp: Variant = _ascii_uint(parts[4])
		var st: Variant = _ascii_uint(parts[5])
		if mp == null or st == null:
			return null
		if not (pet as Dictionary).is_empty():
			pet["mp"] = int(mp)
			pet["st"] = int(st)
			# 最大値は末尾の追加欄 (旧い欄だけでも読める)。
			if parts.size() >= 9:
				var mp_max: Variant = _ascii_uint(parts[7])
				var st_max: Variant = _ascii_uint(parts[8])
				if mp_max != null and st_max != null:
					pet["mpMax"] = int(mp_max)
					pet["stMax"] = int(st_max)
		return {"type": "petSelf", "pet": pet}
	if parts[1] == "chr":
		if parts.size() < 6:
			return null
		var pet2: Variant = _pet_from_frame(parts[3], parts[4], _ascii_uint(parts[5]))
		if pet2 == null:
			return null
		return {"type": "petChr", "chr": parts[2], "pet": pet2}
	return null


func _parse_ex_job(text: String) -> Variant:
	## `#ex-job self "<職業名>" "<性別名>"`
	## `#ex-job chr "<キャラ名>" "<職業名>" "<性別名>"`
	## (PHIDM NEO v2.0)。名前は現在の世界の phi.jb 由来で、
	## 未設定・phi.jb の無い世界では空文字列。読めない形は null。
	var parts := _split_quoted(text)
	if parts.size() < 3:
		return null
	if parts[1] == "self" and parts.size() >= 4:
		return {"type": "jobSelf", "job": parts[2], "sex": parts[3]}
	if parts[1] == "chr" and parts.size() >= 5:
		return {"type": "jobChr", "chr": parts[2], "job": parts[3], "sex": parts[4]}
	return null


func _parse_ex_obj(text: String) -> void:
	var parts := _split_ws_max(text, 5)
	if parts.size() != 6:
		return
	var w: Variant = _py_int(parts[2])
	var h: Variant = _py_int(parts[3])
	var z: Variant = _py_int(parts[4])
	if w == null or h == null or z == null:
		return
	var obj_name := parts[5].strip_edges()
	if obj_name.is_empty():
		return
	var magnify := {"w": w, "h": h, "z": z}
	for i in _name_magnify.size():
		if _name_magnify[i][0] == obj_name:
			_name_magnify[i] = [obj_name, magnify]
			return
	_name_magnify.append([obj_name, magnify])


func _parse_m57_m(raw: PackedByteArray) -> void:
	## `#m57 M`。raw[18..116] に (chip, attr) が49組並ぶ。
	_parse_mx_m(raw, 7, _MAP_CHIP_BYTES)


func _parse_m81_m(raw: PackedByteArray) -> void:
	## `#m81 M`。書式は #m57 M と同じで、(chip, attr) が81組並ぶ。
	_parse_mx_m(raw, 9, 162)


func _parse_m121_m(raw: PackedByteArray) -> void:
	## `#m121 M`。書式は #m81 M と同じで、(chip, attr) が121組並ぶ。
	## 接頭辞が 1 バイト長い分、方向は [8]、チップは [19] から。
	_parse_mx_m(raw, 11, 242, 19, 8)


func _note_frame_size(size: int) -> void:
	## 地図の大きさが変わったら、前フレームのキャラ行を捨てる。
	## 大きさが同じ間は、行が来ないフレームでも前フレームの
	## キャラを引き継ぐ (サーバは変化した行だけ送るため)。
	## このフレームのキャラ行が既に届いている場合は捨てない
	## (クラシック地図はキャラ行が地図行より先に来るため)。
	if _last_frame_size != 0 and size != _last_frame_size \
			and _chara_clear_pending:
		_map_chars = []
		_chara_clear_pending = false
	_last_frame_size = size


func _parse_mx_m(raw: PackedByteArray, size: int, chip_bytes: int, chip_offset: int = _M57_CHIP_OFFSET, dir_offset: int = _M57_DIRECTION_OFFSET) -> void:
	_note_frame_size(size)
	_map_size = size
	if raw.size() > dir_offset:
		_map_dir = _dir_to_num(raw[dir_offset])
	var end := chip_offset + chip_bytes
	if raw.size() < end:
		_map_cells = null
		return
	var cells: Array[Dictionary] = []
	for i in range(0, chip_bytes, 2):
		var cell := {"chip": raw[chip_offset + i], "attr": raw[chip_offset + i + 1]}
		cells.append(cell)
	_map_cells = cells


func _parse_mx_h(raw: PackedByteArray, size: int, offset: int) -> void:
	## `#m57 H` / `#m121 H` (高さ行)。ログイン時に
	## `#ex-switch height=1` を申告したときだけ、M 行の直後に
	## セル数ぶんの文字が届く ('0'=通常、'1'..'3'=丘、'9'=窪地、
	## 見えないセルは '0')。並びは M 行と同一順で、保留中の
	## セルへ段数を書き込む。M 行が無い・大きさが違う場合は捨てる。
	if _map_cells == null or _map_size != size:
		return
	var cells: Array = _map_cells
	var count := mini(size * size, cells.size())
	count = mini(count, raw.size() - offset)
	if count <= 0:
		return
	for i in range(count):
		var h := height_for_marker(raw[offset + i])
		if h != 0:
			(cells[i] as Dictionary)["height"] = h


func _parse_map_m(raw: PackedByteArray) -> void:
	## `#map M`(5x5)。本体が `-` なら前フレームのまま。
	_note_frame_size(5)
	_map_size = 5
	var body := raw.slice(7)
	var body_end := 0
	for i in body.size():
		if body[i] != 0x0D and body[i] != 0x0A:
			body_end = i + 1
	if body.slice(0, body_end) == "-".to_ascii_buffer():
		return
	if raw.size() > _M57_DIRECTION_OFFSET:
		_map_dir = _dir_to_num(raw[_M57_DIRECTION_OFFSET])
	var cells: Array[Dictionary] = []
	for i in range(25):
		var chip_idx := 18 + i * 2
		var chip := raw[chip_idx] if chip_idx < raw.size() else 0
		var attr := 0
		if chip_idx + 50 < raw.size() and raw[chip_idx + 50] == 0x2E: # .
			attr |= 0x60
		if chip_idx + 51 < raw.size() and raw[chip_idx + 51] == 0x2D: # -
			attr |= 0x08
		var cell := {"chip": chip, "attr": attr}
		# 対の2文字目が高さ印なら段数を保持する。表示チップは
		# 従来どおり1文字目 (chip) から解決される。
		if chip_idx + 1 < raw.size():
			var hh := height_for_marker(raw[chip_idx + 1])
			if hh != 0:
				cell["height"] = hh
		cells.append(cell)
	_map_cells = cells


func _parse_map_c(raw: PackedByteArray) -> void:
	## `#map C`(5x5 のキャラ・オブジェ行)。書式はサーバの
	## "#map C%02i:%01i %01i %c %-31s %02x %-15s %c %02x " で、
	## #m57 O と同じ欄が 4 バイト前にずれて並ぶ(Philly は "O C0" を
	## 挿入して同じ読み取りに流す)。
	## [6..7]番号(10進) [9]X [11]Y [13]向き [15..45]名前
	## [47..48]状態(16進) [50..64]グラ名 [66]Gigant [68..69]種別(16進)
	if raw.size() < 70:
		return
	var x_ch := raw[9]
	var y_ch := raw[11]
	if not (0x30 <= x_ch and x_ch <= 0x39 and 0x30 <= y_ch and y_ch <= 0x39):
		return
	var index := 0
	if 0x30 <= raw[6] and raw[6] <= 0x39 and 0x30 <= raw[7] and raw[7] <= 0x39:
		index = (raw[6] - 0x30) * 10 + (raw[7] - 0x30)
	var status: Variant = _hex_u32(raw.slice(47, 49))
	var default: Variant = _hex_u32(raw.slice(68, 70))
	if status == null or default == null:
		return
	var chara_name := Cp932.decode(raw.slice(15, 46)).strip_edges(false, true)
	var gra := Cp932.decode(raw.slice(50, 65)).strip_edges(false, true)
	if _chara_clear_pending:
		_map_chars = []
		_chara_clear_pending = false
	var magnify: Variant = null
	for pair in _name_magnify:
		if pair[0] == chara_name:
			magnify = pair[1]
			break
	if _map_chars.size() >= _MAX_MAP_CHARS:
		return
	var chara := {
		"id": index,
		"x": x_ch - 0x30,
		"y": y_ch - 0x30,
		"dir": PackedByteArray([raw[13]]).get_string_from_ascii(),
		"name": chara_name,
		"gra": gra,
		"status": status,
		"gigant": PackedByteArray([raw[66]]).get_string_from_ascii(),
		"layer": index,
		"default": default,
	}
	if magnify != null:
		chara["magnify"] = magnify
	_map_chars.append(chara)


func _parse_m57_o(raw: PackedByteArray) -> void:
	## `#m57 O` の固定位置の欄を読む。
	## [7]層 [8..12]ID(16進) [13]X [15]Y [17]向き [19..50]名前
	## [51..53]状態(16進) [54..69]グラ名 [70]Gigant [72..74]種別(16進)
	if raw.size() < 74:
		return
	var layer := _hex_digit(raw[7])
	if layer < 0:
		return
	var char_id: Variant = _hex_u32(raw.slice(8, 12))
	var x_ch := raw[13]
	var y_ch := raw[15]
	if not (0x30 <= x_ch and x_ch <= 0x39 and 0x30 <= y_ch and y_ch <= 0x39):
		return
	var status: Variant = _hex_u32(raw.slice(51, 53))
	var default: Variant = _hex_u32(raw.slice(72, 74))
	if char_id == null or status == null or default == null:
		return
	var chara_name := Cp932.decode(raw.slice(19, 50)).strip_edges(false, true)
	var gra := Cp932.decode(raw.slice(54, 69)).strip_edges(false, true)
	if _chara_clear_pending:
		_map_chars = []
		_chara_clear_pending = false
	var magnify: Variant = null
	for pair in _name_magnify:
		if pair[0] == chara_name:
			magnify = pair[1]
			break
	if _map_chars.size() >= _MAX_MAP_CHARS:
		return
	# 行末 (種別の後ろの空白の後) の cn マスク (DM 演出拡張)。
	# 無い行・読めない行では 0。
	var cn := 0
	if raw.size() >= 81 and raw[74] == 0x20:
		var mask_v: Variant = _cn_mask(raw.slice(75, 81))
		if mask_v != null:
			cn = int(mask_v)
	var chara := {
		"id": char_id,
		"x": x_ch - 0x30,
		"y": y_ch - 0x30,
		"dir": PackedByteArray([raw[17]]).get_string_from_ascii(),
		"name": chara_name,
		"gra": gra,
		"status": status,
		"gigant": PackedByteArray([raw[70]]).get_string_from_ascii(),
		"layer": layer,
		"default": default,
		"cn": cn,
	}
	if magnify != null:
		chara["magnify"] = magnify
	_map_chars.append(chara)


func _parse_m121_o(raw: PackedByteArray) -> void:
	## `#m121 O`。欄の並びは #m57 O と同じだが、接頭辞が 1 バイト
	## 長く、X/Y が 2 桁 (10) になることがある。X/Y は数字を読み
	## 飛ばして位置を求め、以降の欄は名前の開始位置からの相対で読む。
	## [8]層 [9..12]ID(16進) [13]':' [14..]X ' ' Y ' ' 向き ' ' 名前…
	if raw.size() < 70:
		return
	var layer := _hex_digit(raw[8])
	if layer < 0:
		return
	var char_id: Variant = _hex_u32(raw.slice(9, 13))
	if char_id == null or raw[13] != 0x3A: # ':'
		return
	var pos := 14
	var x := 0
	var digits := 0
	while pos < raw.size() and 0x30 <= raw[pos] and raw[pos] <= 0x39:
		x = x * 10 + raw[pos] - 0x30
		pos += 1
		digits += 1
	if digits == 0 or pos >= raw.size():
		return
	pos += 1 # X の後の空白
	var y := 0
	digits = 0
	while pos < raw.size() and 0x30 <= raw[pos] and raw[pos] <= 0x39:
		y = y * 10 + raw[pos] - 0x30
		pos += 1
		digits += 1
	if digits == 0 or pos + 1 >= raw.size():
		return
	pos += 1 # Y の後の空白
	var dir_ch := raw[pos]
	var base := pos + 2 # 名前の開始位置 (向き + 空白の次)
	if raw.size() < base + 55:
		return
	var status: Variant = _hex_u32(raw.slice(base + 32, base + 34))
	var default: Variant = _hex_u32(raw.slice(base + 53, base + 55))
	if status == null or default == null:
		return
	var chara_name := Cp932.decode(raw.slice(base, base + 31)).strip_edges(false, true)
	var gra := Cp932.decode(raw.slice(base + 35, base + 50)).strip_edges(false, true)
	if _chara_clear_pending:
		_map_chars = []
		_chara_clear_pending = false
	var magnify: Variant = null
	for pair in _name_magnify:
		if pair[0] == chara_name:
			magnify = pair[1]
			break
	if _map_chars.size() >= _MAX_MAP_CHARS:
		return
	# 行末 (種別の後ろの空白の後) の cn マスク (DM 演出拡張)。
	var cn := 0
	if raw.size() >= base + 62 and raw[base + 55] == 0x20:
		var mask_v: Variant = _cn_mask(raw.slice(base + 56, base + 62))
		if mask_v != null:
			cn = int(mask_v)
	var chara := {
		"id": char_id,
		"x": x,
		"y": y,
		"dir": PackedByteArray([dir_ch]).get_string_from_ascii(),
		"name": chara_name,
		"gra": gra,
		"status": status,
		"gigant": PackedByteArray([raw[base + 51]]).get_string_from_ascii(),
		"layer": layer,
		"default": default,
		"cn": cn,
	}
	if magnify != null:
		chara["magnify"] = magnify
	_map_chars.append(chara)


func _finish_map() -> Array[Dictionary]:
	var cells: Array = []
	if _map_cells != null:
		cells = (_map_cells as Array).duplicate()
	var event := {
		"type": "map",
		"size": _map_size,
		"dir": _map_dir,
		"cells": cells,
		"chars": _map_chars.duplicate(),
	}
	if _map_style != null:
		event["style"] = _map_style
	if _abs_pos != null:
		event["pos"] = _abs_pos
	_abs_pos = null
	# chars は次フレームの最初の O 行が来るまで残す
	_chara_clear_pending = true
	return [event]


## `#ex-eagleeye start` から `end` までの行を溜める。

func _eagle_reset() -> void:
	_eagle_grid = []
	for y in range(_MAX_EAGLE_EYE):
		var row: Array = []
		for x in range(_MAX_EAGLE_EYE):
			row.append({"chip": 0, "attr": 0})
		_eagle_grid.append(row)
	_eagle_size_x = 0
	_eagle_size_y = 0
	_eagle_pos = {"x": 0, "y": 0}


func _eagle_feed_line(raw: PackedByteArray) -> void:
	if raw.size() < 14:
		return
	if _starts_with_at(raw, 13, "start"):
		_eagle_reset()
	elif raw[13] == 0x4D: # M
		_eagle_parse_row(raw)
	elif _starts_with_at(raw, 13, "pos"):
		_eagle_parse_pos(raw)


func _eagle_parse_row(raw: PackedByteArray) -> void:
	var header_bytes := raw.slice(0, mini(raw.size(), 21))
	for b in header_bytes:
		if b >= 128:
			return
	var parts := _split_ws(header_bytes.get_string_from_ascii())
	if parts.size() < 4:
		return
	var size: Variant = _py_int(parts[2])
	var y: Variant = _py_int(parts[3])
	if size == null or y == null:
		return
	if not (0 <= y and y < _MAX_EAGLE_EYE):
		return
	_eagle_size_y = maxi(_eagle_size_y, y + 1)
	_eagle_size_x = mini(size + 1, _MAX_EAGLE_EYE)
	for x in range(maxi(_eagle_size_x, 0)):
		var i := 21 + x * 2
		if i + 1 >= raw.size():
			break
		_eagle_grid[y][x] = {"chip": raw[i], "attr": raw[i + 1]}


func _eagle_parse_pos(raw: PackedByteArray) -> void:
	for b in raw:
		if b >= 128:
			return
	var parts := _split_ws(raw.get_string_from_ascii())
	if parts.size() < 4:
		return
	var x: Variant = _py_int(parts[2])
	if x == null:
		return
	_eagle_pos["x"] = x
	var y: Variant = _py_int(parts[3])
	if y == null:
		return
	_eagle_pos["y"] = y


func _eagle_build(mapset: Variant) -> Dictionary:
	var w := maxi(_eagle_size_x, 0)
	var h := maxi(_eagle_size_y, 0)
	var cells: Array = []
	for y in range(h):
		for x in range(w):
			cells.append(_eagle_grid[y][x])
	var event := {
		"type": "eagleEye",
		"width": _eagle_size_x,
		"height": _eagle_size_y,
		"self": {"x": _eagle_pos["x"], "y": _eagle_pos["y"]},
		"cells": cells,
	}
	if mapset != null:
		event["mapset"] = mapset
	return event


# -- phidm-v6 拡張の解析 -------------------------------------------------------
#
# 仕様の正は phidm-v6 の rs/src/phi_v6.rs ほかの実装と test/replay の
# golden。フレームは `#v6 M` 〜 `#v6 .` の自己完結型で、キャラは
# 毎フレーム全員分が届く (従来の差分配信とは違う)。

func _parse_v6_view(rest: String) -> Array[Dictionary]:
	## `#ex-map view=` への返事。`no` は不受理 (従来モードのまま)。
	if rest.strip_edges() == "no":
		_v6_active = false
		_v6_view = Vector2i.ZERO
		return [{"type": "v6view", "accepted": false, "w": 0, "h": 0}]
	var parts := _split_ws(rest)
	if parts.size() >= 2:
		var w: Variant = _ascii_uint(parts[0])
		var h: Variant = _ascii_uint(parts[1])
		if w != null and h != null and int(w) > 0 and int(h) > 0:
			_v6_active = true
			_v6_view = Vector2i(int(w), int(h))
			return [{"type": "v6view", "accepted": true, "w": int(w), "h": int(h)}]
	return []


static func _v6_kv_fields(text: String) -> Dictionary:
	## TAB 区切りの `key=value` 列 → 辞書。値は最初の '=' の後ろ全部
	## (名前や題に空白・'=' が含まれ得る)。
	var out := {}
	for f in text.split("\t"):
		var eq := f.find("=")
		if eq > 0:
			out[f.substr(0, eq)] = f.substr(eq + 1)
	return out


func _feed_v6(raw: PackedByteArray) -> Array[Dictionary]:
	## `#v6 ` で始まる行の振り分け。R 行 (地形の生バイト対) と
	## O 行 (固定欄) はバイトのまま読み、それ以外は CP932 で読む。
	## 最短の行はフレーム確定の `#v6 .` (5バイト)。
	if raw.size() < 5:
		return []
	var sub := raw[4]
	if sub == 0x52: # R
		_v6_parse_r(raw)
		return []
	if sub == 0x4F: # O
		_v6_parse_o(raw)
		return []
	var text := Cp932.decode(raw)
	var rest := text.substr(6) if text.length() > 6 else ""
	match sub:
		0x4D: # M
			_v6_parse_m(text)
		0x2E: # . (フレーム確定)
			return _finish_v6_map()
		0x41, 0x58: # A / X
			_v6_parse_ax(sub, text)
		0x44: # D
			return _v6_parse_d(text)
		0x47: # G
			return _v6_parse_g(text)
		0x4A: # J
			return [{"type": "v6jump"}]
		0x48: # H
			return _v6_parse_h(text)
		0x45: # E
			return _v6_parse_e(text)
		0x57: # W
			return _v6_parse_w(rest)
		0x54: # T
			_v6_parse_t(text)
		0x53, 0x49, 0x42, 0x50, 0x4C, 0x51, 0x4B: # S I B P L Q K
			return _v6_parse_block(sub, rest)
		0x59: # Y (取引)
			return _v6_parse_y(rest)
	return []


func _v6_parse_m(text: String) -> void:
	## `#v6 M 向き 時刻(16進) W H`。フレームの蓄積を始める。
	var parts := _split_ws(text)
	_v6_rows.clear()
	_v6_arows.clear()
	_v6_xrows.clear()
	_v6_chars = []
	_v6_frame = false
	_v6_w = 0
	_v6_h = 0
	if parts.size() < 6:
		return
	_v6_dir = _dir_to_num(parts[2].unicode_at(0) if not parts[2].is_empty() else 0)
	var w: Variant = _ascii_uint(parts[4])
	var h: Variant = _ascii_uint(parts[5])
	if w == null or h == null:
		return
	if not (1 <= int(w) and int(w) <= 128 and 1 <= int(h) and int(h) <= 128):
		return
	_v6_w = int(w)
	_v6_h = int(h)
	_v6_frame = true


func _v6_parse_r(raw: PackedByteArray) -> void:
	## `#v6 R NN ` + (chip, attr) x W の生バイト対 + 空白。
	## セルの符号化は #m57 と同一。
	if not _v6_frame or raw.size() < 9:
		return
	if not (_is_digit(raw[6]) and _is_digit(raw[7])):
		return
	var row := (raw[6] - 0x30) * 10 + (raw[7] - 0x30)
	if row >= _v6_h:
		return
	var need := 9 + _v6_w * 2
	if raw.size() < need:
		return
	_v6_rows[row] = raw.slice(9, need)


func _v6_parse_ax(sub: int, text: String) -> void:
	## `#v6 A NN ` + W 文字 (マップセット枠の16進)、
	## `#v6 X NN ` + W 文字 (通行可否 '.' / 'x')。
	if not _v6_frame or text.length() < 9:
		return
	var row_v: Variant = _ascii_uint(text.substr(6, 2))
	if row_v == null or int(row_v) >= _v6_h:
		return
	var body := text.substr(9, _v6_w)
	if sub == 0x41:
		_v6_arows[int(row_v)] = body
	else:
		_v6_xrows[int(row_v)] = body


func _v6_parse_o(raw: PackedByteArray) -> void:
	## `#v6 O` の固定位置の欄を読む。欄の並びは #m57 O とほぼ同じで、
	## X/Y が2桁固定・区切りに ':' が入る。
	## [6]種別文字 [7..10]ID(16進) [11]':' [12..13]X [15..16]Y
	## [18]向き [20..50]名前 [52..53]状態(16進) [55..69]グラ名
	## [71]印 [73..74]種別(16進)
	if not _v6_frame or raw.size() < 76:
		return
	var layer := _hex_digit(raw[6])
	if layer < 0:
		return
	var char_id: Variant = _hex_u32(raw.slice(7, 11))
	if char_id == null or raw[11] != 0x3A: # ':'
		return
	if not (_is_digit(raw[12]) and _is_digit(raw[13])
			and _is_digit(raw[15]) and _is_digit(raw[16])):
		return
	var status: Variant = _hex_u32(raw.slice(52, 54))
	var default: Variant = _hex_u32(raw.slice(73, 75))
	if status == null or default == null:
		return
	var chara_name := Cp932.decode(raw.slice(20, 51)).strip_edges(false, true)
	var gra := Cp932.decode(raw.slice(55, 70)).strip_edges(false, true)
	var magnify: Variant = null
	for pair in _name_magnify:
		if pair[0] == chara_name:
			magnify = pair[1]
			break
	if _v6_chars.size() >= _MAX_MAP_CHARS:
		return
	var chara := {
		"id": char_id,
		"x": (raw[12] - 0x30) * 10 + (raw[13] - 0x30),
		"y": (raw[15] - 0x30) * 10 + (raw[16] - 0x30),
		"dir": PackedByteArray([raw[18]]).get_string_from_ascii(),
		"name": chara_name,
		"gra": gra,
		"status": status,
		"gigant": PackedByteArray([raw[71]]).get_string_from_ascii(),
		"layer": layer,
		"default": default,
		"cn": 0,
		"kind": PackedByteArray([raw[6]]).get_string_from_ascii(),
	}
	if magnify != null:
		chara["magnify"] = magnify
	_v6_chars.append(chara)


func _finish_v6_map() -> Array[Dictionary]:
	## `#v6 .`。溜めたフレームを地図イベントにする。
	if not _v6_frame or _v6_w <= 0 or _v6_h <= 0:
		_v6_frame = false
		return []
	var cells: Array = []
	for y in range(_v6_h):
		var pairs: PackedByteArray = _v6_rows.get(y, PackedByteArray())
		var arow: String = _v6_arows.get(y, "")
		for x in range(_v6_w):
			var cell := {"chip": 0x3F, "attr": 0}
			if pairs.size() >= (x + 1) * 2:
				cell["chip"] = pairs[x * 2]
				cell["attr"] = pairs[x * 2 + 1]
			if x < arow.length():
				var slot := _hex_digit(arow.unicode_at(x))
				if slot > 0:
					cell["slot"] = slot
			cells.append(cell)
	# 自キャラのマス。solid は中央、turn は後ろ 1/3 を除いた中央
	# (サーバの view_rows と同じ割り付け)。
	var sx := (_v6_w - 1) / 2
	var sy := (_v6_h - 1) / 2
	if _map_style != "solid":
		sy = _v6_h - 1 - _v6_h / 3
	var event := {
		"type": "map",
		"v6": true,
		"w": _v6_w,
		"h": _v6_h,
		"dir": _v6_dir,
		"cells": cells,
		"chars": _v6_chars.duplicate(),
		"selfCell": {"x": sx, "y": sy},
	}
	if not _v6_xrows.is_empty():
		event["xrows"] = _v6_xrows.duplicate()
	if _map_style != null:
		event["style"] = _map_style
	if _abs_pos != null:
		event["pos"] = _abs_pos
	_abs_pos = null
	_v6_frame = false
	return [event]


func _v6_parse_d(text: String) -> Array[Dictionary]:
	## `#v6 D 枠番号 名前`。マップセット16枠の定義 (枠 1〜15)。
	var parts := _split_ws(text)
	if parts.size() < 4:
		return []
	var slot: Variant = _ascii_uint(parts[2])
	if slot == null or not (1 <= int(slot) and int(slot) <= 15):
		return []
	var define_name := " ".join(parts.slice(3))
	_v6_defines[int(slot)] = define_name
	return [{"type": "v6define", "slot": int(slot), "name": define_name}]


func _v6_parse_g(text: String) -> Array[Dictionary]:
	## `#v6 G dx dy [理由]`。自分の go への返事 (フレームの直前に来る)。
	var parts := _split_ws(text)
	if parts.size() < 4:
		return []
	var dx: Variant = _py_int(parts[2])
	var dy: Variant = _py_int(parts[3])
	if dx == null or dy == null:
		return []
	return [{"type": "v6go", "dx": int(dx), "dy": int(dy),
		"word": parts[4] if parts.size() >= 5 else ""}]


func _v6_parse_h(text: String) -> Array[Dictionary]:
	## `#v6 H C番号 hp=割合 ag=0/1`。地図の直後に、変わった者だけ。
	var parts := _split_ws(text)
	if parts.size() < 3 or parts[2].length() < 2 or parts[2][0] != "C":
		return []
	var char_id: Variant = _hex_u32(parts[2].substr(1).to_ascii_buffer())
	if char_id == null:
		return []
	var fields := _v6_kv_fields("\t".join(parts.slice(3))) if parts.size() > 3 else {}
	var hp: Variant = _py_int(str(fields.get("hp", "")))
	var ag: Variant = _py_int(str(fields.get("ag", "")))
	return [{"type": "v6health", "id": int(char_id),
		"hp": int(hp) if hp != null else -1,
		"ag": int(ag) if ag != null else 0}]


func _v6_parse_e(text: String) -> Array[Dictionary]:
	## `#v6 E 種類 AX AY TX TY 属性 分類 [待ち]`。戦闘ログの直前に来る。
	## 座標は視界の列・行 (0始まり)。攻撃側が視界外なら `-- --`。
	var parts := _split_ws(text)
	if parts.size() < 9:
		return []
	var ax := -1
	var ay := -1
	if parts[3] != "--":
		var axv: Variant = _py_int(parts[3])
		var ayv: Variant = _py_int(parts[4])
		if axv != null and ayv != null:
			ax = int(axv)
			ay = int(ayv)
	var txv: Variant = _py_int(parts[5])
	var tyv: Variant = _py_int(parts[6])
	if txv == null or tyv == null:
		return []
	var wait_v: Variant = _py_int(parts[9]) if parts.size() >= 10 else null
	return [{"type": "v6effect", "kind": parts[2], "ax": ax, "ay": ay,
		"tx": int(txv), "ty": int(tyv), "attr": parts[7], "class": parts[8],
		"wait": int(wait_v) if wait_v != null else -1}]


func _v6_parse_w(rest: String) -> Array[Dictionary]:
	## `#v6 W cast=残り [呪文名]` / `cast=stop` / `at=残り` /
	## `#v6 W C番号 cast=…`。詠唱・攻撃の待ち (0.1秒単位)。
	var who: Variant = "self"
	var body := rest
	if body.begins_with("C"):
		var sp := body.find(" ")
		if sp < 0:
			return []
		var id_v: Variant = _hex_u32(body.substr(1, sp - 1).to_ascii_buffer())
		if id_v == null:
			return []
		who = int(id_v)
		body = body.substr(sp + 1)
	if body.begins_with("cast="):
		var tail := body.substr(5)
		var sp2 := tail.find(" ")
		var num := tail if sp2 < 0 else tail.substr(0, sp2)
		var spell := "" if sp2 < 0 else tail.substr(sp2 + 1)
		if num == "stop":
			return [{"type": "v6wait", "who": who, "cast": -1, "spell": spell}]
		var ticks: Variant = _py_int(num)
		if ticks == null:
			return []
		return [{"type": "v6wait", "who": who, "cast": int(ticks), "spell": spell}]
	if body.begins_with("at="):
		var ticks2: Variant = _py_int(body.substr(3).strip_edges())
		if ticks2 == null:
			return []
		return [{"type": "v6wait", "who": who, "at": int(ticks2)}]
	return []


func _v6_parse_t(text: String) -> void:
	## `#v6 T 種類 [C番号]`。直後の発言行の出所タグ。
	var parts := _split_ws(text)
	if parts.size() < 3:
		return
	var tag := {"kind": parts[2]}
	if parts.size() >= 4 and parts[3].length() >= 2 and parts[3][0] == "C":
		var id_v: Variant = _hex_u32(parts[3].substr(1).to_ascii_buffer())
		if id_v != null:
			tag["id"] = int(id_v)
	_v6_tag = tag


func _v6_parse_block(sub: int, rest: String) -> Array[Dictionary]:
	## S/I/B/P/L/Q/K のブロック行。`.` で閉じたら1イベントにする。
	var letter := char(sub)
	if rest.strip_edges() == ".":
		var entries: Array = _v6_blocks.get(letter, [])
		_v6_blocks.erase(letter)
		match letter:
			"S":
				return [{"type": "v6spells", "spells": entries}]
			"I":
				return [{"type": "v6items", "items": entries}]
			"B":
				return [{"type": "v6shop", "items": entries}]
			"P":
				return [{"type": "v6party", "members": entries}]
			"L":
				return [{"type": "v6marks", "marks": entries}]
			"Q":
				return [{"type": "v6quests", "quests": entries}]
			"K":
				return [{"type": "v6talkwords", "words": entries}]
		return []
	var entry := _v6_block_entry(letter, rest)
	if entry.is_empty():
		return []
	var list: Array = _v6_blocks.get(letter, [])
	list.append(entry)
	_v6_blocks[letter] = list
	return []


func _v6_block_entry(letter: String, rest: String) -> Dictionary:
	## ブロックの1行 → エントリ。L は名前始まり、K は言葉始まり、
	## それ以外は番号始まりで、残りは TAB 区切りの key=value。
	var tabs := rest.split("\t")
	if tabs.is_empty():
		return {}
	if letter == "L":
		var entry := {"name": tabs[0]}
		entry.merge(_v6_kv_fields("\t".join(tabs.slice(1))))
		return entry
	if letter == "K":
		var entry2 := {"word": tabs[0]}
		if tabs.size() >= 2:
			entry2["menu"] = tabs[1]
		return entry2
	var no: Variant = _py_int(tabs[0].strip_edges())
	if no == null:
		return {}
	var entry3 := {"no": int(no)}
	entry3.merge(_v6_kv_fields("\t".join(tabs.slice(1))))
	return entry3


func _parse_ex_inv(text: String) -> Array[Dictionary]:
	## `#ex-inv` の行群 (カバン)。I = カバンの中身 (`#ex-inv .` で確定)、
	## F = 足元の品 (`#ex-inv F .` で確定)、no = 失敗の理由。
	var rest := text.substr(7).strip_edges(true, false) # "#ex-inv" の後ろ
	if rest.begins_with("no "):
		return [{"type": "v6invno", "reason": rest.substr(3).strip_edges()}]
	if rest == ".":
		var items := _inv_bag
		_inv_bag = []
		return [{"type": "v6bag", "items": items}]
	if rest == "F .":
		var fitems := _inv_floor
		_inv_floor = []
		return [{"type": "v6flooritems", "items": fitems}]
	if rest.begins_with("I ") or rest.begins_with("F "):
		var entry := _v6_block_entry("I", rest.substr(2))
		if entry.is_empty():
			return []
		if rest.begins_with("I "):
			_inv_bag.append(entry)
		else:
			_inv_floor.append(entry)
	return []


func _v6_parse_y(rest: String) -> Array[Dictionary]:
	## `#v6 Y` の取引行群。ask = 申し込み、with 〜 `.` = 提示の一覧、
	## done = 成立、end 理由 = 終了 (cancel / moved / gone / short / full)。
	if rest.begins_with("ask "):
		var who := _trade_parse_who(rest.substr(4))
		if who.is_empty():
			return []
		return [{"type": "v6trade", "phase": "ask",
			"id": who["id"], "name": who["name"]}]
	if rest.begins_with("with "):
		_trade_with = _trade_parse_who(rest.substr(5))
		_trade_me = {"gp": 0, "ok": false, "items": []}
		_trade_you = {"gp": 0, "ok": false, "items": []}
		return []
	if rest == "done":
		return [{"type": "v6trade", "phase": "done"}]
	if rest.begins_with("end "):
		return [{"type": "v6trade", "phase": "end",
			"reason": rest.substr(4).strip_edges()}]
	if rest == ".":
		if _trade_with.is_empty():
			return []
		return [{"type": "v6trade", "phase": "offers",
			"with": _trade_with.duplicate(),
			"me": _trade_side_dup(_trade_me),
			"you": _trade_side_dup(_trade_you)}]
	if rest.begins_with("me") or rest.begins_with("you"):
		_trade_parse_side(rest)
	return []


static func _trade_side_dup(side: Dictionary) -> Dictionary:
	var items: Array = []
	for it in side.get("items", []):
		items.append((it as Dictionary).duplicate())
	return {"gp": int(side.get("gp", 0)), "ok": bool(side.get("ok", false)),
		"items": items}


func _trade_parse_who(body: String) -> Dictionary:
	## `C%04x 名前` → {"id": 番号, "name": 名前}。読めなければ {}。
	var sp := body.find(" ")
	if sp < 2 or body[0] != "C":
		return {}
	var id_v: Variant = _hex_u32(body.substr(1, sp - 1).to_ascii_buffer())
	if id_v == null:
		return {}
	return {"id": int(id_v), "name": body.substr(sp + 1)}


func _trade_parse_side(rest: String) -> void:
	## 提示行。頭 (`me` / `me 3` / `you` / `you 2`) + TAB 区切りの欄。
	## 頭だけの行は gp と ok、番号付きは提示した品1個。
	var tabs := rest.split("\t")
	if tabs.is_empty():
		return
	var head := tabs[0].strip_edges()
	var side: Dictionary = _trade_me if head.begins_with("me") else _trade_you
	var sp := head.find(" ")
	if sp < 0:
		var kv := _v6_kv_fields("\t".join(tabs.slice(1)))
		var gp: Variant = _py_int(str(kv.get("gp", "")))
		if gp != null:
			side["gp"] = int(gp)
		side["ok"] = str(kv.get("ok", "0")) == "1"
	else:
		var no: Variant = _py_int(head.substr(sp + 1))
		if no == null:
			return
		var entry := {"no": int(no)}
		entry.merge(_v6_kv_fields("\t".join(tabs.slice(1))))
		var items: Array = side.get("items", [])
		items.append(entry)
		side["items"] = items
	if head.begins_with("me"):
		_trade_me = side
	else:
		_trade_you = side
