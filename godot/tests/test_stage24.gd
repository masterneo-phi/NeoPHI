extends SceneTree
## 第24段: 超魔法メニューの出し分け (EXP 99999999 / 設定) の確認。

var _checks := 0
var _failures := 0


func check(cond: bool, label: String) -> void:
	_checks += 1
	if not cond:
		_failures += 1
		print("FAIL: ", label)


func _initialize() -> void:
	# マスターの EXP は 99999999 (仕様書 §9.1)。
	check(PhiMasterMagic.MASTER_EXP == 99999999, "MASTER_EXP は 99999999")
	# アクション定義: 表示メニューに「超魔法メニューを常に出す」がある。
	var action: Dictionary = PhiActions.ACTIONS.get("MasterMagicAlways", {})
	check(not action.is_empty(), "MasterMagicAlways アクションがある")
	check(str(action.get("kind", "")) == "master-magic-toggle", "kind は master-magic-toggle")
	var in_view := false
	for menu in PhiActions.MENUS:
		if str(menu.get("name", "")) == "表示":
			in_view = (menu.get("items", []) as Array).has("MasterMagicAlways")
	check(in_view, "表示メニューに入っている")
	# 未接続でも切り替えられる (常時有効)。
	check(PhiActions.enabled_when("MasterMagicAlways", false), "未接続でも有効")
	check(PhiActions.enabled_when("MasterMagicAlways", true), "接続中も有効")
	# 設定の保存と復元。
	var path := "/tmp/neophi_stage24.ini"
	var cfg := PhiConfig.new()
	check(cfg.master_magic_always == false, "既定は off (マスターの時だけ出す)")
	cfg.master_magic_always = true
	check(cfg.save_file(path), "設定を保存できる")
	var cfg2 := PhiConfig.new()
	check(cfg2.load_file(path), "設定を読める")
	check(cfg2.master_magic_always == true, "MasterMagicMenu が復元される")
	print("test_stage24: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)
