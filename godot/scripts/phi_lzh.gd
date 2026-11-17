class_name PhiLzh
extends RefCounted
## LZH アーカイブの解析と展開(純 GDScript)。
##
## 対応範囲(実アーカイブ chip_ryur.lzh の調査に基づく最小限):
## ・ヘッダレベル 0 / 1 / 2(実物はレベル 2)
## ・メソッド -lh0-(無圧縮)/ -lh5-
## それ以外のメソッド(-lh1- / -lh4- / -lh6- / -lh7- 等)はエラーにする。
##
## -lh5- の復号は LHa の手順どおり:
## ・ブロック = 16 ビットのシンボル数 + PT 表 + C 表 + P 表 + データ。
## ・C 表の 0 ラン: シンボル 0 = 1 個、1 = 3 + getbits(4) 個、
##   2 = 20 + getbits(9) 個。ラン 1 の基数が 3 であることは、
##   実アーカイブを lhafile(Python、検証用)で展開した正解データと
##   バイト一致させる過程で確定した(4 ではエントリ数が合わない)。
## ・展開後に元サイズと CRC16 を照合する。
##
## ファイル名は cp932。区切りは "\" と 0xFF を "/" に直す
## (cp932 の第 2 バイトと衝突しないよう、先行バイトを読み飛ばしながら変換)。

const DICBIT := 13
const DICSIZE := 1 << DICBIT
const MAXMATCH := 256
const THRESHOLD := 3
const NC := 255 + MAXMATCH + 2 - THRESHOLD # 510
const CBIT := 9
const NP := DICBIT + 1 # 14
const NT := 16 + 3 # コード長の最大値 + ラン記号 3 つ = 19
const PBIT := 4
const TBIT := 5

const METHOD_STORE := "-lh0-"
const METHOD_LH5 := "-lh5-"


# -- ビット読み ---------------------------------------------------------------

class _BitReader:
	extends RefCounted

	var _data: PackedByteArray
	var _pos := 0
	var _buf := 0
	var _nbits := 0
	## データを使い切ったら true(以降は 0 で埋めて返す)。
	var failed := false

	func _init(data: PackedByteArray) -> void:
		_data = data

	func getbits(n: int) -> int:
		while _nbits < n:
			_buf <<= 8
			_nbits += 8
			if _pos < _data.size():
				_buf |= _data[_pos]
				_pos += 1
			else:
				failed = true
		_nbits -= n
		var v := (_buf >> _nbits) & ((1 << n) - 1)
		_buf &= (1 << _nbits) - 1
		return v

	func getbit() -> int:
		return getbits(1)


# -- ハフマン(puff 方式の正準コード復号) ---------------------------------------

class _Huff:
	extends RefCounted

	var _counts: Array[int] = [] # コード長ごとの記号数(添字 0..16)
	var _symbols: Array[int] = [] # (コード長, 記号) の順に並べた記号表
	var _single := -1 # 全記号がこれ 1 つだけの表(長さ 0 のみのとき)

	func _init(lengths: Array[int], single: int = -1) -> void:
		_single = single
		_counts.resize(17)
		for l in lengths:
			if l > 0 and l <= 16:
				_counts[l] += 1
		for want in range(1, 17):
			for s in lengths.size():
				if lengths[s] == want:
					_symbols.append(s)

	## 過剰な表( Kraft 和 > 1)なら false。
	func is_sane() -> bool:
		if _single >= 0:
			return true
		var sum := 0
		for l in range(1, 17):
			sum += _counts[l] << (16 - l)
		return sum <= (1 << 16)

	func decode(br: _BitReader) -> int:
		if _single >= 0:
			return _single
		var code := 0
		var first := 0
		var index := 0
		for len in range(1, 17):
			code |= br.getbit()
			var count := _counts[len]
			if code - first < count:
				return _symbols[index + (code - first)]
			index += count
			first = (first + count) << 1
			code <<= 1
		return -1


# -- -lh5- 復号 -----------------------------------------------------------------

