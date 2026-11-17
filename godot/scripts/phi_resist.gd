class_name PhiResist
extends RefCounted
## 世界一覧 `resist.ini` の読解(Philly の REGIST_FILE)。
##
## Philly ルート直下の `resist.ini` を探し、無ければ `Config/resist.ini`。
## 形式は cp932 の INI で、セクション=世界名、キー `Address` / `Port`
## (既定 20017) / `URL` / `Line1`〜`LineN`(説明文。番号が続くまで連結)。
## PhillyNewCharacter と同じく、末尾には「指定したアドレスの世界に登録」
## (アドレス入力可、既定 127.0.0.1:20017)を必ず足す。

## ポートの既定値(PhillyNewCharacter の読み取り既定)。
const DEFAULT_PORT := 20017
## アドレス指定の世界の名前(PhillyNewCharacter と同じ)。
const ADDRESS_INPUT_NAME := "指定したアドレスの世界に登録"
## アドレス指定の世界の説明(PhillyNewCharacter と同じ)。
const ADDRESS_INPUT_COMMENT := "指定したアドレスの世界に登録します。\nアドレス欄に「IPアドレス:ポート番号」という形式で登録世界を指定します。"


static func parse(text: String) -> Array:
	## INI テキストを世界の一覧にする(アドレス指定の世界は含まない)。
	## 各要素は {name, address, port, url, comment, address_input}。
	var sections: Array = []
	var current: Dictionary = {}
	var normalized := text.replace("\r\n", "\n").replace("\r", "\n")
	for raw_line in normalized.split("\n"):
		var line := raw_line.strip_edges()
		if line.is_empty() or line.begins_with(";"):
			continue
		if line.begins_with("[") and line.contains("]"):
			current = {"name": line.substr(1, line.find("]") - 1).strip_edges(), "values": {}}
			sections.append(current)
			continue
		if current.is_empty():
			continue
		var eq := line.find("=")
		if eq < 0:
			continue
		var key := line.substr(0, eq).strip_edges().to_lower()
		var value := line.substr(eq + 1).strip_edges()
		if value.length() >= 2 and value.begins_with("\"") and value.ends_with("\""):
			value = value.substr(1, value.length() - 2)
		(current["values"] as Dictionary)[key] = value
	var worlds: Array = []
	for section in sections:
		var world_name := str(section["name"])
		if world_name.is_empty():
			continue
		var values: Dictionary = section["values"]
		var port := DEFAULT_PORT
		var port_text := str(values.get("port", ""))
		if port_text.is_valid_int():
			port = int(port_text)
		var comment_lines: Array[String] = []
		var j := 1
		while values.has("line%d" % j):
			comment_lines.append(str(values["line%d" % j]))
			j += 1
		worlds.append({
			"name": world_name,
			"address": str(values.get("address", "")),
			"port": port,
			"url": str(values.get("url", "")),
			"comment": "\n".join(comment_lines).strip_edges(false, true),
			"address_input": false,
		})
	return worlds


static func find_resist_file(roots: Array) -> String:
	## resist.ini を探す。各ルートの直下 → `Config/` の順。
	## 見つからなければ ""。
	for root_var in roots:
		var root := str(root_var)
		if root.is_empty():
			continue
		for rel in ["resist.ini", "Config/resist.ini"]:
			var path := root.path_join(rel)
			if FileAccess.file_exists(path):
				return path
	return ""


static func load_worlds(roots: Array) -> Array:
	## 世界の一覧を読む。末尾にアドレス指定の世界を必ず足す。
	var worlds: Array = []
	var path := find_resist_file(roots)
	if not path.is_empty():
		var data := FileAccess.get_file_as_bytes(path)
		if data != null and not data.is_empty():
			worlds = parse(SkinFiles.decode_text_file(data))
	worlds.append({
		"name": ADDRESS_INPUT_NAME,
		"address": "127.0.0.1",
		"port": DEFAULT_PORT,
		"url": "",
		"comment": ADDRESS_INPUT_COMMENT,
		"address_input": true,
	})
	return worlds
