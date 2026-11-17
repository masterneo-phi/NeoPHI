extends SceneTree
## 第1段(設定・スキン・アクション表)のテスト。
##
## 使い方: godot --headless --path . -s tests/test_stage1.gd
## 終了コード 0 = 全一致、1 = 不一致あり。
## Philly の実ソースがある場合は、実ファイルに対する検査も行う
## (無ければその部分だけ飛ばす)。

var _failures := 0
var _checks := 0
var _tmp_files: Array[String] = []
var _tmp_dirs: Array[String] = []

const PHILLY_ROOT := "/home/hatch/workspace/philly-source/PhillySrc/Philly"


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


func _check_color(a: Variant, r: float, g: float, b: float, label: String) -> void:
	_checks += 1
	if a == null or not (a is Color):
		_failures += 1
		printerr("FAIL: ", label, " (got ", a, ", want color)")
		return
	var c := a as Color
	if absf(c.r - r) > 0.01 or absf(c.g - g) > 0.01 or absf(c.b - b) > 0.01:
		_failures += 1
		printerr("FAIL: ", label, " (got ", c, ")")


# -- バイト列の組み立て ---------------------------------------------------

func _u16(v: int) -> PackedByteArray:
	return PackedByteArray([v & 0xFF, (v >> 8) & 0xFF])


func _u32(v: int) -> PackedByteArray:
	return PackedByteArray([v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, (v >> 24) & 0xFF])


func _s32(v: int) -> PackedByteArray:
	return _u32(v & 0xFFFFFFFF)


func _make_bmp24(w: int, h: int, pixels: Array) -> PackedByteArray:
	## 24 ビット BMP。pixels は上から [r, g, b] の並び。
	var row_bytes := ((w * 3 + 3) / 4) * 4
	var data := PackedByteArray()
	data.append_array("BM".to_ascii_buffer())
	data.append_array(_u32(54 + row_bytes * h))
	data.append_array(_u32(0))
	data.append_array(_u32(54))
	data.append_array(_u32(40))
	data.append_array(_s32(w))
	data.append_array(_s32(h))
	data.append_array(_u16(1))
	data.append_array(_u16(24))
	data.append_array(_u32(0))
	data.append_array(_u32(row_bytes * h))
	data.append_array(_s32(2835))
	data.append_array(_s32(2835))
	data.append_array(_u32(0))
	data.append_array(_u32(0))
	for y in range(h - 1, -1, -1):
		for x in w:
			var px: Array = pixels[y * w + x]
			data.append(px[2])
			data.append(px[1])
			data.append(px[0])
		for i in row_bytes - w * 3:
			data.append(0)
	return data


func _make_cur_1bpp() -> PackedByteArray:
	## 2x2・1 ビットのカーソル。ホットスポット (1, 1)。
	## 上段: 黒・白(不透明)、下段: 透明・黒(不透明)。
	var dib := PackedByteArray()
	dib.append_array(_u32(40))
	dib.append_array(_s32(2))
	dib.append_array(_s32(4))
	dib.append_array(_u16(1))
	dib.append_array(_u16(1))
	dib.append_array(_u32(0))
	dib.append_array(_u32(0))
	dib.append_array(_s32(0))
	dib.append_array(_s32(0))
	dib.append_array(_u32(0))
	dib.append_array(_u32(0))
	# パレット: 0=黒、1=白
	dib.append_array(PackedByteArray([0, 0, 0, 0, 255, 255, 255, 0]))
	# XOR マスク(下段から): 下段 10、上段 01
	dib.append_array(PackedByteArray([0x80, 0, 0, 0, 0x40, 0, 0, 0]))
	# AND マスク(下段から): 下段の x=0 だけ透明
	dib.append_array(PackedByteArray([0x80, 0, 0, 0, 0x00, 0, 0, 0]))
	var out := PackedByteArray()
	out.append_array(_u16(0))
	out.append_array(_u16(2))
	out.append_array(_u16(1))
	out.append(2)
	out.append(2)
	out.append(0)
	out.append(0)
	out.append_array(_u16(1))
	out.append_array(_u16(1))
	out.append_array(_u32(dib.size()))
	out.append_array(_u32(22))
	out.append_array(dib)
	return out


func _make_cur_24bpp() -> PackedByteArray:
	## 2x1・24 ビットのカーソル。赤・緑(どちらも不透明)。
	var dib := PackedByteArray()
	dib.append_array(_u32(40))
	dib.append_array(_s32(2))
	dib.append_array(_s32(2))
	dib.append_array(_u16(1))
	dib.append_array(_u16(24))
	dib.append_array(_u32(0))
	dib.append_array(_u32(0))
	dib.append_array(_s32(0))
	dib.append_array(_s32(0))
	dib.append_array(_u32(0))
	dib.append_array(_u32(0))
	# XOR: 赤(0,0,255)・緑(0,255,0) + パディング
	dib.append_array(PackedByteArray([0, 0, 255, 0, 255, 0, 0, 0]))
	# AND: 全部不透明
	dib.append_array(PackedByteArray([0, 0, 0, 0]))
	var out := PackedByteArray()
	out.append_array(_u16(0))
	out.append_array(_u16(2))
	out.append_array(_u16(1))
	out.append(2)
	out.append(1)
	out.append(0)
	out.append(0)
	out.append_array(_u16(0))
	out.append_array(_u16(0))
	out.append_array(_u32(dib.size()))
	out.append_array(_u32(22))
	out.append_array(dib)
	return out


func _write_tmp(path: String, data: PackedByteArray) -> void:
	var dir := path.get_base_dir()
	DirAccess.make_dir_recursive_absolute(dir)
	_tmp_dirs.append(dir)
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_buffer(data)
	f.close()
	_tmp_files.append(path)


