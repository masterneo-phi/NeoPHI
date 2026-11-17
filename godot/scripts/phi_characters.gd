class_name PhiCharacters
extends RefCounted
## キャラクターの保存形式と検証(Philly 互換)。
##
## キャラクターは Philly ルート直下の `<表示名>.chara/` フォルダに置き、
## 中の `.phirc` が ID ファイル。`.phirc` は cp932 テキストで、
## 1行目=ID、2行目=`IP:ポート`(読み取りは `:`/空白/タブ区切り両対応、
## WPHI の read_philly 準拠)。
##
## 表示名は `NN_<名前>`(NN は 01〜99 の空き番号)。管理上限は
## Philly の MAX_CHARACTER_COUNT = 32。
## 名前・メール・IP の検証とパスワード生成は PhillyNewCharacter の
## CheckName / CheckMail / SplitIpPort / MakePassword の移植。

## 管理できるキャラクターの上限(Philly MAX_CHARACTER_COUNT)。
const MAX_CHARACTER_COUNT := 32
## ID フォルダの拡張子(Philly ID_FOLDER_EXT)。
const ID_FOLDER_EXT := ".chara"
## ID ファイル名(Philly ID_FILE)。
const ID_FILE := ".phirc"
## アドレス指定の世界の既定ポート(Philly SplitIpPort)。
const DEFAULT_PORT := 20017

# -- 文字の検証 --------------------------------------------------------------

static func is_single_byte_only(s: String) -> bool:
	## Philly の CheckSingleByteOnly。cp932 で1バイトになる文字だけか。
	## ASCII と半角カタカナ(U+FF61〜U+FF9F)を1バイトとする。
	for i in s.length():
		var c := s.unicode_at(i)
		if c < 0x80:
			continue
		if c >= 0xFF61 and c <= 0xFF9F:
			continue
		return false
	return true


static func check_name(p_name: String) -> String:
	## PhillyNewCharacter の CheckName。問題が無ければ ""、
	## あれば Philly の警告文(そのまま表示できる形)を返す。
	## 文字数は cp932 のバイト数で数える(Philly の AnsiString.Length)。
	var byte_len := Cp932.encode(p_name).size()
	if byte_len < 2:
		return "名前が短すぎます。\n名前は半角英数で2文字以上にして下さい。"
	if byte_len > 31:
		return "名前が長すぎます。\n名前は半角英数で31文字以内にして下さい。"
	if not is_single_byte_only(p_name):
		return "名前に全角文字が含まれています。\n名前には半角の英数のみを使うことができます"
	if p_name.begins_with(" "):
		return "名前の最初の文字がスペースだと不具合が起こることがあります。\n入力しなおして下さい。"
	if p_name.ends_with(" "):
		return "名前の最後の文字がスペースだと不具合が起こることがあります。\n入力しなおして下さい。"
	if p_name.begins_with("#"):
		return "「#」から始まる名前は登録できません。\n入力しなおして下さい。"
	if p_name.contains("/*"):
		return "「/*」が入る名前は登録できません。\n入力しなおして下さい。"
	if p_name.contains("*/"):
		return "「*/」が入る名前は登録できません。\n入力しなおして下さい。"
	return ""


static func check_mail(mail: String) -> Dictionary:
	## PhillyNewCharacter の CheckMail。`@` が無ければ末尾に補う。
	## `{ok: bool, mail: 補正後のメール, error: 警告文}` を返す。
	if not is_single_byte_only(mail):
		return {"ok": false, "mail": mail, "error": "メールアドレスに全角文字が含まれています。\nメールアドレスは半角の英数のみを使うことができます"}
	var out := mail
	if not out.contains("@"):
		out += "@"
	return {"ok": true, "mail": out, "error": ""}


static func make_password(rng: RandomNumberGenerator = null) -> String:
	## PhillyNewCharacter の MakePassword。`[0-9A-Za-z]` から6文字。
	var r := rng
	if r == null:
		r = RandomNumberGenerator.new()
		r.randomize()
	var out := ""
	for i in 6:
		var code := r.randi_range(0, 61)
		if code < 10:
			out += str(code)
		elif code < 36:
			out += char(code - 10 + 0x41)
		else:
			out += char(code - 36 + 0x61)
	return out


