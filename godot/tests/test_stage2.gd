extends SceneTree
## 第2段(操作系: F1〜F12・大声・リスト・priv・スキン探索)のテスト。
##
## 使い方: godot --headless --path . -s tests/test_stage2.gd
## 終了コード 0 = 全一致、1 = 不一致あり。

var _failures := 0
var _checks := 0
var _tmp_files: Array[String] = []
var _tmp_dirs: Array[String] = []


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


func _cleanup_tmp() -> void:
	for path in _tmp_files:
		DirAccess.remove_absolute(path)
	_tmp_files.clear()
	_tmp_dirs.reverse()
	for dir in _tmp_dirs:
		DirAccess.remove_absolute(dir)
	_tmp_dirs.clear()


func _make_dir(path: String) -> void:
	DirAccess.make_dir_recursive_absolute(path)
	_tmp_dirs.append(path)


# -- ショートカットの変換 -----------------------------------------------------

func _test_shortcuts() -> void:
	# F1〜F7: 既定は番号。
	for no in range(1, 8):
		_check_eq(PhiShortcuts.magic_text(no, false, ""), "cast\n" + str(no), "magic number F" + str(no))
		_check_eq(PhiShortcuts.magic_text(no, false, "cure"), "cast\n" + str(no), "magic number ignores spell F" + str(no))
	# FuncKeyMagicFix が on なら魔法名。
	_check_eq(PhiShortcuts.magic_text(1, true, "cure"), "cast\ncure", "magic fix cure")
	_check_eq(PhiShortcuts.magic_text(3, true, "  harm  "), "cast\nharm", "magic fix strips spaces")
	# Fix が on で魔法名が空なら何も送らない。
	_check_eq(PhiShortcuts.magic_text(2, true, ""), "", "magic fix empty")
	_check_eq(PhiShortcuts.magic_text(2, true, "   "), "", "magic fix blank")
	# 番号の範囲外。
	_check_eq(PhiShortcuts.magic_text(0, false, ""), "", "magic no 0")
	_check_eq(PhiShortcuts.magic_text(8, false, ""), "", "magic no 8")

	# F8〜F12: 通常は \n の文字を改行に置き換える。
	_check_eq(PhiShortcuts.shortcut_text("board", ".", false), "board", "shortcut plain")
	_check_eq(PhiShortcuts.shortcut_text("cast\\ncure", ".", false), "cast\ncure", "shortcut backslash n")
	_check_eq(PhiShortcuts.shortcut_text("a\\nb\\nc", ".", false), "a\nb\nc", "shortcut multi newline")
	_check_eq(PhiShortcuts.shortcut_text("", ".", false), "", "shortcut empty")
	# リストの間はリスト用文字列をそのまま。
	_check_eq(PhiShortcuts.shortcut_text("board", ".", true), ".", "shortcut list mode")
	_check_eq(PhiShortcuts.shortcut_text("board", "3", true), "3", "shortcut list mode number")
	_check_eq(PhiShortcuts.shortcut_text("board", "a\\nb", true), "a\\nb", "shortcut list mode literal")

	# リストの行番号。
	_check_eq(PhiShortcuts.list_number("[  1] wizard eye", 0), "1", "list number bracket")
	_check_eq(PhiShortcuts.list_number("[ 12] cure", 3), "12", "list number bracket 12")
	_check_eq(PhiShortcuts.list_number("[1] cure", 0), "1", "list number bracket tight")
	_check_eq(PhiShortcuts.list_number("  [  2] harm", 0), "2", "list number leading spaces")
	_check_eq(PhiShortcuts.list_number("wizard eye", 0), "1", "list number fallback first")
	_check_eq(PhiShortcuts.list_number("cure", 4), "5", "list number fallback fifth")
	_check_eq(PhiShortcuts.list_number("[x] cure", 2), "3", "list number bad bracket")
	_check_eq(PhiShortcuts.list_number("[ 3 cure", 1), "2", "list number no close")

	# #user の鍵から番号。
	_check_eq(PhiShortcuts.user_number("u12"), 12, "user number u12")
	_check_eq(PhiShortcuts.user_number("u3"), 3, "user number u3")
	_check_eq(PhiShortcuts.user_number("u0012"), 12, "user number padded")
	_check_eq(PhiShortcuts.user_number("12"), -1, "user number no prefix")
	_check_eq(PhiShortcuts.user_number("x12"), -1, "user number bad prefix")
	_check_eq(PhiShortcuts.user_number("u"), -1, "user number empty")
	_check_eq(PhiShortcuts.user_number("u0"), -1, "user number zero")
	_check_eq(PhiShortcuts.user_number("u-1"), -1, "user number negative")
	_check_eq(PhiShortcuts.user_number(""), -1, "user number empty key")


