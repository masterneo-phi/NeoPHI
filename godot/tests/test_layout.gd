extends SceneTree
## レイアウト変更(2列化・フォント縮小・ゲージ拡大・世界名ヘッダー・
## 名前一覧の削除・コンパスの地図右下フロート化)のテスト。
## 追加分: 右列(情報欄)の廃止でログが右端まで広がること、
## コンパスがマップチップ1マス分の大きさであること、
## HP/MPバーの左端が一致すること、リストは決定ボタン無しで
## シングルクリック=選択・ダブルクリック=決定であること、
## ツールバーが地図の上に種類ごとの段で浮きドラッグで
## 動かせること、入力欄の高さを境目で変えられ保持されること、
## ログの上端と地図の上端がそろうこと、世界名ヘッダーが
## シルバーの帯であること。
##
## 使い方: godot --headless --path . -s tests/test_layout.gd
## 終了コード 0 = 全一致、1 = 不一致あり。

var _failures := 0
var _checks := 0
var _tab: PhiCharacter = null
var _config: PhiConfig = null
var _frames := 0
var _map_w_before := 0.0
var _log_w_before := 0.0


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
	_test_font_rules()
	_test_check_texture()
	_test_viewport_region()
	_test_place_text()
	_test_status_panel_sizes()
	_test_status_format_and_centering()
	_test_bar_alignment()
	# 配置の幾何学は、ツリーに入れてレイアウトが回ってから見る。
	_config = PhiConfig.new()
	var font := PhiFont.make_ui_font()
	var bold := PhiFont.make_bold_font()
	_tab = PhiCharacter.new()
	_tab.setup(GameAssets.new(), _config, font, bold, PhiLogFilter.new(), {})
	_test_structure()
	_test_log_top_label()
	_test_toolbar_structure()
	_test_compass_structure()
	_test_no_side_panel()
	_test_list_click_behavior()
	root.add_child(_tab)
	# ヘッドレスでは窓の大きさが反映されないため、タブ自体の
	# 大きさを直接付ける(配置はタブの矩形から決まる)。
	_tab.position = Vector2.ZERO
	_tab.size = Vector2(1280, 1024)
	process_frame.connect(_on_frame)


func _on_frame() -> void:
	_frames += 1
	if _frames == 3:
		_test_geometry_initial()
		_test_toolbar_drag()
		_test_input_split()
		# 境目の比率を変えて、両列が追従するか見る。
		_config.split_ratio = 0.3
		_tab._on_split_resized()
	elif _frames == 5:
		_test_geometry_after_ratio()
		_test_world_header()
		_test_input_split_applied()
		print("test_layout: ", _checks, " checks, ", _failures, " failures")
		quit(1 if _failures > 0 else 0)


func _test_font_rules() -> void:
	# 第4段からさらにもうひと回り小さい。
	_check_eq(PhiFont.ui_size_for_zoom(1), 6, "layout ui zoom1")
	_check_eq(PhiFont.ui_size_for_zoom(2), 10, "layout ui zoom2")
	_check_eq(PhiFont.ui_size_for_zoom(3), 16, "layout ui zoom3")
	_check_eq(PhiFont.ui_size_for_zoom(4), 22, "layout ui zoom4")
	# メニュー等は全部ログと同じ大きさに統一(ユーザーの要望)。
	for zoom in [1, 2, 3, 4]:
		_check_eq(PhiFont.chrome_size_for_zoom(zoom), PhiFont.ui_size_for_zoom(zoom), "layout chrome unified zoom" + str(zoom))
		_check_eq(PhiFont.gauge_size_for_zoom(zoom), PhiFont.ui_size_for_zoom(zoom), "layout gauge unified zoom" + str(zoom))
		_check_eq(PhiFont.status_size_for_zoom(zoom), PhiFont.ui_size_for_zoom(zoom), "layout status unified zoom" + str(zoom))


