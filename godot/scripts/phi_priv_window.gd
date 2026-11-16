class_name PhiPrivWindow
extends Window
## priv ウィンドウ(第2段)。宛先チェック・履歴・送信欄を持つ。
##
## 第4段で1つの窓を全タブで共用する作りにした。表示する内容は
## アクティブなタブのもので、タブを切り替えると作り直す。
## 履歴そのものは各タブが持つ。
##
## 不具合の修正(第4段): 素の Window は × を押しても自動では隠れない
## ので、`close_requested` に隠す処理を接続した。Shift+F6 とメニューは
## トグル動作(開いていれば隠す)にする。
##
## 宛先から自分自身を除く(第4段): 自分のキャラ名と一致するエントリは
## チェックボックスを作らない。自分の名前がまだ分からない時(未ログイン)
## は除外しない。

signal send_requested
signal refresh_requested

var _box_holder: VBoxContainer = null
var _boxes: Array[CheckBox] = []
var _log: RichTextLabel = null
var _edit: LineEdit = null
var _opened_once := false
## タグ挿入メニュー(本体の入力欄と同じ TagMenu.xml の木)。
var _tag_tree := {}
var _tag_popup: PopupMenu = null
var _tag_next_id := 0
var _font_size := 15


func _init() -> void:
	# Window は既定で表示されるので、作った直後は隠しておく。
	# そうしないと、初回の popup_centered を経ずに (0,0) に出てしまう。
	visible = false
	title = "宛先がありません"
	transient = true
	min_size = Vector2i(360, 300)
	close_requested.connect(_on_close_requested)
	_build()


func _on_close_requested() -> void:
	## × ボタンで隠す。素の Window は自動では隠れない。
	hide()


func toggle() -> void:
	if visible:
		hide()
	else:
		show_window()


func show_window() -> void:
	if not _opened_once:
		_opened_once = true
		popup_centered(Vector2i(420, 380))
	else:
		show()


func _build() -> void:
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.add_theme_constant_override("separation", 6)
	add_child(box)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 110)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(scroll)
	_box_holder = VBoxContainer.new()
	_box_holder.add_theme_constant_override("separation", 2)
	scroll.add_child(_box_holder)
	var refresh := Button.new()
	refresh.text = "リスト更新"
	refresh.focus_mode = Control.FOCUS_NONE
	refresh.pressed.connect(func() -> void: refresh_requested.emit())
	box.add_child(refresh)
	_log = RichTextLabel.new()
	_log.bbcode_enabled = false
	_log.scroll_following = true
	_log.selection_enabled = true
	_log.custom_minimum_size = Vector2(0, 120)
	_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(_log)
	var send_row := HBoxContainer.new()
	send_row.add_theme_constant_override("separation", 6)
	box.add_child(send_row)
	_edit = LineEdit.new()
	_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_edit.placeholder_text = "priv の言葉"
	# 右クリックはタグ挿入メニューに使うので、標準メニューは止める。
	_edit.context_menu_enabled = false
	_edit.gui_input.connect(_on_edit_gui_input)
	send_row.add_child(_edit)
	_edit.text_submitted.connect(func(_text: String) -> void: send_requested.emit())
	var send_button := Button.new()
	send_button.text = "送信"
	send_button.pressed.connect(func() -> void: send_requested.emit())
	send_row.add_child(send_button)


func apply_font_size(size: int) -> void:
	## 履歴の文字サイズ。ダイアログのテーマはメイン画面が付ける。
	_font_size = size
	_log.add_theme_font_size_override("font_size", size)
	_log.add_theme_font_size_override("normal_font_size", size)
	_log.add_theme_font_size_override("bold_font_size", size)
	_log.add_theme_font_size_override("italics_font_size", size)
	_log.add_theme_font_size_override("bold_italics_font_size", size)
	_log.add_theme_font_size_override("mono_font_size", size)


func rebuild_recipients(users: Array, self_name: String) -> void:
	## 宛先チェックボックスを作り直す。チェック状態はキーで引き継ぐ。
	## 自分自身(self_name と一致する名前)は宛先に入れない。
	var checked: Dictionary = {}
	for box in _boxes:
		if box.button_pressed:
			checked[str(box.get_meta("key"))] = true
	for box in _boxes:
		box.queue_free()
	_boxes.clear()
	for user in users:
		var user_dict: Dictionary = user
		var user_name := str(user_dict.get("name", ""))
		if not self_name.is_empty() and user_name == self_name:
			continue
		var box := CheckBox.new()
		box.text = user_name
		box.set_meta("key", str(user_dict.get("key", "")))
		box.button_pressed = bool(checked.get(str(user_dict.get("key", "")), false))
		box.toggled.connect(_on_recipient_toggled)
		_box_holder.add_child(box)
		_boxes.append(box)
	update_title()


func _on_recipient_toggled(_pressed: bool) -> void:
	update_title()


func update_title() -> void:
	var names: Array[String] = []
	for box in _boxes:
		if box.button_pressed:
			names.append(box.text)
	title = ", ".join(names) if not names.is_empty() else "宛先がありません"


## 今ある宛先チェックボックスの名前の一覧(テスト用)。
func recipient_names() -> Array[String]:
	var names: Array[String] = []
	for box in _boxes:
		names.append(box.text)
	return names


## チェックされている宛先の一覧({key, name, box})。
func checked_entries() -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	for box in _boxes:
		if box.button_pressed:
			entries.append({"key": str(box.get_meta("key")), "name": box.text, "box": box})
	return entries


## チェックされている宛先のキーの一覧。
func checked_keys() -> Array[String]:
	var keys: Array[String] = []
	for entry in checked_entries():
		keys.append(str(entry["key"]))
	return keys


