class_name SkinFiles
extends RefCounted
## Philly スキンのファイルを読む純粋関数群。
##
## 対象: `Buttons/Index.txt` / `chara/Index.txt` (キー = 値)、
## `Style/Menu.txt` (on/off)、`Style/Log.css` (ログのスタイル)、
## `Cursor/*.cur` (カーソル絵)。どれも Shift_JIS か UTF-8 の
## テキストとして読む(.cur はバイナリ)。呼び出し側が cp932 変換済みの
## 文字列を渡すこと。

const BUTTON_DEFAULT_SIZE := 20


# -- テキストの復号 ---------------------------------------------------------

static func _is_utf8_cont(byte: int) -> bool:
	return byte >= 0x80 and byte <= 0xBF


static func is_valid_utf8(data: PackedByteArray) -> bool:
	## 厳密な UTF-8 か。過長表現とサロゲートは弾く。
	var i := 0
	while i < data.size():
		var b := data[i]
		if b < 0x80:
			i += 1
		elif b >= 0xC2 and b <= 0xDF:
			if i + 1 >= data.size() or not _is_utf8_cont(data[i + 1]):
				return false
			i += 2
		elif b == 0xE0:
			if i + 2 >= data.size() or data[i + 1] < 0xA0 or data[i + 1] > 0xBF or not _is_utf8_cont(data[i + 2]):
				return false
			i += 3
		elif (b >= 0xE1 and b <= 0xEC) or b == 0xEE or b == 0xEF:
			if i + 2 >= data.size() or not _is_utf8_cont(data[i + 1]) or not _is_utf8_cont(data[i + 2]):
				return false
			i += 3
		elif b == 0xED:
			if i + 2 >= data.size() or data[i + 1] < 0x80 or data[i + 1] > 0x9F or not _is_utf8_cont(data[i + 2]):
				return false
			i += 3
		elif b == 0xF0:
			if i + 3 >= data.size() or data[i + 1] < 0x90 or data[i + 1] > 0xBF or not _is_utf8_cont(data[i + 2]) or not _is_utf8_cont(data[i + 3]):
				return false
			i += 4
		elif b >= 0xF1 and b <= 0xF3:
			if i + 3 >= data.size() or not _is_utf8_cont(data[i + 1]) or not _is_utf8_cont(data[i + 2]) or not _is_utf8_cont(data[i + 3]):
				return false
			i += 4
		elif b == 0xF4:
			if i + 3 >= data.size() or data[i + 1] < 0x80 or data[i + 1] > 0x8F or not _is_utf8_cont(data[i + 2]) or not _is_utf8_cont(data[i + 3]):
				return false
			i += 4
		else:
			return false
	return true


static func decode_text_file(data: PackedByteArray) -> String:
	## スキンのテキストファイルを読む。UTF-8 なら UTF-8、違えば cp932。
	## Log.css は UTF-8、Index.txt/Menu.txt は cp932 のことが多い。
	if is_valid_utf8(data):
		return data.get_string_from_utf8()
	return Cp932.decode(data)


# -- Index.txt (Buttons / chara) -----------------------------------------

static func parse_index_txt(text: String) -> Dictionary:
	## `キー = 値` の一覧を読む。`//` で始まる行はコメント。
	## `{"width": int, "height": int, "map": {キー: 値}}` を返す。
	## width/height が無ければ 20。
	var out := {"width": BUTTON_DEFAULT_SIZE, "height": BUTTON_DEFAULT_SIZE, "map": {}}
	for raw_line in text.split("\n"):
		var line := raw_line.strip_edges()
		if line.is_empty() or line.begins_with("//"):
			continue
		if not line.contains("="):
			continue
		var parts := line.split("=", true, 1)
		var key := parts[0].strip_edges()
		var value := parts[1].strip_edges()
		if key.to_lower() == "width":
			var w := int(value)
			out["width"] = w if w > 0 else BUTTON_DEFAULT_SIZE
		elif key.to_lower() == "height":
			var h := int(value)
			out["height"] = h if h > 0 else BUTTON_DEFAULT_SIZE
		elif not key.is_empty():
			(out["map"] as Dictionary)[key] = value
	return out


# -- Style/Menu.txt ------------------------------------------------------

static func menu_key(name: String) -> String:
	## メニュー名の正規化。`ツール(&Y)` のような末尾の `(&X)` を取る。
	var s := name.strip_edges()
	var paren := s.find("(")
	if paren >= 0 and s.ends_with(")"):
		s = s.substr(0, paren).strip_edges()
	return s


static func parse_menu_txt(text: String) -> Dictionary:
	## `on,名前` / `off,名前` の一覧を読む。`;` で始まる行はコメント。
	## `{正規化した名前: 表示するか}` を返す。空の名前は無視する。
	var out := {}
	for raw_line in text.split("\n"):
		var line := raw_line.strip_edges()
		if line.is_empty() or line.begins_with(";"):
			continue
		if not line.contains(","):
			continue
		var parts := line.split(",", true, 1)
		var flag := parts[0].strip_edges().to_lower()
		var name := menu_key(parts[1])
		if name.is_empty():
			continue
		if flag == "on":
			out[name] = true
		elif flag == "off":
			out[name] = false
	return out