func _cleanup_tmp() -> void:
	for path in _tmp_files:
		DirAccess.remove_absolute(path)
	_tmp_files.clear()
	_tmp_dirs.reverse()
	for dir in _tmp_dirs:
		DirAccess.remove_absolute(dir)
	_tmp_dirs.clear()


# -- 設定 -----------------------------------------------------------------

func _test_config() -> void:
	var cfg := PhiConfig.new()
	_check_eq(cfg.host, "127.0.0.1", "config default host")
	_check_eq(cfg.port, 20017, "config default port")
	_check_eq(cfg.skin, "Mine", "config default skin")
	_check_eq(cfg.map_size, 81, "config default map size")
	_check_eq(cfg.map_style, "solid", "config default map style")
	_check_eq(cfg.window_width, 1280, "config default window width")
	_check_eq(cfg.window_height, 1024, "config default window height")
	_check_eq(cfg.split_ratio, 0.62, "config default split ratio")
	_check_eq(cfg.scroll_stop, false, "config default scroll stop")
	_check_eq(cfg.split_offset_for(1280, 6), 794, "config split 1280")
	_check_eq(cfg.split_offset_for(1000, 6), 620, "config split 1000")
	# ログの最小幅 280 を保つ
	_check_eq(cfg.split_offset_for(500, 6), 214, "config split log min")
	_check_eq(cfg.split_offset_for(200, 6), 0, "config split tiny")
	cfg.split_ratio = 0.3
	_check_eq(cfg.split_offset_for(1000, 6), 300, "config split saved ratio")
	cfg.split_ratio = 0.55

	var path := OS.get_temp_dir().path_join("neophi-test-config.ini")
	DirAccess.remove_absolute(path)
	cfg.host = "192.0.2.1"
	cfg.port = 20018
	cfg.skin = "TestSkin"
	cfg.map_size = 40
	cfg.map_style = "turn"
	cfg.window_width = 900
	cfg.window_height = 700
	cfg.split_ratio = 0.4
	cfg.scroll_stop = true
	_check(cfg.save_file(path), "config save")
	_tmp_files.append(path)
	# Philly.ini 互換のセクション名で書かれていること
	var text := FileAccess.get_file_as_string(path)
	for section in ["[Connection]", "[Skin]", "[Map]", "[Disp]", "[Log]"]:
		_check(text.contains(section), "config section " + section)
	_check(text.contains("SkinName"), "config SkinName key")
	_check(text.contains("MapSize"), "config MapSize key")
	_check(text.contains("MapStyle"), "config MapStyle key")

	var cfg2 := PhiConfig.new()
	_check(cfg2.load_file(path), "config load")
	_check_eq(cfg2.host, "192.0.2.1", "config roundtrip host")
	_check_eq(cfg2.port, 20018, "config roundtrip port")
	_check_eq(cfg2.skin, "TestSkin", "config roundtrip skin")
	_check_eq(cfg2.map_size, 40, "config roundtrip map size")
	_check_eq(cfg2.map_style, "turn", "config roundtrip map style")
	_check_eq(cfg2.window_width, 900, "config roundtrip window width")
	_check_eq(cfg2.window_height, 700, "config roundtrip window height")
	_check_eq(cfg2.split_ratio, 0.4, "config roundtrip split ratio")
	_check_eq(cfg2.scroll_stop, true, "config roundtrip scroll stop")

	# おかしな値は既定値に戻る
	var bad := ConfigFile.new()
	bad.set_value("Connection", "Host", "")
	bad.set_value("Connection", "Port", 70000)
	bad.set_value("Skin", "SkinName", "")
	bad.set_value("Map", "MapSize", 99)
	bad.set_value("Map", "MapStyle", "bogus")
	bad.set_value("Disp", "WindowWidth", 100)
	bad.set_value("Disp", "WindowHeight", 100)
	bad.set_value("Disp", "SplitRatio", 9.9)
	var bad_path := OS.get_temp_dir().path_join("neophi-test-config-bad.ini")
	bad.save(bad_path)
	_tmp_files.append(bad_path)
	var cfg3 := PhiConfig.new()
	_check(cfg3.load_file(bad_path), "config load bad file")
	_check_eq(cfg3.host, "127.0.0.1", "config bad host")
	_check_eq(cfg3.port, 20017, "config bad port")
	_check_eq(cfg3.skin, "Mine", "config bad skin")
	_check_eq(cfg3.map_size, 81, "config bad map size")
	_check_eq(cfg3.map_style, "solid", "config bad map style")
	_check_eq(cfg3.window_width, 1280, "config bad window width")
	_check_eq(cfg3.window_height, 1024, "config bad window height")
	_check_eq(cfg3.split_ratio, 0.85, "config bad split ratio clamped")

	# 古い設定(絶対ピクセルの SplitOffset)は、保存時の地図幅を保つよう
	# 窓幅から右列分を引いた幅に対する比率に移行する
	var old := ConfigFile.new()
	old.set_value("Disp", "WindowWidth", 1280)
	old.set_value("Disp", "SplitOffset", 704)
	var old_path := OS.get_temp_dir().path_join("neophi-test-config-old.ini")
	old.save(old_path)
	_tmp_files.append(old_path)
	var cfg_old := PhiConfig.new()
	_check(cfg_old.load_file(old_path), "config load old file")
	_check(absf(cfg_old.split_ratio - 704.0 / 1132.0) < 0.001, "config migrate split ratio")

	# 無いファイルは false で既定値のまま
	var cfg4 := PhiConfig.new()
	_check_eq(cfg4.load_file("/definitely/not/here/neophi.ini"), false, "config missing file")
	_check_eq(cfg4.host, "127.0.0.1", "config missing keeps default")

	cfg2.reset()
	_check_eq(cfg2.host, "127.0.0.1", "config reset host")
	_check_eq(cfg2.map_size, 81, "config reset map size")
	_check_eq(cfg2.scroll_stop, false, "config reset scroll stop")


