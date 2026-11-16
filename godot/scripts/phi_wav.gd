class_name PhiWav
extends RefCounted
## 外部の音声ファイルを AudioStream に読む(第5段)。
##
## Godot の ResourceLoader は取り込んだファイルしか読めないので、
## 利用者が置いたファイルを直接読む。WAV は RIFF を自分で解釈する
## (PCM 8/16bit はそのまま、24/32bit と浮動小数点は 16bit に直す。
## IMA-ADPCM 等は読めず null)。OGG/MP3 は Godot の `load_from_file`
## を使う。


static func load_audio_file(path: String) -> AudioStream:
	## 拡張子で読み方を選ぶ。読めなければ null。
	var ext := path.get_extension().to_lower()
	match ext:
		"wav":
			return load_wav(path)
		"ogg":
			return AudioStreamOggVorbis.load_from_file(path)
		"mp3":
			return AudioStreamMP3.load_from_file(path)
	return null


static func load_wav(path: String) -> AudioStreamWAV:
	## WAV ファイルを読む。対応外の形式なら null。
	var data := FileAccess.get_file_as_bytes(path)
	if data == null or data.size() < 44:
		return null
	return parse_wav(data)


static func parse_wav(data: PackedByteArray) -> AudioStreamWAV:
	## WAV のバイト列を解釈する。テストからも呼べるよう分けた。
	if data.size() < 44:
		return null
	if _tag(data, 0) != "RIFF" or _tag(data, 8) != "WAVE":
		return null
	var fmt_info: Dictionary = {}
	var pcm := PackedByteArray()
	var pos := 12
	while pos + 8 <= data.size():
		var chunk := _tag(data, pos)
		var size := _u32(data, pos + 4)
		var body := pos + 8
		if body + size > data.size():
			size = data.size() - body
		if chunk == "fmt ":
			if size < 16:
				return null
			fmt_info = {
				"format": _u16(data, body),
				"channels": _u16(data, body + 2),
				"rate": _u32(data, body + 4),
				"bits": _u16(data, body + 14),
			}
		elif chunk == "data":
			pcm = data.slice(body, body + size)
		pos = body + size + (size & 1) # チャンクは偶数境界にそろえる
	if fmt_info.is_empty() or pcm.is_empty():
		return null
	var audio_format := int(fmt_info["format"])
	var channels := int(fmt_info["channels"])
	var rate := int(fmt_info["rate"])
	var bits := int(fmt_info["bits"])
	if channels < 1 or channels > 2 or rate <= 0:
		return null
	var stream := AudioStreamWAV.new()
	stream.mix_rate = rate
	stream.stereo = channels == 2
	if audio_format == 1 and bits == 8:
		stream.format = AudioStreamWAV.FORMAT_8_BITS
		stream.data = pcm
	elif audio_format == 1 and bits == 16:
		stream.format = AudioStreamWAV.FORMAT_16_BITS
		stream.data = pcm
	elif audio_format == 1 and bits == 24:
		stream.format = AudioStreamWAV.FORMAT_16_BITS
		stream.data = _drop_low_byte(pcm, 3)
	elif audio_format == 1 and bits == 32:
		stream.format = AudioStreamWAV.FORMAT_16_BITS
		stream.data = _drop_low_byte(pcm, 4)
	elif audio_format == 3 and bits == 32:
		stream.format = AudioStreamWAV.FORMAT_16_BITS
		stream.data = _float_to_16(pcm)
	else:
		return null
	return stream


static func _tag(data: PackedByteArray, at: int) -> String:
	if at + 4 > data.size():
		return ""
	return data.slice(at, at + 4).get_string_from_ascii()


static func _u16(data: PackedByteArray, at: int) -> int:
	return data[at] | (data[at + 1] << 8)


static func _u32(data: PackedByteArray, at: int) -> int:
	return data[at] | (data[at + 1] << 8) | (data[at + 2] << 16) | (data[at + 3] << 24)


static func _drop_low_byte(pcm: PackedByteArray, sample_bytes: int) -> PackedByteArray:
	## 24/32bit PCM の下位バイトを落として 16bit にする。
	var out := PackedByteArray()
	var count := pcm.size() / sample_bytes
	out.resize(count * 2)
	for i in range(count):
		var src := i * sample_bytes + (sample_bytes - 2)
		out[i * 2] = pcm[src]
		out[i * 2 + 1] = pcm[src + 1]
	return out


static func _float_to_16(pcm: PackedByteArray) -> PackedByteArray:
	## 32bit 浮動小数点 PCM を 16bit にする。
	var out := PackedByteArray()
	var count := pcm.size() / 4
	out.resize(count * 2)
	var buffer := StreamPeerBuffer.new()
	buffer.data_array = pcm
	for i in range(count):
		buffer.seek(i * 4)
		var v := clampf(buffer.get_float(), -1.0, 1.0)
		var s := int(round(v * 32767.0))
		if s < 0:
			s += 65536
		out[i * 2] = s & 0xFF
		out[i * 2 + 1] = (s >> 8) & 0xFF
	return out
