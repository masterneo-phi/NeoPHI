extends SceneTree
## 第21段: 世界移動 (#ch-srv) のテスト。偽の移動元・移動先サーバを
## プロセス内に立てて、Python 版 tests/test_transfer.py と同じ
## シナリオを確認する。

var _checks := 0
var _failures := 0


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
	var connections := 0
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
			connections += 1
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

	func send_raw(text: String) -> void:
		if peer != null:
			peer.put_data(Cp932.encode(text))


var _session: PhiSession = null
var _events: Array = []
var _confirms: Array = []


func _make_session(src: FakeServer) -> PhiSession:
	_events.clear()
	_confirms.clear()
	var s := PhiSession.new()
	s.event_received.connect(func(e: Dictionary) -> void: _events.append(e))
	s.transfer_confirm_requested.connect(
		func(h: String, p: int) -> void: _confirms.append([h, p]))
	s.connect_to("127.0.0.1", src.port, "TESTID")
	_session = s
	return s


func _pump(servers: Array, frames: int = 1) -> void:
	for i in frames:
		if _session != null:
			_session.poll()
		for s in servers:
			s.poll()
		await process_frame


func _wait_for(pred: Callable, servers: Array, timeout_msec: int = 5000) -> bool:
	var deadline := Time.get_ticks_msec() + timeout_msec
	while Time.get_ticks_msec() < deadline:
		if _session != null:
			_session.poll()
		for s in servers:
			s.poll()
		if pred.call():
			return true
		await process_frame
	return pred.call()


func _has_message(fragment: String) -> bool:
	for e in _events:
		if e.get("type") == "message" and str(e.get("text", "")).contains(fragment):
			return true
	return false


func _initialize() -> void:
	_run()


