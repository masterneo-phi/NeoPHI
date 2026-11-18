extends SceneTree
## 第47段: メニュー・行動の総点検。
## 静的: MENUS/TOOLBAR の項目が全て ACTIONS にある、kind が
## main._do_action の処理対象に全てある、send/ask の中身が揃って
## いる、Alt 表・アクセラレータ・系統魔法表の参照先がある、
## キー表が Python 版と一致する (Shift+9 の 9x9、End のリスト
## 抑えの回帰含む)、超魔法データの step が全て処理対象。
## 動的: 全アクションを実際に _do_action で発火させ、送信系は
## セッションのキュー、ask はダイアログ、切替系は設定の反転、
## 窓系は窓の表示で「動いた」ことを確認する。

const Main := preload("res://scripts/main.gd")

var _checks := 0
var _failures := 0


func check(cond: bool, label: String) -> void:
	_checks += 1
	if not cond:
		_failures += 1
		print("FAIL: ", label)


const DISPATCH_KINDS := [
	"send", "ask", "connect", "disconnect", "force-disconnect",
	"connect-all", "disconnect-all", "force-disconnect-all",
	"reload-config", "reset-config", "clear-cache", "exit",
	"priv-window", "loud-toggle", "talk-add", "shortcut-config",
	"unew-panel", "sound-test", "chip-viewer", "chara-viewer",
	"say-all-tabs", "autosave-toggle", "log-save", "log-save-dir",
	"delete-filter-toggle", "image-window", "screenshot",
	"scroll-toggle", "smooth-scroll-toggle", "disp-magic-toggle", "bgm-toggle", "se-toggle",
	"master-magic-toggle", "open-config-folder", "update-check",
	"about", "image-toggle", "ui-style-toggle", "map-align", "layout-to-all-tabs",
]


func _initialize() -> void:
	call_deferred("_run")