# -- スキンのテキスト ------------------------------------------------------

func _test_decode_text_file() -> void:
	_check_eq(SkinFiles.is_valid_utf8("hello".to_utf8_buffer()), true, "utf8 ascii valid")
	_check_eq(SkinFiles.is_valid_utf8("こんにちは".to_utf8_buffer()), true, "utf8 japanese valid")
	_check_eq(SkinFiles.is_valid_utf8("🎮".to_utf8_buffer()), true, "utf8 emoji valid")
	_check_eq(SkinFiles.is_valid_utf8(PackedByteArray([0x82, 0xA0])), false, "utf8 cp932 invalid")
	_check_eq(SkinFiles.is_valid_utf8(PackedByteArray([0xC3, 0x28])), false, "utf8 bad continuation")
	_check_eq(SkinFiles.is_valid_utf8(PackedByteArray([0xC0, 0x80])), false, "utf8 overlong")
	_check_eq(SkinFiles.is_valid_utf8(PackedByteArray([0xED, 0xA0, 0x80])), false, "utf8 surrogate")
	_check_eq(SkinFiles.is_valid_utf8(PackedByteArray([0xE3, 0x81])), false, "utf8 truncated")
	_check_eq(SkinFiles.decode_text_file("こんにちは".to_utf8_buffer()), "こんにちは", "decode utf8")
	_check_eq(SkinFiles.decode_text_file(Cp932.encode("こんにちは")), "こんにちは", "decode cp932")
	_check_eq(SkinFiles.decode_text_file("body { color: red; }".to_ascii_buffer()), "body { color: red; }", "decode ascii")


func _test_index_txt() -> void:
	var parsed := SkinFiles.parse_index_txt("// コメント\nwidth\t= 20\nheight\t= 20\nEquip\t\t= Equip.bmp\nUnequip = Unequip.bmp\nNoEquals\n")
	_check_eq(parsed["width"], 20, "index width")
	_check_eq(parsed["height"], 20, "index height")
	_check_eq((parsed["map"] as Dictionary).get("Equip"), "Equip.bmp", "index equip")
	_check_eq((parsed["map"] as Dictionary).get("Unequip"), "Unequip.bmp", "index unequip")
	_check_eq((parsed["map"] as Dictionary).size(), 2, "index map size")
	var parsed2 := SkinFiles.parse_index_txt("Foo = Foo.bmp\n")
	_check_eq(parsed2["width"], 20, "index default width")
	_check_eq(parsed2["height"], 20, "index default height")
	var parsed3 := SkinFiles.parse_index_txt("width = abc\nheight = -5\n")
	_check_eq(parsed3["width"], 20, "index bad width")
	_check_eq(parsed3["height"], 20, "index bad height")
	# 値に = が入っても最初の = で分ける
	var parsed4 := SkinFiles.parse_index_txt("Key = a=b\n")
	_check_eq((parsed4["map"] as Dictionary).get("Key"), "a=b", "index value with equals")


func _test_menu_txt() -> void:
	_check_eq(SkinFiles.menu_key("ツール(&Y)"), "ツール", "menu key strips mnemonic")
	_check_eq(SkinFiles.menu_key("ファイル"), "ファイル", "menu key plain")
	var parsed := SkinFiles.parse_menu_txt(";コメント\r\non,ファイル\r\noff,魔法\r\non,ツール(&Y)\r\noff,\r\n")
	_check_eq(parsed.get("ファイル"), true, "menu file on")
	_check_eq(parsed.get("魔法"), false, "menu magic off")
	_check_eq(parsed.get("ツール"), true, "menu tool on")
	_check_eq(parsed.size(), 3, "menu size skips empty")
	var parsed2 := SkinFiles.parse_menu_txt("OFF,行動\nOn,表示\n")
	_check_eq(parsed2.get("行動"), false, "menu case insensitive off")
	_check_eq(parsed2.get("表示"), true, "menu case insensitive on")


func _test_css_color() -> void:
	_check_color(SkinFiles.parse_css_color("#fff"), 1.0, 1.0, 1.0, "css color #fff")
	_check_color(SkinFiles.parse_css_color("#00e0e0"), 0.0, 0.878, 0.878, "css color #00e0e0")
	_check_color(SkinFiles.parse_css_color("white"), 1.0, 1.0, 1.0, "css color white")
	_check_color(SkinFiles.parse_css_color("black"), 0.0, 0.0, 0.0, "css color black")
	_check_color(SkinFiles.parse_css_color("Teal"), 0.0, 0.5, 0.5, "css color teal case")
	_check_color(SkinFiles.parse_css_color("  red  "), 1.0, 0.0, 0.0, "css color red padded")
	_check_eq(SkinFiles.parse_css_color("notacolor"), null, "css color unknown")
	_check_eq(SkinFiles.parse_css_color(""), null, "css color empty")
	_check_eq(SkinFiles.parse_css_color("#12"), null, "css color short hex")
	_check_eq(SkinFiles.parse_css_color("#zzzzzz"), null, "css color bad hex")