func _test_speech_transform() -> void:
	# 普通の発言はそのまま。
	var plain := PhiShortcuts.speech_transform("こんにちは", false, false, false, 0, true)
	_check_eq(plain["text"], "こんにちは", "speech plain")
	_check_eq(plain["need_confirm"], false, "speech plain no confirm")
	# 空行は /**/ になる。
	var empty := PhiShortcuts.speech_transform("", false, false, false, 0, true)
	_check_eq(empty["text"], "/**/", "speech empty")
	# Ctrl+Enter はパーティー発言。
	var party := PhiShortcuts.speech_transform("行くよ", true, false, false, 0, true)
	_check_eq(party["text"], "+行くよ", "speech party")
	# PartyTalkByCtrl が off なら + は付かない。
	var party_off := PhiShortcuts.speech_transform("行くよ", true, false, false, 0, false)
	_check_eq(party_off["text"], "行くよ", "speech party off")
	# 大声ボタンが on なら確認が要る。まだ * は付かない。
	var loud := PhiShortcuts.speech_transform("聞こえる?", false, true, false, 0, true)
	_check_eq(loud["text"], "聞こえる?", "speech loud pending text")
	_check_eq(loud["need_confirm"], true, "speech loud confirm")
	# 「すべて大声」なら確認なしで * を付ける。
	var loud_all := PhiShortcuts.speech_transform("聞こえる?", false, true, true, 0, true)
	_check_eq(loud_all["text"], "*聞こえる?", "speech loud all")
	_check_eq(loud_all["need_confirm"], false, "speech loud all no confirm")
	# 行頭 * は、LoudlyByAsterisk=0 なら /**/ を差し込んで消す。
	var star0 := PhiShortcuts.speech_transform("*大声?", false, false, false, 0, true)
	_check_eq(star0["text"], "/**/*大声?", "speech star mode 0")
	# =1 なら Ctrl+Enter の時だけ大声。
	var star1_plain := PhiShortcuts.speech_transform("*大声?", false, false, false, 1, true)
	_check_eq(star1_plain["text"], "/**/*大声?", "speech star mode 1 plain")
	var star1_ctrl := PhiShortcuts.speech_transform("*大声?", true, false, false, 1, true)
	_check_eq(star1_ctrl["text"], "*大声?", "speech star mode 1 ctrl")
	# =2 ならいつでも大声。
	var star2 := PhiShortcuts.speech_transform("*大声?", false, false, false, 2, true)
	_check_eq(star2["text"], "*大声?", "speech star mode 2")
	# 大声ボタンは行頭 * より先に見る。
	var loud_star := PhiShortcuts.speech_transform("*大声?", false, true, false, 0, true)
	_check_eq(loud_star["need_confirm"], true, "speech loud beats star")
	# 大声ボタンはパーティーより先に見る。
	var loud_party := PhiShortcuts.speech_transform("行くよ", true, true, false, 0, true)
	_check_eq(loud_party["need_confirm"], true, "speech loud beats party")


# -- 設定の新しいキー ----------------------------------------------------------

