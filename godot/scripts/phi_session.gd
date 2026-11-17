class_name PhiSession
extends RefCounted
## 1キャラ分のレガシーサーバへの接続。仕様書 §1・§2。
##
## Python 版 neophi/session.py の移植。`poll()` を毎フレーム呼ぶ
## 方式で、StreamPeerTCP の非同期接続・送受信を行う。自動応答
## (`#lag` / `#remap`) とキープアライブ (`#code-sjis`) を含む。
## 世界移動 (`#ch-srv`、仕様書 §8.4) も Python 版と同じ手順で行う:
## 違うホストへは確認 (transfer_confirm_requested) を挟み、
## `#reserve` → `#trans` → `#ch-srv-ok` の順に進め、失敗したら
## 移動元に留まる。自動装備外しは未移植。

signal event_received(event: Dictionary)
signal session_error(message: String)
signal session_closed
## 違うホストへの世界移動の確認。UI が利用者に確かめて
## answer_transfer() で答える。
signal transfer_confirm_requested(host: String, port: int)

## 無受信がこの時間続いたら `#code-sjis` を送る
const KEEPALIVE_AFTER := 120.0
## 無受信がこの時間続いたら警告を出す
const WARN_AFTER := 180.0
## 1 回の poll で処理する受信行の上限。看板検索の結果など
## 数千行が一度に届いた時、処理に専念するとソケットを読みに
## 行けず、サーバ側の送信バッファ (16KB) があふれて切断される。
## サーバ (tcp.cpp の write_line) はあふれる瞬間に一度だけ
## 送出を試し (待ち時間 0)、その間に受け側が読み続けていないと
## CONNECT_BUFFULL で切る。残りは次の poll で処理し、その間も
## 受信は続ける。1 回の処理を短く保ち、poll_burst で受信と
## 処理を細かく交互に回すのが効く。
const MAX_LINES_PER_POLL := 120
## 接続の制限時間 (秒)
const CONNECT_TIMEOUT := 10.0
## 正常ログアウト (`exit`) を送ってから、サーバが `#close` で
## 閉じてくるのを待つ上限 (秒)。過ぎたら従来どおり閉じる。
const LOGOUT_TIMEOUT := 2.5
## 世界移動の確認と各待ちの制限時間 (秒)
const TRANSFER_TIMEOUT := 300.0

var host := ""
var port := 0
var char_id := ""
## ログイン時に送る地図の大きさ(40=5x5, 57=7x7)とスタイル。
var map_size := 81
var map_style := "solid"
## ログイン時に送る `#ex-switch ex-disp-magic=` の値。
var disp_magic := true
## 解読済みの受信行を、パーサ処理の前に通知する任意のフック。
## 新規キャラクター作成(PhiRegister)がプロンプト応答に使う。
## 既定は無効で、その場合は従来どおりの振る舞いになる。
var line_observer := Callable()
## ログイン行の差し替え。新規キャラクター作成のセッションが使う。
## `has_login_override` が true の間は `login_lines()` の代わりに
## `login_override` を送る。
var login_override: Array[String] = []
var has_login_override := false

var _tcp := StreamPeerTCP.new()
var _lines := LineBuffer.new()
var _parser := PhiParser.new()
var _send_queue: Array[String] = []
var _out_buffer := PackedByteArray()
## 受信したが未処理の行。世界移動が始まると残りは保留され、
## 留まった時に続きから処理し、移動したら捨てる (Python 版の
## pending_lines と同じ)。
var _pending_lines: Array[PackedByteArray] = []
## 系統魔法の前に武器を外す (Philly の AutoUnequipSystemMagic)。
## 既定 on、装備し直し (AutoEquipSystemMagic) は既定 off。
var auto_unequip_enabled := true
var auto_equip := false
var _auto_unequip := PhiAutoUnequip.new()
var _state := "idle" # idle | connecting | open | closed
var _logged_in := false
var _logout_pending := false
var _logout_deadline := 0.0
var _logout_close_seen := false
var _last_recv_msec := 0
var _keepalive_sent := false
var _warned := false