func _test_log_css() -> void:
	var css := SkinFiles.parse_log_css("/* ログのスタイル */\nbody /* コメント */\n{\n\tbackground: white;\n\tcolor: black;\n\tfont-size: 14px;\n}\n.class_system_ok\n{\n\tcolor: teal;\n}\n.class_system_ng { color: red;; }\n")
	_check_eq((css["body"] as Dictionary).get("background"), "white", "css body background")
	_check_eq((css["body"] as Dictionary).get("color"), "black", "css body color")
	_check_eq((css["body"] as Dictionary).get("font-size"), "14px", "css body font size")
	_check_eq(((css["classes"] as Dictionary).get("class_system_ok", {}) as Dictionary).get("color"), "teal", "css system ok")
	_check_eq(((css["classes"] as Dictionary).get("class_system_ng", {}) as Dictionary).get("color"), "red", "css system ng double semicolon")
	# 複数セレクタと後勝ちマージ
	var css2 := SkinFiles.parse_log_css(".size__9, .size_9 { font-size: 100px; }\n.size_9 { font-size: 90px; line-height: 92px; }\n")
	_check_eq(((css2["classes"] as Dictionary).get("size__9", {}) as Dictionary).get("font-size"), "100px", "css multi selector")
	_check_eq(((css2["classes"] as Dictionary).get("size_9", {}) as Dictionary).get("font-size"), "90px", "css merge override")
	_check_eq(((css2["classes"] as Dictionary).get("size_9", {}) as Dictionary).get("line-height"), "92px", "css merge add")
	# コメントの中の { } に惑わされない
	var css3 := SkinFiles.parse_log_css("/* { } */\nbody { color: blue; }\n")
	_check_eq((css3["body"] as Dictionary).get("color"), "blue", "css comment braces")


# -- .cur -----------------------------------------------------------------

func _test_cur() -> void:
	var cur1 := SkinFiles.decode_cur(_make_cur_1bpp())
	_check(not cur1.is_empty(), "cur 1bpp decoded")
	_check_eq(cur1.get("hotspot"), Vector2i(1, 1), "cur 1bpp hotspot")
	var img1: Image = cur1["image"]
	_check_eq(img1.get_size(), Vector2i(2, 2), "cur 1bpp size")
	_check_color(img1.get_pixel(0, 0), 0.0, 0.0, 0.0, "cur 1bpp black")
	_check_eq(img1.get_pixel(0, 0).a, 1.0, "cur 1bpp black opaque")
	_check_color(img1.get_pixel(1, 0), 1.0, 1.0, 1.0, "cur 1bpp white")
	_check_eq(img1.get_pixel(0, 1).a, 0.0, "cur 1bpp transparent")
	_check_color(img1.get_pixel(1, 1), 0.0, 0.0, 0.0, "cur 1bpp bottom black")
	_check_eq(img1.get_pixel(1, 1).a, 1.0, "cur 1bpp bottom opaque")

	var cur24 := SkinFiles.decode_cur(_make_cur_24bpp())
	_check(not cur24.is_empty(), "cur 24bpp decoded")
	var img24: Image = cur24["image"]
	_check_color(img24.get_pixel(0, 0), 1.0, 0.0, 0.0, "cur 24bpp red")
	_check_color(img24.get_pixel(1, 0), 0.0, 1.0, 0.0, "cur 24bpp green")

	# PNG 埋め込み
	var png_img := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	png_img.set_pixel(0, 0, Color(1, 0, 0, 1))
	png_img.set_pixel(1, 0, Color(0, 1, 0, 0.5))
	png_img.set_pixel(0, 1, Color(0, 0, 1, 1))
	png_img.set_pixel(1, 1, Color(1, 1, 0, 0))
	var png_data := png_img.save_png_to_buffer()
	var cur_png := PackedByteArray()
	cur_png.append_array(_u16(0))
	cur_png.append_array(_u16(2))
	cur_png.append_array(_u16(1))
	cur_png.append(2)
	cur_png.append(2)
	cur_png.append(0)
	cur_png.append(0)
	cur_png.append_array(_u16(3))
	cur_png.append_array(_u16(4))
	cur_png.append_array(_u32(png_data.size()))
	cur_png.append_array(_u32(22))
	cur_png.append_array(png_data)
	var decoded_png := SkinFiles.decode_cur(cur_png)
	_check(not decoded_png.is_empty(), "cur png decoded")
	_check_eq(decoded_png.get("hotspot"), Vector2i(3, 4), "cur png hotspot")
	var img_png: Image = decoded_png["image"]
	_check_color(img_png.get_pixel(0, 0), 1.0, 0.0, 0.0, "cur png red")
	_check_eq(img_png.get_pixel(1, 1).a, 0.0, "cur png transparent")

	# 読めないもの
	_check_eq(SkinFiles.decode_cur(PackedByteArray()), {}, "cur empty")
	_check_eq(SkinFiles.decode_cur(PackedByteArray([0, 0, 1, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])), {}, "cur wrong type")
	_check_eq(SkinFiles.decode_cur(_make_cur_1bpp().slice(0, 10)), {}, "cur truncated")


# -- GameAssets のスキン ----------------------------------------------------

func _make_temp_skin() -> String:
	var root := OS.get_temp_dir().path_join("neophi-test-skin")
	# Buttons
	_write_tmp(root.path_join("Skins/Mine/Buttons/Index.txt"), Cp932.encode("// コメント\nwidth\t= 20\nheight\t= 20\nEquip = Equip.bmp\nMissing = Missing.bmp\n"))
	_write_tmp(root.path_join("Skins/Mine/Buttons/Equip.bmp"), _make_bmp24(2, 2, [[255, 0, 0], [0, 255, 0], [0, 0, 255], [0, 128, 128]]))
	_write_tmp(root.path_join("Skins/Mine/Buttons/NoImage.bmp"), _make_bmp24(2, 2, [[1, 2, 3], [1, 2, 3], [1, 2, 3], [1, 2, 3]]))
	# Style
	_write_tmp(root.path_join("Skins/Mine/Style/Menu.txt"), Cp932.encode(";コメント\non,ファイル\noff,魔法\n"))
	_write_tmp(root.path_join("Skins/Mine/Style/Log.css"), "body { background: white; color: black; }\n.class_system_ok { color: teal; }\n.class_system_ng { color: red; }\n".to_utf8_buffer())
	# Cursor / Images
	_write_tmp(root.path_join("Skins/Mine/Cursor/MouseUp.cur"), _make_cur_1bpp())
	_write_tmp(root.path_join("Skins/Mine/Images/Direction.bmp"), _make_bmp24(2, 2, [[9, 9, 9], [9, 9, 9], [9, 9, 9], [9, 9, 9]]))
	# chara フォールバック
	_write_tmp(root.path_join("Skins/Mine/Chara/Index.txt"), Cp932.encode("獣 = FallbackBeast.bmp\n"))
	_write_tmp(root.path_join("Skins/Mine/Chara/FallbackBeast.bmp"), _make_bmp24(2, 2, [[7, 7, 7], [7, 7, 7], [7, 7, 7], [7, 7, 7]]))
	return root


