extends SceneTree
## 第95段 (改) のテスト: 魔法の発動演出は、術師を中心に円状に
## 広がる波 (オーラ)。魔法弾は廃止せず、「魔法表示」が ON の
## 時だけ対象へ飛ぶ (MapView.magic_bolt、設定連動は第97段)。
## OFF では波だけが出て、弾も着弾も出ない。ON では波に加えて
## 弾が飛び、届くと着弾になる。
##
## 使い方: godot --headless --path . -s tests/test_stage95.gd
## 終了コード 0 = 全一致、1 = 不一致あり。

var _checks := 0
var _failures := 0


func check(cond: bool, label: String) -> void:
	_checks += 1
	if not cond:
		_failures += 1
		printerr("FAIL: ", label)


func _make_view() -> MapView:
	var mv := MapView.new()
	mv.player_name = "Alice"
	mv.set_map({"size": 7, "cells": [], "chars": [
		{"name": "Alice", "x": 3, "y": 3, "dir": "F", "gra": "", "status": 0, "gigant": "#", "default": 0, "layer": 0},
		{"name": "Bob", "x": 3, "y": 2, "dir": "F", "gra": "", "status": 0, "gigant": "#", "default": 0, "layer": 0},
	]}, null, "")
	return mv


const CAST_LINE := "DM > Alice は魔法を唱えている... \nDM > Alice は Bob を Harm で攻撃した. [10 hp]"


func _run() -> void:
	# 魔法表示 OFF (magic_bolt=false): 波だけ。弾も着弾も無い。
	var mv := _make_view()
	mv.spawn_combat_fx(CAST_LINE)
	check(mv.debug_cast_count() == 1, "s95 cast appears on magic attack")
	check(mv.debug_bolt_count() == 0, "s95 no bolt when magic display off")
	check(mv.debug_impact_count() == 0, "s95 no impact when magic display off")
	var casts: Array = mv.get("_casts")
	var center: Vector2 = casts[0]["center"]
	var alice_center: Vector2 = mv.call("_sprite_center", mv.call("_float_position", "Alice"))
	var bob_center: Vector2 = mv.call("_sprite_center", mv.call("_float_position", "Bob"))
	check(center == alice_center, "s95 cast centered on caster")
	check(center != bob_center, "s95 cast not on target")
	# 持続時間の途中では消えず、過ぎると消える。
	casts[0]["spawned"] = float(casts[0]["spawned"]) - MapView.CAST_DURATION * 0.5
	mv.call("_expire_effects")
	check(mv.debug_cast_count() == 1, "s95 cast alive mid duration")
	casts[0]["spawned"] = float(casts[0]["spawned"]) - MapView.CAST_DURATION
	mv.call("_expire_effects")
	check(mv.debug_cast_count() == 0, "s95 cast expires after duration")
	mv.queue_free()
	# 魔法表示 ON (magic_bolt=true): 波に加えて弾が飛び、
	# 飛び終わると着弾になる。
	var mv2 := _make_view()
	mv2.magic_bolt = true
	mv2.spawn_combat_fx(CAST_LINE)
	check(mv2.debug_cast_count() == 1, "s95 cast also appears when bolt on")
	check(mv2.debug_bolt_count() == 1, "s95 bolt flies when magic display on")
	var bolts: Array = mv2.get("_bolts")
	bolts[0]["spawned"] = float(bolts[0]["spawned"]) - MapView.BOLT_STEP * MapView.BOLT_STEPS - 0.01
	mv2.call("_expire_effects")
	check(mv2.debug_bolt_count() == 0, "s95 bolt lands")
	check(mv2.debug_impact_count() == 1, "s95 impact after bolt lands")
	mv2.queue_free()
	# 物理攻撃では波は出ない (従来どおり斬撃側)。
	var mv3 := _make_view()
	mv3.spawn_combat_fx("DM > Alice は Bob を攻撃した. [10 hp]")
	check(mv3.debug_cast_count() == 0, "s95 no cast on physical attack")
	mv3.queue_free()
	# リングの進みと半径: 後の輪ほど遅れ、半径は単調に広がる。
	check(MapView._cast_ring_progress(0.0, 0) > 0.0 or MapView._cast_ring_progress(0.01, 0) > 0.0, "s95 ring0 starts at once")
	check(MapView._cast_ring_progress(0.01, 2) == 0.0, "s95 ring2 delayed")
	check(MapView._cast_ring_progress(MapView.CAST_DURATION, 2) >= 1.0, "s95 ring2 completes")
	check(MapView._cast_ring_radius(0.0) < MapView._cast_ring_radius(0.5), "s95 radius grows 1")
	check(MapView._cast_ring_radius(0.5) < MapView._cast_ring_radius(1.0), "s95 radius grows 2")
	check(MapView.CAST_DURATION < 1.0, "s95 duration under a second")
	print("test_stage95: ", _checks, " checks, ", _failures, " failures")
	quit(1 if _failures > 0 else 0)


func _initialize() -> void:
	call_deferred("_run")
