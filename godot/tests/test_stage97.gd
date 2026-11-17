extends SceneTree
## 第97段のテスト: 魔法弾と魔法陣の扱い (ユーザーの指定)。
## - 魔法弾は「魔法表示」(config.disp_magic) に連動する:
##   タブの MapView.magic_bolt が設定に追随し、メニューの
##   切り替えで全タブへ反映される。
## - サーバー駆動表示の発動タイル (魔法陣 CELL_CAST) は
##   描かず、代わりに術師の位置へ円状オーラが出る。
##
## 使い方: godot --headless --path . -s tests/test_stage97.gd
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


func _run() -> void:
	# --- サーバー駆動表示: 魔法陣 → オーラ差し替え ---
	var mv := MapView.new()
	root.add_child(mv)
	await process_frame
	var cast_data := {
		"start": {"x": 2, "y": 2, "effect": "C", "param": 0},
		"end": {"x": 2, "y": 1, "effect": "H", "param": 0},
	}
	mv.spawn_disp_magic(cast_data)
	check(mv.debug_disp_magic_count() == 1, "s97 disp magic stored")
	check(mv.debug_cast_count() == 1, "s97 cast tile becomes aura")
	var casts: Array = mv.get("_casts")
	# オーラの中心は発動タイルの中心 (タイル左上 + 16,16)。
	var tile: Vector2 = PhiDispMagic.phase_cells(cast_data, 0)[0][0]
	check(casts[0]["center"] == tile + Vector2(16.0, 16.0), "s97 aura at cast tile center")
	# 発動タイルを含まない表示ではオーラは出ない。
	var pass_data := {
		"start": {"x": 2, "y": 2, "effect": "-", "param": 0},
		"end": {"x": 2, "y": 1, "effect": "H", "param": 0},
	}
	mv.spawn_disp_magic(pass_data)
	check(mv.debug_cast_count() == 1, "s97 no aura without cast tile")
	mv.queue_free()

	# --- 魔法表示の設定連動 ---
	var main: Node = Main.new()
	var iso := ProjectSettings.globalize_path("user://stage97_tabs.ini")
	OS.execute("rm", ["-f", iso])
	main.set("_tab_session_path", "user://stage97_tabs.ini")
	var isoc := ProjectSettings.globalize_path("user://stage97_cfg.ini")
	OS.execute("rm", ["-f", isoc])
	main.set("_config_path", "user://stage97_cfg.ini")
	root.add_child(main)
	await process_frame
	await process_frame
	var tab: Variant = main.call("_active_tab")
	var config: Variant = main.get("_config")
	var view: Variant = tab.get("map_view")
	# 既定は魔法表示 ON なので、起動直後から魔法弾あり。
	check(config.disp_magic, "s97 disp magic default on")
	check(view.magic_bolt, "s97 bolt follows config at build")
	# メニュー切り替えで OFF になり、タブの表示にも反映される。
	main.call("_do_action", "DispMagic")
	check(not config.disp_magic, "s97 disp magic off after toggle")
	check(not view.magic_bolt, "s97 bolt off after toggle")
	# 戻すと ON。
	main.call("_do_action", "DispMagic")
	check(config.disp_magic, "s97 disp magic back on")
	check(view.magic_bolt, "s97 bolt back on")
	print("test_stage97: ", _checks, " checks, ", _failures, " failures")
	quit(1 if _failures > 0 else 0)