func _test_game_assets_skin() -> void:
	var root := _make_temp_skin()
	var assets := GameAssets.new()
	assets.setup([root], [], [], "Mine")
	_check_eq(assets.button_size(), Vector2i(20, 20), "assets button size")
	var equip: Variant = assets.button_icon("Equip")
	_check(equip != null, "assets button icon found")
	if equip != null:
		var img := (equip as ImageTexture).get_image()
		# Teal のピクセルは透明になる
		_check_eq(img.get_pixel(1, 1).a, 0.0, "assets button icon teal transparent")
		_check_eq(img.get_pixel(0, 0).a, 1.0, "assets button icon opaque")
	# 無い BMP は NoImage.bmp になる
	var missing: Variant = assets.button_icon("Missing")
	_check(missing != null, "assets button icon noimage fallback")
	if missing != null:
		_check_color((missing as ImageTexture).get_image().get_pixel(0, 0), 1.0 / 255.0, 2.0 / 255.0, 3.0 / 255.0, "assets button icon noimage pixels")
	# Index.txt に無いアクションも NoImage.bmp になる
	_check(assets.button_icon("NotListed") != null, "assets button icon unlisted noimage")
	# Images
	_check(assets.skin_image("Direction") != null, "assets skin image found")
	_check_eq(assets.skin_image("NoSuchImage"), null, "assets skin image missing")
	# Cursor
	var cursor: Variant = assets.cursor_texture("MouseUp")
	_check(cursor != null, "assets cursor found")
	if cursor != null:
		_check_eq((cursor as Dictionary).get("hotspot"), Vector2i(1, 1), "assets cursor hotspot")
		_check((cursor as Dictionary).get("texture") is ImageTexture, "assets cursor texture")
	_check_eq(assets.cursor_texture("NoSuchCursor"), null, "assets cursor missing")
	# Log.css / Menu.txt
	var css := assets.log_css()
	_check_eq((css["body"] as Dictionary).get("background"), "white", "assets log css background")
	_check_eq(((css["classes"] as Dictionary).get("class_system_ok", {}) as Dictionary).get("color"), "teal", "assets log css system ok")
	var vis := assets.menu_visibility()
	_check_eq(vis.get("ファイル"), true, "assets menu file on")
	_check_eq(vis.get("魔法"), false, "assets menu magic off")
	# chara フォールバック(Index.txt)
	var fallback: Variant = assets.chara("nobody_xyz", "", 0x02)
	_check(fallback != null, "assets chara fallback found")
	# キャッシュ初期化の後は読み直す
	assets.clear_cache()
	_check(assets.button_icon("Equip") != null, "assets after clear cache")
	# LANU 系もキャラグラとして読む (第34段で解禁。Philly の
	# 既定グラが LANU 系のため)。
	var lanu_dir := OS.get_temp_dir().path_join("neophi-test-lanu")
	_write_tmp(lanu_dir.path_join("lanu_test.bmp"), _make_bmp24(2, 2, [[5, 5, 5], [5, 5, 5], [5, 5, 5], [5, 5, 5]]))
	var assets2 := GameAssets.new()
	assets2.setup([], [], [lanu_dir], "Mine")
	_check(assets2.chara("nobody", "lanu_test", 0x00) != null, "assets lanu read as chara")


# -- Philly の実ファイル ------------------------------------------------------

func _test_real_philly_files() -> void:
	if DirAccess.open(PHILLY_ROOT) == null:
		print("skip real philly files: no source tree")
		return
	var assets := GameAssets.new()
	assets.setup([PHILLY_ROOT], [], [], "Mine")
	_check_eq(assets.button_size(), Vector2i(20, 20), "real button size")
	_check(assets.button_icon("Equip") != null, "real button Equip")
	_check(assets.button_icon("Cast") != null, "real button Cast")
	# 実 BMP が無いアクションは NoImage.bmp になる
	_check(assets.button_icon("Board") != null, "real button Board noimage")
	var index := assets.button_index()
	_check((index["map"] as Dictionary).size() > 80, "real button index count")
	_check_eq((index["map"] as Dictionary).get("Equip"), "Equip.bmp", "real button index equip")
	var cursor: Variant = assets.cursor_texture("MouseUp")
	_check(cursor != null, "real cursor MouseUp")
	if cursor != null:
		_check_eq((cursor as Dictionary).get("hotspot"), Vector2i(5, 0), "real cursor hotspot")
		_check_eq(((cursor as Dictionary).get("texture") as ImageTexture).get_image().get_size(), Vector2i(32, 32), "real cursor size")
	for cursor_name in ["MouseDown", "MouseLeft", "MouseRight", "MouseTurnN", "MouseTurnS", "MouseTurnE", "MouseTurnW", "MouseUpLeft", "MouseUpRight", "MouseDownLeft", "MouseDownRight", "MouseTLeft", "MouseTRight", "MouseTurnLeft", "MouseTurnRight"]:
		_check(assets.cursor_texture(cursor_name) != null, "real cursor " + cursor_name)
	var css := assets.log_css()
	_check_eq((css["body"] as Dictionary).get("background"), "white", "real css background")
	_check_eq((css["body"] as Dictionary).get("color"), "black", "real css color")
	_check_eq(((css["classes"] as Dictionary).get("class_system_ok", {}) as Dictionary).get("color"), "teal", "real css system ok")
	_check_eq(((css["classes"] as Dictionary).get("class_system_ng", {}) as Dictionary).get("color"), "red", "real css system ng")
	_check_eq(((css["classes"] as Dictionary).get("color_a_", {}) as Dictionary).get("color"), "aqua", "real css color class")
	var vis := assets.menu_visibility()
	_check_eq(vis.get("ファイル"), true, "real menu file")
	_check_eq(vis.get("魔法"), true, "real menu magic")
	_check_eq(vis.get("ツール"), true, "real menu tool mnemonic")
	_check(assets.skin_image("Direction") != null, "real skin image Direction")
	_check(assets.skin_image("HpMpBar") != null, "real skin image HpMpBar")
	_check(assets.items() != null, "real skin image Items")


