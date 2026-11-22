extends SceneTree
## 第124段: マップの高さ (起伏)。
## (1) パーサ: 高さの印 ('1'=+1 '2'=+2 '3'=+3 '9'=-1) を段数として
##     保持する。#m57/#m121 は `#ex-switch height=1` 申告時に M 行の
##     直後へ来る H 行から、従来 #map はセル対の2バイト目から読む。
##     印でないフレームは従来どおり (height キー自体が付かない)。
## (2) MapView の静的計算: height_at の端延長、relief_involved、
##     段面の帯形状、色調変換 (Field の草ではサンプルと一致、
##     暗いピクセルでのみ補正が効く)、足元基準の行パス
##     (高さ 0 では従来の char_draw_row と完全一致)、段差を渡る
##     曲線 relief_scroll_dy (登りはホップ、降りは後半に落ちる)。
## (3) テクスチャ生成: 色調キャッシュと段面合成の画素、
##     高さ 0 の地図では起伏テクスチャが作られないこと。

var _checks := 0
var _failures := 0


func check(cond: bool, label: String) -> void:
	_checks += 1
	if not cond:
		_failures += 1
		print("FAIL: ", label)


func check_eq(a: Variant, b: Variant, label: String) -> void:
	_checks += 1
	if a != b:
		_failures += 1
		print("FAIL: ", label, " (got ", a, ", want ", b, ")")


func check_near(a: float, b: float, tol: float, label: String) -> void:
	_checks += 1
	if absf(a - b) > tol:
		_failures += 1
		print("FAIL: ", label, " (got ", a, ", want ", b, ")")


func _initialize() -> void:
	_run.call_deferred()


func _put(raw: PackedByteArray, off: int, s: String) -> void:
	var b := s.to_ascii_buffer()
	for i in b.size():
		raw[off + i] = b[i]


func _cells_with(dim: int, heights: Dictionary) -> Array:
	## heights: Vector2i → 段数。その他は chip ':' の平地。
	var cells: Array = []
	for y in range(dim):
		for x in range(dim):
			var cell := {"chip": 0x3A, "attr": 0x80}
			var h: Variant = heights.get(Vector2i(x, y))
			if h != null:
				cell["height"] = int(h)
			cells.append(cell)
	return cells


