extends SceneTree
## 第4段(ログ・複数キャラ)のテスト。
##
## 使い方: godot --headless --path . -s tests/test_stage4.gd
## 終了コード 0 = 全一致、1 = 不一致あり。

var _failures := 0
var _checks := 0


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
	_test_tag_menu()
	_test_master_magic()
	_test_log_filter()
	_test_log_copy()
	_test_input_history()
	_test_tab_session()
	_test_images()
	_test_log_file()
	_test_config()
	_test_actions()
	_test_font_sizes()
	_test_digits()
	_test_clear_cache()
	_test_version()
	_test_list_titles()
	_test_list_overlay()
	# priv ウィンドウの popup は、ツリーが動き出してからでないと
	# 開けない(_initialize の中では is_inside_tree が false のため)。
	# 最初のフレームで試し、そこで結果を出して終える。
	process_frame.connect(_finish_priv_tests, CONNECT_ONE_SHOT)


func _finish_priv_tests() -> void:
	_test_priv_window()
	print("test_stage4: ", _checks, " checks, ", _failures, " failures")
	quit(1 if _failures > 0 else 0)


func _test_tag_menu() -> void:
	var tree := PhiTagMenu.parse(PhiTagMenu.DEFAULT_XML)
	_check_eq(str(tree.get("caption", "")), "タグ", "tag root caption")
	var children: Array = tree.get("children", [])
	_check_eq(children.size(), 4, "tag 4 submenus")
	_check_eq(str(children[0].get("caption", "")), "色タグ", "tag color submenu")
	var flat := PhiTagMenu.flatten(tree)
	_check_eq(flat.size(), 25, "tag 25 items")
	_check_eq(str(flat[0].get("tag", "")), "/*color=#", "tag first tag")
	_check_eq(str(flat[0].get("closetag", "")), "*//*.*/", "tag first closetag")
	_check_eq(PhiTagMenu.strip_mnemonic("色タグ(&C)"), "色タグ", "tag strip mnemonic")
	_check_eq(PhiTagMenu.strip_mnemonic("タグ"), "タグ", "tag strip no mnemonic")
	_check(PhiTagMenu.parse("not xml").is_empty(), "tag bad xml empty")


func _test_master_magic() -> void:
	var data := PhiMasterMagic.parse(PhiMasterMagic.DEFAULT_XML)
	_check_eq(str(data.get("caption", "")), "超魔法", "mm caption")
	var menus: Array = data.get("menus", [])
	_check_eq(menus.size(), 6, "mm 6 menus")
	_check_eq(str(menus[0].get("caption", "")), "移動魔法", "mm first menu")
	var items: Array = menus[0].get("items", [])
	_check_eq(str(items[0].get("caption", "")), "jump", "mm jump item")
	var steps: Array = items[0].get("steps", [])
	_check_eq(steps.size(), 5, "mm jump 5 steps")
	_check_eq(str(steps[0].get("kind", "")), "send", "mm jump step0 send")
	_check_eq(str(steps[0].get("text", "")), "cast", "mm jump step0 text")
	_check_eq(str(steps[0].get("list", "")), "no", "mm jump step0 list attr")
	_check_eq(str(steps[2].get("kind", "")), "int_dialog", "mm jump step2 int_dialog")
	_check_eq(str(steps[4].get("text", "")), "jump %int", "mm jump step4 text")
	_check(bool(items[2].get("separator", false)), "mm separator item")
	var malor_steps: Array = items[3].get("steps", [])
	_check_eq(str(malor_steps[0].get("kind", "")), "string_dialog", "mm malor string_dialog")
	_check(str(malor_steps[0].get("text", "")).contains("\n"), "mm malor newline")
	var evil_items: Array = menus[5].get("items", [])
	var evil_steps: Array = evil_items[0].get("steps", [])
	_check_eq(str(evil_steps[0].get("text", "")), "世界を停止させます。\nよろしいですか？", "mm ok_dialog newline")
	_check_eq(PhiMasterMagic.substitute("jump %int", "3", ""), "jump 3", "mm substitute int")
	_check_eq(PhiMasterMagic.substitute("malor %string", "", "10 20"), "malor 10 20", "mm substitute string")
	var many: Array = []
	for i in range(7):
		many.append({"kind": "send", "text": "x%d" % i})
	many.append({"kind": "ok_dialog", "text": "ok"})
	_check_eq(PhiMasterMagic.effective_steps(many).size(), 6, "mm 5 sends cap")
	_check(PhiMasterMagic.parse("not xml").get("menus", [1]).is_empty(), "mm bad xml no menus")


