extends SceneTree
## 第10段のテスト: ウィンドウのフロート化(半透過+金属ボタン+
## 題名の自前表示)、新規作成のテクスチャ枠、Unew の初期サイズ、
## 地図モードのラジオチェック、コンパスの様式表示。
##
## 使い方: godot --headless --path . -s tests/test_stage10.gd
## 終了コード 0 = 全一致、1 = 不一致あり。

var _failures := 0
var _checks := 0
var _frames := 0
var _main: Node = null


func _check(cond: bool, label: String) -> void:
	_checks += 1
	if not cond:
		_failures += 1
		printerr("FAIL: ", label)


func _check_eq(a: Variant, b: Variant, label: String) -> void:
	_checks += 1
	if a != b:
		_failures += 1
		printerr("FAIL: ", label, " (got ", a, ", want ", b, ")")


func _initialize() -> void:
	_test_ui_style()
	_test_compass_mode()
	_test_unew_panel()
	_test_priv_window()
	var ps := load("res://main.tscn") as PackedScene
	_main = ps.instantiate()
	root.add_child(_main)
	process_frame.connect(_on_frame)


func _on_frame() -> void:
	_frames += 1
	if _frames == 5:
		_test_main_windows()
		print("test_stage10: ", _checks, " checks, ", _failures, " failures")
		quit(1 if _failures > 0 else 0)


func _test_ui_style() -> void:
	var plate := UiStyle.window_plate_stylebox()
	_check(absf(plate.bg_color.a - 0.88) < 0.01, "window plate is translucent")
	_check_eq(plate.corner_radius_top_left, UiStyle.FLOAT_RADIUS, "window plate radius")
	var normal := UiStyle.metal_button_stylebox("normal")
	_check(normal is StyleBoxTexture, "metal button normal is texture")
	var pressed := UiStyle.metal_button_stylebox("pressed")
	_check(pressed is StyleBoxTexture and (pressed as StyleBoxTexture).modulate_color.r < 0.9, "metal button pressed darker")
	var disabled := UiStyle.metal_button_stylebox("disabled")
	_check(disabled is StyleBoxTexture and (disabled as StyleBoxTexture).modulate_color.a < 0.8, "metal button disabled faded")
	_check(UiStyle.metal_button_font_color("normal").r < 0.3, "metal button font dark")
	_check(UiStyle.metal_button_font_color("disabled").r > 0.3, "metal button disabled font gray")


func _test_compass_mode() -> void:
	var compass := CompassView.new()
	_check_eq(compass.mode_text(), "北固定", "compass default mode text")
	compass.set_mode_style("turn")
	_check_eq(compass.mode_text(), "回転", "compass turn mode text")
	compass.set_mode_style("solid")
	_check_eq(compass.mode_text(), "北固定", "compass solid mode text")
	var mv := MapView.new()
	mv.label_font = ThemeDB.fallback_font
	mv.bold_font = ThemeDB.fallback_font
	mv.set_compass_mode_style("turn")
	_check_eq(mv.compass.mode_style, "turn", "map view delegates mode style")
	# 様式表示は MapView のオーバーレイ(太字+縁取りのラベル)が担う。
	# 本体は半透明なので、中に描くと薄れて読みにくいため。
	var mode_label: Label = mv.get("_compass_mode_label")
	_check(mode_label != null, "compass overlay label exists")
	_check_eq(mode_label.text, "回転", "compass overlay label text")
	_check(mode_label.get_theme_font("font") == ThemeDB.fallback_font, "compass overlay uses bold font slot")
	_check_eq(mode_label.get_theme_color("font_color"), Color.WHITE, "compass overlay font white")
	_check(mode_label.get_theme_constant("outline_size") >= 2, "compass overlay has outline")
	mv.compass.visible = true
	_check(mode_label.visible, "compass overlay follows compass visibility (show)")
	_check((mv.get("_compass_mode_plate") as Control).visible, "compass overlay plate follows visibility")
	mv.compass.visible = false
	_check(not mode_label.visible, "compass overlay follows compass visibility (hide)")
	mv.free()
	compass.free()


