extends SceneTree
## 第27段: 5x5(クラシック地図)の #map C 解析と自分の合成、
## LZH レベル 1 拡張ヘッダ (bgm_guran.lzh)、新規作成ダイアログの
## ドラッグを確認する。
##
## 使い方: godot --headless --path . -s tests/test_stage27.gd

var _checks := 0
var _failures := 0

const GURAN_LZH := "/home/hatch/workspace/unew-probe/bgm_guran.lzh"


func check(cond: bool, label: String) -> void:
	_checks += 1
	if not cond:
		_failures += 1
		printerr("FAIL: ", label)


func _initialize() -> void:
	_test_map_c()
	_test_lzh_level1()
	_test_classic_self()
	_finish_with_drag()


func _finish_with_drag() -> void:
	await _test_register_drag()
	print("test_stage27: ", _checks, " checks, ", _failures, " failures")
	quit(1 if _failures > 0 else 0)


func _wait(sec: float) -> void:
	var until := Time.get_ticks_msec() + int(sec * 1000.0)
	while Time.get_ticks_msec() < until:
		await process_frame


# -- #map C の解析 ---------------------------------------------------------------

func _classic_m() -> PackedByteArray:
	var b := PackedByteArray()
	b.append_array("#map M W 00000000:".to_ascii_buffer())
	for i in 25:
		b.append(0x2E) # '.'
		b.append(0x2E)
	for i in 50:
		b.append(0x20)
	return b


func _pad_bytes(text: String, width: int) -> PackedByteArray:
	## cp932 のバイト数で幅に合わせる (サーバの %-31s と同じ)。
	var b := Cp932.encode(text)
	while b.size() < width:
		b.append(0x20)
	return b


func _classic_c(index: int, x: int, y: int, dir_ch: String, name: String, status: int, gra: String, default: int) -> PackedByteArray:
	var b := PackedByteArray()
	b.append_array(("#map C%02d:%d %d %s " % [index, x, y, dir_ch]).to_ascii_buffer())
	b.append_array(_pad_bytes(name, 31))
	b.append_array((" %02x " % status).to_ascii_buffer())
	b.append_array(_pad_bytes(gra, 15))
	b.append_array((" # %02x " % default).to_ascii_buffer())
	return b


func _feed_all(parser: PhiParser, lines: Array) -> Array:
	var events: Array = []
	for line in lines:
		events.append_array(parser.feed(line))
	return events


func _test_map_c() -> void:
	var parser := PhiParser.new()
	var events := _feed_all(parser, [
		_classic_m(),
		_classic_c(0, 1, 4, "L", "Human", 0, "", 1),
		_classic_c(1, 2, 2, "F", "モック猫", 0, "t_catW", 5),
		"#map .".to_ascii_buffer(),
	])
	check(events.size() == 1, "#map 一式で地図イベント 1 つ")
	if events.size() != 1:
		return
	var ev: Dictionary = events[0]
	check(int(ev.get("size", 0)) == 5, "size は 5")
	check(int(ev.get("dir", -1)) == 6, "向きは W = 6")
	check((ev.get("cells", []) as Array).size() == 25, "セルは 25")
	var chars: Array = ev.get("chars", [])
	check(chars.size() == 2, "キャラは 2 件 (C 行から)")
	if chars.size() == 2:
		var h: Dictionary = chars[0]
		check(str(h.get("name", "")) == "Human" and int(h.get("x", -1)) == 1 and int(h.get("y", -1)) == 4
			and str(h.get("dir", "")) == "L" and int(h.get("default", -1)) == 1, "C00 の欄が合う")
		var c: Dictionary = chars[1]
		check(str(c.get("name", "")) == "モック猫" and str(c.get("gra", "")) == "t_catW"
			and int(c.get("layer", -1)) == 1, "C01 の欄が合う (日本語名・グラ)")
	# 次のフレームでは C 行の分だけに置き換わる (前の分が残らない)
	var events2 := _feed_all(parser, [
		_classic_m(),
		_classic_c(0, 3, 3, "R", "案内人", 0, "t_Residents", 5),
		"#map .".to_ascii_buffer(),
	])
	check(events2.size() == 1 and (events2[0].get("chars", []) as Array).size() == 1,
		"次フレームでキャラが置き換わる")


