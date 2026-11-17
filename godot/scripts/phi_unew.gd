class_name PhiUnew
extends RefCounted
## Philly の Unew 方式の更新設定 `unew.ini` の読解と、
## 取得記録・状態判定の純粋ロジック(第8段)。
##
## WPHI の download.rs / DownloadPanel が参照実装。相違点が 1 つある:
## WPHI の取得記録 downloaded.json はキーがセクション名(Schedule3 等)
## だが、ここでは仕様指定どおり「URL のファイル名」をキーにし、
## 値に取得した item の Date を保存する。
##
## unew.ini は cp932 の INI。[ScheduleN] ごとに
## Title / URL / exOption / Date / Memo を持つ。
## exOption は `-m1 chip\ *.*` の形で、末尾が "\" のトークンが
## Philly ルート配下の展開先フォルダを表す(WPHI の dest_dir と同じ解釈)。
## ルート直下に置くもの(resist.lzh 等)は exOption にフォルダが無く、
## 展開先は ""(ルート直下)になる。

enum Status { NOT_DOWNLOADED, UP_TO_DATE, UPDATE_AVAILABLE }

## 取得記録の保存先(WPHI の dataDir/downloaded.json 相当)。
const RECORD_PATH := "user://downloaded.json"
## ダウンロード上限(WPHI と同じ 30MB)。
const MAX_BYTES := 30 * 1024 * 1024


# -- INI の読解 -----------------------------------------------------------------

## INI テキストをセクションの列にする。各要素は {name, values}、
## values のキーは小文字化し、値は前後の空白と引用符を取り除く。
static func parse_sections(text: String) -> Array:
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
		while value.length() >= 2 and value.begins_with("\"") and value.ends_with("\""):
			value = value.substr(1, value.length() - 2).strip_edges()
		(current["values"] as Dictionary)[key] = value
	return sections


## unew.ini のテキストからスケジュール項目の一覧を作る。
## 各要素は {id, title, url, date, memo, ex_option, dest_dir}。
## [Schedule*] で URL のあるものだけを、ファイルの順で返す。
static func parse_items(text: String) -> Array:
	var items: Array = []
	for section in parse_sections(text):
		var section_dict: Dictionary = section
		var id := str(section_dict["name"])
		if not id.to_lower().begins_with("schedule"):
			continue
		var values: Dictionary = section_dict["values"]
		var url := str(values.get("url", ""))
		if url.is_empty():
			continue
		var ex_option := str(values.get("exoption", ""))
		items.append({
			"id": id,
			"title": str(values.get("title", "")),
			"url": url,
			"date": str(values.get("date", "")),
			"memo": str(values.get("memo", "")),
			"ex_option": ex_option,
			"dest_dir": dest_dir_from_ex_option(ex_option),
		})
	return items


## exOption から展開先の相対フォルダを求める(WPHI の dest_dir と同じ)。
## 末尾が "\" のトークンを探し、"\" → "/"、小文字化する。
## 無ければ ""(Philly ルート直下)。
static func dest_dir_from_ex_option(ex_option: String) -> String:
	for token in ex_option.split(" ", false):
		var part := token.strip_edges()
		if part.ends_with("\\"):
			while part.ends_with("\\"):
				part = part.substr(0, part.length() - 1)
			return part.replace("\\", "/").to_lower()
	return ""


## URL のファイル名部分(記録のキー)。
static func url_file_name(url: String) -> String:
	return url.get_file()


## .lzh の URL に対応する .zip 版の URL。素材の多くは zip 版も
## 用意されているので、取得はそちらを優先する (用意されていない
## ものは呼び出し側が .lzh にフォールバックする)。zip 版が
## あり得ない URL では "" を返す。
static func zip_twin_url(url: String) -> String:
	if url.length() >= 4 and url.substr(url.length() - 4).to_lower() == ".lzh":
		return url.substr(0, url.length() - 4) + ".zip"
	return ""


# -- unew.ini の探索と読み込み ----------------------------------------------------

## unew.ini を探す。各ルートの直下 → `Config/` の順(PhiResist と同じ流儀)。
## 見つからなければ ""。
static func find_unew_file(roots: Array) -> String:
	for root_var in roots:
		var root := str(root_var)
		if root.is_empty():
			continue
		for rel in ["unew.ini", "Config/unew.ini"]:
			var path := root.path_join(rel)
			if FileAccess.file_exists(path):
				return path
	return ""


## ルート群から unew.ini を読み、項目一覧を返す。
## {items: Array, path: String, error: String}。
static func load_items(roots: Array) -> Dictionary:
	var path := find_unew_file(roots)
	if path.is_empty():
		return {"items": [], "path": "", "error": "unew.ini が見つかりません"}
	var data := FileAccess.get_file_as_bytes(path)
	if data == null or data.is_empty():
		return {"items": [], "path": path, "error": "unew.ini が読めません: " + path}
	return {"items": parse_items(SkinFiles.decode_text_file(data)), "path": path, "error": ""}


# -- 取得記録と状態判定 -----------------------------------------------------------

## 取得記録(URL ファイル名 → 取得した item の Date)を読む。
## 無い・壊れている場合は空を返す。
static func load_record(path: String = RECORD_PATH) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed is Dictionary:
		return parsed
	return {}


## 取得記録を保存する。成功したら true。
static func save_record(record: Dictionary, path: String = RECORD_PATH) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(record))
	return true


## item の状態(未取得 / 取得済み / 更新あり)を記録と照らして返す。
static func status_of(item: Dictionary, record: Dictionary) -> Status:
	var key := url_file_name(str(item.get("url", "")))
	if key.is_empty() or not record.has(key):
		return Status.NOT_DOWNLOADED
	if str(record[key]) == str(item.get("date", "")):
		return Status.UP_TO_DATE
	return Status.UPDATE_AVAILABLE


## 状態の表示文字列(WPHI の DownloadPanel と同じ文言)。
## 未取得は空(WPHI では空欄)。
static func status_text(status: Status) -> String:
	match status:
		Status.UP_TO_DATE:
			return "取得済み"
		Status.UPDATE_AVAILABLE:
			return "新しい版があります"
		_:
			return ""


## 取得済みとして記録する(キーは URL のファイル名、値は item の Date)。
static func mark_downloaded(record: Dictionary, item: Dictionary) -> void:
	var key := url_file_name(str(item.get("url", "")))
	if not key.is_empty():
		record[key] = str(item.get("date", ""))
