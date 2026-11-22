extends SceneTree
## 第125段: りんぐ報告 (2026-11-22) の3件。
## (1) リスト表示中、入力欄にフォーカスがある時の数字キーは
##     リストの即時選択に使わず入力欄へ譲る (345 番などを打って
##     Enter で確定できる)。フォーカスが無い時は従来どおり
##     数字キーで即選択 (Philly のリストモード)。
## (2) リストとステータスパネルの文字は、地図の倍率ではなく
##     全体のフォント設定 (MenuFontSize) に追従する。設定変更が
##     倍率の変更なしでも反映されることも見る。
## (3) ログ窓 (フロート) の帯に「最下部へ」ボタンがあり、
##     フォントサイズ変更ボタンの隣に並び、押すとログが
##     一番下までスクロールする。
##
## 使い方: godot --headless --path . -s tests/test_stage125.gd
## 終了コード 0 = 全一致、1 = 不一致あり。

var _failures := 0
var _checks := 0
var _tab: PhiCharacter = null
var _config: PhiConfig = null
var _frames := 0


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
	_config = PhiConfig.new()
	_config.log_auto_save = false
	_config.ui_style = "old"
	_config.menu_font_size = 20
	var font := PhiFont.make_ui_font()
	var bold := PhiFont.make_bold_font()
	_tab = PhiCharacter.new()
	_tab.setup(GameAssets.new(), _config, font, bold, PhiLogFilter.new(), PhiTagMenu.parse(PhiTagMenu.DEFAULT_XML))
	root.add_child(_tab)
	_tab.position = Vector2.ZERO
	_tab.size = Vector2(1280, 1024)
	process_frame.connect(_on_frame)


func _key_event(keycode: Key, unicode := 0) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.keycode = keycode
	ev.physical_keycode = keycode
	ev.unicode = unicode
	ev.pressed = true
	return ev


func _queue(tab: PhiCharacter) -> Array:
	return tab.session.get("_send_queue")


func _open_list(tab: PhiCharacter) -> void:
	var lines: Array[String] = ["[ 1] apple", "[ 2] banana", "[ 3] cherry"]
	tab.set("_list_lines", lines)
	tab.set("_list_active", true)
	tab._show_list_overlay()


func _on_frame() -> void:
	_frames += 1
	if _frames == 3:
		_test_list_digit_focus()
	elif _frames == 6:
		_test_font_follow()
		_test_bottom_button_setup()
	elif _frames == 10:
		_test_bottom_button_scroll()
		print("test_stage125: ", _checks, " checks, ", _failures, " failures")
		quit(1 if _failures > 0 else 0)


# -- (1) リスト表示中の数字キー ------------------------------------------------

func _test_list_digit_focus() -> void:
	var tab := _tab
	# フォーカスが無い時: 数字キーは従来どおり即選択。
	tab.input_box.release_focus()
	_open_list(tab)
	check(tab.handle_key(_key_event(KEY_2, 0x32)), "s125 unfocused digit handled")
	check_eq(_queue(tab), ["2"], "s125 unfocused digit sends row")
	check(not tab.list_active(), "s125 list closed after unfocused digit")
	_queue(tab).clear()
	# フォーカスが無い時: 0 は従来どおりキャンセル (".")。
	_open_list(tab)
	check(tab.handle_key(_key_event(KEY_0, 0x30)), "s125 unfocused zero handled")
	check_eq(_queue(tab), ["."], "s125 unfocused zero cancels")
	_queue(tab).clear()
	# 入力欄にフォーカスがある時: 数字キーはリストに横取りされない。
	_open_list(tab)
	tab.input_box.grab_focus()
	check(tab.input_box.has_focus(), "s125 input focused")
	check(tab._list_digit_goes_to_input("Digit3"), "s125 digit goes to input when focused")
	check(tab._list_digit_goes_to_input("Digit0"), "s125 zero goes to input when focused")
	check(tab._list_digit_goes_to_input("Numpad5"), "s125 numpad goes to input when focused")
	check(not tab._list_digit_goes_to_input("ArrowDown"), "s125 arrow is not a digit")
	check(not tab.handle_key(_key_event(KEY_3, 0x33)), "s125 focused digit not handled")
	check_eq(_queue(tab), [], "s125 focused digit sends nothing")
	check(tab.list_active(), "s125 list stays open after focused digit")
	check(not tab.handle_key(_key_event(KEY_0, 0x30)), "s125 focused zero not handled")
	check_eq(_queue(tab), [], "s125 focused zero sends nothing")
	check(tab.list_active(), "s125 list stays open after focused zero")
	# Shift+数字も、フォーカス中はチェック切替に化けない。
	check(not tab.handle_key(_shift_digit_event()), "s125 focused shift digit not handled")
	check_eq(tab.list_checked_indices(), [], "s125 focused shift digit toggles nothing")
	# 複数桁を打って Enter で確定すると、その文がリストへの答えになる。
	tab.input_box.text = "345"
	tab.set("_history_boundary", 0)
	check(tab.handle_key(_key_event(KEY_ENTER)), "s125 enter submits")
	check_eq(_queue(tab), ["345"], "s125 typed number sent as answer")
	check(not tab.list_active(), "s125 list closed after typed answer")
	_queue(tab).clear()
	tab.input_box.release_focus()