# -- Style/Log.css -------------------------------------------------------

const _CSS_NAMED_COLORS := {
	"white": "#ffffff", "black": "#000000", "red": "#ff0000",
	"green": "#008000", "blue": "#0000ff", "yellow": "#ffff00",
	"aqua": "#00ffff", "cyan": "#00ffff", "fuchsia": "#ff00ff",
	"magenta": "#ff00ff", "gray": "#808080", "grey": "#808080",
	"silver": "#c0c0c0", "maroon": "#800000", "olive": "#808000",
	"lime": "#00ff00", "navy": "#000080", "purple": "#800080",
	"teal": "#008080", "orange": "#ffa500", "pink": "#ffc0cb",
	"brown": "#a52a2a", "gold": "#ffd700", "skyblue": "#87ceeb",
	"salmon": "#fa8072", "khaki": "#f0e68c", "beige": "#f5f5dc",
	"ivory": "#fffff0", "coral": "#ff7f50", "violet": "#ee82ee",
	"indigo": "#4b0082", "turquoise": "#40e0d0", "plum": "#dda0dd",
}


static func parse_css_color(text: String) -> Variant:
	## CSS の色を Color にする。`#rgb` / `#rrggbb` / 色名。
	## 読めなければ null。
	var s := text.strip_edges().to_lower()
	if s.is_empty():
		return null
	if s.begins_with("#"):
		var hex := s.substr(1)
		if hex.length() == 3:
			hex = hex[0] + hex[0] + hex[1] + hex[1] + hex[2] + hex[2]
		if hex.length() != 6:
			return null
		for i in hex.length():
			var c := hex.unicode_at(i)
			var digit := (c >= 0x30 and c <= 0x39) or (c >= 0x61 and c <= 0x66)
			if not digit:
				return null
		return Color(hex)
	var named: Variant = _CSS_NAMED_COLORS.get(s)
	if named == null:
		return null
	return Color(str(named))


static func _strip_css_comments(text: String) -> String:
	var out := ""
	var i := 0
	while i < text.length():
		if i + 1 < text.length() and text[i] == "/" and text[i + 1] == "*":
			var end := text.find("*/", i + 2)
			if end < 0:
				break
			i = end + 2
		else:
			out += text[i]
			i += 1
	return out


static func parse_log_css(text: String) -> Dictionary:
	## Log.css を読む。`{"body": {項目: 値}, "classes": {クラス名: {項目: 値}}}`
	## を返す。値は生の文字列。同じセレクタが複数回出たら項目ごとに
	## 後勝ちでまとめる。body と `.` 付きクラス以外は無視する。
	var body := {}
	var classes := {}
	var clean := _strip_css_comments(text)
	for chunk in clean.split("}"):
		if not chunk.contains("{"):
			continue
		var parts := chunk.split("{", true, 1)
		var selectors := parts[0]
		var decls := {}
		for decl in parts[1].split(";"):
			if not decl.contains(":"):
				continue
			var kv := decl.split(":", true, 1)
			var prop := kv[0].strip_edges().to_lower()
			var value := kv[1].strip_edges()
			if not prop.is_empty():
				decls[prop] = value
		for raw_sel in selectors.split(","):
			var sel := raw_sel.strip_edges()
			if sel == "body":
				for prop in decls:
					body[prop] = decls[prop]
			elif sel.begins_with("."):
				var name := sel.substr(1).strip_edges()
				if name.is_empty():
					continue
				if not classes.has(name):
					classes[name] = {}
				for prop in decls:
					(classes[name] as Dictionary)[prop] = decls[prop]
	return {"body": body, "classes": classes}


static func tag_colors_from_css(css: Dictionary) -> Dictionary:
	## Log.css のカラークラスから、タグの色名 → "#rrggbb" の対応表を作る。
	## Philly では `/*color=+hp*/` が `.color__hp` クラスになる
	## (`+` は `_` に置換、1文字色は末尾に `_` が付く)。
	## `.c_` / `.cl_` より `.color_` を優先する。
	var classes: Dictionary = css.get("classes", {})
	var out := {}
	for prefix in ["c_", "cl_", "color_"]:
		for name in classes:
			if not str(name).begins_with(prefix):
				continue
			var rest := str(name).substr(prefix.length())
			var value := ""
			if rest.begins_with("_"):
				value = "+" + rest.substr(1)
			elif rest.length() == 2 and rest.ends_with("_"):
				value = rest.substr(0, 1)
			else:
				value = rest
			if value.is_empty():
				continue
			var decls: Dictionary = classes[name]
			var col: Variant = parse_css_color(str(decls.get("color", "")))
			if col != null:
				out[value] = "#" + (col as Color).to_html(false)
	return out