static func split_ip_port(input: String) -> Dictionary:
	## PhillyNewCharacter の SplitIpPort。`IP:ポート` を分ける。
	## `:` が無ければポートは 20017、ポートが数値でなければ 20017。
	## IP はドット4桁形式でなければ不正。
	## `{ok: bool, ip: String, port: int, error: 警告文}` を返す。
	var ip := input
	var port := DEFAULT_PORT
	var idx := input.find(":")
	if idx >= 0:
		ip = input.substr(0, idx)
		var port_text := input.substr(idx + 1)
		if port_text.is_valid_int():
			port = int(port_text)
	var re := RegEx.new()
	re.compile("^\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}$")
	if re.search(ip) == null:
		return {"ok": false, "ip": ip, "port": port, "error": "IP アドレスが不正です。"}
	return {"ok": true, "ip": ip, "port": port, "error": ""}

# -- 表示名 ------------------------------------------------------------------

static func sanitize_display_name(p_name: String) -> String:
	## Philly の MakeDisplayName の置換。`[\e\\/:*?"<>|,; ]` → `-`、
	## 改行は除去する。
	var out := ""
	for i in p_name.length():
		var c := p_name.unicode_at(i)
		if c == 0x0D or c == 0x0A:
			continue
		if c == 0x1B or c in [0x5C, 0x2F, 0x3A, 0x2A, 0x3F, 0x22, 0x3C, 0x3E, 0x7C, 0x2C, 0x3B, 0x20]:
			out += "-"
		else:
			out += p_name.substr(i, 1)
	return out


static func empty_no(entries: Array) -> int:
	## 使われていない最小の番号(1〜99)。無ければ -1。
	## Philly の SearchEmptyNo(表示名の先頭2文字を番号と見る)。
	var used := {}
	for entry in entries:
		var display := str(entry.get("display_name", "")) if entry is Dictionary else str(entry)
		if display.length() < 2:
			continue
		var c0 := display.unicode_at(0)
		var c1 := display.unicode_at(1)
		if c0 >= 0x30 and c0 <= 0x39 and c1 >= 0x30 and c1 <= 0x39:
			used[int(display.substr(0, 2))] = true
	for i in range(1, 100):
		if not used.has(i):
			return i
	return -1


static func make_display_name(p_name: String, entries: Array, root: String) -> Dictionary:
	## 表示名 `NN_<名前>` を作る(Philly の MakeDisplayName)。
	## `{ok: bool, display_name: String, is_new: 完全新規か, error: 警告文}`。
	if entries.size() >= MAX_CHARACTER_COUNT:
		return {"ok": false, "error": "管理できるキャラクターの上限をこえています。"}
	var no := empty_no(entries)
	if no < 0:
		return {"ok": false, "error": "キャラクターナンバーに空きがありません。"}
	var display := "%02d_%s" % [no, sanitize_display_name(p_name)]
	for entry in entries:
		if str(entry.get("display_name", "")).to_lower() == display.to_lower():
			return {"ok": false, "error": "すでに存在するキャラクターとIDフォルダが重なってしまいます。"}
	var folder := root.path_join(display + ID_FOLDER_EXT)
	if DirAccess.open(folder) != null or FileAccess.file_exists(folder):
		return {"ok": false, "error": "すでに存在するキャラクターとIDフォルダが重なってしまいます。"}
	return {"ok": true, "display_name": display, "is_new": entries.is_empty(), "error": ""}

# -- .phirc の読み書き ---------------------------------------------------------

static func phirc_text(id: String, host: String, port: int) -> String:
	## `.phirc` の中身。1行目=ID、2行目=`IP:ポート`。
	return "%s\r\n%s:%d\r\n" % [id, host, port]


static func parse_phirc_text(text: String) -> Dictionary:
	## `.phirc` の中身を読む。読めなければ空の辞書。
	## 2行目は最初の `:`/空白/タブで割り、ポート側の先行区切りは落とす
	## (WPHI read_philly / Philly IpPort.SplitSet 準拠)。
	var lines := text.split("\n")
	if lines.size() < 2:
		return {}
	var id := lines[0].strip_edges()
	if id.is_empty():
		return {}
	var line2 := lines[1].strip_edges()
	var cut := -1
	for i in line2.length():
		var c := line2.unicode_at(i)
		if c == 0x3A or c == 0x20 or c == 0x09:
			cut = i
			break
	if cut < 0:
		return {}
	var host := line2.substr(0, cut)
	var rest := line2.substr(cut)
	var j := 0
	while j < rest.length():
		var c2 := rest.unicode_at(j)
		if c2 == 0x3A or c2 == 0x20 or c2 == 0x09:
			j += 1
		else:
			break
	var port_text := rest.substr(j).strip_edges()
	if not port_text.is_valid_int():
		return {}
	return {"id": id, "host": host, "port": int(port_text)}


