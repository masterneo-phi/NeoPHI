class_name GameAssets
extends RefCounted
## Philly の BMP を探して、透過を付けたテクスチャで返す。
##
## Python 版 neophi/assets.py の移植。探す場所は2種類ある:
## ・Philly 式: フォルダ直下に `chara/`、`Skins/<skin>/chip/Default.bmp` 等がある。
## ・フラット式: チップとキャラがそれぞれ1フォルダに平置きされている
##   (phi-option-data の各パック)。チップは `<mapset>.bmp`、無ければ
##   `default.bmp`。キャラは `<名前>.bmp` を大文字小文字を無視して探す。
## どちらも、グラフィックス自体はプロジェクトに同梱せず、実行時に読む。
##
## 名前やグラ名は他のプレイヤーやサーバが決めるので、探す場所の外を指す
## パス(`..` や `\` など)は読まない。LANU 系のグラフィックスも読まない。

## 使っているスキン(Philly.ini の `SkinName`)。
const DEFAULT_SKIN := "Mine"

## `#m57 O` の種別 → スキンの `Chara/Index.txt` のキー
## (Philly `Const.cpp` の SKIN_CHARA_GRA)。
const DEFAULT_GRA := [
	[0x00, "人・銅像"],
	[0x01, "知的生物"],
	[0x02, "獣"],
	[0x03, "狂戦士"],
	[0x04, "魔法生物"],
	[0x05, "アンデッド"],
	[0x06, "精神体"],
	[0x07, "イレイザー"],
	[0x40, "setcg使用キャラ"],
	[0x80, "生物"],
	[0x81, "看板"],
	[0x82, "魔法エフェクト"],
	[0x70, "アニメオブジェ"],
	[0x75, "アニメなしオブジェ"],
]

const _CACHE_LIMIT := 4096

var skin := DEFAULT_SKIN
## Philly 式の探す場所(先に探す方から)。
var philly_roots: Array[String] = []
## フラット式のチップフォルダ(先に探す方から)。
var chip_dirs: Array[String] = []
## フラット式のキャラフォルダ(先に探す方から)。
var chara_dirs: Array[String] = []
## フラット式で種別の既定グラが無い時に使うファイル名(空なら無し)。
var default_chara_file := ""
## Items.bmp の直接指定(空なら Philly 式の場所から探す)。
var items_file := ""

var _aliases: Dictionary = {}
var _cache: Dictionary = {} # 問い合わせキー → ImageTexture
var _converted: Dictionary = {} # ファイルの絶対パス → ImageTexture
var _dirs: Dictionary = {} # フォルダ → {小文字の名前: 実際のパス}
var _button_index: Variant = null # パース済みの Buttons/Index.txt
var _cursors: Dictionary = {} # カーソル名 → {"texture": ImageTexture, "hotspot": Vector2i}
var _log_css: Variant = null # パース済みの Style/Log.css
var _menu_visibility: Variant = null # パース済みの Style/Menu.txt


func _init() -> void:
	pass


func setup(p_philly_roots: Array[String], p_chip_dirs: Array[String], p_chara_dirs: Array[String], p_skin: String = DEFAULT_SKIN) -> void:
	philly_roots = p_philly_roots
	chip_dirs = p_chip_dirs
	chara_dirs = p_chara_dirs
	skin = p_skin
	_aliases = _load_aliases()
	_button_index = null
	_cursors.clear()
	_log_css = null
	_menu_visibility = null


func clear_cache() -> void:
	## グラフィックスのキャッシュを全部捨てる(「グラキャッシュ初期化」)。
	## 次に使う時にファイルを読み直す。
	_cache.clear()
	_converted.clear()
	_dirs.clear()
	_button_index = null
	_cursors.clear()
	_log_css = null
	_menu_visibility = null
	_aliases = _load_aliases()


static func is_lanu(file_name: String) -> bool:
	## LANU 系のグラフィックスか (4bpp)。キャラグラとしては
	## 通常どおり読む (Philly の既定グラも LANU 系)。ボタンの
	## 絵の候補からは外すために使う。
	return file_name.get_file().to_lower().begins_with("lanu_")