func _test_config_stage2() -> void:
	var cfg := PhiConfig.new()
	_check_eq(cfg.func_key_magic_fix, false, "config default magic fix")
	_check_eq(cfg.magic_f, ["", "", "", "", "", "", ""], "config default magic names")
	_check_eq(cfg.shortcut_f, ["", "", "", "", ""], "config default shortcuts")
	_check_eq(cfg.shortcut_list_cancel, [0, 0, 0, 0, 0], "config default list cancel")
	_check_eq(cfg.list_mode_shortcut, [".", ".", ".", ".", "."], "config default list shortcuts")
	_check_eq(cfg.alt_g_word, "おやすみなさいませ", "config default alt g")
	_check_eq(cfg.loudly_by_asterisk, 0, "config default loudly")
	_check_eq(cfg.party_talk_by_ctrl, true, "config default party ctrl")
	_check_eq(cfg.popup_priv_form, true, "config default popup priv")

	var path := OS.get_temp_dir().path_join("neophi-test-config-stage2.ini")
	DirAccess.remove_absolute(path)
	cfg.func_key_magic_fix = true
	cfg.magic_f = ["cure", "harm", "", "", "", "", ""]
	cfg.shortcut_f = ["board", "cast\\ncure", "", "", ""]
	cfg.shortcut_list_cancel = [1, 0, 2, 0, 0]
	cfg.list_mode_shortcut = [".", "3", ".", ".", "."]
	cfg.alt_g_word = "おはよう"
	cfg.loudly_by_asterisk = 2
	cfg.party_talk_by_ctrl = false
	cfg.popup_priv_form = false
	_check(cfg.save_file(path), "config stage2 save")
	_tmp_files.append(path)
	var text := FileAccess.get_file_as_string(path)
	for section in ["[Shortcut]", "[Edit]", "[Priv]"]:
		_check(text.contains(section), "config stage2 section " + section)
	_check(text.contains("MagicF01"), "config stage2 MagicF01 key")
	_check(text.contains("ShortcutF08"), "config stage2 ShortcutF08 key")
	_check(text.contains("ListModeShortcutF08"), "config stage2 ListModeShortcutF08 key")
	_check(text.contains("AltGWord"), "config stage2 AltGWord key")
	_check(not text.contains("guest"), "config stage2 no id saved")

	var cfg2 := PhiConfig.new()
	_check(cfg2.load_file(path), "config stage2 load")
	_check_eq(cfg2.func_key_magic_fix, true, "config stage2 roundtrip fix")
	_check_eq(cfg2.magic_f[0], "cure", "config stage2 roundtrip magic 1")
	_check_eq(cfg2.magic_f[1], "harm", "config stage2 roundtrip magic 2")
	_check_eq(cfg2.shortcut_f[0], "board", "config stage2 roundtrip shortcut 8")
	_check_eq(cfg2.shortcut_f[1], "cast\\ncure", "config stage2 roundtrip shortcut 9")
	_check_eq(cfg2.shortcut_list_cancel[0], 1, "config stage2 roundtrip cancel 8")
	_check_eq(cfg2.shortcut_list_cancel[2], 2, "config stage2 roundtrip cancel 10")
	_check_eq(cfg2.list_mode_shortcut[1], "3", "config stage2 roundtrip list shortcut")
	_check_eq(cfg2.alt_g_word, "おはよう", "config stage2 roundtrip alt g")
	_check_eq(cfg2.loudly_by_asterisk, 2, "config stage2 roundtrip loudly")
	_check_eq(cfg2.party_talk_by_ctrl, false, "config stage2 roundtrip party")
	_check_eq(cfg2.popup_priv_form, false, "config stage2 roundtrip popup")

	# おかしな値は既定値に戻る。
	var bad := ConfigFile.new()
	bad.set_value("Edit", "LoudlyByAsterisk", 9)
	bad.set_value("Shortcut", "ShortcutF08ListCancel", -3)
	var bad_path := OS.get_temp_dir().path_join("neophi-test-config-stage2-bad.ini")
	bad.save(bad_path)
	_tmp_files.append(bad_path)
	var cfg3 := PhiConfig.new()
	_check(cfg3.load_file(bad_path), "config stage2 load bad file")
	_check_eq(cfg3.loudly_by_asterisk, 2, "config stage2 bad loudly clamped")
	_check_eq(cfg3.shortcut_list_cancel[0], 0, "config stage2 bad cancel clamped")

	cfg2.reset()
	_check_eq(cfg2.func_key_magic_fix, false, "config stage2 reset fix")
	_check_eq(cfg2.magic_f[0], "", "config stage2 reset magic")
	_check_eq(cfg2.shortcut_f[0], "", "config stage2 reset shortcut")
	_check_eq(cfg2.alt_g_word, "おやすみなさいませ", "config stage2 reset alt g")
	_check_eq(cfg2.loudly_by_asterisk, 0, "config stage2 reset loudly")
	_check_eq(cfg2.popup_priv_form, true, "config stage2 reset popup")