# -- 世界移動の状態 -------------------------------------------------
## "" = 移動していない。"confirm" = 確認待ち、"connecting" = 移動先へ
## 接続中、"reserve" = `#rsv-ok` 待ち、"trans" = `#trs-ok` 待ち。
var _transfer_stage := ""
var _transfer_host := ""
var _transfer_port := 0
var _transfer_deadline := 0
var _dst_tcp: StreamPeerTCP = null
var _dst_lines := LineBuffer.new()
var _dst_out := PackedByteArray()
## `#trs-ok` を待つ間に届いた移動元の行。失敗したら処理し直す。
var _skipped_lines: Array[PackedByteArray] = []


static func login_lines(p_char_id: Variant, p_map_size: int = 81, p_map_style: String = "solid", p_disp_magic: bool = true) -> Array[String]:
	## Philly のログイン時の送信。値は Philly の既定値。
	## 世界移動の後は `#open` を送らないので、その時は p_char_id=null で呼ぶ。
	## 地図の大きさ(40=5x5, 57=7x7)とスタイルは設定から渡す。
	## `#ex-disp-magic` は Philly.ini の DispMagicClientSide 既定(on)に従う。
	var lines: Array[String] = []
	if p_char_id != null:
		lines.append("#open " + str(p_char_id))
	lines.append_array([
		"#version-cli 05107100",
		"#map-iv 2",
		"#status-iv 2",
		"#ex-switch eagleeye=form",
		"#ex-map size=%d" % p_map_size,
		"#ex-map style=%s" % p_map_style,
		"#ex-switch ex-move-recv=true",
		"#ex-switch ex-list-mode-end=true",
		"#ex-switch ex-disp-magic=" + ("true" if p_disp_magic else "false"),
		"#ex-switch ex-abspos=true",
	])
	return lines


static func post_register_lines(p_map_size: int = 81, p_map_style: String = "solid", p_disp_magic: bool = true) -> Array[String]:
	## 新規キャラクター作成の成功後に送る、通常セッション用の残りの
	## 設定。`login_lines()` の後半(地図と ex-switch 群)と同じ並びで、
	## `#open` や間隔指定は作成時のものを送り済みなので含まない。
	return [
		"#ex-map size=%d" % p_map_size,
		"#ex-map style=%s" % p_map_style,
		"#ex-switch ex-move-recv=true",
		"#ex-switch ex-list-mode-end=true",
		"#ex-switch ex-disp-magic=" + ("true" if p_disp_magic else "false"),
		"#ex-switch ex-abspos=true",
	]


func is_open() -> bool:
	return _state == "open"


func connect_to(p_host: String, p_port: int, p_char_id: String) -> void:
	host = p_host
	port = p_port
	char_id = p_char_id
	_cancel_transfer_for_close()
	_lines.reset()
	_pending_lines.clear()
	_parser = PhiParser.new()
	_send_queue.clear()
	_out_buffer = PackedByteArray()
	_keepalive_sent = false
	_warned = false
	_logged_in = false
	_logout_pending = false
	_logout_close_seen = false
	var err := _tcp.connect_to_host(host, port)
	if err != OK:
		_state = "closed"
		session_error.emit("接続出来ません: %s" % error_string(err))
		session_closed.emit()
		return
	_state = "connecting"
	_last_recv_msec = Time.get_ticks_msec()


## 1行を送る。`\r` や `\n` を含む行は送らない。
## 世界移動の手順の間は、Python 版と同じく打った行を捨てる。
func send_line(line: String) -> void:
	if _transfer_stage != "":
		return
	# 系統魔法の唱える行はセッション内部の接頭辞。サーバへは送らず、
	# `unequip` だけを先に送って唱える行を覚える。
	if line.begins_with(PhiAutoUnequip.CAST_PREFIX):
		var first := _auto_unequip.start(line, _now_sec())
		if not first.is_empty():
			_send_queue.append(first)
		return
	if line.begins_with("#wphi-"):
		# セッション内部の接頭辞。サーバへは送らない。
		return
	if line.contains("\r") or line.contains("\n"):
		push_error("送る1行に改行を含める事はできません")
		return
	if line == "#ulist":
		_parser.clear_users()
	_send_queue.append(line)


