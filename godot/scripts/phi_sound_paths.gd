class_name PhiSoundPaths
extends RefCounted
## 音ファイルの場所探し(第5段)。Philly の流儀に合わせる。
##
## - 効果音: `SoundFile.ini` の表記は Philly.exe のあるフォルダ
##   (Philly ルート)からの相対パスか絶対パス。相対は各ルートで探す。
## - BGM: Philly ルート直下の `sound/bgm/` ＋ 通知のファイル名。
##   先に `user://sound/bgm/` も探す(NeoPHI の置き場所)。
## - 表記の `\` は `/` に直す(Windows 形式の表記対策)。
##
## どれも、見つからなければ "" を返す(呼び出し側は無音にする)。


static func normalize_entry(entry: String) -> String:
	## 表記を整える。前後の空白を落とし、`\` を `/` にする。
	return entry.strip_edges().replace("\\", "/")


static func is_absolute(entry: String) -> bool:
	## 絶対パスか(Unix 形式か Windows のドライブ表記か)。
	if entry.begins_with("/"):
		return true
	return entry.length() >= 3 and entry[1] == ":" and entry[2] == "/"


static func resolve_se(entry: String, roots: Array) -> String:
	## 効果音のファイルを探す。絶対パスならその場所だけを見る。
	var rel := normalize_entry(entry)
	if rel.is_empty():
		return ""
	if is_absolute(rel):
		return rel if FileAccess.file_exists(rel) else ""
	for root in roots:
		var base := str(root).replace("\\", "/").trim_suffix("/")
		if base.is_empty():
			continue
		var path := base + "/" + rel
		if FileAccess.file_exists(path):
			return path
	return ""


static func bgm_candidates(file_name: String, roots: Array) -> Array[String]:
	## BGM の候補パスの並び(探す順)。user:// を先に、各 Philly
	## ルートの `sound/bgm/` を後に。
	var out: Array[String] = []
	var name := normalize_entry(file_name)
	if name.is_empty():
		return out
	out.append("user://sound/bgm/" + name)
	for root in roots:
		var base := str(root).replace("\\", "/").trim_suffix("/")
		if base.is_empty():
			continue
		out.append(base + "/sound/bgm/" + name)
	return out


static func resolve_bgm(file_name: String, roots: Array) -> String:
	## BGM のファイルを探す。見つからなければ ""。
	for path in bgm_candidates(file_name, roots):
		if FileAccess.file_exists(path):
			return path
	return ""


static func soundfont_candidates(roots: Array) -> Array[String]:
	## サウンドフォント(GeneralUser GS)の候補パスの並び。
	## 同梱の `res://assets/` を先に、Philly ルートの `sound/` を後に。
	var out: Array[String] = ["res://assets/GeneralUser-GS.sf2"]
	for root in roots:
		var base := str(root).replace("\\", "/").trim_suffix("/")
		if base.is_empty():
			continue
		out.append(base + "/sound/GeneralUser-GS.sf2")
		out.append(base + "/GeneralUser-GS.sf2")
	return out


static func resolve_soundfont(roots: Array) -> String:
	## サウンドフォントを探す。見つからなければ ""(MIDI は無音)。
	for path in soundfont_candidates(roots):
		if FileAccess.file_exists(path):
			return path
	return ""
