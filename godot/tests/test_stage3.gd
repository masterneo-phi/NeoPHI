extends SceneTree
## 第3段(地図・表示: コンパス・状態パネル・状態アイコン・#ex-disp-magic・
## マウス操作・境目の比率化・新ズーム規則・ツールチップ)のテスト。
##
## 使い方: godot --headless --path . -s tests/test_stage3.gd
## 終了コード 0 = 全一致、1 = 不一致あり。

const PHILLY_ROOT := "/home/hatch/workspace/philly-source/PhillySrc/Philly"

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


# -- #ex-disp-magic の解析 ---------------------------------------------------

func _test_disp_magic_parse() -> void:
	# 基本形: 16進数と、文字＋数値がくっついた効果。
	var dm: Variant = PhiDispMagic.parse("#ex-disp-magic 1 2 3 3 3 C0 3 2 H0")
	_check(dm != null, "disp parse basic")
	if dm != null:
		_check_eq(dm["effect"], 1, "disp parse effect")
		_check_eq(dm["fn"], 2, "disp parse fn")
		_check_eq(dm["power"], 3, "disp parse power")
		_check_eq(dm["start"], {"x": 3, "y": 3, "effect": "C", "param": 0}, "disp parse start")
		_check_eq(dm["end"], {"x": 3, "y": 2, "effect": "H", "param": 0}, "disp parse end")
	# 効果の文字と引数が離れていても読める。
	var dm2: Variant = PhiDispMagic.parse("#ex-disp-magic 0 0 A 1 2 - 0 5 6 E FF")
	_check(dm2 != null, "disp parse spaced")
	if dm2 != null:
		_check_eq(dm2["power"], 10, "disp parse hex power")
		_check_eq(dm2["start"]["effect"], "-", "disp parse dash")
		_check_eq(dm2["end"]["param"], 255, "disp parse hex param")
	# タブ区切り(Philly はタブで照合する)。
	var dm3: Variant = PhiDispMagic.parse("#ex-disp-magic\t1 2 3 3 3 C0 3 2 H0")
	_check(dm3 != null, "disp parse tab")
	# 大文字の16進数と 0x。
	var dm4: Variant = PhiDispMagic.parse("#ex-disp-magic 0X1B 0 0 3 3 C0 3 2 H0")
	_check(dm4 != null and dm4["effect"] == 27, "disp parse 0x hex")
	# 読めないものは null。
	_check_eq(PhiDispMagic.parse("#ex-disp-magic"), null, "disp parse empty")
	_check_eq(PhiDispMagic.parse("#ex-disp-magic 1 2"), null, "disp parse short")
	_check_eq(PhiDispMagic.parse("#ex-disp-magic 1 2 3 3 3"), null, "disp parse no effects")
	_check_eq(PhiDispMagic.parse("#ex-disp-magic 1 2 3 3 3 C0 3 2"), null, "disp parse no end effect")
	_check_eq(PhiDispMagic.parse("#ex-disp-magicx 1 2 3 3 3 C0 3 2 H0"), null, "disp parse bad prefix")
	_check_eq(PhiDispMagic.parse("#ex-disp-magic ZZ 2 3 3 3 C0 3 2 H0"), null, "disp parse bad hex")
	_check_eq(PhiDispMagic.parse("#ex-map size=57"), null, "disp parse other command")