## `\n` 区切りの複数行を、行に分けて送る。
func send_text(text: String) -> void:
	var lines := text.split("\n")
	if text.ends_with("\n") and not lines.is_empty() and lines[lines.size() - 1] == "":
		lines.remove_at(lines.size() - 1)
	for line in lines:
		send_line(line)


## 系統魔法を唱える行を送る。自動装備外しが有効なら `#wphi-cast` の
## 1行にまとめて送り、セッションが `unequip` だけを先に送ってから
## 装備のリストを見て唱える。無効なら行をそのまま送る。
func send_system_magic(text: String, reequip: bool) -> void:
	if not auto_unequip_enabled:
		send_text(text)
		return
	var flag := "1" if (reequip and auto_equip) else "0"
	send_line(PhiAutoUnequip.CAST_PREFIX + flag + " " + "\t".join(text.split("\n")))


## リストを閉じた事をパーサへ伝える。サーバへは何も送らない。
func close_list() -> void:
	for event in _parser.end_list():
		event_received.emit(event)


## 切断を頼む。ログイン済みなら、まずサーバの正常ログアウト
## コマンド `exit` を送り、サーバがセーブして `#close` で閉じて
## くるのを待つ (サーバ側で「ログアウトした」と表示される)。
## `#x` を送るだけだとサーバはロストコネクションとして扱う。
## 世界移動の途中や未ログインなら、従来どおり `#x` で閉じる。
func disconnect_graceful() -> void:
	var was_transfer := _transfer_stage != ""
	_cancel_transfer_for_close()
	if _state == "open":
		_flush_queue()
		if _logged_in and not was_transfer and not has_login_override:
			_out_buffer.append_array(Cp932.encode("exit") + PackedByteArray([10]))
			_try_flush()
			_logout_pending = true
			_logout_close_seen = false
			_logout_deadline = _now_sec() + LOGOUT_TIMEOUT
			return
		_out_buffer.append_array(Cp932.encode("#x") + PackedByteArray([10]))
		_try_flush()
	_tcp.disconnect_from_host()
	_state = "closed"


## 正常ログアウトの完了待ちかどうか。
func is_logout_pending() -> bool:
	return _logout_pending


## ログアウト待ちを終えて、接続を閉じる。
func _finish_logout() -> void:
	_logout_pending = false
	_logout_close_seen = false
	_tcp.disconnect_from_host()
	_state = "closed"
	session_closed.emit()


## 強制切断。`#x` を送らず、送受信の残りも捨てて、その場で閉じる。
func disconnect_force() -> void:
	_logout_pending = false
	_logout_close_seen = false
	_cancel_transfer_for_close()
	_send_queue.clear()
	_out_buffer = PackedByteArray()
	_tcp.disconnect_from_host()
	_state = "closed"


