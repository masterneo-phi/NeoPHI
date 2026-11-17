class_name PhiSoundTestWindow
extends Window
## サウンドテスト (ツール)。同梱・配置済みの効果音と BGM を
## 一覧から試聴する。キャラグラ確認と同じく ItemList で、
## 選んだ行がそのまま再生中のハイライトになる。再生は
## PhiSoundEngine 経由なので、BGM と効果音は互いに止めない。
## 設定で OFF の時は注意書きを出す。
##
## テーマと transparent は生成側 (main) が当てる。

var title_font: Font = null
var title_size := 20

var _title_label: Label = null
var _se_list: ItemList = null
var _bgm_list: ItemList = null
var _se_note: Label = null
var _bgm_note: Label = null
var _se_title: Label = null
var _bgm_title: Label = null
var _engine: PhiSoundEngine = null
var _roots: Array = []
var _se_names: Array = []
var _bgm_names: Array = []
## 再生中の効果音 (ファイル名、鳴り始めた順)。
var _se_playing: Array[String] = []

## 見出し (BGM / 効果音) の色。窓の題名の金色に合わせる。
const SECTION_COLOR := Color(1.0, 0.84, 0.35)


func _init() -> void:
	title = ""
	visible = false
	_build()


func setup(engine: PhiSoundEngine, roots: Array, se_names: Array, bgm_names: Array, se_enabled: bool, bgm_enabled: bool) -> void:
	if _engine != engine:
		if _engine != null:
			if _engine.se_started.is_connected(_on_se_started):
				_engine.se_started.disconnect(_on_se_started)
			if _engine.se_finished.is_connected(_on_se_finished):
				_engine.se_finished.disconnect(_on_se_finished)
		_engine = engine
		if _engine != null:
			_engine.se_started.connect(_on_se_started)
			_engine.se_finished.connect(_on_se_finished)
	_roots = roots.duplicate()
	_se_names = se_names.duplicate()
	_bgm_names = bgm_names.duplicate()
	_se_note.visible = not se_enabled
	_bgm_note.visible = not bgm_enabled
	_se_list.clear()
	for name in _se_names:
		_se_list.add_item(str(name))
	_bgm_list.clear()
	for name in _bgm_names:
		_bgm_list.add_item(str(name))


func show_viewer() -> void:
	if title_font != null and _title_label != null:
		_title_label.add_theme_font_override("font", title_font)
		_title_label.add_theme_font_size_override("font_size", title_size)
		for section in [_se_title, _bgm_title]:
			section.add_theme_font_override("font", title_font)
			section.add_theme_font_size_override("font_size", maxi(14, title_size - 4))
		for list in [_se_list, _bgm_list]:
			list.add_theme_font_override("font", title_font)
			list.add_theme_font_size_override("font_size", maxi(14, title_size - 4))
	_sync_bgm_selection()
	if visible:
		grab_focus()
		return
	popup_centered(UiStyle.fit_popup_size(Vector2i(800, 560), get_tree().root.size))


## 再生中の BGM があれば、その行を選んでハイライトする。
func _sync_bgm_selection() -> void:
	if _engine == null:
		return
	var current := _engine.bgm_current_path()
	if current.is_empty() or _engine.bgm_state() == "stop":
		_bgm_list.deselect_all()
		return
	for i in _bgm_names.size():
		if PhiSoundPaths.resolve_bgm(str(_bgm_names[i]), _roots) == current:
			_bgm_list.select(i)
			return
	_bgm_list.deselect_all()


func _play_bgm_at(index: int) -> void:
	if _engine == null or index < 0 or index >= _bgm_names.size():
		return
	var path := PhiSoundPaths.resolve_bgm(str(_bgm_names[index]), _roots)
	if not path.is_empty():
		_engine.bgm_play(path)


func _play_se_at(index: int) -> void:
	if _engine == null or index < 0 or index >= _se_names.size():
		return
	_engine.play_se_entry("sound/se/" + str(_se_names[index]))


## 鳴っている効果音の行をハイライトする。同時に複数鳴って
## いる時は最後に鳴り始めたものを出し、終わったら残りの
## うち最後のものに戻す。全部終わったらハイライトを消す。
func _on_se_started(path: String) -> void:
	var file := path.get_file()
	for i in _se_names.size():
		if str(_se_names[i]) == file:
			_se_playing.erase(file)
			_se_playing.append(file)
			_se_list.select(i)
			return


func _on_se_finished(path: String) -> void:
	_se_playing.erase(path.get_file())
	if _se_playing.is_empty():
		_se_list.deselect_all()
		return
	var last := _se_playing[_se_playing.size() - 1]
	for i in _se_names.size():
		if str(_se_names[i]) == last:
			_se_list.select(i)
			return
	_se_list.deselect_all()


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
	_title_label.text = "サウンドテスト"
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
	# 2列: 左に BGM、右に効果音。
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 12)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(cols)
	var bgm_col := VBoxContainer.new()
	bgm_col.add_theme_constant_override("separation", 6)
	bgm_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(bgm_col)
	var bgm_head := HBoxContainer.new()
	bgm_head.add_theme_constant_override("separation", 6)
	bgm_col.add_child(bgm_head)
	_bgm_title = Label.new()
	_bgm_title.text = "BGM"
	_bgm_title.add_theme_color_override("font_color", SECTION_COLOR)
	_bgm_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bgm_head.add_child(_bgm_title)
	var stop_button := Button.new()
	stop_button.text = "停止"
	stop_button.focus_mode = Control.FOCUS_NONE
	UiStyle.apply_metal_button(stop_button)
	stop_button.pressed.connect(func() -> void:
		if _engine != null:
			_engine.bgm_stop()
		_bgm_list.deselect_all())
	bgm_head.add_child(stop_button)
	_bgm_note = Label.new()
	_bgm_note.text = "※ BGM は設定で OFF です（表示メニュー → BGM を再生する）"
	_bgm_note.add_theme_color_override("font_color", Color(1.0, 0.75, 0.5))
	_bgm_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bgm_col.add_child(_bgm_note)
	_bgm_list = ItemList.new()
	_bgm_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_bgm_list.item_selected.connect(_play_bgm_at)
	_bgm_list.item_activated.connect(_play_bgm_at)
	bgm_col.add_child(_bgm_list)
	var se_col := VBoxContainer.new()
	se_col.add_theme_constant_override("separation", 6)
	se_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(se_col)
	_se_title = Label.new()
	_se_title.text = "効果音"
	_se_title.add_theme_color_override("font_color", SECTION_COLOR)
	se_col.add_child(_se_title)
	_se_note = Label.new()
	_se_note.text = "※ 効果音は設定で OFF です（表示メニュー → 効果音を再生する）"
	_se_note.add_theme_color_override("font_color", Color(1.0, 0.75, 0.5))
	_se_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	se_col.add_child(_se_note)
	_se_list = ItemList.new()
	_se_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_se_list.item_selected.connect(_play_se_at)
	_se_list.item_activated.connect(_play_se_at)
	se_col.add_child(_se_list)
	close_requested.connect(func() -> void: hide())
