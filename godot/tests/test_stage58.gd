extends SceneTree
## 第58段: (1) 選択中のタブが青くなる。
## (2) 接続直後とログ描き直しの後、スクロールが最下部に留まる
##     (留め置き期限が立つことと、実際に最下部へ寄ること)。

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
	var ps := load("res://main.tscn") as PackedScene
	var main: Node = ps.instantiate()
	root.add_child(main)
	await create_timer(1.0).timeout
	var tab1: Variant = main.call("_active_tab")
	var tab2: Variant = main.call("_create_tab")
	main.call("_activate_tab", tab2)
	await process_frame
	# (1) 青い地はアクティブなタブのボタンだけに付く。
	var buttons: Dictionary = {}
	for entry in main.get("_tab_buttons"):
		buttons[entry["tab"]] = entry["button"]
	var b2: Button = buttons[tab2]
	var box: StyleBox = b2.get_theme_stylebox("normal")
	check(box is StyleBoxFlat and (box as StyleBoxFlat).bg_color.b > 0.6, "active tab button is blue")
	check(b2.get_theme_color("font_color") == Color.WHITE, "active tab text is white")
	var b1: Button = buttons[tab1]
	check(not b1.has_theme_stylebox_override("normal"), "inactive tab has no blue box")
	main.call("_activate_tab", tab1)
	await process_frame
	check(not b2.has_theme_stylebox_override("normal"), "blue moves with activation")
	check(b1.get_theme_stylebox("normal") is StyleBoxFlat, "new active tab is blue")
	# (2) ログの留め置き: 描き直しで最下部だった場合は期限が立ち、
	# その間 _process が最下部へ寄せ続ける。
	var tab: Variant = tab1
	for i in range(60):
		tab.log_message("log", "スクロール確認の行 %d" % i)
	await process_frame
	await process_frame
	tab.call("_restore_log_scroll", 1.0, true)
	check(float(tab.get("_stick_log_bottom_until")) > Time.get_ticks_msec() / 1000.0, "stick deadline set after rebuild at bottom")
	var bar: VScrollBar = tab.log_view.get_v_scroll_bar()
	bar.value = 0.0
	tab.call("_process", 0.016)
	check(bar.value >= bar.max_value - bar.page - 1.0, "process pins scroll to bottom (got %s of %s)" % [bar.value, bar.max_value])
	main.queue_free()

	print("stage58: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)
