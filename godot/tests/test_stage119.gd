extends SceneTree
## 第119段: 実サーバは #ex-pos を送らないので、絶対座標が
## 無い時は自分が出した移動コマンドで滑らかスクロールの
## ずれ方向を決める。霧の中など一面同じ地形で横移動すると
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


func _ev(dim: int, chip: int) -> Dictionary:
	return {"size": dim, "cells": _cells(dim, chip)}


func _initialize() -> void:
	var v := MapView.new()
	# 東への移動コマンドの直後のフレーム: 一面同じ地形でも東へ滑る
	v._event = _ev(7, 5)
	v.note_move(Vector2i(1, 0))
	v._detect_scroll(_ev(7, 5))
	check(v._scroll_from == Vector2(1, 0), "commanded east scrolls east: %s" % str(v._scroll_from))
	check(v._scroll_t == 0.0, "commanded east starts animation")
	# 西・南・北
	for d in [Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		v._event = _ev(7, 5)
		v.note_move(d)
		v._detect_scroll(_ev(7, 5))
		check(v._scroll_from == Vector2(d), "commanded %s scrolls that way" % str(d))
	# 回転 (移動なし) の直後のフレームでは滑らせない
	v._event = _ev(7, 5)
	v.note_move(Vector2i.ZERO)
	v._detect_scroll(_ev(7, 5))
	check(v._scroll_t == 1.0 and v._prev_cells.is_empty(), "turn does not scroll")
	# 印は1フレームで消費される。消費後のフレームは、地形が
	# 完全に同じなら滑らせない (第123段: 以前はチップ比較の
	# フォールバックで (0,-1) に一致し、向き変更のたびに
	# 地図が揺れる原因になっていた)。
	v._event = _ev(7, 5)
	v.note_move(Vector2i(1, 0))
	v._detect_scroll(_ev(7, 5))
	check(v._scroll_from == Vector2(1, 0), "first frame uses the mark")
	v._event = _ev(7, 5)
	v._detect_scroll(_ev(7, 5))
	check(v._scroll_t == 1.0 and v._prev_cells.is_empty(), "second identical frame does not scroll")
	# 古い印 (2秒超) は使わない。地形が同じフレームは同じく
	# 滑らせない (第123段)。
	v._event = _ev(7, 5)
	v.note_move(Vector2i(1, 0))
	v._pending_move_at = Time.get_ticks_msec() - 3000
	v._detect_scroll(_ev(7, 5))
	check(v._scroll_t == 1.0 and v._prev_cells.is_empty(), "stale mark ignored, identical frame does not scroll")
	print("stage119: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)