# -- LZH レベル 1 (拡張ヘッダ付き) -------------------------------------------------

func _test_lzh_level1() -> void:
	var data := FileAccess.get_file_as_bytes(GURAN_LZH)
	check(not data.is_empty(), "bgm_guran.lzh が読める")
	if data.is_empty():
		return
	var report := PhiLzh.extract_report(data)
	check(bool(report["ok"]), "レベル 1 + 拡張ヘッダのアーカイブが展開できる: " + str(report["error"]))
	var files: Dictionary = report["files"]
	check(files.size() == 26, "エントリは 26 件")
	var mid: PackedByteArray = files.get("bgm/01_crying.mid", PackedByteArray())
	check(mid.size() == 3759 and mid.slice(0, 4).get_string_from_ascii() == "MThd",
		"bgm/01_crying.mid の中身が合う")


# -- 5x5 の自分の合成 --------------------------------------------------------------

func _test_classic_self() -> void:
	var tab := PhiCharacter.new()
	tab.set("_player_name", "モック太郎")
	# 7x7 のフレームで自分のグラを覚える
	tab.call("_learn_self_gra", {"chars": [
		{"name": "モック太郎", "gra": "t_Lord"},
		{"name": "案内人", "gra": "t_Residents"},
	]})
	check(str(tab.get("_self_gra")) == "t_Lord", "自分のグラを覚える")
	# 5x5: 自分が居なければ (2, 3) に合成する
	var ev := {"size": 5, "chars": [{"name": "案内人", "gra": "t_Residents", "x": 3, "y": 3, "dir": "L"}]}
	tab.call("_fixup_classic_self", ev)
	var chars: Array = ev["chars"]
	check(chars.size() == 2, "5x5 で自分が足される")
	if chars.size() == 2:
		var me: Dictionary = chars[1]
		check(int(me.get("x", -1)) == 2 and int(me.get("y", -1)) == 3 and str(me.get("dir", "")) == "B"
			and str(me.get("name", "")) == "モック太郎" and str(me.get("gra", "")) == "t_Lord",
			"合成した自分は (2,3) 向き B で覚えたグラ")
	# 5x5: 名前欄が空の自分行 (旧クライアント向け) は名前に直す
	var ev2 := {"size": 5, "chars": [{"name": "", "gra": "t_Lord", "x": 2, "y": 3, "dir": "B"}]}
	tab.call("_fixup_classic_self", ev2)
	var chars2: Array = ev2["chars"]
	check(chars2.size() == 1 and str((chars2[0] as Dictionary).get("name", "")) == "モック太郎",
		"名前なしの自分行は自分の名前に直る")
	tab.free()


# -- 新規作成ダイアログのドラッグ ----------------------------------------------------

func _find_drag_handle(node: Node) -> Control:
	if node is Control and (node as Control).has_meta("phi_window_drag"):
		return node as Control
	for child in node.get_children():
		var found := _find_drag_handle(child)
		if found != null:
			return found
	return null


func _test_register_drag() -> void:
	var ps := load("res://main.tscn") as PackedScene
	var main: Node = ps.instantiate()
	root.add_child(main)
	await _wait(1.2)
	main.call("_show_register_dialog")
	await _wait(0.5)
	var dlg: Window = main.get("_register_dialog")
	check(dlg != null and dlg.visible, "新規作成ダイアログが開く")
	if dlg == null:
		main.queue_free()
		return
	var band := _find_drag_handle(dlg)
	check(band != null, "題名の帯にドラッグハンドルが付いている")
	if band != null:
		var drag: PhiWindowDrag = band.get_meta("phi_window_drag")
		var start := dlg.position
		var press := InputEventMouseButton.new()
		press.button_index = MOUSE_BUTTON_LEFT
		press.pressed = true
		press.position = Vector2(10, 10)
		drag._on_gui_input(press)
		var motion := InputEventMouseMotion.new()
		motion.relative = Vector2(18, 11)
		drag._on_gui_input(motion)
		check(dlg.position == start + Vector2i(18, 11), "帯のドラッグで窓が動く")
	dlg.hide()
	main.queue_free()
