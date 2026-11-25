extends SceneTree
## 第135段: PHIDM NEO v2.0 のペット・職業表示 (クライアント側)。
##
## - #ex-pet / #ex-job フレームの解析 (実サーバのフレーム形式)
## - ログイン時の #ex-switch pet=1 / job=1 申告
## - ペットの追随経路 (1マス遅れ) と、自キャラのスクロール追随
## - ペットのホップ (セル移動に連動する上下揺れ) の形と開始条件
## - ホバーのヒントへのペット・職業の併記
## - ステータスパネルのペット行 (名前とプール) と高さ
## - ペットシート (Pets.bmp) の読み込みと、無い場合の null
##
## 使い方: godot --headless --path . -s tests/test_stage135.gd
## 終了コード 0 = 全一致、1 = 不一致あり。

var _checks := 0
var _failures := 0


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


func check_near(a: float, b: float, eps: float, label: String) -> void:
	_checks += 1
	if absf(a - b) > eps:
		_failures += 1
		printerr("FAIL: ", label, " (got ", a, ", want ", b, ")")


func _events(parser: PhiParser, line: String) -> Array:
	return parser.feed(Cp932.encode(line))


func _test_parser() -> void:
	var parser := PhiParser.new()
	# 自分のペット (最大値つき、v2.0 の形式)
	var evs := _events(parser, "#ex-pet self fairy ユイ 87 92 1 100 100")
	check_eq(evs.size(), 1, "pet self events")
	if evs.size() == 1:
		check_eq(evs[0].get("type"), "petSelf", "pet self type")
		var pet: Dictionary = evs[0].get("pet", {})
		check_eq(pet.get("type"), "fairy", "pet self pet type")
		check_eq(pet.get("name"), "ユイ", "pet self pet name")
		check_eq(pet.get("mp"), 87, "pet self mp")
		check_eq(pet.get("st"), 92, "pet self st")
		check_eq(pet.get("active"), 1, "pet self active")
		check_eq(pet.get("mpMax"), 100, "pet self mpMax")
		check_eq(pet.get("stMax"), 100, "pet self stMax")
	# ペット無し
	evs = _events(parser, "#ex-pet self none - 0 0 0 100 100")
	check_eq(evs.size(), 1, "pet none events")
	if evs.size() == 1:
		check_eq((evs[0].get("pet", {"x": 1}) as Dictionary).is_empty(), true, "pet none empty")
	# 最大値の無い短い形式でも読める
	evs = _events(parser, "#ex-pet self cat ねこ 100 100 0")
	check_eq(evs.size(), 1, "pet short events")
	if evs.size() == 1:
		var pet2: Dictionary = evs[0].get("pet", {})
		check_eq(pet2.get("type"), "cat", "pet short type")
		check_eq(pet2.get("active"), 0, "pet short active")
		check_eq(pet2.has("mpMax"), false, "pet short no max")
	# 他人のペット (名前は引用符つき)
	evs = _events(parser, "#ex-pet chr \"タロウ\" dog ジョン 1")
	check_eq(evs.size(), 1, "pet chr events")
	if evs.size() == 1:
		check_eq(evs[0].get("type"), "petChr", "pet chr type")
		check_eq(evs[0].get("chr"), "タロウ", "pet chr name")
		check_eq((evs[0].get("pet", {}) as Dictionary).get("type"), "dog", "pet chr pet type")
	# 他人のペット無し
	evs = _events(parser, "#ex-pet chr \"タロウ\" none - 0")
	check_eq(evs.size(), 1, "pet chr none events")
	if evs.size() == 1:
		check_eq((evs[0].get("pet", {"x": 1}) as Dictionary).is_empty(), true, "pet chr none empty")
	# 知らないタイプ・途中で切れた行は無視する
	check_eq(_events(parser, "#ex-pet self dragon x 1 1 1").size(), 0, "pet unknown type ignored")
	check_eq(_events(parser, "#ex-pet self fairy").size(), 0, "pet truncated ignored")
	check_eq(_events(parser, "#ex-pet self fairy ユイ x 92 1").size(), 0, "pet bad number ignored")
	# 職業・性別
	evs = _events(parser, "#ex-job self \"戦士\" \"男\"")
	check_eq(evs.size(), 1, "job self events")
	if evs.size() == 1:
		check_eq(evs[0].get("type"), "jobSelf", "job self type")
		check_eq(evs[0].get("job"), "戦士", "job self job")
		check_eq(evs[0].get("sex"), "男", "job self sex")
	evs = _events(parser, "#ex-job chr \"タロウ\" \"僧侶\" \"女\"")
	check_eq(evs.size(), 1, "job chr events")
	if evs.size() == 1:
		check_eq(evs[0].get("type"), "jobChr", "job chr type")
		check_eq(evs[0].get("chr"), "タロウ", "job chr name")
		check_eq(evs[0].get("job"), "僧侶", "job chr job")
	# phi.jb の無い世界では空名前
	evs = _events(parser, "#ex-job self \"\" \"\"")
	check_eq(evs.size(), 1, "job empty events")
	if evs.size() == 1:
		check_eq(evs[0].get("job"), "", "job empty job")
		check_eq(evs[0].get("sex"), "", "job empty sex")
	check_eq(_events(parser, "#ex-job self").size(), 0, "job truncated ignored")


