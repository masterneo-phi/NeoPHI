class_name PhiChipViewer
extends Window
## マップチップ確認モード (ツール)。マップセットのシートを
## 指数と対応文字つきで一覧する。アイテムシートも選べる。
##
## テーマと transparent は生成側 (main) が当てる。

var title_font: Font = null
var title_size := 20
var body_font: Font = null

var _title_label: Label = null
var _picker: OptionButton = null
var _view: SheetView = null
var _assets: GameAssets = null
var _mapsets: Array[String] = []


class SheetView:
	extends Control
	## シートを拡大して描き、各セルに番号と対応文字を重ねる。
	var texture: Texture2D = null
	var cell := Vector2i(32, 48)
	var cols := 16
	var labels: Array = [] # index -> String (2行目に出す文字)
	var font: Font = null
	var scale_factor := 2

	func _ready() -> void:
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

	func set_sheet(p_texture: Texture2D, p_cell: Vector2i, p_cols: int, p_labels: Array) -> void:
		texture = p_texture
		cell = p_cell
		cols = p_cols
		labels = p_labels
		if texture != null:
			var rows := int(texture.get_height()) / cell.y
			custom_minimum_size = Vector2(cols * cell.x * scale_factor, rows * cell.y * scale_factor)
		else:
			custom_minimum_size = Vector2(320, 120)
		queue_redraw()

	func _draw() -> void:
		if texture == null:
			if font != null:
				draw_string(font, Vector2(8, 24), "画像が読めません", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 0.6, 0.6))
			return
		var rows := int(texture.get_height()) / cell.y
		var count := cols * rows
		for i in range(count):
			var sx := (i % cols) * cell.x
			var sy := (i / cols) * cell.y
			var dest := Rect2((i % cols) * cell.x * scale_factor, (i / cols) * cell.y * scale_factor, cell.x * scale_factor, cell.y * scale_factor)
			draw_texture_rect_region(texture, dest, Rect2(sx, sy, cell.x, cell.y))
			draw_rect(dest, Color(1, 1, 1, 0.25), false, 1.0)
			if font != null:
				var text_col := Color(1, 1, 0.6)
				draw_string(font, dest.position + Vector2(3, 13), str(i), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, text_col)
				if i < labels.size() and not str(labels[i]).is_empty():
					draw_string(font, dest.position + Vector2(3, dest.size.y - 4), str(labels[i]), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.7, 0.9, 1.0))


func _init() -> void:
	title = ""
	visible = false
	_build()


func setup(assets: GameAssets, mapsets: Array, current_mapset: String) -> void:
	## 資材とマップセット名の一覧を受け取る。
	_assets = assets
	_mapsets.clear()
	for name in mapsets:
		_mapsets.append(str(name))
	_picker.clear()
	for name in _mapsets:
		_picker.add_item(name)
	_picker.add_item("Items (アイテム)")
	var select := 0
	for i in range(_mapsets.size()):
		if _mapsets[i] == current_mapset:
			select = i
			break
	_picker.select(select)
	_apply_selection(select)


func show_viewer() -> void:
	if title_font != null and _title_label != null:
		_title_label.add_theme_font_override("font", title_font)
		_title_label.add_theme_font_size_override("font_size", title_size)
	_view.font = body_font
	if visible:
		grab_focus()
		return
	popup_centered(UiStyle.fit_popup_size(Vector2i(880, 420), get_tree().root.size))


func _apply_selection(index: int) -> void:
	if _assets == null:
		return
	if index >= _mapsets.size():
		# アイテムシート (32x32 の並び、番号のみ)。
		var tex: Variant = _assets.items()
		_view.set_sheet(tex, Vector2i(32, 32), 16, [])
		return
	var tex: Variant = _assets.chip(_mapsets[index])
	# 番号 → 対応する文字 (サーバが送るチップ文字) を逆引きする。
	var labels: Array = []
	labels.resize(MapView.CHIP_COUNT)
	for i in range(labels.size()):
		labels[i] = ""
	for byte_value in MapView.CHIP_BYTE_TO_INDEX:
		for idx in MapView.CHIP_BYTE_TO_INDEX[byte_value]:
			if int(idx) < labels.size():
				labels[int(idx)] = (str(labels[int(idx)]) + " " + char(byte_value)).strip_edges()
	_view.set_sheet(tex, Vector2i(MapView.CHIP_SIZE, MapView.CHIP_HEIGHT), MapView.CHIPS_PER_ROW, labels)


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
	_title_label.text = "マップチップ確認"
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
	_picker = OptionButton.new()
	_picker.focus_mode = Control.FOCUS_NONE
	_picker.item_selected.connect(_apply_selection)
	box.add_child(_picker)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(scroll)
	_view = SheetView.new()
	scroll.add_child(_view)
	close_requested.connect(func() -> void: hide())
