class_name PhiEagleWindow
extends Window
## Eagle Eye の広域マップ窓 (Python 版の EagleEye 窓相当)。
##
## 中身は PhiEagleView。題名行のドラッグで移動し、× で閉じる。
## テーマと transparent は生成側 (main) が当てる。

var title_font: Font = null
var title_size := 20

## 画像を保存した (Philly SSEagleEye)。Main がログに出す。
signal image_saved(path: String)

var _title_label: Label = null
var _view: PhiEagleView = null


func _init() -> void:
	title = ""
	visible = false
	_build()


func show_event(event: Dictionary, assets: GameAssets, mapset: String, zoom: float, source_name: String, defines: Dictionary = {}) -> void:
	if title_font != null and _title_label != null:
		_title_label.add_theme_font_override("font", title_font)
		_title_label.add_theme_font_size_override("font_size", title_size)
	_title_label.text = "Eagle Eye" if source_name.is_empty() else "Eagle Eye ― " + source_name
	_view.set_event(event, assets, mapset, zoom, defines)
	var frame := get_child(0) as Control
	var need := Vector2i(frame.get_combined_minimum_size()) + Vector2i(24, 18)
	if visible:
		size = need
		min_size = need
		# 大きくなった時は、窓が画面の外へはみ出さないよう
		# 位置を内側へ戻す。
		var rs := get_tree().root.size
		position = Vector2i(
			clampi(position.x, 0, maxi(rs.x - size.x, 0)),
			clampi(position.y, 0, maxi(rs.y - size.y, 0)))
	else:
		min_size = need
		var root_size := get_tree().root.size
		need = Vector2i(mini(need.x, maxi(root_size.x - 16, 320)), mini(need.y, maxi(root_size.y - 16, 240)))
		min_size = need
		popup_centered(need)


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
	_title_label.text = "Eagle Eye"
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	head.add_child(_title_label)
	var save_button := Button.new()
	save_button.text = "保存"
	save_button.focus_mode = Control.FOCUS_NONE
	UiStyle.apply_metal_button(save_button)
	save_button.pressed.connect(_save_image)
	head.add_child(save_button)
	var close_button := Button.new()
	close_button.text = "×"
	close_button.focus_mode = Control.FOCUS_NONE
	UiStyle.apply_metal_button(close_button)
	close_button.pressed.connect(func() -> void: hide())
	head.add_child(close_button)
	PhiWindowDrag.attach(head, self)
	_view = PhiEagleView.new()
	_view.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	box.add_child(_view)
	close_requested.connect(func() -> void: hide())


func _save_image() -> void:
	## 盤面の画像を ScreenShot フォルダに保存する (Philly
	## SSEagleEye)。窓全体ではなく盤面の範囲だけを切り取る。
	await get_tree().process_frame
	var img := get_texture().get_image()
	var region := UiStyle.viewport_region(
		Vector2i(img.get_width(), img.get_height()),
		Vector2(size), _view.get_global_rect())
	if region.size.x > 0 and region.size.y > 0:
		img = img.get_region(region)
	var dir := "user://ScreenShot"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var stamp := Time.get_datetime_string_from_system(false, false).replace(":", "").replace("-", "").replace("T", "_")
	var path := "%s/EagleEye_%s.png" % [dir, stamp]
	if img.save_png(path) == OK:
		image_saved.emit(path)