func _test_unew_panel() -> void:
	var panel := PhiUnewPanel.new([])
	_check_eq(panel.title, "", "unew title empty (in-content title)")
	_check_eq(panel.min_size, Vector2i(640, 460), "unew min size")
	var found := false
	for label in _find_labels(panel):
		if (label as Label).text == "キャラグラとマップチップを取得する":
			found = true
			_check_eq((label as Label).get_theme_font_size("font_size"), 16, "unew title font size = body size")
	_check(found, "unew has in-content title label")
	# 行のレイアウト: 横スクロール無効+ラベル省略で、右端の
	# 取得ボタンが常に画面内に入る(ユーザーの報告を受けて)。
	panel.set("_items", [{"title": "マップチップ(Tofup)", "date": "Sat, 09 Jan 2010 16:45:14 GMT", "url": "http://example.com/chip_tofup.lzh", "dest_dir": "chip"}])
	panel.call("_rebuild_rows")
	var list_box: VBoxContainer = panel.get("_list_box")
	_check_eq(list_box.get_child_count(), 1, "unew row built")
	var row_box := list_box.get_child(0) as HBoxContainer
	_check(row_box.get_child(row_box.get_child_count() - 1) is Button, "unew row last child is the fetch button")
	var date_label := row_box.get_child(1) as Label
	_check_eq(date_label.text_overrun_behavior, TextServer.OVERRUN_TRIM_ELLIPSIS, "unew date label trims with ellipsis")
	var scroll := _find_scroll(panel)
	_check(scroll != null and scroll.horizontal_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED, "unew horizontal scroll disabled")
	panel.free()


func _find_scroll(node: Node) -> ScrollContainer:
	for c in node.get_children():
		if c is ScrollContainer:
			return c as ScrollContainer
		var found_scroll := _find_scroll(c)
		if found_scroll != null:
			return found_scroll
	return null


func _test_priv_window() -> void:
	var win := PhiPrivWindow.new()
	_check_eq(win.title, "", "priv title empty (in-content title)")
	win.update_title()
	_check_eq(win._title_label.text, "宛先がありません", "priv title label default")
	win.free()


func _find_labels(node: Node) -> Array:
	var out: Array = []
	for c in node.get_children():
		if c is Label:
			out.append(c)
		out.append_array(_find_labels(c))
	return out


func _test_main_windows() -> void:
	# ダイアログテーマ: 地は半透過、ボタンは金属プレート。
	var theme: Theme = _main._dialog_theme()
	var panel := theme.get_stylebox("panel", "AcceptDialog") as StyleBoxFlat
	_check(panel != null and absf(panel.bg_color.a - 0.88) < 0.01, "dialog panel translucent")
	_check(theme.get_stylebox("normal", "Button") is StyleBoxTexture, "dialog buttons metal")
	# 新規作成: 題名は窓に持たず、中身のテクスチャ枠+金題名で出す。
	_main._build_register_dialog()
	var dlg: ConfirmationDialog = _main._register_dialog
	_check_eq(dlg.title, "", "register dialog title empty")
	var frame_found := false
	var gold_title := false
	for c in dlg.get_children():
		if c is PanelContainer:
			frame_found = (c as PanelContainer).get_theme_stylebox("panel") is StyleBoxTexture
	for label in _find_labels(dlg):
		if (label as Label).text == "PHIキャラクターの新規作成":
			gold_title = (label as Label).get_theme_color("font_color") == Color(0.96, 0.89, 0.70)
	_check(frame_found, "register has texture frame")
	_check(gold_title, "register has gold in-content title")
	# 表示メニュー: 地図モードはラジオチェックで、設定に追随する。
	var popup: PopupMenu = _main._map_mode_popup
	_check(popup != null, "map mode popup found")
	if popup != null:
		_check(popup.is_item_radio_checkable(_main._m5_item), "M5x5 is radio checkable")
		_check(popup.is_item_radio_checkable(_main._msolid_item), "MSolid is radio checkable")
		_main._config.map_size = 40
		_main._config.map_style = "turn"
		_main._update_action_states()
		_check(popup.is_item_checked(_main._m5_item), "M5x5 checked when size 40")
		_check(not popup.is_item_checked(_main._m7_item), "M7x7 unchecked when size 40")
		_check(popup.is_item_checked(_main._mturn_item), "MTurn checked when turn")
		_check(not popup.is_item_checked(_main._msolid_item), "MSolid unchecked when turn")
		_main._config.map_size = 57
		_main._config.map_style = "solid"
		_main._update_action_states()
		_check(popup.is_item_checked(_main._m7_item), "M7x7 checked when size 57")
		_check(popup.is_item_checked(_main._msolid_item), "MSolid checked when solid")
	# バージョン情報: Mac 実機で AcceptDialog が開かない事象が
	# あったため、通常の Window で出す。
	_main._show_about()
	var about_win: Window = _main.get("_about_dialog")
	_check(about_win != null and not (about_win is AcceptDialog), "about is a plain Window")
	_check(about_win.visible, "about window shows")
	# 埋め込み窓の地は透明にしておく。Mac では地が黒で塗られ、
	# 角丸の外側が四角く黒く見える事象があったため。
	_check(about_win.transparent, "about window transparent background")
	var about_title_found := false
	for label in _find_labels(about_win):
		if (label as Label).text == "バージョン情報":
			about_title_found = true
	_check(about_title_found, "about has in-content title")
	about_win.hide()
	_main._ask_text("Pay")
	var ask_dlg: Window = _main.get("_ask_dialog")
	_check(ask_dlg != null and ask_dlg.transparent, "ask dialog transparent background")
	ask_dlg.hide()
