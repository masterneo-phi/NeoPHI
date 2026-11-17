extends SceneTree
## 第15段のテスト: Eagle Eye の広域マップ表示。
## PhiEagleView の盤面整形 (正方形化・外側は '?'・人のマスは地形+
## 人に分離・倍率の上限) と、タブに eagleEye イベントを流すと
## Main の Eagle Eye 窓が開くことを確認する。
##
## 使い方: godot --headless --path . -s tests/test_stage15.gd
## 終了コード 0 = 全一致、1 = 不一致あり。

var _failures := 0
var _checks := 0


func _check(cond: bool, label: String) -> void:
	_checks += 1
	if not cond:
		_failures_add(label)


func _check_eq(a: Variant, b: Variant, label: String) -> void:
	_checks += 1
	if a != b:
		_failures_add(label + " (got " + str(a) + ", want " + str(b) + ")")


func _failures_add(label: String) -> void:
	_failures += 1
	printerr("FAIL: ", label)


func _initialize() -> void:
	_run()


func _sample_event() -> Dictionary:
	# 5x3 の盤面。 (2,1) に人 (attr 0x58)、(0,0) に看板 (attr 0x08)、
	# (4,2) にアイテム (attr 0x10)。
	var cells: Array = []
	for i in 15:
		cells.append({"chip": 0x2E, "attr": 0})
	cells[0] = {"chip": 0x2E, "attr": 0x08}
	cells[1 * 5 + 2] = {"chip": 0x2E, "attr": 0x58}
	cells[2 * 5 + 4] = {"chip": 0x2E, "attr": 0x10}
	return {"type": "eagleEye", "width": 5, "height": 3, "cells": cells, "self": {"x": 2, "y": 1}}


func _test_view_board() -> void:
	var view := PhiEagleView.new()
	view.set_event(_sample_event(), null, "", 1.0)
	_check_eq(view.board_dim(), 5, "盤面は max(width, height) の正方形")
	_check_eq(view.get("_cells").size(), 25, "セルは 25 個に整う")
	var cells: Array = view.get("_cells")
	_check_eq(int(cells[4 * 5 + 4]["chip"]), 0x3F, "盤面の外は '?' で埋まる")
	_check_eq(int(cells[0]["attr"]), 0x08, "看板の attr は残る")
	_check_eq(int(cells[1 * 5 + 2]["attr"]), 0, "人のマスの attr は地形に戻る")
	var persons: Array = view.get("_persons")
	_check_eq(persons.size(), 1, "人が 1 人分離される")
	_check_eq(int(persons[0]["x"]), 2, "人の x")
	_check_eq(int(persons[0]["y"]), 1, "人の y")
	_check_eq(view.board_pixel_size(), Vector2(160, 176), "倍率1の大きさ (5*32, 5*32+16)")
	view.set_event(_sample_event(), null, "", 4.0)
	_check_eq(view.board_pixel_size(), Vector2(640, 704), "倍率4の大きさ")
	# 大きい盤面では上限に合わせて倍率が落ちる。
	var big := {"type": "eagleEye", "width": 15, "height": 15, "cells": []}
	var big_cells: Array = []
	for i in 225:
		big_cells.append({"chip": 0x2E, "attr": 0})
	big["cells"] = big_cells
	view.set_event(big, null, "", 4.0)
	_check(view.board_pixel_size().x <= PhiEagleView.MAX_BOARD_PX + 0.01, "大きい盤面は上限 px に収まる")
	view.free()


func _test_bar_number_layout() -> void:
	# スラッシュはバーの中央に固定され、現在値の右端と最大値の
	# 左端は現在値の幅に依らず同じ位置に来る (行間整列の要)。
	var rect := Rect2(100, 0, 400, 20)
	var a := StatusPanel.bar_number_layout(40.0, 10.0, rect)
	var b := StatusPanel.bar_number_layout(73.0, 10.0, rect)
	_check_eq(a[1], 295.0, "スラッシュは中央 (100+200-5)")
	_check_eq(a[2], b[2], "最大値の左端は現在値の幅に依らない")
	_check_eq(a[0] + 40.0, b[0] + 73.0, "現在値の右端は幅に依らずそろう")
	_check(a[0] < a[1] and a[1] < a[2], "並びは 現在値 < / < 最大値")


func _run() -> void:
	_test_view_board()
	_test_bar_number_layout()
	# Main + タブ: eagleEye イベントで窓が開く。
	var ps := load("res://main.tscn") as PackedScene
	var main: Node = ps.instantiate()
	root.add_child(main)
	for i in 10:
		await process_frame
	var tab: Node = main.call("_active_tab")
	tab.call("_on_event", _sample_event())
	for i in 5:
		await process_frame
	var win: Variant = main.get("_eagle_window")
	_check(win != null, "Eagle Eye 窓が作られる")
	if win != null:
		_check((win as Window).visible, "Eagle Eye 窓が表示される")
		var view: Variant = (win as PhiEagleWindow).get("_view")
		_check_eq((view as PhiEagleView).board_dim(), 5, "窓の盤面が 5x5")
	main.queue_free()
	print("test_stage15: ", _checks, " checks, ", _failures, " failures")
	quit(1 if _failures > 0 else 0)
