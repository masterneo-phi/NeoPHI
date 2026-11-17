extends SceneTree
## 第20段のテスト: キャラの歩行アニメーション。
## chara_src_rect のフレーム位置 (0/1 で小・大それぞれ次のコマ) と、
## MapView が 500ms ごとに _anim_frame を切り替えること、
## PhiEagleView の人のフレームも切り替わることを確認する。
##
## 使い方: godot --headless --path . -s tests/test_stage20.gd
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


func _wait(sec: float) -> void:
	var until := Time.get_ticks_msec() + int(sec * 1000.0)
	while Time.get_ticks_msec() < until:
		await process_frame


func _clock_frame() -> int:
	return int(Time.get_ticks_msec() / 500) % 2


func _run() -> void:
	# フレーム位置: 小は 16px 刻み (0, 16)、大は 32+32px 刻み (32, 64)。
	_check_eq(MapView.chara_src_rect("F", "#", 0).position.x, 0.0, "小 frame0 の x")
	_check_eq(MapView.chara_src_rect("F", "#", 1).position.x, 16.0, "小 frame1 の x")
	_check_eq(MapView.chara_src_rect("F", "*", 0).position.x, 32.0, "大 frame0 の x")
	_check_eq(MapView.chara_src_rect("F", "*", 1).position.x, 64.0, "大 frame1 の x")
	_check_eq(MapView.chara_src_rect("F", "#", 3).position.x, 16.0, "frame は 2 で割った余り")
	# MapView: 地図がある間 _anim_frame が時計に追随する。
	var view := MapView.new()
	view.size = Vector2(400, 400)
	root.add_child(view)
	var cells: Array = []
	for i in range(49):
		cells.append({"chip": 0x2E, "attr": 0})
	view.set_map({"size": 7, "cells": cells, "chars": []}, null, "")
	_check_eq(int(view.get("_anim_frame")), _clock_frame(), "set_map 直後のフレームは時計どおり")
	var first := int(view.get("_anim_frame"))
	var flipped := false
	var until := Time.get_ticks_msec() + 1400
	while Time.get_ticks_msec() < until:
		await process_frame
		if int(view.get("_anim_frame")) != first:
			flipped = true
			break
	_check(flipped, "500ms 周期でフレームが切り替わる")
	_check_eq(int(view.get("_anim_frame")), _clock_frame(), "切替後のフレームも時計どおり")
	# PhiEagleView: 人のフレームも切り替わる。
	var eagle := PhiEagleView.new()
	root.add_child(eagle)
	var ecells: Array = []
	for i in range(9):
		ecells.append({"chip": 0x2E, "attr": 0})
	eagle.set_event({"width": 3, "height": 3, "cells": ecells}, null, "", 2.0)
	var efirst := int(eagle.get("_anim_frame"))
	var eflipped := false
	until = Time.get_ticks_msec() + 1400
	while Time.get_ticks_msec() < until:
		await process_frame
		if int(eagle.get("_anim_frame")) != efirst:
			eflipped = true
			break
	_check(eflipped, "Eagle のフレームも切り替わる")
	print("test_stage20: ", _checks, " checks, ", _failures, " failures")
	quit(1 if _failures > 0 else 0)