func _test_disp_magic_phases() -> void:
	var data: Variant = PhiDispMagic.parse("#ex-disp-magic 1 2 3 3 3 C0 3 1 H0")
	_check(data != null, "disp phases parse")
	if data == null:
		return
	# 1段目: 始点の C → 発射のセル 9 を始点に。
	var p0 := PhiDispMagic.phase_cells(data, 0)
	_check_eq(p0.size(), 1, "disp phase0 cast count")
	_check_eq(p0[0][1], 9, "disp phase0 cast cell")
	_check_eq(p0[0][0], Vector2(96, 101), "disp phase0 cast pos")
	# 2段目: 終点の H → 命中のセル 20 を終点に。
	var p1 := PhiDispMagic.phase_cells(data, 1)
	_check_eq(p1.size(), 1, "disp phase1 hit count")
	_check_eq(p1[0][1], 20, "disp phase1 hit cell")
	_check_eq(p1[0][0], Vector2(96, 37), "disp phase1 hit pos")
	# 3段目: H → もう一度命中。
	var p2 := PhiDispMagic.phase_cells(data, 2)
	_check_eq(p2.size(), 1, "disp phase2 hit count")
	_check_eq(p2[0][1], 20, "disp phase2 hit cell")

	# 通過: 始点(1,3)→終点(5,3)。全長 4、半分 2。
	var pass_data: Variant = PhiDispMagic.parse("#ex-disp-magic 0 0 0 1 3 -0 5 3 -0")
	var pp0 := PhiDispMagic.phase_cells(pass_data, 0)
	_check_eq(pp0.size(), 3, "disp pass phase0 count")
	_check_eq(pp0[0][0], Vector2(32, 101), "disp pass phase0 first")
	_check_eq(pp0[2][0], Vector2(96, 101), "disp pass phase0 last")
	var pp1 := PhiDispMagic.phase_cells(pass_data, 1)
	_check_eq(pp1.size(), 3, "disp pass phase1 count")
	_check_eq(pp1[0][0], Vector2(96, 101), "disp pass phase1 first")
	_check_eq(pp1[2][0], Vector2(160, 101), "disp pass phase1 last")
	# 3段目: 終点が - なら何も描かない。
	_check_eq(PhiDispMagic.phase_cells(pass_data, 2).size(), 0, "disp pass phase2 empty")
	# CastPass(P): 1段目は始点を除く通過＋発射。
	var cp_data: Variant = PhiDispMagic.parse("#ex-disp-magic 0 0 0 1 3 P0 5 3 -0")
	var cp0 := PhiDispMagic.phase_cells(cp_data, 0)
	_check_eq(cp0.size(), 3, "disp castpass count")
	_check_eq(cp0[0][0], Vector2(64, 101), "disp castpass skips start")
	_check_eq(cp0[2][1], 9, "disp castpass cast cell")
	# 爆発(E): 3段目は中心＋引数のビットの周り。
	var ex_data: Variant = PhiDispMagic.parse("#ex-disp-magic 0 0 0 3 3 C0 3 2 EFF")
	var ex2 := PhiDispMagic.phase_cells(ex_data, 2)
	_check_eq(ex2.size(), 9, "disp explode count")
	var cells: Array = []
	for c in ex2:
		cells.append(c[1])
	_check(cells.has(25), "disp explode center")
	_check(cells.has(21) and cells.has(29), "disp explode corners")
	var ex_data0: Variant = PhiDispMagic.parse("#ex-disp-magic 0 0 0 3 3 C0 3 2 E0")
	_check_eq(PhiDispMagic.phase_cells(ex_data0, 2).size(), 1, "disp explode param 0 center only")
	# 知らない効果文字は何も描かない。
	var unk: Variant = PhiDispMagic.parse("#ex-disp-magic 0 0 0 3 3 Z0 3 2 Q0")
	_check_eq(PhiDispMagic.phase_cells(unk, 0).size(), 0, "disp unknown phase0")
	_check_eq(PhiDispMagic.phase_cells(unk, 1).size(), 0, "disp unknown phase1")
	_check_eq(PhiDispMagic.phase_cells(unk, 2).size(), 0, "disp unknown phase2")
	# 始点と終点が同じでも落ちない。
	var same: Variant = PhiDispMagic.parse("#ex-disp-magic 0 0 0 3 3 -0 3 3 -0")
	_check_eq(PhiDispMagic.phase_cells(same, 0).size(), 1, "disp same cell pass")

	# 魔法弾の抑え込み: 同じマス・最近なら抑える。
	var recent := [{"cell": Vector2i(3, 2), "spawned": 100.0}]
	_check(PhiDispMagic.bolt_suppressed(recent, Vector2i(3, 2), 100.5, 1.0), "disp suppress same cell")
	_check(not PhiDispMagic.bolt_suppressed(recent, Vector2i(3, 3), 100.5, 1.0), "disp suppress other cell")
	_check(not PhiDispMagic.bolt_suppressed(recent, Vector2i(3, 2), 101.5, 1.0), "disp suppress expired")
	_check(not PhiDispMagic.bolt_suppressed([], Vector2i(3, 2), 100.5, 1.0), "disp suppress empty")


# -- キャラの状態アイコン -----------------------------------------------------

