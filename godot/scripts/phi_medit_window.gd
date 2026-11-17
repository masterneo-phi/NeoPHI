class_name PhiMEditWindow
extends Window
## 看板の複数行エディタ (#m-edit、Philly MEditForm 相当)。
## 送信すると本文の行と "." を、キャンセルや閉じる操作では
## ".!" を送る (実際の送信は Main 経由でタブへ)。サーバ側から
## 編集が終わった時 (#.) は、何も送らずに閉じる。
##
## 下半分は書き上がりのプレビュー (Philly の Preview 相当)。
## サーバが保存時に付けるヘッダ (名前を16バイトに詰めたもの +
## 日時) と46文字の区切り線を、入力に合わせてその場で組む。

signal send_requested(lines: Array)
signal cancel_requested

var title_font: Font = null
var title_size := 20
var body_font: Font = null
## プレビューの [b] [i] 用 (Main が渡す)。
var bold_font: Font = null
var italics_font: Font = null
var bold_italics_font: Font = null
var body_size := 16

## タグツールバーの色 (Philly の TagMenu.xml と同じ並び + 黒)。
## [タグに入る色名, 見本の色]。
const TAG_COLORS := [
	["red", Color(1, 0, 0)], ["blue", Color(0, 0, 1)],
	["cyan", Color(0, 1, 1)], ["magenta", Color(1, 0, 1)],
	["navy", Color(0, 0, 0.5)], ["lime", Color(0, 1, 0)],
	["purple", Color(0.5, 0, 0.5)], ["yellow", Color(1, 1, 0)],
	["silver", Color(0.75, 0.75, 0.75)], ["olieve", Color(0.5, 0.5, 0)],
	["teal", Color(0, 0.5, 0.5)], ["maroon", Color(0.5, 0, 0)],
	["white", Color(1, 1, 1)], ["green", Color(0, 0.5, 0)],
	["gray", Color(0.5, 0.5, 0.5)], ["black", Color(0, 0, 0)],
]
## 書式ボタン。[表示, タグ, 閉じタグ]。
const TAG_STYLES := [
	["A↑", "/*size=large*/", "/*.*/"],
	["A↓", "/*size=small*/", "/*.*/"],
	["B", "/*style=bold*/", "/*.*/"],
	["I", "/*style=italic*/", "/*.*/"],
	["S", "/*style=strike*/", "/*.*/"],
	["U", "/*style=under*/", "/*.*/"],
	["x²", "/*style=sup*/", "/*.*/"],
	["x₂", "/*style=sub*/", "/*.*/"],
]

var _title_label: Label = null
var _edit: TextEdit = null
var _preview: RichTextLabel = null
var _char_name := ""
## サーバの編集セッション中か。false の間の閉じる操作では
## ".!" を送らない (二重送信の防止)。
var _bound := false


func _init() -> void:
	title = ""
	transparent = true
	min_size = Vector2i(640, 440)
	_build()


