extends SceneTree
## 第36段: 実地テストで見つけた3件の修正 + Talk のテスト。
## (1) 吹き出しは話者ごとに積み上げて残す (速い NPC の台詞が
##     読み飛ばされない)。
## (2) 切断は `exit` を送ってサーバの `#close` を待つ正常
##     ログアウトにする (サーバ側で「ログアウトした」になる)。
## (3) 固定魔法 (cast + 詠唱) では魔法選択リストを表示しない。
## (4) Talk アクション (hi) と H キーの割り当て。

var _checks := 0
var _failures := 0
var _main: Node = null


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


func _test_bubble_stack() -> void:
	var mv := MapView.new()
	mv.show_bubble("王妃", "一文目")
	mv.show_bubble("王妃", "二文目")
	mv.show_bubble("王妃", "三文目")
	var stack: Array = mv.get("_bubbles").get("王妃", [])
	check(stack.size() == 3, "吹き出しが3つ積み上がる")
	check(str(stack[0].get("text", "")) == "一文目", "一番下が古い文")
	check(str(stack[2].get("text", "")) == "三文目", "一番上が新しい文")
	mv.show_bubble("王妃", "三文目")
	stack = mv.get("_bubbles").get("王妃", [])
	check(stack.size() == 3, "同じ文の繰り返しは積み増ししない")
	mv.show_bubble("王妃", "四文目")
	mv.show_bubble("王妃", "五文目")
	stack = mv.get("_bubbles").get("王妃", [])
	check(stack.size() == MapView.BUBBLE_STACK_MAX, "保持は上限まで")
	check(str(stack[0].get("text", "")) == "二文目", "上限を超えたら古い文から落ちる")
	# 期限切れの文だけが落ち、話者の残りは残る
	stack[0]["expire"] = 0.0
	mv.set("_bubbles", {"王妃": stack})
	mv._process(0.05)
	var after: Dictionary = mv.get("_bubbles")
	check(after.has("王妃"), "期限切れがあっても話者は残る")
	check(int(after.get("王妃", []).size()) == MapView.BUBBLE_STACK_MAX - 1, "期限切れの文だけ落ちる")
	mv.free()


func _test_fixed_spell_text() -> void:
	check(PhiActions.is_fixed_spell_text("cast\neagle eye"), "cast+詠唱は固定魔法")
	check(not PhiActions.is_fixed_spell_text("cast"), "cast 単体は対象外")
	check(not PhiActions.is_fixed_spell_text("cast\n#ex-switch eagleeye=form"), "cast の次が # 行なら対象外")
	check(PhiActions.is_fixed_spell_text("#ex-switch eagleeye=text\ncast\neagle eye\n#ex-switch eagleeye=form"), "EagleEyeText も固定魔法")
	check(not PhiActions.is_fixed_spell_text("hi"), "hi は対象外")
	check(not PhiActions.is_fixed_spell_text("cast\n"), "詠唱が空なら対象外")
	check(PhiActions.is_fixed_spell_text("cast\nsearch\n王妃"), "Search のまとめ送りも固定魔法")


func _test_talk_action() -> void:
	check(PhiActions.send_text_for("Talk") == "hi", "Talk は hi を送る")
	check(PhiActions.kind_of("Talk") == "send", "Talk は send アクション")
	check(not PhiActions.enabled_when("Talk", false), "Talk は未接続では無効")
	check(PhiActions.enabled_when("Talk", true), "Talk は接続時に有効")
	var in_menu := false
	for menu in PhiActions.MENUS:
		if str(menu.get("name", "")) == "行動" and (menu.get("items", []) as Array).has("Talk"):
			in_menu = true
	check(in_menu, "Talk が行動メニューにある")
	check(int(PhiActions.ACCELERATORS.get("Talk", 0)) == 0, "Talk にアクセラレータは無い (第111段で廃止)")


func _connect_tab(srv: FakeServer) -> Node:
	var tab: Node = _main.call("_create_tab")
	_main.call("_connect_tab", tab, "127.0.0.1", srv.port, "TESTID")
	var ok: bool = await _wait_for(func() -> bool: return srv.received.has("#open TESTID"), [srv])
	check(ok, "ログインが届く")
	ok = await _wait_for(func() -> bool: return tab.call("is_session_open"), [srv])
	check(ok, "セッションが開く")
	return tab


