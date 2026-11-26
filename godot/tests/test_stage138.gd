extends SceneTree
## 第138段: phidm-v6 プロトコル対応 (フェーズ2+3)。
##
## - カバン `#ex-inv` (I/F の一覧、no の理由) の解釈
## - 取引 `#v6 Y` (ask / with 〜 . の提示 / done / end) と
##   `#ex-trade no` の解釈
## - 店 `#v6 B`・依頼 `#v6 Q` の表示連携向けイベント (段階0+1 の
##   パーサの再確認)
## - deflate 圧縮: `#ex-switch compress=` の返事イベントと、
##   PhiInflate の境界検出 + zlib→gzip 差し替えの増分 inflate
## - 従来 golden (m57) で新しいイベントが出ないこと
##
## 検証は phidm-v6 の test/replay の golden (実サーバの実バイト列)
## をパーサへ流して行う。inflate の zlib 列は Python の zlib で
## Z_SYNC_FLUSH x3 を入れて作った固定フィクスチャ (base64)。
##
## 使い方: godot --headless --path . -s tests/test_stage138.gd
## 終了コード 0 = 全一致、1 = 不一致あり。

const GOLDEN_DIR := "/home/hatch/workspace/phidm_v6_analysis/phidm-v6-main/test/replay/golden/"

## フィクスチャの zlib 列 (平文は _inflate_plain() と同じ組み立て)。
const ZLIB_B64 := "eJyc1jFqQlEYROHeVVxwA29m9KlNqhRpbNyBhYFA0MJHyqw9hDgQsDtMfbqP/9711zxOY5rG7bG379/dxtNWr8fxMj6u75/n5TKW" \
	+ "y30Z02r9lwvlam6Uu3lQnuYblG+ab1G+bT6jfG6+Q/mu+R7l++YHlB8euZg6lZ0gu7oTc6fCE4OnyhOTp9ITo6faE7On4hPDp+oT" \
	+ "06fyE+On+jPz5/oz8+f6M7x79Wfmz/Vn5s/1Z+bP9Wfmz/Vn5s/1Z+bP9Wfmz/UX5i/1F+Yv9RfmL/UX+PDWX5i/1F+Yv9RfmL/U" \
	+ "X5i/1F+Yv9RfmL/U379f3w8AAAD//6TWQRHAQBACMFML+Hd2CvroJCryaz7YvsP3HcbvdH5Yv8P7HebvcH+H/Tv8X/B/wf8F/xf8" \
	+ "X/B/wf8F/xf8X/B/wf8V/1f8X/F/xf8V/1f8X/F/xf8V/1f83/B/w/8N/zf83/B/w/8N/zf83/B/+/7fAwAA//+k2DENQgEAxND9" \
	+ "q7ludysDZggiYCIsLDjBBqKwQFIB3V/6V1/pv0r/Vfqv0n+V/qv0X6X/au+f9F+l/yb9N+m/Sf9N+m/Sf5P+m/TfpP8m/TfpPyIB" \
	+ "SKQAiSQgkQYkEoFEKpBIBhLpQCIhSKQEQVIQpAVBYhCkBkFyEKQHQYIQpAhBkhB2PD6vy/37vL7Pt9PxAwAA//8="

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


func _sizes(events: Array, type_name: String) -> Array:
	var out: Array = []
	for ev in _of_type(events, type_name):
		out.append(((ev as Dictionary).get("items", []) as Array).size())
	return out


func _reasons(events: Array, type_name: String) -> Array:
	var out: Array = []
	for ev in _of_type(events, type_name):
		out.append(str((ev as Dictionary).get("reason", "")))
	return out


# -- カバン ---------------------------------------------------------------

func _test_inv() -> void:
	var p1 := PhiParser.new()
	var ev1 := _feed_golden(p1, "inv.out", "a")
	check_eq(_sizes(ev1, "v6bag"), [0, 1, 0], "inv: bag sizes")
	check_eq(_reasons(ev1, "v6invno"), ["empty", "hand", "bad", "off"], "inv: reasons")
	var bags := _of_type(ev1, "v6bag")
	if bags.size() >= 2:
		var items: Array = bags[1].get("items", [])
		if items.size() == 1:
			var it: Dictionary = items[0]
			check_eq(it.get("no"), 1, "inv: item no")
			check_eq(it.get("name"), "Nuts", "inv: item name")
			check_eq(it.get("type"), "Food", "inv: item type")
			check_eq(it.get("eq"), "-", "inv: item eq")
	var p2 := PhiParser.new()
	var ev2 := _feed_golden(p2, "v6floor.out", "a")
	check_eq(_sizes(ev2, "v6flooritems"), [2, 1, 0], "floor: sizes")
	check_eq(_sizes(ev2, "v6bag"), [1, 2], "floor: bag sizes")
	var p3 := PhiParser.new()
	var ev3 := _feed_golden(p3, "bag2.out", "a")
	check_eq(_sizes(ev3, "v6bag"), [1, 2, 1, 0, 1, 2, 1, 0], "bag2: sizes")
	check_eq(_reasons(ev3, "v6invno"), ["bad", "none", "bad", "bad"], "bag2: reasons")
	var p4 := PhiParser.new()
	var ev4 := _feed_golden(p4, "offer.out", "a")
	check_eq(_reasons(ev4, "v6invno"), ["none", "none", "none", "bad", "bad"], "offer: reasons")
	var p5 := PhiParser.new()
	var ev5 := _feed_golden(p5, "epic.out", "a")
	check_eq(_reasons(ev5, "v6invno"), ["epic", "epic"], "epic: reasons")
	var p6 := PhiParser.new()
	var ev6 := _feed_golden(p6, "getbag.out", "a")
	check_eq(_reasons(ev6, "v6invno"), ["hand"], "getbag: reasons")


