extends SceneTree
## 第26段 (小物まとめ後半): 同時押し斜め移動の合成・セルの
## 当たり判定と名前ヒント・看板エディタ窓の信号を確認する。

var _checks := 0
var _failures := 0


func check(cond: bool, label: String) -> void:
	_checks += 1
	if not cond:
		_failures += 1
		print("FAIL: ", label)


func held(pairs: Array) -> Array:
	var out: Array = []
	for p in pairs:
		out.append({"key": p[0], "mods": p[1]})
	return out


func keys_of(steps: Array) -> Array:
	var out: Array = []
	for s in steps:
		out.append(str(s[0]))
	return out


func _initialize() -> void:
	# -- 同時押しの合成 (PhiKeys.compose_held) --
	check(keys_of(PhiKeys.compose_held(held([["up", "none"]]))) == ["up"], "単独はそのまま")
	check(keys_of(PhiKeys.compose_held(held([["up", "none"], ["right", "none"]]))) == ["up", "right"], "↑+→ は斜め (縦→横)")
	check(keys_of(PhiKeys.compose_held(held([["right", "none"], ["up", "none"]]))) == ["up", "right"], "→+↑ も斜め (縦→横)")
	check(keys_of(PhiKeys.compose_held(held([["up", "none"], ["down", "none"]]))) == ["down"], "相反は新しい方だけ")
	check(keys_of(PhiKeys.compose_held(held([["8", "none"], ["up", "none"]]))) == ["up"], "同一方向は新しい方だけ")
	check(keys_of(PhiKeys.compose_held(held([["up", "none"], ["7", "none"]]))) == ["7"], "回転系が優先")
	check(keys_of(PhiKeys.compose_held(held([["7", "none"], ["9", "none"]]))) == ["9"], "回転系は最後のもの")
	check(keys_of(PhiKeys.compose_held(held([["left", "none"], ["down", "none"]]))) == ["down", "left"], "↓+← は斜め (縦→横)")
	check(PhiKeys.compose_held([]).is_empty(), "空は空")
	# -- 地図のセル判定と名前 --
	var view := MapView.new()
	view.zoom = 1
	root.add_child(view)
	view.size = Vector2(7 * 32, 7 * 32 + 16)
	var cells: Array = []
	for i in 49:
		cells.append({"chip": 0x2E, "attr": 0})
	var ev := {"type": "map", "size": 7, "cells": cells, "chars": [
		{"name": "自分", "gra": "", "x": 3, "y": 3, "dir": 0, "default": 0x40},
		{"name": "案内人", "gra": "", "x": 1, "y": 2, "dir": 0, "default": 0},
	]}
	view.set_map(ev, null, "", {})
	check(view.player_cell() == Vector2i(3, 3), "自セルは中心")
	check(view.cell_at_local(Vector2(3 * 32 + 16, 16 + 3 * 32 + 16)) == Vector2i(3, 3), "中心のセル判定")
	check(view.cell_at_local(Vector2(1 * 32 + 16, 16 + 2 * 32 + 16)) == Vector2i(1, 2), "案内人のセル判定")
	check(view.cell_at_local(Vector2(-5, -5)) == Vector2i(-1, -1), "盤外は (-1,-1)")
	check(view.chara_name_at(Vector2(1 * 32 + 16, 16 + 2 * 32 + 16)) == "案内人", "名前ヒントの対象")
	check(view.chara_name_at(Vector2(0 * 32 + 16, 16 + 0 * 32 + 16)) == "", "誰もいないマスは空")
	view.set_guide_cell(Vector2i(0, 0))
	check(view.guide_cell == Vector2i(0, 0), "ガイド線のセル")
	view.queue_free()
	# -- 看板エディタ窓 --
	var win := PhiMEditWindow.new()
	root.add_child(win)
	var sent: Array = []
	var cancels := [0]
	win.send_requested.connect(func(lines: Array) -> void: sent.append(lines))
	win.cancel_requested.connect(func() -> void: cancels[0] += 1)
	win.show_editor("テスト")
	win.get("_edit").text = "一行目\n二行目"
	win.call("_on_send_pressed")
	check(sent.size() == 1 and sent[0] == ["一行目", "二行目"], "送信で本文の行が渡る: %s" % str(sent))
	win.call("_on_cancel_pressed")
	check(cancels[0] == 0, "送信後のキャンセルでは送らない")
	win.show_editor("テスト")
	win.call("_on_cancel_pressed")
	check(cancels[0] == 1, "編集中のキャンセルで知らせる")
	win.show_editor("テスト")
	win.close_silent()
	win.call("_on_cancel_pressed")
	check(cancels[0] == 1, "サーバ終了後の閉じる操作では送らない")
	win.queue_free()
	print("test_stage26: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)