# -- Cursor/*.cur ----------------------------------------------------------

static func _cur_u16(data: PackedByteArray, off: int) -> int:
	return data[off] | (data[off + 1] << 8)


static func _cur_u32(data: PackedByteArray, off: int) -> int:
	return data[off] | (data[off + 1] << 8) | (data[off + 2] << 16) | (data[off + 3] << 24)


static func _cur_s32(data: PackedByteArray, off: int) -> int:
	var v := _cur_u32(data, off)
	if v >= 0x80000000:
		return v - 0x100000000
	return v


static func decode_cur(data: PackedByteArray) -> Dictionary:
	## .cur を読む。`{"image": Image, "hotspot": Vector2i}` を返す。
	## 読めなければ {}。DIB(BMP 形式、1/4/8/24/32 ビット)と
	## PNG 埋め込みに対応する。DIB の高さは XOR マスクと AND マスクの
	## 2 枚分になっている(AND マスクの 1 が透明)。
	if data.size() < 22:
		return {}
	var type_id := _cur_u16(data, 2)
	var count := _cur_u16(data, 4)
	if type_id != 2 or count < 1:
		return {}
	var hotspot := Vector2i(_cur_u16(data, 10), _cur_u16(data, 12))
	var img_size := _cur_u32(data, 14)
	var offset := _cur_u32(data, 18)
	if offset < 22 or offset >= data.size():
		return {}
	var end := mini(offset + img_size, data.size())
	if end - offset < 4:
		return {}
	# PNG 埋め込みのカーソル
	if end - offset >= 8 and data[offset] == 0x89 and data[offset + 1] == 0x50 and data[offset + 2] == 0x4E and data[offset + 3] == 0x47:
		var png := Image.new()
		if png.load_png_from_buffer(data.slice(offset, end)) != OK:
			return {}
		return {"image": png, "hotspot": hotspot}
	var header_size := _cur_u32(data, offset)
	if header_size < 40 or offset + header_size > data.size():
		return {}
	var dib_w := _cur_s32(data, offset + 4)
	var dib_h := _cur_s32(data, offset + 8)
	var bpp := _cur_u16(data, offset + 14)
	var compression := _cur_u32(data, offset + 16)
	if compression != 0 or dib_w <= 0 or dib_h <= 0 or dib_h % 2 != 0:
		return {}
	if bpp != 1 and bpp != 4 and bpp != 8 and bpp != 24 and bpp != 32:
		return {}
	var w := dib_w
	var h := dib_h / 2
	var palette_count := 0
	if bpp <= 8:
		palette_count = 1 << bpp
		var used := _cur_u32(data, offset + 32)
		if used > 0 and used < palette_count:
			palette_count = int(used)
	var palette_off := offset + header_size
	var xor_off := palette_off + palette_count * 4
	var xor_row_bytes := ((w * bpp + 31) / 32) * 4
	var and_row_bytes := ((w + 31) / 32) * 4
	var and_off := xor_off + xor_row_bytes * h
	if and_off + and_row_bytes * h > data.size():
		return {}
	# 32 ビットは XOR のアルファバイトを使うか、全体を見て決める。
	var use_xor_alpha := false
	if bpp == 32:
		var p := xor_off
		while p < and_off:
			if data[p + 3] != 0:
				use_xor_alpha = true
				break
			p += 4
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		var src_y := h - 1 - y # DIB は下から
		var xor_row := xor_off + src_y * xor_row_bytes
		var and_row := and_off + src_y * and_row_bytes
		for x in w:
			var r := 0
			var g := 0
			var b := 0
			var xor_alpha := 255
			if bpp <= 8:
				var index := 0
				if bpp == 1:
					var byte := data[xor_row + x / 8]
					index = (byte >> (7 - (x % 8))) & 1
				elif bpp == 4:
					var byte := data[xor_row + x / 2]
					index = (byte >> 4) & 0x0F if x % 2 == 0 else byte & 0x0F
				else:
					index = data[xor_row + x]
				var pal := palette_off + index * 4
				b = data[pal]
				g = data[pal + 1]
				r = data[pal + 2]
			elif bpp == 24:
				var p := xor_row + x * 3
				b = data[p]
				g = data[p + 1]
				r = data[p + 2]
			else:
				var p := xor_row + x * 4
				b = data[p]
				g = data[p + 1]
				r = data[p + 2]
				xor_alpha = data[p + 3]
			var and_byte := data[and_row + x / 8]
			var transparent := ((and_byte >> (7 - (x % 8))) & 1) == 1
			var alpha := 0
			if not transparent:
				alpha = xor_alpha if use_xor_alpha else 255
			img.set_pixel(x, y, Color(r / 255.0, g / 255.0, b / 255.0, alpha / 255.0))
	return {"image": img, "hotspot": hotspot}
