extends SceneTree
## 第41段: 11x11 マップモード (#ex-map size=121 / #m121)。
## パーサが #m81 フレーム (旧サーバ互換の受信) を解釈すること、設定の
## 121 往復と旧 81 からの移行、アクションとログイン行の配線を見る。

var _checks := 0
var _failures := 0


func check(cond: bool, label: String) -> void:
	_checks += 1
	if not cond:
		_failures += 1
		print("FAIL: ", label)


func _initialize() -> void:
	_run.call_deferred()


func _pad_bytes(text: String, width: int) -> PackedByteArray:
	var b := Cp932.encode(text)
	while b.size() < width:
		b.append(0x20)
	return b


func _m81_m() -> PackedByteArray:
	var b := PackedByteArray()
	b.append_array("#m81 M N 00000000:".to_ascii_buffer())
	for i in 81:
		b.append(i) # chip: 0..80
		b.append(0x80 | (i % 4)) # attr
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


func _m81_o(id: int, x: int, y: int, dir_ch: String, name: String, status: int, gra: String, gigant: String, default: int) -> PackedByteArray:
	var b := PackedByteArray()
	b.append_array(("#m81 O C%04x:%d %d %s " % [id, x, y, dir_ch]).to_ascii_buffer())
	b.append_array(_pad_bytes(name, 31))
	b.append_array((" %02x " % status).to_ascii_buffer())
	b.append_array(_pad_bytes(gra, 15))
	b.append_array((" %s %02x " % [gigant, default]).to_ascii_buffer())
	return b


func _feed_all(parser: PhiParser, lines: Array) -> Array:
	var events: Array = []
	for line in lines:
		events.append_array(parser.feed(line))
	return events


