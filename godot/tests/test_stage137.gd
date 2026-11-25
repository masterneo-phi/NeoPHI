extends SceneTree
## 第137段: phidm-v6 プロトコル対応 (段階0+1)。
##
## - 検出プローブ (`#ex-map view=` / `#ex-switch move=diag`) と返事の解釈
## - `#v6 M/R/O/.` 可変フレームの受信 (MapView の (w,h) 一般化)
## - `#v6 G/J` 移動返事、`#v6 H/E/W/T/P/L/K/S/I/B/Q` の情報系
## - マップセット16枠 (`#v6 D` / A 行の枠番号)
## - 従来フレーム (m57 golden) で v6 イベントが出ないこと
##
## 検証は phidm-v6 の test/replay の golden (実サーバの実バイト列)
## をパーサへ流して行う。golden の1行は "<tick> <a|b> <行>" で、
## 先頭が '+' の行はクライアントの送信、それ以外がサーバの送信。
##
## 使い方: godot --headless --path . -s tests/test_stage137.gd
## 終了コード 0 = 全一致、1 = 不一致あり。

const GOLDEN_DIR := "/home/hatch/workspace/phidm_v6_analysis/phidm-v6-main/test/replay/golden/"

var _checks := 0
var _failures := 0


func check(cond: bool, label: String) -> void:
	_checks += 1
	if not cond:
		_failures += 1
		printerr("FAIL: ", label)


func check_eq(a: Variant, b: Variant, label: String) -> void:
	_checks += 1
	if a != b:
		_failures += 1
		printerr("FAIL: ", label, " (got ", a, ", want ", b, ")")


func _golden_server_lines(file_name: String, side: String) -> Array:
	## golden から片側のサーバ送信行 (生バイト) を取り出す。
	var bytes := FileAccess.get_file_as_bytes(GOLDEN_DIR + file_name)
	var out: Array = []
	var start := 0
	for i in range(bytes.size() + 1):
		if i < bytes.size() and bytes[i] != 0x0A:
			continue
		var line := bytes.slice(start, i)
		start = i + 1
		if line.size() >= 4 and line.slice(0, 4) == "####".to_ascii_buffer():
			break # ここから後は保存内容のダンプ (プロトコルではない)
		# "<tick> <label> <行>" の3つ目からが行本体。
		var sp1 := line.find(0x20)
		if sp1 < 0:
			continue
		var sp2 := -1
		for j in range(sp1 + 1, line.size()):
			if line[j] == 0x20:
				sp2 = j
				break
		if sp2 < 0:
			continue
		if line.slice(sp1 + 1, sp2).get_string_from_ascii() != side:
			continue
		var body := line.slice(sp2 + 1)
		if not body.is_empty() and body[0] == 0x2B: # '+' = クライアント送信
			continue
		out.append(body)
	return out


func _feed_golden(parser: PhiParser, file_name: String, side: String) -> Array:
	var events: Array = []
	for line in _golden_server_lines(file_name, side):
		events.append_array(parser.feed(line))
	return events


func _of_type(events: Array, type_name: String) -> Array:
	var out: Array = []
	for ev in events:
		if str((ev as Dictionary).get("type", "")) == type_name:
			out.append(ev)
	return out