static func _has_nul(s: String) -> bool:
	for i in s.length():
		if s.unicode_at(i) == 0:
			return true
	return false


static func safe_name(file_name: String) -> bool:
	## フォルダの外を指さない1ファイル名か。
	if file_name.is_empty():
		return false
	return not (
		file_name.contains("/") or file_name.contains("\\")
		or file_name.contains(":") or _has_nul(file_name)
		or file_name == "." or file_name == ".."
	)


static func safe_rel(rel: String) -> bool:
	## 探す場所の外を指さない相対パスか。
	for part in rel.split("/"):
		if part.is_empty() or part == "." or part == "..":
			return false
		if part.contains("\\") or part.contains(":") or _has_nul(part):
			return false
	return true


# -- 探す ---------------------------------------------------------------

static func find_philly_root(skin_name: String, bases: Array) -> String:
	## `bases` の順に `Skins/<skin_name>/` を含むフォルダを探す。
	## 見つかればそのフォルダ、無ければ ""。
	## 危険なスキン名(区切りや `..` を含む)は探さない。
	if not safe_name(skin_name):
		return ""
	for base_var in bases:
		var base := str(base_var)
		if base.is_empty():
			continue
		var skin_dir := base.path_join("Skins").path_join(skin_name)
		if DirAccess.open(skin_dir) != null:
			return base
	return ""


func _list_dir(path: String) -> Dictionary:
	## フォルダの中の名前(小文字) → パス。一度読んだフォルダは読み直さない。
	if _dirs.has(path):
		return _dirs[path]
	var listing: Dictionary = {}
	var dir := DirAccess.open(path)
	if dir != null:
		dir.list_dir_begin()
		var entry := dir.get_next()
		while entry != "":
			if not dir.current_is_dir():
				listing[entry.to_lower()] = path.path_join(entry)
			entry = dir.get_next()
		dir.list_dir_end()
	_dirs[path] = listing
	return listing


func _find_in(root: String, rel: String) -> Variant:
	## `root` からの相対パスを、大文字と小文字を無視して探す。
	var path := root
	for part in rel.split("/"):
		var listing := _list_dir(path)
		var found: Variant = listing.get(part.to_lower())
		if found == null:
			# サブフォルダも大文字小文字を無視して探す
			var dir := DirAccess.open(path)
			if dir == null:
				return null
			dir.list_dir_begin()
			var entry := dir.get_next()
			var matched: Variant = null
			while entry != "":
				if dir.current_is_dir() and entry.to_lower() == part.to_lower():
					matched = path.path_join(entry)
					break
				entry = dir.get_next()
			dir.list_dir_end()
			if matched == null:
				return null
			path = matched
		else:
			path = found
	return path


