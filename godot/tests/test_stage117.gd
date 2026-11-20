extends SceneTree
## 第117段: 切断直前にサーバが送る行が、接続終了より先に
## 表示されること。
## - 正常ログアウト: 「セーブ中...」「また会いましょう」が
##   #close と一緒に届いても捨てられない (エラーにもならない)。
## - 死亡切断: 殺されたメッセージを送って即閉じられても、
##   そのメッセージが届く (プレイヤーが切断理由を分かる)。

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

	func close_peer() -> void:
		if peer != null:
			peer.disconnect_from_host()
			peer = null


var _session: PhiSession = null
var _events: Array = []
var _errors: Array = []
var _closed := false


func _initialize() -> void:
	call_deferred("_run")


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


func _pump(servers: Array, frames: int = 30) -> void:
	for i in frames:
		if _session != null:
			_session.poll()
		for s in servers:
			s.poll()
		await process_frame


func _texts() -> Array:
	var out: Array = []
	for e in _events:
		if str(e.get("type", "")) == "message":
			out.append(str(e.get("text", "")))
	return out


func _login_pair() -> Array:
	var srv := FakeServer.new()
	check(srv.start(), "server listen")
	_events.clear()
	_errors.clear()
	_closed = false
	var s := PhiSession.new()
	s.event_received.connect(func(e: Dictionary) -> void: _events.append(e))
	s.session_error.connect(func(m: String) -> void: _errors.append(m))
	s.session_closed.connect(func() -> void: _closed = true)
	s.connect_to("127.0.0.1", srv.port, "TESTID")
	_session = s
	var ok: bool = await _wait_for(func() -> bool: return srv.received.has("#open TESTID"), [srv])
	check(ok, "login reached server")
	srv.send_line("#name Tester")
	await _pump([srv], 10)
	check(s.is_open(), "session open")
	return [srv, s]


func _run() -> void:
	# --- A) 正常ログアウトの別れの行 ---
	var pair_a: Array = await _login_pair()
	var srv_a: FakeServer = pair_a[0]
	var ses_a: PhiSession = pair_a[1]
	ses_a.disconnect_graceful()
	var got_exit: bool = await _wait_for(func() -> bool: return srv_a.received.has("exit"), [srv_a])
	check(got_exit, "exit sent for graceful logout")
	srv_a.send_line("セーブ中...")
	srv_a.send_line("また会いましょう。")
	srv_a.send_line("#close")
	srv_a.close_peer()
	await _pump([srv_a], 40)
	var texts_a := _texts()
	check(texts_a.has("セーブ中..."), "farewell line 1 shown: %s" % str(texts_a))
	check(texts_a.has("また会いましょう。"), "farewell line 2 shown")
	check(_closed, "session closed after logout")
	check(_errors.is_empty(), "no error on graceful logout: %s" % str(_errors))
	srv_a.stop()

	# --- B) 死亡切断のメッセージ ---
	var pair_b: Array = await _login_pair()
	var srv_b: FakeServer = pair_b[0]
	srv_b.send_line("DM > Tester は Goblin に殺された.")
	srv_b.close_peer()
	await _pump([srv_b], 40)
	var texts_b := _texts()
	check(texts_b.has("DM > Tester は Goblin に殺された."), "death message shown: %s" % str(texts_b))
	check(_closed, "session closed after death")
	srv_b.stop()
	print("stage117: ", _checks, " checks, ", _failures, " failures")
	quit(1 if _failures > 0 else 0)
