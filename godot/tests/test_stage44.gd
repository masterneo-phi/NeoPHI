extends SceneTree
## 第44段: 看板検索の大量結果で切断される問題への対処。
## サーバの送信バッファは 16KB しかなく、受信行の処理に専念して
## ソケットを読みに行けないと、あふれて切断される (実サーバの
## ログで確認)。対策は 2 つ:
## (1) PhiSession は 1 回の poll で処理する行数に上限を付ける。
## (2) ログ自動保存は行ごとにファイルを開かず、まとめて書く。

var _checks := 0
var _failures := 0


func check(cond: bool, label: String) -> void:
	_checks += 1
	if not cond:
		_failures += 1
		print("FAIL: ", label)


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	# (1) 処理行数の上限: 1000 行溜めても 1 回では上限までしか
	# 処理せず、残りは次の呼び出しに回る。
	var session := PhiSession.new()
	var counter := [0]
	session.event_received.connect(func(_e: Dictionary) -> void: counter[0] += 1)
	var pending: Array[PackedByteArray] = []
	for i in 1000:
		pending.append(Cp932.encode("テストライン %d" % i))
	session.set("_pending_lines", pending)
	session.call("_process_pending_lines")
	check(counter[0] == PhiSession.MAX_LINES_PER_POLL, "one pass processes the cap (got %d)" % counter[0])
	check(session.get("_pending_lines").size() == 1000 - PhiSession.MAX_LINES_PER_POLL, "rest stays queued")
	var guard := 0
	while not (session.get("_pending_lines") as Array).is_empty() and guard < 50:
		session.call("_process_pending_lines")
		guard += 1
	check(counter[0] == 1000, "all lines processed after more passes (got %d)" % counter[0])
	check(session.get("_pending_lines").is_empty(), "queue drained")

	# (2a) append_lines: まとめて書いても append_line の繰り返しと
	# 同じ結果になる。HTML のヘッダは初回だけ。
	var dir := OS.get_temp_dir().path_join("neophi_stage44_logs")
	OS.execute("rm", ["-rf", dir])
	check(PhiLogFile.append_lines(dir, "Guest", false, ["one", "two"]), "append_lines text")
	check(PhiLogFile.append_lines(dir, "Guest", false, ["three"]), "append_lines text again")
	var text := FileAccess.get_file_as_string(PhiLogFile.log_path(dir, "Guest", false))
	check(text == "one\ntwo\nthree\n", "append_lines content (got %q)" % text)
	check(PhiLogFile.append_lines(dir, "Guest", true, ["a<b"]), "append_lines html")
	check(PhiLogFile.append_lines(dir, "Guest", true, ["c"]), "append_lines html again")
	var html := FileAccess.get_file_as_string(PhiLogFile.log_path(dir, "Guest", true))
	check(html.count("<!DOCTYPE html>") == 1, "html header written once")
	check(html.contains("a&lt;b<br>") and html.contains("c<br>"), "html lines appended")

	# (2b) タブの自動保存: 溜めてから書き出す。100 行で自動で書く。
	var ps := load("res://main.tscn") as PackedScene
	var main: Node = ps.instantiate()
	root.add_child(main)
	await create_timer(1.0).timeout
	var cfg: PhiConfig = main.get("_config")
	cfg.log_auto_save = true
	cfg.log_save_dir = dir
	cfg.log_save_html = false
	cfg.log_save_delete_tag = false
	cfg.log_save_text_with_time = false
	var tab: PhiCharacter = main.call("_create_tab")
	main.call("_activate_tab", tab)
	var path := PhiLogFile.log_path(dir, "character", false)
	tab.log_message("log", "バッチ確認1")
	tab.log_message("log", "バッチ確認2")
	check(not FileAccess.file_exists(path), "auto save is buffered (no file yet)")
	tab.call("_flush_log_save")
	check(FileAccess.file_exists(path), "flush writes the file")
	var saved := FileAccess.get_file_as_string(path)
	check(saved.contains("バッチ確認1") and saved.contains("バッチ確認2"), "flushed lines are in the file")
	for i in 100:
		tab.log_message("log", "大量行 %d" % i)
	var saved2 := FileAccess.get_file_as_string(path)
	check(saved2.contains("大量行 99"), "100 lines trigger an automatic flush")
	cfg.log_auto_save = false
	main.queue_free()
	OS.execute("rm", ["-rf", dir])

	print("stage44: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)