# -- 取引 -----------------------------------------------------------------

func _test_trade() -> void:
	var pa := PhiParser.new()
	var eva := _feed_golden(pa, "v6trade.out", "a")
	check_eq(_reasons(eva, "v6tradeno"), ["off", "none", "empty", "refused"], "trade a: no reasons")
	var phases: Array = []
	for ev in _of_type(eva, "v6trade"):
		phases.append(str((ev as Dictionary).get("phase", "")))
	check(phases.has("done"), "trade a: done exists")
	check(phases.has("end"), "trade a: end exists")
	var offers: Array = []
	for ev in _of_type(eva, "v6trade"):
		if str((ev as Dictionary).get("phase", "")) == "offers":
			offers.append(ev)
	check(not offers.is_empty(), "trade a: offers exist")
	if not offers.is_empty():
		var first: Dictionary = offers[0]
		check_eq((first.get("with", {}) as Dictionary).get("id"), 2, "trade a: with id")
		check_eq((first.get("with", {}) as Dictionary).get("name"), "Bob", "trade a: with name")
		# done の直前の提示: 自分は2品 (put 1 / bag 1) + ok、
		# 相手は 50gp。成立後の done は別イベントで届く。
		var last_offers: Dictionary = {}
		for o in offers:
			if bool(((o as Dictionary).get("me", {}) as Dictionary).get("ok", false)):
				last_offers = o
		check(not last_offers.is_empty(), "trade a: ok offers exist")
		var me: Dictionary = last_offers.get("me", {})
		var you: Dictionary = last_offers.get("you", {})
		check_eq(int(me.get("gp", -1)), 0, "trade a: me gp")
		check_eq(bool(me.get("ok", false)), true, "trade a: me ok")
		var me_items: Array = me.get("items", [])
		check_eq(me_items.size(), 2, "trade a: me items")
		if me_items.size() == 2:
			check_eq(str((me_items[0] as Dictionary).get("from", "")), "put 1", "trade a: me item1 from")
			check_eq(str((me_items[1] as Dictionary).get("from", "")), "bag 1", "trade a: me item2 from")
			check_eq(str((me_items[0] as Dictionary).get("name", "")), "Nuts", "trade a: me item name")
		check_eq(int(you.get("gp", -1)), 50, "trade a: you gp")
	# end の理由
	for ev in _of_type(eva, "v6trade"):
		if str((ev as Dictionary).get("phase", "")) == "end":
			check_eq(str((ev as Dictionary).get("reason", "")), "moved", "trade a: end reason")
	var pb := PhiParser.new()
	var evb := _feed_golden(pb, "v6trade.out", "b")
	var asks: Array = []
	for ev in _of_type(evb, "v6trade"):
		if str((ev as Dictionary).get("phase", "")) == "ask":
			asks.append(ev)
	check_eq(asks.size(), 3, "trade b: ask count")
	if not asks.is_empty():
		check_eq(int((asks[0] as Dictionary).get("id", -1)), 1, "trade b: ask id")
		check_eq(str((asks[0] as Dictionary).get("name", "")), "Alice", "trade b: ask name")
	var b_done := 0
	var b_end: Array = []
	for ev in _of_type(evb, "v6trade"):
		match str((ev as Dictionary).get("phase", "")):
			"done":
				b_done += 1
			"end":
				b_end.append(str((ev as Dictionary).get("reason", "")))
	check_eq(b_done, 1, "trade b: done count")
	check_eq(b_end, ["moved"], "trade b: end reasons")


# -- 店・依頼 ---------------------------------------------------------------

