extends SceneTree
## 第92段のテスト: 再発言と行単位の送信。最終行が空の Enter で
## 直前に送った行が再発言でき、履歴を消すと再発言しない。
## 送信はキャレットのある行だけが対象 (2026-11-23 ユーザー
## 決定): 履歴の行でも、書き換えた行でも、貼った複数行でも、
## その行だけが送られ、他の行は送られない。
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
	# 再発言の後も、続けて打った文はその行として送れる。
	tab.input_box.text = tab.input_box.text + "つづきです"
	tab.input_box.set_caret_line(1)
	tab.input_box.set_caret_column(5)
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
	# -- 行単位の送信 (2026-11-23 ユーザー決定) --
	# 2行を順に送って履歴を作る。
	tab.input_box.text = "いち行目"
	tab.input_box.set_caret_line(0)
	tab.input_box.set_caret_column(4)
	tab.submit_input()
	check(_queue().size() == before + 1, "s92 line1 queued")
	tab.input_box.text = "いち行目\nにぎょう目"
	tab.input_box.set_caret_line(1)
	tab.input_box.set_caret_column(5)
	tab.submit_input()
	check(_queue().size() == before + 2, "s92 line2 queued")
	check(_queue()[before + 1] == "にぎょう目", "s92 line2 only")
	# 履歴の行で Enter → その行だけが送られ、下の行は送られない。
	tab.input_box.set_caret_line(0)
	tab.input_box.set_caret_column(0)
	tab.submit_input()
	check(_queue().size() == before + 3, "s92 history line sends one only")
	check(_queue()[before + 2] == "いち行目", "s92 history line content")
	# 履歴の行を書き換えて Enter → 書き換えた行だけが送られる。
	tab.input_box.text = "いち行目\nにぎょう目・改\n"
	tab.input_box.set_caret_line(1)
	tab.input_box.set_caret_column(7)
	tab.submit_input()
	check(_queue().size() == before + 4, "s92 edited line sends one only")
	check(_queue()[before + 3] == "にぎょう目・改", "s92 edited line content")
	# 再発言の対象は、最後に送った行そのもの (複数行の塊ではない)。
	tab.submit_input()
	check(_queue().size() == before + 5, "s92 resend after edit queued")
	check(_queue()[before + 4] == "にぎょう目・改", "s92 resend is last sent line")
	# 複数行を貼っても、Enter はキャレット行だけを送る。
	tab.input_box.text = "ぺーすと1\nぺーすと2\nぺーすと3"
	tab.input_box.set_caret_line(1)
	tab.input_box.set_caret_column(0)
	tab.submit_input()
	check(_queue().size() == before + 6, "s92 paste sends caret line only")
	check(_queue()[before + 5] == "ぺーすと2", "s92 paste caret line content")
	print("test_stage92: ", _checks, " checks, ", _failures, " failures")
	quit(1 if _failures > 0 else 0)
