extends SceneTree
## 残り項目(第6段)のテスト: priv 入力欄のタグ挿入メニュー、
## ログの手動保存、ログの URL リンク化、TalkAdd(追加発言)、
## リストの複数チェックとページ送り。
##
## 使い方: godot --headless --path . -s tests/test_stage6.gd
## 終了コード 0 = 全一致、1 = 不一致あり。

var _failures := 0
var _checks := 0
var _tab: PhiCharacter = null
var _config: PhiConfig = null
var _frames := 0

const LOG_DIR := "/tmp/neophi-stage6-logs"


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
	_test_actions()
	_test_bbcode_line()
	_test_compose_checked_answer()
	_test_log_file_save_buffer()
	_config = PhiConfig.new()
	_config.log_auto_save = false
	_config.log_save_dir = LOG_DIR
	_config.log_save_html = false
	_config.log_save_delete_tag = false
	_config.log_save_text_with_time = true
	_config.log_delete_filter = false
	var font := PhiFont.make_ui_font()
	var bold := PhiFont.make_bold_font()
	_tab = PhiCharacter.new()
	_tab.setup(GameAssets.new(), _config, font, bold, PhiLogFilter.new(), PhiTagMenu.parse(PhiTagMenu.DEFAULT_XML))
	_test_log_linkify_records()
	_test_manual_save()
	_test_talk_add_draft()
	_test_list_check_state()
	root.add_child(_tab)
	_tab.position = Vector2.ZERO
	_tab.size = Vector2(1280, 1024)
	process_frame.connect(_on_frame)


func _on_frame() -> void:
	_frames += 1
	if _frames == 3:
		_test_priv_tags()
		_test_talk_add_key()
		_prepare_list_mouse_check()
	elif _frames == 5:
		_test_list_mouse_check()
		print("test_stage6: ", _checks, " checks, ", _failures, " failures")
		quit(1 if _failures > 0 else 0)


