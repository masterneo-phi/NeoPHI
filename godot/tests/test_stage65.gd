extends SceneTree
## 第65段: (1) スムーズマップスクロールの表示オプション
## (既定 on、表示メニューのログスクロール停止と魔法表示の間、
## 北固定の時だけ有効、外すと従来動作)。(2) 切断でアニメーション
## が止まらない不具合 (session_closed が先に _was_open を戻すと
## 変化検出が行き違える) の修正。(3) スクロール時のはみ出しを
## 壁紙でマスクする帯の幾何。(4) 大量行対策: 溜めた行の下準備を
## 表示時へ遅らせる、受信中は表示を止める、追いつき表示。

const Main := preload("res://scripts/main.gd")

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
	# --- (1a) 設定の既定と永続化 ---
	var cfg := PhiConfig.new()
	check(cfg.smooth_scroll == true, "smooth scroll defaults on")
	cfg.smooth_scroll = false
	cfg.save_file("user://stage65_cfg.ini")
	var cfg2 := PhiConfig.new()
	cfg2.load_file("user://stage65_cfg.ini")
	check(cfg2.smooth_scroll == false, "smooth scroll persists off")
	cfg2.reset()
	check(cfg2.smooth_scroll == true, "reset restores smooth scroll on")

	# --- (1b) アクション定義とメニューの並び ---
	var act := PhiActions.get_action("SmoothScroll")
	check(str(act.get("caption", "")) == "スムーズマップスクロール", "action caption")
	check(str(act.get("kind", "")) == "smooth-scroll-toggle", "action kind")
	var items: Array = []
	for menu in PhiActions.MENUS:
		if str(menu.get("name", "")) == "表示":
			items = menu["items"]
	var i_stop := items.find("LogScrollStop")
	var i_smooth := items.find("SmoothScroll")
	var i_magic := items.find("DispMagic")
	check(i_stop >= 0 and i_smooth == i_stop + 1 and i_magic == i_smooth + 1,
		"menu order: LogScrollStop < SmoothScroll < DispMagic")

	# --- Main を立てる (タブ復元は隔離) ---
	var main: Node = Main.new()
	var iso := ProjectSettings.globalize_path("user://stage65_start.ini")
	OS.execute("rm", ["-f", iso])
	main.set("_tab_session_path", "user://stage65_start.ini")
	root.add_child(main)
	await process_frame
	await process_frame
	var tab: Variant = main.call("_active_tab")
	var mv: Variant = tab.get("map_view")
	check(mv != null, "map view exists")
	check(main.get("_smooth_popup") != null and int(main.get("_smooth_item")) >= 0,
		"smooth check item wired")
	var popup: PopupMenu = main.get("_smooth_popup")
	var sitem := int(main.get("_smooth_item"))
	check(popup.is_item_checked(sitem), "menu checked by default")

	# --- (1c) トグルで全タブへ反映される ---
	main.call("_do_action", "SmoothScroll")
	check((main.get("_config") as PhiConfig).smooth_scroll == false, "toggle turns config off")
	check(mv.get("smooth_scroll") == false, "toggle reaches map view")
	check(not popup.is_item_checked(sitem), "menu unchecked after toggle")
	main.call("_do_action", "SmoothScroll")
	check(mv.get("smooth_scroll") == true, "toggle back on reaches map view")
	check(popup.is_item_checked(sitem), "menu checked again")

	# --- (1d) 北固定の時だけスクロールし、回転ではしない ---
	var a := grid(10)
	mv.set_map(ev(a), null, "mapset")
	var b := shifted(a, Vector2i(0, -1), 230)
	mv.set_map(ev(b), null, "mapset")
	check(mv.get("_scroll_t") < 1.0, "solid style scrolls")
	await create_timer(0.4).timeout
	mv.call("set_map_style", "turn")
	var c := shifted(b, Vector2i(0, -1), 240)
	mv.set_map(ev(c), null, "mapset")
	check(mv.get("_scroll_t") == 1.0, "turn style does not scroll")
	mv.call("set_map_style", "solid")
	mv.set("smooth_scroll", false)
	var d := shifted(c, Vector2i(0, -1), 250)
	mv.set_map(ev(d), null, "mapset")
	check(mv.get("_scroll_t") == 1.0, "option off does not scroll")
	mv.set("smooth_scroll", true)

	# --- (3) マスクの帯の幾何 ---
	var strips: Array = mv.call("_outside_strips", Rect2(10, 20, 100, 80), Vector2(200, 150))
	check(strips.size() == 4, "four mask strips")
	var area := 0.0
	var overlap := false
	for s in strips:
		var r: Rect2 = s
		area += r.size.x * r.size.y
		if r.intersection(Rect2(10, 20, 100, 80)).get_area() > 0.0:
			overlap = true
	check(area == 200.0 * 150.0 - 100.0 * 80.0, "strips cover exactly the outside")
	check(not overlap, "strips do not cover the grid")
	# マスクの内側はセルの並び: 上は余白帯ぶん下がり、下端は
	# 地図の四角の下端と一致する (ユーザーの指定)
	var mr: Rect2 = mv.call("_scroll_mask_rect", 12.0, 26.0, 9, 2.0)
	check(mr.position == Vector2(12, 26 + 16 * 2), "mask top excludes the headroom band")
	check(mr.size == Vector2(9 * 32 * 2, 9 * 32 * 2), "mask covers exactly the cell area")
	check(mr.end.y == 26.0 + (9 * 32 + 16) * 2.0, "mask bottom matches the grid bottom")

	# --- (2) 切断でアニメーションが止まる ---
	# 同期の行き違い検出: 伝えた値と実状態が食い違えば直る
	mv.call("set_session_live", true)
	tab.set("_live_synced", true)
	await create_timer(0.3).timeout
	check(mv.get("_session_live") == false, "frame sync stops animation while disconnected")
	# session_closed ハンドラ経由でも止まる (行き違いの修正)
	mv.call("set_session_live", true)
	tab.call("_on_session_closed")
	check(mv.get("_session_live") == false, "session_closed stops animation")
	# 強制切断でも止まる
	var tab2: Variant = main.call("_create_tab")
	var mv2: Variant = tab2.get("map_view")
	mv2.call("set_session_live", true)
	tab2.call("disconnect_force")
	check(mv2.get("_session_live") == false, "force disconnect stops animation")

	# --- (4a) 溜めた行は entry のまま (下準備は表示時) ---
	tab.set("_log_batching", true)
	tab.log_message("log", "65遅延その1")
	tab.log_message("log", "65遅延その2")
	tab.set("_log_batching", false)
	var batch: Array = tab.get("_log_batch")
	check(batch.size() == 2, "two lines queued")
	check(batch.size() == 2 and batch[0] is Dictionary, "queued as entries, not bbcode")
	tab.call("_flush_log_batch")
	check(tab.call("log_display_backlog") == 0, "queue drained by flush")
	var parsed := (tab.get("log_view") as RichTextLabel).get_parsed_text()
	var p1 := parsed.find("65遅延その1")
	var p2 := parsed.find("65遅延その2")
	check(p1 >= 0 and p2 > p1, "deferred lines render in order")

	# --- (4b) 追いつき表示: 600行溜めても1回で全部は出さない ---
	tab.set("_log_batching", true)
	for i in range(600):
		tab.log_message("log", "65追いつき %d" % i)
	tab.set("_log_batching", false)
	var before_lines := int(tab.get("_log_view_lines"))
	tab.call("_flush_log_batch")
	var delta := int(tab.get("_log_view_lines")) - before_lines
	check(delta > 40 and delta <= 200, "catch-up flush is boosted but capped (%d)" % delta)
	var guard := 0
	while tab.call("log_display_backlog") > 0 and guard < 30:
		tab.call("_flush_log_batch")
		guard += 1
	check(tab.call("log_display_backlog") == 0, "backlog eventually drains")
	check((tab.get("log_view") as RichTextLabel).get_parsed_text().contains("65追いつき 599"),
		"last catch-up line rendered")

	# --- (4c) 大量行の受信中は表示を止める ---
	tab.set("_log_batching", true)
	for i in range(3):
		tab.log_message("log", "65洪水 %d" % i)
	tab.set("_log_batching", false)
	var session: Variant = tab.get("session")
	var pend: Array[PackedByteArray] = []
	for i in range(301):
		pend.append("x".to_utf8_buffer())
	session.set("_pending_lines", pend)
	tab.call("_flush_log_batch")
	check(tab.call("log_display_backlog") == 3, "flush paused while flooding")
	var empty_pend: Array[PackedByteArray] = []
	session.set("_pending_lines", empty_pend)
	tab.call("_flush_log_batch")
	check(tab.call("log_display_backlog") == 0, "flush resumes after flood")

	print("stage65: ", _checks, " checks, ", _failures, " failures")
	quit(1 if _failures > 0 else 0)