class _Lh5:
	extends RefCounted

	var _br: _BitReader = null
	var error := ""

	func decode(data: PackedByteArray, osize: int) -> PackedByteArray:
		_br = _BitReader.new(data)
		var text := PackedByteArray()
		text.resize(DICSIZE)
		var out := PackedByteArray()
		out.resize(osize)
		var out_pos := 0
		var r := 0
		var blocksize := 0
		var ch: _Huff = null
		var ph: _Huff = null
		while out_pos < osize:
			if blocksize == 0:
				blocksize = _br.getbits(16)
				if blocksize == 0 or _br.failed:
					error = "ブロックサイズが不正です"
					return PackedByteArray()
				var pt := _read_pt_len(NT, TBIT, 3)
				if pt == null:
					return PackedByteArray()
				ch = _read_c_len(pt)
				if ch == null:
					return PackedByteArray()
				ph = _read_pt_len(NP, PBIT, -1)
				if ph == null:
					return PackedByteArray()
			blocksize -= 1
			var c := ch.decode(_br)
			if c < 0 or _br.failed:
				error = "ハフマン復号に失敗しました"
				return PackedByteArray()
			if c < 256:
				out[out_pos] = c
				out_pos += 1
				text[r] = c
				r = (r + 1) & (DICSIZE - 1)
			else:
				var length := c - 256 + THRESHOLD
				var p := ph.decode(_br)
				if p < 0 or _br.failed:
					error = "位置の復号に失敗しました"
					return PackedByteArray()
				if p > 0:
					p = (1 << (p - 1)) + _br.getbits(p - 1)
				var ii := (r - p - 1) & (DICSIZE - 1)
				for _k in length:
					var b := text[ii]
					if out_pos < osize:
						out[out_pos] = b
						out_pos += 1
					text[r] = b
					r = (r + 1) & (DICSIZE - 1)
					ii = (ii + 1) & (DICSIZE - 1)
		return out

	func _read_pt_len(nn: int, nbit: int, i_special: int) -> _Huff:
		var n := _br.getbits(nbit)
		var lengths: Array[int] = []
		lengths.resize(nn)
		if n == 0:
			return _Huff.new(lengths, _br.getbits(nbit))
		var i := 0
		while i < n:
			var c := _br.getbits(3)
			if c == 7:
				while _br.getbit() == 1:
					c += 1
					if c > 16:
						error = "コード長表が壊れています"
						return null
			if i < nn:
				lengths[i] = c
			i += 1
			if i == i_special:
				var cnt := _br.getbits(2)
				for _j in cnt:
					if i < nn:
						lengths[i] = 0
					i += 1
		var h := _Huff.new(lengths)
		if not h.is_sane():
			error = "コード長表が過剰です"
			return null
		return h

	func _read_c_len(pt: _Huff) -> _Huff:
		var n := _br.getbits(CBIT)
		var lengths: Array[int] = []
		lengths.resize(NC)
		if n == 0:
			return _Huff.new(lengths, _br.getbits(CBIT))
		var i := 0
		while i < n:
			var c := pt.decode(_br)
			if c < 0:
				error = "C 表の復号に失敗しました"
				return null
			if c <= 2:
				var cnt := 1
				if c == 1:
					cnt = 3 + _br.getbits(4)
				elif c == 2:
					cnt = 20 + _br.getbits(9)
				for _j in cnt:
					if i < NC:
						lengths[i] = 0
					i += 1
			else:
				if i < NC:
					lengths[i] = c - 2
				i += 1
		var h := _Huff.new(lengths)
		if not h.is_sane():
			error = "C 表が過剰です"
			return null
		return h


# -- CRC16(LHA と同じ、反射多項式 0xA001、初期値 0) -------------------------------

static var _crc_table: Array[int] = []


static func _ensure_crc_table() -> void:
	if not _crc_table.is_empty():
		return
	_crc_table.resize(256)
	for i in 256:
		var c := i
		for _j in 8:
			c = (c >> 1) ^ (0xA001 if (c & 1) != 0 else 0)
		_crc_table[i] = c


static func crc16(data: PackedByteArray, crc: int = 0) -> int:
	_ensure_crc_table()
	var c := crc
	for b in data:
		c = _crc_table[(c ^ b) & 0xFF] ^ (c >> 8)
	return c


# -- ヘッダ解析 -----------------------------------------------------------------

static func _u16(data: PackedByteArray, at: int) -> int:
	return data[at] | (data[at + 1] << 8)


