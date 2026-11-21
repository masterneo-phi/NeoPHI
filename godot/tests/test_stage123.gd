extends SceneTree
## 第123段: 向きを変えるたびに地図全体が揺れる不具合の回帰
## テスト (実機報告、りんぐ)。原因は2つ:
## (1) キー・マウスの移動送信が PhiCharacter の send_text /
##     send_line を通らず session へ直接送られ、移動の印
##     (note_move) が MapView に残らなかった。
## (2) 印が無い時のチップ比較フォールバックが、地形の全く
##     変わっていないフレーム (向き変更・他人の移動) でも
##     候補 (0,-1) に一致し、滑らかスクロールが誤発火した。
## 同位置・4方向で描画原点が一致すること、実移動の滑らか
## スクロールが壊れていないことを確認する。

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
		out.append({"chip": chip, "attr": 0})
	return out


func _ev(dim: int, chip: int, dir: String) -> Dictionary:
	return {"size": dim, "cells": _cells(dim, chip),
		"chars": [{"name": "Tester", "x": dim / 2, "y": dim / 2, "dir": dir, "layer": 12}]}


## そのフレームでの実効描画原点 (地図の四角の左上 + スクロール
## 開始時点のずれ)。スクロールしていなければ素の原点。
func _origin(v: MapView) -> Vector2:
	var o := v.drawn_map_rect().position
	if v._scroll_t < 1.0 and not v._prev_cells.is_empty():
		o += v._scroll_from * float(MapView.CHIP_SIZE) * float(v.zoom)
	return o


func _pattern_cells(dim: int) -> Array:
	var out: Array = []
	for y in range(dim):
		for x in range(dim):
			out.append({"chip": (x * 3 + y * 7) % 9 + 1, "attr": 0})
	return out


## old を s 方向へ1マスずらした新しい盤面 (プレイヤーが s へ
## 動いた時に届くフレーム)。はみ出す端は適当なチップで埋める。
func _shifted(cells: Array, dim: int, s: Vector2i) -> Array:
	var out: Array = []
	for y in range(dim):
		for x in range(dim):
			var ox := x + s.x
			var oy := y + s.y
			if ox < 0 or oy < 0 or ox >= dim or oy >= dim:
				out.append({"chip": 40, "attr": 0})
			else:
				out.append(cells[oy * dim + ox])
	return out


func _initialize() -> void:
	# --- 向き変更 (キー経路 = 印なし): 4方向とも滑らせず、
	# 描画原点が一致する ---
	var v := MapView.new()
	v.size = Vector2(700, 700)
	v._event = _ev(7, 4, "F")
	var base_origin := _origin(v)
	for dir in ["B", "R", "L", "F"]:
		var ev := _ev(7, 4, dir)
		v._detect_scroll(ev)
		v._event = ev
		check(v._scroll_t == 1.0 and v._prev_cells.is_empty(),
			"turn to %s does not scroll (no-note path)" % dir)
		check(_origin(v) == base_origin,
			"origin identical facing %s" % dir)
	# --- 向き変更 (手入力経路 = 印あり) も滑らせない ---
	v._event = _ev(7, 4, "F")
	for dir in ["R", "B"]:
		v.note_move(Vector2i.ZERO)
		var ev2 := _ev(7, 4, dir)
		v._detect_scroll(ev2)
		v._event = ev2
		check(v._scroll_t == 1.0 and v._prev_cells.is_empty(),
			"turn to %s does not scroll (note path)" % dir)
	# --- 地形の模様がある場所での実移動 (印なし) は、今まで
	# どおりチップ比較で正しい向きに滑る ---
	var pat := _pattern_cells(7)
	for s in [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]:
		v._event = {"size": 7, "cells": pat, "chars": []}
		v._detect_scroll({"size": 7, "cells": _shifted(pat, 7, s), "chars": []})
		check(v._scroll_t == 0.0 and v._scroll_from == Vector2(s),
			"real move %s still scrolls by chip matching" % str(s))
	# --- 一面同じ地形での実移動は、印があればその向きに滑る ---
	v._event = _ev(7, 4, "F")
	v.note_move(Vector2i(1, 0))
	v._detect_scroll(_ev(7, 4, "F"))
	check(v._scroll_t == 0.0 and v._scroll_from == Vector2(1, 0),
		"uniform move with note scrolls east")
	# --- PhiCharacter: 保持キー経路が印を残す ---
	var pc := PhiCharacter.new()
	var mv := MapView.new()
	pc.map_view = mv
	pc._held_moves = [{"code": 0, "key": "7", "mods": "none"}]
	pc._send_held_step()
	check(pc.session._send_queue.has("turn l"), "held 7 sends 'turn l'")
	check(mv._pending_move == Vector2i.ZERO, "held turn records ZERO note")
	pc.session._send_queue.clear()
	mv._pending_move = Vector2i(999, 999)
	pc._held_moves = [{"code": 0, "key": "9", "mods": "none"}]
	pc._send_held_step()
	check(pc.session._send_queue.has("turn r"), "held 9 sends 'turn r'")
	check(mv._pending_move == Vector2i.ZERO, "held turn r records ZERO note")
	pc.session._send_queue.clear()
	mv._pending_move = Vector2i(999, 999)
	pc._held_moves = [{"code": 0, "key": "8", "mods": "none"}]
	pc._send_held_step()
	check(mv._pending_move == Vector2i(0, -1), "held go records north note")
	# --- PhiCharacter: マウス長押し移動も印を残す ---
	pc.session._send_queue.clear()
	mv._pending_move = Vector2i(999, 999)
	pc._mouse_hold_cursor = PhiMouse.CURSOR_UP
	pc._mouse_send_step()
	check(mv._pending_move == Vector2i(0, -1), "mouse hold move records north note")
	print("stage123: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)
