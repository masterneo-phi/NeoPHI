extends SceneTree
## 第9段のテスト: ダイアログの角・装飾と、WPHI 式の接続まわり。
## アクション表(強制切断・全キャラ接続/切断/強制切断の種類・並び・
## アクセラレータ・有効条件)、豪華ダイアログ用テクスチャの生成、
## セッションの強制切断が `#x` を送らないこと(ループバックで実地に
## 確認)、通常切断が `#x` を送ること、タブの再接続可否の判定。
##
## 使い方: godot --headless --path . -s tests/test_stage9.gd
## 終了コード 0 = 全一致、1 = 不一致あり。

var _failures := 0
var _checks := 0


func _check(cond: bool, label: String) -> void:
	_checks += 1
	if not cond:
		failures_add(label)


func _check_eq(a: Variant, b: Variant, label: String) -> void:
	_checks += 1
	if a != b:
		failures_add(label + " (got " + str(a) + ", want " + str(b) + ")")


func failures_add(label: String) -> void:
	_failures += 1
	printerr("FAIL: ", label)


func _initialize() -> void:
	_test_actions()
	_test_dialog_texture()
	_test_session_disconnect()
	_test_can_reconnect()
	_test_status_exp()
	print("test_stage9: ", _checks, " checks, ", _failures, " failures")
	quit(1 if _failures > 0 else 0)


# -- アクション表 -------------------------------------------------------------

func _test_actions() -> void:
	_check_eq(PhiActions.kind_of("ForceClose"), "force-disconnect", "ForceClose kind")
	_check_eq(PhiActions.kind_of("OpenAll"), "connect-all", "OpenAll kind")
	_check_eq(PhiActions.kind_of("CloseAll"), "disconnect-all", "CloseAll kind")
	_check_eq(PhiActions.kind_of("ForceCloseAll"), "force-disconnect-all", "ForceCloseAll kind")
	_check_eq(str(PhiActions.get_action("ForceClose").get("caption", "")), "強制切断", "ForceClose caption")
	_check_eq(str(PhiActions.get_action("OpenAll").get("caption", "")), "全キャラを接続", "OpenAll caption")
	_check_eq(str(PhiActions.get_action("CloseAll").get("caption", "")), "全キャラを切断", "CloseAll caption")
	_check_eq(str(PhiActions.get_action("ForceCloseAll").get("caption", "")), "全キャラを強制切断", "ForceCloseAll caption")
	_check_eq(PhiActions.accelerator_for("ForceClose"), 0, "accel ForceClose removed (stage111)")
	_check_eq(PhiActions.accelerator_for("ForceCloseAll"), KEY_PAUSE | KEY_MASK_ALT, "accel ForceCloseAll = Alt+Pause")
	_check(not PhiActions.enabled_when("ForceClose", false), "ForceClose disabled when offline")
	_check(PhiActions.enabled_when("ForceClose", true), "ForceClose enabled when online")
	_check(PhiActions.enabled_when("OpenAll", false), "OpenAll always enabled")
	_check(PhiActions.enabled_when("ForceCloseAll", false), "ForceCloseAll always enabled")
	# ファイルメニューの先頭は WPHI と同じ接続まわりの並び。
	var file_items: Array = []
	for menu in PhiActions.MENUS:
		if str(menu["name"]) == "ファイル":
			file_items = menu["items"]
	var order := ["Open", "Close", "ForceClose", "OpenAll", "CloseAll", "ForceCloseAll"]
	_check(file_items.size() >= order.size(), "file menu has connect group")
	for i in mini(order.size(), file_items.size()):
		_check_eq(str(file_items[i]), order[i], "file menu order %d" % i)


# -- 豪華ダイアログのテクスチャ -------------------------------------------------

func _test_dialog_texture() -> void:
	_check(UiStyle.dialog_texture(Vector2i(4, 4)) == null, "dialog texture tiny is null")
	var tex := UiStyle.dialog_texture(Vector2i(480, 560))
	_check(tex != null, "dialog texture created")
	_check(UiStyle.dialog_texture(Vector2i(480, 560)) == tex, "dialog texture cached")
	var img := tex.get_image()
	_check_eq(img.get_pixel(0, 0).a, 0.0, "dialog texture corner transparent")
	var rim := img.get_pixel(240, 2)
	_check(rim.a > 0.9, "dialog texture rim opaque")
	_check(rim.r > rim.b + 0.1, "dialog texture rim is gold")
	var mid := img.get_pixel(240, 300)
	_check(mid.a > 0.9, "dialog texture center opaque")
	_check(mid.r < 0.5, "dialog texture center is dark metal")