## 毎フレーム呼ぶ。接続の確立・受信・送信・キープアライブを行う。
func poll() -> void:
	if _state == "closed" or _state == "idle":
		return
	_tcp.poll()
	var status := _tcp.get_status()
	if _state == "connecting":
		if status == StreamPeerTCP.STATUS_CONNECTED:
			_state = "open"
			_last_recv_msec = Time.get_ticks_msec()
			var lines := login_lines(char_id, map_size, map_style, disp_magic)
			if has_login_override:
				lines = login_override
			for line in lines:
				_send_queue.append(line)
			_flush_queue()
			_try_flush()
		elif status == StreamPeerTCP.STATUS_ERROR:
			_state = "closed"
			session_error.emit("接続出来ません")
			session_closed.emit()
		return
	if status != StreamPeerTCP.STATUS_CONNECTED:
		_state = "closed"
		if _logout_pending:
			# 正常ログアウトの完了としてサーバが閉じた。異常ではない。
			_logout_pending = false
			_logout_close_seen = false
		else:
			session_error.emit("切断されました")
		session_closed.emit()
		return
	# 世界移動の手順の間は、移動元の行を処理しない (手順側が読む)。
	if _transfer_stage != "":
		_poll_transfer()
		_flush_queue()
		_try_flush()
		return
	# 受信
	_drain_available()
	# 溜まった行を処理する (上限付き。世界移動が始まったら
	# 残りは保留する)。
	_process_pending_lines()
	# 正常ログアウトの後始末: `#close` が来たら閉じ、期限を過ぎたら
	# 従来どおり `#x` で閉じる (仲間を連れている等でサーバが
	# ログアウトを断った場合)。
	if _logout_pending:
		if _logout_close_seen:
			_finish_logout()
			return
		if _now_sec() > _logout_deadline:
			_out_buffer.append_array(Cp932.encode("#x") + PackedByteArray([10]))
			_try_flush()
			_finish_logout()
			return
	# 送信
	_flush_queue()
	_try_flush()
	# キープアライブ
	var quiet_sec := float(Time.get_ticks_msec() - _last_recv_msec) / 1000.0
	if not _keepalive_sent and quiet_sec >= KEEPALIVE_AFTER:
		_keepalive_sent = true
		_send_queue.append("#code-sjis")
		_flush_queue()
		_try_flush()
	elif _keepalive_sent and not _warned and quiet_sec >= WARN_AFTER:
		_warned = true
		session_error.emit("サーバから3分間応答がありません")


func _drain_available() -> void:
	## ソケットに届いているバイトを未処理行へ移す。
	var guard := 0
	while _tcp.get_available_bytes() > 0 and guard < 64:
		guard += 1
		var result := _tcp.get_data(_tcp.get_available_bytes())
		if result[0] != OK:
			break
		var chunk: PackedByteArray = result[1]
		if chunk.is_empty():
			break
		_last_recv_msec = Time.get_ticks_msec()
		_keepalive_sent = false
		_warned = false
		_pending_lines.append_array(_lines.feed(chunk))


func drain_socket() -> void:
	## バイトの取り込みだけ行う (行の処理はしない)。表示など
	## 重い処理の直後にもう一度ソケットを空けておくために使う
	## (第62段)。接続が開いていて世界移動中でない時だけ。
	if _state != "open" or _transfer_stage != "":
		return
	_tcp.poll()
	_drain_available()


func has_pending_lines() -> bool:
	## 受信したのに未処理の行が残っているか。
	return not _pending_lines.is_empty()


func pending_line_count() -> int:
	## 未処理行の数 (描き直しの後回し判定などに使う)。
	return _pending_lines.size()


func poll_burst() -> void:
	## poll() に加え、未処理行が残っている間は poll() を追加で
	## 回す (1 フレーム最大 5 回)。大量行のバースト中もソケットを
	## 空け続け、サーバ側の送信バッファ溢れ切断を避ける。
	## 全体の時間も絞る (1 回の処理自体が時間で区切られている)。
	poll()
	var start := Time.get_ticks_msec()
	var guard := 0
	while has_pending_lines() and _state == "open" and guard < 4:
		if Time.get_ticks_msec() - start >= 20:
			break
		guard += 1
		poll()


## 1 回の行処理にかけてよい時間 (ミリ秒)。行数上限に加えて
## 時間でも区切る: ログ表示が重いと 120 行でもフレームが
## 秒単位に伸び、その間ソケットを読めずサーバ側が溢れて
## 切断されるため。テストから差し替えられるよう変数にする。
var process_budget_msec := 8


