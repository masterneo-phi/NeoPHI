extends SceneTree
## 第144段: バナー画像行もログのバッチ順序を守る。
## - バースト受信中、/*img= 行が先行するテキスト行を追い越さず、
##   テキスト行と同じ表示待ちキューへ受信順に並ぶ (ログイン時の
##   バナー画像がバージョン行より上に割り込んでいた不具合の修正)。
## - キャッシュ済みの画像は、その行が表示される時に埋め込まれる。
## - 未取得の画像は [画像: URL] の文字で順序どおりに出て、
##   取得後の描き直しで順序のまま画像になる。

const Main := preload("res://scripts/main.gd")

var _checks := 0
var _failures := 0


func check(cond: bool, label: String) -> void:
	_checks += 1
	if not cond:
		_failures += 1
		print("FAIL: ", label)


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var main: Node = Main.new()
	var iso := ProjectSettings.globalize_path("user://stage144_tabs.ini")
	OS.execute("rm", ["-f", iso])
	main.set("_tab_session_path", "user://stage144_tabs.ini")
	var isoc := ProjectSettings.globalize_path("user://stage144_cfg.ini")
	OS.execute("rm", ["-f", isoc])
	main.set("_config_path", "user://stage144_cfg.ini")
	root.add_child(main)
	await process_frame
	await process_frame
	var tab: Variant = main.call("_active_tab")
	var config: Variant = main.get("_config")
	config.log_image_disp = true
	config.ui_style = "old"
	tab.call("apply_ui_style")
	tab.log_view.custom_minimum_size = Vector2(600, 200)
	# バナー画像のテクスチャをキャッシュへ入れておく (背の高い
	# 画像にし、埋め込まれたらログ欄の高さが伸びることで見る)。
	var img := Image.create(40, 120, false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 0, 0))
	var tex := ImageTexture.create_from_image(img)
	var url := "http://example.com/login_banner.png"
	PhiCharacter.store_image_texture(url, tex)
	await process_frame
	var h0: int = tab.log_view.get_content_height()
	# ログイン直後のバーストを再現する: バージョン行 → バナー
	# 画像行 → 歓迎行 の順に届く。画像行には前後の文字を付け、
	# parsed text 上の位置で順序を見る。
	tab.set("_log_batching", true)
	tab.log_message("log", "VERSION_LINE_MARK", "VERSION_LINE_MARK")
	var raw := "IMG_BEFORE /*img=" + url + "*/ IMG_AFTER"
	tab.log_message("log", PhiTags.plain_text(raw), raw)
	tab.log_message("log", "WELCOME_LINE_MARK", "WELCOME_LINE_MARK")
	tab.set("_log_batching", false)
	check(int(tab.call("log_display_backlog")) == 3,
		"image line queues with text during burst")
	tab.call("_flush_log_batch")
	await process_frame
	var parsed: String = tab.log_view.get_parsed_text()
	var iv := parsed.find("VERSION_LINE_MARK")
	var ib := parsed.find("IMG_BEFORE")
	var ia := parsed.find("IMG_AFTER")
	var iw := parsed.find("WELCOME_LINE_MARK")
	check(iv >= 0 and ib > iv, "banner image lands after version line")
	check(ia > ib and iw > ia, "welcome line lands after banner image")
	check(not parsed.contains("[画像: " + url + "]"),
		"cached banner embeds at display, no placeholder")
	check(tab.log_view.get_content_height() >= h0 + 130,
		"cached banner image embedded inline (height grew)")
	# 未取得の画像もバースト中は順序を守り、文字で出る。
	var url2 := "http://127.0.0.1:9/banner2.png"
	tab.set("_log_batching", true)
	tab.log_message("log", "BEFORE_MARK", "BEFORE_MARK")
	var raw2 := "/*img=" + url2 + "*/"
	tab.log_message("log", PhiTags.plain_text(raw2), raw2)
	tab.log_message("log", "AFTER_MARK", "AFTER_MARK")
	tab.set("_log_batching", false)
	tab.call("_flush_log_batch")
	await process_frame
	var parsed2: String = tab.log_view.get_parsed_text()
	var ib2 := parsed2.find("BEFORE_MARK")
	var ip := parsed2.find("[画像: " + url2 + "]")
	var ia2 := parsed2.find("AFTER_MARK")
	check(ib2 >= 0 and ip > ib2 and ia2 > ip,
		"uncached banner placeholder keeps order")
	# 取得が終わって描き直すと、順序のまま画像に置き換わる。
	PhiCharacter.store_image_texture(url2, tex)
	tab.call("_rebuild_log_view")
	await process_frame
	await process_frame
	var parsed3: String = tab.log_view.get_parsed_text()
	check(not parsed3.contains("[画像: " + url2 + "]"),
		"placeholder replaced after fetch and rebuild")
	print("stage144: ", _checks, " checks, ", _failures, " failures")
	quit(1 if _failures > 0 else 0)