func _test_session_lines() -> void:
	check(PhiSession.login_lines("testid").has("#ex-switch pet=1"), "login declares pet")
	check(PhiSession.login_lines("testid").has("#ex-switch job=1"), "login declares job")
	check(PhiSession.post_register_lines().has("#ex-switch pet=1"), "post-register declares pet")
	check(PhiSession.post_register_lines().has("#ex-switch job=1"), "post-register declares job")


func _cells(dim: int, shift_y: int = 0) -> Array:
	## スクロール検知に使える、位置ごとに違うチップの並び。
	## shift_y > 0 で中身が shift_y マス北へずれた盤面になる
	## (プレイヤーが南へ進んだ次のフレーム)。
	var cells: Array = []
	for y in dim:
		for x in dim:
			var sy := y + shift_y
			cells.append({"chip": (x + sy * dim) % 47 + 1, "surface": "", "under": ""})
	return cells


func _cells_alt(dim: int) -> Array:
	## 転送先のような、ずらし比較でも一致しない地形。
	var cells: Array = []
	for y in dim:
		for x in dim:
			cells.append({"chip": (x * 11 + y * 17) % 83 + 1, "surface": "", "under": ""})
	return cells


func _cells_flat(dim: int) -> Array:
	## 一面同じチップの地形 (地形比較では窓の移動が読めない)。
	var cells: Array = []
	for i in dim * dim:
		cells.append({"chip": 5, "surface": "", "under": ""})
	return cells


func _char(nm: String, x: int, y: int, dir: String = "F") -> Dictionary:
	return {"name": nm, "x": x, "y": y, "dir": dir, "gra": "",
		"default": 0, "gigant": "#", "layer": 0}


