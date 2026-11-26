extends SceneTree
## 第140段のテスト: 行動メニューの v6 の3機能 (カバン・取引・
## 依頼) は、接続先が v6 と判定された時にだけ有効になる。
## 従来サーバ (PHIDM NEO) への接続では無効のままになり、
## メニュー以外の経路 (ディスパッチ直通) で実行しても
## 何も起きない。v6 判定はログイン後のプローブで決まるため、
## 判定の成立・喪失にメニューの出し分けが追随することも見る。
##
## 使い方: godot --headless --path . -s tests/test_stage140.gd
## 終了コード 0 = 全一致、1 = 不一致あり。

const Main := preload("res://scripts/main.gd")

var _failures := 0
var _checks := 0
var _v6_emits := 0


func check(cond: bool, label: String) -> void:
	_checks += 1
	if not cond:
		_failures += 1
		printerr("FAIL: ", label)


func check_eq(a: Variant, b: Variant, label: String) -> void:
	_checks += 1
	if a != b:
		_failures += 1
		printerr("FAIL: ", label, " (got ", a, ", want ", b, ")")


func _queue(tab: PhiCharacter) -> Array:
	return tab.session.get("_send_queue")


func _make_tab() -> PhiCharacter:
	var config := PhiConfig.new()
	config.log_auto_save = false
	config.ui_style = "old"
	var font := PhiFont.make_ui_font()
	var bold := PhiFont.make_bold_font()
	var tab := PhiCharacter.new()
	tab.setup(GameAssets.new(), config, font, bold, PhiLogFilter.new(), PhiTagMenu.parse(PhiTagMenu.DEFAULT_XML))
	root.add_child(tab)
	tab.position = Vector2.ZERO
	tab.size = Vector2(1280, 1024)
	return tab


func _menu_disabled(main: Node, action_name: String) -> bool:
	## メニューの中の項目の無効状態。見つからなければ true
	## (安全側) ではなく、その旨を失敗として返すため -1 を使う
	## 呼び出し側は _menu_has で先に存在を確認すること。
	for popup in main.get("_menu_popups"):
		for i in popup.item_count:
			var meta: Variant = popup.get_item_metadata(i)
			if meta != null and str(meta) == action_name:
				return popup.is_item_disabled(i)
	return true


func _menu_has(main: Node, action_name: String) -> bool:
	for popup in main.get("_menu_popups"):
		for i in popup.item_count:
			var meta: Variant = popup.get_item_metadata(i)
			if meta != null and str(meta) == action_name:
				return true
	return false


func _initialize() -> void:
	_run()


func _run() -> void:
	_test_enabled_when()
	await _test_tab()
	await _test_main()
	print("test_stage140: ", _checks, " checks, ", _failures, " failures")
	quit(1 if _failures > 0 else 0)


# -- enabled_when の単体 ---------------------------------------------------

func _test_enabled_when() -> void:
	for name in ["V6Bag", "V6Trade", "V6Quests"]:
		check(not PhiActions.enabled_when(name, false, false), "s140 " + name + " offline+v6off disabled")
		check(not PhiActions.enabled_when(name, false, true), "s140 " + name + " offline disabled")
		check(not PhiActions.enabled_when(name, true, false), "s140 " + name + " legacy connected disabled")
		check(PhiActions.enabled_when(name, true, true), "s140 " + name + " v6 connected enabled")
		# 2引数の旧呼び出し (v6 省略) では無効のまま。
		check(not PhiActions.enabled_when(name, true), "s140 " + name + " default v6 arg disabled")
	# 従来の出し分けは不変。
	check(PhiActions.enabled_when("Open", false), "s140 open offline")
	check(not PhiActions.enabled_when("Open", true), "s140 open online disabled")
	check(PhiActions.enabled_when("Equip", true), "s140 equip online")
	check(not PhiActions.enabled_when("Equip", false), "s140 equip offline disabled")
	check(PhiActions.enabled_when("Exit", false), "s140 exit always")


# -- タブ単体: 判定の読みと変化通知 ---------------------------------------