func _test_check_texture() -> void:
	# メニューのチェック印は文字の大きさで描かれ、中身が
	# 描かれている(テーマ標準の小さい印の差し替え)。
	var tex := UiStyle.check_texture(28)
	_check(tex != null, "check texture exists")
	_check_eq(tex.get_width(), 28, "check texture size")
	var img := tex.get_image()
	var painted := 0
	for y in img.get_height():
		for x in img.get_width():
			if img.get_pixel(x, y).a > 0.5:
				painted += 1
	_check(painted > 40, "check texture painted")
	_check(UiStyle.check_texture(28) == tex, "check texture cached")
	_check(UiStyle.check_texture(0) == null, "check texture zero")


func _test_viewport_region() -> void:
	# マップ画像の保存の切り取り範囲。等倍ではそのまま、
	# Retina(2倍)では座標も2倍になる。
	_check_eq(
		UiStyle.viewport_region(Vector2i(1280, 1024), Vector2(1280, 1024), Rect2(10, 20, 300, 200)),
		Rect2i(10, 20, 300, 200), "region 1x")
	_check_eq(
		UiStyle.viewport_region(Vector2i(2560, 2048), Vector2(1280, 1024), Rect2(10, 20, 300, 200)),
		Rect2i(20, 40, 600, 400), "region 2x")
	# 画像の外にはみ出す分は切り取られる。
	_check_eq(
		UiStyle.viewport_region(Vector2i(1280, 1024), Vector2(1280, 1024), Rect2(1200, 20, 300, 200)),
		Rect2i(1200, 20, 80, 200), "region clipped")


func _test_place_text() -> void:
	_check_eq(PhiCharacter.place_text("Test World", "Field"), "Test World / Field", "place both")
	_check_eq(PhiCharacter.place_text("Test World", ""), "Test World", "place world only")
	_check_eq(PhiCharacter.place_text("", "Field"), "Field", "place area only")
	_check_eq(PhiCharacter.place_text("", ""), "", "place empty")


func _test_status_panel_sizes() -> void:
	# 高さ = バー2本＋すきま＋ステータス行。
	_check_eq(StatusPanel.panel_height(24, 21), 99.0, "panel height zoom3")
	_check_eq(StatusPanel.panel_height(14, 14), 72.0, "panel height zoom1")
	_check(StatusPanel.panel_height(32, 28) > StatusPanel.panel_height(24, 21), "panel height grows")
	var panel := StatusPanel.new()
	panel.set_ui_sizes(24, 21)
	_check_eq(panel.gauge_font_size, 24, "panel gauge size kept")
	_check_eq(panel.status_font_size, 21, "panel status size kept")
	_check_eq(panel.custom_minimum_size.y, 99.0, "panel min height")
	panel.queue_free()


