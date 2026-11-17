extends SceneTree
## 第94段のテスト: Eagle Eye の窓は題名行のドラッグで移動
## でき、窓のリサイズで盤が拡縮する (マップ窓と同じ感覚)。
## 開いた直後の大きさは従来どおり盤の既定寸法で、開いている
## 間に新しいイベントが来ても大きさはユーザーのまま。
##
## 使い方: godot --headless --path . -s tests/test_stage94.gd
## 終了コード 0 = 全一致、1 = 不一致あり。

const Main := preload("res://scripts/main.gd")

var _checks := 0
var _failures := 0


func check(cond: bool, label: String) -> void:
	_checks += 1
	if not cond:
		_failures += 1
		printerr("FAIL: ", label)


func _initialize() -> void:
	call_deferred("_run")


func _event(dim: int) -> Dictionary:
	var cells: Array = []
	for i in range(dim * dim):
		cells.append({"chip": 1, "attr": 0})
	return {"width": dim, "height": dim, "cells": cells}


func _find_drag_handle(node: Node) -> Control:
	if node is Control and (node as Control).has_meta("phi_window_drag"):
		return node
	for child in node.get_children():
		var found := _find_drag_handle(child)
		if found != null:
			return found
	return null


func _run() -> void:
	var main: Node = Main.new()
	var iso := ProjectSettings.globalize_path("user://stage94_tabs.ini")
	OS.execute("rm", ["-f", iso])
	main.set("_tab_session_path", "user://stage94_tabs.ini")
	var isoc := ProjectSettings.globalize_path("user://stage94_cfg.ini")
	OS.execute("rm", ["-f", isoc])
	main.set("_config_path", "user://stage94_cfg.ini")
	root.add_child(main)
	await process_frame
	await process_frame
	# ヘッドレスのルートは 64x64 しかないので、窓の確認が
	# できる大きさに広げておく。
	root.size = Vector2i(1400, 1000)
	await process_frame
	# ビュー単体: 割り当てた大きさに盤が追随する。
	var view := PhiEagleView.new()
	root.add_child(view)
	view.set_event(_event(20), null, "", 1.0, {})
	var base_scale := view.debug_current_scale()
	check(is_equal_approx(base_scale, 560.0 / 640.0), "s94 default scale is the cap")
	view.size = Vector2(640, 656)
	await process_frame
	check(is_equal_approx(view.debug_current_scale(), 1.0), "s94 scale follows size 1x")
	view.size = Vector2(1280, 1312)
	await process_frame
	check(is_equal_approx(view.debug_current_scale(), 2.0), "s94 scale follows size 2x")
	view.queue_free()
	# 窓: 開いた直後は盤の既定寸法で開く。
	var win := PhiEagleWindow.new()
	win.theme = main.call("_dialog_theme")
	win.transparent = true
	main.add_child(win)
	win.show_event(_event(11), null, "", 1.0, "Test")
	await process_frame
	await process_frame
	check(win.visible, "s94 window visible")
	var size0 := win.size
	var pos0 := win.position
	var wview: PhiEagleView = win.get("_view")
	var win_base := wview.debug_current_scale()
	check(win_base > 0.8 and win_base < 1.25, "s94 window opens near default scale")
	# 題名行のドラッグで移動する。
	var handle := _find_drag_handle(win)
	check(handle != null, "s94 drag handle exists")
	if handle != null:
		# 埋め込み窓の中のコントロールの全体座標は、窓の
		# ローカル座標そのもの (ビューポートの原点基準)。
		var rect := handle.get_global_rect()
		var local := rect.get_center()
		var press := InputEventMouseButton.new()
		press.button_index = MOUSE_BUTTON_LEFT
		press.pressed = true
		press.position = local
		win.push_input(press)
		var motion := InputEventMouseMotion.new()
		motion.button_mask = MOUSE_BUTTON_MASK_LEFT
		motion.position = local + Vector2(36, 22)
		motion.relative = Vector2(36, 22)
		win.push_input(motion)
		var release := InputEventMouseButton.new()
		release.button_index = MOUSE_BUTTON_LEFT
		release.pressed = false
		release.position = local + Vector2(36, 22)
		win.push_input(release)
		await process_frame
		check(win.position == pos0 + Vector2i(36, 22), "s94 window dragged")
	# 窓を大きくすると盤が拡大する。
	win.size = size0 + Vector2i(220, 220)
	await process_frame
	await process_frame
	check(wview.debug_current_scale() > win_base * 1.15, "s94 board grows with window")
	# 窓を小さくすると盤が縮む。
	win.size = Vector2i(240, 220)
	await process_frame
	await process_frame
	check(wview.debug_current_scale() < win_base, "s94 board shrinks with window")
	# 開いている間に新しいイベントが来ても、大きさは保たれる。
	var kept := win.size
	win.show_event(_event(15), null, "", 1.0, "Test")
	await process_frame
	check(win.size == kept, "s94 size kept on new event while open")
	print("test_stage94: ", _checks, " checks, ", _failures, " failures")
	quit(1 if _failures > 0 else 0)