func _test_shop_quest() -> void:
	var p1 := PhiParser.new()
	var ev1 := _feed_golden(p1, "v6shop.out", "a")
	check_eq(_sizes(ev1, "v6shop"), [3, 2, 0, 2, 3], "shop: sizes")
	var shops := _of_type(ev1, "v6shop")
	if not shops.is_empty():
		var items: Array = shops[0].get("items", [])
		if items.size() == 3:
			check_eq(str((items[0] as Dictionary).get("gp", "")), "3000", "shop: gp")
			check_eq(str((items[0] as Dictionary).get("name", "")), "Hinezumi-ginu", "shop: name")
	var p2 := PhiParser.new()
	var ev2 := _feed_golden(p2, "v6quest.out", "a")
	var qsizes: Array = []
	for ev in _of_type(ev2, "v6quests"):
		qsizes.append(((ev as Dictionary).get("quests", []) as Array).size())
	check_eq(qsizes, [2, 2, 2, 0], "quest: sizes")
	var quests := _of_type(ev2, "v6quests")
	if not quests.is_empty():
		var qs: Array = quests[0].get("quests", [])
		if qs.size() == 2:
			check_eq(str((qs[0] as Dictionary).get("title", "")), "Old well", "quest: title")
			check_eq(str((qs[0] as Dictionary).get("kind", "")), "main", "quest: kind")
			check_eq(str((qs[0] as Dictionary).get("text", "")), "Walk east.", "quest: text")


# -- 直接の行と従来モード ----------------------------------------------------

func _test_direct() -> void:
	var p := PhiParser.new()
	var e1 := p.feed(Cp932.encode("#ex-inv no empty"))
	check_eq(e1.size(), 1, "direct: invno count")
	if e1.size() == 1:
		check_eq(e1[0].get("type"), "v6invno", "direct: invno type")
		check_eq(e1[0].get("reason"), "empty", "direct: invno reason")
	var e2 := p.feed(Cp932.encode("#ex-trade no busy"))
	check_eq(e2.size(), 1, "direct: tradeno count")
	if e2.size() == 1:
		check_eq(e2[0].get("type"), "v6tradeno", "direct: tradeno type")
		check_eq(e2[0].get("reason"), "busy", "direct: tradeno reason")
	var e3 := p.feed(Cp932.encode("#ex-switch compress=deflate"))
	check_eq(e3.size(), 1, "direct: compress count")
	if e3.size() == 1:
		check_eq(e3[0].get("type"), "v6compress", "direct: compress type")
		check_eq(e3[0].get("accepted"), true, "direct: compress accepted")
	var e4 := p.feed(Cp932.encode("#ex-switch compress=no"))
	check_eq(e4.size(), 1, "direct: compress=no count")
	if e4.size() == 1:
		check_eq(e4[0].get("accepted"), false, "direct: compress=no accepted")
	# 従来 golden では新しいイベントは出ない。
	var p2 := PhiParser.new()
	var ev := _feed_golden(p2, "m57.out", "a")
	for t in ["v6bag", "v6flooritems", "v6invno", "v6trade", "v6tradeno", "v6compress"]:
		check(_of_type(ev, t).is_empty(), "legacy: no %s events" % t)


# -- Eagle Eye 65x49 (v6 の接続でサーバが送る最大の広域図) -------------------

func _test_eagle() -> void:
	## サーバ (phi_m57.rs の eagleeye_m57) と同じ書式で 65x49 の
	## フレームを作って流し、イベントと表示側の盤寸法を確かめる。
	var p := PhiParser.new()
	var events: Array = []
	events.append_array(p.feed("#ex-eagleeye start".to_ascii_buffer()))
	for row in range(49):
		var line := PackedByteArray()
		line.append_array(("#ex-eagleeye M 64 %02d " % row).to_ascii_buffer())
		for x in range(65):
			line.append(0x6F) # 'o'
			line.append(0x58 if (x == 32 and row == 24) else 0x00)
		line.append(0x20)
		events.append_array(p.feed(line))
	events.append_array(p.feed("#ex-eagleeye end".to_ascii_buffer()))
	var eagles := _of_type(events, "eagleEye")
	check_eq(eagles.size(), 1, "eagle: event count")
	if eagles.size() == 1:
		var ev: Dictionary = eagles[0]
		check_eq(int(ev.get("width", 0)), 65, "eagle: width")
		check_eq(int(ev.get("height", 0)), 49, "eagle: height")
		check_eq((ev.get("cells", []) as Array).size(), 65 * 49, "eagle: cells")
		var view := PhiEagleView.new()
		view.set_event(ev, null, "", 1.0)
		check_eq(view.board_dim(), 65, "eagle: board dim")
		view.free()


# -- deflate (PhiInflate) ---------------------------------------------------

func _inflate_plain() -> PackedByteArray:
	## フィクスチャの平文 (Python 側の組み立てと同じ)。
	var text := ""
	for i in range(120):
		text += "#v6 R %02d " % (i % 40) + "o o o o H~H~H~o o o o o o o o o o" + "\n"
		text += "DM > inflate test %d" % i + "\n"
	text += "圧縮の確認。\n"
	return Cp932.encode(text)


