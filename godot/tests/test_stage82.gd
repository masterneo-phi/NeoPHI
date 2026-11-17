extends SceneTree
## 第82段のテスト: 送受信トレース (診断用)。有効な間、送る行と
## 受けた行の生バイト (16進) が記録されることと、キャラクター
## 側の書き出しで Logs/wire_*.log ができることを確認する。
##
## 使い方: godot --headless --path . -s tests/test_stage82.gd
## 終了コード 0 = 全一致、1 = 不一致あり。

var _failures := 0
var _checks := 0
var _frames := 0
var _tab: PhiCharacter = null
var _config: PhiConfig = null


func _check(cond: bool, label: String) -> void:
	_checks += 1
	if not cond:
		_failures += 1
		printerr("FAIL: ", label)


func _initialize() -> void:
	_test_session_trace()
	_config = PhiConfig.new()
	_config.log_auto_save = false
	_config.wire_trace = true
	_config.log_save_dir = "user://wiretest_logs"
	var font := PhiFont.make_ui_font()
	var bold := PhiFont.make_bold_font()
	_tab = PhiCharacter.new()
	_tab.setup(GameAssets.new(), _config, font, bold, PhiLogFilter.new(), PhiTagMenu.parse(PhiTagMenu.DEFAULT_XML))
	root.add_child(_tab)
	_tab.position = Vector2.ZERO
	_tab.size = Vector2(1280, 1024)
	process_frame.connect(_on_frame)


func _test_session_trace() -> void:
	var s := PhiSession.new()
	_check(not s.wire_trace, "s82 trace off by default")
	s.wire_trace = true
	s.send_line("あ")
	s._flush_queue()
	_check_eq(s.wire_trace_lines.size(), 1, "s82 one sent trace")
	if s.wire_trace_lines.size() == 1:
		_check(s.wire_trace_lines[0].contains("SENT 82a00a"), "s82 sent bytes are cp932 + LF")
	s._feed_lines("hello\n".to_utf8_buffer())
	_check_eq(s.wire_trace_lines.size(), 2, "s82 one recv trace")
	if s.wire_trace_lines.size() == 2:
		_check(s.wire_trace_lines[1].contains("RECV 68656c6c6f"), "s82 recv bytes recorded")
	_check_eq(s.pending_line_count(), 1, "s82 line still delivered")
	var s2 := PhiSession.new()
	s2.send_line("あ")
	s2._flush_queue()
	_check(s2.wire_trace_lines.is_empty(), "s82 no trace when disabled")


func _check_eq(a: Variant, b: Variant, label: String) -> void:
	_checks += 1
	if a != b:
		_failures += 1
		printerr("FAIL: ", label, " (got ", a, ", want ", b, ")")


func _on_frame() -> void:
	_frames += 1
	if _frames == 3:
		_test_character_write()
		print("test_stage82: ", _checks, " checks, ", _failures, " failures")
		quit(1 if _failures > 0 else 0)


func _test_character_write() -> void:
	# セッションへ設定が伝わり、溜まった記録がファイルになる。
	_check(_tab.session.wire_trace, "s82 flag synced to session")
	_tab.session.wire_trace_lines.append("1 SENT 82a00a")
	_tab._flush_wire_trace()
	var dir := ProjectSettings.globalize_path("user://wiretest_logs")
	var found := ""
	var d := DirAccess.open(dir)
	if d != null:
		for name in d.get_files():
			if name.begins_with("wire_"):
				found = name
	_check(found != "", "s82 wire log file created")
	if found != "":
		var text := FileAccess.get_file_as_string(dir.path_join(found))
		_check(text.contains("SENT 82a00a"), "s82 wire log content")
	OS.execute("rm", ["-rf", dir])
