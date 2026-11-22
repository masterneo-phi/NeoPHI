extends SceneTree
## 第128段: 移動の高速化。
## (A) 押し続けリピートの最小間隔を設定値化した
##     ([Disp] MoveRepeatMs、既定 60ms、範囲 30〜500ms。
##     かつては 120ms 固定で秒間約8.3マスが天井だった)。
##     設定の読み書きと往復、クランプ、リピート判定が
##     設定値を参照することを確認する。
## (B) スクロール補間時間を地図の到着間隔に追従させた。
##     速い到着では間隔まで縮み、遅い時は従来の 0.17 秒を
##     維持すること、下限で止まることを確認する。
##
## 使い方: godot --headless --path . -s tests/test_stage128.gd
## 終了コード 0 = 全一致、1 = 不一致あり。

var _failures := 0
var _checks := 0

const CFG_PATH := "user://stage128_cfg.ini"


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


func check_feq(a: float, b: float, label: String) -> void:
	_checks += 1
	if absf(a - b) > 0.0001:
		_failures += 1
		printerr("FAIL: ", label, " (got ", a, ", want ", b, ")")


func _make_tab(config: PhiConfig) -> PhiCharacter:
	var font := PhiFont.make_ui_font()
	var bold := PhiFont.make_bold_font()
	var tab := PhiCharacter.new()
	tab.setup(GameAssets.new(), config, font, bold, PhiLogFilter.new(), PhiTagMenu.parse(PhiTagMenu.DEFAULT_XML))
	root.add_child(tab)
	tab.position = Vector2.ZERO
	tab.size = Vector2(1280, 1024)
	return tab


func _test_config() -> void:
	var cfg := PhiConfig.new()
	check_eq(PhiConfig.DEFAULT_MOVE_REPEAT_MS, 60, "既定定数は 60ms")
	check_eq(cfg.move_repeat_ms, 60, "新規設定の既定は 60ms")
	# 往復: 値を変えて保存し、読み戻しても保たれる。
	cfg.move_repeat_ms = 90
	check(cfg.save_file(CFG_PATH), "設定を保存できる")
	var cfg2 := PhiConfig.new()
	check(cfg2.load_file(CFG_PATH), "設定を読み戻せる")
	check_eq(cfg2.move_repeat_ms, 90, "往復で 90ms が保たれる")
	# クランプ: 生の設定ファイルに範囲外を書くと丸まる。
	var raw := ConfigFile.new()
	raw.set_value("Disp", "MoveRepeatMs", 5)
	raw.save(CFG_PATH)
	var cfg3 := PhiConfig.new()
	cfg3.load_file(CFG_PATH)
	check_eq(cfg3.move_repeat_ms, PhiConfig.MIN_MOVE_REPEAT_MS, "小さすぎる値は下限に丸まる")
	check_eq(PhiConfig.MIN_MOVE_REPEAT_MS, 30, "下限は 30ms")
	raw.set_value("Disp", "MoveRepeatMs", 9999)
	raw.save(CFG_PATH)
	var cfg4 := PhiConfig.new()
	cfg4.load_file(CFG_PATH)
	check_eq(cfg4.move_repeat_ms, PhiConfig.MAX_MOVE_REPEAT_MS, "大きすぎる値は上限に丸まる")
	check_eq(PhiConfig.MAX_MOVE_REPEAT_MS, 500, "上限は 500ms")
	# キーの無い旧設定では既定値になる。
	var raw2 := ConfigFile.new()
	raw2.set_value("Disp", "MenuFontSize", 20)
	raw2.save(CFG_PATH)
	var cfg5 := PhiConfig.new()
	cfg5.load_file(CFG_PATH)
	check_eq(cfg5.move_repeat_ms, 60, "キーが無ければ既定 60ms")
	# reset で既定に戻る。
	cfg.move_repeat_ms = 123
	cfg.reset()
	check_eq(cfg.move_repeat_ms, 60, "reset で既定 60ms に戻る")