func _test_chara_state() -> void:
	_check_eq(PhiCharaState.under_icon(0x20), [8, 0, 5], "state under chant ready")
	_check_eq(PhiCharaState.under_icon(0x21), [13, 0, 5], "state under chanting")
	_check_eq(PhiCharaState.under_icon(0x22), [13, 0, 5], "state under chant done")
	_check_eq(PhiCharaState.under_icon(0x00), null, "state under none")
	_check_eq(PhiCharaState.under_icon(0x01), null, "state under attack is over")
	_check_eq(PhiCharaState.over_icon(0x01, "F", 0), [11, 0, 11], "state attack front")
	_check_eq(PhiCharaState.over_icon(0x01, "B", 0), [9, 0, 1], "state attack back")
	_check_eq(PhiCharaState.over_icon(0x01, "L", 0), [12, -3, 5], "state attack left")
	_check_eq(PhiCharaState.over_icon(0x01, "R", 0), [10, 3, 5], "state attack right")
	_check_eq(PhiCharaState.over_icon(0x70, "F", 0), [14, 0, -9], "state sleep frame 0")
	_check_eq(PhiCharaState.over_icon(0x70, "F", 1), [15, 0, -9], "state sleep frame 1")
	for code in [0x30, 0x31, 0x32, 0x34, 0x41, 0x42, 0x46, 0x61, 0x62, 0x63, 0x65, 0x67, 0x68, 0x75, 0x76, 0x92]:
		_check_eq(PhiCharaState.over_icon(code, "F", 0), [16, 0, 0], "state work %x" % code)
	_check_eq(PhiCharaState.over_icon(0x00, "F", 0), null, "state over none")
	_check_eq(PhiCharaState.over_icon(0x02, "F", 0), null, "state over unknown")


# -- マウス操作 ----------------------------------------------------------------

func _test_mouse() -> void:
	var rect := Vector2(672, 720)
	var center := Vector2(336, 360)
	# 8方向。
	_check_eq(PhiMouse.cursor_for(center + Vector2(0, -200), rect, true, false, 3.0), "MouseUp", "mouse up")
	_check_eq(PhiMouse.cursor_for(center + Vector2(0, 200), rect, true, false, 3.0), "MouseDown", "mouse down")
	_check_eq(PhiMouse.cursor_for(center + Vector2(-200, 0), rect, true, false, 3.0), "MouseLeft", "mouse left")
	_check_eq(PhiMouse.cursor_for(center + Vector2(200, 0), rect, true, false, 3.0), "MouseRight", "mouse right")
	_check_eq(PhiMouse.cursor_for(center + Vector2(-150, -150), rect, true, false, 3.0), "MouseUpLeft", "mouse upleft")
	_check_eq(PhiMouse.cursor_for(center + Vector2(150, -150), rect, true, false, 3.0), "MouseUpRight", "mouse upright")
	_check_eq(PhiMouse.cursor_for(center + Vector2(-150, 150), rect, true, false, 3.0), "MouseDownLeft", "mouse downleft")
	_check_eq(PhiMouse.cursor_for(center + Vector2(150, 150), rect, true, false, 3.0), "MouseDownRight", "mouse downright")
	# 中心と外は既定カーソル。
	_check_eq(PhiMouse.cursor_for(center, rect, true, false, 3.0), "", "mouse center")
	_check_eq(PhiMouse.cursor_for(Vector2(-10, 100), rect, true, false, 3.0), "", "mouse outside")
	_check_eq(PhiMouse.cursor_for(Vector2(700, 100), rect, true, false, 3.0), "", "mouse outside right")
	# 回転マップの上部の角は回転カーソル。
	_check_eq(PhiMouse.cursor_for(Vector2(10, 10), rect, false, false, 3.0), "MouseTurnLeft", "mouse turn left corner")
	_check_eq(PhiMouse.cursor_for(Vector2(662, 10), rect, false, false, 3.0), "MouseTurnRight", "mouse turn right corner")
	# 北固定では角も方向カーソル。
	_check_eq(PhiMouse.cursor_for(Vector2(10, 10), rect, true, false, 3.0), "MouseUpLeft", "mouse northfix corner")
	# 回転マップ＋Shift/Ctrl は左右半分が回転。
	_check_eq(PhiMouse.cursor_for(Vector2(100, 400), rect, false, true, 3.0), "MouseTurnLeft", "mouse turn zone left")
	_check_eq(PhiMouse.cursor_for(Vector2(500, 400), rect, false, true, 3.0), "MouseTurnRight", "mouse turn zone right")
	# 移動キーとコマンド。
	_check_eq(PhiMouse.move_keys("MouseUp"), ["8"], "mouse keys up")
	_check_eq(PhiMouse.move_keys("MouseUpLeft"), ["8", "4"], "mouse keys upleft")
	_check_eq(PhiMouse.move_keys("MouseTurnLeft"), ["7"], "mouse keys turn")
	_check_eq(PhiMouse.move_keys(""), [], "mouse keys none")
	_check_eq(PhiMouse.move_commands("MouseUp", true, "none"), ["go N"], "mouse cmd northfix up")
	_check_eq(PhiMouse.move_commands("MouseUp", false, "none"), ["go"], "mouse cmd turn up")
	_check_eq(PhiMouse.move_commands("MouseUpLeft", true, "none"), ["go N", "go W"], "mouse cmd diagonal")
	_check_eq(PhiMouse.move_commands("MouseTurnLeft", false, "none"), ["turn l"], "mouse cmd turn left")
	_check_eq(PhiMouse.move_commands("MouseUp", true, "ctrl"), ["go n"], "mouse cmd crab")
	# 北固定＋Shift/Ctrl のホバーで向く方向。
	_check_eq(PhiMouse.turn_command(center + Vector2(0, -200), rect, 3.0), "turn n", "mouse turn n")
	_check_eq(PhiMouse.turn_command(center + Vector2(200, 0), rect, 3.0), "turn e", "mouse turn e")
	_check_eq(PhiMouse.turn_command(center + Vector2(0, 200), rect, 3.0), "turn s", "mouse turn s")
	_check_eq(PhiMouse.turn_command(center + Vector2(-200, 0), rect, 3.0), "turn w", "mouse turn w")
	_check_eq(PhiMouse.turn_command(center + Vector2(10, 10), rect, 3.0), "", "mouse turn dead zone")


