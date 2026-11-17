extends SceneTree
## 第92段のテスト: 入力欄で一度発言した行は、下書きが空でも
## Enter でそのまま再発言できる。履歴を書き換えた場合は
## 書き換えた文が下書きとして送られ、履歴を消した場合は
## 再発言しない。境界 (履歴モデル) が壊れないことも見る。
##
## 使い方: godot --headless --path . -s tests/test_stage92.gd
## 終了コード 0 = 全一致、1 = 不一致あり。

const Main := preload("res://scripts/main.gd")

var _checks := 0
var _failures := 0
var _tab: Variant = null


func check(cond: bool, label: String) -> void:
	_checks += 1
	if not cond:
		_failures += 1
		printerr("FAIL: ", label)


func _initialize() -> void:
	call_deferred("_run")


func _queue() -> Array:
	return _tab.session.get("_send_queue")


func _run() -> void:
	var main: Node = Main.new()
	var iso := ProjectSettings.globalize_path("user://stage92_tabs.ini")
	OS.execute("rm", ["-f", iso])
	main.set("_tab_session_path", "user://stage92_tabs.ini")
	var isoc := ProjectSettings.globalize_path("user://stage92_cfg.ini")
	OS.execute("rm", ["-f", isoc])
	main.set("_config_path", "user://stage92_cfg.ini")
	root.add_child(main)
	await process_frame
	await process_frame
	_tab = main.call("_active_tab")
	var tab: Variant = _tab
	tab.input_box.grab_focus()
	# 1回目の発言。
	tab.input_box.text = "こんにちは"
	tab.submit_input()
	check(_queue().size() == 1, "s92 first speech queued")
	var first: Variant = _queue()[0]
	# 下書きが空のまま Enter → 同じ文が再発言される。
	tab.submit_input()
	check(_queue().size() == 2, "s92 resend queued")
	check(_queue()[1] == first, "s92 resend is the same line")
	# 何度でも再発言できる。
	tab.submit_input()
	check(_queue().size() == 3, "s92 resend again")
	# 再発言の後も、続けて打った文は下書きとして送れる
	# (境界が壊れていない)。
	tab.input_box.text = tab.input_box.text + "つづきです"
	tab.submit_input()
	check(_queue().size() == 4, "s92 draft after resend queued")
	check(_queue()[3] != first, "s92 draft after resend is new text")
	# 送った文を書き換えると、書き換えた文が送られる
	# (再発言にはならない)。
	tab.input_box.text = "かきかえた文"
	tab.submit_input()
	check(_queue().size() == 5, "s92 edited history queued as draft")
	# 履歴を消すと、再発言はしない。
	tab.clear_input_history()
	var before := _queue().size()
	tab.submit_input()
	check(_queue().size() == before, "s92 no resend after history clear")
	print("test_stage92: ", _checks, " checks, ", _failures, " failures")
	quit(1 if _failures > 0 else 0)
