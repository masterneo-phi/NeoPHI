class_name PhiTabSession
extends RefCounted
## タブセッションの保存・復元。Philly の `TabSession.ini` 相当。
##
## 開いていたタブのホスト・ポート・キャラ名を保存する。
## **ID は保存しない**。復元したタブは未接続で開き、接続の
## 操作で ID を入れてつなぐ。
##
## 形式: 1行に1タブ、`host<TAB>port<TAB>name`。名前は空でもよい。
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
		out.append({"host": host, "port": port, "name": tab_name})
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
		lines.append("%s\t%d\t%s" % [host, port, tab_name])
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