func _test_status_format_and_centering() -> void:
	# 数字は4桁表示。満たない値は0埋め、9999超はそのまま。
	_check_eq(StatusPanel.format_status_value(567), "0567", "status fmt 567")
	_check_eq(StatusPanel.format_status_value(10000), "10000", "status fmt 10000")
	_check_eq(StatusPanel.format_status_value(0), "0000", "status fmt 0")
	_check_eq(StatusPanel.format_status_value(42), "0042", "status fmt 42")
	_check_eq(StatusPanel.format_status_value(9999), "9999", "status fmt 9999")
	# EXP だけ8桁表示(ユーザーの指定)。他の項目は4桁のまま。
	_check_eq(StatusPanel.format_value_for("exp", 3), "00000003", "status fmt exp 8 digits")
	_check_eq(StatusPanel.format_value_for("exp", 123456789), "123456789", "status fmt exp over 8 digits")
	_check_eq(StatusPanel.format_value_for("gp", 3), "0003", "status fmt gp stays 4 digits")
	_check_eq(StatusPanel.format_value_for("f", 42), "0042", "status fmt f stays 4 digits")
	# バーの数字も4桁表示(現在値/最大値)。HP 行と MP 行で幅がそろい、
	# 数字が縦に整列する。9999超はそのまま出す。
	_check_eq(StatusPanel.format_bar_text(100, 100), "0100/0100", "bar fmt 100/100")
	_check_eq(StatusPanel.format_bar_text(50, 50), "0050/0050", "bar fmt 50/50")
	_check_eq(StatusPanel.format_bar_text(5, 999), "0005/0999", "bar fmt 5/999")
	_check_eq(StatusPanel.format_bar_text(0, 0), "0000/0000", "bar fmt 0/0")
	_check_eq(StatusPanel.format_bar_text(12345, 99999), "12345/99999", "bar fmt over 9999")
	_check_eq(StatusPanel.format_bar_text(100, 100).length(), StatusPanel.format_bar_text(50, 50).length(), "bar fmt widths align")
	# ステータス行の文字ラベルは項目ごとに色が付いている。
	# F=赤、W=紫、M=黄緑、C=黄色、GP=金色。どれも灰色ではない。
	var f_col := StatusPanel.status_label_color("f")
	_check(f_col.r > 0.9 and f_col.g < 0.6 and f_col.b < 0.6, "status label F red")
	var w_col := StatusPanel.status_label_color("w")
	_check(w_col.r > 0.6 and w_col.b > 0.9 and w_col.g < 0.7, "status label W purple")
	var m_col := StatusPanel.status_label_color("m")
	_check(m_col.g > 0.9 and m_col.r > 0.4 and m_col.r < 0.85 and m_col.b < 0.6, "status label M yellow-green")
	var c_col := StatusPanel.status_label_color("c")
	_check(c_col.r > 0.9 and c_col.g > 0.8 and c_col.b < 0.6, "status label C yellow")
	var gp_col := StatusPanel.status_label_color("gp")
	_check(gp_col.r > 0.9 and gp_col.g > 0.6 and gp_col.g < 0.9 and gp_col.b < 0.6, "status label GP gold")
	var label_colors := [f_col, w_col, m_col, c_col, gp_col]
	for col in label_colors:
		_check(col != Color(0.65, 0.65, 0.65), "status label not gray")
	for i in range(label_colors.size()):
		for j in range(i + 1, label_colors.size()):
			_check(label_colors[i] != label_colors[j], "status label colors distinct")
	_check_eq(StatusPanel.status_label_color("x"), Color(0.65, 0.65, 0.65), "status label unknown gray")
	# ステータス行は全体が中央寄せ。枠は5つ、重ならず、左右対称。
	var panel := StatusPanel.new()
	panel.label_font = PhiFont.make_ui_font()
	panel.bold_font = PhiFont.make_bold_font()
	panel.set_ui_sizes(18, 16)
	panel.size = Vector2(717, 99)
	panel.set_status({"f": 10, "w": 11, "m": 12, "c": 13, "gp": 567})
	var rects := panel.status_box_rects(68.0, 30.0)
	_check_eq(rects.size(), 6, "status boxes count")
	if rects.size() == 6:
		var first: Rect2 = rects[0]
		var last: Rect2 = rects[5]
		_check(absf(first.position.x - (panel.size.x - last.end.x)) < 1.5, "status row centered")
		_check(first.position.x > 0.0, "status row has left margin")
		var ordered := true
		for i in range(5):
			var a: Rect2 = rects[i]
			var b: Rect2 = rects[i + 1]
			if not (a.end.x < b.position.x and a.size.x > 0.0):
				ordered = false
		_check(ordered, "status boxes ordered no overlap")
	panel.queue_free()


