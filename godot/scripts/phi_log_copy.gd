class_name PhiLogCopy
extends RefCounted
## ログのコピー変種。Philly のログ編集アクションにあたる。
## 選択範囲の文字に対する純粋な変換だけを持つ。
##
## 変種: タグ付き / タグ無し / 時刻削除 / 名前削除 /
## タグ無効化(`/*` → `／*`)。

const _PREFIXES := ["[発言] ", "[priv] ", "[お知らせ] "]


static func _each_line(text: String, fn: Callable) -> String:
	var lines := text.split("\n")
	var out: Array[String] = []
	for line in lines:
		out.append(str(fn.call(line)))
	return "\n".join(out)


static func strip_time(text: String) -> String:
	## 行頭の時刻(`HH:MM:SS ` または `[HH:MM:SS] `)を取る。
	## 今のログ表示に時刻は無いが、時刻入りの文字にも効く。
	var re := RegEx.new()
	re.compile("^(\\[\\d{2}:\\d{2}:\\d{2}\\] |\\d{2}:\\d{2}:\\d{2} )")
	return _each_line(text, func(line: String) -> String: return re.sub(line, ""))


static func strip_name(text: String) -> String:
	## 表示の接頭辞と、発言者の名前(`名前 > `)を取る。本文だけが残る。
	var re := RegEx.new()
	re.compile("^((\\[[^\\]]*\\])|(\"[^\"]*\")|(\\([^)]*\\))|(\\{[^}]*\\})|([^>\\s][^>]*?)) > ")
	return _each_line(text, func(line: String) -> String:
		var out := line
		for prefix in _PREFIXES:
			if out.begins_with(prefix):
				out = out.substr(prefix.length())
				break
		return re.sub(out, "")
	)


static func strip_tags(text: String) -> String:
	## 残っている `/*...*/` タグを取る(表示は既にタグ無しなので、
	## ふつうは何も変わらない。念のための変種)。
	return PhiTags.strip_tags(text)


static func disable_tags(text: String) -> String:
	## タグを無効化する。`/*` を全角の `／*` にする(Philly と同じ)。
	return text.replace("/*", "／*")


static func with_tags(selected: String, buffer: Array) -> String:
	## タグ付きでコピーする。選んだ各行について、ログの記録から
	## 表示が一致する行のタグ付きの原文を探して使う。見つからな
	## ければ選んだ行をそのまま使う(部分選択の時など)。
	## buffer の要素は {"display": 表示行, "raw": タグ付きの原文}。
	var index := {}
	for entry in buffer:
		var entry_dict: Dictionary = entry
		var display := str(entry_dict.get("display", ""))
		if not display.is_empty() and not index.has(display):
			index[display] = str(entry_dict.get("raw", display))
	return _each_line(selected, func(line: String) -> String:
		if index.has(line):
			return str(index[line])
		return line
	)