func _test_log_filter() -> void:
	var patterns := PhiLogFilter.parse_patterns("説明文\n/abc/\n/def/\n\n")
	_check_eq(patterns, ["abc", "def"], "filter parse patterns")
	var filter := PhiLogFilter.default_filter()
	_check_eq(filter.pattern_count(), 5, "filter 5 defaults")
	_check_eq(filter.bad_count, 0, "filter no bad defaults")
	_check(filter.matches("DM > Guest へメッセージを送りました"), "filter matches sent")
	_check(not filter.matches("DM > Guest は Cat を攻撃した. [6 hp]"), "filter no match attack")
	var bad := PhiLogFilter.new()
	bad.load_patterns(["ok", "([bad"])
	_check_eq(bad.pattern_count(), 1, "filter bad pattern skipped")
	_check_eq(bad.bad_count, 1, "filter bad pattern counted")
	_check(bad.matches("ok"), "filter good pattern works")


func _test_log_copy() -> void:
	_check_eq(PhiLogCopy.strip_time("12:34:56 hello"), "hello", "copy strip time plain")
	_check_eq(PhiLogCopy.strip_time("[12:34:56] hello"), "hello", "copy strip time bracket")
	_check_eq(PhiLogCopy.strip_time("hello"), "hello", "copy strip time none")
	_check_eq(PhiLogCopy.strip_name("[発言] Taro > hello"), "hello", "copy strip name talk")
	_check_eq(PhiLogCopy.strip_name("[priv] [Taro] > hello"), "hello", "copy strip name priv")
	_check_eq(PhiLogCopy.strip_name("DM > hello"), "hello", "copy strip name dm")
	_check_eq(PhiLogCopy.strip_name("plain line"), "plain line", "copy strip name none")
	_check_eq(PhiLogCopy.strip_tags("a /*color=red*/b/*.*/ c"), "a b c", "copy strip tags")
	_check_eq(PhiLogCopy.disable_tags("a /*color=red*/b"), "a ／*color=red*/b", "copy disable tags")
	var buffer := [
		{"display": "[発言] Taro > hello", "raw": "/*color=red*/Taro > hello"},
		{"display": "DM > hit", "raw": "DM > hit"},
	]
	_check_eq(PhiLogCopy.with_tags("[発言] Taro > hello", buffer), "/*color=red*/Taro > hello", "copy with tags hit")
	_check_eq(PhiLogCopy.with_tags("unknown", buffer), "unknown", "copy with tags miss")