# -- アクション表 -------------------------------------------------------------

func _test_actions() -> void:
	for menu in PhiActions.MENUS:
		_check(not str(menu["name"]).is_empty(), "actions menu name")
		for item in menu["items"]:
			if str(item) == "-":
				continue
			_check(not PhiActions.get_action(str(item)).is_empty(), "actions menu item exists: " + str(item))
	for item in PhiActions.TOOLBAR:
		if str(item) == "-":
			continue
		_check(not PhiActions.get_action(str(item)).is_empty(), "actions toolbar item exists: " + str(item))
	# メニューに表示するショートカット（アクセラレータ）の対応
	_check_eq(PhiActions.accelerator_for("Cast1"), KEY_F1, "accel Cast1 = F1")
	_check_eq(PhiActions.accelerator_for("Cast7"), KEY_F7, "accel Cast7 = F7")
	_check_eq(PhiActions.accelerator_for("M5x5"), KEY_5 | KEY_MASK_SHIFT, "accel M5x5 = Shift+5")
	_check_eq(PhiActions.accelerator_for("M7x7"), KEY_7 | KEY_MASK_SHIFT, "accel M7x7 = Shift+7")
	_check_eq(PhiActions.accelerator_for("MTurn"), KEY_T, "accel MTurn = T")
	_check_eq(PhiActions.accelerator_for("MSolid"), KEY_T | KEY_MASK_SHIFT, "accel MSolid = Shift+T")
	_check_eq(PhiActions.accelerator_for("NewPrivWindow"), KEY_F6 | KEY_MASK_SHIFT, "accel priv = Shift+F6")
	_check_eq(PhiActions.accelerator_for("Cast"), 0, "accel none for Cast")
	# Alt / Shift+Alt の魔法キー(Philly KeyBindAlt / KeyBindShiftAlt)
	_check_eq(PhiActions.accelerator_for("WizardEye"), KEY_W | KEY_MASK_ALT, "accel WizardEye = Alt+W")
	_check_eq(PhiActions.accelerator_for("WizardLight"), KEY_W | KEY_MASK_ALT | KEY_MASK_SHIFT, "accel WizardLight = Shift+Alt+W")
	_check_eq(PhiActions.accelerator_for("List"), KEY_L | KEY_MASK_ALT | KEY_MASK_SHIFT, "accel List = Shift+Alt+L")
	_check_eq(PhiActions.accelerator_for("Appear"), KEY_A | KEY_MASK_ALT | KEY_MASK_SHIFT, "accel Appear = Shift+Alt+A")
	_check_eq(PhiActions.alt_action_for("KeyW", false), "WizardEye", "alt KeyW")
	_check_eq(PhiActions.alt_action_for("KeyW", true), "WizardLight", "shift-alt KeyW")
	_check_eq(PhiActions.alt_action_for("KeyE", true), "EagleEyeText", "shift-alt KeyE")
	_check_eq(PhiActions.alt_action_for("KeyL", false), "WizardLock", "alt KeyL")
	_check_eq(PhiActions.alt_action_for("KeyL", true), "List", "shift-alt KeyL")
	_check_eq(PhiActions.alt_action_for("KeyP", false), "PartyEye", "alt KeyP")
	_check_eq(PhiActions.alt_action_for("KeyS", false), "Search", "alt KeyS")
	_check_eq(PhiActions.alt_action_for("KeyG", false), "", "alt KeyG is greeting, not an action")
	_check(PhiActions.ALT_CONFIRMS.has("Call"), "alt confirm for Call")
	_check(PhiActions.ALT_CONFIRMS.has("Return"), "alt confirm for Return")
	for action_name in PhiActions.ACTIONS:
		var action: Dictionary = PhiActions.ACTIONS[action_name]
		_check(not str(action.get("caption", "")).is_empty(), "actions caption: " + action_name)
		_check(not str(action.get("hint", "")).is_empty(), "actions hint: " + action_name)
		var kind := str(action.get("kind", ""))
		_check(not kind.is_empty(), "actions kind: " + action_name)
		if kind == "send":
			_check(not str(action.get("send", "")).is_empty(), "actions send text: " + action_name)
		elif kind == "ask":
			_check(str(action.get("template", "")).contains("%s"), "actions ask template: " + action_name)
			_check(not str(action.get("title", "")).is_empty(), "actions ask title: " + action_name)
			_check(not str(action.get("label", "")).is_empty(), "actions ask label: " + action_name)
	# Philly の送信内容
	_check_eq(PhiActions.send_text_for("Equip"), "equip", "actions equip send")
	_check_eq(PhiActions.send_text_for("Unequip"), "unequip", "actions unequip send")
	_check_eq(PhiActions.send_text_for("Check"), "check\nlook", "actions check send")
	_check_eq(PhiActions.send_text_for("FloorItem"), "floor item", "actions floor item send")
	_check_eq(PhiActions.send_text_for("WizardEye"), "cast\nwizard eye", "actions wizard eye send")
	_check_eq(PhiActions.send_text_for("WizardLock"), "cast\nwizard lock\nsee", "actions wizard lock send")
	_check_eq(PhiActions.send_text_for("EagleEyeText"), "#ex-switch eagleeye=text\ncast\neagle eye\n#ex-switch eagleeye=form", "actions eagle eye text send")
	_check_eq(PhiActions.send_text_for("M5x5"), "#ex-map size=40", "actions m5x5 send")
	_check_eq(PhiActions.send_text_for("M7x7"), "#ex-map size=57", "actions m7x7 send")
	_check_eq(PhiActions.send_text_for("MTurn"), "#ex-map style=turn", "actions mturn send")
	_check_eq(PhiActions.send_text_for("MSolid"), "#ex-map style=solid", "actions msolid send")
	_check_eq(PhiActions.send_text_for("Cast3"), "cast\n3", "actions cast3 send")
	_check_eq(PhiActions.send_text_for("Open"), "", "actions open is not send")
	_check_eq(PhiActions.build_ask_text("Pay", "100"), "pay 100", "actions pay ask")
	_check_eq(PhiActions.build_ask_text("Search", "酒場"), "cast\nsearch\n酒場", "actions search ask")
	_check_eq(PhiActions.build_ask_text("Appear", "案内人"), "cast\nappear 案内人", "actions appear ask")
	_check_eq(PhiActions.build_ask_text("Equip", "x"), "", "actions build ask non-ask")
	# 有効・無効
	_check_eq(PhiActions.enabled_when("Open", false), true, "actions open enabled offline")
	_check_eq(PhiActions.enabled_when("Open", true), false, "actions open disabled online")
	_check_eq(PhiActions.enabled_when("Close", true), true, "actions close enabled online")
	_check_eq(PhiActions.enabled_when("Close", false), false, "actions close disabled offline")
	_check_eq(PhiActions.enabled_when("Equip", true), true, "actions send enabled online")
	_check_eq(PhiActions.enabled_when("Equip", false), false, "actions send disabled offline")
	_check_eq(PhiActions.enabled_when("Pay", false), false, "actions ask disabled offline")
	_check_eq(PhiActions.enabled_when("Exit", false), true, "actions exit always")
	_check_eq(PhiActions.enabled_when("VersionInfo", true), true, "actions about always")
	_check_eq(PhiActions.enabled_when("NoSuchAction", true), true, "actions unknown always")


