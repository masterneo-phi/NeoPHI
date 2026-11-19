extends SceneTree
## 第114段: 11x11 マッププロトコル (#m121) のクライアント対応。
## サーバ (PHIDM_NEO 実験版) が #ex-map size=121 に応えて送る
## #m121 M / #m121 O / #m121 . をパーサが読み、地図ビューが
## 11x11 で描けることを確かめる。O 行の座標は 2 桁 (10) に
## なることがあるのが 9x9 までとの違い。

var _checks := 0
var _failures := 0


func check(cond: bool, label: String) -> void:
	_checks += 1
	if not cond:
		_failures += 1
		print("FAIL: ", label)


func _pad_bytes(text: String, width: int) -> PackedByteArray:
	var b := Cp932.encode(text)
	while b.size() < width:
		b.append(0x20)
	return b


func _m121_m() -> PackedByteArray:
	var b := PackedByteArray()
	b.append_array("#m121 M S 00000000:".to_ascii_buffer())
	for i in 121:
		b.append(0x2E)
		b.append(0x80)
	b.append(0x20)
	return b


func _m121_o(id: int, x: int, y: int, name: String, gra: String) -> PackedByteArray:
	var b := PackedByteArray()
	b.append_array(("#m121 O C%04x:%d %d %s " % [id, x, y, "B"]).to_ascii_buffer())
	b.append_array(_pad_bytes(name, 31))
	b.append_array(" 40 ".to_ascii_buffer())
	b.append_array(_pad_bytes(gra, 15))
	b.append_array(" # 40 ".to_ascii_buffer())
	return b


func _m81_m() -> PackedByteArray:
	var b := PackedByteArray()
	b.append_array("#m81 M S 00000000:".to_ascii_buffer())
	for i in 81:
		b.append(0x2E)
		b.append(0x80)
	b.append(0x20)
	return b


func _feed_all(parser: PhiParser, lines: Array) -> Array:
	var events: Array = []
	for line in lines:
		events.append_array(parser.feed(line))
	return events


func _map_events(events: Array) -> Array:
	var out: Array = []
	for e in events:
		if str(e.get("type", "")) == "map":
			out.append(e)
	return out


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	# --- M フレーム: 121 セル・大きさ 11 ・方向が読める ---
	var parser := PhiParser.new()
	var ev := _map_events(_feed_all(parser, [
		_m121_m(), "#m121 .".to_ascii_buffer()]))
	check(ev.size() == 1, "m121 map event arrives")
	if ev.size() == 1:
		check(int(ev[0]["size"]) == 11, "m121 size is 11: %s" % str(ev[0]["size"]))
		check((ev[0]["cells"] as Array).size() == 121, "m121 cells are 121")
		check(int(ev[0]["dir"]) == 4, "m121 dir S is 4: %s" % str(ev[0]["dir"]))

	# --- O 行: 2 桁座標 (10,10) と 1 桁座標 (5,5) が両方読める ---
	var parser2 := PhiParser.new()
	var ev2 := _map_events(_feed_all(parser2, [
		_m121_m(),
		_m121_o(7, 10, 10, "EDGE", "t_man"),
		_m121_o(1, 5, 5, "SELF", "human"),
		"#m121 .".to_ascii_buffer()]))
	check(ev2.size() == 1, "m121 map event with chars")
	if ev2.size() == 1:
		var chars := ev2[0]["chars"] as Array
		check(chars.size() == 2, "m121 chars are 2: %d" % chars.size())
		if chars.size() == 2:
			check(int(chars[0]["x"]) == 10 and int(chars[0]["y"]) == 10,
				"m121 two-digit coords: %s,%s" % [str(chars[0]["x"]), str(chars[0]["y"])])
			check(str(chars[0]["name"]) == "EDGE", "m121 two-digit name")
			check(str(chars[0]["gra"]) == "t_man", "m121 two-digit gra")
			check(int(chars[1]["x"]) == 5 and int(chars[1]["y"]) == 5,
				"m121 one-digit coords")
			check(str(chars[1]["name"]) == "SELF", "m121 one-digit name")

	# --- 9x9 から 11x11 への切り替え ---
	var parser3 := PhiParser.new()
	var ev3a := _map_events(_feed_all(parser3, [
		_m81_m(), "#m81 .".to_ascii_buffer()]))
	var ev3b := _map_events(_feed_all(parser3, [
		_m121_m(), "#m121 .".to_ascii_buffer()]))
	check(ev3a.size() == 1 and int(ev3a[0]["size"]) == 9, "m81 still 9")
	check(ev3b.size() == 1 and int(ev3b[0]["size"]) == 11, "switch to 11")

	# --- 地図ビューの格子数 ---
	check(MapView.grid_dim(11) == 11, "grid_dim(11) is 11")
	check(MapView.grid_dim(9) == 9, "grid_dim(9) unchanged")
	check(MapView.grid_dim(7) == 7, "grid_dim(7) unchanged")

	print("test_stage114: ", _checks, " checks, ", _failures, " failures")
	quit(1 if _failures > 0 else 0)
