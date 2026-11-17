extends SceneTree
## 第55段: 大量行バーストでも受信を空け続ける。
## サーバ (tcp.cpp write_line) は送信バッファがあふれる瞬間に
## 一度だけ送出を試し、受け側が読み続けていないと切断する。
## 対策: 1 回の処理上限を 120 行に絞り、PhiCharacter._process は
## session.poll_burst() で 1 フレームに複数回 poll する。

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
	check(PhiSession.MAX_LINES_PER_POLL == 120, "cap is 120")
	# 1000 行を溜めても、繰り返し処理すれば欠けなく全部処理される
	var session := PhiSession.new()
	var counter := [0]
	session.event_received.connect(func(_e: Dictionary) -> void: counter[0] += 1)
	var pending: Array[PackedByteArray] = []
	for i in range(1000):
		pending.append(Cp932.encode("バースト行 %d" % i))
	session.set("_pending_lines", pending)
	check(session.has_pending_lines(), "pending reported")
	var passes := 0
	while session.has_pending_lines() and passes < 50:
		session.call("_process_pending_lines")
		passes += 1
		check(counter[0] <= 120 * passes, "cap respected at pass %d" % passes)
	check(counter[0] == 1000, "all 1000 lines processed (got %d)" % counter[0])
	check(not session.has_pending_lines(), "queue drained")
	# poll_burst があり、キャラクタの _process がそれを使っている
	check(session.has_method("poll_burst"), "poll_burst exists")
	var src := FileAccess.get_file_as_string("res://scripts/phi_character.gd")
	check(src.contains("session.poll_burst()"), "character _process uses poll_burst")

	print("stage55: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)