func _run() -> void:
	# -- (1a) 印 → 段数 ------------------------------------------------
	check_eq(PhiParser.height_for_marker(0x31), 1, "'1' は +1段")
	check_eq(PhiParser.height_for_marker(0x32), 2, "'2' は +2段")
	check_eq(PhiParser.height_for_marker(0x33), 3, "'3' は +3段")
	check_eq(PhiParser.height_for_marker(0x39), -1, "'9' は -1段 (窪地)")
	check_eq(PhiParser.height_for_marker(0x3A), 0, "':' は印でない")
	check_eq(PhiParser.height_for_marker(0x80), 0, "属性バイトは印でない")
	check_eq(PhiParser.height_for_marker(0x7E), 0, "'~' (屋根) は印でない")
	check_eq(PhiParser.height_for_marker(0x58), 0, "'X' (Eagle) は印でない")

	check_eq(PhiParser.height_for_marker(0x30), 0, "'0' は通常 (段数 0)")
	check(PhiSession.login_lines("X").has("#ex-switch height=1"), "login_lines に height=1 の申告")
	check(PhiSession.post_register_lines().has("#ex-switch height=1"), "post_register_lines に height=1 の申告")

	# -- (1b) #m121 M + H 行 -------------------------------------------
	var p121 := PhiParser.new()
	var body := PackedByteArray()
	body.resize(242)
	for i in range(121):
		body[i * 2] = 0x3A
		body[i * 2 + 1] = 0x80
	body[4] = 0x54 # セル2 のチップは 'T'
	body[7] = 0x8A # セル3 の属性 (アイテム等) はそのまま保持される
	var raw121 := PackedByteArray()
	raw121.append_array("#m121 M F 00000000:".to_ascii_buffer())
	raw121.append_array(body)
	raw121.append_array(" \n".to_ascii_buffer())
	check_eq(raw121.size(), 19 + 242 + 2, "m121 フレームの長さ")
	p121.feed(raw121)
	var hrow := "#m121 H ".to_ascii_buffer()
	var hchars := PackedByteArray()
	hchars.resize(121)
	for i in range(121):
		hchars[i] = 0x30 # '0' = 通常
	hchars[0] = 0x31 # +1段
	hchars[1] = 0x39 # -1段
	hchars[2] = 0x33 # +3段
	hrow.append_array(hchars)
	p121.feed(hrow)
	var evs := p121.feed("#m121 .".to_ascii_buffer())
	check_eq(evs.size(), 1, "m121 の確定で地図イベント")
	var cells121: Array = evs[0].get("cells", [])
	check_eq(cells121.size(), 121, "m121 セル数")
	check_eq(int(cells121[0].get("height", 0)), 1, "m121 H行 セル0 は +1段")
	check_eq(int(cells121[1].get("height", 0)), -1, "m121 H行 セル1 は -1段")
	check_eq(int(cells121[2].get("height", 0)), 3, "m121 H行 セル2 は +3段")
	check_eq(int(cells121[2].get("chip", 0)), 0x54, "m121 セル2 のチップは 'T'")
	check(not cells121[3].has("height"), "m121 H行 '0' のセルに height は付かない")
	check_eq(int(cells121[3].get("attr", 0)), 0x8A, "m121 属性は H 行と独立に保持")
	check(not cells121[4].has("height"), "m121 通常セルに height は付かない")
	# H 行が来ないフレーム (高さ未対応のサーバ) では高さは付かない。
	var p121b := PhiParser.new()
	p121b.feed(raw121)
	var evsb := p121b.feed("#m121 .".to_ascii_buffer())
	check_eq(evsb.size(), 1, "m121 H行なしでも地図イベント")
	check(not (evsb[0].get("cells", [])[0] as Dictionary).has("height"), "H行なしでは height は付かない")

	# -- (1c) #m57 M + H 行 --------------------------------------------
	var p57 := PhiParser.new()
	var body57 := PackedByteArray()
	body57.resize(98)
	for i in range(49):
		body57[i * 2] = 0x3A
		body57[i * 2 + 1] = 0x80
	var raw57 := PackedByteArray()
	raw57.append_array("#m57 M F 00000000:".to_ascii_buffer())
	raw57.append_array(body57)
	raw57.append_array(" \n".to_ascii_buffer())
	p57.feed(raw57)
	var hrow57 := "#m57 H ".to_ascii_buffer()
	var hchars57 := PackedByteArray()
	hchars57.resize(49)
	for i in range(49):
		hchars57[i] = 0x30
	hchars57[0] = 0x32 # +2段
	hchars57[48] = 0x39 # 最終セルは -1段
	hrow57.append_array(hchars57)
	p57.feed(hrow57)
	var evs57 := p57.feed("#m57 .".to_ascii_buffer())
	check_eq(evs57.size(), 1, "m57 の確定で地図イベント")
	var cells57: Array = evs57[0].get("cells", [])
	check_eq(int(cells57[0].get("height", 0)), 2, "m57 H行 セル0 は +2段")
	check_eq(int(cells57[48].get("height", 0)), -1, "m57 H行 最終セルは -1段")
	check(not cells57[1].has("height"), "m57 通常セルに height は付かない")

	# -- (1d) #map M フレーム (対の2文字目) ---------------------------
	var pmap := PhiParser.new()
	var rawmap := PackedByteArray()
	rawmap.resize(118)
	for i in rawmap.size():
		rawmap[i] = 0x20
	_put(rawmap, 0, "#map M F 00000000:")
	for i in range(25):
		rawmap[18 + i * 2] = 0x3A
		rawmap[18 + i * 2 + 1] = 0x3A
	rawmap[19] = 0x32 # セル0: ':' + '2' → +2段
	rawmap[20] = 0x5F # セル1: '_' + '9' → -1段 (水)
	rawmap[21] = 0x39
	rawmap[22] = 0x48 # セル2: 'H' + 'H' は印でない
	rawmap[23] = 0x48
	pmap.feed(rawmap)
	var evsm := pmap.feed("#map .".to_ascii_buffer())
	check_eq(evsm.size(), 1, "#map の確定で地図イベント")
	var cellsm: Array = evsm[0].get("cells", [])
	check_eq(cellsm.size(), 25, "#map セル数")
	check_eq(int(cellsm[0].get("height", 0)), 2, "#map セル0 は +2段")
	check_eq(int(cellsm[0].get("chip", 0)), 0x3A, "#map 印セルのチップは1文字目")
	check_eq(int(cellsm[1].get("height", 0)), -1, "#map セル1 は -1段")
	check(not cellsm[2].has("height"), "#map 'HH' に height は付かない")

	# -- (2a) height_at / relief_involved ------------------------------
	var hc := _cells_with(7, {Vector2i(3, 2): 1, Vector2i(5, 5): -1})
	check_eq(MapView.height_at(hc, 7, 3, 2), 1, "height_at 自セル")
	check_eq(MapView.height_at(hc, 7, 3, 1), 0, "height_at 隣")
	check_eq(MapView.height_at(hc, 7, -1, 2), 0, "height_at 範囲外は端で延長 (西)")
	check_eq(MapView.height_at(hc, 7, 3, -1), 0, "height_at 範囲外は端で延長 (北)")
	var corner := _cells_with(7, {Vector2i(0, 0): 2})
	check_eq(MapView.height_at(corner, 7, -1, -1), 2, "height_at 角の延長")
	var flat := _cells_with(7, {})
	var any_involved := false
	for y in range(7):
		for x in range(7):
			if MapView.relief_involved(flat, 7, x, y):
				any_involved = true
	check(not any_involved, "平坦な地図は起伏対象が無い")
	check(MapView.relief_involved(hc, 7, 3, 2), "段のあるセルは対象")
	check(MapView.relief_involved(hc, 7, 3, 3), "段の南 (段面セル) は対象")
	check(MapView.relief_involved(hc, 7, 2, 2), "段の西隣は対象")
	check(not MapView.relief_involved(hc, 7, 0, 0), "無関係なセルは対象外")
	check(not MapView.relief_involved(hc, 7, 4, 4), "斜めだけの隣接は対象外")

	# -- (2b) 段面の帯形状 ---------------------------------------------
	var edge := _cells_with(7, {})
	for x in range(7):
		edge[2 * 7 + x]["height"] = 1 # 行2が全部 +1、行3が段面
	var span_mid := MapView.relief_face_span(edge, 7, 3, 3, 16)
	check_eq(span_mid, [12, 3], "まっすぐな縁の中央は [fb=12, lip=3]")
	var single := _cells_with(7, {Vector2i(3, 2): 1})
	var span_end := MapView.relief_face_span(single, 7, 3, 3, 0)
	check_eq(span_end.size(), 2, "孤立した段の端にも帯は出る")
	check_eq(int(span_end[0]), 4, "端のテーパーで fb は浅くなる")
	check(not MapView.relief_is_face(flat, 7, 3, 3), "平坦では段面なし")
	check(MapView.relief_is_face(edge, 7, 3, 3), "北が高いと段面")

	# -- (2c) 色調変換 ---------------------------------------------------
	# Field の草に近い明るさ (輝度 ≈ 0.55) ではサンプルの純乗算と一致。
	var g1 := MapView.relief_tone_rgb(106.0, 168.0, 62.0, 1)
	check_near(g1[0], 106.0 * 1.07, 0.01, "色調 +1段 r は純乗算")
	check_near(g1[1], 168.0 * 1.07, 0.01, "色調 +1段 g は純乗算")
	check_near(g1[2], 62.0 * 1.07, 0.01, "色調 +1段 b は純乗算")
	var gm := MapView.relief_tone_rgb(106.0, 168.0, 62.0, -1)
	var lum_g := 0.35 * 84.8 + 0.5 * 134.4 + 0.15 * 49.6
	check_near(gm[0], 84.8 * 0.85 + lum_g * 0.15, 0.01, "色調 -1段 r はサンプルの彩度落とし")
	check_near(gm[2], 49.6 * 0.9 + lum_g * 0.1 + 4.0, 0.01, "色調 -1段 b はサンプルどおり")
	# 暗いピクセル (輝度 ≈ 0.10) では加算成分で段差が残る。
	var d2 := MapView.relief_tone_rgb(20.0, 26.0, 18.0, 2)
	check(d2[0] > 20.0 * 1.15 + 3.0 and d2[0] < 20.0 * 1.15 + 12.0,
		"暗部 +2段は加算成分が効く (got " + str(d2[0]) + ")")
	# 暗いピクセルの窪地は追加の彩度落としで灰色に寄る。
	var dm := MapView.relief_tone_rgb(20.0, 26.0, 18.0, -1)
	var dm_pure := MapView.relief_tone_rgb(20.0, 26.0, 18.0, -1)
	var pure_lum := 0.35 * 16.0 + 0.5 * 20.8 + 0.15 * 14.4
	var pure_r := 16.0 * 0.85 + pure_lum * 0.15
	var pure_g := 20.8 * 0.85 + pure_lum * 0.15
	check(absf(dm[0] - dm[1]) < absf(pure_r - pure_g), "暗部 -1段は彩度がさらに落ちる")
	check(dm_pure[0] > 0.0, "色調 -1段の暗部も潰れない")

	# -- (2d) 足元基準の行パス -------------------------------------------
	var ch_flat := {"x": 3, "y": 3, "gigant": "#"}
	check_eq(MapView.char_pass(ch_flat, flat, 7, 0.0),
		MapView.char_draw_row(ch_flat, 7), "高さ0では従来の行パスと一致")
	var ch_big := {"x": 3, "y": 3, "gigant": "B"}
	check_eq(MapView.char_pass(ch_big, flat, 7, 0.0),
		MapView.char_draw_row(ch_big, 7), "高さ0の2x2敵も従来と一致")
	var hollow := _cells_with(7, {Vector2i(3, 3): -1})
	check_eq(MapView.char_pass(ch_flat, hollow, 7, 8.0), 4,
		"窪地のキャラは足元の行 (y+1) で描く")
	var hill := _cells_with(7, {Vector2i(3, 3): 2})
	check_eq(MapView.char_pass(ch_flat, hill, 7, -16.0), 3,
		"丘のキャラは自セル行で描く")
	var hill3 := _cells_with(7, {Vector2i(3, 3): 3})
	check_eq(MapView.char_pass(ch_flat, hill3, 7, -24.0), 3,
		"+3段でも自セル行")
	var ch_edge := {"x": 3, "y": 6, "gigant": "#"}
	var hollow_edge := _cells_with(7, {Vector2i(3, 6): -1})
	check_eq(MapView.char_pass(ch_edge, hollow_edge, 7, 8.0), 6,
		"最終行の窪地では行をクランプ")
	check_eq(MapView.char_pass(ch_flat, flat, 7, 8.0), 4,
		"補間中 (dy>0) は足元基準になる")
	check_eq(MapView.char_pass(ch_flat, flat, 7, -8.0), 3,
		"補間中 (dy<0) は自セル行のまま")

	# -- (2f) 段差を渡る曲線 (ホップと落下) -----------------------------
	# 登り 0→+1: 端点一致、中盤は線形より浮く (ホップ)。
	check_near(MapView.relief_scroll_dy(0, 1, 0.0), 0.0, 0.001, "ホップ 登り p=0 は開始段")
	check_near(MapView.relief_scroll_dy(0, 1, 1.0), -8.0, 0.001, "ホップ 登り p=1 は終了段")
	var up_mid := MapView.relief_scroll_dy(0, 1, 0.5)
	check(up_mid < -4.0, "ホップ 登り p=0.5 は線形 (-4) より浮く")
	check_near(up_mid, -9.0, 0.001, "ホップ 登り p=0.5 は線形 -4 に浮き 5px")
	check_near(MapView.relief_scroll_dy(0, 1, 0.25), -5.75, 0.001,
		"ホップ 登り p=0.25 は放物線 (浮き 3.75px)")
	# 登り 0→+3: 浮きは上限 10px で頭打ち。
	check_near(MapView.relief_scroll_dy(0, 3, 0.5), -22.0, 0.001,
		"ホップ 3段登り p=0.5 は線形 -12 に上限の浮き 10px")
	# 降り +2→0: 端点一致、中盤は線形より遅れて落ちる。
	check_near(MapView.relief_scroll_dy(2, 0, 0.0), -16.0, 0.001, "落下 p=0 は開始段")
	check_near(MapView.relief_scroll_dy(2, 0, 1.0), 0.0, 0.001, "落下 p=1 は終了段")
	var dn_mid := MapView.relief_scroll_dy(2, 0, 0.5)
	check(dn_mid < -8.0, "落下 p=0.5 は線形 (-8) より高い (遅れて落ちる)")
	check_near(dn_mid, -12.0, 0.001, "落下 p=0.5 は q=0.25 で -12")
	# 降りは単調で行き過ぎない (区間内に収まる)。
	var dn_ok := true
	var dn_prev := -16.0
	for i in range(11):
		var dv := MapView.relief_scroll_dy(2, 0, float(i) / 10.0)
		if dv < -16.0 or dv > 0.0 or dv < dn_prev - 0.001:
			dn_ok = false
		dn_prev = dv
	check(dn_ok, "落下は単調でオーバーシュートなし")
	# 丘から窪地へ (+1→-1) も遅れて落ちる。
	check_near(MapView.relief_scroll_dy(1, -1, 0.5), -4.0, 0.001,
		"落下 +1→-1 の p=0.5 は -4 (線形は 0)")
	# 段差なし: どの p でも静止時のずれと一致。
	check_near(MapView.relief_scroll_dy(2, 2, 0.5), -16.0, 0.001, "段差なし +2 は不変")
	check_near(MapView.relief_scroll_dy(0, 0, 0.5), 0.0, 0.001, "段差なし 0 は 0")
	check_near(MapView.relief_scroll_dy(-1, -1, 0.25), 8.0, 0.001, "段差なし窪地は不変")
	# ホップ中の dy を char_pass に入れても足元基準が破綻しない。
	check_eq(MapView.char_pass(ch_flat, flat, 7, up_mid), 3,
		"ホップ中 (dy=-9) でも足元は自セル行")
	check_eq(MapView.char_pass(ch_flat, flat, 7,
		MapView.relief_scroll_dy(0, 3, 0.5)), 3,
		"3段ホップ中 (dy=-22) でも足元は自セル行")
	check_eq(MapView.char_pass(ch_flat, flat, 7, dn_mid), 3,
		"落下中 (dy=-12) でも足元は自セル行")

	# -- (2e) ノイズ ------------------------------------------------------
	check_eq(MapView.relief_noise(0, 0), -6, "ノイズ (0,0)")
	check(MapView.relief_noise(7, 9) >= -6 and MapView.relief_noise(7, 9) <= 6,
		"ノイズは -6〜6")
	check_eq(MapView.relief_noise(7, 9), MapView.relief_noise(7, 9), "ノイズは決定的")

	# -- (3) テクスチャ生成 ------------------------------------------------
	var assets := GameAssets.new()
	assets.setup([], [], [], "Mine")
	var mv := MapView.new()
	root.add_child(mv)
	mv.zoom_mode = 1
	mv.zoom_fixed = 1
	mv.zoom = 1
	mv.size = Vector2(224, 240)
	# 合成シート: チップ1 (':') を一様な草色にする。
	var sheet_img := Image.create(512, 96, false, Image.FORMAT_RGBA8)
	sheet_img.fill(Color(100.0 / 255.0, 150.0 / 255.0, 60.0 / 255.0, 1.0))
	var sheet_tex := ImageTexture.create_from_image(sheet_img)
	var flat_ev := {"size": 7, "cells": flat, "chars": []}
	mv.set_map(flat_ev, assets, "")
	mv._chip_texs[0] = sheet_tex
	await create_timer(0.3).timeout
	check_eq(mv.debug_relief_cache_size(), 0, "高さ0の地図では起伏テクスチャを作らない")
	# 色調データ: h=0 は無変換、h=+1 は丸めた色調値。
	var d0 := mv._toned_chip_data(sheet_tex, 1, 0)
	var px0 := (20 * 32 + 5) * 4
	check_eq(int(d0[px0]), 100, "色調 h=0 は元の r")
	check_eq(int(d0[px0 + 1]), 150, "色調 h=0 は元の g")
	var d1 := mv._toned_chip_data(sheet_tex, 1, 1)
	var tone := MapView.relief_tone_rgb(100.0, 150.0, 60.0, 1)
	check_eq(int(d1[px0]), clampi(int(round(tone[0])), 0, 255), "色調 +1 の r")
	check_eq(int(d1[px0 + 1]), clampi(int(round(tone[1])), 0, 255), "色調 +1 の g")
	# 段面セルの合成: 唇は北隣の色調画素、帯は土色寄り。
	var hill_cells := _cells_with(7, {})
	for x in range(7):
		hill_cells[2 * 7 + x]["height"] = 1
	var ftex: Variant = mv.relief_cell_texture(hill_cells, 7, 3, 3)
	check(ftex != null, "段面セルのテクスチャが作れる")
	var fimg: Image = (ftex as Texture2D).get_image()
	var lip_px := fimg.get_pixel(16, 0)
	check_eq(int(round(lip_px.r * 255.0)), int(d1[px0]), "唇は北隣の色調 (r)")
	check_eq(int(round(lip_px.g * 255.0)), int(d1[px0 + 1]), "唇は北隣の色調 (g)")
	var stored_n := [int(d1[px0]), int(d1[px0 + 1]), int(d1[px0 + 2])]
	var sh_px := fimg.get_pixel(16, 3)
	check_eq(int(round(sh_px.r * 255.0)), int(round(float(stored_n[0]) * 0.5)), "唇の下の影 (r)")
	check_eq(int(round(sh_px.g * 255.0)), int(round(float(stored_n[1]) * 0.5)), "唇の下の影 (g)")
	var band_px := fimg.get_pixel(16, 6)
	var noise6 := MapView.relief_noise(16, 6)
	var band_r := clampi(int(round((100.0 * 0.5 + 98.0 * 0.5) * (0.92 - 0.20 * 0.25))) + noise6, 0, 255)
	check_eq(int(round(band_px.r * 255.0)), band_r, "段面の帯は土色寄り (r)")
	check_near(band_px.a, 1.0, 0.01, "段面の帯は不透明")
	var cache_size := mv.debug_relief_cache_size()
	var ftex2: Variant = mv.relief_cell_texture(hill_cells, 7, 3, 3)
	check(ftex2 == ftex, "同じセルはキャッシュを返す")
	check_eq(mv.debug_relief_cache_size(), cache_size, "キャッシュは増えない")
	# 高さのある地図を描くと起伏テクスチャが使われる。
	var hill_ev := {"size": 7, "cells": hill_cells, "chars": []}
	mv.set_map(hill_ev, assets, "")
	mv._chip_texs[0] = sheet_tex
	await create_timer(0.3).timeout
	check(mv.debug_relief_cache_size() > 0, "高さのある地図の描画で起伏テクスチャが作られる")
	mv.free()

	print("stage124: ", _checks, " checks, ", _failures, " failures")
	quit(1 if _failures > 0 else 0)
