extends SceneTree
## 第16段のテスト: 既定の効果音 (同梱 WAV + 既定ルール) と
## 「効果音を再生する」トグル。ルールの照合先、優先順位、
## エンジンが se_requested を出すこと、BGM と独立なことを見る。
##
## 使い方: godot --headless --path . -s tests/test_stage16.gd
## 終了コード 0 = 全一致、1 = 不一致あり。

var _failures := 0
var _checks := 0
var _se_paths: Array = []


func _check(cond: bool, label: String) -> void:
	_checks += 1
	if not cond:
		_failures_add(label)


func _check_eq(a: Variant, b: Variant, label: String) -> void:
	_checks += 1
	if a != b:
		_failures_add(label + " (got " + str(a) + ", want " + str(b) + ")")


func _failures_add(label: String) -> void:
	_failures += 1
	printerr("FAIL: ", label)


func _initialize() -> void:
	_run()


func _test_default_rules() -> void:
	var rules := PhiSeRules.new()
	rules.load_texts(PhiSeRules.DEFAULT_REGEXP_TEXT, PhiSeRules.DEFAULT_FILE_TEXT)
	_check_eq(rules.bad_count, 0, "既定ルールは全部コンパイルできる")
	_check_eq(rules.rule_count(), 15, "既定ルールは15件")
	var cases := [
		["DM > モック太郎 は魔法を唱えている...", "sound\\se\\cast.wav"],
		["DM > モック猫 は モック太郎 に殺された.", "sound\\se\\death.wav"],
		["DM > モック太郎 が Cure によって回復した. [40 hp]", "sound\\se\\cure.wav"],
		["DM > モック太郎 は 20 mp 回復した.", "sound\\se\\cure.wav"],
		["DM > アイテムを拾いました", "sound\\se\\get.wav"],
		["DM > それはできません", "sound\\se\\ng.wav"],
		["DM > モック太郎 は モック猫 を 拳 で攻撃した. [6 hp]", "sound\\se\\attack.wav"],
		["DM > モック猫 は モック太郎 を Fang で攻撃した. [3 hp]", "sound\\se\\attack.wav"],
		["DM > 鍵を掛けました.", "sound\\se\\lock.wav"],
		["DM > 鍵を外しました.", "sound\\se\\unlock.wav"],
		["DM > Guest によって鍵を掛けられています.", "sound\\se\\bump.wav"],
		["DM > モック太郎 はレベル 5 になった.", "sound\\se\\levelup.wav"],
		["DM > モック太郎 は モック猫 からダメージを受けた. [5 hp]", "sound\\se\\hurt.wav"],
		["DM > モック猫 は モック太郎 の攻撃を受け止めた.", "sound\\se\\guard.wav"],
		["DM > モック太郎 は 剣 を装備した.", "sound\\se\\equip.wav"],
		["DM > モック太郎 は 剣 を外しました.", "sound\\se\\equip.wav"],
		["DM > テスト世界 へ移動中 ...", "sound\\se\\warp.wav"],
		["DM > 鍵を掛けるのに失敗しました.", "sound\\se\\fail.wav"],
	]
	for c in cases:
		var entry := rules.match_entry(str(c[0]))
		_check_eq(str(entry.get("file", "")), str(c[1]), "照合: " + str(c[0]))
	_check(rules.match_entry("DM > モックサーバへようこそ。").is_empty(), "関係ない行には合わない")
	# 先勝ち: 詠唱行は攻撃より先に判定される。
	var chant := rules.match_entry("DM > 魔法を唱えている... 攻撃した")
	_check_eq(str(chant.get("file", "")), "sound\\se\\cast.wav", "詠唱が先勝ち")


func _test_engine(root_dir: String) -> void:
	var config := PhiConfig.new()
	var engine := PhiSoundEngine.new()
	root.add_child(engine)
	engine.setup(config, [root_dir])
	engine.set_se_texts(PhiSeRules.DEFAULT_REGEXP_TEXT, PhiSeRules.DEFAULT_FILE_TEXT)
	engine.se_requested.connect(func(path: String) -> void: _se_paths.append(path))
	engine.play_se_for_line("DM > モック太郎 は モック猫 を 拳 で攻撃した. [6 hp]")
	_check_eq(_se_paths.size(), 1, "攻撃行で SE が1つ鳴る")
	if _se_paths.size() == 1:
		_check(str(_se_paths[0]).ends_with("sound/se/attack.wav"), "attack.wav が解決される")
	# トグル off では鳴らない。
	config.sound_play = false
	engine.play_se_for_line("DM > モック太郎 は モック猫 を 拳 で攻撃した. [6 hp]")
	_check_eq(_se_paths.size(), 1, "sound_play off では鳴らない")
	config.sound_play = true
	# BGM とは独立: BGM の状態に触れていない。
	_check_eq(engine.bgm_state(), "stop", "BGM は止まったまま (SE と独立)")
	engine.queue_free()


func _test_action_table() -> void:
	_check_eq(PhiActions.kind_of("PlaySE"), "se-toggle", "PlaySE の kind")
	var found := false
	for menu in PhiActions.MENUS:
		if str(menu["name"]) == "表示" and (menu["items"] as Array).has("PlaySE"):
			found = true
	_check(found, "表示メニューに PlaySE がある")


func _run() -> void:
	_test_default_rules()
	_test_action_table()
	# WAV の置き場所 (リポジトリ内の生成物) をルートにして解決を見る。
	var root_dir := ProjectSettings.globalize_path("res://").path_join("../neophi-se")
	_test_engine(root_dir)
	print("test_stage16: ", _checks, " checks, ", _failures, " failures")
	quit(1 if _failures > 0 else 0)