func _build() -> void:
	var frame := UiStyle.window_frame()
	add_child(frame)
	frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	frame.add_child(box)
	var head_inner := HBoxContainer.new()
	head_inner.add_theme_constant_override("separation", 6)
	_title_label = Label.new()
	_title_label.text = "看板を書く"
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head_inner.add_child(_title_label)
	var close_button := Button.new()
	close_button.text = "×"
	close_button.focus_mode = Control.FOCUS_NONE
	UiStyle.apply_metal_button(close_button)
	close_button.pressed.connect(_on_cancel_pressed)
	head_inner.add_child(close_button)
	var head := UiStyle.title_band(head_inner)
	box.add_child(head)
	PhiWindowDrag.attach(head, self)
	box.add_child(_build_tag_toolbar())
	_edit = TextEdit.new()
	_edit.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_edit.text_changed.connect(_refresh_preview)
	_edit.gui_input.connect(_on_edit_gui_input)
	box.add_child(_edit)
	# 書き上がりのプレビュー。看板の紙面らしく白地に濃い文字。
	var paper := PanelContainer.new()
	paper.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var paper_style := StyleBoxFlat.new()
	paper_style.bg_color = Color(0.97, 0.97, 0.95)
	paper_style.set_corner_radius_all(4)
	paper_style.set_content_margin_all(8)
	paper.add_theme_stylebox_override("panel", paper_style)
	_preview = RichTextLabel.new()
	_preview.bbcode_enabled = true
	_preview.fit_content = false
	_preview.scroll_following = false
	_preview.add_theme_color_override("default_color", Color(0.08, 0.08, 0.10))
	paper.add_child(_preview)
	box.add_child(paper)
	var hint := Label.new()
	hint.text = "送信 (Shift+Enter でも可) すると本文と '.' が送られます。やめる時は '.!' が送られます。"
	box.add_child(hint)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	box.add_child(row)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	var cancel := Button.new()
	cancel.text = "キャンセル"
	cancel.focus_mode = Control.FOCUS_NONE
	UiStyle.apply_metal_button(cancel)
	cancel.pressed.connect(_on_cancel_pressed)
	row.add_child(cancel)
	var send := Button.new()
	send.text = "送信"
	send.focus_mode = Control.FOCUS_NONE
	UiStyle.apply_metal_button(send)
	send.pressed.connect(_on_send_pressed)
	row.add_child(send)
	close_requested.connect(_on_cancel_pressed)


static func preview_text(char_name: String, body: String, when: Dictionary) -> String:
	## プレビューの全文。ヘッダはサーバが記事を読む時に出す形と
	## 同じ (名前を cp932 の16バイトに詰め、日時を括弧で)。
	var name_bytes := Cp932.encode(char_name)
	var padded := char_name
	if name_bytes.size() < 16:
		padded += " ".repeat(16 - name_bytes.size())
	var head := "%s(%04d/%02d/%02d %02d:%02d:%02d)" % [
		padded,
		int(when.get("year", 0)), int(when.get("month", 0)), int(when.get("day", 0)),
		int(when.get("hour", 0)), int(when.get("minute", 0)), int(when.get("second", 0))]
	return head + "\n" + "-".repeat(46) + "\n" + body


func _refresh_preview() -> void:
	if _preview == null:
		return
	# ヘッダと区切りはそのまま、本文のタグだけ BBCode にして
	# 色や書式が付いた姿で見せる。
	var full := preview_text(_char_name, _edit.text, Time.get_datetime_dict_from_system())
	var head_end := full.find("-".repeat(46) + "\n")
	if head_end < 0:
		_preview.text = full
		return
	var head := full.substr(0, head_end + 47)
	_preview.text = head + PhiTags.to_bbcode(_edit.text, body_size)


func _build_tag_toolbar() -> HBoxContainer:
	## 色見本と書式のボタン (WPHI の看板窓の上部と同じ並び)。
	## 押すと編集中の本文へタグを入れる。選択があればタグで囲む。
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 3)
	for pair in TAG_COLORS:
		var color_name := str(pair[0])
		var swatch := Button.new()
		swatch.custom_minimum_size = Vector2(20, 20)
		swatch.focus_mode = Control.FOCUS_NONE
		swatch.tooltip_text = color_name
		var style := StyleBoxFlat.new()
		style.bg_color = pair[1]
		style.set_border_width_all(1)
		style.border_color = Color(0.1, 0.1, 0.12)
		style.set_corner_radius_all(3)
		swatch.add_theme_stylebox_override("normal", style)
		swatch.add_theme_stylebox_override("hover", style)
		swatch.add_theme_stylebox_override("pressed", style)
		swatch.pressed.connect(_insert_tag.bind("/*color=%s*/" % color_name, "/*.*/"))
		bar.add_child(swatch)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(8, 0)
	bar.add_child(gap)
	for spec in TAG_STYLES:
		var button := Button.new()
		button.text = str(spec[0])
		button.focus_mode = Control.FOCUS_NONE
		button.tooltip_text = str(spec[1])
		button.pressed.connect(_insert_tag.bind(str(spec[1]), str(spec[2])))
		bar.add_child(button)
	var font_button := Button.new()
	font_button.text = "フォント"
	font_button.focus_mode = Control.FOCUS_NONE
	font_button.tooltip_text = "/*font=フォント名*/"
	font_button.pressed.connect(_insert_tag.bind("/*font=", "*//*.*/"))
	bar.add_child(font_button)
	return bar