func _test_input_history() -> void:
	_check_eq(PhiInputHistory.clamp_boundary("hello", 99), 5, "history clamp long")
	_check_eq(PhiInputHistory.clamp_boundary("hello", -3), 0, "history clamp negative")
	_check_eq(PhiInputHistory.draft_of("hello\nworld", 6), "world", "history draft")
	_check_eq(PhiInputHistory.draft_of("hello", 0), "hello", "history draft all")
	var advanced := PhiInputHistory.advance("hello", 0)
	_check_eq(str(advanced["text"]), "hello\n", "history advance text")
	_check_eq(int(advanced["boundary"]), 6, "history advance boundary")
	# 送信→下書きだけが送られ、境界が進む。
	var text := "hello"
	var boundary := 0
	var sent1 := PhiInputHistory.draft_of(text, boundary)
	_check_eq(sent1, "hello", "history send1 draft only")
	var after1 := PhiInputHistory.advance(text, boundary)
	text = str(after1["text"])
	boundary = int(after1["boundary"])
	text += "world"
	var sent2 := PhiInputHistory.draft_of(text, boundary)
	_check_eq(sent2, "world", "history send2 draft only")
	var after2 := PhiInputHistory.advance(text, boundary)
	_check_eq(str(after2["text"]), "hello\nworld\n", "history both remain")
	# クリアで履歴だけ消える。
	var cleared := PhiInputHistory.clear_history("hello\nworld", 6)
	_check_eq(str(cleared["text"]), "world", "history clear keeps draft")
	_check_eq(int(cleared["boundary"]), 0, "history clear boundary")
	# 送信は行単位 (2026-11-23 ユーザー決定)。Enter を押した行
	# だけが送られ、境界の後退 (旧仕様) は無い。行の取り出しは
	# line_at が担う。
	_check_eq(PhiInputHistory.line_at("one\ntwo\nthree", 0), "one", "history line first")
	_check_eq(PhiInputHistory.line_at("one\ntwo\nthree", 1), "two", "history line middle")
	_check_eq(PhiInputHistory.line_at("one\ntwo\nthree", 2), "three", "history line last")
	_check_eq(PhiInputHistory.line_at("one\ntwo\n", 2), "", "history line trailing empty")
	_check_eq(PhiInputHistory.line_at("one\ntwo", 99), "two", "history line clamp high")
	_check_eq(PhiInputHistory.line_at("one\ntwo", -1), "one", "history line clamp low")
	_check_eq(PhiInputHistory.line_at("", 0), "", "history line empty text")
	_check_eq(PhiInputHistory.line_at("solo", 0), "solo", "history line single")
	# 200行で古い方から切り捨てる。
	var long_text := ""
	for i in range(250):
		long_text += "line%d\n" % i
	var trimmed := PhiInputHistory.trim_old_lines(long_text, long_text.length())
	_check(str(trimmed["text"]).split("\n").size() <= PhiInputHistory.MAX_LINES + 1, "history trim lines")
	_check(not str(trimmed["text"]).contains("line0"), "history trim oldest")


func _test_tab_session() -> void:
	var parsed := PhiTabSession.parse("127.0.0.1\t20017\tGuest\nfoo.example\t20018\t\nbad line\n127.0.0.1\t99999\tX\n")
	_check_eq(parsed.size(), 2, "tabsession parse count")
	_check_eq(str(parsed[0]["host"]), "127.0.0.1", "tabsession parse host")
	_check_eq(int(parsed[0]["port"]), 20017, "tabsession parse port")
	_check_eq(str(parsed[0]["name"]), "Guest", "tabsession parse name")
	_check_eq(str(parsed[1]["name"]), "", "tabsession parse empty name")
	var text := PhiTabSession.serialize(parsed)
	_check_eq(text, "127.0.0.1\t20017\tGuest\nfoo.example\t20018\t\n", "tabsession serialize")
	_check(not text.contains("guest"), "tabsession no id saved")
	_check_eq(PhiTabSession.serialize([{"host": "", "port": 0, "name": "x"}]), "", "tabsession skip empty host")
	var tmp := "user://stage4_test_tabsession.ini"
	_check(PhiTabSession.save_file(parsed, tmp), "tabsession save file")
	var loaded := PhiTabSession.load_file(tmp)
	_check_eq(loaded.size(), 2, "tabsession load roundtrip")
	var dir := DirAccess.open("user://")
	if dir != null:
		dir.remove("stage4_test_tabsession.ini")


func _test_images() -> void:
	var refs := PhiImages.extract_refs("see /*img=http://127.0.0.1/a.png*/ and https://example.com/b.jpg. dup https://example.com/b.jpg")
	_check_eq(refs, ["http://127.0.0.1/a.png", "https://example.com/b.jpg"], "images extract dedup trim")
	var refs2 := PhiImages.extract_refs("/*IMAGE=https://h/x.gif*/")
	_check_eq(refs2, ["https://h/x.gif"], "images extract image tag case")
	_check_eq(PhiImages.extract_refs("no urls here"), [], "images extract none")
	var parsed := PhiImages.parse_url("http://127.0.0.1:8080/path?q=1")
	_check_eq(str(parsed["scheme"]), "http", "images parse scheme")
	_check_eq(str(parsed["host"]), "127.0.0.1", "images parse host")
	_check_eq(int(parsed["port"]), 8080, "images parse port")
	_check_eq(str(parsed["path"]), "/path?q=1", "images parse path")
	_check(PhiImages.parse_url("http://user@evil.com/x.png").is_empty(), "images reject userinfo")
	_check(PhiImages.parse_url("http://h:xx/x.png").is_empty(), "images reject bad port")
	_check(PhiImages.can_fetch("http://127.0.0.1/a.png", "127.0.0.1"), "images can fetch same host")
	_check(PhiImages.can_fetch("HTTP://127.0.0.1/a.png", "127.0.0.1"), "images can fetch scheme case")
	_check(not PhiImages.can_fetch("http://example.com/a.png", "127.0.0.1"), "images refuse other host")
	_check(not PhiImages.can_fetch("http://127.0.0.1/a.png", ""), "images refuse empty host")
	_check(not PhiImages.can_fetch("ftp://127.0.0.1/a.png", "127.0.0.1"), "images refuse ftp")


