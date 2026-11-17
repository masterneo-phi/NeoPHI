extends SceneTree
## 第18段のテスト: 効果音の拡張 (直接トリガ) とツール3種
## (サウンドテスト/マップチップ確認/キャラグラ確認)。
##
## 使い方: godot --headless --path . -s tests/test_stage18.gd
## 終了コード 0 = 全一致、1 = 不一致あり。

var _failures := 0
var _checks := 0
var _main: Node = null
var _se: Array = []


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


func _test_actions() -> void:
	_check_eq(PhiActions.kind_of("SoundTest"), "sound-test", "SoundTest の kind")
	_check_eq(PhiActions.kind_of("ChipViewer"), "chip-viewer", "ChipViewer の kind")
	_check_eq(PhiActions.kind_of("CharaViewer"), "chara-viewer", "CharaViewer の kind")
	var found := 0
	for menu in PhiActions.MENUS:
		if str(menu["name"]) == "ツール":
			for item in menu["items"]:
				if str(item) in ["SoundTest", "ChipViewer", "CharaViewer"]:
					found += 1
	_check_eq(found, 3, "ツールメニューに3件ある")


func _map_event(shift: int) -> Dictionary:
	var cells: Array = []
	for i in range(49):
		cells.append({"chip": 10 + ((i + shift) % 3), "attr": 0})
	return {"type": "map", "size": 7, "dir": 0, "cells": cells, "chars": []}


func _run() -> void:
	_test_actions()
	var ps := load("res://main.tscn") as PackedScene
	_main = ps.instantiate()
	root.add_child(_main)
	await _wait(1.5)
	var engine: Object = _main.get("_sound_engine")
	engine.connect("se_requested", func(path: String) -> void: _se.append(path))
	# 効果音の実ファイルは配布側 (zip ステージ) にあるので、
	# テスト用ルートへ写してエンジンに渡し直す。
	var se_root := "/tmp/neophi-test-se"
	OS.execute("mkdir", ["-p", se_root + "/sound/se"])
	OS.execute("cp", ["/home/hatch/workspace/.zipstage/mac/sound/se/lock.wav", "/home/hatch/workspace/.zipstage/mac/sound/se/bump.wav", se_root + "/sound/se/"])
	engine.call("setup", PhiConfig.new(), [se_root])
	# 直接トリガ (play_se_entry)。
	engine.call("play_se_entry", "sound\\se\\lock.wav")
	_check(_se.any(func(p: String) -> bool: return p.ends_with("sound/se/lock.wav")), "直接トリガで lock.wav")
	# ツール窓が開く。
	_main.call("_show_sound_test")
	await _wait(0.3)
	var st: Window = _main.get("_sound_test_window")
	_check(st != null and st.visible, "サウンドテスト窓が開く")
	if st != null:
		st.hide()
	_main.call("_show_chip_viewer")
	await _wait(0.3)
	var cv: Window = _main.get("_chip_viewer")
	_check(cv != null and cv.visible, "マップチップ確認窓が開く")
	if cv != null:
		cv.hide()
	_main.call("_show_chara_viewer")
	await _wait(0.3)
	var gv: Window = _main.get("_chara_viewer")
	_check(gv != null and gv.visible, "キャラグラ確認窓が開く")
	if gv != null:
		gv.hide()
	# ぶつかり: 同一盤面で bump、違う盤面では鳴らない。
	var tab: Node = _main.call("_active_tab")
	_se.clear()
	tab.call("_on_event", _map_event(0))
	tab.call("_arm_bump_watch")
	tab.call("_on_event", _map_event(0))
	_check(_se.any(func(p: String) -> bool: return p.ends_with("sound/se/bump.wav")), "同一盤面で bump.wav")
	_se.clear()
	tab.call("_arm_bump_watch")
	tab.call("_on_event", _map_event(1))
	_check(not _se.any(func(p: String) -> bool: return p.ends_with("sound/se/bump.wav")), "違う盤面では bump しない")
	print("test_stage18: ", _checks, " checks, ", _failures, " failures")
	quit(1 if _failures > 0 else 0)