func _test_trails() -> void:
	# 静的な経路計算
	check_eq(MapView.pet_trail_step([], Vector2i(2, 2)), [Vector2i(2, 2)], "trail first")
	check_eq(MapView.pet_trail_step([Vector2i(2, 2)], Vector2i(2, 2)), [Vector2i(2, 2)], "trail stay")
	check_eq(MapView.pet_trail_step([Vector2i(2, 2)], Vector2i(2, 3)),
		[Vector2i(2, 2), Vector2i(2, 3)], "trail step")
	check_eq(MapView.pet_trail_step([Vector2i(2, 2), Vector2i(2, 3)], Vector2i(5, 5)),
		[Vector2i(5, 5)], "trail teleport resets")
	check_eq(MapView.pet_draw_cell([Vector2i(2, 2), Vector2i(2, 3)], Vector2i(2, 3)),
		Vector2i(2, 2), "draw cell one behind")
	check_eq(MapView.pet_draw_cell([Vector2i(2, 3)], Vector2i(2, 3)),
		Vector2i(2, 3), "draw cell at feet")
	check_eq(MapView.dir_between(Vector2i(1, 1), Vector2i(1, 0)), "B", "dir B")
	check_eq(MapView.dir_between(Vector2i(1, 1), Vector2i(2, 1)), "R", "dir R")
	check_eq(MapView.dir_between(Vector2i(1, 1), Vector2i(1, 2)), "F", "dir F")
	check_eq(MapView.dir_between(Vector2i(1, 1), Vector2i(0, 1)), "L", "dir L")
	# set_map 経由: 他キャラのペットが1マス遅れる
	var view := MapView.new()
	view.self_name = "自分"
	view.set_pets({"相手": {"type": "dog", "name": "ジョン", "active": 1},
		"自分": {"type": "cat", "name": "ねこ", "active": 1}})
	view.set_map({"size": 7, "cells": _cells(7), "chars": [
		_char("自分", 3, 3), _char("相手", 1, 1)]}, null, "")
	view.set_map({"size": 7, "cells": _cells(7), "chars": [
		_char("自分", 3, 3), _char("相手", 1, 2)]}, null, "")
	var state := view.debug_pet_state()
	check_eq(state.get("trails", {}).get("相手"), [Vector2i(1, 1), Vector2i(1, 2)], "trail via set_map")
	# 自キャラが南へ進むと、自分のペットは直前のマス (北) へ
	view.set_map({"size": 7, "cells": _cells(7, 1), "chars": [
		_char("自分", 3, 3), _char("相手", 1, 1)]}, null, "")
	state = view.debug_pet_state()
	check_eq(state.get("selfCell"), Vector2i(3, 2), "self pet behind after scroll")
	check_eq(state.get("selfDir"), "F", "self pet faces movement")
	view.free()


func _test_trails_world() -> void:
	# 絶対座標がある時は世界座標で経路を持つ。自分の移動で
	# 他人の経路が汚れず、自キャラのペットは前回の世界座標に残る。
	var view := MapView.new()
	view.self_name = "自分"
	view.set_pets({"相手": {"type": "dog", "name": "ジョン", "active": 1},
		"自分": {"type": "cat", "name": "ねこ", "active": 1}})
	# 自分は世界 (10,10)、相手は世界 (8,8) = 盤面 (1,1)
	view.set_map({"size": 7, "cells": _cells(7), "pos": {"x": 10, "y": 10}, "chars": [
		_char("自分", 3, 3), _char("相手", 1, 1)]}, null, "")
	# 自分だけ南へ: 相手の盤面は (1,0) にずれるが経路は不変
	view.set_map({"size": 7, "cells": _cells(7), "pos": {"x": 10, "y": 11}, "chars": [
		_char("自分", 3, 3), _char("相手", 1, 0)]}, null, "")
	var state := view.debug_pet_state()
	check_eq(state.get("originOk"), true, "world mode on")
	check_eq(state.get("trails", {}).get("相手"), [Vector2i(8, 8)], "world trail untouched by self move")
	check_eq(state.get("selfWorld"), Vector2i(10, 10), "self pet at previous world cell")
	# 相手が東へ1歩: 経路が伸び、描くマスは1つ遅れ (世界 (8,8))
	view.set_map({"size": 7, "cells": _cells(7), "pos": {"x": 10, "y": 11}, "chars": [
		_char("自分", 3, 3), _char("相手", 2, 0)]}, null, "")
	state = view.debug_pet_state()
	check_eq(state.get("trails", {}).get("相手"),
		[Vector2i(8, 8), Vector2i(9, 8)], "world trail follows owner")
	view.free()