# -- スキンの探索 ---------------------------------------------------------------

func _test_find_philly_root() -> void:
	var base := OS.get_temp_dir().path_join("neophi-stage2-root-test")
	_make_dir(base.path_join("first/Skins/Mine"))
	_make_dir(base.path_join("second/Skins/Mine"))
	_make_dir(base.path_join("third/Skins/Other"))
	_make_dir(base.path_join("empty"))
	# 最初に見つかった土台を返す。
	_check_eq(
		GameAssets.find_philly_root("Mine", [base.path_join("first"), base.path_join("second")]),
		base.path_join("first"), "find root first")
	# 無い土台は飛ばす。
	_check_eq(
		GameAssets.find_philly_root("Mine", [base.path_join("empty"), base.path_join("second")]),
		base.path_join("second"), "find root skips empty")
	# 違うスキン名のフォルダしか無ければ見つからない。
	_check_eq(
		GameAssets.find_philly_root("Mine", [base.path_join("third")]),
		"", "find root wrong skin")
	_check_eq(
		GameAssets.find_philly_root("Other", [base.path_join("third")]),
		base.path_join("third"), "find root other skin")
	# 空の土台は飛ばす。
	_check_eq(
		GameAssets.find_philly_root("Mine", ["", base.path_join("first")]),
		base.path_join("first"), "find root skips blank base")
	# 無ければ ""。
	_check_eq(GameAssets.find_philly_root("Mine", []), "", "find root no bases")
	_check_eq(
		GameAssets.find_philly_root("NoSuch", [base.path_join("first"), base.path_join("second")]),
		"", "find root missing")
	# 危険なスキン名は探さない。
	_check_eq(GameAssets.find_philly_root("../Mine", [base.path_join("first")]), "", "find root dotdot")
	_check_eq(GameAssets.find_philly_root("a/b", [base.path_join("first")]), "", "find root slash")
	_check_eq(GameAssets.find_philly_root("", [base.path_join("first")]), "", "find root empty skin")
	# 実物の Philly ソースがあれば、Mine が見つかる。
	var real_root := "/home/hatch/workspace/philly-source/PhillySrc/Philly"
	if DirAccess.open(real_root.path_join("Skins/Mine")) != null:
		_check_eq(
			GameAssets.find_philly_root("Mine", [real_root]),
			real_root, "find root real philly")


# -- アクション表の新しい項目 ----------------------------------------------------

