class_name PhiTabSession
extends RefCounted
## タブセッションの保存・復元。Philly の `TabSession.ini` 相当。
##
## 開いていたタブのホスト・ポート・キャラ名・ID を保存する。
## **パスワードは保存しない**。ID はタブ復元のために保存する
## (手入力でつないだキャラは登録ファイルが無いので、ID まで
## 保存しないと再起動後に二度とつなげなくなる。第116段で変更)。
## 復元したタブは未接続で開き、接続の操作でつなぐ。
##
## 形式: 1行に1タブ、`host<TAB>port<TAB>name<TAB>id`。
## id は任意 (古い3フィールド形式も読める)。名前は空でもよい。
## ホストが空のタブ(未接続の空タブ)は保存しない。

const DEFAULT_PATH := "user://TabSession.ini"


static func parse(text: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for raw_line in text.split("\n"):
		var line := raw_line.strip_edges()
		if line.is_empty():
			continue
		var parts := line.split("\t")
		if parts.size() < 2:
			continue
		var host := parts[0].strip_edges()
		if host.is_empty():
			continue
		var port := int(parts[1]) if parts[1].strip_edges().is_valid_int() else 0
		if port < 1 or port > 65535:
			continue
		var tab_name := ""
		if parts.size() >= 3:
			tab_name = parts[2].strip_edges()
		var char_id := ""
		if parts.size() >= 4:
			char_id = parts[3].strip_edges()
		out.append({"host": host, "port": port, "name": tab_name, "id": char_id})
	return out


static func serialize(tabs: Array) -> String:
	var lines: Array[String] = []
	for tab_var in tabs:
		var tab: Dictionary = tab_var
		var host := str(tab.get("host", "")).strip_edges()
		if host.is_empty():
			continue
		var port := int(tab.get("port", 0))
		if port < 1 or port > 65535:
			continue
		var tab_name := str(tab.get("name", ""))
		tab_name = tab_name.replace("\t", " ").replace("\n", " ").replace("\r", " ").strip_edges()
		var char_id := str(tab.get("id", ""))
		char_id = char_id.replace("\t", " ").replace("\n", " ").replace("\r", " ").strip_edges()
		if char_id.is_empty():
			lines.append("%s\t%d\t%s" % [host, port, tab_name])
		else:
			lines.append("%s\t%d\t%s\t%s" % [host, port, tab_name, char_id])
	if lines.is_empty():
		return ""
	return "\n".join(lines) + "\n"


static func load_file(path: String = DEFAULT_PATH) -> Array[Dictionary]:
	if not FileAccess.file_exists(path):
		return []
	var bytes := FileAccess.get_file_as_bytes(path)
	return parse(bytes.get_string_from_utf8())


static func save_file(tabs: Array, path: String = DEFAULT_PATH) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(serialize(tabs))
	file.close()
	return true
