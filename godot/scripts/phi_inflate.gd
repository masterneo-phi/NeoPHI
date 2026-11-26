class_name PhiInflate
extends RefCounted
## phidm-v6 の deflate 圧縮 (サーバ→クライアント方向のみ) の受信側。
##
## 仕様 (phidm-v6 docs/dev/protocol-v6.md「通信の圧縮」):
## クライアントが `#ex-switch compress=deflate` を送ると、サーバは
## その返事行までは平文で送り、返事行の改行の次のバイトから
## zlib (RFC1950) ストリームを切断まで送り続ける。止める手段は無い。
##
## Godot の StreamPeerGZIP は gzip 形式しか解凍できない (実測:
## zlib をそのまま渡すと最初の put_data で失敗する)。そこで
## zlib の先頭 2 バイト (CMF/FLG) を gzip の 10 バイトのヘッダに
## 差し替えてから渡す。差し替えは中身の deflate 列には触らない。
## 末尾の Adler32 は接続中は届かず、切断の時は finish() を
## 呼ばないので、CRC・チェックサムの照合は行われない。
## 小さな実測 (5 バイトずつの分割投入 + Z_SYNC_FLUSH x3) で
## 増分 inflate の成立を確認済み。
##
## 状態:
##   off   … 平文のまま通す (従来サーバ・申告前)。
##   armed … 申告済みで返事行を探している。返事行までの平文は
##           境界を見落とさないよう末尾を少し残して通す。
##   on    … 返事行を見つけ、その後ろを inflate している。
## feed() の返り値は、LineBuffer へ渡すべき平文バイト列。

const MARK_DEFLATE := "#ex-switch compress=deflate\n"
const MARK_NO := "#ex-switch compress=no\n"
const FEED_SLICE := 16384

var _state := "off"
var _hold := PackedByteArray()
var _peer: StreamPeerGZIP = null
var _zhead := PackedByteArray()
var _header_done := false
## inflate に失敗したか (失敗したら平文へは戻さない。接続は壊れる)。
var failed := false


func arm() -> void:
	## 圧縮を申し込んだ。返事行の探索を始める。
	if _state == "off":
		_state = "armed"
		_hold.clear()


func reset() -> void:
	_state = "off"
	_hold.clear()
	_peer = null
	_zhead.clear()
	_header_done = false
	failed = false


func is_on() -> bool:
	return _state == "on"


func is_armed() -> bool:
	return _state == "armed"


func flush_armed() -> PackedByteArray:
	## armed のまま制限時間を過ぎた (古いサーバは返事をしない)。
	## 貯めた平文を放出して off へ戻す。返す平文は呼び出し側が
	## LineBuffer へ渡すこと。
	if _state != "armed":
		return PackedByteArray()
	var out := _hold
	_hold = PackedByteArray()
	_state = "off"
	return out


func feed(chunk: PackedByteArray) -> PackedByteArray:
	match _state:
		"off":
			return chunk
		"armed":
			return _feed_armed(chunk)
		_:
			return _inflate(chunk)


func _feed_armed(chunk: PackedByteArray) -> PackedByteArray:
	_hold.append_array(chunk)
	var mark := MARK_DEFLATE.to_ascii_buffer()
	var pos := _find_line_start(_hold, mark)
	if pos >= 0:
		var cut := pos + mark.size()
		var plain := _hold.slice(0, cut)
		var rest := _hold.slice(cut)
		_hold = PackedByteArray()
		_state = "on"
		_peer = StreamPeerGZIP.new()
		if _peer.start_decompression() != OK:
			failed = true
			return plain
		plain.append_array(_inflate(rest))
		return plain
	var mark_no := MARK_NO.to_ascii_buffer()
	if _find_line_start(_hold, mark_no) >= 0:
		var out := _hold
		_hold = PackedByteArray()
		_state = "off"
		return out
	# まだ返事行が無い。返事行の接頭辞になり得る末尾だけ残して通す。
	# (完成した行は即座に全部通る。残すのは、行頭から始まって
	# マーカーの真の接頭辞になっている最長の末尾だけ。)
	var keep := _armed_holdback(_hold)
	if keep <= 0:
		var out2 := _hold
		_hold = PackedByteArray()
		return out2
	if _hold.size() <= keep:
		return PackedByteArray()
	var out2 := _hold.slice(0, _hold.size() - keep)
	_hold = _hold.slice(_hold.size() - keep)
	return out2


static func _armed_holdback(hay: PackedByteArray) -> int:
	## armed 中に留保すべき末尾の長さ。行頭 (先頭か改行の直後) から
	## 始まり、返事行マーカーどちらかの真の接頭辞になっている最長の
	## サフィックスの長さ。そのような末尾が無ければ 0 (全部通す)。
	var marks := [MARK_DEFLATE.to_ascii_buffer(), MARK_NO.to_ascii_buffer()]
	var maxlen := 0
	for m in marks:
		maxlen = maxi(maxlen, m.size() - 1)
	var lo := maxi(0, hay.size() - maxlen)
	for i in range(lo, hay.size()):
		if i > 0 and hay[i - 1] != 0x0A:
			continue
		var suffix := hay.slice(i)
		for m in marks:
			if suffix.size() < m.size() and m.slice(0, suffix.size()) == suffix:
				return suffix.size()
	return 0


func _inflate(data: PackedByteArray) -> PackedByteArray:
	if _peer == null or failed:
		return PackedByteArray()
	if not _header_done:
		_zhead.append_array(data)
		if _zhead.size() < 2:
			return PackedByteArray()
		var b0 := _zhead[0]
		var b1 := _zhead[1]
		# zlib の CMF/FLG: 圧縮法 8、チェックサム (CMF*256+FLG) % 31 == 0
		if (b0 & 0x0F) != 8 or ((b0 << 8) + b1) % 31 != 0:
			failed = true
			return PackedByteArray()
		# gzip の固定ヘッダ (名前・時刻なし) へ差し替える。
		data = PackedByteArray([0x1F, 0x8B, 0x08, 0x00, 0, 0, 0, 0, 0x00, 0x03])
		data.append_array(_zhead.slice(2))
		_zhead.clear()
		_header_done = true
	var out := PackedByteArray()
	var pos := 0
	while pos < data.size():
		var n := mini(FEED_SLICE, data.size() - pos)
		if _peer.put_data(data.slice(pos, pos + n)) != OK:
			failed = true
			break
		pos += n
		_drain(out)
	_drain(out)
	return out


func _drain(out: PackedByteArray) -> void:
	var guard := 0
	while _peer != null and _peer.get_available_bytes() > 0 and guard < 4096:
		guard += 1
		var r: Array = _peer.get_data(_peer.get_available_bytes())
		if int(r[0]) != OK:
			break
		out.append_array(r[1])


static func _find_line_start(hay: PackedByteArray, needle: PackedByteArray) -> int:
	## needle が行頭 (先頭か改行の直後) に現れる位置。無ければ -1。
	if needle.is_empty() or hay.size() < needle.size():
		return -1
	var last := hay.size() - needle.size()
	for i in range(last + 1):
		if i > 0 and hay[i - 1] != 0x0A:
			continue
		var ok := true
		for j in range(needle.size()):
			if hay[i + j] != needle[j]:
				ok = false
				break
		if ok:
			return i
	return -1