func _test_log_file() -> void:
	_check_eq(PhiLogFile.sanitize_name("Guest"), "Guest", "logfile sanitize plain")
	_check_eq(PhiLogFile.sanitize_name("a/b:c"), "a_b_c", "logfile sanitize separators")
	_check_eq(PhiLogFile.sanitize_name(""), "character", "logfile sanitize empty")
	_check_eq(PhiLogFile.log_path("user://Logs", "Guest", false, "20261117"), "user://Logs/Guest_20261117.log", "logfile text path")
	_check_eq(PhiLogFile.log_path("user://Logs", "Guest", true, "20261117"), "user://Logs/Guest_20261117.html", "logfile html path")
	_check_eq(PhiLogFile.format_text_line("hello", true, "12:34:56"), "[12:34:56] hello", "logfile text line time")
	_check_eq(PhiLogFile.format_text_line("hello", false, "12:34:56"), "hello", "logfile text line plain")
	_check_eq(PhiLogFile.escape_html("<a>&\"b\""), "&lt;a&gt;&amp;&quot;b&quot;", "logfile escape html")
	_check_eq(PhiLogFile.format_html_line("a<b"), "a&lt;b<br>\n", "logfile html line")
	var dir := "user://stage4_test_logs"
	_check(PhiLogFile.append_line(dir, "Guest", false, "line1"), "logfile append text")
	_check(PhiLogFile.append_line(dir, "Guest", false, "line2"), "logfile append text2")
	var text := FileAccess.get_file_as_string(PhiLogFile.log_path(dir, "Guest", false))
	_check_eq(text, "line1\nline2\n", "logfile text content")
	_check(PhiLogFile.append_line(dir, "Guest", true, "a<b"), "logfile append html")
	var html := FileAccess.get_file_as_string(PhiLogFile.log_path(dir, "Guest", true))
	_check(html.begins_with("<!DOCTYPE html>") or html.contains("<html"), "logfile html header")
	_check(html.contains("a&lt;b<br>"), "logfile html body")
	var log_dir := DirAccess.open(dir)
	if log_dir != null:
		log_dir.remove(PhiLogFile.log_path(dir, "Guest", false).get_file())
		log_dir.remove(PhiLogFile.log_path(dir, "Guest", true).get_file())
	var user_dir := DirAccess.open("user://")
	if user_dir != null:
		user_dir.remove("stage4_test_logs")


func _test_config() -> void:
	var cfg := PhiConfig.new()
	cfg.log_auto_save = true
	cfg.log_save_dir = "user://MyLogs"
	cfg.log_save_html = false
	cfg.log_save_delete_tag = true
	cfg.log_save_text_with_time = false
	cfg.log_delete_filter = false
	cfg.load_tab_session = false
	cfg.mclick_tab_close = false
	var tmp := "user://stage4_test_config.ini"
	_check(cfg.save_file(tmp), "config save")
	var loaded := PhiConfig.new()
	_check(loaded.load_file(tmp), "config load")
	_check_eq(loaded.log_auto_save, true, "config log_auto_save")
	_check_eq(loaded.log_save_dir, "user://MyLogs", "config log_save_dir")
	_check_eq(loaded.log_save_html, false, "config log_save_html")
	_check_eq(loaded.log_save_delete_tag, true, "config log_save_delete_tag")
	_check_eq(loaded.log_save_text_with_time, false, "config log_save_text_with_time")
	_check_eq(loaded.log_delete_filter, false, "config log_delete_filter")
	_check_eq(loaded.load_tab_session, false, "config load_tab_session")
	_check_eq(loaded.mclick_tab_close, false, "config mclick_tab_close")
	loaded.reset()
	_check_eq(loaded.log_auto_save, false, "config reset autosave")
	_check_eq(loaded.log_save_html, true, "config reset html")
	_check_eq(loaded.log_delete_filter, true, "config reset filter")
	_check_eq(loaded.load_tab_session, true, "config reset tabsession")
	var dir := DirAccess.open("user://")
	if dir != null:
		dir.remove("stage4_test_config.ini")


