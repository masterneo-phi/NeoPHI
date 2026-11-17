class_name PhiCharaViewer
extends Window
## キャラグラ確認モード (ツール)。キャラ名の一覧から選んで、
## シート全体 (4方向×大小フレーム) と歩行アニメーションを見る。
##
## テーマと transparent は生成側 (main) が当てる。

var title_font: Font = null
var title_size := 20
var body_font: Font = null

var _title_label: Label = null
var _filter_edit: LineEdit = null
var _list: ItemList = null
var _view: SheetView = null
var _assets: GameAssets = null
var _names: Array[String] = []
var _shown: Array[String] = []


class SheetView:
	extends Control
	## シート全体と、下段に4方向の歩行アニメーションを描く。
	var texture: Texture2D = null
	var font: Font = null
	var frame := 0

	const SCALE := 3
	const DIRS := ["B", "R", "F", "L"]

	func _ready() -> void:
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		custom_minimum_size = Vector2(34 + 4 * 32 * SCALE + 3 * 18 + 12,
			22 + 128 * SCALE + 26 + 2 * (32 * SCALE) + 96)

	func set_texture(p_texture: Texture2D) -> void:
		texture = p_texture
		queue_redraw()

	func tick() -> void:
		frame = (frame + 1) & 1
		queue_redraw()

	func _draw() -> void:
		if texture == null:
			if font != null:
				draw_string(font, Vector2(8, 24), "画像が読めません", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 0.6, 0.6))
			return
		# シート全体 (96x128)。左に行ラベル (方向)、上に列ラベル。
		if font != null:
			var col_labels := ["小1", "小2", "大1", "大2"]
			var col_x := [0, 16, 32, 64]
			var col_w := [16, 16, 32, 32]
			for c in range(4):
				draw_string(font, Vector2(34 + col_x[c] * SCALE + col_w[c], 14), col_labels[c], HORIZONTAL_ALIGNMENT_CENTER, -1, 12, Color(0.85, 0.85, 0.85))
			for r in range(4):
				draw_string(font, Vector2(16, 34 + r * 32 * SCALE + 18), DIRS[r], HORIZONTAL_ALIGNMENT_CENTER, -1, 14, Color(0.85, 0.85, 0.85))
		var sheet_dest := Rect2(34, 22, 96 * SCALE, 128 * SCALE)
		draw_texture_rect_region(texture, sheet_dest, Rect2(0, 0, 96, 128))
		draw_rect(sheet_dest, Color(1, 1, 1, 0.25), false, 1.0)
		for r in range(1, 4):
			var y := 22.0 + r * 32 * SCALE
			draw_line(Vector2(34, y), Vector2(34 + 96 * SCALE, y), Color(1, 1, 1, 0.18), 1.0)
		# 歩行アニメーション (小フレーム、4方向)。
		var anim_y := 22.0 + 128 * SCALE + 26
		if font != null:
			draw_string(font, Vector2(34, anim_y - 8), "歩行・小", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.85, 0.85, 0.85))
		for r in range(4):
			var src := Rect2(frame * 16, r * 32, 16, 32)
			var dest := Rect2(34 + r * (16 * SCALE + 18), anim_y, 16 * SCALE, 32 * SCALE)
			draw_texture_rect_region(texture, dest, src)
			if font != null:
				draw_string(font, dest.position + Vector2(24, dest.size.y + 14), DIRS[r], HORIZONTAL_ALIGNMENT_CENTER, -1, 12, Color(0.85, 0.85, 0.85))
		# 歩行アニメーション (大フレーム、4方向)。シートの
		# 大1 = x32、大2 = x64 (幅 32)。
		var big_y := anim_y + 32 * SCALE + 44
		if font != null:
			draw_string(font, Vector2(34, big_y - 8), "歩行・大", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.85, 0.85, 0.85))
		for r in range(4):
			var src := Rect2(32 + frame * 32, r * 32, 32, 32)
			var dest := Rect2(34 + r * (32 * SCALE + 18), big_y, 32 * SCALE, 32 * SCALE)
			draw_texture_rect_region(texture, dest, src)
			if font != null:
				draw_string(font, dest.position + Vector2(48, dest.size.y + 14), DIRS[r], HORIZONTAL_ALIGNMENT_CENTER, -1, 12, Color(0.85, 0.85, 0.85))


func _init() -> void:
	title = ""
	visible = false
	_build()


func setup(assets: GameAssets, names: Array) -> void:
	_assets = assets
	_names.clear()
	for name in names:
		_names.append(str(name))
	_apply_filter("")


func show_viewer() -> void:
	if title_font != null and _title_label != null:
		_title_label.add_theme_font_override("font", title_font)
		_title_label.add_theme_font_size_override("font_size", title_size)
	_view.font = body_font
	if visible:
		grab_focus()
		return
	popup_centered(UiStyle.fit_popup_size(Vector2i(780, 800), get_tree().root.size))


func _apply_filter(text: String) -> void:
	_shown.clear()
	var needle := text.strip_edges().to_lower()
	for name in _names:
		if needle.is_empty() or name.to_lower().contains(needle):
			_shown.append(name)
	_list.clear()
	for name in _shown:
		_list.add_item(name)
	if not _shown.is_empty():
		_list.select(0)
		_show_chara(_shown[0])
	else:
		_view.set_texture(null)


func _show_chara(chara_name: String) -> void:
	if _assets == null:
		return
	var tex: Variant = _assets.chara(chara_name, chara_name, 0x40)
	_view.set_texture(tex)


func _build() -> void:
	var frame := UiStyle.window_frame()
	frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(frame)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	frame.add_child(box)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 6)
	box.add_child(UiStyle.title_band(head))
	_title_label = Label.new()
	_title_label.text = "キャラグラ確認"
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	head.add_child(_title_label)
	var close_button := Button.new()
	close_button.text = "×"
	close_button.focus_mode = Control.FOCUS_NONE
	UiStyle.apply_metal_button(close_button)
	close_button.pressed.connect(func() -> void: hide())
	head.add_child(close_button)
	PhiWindowDrag.attach(head, self)
	var split := HBoxContainer.new()
	split.add_theme_constant_override("separation", 6)
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(split)
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(210, 0)
	split.add_child(left)
	_filter_edit = LineEdit.new()
	_filter_edit.placeholder_text = "名前で絞り込み"
	_filter_edit.text_changed.connect(_apply_filter)
	left.add_child(_filter_edit)
	_list = ItemList.new()
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.item_selected.connect(func(index: int) -> void:
		if index >= 0 and index < _shown.size():
			_show_chara(_shown[index]))
	left.add_child(_list)
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_child(scroll)
	_view = SheetView.new()
	scroll.add_child(_view)
	var timer := Timer.new()
	timer.wait_time = 0.28
	timer.autostart = true
	timer.timeout.connect(func() -> void:
		if visible:
			_view.tick())
	add_child(timer)
	close_requested.connect(func() -> void: hide())