func _clean_dir(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir != null:
		dir.list_dir_begin()
		var name := dir.get_next()
		while not name.is_empty():
			if not dir.current_is_dir():
				DirAccess.remove_absolute(path.path_join(name))
			name = dir.get_next()
		dir.list_dir_end()
		DirAccess.remove_absolute(path)


func _read_file(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var text := file.get_as_text()
	file.close()
	return text


# -- アクション表 --------------------------------------------------------------

func _test_actions() -> void:
	_check_eq(PhiActions.kind_of("TalkAdd"), "talk-add", "s6 talkadd kind")
	_check_eq(str(PhiActions.get_action("TalkAdd")["caption"]), "追加発言", "s6 talkadd caption")
	_check_eq(PhiActions.kind_of("LogSave"), "log-save", "s6 logsave kind")
	_check_eq(str(PhiActions.get_action("LogSave")["caption"]), "ログを保存", "s6 logsave caption")
	# どちらも接続状態によらず常に有効(ローカルな操作のため)。
	_check(PhiActions.enabled_when("TalkAdd", false), "s6 talkadd enabled offline")
	_check(PhiActions.enabled_when("TalkAdd", true), "s6 talkadd enabled online")
	_check(PhiActions.enabled_when("LogSave", false), "s6 logsave enabled offline")
	_check(PhiActions.enabled_when("LogSave", true), "s6 logsave enabled online")
	var in_control := false
	var in_disp := false
	for menu in PhiActions.MENUS:
		var items: Array = menu["items"]
		if str(menu["name"]) == "操作":
			in_control = items.has("TalkAdd")
		if str(menu["name"]) == "表示":
			in_disp = items.has("LogSave")
	_check(in_control, "s6 talkadd in control menu")
	_check(in_disp, "s6 logsave in disp menu")


# -- ログの URL リンク化 --------------------------------------------------------

func _test_bbcode_line() -> void:
	_check_eq(PhiCharacter.escape_bbcode("a[b]c"), "a[lb]b[rb]c", "s6 escape brackets")
	_check_eq(PhiCharacter.bbcode_line("DM > [ 1] item"), "DM > [lb] 1[rb] item", "s6 bbcode no url escapes only")
	_check_eq(
		PhiCharacter.bbcode_line("see https://example.com/a?b=1 end"),
		"see [url=https://example.com/a?b=1][color=#5599ff][u]https://example.com/a?b=1[/u][/color][/url] end",
		"s6 bbcode url wrapped")
	# 末尾の句読点はリンクに入れない(本文として残る)。
	_check_eq(
		PhiCharacter.bbcode_line("url https://example.com/x."),
		"url [url=https://example.com/x][color=#5599ff][u]https://example.com/x[/u][/color][/url].",
		"s6 bbcode url tail dot")
	_check_eq(
		PhiCharacter.bbcode_line("見て https://a.b/c。"),
		"見て [url=https://a.b/c][color=#5599ff][u]https://a.b/c[/u][/color][/url]。",
		"s6 bbcode url tail jp period")
	# タグ風の文字列はエスケープされ、タグとして解釈される事は無い
	# (中の URL 部分だけがリンクになる)。
	_check_eq(
		PhiCharacter.bbcode_line("[url=https://evil.example/]x[/url]"),
		"[lb]url=[url=https://evil.example/][color=#5599ff][u]https://evil.example/[/u][/color][/url][rb]x[lb]/url[rb]",
		"s6 bbcode fake tag escaped")
	_check_eq(PhiCharacter.url_spans("a http://x.jp/ b https://y.jp/ c").size(), 2, "s6 url spans two")
	_check_eq(PhiCharacter.url_spans("no links here").size(), 0, "s6 url spans none")


func _test_log_linkify_records() -> void:
	_tab.log_message("log", "DM > see https://example.com/x for details")
	_tab.log_message("talk", "太郎 > [tag] と https://a.b/c。")
	var buffer := _tab.log_buffer()
	_check_eq(buffer.size(), 2, "s6 linkify records two")
	# 記録は従来どおりプレーンなまま(BBCode を含まない)。
	_check_eq(str(buffer[0]["display"]), "DM > see https://example.com/x for details", "s6 record plain 1")
	_check_eq(str(buffer[1]["display"]), "[発言] 太郎 > [tag] と https://a.b/c。", "s6 record plain 2")
	_check_eq(str(buffer[1].get("prefix", "?")), "[発言] ", "s6 record prefix kept")
	# 表示側(get_parsed_text)はタグを取り除いた文字列を返す。
	var parsed := _tab.debug_log_text()
	_check(parsed.contains("https://example.com/x"), "s6 parsed has url")
	_check(not parsed.contains("[url="), "s6 parsed has no url tag")
	_check(not parsed.contains("[lb]"), "s6 parsed has no lb")
	_check(parsed.contains("[tag] と https://a.b/c。"), "s6 parsed keeps brackets text")
	# コピー変種も壊れない(タグ付きコピーは記録から原文を引く)。
	var copied := PhiLogCopy.with_tags("[発言] 太郎 > [tag] と https://a.b/c。", buffer)
	_check_eq(copied, "太郎 > [tag] と https://a.b/c。", "s6 copy with tags resolves raw")


# -- ログの手動保存 --------------------------------------------------------------

func _test_log_file_save_buffer() -> void:
	_clean_dir(LOG_DIR)
	_check_eq(PhiLogFile.buffer_file_name("a/b", false, "20261116-010203"), "a_b_20261116-010203.log", "s6 buffer name sanitized")
	_check_eq(PhiLogFile.buffer_file_name("Tester", true, "20261116-010203"), "Tester_20261116-010203.html", "s6 buffer name html")
	var path := PhiLogFile.save_buffer(LOG_DIR, "Tester", false, ["one", "two"])
	_check(not path.is_empty(), "s6 save_buffer path")
	_check(path.ends_with(".log"), "s6 save_buffer ext")
	_check_eq(_read_file(path), "one\ntwo\n", "s6 save_buffer content")
	# 同じ秒にもう一度保存しても、別のファイルになる。
	var path2 := PhiLogFile.save_buffer(LOG_DIR, "Tester", false, ["three"])
	_check(not path2.is_empty() and path2 != path, "s6 save_buffer unique")
	_check(FileAccess.file_exists(path), "s6 save_buffer first remains")
	var html_path := PhiLogFile.save_buffer(LOG_DIR, "Tester", true, ["<one>"])
	var html := _read_file(html_path)
	_check(html.begins_with("<!DOCTYPE html>"), "s6 save_buffer html header")
	_check(html.contains("&lt;one&gt;<br>"), "s6 save_buffer html escaped")
	_check(html.ends_with("</html>\n"), "s6 save_buffer html closed")


func _test_manual_save() -> void:
	# _test_log_linkify_records で入れた2行が記録にある状態。
	var path := _tab.save_log_buffer()
	_check(not path.is_empty(), "s6 manual save path")
	var content := _read_file(path)
	# テキスト＋時刻入り: 行頭に [HH:MM:SS] が付き、本文は原文。
	_check(content.contains("] DM > see https://example.com/x for details"), "s6 manual save raw line")
	_check(content.contains("] [発言] 太郎 > [tag] と https://a.b/c。"), "s6 manual save prefix line")
	_check(not content.contains("[url="), "s6 manual save no bbcode")
	# タグ削除 on なら、原文ではなく表示(タグ無し)が入る。
	_config.log_save_delete_tag = true
	_tab.log_message("log", "表示だけの行", "/*b*/原文の行/*.*/")
	var path2 := _tab.save_log_buffer()
	var content2 := _read_file(path2)
	_check(content2.contains("表示だけの行"), "s6 manual save plain when delete tag")
	_check(not content2.contains("原文の行"), "s6 manual save no raw when delete tag")
	_config.log_save_delete_tag = false
	# HTML 保存。
	_config.log_save_html = true
	var path3 := _tab.save_log_buffer()
	_check(path3.ends_with(".html"), "s6 manual save html ext")
	_check(_read_file(path3).contains("DM &gt; see https://example.com/x for details<br>"), "s6 manual save html line")
	_config.log_save_html = false


# -- TalkAdd ---------------------------------------------------------------------

func _test_talk_add_draft() -> void:
	var tab := _tab
	# 下書きが空なら、設定した言葉が入力欄にも入る。
	tab.input_box.text = ""
	tab.set("_history_boundary", 0)
	tab.set_talk_add("（メモ） ")
	_check_eq(tab.talk_add_text(), "（メモ） ", "s6 talkadd kept")
	_check_eq(tab.debug_input_text(), "（メモ） ", "s6 talkadd fills empty draft")
	# 下書きがある時は、入力欄は変えない。
	tab.input_box.text = "abc"
	tab.set("_history_boundary", 0)
	tab.set_talk_add("X")
	_check_eq(tab.debug_input_text(), "abc", "s6 talkadd keeps draft")
	# 履歴だけの状態(下書き空)でも入る。
	tab.input_box.text = "hello\n"
	tab.set("_history_boundary", 6)
	tab.set_talk_add("Y")
	_check_eq(tab.debug_input_text(), "hello\nY", "s6 talkadd after history")
	# 送信で履歴を進めると、次の下書きに先に入る。
	tab.input_box.text = "hello\nworld"
	tab.set("_history_boundary", 6)
	tab.set_talk_add("Z")
	tab._advance_history()
	_check_eq(tab.debug_input_text(), "hello\nworld\nZ", "s6 talkadd prefilled after send")
	_check_eq(tab.history_boundary(), 12, "s6 talkadd boundary after send")
	# 空にすれば呼び出しも先入れも止まる。
	tab.set_talk_add("")
	_check_eq(tab.talk_add_text(), "", "s6 talkadd cleared")


func _key_event(keycode: Key, shift: bool = false) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.keycode = keycode
	ev.physical_keycode = keycode
	ev.pressed = true
	ev.shift_pressed = shift
	return ev


func _test_talk_add_key() -> void:
	var tab := _tab
	tab.set_talk_add("（定型）")
	# 最終行(下書きの行)で ↓ → 行が追加発言に置き換わる。
	tab.input_box.text = "sent\n"
	tab.set("_history_boundary", 5)
	tab.input_box.grab_focus()
	tab.input_box.set_caret_line(1)
	tab.input_box.set_caret_column(0)
	_check(tab.handle_key(_key_event(KEY_DOWN)), "s6 talkadd down handled")
	_check_eq(tab.debug_input_text(), "sent\n（定型）", "s6 talkadd recalled")
	# 下書きがあっても置き換わる(Philly は行ごと置換)。
	tab.input_box.text = "sent\ndraft"
	tab.set("_history_boundary", 5)
	tab.input_box.set_caret_line(1)
	tab.input_box.set_caret_column(5)
	_check(tab.handle_key(_key_event(KEY_DOWN)), "s6 talkadd down handled 2")
	_check_eq(tab.debug_input_text(), "sent\n（定型）", "s6 talkadd replaces draft line")
	# キャレットが最終行でなければ何もしない。
	tab.input_box.text = "a\nb"
	tab.set("_history_boundary", 0)
	tab.input_box.set_caret_line(0)
	tab.input_box.set_caret_column(1)
	_check(not tab.handle_key(_key_event(KEY_DOWN)), "s6 talkadd down ignored mid")
	_check_eq(tab.debug_input_text(), "a\nb", "s6 talkadd mid unchanged")
	# Shift 付きはキャレット移動のまま(扱わない)。
	tab.input_box.set_caret_line(1)
	_check(not tab.handle_key(_key_event(KEY_DOWN, true)), "s6 talkadd shift down ignored")
	# 追加発言が空なら ↓ は TextEdit 任せ。
	tab.set_talk_add("")
	tab.input_box.text = "sent\n"
	tab.set("_history_boundary", 5)
	tab.input_box.set_caret_line(1)
	_check(not tab.handle_key(_key_event(KEY_DOWN)), "s6 talkadd empty down ignored")
	tab.input_box.release_focus()


# -- リストの複数チェック ---------------------------------------------------------

func _test_compose_checked_answer() -> void:
	var lines: Array = ["[ 1] a", "[ 2] b", "[ 3] c"]
	_check_eq(PhiCharacter.compose_checked_answer(lines, []), "", "s6 compose none")
	_check_eq(PhiCharacter.compose_checked_answer(lines, [2, 0]), "1 3", "s6 compose sorted join")
	_check_eq(PhiCharacter.compose_checked_answer(lines, [1]), "2", "s6 compose single")
	# 2ページ目の絶対番号が使われる。
	var page2: Array = ["[ 9] i", "[10] j", "[11] k"]
	_check_eq(PhiCharacter.compose_checked_answer(page2, [1, 2]), "10 11", "s6 compose page2 absolute")
	# 続き行が含まれていれば、その番号だけ(ページ送り)。
	var with_more: Array = ["[ 1] a", "[ 2] b", "[ 3] c", "[ 4] d", "[ 5] e", "[ 6] f", "[ 7] g", "[ 8] h", "[ 9] ... and more."]
	_check(PhiCharacter.is_more_list_line("[ 9] ... and more."), "s6 more line detected")
	_check(not PhiCharacter.is_more_list_line("[ 9] item"), "s6 more line not item")
	_check_eq(PhiCharacter.compose_checked_answer(with_more, [0, 8]), "9", "s6 compose more alone")
	_check_eq(PhiCharacter.compose_checked_answer(with_more, [8]), "9", "s6 compose more single")
	# 番号が読み取れない行は行番号+1 で代用する。
	_check_eq(PhiCharacter.compose_checked_answer(["apple", "banana"], [1]), "2", "s6 compose fallback number")


func _queue(tab: PhiCharacter) -> Array:
	return tab.session.get("_send_queue")


func _test_list_check_state() -> void:
	var tab := _tab
	var lines: Array[String] = ["[ 1] wizard eye", "[ 2] cure", "[ 3] harm"]
	tab.set("_list_lines", lines)
	tab.set("_list_active", true)
	tab._show_list_overlay()
	var box: ItemList = tab.get("_list_box")
	_check_eq(box.item_count, 3, "s6 list items")
	_check(box.get_item_icon(0) != null, "s6 list has check icon")
	_check_eq(tab.list_checked_indices(), [], "s6 list checks start empty")
	# Space: 選択行をチェックして選択を下へ(Philly)。
	_check(tab.handle_list_key("Space", false, false, false), "s6 list space handled")
	_check_eq(tab.list_checked_indices(), [0], "s6 list space checks row0")
	_check_eq(Array(box.get_selected_items()), [1], "s6 list space moves selection")
	_check(tab.handle_list_key("Space", false, false, false), "s6 list space handled 2")
	_check_eq(tab.list_checked_indices(), [0, 1], "s6 list space checks row1")
	# Shift+数字: その行のチェック切替。
	_check(tab.handle_list_key("Digit1", true, false, false), "s6 list shift digit handled")
	_check_eq(tab.list_checked_indices(), [1], "s6 list shift digit toggles")
	# Ctrl+数字でも切替できる。
	_check(tab.handle_list_key("Numpad3", false, true, false), "s6 list ctrl numpad handled")
	_check_eq(tab.list_checked_indices(), [1, 2], "s6 list ctrl numpad toggles")
	# Shift+0: 全消し。
	_check(tab.handle_list_key("Digit0", true, false, false), "s6 list shift zero handled")
	_check_eq(tab.list_checked_indices(), [], "s6 list shift zero clears")
	# Shift+ +/-: 全反転。
	_check(tab.handle_list_key("NumpadAdd", true, false, false), "s6 list shift add handled")
	_check_eq(tab.list_checked_indices(), [0, 1, 2], "s6 list invert all")
	# Shift+↑↓: 選択行のチェック切替＋移動。
	box.select(0)
	_check(tab.handle_list_key("ArrowDown", true, false, false), "s6 list shift down handled")
	_check_eq(tab.list_checked_indices(), [1, 2], "s6 list shift down toggles current")
	_check_eq(Array(box.get_selected_items()), [1], "s6 list shift down moves")
	# 修飾キー無しの数字は従来どおり即送信(チェックがあっても数字キーは行送信)。
	# ここではチェックを消してから確認する。
	tab._clear_list_checks()
	_check(tab.handle_list_key("Digit2", false, false, false), "s6 list digit handled")
	_check_eq(_queue(tab), ["2"], "s6 list digit sends row")
	_check(not tab.list_active(), "s6 list closed after answer")
	_queue(tab).clear()
	# チェックがある状態で Enter 決定すると、まとめて送る。
	tab.set("_list_lines", lines)
	tab.set("_list_active", true)
	tab._show_list_overlay()
	_check_eq(tab.list_checked_indices(), [], "s6 list checks reset per page")
	tab._toggle_list_check(0)
	tab._toggle_list_check(2)
	tab._send_list_selected()
	_check_eq(_queue(tab), ["1 3"], "s6 list decision sends joined")
	_check(not tab.list_active(), "s6 list closed after decision")
	_queue(tab).clear()
	# 続き行を含むチェックは、その番号だけ送る(ページ送り)。
	var more_lines: Array[String] = ["[ 1] a", "[ 2] b", "[ 3] c", "[ 4] d", "[ 5] e", "[ 6] f", "[ 7] g", "[ 8] h", "[ 9] ... and more."]
	tab.set("_list_lines", more_lines)
	tab.set("_list_active", true)
	tab._show_list_overlay()
	tab._toggle_list_check(0)
	tab._toggle_list_check(8)
	tab._send_list_selected()
	_check_eq(_queue(tab), ["9"], "s6 list decision more alone")
	_queue(tab).clear()
	# チェック欄でのダブルクリックは決定しない。
	tab.set("_list_lines", lines)
	tab.set("_list_active", true)
	tab._show_list_overlay()
	tab.set("_list_press_in_check", true)
	tab._on_list_row_activated(1)
	_check_eq(_queue(tab), [], "s6 list check-area activation ignored")
	_check(tab.list_active(), "s6 list still open after check-area activation")
	tab._hide_list_overlay()


func _prepare_list_mouse_check() -> void:
	# リストを出しておき、レイアウトが済んでから矩形を見る。
	var lines: Array[String] = ["[ 1] wizard eye", "[ 2] cure", "[ 3] harm"]
	_tab.set("_list_lines", lines)
	_tab.set("_list_active", true)
	_tab._show_list_overlay()


func _test_list_mouse_check() -> void:
	# ツリーに入った状態で、実際の行の矩形から押下位置を作る。
	var tab := _tab
	var box: ItemList = tab.get("_list_box")
	var rect := box.get_item_rect(1)
	_check(rect.size.x > 60.0, "s6 list rect sane")
	# チェック欄(左端)を押すとチェックが切り替わる。
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = Vector2(5, rect.position.y + rect.size.y * 0.5)
	tab._on_list_box_gui_input(press)
	_check_eq(tab.list_checked_indices(), [1], "s6 list mouse check toggles")
	_check(bool(tab.get("_list_press_in_check")), "s6 list mouse press flagged")
	# 本文側を押してもチェックは変わらない(クリック=選択のまま)。
	var press2 := InputEventMouseButton.new()
	press2.button_index = MOUSE_BUTTON_LEFT
	press2.pressed = true
	press2.position = Vector2(rect.size.x - 10.0, rect.position.y + rect.size.y * 0.5)
	tab._on_list_box_gui_input(press2)
	_check_eq(tab.list_checked_indices(), [1], "s6 list mouse text no toggle")
	_check(not bool(tab.get("_list_press_in_check")), "s6 list mouse text not flagged")
	tab._hide_list_overlay()


# -- priv のタグ挿入 ---------------------------------------------------------------

func _test_priv_tags() -> void:
	var win := PhiPrivWindow.new()
	root.add_child(win)
	win.set_tag_tree(PhiTagMenu.parse(PhiTagMenu.DEFAULT_XML))
	_check_eq(win.tag_item_count(), 25, "s6 priv tag items 25")
	var edit := win.edit_control()
	_check(not edit.context_menu_enabled, "s6 priv builtin menu off")
	# ポップアップの構造: 4つのサブメニュー＋区切り＋編集系4つ。
	win._build_tag_popup()
	var popup: PopupMenu = win.get("_tag_popup")
	_check_eq(popup.item_count, 9, "s6 priv popup top items")
	_check(str(popup.get_item_submenu(0)) != "", "s6 priv popup has submenu")
	# 選択が無い時はキャレット位置にタグ対を入れ、間に入る。
	edit.text = "ab"
	edit.caret_column = 1
	win.insert_tag("/*b*/", "/*.*/")
	_check_eq(edit.text, "a/*b*//*.*/b", "s6 priv insert pair")
	_check_eq(edit.caret_column, 6, "s6 priv insert caret")
	# 選択があればタグで包む。
	edit.text = "hello world"
	edit.select(6, 11)
	win.insert_tag("/*i*/", "/*.*/")
	_check_eq(edit.text, "hello /*i*/world/*.*/", "s6 priv insert wraps selection")
	_check_eq(edit.caret_column, 21, "s6 priv insert wrap caret")
	win.queue_free()
