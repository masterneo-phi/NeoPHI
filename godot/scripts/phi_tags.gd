class_name PhiTags
extends RefCounted
## PHI の発言タグ(`/*...*/`)を、表示できる素の文字にする。仕様書 §4。
##
## Python 版 neophi/tags.py の移植。画像の URL は文字として出すだけで、
## 取得はしない(取得すると、受けた人の環境から LAN の機器へ要求を出させてしまう)。

## タグを除いた表示用の文字を返す。`/*br*/` は改行になる。
static func plain_text(text: String) -> String:
	# 高速路: タグ (/*...*/) も「はーと」も無ければ素通り。
	# 以下の置換はすべてタグ相手なので結果は同じ (第73段)。
	if not text.contains("/*") and not text.contains("はーと"):
		return text
	var out := _replace_br(text)
	out = _strip_img_wnd(out)
	out = _replace_img(out)
	out = _strip_all_tags(out)
	out = out.replace("はーと", "♥")
	return out


## plain_text と同じ置換 (改行・画像・はーと) をしつつ、色や
## 書式のタグは残した文字を返す。表示側で to_bbcode へ渡す前段。
static func tagged_text(text: String) -> String:
	var out := _replace_br(text)
	out = _strip_img_wnd(out)
	out = _replace_img(out)
	out = out.replace("はーと", "♥")
	return out


## Philly の特殊カラー (`/*color=+hp*/` など) の既定色。スキンの
## Log.css に `.color__hp` 等の定義があればそちらが優先する
## (呼び出し側が colors で渡す)。
const DEFAULT_SPECIAL_COLORS := {
	"+hp": "#008000", "-hp": "#ff0000",
	"+mp": "#0000ff", "-mp": "#ff0000",
}


static func to_bbcode(text: String, base_size: int, colors: Dictionary = {}) -> String:
	## プレビュー用に `/*...*/` タグを BBCode へ変換する。
	## 対応するのは色・サイズ・スタイルで、フォント名や画像など
	## 描けないものは落とす。閉じタグ `/*.*/` は開いているものを
	## 全部閉じる (Philly の意味どおり)。
	## colors は色名 → "#rrggbb" の対応表 (スキンの Log.css 由来)。
	## 特殊カラーと、スキンが色名に独自の色を割り当てている場合に使う。
	var out := ""
	var stack: Array = []
	var i := 0
	var n := text.length()
	while i < n:
		if text.substr(i, 2) == "/*":
			var close := text.find("*/", i + 2)
			if close < 0:
				out += _escape_bb(text.substr(i))
				break
			var lower := text.substr(i + 2, close - (i + 2)).strip_edges().to_lower()
			i = close + 2
			if lower == ".":
				while not stack.is_empty():
					out += str(stack.pop_back())
				continue
			if lower == "br":
				out += "\n"
				continue
			out += _bbcode_for_tag(lower, base_size, stack, colors)
			continue
		var next := text.find("/*", i)
		if next < 0:
			next = n
		out += _escape_bb(text.substr(i, next - i))
		i = next
	while not stack.is_empty():
		out += str(stack.pop_back())
	return out


static func _escape_bb(text: String) -> String:
	## 1文字ずつ置く (置換で入れた "[lb]" 自身を再置換しないため)。
	var out := ""
	for i in text.length():
		var c := text[i]
		if c == "[":
			out += "[lb]"
		elif c == "]":
			out += "[rb]"
		else:
			out += c
	return out


