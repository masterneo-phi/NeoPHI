extends SceneTree
## 第22段: 自動装備外し (系統魔法) のテスト。Python 版
## tests/test_auto_unequip.py の移植 + セッション統合の確認。

var _checks := 0
var _failures := 0

const WEAPON := "     [ 1] ロングソード                    Wp  :  5 [Wpn]"
const WEAPON_TAGGED := "     [/*color=cyan*/ 1/*.*/] ロングソード                    Wp  :  5 [/*color=red*/Wpn/*.*/]"
const ARMOR := "     [ 1] 革の鎧                      Wp  :  3 [Arm]"


func check(cond: bool, label: String) -> void:
	_checks += 1
	if not cond:
		_failures += 1
		print("FAIL: ", label)


class FakeServer:
	var server := TCPServer.new()
	var peer: StreamPeerTCP = null
	var lines := LineBuffer.new()
	var received: Array[String] = []
	var port := 0

	func start() -> bool:
		if server.listen(0, "*") != OK:
			return false
		port = server.get_local_port()
		return true

	func stop() -> void:
		if peer != null:
			peer.disconnect_from_host()
			peer = null
		server.stop()

	func poll() -> void:
		if peer == null and server.is_connection_available():
			peer = server.take_connection()
		if peer != null:
			peer.poll()
			var guard := 0
			while peer.get_available_bytes() > 0 and guard < 64:
				guard += 1
				var r := peer.get_data(peer.get_available_bytes())
				if r[0] != OK:
					break
				var chunk: PackedByteArray = r[1]
				if chunk.is_empty():
					break
				for line in lines.feed(chunk):
					received.append(Cp932.decode(line))

	func send_line(text: String) -> void:
		if peer != null:
			peer.put_data(Cp932.encode(text) + PackedByteArray([10]))


func _start_auto(cast: String = "cast\twizard eye", reequip: bool = false) -> PhiAutoUnequip:
	var auto := PhiAutoUnequip.new()
	var flag := "1" if reequip else "0"
	check(auto.start(PhiAutoUnequip.CAST_PREFIX + flag + " " + cast, 0.0) == "unequip",
		"start は unequip を返す")
	return auto


func _feed(auto: PhiAutoUnequip, lines: Array, now: float = 0.0) -> Array:
	var shown: Array[String] = []
	var replies: Array[String] = []
	for line in lines:
		var r := auto.filter(str(line), now)
		replies.append_array(r["reply"])
		if not bool(r["hidden"]):
			shown.append(str(line))
	return [shown, replies]


func _initialize() -> void:
	_run()