func _process_pending_lines() -> void:
	## 溜まった受信行を処理する。1 回で処理する行数は
	## MAX_LINES_PER_POLL まで、時間は process_budget_msec まで
	## (理由は定数のコメント参照)。
	var count := 0
	var start := Time.get_ticks_msec()
	while not _pending_lines.is_empty() and _transfer_stage == "" and count < MAX_LINES_PER_POLL:
		_process_line(_pending_lines.pop_front())
		count += 1
		if count % 16 == 0 and Time.get_ticks_msec() - start >= process_budget_msec:
			break


func _process_line(line: PackedByteArray) -> void:
	# 行フック(新規キャラクター作成のプロンプト応答)。パーサ処理の前に、
	# 解読済みの行をそのまま渡す。
	if line_observer.is_valid():
		line_observer.call(Cp932.decode(line))
	# 自動装備外し: 地形はバイナリなので判定に掛けない。それ以外の行は
	# パーサの前に横取り判定をし、横取りした行はパーサへ渡さない
	# (Python 版 session.process_line と同じ)。
	if not has_login_override and not _is_terrain_line(line):
		var filtered := _auto_unequip.filter(
			PhiTags.strip_tags(Cp932.decode(line)), _now_sec())
		if bool(filtered["hidden"]):
			for reply_line in filtered["reply"]:
				_send_queue.append(str(reply_line))
			return
	var produced := false
	for event in _parser.feed(line):
		produced = true
		if event.get("type") == "notice" and event.has("name"):
			_logged_in = true
		if _logout_pending and event.get("type") == "connection":
			# 自分から頼んだ正常ログアウトへの `#close`。切断の
			# 後始末は poll 側で行うので、イベントとしては出さない。
			_logout_close_seen = true
			continue
		if event.get("type") == "worldTransfer" and not has_login_override:
			# 世界移動はセッションが引き受ける (UI へは出さない)。
			_begin_transfer(str(event.get("server", "")))
		elif event.get("type") == "_internal":
			if event.get("action") == "lag":
				_send_queue.append("#end-lag")
			elif event.get("action") == "remap":
				_send_queue.append("#map")
		else:
			event_received.emit(event)
	# BGM 通知(#bgm / #ex-bgm-speed)はパーサが wphi 互換で無視する
	# ので、イベントにならなかった '#' 行だけをここで拾う(第5段)。
	# #more の中の行はパーサが message イベントにするので対象にならない。
	if not produced and not line.is_empty() and line[0] == 0x23:
		var bgm_event := PhiParser.bgm_event_for_line(Cp932.decode(line))
		if not bgm_event.is_empty():
			event_received.emit(bgm_event)


func _flush_queue() -> void:
	for line in _send_queue:
		_out_buffer.append_array(Cp932.encode(line))
		_out_buffer.append(10)
	_send_queue.clear()


func _try_flush() -> void:
	if _out_buffer.is_empty():
		return
	var result := _tcp.put_partial_data(_out_buffer)
	if result[0] != OK:
		return
	var sent: int = result[1]
	if sent >= _out_buffer.size():
		_out_buffer = PackedByteArray()
	elif sent > 0:
		_out_buffer = _out_buffer.slice(sent)


# -- 世界移動 ---------------------------------------------------------

static func transfer_target(server: String) -> Variant:
	## `#ch-srv` の移動先。"host:port" を [host, port] にする。
	## ポートが読めない・範囲外なら null (Python 版と同じ)。
	var idx := server.rfind(":")
	if idx <= 0:
		return null
	var h := server.substr(0, idx)
	var p := server.substr(idx + 1)
	if not p.is_valid_int():
		return null
	var port := p.to_int()
	if port < 0 or port > 65535:
		return null
	return [h, port]


func _system_message(text: String) -> void:
	## クライアント内の知らせ。ログに混ぜて出す。
	event_received.emit({"type": "message", "channel": "system", "text": text, "markup": false})


