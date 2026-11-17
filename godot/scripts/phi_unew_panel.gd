class_name PhiUnewPanel
extends Window
## unew.ini に基づくグラフィックス/音楽パックの取得パネル(第8段)。
## WPHI の「キャラグラとマップチップを取得する」モーダル相当。
##
## 開く側の使い方(main.gd 統合時):
##   var panel := PhiUnewPanel.new(_assets.philly_roots)
##   add_child(panel)
##   panel.show_window()
## roots は Philly ルートの候補(GameAssets.philly_roots と同じ)。
## unew.ini が見つかったルート(Config/ 配下ならその親)を
## 展開先の基準にする。ダウンロードは HTTPRequest、展開は
## zip 版があれば ZIP (無ければ LZH)、配置は WPHI と同じく
## ファイル名のみを dest_dir の下に置く。
## 取得できたら user://downloaded.json に記録する(PhiUnew)。

var _roots: Array[String] = []
## 題名用の太字フォント(main が渡す。無ければ通常フォントで出す)。
var title_font: Font = null
## 本文の文字サイズ(main が渡す)。題名はこれと同じ大きさにし、
## 日付や状態の列幅もこれに合わせて決める。
var body_size := 16
var _title_label: Label = null
var _base_root := ""
var _items: Array = []
var _record: Dictionary = {}
var _list_box: VBoxContainer = null
var _message: Label = null
var _all_button: Button = null
var _close_button: Button = null
var _row_buttons: Array[Button] = []
var _http: HTTPRequest = null
var _busy := false
var _queue: Array = []
var _current: Dictionary = {}
## 取得中の URL と、zip 版を試している途中かどうか。
var _fetch_url := ""
var _trying_zip := false
var _opened_once := false


func _init(p_roots: Array = []) -> void:
	# Window は既定で表示されるので、作った直後は隠しておく(priv 窓と同じ)。
	visible = false
	# 題名は中身の先頭行に出す(タイトル帯は地が描かれない環境がある)。
	title = ""
	transient = true
	min_size = Vector2i(640, 460)
	for r in p_roots:
		_roots.append(str(r))
	close_requested.connect(_on_close_requested)
	_build()
	_http = HTTPRequest.new()
	add_child(_http)
	_http.request_completed.connect(_on_request_completed)
	reload()


func set_roots(p_roots: Array) -> void:
	_roots.clear()
	for r in p_roots:
		_roots.append(str(r))
	reload()


func show_window() -> void:
	reload()
	_apply_title_font()
	if not _opened_once:
		_opened_once = true
		# 初回は大きめに出すが、メインウィンドウより大きくは
		# ならないよう収める(埋め込み窓は親窓を超えられない)。
		# ※ Window の get_window() は自分自身を返すので、
		# 親ウィンドウの大きさは get_tree().root から取る。
		var win := get_tree().root.size
		var want := Vector2i(mini(940, maxi(win.x - 16, 480)), mini(780, maxi(win.y - 16, 400)))
		popup_centered(want)
	else:
		show()


func _apply_title_font() -> void:
	## 題名は太字で、大きさは本文と同じにする(ユーザーの指定)。
	if _title_label == null:
		return
	if title_font != null:
		_title_label.add_theme_font_override("font", title_font)
	_title_label.add_theme_font_size_override("font_size", body_size)


func _on_close_requested() -> void:
	## 取得中は閉じない(WPHI と同じ)。
	if _busy:
		return
	hide()


func _build() -> void:
	# 中身は枠プレートで包む(題名や×が枠の中に収まるように)。
	var frame := UiStyle.window_frame()
	frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(frame)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	frame.add_child(box)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 6)
	box.add_child(UiStyle.title_band(head))
	var title_label := Label.new()
	title_label.text = "キャラグラとマップチップを取得する"
	# 題名は本文(行のラベル)と同じ大きさにする(ユーザーの指定)。
	title_label.add_theme_font_size_override("font_size", body_size)
	_title_label = title_label
	head.add_child(title_label)
	var head_spacer := Control.new()
	head_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(head_spacer)
	var head_close := Button.new()
	head_close.text = "×"
	head_close.focus_mode = Control.FOCUS_NONE
	head_close.pressed.connect(_on_close_requested)
	head.add_child(head_close)
	# 題名行を掴んで動かせるようにする。
	PhiWindowDrag.attach(head, self)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# 横スクロールはさせない。行のほうが幅に合わせて縮む
	# (ボタンが画面外へ押し出されて見えなくなるのを防ぐ)。
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	_list_box = VBoxContainer.new()
	_list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list_box.add_theme_constant_override("separation", 2)
	scroll.add_child(_list_box)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	box.add_child(row)
	_all_button = Button.new()
	_all_button.text = "全部取得する"
	_all_button.focus_mode = Control.FOCUS_NONE
	_all_button.pressed.connect(_fetch_all)
	row.add_child(_all_button)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	_close_button = Button.new()
	_close_button.text = "閉じる"
	_close_button.focus_mode = Control.FOCUS_NONE
	_close_button.pressed.connect(_on_close_requested)
	row.add_child(_close_button)
	_message = Label.new()
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_message)