func _test_actions() -> void:
	for action_name in ["SayAllTabs", "LogAutoSave", "LogDeleteFilter", "ImageWindow"]:
		var action := PhiActions.get_action(action_name)
		_check(not action.is_empty(), "actions has " + action_name)
		_check(not str(action.get("caption", "")).is_empty(), "actions caption " + action_name)
		_check(not str(action.get("hint", "")).is_empty(), "actions hint " + action_name)
	_check_eq(PhiActions.kind_of("SayAllTabs"), "say-all-tabs", "actions kind say-all-tabs")
	_check_eq(PhiActions.kind_of("LogAutoSave"), "autosave-toggle", "actions kind autosave")
	_check(PhiActions.enabled_when("SayAllTabs", true), "actions say-all enabled connected")
	_check(not PhiActions.enabled_when("SayAllTabs", false), "actions say-all disabled offline")
	_check(PhiActions.enabled_when("ImageWindow", false), "actions image-window always enabled")


func _test_font_sizes() -> void:
	_check_eq(PhiFont.ui_size_for_zoom(1), 6, "font ui zoom1")
	_check_eq(PhiFont.ui_size_for_zoom(3), 16, "font ui zoom3")
	_check_eq(PhiFont.chrome_size_for_zoom(1), 6, "font chrome zoom1 unified")
	_check_eq(PhiFont.chrome_size_for_zoom(3), 16, "font chrome zoom3 unified")


func _test_digits() -> void:
	_check_eq(PhiDigits.to_half_width_digits("１２３"), "123", "digits fullwidth")
	_check_eq(PhiDigits.to_half_width_digits("－４２"), "-42", "digits minus")
	_check_eq(PhiDigits.to_half_width_digits("３．１４"), "3.14", "digits period")
	_check_eq(PhiDigits.to_half_width_digits("a１b２"), "a1b2", "digits mixed")
	_check_eq(PhiDigits.to_half_width_digits("こんにちは１２３"), "こんにちは123", "digits japanese kept")
	_check_eq(PhiDigits.to_half_width_digits("１２３円です"), "123円です", "digits japanese suffix kept")
	_check_eq(PhiDigits.to_half_width_digits("123"), "123", "digits already half")
	_check_eq(PhiDigits.to_half_width_digits(""), "", "digits empty")


func _test_priv_window() -> void:
	# ×ボタン(close_requested)で隠れる。
	var win := PhiPrivWindow.new()
	root.add_child(win)
	win.show()
	_check(win.visible, "priv visible after show")
	win.close_requested.emit()
	_check(not win.visible, "priv hidden after close_requested")
	# トグル動作。
	win.toggle()
	_check(win.visible, "priv toggle shows")
	win.toggle()
	_check(not win.visible, "priv toggle hides")
	# 宛先から自分を除く。
	var users := [
		{"key": "1", "name": "自分"},
		{"key": "2", "name": "他人"},
		{"key": "3", "name": "自分2"},
	]
	win.rebuild_recipients(users, "自分")
	_check_eq(win.recipient_names(), ["他人", "自分2"], "priv exclude self")
	win.rebuild_recipients(users, "")
	_check_eq(win.recipient_names(), ["自分", "他人", "自分2"], "priv no exclude when unknown")
	# チェック状態は作り直しで引き継ぐ。
	win.set_checked("2", true)
	win.rebuild_recipients(users, "")
	_check_eq(win.checked_keys(), ["2"], "priv check preserved")
	_check_eq(win._title_label.text, "他人", "priv title checked name")
	win.queue_free()