func _test_log_top_label() -> void:
	# ログ列の上の帯には「Log Window」の文字が中央寄せで出る。
	# 帯の高さは世界名ヘッダーと同じ(ログ上端と地図上端の一致は
	# _test_structure 側の幾何学の確認に任せる)。
	var spacer: Variant = _tab.get("_log_top_spacer")
	_check(spacer is Label, "log top band is label")
	if spacer is Label:
		var label := spacer as Label
		_check_eq(label.text, "Log Window", "log top band text")
		_check_eq(label.horizontal_alignment, HORIZONTAL_ALIGNMENT_CENTER, "log top band centered")
		_check_eq(label.vertical_alignment, VERTICAL_ALIGNMENT_CENTER, "log top band vcentered")
		_check_eq(label.mouse_filter, Control.MOUSE_FILTER_IGNORE, "log top band mouse ignore")


func _test_bar_alignment() -> void:
	# HPバーとMPバーの左端・幅は完全に一致する。札幅は両行共通の
	# 固定幅(広い方に合わせる)なので、行ごとにずれない。
	var panel := StatusPanel.new()
	panel.label_font = PhiFont.make_ui_font()
	panel.bold_font = PhiFont.make_bold_font()
	panel.set_ui_sizes(24, 21)
	panel.size = Vector2(717, 99)
	panel.set_status({"hp": 100, "maxHp": 100, "mp": 50, "maxMp": 50})
	var rects := panel.bar_rects()
	_check_eq(rects.size(), 2, "bar rects count")
	if rects.size() == 2:
		_check_eq(rects[0].position.x, rects[1].position.x, "bar left edges match")
		_check_eq(rects[0].size.x, rects[1].size.x, "bar widths match")
		_check(rects[0].position.x > 0.0, "bar left after plate")
		_check_eq(rects[1].position.y, rects[0].size.y + StatusPanel.BAR_GAP, "bar mp below hp")
	_check(panel.plate_width(30.0) > 30.0, "plate width positive")
	panel.queue_free()


func _test_no_side_panel() -> void:
	# 右列(情報欄)は廃止。タブに side_panel は無く、スクリプトも無い。
	var has_side := false
	for p in _tab.get_property_list():
		if str(p.get("name", "")) == "side_panel":
			has_side = true
	_check(not has_side, "layout no side panel property")
	_check(not ResourceLoader.exists("res://scripts/side_panel.gd"), "layout side panel file gone")


func _test_list_click_behavior() -> void:
	# リスト: 決定ボタンは無い(残るのはキャンセルだけ)。
	# シングルクリックは選択だけで送信せず、ダブルクリックで送信。
	var tab := _tab
	var lines: Array[String] = ["[ 1] wizard eye", "[ 2] cure", "[ 3] harm"]
	tab.set("_list_lines", lines)
	tab.set("_list_active", true)
	tab._show_list_overlay()
	var panel := tab.get("_list_panel") as PanelContainer
	var box := tab.get("_list_box") as ItemList
	_check(panel.visible, "list overlay shown")
	var has_ok := false
	for p in tab.get_property_list():
		if str(p.get("name", "")) == "_list_ok_button":
			has_ok = true
	_check(not has_ok, "list no ok button property")
	var buttons := panel.find_children("", "Button", true, false)
	_check_eq(buttons.size(), 1, "list buttons count")
	if buttons.size() == 1:
		_check_eq((buttons[0] as Button).text, "キャンセル", "list only cancel button")
	# シングルクリック(選択)では送信されない。
	box.select(1)
	box.item_clicked.emit(1, Vector2.ZERO, MOUSE_BUTTON_LEFT)
	_check_eq(Array(box.get_selected_items()), [1], "list click selects row")
	_check_eq((tab.session.get("_send_queue") as Array).size(), 0, "list single click no send")
	_check(panel.visible, "list overlay stays after click")
	# ダブルクリック(activated)で、その行の番号が送信される。
	box.item_activated.emit(1)
	var queue: Array = tab.session.get("_send_queue")
	_check_eq(queue.size(), 1, "list double click sends")
	if queue.size() == 1:
		_check_eq(str(queue[0]), "2", "list double click sends number")
	_check(not panel.visible, "list overlay hides after send")
	_check(not bool(tab.get("_list_active")), "list inactive after send")


