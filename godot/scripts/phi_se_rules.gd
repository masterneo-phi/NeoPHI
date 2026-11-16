class_name PhiSeRules
extends RefCounted
## 効果音の正規表現ルール。Philly の `SoundRegexp.ini` と
## `SoundFile.ini` の組(第5段)。
##
## 両ファイルとも1行目が説明文で、2行目以降が対応する組になる。
## ログ行が正規表現(2行目以降、`/パターン/` 形式)に合ったら、
## 対応する行のファイル名の .wav を鳴らす。ファイル名が空なら
## タスクバーフラッシュ(呼び出し側が注意を促す合図にする)。
## Philly と同じく、最初に合った行だけが効き、合わなければ何もしない。
##
## Godot の RegEx(PCRE2)で照合する。コンパイルできない行は
## 無視し、`bad_count` に数える。

## 組み込みの既定(Philly の Config.cpp の ClearStrList と同じで、
## 説明文だけ＝鳴らす行は無い)。
const DEFAULT_REGEXP_TEXT := "サウンドの正規表現文字列（ perl5 にほぼ準拠）"
const DEFAULT_FILE_TEXT := "サウンドファイル名（.wav）空文字列でタスクバーフラッシュ"

var _res: Array = [] # index はファイルの行番号と対応(0 は説明文で null)
var _files: Array[String] = []
var bad_count := 0


static func split_lines(text: String) -> Array[String]:
	## ファイルの文字を行に分ける。行番号の対応を保つため、
	## 空行も落とさない(末尾の改行による最後の空要素だけ落とす)。
	var out: Array[String] = []
	var lines := text.replace("\r\n", "\n").replace("\r", "\n").split("\n")
	for i in range(lines.size()):
		out.append(lines[i])
	while out.size() > 1 and out[out.size() - 1].is_empty():
		out.remove_at(out.size() - 1)
	return out


static func unwrap_pattern(line: String) -> String:
	## `/パターン/` の囲みを外す。囲みが無ければそのまま。
	var s := line.strip_edges()
	if s.length() >= 2 and s.begins_with("/") and s.ends_with("/"):
		s = s.substr(1, s.length() - 2)
	return s


func load_texts(regexp_text: String, file_text: String) -> void:
	## SoundRegexp.ini と SoundFile.ini の中身から読み込む。
	var pattern_lines := split_lines(regexp_text)
	var file_lines := split_lines(file_text)
	_res.clear()
	_files.clear()
	bad_count = 0
	var count := maxi(pattern_lines.size(), file_lines.size())
	for i in range(count):
		var raw_pattern := pattern_lines[i] if i < pattern_lines.size() else ""
		var raw_file := file_lines[i].strip_edges() if i < file_lines.size() else ""
		_files.append(raw_file)
		if i == 0:
			_res.append(null) # 1行目は説明文
			continue
		var pattern := unwrap_pattern(raw_pattern)
		if pattern.is_empty():
			_res.append(null)
			continue
		var re := RegEx.new()
		if re.compile(pattern) == OK:
			_res.append(re)
		else:
			_res.append(null)
			bad_count += 1


func rule_count() -> int:
	## 説明文を除いたルールの行数(ファイル名だけの行も含む)。
	return maxi(_res.size() - 1, 0)


func match_entry(line: String) -> Dictionary:
	## ログ行に合う最初のルールを返す。合わなければ空の辞書。
	## 返り値: {"index": 行番号, "file": ファイル名(生の表記),
	##          "flash": ファイル名が空＝フラッシュの合図}
	for i in range(1, _res.size()):
		var re: Variant = _res[i]
		if re == null:
			continue
		if (re as RegEx).search(line) != null:
			var file := _files[i] if i < _files.size() else ""
			return {"index": i, "file": file, "flash": file.is_empty()}
	return {}