func _begin_transfer(server: String) -> void:
	if _transfer_stage != "":
		return
	var target: Variant = transfer_target(server)
	if target != null and str(target[0]).to_lower() != host.to_lower():
		# 今と違うホストへは、キャラ ID を送る前に確かめる。
		_transfer_host = str(target[0])
		_transfer_port = int(target[1])
		_transfer_stage = "confirm"
		_transfer_deadline = Time.get_ticks_msec() + int(TRANSFER_TIMEOUT * 1000.0)
		transfer_confirm_requested.emit(_transfer_host, _transfer_port)
		return
	_start_gate(target)


## 世界移動の確認への答え。True = 行く、False = やめる。
## 期限切れもやめる扱い (poll 側から False で呼ばれる)。
func answer_transfer(yes: bool) -> void:
	if _transfer_stage != "confirm":
		return
	_transfer_stage = ""
	if not yes:
		_system_message("世界移動をやめました")
		_send_queue.append("#no-srv")
		_last_recv_msec = Time.get_ticks_msec()
		return
	_start_gate([_transfer_host, _transfer_port])


func _start_gate(target: Variant) -> void:
	_system_message("転送先世界へゲート接続開始...")
	if target == null:
		_fail_stay("転送先の世界が見つかりません", "#no-srv")
		return
	_transfer_host = str(target[0])
	_transfer_port = int(target[1])
	_dst_tcp = StreamPeerTCP.new()
	_dst_lines.reset()
	_dst_out = PackedByteArray()
	var err := _dst_tcp.connect_to_host(_transfer_host, _transfer_port)
	if err != OK:
		_fail_stay("転送先の世界が見つかりません", "#no-srv")
		return
	_transfer_stage = "connecting"
	_transfer_deadline = Time.get_ticks_msec() + int(CONNECT_TIMEOUT * 1000.0)


## 移動に失敗して移動元に留まる。src_line は移動元へ送る行。
func _fail_stay(message: String, src_line: String) -> void:
	if not message.is_empty():
		_system_message(message)
	if not src_line.is_empty():
		_send_queue.append(src_line)
	_close_dst()
	_transfer_stage = ""
	_last_recv_msec = Time.get_ticks_msec()
	_keepalive_sent = false
	_warned = false


## `#trs-ok` 待ちの失敗。待つ間に届いた行は処理し直す。
func _fail_trans() -> void:
	_send_queue.append("#ch-srv-no")
	_system_message("転送失敗")
	_close_dst()
	_transfer_stage = ""
	_last_recv_msec = Time.get_ticks_msec()
	_keepalive_sent = false
	_warned = false
	var skipped := _skipped_lines
	_skipped_lines = []
	for line in skipped:
		_process_line(line)


## 移動の完了。接続を移動先へ差し替える。
func _complete_transfer() -> void:
	var lines: Array[String] = ["#ch-srv-ok"]
	lines.append_array(login_lines(null, map_size, map_style, disp_magic))
	for line in lines:
		_dst_out.append_array(Cp932.encode(line))
		_dst_out.append(10)
	_dst_flush()
	_system_message("転送完了")
	var old_tcp := _tcp
	_tcp = _dst_tcp
	_dst_tcp = null
	_lines = _dst_lines
	_dst_lines = LineBuffer.new()
	_parser = PhiParser.new()
	host = _transfer_host
	port = _transfer_port
	_send_queue.clear()
	_pending_lines.clear()
	_out_buffer = _dst_out
	_dst_out = PackedByteArray()
	_skipped_lines.clear()
	_transfer_stage = ""
	_last_recv_msec = Time.get_ticks_msec()
	_keepalive_sent = false
	_warned = false
	old_tcp.disconnect_from_host()


