extends SceneTree
## 第76段: コマンドパレットの初期位置が左上に残る不具合の修正。
## 起動直後はレイアウト前で地図の大きさが 0 のため、右上を
## 計算できず仮置き (8,8) になっていた。大きさが決まったら
## (地図の resized) 置き直す。保持値がある場合は従来どおり
## 大きさに依らず即その位置。ドラッグを始めたら置き直しは止まる。

var _checks := 0
var _failures := 0


func check(cond: bool, label: String) -> void:
	_checks += 1
	if not cond:
		_failures += 1
		print("FAIL: ", label)


func _initialize() -> void:
	_run.call_deferred()


func _make_tab(cfg: PhiConfig) -> PhiCharacter:
	var tab := PhiCharacter.new()
	tab.setup(GameAssets.new(), cfg, PhiFont.make_ui_font(),
		PhiFont.make_bold_font(), PhiLogFilter.new(), {})
	return tab


func _shrink_buttons(tab: PhiCharacter) -> void:
	# アイコン付きボタンの寸法に寄せる (test_layout と同じ流儀)。
	for b in tab.get("_toolbar_buttons"):
		var button := b as Button
		button.text = ""
		button.custom_minimum_size = Vector2(34, 34)
	tab.call("_fit_toolbar_panel")


func _run() -> void:
	# (1) 保持値なし・大きさ未定 → 仮置き (8,8) で自動配置中。
	var cfg := PhiConfig.new()
	var tab := _make_tab(cfg)
	var panel := tab.get("_toolbar_panel") as PanelContainer
	check(panel != null, "panel exists")
	check(panel.position == Vector2(8, 8), "provisional position is (8,8)")
	check(bool(tab.get("_toolbar_auto_home")), "auto home while unsized")
	_shrink_buttons(tab)

	# (2) ツリーに入れて大きさが決まると、右上へ置き直される。
	# パネル自体の縮みにも追随する (フォント確定で幅が変わる)。
	root.add_child(tab)
	tab.position = Vector2.ZERO
	tab.size = Vector2(1280, 1024)
	await create_timer(0.5).timeout
	check(bool(tab.get("_toolbar_auto_home")), "still auto home after layout")
	check(panel.position.y == 8.0, "pallet at top after layout")
	check(panel.position.x > 8.0, "pallet moved right after layout x=%f" % panel.position.x)
	check(panel.position == (tab.call("_toolbar_home_position") as Vector2),
		"pallet matches home after layout")

	# (3) 保持値がある場合は、大きさ未定でも即その位置で自動配置なし。
	var cfg2 := PhiConfig.new()
	cfg2.toolbar_pos = Vector2(100, 50)
	var tab2 := _make_tab(cfg2)
	var panel2 := tab2.get("_toolbar_panel") as PanelContainer
	check(panel2.position == Vector2(100, 50), "saved position applied at once")
	check(not bool(tab2.get("_toolbar_auto_home")), "no auto home with saved position")
	tab2.free()

	# (4) ドラッグを始めたら、自動配置は終わる。
	var cfg3 := PhiConfig.new()
	var tab3 := _make_tab(cfg3)
	check(bool(tab3.get("_toolbar_auto_home")), "auto home before drag")
	var panel3 := tab3.get("_toolbar_panel") as PanelContainer
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = panel3.global_position + Vector2(4, 4)
	press.global_position = press.position
	tab3.call("_on_toolbar_panel_gui_input", press)
	check(not bool(tab3.get("_toolbar_auto_home")), "drag start ends auto home")
	tab3.free()

	tab.free()
	print("test_stage76: ", _checks, " checks, ", _failures, " failures")
	quit(1 if _failures > 0 else 0)