func _test_structure() -> void:
	# 左列: 世界名ヘッダー→地図→状態パネル、同じ VBox の子。
	var left := _tab.map_view.get_parent()
	_check_eq(_tab.world_header.get_parent(), left, "layout header same column as map")
	_check_eq(_tab.status_panel.get_parent(), left, "layout status same column as map")
	_check(left.get_child_count() == 3, "layout left column 3 children")
	_check_eq(left.get_child(0), _tab.world_header, "layout header first")
	_check_eq(left.get_child(1), _tab.map_view, "layout map second")
	_check_eq(left.get_child(2), _tab.status_panel, "layout status third")
	# 世界名ヘッダーはシルバーの帯で、文字は濃い色。帯は角丸。
	var band := _tab.world_header.get_theme_stylebox("normal") as StyleBoxFlat
	_check(band != null, "layout header has band")
	if band != null:
		_check_eq(band.bg_color, PhiCharacter.WORLD_HEADER_BG, "layout header silver band")
		_check_eq(band.corner_radius_top_left, UiStyle.CORNER_RADIUS, "layout header band rounded")
	_check(_tab.world_header.get_theme_color("font_color").r < 0.3, "layout header dark text")
	# 境目は金属スリットの分割(ドラッグは従来どおり)。
	_check(_tab.split is MetalHSplit, "layout h split is metal slit")
	_check(_tab.input_split is MetalVSplit, "layout v split is metal slit")
	# 入力欄の枠は角丸。
	var input_style := _tab.input_box.get_theme_stylebox("normal") as StyleBoxFlat
	_check(input_style != null and input_style.corner_radius_top_left == UiStyle.CORNER_RADIUS, "layout input rounded")
	# 右列: 余白→上下分割(ログ→入力欄)。固定のヒント表示は無い。
	var right := _tab.input_split.get_parent()
	_check_eq(_tab.split.get_child(1), right, "layout split right is log column")
	_check(right.get_child_count() == 2, "layout right column 2 children")
	_check_eq(right.get_child(0), _tab.get("_log_top_spacer"), "layout log spacer first")
	_check_eq(right.get_child(1), _tab.input_split, "layout input split second")
	_check_eq(_tab.log_view.get_parent(), _tab.input_split, "layout log in input split")
	_check_eq(_tab.input_box.get_parent(), _tab.input_split, "layout input in input split")
	_check_eq(_tab.input_split.get_child(0), _tab.log_view, "layout log first in split")
	_check_eq(_tab.input_split.get_child(1), _tab.input_box, "layout input second in split")
	var has_hint := false
	for child in _tab.input_split.get_children():
		if child is Label:
			has_hint = true
	_check(not has_hint, "layout no hint label")
	# 境目の両側が2列。
	_check_eq(_tab.split.get_child(0), left, "layout split left is map column")
	# 右列は無い。境目がタブの直接の子で、幅いっぱいに広がる。
	_check_eq(_tab.split.get_parent(), _tab, "layout split direct child")