func _run() -> void:
	_test_first_equipment()
	_test_flows()
	await _test_session_integration()
	print("test_stage22: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _test_first_equipment() -> void:
	var found: Variant = PhiAutoUnequip.first_equipment(PhiTags.strip_tags(WEAPON_TAGGED))
	check(found != null and str(found[0]) == "ロングソード" and str(found[1]) == "Wpn",
		"タグつき武器を読む: %s" % str(found))
	found = PhiAutoUnequip.first_equipment(WEAPON)
	check(found != null and str(found[0]) == "ロングソード" and str(found[1]) == "Wpn", "武器を読む")
	found = PhiAutoUnequip.first_equipment(ARMOR)
	check(found != null and str(found[0]) == "革の鎧" and str(found[1]) == "Arm", "防具を読む")
	check(PhiAutoUnequip.first_equipment("[ 2] 革の盾   Wp  :  2 [Arm]") == null, "2番は読まない")
	check(PhiAutoUnequip.first_equipment("[ 1] 木の剣") == null, "種別が無ければ読まない")


func _test_flows() -> void:
	# 武器: 1 を送ってから唱える。リストと促しは出ない。
	var auto := _start_auto()
	var r := _feed(auto, ["#list", WEAPON, "#end-list", "外す装備を選択して下さい", "DM > wizard eye を唱えた。"])
	check(r[1] == ["1", "cast", "wizard eye"], "武器の流れの送信: %s" % str(r[1]))
	check(r[0] == ["DM > wizard eye を唱えた。"], "武器の流れの表示: %s" % str(r[0]))
	# 防具: . で取り消してから唱える。
	auto = _start_auto("cast\tdetect")
	r = _feed(auto, ["#list", ARMOR, "#end-list"])
	check(r[1] == [".", "cast", "detect"], "防具の流れ: %s" % str(r[1]))
	# 装備なし: すぐ唱える。
	auto = _start_auto()
	r = _feed(auto, ["なにも装備していません"])
	check(r[1] == ["cast", "wizard eye"], "装備なしはすぐ唱える: %s" % str(r[1]))
	check(r[0].is_empty(), "装備なしの行は出ない")
	for text in ["装備を外せません", "Can not unequip."]:
		auto = _start_auto()
		r = _feed(auto, [text])
		check(r[1] == ["cast", "wizard eye"], "外せない文言でも唱える: " + text)
	# 1番が読めない: . で取り消して唱える。
	auto = _start_auto()
	r = _feed(auto, ["#list", "[ 2] 革の盾   Wp  :  2 [Arm]", "#end-list"])
	check(r[1] == [".", "cast", "wizard eye"], "読めない時は取り消す: %s" % str(r[1]))
	# 5秒過ぎたら横取りしない。
	auto = _start_auto()
	r = _feed(auto, ["#list", WEAPON, "#end-list"], 6.0)
	check(r[1].is_empty(), "期限切れは唱えない")
	check(r[0] == ["#list", WEAPON, "#end-list"], "期限切れは全部出す: %s" % str(r[0]))
	# 英語の促しも出さない。
	auto = _start_auto()
	r = _feed(auto, ["#list", WEAPON, "#end-list", "Input item number to unequip."])
	check(r[1] == ["1", "cast", "wizard eye"], "英語の促し: %s" % str(r[1]))
	check(r[0].is_empty(), "英語の促しは出ない")
	# 装備し直し: 唱えた後に equip し、「を装備した」を出さない。
	auto = _start_auto("cast\teagle eye", true)
	r = _feed(auto, ["#list", WEAPON, "#end-list", "ロングソードを装備した"])
	check(r[1] == ["1", "cast", "eagle eye", "equip ロングソード"], "装備し直し: %s" % str(r[1]))
	check(r[0].is_empty(), "装備した行は出ない")
	# 関係ない行は素通し。
	auto = _start_auto()
	r = _feed(auto, ["誰か > こんにちは"])
	check(r[1].is_empty() and r[0] == ["誰か > こんにちは"], "関係ない行は素通し")
	# start は他の行を受け付けない。
	auto = PhiAutoUnequip.new()
	check(auto.start("cast", 0.0) == "" and auto.cast.is_empty(), "start は cast 行だけ")


func _test_session_integration() -> void:
	var src := FakeServer.new()
	check(src.start(), "偽サーバ listen")
	var events: Array = []
	var s := PhiSession.new()
	s.event_received.connect(func(e: Dictionary) -> void: events.append(e))
	s.connect_to("127.0.0.1", src.port, "TESTID")
	var deadline := Time.get_ticks_msec() + 5000
	while Time.get_ticks_msec() < deadline and not src.received.has("#open TESTID"):
		s.poll()
		src.poll()
		await process_frame
	check(src.received.has("#open TESTID"), "ログインが届く")
	# 系統魔法: unequip だけが先に届き、#wphi-cast は届かない。
	s.send_system_magic("cast\nwizard eye", false)
	deadline = Time.get_ticks_msec() + 5000
	while Time.get_ticks_msec() < deadline and not src.received.has("unequip"):
		s.poll()
		src.poll()
		await process_frame
	check(src.received.has("unequip"), "unequip が先に届く: %s" % str(src.received))
	check(not src.received.any(func(l: String) -> bool: return l.begins_with("#wphi-")),
		"#wphi-cast はサーバへ送らない")
	# 装備リストが届く → 1 → cast → wizard eye の順に送り、リストは出ない。
	src.send_line("#list")
	src.send_line(WEAPON_TAGGED)
	src.send_line("#end-list")
	src.send_line("外す装備を選択して下さい")
	deadline = Time.get_ticks_msec() + 5000
	while Time.get_ticks_msec() < deadline and not src.received.has("wizard eye"):
		s.poll()
		src.poll()
		await process_frame
	var tail := src.received.slice(src.received.find("unequip"))
	check(tail == ["unequip", "1", "cast", "wizard eye"], "送信の順序: %s" % str(tail))
	var saw_list := false
	var saw_weapon := false
	for e in events:
		if e.get("type") == "list":
			saw_list = true
		if e.get("type") == "message" and str(e.get("text", "")).contains("ロングソード"):
			saw_weapon = true
	check(not saw_list, "装備リストのイベントは出ない")
	check(not saw_weapon, "装備の行はログに出ない")
	# 唱えた後の通常リストは普通に出る。
	events.clear()
	src.send_line("#list")
	src.send_line("     [ 1] 木の剣")
	src.send_line("#end-list")
	deadline = Time.get_ticks_msec() + 5000
	saw_list = false
	while Time.get_ticks_msec() < deadline and not saw_list:
		s.poll()
		src.poll()
		await process_frame
		for e in events:
			if e.get("type") == "list":
				saw_list = true
	check(saw_list, "通常のリストは出る")
	s.disconnect_force()
	src.stop()
