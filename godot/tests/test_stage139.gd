extends SceneTree
## 第139段のテスト: マウス移動の有効範囲は、自キャラを中心に
## 上下左右 3 マス (従来の 7×7 視界) の正方形だけ。11×11 や
## v6 の大きな視界でも、範囲外のクリックは歩行を始めず、
## 長押し中の方向も範囲外の位置では変わらない。描画範囲と
## 重なるタブの上の押しも歩行にしない。GUI のドラッグ
## (フロート窓) は従来どおり動く。
##
## 使い方: godot --headless --path . -s tests/test_stage139.gd
## 終了コード 0 = 全一致、1 = 不一致あり。

const Main := preload("res://scripts/main.gd")

var _failures := 0
var _checks := 0
var _tab: PhiCharacter = null


func check(cond: bool, label: String) -> void:
	_checks += 1
	if not cond:
		_failures += 1
		printerr("FAIL: ", label)


func check_eq(a: Variant, b: Variant, label: String) -> void:
	_checks += 1
	if a != b:
		_failures += 1
		printerr("FAIL: ", label, " (got ", a, ", want ", b, ")")


func _queue(tab: PhiCharacter) -> Array:
	return tab.session.get("_send_queue")


func _press(pos: Vector2) -> InputEventMouseButton:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = pos
	ev.global_position = pos
	return ev


func _release(pos: Vector2) -> InputEventMouseButton:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = false
	ev.position = pos
	ev.global_position = pos
	return ev


func _motion(pos: Vector2) -> InputEventMouseMotion:
	var ev := InputEventMouseMotion.new()
	ev.button_mask = MOUSE_BUTTON_MASK_LEFT
	ev.position = pos
	ev.global_position = pos
	return ev


func _cells(w: int, h: int) -> Array:
	var out: Array = []
	for i in range(w * h):
		out.append({"chip": 0x3F, "attr": 0})
	return out


func _feed(tab: PhiCharacter, ev: Dictionary) -> void:
	tab._on_event(ev)
	_queue(tab).clear()


func _feed_legacy(tab: PhiCharacter, size: int) -> void:
	_feed(tab, {"type": "map", "size": size, "dir": 0,
		"cells": _cells(size, size), "chars": []})


func _cell_pos(tab: PhiCharacter, cell: Vector2i) -> Vector2:
	## セルの中心の画面座標 (クリック位置の組み立て用)。
	var mv := tab.map_view
	var rect := mv.drawn_map_rect()
	var z := float(mv.zoom)
	var board := Vector2((float(cell.x) + 0.5) * float(MapView.CHIP_SIZE),
		float(MapView.MAP_TOP) + (float(cell.y) + 0.5) * float(MapView.CHIP_SIZE))
	return mv.get_global_transform() * (rect.position + board * z)


func _make_tab() -> PhiCharacter:
	var config := PhiConfig.new()
	config.log_auto_save = false
	config.ui_style = "old"
	var font := PhiFont.make_ui_font()
	var bold := PhiFont.make_bold_font()
	var tab := PhiCharacter.new()
	tab.setup(GameAssets.new(), config, font, bold, PhiLogFilter.new(), PhiTagMenu.parse(PhiTagMenu.DEFAULT_XML))
	root.add_child(tab)
	tab.position = Vector2.ZERO
	tab.size = Vector2(1280, 1024)
	# リスト決定直後の押しを呑むガード (第78段) に引っかからない
	# よう、決定時刻をはるか過去にしておく。
	tab.set("_list_click_decided_at", -1000000)
	return tab


func _initialize() -> void:
	_run()


func _run() -> void:
	_tab = _make_tab()
	await process_frame
	await process_frame
	await process_frame
	_test_legacy11()
	_test_legacy_small()
	_test_v6()
	_test_steering()
	await _test_main()
	print("test_stage139: ", _checks, " checks, ", _failures, " failures")
	quit(1 if _failures > 0 else 0)


# -- 従来 11×11: 距離 3 は動き、距離 4 は動かない --------------------------------