func _static_checks() -> void:
	# メニューとツールバーの項目が全て実在する。
	for menu in PhiActions.MENUS:
		for item in menu["items"]:
			var name := str(item)
			if name == "-":
				continue
			check(not PhiActions.get_action(name).is_empty(), "menu item exists: " + name)
	for item in PhiActions.TOOLBAR:
		var name := str(item)
		if name == "-":
			continue
		check(not PhiActions.get_action(name).is_empty(), "toolbar item exists: " + name)
	# 全アクションの定義が揃い、kind に受け口がある。
	for name in PhiActions.ACTIONS:
		var action := PhiActions.get_action(name)
		check(not str(action.get("caption", "")).is_empty(), "caption: " + name)
		var kind := PhiActions.kind_of(name)
		check(DISPATCH_KINDS.has(kind), "kind dispatched: " + name + " (" + kind + ")")
		if kind == "send":
			check(not PhiActions.send_text_for(name).is_empty(), "send text: " + name)
		if kind == "ask":
			check(str(action.get("template", "")).contains("%s"), "ask template: " + name)
			check(not str(action.get("title", "")).is_empty(), "ask title: " + name)
			check(not str(action.get("label", "")).is_empty(), "ask label: " + name)
	# Alt 表・アクセラレータ・系統魔法表の参照先。
	for code in PhiActions.ALT_ACTIONS:
		check(PhiActions.ACTIONS.has(str(PhiActions.ALT_ACTIONS[code])), "alt target: " + code)
	for code in PhiActions.SHIFT_ALT_ACTIONS:
		check(PhiActions.ACTIONS.has(str(PhiActions.SHIFT_ALT_ACTIONS[code])), "shift-alt target: " + code)
	for name in PhiActions.ACCELERATORS:
		check(PhiActions.ACTIONS.has(name), "accelerator target: " + name)
	for name in PhiActions.SYSTEM_MAGIC:
		check(PhiActions.ACTIONS.has(name), "system magic exists: " + name)
	# キー表 (第111段で全面変更: 文字を打つキーは割り当てず、
	# 1文字ショートカットは当初の割り当てのまま (第111段の
	# 最終決定)。追加分は Option (Alt) 系だけ。
	var none_expect := {
		"KeyA": "read", "KeyB": "board", "KeyC": "use", "KeyD": "erase",
		"KeyF": "floor item", "KeyM": "check\nlook",
		"KeyN": "n", "KeyQ": "equip", "KeyR": "spells", "KeyS": "write",
		"KeyV": "sort", "KeyW": "unequip",
		"KeyX": "put", "KeyY": "y", "KeyZ": "get", "Period": ".",
		"Space": "hit", "Digit0": ".", "Home": "equip\nsort",
		"End": "unequip\n1", "Numpad0": "check\nlook",
		"Numpad1": "hit", "Numpad3": "cast", "NumpadAdd": "get",
		"NumpadSubtract": "put", "NumpadEnter": "cast",
		"NumpadDivide": "equip", "NumpadMultiply": "use",
		"NumpadDecimal": ".",
	}
	for i in range(1, 7):
		none_expect["Digit%d" % i] = str(i)
	# Digit7/8/9 はフルキー移動でテンキー扱い (移動キー) なので、
	# 数字の送信にはならない (Python 版の _normalize と同じ)。
	for i in range(7, 10):
		check(PhiKeys.key_send("Digit%d" % i) == "", "key_send Digit%d is a move" % i)
		check(PhiKeys.move_input("Digit%d" % i) != null, "move_input Digit%d" % i)
	for i in range(1, 8):
		none_expect["F%d" % i] = "cast\n%d" % i
	for code in none_expect:
		check(PhiKeys.key_send(code) == str(none_expect[code]), "key_send none: " + code)
	check(PhiKeys.key_send("KeyP") == "", "key_send KeyP is ask, not send")
	# Shift を使うショートカットは廃止 (第111段)。回転 (T /
	# Shift+T)・話しかける (H)・サイズ (Shift+数字) は Option
	# 系へ移した。
	var shift_expect := {"Space": "hit"}
	for code in shift_expect:
		check(PhiKeys.key_send(code, true) == str(shift_expect[code]), "key_send shift: " + code)
	check(PhiKeys.key_send("KeyT") == "", "key_send KeyT removed (Option+T toggle)")
	check(PhiKeys.key_send("KeyT", true) == "", "key_send Shift+KeyT removed")
	check(PhiKeys.key_send("KeyH") == "", "key_send KeyH removed (Option+H)")
	check(PhiKeys.key_send("Digit5", true) == "", "key_send Shift+Digit5 removed")
	check(PhiKeys.move_input("Digit9", true) != null, "shift+9 is a shift-move now")
	check(PhiKeys.move_input("Numpad9", true) != null, "shift+numpad9 is a shift-move now")
	var ctrl_expect := {"Numpad1": "hit", "Numpad3": "cast", "Space": "hit"}
	for code in ctrl_expect:
		check(PhiKeys.key_send(code, false, true) == str(ctrl_expect[code]), "key_send ctrl: " + code)
	# Alt 系の追加分: 話しかける (Option+H) とマップサイズ
	# (Option+5/7/9)。Alt+T は送信表ではなくトグル処理
	# (handle_key) が担うので空。
	var alt_expect := {
		"KeyH": "hi",
		"Digit5": "#ex-map size=40", "Numpad5": "#ex-map size=40",
		"Digit7": "#ex-map size=57",
		"Numpad7": "#ex-map size=57", "Digit9": "#ex-map size=81",
		"Numpad9": "#ex-map size=81",
	}
	for code in alt_expect:
		check(PhiKeys.key_send(code, false, false, true) == str(alt_expect[code]), "key_send alt: " + code)
	check(PhiKeys.key_send("KeyT", false, false, true) == "", "key_send alt KeyT is toggle, not send")
	# 超魔法データ: 全項目に処理できる step がある。
	var mm := PhiMasterMagic.parse(PhiMasterMagic.DEFAULT_XML)
	var menus: Array = mm.get("menus", [])
	check(not menus.is_empty(), "master magic menus exist")
	var step_kinds := ["send", "ok_dialog", "int_dialog", "string_dialog"]
	for menu in menus:
		for item in menu.get("items", []):
			if bool(item.get("separator", false)):
				continue
			var steps: Array = PhiMasterMagic.effective_steps(item.get("steps", []))
			check(not steps.is_empty(), "master magic steps: " + str(item.get("caption", "?")))
			for step in steps:
				check(step_kinds.has(str(step.get("kind", ""))), "master magic step kind: " + str(step.get("kind", "")))


func _visible_windows(node: Node, out: Array) -> void:
	for child in node.get_children():
		if child is Window and (child as Window).visible:
			out.append(child)
		_visible_windows(child, out)


func _hide_all_windows(node: Node) -> void:
	for child in node.get_children():
		if child is Window:
			(child as Window).hide()
		_hide_all_windows(child)


