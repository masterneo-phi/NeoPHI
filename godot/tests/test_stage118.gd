extends SceneTree
## 第118段: 滑らかスクロールのずれ方向は、絶対座標があれば
## プレイヤーの実移動で決める。一面同じ地形で横移動すると
## 上下に揺れて見えた不具合の回帰テスト。

var _checks := 0
var _failures := 0


func check(cond: bool, label: String) -> void:
	_checks += 1
	if not cond:
		_failures += 1
		print("FAIL: ", label)


func _cells(dim: int, chip: int) -> Array:
	var out: Array = []
	for i in dim * dim:
		out.append({"chip": chip})
	return out


func _ev(dim: int, chip: int, pos: Variant) -> Dictionary:
	var e := {"size": dim, "cells": _cells(dim, chip)}
	if pos != null:
		e["pos"] = pos
	return e


func _initialize() -> void:
	var v := MapView.new()
	# 東へ移動 (一面砂): 以前は北 (0,-1) と誤判定していた
	v._event = _ev(7, 5, {"x": 10, "y": 10})
	v._detect_scroll(_ev(7, 5, {"x": 11, "y": 10}))
	check(v._scroll_from == Vector2(1, 0), "east move scrolls east: %s" % str(v._scroll_from))
	check(v._scroll_t == 0.0, "east move starts animation")
	# 南へ移動
	v._event = _ev(7, 5, {"x": 10, "y": 10})
	v._detect_scroll(_ev(7, 5, {"x": 10, "y": 11}))
	check(v._scroll_from == Vector2(0, 1), "south move scrolls south: %s" % str(v._scroll_from))
	# 北・西
	v._event = _ev(7, 5, {"x": 10, "y": 10})
	v._detect_scroll(_ev(7, 5, {"x": 10, "y": 9}))
	check(v._scroll_from == Vector2(0, -1), "north move scrolls north")
	v._event = _ev(7, 5, {"x": 10, "y": 10})
	v._detect_scroll(_ev(7, 5, {"x": 9, "y": 10}))
	check(v._scroll_from == Vector2(-1, 0), "west move scrolls west")
	# 移動失敗 (座標が変わらない) ではスクロールしない
	v._event = _ev(7, 5, {"x": 10, "y": 10})
	v._detect_scroll(_ev(7, 5, {"x": 10, "y": 10}))
	check(v._scroll_t == 1.0 and v._prev_cells.is_empty(), "no move, no scroll")
	# 転送 (大きく跳ぶ) でもスクロールしない
	v._event = _ev(7, 5, {"x": 10, "y": 10})
	v._detect_scroll(_ev(7, 5, {"x": 40, "y": 10}))
	check(v._scroll_t == 1.0 and v._prev_cells.is_empty(), "teleport, no scroll")
	# 絶対座標も移動の印も無い時、地形が完全に同じフレーム
	# では滑らせない (第123段: 以前はチップ比較に落ちて
	# (0,-1) に一致し、向き変更のたびに地図が揺れていた。
	# 一面同じ地形での実移動は、移動コマンドの印 (第119段)
	# が方向を決める)。
	v._event = _ev(7, 5, null)
	v._detect_scroll(_ev(7, 5, null))
	check(v._scroll_t == 1.0 and v._prev_cells.is_empty(), "no pos, identical frame does not scroll")
	print("stage118: ", _checks, " checks, ", _failures, " failures")
	quit(1 if _failures > 0 else 0)