func _test_toolbar_structure() -> void:
	# ツールバーは地図の上に浮くパネルで、種類(区切り)ごとに
	# 段が分かれている。既定の位置は地図の左上。
	var panel := _tab.get("_toolbar_panel") as PanelContainer
	_check(panel != null, "layout toolbar panel exists")
	if panel == null:
		return
	_check_eq(panel.get_parent(), _tab.map_view, "layout toolbar floats on map")
	_check_eq(panel.position, Vector2(8, 8), "layout toolbar default position")
	# パネルの地は角丸。
	var panel_box := panel.get_theme_stylebox("panel") as StyleBoxFlat
	_check(panel_box != null and panel_box.corner_radius_top_left == UiStyle.FLOAT_RADIUS, "layout toolbar panel rounded")
	var buttons := _tab.get("_toolbar_buttons") as Array
	_check_eq(buttons.size(), 22, "layout toolbar button count")
	var rows := panel.get_child(0) as VBoxContainer
	_check(rows != null, "layout toolbar rows box")
	if rows == null:
		return
	# 一番上は題名「Command Pallet」、その下にボタンの段が5つ。
	_check_eq(rows.get_child_count(), 6, "layout toolbar row count with title")
	var title := rows.get_child(0) as Label
	_check(title != null and title.text == "Command Pallet", "layout toolbar title text")
	_check(title != null and title.get_theme_font_size("font_size") == PhiFont.ui_size_for_zoom(_tab.map_view.zoom), "layout toolbar title font size")
	var want := [2, 8, 5, 6, 1]
	for i in 5:
		_check_eq(rows.get_child(i + 1).get_child_count(), want[i], "layout toolbar row " + str(i) + " size")
	# 大声ボタンはトグル。ボタンは UI 文字サイズに追従する。
	var size := PhiFont.ui_size_for_zoom(_tab.map_view.zoom)
	for b in buttons:
		var button := b as Button
		if str(button.get_meta("action")) == "Loud":
			_check(button.toggle_mode, "layout toolbar loud toggle")
		_check_eq(button.get_theme_font_size("font_size"), size, "layout toolbar button font size")
	# アイコンが無い環境では文字ボタンになり、高さは size + 12。
	var first := buttons[0] as Button
	_check_eq(first.custom_minimum_size, Vector2(0, size + 12), "layout toolbar button min size")


func _test_toolbar_drag() -> void:
	# パネルの地のドラッグで位置が変わり、離すと設定に残る。
	var panel := _tab.get("_toolbar_panel") as PanelContainer
	_check_eq(panel.position, Vector2(8, 8), "layout toolbar starts top left")
	# スキンの無い環境では文字ボタンでパネルが地図より広くなる
	# ため、アイコン付きボタンの寸法(34px四方)に寄せてから
	# ドラッグする(リストのドラッグ確認と同じ流儀)。
	for b in _tab.get("_toolbar_buttons"):
		var button := b as Button
		button.text = ""
		button.custom_minimum_size = Vector2(34, 34)
	_tab._fit_toolbar_panel()
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = panel.global_position + Vector2(4, 4)
	press.global_position = press.position
	_tab._on_toolbar_panel_gui_input(press)
	_check(bool(_tab.get("_toolbar_dragging")), "layout toolbar drag starts")
	var motion := InputEventMouseMotion.new()
	motion.position = press.position + Vector2(120, 80)
	motion.global_position = motion.position
	_tab.handle_mouse_motion(motion)
	_check_eq(panel.position, Vector2(128, 88), "layout toolbar drag moves")
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.position = motion.position
	release.global_position = motion.position
	_tab.handle_mouse_button(release)
	_check(not bool(_tab.get("_toolbar_dragging")), "layout toolbar drag stops")
	_check_eq(_config.toolbar_pos, Vector2(128, 88), "layout toolbar position kept")
	# 別のタブを作ると、保持した位置から始まる。
	var tab2 := PhiCharacter.new()
	tab2.setup(GameAssets.new(), _config, PhiFont.make_ui_font(), PhiFont.make_bold_font(), PhiLogFilter.new(), {})
	var panel2 := tab2.get("_toolbar_panel") as PanelContainer
	_check(panel2 != null, "layout toolbar second panel exists")
	if panel2 != null:
		_check_eq(panel2.position, Vector2(128, 88), "layout toolbar position restored")
	tab2.free()
	# ボタンを押すと、アクションのシグナルが届く。
	var got: Array = []
	_tab.action_requested.connect(func(name: String) -> void: got.append(name))
	var open_button: Button = null
	for b in _tab.get("_toolbar_buttons"):
		if str((b as Button).get_meta("action")) == "Open":
			open_button = b
	_check(open_button != null, "layout toolbar open button")
	if open_button != null:
		open_button.pressed.emit()
	_check(got.size() == 1 and str(got[0]) == "Open", "layout toolbar action signal")


