extends SceneTree
## 第19段のテスト: #mapset-define の複数シート描画。
## セルの属性下位2ビットが指すシートで描くための解決を確認する:
## slot0 = 現在のマップセット、slot1〜3 = define の名前、
## define が無いスロットは既定シート。PhiCharacter が
## mapsetDefine 通知を保持して MapView/EagleView へ渡すことも見る。
##
## 使い方: godot --headless --path . -s tests/test_stage19.gd
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


## チップシートの代用品 BMP を書く。Philly 形式は横2倍で、
## 左半分が絵・右半分がマスク (白=不透明)。実寸は 1024x96 で
## 読み込むと 512x96 のシートになる。
func _write_bmp(path: String, r: int, g: int, b: int) -> void:
	var w := 1024
	var h := 96
	var row := w * 3
	var img_size := row * h
	var bytes := PackedByteArray()
	bytes.resize(54 + img_size)
	bytes.encode_u8(0, 0x42) # 'B'
	bytes.encode_u8(1, 0x4D) # 'M'
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


func _run() -> void:
	_dir = OS.get_temp_dir() + "/neophi_mapset_test"
	DirAccess.make_dir_recursive_absolute(_dir)
	_write_bmp(_dir + "/SheetA.bmp", 200, 30, 30)
	_write_bmp(_dir + "/SheetB.bmp", 30, 30, 200)
	_write_bmp(_dir + "/default.bmp", 30, 200, 30)
	var assets := GameAssets.new()
	assets.setup([] as Array[String], [_dir] as Array[String], [] as Array[String])
	# MapView のシート解決。
	var view := MapView.new()
	root.add_child(view)
	var cells: Array = []
	for i in range(49):
		cells.append({"chip": 0x2E, "attr": 0})
	view.set_map({"size": 7, "cells": cells, "chars": []}, assets, "SheetA", {1: "SheetB"})
	_check_eq(_tex_color(view.get("_chip_texs")[0]).r8, 200, "slot0 は SheetA")
	_check_eq(_tex_color(view.get("_chip_texs")[1]).b8, 200, "slot1 は define の SheetB")
	_check_eq(_tex_color(view.get("_chip_texs")[2]).g8, 200, "slot2 は既定シートに落ちる")
	_check(view.call("_sheet_for", {"attr": 0}) == view.get("_chip_texs")[0], "attr 0 → slot0")
	_check(view.call("_sheet_for", {"attr": 1}) == view.get("_chip_texs")[1], "attr 1 → slot1")
	_check(view.call("_sheet_for", {"attr": 0x42}) == view.get("_chip_texs")[2], "attr 0x42 → slot2 (下位2ビット)")
	_check(view.call("_sheet_for", {"attr": 0x0B}) == view.get("_chip_texs")[3], "attr 0x0B → slot3")
	_check(bool(view.call("_any_sheet")), "シートあり")
	# define 無しなら slot1 も既定シート。
	var view2 := MapView.new()
	root.add_child(view2)
	view2.set_map({"size": 7, "cells": cells, "chars": []}, assets, "SheetA")
	_check_eq(_tex_color(view2.get("_chip_texs")[1]).g8, 200, "define 無しの slot1 は既定シート")
	# PhiEagleView のシート解決。
	var eagle := PhiEagleView.new()
	root.add_child(eagle)
	var ecells: Array = []
	for i in range(9):
		ecells.append({"chip": 0x2E, "attr": 0})
	eagle.set_event({"width": 3, "height": 3, "cells": ecells}, assets, "SheetA", 2.0, {1: "SheetB"})
	_check_eq(_tex_color(eagle.get("_chip_texs")[1]).b8, 200, "Eagle の slot1 は SheetB")
	_check(eagle.call("_sheet_for", {"attr": 1}) == eagle.get("_chip_texs")[1], "Eagle attr 1 → slot1")
	# PhiCharacter が mapsetDefine を保持して MapView へ渡す。
	var ps := load("res://main.tscn") as PackedScene
	var main: Node = ps.instantiate()
	root.add_child(main)
	await _wait(1.5)
	var tab: Node = main.call("_active_tab")
	tab.call("_on_event", {"type": "notice", "mapsetDefine": [2, "SheetB"]})
	_check_eq(str(tab.get("_defines").get(2, "")), "SheetB", "タブが define を保持")
	tab.call("_on_event", {"type": "map", "size": 7, "dir": 0, "cells": cells, "chars": []})
	var mv: Object = tab.get("map_view")
	_check_eq(str(mv.get("_defines").get(2, "")), "SheetB", "MapView へ define が渡る")
	print("test_stage19: ", _checks, " checks, ", _failures, " failures")
	quit(1 if _failures > 0 else 0)
