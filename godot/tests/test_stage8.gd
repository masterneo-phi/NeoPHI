extends SceneTree
## 第8段のテスト: Unew 方式の取得機構の中核。
## unew.ini の読解(実物)、exOption の解釈、状態判定、取得記録の往復、
## LZH の一覧と展開(実アーカイブ chip_ryur.lzh を既知の正解 BMP と照合)、
## 合成した -lh0- レベル 0 アーカイブ、壊れたデータの扱い、パネルの生成。
##
## 使い方: godot --headless --path . -s tests/test_stage8.gd
## 終了コード 0 = 全一致、1 = 不一致あり。

var _failures := 0
var _checks := 0

const UNEW_INI := "/home/hatch/workspace/phi-option-data/unew.ini"
const RYUR_LZH := "/home/hatch/workspace/unew-probe/chip_ryur.lzh"
const RYUR_DIR := "/home/hatch/workspace/phi-option-data/chip_ryur"
const OPTION_DATA := "/home/hatch/workspace/phi-option-data"


func _check(cond: bool, label: String) -> void:
	_checks += 1
	if not cond:
		failures_add(label)


func _check_eq(a: Variant, b: Variant, label: String) -> void:
	_checks += 1
	if a != b:
		failures_add(label + " (got " + str(a) + ", want " + str(b) + ")")


func failures_add(label: String) -> void:
	_failures += 1
	printerr("FAIL: ", label)


func _initialize() -> void:
	_test_crc16()
	_test_dest_dir()
	_test_unew_parse()
	_test_status()
	_test_lzh_list()
	_test_lzh_extract()
	_test_lzh_store_level0()
	_test_lzh_errors()
	_test_panel()
	print("test_stage8: ", _checks, " checks, ", _failures, " failures")
	quit(1 if _failures > 0 else 0)


func _item_by_file(items: Array, file_name: String) -> Dictionary:
	for item_var in items:
		var item: Dictionary = item_var
		if PhiUnew.url_file_name(str(item["url"])) == file_name:
			return item
	return {}


# -- CRC16 ----------------------------------------------------------------------

func _test_crc16() -> void:
	# CRC-16/ARC の検査値(初期値 0、反射多項式 0xA001。LHA の CRC と同じ)。
	_check_eq(PhiLzh.crc16("123456789".to_ascii_buffer()), 0xBB3D, "crc16 check value")
	_check_eq(PhiLzh.crc16(PackedByteArray()), 0, "crc16 empty")


# -- exOption の解釈 --------------------------------------------------------------

func _test_dest_dir() -> void:
	_check_eq(PhiUnew.dest_dir_from_ex_option("-m1 chip\\ *.*"), "chip", "dest chip")
	_check_eq(PhiUnew.dest_dir_from_ex_option("-m1 chara\\ *.*"), "chara", "dest chara")
	_check_eq(PhiUnew.dest_dir_from_ex_option("-m1 sound\\bgm\\ *.*"), "sound/bgm", "dest bgm")
	_check_eq(PhiUnew.dest_dir_from_ex_option("-m1 Config\\ *.*"), "config", "dest lowercase")
	_check_eq(PhiUnew.dest_dir_from_ex_option("-m1"), "", "dest none")
	_check_eq(PhiUnew.dest_dir_from_ex_option(""), "", "dest empty")
	_check_eq(PhiUnew.url_file_name("http://www.tofup.net/chip_ryur.lzh"), "chip_ryur.lzh", "url file name")
	_check_eq(PhiUnew.url_file_name("http://www.tofup.net/raphi/resist.lzh"), "resist.lzh", "url file name subdir")


# -- unew.ini(実物)の読解 ---------------------------------------------------------

