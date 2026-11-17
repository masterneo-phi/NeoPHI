extends SceneTree
## 第93段のテスト: コマンドパレットに BGM 再生とログ記録の
## ON/OFF スイッチを追加。メニューと同じ設定 (play_bgm /
## log_auto_save) を共有し、押すと設定が切り替わって保存され、
## ボタンの押下状態も追随する。
##
## 使い方: godot --headless --path . -s tests/test_stage93.gd
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


func _find_button(tab: Variant, action_name: String) -> Button:
	for b in tab.get("_toolbar_buttons"):
		if str(b.get_meta("action")) == action_name:
			return b
	return null


func _run() -> void:
	var main: Node = Main.new()
	var iso := ProjectSettings.globalize_path("user://stage93_tabs.ini")
	OS.execute("rm", ["-f", iso])
	main.set("_tab_session_path", "user://stage93_tabs.ini")
	var isoc := ProjectSettings.globalize_path("user://stage93_cfg.ini")
	OS.execute("rm", ["-f", isoc])
	main.set("_config_path", "user://stage93_cfg.ini")
	root.add_child(main)
	await process_frame
	await process_frame
	var tab: Variant = main.call("_active_tab")
	var config: Variant = main.get("_config")
	# パレットに2つのスイッチがある (トグル形式)。
	var bgm_btn := _find_button(tab, "PlayBGM")
	var log_btn := _find_button(tab, "LogAutoSave")
	check(bgm_btn != null, "s93 pallet has BGM switch")
	check(log_btn != null, "s93 pallet has log switch")
	check(bgm_btn != null and bgm_btn.toggle_mode, "s93 BGM switch is toggle")
	check(log_btn != null and log_btn.toggle_mode, "s93 log switch is toggle")
	# 既定: BGM は ON、ログ記録は OFF で、ボタンも一致する。
	check(config.play_bgm, "s93 bgm default on")
	check(not config.log_auto_save, "s93 log default off")
	check(bgm_btn.button_pressed, "s93 BGM switch shows on")
	check(not log_btn.button_pressed, "s93 log switch shows off")
	# BGM スイッチを押すと設定が OFF になり、ボタンも追随する。
	bgm_btn.pressed.emit()
	check(not config.play_bgm, "s93 bgm off after press")
	check(not bgm_btn.button_pressed, "s93 BGM switch shows off")
	# 設定ファイルにも保存される。
	var saved := ConfigFile.new()
	check(saved.load(isoc) == OK, "s93 config file saved")
	check(not bool(saved.get_value("Sound", "PlayBgm", true)), "s93 PlayBgm saved off")
	# もう一度押すと ON に戻る。
	bgm_btn.pressed.emit()
	check(config.play_bgm, "s93 bgm back on")
	check(bgm_btn.button_pressed, "s93 BGM switch shows on again")
	# ログ記録スイッチも同じ。
	log_btn.pressed.emit()
	check(config.log_auto_save, "s93 log on after press")
	check(log_btn.button_pressed, "s93 log switch shows on")
	var saved2 := ConfigFile.new()
	check(saved2.load(isoc) == OK, "s93 config file saved 2")
	check(bool(saved2.get_value("Log", "LogAutoSave", false)), "s93 LogAutoSave saved on")
	log_btn.pressed.emit()
	check(not config.log_auto_save, "s93 log back off")
	check(not log_btn.button_pressed, "s93 log switch shows off again")
	print("test_stage93: ", _checks, " checks, ", _failures, " failures")
	quit(1 if _failures > 0 else 0)
