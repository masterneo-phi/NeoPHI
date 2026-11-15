class_name PhiTags
extends RefCounted
## PHI の発言タグ(`/*...*/`)を、表示できる素の文字にする。仕様書 §4。
##
## Python 版 neophi/tags.py の移植。画像の URL は文字として出すだけで、
## 取得はしない(取得すると、受けた人の環境から LAN の機器へ要求を出させてしまう)。

## タグを除いた表示用の文字を返す。`/*br*/` は改行になる。
static func plain_text(text: String) -> String:
	var out := _replace_br(text)
	out = _strip_img_wnd(out)
	out = _replace_img(out)
	out = _strip_all_tags(out)
	out = out.replace("はーと", "♥")
	return out


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