func _test_input_split() -> void:
	# ログと入力欄の上下分割。既定では入力欄は3行ぶんの高さ。
	var split := _tab.input_split
	_check(split != null, "layout input split exists")
	if split == null:
		return
	_check(absf(_tab.input_box.size.y - float(_tab._default_input_height())) < 2.0, "layout input default height")
	# 境目をドラッグすると、決まった高さが設定に残る。
	var total := split.size.y
	var sep := _tab._input_split_gap()
	var off := split.split_offset - 40
	_tab._on_input_split_dragged(off)
	_check_eq(_config.input_height, int(round(total - sep - float(off))), "layout input height kept")
	# 保持した高さを適用する(反映は次のフレームで見る)。
	_config.input_height = 200
	_tab._apply_input_height()


func _test_input_split_applied() -> void:
	_check(absf(_tab.input_box.size.y - 200.0) < 2.0, "layout input height applied")
	# 大きすぎる値は、ログの最小の高さを残すところで止まる。
	_config.input_height = 100000
	_tab._apply_input_height()
	_check_eq(_tab.input_split.split_offset, PhiCharacter.MIN_LOG_HEIGHT, "layout input clamps to log min")
	# 小さすぎる値は、入力欄の最小の高さで止まる。
	_config.input_height = 1
	_tab._apply_input_height()
	var total := _tab.input_split.size.y
	var sep := _tab._input_split_gap()
	_check_eq(_tab.input_split.split_offset, int(round(total - sep - float(_tab._min_input_height()))), "layout input clamps to input min")
	_config.input_height = -1
	_tab._apply_input_height()


func _test_compass_structure() -> void:
	# コンパスは地図の子として右下に浮き、半透明で、マウスを通す。
	var compass := _tab.map_view.compass
	_check(compass != null, "layout compass exists")
	if compass == null:
		return
	_check_eq(compass.get_parent(), _tab.map_view, "layout compass is map child")
	_check(compass.mouse_filter == Control.MOUSE_FILTER_IGNORE, "layout compass ignores mouse")
	_check(compass.modulate.a < 1.0, "layout compass translucent")
	_check(absf(compass.modulate.a - MapView.COMPASS_ALPHA) < 0.001, "layout compass alpha value")
	# 地図が届くまでは隠れている。
	_check(not compass.visible, "layout compass hidden before map")
	# 大きさはマップチップ1マス分(32px×ズーム)。生成直後は
	# 既定のズーム4なので 128px 四方。
	_check_eq(compass.custom_minimum_size, Vector2(32.0 * _tab.map_view.zoom, 32.0 * _tab.map_view.zoom), "layout compass one cell size")
	# 向きの受け渡しは地図経由。
	_tab.map_view.set_compass_direction(2, false)
	_check_eq(compass.dir_num, 2, "layout compass direction set")
	_check_eq(compass.north_fix, false, "layout compass north flag set")
	_tab.map_view.set_compass_direction(0, true)
	_check_eq(compass.dir_num, 0, "layout compass direction reset")
	_check_eq(compass.north_fix, true, "layout compass north flag reset")


