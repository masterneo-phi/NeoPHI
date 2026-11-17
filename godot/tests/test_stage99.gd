extends SceneTree
## 第99段のテスト: ログの保存先を画面から指定できる。
## 表示メニュー「ログの保存先...」でフォルダ選択ダイアログを
## 開き、選んだフォルダが [Log] LogSaveDir に保存されて、
## 手動保存がそのフォルダへ書かれることを確かめる
## (利用者の要望。設定自体は前から ini にあった)。
##
## 使い方: godot --headless --path . -s tests/test_stage99.gd
## 終了コード 0 = 全一致、1 = 不一致あり。

const Main := preload("res://scripts/main.gd")

var _failures := 0
var _checks := 0


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


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	# (1) アクションとメニュー。
	check_eq(PhiActions.kind_of("LogSaveDir"), "log-save-dir", "s99 kind")
	var main = Main.new()
	for p in ["user://stage99_tabs.ini", "user://stage99_cfg.ini"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	main.set("_tab_session_path", "user://stage99_tabs.ini")
	main.set("_config_path", "user://stage99_cfg.ini")
	root.add_child(main)
	await process_frame
	await process_frame
	var found := false
	for popup in main.get("_menu_popups"):
		for i in range((popup as PopupMenu).item_count):
			if (popup as PopupMenu).get_item_text(i) == "ログの保存先...":
				found = true
	check(found, "s99 menu has LogSaveDir")
	# (2) 実行するとフォルダ選択ダイアログが出る。
	main._do_action("LogSaveDir")
	await process_frame
	var dialog = main.get("_log_dir_dialog")
	check(dialog is FileDialog, "s99 dialog created")
	check_eq((dialog as FileDialog).file_mode, FileDialog.FILE_MODE_OPEN_DIR, "s99 dialog is dir mode")
	# (3) フォルダを選ぶと設定に残る。
	var target := "/tmp/neophi-logdir-test"
	OS.execute("rm", ["-rf", target])
	main.call("_on_log_dir_selected", target)
	check_eq(str(main.get("_config").log_save_dir), target, "s99 config updated")
	var cfg := ConfigFile.new()
	check_eq(cfg.load("user://stage99_cfg.ini"), OK, "s99 ini loads")
	check_eq(str(cfg.get_value("Log", "LogSaveDir", "")), target, "s99 ini has LogSaveDir")
	# (4) 手動保存が新しい保存先へ書かれる。
	var tab = main.call("_active_tab")
	tab.set("_player_name", "Saver")
	tab.log_message("log", "stage99 line")
	var saved := str(tab.save_log_buffer())
	check(saved.begins_with(target), "s99 save path under target: " + saved)
	check(FileAccess.file_exists(saved), "s99 saved file exists")
	OS.execute("rm", ["-rf", target])
	print("test_stage99: ", _checks, " checks, ", _failures, " failures")
	quit(1 if _failures > 0 else 0)