# -- ログイン行 -----------------------------------------------------------------

func _test_login_lines() -> void:
	var lines := PhiSession.login_lines("guest")
	_check(lines.has("#ex-map size=81"), "login default size")
	_check(lines.has("#ex-map style=solid"), "login default style")
	_check(lines.has("#open guest"), "login open")
	var lines40 := PhiSession.login_lines("guest", 40, "turn")
	_check(lines40.has("#ex-map size=40"), "login size 40")
	_check(lines40.has("#ex-map style=turn"), "login style turn")
	var lines_no_open := PhiSession.login_lines(null, 57, "solid")
	_check(not lines_no_open.has("#open guest"), "login no open")


# -- ズームの規則(第3段の追加要望で変更) -------------------------------------
# 拡大は、窓のリサイズ・境目のドラッグといった外部からのサイズ変更で
# 立てた要求フラグがある時だけ、収まるなら1段階ずつ。縮小は即座に。
# 要求が無いときは拡大しないので、文字サイズの連動によるレイアウトの
# フィードバックでは発振しない。96px の余裕要求は廃止した。
#
# 行の高さ(窓の高さから地図の高さを引いたもの)の実測値:
# ズーム 1→185、2→198、3→246、4→297(2026-11-16、VM の実測。
# ツールバーを地図上のフロートに移してメニュー下の一列を無くし、
# 画面外周の外枠(幅6)とタブ行下のスリット(8)が加わった後の値。
# 地図の大きさは 800x600→489x415、900x700→551x502、
# 1280x1024→786x778、1700x1300→1047x1003、2000x1400→1233x1103 で、
# ズームは従来どおり 1/2/3/4/4、どの大きさでも発振しない)。
# 5段以上は 3→4 の増分 51 で外挿する。フォント描画の
# 違いで数ピクセル変わりうるが、規則の収束性には影響しない。
const _CHROME_H := {1: 185, 2: 198, 3: 246, 4: 297}


func _sim_chrome_h(zoom: int) -> int:
	if _CHROME_H.has(zoom):
		return _CHROME_H[zoom]
	return 297 + 51 * (zoom - 4)


func _sim_map_size(win_w: int, win_h: int, zoom: int) -> Vector2:
	## ズームに応じたレイアウトで、地図に割り当てられる大きさ。
	## 右列は廃止され、境目(HSplit)が窓幅いっぱいに広がる。
	## 外枠の分だけ内側(幅−12)が使える幅になる。境目は幅の 0.62、
	## ログの最小幅 280 と区切り 6 を保つ
	## (PhiConfig.split_offset_for と同じ計算)。
	var content_w := win_w - 12
	var map_w := mini(int(round(content_w * 0.62)), content_w - 280 - 6)
	map_w = maxi(map_w, 0)
	return Vector2(map_w, win_h - _sim_chrome_h(zoom))