func _test_clear_cache() -> void:
	## clear_cache の前後で chara()/chip() の返す画像データが変わらない。
	## 素材フォルダが無い環境では飛ばす。
	var home := OS.get_environment("HOME")
	var chara_dir := home.path_join("workspace/phi-option-data/chara_tofup")
	var chip_dir := home.path_join("workspace/phi-option-data/chip_tofup")
	if DirAccess.open(chara_dir) == null or DirAccess.open(chip_dir) == null:
		print("test_stage4: asset dirs missing, clear-cache checks skipped")
		return
	var assets := GameAssets.new()
	var roots: Array[String] = []
	var chips: Array[String] = [chip_dir]
	var charas: Array[String] = [chara_dir]
	assets.setup(roots, chips, charas, "Mine")
	var before: Variant = assets.chara("x", "t_Lord", 5)
	_check(before != null, "clearcache chara before")
	var before_img := (before as Texture2D).get_image()
	var before_data := before_img.get_data()
	assets.clear_cache()
	var after: Variant = assets.chara("x", "t_Lord", 5)
	_check(after != null, "clearcache chara after")
	var after_img := (after as Texture2D).get_image()
	_check_eq(after_img.get_size(), before_img.get_size(), "clearcache chara size")
	_check_eq(after_img.get_data(), before_data, "clearcache chara pixels")
	var chip_before: Variant = assets.chip("")
	_check(chip_before != null, "clearcache chip before")
	var chip_before_data := (chip_before as Texture2D).get_image().get_data()
	assets.clear_cache()
	var chip_after: Variant = assets.chip("")
	_check(chip_after != null, "clearcache chip after")
	_check_eq((chip_after as Texture2D).get_image().get_data(), chip_before_data, "clearcache chip pixels")
	# 地図ビューの絵の取り直しが落ちない。
	var view := MapView.new()
	view.assets = assets
	view.reload_cached_textures()
	_check(true, "clearcache map reload no crash")
	view.queue_free()
	# 温め: clear_cache → reload のあとは、chara() がキャッシュから
	# 返る(再デコード無し)。VM では白く描かれる現象そのものは
	# 再現できないので、この温まりが代わりの検証になる。
	var view2 := MapView.new()
	view2.set_map({"size": 7, "chars": [{"name": "x", "gra": "t_Lord", "default": 5, "x": 3, "y": 3}]}, assets, "")
	assets.clear_cache()
	_check((assets.get("_cache") as Dictionary).is_empty(), "clearcache cache empty")
	view2.reload_cached_textures()
	_check((assets.get("_cache") as Dictionary).has("chara?x&t_Lord&5&"), "clearcache warmed chara key")
	var w1: Variant = assets.chara("x", "t_Lord", 5)
	var w2: Variant = assets.chara("x", "t_Lord", 5)
	_check(w1 != null and w1 == w2, "clearcache warmed same texture")
	view2.queue_free()


func _test_version() -> void:
	_check_eq(PhiVersion.VERSION, "0.7.2", "version number")
	var action: Dictionary = PhiActions.get_action("VersionInfo")
	_check_eq(str(action.get("caption", "")), "NeoPHI " + PhiVersion.VERSION, "version menu caption")
	_check_eq(str(action.get("hint", "")), "バージョン情報を表示する", "version menu hint kept")
	var body := PhiVersion.about_text()
	_check(body.begins_with("NeoPHI"), "version about app name line")
	_check(body.contains("Phantasmal Island Client"), "version about subtitle")
	_check(body.contains("バージョン " + PhiVersion.VERSION), "version about version line")
	_check(body.contains("Godot "), "version about engine line")
	_check(not body.contains("Philly"), "version about no description")
	# 作者名は About ダイアログにだけ入れる(メニュー項目名には入れない)。
	_check_eq(PhiVersion.AUTHOR, "Master NEO", "version author name")
	_check(body.contains("作者 Master NEO"), "version about author line")
	_check(not str(action.get("caption", "")).contains("Master NEO"), "version menu caption has no author")


