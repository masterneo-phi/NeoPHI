extends SceneTree
## エフェクトの純粋ロジックのテスト。Python 版の test_float_text.py /
## test_bubbles.py / test_combat_fx.py に対応します。
##
## 使い方: godot --headless --path . -s tests/test_fx.gd
## 終了コード 0 = 全一致、1 = 不一致あり。

var _failures := 0
var _checks := 0


func _check(cond: bool, label: String) -> void:
	_checks += 1
	if not cond:
		_failures += 1
		printerr("FAIL: ", label)


func _check_eq(a: Variant, b: Variant, label: String) -> void:
	_checks += 1
	if a != b:
		_failures += 1
		printerr("FAIL: ", label, " (got ", a, ", want ", b, ")")


func _check_approx(a: float, b: float, label: String, eps: float = 0.001) -> void:
	_checks += 1
	if absf(a - b) > eps:
		_failures += 1
		printerr("FAIL: ", label, " (got ", a, ", want ", b, ")")


func _float_case(text: String, kind: String, target: Variant, amount: int) -> void:
	var got := PhiFloatText.parse_floats(text)
	_check_eq(got.size(), 1, "float count: " + text)
	if got.size() != 1:
		return
	_check_eq(got[0]["kind"], kind, "float kind: " + text)
	_check_eq(got[0]["target"], target, "float target: " + text)
	_check_eq(got[0]["amount"], amount, "float amount: " + text)


func _test_float_text() -> void:
	_float_case("DM > モック太郎 は モック花子 を ロングソード で攻撃した. [12 hp]", "dealt", "モック花子", 12)
	_float_case("DM > モック太郎 は モック花子 を ロングソード で攻撃した. [8 mp]", "mpdmg", "モック花子", 8)
	_float_case("DM > モック太郎 は ドラゴン を ファイアーボール で攻撃した. [30 hp]", "dealt", "ドラゴン", 30)
	_float_case("DM > ドラゴン は あなた を 牙 で攻撃した. [9 hp]", "dealt", "あなた", 9)
	_float_case("DM > モック花子 は モック太郎 の ロングソード による攻撃を吸収した. [5 hp]", "heal", "モック花子", 5)
	_float_case("DM > モック花子 は モック太郎 の ファイアーボール を吸収した. [7 mp]", "mp", "モック花子", 7)
	_float_case("DM > モック花子 は 落とし穴 を吸収した. [7 mp]", "mp", "モック花子", 7)
	_float_case("DM > モック太郎 は 落とし穴 からダメージを受けた. [10 hp]", "taken", "モック太郎", 10)
	_float_case("DM > モック太郎 は 毒の罠 からダメージを受けた. [10 mp]", "mpdmg", "モック太郎", 10)
	_float_case("DM > モック太郎 は 魔法の暴発でダメージを受けた. [15 hp]", "taken", "モック太郎", 15)
	_float_case("DM > 暴発! ダメージ 20 hp.", "taken", null, 20)
	_float_case("DM > モック花子 が キュアー によって回復した. [25 hp]", "heal", "モック花子", 25)
	_float_case("DM > モック太郎 は モック花子 を キュアー で回復した. [25 hp]", "heal", "モック花子", 25)
	_float_case("DM > モック太郎 は モック花子 を キュアー で回復した. [10 mp]", "mp", "モック花子", 10)
	_float_case("DM > モック太郎 は パン で回復した. [6 mp]", "mp", "モック太郎", 6)
	_float_case("DM > モック太郎 は 6 mp 回復した.", "mp", "モック太郎", 6)
	_float_case("DM > しかし モック太郎 は 6 mp 回復した.", "mp", "モック太郎", 6)
	_float_case("DM > モック太郎 は 毒キノコ でダメージを受けた. [4 mp]", "mpdmg", "モック太郎", 4)
	_float_case("DM > モック太郎 は食中毒でダメージを受けた. [4 mp]", "mpdmg", "モック太郎", 4)
	_float_case("DM > モック太郎 は ドラゴン を ロングソード で攻撃した. [1,200 hp]", "dealt", "ドラゴン", 1200)
	for text in [
		"DM > モック太郎 はミスした.",
		"DM > クリティカル!",
		"DM > 12/100 hp left.",
		"DM > モック太郎 は 3 lv の毒を受けた.",
		"DM > 攻撃力が 5 point 上がった.",
		"DM > 30 秒間 HPが回復します.",
		"DM > モック太郎 は モック花子 に殺された.",
		"DM > モック太郎 は ALL mp 回復した.",
		"こんにちは。",
		"",
	]:
		_check_eq(PhiFloatText.parse_floats(text), [], "float no match: " + text)