## 指定したキーのチェックを変える(テスト用)。
func set_checked(key: String, pressed: bool) -> void:
	for box in _boxes:
		if str(box.get_meta("key")) == key:
			box.button_pressed = pressed
			return


func send_text() -> String:
	return _edit.text


func clear_send_text() -> void:
	_edit.text = ""


func set_history(lines: Array[String]) -> void:
	_log.clear()
	for line in lines:
		_log.add_text(line + "\n")


func append_history(line: String) -> void:
	_log.add_text(line + "\n")


func log_line(text: String, is_error: bool) -> void:
	if is_error:
		_log.push_color(Color(1, 0.25, 0.25))
	_log.add_text(text + "\n")
	if is_error:
		_log.pop()


# -- タグ挿入メニュー(残り項目) ----------------------------------------------
## 本体の入力欄と同じタグ木を、priv の入力欄でも使えるようにする。
## 構造は PhiCharacter のタグポップアップと同じ(サブメニューごとに
## id_pressed をつなぐ)。違うのは編集対象が LineEdit なことだけで、
## LineEdit には選択範囲への挿入が無いので、文字列を組み立てて
## 差し替える形で挿入する(選択があればタグで包む)。

func set_tag_tree(tree: Dictionary) -> void:
	_tag_tree = tree
	_tag_popup = null
	_tag_next_id = 0


func _on_edit_gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb == null or not mb.pressed or mb.button_index != MOUSE_BUTTON_RIGHT:
		return
	_show_tag_popup()
	_edit.accept_event()


func _show_tag_popup() -> void:
	if _tag_popup == null:
		_build_tag_popup()
	if _tag_popup.item_count == 0:
		return
	_tag_popup.popup(Rect2i(Vector2i(get_mouse_position()) + position, Vector2i(1, 1)))


func _build_tag_popup() -> void:
	_tag_popup = PopupMenu.new()
	_tag_popup.id_pressed.connect(_on_tag_popup_pressed.bind(_tag_popup))
	add_child(_tag_popup)
	_tag_next_id = 0
	var children: Array = _tag_tree.get("children", [])
	for child in children:
		_add_tag_node(_tag_popup, child)
	_tag_popup.add_separator()
	_add_tag_action(_tag_popup, "切り取り", "cut")
	_add_tag_action(_tag_popup, "コピー", "copy")
	_add_tag_action(_tag_popup, "貼り付け", "paste")
	_add_tag_action(_tag_popup, "すべて選択", "select_all")
	_tag_popup.add_theme_font_size_override("font_size", maxi(_font_size, 15))
	_tag_popup.add_theme_font_size_override("font_separator_size", maxi(_font_size, 15))


func _add_tag_node(parent: PopupMenu, node: Dictionary) -> void:
	var caption := PhiTagMenu.strip_mnemonic(str(node.get("caption", "")))
	if str(node.get("kind", "")) == "item":
		var id := _tag_next_id
		_tag_next_id += 1
		parent.add_item(caption, id)
		parent.set_item_metadata(parent.get_item_index(id), {"tag": str(node.get("tag", "")), "closetag": str(node.get("closetag", ""))})
		return
	var sub := PopupMenu.new()
	sub.name = "tag_sub_%d" % _tag_next_id
	_tag_next_id += 1
	sub.id_pressed.connect(_on_tag_popup_pressed.bind(sub))
	parent.add_child(sub)
	sub.add_theme_font_size_override("font_size", maxi(_font_size, 15))
	sub.add_theme_font_size_override("font_separator_size", maxi(_font_size, 15))
	parent.add_submenu_item(caption, sub.name)
	var children: Array = node.get("children", [])
	for child in children:
		_add_tag_node(sub, child)


func _add_tag_action(parent: PopupMenu, caption: String, action: String) -> void:
	var id := _tag_next_id
	_tag_next_id += 1
	parent.add_item(caption, id)
	parent.set_item_metadata(parent.get_item_index(id), {"action": action})


func _on_tag_popup_pressed(id: int, popup: PopupMenu) -> void:
	var meta: Variant = popup.get_item_metadata(popup.get_item_index(id))
	if meta == null:
		return
	var data: Dictionary = meta
	if data.has("action"):
		match str(data["action"]):
			"cut":
				_edit.menu_option(LineEdit.MENU_CUT)
			"copy":
				_edit.menu_option(LineEdit.MENU_COPY)
			"paste":
				_edit.menu_option(LineEdit.MENU_PASTE)
			"select_all":
				_edit.select_all()
		return
	insert_tag(str(data.get("tag", "")), str(data.get("closetag", "")))


## タグを入力欄に挿入する。選択範囲があればタグで囲み、無ければ
## タグを入れてキャレットを開きタグの直後に置く(本体と同じ)。
func insert_tag(tag: String, closetag: String) -> void:
	if tag.is_empty():
		return
	_edit.grab_focus()
	var text := _edit.text
	if _edit.has_selection():
		var from := _edit.get_selection_from_column()
		var to := _edit.get_selection_to_column()
		var selected := _edit.get_selected_text()
		_edit.deselect()
		_edit.text = text.substr(0, from) + tag + selected + closetag + text.substr(to)
		_edit.caret_column = from + tag.length() + selected.length() + closetag.length()
	else:
		var col := _edit.caret_column
		_edit.text = text.substr(0, col) + tag + closetag + text.substr(col)
		_edit.caret_column = col + tag.length()


## 入力欄(テスト用)。
func edit_control() -> LineEdit:
	return _edit


## タグ項目の数(編集系を除く、テスト用)。
func tag_item_count() -> int:
	return PhiTagMenu.flatten(_tag_tree).size()