func _test_v6_frames() -> void:
	var parser := PhiParser.new()
	var events := _feed_golden(parser, "v6.out", "a")
	# 検出: view= の受理 (9x9 → 9x5 → …) と、size= による解除。
	var views := _of_type(events, "v6view")
	check(views.size() >= 3, "v6 view replies exist")
	if views.size() >= 2:
		check_eq(views[0].get("accepted"), true, "v6 view first accepted")
		check_eq(views[0].get("w"), 9, "v6 view first w")
		check_eq(views[0].get("h"), 9, "v6 view first h")
		check_eq(views[1].get("h"), 5, "v6 view second h (9x5)")
	var rejected := false
	for v in views:
		if not bool(v.get("accepted", true)):
			rejected = true
	check(rejected, "v6 view rejected after size= (v6.out)")
	# フレーム: 最初の 9x9。
	var maps := _of_type(events, "map")
	var v6maps: Array = []
	for m in maps:
		if bool((m as Dictionary).get("v6", false)):
			v6maps.append(m)
	check(not v6maps.is_empty(), "v6 map frames exist")
	if not v6maps.is_empty():
		var m0: Dictionary = v6maps[0]
		check_eq(m0.get("w"), 9, "v6 frame w")
		check_eq(m0.get("h"), 9, "v6 frame h")
		check_eq((m0.get("cells", []) as Array).size(), 81, "v6 frame cells")
		# turn 様式 (既定) の自キャラマス: 後ろ3行・前5行で (4,5)。
		check_eq(m0.get("selfCell"), {"x": 4, "y": 5}, "v6 frame selfCell (turn)")
		var self_ch: Dictionary = {}
		var obj_ch: Dictionary = {}
		for ch in m0.get("chars", []):
			if int((ch as Dictionary).get("id", -1)) == 1:
				self_ch = ch
			if int((ch as Dictionary).get("id", -1)) == 2:
				obj_ch = ch
		check_eq(self_ch.get("name"), "Vtester", "v6 self name")
		check_eq(self_ch.get("x"), 4, "v6 self x")
		check_eq(self_ch.get("y"), 5, "v6 self y")
		check_eq(self_ch.get("layer"), 12, "v6 self layer (C)")
		check_eq(self_ch.get("kind"), "C", "v6 self kind")
		check_eq(self_ch.get("status"), 0x70, "v6 self status")
		check_eq(self_ch.get("gra"), "human", "v6 self gra")
		check_eq(obj_ch.get("layer"), 11, "v6 object layer (B)")
		check_eq(obj_ch.get("gigant"), "*", "v6 object mark")
		check_eq(obj_ch.get("default"), 0x81, "v6 object kind byte")
	# 9x5 のフレーム (step 40)。この時点の様式は solid なので
	# 自キャラは中央 (4,2) (golden の O 行 C0001:04 02 と一致)。
	var found95 := false
	for m in v6maps:
		if int(m.get("h", 0)) == 5:
			found95 = true
			check_eq(m.get("selfCell"), {"x": 4, "y": 2}, "v6 9x5 selfCell (solid)")
			break
	check(found95, "v6 9x5 frame exists")


func _test_mapsets() -> void:
	var parser := PhiParser.new()
	var events := _feed_golden(parser, "mapsets.out", "a")
	var defs := _of_type(events, "v6define")
	check(defs.size() >= 2, "v6 defines exist")
	if defs.size() >= 2:
		check_eq(defs[0].get("slot"), 1, "v6 define slot 1")
		check_eq(defs[0].get("name"), "sakura", "v6 define slot 1 name")
		check_eq(defs[1].get("slot"), 2, "v6 define slot 2")
		check_eq(defs[1].get("name"), "phantom", "v6 define slot 2 name")
	var slot1 := false
	var slot2 := false
	for m in _of_type(events, "map"):
		if not bool((m as Dictionary).get("v6", false)):
			continue
		for cell in m.get("cells", []):
			if int((cell as Dictionary).get("slot", 0)) == 1:
				slot1 = true
			if int((cell as Dictionary).get("slot", 0)) == 2:
				slot2 = true
	check(slot1, "v6 A row slot 1 cells")
	check(slot2, "v6 A row slot 2 cells")


func _test_diag() -> void:
	var parser := PhiParser.new()
	var events := _feed_golden(parser, "v6diag.out", "a")
	var moves := _of_type(events, "v6move")
	check_eq(moves.size(), 1, "v6diag a: move reply count")
	if moves.size() == 1:
		check_eq(moves[0].get("diag"), true, "v6diag a: diag on")
	var gos := _of_type(events, "v6go")
	var saw_diag := false
	var saw_wall := false
	for g in gos:
		if int(g.get("dx", 0)) == 1 and int(g.get("dy", 0)) == -1:
			saw_diag = true
		if int(g.get("dx", 0)) == 0 and int(g.get("dy", 0)) == 0 \
				and str(g.get("word", "")) == "wall":
			saw_wall = true
	check(saw_diag, "v6diag a: diagonal G reply")
	check(saw_wall, "v6diag a: wall G reply")
	# b 側は move=diag を送っていないので、返事も斜めも無い。
	var parser_b := PhiParser.new()
	var events_b := _feed_golden(parser_b, "v6diag.out", "b")
	check_eq(_of_type(events_b, "v6move").size(), 0, "v6diag b: no move reply")


