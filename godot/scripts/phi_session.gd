class_name PhiSession
extends RefCounted
## 1キャラ分のレガシーサーバへの接続。仕様書 §1・§2。
##
## Python 版 neophi/session.py の試作向け移植。`poll()` を毎フレーム呼ぶ
## 方式で、StreamPeerTCP の非同期接続・送受信を行う。自動応答(`#lag` /
## `#remap`)とキープアライブ(`#code-sjis`)を含む。世界移動と自動装備外しは
## 試作の範囲外。

signal event_received(event: Dictionary)
signal session_error(message: String)
signal session_closed

## 無受信がこの時間続いたら `#code-sjis` を送る
const KEEPALIVE_AFTER := 120.0
## 無受信がこの時間続いたら警告を出す
const WARN_AFTER := 180.0

var host := ""
var port := 0
var char_id := ""
## ログイン時に送る地図の大きさ(40=5x5, 57=7x7)とスタイル。
var map_size := 57
var map_style := "solid"
## ログイン時に送る `#ex-switch ex-disp-magic=` の値。
var disp_magic := true

var _tcp := StreamPeerTCP.new()
var _lines := LineBuffer.new()
var _parser := PhiParser.new()
var _send_queue: Array[String] = []
var _out_buffer := PackedByteArray()
var _state := "idle" # idle | connecting | open | closed
var _last_recv_msec := 0
var _keepalive_sent := false
var _warned := false


static func login_lines(p_char_id: Variant, p_map_size: int = 57, p_map_style: String = "solid", p_disp_magic: bool = true) -> Array[String]:
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


func is_open() -> bool:
	return _state == "open"


func connect_to(p_host: String, p_port: int, p_char_id: String) -> void:
	host = p_host
	port = p_port
	char_id = p_char_id
	_lines.reset()
	_parser = PhiParser.new()
	_send_queue.clear()
	_out_buffer = PackedByteArray()
	_keepalive_sent = false
	_warned = false
	var err := _tcp.connect_to_host(host, port)
	if err != OK:
		_state = "closed"
		session_error.emit("接続出来ません: %s" % error_string(err))
		session_closed.emit()
		return
	_state = "connecting"
	_last_recv_msec = Time.get_ticks_msec()


## 1行を送る。`\r` や `\n` を含む行は送らない。
func send_line(line: String) -> void:
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


## 切断を頼む。graceful なら `#x` を送ってから閉じる。
func disconnect_graceful() -> void:
	if _state == "open":
		_flush_queue()
		_out_buffer.append_array(Cp932.encode("#x") + PackedByteArray([10]))
		_try_flush()
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
			for line in login_lines(char_id, map_size, map_style, disp_magic):
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
		session_error.emit("切断されました")
		session_closed.emit()
		return
	# 受信
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
		for line in _lines.feed(chunk):
			_process_line(line)
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


func _process_line(line: PackedByteArray) -> void:
	var produced := false
	for event in _parser.feed(line):
		produced = true
		if event.get("type") == "_internal":
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
