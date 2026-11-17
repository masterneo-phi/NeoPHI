extends SceneTree
## 第87段のテスト: Eagle Eye の盤は地図の倍率に連動せず、
## チップ実寸を上限に、全体が 560px に収まる大きさになる。
##
## 使い方: godot --headless --path . -s tests/test_stage87.gd
## 終了コード 0 = 全一致、1 = 不一致あり。

var _checks := 0
var _failures := 0


func check(cond: bool, label: String) -> void:
	_checks += 1
	if not cond:
		_failures += 1
		printerr("FAIL: ", label)


func _event(dim: int) -> Dictionary:
	var cells: Array = []
	for i in range(dim * dim):
		cells.append({"chip": 1, "attr": 0})
	return {"width": dim, "height": dim, "cells": cells}


func _initialize() -> void:
	var view := PhiEagleView.new()
	# 20x20 でも地図倍率 4 でも、盤は 560px (+上帯) に収まる。
	view.set_event(_event(20), null, "", 4.0, {})
	var s20 := view.board_pixel_size()
	check(s20.x <= 560.0 and s20.y <= 560.0 + MapView.MAP_TOP, "s87 20x20 board capped")
	check(is_equal_approx(s20.x, 560.0), "s87 20x20 board uses the cap")
	# 15x15 は実寸 (480px) のまま、倍率に引きずられない。
	view.set_event(_event(15), null, "", 4.0, {})
	var s15 := view.board_pixel_size()
	check(is_equal_approx(s15.x, 480.0), "s87 15x15 board at native size")
	# 11x11 も実寸。
	view.set_event(_event(11), null, "", 2.0, {})
	var s11 := view.board_pixel_size()
	check(is_equal_approx(s11.x, 352.0), "s87 11x11 board at native size")
	print("test_stage87: ", _checks, " checks, ", _failures, " failures")
	quit(1 if _failures > 0 else 0)