func _test_unew_parse() -> void:
	var data := FileAccess.get_file_as_bytes(UNEW_INI)
	_check(not data.is_empty(), "unew.ini fixture exists")
	if data.is_empty():
		return
	var items := PhiUnew.parse_items(SkinFiles.decode_text_file(data))
	_check_eq(items.size(), 13, "unew item count")
	if items.size() != 13:
		return
	_check_eq(str(items[0]["id"]), "Schedule3", "unew first id")
	var ryur := _item_by_file(items, "chip_ryur.lzh")
	_check_eq(str(ryur.get("id", "")), "Schedule5", "ryur id")
	_check_eq(str(ryur.get("title", "")), "マップチップ(Ryur)", "ryur title")
	_check_eq(str(ryur.get("date", "")), "Sat, 07 Oct 2006 14:12:17 GMT", "ryur date")
	_check_eq(str(ryur.get("ex_option", "")), "-m1 chip\\ *.*", "ryur ex_option")
	_check_eq(str(ryur.get("dest_dir", "")), "chip", "ryur dest_dir")
	var bgm := _item_by_file(items, "bgm_tofup.lzh")
	_check_eq(str(bgm.get("id", "")), "Schedule14", "bgm id")
	_check_eq(str(bgm.get("title", "")), "音楽(Tofup)", "bgm title")
	_check_eq(str(bgm.get("dest_dir", "")), "sound/bgm", "bgm dest_dir")
	var resist := _item_by_file(items, "resist.lzh")
	_check_eq(str(resist.get("id", "")), "Schedule15", "resist id")
	_check_eq(str(resist.get("title", "")), "新規接続設定ファイル", "resist title")
	_check_eq(str(resist.get("dest_dir", "")), "", "resist dest_dir root")
	var pg := _item_by_file(items, "PG.lzh")
	_check_eq(str(pg.get("id", "")), "Schedule10", "pg id")
	_check_eq(str(pg.get("dest_dir", "")), "chara", "pg dest_dir")


# -- 状態判定と記録 -----------------------------------------------------------------

func _test_status() -> void:
	var item := {"id": "Schedule5", "title": "t", "url": "http://www.tofup.net/chip_ryur.lzh", "date": "D1", "memo": "", "ex_option": "", "dest_dir": "chip"}
	var record := {}
	_check_eq(PhiUnew.status_of(item, record), PhiUnew.Status.NOT_DOWNLOADED, "status none")
	_check_eq(PhiUnew.status_text(PhiUnew.Status.NOT_DOWNLOADED), "", "status text none")
	PhiUnew.mark_downloaded(record, item)
	_check_eq(record, {"chip_ryur.lzh": "D1"}, "record keyed by file name")
	_check_eq(PhiUnew.status_of(item, record), PhiUnew.Status.UP_TO_DATE, "status up to date")
	_check_eq(PhiUnew.status_text(PhiUnew.Status.UP_TO_DATE), "取得済み", "status text up to date")
	var newer := item.duplicate()
	newer["date"] = "D2"
	_check_eq(PhiUnew.status_of(newer, record), PhiUnew.Status.UPDATE_AVAILABLE, "status update")
	_check_eq(PhiUnew.status_text(PhiUnew.Status.UPDATE_AVAILABLE), "新しい版があります", "status text update")
	# 記録の保存と読み戻し。
	var path := "/tmp/neophi-stage8-record.json"
	_check(PhiUnew.save_record(record, path), "record save")
	_check_eq(PhiUnew.load_record(path), record, "record roundtrip")
	_check_eq(PhiUnew.load_record("/tmp/neophi-stage8-no-such.json"), {}, "record missing is empty")


# -- LZH: 一覧 ----------------------------------------------------------------------

func _test_lzh_list() -> void:
	var data := FileAccess.get_file_as_bytes(RYUR_LZH)
	_check(not data.is_empty(), "chip_ryur.lzh fixture exists")
	if data.is_empty():
		return
	var entries := PhiLzh.list_entries(data)
	_check_eq(entries.size(), 3, "lzh entry count")
	if entries.size() != 3:
		return
	var names: Array = []
	var methods: Array = []
	var csizes: Array = []
	var osizes: Array = []
	var crcs: Array = []
	var levels: Array = []
	for e in entries:
		var entry: Dictionary = e
		names.append(str(entry["name"]))
		methods.append(str(entry["method"]))
		csizes.append(int(entry["compressed_size"]))
		osizes.append(int(entry["original_size"]))
		crcs.append(int(entry["crc"]))
		levels.append(int(entry["header_level"]))
	_check_eq(names, ["MapChip/nightmare.bmp", "MapChip/ryur.bmp", "MapChip/town_v.bmp"], "lzh names")
	_check_eq(methods, ["-lh5-", "-lh5-", "-lh5-"], "lzh methods")
	_check_eq(csizes, [16457, 14768, 15220], "lzh compressed sizes")
	_check_eq(osizes, [99382, 99382, 99382], "lzh original sizes")
	_check_eq(crcs, [0x4F8A, 0x257C, 0x4734], "lzh crcs")
	_check_eq(levels, [2, 2, 2], "lzh header levels")


