extends SceneTree
## 第29段: キャラデータ読み込み (PhiCharacters.import_from)。
## Philly フォルダ直下の *.chara を別のルートへ取り込み、
## 既存の表示名は上書きしないことを確かめる。

var _checks := 0
var _failures := 0

const BASE := "/tmp/neophi_stage29"


func check(cond: bool, label: String) -> void:
	_checks += 1
	if not cond:
		_failures += 1
		print("FAIL: ", label)


func _rm(path: String) -> void:
	OS.execute("rm", ["-rf", path])


func _mk_chara(root: String, display: String, body: String) -> void:
	var dir_path := root.path_join(display + ".chara")
	DirAccess.make_dir_recursive_absolute(dir_path)
	if body.is_empty():
		return
	var file := FileAccess.open(dir_path.path_join(".phirc"), FileAccess.WRITE)
	file.store_buffer(Cp932.encode(body))
	file.close()


func _initialize() -> void:
	_rm(BASE)
	var src := BASE.path_join("philly")
	var dest := BASE.path_join("mine")
	DirAccess.make_dir_recursive_absolute(src)
	DirAccess.make_dir_recursive_absolute(dest)
	# 取り込み元: 正常2件 (うち1件は dest と同名)、壊れた1件、
	# .phirc 無し1件 (数えない)。
	_mk_chara(src, "01_たろう", "id-taro\r\n192.0.2.11:20017\r\n")
	_mk_chara(src, "02_はなこ", "id-hana\r\n192.0.2.12:20018\r\n")
	_mk_chara(src, "03_こわれた", "x\r\n")
	_mk_chara(src, "04_なかみなし", "")
	# 取り込み先に同名が既にある。
	_mk_chara(dest, "02_はなこ", "id-old\r\n192.0.2.99:20017\r\n")

	var r1 := PhiCharacters.import_from(src, dest, [])
	check(int(r1["found"]) == 2, "見つけたのは読める2件: %s" % str(r1))
	check(int(r1["imported"]) == 1, "取り込みは新規の1件")
	check(int(r1["skipped"]) == 1, "同名の1件はスキップ")

	var entries := PhiCharacters.scan_root(dest)
	check(entries.size() == 2, "dest は2件になる")
	var by_name := {}
	for e in entries:
		by_name[str(e["display_name"])] = e
	check(str(by_name["01_たろう"]["id"]) == "id-taro", "たろうの ID が移る")
	check(int(by_name["01_たろう"]["port"]) == 20017, "たろうのポートが移る")
	check(str(by_name["02_はなこ"]["id"]) == "id-old", "既存のはなこは上書きされない")

	# 2回目は全部スキップ。
	var r2 := PhiCharacters.import_from(src, dest, [])
	check(int(r2["imported"]) == 0 and int(r2["skipped"]) == 2, "2回目は全スキップ")

	# 大小文字違いの同名も重複とみなす。
	_mk_chara(dest, "06_abc", "id-abc\r\n192.0.2.15:20017\r\n")
	_mk_chara(src, "06_ABC", "id-other\r\n192.0.2.13:20017\r\n")
	var r3 := PhiCharacters.import_from(src, dest, [])
	check(int(r3["imported"]) == 0, "大小文字違いの同名も取り込まない")

	# existing_entries 経由の重複 (dest 以外の置き場にある分) も避ける。
	_mk_chara(src, "05_じろう", "id-jiro\r\n192.0.2.14:20017\r\n")
	var r4 := PhiCharacters.import_from(src, dest, [{"display_name": "05_じろう"}])
	check(int(r4["imported"]) == 0, "existing_entries の分もスキップ")

	_rm(BASE)
	print("test_stage29: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)