func _insert_tag(tag: String, closetag: String) -> void:
	## 選択範囲があればタグで囲み、無ければタグを入れて
	## キャレットをタグと閉じタグの間に置く (入力欄と同じ流儀)。
	_edit.grab_focus()
	var selected := _edit.get_selected_text()
	if not selected.is_empty():
		_edit.insert_text_at_caret(tag + selected + closetag)
		return
	_edit.insert_text_at_caret(tag + closetag)
	_edit.set_caret_column(maxi(0, _edit.get_caret_column() - closetag.length()))


func show_editor(char_name: String) -> void:
	## 編集をはじめる。題名にキャラ名を出し、本文は空にする。
	_bound = true
	_char_name = char_name
	_title_label.text = "看板を書く — " + char_name if not char_name.is_empty() else "看板を書く"
	if title_font != null:
		_title_label.add_theme_font_override("font", title_font)
	_title_label.add_theme_font_size_override("font_size", title_size)
	if body_font != null:
		_edit.add_theme_font_override("font", body_font)
		_preview.add_theme_font_override("normal_font", body_font)
	if bold_font != null:
		_preview.add_theme_font_override("bold_font", bold_font)
	if italics_font != null:
		_preview.add_theme_font_override("italics_font", italics_font)
	if bold_italics_font != null:
		_preview.add_theme_font_override("bold_italics_font", bold_italics_font)
	_edit.add_theme_font_size_override("font_size", body_size)
	_preview.add_theme_font_size_override("normal_font_size", body_size)
	_preview.add_theme_font_size_override("bold_font_size", body_size)
	_preview.add_theme_font_size_override("italics_font_size", body_size)
	_preview.add_theme_font_size_override("bold_italics_font_size", body_size)
	_edit.text = ""
	_refresh_preview()
	var want := Vector2i(880, 600)
	var root_size := Vector2i(1280, 1024)
	var tree := get_tree()
	if tree != null and tree.root != null:
		root_size = tree.root.size
	var size_i := Vector2i(UiStyle.fit_popup_size(Vector2(want), Vector2(root_size)))
	if visible:
		size = size_i
		position = Vector2i(
			clampi(position.x, 0, maxi(0, root_size.x - size_i.x)),
			clampi(position.y, 0, maxi(0, root_size.y - size_i.y)))
	else:
		popup_centered(size_i)
	_edit.grab_focus()


func close_silent() -> void:
	## サーバ側から編集が終わった時の閉じ方。何も送らない。
	_bound = false
	hide()


func _on_edit_gui_input(event: InputEvent) -> void:
	## Shift+Enter で書き込む (送信ボタンと同じ)。素の Enter は
	## 改行のまま TextEdit に任せる。
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.keycode != KEY_ENTER and key.keycode != KEY_KP_ENTER:
		return
	if not key.shift_pressed or key.ctrl_pressed or key.alt_pressed or key.meta_pressed:
		return
	_on_send_pressed()
	_edit.accept_event()


func _on_send_pressed() -> void:
	if _bound:
		_bound = false
		var lines: Array = []
		for line in _edit.text.split("\n"):
			lines.append(line)
		send_requested.emit(lines)
	hide()


func _on_cancel_pressed() -> void:
	if _bound:
		_bound = false
		cancel_requested.emit()
	hide()
