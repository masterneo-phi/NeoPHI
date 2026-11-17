extends SceneTree
## 第72段: ログの自動保存を Philly と同じ日付単位のファイルに
## する (Logs/<名前>_<YYYYMMDD>.log/.html)。日付が変わると
## 次のファイルに移る。手動保存は従来どおり日時付き。

var _checks := 0
var _failures := 0


func check(cond: bool, label: String) -> void:
	_checks += 1
	if not cond:
		_failures += 1
		print("FAIL: ", label)


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	# --- 日付スタンプの形 ---
	var stamp := PhiLogFile.date_stamp()
	check(stamp.length() == 8 and stamp.is_valid_int(), "date stamp is YYYYMMDD")
	var now := Time.get_date_dict_from_system()
	var expect := "%04d%02d%02d" % [int(now["year"]), int(now["month"]), int(now["day"])]
	check(stamp == expect, "date stamp is today")

	# --- パス: 日付ごとに別ファイルになる ---
	var p1 := PhiLogFile.log_path("user://Logs", "KURO", true, "20261117")
	var p2 := PhiLogFile.log_path("user://Logs", "KURO", true, "20261118")
	check(p1 == "user://Logs/KURO_20261117.html", "dated html path")
	check(p2 == "user://Logs/KURO_20261118.html", "next day path")
	check(p1 != p2, "date change means another file")
	check(PhiLogFile.log_path("user://Logs", "KURO", false, "20261117")
		== "user://Logs/KURO_20261117.log", "dated text path")
	check(PhiLogFile.log_path("user://Logs", "KURO", true) == 
		"user://Logs/KURO_" + stamp + ".html", "default stamp is today")
	check(PhiLogFile.log_path("user://Logs", "a/b", true, "20261117")
		== "user://Logs/a_b_20261117.html", "name sanitized with date")

	# --- 追記: 今日のファイルができ、ヘッダは1回だけ ---
	var dir := "user://stage72_test_logs"
	OS.execute("rm", ["-rf", ProjectSettings.globalize_path(dir)])
	check(PhiLogFile.append_lines(dir, "KURO", true, ["one", "two"]), "append lines 1")
	check(PhiLogFile.append_lines(dir, "KURO", true, ["three"]), "append lines 2")
	var path := PhiLogFile.log_path(dir, "KURO", true)
	check(FileAccess.file_exists(path), "dated file created")
	var content := FileAccess.get_file_as_string(path)
	check(content.begins_with("<!DOCTYPE html>"), "html header written")
	check(content.count("<!DOCTYPE html>") == 1, "header written once")
	check(content.contains("one<br>") and content.contains("three<br>"),
		"all lines in today's file")
	OS.execute("rm", ["-rf", ProjectSettings.globalize_path(dir)])

	print("test_stage72: ", _checks, " checks, ", _failures, " failures")
	quit(1 if _failures > 0 else 0)