func _measure_10(text: String) -> float:
	return text.length() * 10.0


func _test_bubbles() -> void:
	_check_eq(PhiBubbles.bubble_body("案内人 > こんにちは"), "こんにちは", "bubble_body talk")
	_check_eq(PhiBubbles.bubble_body("[案内人] > こんにちは"), "こんにちは", "bubble_body priv")
	_check_eq(PhiBubbles.bubble_body("A > a > b"), "a > b", "bubble_body separator in body")
	_check_eq(PhiBubbles.bubble_body("ただのログ"), "", "bubble_body no separator")
	_check_eq(PhiBubbles.bubble_body("A >  こんにちは  "), "こんにちは", "bubble_body strips spaces")
	var m := Callable(self, "_measure_10")
	_check_eq(PhiBubbles.wrap_bubble_lines("こんにちは", m, 100), ["こんにちは"], "wrap short")
	_check_eq(PhiBubbles.wrap_bubble_lines("", m, 100), [], "wrap empty")
	_check_eq(PhiBubbles.wrap_bubble_lines("   ", m, 100), [], "wrap spaces")
	_check_eq(PhiBubbles.wrap_bubble_lines("あいうえおかき", m, 30), ["あいう", "えおか", "き"], "wrap at width")
	_check_eq(PhiBubbles.wrap_bubble_lines("あいう", m, 30), ["あいう"], "wrap exact fit")
	var truncated := PhiBubbles.wrap_bubble_lines("あいうえおかきくけこ", m, 30, 2)
	_check_eq(truncated.size(), 2, "wrap truncate count")
	_check(truncated[1].ends_with("…"), "wrap truncate ellipsis")
	for line in truncated:
		_check(_measure_10(line) <= 30.0, "wrap truncate width")
	_check_eq(PhiBubbles.wrap_bubble_lines("あ", m, 5), ["あ"], "wrap single wide char")
	_check_eq(PhiBubbles.wrap_bubble_lines("あい\nうえ", m, 100), ["あい", "うえ"], "wrap newlines")
	_check_eq(PhiBubbles.wrap_bubble_lines("あいう", m, 30, 0), [], "wrap max_lines zero")
	# 配置
	_check_eq(PhiBubbles.place_bubble_rect(100, 200, 60, 40, 400, 10, []), [70.0, 150.0, false], "place centered")
	_check_eq(PhiBubbles.place_bubble_rect(10, 200, 60, 40, 400, 10, [])[0], 0.0, "place left edge")
	_check_eq(PhiBubbles.place_bubble_rect(390, 200, 60, 40, 400, 10, [])[0], 340.0, "place right edge")
	_check_eq(PhiBubbles.place_bubble_rect(100, 30, 60, 40, 400, 10, [])[1], 0.0, "place top edge")
	var placed := PhiBubbles.place_bubble_rect(100, 200, 60, 40, 400, 10, [[70, 150, 60, 40]])
	_check_eq(placed, [70.0, 100.0, true], "place stacked")
	_check_eq(PhiBubbles.place_bubble_rect(100, 200, 60, 40, 400, 10, [[200, 150, 60, 40]])[2], false, "place no stack")
	_check_eq(PhiBubbles.place_bubble_rect(100, 200, 60, 40, 400, 10, [[70, 150, 60, 40], [70, 100, 60, 40]])[1], 50.0, "place stacked twice")
	# 輪郭
	var outline := PhiBubbles.bubble_outline(10, 20, 110, 60, 8, 60, 6, 60, 72)
	for p in outline:
		_check(p.x >= 10.0 and p.x <= 110.0 and p.y >= 20.0 and p.y <= 72.0, "outline in bounds")
	for corner in [Vector2(10, 20), Vector2(110, 20), Vector2(10, 60), Vector2(110, 60)]:
		var nearest := 1e9
		for p in outline:
			nearest = minf(nearest, p.distance_to(corner))
		_check(nearest > 2.0, "outline rounded corner")
	var has_top := false
	var has_left := false
	for p in outline:
		if absf(p.y - 20.0) < 0.000001 and p.x > 10.0 and p.x < 110.0:
			has_top = true
		if absf(p.x - 10.0) < 0.000001 and p.y > 20.0 and p.y < 60.0:
			has_left = true
	_check(has_top, "outline top edge point")
	_check(has_left, "outline left edge point")
	var outline2 := PhiBubbles.bubble_outline(10, 20, 110, 60, 8, 60, 6, 55, 72)
	_check(Vector2(55, 72) in outline2, "outline tail tip")
	var narrow := PhiBubbles.bubble_outline(10, 20, 30, 60, 8, 20, 6, 20, 72)
	_check(not narrow.is_empty(), "outline narrow box")
	for p in narrow:
		_check(p.x >= 10.0 and p.x <= 30.0, "outline narrow in bounds")
	# log行からの発言
	var names := ["案内人", "Human", "Guest"]
	_check_eq(PhiBubbles.bubble_from_log_line("案内人 > いらっしゃい", names), ["案内人", "いらっしゃい"], "log npc talk")
	_check_eq(PhiBubbles.bubble_from_log_line("(Human) > こんにちは", names), ["Human", "こんにちは"], "log shout")
	_check_eq(PhiBubbles.bubble_from_log_line("{Human} > こんにちは", names), ["Human", "こんにちは"], "log area")
	_check_eq(PhiBubbles.bubble_from_log_line('"Human" > こんにちは', names), ["Human", "こんにちは"], "log party")
	_check_eq(PhiBubbles.bubble_from_log_line("DM > Human は死んだ.", names), null, "log dm line not speech")
	_check_eq(PhiBubbles.bubble_from_log_line("Unknown > こんにちは", names), null, "log unknown name")
	_check_eq(PhiBubbles.bubble_from_log_line("案内人 >   ", names), null, "log empty body")
	_check_eq(PhiBubbles.bubble_from_log_line("案内人 > a > b", names), ["案内人", "a > b"], "log body with separator")
	# action行
	_check_eq(PhiBubbles.bubble_from_action_line("DM > Guest 手を振った", names), ["Guest", "手を振った"], "action line")
	_check_eq(PhiBubbles.bubble_from_action_line("DM > 案内人 いらっしゃい", ["案内", "案内人", "Guest"]), ["案内人", "いらっしゃい"], "action longest name first")
	_check_eq(PhiBubbles.bubble_from_action_line("Guest 手を振った", names), null, "action no dm prefix")
	_check_eq(PhiBubbles.bubble_from_action_line("DM > Unknown 手を振った", names), null, "action unknown name")
	_check_eq(PhiBubbles.bubble_from_action_line("DM > Guest  ", names), null, "action empty body")


