extends SceneTree
## 第68段: (1) 9x9 を要求してもサーバが無応答 (地図フレーム
## 自体が来ない) な場合に、1.5 秒で見切って 7x7 へ送り直す
## ウォッチドッグ (第66段のフレーム駆動フォールバックの補完)。
## (2) パーサの行クリア精緻化: 大きさが変わっても、その
## フレームのキャラ行が既に届いていれば捨てない (クラシック
## 地図はキャラ行が地図行より先に来る)。

const Main := preload("res://scripts/main.gd")

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


func _m57_m() -> PackedByteArray:
	var b := PackedByteArray()
	b.append_array("#m57 M S 00000000:".to_ascii_buffer())
	for i in 49:
		b.append(0x2E)
		b.append(0x80)
	b.append(0x20)
	return b


func _m57_o(id: int, x: int, y: int, name: String, gra: String) -> PackedByteArray:
	var b := PackedByteArray()
	b.append_array(("#m57 O C%04x:%d %d %s " % [id, x, y, "B"]).to_ascii_buffer())
	b.append_array(_pad_bytes(name, 31))
	b.append_array(" 40 ".to_ascii_buffer())
	b.append_array(_pad_bytes(gra, 15))
	b.append_array(" # 40 ".to_ascii_buffer())
	return b


func _classic_m() -> PackedByteArray:
	var b := PackedByteArray()
	b.append_array("#map M W 00000000:".to_ascii_buffer())
	for i in 25:
		b.append(0x2E)
		b.append(0x2E)
	for i in 50:
		b.append(0x20)
	return b


func _classic_c(index: int, x: int, y: int, name: String, gra: String) -> PackedByteArray:
	var b := PackedByteArray()
	b.append_array(("#map C%02d:%d %d %s " % [index, x, y, "B"]).to_ascii_buffer())
	b.append_array(_pad_bytes(name, 31))
	b.append_array(" 40 ".to_ascii_buffer())
	b.append_array(_pad_bytes(gra, 15))
	b.append_array(" # 40 ".to_ascii_buffer())
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
	# --- (2) このフレームのキャラ行は大きさ変更でも捨てない ---
	var parser := PhiParser.new()
	var ev57 := _map_events(_feed_all(parser, [
		_m57_m(), _m57_o(1, 3, 3, "KURO", "elb_cat"), "#m57 .".to_ascii_buffer()]))
	check((ev57[0]["chars"] as Array).size() == 1, "m57 self row present")
	# クラシックはキャラ行が先に来る。他人の行は残り、前の
	# モードの自分行は混ざらない。
	var ev5 := _map_events(_feed_all(parser, [
		_classic_c(0, 0, 0, "OTHER", "t_man"), _classic_m(), "#map .".to_ascii_buffer()]))
	check((ev5[0]["chars"] as Array).size() == 1, "fresh classic row kept on size change")
	check(str(ev5[0]["chars"][0]["name"]) == "OTHER", "kept row is the fresh one")
	# 行が無ければ前のモードの行は残らない (第66段の再確認)
	var ev5b := _map_events(_feed_all(parser, [
		_m57_m(), _m57_o(1, 3, 3, "KURO", "elb_cat"), "#m57 .".to_ascii_buffer()]))
	check((ev5b[0]["chars"] as Array).size() == 1, "m57 self row again")
	var ev5c := _map_events(_feed_all(parser, [
		_classic_m(), "#map .".to_ascii_buffer()]))
	check((ev5c[0]["chars"] as Array).size() == 0, "stale rows cleared when no fresh rows")

	# --- Main を立てる (タブ復元は隔離) ---
	var main: Node = Main.new()
	var iso := ProjectSettings.globalize_path("user://stage68_tabs.ini")
	OS.execute("rm", ["-f", iso])
	main.set("_tab_session_path", "user://stage68_tabs.ini")
	root.add_child(main)
	await process_frame
	await process_frame
	var tab: Variant = main.call("_active_tab")
	var tsession: Variant = tab.get("session")

	# --- (1) ウォッチドッグ: 無応答なら 1.5 秒で 7x7 へ ---
	tsession.set("_state", "open")
	tsession.map_size = 81
	tab.set("_map_dim_now", 5)
	tab.set("_m81_fell_back", false)
	tab.call("_check_m81_watchdog", 100000)
	check(int(tsession.map_size) == 81, "watchdog armed only")
	tab.call("_check_m81_watchdog", 100000 + 1499)
	check(int(tsession.map_size) == 81, "watchdog not yet fired")
	tab.call("_check_m81_watchdog", 100000 + 1500)
	check(int(tsession.map_size) == 57, "watchdog fell back to 57")
	check(bool(tab.get("_m81_fell_back")) == true, "fallback latched")
	var queue: Array = tsession.get("_send_queue")
	check(not queue.is_empty() and str(queue[queue.size() - 1]) == "#ex-map size=57",
		"watchdog sent size=57 request")
	# 9x9 が届いている間は見切らない
	tab.set("_m81_fell_back", false)
	tsession.map_size = 81
	tab.set("_map_dim_now", 9)
	tab.call("_check_m81_watchdog", 200000)
	tab.call("_check_m81_watchdog", 200000 + 60000)
	check(int(tsession.map_size) == 81, "no fallback while 9x9 alive")
	tsession.set("_state", "idle")

	print("test_stage68: ", _checks, " checks, ", _failures, " failures")
	quit(1 if _failures > 0 else 0)
