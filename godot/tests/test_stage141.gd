extends SceneTree
## 第141段: 世界移動の完了 (`#trs-ok`) が、移動元サーバとの
## deflate 交渉済みの圧縮列の中に届いても認識できること。
##
## 不具合 (2026-11-26 実地報告): v6 サーバ (ALNES) から従来
## サーバへゲート移動すると、移動元の `#trs-ok` は圧縮されて
## 届くのに、移動手順中の読み取りが PhiInflate を通らないため
## 認識できず、移動が完了しない。移動元が接続を閉じると通常の
## 切断に見え、移動先へ自動で繋ぎ直すこともなかった。
## サーバ側の受け渡し自体は完了しており (移動先はキャラを
## 保存済み)、再接続すると移動先にいる。
##
## - A) deflate 交渉済みの移動元 → 従来の移動先: 圧縮された
##   `#ch-srv` で手順が始まり、圧縮された `#trs-ok` で完了し、
##   移動先が `#ch-srv-ok` を受け取ること。
## - B) 平文の移動元 → 平文の移動先 (従来経路の回帰確認)。
## - C) 圧縮された `#trs-no` で移動元に留まり、接続が生きて
##   次の圧縮行も届くこと。
##
## 圧縮列は zlib の無圧縮 (stored) ブロックで組み立てる
## (同期フラッシュ相当の空ブロック付き)。クライアント側の
## 増分 inflate は形式どおりの deflate 列として処理できる。
##
## 使い方: godot --headless --path . -s tests/test_stage141.gd
## 終了コード 0 = 全一致、1 = 不一致あり。

var _checks := 0
var _failures := 0


func check(cond: bool, label: String) -> void:
	_checks += 1
	if not cond:
		_failures += 1
		print("FAIL: ", label)


class ByteServer:
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

	func send_raw(bytes: PackedByteArray) -> void:
		if peer != null:
			peer.put_data(bytes)

	func close_peer() -> void:
		if peer != null:
			peer.disconnect_from_host()
			peer = null


static func zlib_header() -> PackedByteArray:
	return PackedByteArray([0x78, 0x9C])


static func zlib_segment(text: String) -> PackedByteArray:
	## 同期フラッシュで区切られた 1 セグメント分の zlib 列。
	## stored ブロック (非最終) + 空の stored ブロック。
	var data := text.to_ascii_buffer()
	var out := PackedByteArray()
	out.append(0)
	out.append(data.size() & 0xFF)
	out.append((data.size() >> 8) & 0xFF)
	var nlen := (~data.size()) & 0xFFFF
	out.append(nlen & 0xFF)
	out.append((nlen >> 8) & 0xFF)
	out.append_array(data)
	out.append_array(PackedByteArray([0, 0, 0, 0xFF, 0xFF]))
	return out


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


func _new_session() -> PhiSession:
	_events.clear()
	_errors.clear()
	_closed = false
	var s := PhiSession.new()
	s.event_received.connect(func(e: Dictionary) -> void: _events.append(e))
	s.session_error.connect(func(m: String) -> void: _errors.append(m))
	s.session_closed.connect(func() -> void: _closed = true)
	_session = s
	return s


## 移動元へログインし、#trans が移動元へ送られる所まで進める。
## v6 の時は deflate 交渉まで済ませ、#ch-srv は圧縮で送る。
func _drive_to_trans(src: ByteServer, dst: ByteServer, v6: bool) -> PhiSession:
	var s := _new_session()
	s.connect_to("127.0.0.1", src.port, "TESTID")
	var ok: bool = await _wait_for(
		func() -> bool: return src.received.has("#open TESTID"), [src])
	check(ok, "login reached source server")
	if v6:
		ok = await _wait_for(
			func() -> bool: return src.received.has("#ex-switch compress=deflate"),
			[src])
		check(ok, "probe reached source server")
		src.send_line("#name Tester")
		src.send_line("#ex-map view=25 19")
		src.send_line("#ex-switch move=diag")
		src.send_line("#ex-switch compress=deflate")
		ok = await _wait_for(
			func() -> bool: return s.v6_mode and s.v6_compress_on(), [src])
		check(ok, "deflate negotiated (v6_mode + compress on)")
		src.send_raw(zlib_header() + zlib_segment("DM > compressed hello\n"))
		ok = await _wait_for(
			func() -> bool: return _texts().has("DM > compressed hello"), [src])
		check(ok, "compressed line delivered before transfer")
		src.send_raw(zlib_segment("#ch-srv 127.0.0.1 %d\n" % dst.port))
	else:
		src.send_line("#ch-srv 127.0.0.1 %d" % dst.port)
	ok = await _wait_for(
		func() -> bool: return dst.received.has("#reserve TESTID"), [src, dst])
	check(ok, "destination received #reserve")
	dst.send_line("#rsv-ok")
	ok = await _wait_for(
		func() -> bool: return src.received.has("#trans 127.0.0.1 %d" % dst.port),
		[src, dst])
	check(ok, "source received #trans")
	check(s.is_transferring(), "session is transferring")
	return s