func _test_geometry_initial() -> void:
	var map_view := _tab.map_view
	var status := _tab.status_panel
	var log_view := _tab.log_view
	var input_box := _tab.input_box
	var header := _tab.world_header
	# 状態パネルは地図の下にあり、幅は地図の列と同じ。
	_check(status.global_position.y >= map_view.global_position.y + map_view.size.y - 1.0, "layout status below map")
	_check_eq(status.size.x, map_view.size.x, "layout status width matches map")
	# 入力欄はログの下にあり、幅はログ列と同期する。
	_check(input_box.global_position.y >= log_view.global_position.y + log_view.size.y - 1.0, "layout input below log")
	_check_eq(input_box.size.x, log_view.size.x, "layout input width matches log")
	# 世界名ヘッダーは地図の上にあり、幅は地図の列と同じ。
	_check(header.global_position.y + header.size.y <= map_view.global_position.y + 1.0, "layout header above map")
	_check_eq(header.size.x, map_view.size.x, "layout header width matches map")
	# ログの上端と地図の上端がそろう(ログ列の上に、世界名
	# ヘッダーと同じ高さの余白があるため)。
	_check(absf(log_view.global_position.y - map_view.global_position.y) < 1.0, "layout log top aligns map top")
	# 既定の比率 0.62 で、地図列の方が広い。
	_check(map_view.size.x > log_view.size.x, "layout map wider than log at 0.62")
	# コンパスは地図の右下に重なる(地図の矩形の内側、右下の隅)。
	var compass := map_view.compass
	var crect := compass.get_global_rect()
	var mrect := map_view.get_global_rect()
	_check(crect.position.x >= mrect.position.x + mrect.size.x * 0.5, "layout compass right half")
	_check(crect.position.y >= mrect.position.y + mrect.size.y * 0.5, "layout compass bottom half")
	_check(absf(crect.end.x - (mrect.end.x - MapView.COMPASS_MARGIN)) < 2.0, "layout compass right edge")
	_check(absf(crect.end.y - (mrect.end.y - MapView.COMPASS_MARGIN)) < 2.0, "layout compass bottom edge")
	_check(crect.size.x > 30.0 and crect.size.y > 30.0, "layout compass has size")
	# レイアウト後も、コンパスは1マス分(32px×今のズーム)。
	_check(absf(crect.size.x - 32.0 * map_view.zoom) < 2.0, "layout compass cell width after layout")
	_check(absf(crect.size.y - 32.0 * map_view.zoom) < 2.0, "layout compass cell height after layout")
	# 右列が無いので、ログと入力欄がタブの右端まで届く。
	_check(absf(log_view.global_position.x + log_view.size.x - 1280.0) < 3.0, "layout log reaches right edge")
	_check(absf(input_box.global_position.x + input_box.size.x - 1280.0) < 3.0, "layout input reaches right edge")
	_map_w_before = map_view.size.x
	_log_w_before = log_view.size.x


func _test_geometry_after_ratio() -> void:
	# 比率を 0.3 にしたら、地図列が狭くなりログ列が広くなる。
	_check(_tab.map_view.size.x < _map_w_before - 10.0, "layout ratio shrinks map column")
	_check(_tab.log_view.size.x > _log_w_before + 10.0, "layout ratio widens log column")
	# 追従後も、状態パネルは地図列の幅、入力欄はログ列の幅。
	_check_eq(_tab.status_panel.size.x, _tab.map_view.size.x, "layout status follows ratio")
	_check_eq(_tab.input_box.size.x, _tab.log_view.size.x, "layout input follows ratio")


func _test_world_header() -> void:
	_tab.set("_world", "Test World")
	_tab.set("_area", "Field")
	_tab.set("_player_name", "Guest")
	_tab._update_side_info()
	_check_eq(_tab.world_header.text, "Test World / Field", "layout header shows world")
	# ヘッダーには世界名・エリア名だけ。キャラ名や接続先は出さない
	# (右列の情報欄は廃止した)。
	_check(not _tab.world_header.text.contains("Guest"), "layout header has no player")
	_check(not _tab.world_header.text.contains("127.0.0.1"), "layout header has no conn")
	# 未接続の時は空欄。
	_tab.set("_world", "")
	_tab.set("_area", "")
	_tab._update_side_info()
	_check_eq(_tab.world_header.text, "", "layout header empty when offline")
