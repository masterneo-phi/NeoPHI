extends SceneTree
## 第28段: Unew 取得の zip 優先。URL の .lzh → .zip 変換と、
## パネルの形式振り分け展開 (ZIP / LZH) を確認する。
##
## 使い方: godot --headless --path . -s tests/test_stage28.gd

var _checks := 0
var _failures := 0

const TEST_ZIP := "/home/hatch/workspace/unew-probe/test_pack.zip"
const RYUR_LZH := "/home/hatch/workspace/unew-probe/chip_ryur.lzh"


func check(cond: bool, label: String) -> void:
	_checks += 1
	if not cond:
		_failures += 1
		printerr("FAIL: ", label)


func _initialize() -> void:
	# -- zip 版 URL の変換 --
	check(PhiUnew.zip_twin_url("http://www.tofup.net/bgm_guran.lzh") == "http://www.tofup.net/bgm_guran.zip", "lzh → zip")
	check(PhiUnew.zip_twin_url("http://www.tofup.net/raphi/resist.lzh") == "http://www.tofup.net/raphi/resist.zip", "サブフォルダでも変換")
	check(PhiUnew.zip_twin_url("http://phi.netgamers.jp/grap/archive/PG.lzh") == "http://phi.netgamers.jp/grap/archive/PG.zip", "他ホストでも変換 (取れるかは別)")
	check(PhiUnew.zip_twin_url("http://example.com/PACK.LZH") == "http://example.com/PACK.zip", "大文字 .LZH も変換")
	check(PhiUnew.zip_twin_url("http://example.com/pack.zip") == "", "zip には zip 版なし")
	check(PhiUnew.zip_twin_url("http://example.com/pack") == "", "拡張子なしは対象外")

	# -- 形式の振り分け展開 --
	var panel := PhiUnewPanel.new([])
	var zip_bytes := FileAccess.get_file_as_bytes(TEST_ZIP)
	check(not zip_bytes.is_empty(), "テスト zip が読める")
	var report: Dictionary = panel.call("_extract_archive", zip_bytes, "http://example.com/test_pack.zip")
	check(bool(report.get("ok", false)), "zip が展開できる: " + str(report.get("error", "")))
	var files: Dictionary = report.get("files", {})
	check(files.size() == 2, "zip のファイルは 2 件 (フォルダは除く)")
	check((files.get("a.txt", PackedByteArray()) as PackedByteArray).get_string_from_utf8() == "hello zip", "a.txt の中身")
	check((files.get("sub/b.txt", PackedByteArray()) as PackedByteArray).get_string_from_utf8() == "nested world", "sub/b.txt の中身")

	var bad: Dictionary = panel.call("_extract_archive", zip_bytes, "http://example.com/test_pack.lzh")
	check(not bool(bad.get("ok", false)), "zip の中身を .lzh として読むと失敗する (振り分けは URL で決まる)")
	var garbage: Dictionary = panel.call("_extract_archive", PackedByteArray([1, 2, 3]), "http://example.com/x.zip")
	check(not bool(garbage.get("ok", false)), "壊れた zip は失敗する (フォールバック用)")

	var lzh_bytes := FileAccess.get_file_as_bytes(RYUR_LZH)
	var lzh_report: Dictionary = panel.call("_extract_archive", lzh_bytes, "http://www.tofup.net/chip_ryur.lzh")
	check(bool(lzh_report.get("ok", false)), "lzh も従来どおり展開できる")
	panel.free()

	print("test_stage28: ", _checks, " checks, ", _failures, " failures")
	quit(1 if _failures > 0 else 0)
