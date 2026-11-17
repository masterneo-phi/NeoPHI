extends SceneTree
## 第63段: (1) 切断中はマップの歩行アニメーションが止まる
##     (接続状態で MapView のアニメーションが開閉すること)。
## (2) ログのスクロール追随: 行を追加したら次のフレームで
##     最下部へ合う。上へスクロールしている時は引っ張らない。
##     スクロール停止が on の時は追随しない。

var _checks := 0
var _failures := 0


func check(cond: bool, label: String) -> void:
	_checks += 1
	if not cond:
		_failures += 1
		print("FAIL: ", label)


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var ps := load("res://main.tscn") as PackedScene
	var main: Node = ps.instantiate()
	root.add_child(main)
	await create_timer(0.6).timeout
	var tab: Variant = main.call("_active_tab")
	check(tab != null, "tab exists")
	# ---- (1) アニメーションの開閉 ----
	var mv: Variant = tab.get("map_view")
	check(mv != null, "map view exists")
	check(mv.get("_session_live") == false, "unconnected tab starts with animation stopped")
	mv.set("_event", {"size": 7, "cells": [], "chars": []})
	var f0: int = mv.get("_anim_frame")
	await create_timer(1.3).timeout
	check(mv.get("_anim_frame") == f0, "anim frame frozen while disconnected")
	mv.set_session_live(true)
	check(mv.get("_session_live") == true, "set_session_live(true) opens the gate")
	var flipped := false
	for i in range(15):
		await create_timer(0.1).timeout
		if mv.get("_anim_frame") != f0:
			flipped = true
			break
	check(flipped, "anim frame advances while connected")
	mv.set_session_live(false)
	var f1: int = mv.get("_anim_frame")
	await create_timer(1.3).timeout
	check(mv.get("_anim_frame") == f1, "anim frame freezes again on disconnect")
	# ---- (2) ログの追随 ----
	# 共有 HOME の設定に ScrollStop=true が残っていることがある
	# ので、このテストでは明示的に off にしてから始める。
	var cfg0: Variant = tab.get("_config")
	if cfg0 != null:
		cfg0.set("scroll_stop", false)
	for i in range(60):
		tab.log_message("log", "追随確認の行 %d" % i)
	check(tab.get("_pin_bottom_pending") == true, "append at bottom reserves a pin")
	await process_frame
	await process_frame
	await process_frame
	var lv: Variant = tab.get("log_view")
	var bar: VScrollBar = lv.get_v_scroll_bar()
	check(bar != null and bar.max_value > 0.0, "scroll bar has range")
	check(bar.value >= bar.max_value - bar.page - 1.0, "view settles at the very bottom")
	# 上へスクロールしている時は引っ張らない。
	bar.value = 0.0
	await process_frame
	tab.log_message("log", "上にいる時の行")
	check(tab.get("_pin_bottom_pending") == false, "no pin reserved while scrolled up")
	await process_frame
	await process_frame
	check(bar.value < bar.max_value - bar.page - 100.0, "view is not yanked down")
	# 最下部へ戻せば追随が復活する。
	bar.value = bar.max_value
	await process_frame
	await process_frame
	tab.log_message("log", "戻ってからの行")
	check(tab.get("_pin_bottom_pending") == true, "follow resumes at the bottom")
	await process_frame
	await process_frame
	await process_frame
	check(bar.value >= bar.max_value - bar.page - 1.0, "bottom again after resume")
	# スクロール停止が on なら追随しない。
	var cfg: Variant = cfg0
	if cfg != null:
		cfg.set("scroll_stop", true)
		tab.log_message("log", "停止中の行")
		check(tab.get("_pin_bottom_pending") == false, "no pin while scroll-stop is on")
		cfg.set("scroll_stop", false)
	print("stage63: ", _checks, " checks, ", _failures, " failures")
	quit(1 if _failures > 0 else 0)
