extends SceneTree
## 第143段: 世界移動の追随後、地図の大きさが 7x7 に固まる件。
##
## 実地報告 (2026-11-27): v6 サーバ (ALNES) から従来サーバ
## (The United Kingdom NEO) へゲート移動すると、表示設定は
## 11x11 なのに地図が 7x7 のままになり、歩いても直らない。
## 手動で表示モードを切り替え直すと即座に 11x11 になる。
##
## 仕組み: 接続時は desired=121 / map_size=57 で入り、開いた
## 直後の「昇格試行」(_on_bigmap_session_opened) が 121 を
## 取りに行く。ところが転送追随では接続が開き直さない (セッ
## ションは開いたまま差し替わる) ので試行が再武装されず、
## 到着バーストが今の map_size=57 で size=57 を頼んだまま、
## 誰も 121 を頼み直さない。v6滞在中に昇格ペンディングは
## v6 分岐で消費されている。
##
## ここでは実転送 (フェイク v6 元 → フェイク従来先) を通し:
##  A) 追随完了後、クライアントが自力で #ex-map size=121 を
##     移動先へ送り直し、#m121 フレームで表示が 11 になる。
##  B) 移動先は最初から 121 対応 (手動相当の要求には応える)
##     = 固まる原因は再要求の欠落そのもの。
##
## 使い方: godot --headless --path . -s tests/test_stage143.gd
## 終了コード 0 = 全一致、1 = 不一致あり。

const Main := preload("res://scripts/main.gd")

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

	func count_of(text: String) -> int:
		var n := 0
		for line in received:
			if line == text:
				n += 1
		return n


func _m57_frame() -> PackedByteArray:
	var b := PackedByteArray()
	b.append_array("#m57 M S 00000000:".to_ascii_buffer())
	for i in 49:
		b.append(0x2E)
		b.append(0x80)
	b.append(0x20)
	b.append_array("\n#m57 .\n".to_ascii_buffer())
	return b


func _m121_frame() -> PackedByteArray:
	var b := PackedByteArray()
	b.append_array("#m121 M S 00000000:".to_ascii_buffer())
	for i in 121:
		b.append(0x2E)
		b.append(0x80)
	b.append(0x20)
	b.append_array("\n#m121 .\n".to_ascii_buffer())
	return b


func _initialize() -> void:
	call_deferred("_run")


## サーバ群を回しながら pred が真になるまで待つ (タブの _process
## がセッションを回すので、フレームを進めるだけでよい)。
func _wait_for(pred: Callable, servers: Array, timeout_msec: int = 6000) -> bool:
	var deadline := Time.get_ticks_msec() + timeout_msec
	while Time.get_ticks_msec() < deadline:
		for s in servers:
			s.poll()
		if pred.call():
			return true
		await process_frame
	for s in servers:
		s.poll()
	return pred.call()


func _run() -> void:
	var src := ByteServer.new()
	var dst := ByteServer.new()
	check(src.start(), "src listen")
	check(dst.start(), "dst listen")

	# --- Main を立てる (設定・タブ復元は隔離) ---
	var main: Node = Main.new()
	OS.execute("rm", ["-f", ProjectSettings.globalize_path("user://stage143_tabs.ini")])
	OS.execute("rm", ["-f", ProjectSettings.globalize_path("user://stage143 config.ini")])
	main.set("_tab_session_path", "user://stage143_tabs.ini")
	main.set("_config_path", "user://stage143 config.ini")
	root.add_child(main)
	await process_frame
	await process_frame
	var tab: Variant = main.call("_active_tab")
	check(tab != null, "active tab exists")
	var session: Variant = tab.get("session")

	# 表示設定は 11x11 (実地と同じ)。接続時の付け方は Main と
	# 同じ: desired=121 / map_size=57 で入る。
	session.desired_map_size = 121
	session.map_size = 57
	tab.call("connect_to", "127.0.0.1", src.port, "TESTID")
	var ok: bool = await _wait_for(
		func() -> bool: return src.received.has("#open TESTID"), [src])
	check(ok, "login reached v6 source")

	# v6 として受理させる (視界 33x25)。圧縮は本件と無関係
	# なので申し込まない。
	src.send_line("#name Tester")
	src.send_line("#ex-map view=33 25")
	src.send_line("#ex-switch move=diag")
	ok = await _wait_for(func() -> bool: return bool(session.v6_mode), [src])
	check(ok, "v6 mode accepted on source")
	# 昇格試行が v6 中に消費される時間を与える (実地の滞在相当)。
	ok = await _wait_for(
		func() -> bool: return not bool(tab.get("_bigmap_upgrade_pending")),
		[src], 3000)
	check(ok, "bigmap upgrade pending consumed during v6 stay")
	check(int(session.map_size) == 57, "map_size record still 57 on v6 world")

	# --- 転送: v6 元 → 従来先 ---
	src.send_line("#ch-srv 127.0.0.1 %d" % dst.port)
	ok = await _wait_for(
		func() -> bool: return dst.received.has("#reserve TESTID"), [src, dst])
	check(ok, "destination received #reserve")
	dst.send_line("#rsv-ok")
	ok = await _wait_for(
		func() -> bool: return src.count_of("#trans 127.0.0.1 %d" % dst.port) > 0,
		[src, dst])
	check(ok, "source received #trans")
	src.send_line("#trs-ok")
	ok = await _wait_for(
		func() -> bool: return dst.received.has("#ch-srv-ok"), [dst], 3000)
	check(ok, "transfer followed to destination")
	check(int(session.port) == dst.port, "session endpoint is destination")
	# 到着バーストは今の map_size で頼む (ここは仕様どおり)。
	check(dst.received.has("#ex-map size=57"), "arrival batch asked size=57")

	# 移動先は従来サーバ: プローブは断り、まず #m57 を出す。
	# プレイヤーが歩く = フレームが続く、という形で何度か送る。
	dst.send_line("#ex-map view=no")
	var got121 := false
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 6000:
		dst.send_raw(_m57_frame())
		got121 = await _wait_for(
			func() -> bool: return dst.received.has("#ex-map size=121"),
			[dst], 700)
		if got121:
			break
	check(int(tab.get("_map_dim_now")) == 7 or got121,
		"frames are 7x7 until renegotiation")
	check(got121, "client re-requests size=121 after transfer follow")
	check(int(session.map_size) == 121, "map_size record upgraded to 121")

	# 121 が届いたら移動先は #m121 を出す (最初から対応している)。
	if got121:
		dst.send_raw(_m121_frame())
		ok = await _wait_for(
			func() -> bool: return int(tab.get("_map_dim_now")) == 11,
			[dst], 3000)
		check(ok, "view becomes 11x11 on #m121 frames")
	else:
		# 再現確認: 手動切替相当なら即座に届く = 移動先は無実で、
		# 欠けているのは追随後の自動再要求だけ。
		tab.call("do_send_action", "M11x11")
		ok = await _wait_for(
			func() -> bool: return dst.received.has("#ex-map size=121"),
			[dst], 2000)
		check(ok, "manual M11x11 reaches destination (destination innocent)")

	tab.call("disconnect_force")
	src.stop()
	dst.stop()
	print("test_stage143: ", _checks, " checks, ", _failures, " failures")
	quit(1 if _failures > 0 else 0)