func _test_tab() -> void:
	var tab := _make_tab()
	await process_frame
	await process_frame
	check(not tab.is_v6_ready(), "s140 tab legacy not v6 ready")
	# 従来接続では toggle してもパネルは開かない (既存の守り)。
	tab.toggle_v6_bag()
	var bag_panel: Variant = tab.get("_bag_panel")
	check(bag_panel != null and not bag_panel.visible, "s140 legacy toggle bag stays closed")
	check_eq(_queue(tab), [], "s140 legacy toggle sends nothing")
	# 判定が立つと通知が1回だけ出る。
	_v6_emits = 0
	tab.v6_state_changed.connect(func() -> void: _v6_emits += 1)
	tab.session.v6_mode = true
	await process_frame
	await process_frame
	check(tab.is_v6_ready(), "s140 tab v6 ready after flag")
	check_eq(_v6_emits, 1, "s140 v6_state_changed emitted once on gain")
	# 立ったままでは再通知しない。
	await process_frame
	check_eq(_v6_emits, 1, "s140 no re-emit while v6 stays")
	# 判定が落ちても1回だけ。
	tab.session.v6_mode = false
	await process_frame
	await process_frame
	check(not tab.is_v6_ready(), "s140 tab not v6 ready after drop")
	check_eq(_v6_emits, 2, "s140 v6_state_changed emitted once on loss")
	tab.queue_free()


# -- Main 経由: メニューの出し分けとディスパッチの守り ---------------------

func _test_main() -> void:
	var dir := DirAccess.open("user://")
	if dir != null:
		for f in ["stage140_tabs.ini", "stage140_main.ini"]:
			if dir.file_exists(f):
				dir.remove(f)
	var main: Node = Main.new()
	main.set("_tab_session_path", "user://stage140_tabs.ini")
	main.set("_config_path", "user://stage140_main.ini")
	root.add_child(main)
	await process_frame
	await process_frame
	var tab: PhiCharacter = main.call("_active_tab")
	check(tab != null, "s140 main has active tab")
	for name in ["V6Bag", "V6Trade", "V6Quests"]:
		check(_menu_has(main, name), "s140 menu has " + name)
	# 未接続: 3機能とも無効。
	for name in ["V6Bag", "V6Trade", "V6Quests"]:
		check(_menu_disabled(main, name), "s140 menu " + name + " disabled offline")
	# 従来サーバへ接続した体にする (セッションの状態だけ立てる)。
	tab.session.set("_state", "open")
	main.call("_update_action_states")
	for name in ["V6Bag", "V6Trade", "V6Quests"]:
		check(_menu_disabled(main, name), "s140 menu " + name + " disabled on legacy")
	check(not _menu_disabled(main, "Equip"), "s140 menu Equip enabled on legacy")
	# ディスパッチ直通でも何も起きない。
	_queue(tab).clear()
	main.call("_do_action", "V6Bag")
	var bag_panel: Variant = tab.get("_bag_panel")
	check(bag_panel != null and not bag_panel.visible, "s140 legacy dispatch bag stays closed")
	check_eq(_queue(tab), [], "s140 legacy dispatch sends nothing")
	# v6 判定が立つと、通知経由でメニューが有効に追随する。
	# (偽の接続状態は poll が閉じてしまうため、通知が届いた後に
	# 接続状態を立て直してからハンドラ経路で再評価させる。)
	tab.session.v6_mode = true
	await process_frame
	await process_frame
	check(bool(tab.get("_v6_synced")), "s140 main tab noticed v6 gain")
	tab.session.set("_state", "open")
	main.call("_on_tab_v6_state_changed", tab)
	for name in ["V6Bag", "V6Trade", "V6Quests"]:
		check(not _menu_disabled(main, name), "s140 menu " + name + " enabled on v6")
	# ディスパッチが通ってカバンが開く。
	main.call("_do_action", "V6Bag")
	check(bag_panel.visible, "s140 v6 dispatch opens bag")
	check(_queue(tab).has("#ex-inv list"), "s140 v6 dispatch requests bag list")
	# 閉じてから判定を落とすと、メニューは無効に戻り、
	# ディスパッチも素通りする。
	main.call("_do_action", "V6Bag")
	check(not bag_panel.visible, "s140 v6 dispatch closes bag")
	tab.session.v6_mode = false
	await process_frame
	await process_frame
	check(not bool(tab.get("_v6_synced")), "s140 main tab noticed v6 loss")
	tab.session.set("_state", "open")
	main.call("_on_tab_v6_state_changed", tab)
	for name in ["V6Bag", "V6Trade", "V6Quests"]:
		check(_menu_disabled(main, name), "s140 menu " + name + " disabled after v6 loss")
	_queue(tab).clear()
	main.call("_do_action", "V6Bag")
	check(not bag_panel.visible, "s140 post-loss dispatch bag stays closed")
	check_eq(_queue(tab), [], "s140 post-loss dispatch sends nothing")
	main.queue_free()
