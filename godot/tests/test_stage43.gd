extends SceneTree
## 第43段: Mac 実機報告 4 件の修正。
## (1) 修飾なし S キー (看板を書く) がキー表から漏れていた。
## (2) P キー (支払い) も同じ漏れ。ask アクションへつなぐ。
## (3) ログ表示でタグが落ち、看板の読み返しがプレビューと違う
##     見た目になっていた。タグ入りの行はタグを効かせて出す。
## (4) 看板エディタに Shift+Enter の書き込みが無い。
## (5) priv 窓は開いた時に #ulist を送り、宛先を取り直す。

var _checks := 0
var _failures := 0


func check(cond: bool, label: String) -> void:
	_checks += 1
	if not cond:
		_failures += 1
		print("FAIL: ", label)


func _initialize() -> void:
	_run.call_deferred()


func _key(code_key: Key) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.pressed = true
	ev.keycode = code_key
	ev.physical_keycode = code_key
	return ev


func _run() -> void:
	# (1) キー表: S で write、P は送信表には無い (ask で受ける)
	check(PhiKeys.key_send("KeyS") == "write", "key_send KeyS == write")
	check(PhiKeys.key_send("KeyS", true) == "", "key_send Shift+KeyS is empty")
	check(PhiKeys.key_send("KeyA") == "read", "key_send KeyA unchanged")
	check(PhiKeys.key_send("KeyP") == "", "key_send KeyP stays empty (ask path)")

	# (3) タグ入り行の BBCode 化 (関数レベル)
	var bb := PhiCharacter.tagged_bbcode_line("/*color=red*/赤い/*.*/ 通常", 16)
	check(bb.contains("[color=red]赤い[/color]"), "tagged line: color applied (%s)" % bb)
	check(bb.contains("通常"), "tagged line: plain part kept")
	var bb2 := PhiCharacter.tagged_bbcode_line("/*size=large*/大/*.*/", 16)
	check(bb2.contains("[font_size=24]大[/font_size]"), "tagged line: size applied (%s)" % bb2)
	var bb3 := PhiCharacter.tagged_bbcode_line("見て http://example.jp/x です", 16)
	check(bb3.contains("[url=http://example.jp/x]"), "tagged line: URL linked")
	var bb4 := PhiCharacter.tagged_bbcode_line("a[b", 16)
	check(bb4.contains("[lb]"), "tagged line: brackets escaped")
	var bb5 := PhiCharacter.tagged_bbcode_line("/*style=bold*/太/*.*/", 16)
	check(bb5.contains("[b]太[/b]"), "tagged line: bold applied")

	var ps := load("res://main.tscn") as PackedScene
	var main: Node = ps.instantiate()
	root.add_child(main)
	await create_timer(1.0).timeout
	var tab: PhiCharacter = main.call("_create_tab")
	main.call("_activate_tab", tab)
	root.gui_release_focus()

	# (2) P キーで Pay の ask が飛び、S キーで write が
	# 送られる (当初の割り当て)。
	var captured: Array = []
	tab.action_requested.connect(func(name: String) -> void: captured.append(name))
	check(tab.handle_key(_key(KEY_P)), "handle_key handles P")
	check(captured == ["Pay"], "P emits the Pay action (got %s)" % [captured])
	captured.clear()
	var queue: Array = tab.session.get("_send_queue")
	queue.clear()
	check(tab.handle_key(_key(KEY_S)), "handle_key handles S")
	check(queue == ["write"], "S sends write (got %s)" % [queue])
	queue.clear()

	# (3) ログ統合: タグ入りの行はタグが効いた表示になり、
	# 記録 (display) は素の文字のまま
	var before: int = tab.get("_log_lines").size()
	tab.log_message("log", "赤い看板", "/*color=red*/赤い看板/*.*/")
	var parsed := tab.log_view.get_parsed_text()
	check(parsed.contains("赤い看板"), "log shows sign text")
	check(not parsed.contains("/*color"), "log does not leak tag literals")
	var entries: Array = tab.get("_log_lines")
	check(entries.size() == before + 1, "log line recorded")
	check(str(entries[entries.size() - 1].get("display", "")) == "赤い看板", "recorded display stays plain")

	# (4) 看板エディタ: Shift+Enter で送信、素の Enter では送らない
	var win := PhiMEditWindow.new()
	root.add_child(win)
	var sent: Array = []
	win.send_requested.connect(func(lines: Array) -> void: sent.append(lines))
	win.show_editor("Guest")
	await create_timer(0.3).timeout
	var edit: TextEdit = win.get("_edit")
	edit.text = "1行目\n2行目"
	var plain_enter := _key(KEY_ENTER)
	edit.gui_input.emit(plain_enter)
	check(sent.is_empty(), "medit: plain Enter does not send")
	check(win.visible, "medit: still open after plain Enter")
	var shift_enter := _key(KEY_ENTER)
	shift_enter.shift_pressed = true
	edit.gui_input.emit(shift_enter)
	check(sent.size() == 1, "medit: Shift+Enter sends")
	if sent.size() == 1:
		check(sent[0] == ["1行目", "2行目"], "medit: sent lines match (got %s)" % [sent[0]])
	check(not win.visible, "medit: closed after Shift+Enter")
	win.queue_free()

	# (5) priv: 開いたら #ulist で宛先が入る (実サーバが要る。
	# 届かない環境では飛ばす)。
	await _priv_live_check(main)

	main.queue_free()
	print("stage43: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _priv_live_check(main: Node) -> void:
	var tab1: PhiCharacter = main.call("_create_tab")
	var tab2: PhiCharacter = main.call("_create_tab")
	main.call("_connect_tab", tab1, "127.0.0.1", 20017, "guest")
	main.call("_connect_tab", tab2, "127.0.0.1", 20017, "master")
	var waited := 0.0
	while waited < 8.0:
		if tab1.is_session_open() and tab2.is_session_open():
			break
		await create_timer(0.25).timeout
		waited += 0.25
	if not (tab1.is_session_open() and tab2.is_session_open()):
		print("SKIP priv live check (server unreachable)")
		return
	# ログイン (#name) まで待つ
	waited = 0.0
	while waited < 8.0:
		if not tab1.player_name().is_empty() and not tab2.player_name().is_empty():
			break
		await create_timer(0.25).timeout
		waited += 0.25
	main.call("_activate_tab", tab1)
	main.call("_show_priv_window")
	var win: PhiPrivWindow = main.get("_priv_window")
	check(win != null and win.visible, "priv window opens")
	waited = 0.0
	var names: Array = []
	while waited < 6.0:
		names = win.recipient_names()
		if not names.is_empty():
			break
		await create_timer(0.25).timeout
		waited += 0.25
	check(not names.is_empty(), "priv recipients arrive after open (got %s)" % [names])
	check(not names.has(tab1.player_name()), "priv recipients exclude self")
	tab1.disconnect_graceful()
	tab2.disconnect_graceful()
	await create_timer(0.5).timeout
