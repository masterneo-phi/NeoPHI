class_name LineBuffer
extends RefCounted
## 受信バイト列を `\n` で行に分ける。仕様書 §1 と Python 版 line_buffer.py の移植。
##
## cp932 の2バイト目に 0x0A は現れないので、`\n` で切っても2バイト文字は
## 割れない。行末の `\r` を1つ落とし、空の行は捨てる。1行の上限は 64KiB で、
## 超えた行は次の `\n` まで丸ごと捨てる。

## 1行の上限(バイト)。超えた行は丸ごと捨てる。
const MAX_LINE := 64 * 1024

var _partial := PackedByteArray()
## 上限を超えた行の残りを、次の `\n` まで捨てている
var _discarding := false


## `data` を足し、確定した行(`\n` を含まない)を返す。
func feed(data: PackedByteArray) -> Array[PackedByteArray]:
	var last_nl := data.rfind(10)
	if last_nl < 0:
		_keep(data)
		return []
	# 最初の部分は、捨てている途中の行の残り
	var skip_first := _discarding
	_discarding = false
	var done := PackedByteArray()
	done.append_array(_partial)
	done.append_array(data.slice(0, last_nl))
	_partial = PackedByteArray()
	_keep(data.slice(last_nl + 1))
	var lines: Array[PackedByteArray] = []
	var start := 0
	for i in done.size():
		if done[i] == 10:
			lines.append(done.slice(start, i))
			start = i + 1
	lines.append(done.slice(start))
	if skip_first and not lines.is_empty():
		lines.remove_at(0)
	var out: Array[PackedByteArray] = []
	for line in lines:
		if line.size() > MAX_LINE:
			continue
		if line.size() > 0 and line[line.size() - 1] == 13:
			line = line.slice(0, line.size() - 1)
		if line.is_empty():
			continue
		out.append(line)
	return out


func _keep(data: PackedByteArray) -> void:
	## 未確定分に足す。上限を超えたら、その行を次の `\n` まで捨てる。
	if _discarding:
		return
	if _partial.size() + data.size() > MAX_LINE:
		_partial = PackedByteArray()
		_discarding = true
	else:
		_partial.append_array(data)


func reset() -> void:
	## 持ち越し中の未確定分を捨てる(再接続時)。
	_partial = PackedByteArray()
	_discarding = false