func _test_list_titles() -> void:
	_check_eq(PhiCharacter.list_title_for_command("cast"), "魔法リスト", "list title cast")
	_check_eq(PhiCharacter.list_title_for_command("CAST"), "魔法リスト", "list title cast upper")
	_check_eq(PhiCharacter.list_title_for_command("equip"), "装備リスト", "list title equip")
	_check_eq(PhiCharacter.list_title_for_command("unequip"), "装備リスト", "list title unequip")
	_check_eq(PhiCharacter.list_title_for_command("get"), "アイテムリスト", "list title get")
	_check_eq(PhiCharacter.list_title_for_command("put"), "アイテムリスト", "list title put")
	_check_eq(PhiCharacter.list_title_for_command("use"), "アイテムリスト", "list title use")
	_check_eq(PhiCharacter.list_title_for_command("go"), "リスト", "list title unknown")
	_check_eq(PhiCharacter.list_title_for_command(""), "リスト", "list title empty")
	_check_eq(PhiCharacter.list_title_for_command("xyz", "魔法を選んでください"), "魔法リスト", "list title prompt magic")
	_check_eq(PhiCharacter.list_title_for_command("xyz", "装備を選んでください"), "装備リスト", "list title prompt equip")
	_check_eq(PhiCharacter.list_title_for_command("xyz", "アイテムを選んでください"), "アイテムリスト", "list title prompt item")
	_check_eq(PhiCharacter.list_title_for_command("xyz", "どれにしますか"), "リスト", "list title prompt unknown")


func _test_list_overlay() -> void:
	var tab := PhiCharacter.new()
	tab.map_view = MapView.new()
	tab.map_view.size = Vector2(700, 700)
	tab.add_child(tab.map_view)
	tab._build_list_overlay()
	# 決定ボタンは無い。残るキャンセルボタンの文字サイズは
	# リストと同じ大きさで、高さも付く。
	tab._apply_list_font_size(21)
	var has_ok := false
	for p in tab.get_property_list():
		if str(p.get("name", "")) == "_list_ok_button":
			has_ok = true
	_check(not has_ok, "list ok button removed")
	var cancel_button := tab.get("_list_cancel_button") as Button
	var list_box := tab.get("_list_box") as ItemList
	var header := tab.get("_list_header") as Label
	_check_eq(cancel_button.get_theme_font_size("font_size"), 21, "list cancel button font size")
	_check_eq(list_box.get_theme_font_size("font_size"), 21, "list box font size")
	_check_eq(header.get_theme_font_size("font_size"), 21, "list header font size")
	_check_eq(cancel_button.custom_minimum_size.y, 37.0, "list cancel button min height")
	# 送った文の先頭の言葉を覚える。
	tab._note_sent("cast\n1")
	_check_eq(str(tab.get("_last_command")), "cast", "list note sent cast")
	tab._note_sent("  equip sword")
	_check_eq(str(tab.get("_last_command")), "equip", "list note sent equip")
	tab._note_sent("")
	_check_eq(str(tab.get("_last_command")), "equip", "list note sent empty keeps")
	# ドラッグでパネルの位置が変わる。
	var panel := tab.get("_list_panel") as PanelContainer
	panel.size = Vector2(200, 100)
	panel.position = Vector2(8, 8)
	panel.visible = true
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = Vector2(20, 20)
	press.global_position = Vector2(20, 20)
	tab._on_list_header_gui_input(press)
	_check(bool(tab.get("_list_dragging")), "list drag starts")
	var motion := InputEventMouseMotion.new()
	motion.position = Vector2(120, 120)
	motion.global_position = Vector2(120, 120)
	tab.handle_mouse_motion(motion)
	_check_eq(panel.position, Vector2(108, 108), "list drag moves panel")
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.position = Vector2(120, 120)
	tab.handle_mouse_button(release)
	_check(not bool(tab.get("_list_dragging")), "list drag stops on release")
	motion.position = Vector2(200, 200)
	tab.handle_mouse_motion(motion)
	_check_eq(panel.position, Vector2(108, 108), "list drag no move after release")
	# 地図の端を超えて動かしても、地図の中に収まる。
	press.position = Vector2(120, 120)
	press.global_position = Vector2(120, 120)
	tab._on_list_header_gui_input(press)
	motion.position = Vector2(690, 690)
	motion.global_position = Vector2(690, 690)
	tab.handle_mouse_motion(motion)
	_check_eq(panel.position, Vector2(500, 600), "list drag clamps to map")
	tab.queue_free()
