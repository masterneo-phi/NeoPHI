extends SceneTree
## cp932 変換の検証用。決まったバイト列を復号・符号化して結果を書き出す。
## Python 側で同じ列を Python のコーデックで変換して比べる。
##
## 使い方: godot --headless --path . -s tests/test_cp932.gd
## 出力: /tmp/cp932_decode_godot.txt, /tmp/cp932_encode_godot.txt

const LEADS := [
	0x81, 0x82, 0x83, 0x84, 0x85, 0x86, 0x87, 0x88, 0x89, 0x8A, 0x8B, 0x8C, 0x8D,
	0x8E, 0x8F, 0x90, 0x91, 0x92, 0x93, 0x94, 0x95, 0x96, 0x97, 0x98, 0x99, 0x9A,
	0x9B, 0x9C, 0x9D, 0x9E, 0x9F, 0xE0, 0xE1, 0xE2, 0xE3, 0xE4, 0xE5, 0xE6, 0xE7,
	0xE8, 0xE9, 0xEA, 0xEB, 0xEC, 0xED, 0xEE, 0xEF, 0xF0, 0xF1, 0xF2, 0xF3, 0xF4,
	0xF5, 0xF6, 0xF7, 0xF8, 0xF9, 0xFA, 0xFB, 0xFC,
]

var _lcg_state := 12345


func _lcg_byte() -> int:
	_lcg_state = (_lcg_state * 1103515245 + 12345) & 0x7FFFFFFF
	return (_lcg_state >> 16) & 0xFF


func _chr_utf8(cp: int) -> String:
	var b := PackedByteArray()
	if cp < 0x80:
		b.append(cp)
	elif cp < 0x800:
		b.append(0xC0 | (cp >> 6))
		b.append(0x80 | (cp & 0x3F))
	else:
		b.append(0xE0 | (cp >> 12))
		b.append(0x80 | ((cp >> 6) & 0x3F))
		b.append(0x80 | (cp & 0x3F))
	return b.get_string_from_utf8()


func _initialize() -> void:
	Cp932.ensure_loaded()
	var decode_lines: Array[String] = []
	# 全1バイト
	for b in range(256):
		var raw := PackedByteArray([b])
		decode_lines.append("%s\t%s" % [raw.hex_encode(), Cp932.decode(raw).to_utf8_buffer().hex_encode()])
	# 全先行バイト×全2バイト目
	for lead in LEADS:
		for trail in range(256):
			var raw := PackedByteArray([lead, trail])
			decode_lines.append("%s\t%s" % [raw.hex_encode(), Cp932.decode(raw).to_utf8_buffer().hex_encode()])
	# 乱数列200本(決まった種)
	for n in range(200):
		var length := 1 + _lcg_byte() % 32
		var raw := PackedByteArray()
		for i in range(length):
			raw.append(_lcg_byte())
		decode_lines.append("%s\t%s" % [raw.hex_encode(), Cp932.decode(raw).to_utf8_buffer().hex_encode()])
	# 実際のゲーム行
	var game_lines: Array[PackedByteArray] = [
		Cp932.encode("DM > Guest は魔法を唱えている..."),
		Cp932.encode("DM > モック太郎 が Cure によって回復した. [40 hp]"),
		Cp932.encode("/**/Guest > こんにちはテスト"),
		Cp932.encode("DM > 82/1000 hp left."),
		Cp932.encode("ｱｲｳｴｵ半角ｶﾅ"),
		Cp932.encode("〜～‖￤髙﨑"),
	]
	for raw in game_lines:
		decode_lines.append("%s\t%s" % [raw.hex_encode(), Cp932.decode(raw).to_utf8_buffer().hex_encode()])
	var f := FileAccess.open("/tmp/cp932_decode_godot.txt", FileAccess.WRITE)
	for line in decode_lines:
		f.store_line(line)
	f.close()
	print("decode cases: ", decode_lines.size())

	var encode_lines: Array[String] = []
	for cp in range(0x10000):
		if 0xD800 <= cp and cp <= 0xDFFF:
			continue
		var text := _chr_utf8(cp)
		encode_lines.append("%04x\t%s" % [cp, Cp932.encode(text).hex_encode()])
	# 文字列の符号化
	var texts := [
		"こんにちはテスト",
		"DM > Guest は魔法を唱えている...",
		"ｱｲｳｴｵ",
		"〜～",
		"€😀",
		"髙﨑",
		"",
	]
	for text in texts:
		encode_lines.append("str:%s\t%s" % [text.to_utf8_buffer().hex_encode(), Cp932.encode(text).hex_encode()])
	var g := FileAccess.open("/tmp/cp932_encode_godot.txt", FileAccess.WRITE)
	for line in encode_lines:
		g.store_line(line)
	g.close()
	print("encode cases: ", encode_lines.size())
	quit(0)