## unew.ini と取得記録を読み直し、一覧を作り直す。
func reload() -> void:
	_record = PhiUnew.load_record()
	var loaded := PhiUnew.load_items(_roots)
	_items = loaded["items"]
	_base_root = ""
	var path := str(loaded["path"])
	if not path.is_empty():
		var dir := path.get_base_dir()
		if dir.get_file() == "Config":
			dir = dir.get_base_dir()
		_base_root = dir
	_rebuild_rows()
	if _busy:
		_set_busy(true)
	var error_text := str(loaded["error"])
	if error_text != "":
		_set_message(error_text, true)
	else:
		_set_message("", false)


static func _short_date(text: String) -> String:
	## 日付の表示を短くする: "Sat, 09 Jan 2010 16:31:38 GMT" を
	## "2010-01-09 16:31" にする(横幅の節約)。読めない形式は
	## そのまま返す。
	var months := {
		"Jan": 1, "Feb": 2, "Mar": 3, "Apr": 4, "May": 5, "Jun": 6,
		"Jul": 7, "Aug": 8, "Sep": 9, "Oct": 10, "Nov": 11, "Dec": 12,
	}
	var parts := text.replace(",", " ").split(" ", false)
	if parts.size() >= 5 and months.has(parts[2]):
		return "%s-%02d-%02d %s" % [parts[3], int(months[parts[2]]), parts[1].to_int(), parts[4].substr(0, 5)]
	return text


func _rebuild_rows() -> void:
	for child in _list_box.get_children():
		child.queue_free()
	_row_buttons.clear()
	for item_var in _items:
		var item: Dictionary = item_var
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		_list_box.add_child(row)
		var title_label := Label.new()
		title_label.text = str(item.get("title", ""))
		title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		# 幅が足りない時は「…」で省略し、右端のボタンを守る。
		title_label.clip_text = true
		title_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		row.add_child(title_label)
		var date_label := Label.new()
		date_label.text = _short_date(str(item.get("date", "")))
		# clip_text のラベルは最小幅 0 になり、広がる題名に全部
		# 食べられて消えてしまうので、幅を確保する。
		date_label.custom_minimum_size = Vector2(body_size * 8.0, 0)
		date_label.clip_text = true
		date_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		row.add_child(date_label)
		var status := PhiUnew.status_of(item, _record)
		var status_label := Label.new()
		status_label.text = PhiUnew.status_text(status)
		status_label.custom_minimum_size = Vector2(maxf(96.0, body_size * 4.5), 0)
		row.add_child(status_label)
		var button := Button.new()
		button.text = "取得し直す" if status != PhiUnew.Status.NOT_DOWNLOADED else "取得する"
		button.focus_mode = Control.FOCUS_NONE
		button.disabled = _busy
		button.pressed.connect(_on_row_button.bind(item))
		row.add_child(button)
		_row_buttons.append(button)


func _set_message(text: String, is_error: bool) -> void:
	_message.text = text
	_message.add_theme_color_override("font_color", Color(1, 0.35, 0.35) if is_error else Color(1, 1, 1))


func _set_busy(busy: bool) -> void:
	_busy = busy
	for button in _row_buttons:
		button.disabled = busy
	_all_button.disabled = busy
	_close_button.disabled = busy


# -- 取得 -----------------------------------------------------------------------

func _on_row_button(item: Dictionary) -> void:
	if _busy:
		return
	_queue = [item]
	_start_next()


func _fetch_all() -> void:
	if _busy:
		return
	_queue.clear()
	for item_var in _items:
		var item: Dictionary = item_var
		if PhiUnew.status_of(item, _record) != PhiUnew.Status.UP_TO_DATE:
			_queue.append(item)
	if _queue.is_empty():
		_set_message("取得するものはありません。", false)
		return
	_start_next()


