class_name PhiLogFilter
extends RefCounted
## ログ削除フィルタ。Philly の `LogDeleteRegexp.ini` 互換。
##
## ファイル形式: 1行目は説明文、2行目以降が `/パターン/` 形式の
## 正規表現(perl5 準拠)。合う行をログに表示しない。
## Godot の RegEx(PCRE2)で照合する。コンパイルできない行は
## 無視し、`bad_count` に数える。

## Philly に同梱されている既定のパターン(`/` を除いた中身)。
const DEFAULT_PATTERNS: Array[String] = [
	"DM.*?> .*?へメッセージを送りました",
	"DM.*?> メッセージを.*?に送信しました\\.",
	"DM.*?> Your message sent to .*?\\.",
	"拾うアイテムを選択して下さい\\.",
	"拾うアイテムの番号を選択",
]

var _res: Array[RegEx] = []
var bad_count := 0


static func parse_patterns(text: String) -> Array[String]:
	## ファイルの文字からパターンの一覧を抜く。1行目は説明文。
	var out: Array[String] = []
	var lines := text.split("\n")
	for i in range(1, lines.size()):
		var line := lines[i].strip_edges()
		if line.is_empty():
			continue
		if line.begins_with("/"):
			line = line.substr(1)
			if line.ends_with("/"):
				line = line.substr(0, line.length() - 1)
		if not line.is_empty():
			out.append(line)
	return out


static func default_filter() -> PhiLogFilter:
	var filter := PhiLogFilter.new()
	filter.load_patterns(DEFAULT_PATTERNS)
	return filter


func load_text(text: String) -> void:
	load_patterns(parse_patterns(text))


func load_patterns(patterns: Array[String]) -> void:
	_res.clear()
	bad_count = 0
	for pattern in patterns:
		var re := RegEx.new()
		if re.compile(pattern) == OK:
			_res.append(re)
		else:
			bad_count += 1


func pattern_count() -> int:
	return _res.size()


func matches(text: String) -> bool:
	for re in _res:
		if re.search(text) != null:
			return true
	return false