func _test_info_lines() -> void:
	# H / E (v6effect.out)
	var parser := PhiParser.new()
	var events := _feed_golden(parser, "v6effect.out", "a")
	var health := _of_type(events, "v6health")
	check(health.size() >= 2, "v6 H events exist")
	if health.size() >= 2:
		check_eq(health[0].get("id"), 2, "v6 H id")
		check_eq(health[0].get("hp"), 100, "v6 H hp first")
		check_eq(health[1].get("hp"), 98, "v6 H hp later")
	var effects := _of_type(events, "v6effect")
	check(not effects.is_empty(), "v6 E events exist")
	if not effects.is_empty():
		check_eq(effects[0].get("kind"), "hit", "v6 E kind")
		check_eq(effects[0].get("ax"), 4, "v6 E ax")
		check_eq(effects[0].get("ay"), 5, "v6 E ay")
		check_eq(effects[0].get("tx"), 4, "v6 E tx")
		check_eq(effects[0].get("ty"), 4, "v6 E ty")
		check_eq(effects[0].get("attr"), "none", "v6 E attr")
	# W (v6cast.out)
	parser = PhiParser.new()
	events = _feed_golden(parser, "v6cast.out", "a")
	var waits := _of_type(events, "v6wait")
	var self_cast := false
	var self_stop := false
	var other_cast := false
	for w in waits:
		if str(w.get("who", "")) == "self" and int(w.get("cast", -2)) == 8:
			self_cast = true
		if str(w.get("who", "")) == "self" and int(w.get("cast", 0)) == -1:
			self_stop = true
		if int(w.get("who", -1)) == 2 and int(w.get("cast", -2)) == 8:
			other_cast = true
	check(self_cast, "v6 W self cast")
	check(self_stop, "v6 W self cast stop")
	check(other_cast, "v6 W other cast")
	# P (party.out)
	parser = PhiParser.new()
	events = _feed_golden(parser, "party.out", "a")
	var parties := _of_type(events, "v6party")
	check(not parties.is_empty(), "v6 P events exist")
	var two: Dictionary = {}
	for p in parties:
		if (p.get("members", []) as Array).size() == 2:
			two = p
	check(not two.is_empty(), "v6 P two members")
	if not two.is_empty():
		var members: Array = two["members"]
		check_eq((members[0] as Dictionary).get("name"), "Alice", "v6 P member 1")
		check_eq((members[0] as Dictionary).get("hp"), "1000", "v6 P member 1 hp")
		check_eq((members[1] as Dictionary).get("name"), "Bob", "v6 P member 2")
	# L (v6mark.out)
	parser = PhiParser.new()
	events = _feed_golden(parser, "v6mark.out", "a")
	var marks := _of_type(events, "v6marks")
	check(not marks.is_empty(), "v6 L events exist")
	if not marks.is_empty():
		var ms: Array = marks[0].get("marks", [])
		check_eq(ms.size(), 2, "v6 L count")
		if ms.size() == 2:
			check_eq((ms[0] as Dictionary).get("name"), "Town", "v6 L name 1")
			check_eq((ms[0] as Dictionary).get("dx"), "7", "v6 L dx 1")
			check_eq((ms[1] as Dictionary).get("name"), "Old well", "v6 L name 2 (space)")
			check_eq((ms[1] as Dictionary).get("dy"), "5", "v6 L dy 2")
	# T / K (v6talk.out)
	parser = PhiParser.new()
	events = _feed_golden(parser, "v6talk.out", "a")
	var words := _of_type(events, "v6talkwords")
	var got_words := false
	for w in words:
		var ws: Array = w.get("words", [])
		if ws.size() >= 2 and str((ws[0] as Dictionary).get("word", "")) == "1" \
				and str((ws[0] as Dictionary).get("menu", "")) == "menu":
			got_words = true
	check(got_words, "v6 K words with menu")
	var tag_kinds: Array = []
	for ev in events:
		if str((ev as Dictionary).get("type", "")) == "message" and (ev as Dictionary).has("v6tag"):
			tag_kinds.append(str(((ev as Dictionary)["v6tag"] as Dictionary).get("kind", "")))
	check(tag_kinds.has("say"), "v6 T say tag on message")
	check(tag_kinds.has("switch"), "v6 T switch tag on message")
	# S / I (inv.out)
	parser = PhiParser.new()
	events = _feed_golden(parser, "inv.out", "a")
	var spells := _of_type(events, "v6spells")
	check(not spells.is_empty(), "v6 S events exist")
	if not spells.is_empty():
		var ss: Array = spells[0].get("spells", [])
		check_eq(ss.size(), 1, "v6 S count")
		if ss.size() == 1:
			check_eq((ss[0] as Dictionary).get("name"), "Cure", "v6 S name")
			check_eq((ss[0] as Dictionary).get("no"), 1, "v6 S no")
	var items := _of_type(events, "v6items")
	check(not items.is_empty(), "v6 I events exist")
	if not items.is_empty():
		check_eq((items[0].get("items", []) as Array).size(), 8, "v6 I slots (no compaction)")
	# B (v6shop.out) / Q (v6quest.out)
	parser = PhiParser.new()
	events = _feed_golden(parser, "v6shop.out", "a")
	var shops := _of_type(events, "v6shop")
	check(not shops.is_empty(), "v6 B events exist")
	if not shops.is_empty():
		var bs: Array = shops[0].get("items", [])
		if not bs.is_empty():
			check_eq((bs[0] as Dictionary).get("gp"), "3000", "v6 B gp")
	parser = PhiParser.new()
	events = _feed_golden(parser, "v6quest.out", "a")
	var quests := _of_type(events, "v6quests")
	check(not quests.is_empty(), "v6 Q events exist")
	if not quests.is_empty():
		var qs: Array = quests[0].get("quests", [])
		if not qs.is_empty():
			check_eq((qs[0] as Dictionary).get("kind"), "main", "v6 Q kind")
			check_eq((qs[0] as Dictionary).get("title"), "Old well", "v6 Q title")


