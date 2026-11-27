extends SceneTree
## 第121段: 次回バッチのうち DM コマンド搭載とマップサイズ設定、
## マスター魔法への dmsetupcheck / gfakeaction 追加のテスト。
##
## 使い方: godot --headless --path . -s tests/test_stage121.gd
## 終了コード 0 = 全一致、1 = 不一致あり。

var _checks := 0
var _failures := 0


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


func _init() -> void:
	_test_actions()
	_test_master_magic()
	_test_config_zoom()
	_test_map_zoom()
	print("stage121: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _menu_items(menu_name: String) -> Array:
	for menu in PhiActions.MENUS:
		if str(menu.get("name", "")) == menu_name:
			return menu.get("items", [])
	return []


func _test_actions() -> void:
	# 送信系 (kind "send") のコマンド文字列。
	_check_eq(PhiActions.send_text_for("Level"), "level", "level send")
	_check_eq(PhiActions.send_text_for("ReadMail"), "readmail", "readmail send")
	_check_eq(PhiActions.send_text_for("DelMail"), "delmail", "delmail send")
	_check_eq(PhiActions.send_text_for("ServerVersion"), "version", "version send")
	_check_eq(PhiActions.send_text_for("WizList"), "wizlist", "wizlist send")
	_check_eq(PhiActions.send_text_for("WizEye"), "wizeye", "wizeye send")
	_check_eq(PhiActions.send_text_for("ChatMode"), "chat", "chat send")
	_check_eq(PhiActions.send_text_for("Address"), "address", "address send")
	# ask 系。
	_check_eq(PhiActions.build_ask_text("SetCG", "hero.bmp"), "setcg hero.bmp", "setcg ask")
	_check_eq(PhiActions.build_ask_text("ActionSay", "is dancing"), "action is dancing", "action ask")
	_check_eq(PhiActions.build_ask_text("FakeAction", "is here"), "fakeaction is here", "fakeaction ask")
	# ask2 (sendmail) は2つの %s を順に置き換える。
	_check_eq(PhiActions.kind_of("SendMail"), "ask2", "sendmail kind ask2")
	_check_eq(PhiActions.build_ask2_text("SendMail", "12", "hello"), "sendmail 12:hello", "sendmail ask2")
	_check_eq(PhiActions.build_ask2_text("Level", "1", "2"), "", "ask2 wrong kind empty")
	# 接続状態での有効・無効。
	_check(not PhiActions.enabled_when("SendMail", false), "sendmail disabled offline")
	_check(PhiActions.enabled_when("SendMail", true), "sendmail enabled online")
	_check(not PhiActions.enabled_when("SetCG", false), "setcg disabled offline")
	_check(PhiActions.enabled_when("MapSizeSetting", false), "map size setting always enabled")
	_check_eq(PhiActions.kind_of("MapSizeSetting"), "map-size-dialog", "map size kind")
	# メニュー配置。
	var ops := _menu_items("操作")
	for name in ["SetCG", "SendMail", "ReadMail", "DelMail", "ServerVersion", "ActionSay", "FakeAction", "ChatMode", "Address"]:
		_check(ops.has(name), "ops menu has " + name)
	var act := _menu_items("行動")
	_check(act.has("Level"), "action menu has Level")
	_check_eq(act.find("Level"), act.find("Skills") - 1, "Level just above Skills")
	var mag := _menu_items("魔法")
	_check(mag.has("WizList") and mag.has("WizEye"), "magic menu has wizlist/wizeye")
	var disp := _menu_items("表示")
	_check(disp.has("MapSizeSetting"), "disp menu has MapSizeSetting")
	# コマンドパレット (ツールバー) 配置。
	for name in ["Level", "SetCG", "SendMail", "ReadMail", "DelMail", "ActionSay", "FakeAction"]:
		_check(PhiActions.TOOLBAR.has(name), "toolbar has " + name)


func _test_master_magic() -> void:
	var data := PhiMasterMagic.parse(PhiMasterMagic.DEFAULT_XML)
	var menus: Array = data.get("menus", [])
	_check_eq(menus.size(), 6, "mm still 6 menus")
	var normal: Dictionary = {}
	for menu in menus:
		if str(menu.get("caption", "")) == "通常魔法":
			normal = menu
	_check(not normal.is_empty(), "mm normal menu found")
	var by_caption := {}
	for item in normal.get("items", []):
		by_caption[str(item.get("caption", ""))] = item
	_check(by_caption.has("DM setup check"), "mm has dmsetupcheck item")
	var check_steps: Array = by_caption.get("DM setup check", {}).get("steps", [])
	_check_eq(check_steps.size(), 1, "dmsetupcheck 1 step")
	_check_eq(str(check_steps[0].get("kind", "")), "send", "dmsetupcheck step send")
	_check_eq(str(check_steps[0].get("text", "")), "dmsetupcheck", "dmsetupcheck text")
	_check(by_caption.has("gfakeaction"), "mm has gfakeaction item")
	var gf_steps: Array = by_caption.get("gfakeaction", {}).get("steps", [])
	_check_eq(gf_steps.size(), 2, "gfakeaction 2 steps")
	_check_eq(str(gf_steps[0].get("kind", "")), "string_dialog", "gfakeaction dialog first")
	_check_eq(str(gf_steps[1].get("text", "")), "gfakeaction %string", "gfakeaction send text")
	var file_menu: Dictionary = {}
	for menu in menus:
		if str(menu.get("caption", "")) == "操作魔法":
			file_menu = menu
	_check(not file_menu.is_empty(), "mm file menu found")
	var file_by_caption := {}
	for item in file_menu.get("items", []):
		file_by_caption[str(item.get("caption", ""))] = item
	for load_name in ["Load jb", "Load pt"]:
		_check(file_by_caption.has(load_name), "mm has " + load_name + " item")
		var load_item: Dictionary = file_by_caption.get(load_name, {})
		var ext: String = str(load_name).trim_prefix("Load ")
		_check_eq(str(load_item.get("hint", "")), "phi." + ext + " を読み込む", load_name + " hint")
		var load_steps: Array = load_item.get("steps", [])
		_check_eq(load_steps.size(), 2, load_name + " 2 steps")
		if load_steps.size() == 2:
			_check_eq(str(load_steps[0].get("kind", "")), "send", load_name + " step0 send")
			_check_eq(str(load_steps[0].get("text", "")), "cast", load_name + " step0 cast")
			_check_eq(str(load_steps[0].get("list", "")), "no", load_name + " step0 list attr")
			_check_eq(str(load_steps[1].get("text", "")), load_name, load_name + " step1 text")


func _test_config_zoom() -> void:
	var path := "/tmp/neophi_stage121.ini"
	var cfg := PhiConfig.new()
	cfg.map_zoom_mode = 1
	cfg.map_zoom_fixed = 7
	_check(cfg.save_file(path), "config save ok")
	var back := PhiConfig.new()
	_check(back.load_file(path), "config load ok")
	_check_eq(back.map_zoom_mode, 1, "zoom mode round trip")
	_check_eq(back.map_zoom_fixed, 7, "zoom fixed round trip")
	# 範囲外は読み込みで丸める。
	var raw := ConfigFile.new()
	raw.set_value("Map", "ZoomMode", 5)
	raw.set_value("Map", "ZoomFixed", 99)
	raw.save(path)
	var clamped := PhiConfig.new()
	clamped.load_file(path)
	_check_eq(clamped.map_zoom_mode, 0, "zoom mode clamped to fit")
	_check_eq(clamped.map_zoom_fixed, 8, "zoom fixed clamped to 8")
	DirAccess.remove_absolute(path)


func _test_map_zoom() -> void:
	# 固定倍率: 小さな窓でも指定倍率のまま。
	var mv := MapView.new()
	mv.size = Vector2(100, 100)
	mv.zoom_mode = 1
	mv.zoom_fixed = 5
	mv._update_zoom()
	_check_eq(mv.zoom, 5, "fixed zoom applied in small window")
	# 固定倍率: 大きな窓でも広がらない。
	mv.size = Vector2(4000, 4000)
	mv.zoom_fixed = 2
	mv._update_zoom()
	_check_eq(mv.zoom, 2, "fixed zoom kept in big window")
	# 固定倍率では地図が窓より大きい時、原点が負側 (中心が見える)。
	mv.zoom_fixed = 2
	mv._update_zoom()
	mv.size = Vector2(100, 100)
	var rect := mv.drawn_map_rect()
	_check(rect.position.x < 0.0 and rect.position.y < 0.0, "fixed mode centers overflow")
	# 通常モード (窓に合わせる) は従来どおり: 収まらなければ縮小し、
	# 原点は 0 で止まる。
	var fv := MapView.new()
	fv.size = Vector2(100, 100)
	fv.zoom = 4
	fv._update_zoom()
	_check_eq(fv.zoom, 1, "fit mode shrinks to fit")
	_check_eq(fv.drawn_map_rect().position, Vector2.ZERO, "fit mode origin clamped")
	mv.free()
	fv.free()