static func scan_root(root: String) -> Array:
	## ルート直下の `*.chara`(大小文字不問)を走査し、`.phirc` が
	## 読めたものを表示名順に返す。上限は MAX_CHARACTER_COUNT。
	## 各要素は {display_name, id, host, port, root}。
	var out: Array = []
	if root.is_empty():
		return out
	var dir := DirAccess.open(root)
	if dir == null:
		return out
	for entry_name in dir.get_directories():
		if not entry_name.to_lower().ends_with(ID_FOLDER_EXT):
			continue
		var display := entry_name.substr(0, entry_name.length() - ID_FOLDER_EXT.length())
		if display.is_empty():
			continue
		var phirc_path := root.path_join(entry_name).path_join(ID_FILE)
		if not FileAccess.file_exists(phirc_path):
			continue
		var data := FileAccess.get_file_as_bytes(phirc_path)
		if data == null or data.is_empty():
			continue
		var parsed := parse_phirc_text(Cp932.decode(data))
		if parsed.is_empty():
			continue
		out.append({
			"display_name": display,
			"id": str(parsed["id"]),
			"host": str(parsed["host"]),
			"port": int(parsed["port"]),
			"root": root,
		})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a["display_name"]) < str(b["display_name"]))
	while out.size() > MAX_CHARACTER_COUNT:
		out.pop_back()
	return out


static func scan_roots(roots: Array) -> Array:
	## 複数のルートを走査してまとめる。同じ表示名は先のルート優先。
	var out: Array = []
	var seen := {}
	for root_var in roots:
		for entry in scan_root(str(root_var)):
			var key := str(entry["display_name"])
			if seen.has(key):
				continue
			seen[key] = true
			out.append(entry)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a["display_name"]) < str(b["display_name"]))
	return out


static func chara_root(philly_roots: Array) -> String:
	## 書き込み先のルート。最初に見つかった Philly ルート。
	## 無ければ `user://` 直下。
	for root_var in philly_roots:
		var root := str(root_var)
		if root.is_empty():
			continue
		if DirAccess.open(root) != null:
			return root
	return "user://"


static func import_from(src_root: String, dest_root: String, existing_entries: Array) -> Dictionary:
	## src_root (Philly のフォルダなど) 直下の `*.chara` を全部
	## dest_root へ取り込む。既に登録済みの表示名 (大小文字不問、
	## existing_entries と dest_root の走査で判定) は上書きしない。
	## `{found: 見つけた数, imported: 取り込んだ数, skipped: 見送った数}`。
	var found := scan_root(src_root)
	var existing := {}
	for entry in existing_entries:
		existing[str(entry.get("display_name", "")).to_lower()] = true
	for entry in scan_root(dest_root):
		existing[str(entry["display_name"]).to_lower()] = true
	var imported := 0
	var skipped := 0
	for entry in found:
		var display := str(entry["display_name"])
		var key := display.to_lower()
		if existing.has(key):
			skipped += 1
			continue
		if write_phirc(dest_root, display, str(entry["id"]), str(entry["host"]), int(entry["port"])):
			imported += 1
			existing[key] = true
		else:
			skipped += 1
	return {"found": found.size(), "imported": imported, "skipped": skipped}


static func write_phirc(root: String, display_name: String, id: String, host: String, port: int) -> bool:
	## `<ルート>/<表示名>.chara/.phirc` を書く。フォルダは作る。
	var dir_path := root.path_join(display_name + ID_FOLDER_EXT)
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir_path)) != OK:
		return false
	var file := FileAccess.open(dir_path.path_join(ID_FILE), FileAccess.WRITE)
	if file == null:
		return false
	file.store_buffer(Cp932.encode(phirc_text(id, host, port)))
	file.close()
	return true