func _test_combat_fx() -> void:
	var ev: Variant = PhiCombatFx.parse_attack("DM > Guest は Human を 拳 で攻撃した. [6 hp]")
	_check(ev != null, "attack physical")
	if ev != null:
		_check_eq(ev["attacker"], "Guest", "attack attacker")
		_check_eq(ev["target"], "Human", "attack target")
		_check_eq(ev["weapon"], "拳", "attack weapon")
	ev = PhiCombatFx.parse_attack("DM > Human は Dog を Insane で攻撃した. [127 mp]")
	_check(ev != null and ev["weapon"] == "Insane", "attack mp damage")
	ev = PhiCombatFx.parse_attack("DM > Guest は Human を ロングソード で攻撃した. [43 hp]")
	_check(ev != null and ev["weapon"] == "ロングソード", "attack weapon with spaces")
	_check_eq(PhiCombatFx.parse_attack("DM > Guest が Cure によって回復した. [40 hp]"), null, "attack no match cure")
	_check_eq(PhiCombatFx.parse_attack("DM > Guest は罠からダメージを受けた. [10 hp]"), null, "attack no match trap")
	_check_eq(PhiCombatFx.parse_attack("ただのログ"), null, "attack no match plain")
	_check_eq(PhiCombatFx.parse_chant("DM > Human は魔法を唱えている... "), "Human", "chant cast")
	_check_eq(PhiCombatFx.parse_chant("DM > Human は力を集中している... "), "Human", "chant special")
	_check_eq(PhiCombatFx.parse_chant("DM > Guest は Human を攻撃した."), null, "chant no match")
	_check_eq(PhiCombatFx.parse_chant("DM > 詠唱を止めました. "), null, "chant no match stop")
	_check(PhiCombatFx.parse_chant_stop("DM > 詠唱を止めました. "), "chant stop")
	_check(PhiCombatFx.parse_chant_stop("DM > 詠唱は完了しなかった. "), "chant incomplete")
	_check(not PhiCombatFx.parse_chant_stop("DM > Human は魔法を唱えている... "), "chant stop no match")
	# CasterTracker
	var tracker := PhiCombatFx.CasterTracker.new(5.0)
	tracker.note("Human", 100.0)
	_check(tracker.consume("Human", 102.0), "tracker consume once")
	_check(not tracker.consume("Human", 103.0), "tracker consumed")
	tracker.note("Human", 100.0)
	_check(not tracker.consume("Human", 106.0), "tracker expired")
	tracker.note("Guest", 100.0)
	tracker.clear("Guest")
	_check(not tracker.consume("Guest", 101.0), "tracker clear")
	tracker.note("Human", 100.0)
	_check(not tracker.consume("Guest", 101.0), "tracker other names")
	_check(tracker.consume("Human", 101.0), "tracker right name")
	# 幾何
	var slash := PhiCombatFx.slash_points(100.0, 100.0, 2.0)
	_check_eq(slash.size(), 14, "slash point count")
	var min_x := 1e9
	var max_x := -1e9
	var min_y := 1e9
	var max_y := -1e9
	for p in slash:
		min_x = minf(min_x, p.x)
		max_x = maxf(max_x, p.x)
		min_y = minf(min_y, p.y)
		max_y = maxf(max_y, p.y)
	_check(min_x < 100.0 and max_x > 100.0 and min_y < 100.0 and max_y > 100.0, "slash bounds")
	var slash1 := PhiCombatFx.slash_points(100.0, 100.0, 1.0)
	_check(slash1[0].x > 100.0 and slash1[0].y < 100.0, "slash starts top right")
	var streak := PhiCombatFx.streak_points(100.0, 100.0, 2.0, 20.0, -1.0, 1.0, 3.0)
	_check(streak.size() >= 6, "streak point count")
	for p in streak:
		var dist := p.distance_to(Vector2(100, 100))
		_check(dist <= 43.0 + 0.001 and dist >= 37.0 - 0.001, "streak near radius")
	var streak2 := PhiCombatFx.streak_points(100.0, 100.0, 1.0, 20.0, -1.0, 1.0, 4.0)
	var half := streak2.size() / 2
	_check_approx(streak2[0].x, streak2[streak2.size() - 1].x, "streak pointed start x")
	_check_approx(streak2[0].y, streak2[streak2.size() - 1].y, "streak pointed start y")
	_check_approx(streak2[half - 1].x, streak2[half].x, "streak pointed end x")
	_check_approx(streak2[half - 1].y, streak2[half].y, "streak pointed end y")
	var mid := half / 2
	var gap := streak2[mid].distance_to(streak2[streak2.size() - 1 - mid])
	_check_approx(gap, 4.0, "streak thick middle", 0.1)
	var tail := PhiCombatFx.comet_tail_points(100.0, 100.0, 60.0, 100.0, 2.0, 7.0)
	_check_eq(tail.size(), 3, "comet point count")
	_check_approx(tail[0].distance_to(tail[2]), 14.0, "comet head width")
	_check_eq(tail[1], Vector2(60, 100), "comet tail tip")
	_check_eq(PhiCombatFx.comet_tail_points(100.0, 100.0, 100.0, 100.0, 1.0, 7.0), PackedVector2Array([Vector2(100, 100), Vector2(100, 100), Vector2(100, 100)]), "comet degenerate")
	var spark := PhiCombatFx.radial_spark_points(100.0, 100.0, 1.0, 0.0, 20.0, 2.0)
	_check_eq(spark.size(), 4, "spark point count")
	_check_approx(spark[2].x, 120.0, "spark tip x")
	_check_approx(spark[2].y, 100.0, "spark tip y")
	_check_approx(spark[1].distance_to(spark[3]), 4.0, "spark width")
	# 死亡
	_check_eq(PhiCombatFx.parse_kill("DM > Dog は Human に殺された. "), "Dog", "kill by other")
	_check_eq(PhiCombatFx.parse_kill("DM > Guest は Human に殺された. "), "Guest", "kill by pk")
	_check_eq(PhiCombatFx.parse_kill("DM > Guest は 毒で死んだ. "), "Guest", "kill self")
	_check_eq(PhiCombatFx.parse_kill("DM > あなたは死にました... "), "あなた", "kill dead self")
	_check_eq(PhiCombatFx.parse_kill("DM > Human は Cat を Knife で攻撃した. [43 hp]"), null, "kill no match attack")
	_check_eq(PhiCombatFx.parse_kill("DM > 死んだ時のメッセージを入力して下さい. "), null, "kill no match prompt")
	_check_eq(PhiCombatFx.parse_kill("DM > Guest が Cure によって回復した. [40 hp]"), null, "kill no match cure")