func _test_legacy11() -> void:
	var tab := _tab
	_feed_legacy(tab, 11)
	check_eq(tab.map_view.player_cell(), Vector2i(5, 5), "s139 11x11 self cell")
	# 範囲判定そのもの (境界)。
	check(bool(tab.call("_mouse_move_range_ok", _cell_pos(tab, Vector2i(5, 5)))), "s139 range self")
	check(bool(tab.call("_mouse_move_range_ok", _cell_pos(tab, Vector2i(2, 2)))), "s139 range corner 3")
	check(bool(tab.call("_mouse_move_range_ok", _cell_pos(tab, Vector2i(8, 8)))), "s139 range corner 3 se")
	check(not bool(tab.call("_mouse_move_range_ok", _cell_pos(tab, Vector2i(5, 1)))), "s139 range 4 north out")
	check(not bool(tab.call("_mouse_move_range_ok", _cell_pos(tab, Vector2i(9, 5)))), "s139 range 4 east out")
	# 距離 3 (真上) のクリックで歩行が始まる。
	var p3 := _cell_pos(tab, Vector2i(5, 2))
	tab.handle_mouse_button(_press(p3))
	check(bool(tab.get("_mouse_held")), "s139 dist3 starts hold")
	check_eq(_queue(tab), ["go N"], "s139 dist3 sends go N")
	tab.handle_mouse_button(_release(p3))
	check(not bool(tab.get("_mouse_held")), "s139 release ends hold")
	_queue(tab).clear()
	# 距離 3 (正方形の角) のクリックでも始まる (2 行の移動)。
	var pc := _cell_pos(tab, Vector2i(2, 2))
	tab.handle_mouse_button(_press(pc))
	check(bool(tab.get("_mouse_held")), "s139 corner3 starts hold")
	check_eq(_queue(tab), ["go N", "go W"], "s139 corner3 sends two steps")
	tab.handle_mouse_button(_release(pc))
	_queue(tab).clear()
	# 距離 4 のクリックは、描いている地図の上であっても歩行に
	# ならない (以前はここで歩き出していた)。
	var p4 := _cell_pos(tab, Vector2i(5, 1))
	check(bool(tab.call("_over_map", p4)), "s139 dist4 is on drawn map")
	tab.handle_mouse_button(_press(p4))
	check(not bool(tab.get("_mouse_held")), "s139 dist4 starts no hold")
	check_eq(_queue(tab), [], "s139 dist4 sends nothing")
	tab.handle_mouse_button(_release(p4))


# -- 従来 7×7 / 5×5: 盤内は全部範囲内 (従来どおり) ------------------------------

func _test_legacy_small() -> void:
	var tab := _tab
	_feed_legacy(tab, 7)
	check_eq(tab.map_view.player_cell(), Vector2i(3, 3), "s139 7x7 self cell")
	var p := _cell_pos(tab, Vector2i(3, 0))
	tab.handle_mouse_button(_press(p))
	check(bool(tab.get("_mouse_held")), "s139 7x7 edge starts hold")
	check_eq(_queue(tab), ["go N"], "s139 7x7 edge sends go N")
	tab.handle_mouse_button(_release(p))
	_queue(tab).clear()
	_feed_legacy(tab, 5)
	check_eq(tab.map_view.player_cell(), Vector2i(2, 2), "s139 5x5 self cell")
	# 5×5 は回転様式なので、角は回転ゾーン (従来どおり)。西の
	# 縁のマスで移動を見る。
	var p5 := _cell_pos(tab, Vector2i(0, 2))
	tab.handle_mouse_button(_press(p5))
	check(bool(tab.get("_mouse_held")), "s139 5x5 edge starts hold")
	check_eq(_queue(tab), ["go l"], "s139 5x5 edge sends go l")
	tab.handle_mouse_button(_release(p5))
	_queue(tab).clear()


# -- v6 の大きな視界: 自キャラの位置基準で判定し、斜めも畳める -------------------

func _test_v6() -> void:
	var tab := _tab
	tab.session.v6_mode = true
	tab.session.v6_diag = true
	_feed(tab, {"type": "map", "v6": true, "w": 25, "h": 19, "dir": 0,
		"cells": _cells(25, 19), "chars": [], "selfCell": {"x": 7, "y": 12}})
	check_eq(tab.map_view.player_cell(), Vector2i(7, 12), "s139 v6 self cell off-center")
	# 自キャラから距離 3 の角 (画面中心からは遠い) でも始まり、
	# 斜めは 1 行に畳まれる。
	var pd := _cell_pos(tab, Vector2i(4, 15))
	tab.handle_mouse_button(_press(pd))
	check(bool(tab.get("_mouse_held")), "s139 v6 dist3 starts hold")
	check_eq(_queue(tab), ["go sw"], "s139 v6 dist3 diagonal collapsed")
	tab.handle_mouse_button(_release(pd))
	_queue(tab).clear()
	# 距離 4 は始まらない。
	var p4 := _cell_pos(tab, Vector2i(11, 12))
	tab.handle_mouse_button(_press(p4))
	check(not bool(tab.get("_mouse_held")), "s139 v6 dist4 starts no hold")
	check_eq(_queue(tab), [], "s139 v6 dist4 sends nothing")
	tab.handle_mouse_button(_release(p4))
	# 画面の中心付近でも、自キャラから遠ければ始まらない
	# (判定は視界の中心ではなく自キャラの位置が基準)。
	var pc := _cell_pos(tab, Vector2i(12, 9))
	check(bool(tab.call("_over_map", pc)), "s139 v6 center cell is on drawn map")
	tab.handle_mouse_button(_press(pc))
	check(not bool(tab.get("_mouse_held")), "s139 v6 view-center far cell starts no hold")
	check_eq(_queue(tab), [], "s139 v6 view-center far cell sends nothing")
	tab.handle_mouse_button(_release(pc))
	tab.session.v6_mode = false
	tab.session.v6_diag = false