# -- セッションの切断(ループバック) ---------------------------------------------

func _collect(session: PhiSession, peer: StreamPeerTCP, msec: int) -> String:
	## セッションを回しながら、相手側が受け取った文字列を集める。
	var got := PackedByteArray()
	var deadline := Time.get_ticks_msec() + msec
	while Time.get_ticks_msec() < deadline:
		session.poll()
		if peer != null:
			peer.poll()
			var avail := peer.get_available_bytes()
			if avail > 0:
				var res := peer.get_data(avail)
				if int(res[0]) == OK:
					got.append_array(res[1])
		OS.delay_msec(10)
	return Cp932.decode(got)


func _open_test_session(server: TCPServer, port: int) -> Array:
	## [セッション, 相手側]。開くまで回す(最大3秒)。
	var session := PhiSession.new()
	session.connect_to("127.0.0.1", port, "guest")
	var peer: StreamPeerTCP = null
	var deadline := Time.get_ticks_msec() + 3000
	while Time.get_ticks_msec() < deadline and not session.is_open():
		session.poll()
		if peer == null and server.is_connection_available():
			peer = server.take_connection()
		OS.delay_msec(10)
	return [session, peer]


func _test_session_disconnect() -> void:
	var server := TCPServer.new()
	var port := 39217
	_check_eq(server.listen(port, "127.0.0.1"), OK, "test server listen")
	# 強制切断: ログインは届くが、`#x` は届かない。
	var pair1 := _open_test_session(server, port)
	var s1: PhiSession = pair1[0]
	var peer1: StreamPeerTCP = pair1[1]
	_check(s1.is_open(), "session1 open")
	var received := _collect(s1, peer1, 300)
	_check(received.contains("#open"), "session1 login sent")
	s1.disconnect_force()
	_check(not s1.is_open(), "session1 closed after force")
	var after1 := _collect(s1, peer1, 300)
	_check(not after1.contains("#x"), "force disconnect sends no #x")
	# 通常切断: `#x` が届く。
	var pair2 := _open_test_session(server, port)
	var s2: PhiSession = pair2[0]
	var peer2: StreamPeerTCP = pair2[1]
	_check(s2.is_open(), "session2 open")
	_collect(s2, peer2, 300)
	s2.disconnect_graceful()
	var after2 := _collect(s2, peer2, 300)
	_check(after2.contains("#x"), "graceful disconnect sends #x")
	server.stop()


# -- ステータス表示の EXP --------------------------------------------------------

func _test_status_exp() -> void:
	# 並びは F/W/M/C/EXP/GP(EXP は C と GP の間)。
	var keys: Array = []
	for item in StatusPanel.STATUS_ITEMS:
		keys.append(str(item[1]))
	_check_eq(keys, ["f", "w", "m", "c", "exp", "gp"], "status items order with exp")
	_check_eq(StatusPanel.status_label_color("exp"), Color(0.45, 0.85, 1.0), "exp label color")
	# パーサが拾った exp が、そのままステータス表示の値になる。
	var panel := StatusPanel.new()
	panel.set_status({"exp": 12345, "gp": 777})
	_check_eq(int(panel.debug_values()["exp"]), 12345, "status exp value kept")
	_check_eq(int(panel.debug_values()["gp"]), 777, "status gp value kept")
	panel.set_status({"gp": 778})
	_check_eq(int(panel.debug_values()["exp"]), 12345, "status exp survives partial update")
	panel.free()


# -- 再接続の可否 ---------------------------------------------------------------

func _test_can_reconnect() -> void:
	var tab := PhiCharacter.new()
	_check(not tab.can_reconnect(), "fresh tab cannot reconnect")
	tab.host = "127.0.0.1"
	tab.port = 20017
	_check(not tab.can_reconnect(), "tab without char id cannot reconnect")
	tab.session.char_id = "guest"
	_check(tab.can_reconnect(), "tab with host and id can reconnect")
	tab.free()