func _test_trail_survives_observer() -> void:
	# 回帰: 飼い主が静止し、観察側 (自分) だけが歩くと、他キャラの
	# ペットが飼い主に重なったまま直らなくなる実機報告。
	# 観察側の移動で見える地形が変わっても経路は壊れず、ペットは
	# 飼い主の1マス後ろに留まり続けること。
	# --- 世界座標モード ---
	var view := MapView.new()
	view.self_name = "自分"
	view.set_pets({"相手": {"type": "dog", "name": "ジョン", "active": 1}})
	# 自分は世界 (10,10)、相手は世界 (8,8) = 盤面 (1,1)
	view.set_map({"size": 7, "cells": _cells(7), "pos": {"x": 10, "y": 10}, "chars": [
		_char("自分", 3, 3), _char("相手", 1, 1)]}, null, "")
	# 相手が南へ1歩 (世界 (8,9))。ペットは (8,8) に付く。
	view.set_map({"size": 7, "cells": _cells(7), "pos": {"x": 10, "y": 10}, "chars": [
		_char("自分", 3, 3), _char("相手", 1, 2)]}, null, "")
	var state := view.debug_pet_state()
	check_eq(state.get("trails", {}).get("相手"),
		[Vector2i(8, 8), Vector2i(8, 9)], "regression world: trail built")
	check_eq(state.get("drawnCells", {}).get("相手"), Vector2i(8, 8),
		"regression world: pet behind owner")
	# 自分だけが南へ2歩・東へ1歩 (窓の地形も一緒に変わる)。
	# 相手は世界 (8,9) で静止したまま。
	view.set_map({"size": 7, "cells": _cells(7, 1), "pos": {"x": 10, "y": 11}, "chars": [
		_char("自分", 3, 3), _char("相手", 1, 1)]}, null, "")
	view.set_map({"size": 7, "cells": _cells(7, 2), "pos": {"x": 10, "y": 12}, "chars": [
		_char("自分", 3, 3), _char("相手", 1, 0)]}, null, "")
	view.set_map({"size": 7, "cells": _cells(7, 3), "pos": {"x": 11, "y": 12}, "chars": [
		_char("自分", 3, 3), _char("相手", 0, 0)]}, null, "")
	state = view.debug_pet_state()
	check_eq(state.get("trails", {}).get("相手"),
		[Vector2i(8, 8), Vector2i(8, 9)], "regression world: trail survives observer walk")
	check_eq(state.get("drawnCells", {}).get("相手"), Vector2i(8, 8),
		"regression world: pet stays behind owner")
	# 自分が遠くへ転送されたら経路は作り直し、ペットは足元に落ちる。
	view.set_map({"size": 7, "cells": _cells_alt(7), "pos": {"x": 40, "y": 40}, "chars": [
		_char("自分", 3, 3), _char("相手", 2, 2)]}, null, "")
	state = view.debug_pet_state()
	check_eq(state.get("trails", {}).get("相手"), [Vector2i(39, 39)],
		"regression world: teleport rebuilds trail")
	check_eq(state.get("drawnCells", {}).get("相手"), Vector2i(39, 39),
		"regression world: feet fallback after teleport")
	view.free()
	# --- 盤面座標モード (スクロールあり) ---
	var view2 := MapView.new()
	view2.self_name = "自分"
	view2.set_pets({"相手": {"type": "dog", "name": "ジョン", "active": 1}})
	view2.set_map({"size": 7, "cells": _cells(7), "chars": [
		_char("自分", 3, 3), _char("相手", 1, 1)]}, null, "")
	view2.set_map({"size": 7, "cells": _cells(7), "chars": [
		_char("自分", 3, 3), _char("相手", 1, 2)]}, null, "")
	state = view2.debug_pet_state()
	check_eq(state.get("drawnCells", {}).get("相手"), Vector2i(1, 1),
		"regression board: pet behind owner")
	# 自分が南へスクロール。相手はその場にいるので盤面では
	# 北へ1マスずれて見える。経路は補正されて生き残る。
	view2.set_map({"size": 7, "cells": _cells(7, 1), "chars": [
		_char("自分", 3, 3), _char("相手", 1, 1)]}, null, "")
	state = view2.debug_pet_state()
	check_eq(state.get("trails", {}).get("相手"),
		[Vector2i(1, 0), Vector2i(1, 1)], "regression board: trail shifted with scroll")
	check_eq(state.get("drawnCells", {}).get("相手"), Vector2i(1, 0),
		"regression board: pet stays behind after scroll")
	view2.free()
	# --- 盤面座標モード (スクロール無効) ---
	# スクロール検知が働かなくても、地形のずらし比較で窓の
	# 移動と分かり、経路は生き残る。
	var view3 := MapView.new()
	view3.self_name = "自分"
	view3.smooth_scroll = false
	view3.set_pets({"相手": {"type": "dog", "name": "ジョン", "active": 1}})
	view3.set_map({"size": 7, "cells": _cells(7), "chars": [
		_char("自分", 3, 3), _char("相手", 1, 1)]}, null, "")
	view3.set_map({"size": 7, "cells": _cells(7), "chars": [
		_char("自分", 3, 3), _char("相手", 1, 2)]}, null, "")
	view3.set_map({"size": 7, "cells": _cells(7, 1), "chars": [
		_char("自分", 3, 3), _char("相手", 1, 1)]}, null, "")
	state = view3.debug_pet_state()
	check_eq(state.get("trails", {}).get("相手"),
		[Vector2i(1, 0), Vector2i(1, 1)], "regression board-noscroll: trail shifted")
	check_eq(state.get("drawnCells", {}).get("相手"), Vector2i(1, 0),
		"regression board-noscroll: pet stays behind")
	view3.free()
	# --- 盤面座標モード: 一部の地形変化では壊れない ---
	var view4 := MapView.new()
	view4.self_name = "自分"
	view4.set_pets({"相手": {"type": "dog", "name": "ジョン", "active": 1}})
	view4.set_map({"size": 7, "cells": _cells(7), "chars": [
		_char("自分", 3, 3), _char("相手", 1, 1)]}, null, "")
	view4.set_map({"size": 7, "cells": _cells(7), "chars": [
		_char("自分", 3, 3), _char("相手", 1, 2)]}, null, "")
	var cells4 := _cells(7)
	cells4[0] = {"chip": 999, "surface": "", "under": ""}
	cells4[10] = {"chip": 998, "surface": "", "under": ""}
	view4.set_map({"size": 7, "cells": cells4, "chars": [
		_char("自分", 3, 3), _char("相手", 1, 2)]}, null, "")
	state = view4.debug_pet_state()
	check_eq(state.get("trails", {}).get("相手"),
		[Vector2i(1, 1), Vector2i(1, 2)], "regression board: local change keeps trail")
	check_eq(state.get("drawnCells", {}).get("相手"), Vector2i(1, 1),
		"regression board: pet behind after local change")
	view4.free()
	# --- 盤面座標モード: 地形の入れ替わりでは作り直す ---
	var view5 := MapView.new()
	view5.self_name = "自分"
	view5.set_pets({"相手": {"type": "dog", "name": "ジョン", "active": 1}})
	view5.set_map({"size": 7, "cells": _cells(7), "chars": [
		_char("自分", 3, 3), _char("相手", 1, 1)]}, null, "")
	view5.set_map({"size": 7, "cells": _cells(7), "chars": [
		_char("自分", 3, 3), _char("相手", 1, 2)]}, null, "")
	view5.set_map({"size": 7, "cells": _cells_alt(7), "chars": [
		_char("自分", 3, 3), _char("相手", 4, 4)]}, null, "")
	state = view5.debug_pet_state()
	check_eq(state.get("trails", {}).get("相手"), [Vector2i(4, 4)],
		"regression board: terrain swap rebuilds trail")
	check_eq(state.get("drawnCells", {}).get("相手"), Vector2i(4, 4),
		"regression board: feet fallback after terrain swap")
	view5.free()
	# --- 盤面座標モード: 一面同じ地形 + スクロール無効 ---
	# 地形比較では窓の移動が読めないが、複数キャラの盤面位置が
	# 一斉にずれれば窓の移動と分かる。
	var view6 := MapView.new()
	view6.self_name = "自分"
	view6.smooth_scroll = false
	view6.set_pets({"相手": {"type": "dog", "name": "ジョン", "active": 1},
		"相手2": {"type": "cat", "name": "ミケ", "active": 1}})
	view6.set_map({"size": 7, "cells": _cells_flat(7), "chars": [
		_char("自分", 3, 3), _char("相手", 1, 1), _char("相手2", 5, 1)]}, null, "")
	view6.set_map({"size": 7, "cells": _cells_flat(7), "chars": [
		_char("自分", 3, 3), _char("相手", 1, 2), _char("相手2", 5, 1)]}, null, "")
	# 自分が南へ。静止している2人は盤面で北へ1マスずれる。
	view6.set_map({"size": 7, "cells": _cells_flat(7), "chars": [
		_char("自分", 3, 3), _char("相手", 1, 1), _char("相手2", 5, 0)]}, null, "")
	state = view6.debug_pet_state()
	check_eq(state.get("trails", {}).get("相手"),
		[Vector2i(1, 0), Vector2i(1, 1)], "regression board-flat: trail shifted by char delta")
	check_eq(state.get("drawnCells", {}).get("相手"), Vector2i(1, 0),
		"regression board-flat: pet stays behind")
	view6.free()