static func _u32(data: PackedByteArray, at: int) -> int:
	return data[at] | (data[at + 1] << 8) | (data[at + 2] << 16) | (data[at + 3] << 24)


static func _method_string(data: PackedByteArray, at: int) -> String:
	return data.slice(at, at + 5).get_string_from_ascii()


## パスの区切りを "/" に直して cp932 デコードする。
## 0x5C / 0xFF は単独バイトのときだけ区切りとみなす
## (先行バイトの次バイトはそのまま通す)。
static func _decode_path(raw: PackedByteArray) -> String:
	var out := PackedByteArray()
	var i := 0
	while i < raw.size():
		var b := raw[i]
		if Cp932.is_lead_byte(b) and i + 1 < raw.size():
			out.append(b)
			out.append(raw[i + 1])
			i += 2
		elif b == 0x5C or b == 0xFF:
			out.append(0x2F)
			i += 1
		else:
			out.append(b)
			i += 1
	return Cp932.decode(out)


static func _join_path(dir_raw: PackedByteArray, name_raw: PackedByteArray) -> String:
	var name := _decode_path(name_raw)
	if dir_raw.is_empty():
		return name
	var dir := _decode_path(dir_raw)
	while dir.ends_with("/"):
		dir = dir.substr(0, dir.length() - 1)
	while name.begins_with("/"):
		name = name.substr(1)
	if dir.is_empty():
		return name
	return dir + "/" + name


## 拡張ヘッダ列を読む。{name, dir, error, end}。end は終端の 0 の
## 次の位置(データの開始位置)。from から limit までの間を
## [サイズ(2)][種類(1)][データ] の連鎖でたどる。
static func _read_ext_headers(data: PackedByteArray, from: int, limit: int) -> Dictionary:
	var name_raw := PackedByteArray()
	var dir_raw := PackedByteArray()
	var epos := from
	var end := from
	while epos + 2 <= limit:
		var esize := _u16(data, epos)
		if esize == 0:
			end = epos + 2
			break
		if esize < 3 or epos + esize > limit:
			return {"name": name_raw, "dir": dir_raw, "error": "拡張ヘッダが壊れています", "end": end}
		var etype := data[epos + 2]
		var edata := data.slice(epos + 3, epos + esize)
		if etype == 0x01:
			name_raw = edata
		elif etype == 0x02:
			dir_raw = edata
		epos += esize
		end = epos
	return {"name": name_raw, "dir": dir_raw, "error": "", "end": end}


## 全エントリの内部表現({name, method, compressed_size, original_size,
## crc, header_level, data_offset})とエラーを返す。
static func _parse_entries(data: PackedByteArray) -> Dictionary:
	var entries: Array = []
	var size := data.size()
	var pos := 0
	while pos < size:
		if data[pos] == 0:
			break # 終端マーク
		if size - pos < 21:
			return {"entries": entries, "error": "ヘッダが途中で切れています"}
		var level := data[pos + 20]
		if level == 2:
			var header_size := _u16(data, pos)
			if header_size < 24 or pos + header_size > size:
				return {"entries": entries, "error": "レベル 2 ヘッダが壊れています"}
			var ext := _read_ext_headers(data, pos + 24, pos + header_size)
			if str(ext["error"]) != "":
				return {"entries": entries, "error": str(ext["error"])}
			var csize := _u32(data, pos + 7)
			entries.append({
				"name": _join_path(ext["dir"], ext["name"]),
				"method": _method_string(data, pos + 2),
				"compressed_size": csize,
				"original_size": _u32(data, pos + 11),
				"crc": _u16(data, pos + 21),
				"header_level": 2,
				"data_offset": pos + header_size,
			})
			pos += header_size + csize
		elif level == 0 or level == 1:
			var total := data[pos] + 2
			if pos + total > size:
				return {"entries": entries, "error": "ヘッダが途中で切れています"}
			var name_len := data[pos + 21]
			if 22 + name_len + 2 > total:
				return {"entries": entries, "error": "ファイル名がヘッダに収まりません"}
			var name_raw := data.slice(pos + 22, pos + 22 + name_len)
			var csize2 := _u32(data, pos + 7)
			var data_start := pos + total
			var entry_csize := csize2
			if level == 1:
				# レベル 1 は基本ヘッダの固定長部分(CRC と OS バイト
				# まで)の直後に拡張ヘッダ列が続く。ヘッダサイズ欄は
				# 固定部 + 2 を指し(最初の拡張ヘッダのサイズ欄だけが
				# 基本ヘッダ側に数えられる)、残りの拡張ヘッダ分は
				# 圧縮サイズ欄に含まれる。データは終端の 0 の次から。
				var ext2 := _read_ext_headers(data, pos + 25 + name_len, size)
				if str(ext2["error"]) != "":
					return {"entries": entries, "error": str(ext2["error"])}
				if not (ext2["name"] as PackedByteArray).is_empty():
					name_raw = ext2["name"]
				if not (ext2["dir"] as PackedByteArray).is_empty():
					# フォルダ名の末尾には区切り (0xFF) が付いている
					# ので、無い時だけ足して連結する (二重区切り防止)。
					var joined: PackedByteArray = (ext2["dir"] as PackedByteArray).duplicate()
					if joined[joined.size() - 1] != 0xFF:
						joined.append(0xFF)
					joined.append_array(name_raw)
					name_raw = joined
				data_start = int(ext2["end"])
				entry_csize = pos + total + csize2 - data_start
				if entry_csize < 0:
					return {"entries": entries, "error": "拡張ヘッダが壊れています"}
			entries.append({
				"name": _decode_path(name_raw),
				"method": _method_string(data, pos + 2),
				"compressed_size": entry_csize,
				"original_size": _u32(data, pos + 11),
				"crc": _u16(data, pos + 22 + name_len),
				"header_level": level,
				"data_offset": data_start,
			})
			pos += total + csize2
		else:
			return {"entries": entries, "error": "未対応のヘッダレベルです: " + str(level)}
	return {"entries": entries, "error": ""}


