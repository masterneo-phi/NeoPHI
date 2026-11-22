extends SceneTree
## 第127段: FX 文字 (DM 演出拡張の :A z text) の shrink-to-fit。
## サイズ指定 200 は 64px 固定で描かれ、マップ描画幅に収まらない
## 章タイトルが途中で切れていた (ズーム1 の 11x11 = 352px に対し
## 全文は約 544〜672px)。収まらない場合だけフォントサイズを
## 縮小して全文を収め、収まっている場合は従来どおりの大きさで
## 描くことを確認する。
##
## 使い方: godot --headless --path . -s tests/test_stage127.gd
## 終了コード 0 = 全一致、1 = 不一致あり。

var _failures := 0
var _checks := 0

# 実機で切れた章タイトル (エルディウス第8章)。
const TITLE := "第八章 そして光となる"
# Murder Club 等で従来から収まって表示されていた短い例。
const SHORT := "第一章"


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


func _width(font: Font, text: String, px: int) -> float:
	return font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x


func _test_fit() -> void:
	var font := PhiFont.make_ui_font()
	# 前提: 名目 64px ではタイトル全文が 11x11 (352px) に収まらない。
	check(_width(font, TITLE, 64) > 352.0, "前提: 64px では 352px に収まらない")
	# 短い文字列は従来どおり名目サイズ (見た目不変)。
	check_eq(MapView.fx_text_font_size(font, SHORT, 200, 352.0), 64, "短文は 200% = 64px のまま")
	check_eq(MapView.fx_text_font_size(font, SHORT, 100, 352.0), 32, "短文は 100% = 32px のまま")
	check_eq(MapView.fx_text_font_size(font, SHORT, 50, 352.0), 16, "短文は 50% = 16px のまま")
	check_eq(MapView.fx_text_font_size(font, TITLE, 200, 4096.0), 64, "幅が十分なら長文も名目どおり")
	# 11x11 ズーム1 (352px): 縮小して全文が収まる。
	var fit11 := MapView.fx_text_font_size(font, TITLE, 200, 352.0)
	check(fit11 < 64, "11x11 では 64px から縮小される")
	check(_width(font, TITLE, fit11) <= 352.0, "11x11 で全文が収まる")
	check(fit11 >= MapView.FX_TEXT_MIN_PX, "11x11 の縮小は下限以上")
	# 縮小は必要最小限 (1px 大きいと溢れる = 最大の収まる大きさ)。
	check(_width(font, TITLE, fit11 + 1) > 352.0, "11x11 では 1px 大きいと溢れる")
	# 7x7 ズーム1 (224px): さらに縮小して全文が収まる。
	var fit7 := MapView.fx_text_font_size(font, TITLE, 200, 224.0)
	check(fit7 < fit11, "7x7 では 11x11 よりさらに小さい")
	check(_width(font, TITLE, fit7) <= 224.0, "7x7 で全文が収まる")
	check(fit7 >= MapView.FX_TEXT_MIN_PX, "7x7 の縮小は下限以上")
	check(_width(font, TITLE, fit7 + 1) > 224.0, "7x7 では 1px 大きいと溢れる")
	# L/R スロットは左右マージン 16px を引いた幅で収まる。
	var fit_lr := MapView.fx_text_font_size(font, TITLE, 200, 352.0 - 16.0)
	check(_width(font, TITLE, fit_lr) <= 336.0, "L/R の実効幅でも全文が収まる")
	# 極端な長文は下限 8px で止まる (それ未満は判読不能なため)。
	var huge := TITLE + TITLE + TITLE + TITLE + TITLE + TITLE
	check_eq(MapView.fx_text_font_size(font, huge, 200, 224.0),
		MapView.FX_TEXT_MIN_PX, "極端な長文は下限で止まる")
	# 退化ケース: 空文・フォントなし・幅なしは名目サイズを返す。
	check_eq(MapView.fx_text_font_size(font, "", 200, 352.0), 64, "空文は名目")
	check_eq(MapView.fx_text_font_size(null, TITLE, 200, 352.0), 64, "フォントなしは名目")
	check_eq(MapView.fx_text_font_size(font, TITLE, 200, 0.0), 64, "幅 0 は名目")
	# 名目側の下限クランプは従来どおり (10% = 3px → 8px)。
	check_eq(MapView.fx_text_font_size(font, SHORT, 10, 352.0),
		MapView.FX_TEXT_MIN_PX, "名目サイズの下限クランプ")


func _test_geometry() -> void:
	# MapView の描画矩形が想定どおりの幅になること (フィットの
	# 入力になる幅)。ズーム1: 11x11 = 352px、7x7 = 224px。
	var view := MapView.new()
	view.zoom = 1
	view.size = Vector2(352, 368)
	view.set_map({"size": 11, "cells": [], "chars": []}, null, "")
	check_eq(view.drawn_map_rect().size.x, 352.0, "11x11 ズーム1 の描画幅")
	view.size = Vector2(224, 240)
	view.set_map({"size": 7, "cells": [], "chars": []}, null, "")
	check_eq(view.drawn_map_rect().size.x, 224.0, "7x7 ズーム1 の描画幅")
	# その幅でタイトルがフィットすることまでを通しで確認する。
	var font := PhiFont.make_ui_font()
	view.label_font = font
	for w in [352.0, 224.0]:
		var px := MapView.fx_text_font_size(font, TITLE, 200, w)
		check(_width(font, TITLE, px) <= w, "描画幅 %d で全文フィット" % int(w))
	view.free()


func _initialize() -> void:
	_test_fit()
	_test_geometry()
	print("test_stage127: ", _checks, " checks, ", _failures, " failures")
	quit(1 if _failures > 0 else 0)