static func _bbcode_for_tag(lower: String, base_size: int, stack: Array, colors: Dictionary = {}) -> String:
	## タグ1つ分の BBCode を返す。stack へ閉じ側を積む。
	for prefix in ["color=", "cl=", "c="]:
		if lower.begins_with(prefix):
			var value := lower.substr(prefix.length())
			if value == "olieve":
				value = "olive"
			# スキンの色定義、無ければ特殊カラーの既定色で引く
			# (`+hp` のような値は通常の色名の規則では通らない)。
			var special := str(colors.get(value, DEFAULT_SPECIAL_COLORS.get(value, "")))
			if not special.is_empty():
				stack.append("[/color]")
				return "[color=%s]" % special
			var re := RegEx.new()
			re.compile("^[a-z0-9#]+$")
			if re.search(value) == null:
				return ""
			stack.append("[/color]")
			return "[color=%s]" % value
	if lower.begins_with("size="):
		var value := lower.substr(5)
		var size := 0
		if value == "large":
			size = base_size + 8
		elif value == "small":
			size = maxi(6, base_size - 4)
		elif value.is_valid_int():
			size = int(value)
		elif (value.begins_with("+") or value.begins_with("-")) and value.substr(1).is_valid_int():
			size = maxi(6, base_size + int(value))
		if size <= 0:
			return ""
		stack.append("[/font_size]")
		return "[font_size=%d]" % size
	if lower.begins_with("style="):
		match lower.substr(6):
			"bold":
				stack.append("[/b]")
				return "[b]"
			"italic":
				stack.append("[/i]")
				return "[i]"
			"strike":
				stack.append("[/s]")
				return "[s]"
			"under":
				stack.append("[/u]")
				return "[u]"
			"sup", "sub":
				stack.append("[/font_size]")
				return "[font_size=%d]" % maxi(6, base_size - 4)
		return ""
	match lower:
		"b":
			stack.append("[/b]")
			return "[b]"
		"i":
			stack.append("[/i]")
			return "[i]"
		"u":
			stack.append("[/u]")
			return "[u]"
		"s":
			stack.append("[/s]")
			return "[s]"
	return ""


## タグをすべて除く。リストの行の番号読み取りなど、表示しない用途向け。
static func strip_tags(text: String) -> String:
	var out := _replace_br(text, "")
	out = _strip_all_tags(out)
	return out


## `/*to=名前*/` の名前を、現れた順に返す。
static func extract_to_names(text: String) -> Array[String]:
	var names: Array[String] = []
	var pos := 0
	while true:
		var start := _find_tag_open(text, pos, "to=")
		if start < 0:
			break
		var close := text.find("*/", start)
		if close < 0:
			break
		var body := text.substr(start + 4, close - (start + 4))
		names.append(body.strip_edges())
		pos = close + 2
	return names


static func _find_tag_open(text: String, from: int, prefix: String) -> int:
	## `/*<prefix>` の開始位置。大文字小文字を区別しない。無ければ -1。
	var lower := text.to_lower()
	var needle := "/*" + prefix.to_lower()
	return lower.find(needle, from)


static func _replace_br(text: String, replacement: String = "\n") -> String:
	var out := text
	var pos := 0
	while true:
		var start := _find_tag_open(out, pos, "br")
		if start < 0:
			break
		# /*br*/ の形だけを対象にする
		if out.substr(start, 6).to_lower() != "/*br*/":
			pos = start + 2
			continue
		out = out.substr(0, start) + replacement + out.substr(start + 6)
		pos = start + replacement.length()
	return out


static func _strip_img_wnd(text: String) -> String:
	var out := text
	var pos := 0
	while true:
		var start := _find_tag_open(out, pos, "img_wnd=")
		if start < 0:
			break
		var close := out.find("*/", start)
		if close < 0:
			break
		out = out.substr(0, start) + out.substr(close + 2)
		pos = start
	return out


static func _replace_img(text: String) -> String:
	var out := text
	var pos := 0
	while true:
		var start := _find_tag_open(out, pos, "img=")
		if start < 0:
			break
		var close := out.find("*/", start)
		if close < 0:
			break
		var body := out.substr(start + 6, close - (start + 6)).strip_edges()
		var url := ""
		if not body.is_empty():
			url = body.split(" ", false, 1)[0]
		var replacement := "[画像: %s]" % url if not url.is_empty() else "[画像]"
		out = out.substr(0, start) + replacement + out.substr(close + 2)
		pos = start + replacement.length()
	return out


static func _strip_all_tags(text: String) -> String:
	var out := text
	var pos := 0
	while true:
		var start := out.find("/*", pos)
		if start < 0:
			break
		var close := out.find("*/", start + 2)
		if close < 0:
			break
		out = out.substr(0, start) + out.substr(close + 2)
		pos = start
	return out