func _start_next() -> void:
	if _queue.is_empty():
		_set_busy(false)
		return
	_current = _queue[0]
	_queue.remove_at(0)
	_set_busy(true)
	_set_message("取得しています: " + str(_current.get("title", "")), false)
	# zip 版が用意されている素材はそちらを優先して取りに行く。
	# 取れなければ _on_request_completed が .lzh に取り直す。
	var url := str(_current.get("url", ""))
	var twin := PhiUnew.zip_twin_url(url)
	_trying_zip = not twin.is_empty()
	_fetch_url = twin if _trying_zip else url
	var err := _http.request(_fetch_url)
	if err != OK:
		_set_message("リクエストを開始できませんでした: " + str(_current.get("title", "")), true)
		_current = {}
		_start_next()


func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var item := _current
	var item_title := str(item.get("title", ""))
	var fail := ""
	var report: Dictionary = {}
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		fail = "ダウンロードに失敗しました: " + item_title + "(HTTP " + str(response_code) + ")"
	elif body.size() > PhiUnew.MAX_BYTES:
		fail = "ファイルが大きすぎます: " + item_title
	else:
		report = _extract_archive(body, _fetch_url)
		if not bool(report.get("ok", false)):
			fail = "展開に失敗しました: " + item_title + ": " + str(report.get("error", ""))
	if fail != "":
		if _trying_zip:
			# zip 版が用意されていない (tofup.net 以外など) か
			# 使えなかったので、本来の .lzh を取りに行く。
			_trying_zip = false
			_fetch_url = str(item.get("url", ""))
			if _http.request(_fetch_url) == OK:
				return
		_current = {}
		_set_message(fail, true)
		_finish_item()
		return
	_current = {}
	var files: Dictionary = report["files"]
	var written := _write_files(item, files)
	if written < 0:
		_set_message("書き込みに失敗しました: " + item_title, true)
		_finish_item()
		return
	PhiUnew.mark_downloaded(_record, item)
	PhiUnew.save_record(_record)
	_set_message(item_title + " を取得しました(" + str(written) + " 個のファイル)。", false)
	_rebuild_rows()
	_set_busy(true) # 作り直したボタンを取得中は無効のままにする
	_finish_item()


func _finish_item() -> void:
	if _queue.is_empty():
		_set_busy(false)
	else:
		_start_next()


## 取得したバイト列を展開する。URL の拡張子で形式を決める
## (.zip は ZIP、それ以外は LZH)。PhiLzh.extract_report と同じ
## {ok, error, files} を返す。
func _extract_archive(body: PackedByteArray, url: String) -> Dictionary:
	if url.to_lower().ends_with(".zip"):
		return _extract_zip(body)
	return PhiLzh.extract_report(body)


## ZIP を展開する。ZIPReader はファイルからしか開けないので、
## 一時ファイルに書いてから読む。
func _extract_zip(body: PackedByteArray) -> Dictionary:
	var tmp := "user://unew_tmp.zip"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return {"ok": false, "error": "一時ファイルを作れません", "files": {}}
	f.store_buffer(body)
	f.close()
	var reader := ZIPReader.new()
	var err := reader.open(tmp)
	if err != OK:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp))
		return {"ok": false, "error": "ZIP が開けません", "files": {}}
	var files := {}
	for name in reader.get_files():
		if name.ends_with("/"):
			continue
		files[name] = reader.read_file(name)
	reader.close()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp))
	if files.is_empty():
		return {"ok": false, "error": "ZIP が空です", "files": {}}
	return {"ok": true, "error": "", "files": files}


## 展開したファイルを展開先に置く。WPHI と同じくフォルダ階層は
## 使わずファイル名のみ。書き込んだ数を返し、失敗したら -1。
func _write_files(item: Dictionary, files: Dictionary) -> int:
	if _base_root.is_empty():
		return -1
	var dest := _base_root
	var sub := str(item.get("dest_dir", ""))
	if not sub.is_empty():
		dest = dest.path_join(sub)
	var count := 0
	for name_var in files:
		var base := str(name_var).get_file()
		if base.is_empty() or base == "." or base == "..":
			continue
		var dir_err := DirAccess.make_dir_recursive_absolute(dest)
		if dir_err != OK and dir_err != ERR_ALREADY_EXISTS:
			return -1
		var content: PackedByteArray = files[name_var]
		var f := FileAccess.open(dest.path_join(base), FileAccess.WRITE)
		if f == null:
			return -1
		f.store_buffer(content)
		f.close()
		count += 1
	return count


# -- テスト用 ---------------------------------------------------------------------

## 読み込めた項目の数。
func item_count() -> int:
	return _items.size()


## 読み込めた項目の一覧。
func items() -> Array:
	return _items


## 展開先の基準ルート(unew.ini のあるルート)。
func base_root() -> String:
	return _base_root