func _read_file(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	return FileAccess.get_file_as_bytes(path)


func _load_aliases() -> Dictionary:
	## `chara/*.ali` の各行 `<グラ名> <別名>` を読む。先に探す場所を優先する。
	var aliases: Dictionary = {}
	var chara_roots: Array[String] = []
	for root in philly_roots:
		var found: Variant = _find_in(root, "chara")
		if found != null:
			chara_roots.append(found)
	for dir in chara_dirs:
		chara_roots.append(dir)
	# 後ろの定義を先に読んで、先の定義で上書きする
	chara_roots.reverse()
	for chara_dir in chara_roots:
		var listing := _list_dir(chara_dir)
		for lower_name in listing:
			if not lower_name.ends_with(".ali"):
				continue
			var data: Variant = _read_file(listing[lower_name])
			if data == null:
				continue
			for line in Cp932.decode(data).split("\n"):
				var parts := _split_first_ws(line.strip_edges())
				if parts.size() == 2:
					aliases[parts[1].strip_edges()] = parts[0]
	return aliases


func _open_image(abs_path: String, convert: String) -> Variant:
	var done: Variant = _converted.get(abs_path)
	if done != null:
		return done
	var data: Variant = _read_file(abs_path)
	if data == null:
		return null
	var img := BmpLoader.decode_bmp(data)
	if img == null:
		return null
	if convert == "colorkey":
		img = BmpLoader.colorkey(img)
	elif convert == "mask_h":
		img = BmpLoader.mask_h(img)
	elif convert == "mask_v":
		img = BmpLoader.mask_v(img)
	var tex := ImageTexture.create_from_image(img)
	_converted[abs_path] = tex
	return tex


func _remember(key: String, tex: ImageTexture) -> ImageTexture:
	if _cache.size() >= _CACHE_LIMIT:
		_cache.clear()
	_cache[key] = tex
	return tex


# -- 種類ごと -----------------------------------------------------------

func chara(chara_name: String, gra: String, code: int) -> Variant:
	## キャラグラのテクスチャ(Philly `GraCache.cpp` の解決の順番)。
	## setcg(0x40)はグラ名 → 別名 → キャラ名、それ以外は別名 → グラ名 →
	## キャラ名の順に探し、無ければ種別ごとの既定グラにする。
	var key := "chara?%s&%s&%d&" % [chara_name, gra, code]
	var cached: Variant = _cache.get(key)
	if cached != null:
		return cached
	var path: Variant = _chara_path(chara_name, gra, code)
	if path == null:
		return null
	var tex: Variant = _open_image(path, "colorkey")
	if tex == null:
		return null
	return _remember(key, tex)


func _chara_path(chara_name: String, gra: String, code: int) -> Variant:
	var alias: Variant = _aliases.get(chara_name)
	var order: Array = []
	if code == 0x40:
		order = [gra, alias, chara_name]
	else:
		order = [alias, gra, chara_name]
	for candidate in order:
		if candidate == null or str(candidate).is_empty():
			continue
		var file_name := str(candidate) + ".bmp"
		if not safe_name(file_name):
			continue
		# フラット式のフォルダ
		for dir in chara_dirs:
			var listing := _list_dir(dir)
			var found: Variant = listing.get(file_name.to_lower())
			if found != null:
				return found
		# Philly 式
		for root in philly_roots:
			var rel := "chara/" + file_name
			if not safe_rel(rel):
				continue
			var found: Variant = _find_in(root, rel)
			if found != null:
				return found
	return _default_chara_path(code)


func _default_chara_path(code: int) -> Variant:
	## 種別の既定グラのファイル。Philly 式はスキンの `Chara/Index.txt` を見る。
	var key := "知的生物"
	for pair in DEFAULT_GRA:
		if pair[0] == code:
			key = pair[1]
			break
	var index_rel := "Skins/%s/Chara/Index.txt" % skin
	for root in philly_roots:
		var path: Variant = _find_in(root, index_rel)
		if path == null:
			continue
		var data: Variant = _read_file(path)
		if data == null:
			continue
		var file: Variant = _index_value(Cp932.decode(data), key)
		if file == null or file.is_empty():
			continue
		for rel in ["Skins/%s/Chara/%s" % [skin, file], "chara/" + file]:
			if not safe_rel(rel):
				continue
			var found: Variant = _find_in(root, rel)
			if found != null:
				return found
	# フラット式の既定ファイル
	if not default_chara_file.is_empty() and safe_name(default_chara_file):
		for dir in chara_dirs:
			var listing := _list_dir(dir)
			var found: Variant = listing.get(default_chara_file.to_lower())
			if found != null:
				return found
	return null


func chip(mapset: String) -> Variant:
	## マップチップのテクスチャ。`<mapset>.bmp` が無ければ既定のチップ。
	var key := "chip?&&&" + mapset
	var cached: Variant = _cache.get(key)
	if cached != null:
		return cached
	var path: Variant = null
	# フラット式: <mapset>.bmp、無ければ default.bmp
	if not mapset.is_empty() and safe_name(mapset + ".bmp"):
		for dir in chip_dirs:
			var listing := _list_dir(dir)
			var found: Variant = listing.get((mapset + ".bmp").to_lower())
			if found != null:
				path = found
				break
	if path == null:
		for dir in chip_dirs:
			var listing := _list_dir(dir)
			var found: Variant = listing.get("default.bmp")
			if found != null:
				path = found
				break
	# Philly 式
	if path == null and not mapset.is_empty():
		var candidate := "chip/" + mapset + ".bmp"
		if safe_rel(candidate):
			for root in philly_roots:
				var found: Variant = _find_in(root, candidate)
				if found != null:
					path = found
					break
	if path == null:
		var rel := "Skins/%s/chip/Default.bmp" % skin
		for root in philly_roots:
			var found: Variant = _find_in(root, rel)
			if found != null:
				path = found
				break
	if path == null:
		return null
	var tex: Variant = _open_image(path, "mask_h")
	if tex == null:
		return null
	return _remember(key, tex)


func items() -> Variant:
	## アイテムのテクスチャ(`Skins/<skin>/Images/Items.bmp` か直接指定)。
	var key := "items?&&&"
	var cached: Variant = _cache.get(key)
	if cached != null:
		return cached
	var path: Variant = null
	if not items_file.is_empty() and FileAccess.file_exists(items_file):
		path = items_file
	if path == null:
		var rel := "Skins/%s/Images/Items.bmp" % skin
		for root in philly_roots:
			var found: Variant = _find_in(root, rel)
			if found != null:
				path = found
				break
	if path == null:
		return null
	var tex: Variant = _open_image(path, "mask_v")
	if tex == null:
		return null
	return _remember(key, tex)


# -- スキン --------------------------------------------------------------

func _skin_file(rel: String) -> Variant:
	## スキン内の相対パスを探す。最初に見つかった場所の絶対パスか null。
	var full := "Skins/%s/%s" % [skin, rel]
	if not safe_rel(full):
		return null
	for root in philly_roots:
		var found: Variant = _find_in(root, full)
		if found != null:
			return found
	return null


func _read_skin_text(rel: String) -> Variant:
	## スキン内のテキストファイルを読む。見つからなければ null。
	## UTF-8 か cp932 かは中身で決める(Log.css は UTF-8 のことがある)。
	var path: Variant = _skin_file(rel)
	if path == null:
		return null
	var data: Variant = _read_file(path)
	if data == null:
		return null
	return SkinFiles.decode_text_file(data)


func config_text(file_name: String) -> String:
	## Philly の `Config/<file_name>` を探して読む。第4段の XML メニュー
	## や削除フィルタの既定ファイルに使う。無ければ ""。
	if not safe_name(file_name):
		return ""
	var rel := "Config/%s" % file_name
	if not safe_rel(rel):
		return ""
	for root in philly_roots:
		var found: Variant = _find_in(root, rel)
		if found == null:
			continue
		var data: Variant = _read_file(found)
		if data != null:
			return SkinFiles.decode_text_file(data)
	return ""


func button_index() -> Dictionary:
	## `Buttons/Index.txt` の中身。無ければ空の一覧(大きさは既定の 20)。
	if _button_index != null:
		return _button_index
	var text: Variant = _read_skin_text("Buttons/Index.txt")
	if text == null:
		_button_index = {"width": SkinFiles.BUTTON_DEFAULT_SIZE, "height": SkinFiles.BUTTON_DEFAULT_SIZE, "map": {}}
	else:
		_button_index = SkinFiles.parse_index_txt(text)
	return _button_index


func button_size() -> Vector2i:
	var index := button_index()
	return Vector2i(int(index["width"]), int(index["height"]))


func button_icon(action_name: String) -> Variant:
	## ツールバーボタンの絵。BMP が無ければ `NoImage.bmp`、それも
	## 無ければ null。透過色は Teal。
	var key := "button?" + action_name
	var cached: Variant = _cache.get(key)
	if cached != null:
		return cached
	var index := button_index()
	var file_name: Variant = (index["map"] as Dictionary).get(action_name)
	var path: Variant = null
	if file_name != null and not str(file_name).is_empty():
		var rel := "Buttons/" + str(file_name)
		if safe_rel("Skins/%s/%s" % [skin, rel]) and not is_lanu(str(file_name)):
			path = _skin_file(rel)
	if path == null:
		path = _skin_file("Buttons/NoImage.bmp")
	if path == null:
		return null
	var tex: Variant = _open_image(path, "colorkey")
	if tex == null:
		return null
	return _remember(key, tex)


func button_icon_sized(action_name: String, px: int) -> Variant:
	## button_icon を px の大きさに拡大した絵。プルダウンメニューの
	## アイコンを少し大きくするために使う(ユーザーの要望)。
	## ドット絵なので拡大は NEAREST。大きさ別にキャッシュする。
	var base: Variant = button_icon(action_name)
	if base == null:
		return null
	var tex := base as Texture2D
	if tex == null or tex.get_width() == px:
		return base
	var key := "button?%s@%d" % [action_name, px]
	var cached: Variant = _cache.get(key)
	if cached != null:
		return cached
	var img := tex.get_image()
	if img == null:
		return base
	img = img.duplicate()
	img.resize(px, px, Image.INTERPOLATE_NEAREST)
	return _remember(key, ImageTexture.create_from_image(img))


func skin_image(image_name: String) -> Variant:
	## `Images/<名前>.bmp` のテクスチャ。方角コンパスや HP/MP バーなど
	## (第3段で使う)。無ければ null。
	var key := "skinimg?" + image_name
	var cached: Variant = _cache.get(key)
	if cached != null:
		return cached
	var rel := "Images/" + image_name + ".bmp"
	if not safe_rel("Skins/%s/%s" % [skin, rel]):
		return null
	var path: Variant = _skin_file(rel)
	if path == null:
		return null
	var tex: Variant = _open_image(path, "colorkey")
	if tex == null:
		return null
	return _remember(key, tex)


func cursor_texture(cursor_name: String) -> Variant:
	## `Cursor/<名前>.cur` のカーソル。`{"texture", "hotspot"}` か null。
	## 第3段の方向カーソルで使う。
	if _cursors.has(cursor_name):
		return _cursors[cursor_name]
	var rel := "Cursor/" + cursor_name + ".cur"
	var result: Variant = null
	if safe_rel("Skins/%s/%s" % [skin, rel]):
		var path: Variant = _skin_file(rel)
		if path != null:
			var data: Variant = _read_file(path)
			if data != null:
				var decoded := SkinFiles.decode_cur(data)
				if not decoded.is_empty():
					result = {"texture": ImageTexture.create_from_image(decoded["image"]), "hotspot": decoded["hotspot"]}
	_cursors[cursor_name] = result
	return result


func log_css() -> Dictionary:
	## `Style/Log.css` の中身。無ければ空。`{"body": {}, "classes": {}}`。
	if _log_css != null:
		return _log_css
	var text: Variant = _read_skin_text("Style/Log.css")
	if text == null:
		_log_css = {"body": {}, "classes": {}}
	else:
		_log_css = SkinFiles.parse_log_css(text)
	return _log_css


func menu_visibility() -> Dictionary:
	## `Style/Menu.txt` の中身。無ければ空。`{メニュー名: 表示するか}`。
	if _menu_visibility != null:
		return _menu_visibility
	var text: Variant = _read_skin_text("Style/Menu.txt")
	if text == null:
		_menu_visibility = {}
	else:
		_menu_visibility = SkinFiles.parse_menu_txt(text)
	return _menu_visibility


static func _split_first_ws(text: String) -> Array[String]:
	## 最初の空白の並びで2つに分ける。空白が無ければ1要素。
	var n := text.length()
	var i := 0
	while i < n:
		var c := text.unicode_at(i)
		if c == 0x20 or c == 0x09:
			break
		i += 1
	if i >= n:
		return [text] if not text.is_empty() else []
	var j := i
	while j < n:
		var c := text.unicode_at(j)
		if c != 0x20 and c != 0x09:
			break
		j += 1
	return [text.substr(0, i), text.substr(j)]


static func _index_value(index_text: String, wanted: String) -> Variant:
	return (SkinFiles.parse_index_txt(index_text)["map"] as Dictionary).get(wanted)