func _test_legacy_safety() -> void:
	# 従来フレーム (m57 golden) では v6 イベントは一切出ない。
	var parser := PhiParser.new()
	var events := _feed_golden(parser, "m57.out", "a")
	check_eq(_of_type(events, "v6view").size(), 0, "m57: no v6view")
	check_eq(_of_type(events, "v6move").size(), 0, "m57: no v6move")
	var legacy_maps := 0
	for m in _of_type(events, "map"):
		check(not bool((m as Dictionary).get("v6", false)), "m57: map is not v6")
		legacy_maps += 1
	check(legacy_maps > 0, "m57: legacy maps parsed")
	# view=no は不受理イベントになる。
	var parser2 := PhiParser.new()
	var evs := parser2.feed(Cp932.encode("#ex-map view=no"))
	check_eq(evs.size(), 1, "view=no event count")
	if evs.size() == 1:
		check_eq(evs[0].get("accepted"), false, "view=no accepted=false")
	# 様式が solid なら自キャラマスは中央。
	var parser3 := PhiParser.new()
	parser3.feed(Cp932.encode("#ex-map style=solid"))
	var events3 := _feed_golden(parser3, "v6.out", "a")
	for m in _of_type(events3, "map"):
		if bool((m as Dictionary).get("v6", false)) and int(m.get("w", 0)) == 9 and int(m.get("h", 0)) == 9:
			check_eq(m.get("selfCell"), {"x": 4, "y": 4}, "v6 solid selfCell center")
			break


func _test_session_probe() -> void:
	var s := PhiSession.new()
	s.desired_map_size = 121
	var lines := s.v6_probe_lines()
	check(lines.has("#ex-map mapsets=16 view=33 25"), "probe 121 view")
	check(lines.has("#ex-switch move=diag"), "probe move=diag")
	s.desired_map_size = 57
	check(s.v6_probe_lines().has("#ex-map mapsets=16 view=25 19"), "probe 57 view")
	s.desired_map_size = 40
	check(s.v6_probe_lines().has("#ex-map mapsets=16 view=15 11"), "probe 40 view")


func _test_mapview_geometry() -> void:
	check_eq(MapView.grid_dims({"size": 57}), Vector2i(7, 7), "grid_dims legacy")
	check_eq(MapView.grid_dims({"w": 25, "h": 19}), Vector2i(25, 19), "grid_dims v6")
	check_eq(MapView.self_cell_of({"size": 57}), Vector2i(3, 3), "self_cell legacy")
	check_eq(MapView.self_cell_of({"w": 9, "h": 9, "selfCell": {"x": 4, "y": 5}}),
		Vector2i(4, 5), "self_cell v6")
	# (w,h) 版の静的ヘルパが正方形版と一致する。
	var cells: Array = []
	for i in 6:
		cells.append({"chip": 0x5F, "height": 1 if i == 4 else 0})
	check_eq(MapView.height_at_wh(cells, 3, 2, 1, 1), 1, "height_at_wh")
	check_eq(MapView.build_water_grid_wh(cells, 3, 2)[2][2], 1, "build_water_grid_wh")
	check_eq(PhiCharacter.diag_word_for(Vector2i(1, -1)), "ne", "diag word ne")
	check_eq(PhiCharacter.diag_word_for(Vector2i(-1, 1)), "sw", "diag word sw")
	check_eq(PhiCharacter.diag_word_for(Vector2i(1, 0)), "", "diag word none")
	# MapView へ v6 フレームを渡すと、寸法と自マスが伝わる。
	var parser := PhiParser.new()
	var events := _feed_golden(parser, "v6.out", "a")
	var frame: Dictionary = {}
	for m in _of_type(events, "map"):
		if bool((m as Dictionary).get("v6", false)):
			frame = m
			break
	check(not frame.is_empty(), "mapview: v6 frame found")
	if not frame.is_empty():
		var view := MapView.new()
		view.set_map(frame, null, "", {})
		check_eq(view.custom_minimum_size, Vector2(9 * 32, 9 * 32 + 16), "mapview v6 min size")
		check_eq(view.player_cell(), Vector2i(4, 5), "mapview v6 player cell")
		view.free()


func _initialize() -> void:
	Cp932.ensure_loaded()
	_test_v6_frames()
	_test_mapsets()
	_test_diag()
	_test_info_lines()
	_test_legacy_safety()
	_test_session_probe()
	_test_mapview_geometry()
	print("stage137: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)
