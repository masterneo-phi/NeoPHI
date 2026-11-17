extends SceneTree
## 第75段: 受信スレッド。ソケットの読み取りを専用スレッドで
## 回し、メインスレッドが止まっても読みが滞らないようにする。
## ここでは (1) スレッドの開始/停止が安全なこと、(2) スレッドが
## 運んだバイトの塊が従来どおり行に分かれること、(3) 送信が
## outbox 経由になること、(4) スレッド無効時は従来動作のまま、
## を確かめる。実サーバへの接続自体は環境依存なので扱わない。

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
	# --- (1) 接続できない相手でもスレッドが始まり、止まる ---
	var s1 := PhiSession.new()
	s1.connect_to("127.0.0.1", 9, "guest")
	for i in 5:
		s1.poll()
		await process_frame
	s1.disconnect_force()
	check(s1.get("_reader_thread") == null, "reader stopped on force close")
	check(s1.is_open() == false, "not open after force close")

	# --- (2) inbox の塊が行に分かれる (分割は従来どおり) ---
	var s2 := PhiSession.new()
	s2.call("_start_reader")
	check(s2.get("_reader_thread") != null, "reader started")
	var chunks: Array[PackedByteArray] = []
	chunks.append("abc\ndef\n".to_ascii_buffer())
	s2.set("_inbox_chunks", chunks)
	s2.call("_drain_available")
	check(int(s2.call("pending_line_count")) == 2, "two lines from chunk")
	var lines: Array = s2.get("_pending_lines")
	check((lines[0] as PackedByteArray).get_string_from_ascii() == "abc",
		"first line abc")
	check((lines[1] as PackedByteArray).get_string_from_ascii() == "def",
		"second line def")
	var chunks2: Array[PackedByteArray] = []
	chunks2.append("gh".to_ascii_buffer())
	s2.set("_inbox_chunks", chunks2)
	s2.call("_drain_available")
	check(int(s2.call("pending_line_count")) == 2,
		"partial line held in buffer")
	var chunks3: Array[PackedByteArray] = []
	chunks3.append("i\n".to_ascii_buffer())
	s2.set("_inbox_chunks", chunks3)
	s2.call("_drain_available")
	check(int(s2.call("pending_line_count")) == 3,
		"line completed across chunks")
	s2.disconnect_force()
	check(s2.get("_reader_thread") == null, "reader stopped (inbox case)")

	# --- (3) 送信は outbox へ、停止時に _out_buffer へ戻る ---
	var s3 := PhiSession.new()
	s3.call("_start_reader")
	s3.set("_out_buffer", "hello".to_ascii_buffer())
	s3.call("_try_flush")
	check((s3.get("_out_buffer") as PackedByteArray).is_empty(),
		"out buffer handed to outbox")
	# スレッドが拾う前に outbox へ直接積み、回収を確かめる。
	# 世界移動中にしてスレッドを止めておく (競合しない)。
	s3.set("_transfer_stage", "trans")
	s3.set("_outbox_bytes", "zz".to_ascii_buffer())
	s3.call("_stop_reader_draining_outbox")
	check((s3.get("_out_buffer") as PackedByteArray)
		.get_string_from_ascii().begins_with("zz"),
		"outbox recovered at stop")
	check(s3.get("_reader_thread") == null, "reader stopped (outbox case)")
	s3.set("_transfer_stage", "")

	# --- (4) スレッド無効なら従来どおり (スレッドを作らない) ---
	var s4 := PhiSession.new()
	s4.threaded_reader = false
	s4.connect_to("127.0.0.1", 9, "guest")
	check(s4.get("_reader_thread") == null, "no reader when disabled")
	s4.poll()
	s4.disconnect_force()
	check(s4.get("_reader_thread") == null, "still no reader (legacy)")

	print("test_stage75: ", _checks, " checks, ", _failures, " failures")
	quit(1 if _failures > 0 else 0)
