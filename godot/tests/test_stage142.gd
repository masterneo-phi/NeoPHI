extends SceneTree
## 第142段のテスト: マップセット (チップシート) 対応表の寿命と再描画。
## 実地報告 (2026-11-26, The United Kingdom NEO・転送魔方陣) の切り分け:
## 同じセルの地形が、ある時は正しいシート・ある時は既定シートで
## 描かれる。原因候補は2つ —
##  (A) フレームの後から届いた #mapset / #mapset-define が表示中の
##      フレームへ反映されない (従来経路そのものの欠陥)
##  (B) v6 セッションの状態 (16枠 define 等) や前世界の対応表が
##      接続・世界移動を越えて残り、従来フレームの解決を汚す
## ここでは両方を分けて固定する:
##  A: 新規タブ→従来世界のみ。フレーム→define 通知 (フレーム無し)
##     で MapView の対応表が新しい define に追随すること。
##  B: 接続し直しと転送追随 (transfer_completed) で、タブの
##     _mapset/_defines/_defines16 と MapView の16枠が落ちること。
##
## 使い方: godot --headless --path . -s tests/test_stage142.gd
## 終了コード 0 = 全一致、1 = 不一致あり。

var _failures := 0
var _checks := 0
var _dir := ""


func _check(cond: bool, label: String) -> void:
	_checks += 1
	if not cond:
		_failures_add(label)


func _check_eq(a: Variant, b: Variant, label: String) -> void:
	_checks += 1
	if a != b:
		_failures_add(label + " (got " + str(a) + ", want " + str(b) + ")")


func _failures_add(label: String) -> void:
	_failures += 1
	printerr("FAIL: ", label)


func _initialize() -> void:
	_run()


func _wait(sec: float) -> void:
	var until := Time.get_ticks_msec() + int(sec * 1000.0)
	while Time.get_ticks_msec() < until:
		await process_frame


## チップシートの代用品 BMP (stage19 と同じ作法)。
func _write_bmp(path: String, r: int, g: int, b: int) -> void:
	var w := 1024
	var h := 96
	var row := w * 3
	var img_size := row * h
	var bytes := PackedByteArray()
	bytes.resize(54 + img_size)
	bytes.encode_u8(0, 0x42)
	bytes.encode_u8(1, 0x4D)
	bytes.encode_u32(2, 54 + img_size)
	bytes.encode_u32(10, 54)
	bytes.encode_u32(14, 40)
	bytes.encode_s32(18, w)
	bytes.encode_s32(22, h)
	bytes.encode_u16(26, 1)
	bytes.encode_u16(28, 24)
	bytes.encode_u32(34, img_size)
	for y in range(h):
		for x in range(w):
			var i := 54 + (y * w + x) * 3
			if x < w / 2:
				bytes[i] = b
				bytes[i + 1] = g
				bytes[i + 2] = r
			else:
				bytes[i] = 255
				bytes[i + 1] = 255
				bytes[i + 2] = 255
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_buffer(bytes)
	f.close()


func _tex_color(tex: Texture2D) -> Color:
	if tex == null:
		return Color(-1, -1, -1)
	var img := tex.get_image()
	if img == null:
		return Color(-1, -1, -1)
	return img.get_pixel(3, 3)


func _cells() -> Array:
	var cells: Array = []
	for i in range(49):
		cells.append({"chip": 0x2E, "attr": 0x80 | (i % 3)})
	return cells