func _test_actions_stage2() -> void:
	for action_name in ["NewPrivWindow", "Loud", "ShortcutConfig"]:
		var action := PhiActions.get_action(action_name)
		_check(not action.is_empty(), "stage2 action exists " + action_name)
		_check(not str(action.get("caption", "")).is_empty(), "stage2 action caption " + action_name)
		_check(not str(action.get("hint", "")).is_empty(), "stage2 action hint " + action_name)
		_check(not str(action.get("kind", "")).is_empty(), "stage2 action kind " + action_name)
	_check_eq(PhiActions.kind_of("NewPrivWindow"), "priv-window", "stage2 kind priv")
	_check_eq(PhiActions.kind_of("Loud"), "loud-toggle", "stage2 kind loud")
	_check_eq(PhiActions.kind_of("ShortcutConfig"), "shortcut-config", "stage2 kind shortcut config")
	# 操作メニューがある。
	var has_ops := false
	for menu in PhiActions.MENUS:
		if str(menu["name"]) == "操作":
			has_ops = true
			var items: Array = menu["items"]
			_check(items.has("NewPrivWindow"), "stage2 menu has priv")
			_check(items.has("Loud"), "stage2 menu has loud")
	_check(has_ops, "stage2 ops menu exists")
	# ツールバーに priv と大声がある。
	_check((PhiActions.TOOLBAR as Array).has("NewPrivWindow"), "stage2 toolbar has priv")
	_check((PhiActions.TOOLBAR as Array).has("Loud"), "stage2 toolbar has loud")
	# 接続時のみ有効。
	_check_eq(PhiActions.enabled_when("NewPrivWindow", true), true, "stage2 priv enabled connected")
	_check_eq(PhiActions.enabled_when("NewPrivWindow", false), false, "stage2 priv disabled offline")
	_check_eq(PhiActions.enabled_when("Loud", true), true, "stage2 loud enabled connected")
	_check_eq(PhiActions.enabled_when("Loud", false), false, "stage2 loud disabled offline")
	_check_eq(PhiActions.enabled_when("ShortcutConfig", false), true, "stage2 shortcut config always enabled")


# -- 移動キー表 -------------------------------------------------------------------

func _test_move_tables() -> void:
	# 北固定: カーソルは絶対方向、Ctrl+カーソルは向きを変えずに進む(カニ歩き)。
	_check_eq(PhiKeys.move_command("8", "none", true), "go N", "north fix up")
	_check_eq(PhiKeys.move_command("2", "none", true), "go S", "north fix down")
	_check_eq(PhiKeys.move_command("4", "none", true), "go W", "north fix left")
	_check_eq(PhiKeys.move_command("6", "none", true), "go E", "north fix right")
	_check_eq(PhiKeys.move_command("8", "ctrl", true), "go n", "north fix ctrl up")
	_check_eq(PhiKeys.move_command("4", "ctrl", true), "go w", "north fix ctrl left")
	# 回転: カーソルは相対移動、左右はカニ歩き。
	_check_eq(PhiKeys.move_command("8", "none", false), "go", "turn up")
	_check_eq(PhiKeys.move_command("2", "none", false), "go b", "turn down")
	_check_eq(PhiKeys.move_command("4", "none", false), "go l", "turn left crab")
	_check_eq(PhiKeys.move_command("6", "none", false), "go r", "turn right crab")
	# move_input がカーソルキーと Ctrl を通す。
	var up: Variant = PhiKeys.move_input("ArrowUp", false, false, false, false, true)
	_check(up != null, "move input arrow up")
	_check_eq(PhiKeys.move_command(str(up[0]), str(up[1]), true), "go N", "move input up north fix")
	var ctrl_left: Variant = PhiKeys.move_input("ArrowLeft", false, true, false, false, true)
	_check(ctrl_left != null, "move input ctrl left")
	_check_eq(PhiKeys.move_command(str(ctrl_left[0]), str(ctrl_left[1]), true), "go w", "move input ctrl left crab")
	# F キーは移動キーではない。
	_check_eq(PhiKeys.move_input("F1", false, false, false, false, true), null, "move input F1 null")
	# キー名の確認。
	_check_eq(PhiKeys.code_name(KEY_F8), "F8", "code name F8")
	_check_eq(PhiKeys.code_name(KEY_F12), "F12", "code name F12")
	_check_eq(PhiKeys.code_name(KEY_G), "KeyG", "code name G")
	_check_eq(PhiKeys.code_name(KEY_UP), "ArrowUp", "code name up")
	_check_eq(PhiKeys.code_name(KEY_1), "Digit1", "code name digit 1")
	_check_eq(PhiKeys.code_name(KEY_KP_3), "Numpad3", "code name numpad 3")


func _initialize() -> void:
	_test_shortcuts()
	_test_speech_transform()
	_test_config_stage2()
	_test_find_philly_root()
	_test_actions_stage2()
	_test_move_tables()
	_cleanup_tmp()
	print("test_stage2: ", _checks, " checks, ", _failures, " failures")
	quit(1 if _failures > 0 else 0)
