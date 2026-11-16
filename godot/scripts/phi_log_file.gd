class_name PhiLogFile
extends RefCounted
## ログの自動保存。Philly の `SrcLink/LogFile` にあたる。
##
## キャラクターごとに `Logs/<名前>.log`(テキスト)か `.html` に追記する。
## テキスト保存は時刻入り・タグ削除を選べる(Philly.ini の
## LogSaveTextWithTime / LogSaveDeleteTag)。HTML 保存は、作った時に
## ヘッダを1回だけ書き、以後は行を足していく(Philly の
## AppendHtmlLogFile と同じ、追記しやすい形)。
## ファイルは書くたびに開いて閉じる(LogFileAlwaysOpen の 0 相当)。
## 同時オープン数の心配が無く、クラッシュしても残る。

const DEFAULT_DIR := "user://Logs"


static func sanitize_name(char_name: String) -> String:
	## ファイル名に使える名前にする。使えない字は `_` にする。
	var out := ""
	for i in char_name.length():
		var ch := char_name[i]
		if ch == "/" or ch == "\\" or ch == ":" or ch == "*" or ch == "?" or ch == "\"" or ch == "<" or ch == ">" or ch == "|" or ch.unicode_at(0) < 32:
			out += "_"
		else:
			out += ch
	out = out.strip_edges()
	if out.is_empty() or out == "." or out == "..":
		return "character"
	return out


static func log_path(dir: String, char_name: String, html: bool) -> String:
	var ext := ".html" if html else ".log"
	return dir.path_join(sanitize_name(char_name) + ext)


static func format_text_line(line: String, with_time: bool, stamp: String) -> String:
	## テキスト保存の1行。時刻は `[HH:MM:SS] ` の形で頭に付ける。
	if with_time and not stamp.is_empty():
		return "[%s] %s" % [stamp, line]
	return line


static func escape_html(text: String) -> String:
	var out := text.replace("&", "&amp;")
	out = out.replace("<", "&lt;")
	out = out.replace(">", "&gt;")
	out = out.replace("\"", "&quot;")
	return out


static func html_header(title: String) -> String:
	return "<!DOCTYPE html>\n<html lang=\"ja\">\n<head>\n<meta charset=\"utf-8\">\n<title>%s</title>\n</head>\n<body>\n" % escape_html(title)


static func format_html_line(line: String) -> String:
	return escape_html(line) + "<br>\n"


## 1行を追記する。HTML でファイルが無ければヘッダも書く。
## 失敗したら false を返す(呼び出し側はログに出すだけにする)。
## 新しいファイルは WRITE で作る。READ_WRITE は既存のファイル
## しか開けないため、そのままでは新規作成できない。
static func append_line(dir: String, char_name: String, html: bool, line: String) -> bool:
	var err := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	if err != OK:
		return false
	var path := log_path(dir, char_name, html)
	var is_new := not FileAccess.file_exists(path)
	var file: FileAccess = null
	if is_new:
		file = FileAccess.open(path, FileAccess.WRITE)
	else:
		file = FileAccess.open(path, FileAccess.READ_WRITE)
	if file == null:
		return false
	if not is_new:
		file.seek_end()
	if html and is_new:
		file.store_string(html_header(char_name + " - NeoPHI log"))
	file.store_string(line + "\n" if not html else format_html_line(line))
	file.close()
	return true


static func buffer_file_name(char_name: String, html: bool, stamp: String) -> String:
	## 手動保存のファイル名。`<名前>_<YYYYMMDD-HHMMSS>.log/.html`。
	var ext := ".html" if html else ".log"
	return sanitize_name(char_name) + "_" + stamp + ext


static func datetime_stamp() -> String:
	## `YYYYMMDD-HHMMSS`(手動保存のファイル名用)。
	var now := Time.get_datetime_dict_from_system()
	return "%04d%02d%02d-%02d%02d%02d" % [
		int(now["year"]), int(now["month"]), int(now["day"]),
		int(now["hour"]), int(now["minute"]), int(now["second"])]


## ログのバッファ全体を新しいファイルに書き出す(手動保存)。
## 自動保存と同じ保存先・同じ行形式で、ファイル名は日時付きにして
## 衝突しないようにする(同じ秒に保存したら `_2`, `_3`… を付ける)。
## lines は保存形式に整えた行(テキストは時刻印も付けた行)。
## 成功したらファイルのパス、失敗したら "" を返す。
static func save_buffer(dir: String, char_name: String, html: bool, lines: Array) -> String:
	var err := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	if err != OK:
		return ""
	var stamp := datetime_stamp()
	var name := buffer_file_name(char_name, html, stamp)
	var path := dir.path_join(name)
	var n := 2
	while FileAccess.file_exists(path):
		var ext := ".html" if html else ".log"
		path = dir.path_join(sanitize_name(char_name) + "_" + stamp + "_" + str(n) + ext)
		n += 1
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return ""
	if html:
		file.store_string(html_header(char_name + " - NeoPHI log"))
		for line in lines:
			file.store_string(format_html_line(str(line)))
		file.store_string("</body>\n</html>\n")
	else:
		for line in lines:
			file.store_string(str(line) + "\n")
	file.close()
	return path