func _run() -> void:
	_dir = OS.get_temp_dir() + "/neophi_mapset142_test"
	DirAccess.make_dir_recursive_absolute(_dir)
	_write_bmp(_dir + "/SheetA.bmp", 200, 30, 30)   # 赤
	_write_bmp(_dir + "/SheetB.bmp", 30, 30, 200)   # 青
	_write_bmp(_dir + "/SheetC.bmp", 200, 200, 30)  # 黄
	_write_bmp(_dir + "/default.bmp", 30, 200, 30)  # 緑=既定
	var assets := GameAssets.new()
	assets.setup([] as Array[String], [_dir] as Array[String], [] as Array[String])

	# --- MapView 単体: refresh_mapsets で表示中フレームのシートが替わる ---
	var view := MapView.new()
	root.add_child(view)
	view.set_map({"size": 7, "cells": _cells(), "chars": []}, assets, "SheetA", {})
	_check_eq(_tex_color(view.get("_chip_texs")[1]).g8, 200,
		"view: define 無しの slot1 は既定シート")
	if view.has_method("refresh_mapsets"):
		view.call("refresh_mapsets", "SheetA", {1: "SheetB"})
		_check_eq(_tex_color(view.get("_chip_texs")[1]).b8, 200,
			"view: refresh_mapsets で slot1 が SheetB に替わる (フレーム再送なし)")
		view.call("refresh_mapsets", "SheetC", {})
		_check_eq(_tex_color(view.get("_chip_texs")[0]).r8, 200,
			"view: refresh_mapsets で slot0 が SheetC に替わる")
		_check_eq(_tex_color(view.get("_chip_texs")[0]).g8, 200,
			"view: slot0 の緑成分も SheetC のもの")
	else:
		_check(false, "view: MapView.refresh_mapsets が無い")

	# --- 分離: v6 の定義は従来の解決を汚さず、逆も同様 ---
	if view.get("_chip_texs16") != null:
		view.set_defines16({1: "SheetB"})
		_check_eq(_tex_color(view.get("_chip_texs16")[1]).b8, 200,
			"分離: v6 表の slot1 は SheetB")
		view.set_map({"size": 7, "cells": _cells(), "chars": []}, assets, "SheetA", {1: "SheetC"})
		_check_eq(_tex_color(view.get("_chip_texs")[1]).r8, 200,
			"分離: 従来表の slot1 は SheetC (赤成分)")
		_check_eq(_tex_color(view.get("_chip_texs")[1]).g8, 200,
			"分離: 従来表の slot1 は SheetC (緑成分)")
		_check(view.call("_sheet_for", {"attr": 1}) == view.get("_chip_texs")[1],
			"分離: 従来セルは従来表だけを見る")
		_check(view.call("_sheet_for", {"slot": 1, "attr": 0}) == view.get("_chip_texs16")[1],
			"分離: v6 セルは v6 表だけを見る")
		_check(view.call("_sheet_for", {"slot": 9, "attr": 2}) == view.get("_chip_texs")[2],
			"分離: 定義の無い v6 枠は従来解決へ落ちる")
	else:
		_check(false, "分離: MapView._chip_texs16 が無い")

	# --- タブ経由 (main.tscn) ---
	var ps := load("res://main.tscn") as PackedScene
	var main: Node = ps.instantiate()
	root.add_child(main)
	await _wait(1.5)
	var tab: Node = main.call("_active_tab")
	var mv: Object = tab.get("map_view")

	# (A) 従来世界のみ: 通知→フレーム→フレーム→define 通知だけ。
	tab.call("_on_event", {"type": "notice", "mapset": "Base"})
	tab.call("_on_event", {"type": "notice", "mapsetDefine": [1, "default"]})
	tab.call("_on_event", {"type": "notice", "mapsetDefine": [2, "Heaven"]})
	tab.call("_on_event", {"type": "map", "size": 7, "dir": 0,
		"cells": _cells(), "chars": []})
	_check_eq(str(mv.get("_defines").get(1, "")), "default",
		"A: 最初のフレームは define 1=default で描かれる")
	# 別エリアへ一歩 (新しい視界のフレームが先に届いた) 後に、
	# define の付け替えだけが届く — 新しいフレームは来ない。
	tab.call("_on_event", {"type": "map", "size": 7, "dir": 0,
		"cells": _cells(), "chars": []})
	tab.call("_on_event", {"type": "notice", "mapsetDefine": [1, "Heaven"]})
	tab.call("_on_event", {"type": "notice", "mapsetDefine": [2, "default"]})
	_check_eq(str(tab.get("_defines").get(1, "")), "Heaven",
		"A: タブの対応表は新しい define を保持する")
	_check_eq(str(mv.get("_defines").get(1, "")), "Heaven",
		"A: フレーム無しでも MapView の define 1 が Heaven に追随する")
	_check_eq(str(mv.get("_defines").get(2, "")), "default",
		"A: フレーム無しでも MapView の define 2 が default に追随する")
	# #mapset の付け替えも同様に追随する。
	tab.call("_on_event", {"type": "notice", "mapset": "Heaven"})
	_check_eq(str(mv.get("mapset")), "Heaven",
		"A: フレーム無しでも MapView の mapset が追随する")

	# (B1) 再接続で前世界の対応表が落ちる。
	tab.call("_on_event", {"type": "v6define", "slot": 5, "name": "SheetB"})
	_check_eq(str(tab.get("_defines16").get(5, "")), "SheetB",
		"B: 前提として v6 define が入る")
	tab.call("connect_to", "127.0.0.1", 9, "TESTID")
	_check_eq(str(tab.get("_mapset")), "", "B1: 再接続で _mapset が落ちる")
	_check(tab.get("_defines").is_empty(), "B1: 再接続で _defines が落ちる")
	_check(tab.get("_defines16").is_empty(), "B1: 再接続で _defines16 が落ちる")
	_check(mv.get("_defines16").is_empty(), "B1: 再接続で MapView の16枠が落ちる")

	# (B2) 転送追随 (セッション内部の接続差し替え) でも落ちる。
	tab.call("_on_event", {"type": "notice", "mapset": "Base"})
	tab.call("_on_event", {"type": "notice", "mapsetDefine": [1, "Heaven"]})
	tab.call("_on_event", {"type": "v6define", "slot": 2, "name": "SheetB"})
	var sess: Object = tab.get("session")
	if sess.has_signal("transfer_completed"):
		sess.emit_signal("transfer_completed")
		_check_eq(str(tab.get("_mapset")), "", "B2: 転送追随で _mapset が落ちる")
		_check(tab.get("_defines").is_empty(), "B2: 転送追随で _defines が落ちる")
		_check(tab.get("_defines16").is_empty(), "B2: 転送追随で _defines16 が落ちる")
		_check(mv.get("_defines16").is_empty(), "B2: 転送追随で MapView の16枠が落ちる")
	else:
		_check(false, "B2: PhiSession に transfer_completed 信号が無い")

	print("test_stage142: ", _checks, " checks, ", _failures, " failures")
	quit(1 if _failures > 0 else 0)