# -- コンパスと状態パネル ------------------------------------------------------

func _test_compass_and_status() -> void:
	_check_eq(CompassView.cell_index(0, false), 0, "compass N")
	_check_eq(CompassView.cell_index(2, false), 6, "compass E")
	_check_eq(CompassView.cell_index(4, false), 4, "compass S")
	_check_eq(CompassView.cell_index(6, false), 2, "compass W")
	_check_eq(CompassView.cell_index(2, true), 0, "compass northfix")
	_check_eq(CompassView.cell_index(6, true), 0, "compass northfix W")
	# バーの区間分け。
	_check_eq(StatusPanel.bar_segments(100, 100, -1, 200.0, 0, 1, 2), [[0.0, 200.0, 0]], "bar full")
	_check_eq(StatusPanel.bar_segments(50, 100, -1, 200.0, 0, 1, 2), [[0.0, 100.0, 0], [100.0, 100.0, 2]], "bar half")
	_check_eq(StatusPanel.bar_segments(0, 100, -1, 200.0, 0, 1, 2), [[0.0, 200.0, 2]], "bar empty")
	_check_eq(StatusPanel.bar_segments(50, 100, 80, 200.0, 0, 1, 2), [[0.0, 100.0, 0], [100.0, 60.0, 1], [160.0, 40.0, 2]], "bar trail")
	_check_eq(StatusPanel.bar_segments(80, 100, 50, 200.0, 0, 1, 2), [[0.0, 160.0, 0], [160.0, 40.0, 2]], "bar healed no trail")
	_check_eq(StatusPanel.bar_segments(10, 0, -1, 200.0, 0, 1, 2), [], "bar no max")
	# 毒と混乱でセルが変わる。
	_check_eq(StatusPanel.bar_cells(false, false), [0, 1, 2, 4, 5, 6], "bar cells normal")
	_check_eq(StatusPanel.bar_cells(true, false), [3, 1, 2, 4, 5, 6], "bar cells poison")
	_check_eq(StatusPanel.bar_cells(false, true), [0, 1, 2, 7, 5, 6], "bar cells panic")
	# 状態の保持: 無い項目は前の値を保ち、減った分を覚える。
	var panel := StatusPanel.new()
	panel.set_status({"hp": 100, "maxHp": 100, "mp": 50, "maxMp": 80, "f": 10, "w": 0, "m": 0, "c": 0, "gp": 885})
	_check_eq(panel.debug_values()["hp"], 100, "panel hp")
	panel.set_status({"hp": 60})
	_check_eq(panel.debug_values()["hp"], 60, "panel hp update")
	_check_eq(panel.debug_values()["maxHp"], 100, "panel maxHp kept")
	_check_eq(panel.debug_values()["prevHp"], 100, "panel prevHp")
	_check_eq(panel.debug_values()["gp"], 885, "panel gp kept")
	panel.queue_free()
	# 右列(情報欄)は廃止された。スクリプト自体が無い。
	_check(not ResourceLoader.exists("res://scripts/side_panel.gd"), "side panel removed")