func _test_hop() -> void:
	# ホップの形: 開始時と終了時 (PET_HOP_DURATION 以降) は 0、
	# 中間で最大 (-PET_HOP_PX) の放物線。前半で上がりきり、
	# 後半で戻る (左右対称)。
	var dur := MapView.PET_HOP_DURATION
	check_eq(MapView.pet_hop_offset(-0.05), 0.0, "hop before start")
	check_eq(MapView.pet_hop_offset(0.0), 0.0, "hop at start")
	check_near(MapView.pet_hop_offset(dur * 0.5), -MapView.PET_HOP_PX, 0.001, "hop peak at middle")
	check_near(MapView.pet_hop_offset(dur * 0.25), -MapView.PET_HOP_PX * 0.75, 0.001, "hop quarter")
	check_near(MapView.pet_hop_offset(dur * 0.75), MapView.pet_hop_offset(dur * 0.25), 0.001, "hop symmetric")
	check(MapView.pet_hop_offset(dur * 0.25) > MapView.pet_hop_offset(dur * 0.5), "hop rises to peak")
	check(MapView.pet_hop_offset(dur * 0.1) <= 0.0 and MapView.pet_hop_offset(dur * 0.9) <= 0.0, "hop never below ground")
	check_eq(MapView.pet_hop_offset(dur), 0.0, "hop at end")
	check_eq(MapView.pet_hop_offset(dur + 0.1), 0.0, "hop settled after end")
	# 静止中の揺れは 1px の範囲内 (従来どおり)
	check_eq(MapView.pet_idle_bob(1, 1), -1.0, "idle bob up")
	check_eq(MapView.pet_idle_bob(1, 0), 0.0, "idle bob rest")
	check_eq(MapView.pet_idle_bob(0, 1), 0.0, "idle bob inactive")
	# set_map 経由 (盤面座標): 相手のペットは主人の1歩目では
	# まだ移らず (ホップなし)、2歩目で実際にマスを移って跳ねる
	var view := MapView.new()
	view.self_name = "自分"
	view.set_pets({"相手": {"type": "dog", "name": "ジョン", "active": 1}})
	view.set_map({"size": 7, "cells": _cells(7), "chars": [
		_char("自分", 3, 3), _char("相手", 1, 1)]}, null, "")
	view.set_map({"size": 7, "cells": _cells(7), "chars": [
		_char("自分", 3, 3), _char("相手", 1, 2)]}, null, "")
	var state := view.debug_pet_state()
	check_eq((state.get("hopAt", {}) as Dictionary).has("相手"), false, "no hop while pet stays")
	view.set_map({"size": 7, "cells": _cells(7), "chars": [
		_char("自分", 3, 3), _char("相手", 1, 3)]}, null, "")
	state = view.debug_pet_state()
	check_eq((state.get("hopAt", {}) as Dictionary).has("相手"), true, "hop starts when pet steps")
	check_eq((state.get("drawnCells", {}) as Dictionary).get("相手"), Vector2i(1, 2), "drawn cell after step")
	view.free()
	# set_map 経由 (世界座標): 自キャラのペットは主人の1歩目では
	# 前のマスに残るだけ (ホップなし)、2歩目で移って跳ねる
	var view2 := MapView.new()
	view2.self_name = "自分"
	view2.set_pets({"自分": {"type": "cat", "name": "ねこ", "active": 1}})
	view2.set_map({"size": 7, "cells": _cells(7), "pos": {"x": 10, "y": 10}, "chars": [
		_char("自分", 3, 3)]}, null, "")
	view2.set_map({"size": 7, "cells": _cells(7), "pos": {"x": 10, "y": 11}, "chars": [
		_char("自分", 3, 3)]}, null, "")
	state = view2.debug_pet_state()
	check_eq((state.get("hopAt", {}) as Dictionary).has("自分"), false, "self pet no hop on first step")
	view2.set_map({"size": 7, "cells": _cells(7), "pos": {"x": 10, "y": 12}, "chars": [
		_char("自分", 3, 3)]}, null, "")
	state = view2.debug_pet_state()
	check_eq((state.get("hopAt", {}) as Dictionary).has("自分"), true, "self pet hops on second step")
	view2.free()
	# 転送のような遠くへの跳びではホップは始まらない
	var view3 := MapView.new()
	view3.self_name = "自分"
	view3.set_pets({"相手": {"type": "dog", "name": "ジョン", "active": 1}})
	view3.set_map({"size": 7, "cells": _cells(7), "chars": [
		_char("自分", 3, 3), _char("相手", 1, 1)]}, null, "")
	view3.set_map({"size": 7, "cells": _cells(7), "chars": [
		_char("自分", 3, 3), _char("相手", 5, 5)]}, null, "")
	state = view3.debug_pet_state()
	check_eq((state.get("hopAt", {}) as Dictionary).has("相手"), false, "no hop on teleport")
	view3.free()