func _test_logout_exit() -> void:
	var srv := FakeServer.new()
	check(srv.start(), "listen (logout)")
	var tab := await _connect_tab(srv)
	srv.send_line("#name テスト")
	await _wait_for(func() -> bool: return str(tab.get("_player_name")) == "テスト", [srv])
	tab.call("disconnect_graceful")
	var ok: bool = await _wait_for(func() -> bool: return srv.received.has("exit"), [srv], 3.0)
	check(ok, "切断で exit が送られる")
	check(not srv.received.has("#x"), "exit の前に #x は送られない")
	check(bool(tab.call("is_session_open")), "#close までは接続が開いたまま")
	check(bool(tab.get("session").call("is_logout_pending")), "ログアウト完了待ちになる")
	srv.send_line("#close")
	ok = await _wait_for(func() -> bool: return not tab.call("is_session_open"), [srv], 3.0)
	check(ok, "#close で切断が確定する")
	check(_log_has(tab, "接続が閉じました"), "通常の切断ログが出る")
	check(not _log_has(tab, "サーバから切断されました"), "自分から閉じた時はサーバ切断のログは出ない")
	srv.stop()


func _test_logout_fallback() -> void:
	var srv := FakeServer.new()
	check(srv.start(), "listen (fallback)")
	var tab := await _connect_tab(srv)
	srv.send_line("#name テスト")
	await _wait_for(func() -> bool: return str(tab.get("_player_name")) == "テスト", [srv])
	tab.call("disconnect_graceful")
	await _wait_for(func() -> bool: return srv.received.has("exit"), [srv], 3.0)
	# サーバが #close を返さないまま期限を過ぎたことにする
	tab.get("session").set("_logout_deadline", 0.0)
	var ok: bool = await _wait_for(func() -> bool: return srv.received.has("#x"), [srv], 3.0)
	check(ok, "期限切れで #x が送られる")
	ok = await _wait_for(func() -> bool: return not tab.call("is_session_open"), [srv], 3.0)
	check(ok, "期限切れで切断が確定する")
	srv.stop()


func _test_logout_before_login() -> void:
	var srv := FakeServer.new()
	check(srv.start(), "listen (pre-login)")
	var tab := await _connect_tab(srv)
	tab.call("disconnect_graceful")
	var ok: bool = await _wait_for(func() -> bool: return srv.received.has("#x"), [srv], 3.0)
	check(ok, "未ログインの切断は #x が送られる")
	check(not srv.received.has("exit"), "未ログインでは exit は送られない")
	srv.stop()


func _test_cast_list_suppressed() -> void:
	var srv := FakeServer.new()
	check(srv.start(), "listen (cast)")
	var tab := await _connect_tab(srv)
	srv.send_line("#name テスト")
	await _wait_for(func() -> bool: return str(tab.get("_player_name")) == "テスト", [srv])
	tab.call("do_send_action", "EagleEye")
	check(int(tab.get("_suppress_lists")) == 1, "固定魔法のアクションでリスト抑止が立つ")
	# 系統魔法扱いなので、まず unequip が送られ、装備リストで
	# 答えると cast + 詠唱が送られる (第22段の流れ)。
	var ok2: bool = await _wait_for(func() -> bool: return srv.received.has("unequip"), [srv], 3.0)
	check(ok2, "固定魔法では unequip が先に送られる")
	srv.send_line("#list")
	srv.send_line("     [/*color=cyan*/ 1/*.*/] ロングソード                    Wp  :  5 [/*color=red*/Wpn/*.*/]")
	srv.send_line("#end-list")
	srv.send_line("外す装備を選択して下さい")
	ok2 = await _wait_for(func() -> bool: return srv.received.has("eagle eye"), [srv], 3.0)
	check(ok2, "装備を外してから詠唱が送られる")
	# ここでサーバが出す魔法選択リストが、抑止で表示されない。
	srv.send_line("#list")
	srv.send_line("[4] Eagle eye")
	srv.send_line("#end-list")
	var panel: Control = tab.get("_list_panel")
	await _wait_for(func() -> bool: return int(tab.get("_suppress_lists")) == 0, [srv], 3.0)
	check(not panel.visible, "固定魔法のリストは表示されない")
	# cast 単体では抑止されず、リストが表示される
	tab.call("send_text", "cast")
	check(int(tab.get("_suppress_lists")) == 0, "cast 単体では抑止されない")
	srv.send_line("#list")
	srv.send_line("[4] Eagle eye")
	srv.send_line("#end-list")
	var ok: bool = await _wait_for(func() -> bool: return panel.visible, [srv], 3.0)
	check(ok, "cast 単体のリストは表示される")
	srv.stop()


func _run() -> void:
	_test_bubble_stack()
	_test_fixed_spell_text()
	_test_talk_action()
	var ps := load("res://main.tscn") as PackedScene
	_main = ps.instantiate()
	root.add_child(_main)
	await create_timer(1.0).timeout
	await _test_logout_exit()
	await _test_logout_fallback()
	await _test_logout_before_login()
	await _test_cast_list_suppressed()
	print("test_stage36: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)