func _feed_sliced(inf: PhiInflate, data: PackedByteArray, slice_size: int) -> PackedByteArray:
	var out := PackedByteArray()
	var pos := 0
	while pos < data.size():
		var n := mini(slice_size, data.size() - pos)
		out.append_array(inf.feed(data.slice(pos, pos + n)))
		pos += n
	return out


func _test_inflate() -> void:
	var plain := _inflate_plain()
	var zipped := Marshalls.base64_to_raw(ZLIB_B64)
	check(zipped.size() > 100, "inflate: fixture size")
	# off: そのまま通す。
	var inf0 := PhiInflate.new()
	check_eq(inf0.feed(plain), plain, "inflate: off passthrough")
	# armed のまま返事が無い: 末尾を残して通り、flush で揃う。
	var inf1 := PhiInflate.new()
	inf1.arm()
	var got1 := _feed_sliced(inf1, plain, 7)
	check(inf1.is_armed(), "inflate: still armed without reply")
	got1.append_array(inf1.flush_armed())
	check_eq(got1, plain, "inflate: armed passthrough + flush")
	check(not inf1.is_armed(), "inflate: disarmed after flush")
	# 境界 + inflate: 3 バイトずつ。
	var prefix := Cp932.encode("ようこそ\n#status 1 2\n")
	var stream := prefix.duplicate()
	stream.append_array("#ex-switch compress=deflate\n".to_ascii_buffer())
	stream.append_array(zipped)
	var want := prefix.duplicate()
	want.append_array("#ex-switch compress=deflate\n".to_ascii_buffer())
	want.append_array(plain)
	var inf2 := PhiInflate.new()
	inf2.arm()
	var got2 := _feed_sliced(inf2, stream, 3)
	check_eq(got2, want, "inflate: boundary + sliced stream")
	check(inf2.is_on(), "inflate: on after boundary")
	check(not inf2.failed, "inflate: not failed")
	# 境界 + inflate: 一括。
	var inf3 := PhiInflate.new()
	inf3.arm()
	var got3 := inf3.feed(stream)
	check_eq(got3, want, "inflate: boundary + one-shot")
	# compress=no: 全て平文で通る。
	var inf4 := PhiInflate.new()
	inf4.arm()
	var no_stream := Cp932.encode("#ex-switch compress=no\n")
	no_stream.append_array(plain)
	var got4 := _feed_sliced(inf4, no_stream, 5)
	check_eq(got4, no_stream, "inflate: compress=no passthrough")
	check(not inf4.is_on(), "inflate: not on after no")
	# reset で off に戻る。
	inf2.reset()
	check_eq(inf2.feed(plain), plain, "inflate: reset passthrough")
	check(not inf2.is_on(), "inflate: not on after reset")
	# armed: 完成した行ブロックは留保されず即座に全部出る
	# (従来サーバは返事をしないので、末尾留保があると最終行が
	# 次の受信か flush まで遅れる。33 バイトの #list 塊が回帰例)。
	var inf5 := PhiInflate.new()
	inf5.arm()
	var block := "#list\nabcdefghijklmnopqrstuvwxyz\n".to_ascii_buffer()
	check_eq(block.size(), 33, "inflate: armed block fixture size")
	check_eq(inf5.feed(block), block, "inflate: armed releases complete block at once")
	check(inf5.is_armed(), "inflate: still armed after plain block")
	# armed: 返事行が 2 回の feed に跨っても境界を検出する。
	var inf6 := PhiInflate.new()
	inf6.arm()
	var cut6 := prefix.size() + "#ex-switch compress=".length()
	var got6 := inf6.feed(stream.slice(0, cut6))
	check_eq(got6, prefix, "inflate: split marker holds only the prefix")
	check(inf6.is_armed(), "inflate: split marker still armed")
	got6.append_array(inf6.feed(stream.slice(cut6)))
	check_eq(got6, want, "inflate: split marker stream")
	check(inf6.is_on(), "inflate: on after split marker")
	check(not inf6.failed, "inflate: not failed after split marker")
	# armed: マーカーの接頭辞に見えた末尾が外れたら平文として出る。
	var inf7 := PhiInflate.new()
	inf7.arm()
	check_eq(inf7.feed(Cp932.encode("案内\n#ex-switch comp")), Cp932.encode("案内\n"),
		"inflate: partial prefix held")
	check_eq(inf7.feed(Cp932.encode("uter\n次\n")), Cp932.encode("#ex-switch computer\n次\n"),
		"inflate: false prefix released as plain")
	check(inf7.is_armed(), "inflate: still armed after false prefix")


func _initialize() -> void:
	_test_inv()
	_test_trade()
	_test_shop_quest()
	_test_direct()
	_test_eagle()
	_test_inflate()
	print("stage138: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)
