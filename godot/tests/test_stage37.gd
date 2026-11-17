extends SceneTree
## 第37段: (1) ファイルメニューから「新しいタブ」「タブを閉じる」を
## 削除 (タブの×・新規接続・キャラデータ読み込みで代替できる)。
## (2) Talk ボタンをドラッグで移動可能にし、位置を設定に残す。

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
	# (1) アクションとメニューから消えていること
	check(PhiActions.get_action("NewTab").is_empty(), "NewTab action removed")
	check(PhiActions.get_action("CloseTab").is_empty(), "CloseTab action removed")
	var file_items: Array = []
	for menu in PhiActions.MENUS:
		if str(menu.get("name", "")) == "ファイル":
			file_items = menu.get("items", [])
	check(not file_items.has("NewTab"), "file menu has no NewTab")
	check(not file_items.has("CloseTab"), "file menu has no CloseTab")
	check(file_items.has("Open"), "file menu keeps Open")
	check(file_items.has("Exit"), "file menu keeps Exit")

	# (2) 設定の往復 (Talk ボタンの位置)
	var cfg := PhiConfig.new()
	cfg.talk_button_pos = Vector2(123, 45)
	check(cfg.save_file("user://stage37_test_config.ini"), "config save ok")
	var loaded := PhiConfig.new()
	check(loaded.load_file("user://stage37_test_config.ini"), "config load ok")
	check(loaded.talk_button_pos == Vector2(123, 45), "talk pos roundtrip")
	var dir := DirAccess.open("user://")
	if dir != null:
		dir.remove("stage37_test_config.ini")

	# (3) 実物のボタンでドラッグとクリックを確かめる
	var ps := load("res://main.tscn") as PackedScene
	var main: Node = ps.instantiate()
	root.add_child(main)
	await create_timer(1.5).timeout
	var tab: Node = main.call("_create_tab")
	main.call("_activate_tab", tab)
	await create_timer(0.8).timeout
	var btn: Button = tab.get("_talk_button")
	check(btn != null, "talk button exists")
	if btn != null:
		var map_view: Control = tab.get("map_view")
		# ヘッドレスではレイアウトが潰れるので、地図の大きさを
		# 明示してから位置関係を確かめる (以降は同期呼び出しのみ)。
		map_view.size = Vector2(900, 700)
		check(btn.size.x >= 56.0, "talk button size")
		# 既定は左下 (地図の下辺近く)
		check(btn.position.y > map_view.size.y - btn.size.y - 40.0, "talk default bottom")
		check(btn.position.x < 40.0, "talk default left")
		# プレス → 大きく動かす → 離す = ドラッグ移動
		var press_global := btn.global_position + Vector2(20, 20)
		var ev_press := InputEventMouseButton.new()
		ev_press.button_index = MOUSE_BUTTON_LEFT
		ev_press.pressed = true
		ev_press.position = press_global
		ev_press.global_position = press_global
		tab.call("_on_talk_button_gui_input", ev_press)
		check(bool(tab.get("_talk_dragging")), "drag armed")
		var ev_motion := InputEventMouseMotion.new()
		ev_motion.position = press_global + Vector2(150, -90)
		ev_motion.global_position = press_global + Vector2(150, -90)
		tab.call("handle_mouse_motion", ev_motion)
		check(bool(tab.get("_talk_drag_moved")), "drag moved flag")
		var ev_release := InputEventMouseButton.new()
		ev_release.button_index = MOUSE_BUTTON_LEFT
		ev_release.pressed = false
		ev_release.position = press_global + Vector2(150, -90)
		ev_release.global_position = press_global + Vector2(150, -90)
		tab.call("_on_talk_button_gui_input", ev_release)
		check(not bool(tab.get("_talk_dragging")), "drag ended")
		check(btn.position.x > 100.0, "button moved right")
		check(btn.position.y < map_view.size.y - btn.size.y - 40.0, "button moved up")
		var cfg2: PhiConfig = tab.get("_config")
		check(cfg2 != null and cfg2.talk_button_pos == btn.position, "drag pos saved to config")
		# 動かさずに離す = クリック (未接続なので発言はしない、位置も不変)
		var before := btn.position
		var ev_press2 := InputEventMouseButton.new()
		ev_press2.button_index = MOUSE_BUTTON_LEFT
		ev_press2.pressed = true
		ev_press2.position = btn.global_position + Vector2(10, 10)
		ev_press2.global_position = btn.global_position + Vector2(10, 10)
		tab.call("_on_talk_button_gui_input", ev_press2)
		var ev_release2 := InputEventMouseButton.new()
		ev_release2.button_index = MOUSE_BUTTON_LEFT
		ev_release2.pressed = false
		ev_release2.position = ev_press2.position
		ev_release2.global_position = ev_press2.global_position
		tab.call("_on_talk_button_gui_input", ev_release2)
		check(btn.position == before, "click keeps position")
		check(not bool(tab.get("_talk_dragging")), "click ends drag state")
	print("test_stage37: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)