# -- 太字 ----------------------------------------------------------------------

func _test_bold_font() -> void:
	var base := SystemFont.new()
	base.font_names = ["DejaVu Sans"]
	var bold := FontVariation.new()
	bold.base_font = base
	bold.variation_embolden = 1.0
	_check_eq(bold.variation_embolden, 1.0, "bold embolden set")
	_check_eq(bold.base_font, base, "bold base font")
	# 太くした文字は、細い文字より幅が狭くならない。
	var w_base := base.get_string_size("Guest", HORIZONTAL_ALIGNMENT_LEFT, -1, 24).x
	var w_bold := bold.get_string_size("Guest", HORIZONTAL_ALIGNMENT_LEFT, -1, 24).x
	_check(w_bold >= w_base and w_bold > 0.0, "bold width")


# -- パーサ・セッション・設定 ----------------------------------------------------

func _test_parser_session_config() -> void:
	var parser := PhiParser.new()
	var events := parser.feed(Cp932.encode("#ex-disp-magic 1 2 3 3 3 C0 3 2 H0"))
	_check_eq(events.size(), 1, "parser disp event count")
	if events.size() == 1:
		_check_eq(events[0]["type"], "dispMagic", "parser disp event type")
		_check_eq(events[0]["data"]["start"]["effect"], "C", "parser disp event data")
	# #more の間はログ行になり、コマンドとして扱わない。
	parser.feed(Cp932.encode("#more"))
	var more_events := parser.feed(Cp932.encode("#ex-disp-magic 1 2 3 3 3 C0 3 2 H0"))
	_check_eq(more_events.size(), 1, "parser disp in more count")
	if more_events.size() == 1:
		_check_eq(more_events[0]["type"], "message", "parser disp in more is log")
	parser.feed(Cp932.encode("#end-more"))
	# 読めない #ex-disp-magic は無視される。
	_check_eq(parser.feed(Cp932.encode("#ex-disp-magic 1 2")).size(), 0, "parser disp bad ignored")
	# ログイン行: 魔法表示のスイッチ。
	_check(PhiSession.login_lines("guest").has("#ex-switch ex-disp-magic=true"), "session login disp true")
	_check(PhiSession.login_lines("guest", 57, "solid", false).has("#ex-switch ex-disp-magic=false"), "session login disp false")
	# 設定: DispMagicClientSide の往復。
	var cfg := PhiConfig.new()
	_check_eq(cfg.disp_magic, true, "config disp default")
	cfg.disp_magic = false
	var path := OS.get_temp_dir().path_join("neophi-test-config-disp.ini")
	DirAccess.remove_absolute(path)
	_check(cfg.save_file(path), "config disp save")
	var cfg2 := PhiConfig.new()
	_check(cfg2.load_file(path), "config disp load")
	_check_eq(cfg2.disp_magic, false, "config disp roundtrip")
	cfg2.reset()
	_check_eq(cfg2.disp_magic, true, "config disp reset")
	DirAccess.remove_absolute(path)


# -- スキンの絵 ------------------------------------------------------------------

func _test_skin_images() -> void:
	if DirAccess.open(PHILLY_ROOT) == null:
		print("skip real philly files: no source tree")
		return
	var assets := GameAssets.new()
	assets.setup([PHILLY_ROOT], [], [], "Mine")
	var direction: Variant = assets.skin_image("Direction")
	_check(direction != null, "skin direction found")
	if direction != null:
		_check_eq([(direction as Texture2D).get_width(), (direction as Texture2D).get_height()], [400, 50], "skin direction size")
	var bar: Variant = assets.skin_image("HpMpBar")
	_check(bar != null, "skin hpmbar found")
	if bar != null:
		_check_eq([(bar as Texture2D).get_width(), (bar as Texture2D).get_height()], [400, 31], "skin hpmbar size")
	var panel: Variant = assets.skin_image("HpMpPanel")
	_check(panel != null, "skin hpmppanel found")
	if panel != null:
		_check_eq([(panel as Texture2D).get_width(), (panel as Texture2D).get_height()], [20, 50], "skin hpmppanel size")
	var status: Variant = assets.skin_image("Status")
	_check(status != null, "skin status found")
	if status != null:
		_check_eq([(status as Texture2D).get_width(), (status as Texture2D).get_height()], [200, 50], "skin status size")
	var items: Variant = assets.items()
	_check(items != null, "skin items found")
	if items != null:
		_check_eq([(items as Texture2D).get_width(), (items as Texture2D).get_height()], [960, 32], "skin items size")
	var cursor: Variant = assets.cursor_texture("MouseUp")
	_check(cursor != null, "skin cursor up found")
	if cursor != null:
		_check((cursor as Dictionary).get("texture") is ImageTexture, "skin cursor texture")
	_check(assets.cursor_texture("MouseTurnLeft") != null, "skin cursor turn found")