# -- 公開 API -------------------------------------------------------------------

## エントリの一覧。各要素は {name, method, compressed_size,
## original_size, crc, header_level}。解析できない場合は途中までの
## 一覧を返す(エラー詳細は extract_report で得る)。
static func list_entries(data: PackedByteArray) -> Array:
	var parsed := _parse_entries(data)
	var out: Array = []
	for e in parsed["entries"]:
		var entry: Dictionary = e
		out.append({
			"name": entry["name"],
			"method": entry["method"],
			"compressed_size": entry["compressed_size"],
			"original_size": entry["original_size"],
			"crc": entry["crc"],
			"header_level": entry["header_level"],
		})
	return out


## 展開する。ファイル名("/" 区切りの相対パス)→ 内容。
## 失敗したら空の Dictionary を返す。
static func extract(data: PackedByteArray) -> Dictionary:
	var report := extract_report(data)
	return report["files"]


## 展開して結果を報告する。{ok: bool, error: String, files: Dictionary}。
## 1 つでも失敗したら全体を失敗にする(CRC 不一致も失敗)。
static func extract_report(data: PackedByteArray) -> Dictionary:
	var parsed := _parse_entries(data)
	if str(parsed["error"]) != "":
		return {"ok": false, "error": str(parsed["error"]), "files": {}}
	var files := {}
	for e in parsed["entries"]:
		var entry: Dictionary = e
		var name := str(entry["name"])
		var method := str(entry["method"])
		var csize := int(entry["compressed_size"])
		var osize := int(entry["original_size"])
		var offset := int(entry["data_offset"])
		if offset + csize > data.size():
			return {"ok": false, "error": "データが途中で切れています: " + name, "files": {}}
		var raw := data.slice(offset, offset + csize)
		var content := PackedByteArray()
		if method == METHOD_STORE:
			content = raw
		elif method == METHOD_LH5:
			var dec := _Lh5.new()
			content = dec.decode(raw, osize)
			if dec.error != "":
				return {"ok": false, "error": name + ": " + dec.error, "files": {}}
		else:
			return {"ok": false, "error": "未対応のメソッドです: " + method + " (" + name + ")", "files": {}}
		if content.size() != osize:
			return {"ok": false, "error": "展開サイズが一致しません: " + name, "files": {}}
		if crc16(content) != int(entry["crc"]):
			return {"ok": false, "error": "CRC が一致しません: " + name, "files": {}}
		if not name.is_empty():
			files[name] = content
	return {"ok": true, "error": "", "files": files}