func _test_repeat_due() -> void:
	# 未送信 (last <= 0) なら間隔によらず送ってよい。
	check(PhiCharacter.repeat_due(1000, 0, 60), "未送信なら即 due")
	check(PhiCharacter.repeat_due(1000, -5, 60), "last が負でも due")
	# 60ms 設定: 59ms ではまだ、60ms で due。
	check(not PhiCharacter.repeat_due(1059, 1000, 60), "59ms 経過ではまだ (60ms設定)")
	check(PhiCharacter.repeat_due(1060, 1000, 60), "60ms 経過で due (60ms設定)")
	# 同じ経過時間でも設定が違えば判定が変わる (設定参照の証拠)。
	check(not PhiCharacter.repeat_due(1060, 1000, 120), "同じ60ms経過でも 120ms設定ではまだ")
	check(PhiCharacter.repeat_due(1120, 1000, 120), "120ms 経過で due (120ms設定)")
	# 下限 30ms 設定でも判定は同じ形。
	check(not PhiCharacter.repeat_due(1029, 1000, 30), "29ms 経過ではまだ (30ms設定)")
	check(PhiCharacter.repeat_due(1030, 1000, 30), "30ms 経過で due (30ms設定)")


func _test_character_reflects_config() -> void:
	var cfg := PhiConfig.new()
	cfg.log_auto_save = false
	cfg.ui_style = "old"
	var tab := _make_tab(cfg)
	check_eq(tab._repeat_min_interval_ms(), 60, "タブは既定 60ms を使う")
	cfg.move_repeat_ms = 45
	check_eq(tab._repeat_min_interval_ms(), 45, "設定変更がそのまま反映される")
	cfg.move_repeat_ms = 120
	check_eq(tab._repeat_min_interval_ms(), 120, "120ms の設定も反映される")
	tab.free()
	# 設定を持たない素のインスタンスは既定値に落ちる。
	var bare := PhiCharacter.new()
	check_eq(bare._repeat_min_interval_ms(), 60, "設定なしでは既定 60ms")
	bare.free()


func _test_scroll_duration() -> void:
	check_feq(MapView.SCROLL_DURATION, 0.17, "従来の補間時間は 0.17 秒")
	check_feq(MapView.scroll_duration_for_interval(0.0), 0.17, "間隔不明 (0) は 0.17")
	check_feq(MapView.scroll_duration_for_interval(-1.0), 0.17, "負の間隔は 0.17")
	check_feq(MapView.scroll_duration_for_interval(0.5), 0.17, "遅い到着 (500ms) は 0.17 維持")
	check_feq(MapView.scroll_duration_for_interval(0.17), 0.17, "170ms 到着は 0.17")
	check_feq(MapView.scroll_duration_for_interval(0.1), 0.1, "100ms 到着は 0.10 に短縮")
	check_feq(MapView.scroll_duration_for_interval(0.06), 0.06, "60ms 到着は 0.06 に短縮")
	check_feq(MapView.scroll_duration_for_interval(0.03), 0.03, "30ms 到着は下限ちょうど")
	check_feq(MapView.scroll_duration_for_interval(0.01), MapView.MIN_SCROLL_DURATION, "速すぎる到着は下限で止まる")
	check_feq(MapView.MIN_SCROLL_DURATION, 0.03, "下限は 0.03 秒")


func _test_scroll_adaptation() -> void:
	var view := MapView.new()
	check_feq(view._scroll_duration, 0.17, "初期の補間時間は 0.17")
	view._note_scroll_start(100.0)
	check_feq(view._scroll_duration, 0.17, "最初のスクロールは 0.17")
	view._note_scroll_start(100.06)
	check_feq(view._scroll_duration, 0.06, "60ms 間隔で 0.06 に適応")
	view._note_scroll_start(100.12)
	check_feq(view._scroll_duration, 0.06, "60ms 間隔が続くと 0.06 のまま")
	view._note_scroll_start(101.12)
	check_feq(view._scroll_duration, 0.17, "間隔が空くと 0.17 に戻る")
	view._note_scroll_start(101.13)
	check_feq(view._scroll_duration, MapView.MIN_SCROLL_DURATION, "10ms 間隔は下限に張り付く")
	view.free()


func _initialize() -> void:
	_test_config()
	_test_repeat_due()
	_test_character_reflects_config()
	_test_scroll_duration()
	_test_scroll_adaptation()
	print("test_stage128: ", _checks, " checks, ", _failures, " failures")
	quit(1 if _failures > 0 else 0)
