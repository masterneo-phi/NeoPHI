extends SceneTree
## 第35段: サーバからの #close を受けたら、ソケットの死活検出を
## 待たずに切断として確定させる。ほかのクライアントに接続を
## 切り替えられた時は、その理由もログに出る。

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


var _main: Node = null


func _initialize() -> void:
	_run.call_deferred()


func _wait_for(cond: Callable, servers: Array, timeout_sec: float = 5.0) -> bool:
	var waited := 0.0
	while waited < timeout_sec:
		for s in servers:
			s.poll()
		if cond.call():
			return true
		await create_timer(0.05).timeout
		waited += 0.05
	return cond.call()


func _log_has(tab: Node, needle: String) -> bool:
	for entry in tab.get("_log_lines"):
		if str(entry.get("display", "")).contains(needle):
			return true
	return false


func _scenario(by_other: bool) -> Node:
	var srv := FakeServer.new()
	check(srv.start(), "listen")
	var tab: Node = _main.call("_create_tab")
	_main.call("_connect_tab", tab, "127.0.0.1", srv.port, "TESTID")
	var ok: bool = await _wait_for(func() -> bool: return srv.received.has("#open TESTID"), [srv])
	check(ok, "ログインが届く")
	ok = await _wait_for(func() -> bool: return tab.call("is_session_open"), [srv])
	check(ok, "セッションが開く")
	if by_other:
		srv.send_line("accessed by other clinet!")
	srv.send_line("#close")
	# ソケットは閉じない。#close だけで切断が確定するかを見る。
	ok = await _wait_for(func() -> bool: return not tab.call("is_session_open"), [srv], 3.0)
	check(ok, "#close でセッションが閉じる (by_other=%s)" % str(by_other))
	check(_log_has(tab, "サーバから切断されました"), "#close のログが出る")
	if by_other:
		check(_log_has(tab, "ほかのクライアントでログインされたため、接続が切り替わりました"), "切り替えの理由が出る")
	else:
		check(_log_has(tab, "接続が閉じました"), "通常の切断ログが出る")
		check(not _log_has(tab, "ほかのクライアントでログインされたため"), "切り替えの理由は出ない")
	srv.stop()
	return tab


func _run() -> void:
	var ps := load("res://main.tscn") as PackedScene
	_main = ps.instantiate()
	root.add_child(_main)
	await create_timer(1.0).timeout
	await _scenario(true)
	await _scenario(false)
	print("test_stage35: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)
