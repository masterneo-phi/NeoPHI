extends SceneTree
## 第64段 (試作): 滑らかスクロール。新しい地図が前の地図から
## 1マス分だけずれている時だけスクロールが始まり、向きが
## プレイヤーの移動方向と一致すること。関係ない地図や同じ
## 地図では始まらないこと。食い違いが 2 マスまでなら許し、
## 5 マスでは始めないこと。

var _checks := 0
var _failures := 0


func check(cond: bool, label: String) -> void:
	_checks += 1
	if not cond:
		_failures += 1
		print("FAIL: ", label)


func grid(base: int) -> Array:
	var cells: Array = []
	for y in range(7):
		for x in range(7):
			cells.append({"chip": base + x + y * 16, "attr": 0})
	return cells


func shifted(cells: Array, s: Vector2i, fresh: int) -> Array:
	## new(x,y) = old(x + s.x, y + s.y) のずらし (入り側は新しい行・列)。
	var out: Array = []
	for y in range(7):
		for x in range(7):
			var ox := x + s.x
			var oy := y + s.y
			if ox < 0 or oy < 0 or ox >= 7 or oy >= 7:
				out.append({"chip": fresh + x + y, "attr": 0})
			else:
				out.append(cells[oy * 7 + ox])
	return out


func ev(cells: Array) -> Dictionary:
	return {"size": 7, "cells": cells, "chars": []}


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var ps := load("res://main.tscn") as PackedScene
	var main: Node = ps.instantiate()
	root.add_child(main)
	await create_timer(0.6).timeout
	var tab: Variant = main.call("_active_tab")
	var mv: Variant = tab.get("map_view")
	check(mv != null, "map view exists")
	var a := grid(10)
	mv.set_map(ev(a), null, "mapset")
	check(mv.get("_scroll_t") == 1.0, "first map does not scroll")
	# 北へ移動: B(x,y) = A(x, y-1)
	var b := shifted(a, Vector2i(0, -1), 230)
	mv.set_map(ev(b), null, "mapset")
	check(mv.get("_scroll_from") == Vector2(0, -1), "north shift detected")
	check(mv.get("_scroll_t") < 1.0, "scroll started")
	check((mv.get("_prev_cells") as Array).size() == 49, "previous cells kept")
	await create_timer(0.4).timeout
	check(mv.get("_scroll_t") == 1.0, "scroll completes")
	# 東へ移動: C(x,y) = B(x-1, y)
	var c := shifted(b, Vector2i(1, 0), 240)
	mv.set_map(ev(c), null, "mapset")
	check(mv.get("_scroll_from") == Vector2(1, 0), "east shift detected")
	await create_timer(0.4).timeout
	# 関係ない地図ではスクロールしない
	var d := grid(60)
	mv.set_map(ev(d), null, "mapset")
	check(mv.get("_scroll_t") == 1.0, "unrelated map does not scroll")
	check((mv.get("_prev_cells") as Array).is_empty(), "no previous cells for unrelated map")
	# 同じ地図の再送でもスクロールしない
	mv.set_map(ev(d), null, "mapset")
	check(mv.get("_scroll_t") == 1.0, "identical map does not scroll")
	# 南へ移動 + 2マスの食い違いは許す
	var e := shifted(d, Vector2i(0, 1), 250)
	e[2 * 7 + 2] = {"chip": 901, "attr": 0}
	e[3 * 7 + 4] = {"chip": 902, "attr": 0}
	mv.set_map(ev(e), null, "mapset")
	check(mv.get("_scroll_from") == Vector2(0, 1), "south shift with 2 diffs detected")
	check(mv.get("_scroll_t") < 1.0, "scroll started with 2 diffs")
	await create_timer(0.4).timeout
	# 西へ移動 + 5マスの食い違いはスクロールしない
	var f := shifted(e, Vector2i(-1, 0), 260)
	for i in range(5):
		f[i * 7 + 3] = {"chip": 950 + i, "attr": 0}
	mv.set_map(ev(f), null, "mapset")
	check(mv.get("_scroll_t") == 1.0, "5 diffs do not scroll")
	print("stage64: ", _checks, " checks, ", _failures, " failures")
	quit(1 if _failures > 0 else 0)