func _run() -> void:
	_static_checks()
	var main: Node = Main.new()
	root.add_child(main)
	await process_frame
	await process_frame
	var tab: Variant = main.call("_active_tab")
	check(tab != null, "active tab exists")
	# メニューの組み立て: metadata の集合が MENUS と一致する。
	var built := {}
	for popup in main.get("_menu_popups"):
		for i in popup.item_count:
			var meta: Variant = popup.get_item_metadata(i)
			if meta != null:
				built[str(meta)] = true
	for menu in PhiActions.MENUS:
		for item in menu["items"]:
			var name := str(item)
			if name != "-":
				check(built.has(name), "menu built: " + name)
	# 設定ファイルの退避 (切替系が保存までするので)。
	var config_path := str(main.get("_config_path"))
	var saved_config := ""
	if FileAccess.file_exists(config_path):
		saved_config = FileAccess.get_file_as_string(config_path)
	var config: Variant = main.get("_config")
	# 動的: 全アクションを発火させる (Exit は終了するので除く)。
	var names: Array = PhiActions.ACTIONS.keys()
	names.sort()
	for name in names:
		if name == "Exit":
			continue
		var kind := PhiActions.kind_of(name)
		var queue_before: int = tab.session._send_queue.size()
		var windows_before: Array = []
		_visible_windows(main, windows_before)
		var toggle_before: Variant = _toggle_state(name, main, config, tab)
		main.call("_do_action", name)
		await process_frame
		await process_frame
		var queue: Array = tab.session._send_queue
		match kind:
			"send":
				if name == "Call" or name == "Return":
					var wins: Array = []
					_visible_windows(main, wins)
					check(queue.size() > queue_before or wins.size() > windows_before.size(), "confirm or send: " + name)
				elif PhiActions.is_system_magic(name):
					check(queue.size() > queue_before and str(queue[queue_before]) == "unequip", "system magic sends unequip first: " + name)
				else:
					var expect: Array = PhiActions.send_text_for(name).split("\n")
					var ok := queue.size() >= queue_before + expect.size()
					if ok:
						for j in range(expect.size()):
							if str(queue[queue_before + j]) != str(expect[j]):
								ok = false
					check(ok, "send queued: " + name)
			"ask":
				var wins2: Array = []
				_visible_windows(main, wins2)
				check(wins2.size() > windows_before.size(), "ask dialog opens: " + name)
			"loud-toggle", "autosave-toggle", "delete-filter-toggle", "scroll-toggle", "disp-magic-toggle", "bgm-toggle", "se-toggle", "master-magic-toggle", "image-toggle":
				check(_toggle_state(name, main, config, tab) != toggle_before, "toggle flips: " + name)
			"priv-window", "shortcut-config", "sound-test", "chip-viewer", "chara-viewer", "unew-panel", "image-window", "say-all-tabs", "talk-add", "connect":
				var wins3: Array = []
				_visible_windows(main, wins3)
				check(wins3.size() > windows_before.size(), "window opens: " + name)
			_:
				check(true, "no crash: " + name)
		_hide_all_windows(main)
	# 切替系を元に戻す (設定ファイルは最後に復元する)。
	# End キー: 装備リストを抑えて unequip + 1 を送る。
	tab.session._send_queue.clear()
	var end_event := InputEventKey.new()
	end_event.physical_keycode = KEY_END
	end_event.pressed = true
	check(tab.handle_key(end_event), "End key handled")
	check(tab.session._send_queue == ["unequip", "1"], "End queues unequip + 1")
	check(tab.get("_suppress_lists") == 1, "End suppresses the equip list")
	tab.call("_on_event", {"type": "list", "active": true, "lines": ["[ 1] Sword "]})
	check(not tab.get("_list_active"), "suppressed list stays hidden")
	# P キー: Pay の ask を出す (当初の割り当て)。
	var pay_box := [""]
	tab.action_requested.connect(func(action_name: String) -> void: pay_box[0] = action_name)
	var p_event := InputEventKey.new()
	p_event.physical_keycode = KEY_P
	p_event.pressed = true
	check(tab.handle_key(p_event), "P key handled")
	check(pay_box[0] == "Pay", "P key requests Pay")
	# 設定ファイルを復元する。
	if not saved_config.is_empty():
		var f := FileAccess.open(config_path, FileAccess.WRITE)
		f.store_string(saved_config)
		f.close()
		config.load_file(config_path)
	print("stage47: ", _checks, " checks, ", _failures, " failures")
	quit(1 if _failures > 0 else 0)


func _toggle_state(name: String, main: Node, config: Variant, tab: Variant) -> Variant:
	match name:
		"Loud":
			return tab.is_loud()
		"LogAutoSave":
			return config.log_auto_save
		"LogDeleteFilter":
			return config.log_delete_filter
		"LogScrollStop":
			return config.scroll_stop
		"DispMagic":
			return config.disp_magic
		"PlayBGM":
			return config.play_bgm
		"PlaySE":
			return config.sound_play
		"MasterMagicAlways":
			return config.master_magic_always
		"LogImage":
			return config.log_image_disp
	return null