# -- LZH: 展開(正解 BMP とバイト照合) -------------------------------------------------

func _test_lzh_extract() -> void:
	var data := FileAccess.get_file_as_bytes(RYUR_LZH)
	if data.is_empty():
		_check(false, "chip_ryur.lzh fixture exists (extract)")
		return
	var report := PhiLzh.extract_report(data)
	_check(bool(report["ok"]), "extract ok: " + str(report["error"]))
	if not bool(report["ok"]):
		return
	var files: Dictionary = report["files"]
	_check_eq(files.size(), 3, "extract file count")
	for base in ["nightmare.bmp", "ryur.bmp", "town_v.bmp"]:
		var key: String = "MapChip/" + base
		_check(files.has(key), "extract has " + key)
		if not files.has(key):
			continue
		var got: PackedByteArray = files[key]
		var ref := FileAccess.get_file_as_bytes(RYUR_DIR.path_join(base))
		_check_eq(got.size(), ref.size(), "extract size " + base)
		_check(got == ref, "extract bytes " + base)
	# extract() でも同じ結果になる。
	_check_eq(PhiLzh.extract(data).size(), 3, "extract() file count")


# -- LZH: 合成 -lh0- レベル 0 ---------------------------------------------------------

func _make_store_archive(name_bytes: PackedByteArray, payload: PackedByteArray) -> PackedByteArray:
	var crc := PhiLzh.crc16(payload)
	var header := PackedByteArray()
	header.append(22 + name_bytes.size()) # ヘッダサイズ - 2
	header.append(0) # チェックサム(後で入れる)
	header.append_array("-lh0-".to_ascii_buffer())
	for v in [payload.size(), payload.size()]:
		header.append(v & 0xFF)
		header.append((v >> 8) & 0xFF)
		header.append((v >> 16) & 0xFF)
		header.append((v >> 24) & 0xFF)
	header.append_array(PackedByteArray([0, 0, 0, 0])) # 時刻
	header.append(0x20) # 属性
	header.append(0) # レベル 0
	header.append(name_bytes.size())
	header.append_array(name_bytes)
	header.append(crc & 0xFF)
	header.append((crc >> 8) & 0xFF)
	var sum := 0
	for i in range(2, header.size()):
		sum = (sum + header[i]) & 0xFF
	header[1] = sum
	header.append_array(payload)
	header.append(0) # 終端
	return header


func _test_lzh_store_level0() -> void:
	var payload := "Hello, NeoPHI!".to_ascii_buffer()
	var arc := _make_store_archive("test.txt".to_ascii_buffer(), payload)
	var entries := PhiLzh.list_entries(arc)
	_check_eq(entries.size(), 1, "store entry count")
	if entries.size() == 1:
		_check_eq(str(entries[0]["method"]), "-lh0-", "store method")
		_check_eq(int(entries[0]["header_level"]), 0, "store level 0")
	var files := PhiLzh.extract(arc)
	_check_eq(files.size(), 1, "store extract count")
	if files.has("test.txt"):
		var got: PackedByteArray = files["test.txt"]
		_check(got == payload, "store payload bytes")
	# "\" 区切りの名前は "/" に直される。
	var arc2 := _make_store_archive("sub\\inner.bin".to_ascii_buffer(), payload)
	var files2 := PhiLzh.extract(arc2)
	_check(files2.has("sub/inner.bin"), "store subdir name normalized")


# -- LZH: 壊れたデータ ------------------------------------------------------------------

func _test_lzh_errors() -> void:
	var junk := "this is not an lzh archive at all........".to_ascii_buffer()
	_check(not bool(PhiLzh.extract_report(junk)["ok"]), "junk is error")
	_check_eq(PhiLzh.extract(junk), {}, "junk extract empty")
	var data := FileAccess.get_file_as_bytes(RYUR_LZH)
	if not data.is_empty():
		var truncated := data.slice(0, 100)
		_check(not bool(PhiLzh.extract_report(truncated)["ok"]), "truncated is error")


# -- パネル ---------------------------------------------------------------------------

func _test_panel() -> void:
	var panel := PhiUnewPanel.new([OPTION_DATA])
	_check_eq(panel.item_count(), 13, "panel item count")
	_check_eq(panel.base_root(), OPTION_DATA, "panel base root")
	panel.free()