func _test_hover() -> void:
	var view := MapView.new()
	view.set_pets({"タロウ": {"type": "dog", "name": "ジョン", "active": 1}})
	view.set_job_info({"タロウ": {"job": "戦士", "sex": "男"},
		"ジロウ": {"job": "", "sex": ""}})
	check_eq(view.hover_text_for("タロウ"), "タロウ\nジョン (犬)\n戦士 男", "hover full")
	check_eq(view.hover_text_for("ジロウ"), "ジロウ", "hover empty job no line")
	check_eq(view.hover_text_for("サブロウ"), "サブロウ", "hover plain")
	view.free()


func _test_status_panel() -> void:
	var panel := StatusPanel.new()
	var base_h := panel.custom_minimum_size.y
	check_eq(panel.extra_row_visible(), false, "panel no extra at first")
	panel.set_pet({"type": "cat", "name": "ねこ", "mp": 80, "st": 45,
		"active": 1, "mpMax": 100, "stMax": 100})
	check_eq(panel.extra_row_visible(), true, "panel extra with pet")
	check(panel.custom_minimum_size.y > base_h, "panel grows with pet")
	check_eq(StatusPanel.pet_head_text_for({"type": "cat", "name": "ねこ", "active": 1}),
		"ねこ (猫)", "pet head")
	check_eq(StatusPanel.pet_head_text_for({"type": "dog", "name": "ジョン", "active": 0}),
		"ジョン (犬) 休止中", "pet head inactive")
	check_eq(StatusPanel.pet_head_text_for({}), "", "pet head empty")
	panel.set_pet({})
	check_eq(panel.extra_row_visible(), false, "panel extra cleared")
	check_eq(panel.custom_minimum_size.y, base_h, "panel height restored")
	panel.set_job("戦士", "男")
	check_eq(panel.extra_row_visible(), true, "panel extra with job")
	check_eq(StatusPanel.job_text_for("戦士", "男"), "戦士 男", "job text")
	check_eq(StatusPanel.job_text_for("", "女"), "女", "job text sex only")
	check_eq(StatusPanel.job_text_for("", ""), "", "job text empty")
	panel.free()


func _test_assets() -> void:
	var assets := GameAssets.new()
	check_eq(assets.pet_sheet(), null, "pet sheet absent is null")
	assets.chip_dirs = [ProjectSettings.globalize_path("res://assets")]
	var tex: Variant = assets.pet_sheet()
	check(tex != null, "pet sheet found in assets dir")
	if tex != null:
		check_eq((tex as Texture2D).get_width(), 128, "pet sheet width")
		check_eq((tex as Texture2D).get_height(), 128, "pet sheet height")


func _initialize() -> void:
	Cp932.ensure_loaded()
	_test_parser()
	_test_session_lines()
	_test_trails()
	_test_trails_world()
	_test_trail_survives_observer()
	_test_hop()
	_test_hover()
	_test_status_panel()
	_test_assets()
	print("stage135: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)