func _shift_digit_event() -> InputEventKey:
	var ev := _key_event(KEY_1, 0x31)
	ev.shift_pressed = true
	return ev


# -- (2) フォント設定への追従 ---------------------------------------------------

func _test_font_follow() -> void:
	var tab := _tab
	_config.menu_font_size = 26
	tab.refresh_ui_font_size()
	var list_box := tab.get("_list_box") as ItemList
	var header := tab.get("_list_header") as Label
	var cancel := tab.get("_list_cancel_button") as Button
	check_eq(list_box.get_theme_font_size("font_size"), 26, "s125 list follows menu font")
	check_eq(header.get_theme_font_size("font_size"), 26, "s125 list header follows menu font")
	check_eq(cancel.get_theme_font_size("font_size"), 26, "s125 list cancel follows menu font")
	check_eq(int(tab.get("_list_font_size")), 26, "s125 list font size recorded")
	check_eq(tab.status_panel.gauge_font_size, 26, "s125 gauge follows menu font")
	check_eq(tab.status_panel.status_font_size, 26, "s125 status row follows menu font")
	# 倍率を変えずに設定だけ変えても追従する。
	_config.menu_font_size = 18
	tab.refresh_ui_font_size()
	check_eq(list_box.get_theme_font_size("font_size"), 18, "s125 list follows menu font change")
	check_eq(tab.status_panel.gauge_font_size, 18, "s125 gauge follows menu font change")
	# ログの文字は従来どおり倍率連動のまま (対象外)。
	check_eq(tab.log_view.get_theme_font_size("font_size"), PhiFont.ui_size_for_zoom(tab.map_view.zoom), "s125 log still follows zoom")
	_config.menu_font_size = 20
	tab.refresh_ui_font_size()


# -- (3) 最下部へボタン ----------------------------------------------------------

func _test_bottom_button_setup() -> void:
	var tab := _tab
	var button := tab.get("_log_bottom_button") as Button
	check(button != null, "s125 bottom button exists")
	if button == null:
		return
	check_eq(button.text, "最下部へ", "s125 bottom button label")
	check(not button.tooltip_text.is_empty(), "s125 bottom button has tooltip")
	# フォントサイズ変更ボタンと同じ帯の行に並んでいる。
	var band_button := tab.get("_log_band_button") as Button
	check(band_button != null and button.get_parent() == band_button.get_parent(), "s125 bottom button next to font button")
	# スクロールの確認用に、ログをたくさん流しておく。
	for i in range(120):
		tab.log_message("log", "s125 scroll line %d" % i)


func _test_bottom_button_scroll() -> void:
	var tab := _tab
	var button := tab.get("_log_bottom_button") as Button
	if button == null:
		return
	var bar := tab.log_view.get_v_scroll_bar()
	check(bar != null and bar.max_value > bar.page, "s125 log overflows")
	if bar == null:
		return
	bar.value = 0.0
	check(not tab._log_at_bottom(), "s125 log scrolled up")
	button.pressed.emit()
	check(tab._log_at_bottom(), "s125 bottom button pins to bottom")