func _test_anchors() -> void:
	var view := MapView.new()
	view.set_map({"size": 7, "cells": [], "chars": [
		{"name": "自分", "x": 3, "y": 3, "dir": "F", "gra": "", "default": 0, "gigant": "#", "layer": 0},
		{"name": "モック太郎", "x": 0, "y": 0, "dir": "F", "gra": "", "default": 0, "gigant": "#", "layer": 0},
		{"name": "モック花子", "x": 6, "y": 6, "dir": "F", "gra": "", "default": 0, "gigant": "#", "layer": 0},
	]}, null, "")
	var anchors := view.debug_anchors()
	_check_eq(anchors.size(), 3, "anchors count")
	_check_eq(anchors.get("自分"), Vector2(3 * 32 + 16, 3 * 32 + 5), "anchors center")
	_check_eq(view.debug_center_anchor(), Vector2(3 * 32 + 16, 3 * 32 + 5), "anchors center anchor")
	view.set_map({"size": 7, "cells": [], "chars": [
		{"name": "  ", "x": 0, "y": 0, "dir": "F", "gra": "", "default": 0, "gigant": "#", "layer": 0},
		{"name": "モック太郎", "x": 9, "y": 9, "dir": "F", "gra": "", "default": 0, "gigant": "#", "layer": 0},
	]}, null, "")
	_check_eq(view.debug_anchors(), {}, "anchors skip empty and out of bounds")
	view.free()


func _initialize() -> void:
	_test_float_text()
	_test_bubbles()
	_test_combat_fx()
	_test_anchors()
	print("test_fx: ", _checks, " checks, ", _failures, " failures")
	quit(1 if _failures > 0 else 0)