func _run() -> void:
	# (1) #m81 フレームの解釈
	var parser := PhiParser.new()
	var events := _feed_all(parser, [
		_m81_m(),
		_m81_o(3, 8, 0, "F", "Hero", 0, "elb_cat", "*", 0x40),
		"#m81 .".to_ascii_buffer(),
	])
	var maps := events.filter(func(e): return str(e.get("type", "")) == "map")
	check(maps.size() == 1, "m81: one map event")
	if maps.size() == 1:
		var ev: Dictionary = maps[0]
		check(int(ev.get("size", 0)) == 9, "m81: size == 9")
		check(int(ev.get("dir", -1)) == 0, "m81: dir N == 0")
		var cells: Array = ev.get("cells", [])
		check(cells.size() == 81, "m81: 81 cells")
		if cells.size() == 81:
			check(int(cells[0].get("chip", -1)) == 0 and int(cells[0].get("attr", -1)) == 0x80, "m81: cell 0")
			check(int(cells[80].get("chip", -1)) == 80 and int(cells[80].get("attr", -1)) == 0x80, "m81: cell 80")
			check(int(cells[41].get("chip", -1)) == 41 and int(cells[41].get("attr", -1)) == 0x81, "m81: cell 41 (center)")
		var chars: Array = ev.get("chars", [])
		check(chars.size() == 1, "m81: one char")
		if chars.size() == 1:
			check(int(chars[0].get("x", -1)) == 8 and int(chars[0].get("y", -1)) == 0, "m81: char at (8,0)")
			check(str(chars[0].get("name", "")) == "Hero", "m81: char name")
			check(str(chars[0].get("gra", "")) == "elb_cat", "m81: char gra")
			check(str(chars[0].get("gigant", "")) == "*", "m81: char gigant")
			check(str(chars[0].get("dir", "")) == "F", "m81: char dir")

	# (2) #m57 は従来通り size=7 (回帰)
	var parser57 := PhiParser.new()
	var events57 := _feed_all(parser57, [_m57_m(), "#m57 .".to_ascii_buffer()])
	var maps57 := events57.filter(func(e): return str(e.get("type", "")) == "map")
	check(maps57.size() == 1 and int(maps57[0].get("size", 0)) == 7, "m57 regression: size == 7")
	check(maps57.size() == 1 and (maps57[0].get("cells", []) as Array).size() == 49, "m57 regression: 49 cells")

	# (3) MapView.grid_dim
	check(MapView.grid_dim(9) == 9, "grid_dim(9) == 9")
	check(MapView.grid_dim(7) == 7, "grid_dim(7) == 7")
	check(MapView.grid_dim(5) == 5, "grid_dim(5) == 5")
	check(MapView.grid_dim(57) == 7, "grid_dim(57) falls back to 7")

	# (4) アクション定義とメニュー・ツールバー・キー
	var def: Dictionary = PhiActions.get_action("M11x11")
	check(str(def.get("send", "")) == "#ex-map size=121", "M11x11 sends size=121")
	check(str(def.get("caption", "")).begins_with("11x11"), "M11x11 caption")
	var disp_items: Array = []
	for menu in PhiActions.MENUS:
		if str(menu.get("name", "")) == "表示":
			disp_items = menu.get("items", [])
	check(disp_items.has("M11x11"), "M11x11 in Disp menu")
	check(not disp_items.has("M9x9"), "M9x9 removed from Disp menu")
	check(PhiActions.TOOLBAR.has("M11x11"), "M11x11 in toolbar")
	check(PhiActions.accelerator_for("M11x11") == 0, "M11x11 accelerator removed (stage111)")

	# (5) ログイン行
	var lines := PhiSession.login_lines("someid", 121, "solid")
	check(lines.has("#ex-map size=121"), "login lines carry size=121")
	var reg := PhiSession.post_register_lines(121, "turn")
	check(reg.has("#ex-map size=121"), "post-register lines carry size=121")

	# (6) 設定の往復 (MapSize=121 が保存・復元できる)
	var path := OS.get_temp_dir().path_join("neophi_stage41_config.ini")
	var cfg := PhiConfig.new()
	cfg.map_size = 121
	check(cfg.save_file(path), "config save")
	var cfg2 := PhiConfig.new()
	check(cfg2.load_file(path), "config load")
	check(cfg2.map_size == 121, "config roundtrip keeps 121")
	DirAccess.remove_absolute(path)
	# 旧 81 (9x9) の設定は仕様削除に伴い 121 で読み戻される
	cfg.map_size = 81
	check(cfg.save_file(path), "config save (old 81)")
	var cfg3 := PhiConfig.new()
	check(cfg3.load_file(path), "config load (old 81)")
	check(cfg3.map_size == 121, "old 81 config migrates to 121")
	DirAccess.remove_absolute(path)

	# (7) 既定は 11x11 (新規設定では MapSize=121)
	check(PhiConfig.new().map_size == 121, "fresh config defaults to 121")
	check(PhiSession.new().map_size == 121, "fresh session defaults to 121")

	# (8) 未対応サーバへのフォールバック (第68段改): 121 を試して
	# 応答が無ければ数回送り直し、それでも来なければその接続
	# だけ 7x7 に落とす。実タブ (main シーン) で見る。
	var ps := load("res://main.tscn") as PackedScene
	var main: Node = ps.instantiate()
	root.add_child(main)
	await create_timer(1.0).timeout
	var tab: PhiCharacter = main.call("_active_tab")
	tab.session.set("_state", "open")
	tab.session.map_size = 121
	tab.set("_bigmap_fell_back", false)
	tab.set("_bigmap_attempts", 0)
	tab.set("_bigmap_watch_since", 0)
	tab.set("_map_dim_now", 7)
	tab.call("_check_bigmap_watchdog", 5000)
	tab.call("_check_bigmap_watchdog", 6500)
	check(tab.session.map_size == 121, "fallback: first timeout resends 121")
	tab.call("_check_bigmap_watchdog", 8000)
	tab.call("_check_bigmap_watchdog", 9500)
	check(tab.session.map_size == 121, "fallback: second timeout still trying")
	tab.call("_check_bigmap_watchdog", 11000)
	tab.call("_check_bigmap_watchdog", 12500)
	check(tab.session.map_size == 57, "fallback: gives up to 57")
	check(bool(tab.get("_bigmap_fell_back")), "fallback: flag set")
	# 11x11 が届いている間は諦めない
	tab.set("_bigmap_fell_back", false)
	tab.set("_bigmap_attempts", 0)
	tab.set("_bigmap_watch_since", 0)
	tab.session.map_size = 121
	tab.set("_map_dim_now", 11)
	tab.call("_check_bigmap_watchdog", 20000)
	tab.call("_check_bigmap_watchdog", 20000 + 60000)
	check(tab.session.map_size == 121, "fallback: size 11 keeps 121")
	tab.session.set("_state", "idle")
	main.queue_free()

	print("stage41: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)