func _poll_transfer() -> void:
	var now := Time.get_ticks_msec()
	match _transfer_stage:
		"confirm":
			if now > _transfer_deadline:
				answer_transfer(false)
		"connecting":
			_dst_tcp.poll()
			var st := _dst_tcp.get_status()
			if st == StreamPeerTCP.STATUS_CONNECTED:
				_system_message("転送先世界に転送準備要求...")
				_dst_out.append_array(Cp932.encode("#reserve " + char_id))
				_dst_out.append(10)
				_dst_flush()
				_transfer_stage = "reserve"
				_transfer_deadline = now + int(TRANSFER_TIMEOUT * 1000.0)
			elif st == StreamPeerTCP.STATUS_ERROR or now > _transfer_deadline:
				_fail_stay("転送先の世界が見つかりません", "#no-srv")
		"reserve":
			if now > _transfer_deadline:
				_fail_stay("転送準備失敗。転送先の世界で同時接続数をオーバーしている可能性があります。", "#no-srv")
				return
			_dst_tcp.poll()
			if _dst_tcp.get_status() != StreamPeerTCP.STATUS_CONNECTED:
				_fail_stay("転送準備失敗。転送先の世界で同時接続数をオーバーしている可能性があります。", "#no-srv")
				return
			_dst_flush()
			for line in _dst_read_lines():
				var text := Cp932.decode(line)
				if text == "#rsv-ok":
					_system_message("転送元世界に転送要求...")
					_skipped_lines.clear()
					_send_queue.append("#trans %s %d" % [_transfer_host, _transfer_port])
					_transfer_stage = "trans"
					_transfer_deadline = now + int(TRANSFER_TIMEOUT * 1000.0)
					return
				if text == "#rsv-no" or text == "#x":
					_fail_stay("転送準備失敗。転送先の世界で同時接続数をオーバーしている可能性があります。", "#no-srv")
					return
				# それ以外の行は捨てる
		"trans":
			if now > _transfer_deadline:
				_fail_trans()
				return
			var guard := 0
			while _tcp.get_available_bytes() > 0 and guard < 64:
				guard += 1
				var result := _tcp.get_data(_tcp.get_available_bytes())
				if result[0] != OK:
					break
				var chunk: PackedByteArray = result[1]
				if chunk.is_empty():
					break
				_last_recv_msec = Time.get_ticks_msec()
				for line in _lines.feed(chunk):
					var text := Cp932.decode(line)
					if text == "#trs-ok":
						_complete_transfer()
						return
					if text == "#trs-no":
						_fail_trans()
						return
					_skipped_lines.append(line)


func _dst_flush() -> void:
	if _dst_tcp == null or _dst_out.is_empty():
		return
	var result := _dst_tcp.put_partial_data(_dst_out)
	if result[0] != OK:
		return
	var sent: int = result[1]
	if sent >= _dst_out.size():
		_dst_out = PackedByteArray()
	elif sent > 0:
		_dst_out = _dst_out.slice(sent)


func _dst_read_lines() -> Array[PackedByteArray]:
	var out: Array[PackedByteArray] = []
	if _dst_tcp == null:
		return out
	var guard := 0
	while _dst_tcp.get_available_bytes() > 0 and guard < 64:
		guard += 1
		var result := _dst_tcp.get_data(_dst_tcp.get_available_bytes())
		if result[0] != OK:
			break
		var chunk: PackedByteArray = result[1]
		if chunk.is_empty():
			break
		out.append_array(_dst_lines.feed(chunk))
	return out


func _close_dst() -> void:
	if _dst_tcp != null:
		_dst_tcp.disconnect_from_host()
		_dst_tcp = null
	_dst_out = PackedByteArray()


func _cancel_transfer_for_close() -> void:
	_close_dst()
	_transfer_stage = ""
	_skipped_lines.clear()


static func _now_sec() -> float:
	## 秒単位の時刻 (Python 版のループ時刻に相当)。
	return float(Time.get_ticks_msec()) / 1000.0


static func _is_terrain_line(line: PackedByteArray) -> bool:
	## 地形のバイナリ行か (`#m57 M` / `#map M`)。
	if line.size() < 6:
		return false
	var head := Cp932.decode(line.slice(0, 6))
	return head == "#m57 M" or head == "#map M"
