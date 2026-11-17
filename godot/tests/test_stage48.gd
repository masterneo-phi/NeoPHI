extends SceneTree
## 第48段: ログへの画像埋め込み表示 (Philly LogImageDisp)。
## - PhiImages.tag_spans が /*img=*/ /*image=*/ の位置と URL、
##   width/height 属性を取る。
## - 取得済みの画像は行内に画像そのもので出る (parsed text に
##   U+FFFC が入る)。未取得なら [画像: URL] の文字のまま。
## - 画像が届いた後の描き直しで、文字だった行が画像になる。
## - 設定 off の間は画像で出ない。記録 (display) は不変。

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
	# tag_spans
	var spans := PhiImages.tag_spans("前 /*img=http://example.com/a.png*/ 後")
	check(spans.size() == 1, "one span")
	check(str(spans[0]["url"]) == "http://example.com/a.png", "span url")
	check(int(spans[0]["start"]) == 2 and int(spans[0]["end"]) == 34, "span range")
	var spans2 := PhiImages.tag_spans("/*image=http://x/b.jpg width=120 height=80*/x/*img=http://x/c.png*/")
	check(spans2.size() == 2, "two spans")
	check(int(spans2[0]["width"]) == 120 and int(spans2[0]["height"]) == 80, "span size attrs")
	check(str(spans2[1]["url"]) == "http://x/c.png", "second span url")
	check(PhiImages.tag_spans("ただの http://example.com/a.png 行").is_empty(), "bare url is not a tag span")
	check(PhiImages.decode_image(PackedByteArray([1, 2, 3])) == null, "decode rejects garbage")

	var main: Node = Main.new()
	root.add_child(main)
	await process_frame
	await process_frame
	var tab: Variant = main.call("_active_tab")
	var config: Variant = main.get("_config")
	config.log_image_disp = true
	tab.log_view.custom_minimum_size = Vector2(600, 200)
	# テクスチャを用意して共有キャッシュへ入れる (背の高い画像で、
	# 埋め込まれたらログ欄の内容の高さが伸びることで確認する)。
	var img := Image.create(40, 120, false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 0, 0))
	var tex := ImageTexture.create_from_image(img)
	var url := "http://example.com/banner.png"
	PhiCharacter.store_image_texture(url, tex)
	check(tab.image_state(url) == "cached", "state cached")
	await process_frame
	var h0: int = tab.log_view.get_content_height()
	# 取得済み: 行内に画像で出る。
	var raw := "前 /*img=" + url + "*/ 後"
	tab.log_message("log", PhiTags.plain_text(raw), raw)
	await process_frame
	var parsed: String = tab.log_view.get_parsed_text()
	check(parsed.contains("前") and parsed.contains("後"), "text around image kept")
	check(tab.log_view.get_content_height() >= h0 + 100, "image embedded inline")
	var entry: Dictionary = tab.get("_log_lines").back()
	check(str(entry["display"]).contains("[画像: " + url + "]"), "record keeps placeholder text")
	check((entry["imgs"] as Array).size() == 1, "entry records the img url")
	# 未取得: 文字のまま出て、取得が始まる。
	var url2 := "http://127.0.0.1:9/none.png"
	var raw2 := "/*img=" + url2 + "*/"
	var h1: int = tab.log_view.get_content_height()
	tab.log_message("log", PhiTags.plain_text(raw2), raw2)
	await process_frame
	check(tab.image_state(url2) == "loading", "fetch started for uncached image")
	var parsed2: String = tab.log_view.get_parsed_text()
	check(parsed2.contains("[画像: " + url2 + "]"), "uncached image stays text")
	check(tab.log_view.get_content_height() < h1 + 60, "uncached image adds no height")
	# 届いたことにして描き直すと画像になる。
	PhiCharacter.store_image_texture(url2, tex)
	tab.call("_rebuild_log_view")
	await process_frame
	await process_frame
	var parsed3: String = tab.log_view.get_parsed_text()
	# 描き直し後は通常行の高さが変わるので、絶対量で見る
	# (通常行 5 行 + 画像 2 枚 ×120)。
	check(tab.log_view.get_content_height() >= 240, "rebuild embeds arrived images")
	check(not parsed3.contains("[画像: " + url2 + "]"), "placeholder replaced after rebuild")
	# 設定 off: 画像で出ない。
	config.log_image_disp = false
	var url3 := "http://example.com/third.png"
	PhiCharacter.store_image_texture(url3, tex)
	var h3: int = tab.log_view.get_content_height()
	var raw3 := "/*img=" + url3 + "*/"
	tab.log_message("log", PhiTags.plain_text(raw3), raw3)
	await process_frame
	var parsed4: String = tab.log_view.get_parsed_text()
	check(parsed4.contains("[画像: " + url3 + "]"), "toggle off keeps text")
	check(tab.log_view.get_content_height() < h3 + 60, "toggle off adds no height")
	check(tab.image_state(url3) == "cached", "state still cached when off")
	config.log_image_disp = true
	# 小さい画像はログ欄の幅に合わせて拡大する。
	var small := Image.create(100, 40, false, Image.FORMAT_RGBA8)
	small.fill(Color(0, 0.6, 0))
	var url4 := "http://example.com/small.png"
	PhiCharacter.store_image_texture(url4, ImageTexture.create_from_image(small))
	await process_frame
	var h4: int = tab.log_view.get_content_height()
	var raw4 := "/*img=" + url4 + "*/"
	tab.log_message("log", PhiTags.plain_text(raw4), raw4)
	await process_frame
	check(tab.log_view.get_content_height() >= h4 + 80, "small image scales up to log width")
	print("stage48: ", _checks, " checks, ", _failures, " failures")
	quit(1 if _failures > 0 else 0)
