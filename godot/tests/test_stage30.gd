extends SceneTree
## 第30段: 看板エディタのプレビュー。
## ヘッダ (名前16バイト詰め + 日時) と46文字の区切り線が
## サーバの記事表示と同じ形になることを確かめる。

var _checks := 0
var _failures := 0


func check(cond: bool, label: String) -> void:
	_checks += 1
	if not cond:
		_failures += 1
		print("FAIL: ", label)


func _initialize() -> void:
	var when := {"year": 2026, "month": 11, "day": 16, "hour": 17, "minute": 20, "second": 53}
	var t1 := PhiMEditWindow.preview_text("02_Enigma", "本文です", when)
	var lines := t1.split("\n")
	check(lines.size() == 3, "3行になる")
	check(lines[0] == "02_Enigma       (2026/11/16 17:20:53)", "英字名は16バイトに詰める: [%s]" % lines[0])
	check(lines[1] == "-".repeat(46) and lines[1].length() == 46, "区切りは46文字")
	check(lines[2] == "本文です", "本文が続く")
	# 日本語名は cp932 のバイト数で詰める (5文字=10バイト→6つの空白)
	var t2 := PhiMEditWindow.preview_text("モック太郎", "", when)
	check(t2.split("\n")[0] == "モック太郎      (2026/11/16 17:20:53)", "日本語名もバイト詰め: [%s]" % t2.split("\n")[0])
	# 16バイトを超える名前は詰めも切りもしない
	var long_name := "ABCDEFGHIJKLMNOPQ"
	var t3 := PhiMEditWindow.preview_text(long_name, "x", when)
	check(t3.split("\n")[0] == long_name + "(2026/11/16 17:20:53)", "長い名前はそのまま")

	# 窓: 開くとヘッダだけのプレビュー、打つと本文が付く
	var win := PhiMEditWindow.new()
	root.add_child(win)
	win.show_editor("モック太郎")
	var preview: RichTextLabel = win.get("_preview")
	check(preview.text.contains("(20"), "開いた時点でヘッダが出る")
	check(preview.text.contains("-".repeat(46)), "開いた時点で区切りが出る")
	# 本文を入れて text_changed を発火 (代入だけでは出ないため。
	# 実機では打鍵で発火する)
	var edit := win.get("_edit") as TextEdit
	edit.text = "こんにちは"
	edit.text_changed.emit()
	check(preview.text.ends_with("こんにちは"), "入力がプレビューに反映される")
	check(win.min_size == Vector2i(640, 440), "最小サイズ")
	win.close_silent()
	print("test_stage30: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)