# -- 長押し中の方向追随: 範囲内では変わり、範囲外では変わらない -------------------

func _test_steering() -> void:
	var tab := _tab
	_feed_legacy(tab, 11)
	var p := _cell_pos(tab, Vector2i(5, 2))
	tab.handle_mouse_button(_press(p))
	check(bool(tab.get("_mouse_held")), "s139 steer hold starts")
	_queue(tab).clear()
	# 範囲内 (距離 3 の東) へ動かすと、方向がそちらへ変わる。
	tab.handle_mouse_motion(_motion(_cell_pos(tab, Vector2i(8, 5))))
	tab.set("_mouse_last_repeat", 0)
	tab.call("_mouse_repeat_send_if_ready")
	check_eq(tab.get("_mouse_hold_cursor"), "MouseRight", "s139 steer in range turns east")
	check_eq(_queue(tab), ["go E"], "s139 steer in range sends go E")
	_queue(tab).clear()
	# 範囲外 (距離 5) へ動かしても、方向は変わらない。
	tab.handle_mouse_motion(_motion(_cell_pos(tab, Vector2i(5, 0))))
	tab.set("_mouse_last_repeat", 0)
	tab.call("_mouse_repeat_send_if_ready")
	check_eq(tab.get("_mouse_hold_cursor"), "MouseRight", "s139 steer out of range keeps direction")
	check_eq(_queue(tab), ["go E"], "s139 steer out of range sends same direction")
	tab.handle_mouse_button(_release(p))
	check(not bool(tab.get("_mouse_held")), "s139 steer release ends hold")
	_queue(tab).clear()


# -- Main 経由: タブの上の押しは歩行にせず、フロート窓のドラッグは従来どおり -------

func _test_main() -> void:
	var dir := DirAccess.open("user://")
	if dir != null:
		for f in ["stage139_tabs.ini", "stage139_main.ini"]:
			if dir.file_exists(f):
				dir.remove(f)
	var main: Node = Main.new()
	main.set("_tab_session_path", "user://stage139_tabs.ini")
	main.set("_config_path", "user://stage139_main.ini")
	root.add_child(main)
	await process_frame
	await process_frame
	var tab: PhiCharacter = main.call("_active_tab")
	tab.set("_list_click_decided_at", -1000000)
	_feed_legacy(tab, 11)
	# タブボタンの中心を、メインの入力経路 (タブへの転送) で押す。
	var buttons: Array = main.get("_tab_buttons")
	check(not buttons.is_empty(), "s139 main has a tab button")
	if not buttons.is_empty():
		var btn := buttons[0]["button"] as Button
		var center := btn.get_global_rect().get_center()
		main.call("_input", _press(center))
		check(not bool(tab.get("_mouse_held")), "s139 tab button press starts no hold")
		check_eq(_queue(tab), [], "s139 tab button press sends nothing")
		main.call("_input", _release(center))
	# フロート窓 (新スタイル) のドラッグは、地図があっても
	# 従来どおり: 帯の押しでドラッグが始まり、歩行は始まらない。
	var config: PhiConfig = main.get("_config")
	tab.map_view.size = Vector2(1380, 700)
	config.ui_style = "new"
	tab.apply_ui_style()
	var log_float := tab.get("_log_float") as PanelContainer
	check(log_float != null, "s139 log float exists")
	if log_float != null:
		var in_log := log_float.global_position + log_float.size * 0.5
		tab.handle_mouse_button(_press(in_log))
		check(not bool(tab.get("_mouse_held")), "s139 press on log float starts no hold")
		var band := tab.get("_log_float_band") as PanelContainer
		var bev := InputEventMouseButton.new()
		bev.button_index = MOUSE_BUTTON_LEFT
		bev.pressed = true
		bev.position = Vector2(20, 5)
		bev.global_position = band.global_position + Vector2(20, 5)
		tab.call("_on_float_band_gui_input", bev, log_float)
		check(tab.get("_float_drag_panel") == log_float, "s139 float drag starts on band")
		check(not bool(tab.get("_mouse_held")), "s139 float drag starts no hold")
		var before := log_float.position
		tab.handle_mouse_motion(_motion(band.global_position + Vector2(90, 50)))
		check(log_float.position != before, "s139 float drag moves window")
		tab.handle_mouse_button(_release(band.global_position + Vector2(90, 50)))
		check(tab.get("_float_drag_panel") == null, "s139 float drag ends on release")
	main.queue_free()
