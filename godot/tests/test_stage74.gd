extends SceneTree
## 第74段: BGM ゲート。重い処理 (接続直後のログの洪水・
## 世界移動・大量行の受信) の間は BGM を一時停止し、
## 落ち着いたら位置を保って再開する。エンジン側の
## 一時停止/再開と、タブ側のゲート判定を確かめる。

const Main := preload("res://scripts/main.gd")

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
	var main: Node = Main.new()
	var iso := ProjectSettings.globalize_path("user://stage74_tabs.ini")
	OS.execute("rm", ["-f", iso])
	main.set("_tab_session_path", "user://stage74_tabs.ini")
	var isoc := ProjectSettings.globalize_path("user://stage74_cfg.ini")
	OS.execute("rm", ["-f", isoc])
	main.set("_config_path", "user://stage74_cfg.ini")
	root.add_child(main)
	await process_frame
	await process_frame
	var tab: Variant = main.call("_active_tab")
	var tsession: Variant = tab.get("session")

	# --- エンジン: 一時停止は位置を保ち、再開できる ---
	var engine: Variant = main.get("_sound_engine")
	var beep := "/tmp/sefixture/sound/se/beep.wav"
	if FileAccess.file_exists(beep):
		check(bool(engine.call("bgm_play", beep)), "bgm play starts")
		check(str(engine.call("bgm_state")) == "playing", "state playing")
		engine.call("bgm_pause")
		check(str(engine.call("bgm_state")) == "paused", "state paused")
		check(str(engine.call("bgm_current_path")) == beep,
			"path kept while paused")
		engine.call("bgm_resume")
		check(str(engine.call("bgm_state")) == "playing", "state resumed")
		engine.call("bgm_stop")
		check(str(engine.call("bgm_state")) == "stop", "state stopped")

	# --- ゲート: 未接続では閉じている ---
	check(bool(tab.call("bgm_suspended")) == true,
		"suspended while not connected")

	# --- 接続して落ち着けば開く ---
	tsession.set("_state", "open")
	tab.set("_bgm_busy_until", 0)
	check(bool(tab.call("bgm_suspended")) == false,
		"open after settle")

	# --- 受信が流れると閉じ、止まって少し経つと開く ---
	var pending: Array[PackedByteArray] = []
	for i in 5000:
		pending.append("dummy".to_ascii_buffer())
	tsession.set("_pending_lines", pending)
	await process_frame
	await process_frame
	check(bool(tab.call("bgm_suspended")) == true,
		"suspended while receiving")
	var empty_pending: Array[PackedByteArray] = []
	tsession.set("_pending_lines", empty_pending)
	# ダミー行の処理中にセッションが閉じた扱いになっている
	# ことがあるので、開いた状態に戻してから確かめる。
	tsession.set("_state", "open")
	check(bool(tab.call("bgm_suspended")) == true,
		"still suspended in settle window")
	tab.set("_bgm_busy_until", 1)
	check(bool(tab.call("bgm_suspended")) == false,
		"opens after settle window")

	# --- 世界移動中は閉じる ---
	tsession.set("_transfer_stage", "wait")
	check(bool(tab.call("bgm_suspended")) == true,
		"suspended while transferring")
	tsession.set("_transfer_stage", "")
	tab.set("_bgm_busy_until", 1)
	check(bool(tab.call("bgm_suspended")) == false,
		"opens after transfer")
	tsession.set("_state", "idle")

	print("test_stage74: ", _checks, " checks, ", _failures, " failures")
	quit(1 if _failures > 0 else 0)