# -- 地図ビューの統合 ------------------------------------------------------------

func _test_map_view_disp_magic() -> void:
	var mv := MapView.new()
	mv.player_name = "Alice"
	mv.set_map({"size": 7, "cells": [], "chars": [
		{"name": "Alice", "x": 3, "y": 3, "dir": "F", "gra": "", "status": 0, "gigant": "#", "default": 0, "layer": 0},
		{"name": "Bob", "x": 3, "y": 2, "dir": "F", "gra": "", "status": 0x21, "gigant": "#", "default": 0, "layer": 0},
	]}, null, "")
	mv.size = Vector2(700, 750)
	mv._update_zoom()
	# 描く範囲の形: 7x7 をズーム3で中央に。
	var rect := mv.drawn_map_rect()
	_check_eq(rect.size, Vector2(672, 720), "map drawn rect size")
	_check_eq(rect.position, Vector2(14, 15), "map drawn rect pos")
	# 地図の大きさが変わると1段階だけ拡大し、同じ大きさでは変わらない。
	mv.set_map({"size": 5, "cells": [], "chars": [
		{"name": "Alice", "x": 2, "y": 2, "dir": "F", "gra": "", "status": 0, "gigant": "#", "default": 0, "layer": 0},
	]}, null, "")
	_check_eq(mv.zoom, 4, "map dim change grows one step")
	mv.set_map({"size": 5, "cells": [], "chars": [
		{"name": "Alice", "x": 2, "y": 2, "dir": "F", "gra": "", "status": 0, "gigant": "#", "default": 0, "layer": 0},
	]}, null, "")
	_check_eq(mv.zoom, 4, "map same dim keeps zoom")
	mv.set_map({"size": 7, "cells": [], "chars": [
		{"name": "Alice", "x": 3, "y": 3, "dir": "F", "gra": "", "status": 0, "gigant": "#", "default": 0, "layer": 0},
	]}, null, "")
	_check_eq(mv.zoom, 3, "map dim back shrinks at once")
	# 魔法表示を出すと覚えられる。
	var data: Variant = PhiDispMagic.parse("#ex-disp-magic 1 2 3 3 3 C0 3 2 H0")
	mv.spawn_disp_magic(data)
	_check_eq(mv.debug_disp_magic_count(), 1, "map disp count")
	_check_eq(mv.debug_recent_disp_hit_count(), 1, "map disp hit count")
	# 同じマスの魔法攻撃では、自前の魔法弾は出ない。
	mv.spawn_combat_fx("DM > Alice は魔法を唱えている... \nDM > Alice は Bob を Harm で攻撃した. [10 hp]")
	_check_eq(mv.debug_bolt_count(), 0, "map disp suppresses bolt")
	_check_eq(mv.debug_impact_count(), 0, "map disp suppresses impact")
	# 魔法表示が無ければ、魔法弾が出る。
	var mv2 := MapView.new()
	mv2.player_name = "Alice"
	mv2.set_map({"size": 7, "cells": [], "chars": [
		{"name": "Alice", "x": 3, "y": 3, "dir": "F", "gra": "", "status": 0, "gigant": "#", "default": 0, "layer": 0},
		{"name": "Bob", "x": 3, "y": 2, "dir": "F", "gra": "", "status": 0, "gigant": "#", "default": 0, "layer": 0},
	]}, null, "")
	mv2.spawn_combat_fx("DM > Alice は魔法を唱えている... \nDM > Alice は Bob を Harm で攻撃した. [10 hp]")
	_check_eq(mv2.debug_bolt_count(), 1, "map bolt without disp")
	mv.queue_free()
	mv2.queue_free()


func _initialize() -> void:
	_test_disp_magic_parse()
	_test_disp_magic_phases()
	_test_chara_state()
	_test_mouse()
	_test_compass_and_status()
	_test_bold_font()
	_test_parser_session_config()
	_test_skin_images()
	_test_map_view_disp_magic()
	print("test_stage3: ", _checks, " checks, ", _failures, " failures")
	quit(1 if _failures > 0 else 0)
