extends SceneTree
## 第96段のテスト: 2x2 の大きな敵 (サーバの大きさ印 'B') の描画。
## is_big の判定、大きな絵のソース矩形、足元に合わせた描画行、
## set_map での受け入れを確認する。
##
## 使い方: godot --headless --path . -s tests/test_stage96.gd
## 終了コード 0 = 全一致、1 = 不一致あり。

const MapView := preload("res://scripts/map_view.gd")

var _checks := 0
var _failures := 0


func check(cond: bool, label: String) -> void:
	_checks += 1
	if not cond:
		_failures += 1
		printerr("FAIL: ", label)


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	# 印の判定: 'B' だけが 2x2。gigant '*' とは区別する。
	check(MapView.is_big("B"), "s96 B is big")
	check(not MapView.is_big("*"), "s96 * is not big")
	check(not MapView.is_big("#"), "s96 # is not big")
	check(not MapView.is_giant("B"), "s96 B is not gigant")
	check(MapView.is_giant("*"), "s96 * is gigant")

	# ソース矩形: 'B' は gigant と同じ大きな絵 (32px 枠) を使う。
	var rb := MapView.chara_src_rect("F", "B", 0)
	var rs := MapView.chara_src_rect("F", "*", 0)
	check(rb == rs, "s96 B src rect equals gigant")
	check(rb.size == Vector2(32, 32), "s96 B src is large frame")
	var rn := MapView.chara_src_rect("F", "#", 0)
	check(rn.size == Vector2(16, 32), "s96 normal src is small frame")

	# 描画行: 通常キャラは自分の行、2x2 は足元 (南の行) で描く。
	var normal := {"x": 3, "y": 3, "gigant": "#"}
	var big := {"x": 3, "y": 3, "gigant": "B"}
	check(MapView.char_draw_row(normal, 7) == 3, "s96 normal row")
	check(MapView.char_draw_row(big, 7) == 4, "s96 big row is feet row")
	var big_edge := {"x": 3, "y": 6, "gigant": "B"}
	check(MapView.char_draw_row(big_edge, 7) == 6, "s96 big row clamped at edge")

	# set_map で 'B' のキャラを受け入れ、保持すること。
	var mv: Control = MapView.new()
	root.add_child(mv)
	var cells: Array = []
	for i in range(49):
		cells.append({"chip": 0, "attr": 0})
	var ev := {
		"size": 7, "style": "solid", "dir": 0,
		"cells": cells,
		"chars": [
			{"name": "BigTest", "gra": "elb_cat", "x": 4, "y": 2,
				"dir": "F", "gigant": "B", "status": 0, "layer": 0,
				"default": 0, "id": 5},
			{"name": "Guest", "gra": "elb_cat", "x": 3, "y": 3,
				"dir": "F", "gigant": "#", "status": 0, "layer": 0,
				"default": 0, "id": 1},
		],
	}
	mv.set_map(ev, null, "", {})
	var stored: Array = mv.get("_event").get("chars", [])
	check(stored.size() == 2, "s96 event stored")
	var found := false
	for ch in stored:
		if str(ch.get("gigant")) == "B":
			found = true
	check(found, "s96 big char kept in event")
	mv.queue_redraw()
	await process_frame
	await process_frame
	check(true, "s96 draw survived")
	print("test_stage96: ", _checks, " checks, ", _failures, " failures")
	quit(1 if _failures > 0 else 0)