func _scenario_a() -> void:
	print("-- A) deflate source -> legacy destination --")
	var src := ByteServer.new()
	var dst := ByteServer.new()
	check(src.start(), "src listen")
	check(dst.start(), "dst listen")
	var s: PhiSession = await _drive_to_trans(src, dst, true)
	var t0 := Time.get_ticks_msec()
	src.send_raw(zlib_segment("#trs-ok\n"))
	var done: bool = await _wait_for(
		func() -> bool: return s.is_open() and not s.is_transferring() \
			and s.port == dst.port,
		[src, dst], 3000)
	var elapsed := Time.get_ticks_msec() - t0
	check(done, "transfer completes on compressed #trs-ok (elapsed %d msec)" % elapsed)
	print("   #trs-ok -> completion: ", elapsed, " msec")
	if done:
		var ok: bool = await _wait_for(
			func() -> bool: return dst.received.has("#ch-srv-ok"), [dst], 2000)
		check(ok, "destination received #ch-srv-ok")
		dst.send_line("DM > arrived plainly")
		ok = await _wait_for(
			func() -> bool: return _texts().has("DM > arrived plainly"),
			[dst], 2000)
		check(ok, "plain line delivered on destination connection")
		await _teardown(s, [src, dst])
	else:
		# 不具合の再現確認: 移動元が閉じると通常切断に見え、
		# 移動先へは繋ぎ直されない。
		src.close_peer()
		await _pump([src, dst], 40)
		check(_closed, "session closed after source close (symptom)")
		check(s.port == src.port, "session never followed to destination")
	await _teardown(s, [src, dst])
	src.stop()
	dst.stop()


func _scenario_b() -> void:
	print("-- B) plain source -> plain destination --")
	var src := ByteServer.new()
	var dst := ByteServer.new()
	check(src.start(), "src listen")
	check(dst.start(), "dst listen")
	var s: PhiSession = await _drive_to_trans(src, dst, false)
	src.send_line("#trs-ok")
	var done: bool = await _wait_for(
		func() -> bool: return s.is_open() and not s.is_transferring() \
			and s.port == dst.port,
		[src, dst], 3000)
	check(done, "plain transfer completes")
	if done:
		var ok: bool = await _wait_for(
			func() -> bool: return dst.received.has("#ch-srv-ok"), [dst], 2000)
		check(ok, "destination received #ch-srv-ok (plain)")
	await _teardown(s, [src, dst])
	src.stop()
	dst.stop()


func _scenario_c() -> void:
	print("-- C) compressed #trs-no keeps the source session --")
	var src := ByteServer.new()
	var dst := ByteServer.new()
	check(src.start(), "src listen")
	check(dst.start(), "dst listen")
	var s: PhiSession = await _drive_to_trans(src, dst, true)
	src.send_raw(zlib_segment("#trs-no\n"))
	var stayed: bool = await _wait_for(
		func() -> bool: return s.is_open() and not s.is_transferring() \
			and s.port == src.port,
		[src, dst], 3000)
	check(stayed, "session stays on source after compressed #trs-no")
	check(_texts().has("転送失敗"), "transfer failure noticed")
	src.send_raw(zlib_segment("DM > still here\n"))
	var ok: bool = await _wait_for(
		func() -> bool: return _texts().has("DM > still here"), [src], 2000)
	check(ok, "compressed line still delivered after failed transfer")
	await _teardown(s, [src, dst])
	src.stop()
	dst.stop()


func _teardown(s: PhiSession, servers: Array) -> void:
	## 読取りスレッドを止めてから終わる (終了コードを汚さない)。
	if s != null and s.is_open():
		s.disconnect_force()
	await _pump(servers, 5)


func _run() -> void:
	await _scenario_a()
	await _scenario_b()
	await _scenario_c()
	await _teardown(_session, [])
	print("stage141: ", _checks, " checks, ", _failures, " failures")
	quit(1 if _failures > 0 else 0)