func _run() -> void:
	_test_target()
	await _test_success_same_host()
	await _test_confirm_no()
	await _test_confirm_yes()
	await _test_rsv_no()
	await _test_trs_no()
	await _test_unreachable()
	print("test_stage21: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _test_target() -> void:
	var t: Variant = PhiSession.transfer_target("example.com:20017")
	check(t != null and str(t[0]) == "example.com" and int(t[1]) == 20017, "target valid")
	t = PhiSession.transfer_target("127.0.0.1:09000")
	check(t != null and int(t[1]) == 9000, "target leading zero port")
	for bad in ["example.com", "example.com:abc", "example.com:99999", "example.com:-1", ":20017"]:
		check(PhiSession.transfer_target(bad) == null, "target invalid: " + bad)


func _start_pair() -> Array:
	var src := FakeServer.new()
	var dst := FakeServer.new()
	check(src.start(), "src listen")
	check(dst.start(), "dst listen")
	return [src, dst]


func _wait_login(src: FakeServer, servers: Array) -> void:
	var ok: bool = await _wait_for(func() -> bool: return src.received.has("#open TESTID"), servers)
	check(ok, "ログインが届く: %s" % str(src.received))


func _test_success_same_host() -> void:
	var pair := _start_pair()
	var src: FakeServer = pair[0]
	var dst: FakeServer = pair[1]
	var servers: Array = pair
	var s := _make_session(src)
	await _wait_login(src, servers)
	src.send_raw("#ch-srv 127.0.0.1 %d\nDM > after-ch-srv\n" % dst.port)
	var ok: bool = await _wait_for(func() -> bool: return dst.received.has("#reserve TESTID"), servers)
	check(ok, "reserve が届く: %s" % str(dst.received))
	dst.send_line("#rsv-ok")
	ok = await _wait_for(func() -> bool: return src.received.has("#trans 127.0.0.1 %d" % dst.port), servers)
	check(ok, "trans が届く: %s" % str(src.received))
	src.send_line("#trs-ok")
	ok = await _wait_for(func() -> bool: return dst.received.size() >= 12, servers)
	check(ok, "移動先への送信: %s" % str(dst.received))
	var expected: Array[String] = ["#reserve TESTID", "#ch-srv-ok"]
	expected.append_array(PhiSession.login_lines(null))
	# ログイン行の後には v6 検出プローブが続く (第137段)。
	expected.append_array(PhiSession.new().v6_probe_lines())
	check(dst.received == expected, "移動先の受信が #reserve + #ch-srv-ok + ログイン行: %s" % str(dst.received))
	dst.send_line("DM > moved-ok")
	ok = await _wait_for(func() -> bool: return _has_message("moved-ok"), servers)
	check(ok, "移動先の行が届く")
	check(_confirms.is_empty(), "同じホストでは確認が出ない")
	check(not _has_message("after-ch-srv"), "#ch-srv の後の行は捨てる")
	check(s.host == "127.0.0.1" and s.port == dst.port, "接続先が移動先に差し替わる")
	s.disconnect_force()
	src.stop()
	dst.stop()


func _test_confirm_no() -> void:
	var pair := _start_pair()
	var src: FakeServer = pair[0]
	var dst: FakeServer = pair[1]
	var servers: Array = pair
	var s := _make_session(src)
	await _wait_login(src, servers)
	src.send_line("#ch-srv 127.0.0.2 %d" % dst.port)
	var ok: bool = await _wait_for(func() -> bool: return not _confirms.is_empty(), servers)
	check(ok, "違うホストでは確認が出る")
	if not _confirms.is_empty():
		check(str(_confirms[0][0]) == "127.0.0.2" and int(_confirms[0][1]) == dst.port, "確認の宛先")
	check(dst.connections == 0, "確認の前には移動先へ繋がない")
	s.send_line("hello-during-transfer")
	s.answer_transfer(false)
	ok = await _wait_for(func() -> bool: return src.received.has("#no-srv"), servers)
	check(ok, "断れば #no-srv: %s" % str(src.received))
	check(not src.received.has("hello-during-transfer"), "移動の間に打った行は捨てる")
	src.send_line("DM > still-here")
	ok = await _wait_for(func() -> bool: return _has_message("still-here"), servers)
	check(ok, "留まった後も行が届く")
	s.disconnect_force()
	src.stop()
	dst.stop()


func _test_confirm_yes() -> void:
	var pair := _start_pair()
	var src: FakeServer = pair[0]
	var dst: FakeServer = pair[1]
	var servers: Array = pair
	var s := _make_session(src)
	await _wait_login(src, servers)
	src.send_line("#ch-srv 127.0.0.2 %d" % dst.port)
	var ok: bool = await _wait_for(func() -> bool: return not _confirms.is_empty(), servers)
	check(ok, "確認が出る")
	s.answer_transfer(true)
	ok = await _wait_for(func() -> bool: return dst.received.has("#reserve TESTID"), servers)
	check(ok, "認めれば reserve が届く: %s" % str(dst.received))
	dst.send_line("#rsv-ok")
	ok = await _wait_for(func() -> bool: return src.received.has("#trans 127.0.0.2 %d" % dst.port), servers)
	check(ok, "trans が届く: %s" % str(src.received))
	src.send_line("#trs-ok")
	ok = await _wait_for(func() -> bool: return dst.received.has("#ch-srv-ok"), servers)
	check(ok, "移動が完了する")
	check(s.host == "127.0.0.2" and s.port == dst.port, "接続先が 127.0.0.2 に差し替わる")
	s.disconnect_force()
	src.stop()
	dst.stop()


func _test_rsv_no() -> void:
	var pair := _start_pair()
	var src: FakeServer = pair[0]
	var dst: FakeServer = pair[1]
	var servers: Array = pair
	var s := _make_session(src)
	await _wait_login(src, servers)
	src.send_raw("#ch-srv 127.0.0.1 %d\nDM > after-ch-srv\n" % dst.port)
	var ok: bool = await _wait_for(func() -> bool: return dst.received.has("#reserve TESTID"), servers)
	check(ok, "reserve が届く")
	dst.send_line("#rsv-no")
	ok = await _wait_for(func() -> bool: return src.received.has("#no-srv"), servers)
	check(ok, "#rsv-no なら #no-srv: %s" % str(src.received))
	ok = await _wait_for(func() -> bool: return _has_message("after-ch-srv"), servers)
	check(ok, "保留した行は留まった後に処理する")
	s.disconnect_force()
	src.stop()
	dst.stop()


func _test_trs_no() -> void:
	var pair := _start_pair()
	var src: FakeServer = pair[0]
	var dst: FakeServer = pair[1]
	var servers: Array = pair
	var s := _make_session(src)
	await _wait_login(src, servers)
	src.send_line("#ch-srv 127.0.0.1 %d" % dst.port)
	var ok: bool = await _wait_for(func() -> bool: return dst.received.has("#reserve TESTID"), servers)
	check(ok, "reserve が届く")
	dst.send_line("#rsv-ok")
	ok = await _wait_for(func() -> bool: return src.received.has("#trans 127.0.0.1 %d" % dst.port), servers)
	check(ok, "trans が届く")
	src.send_line("DM > during-trans")
	await _pump(servers, 10)
	src.send_line("#trs-no")
	ok = await _wait_for(func() -> bool: return src.received.has("#ch-srv-no"), servers)
	check(ok, "#trs-no なら #ch-srv-no: %s" % str(src.received))
	ok = await _wait_for(func() -> bool: return _has_message("during-trans"), servers)
	check(ok, "待つ間に届いた行は処理し直す")
	s.disconnect_force()
	src.stop()
	dst.stop()


func _test_unreachable() -> void:
	var pair := _start_pair()
	var src: FakeServer = pair[0]
	var dst: FakeServer = pair[1]
	var servers: Array = pair
	var closed_port := dst.port
	dst.stop()
	var s := _make_session(src)
	await _wait_login(src, servers)
	src.send_line("#ch-srv 127.0.0.1 %d" % closed_port)
	var ok: bool = await _wait_for(func() -> bool: return src.received.has("#no-srv"), servers)
	check(ok, "移動先に繋がらなければ #no-srv: %s" % str(src.received))
	src.send_line("DM > still-here")
	ok = await _wait_for(func() -> bool: return _has_message("still-here"), servers)
	check(ok, "留まった後も行が届く")
	s.disconnect_force()
	src.stop()