func _settle(mv: MapView, win_w: int, win_h: int, grow: bool) -> int:
	## 1回の外部イベント(要求フラグあり/なし)の後、レイアウトの
	## フィードバックを反復して収束させる。反復回数を返す。
	if grow:
		mv.request_zoom_growth()
	var iters := 0
	while iters < 5:
		mv.size = _sim_map_size(win_w, win_h, mv.zoom)
		var before := mv.zoom
		mv._update_zoom()
		iters += 1
		if mv.zoom == before:
			break
	return iters


func _test_zoom_hysteresis() -> void:
	var mv := MapView.new()
	# 要求が無ければ、収まる余裕があっても拡大しない。
	mv.zoom = 3
	mv.size = Vector2(1100, 1056)
	mv._update_zoom()
	_check_eq(mv.zoom, 3, "zoom no grow without request")
	# 要求があれば1段階だけ拡大する(2段階分の余裕があっても1段)。
	mv.request_zoom_growth()
	mv._update_zoom()
	_check_eq(mv.zoom, 4, "zoom grow one step")
	mv.size = Vector2(2000, 2000)
	mv._update_zoom()
	_check_eq(mv.zoom, 4, "zoom request consumed")
	# 要求があっても、収まらなければ拡大しない。
	mv.zoom = 3
	mv.size = Vector2(1100, 959)
	mv.request_zoom_growth()
	mv._update_zoom()
	_check_eq(mv.zoom, 3, "zoom no grow when not fit")
	# 収まらなくなったら、要求が無くても即座に縮小する。
	mv.size = Vector2(1100, 719)
	mv._update_zoom()
	_check_eq(mv.zoom, 2, "zoom shrink when not fit")
	# 縮小すると、溜まっていた拡大要求は捨てられる。
	mv.request_zoom_growth()
	mv.size = Vector2(1100, 479)
	mv._update_zoom()
	_check_eq(mv.zoom, 1, "zoom shrink consumes request")
	mv.size = Vector2(1100, 1056)
	mv._update_zoom()
	_check_eq(mv.zoom, 1, "zoom no grow after shrink consumed")
	# ぴったり収まる大きさでは今の倍率を保つ。
	mv.zoom = 4
	mv.size = Vector2(1100, 960)
	mv._update_zoom()
	_check_eq(mv.zoom, 4, "zoom keep exact fit")
	# 縮小して1まで落ちても、要求を繰り返せば1段階ずつ戻る。
	mv.zoom = 3
	mv.size = Vector2(698, 880)
	mv._update_zoom()
	_check_eq(mv.zoom, 3, "zoom roundtrip start")
	mv.size = Vector2(400, 500)
	mv._update_zoom()
	_check_eq(mv.zoom, 1, "zoom roundtrip shrink")
	mv.size = Vector2(698, 880)
	for _i in range(4):
		mv.request_zoom_growth()
		mv._update_zoom()
	_check_eq(mv.zoom, 3, "zoom roundtrip grow back")
	# 5x5 地図でも同じ規則(マスが小さい分、同じ幅で倍率が上がる)。
	var mv5 := MapView.new()
	mv5.set_map({"size": 5, "cells": [], "chars": []}, null, "")
	mv5.size = Vector2(400, 400)
	mv5._update_zoom()
	_check_eq(mv5.zoom, 2, "zoom 5x5 shrink")
	mv5.request_zoom_growth()
	mv5.size = Vector2(500, 550)
	mv5._update_zoom()
	_check_eq(mv5.zoom, 3, "zoom 5x5 grow")
	mv.queue_free()
	mv5.queue_free()

	# ドラッグの模擬: 外部イベントを繰り返し、毎回フィードバックが
	# 2回以内に収束し、収まった倍率で安定することを確認する。
	for win_w in [800, 900, 1000, 1280, 1400, 1700, 1900, 2100]:
		for win_h in range(600, 1601, 10):
			var mv2 := MapView.new()
			mv2.zoom = 1
			var settled: Array = []
			var max_iters := 0
			for _e in range(6):
				var iters := _settle(mv2, win_w, win_h, true)
				max_iters = maxi(max_iters, iters)
				settled.append(mv2.zoom)
			# 外部イベント1回あたり、反復は3回以内(要求1回＋反動2回)。
			_check(max_iters <= 3, "zoom settles w=" + str(win_w) + " h=" + str(win_h) + " iters=" + str(max_iters))
			# 収束した倍率は収まっていること。
			var need := Vector2(7 * 32 * mv2.zoom, (7 * 32 + 16) * mv2.zoom)
			var avail := _sim_map_size(win_w, win_h, mv2.zoom)
			_check(avail.x >= need.x and avail.y >= need.y, "zoom fits w=" + str(win_w) + " h=" + str(win_h) + " zoom=" + str(mv2.zoom))
			# 後半の外部イベントでは、収まった倍率が変わらないこと。
			_check(settled[3] == settled[4] and settled[4] == settled[5], "zoom stable w=" + str(win_w) + " h=" + str(win_h))
			# 要求が無いフィードバックだけでは倍率が変わらないこと。
			var iters2 := _settle(mv2, win_w, win_h, false)
			_check_eq(mv2.zoom, settled[5], "zoom no drift w=" + str(win_w) + " h=" + str(win_h))
			_check(iters2 <= 2, "zoom feedback w=" + str(win_w) + " h=" + str(win_h))
			mv2.queue_free()


func _initialize() -> void:
	_test_config()
	_test_zoom_hysteresis()
	_test_decode_text_file()
	_test_index_txt()
	_test_menu_txt()
	_test_css_color()
	_test_log_css()
	_test_cur()
	_test_game_assets_skin()
	_test_real_philly_files()
	_test_actions()
	_test_login_lines()
	_cleanup_tmp()
	print("test_stage1: ", _checks, " checks, ", _failures, " failures")
	quit(1 if _failures > 0 else 0)
