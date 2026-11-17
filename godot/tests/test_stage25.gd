extends SceneTree
## 第25段 (小物まとめ前半): 状態異常7種・モード表示・ログ時刻・
## Call/Return 確認設定・DispMap アクションの確認。

var _checks := 0
var _failures := 0


func check(cond: bool, label: String) -> void:
	_checks += 1
	if not cond:
		_failures += 1
		print("FAIL: ", label)


func _initialize() -> void:
	# 状態異常7種の名前 (Python 版と同じ並び)。
	var names := StatusPanel.condition_names(
		{"poison": true, "palsy": true, "panic": false, "confuse": true,
		"berserk": false, "silence": true, "blind": true})
	check(names == ["毒", "麻痺", "混乱", "沈黙", "盲目"], "状態異常の名前: %s" % str(names))
	check(StatusPanel.condition_names({}).is_empty(), "状態異常なしは空")
	check(StatusPanel.mode_tags(true, true) == ["戦闘", "魔法"], "モード両方")
	check(StatusPanel.mode_tags(true, false) == ["戦闘"], "モード戦闘のみ")
	check(StatusPanel.mode_tags(false, false).is_empty(), "モードなしは空")
	# パネルへの反映。
	var panel := StatusPanel.new()
	root.add_child(panel)
	panel.set_conditions_all({"poison": true, "blind": true})
	check(panel.condition_text() == "毒 盲目", "パネルの状態異常テキスト")
	panel.set_conditions_all({})
	check(panel.condition_text() == "", "状態異常が消える")
	panel.set_mode(false, true)
	check(panel.mode_text() == "魔法", "パネルのモードテキスト")
	panel.queue_free()
	# 設定: 既定値と保存・復元。
	var cfg := PhiConfig.new()
	check(cfg.log_disp_time == true, "LogDispTime 既定 on")
	check(cfg.dialog_for_call == true, "DialogForCall 既定 on")
	check(cfg.dialog_for_return == true, "DialogForReturn 既定 on")
	cfg.log_disp_time = false
	cfg.dialog_for_call = false
	var path := "/tmp/neophi_stage25.ini"
	check(cfg.save_file(path), "設定を保存できる")
	var cfg2 := PhiConfig.new()
	check(cfg2.load_file(path), "設定を読める")
	check(cfg2.log_disp_time == false, "LogDispTime が復元される")
	check(cfg2.dialog_for_call == false, "DialogForCall が復元される")
	check(cfg2.dialog_for_return == true, "DialogForReturn は既定のまま")
	# DispMap (地図の表示/非表示) は仕様削除済み (ユーザー指定)。
	check(not PhiActions.ACTIONS.has("DispMap"), "DispMap アクションは無い")
	var in_view := false
	for menu in PhiActions.MENUS:
		if str(menu.get("name", "")) == "表示":
			in_view = (menu.get("items", []) as Array).has("DispMap")
	check(not in_view, "DispMap は表示メニューに無い")
	print("test_stage25: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)
