extends SceneTree
## 第46段: リストの見出しが中身と違う問題。
## 装備を外すリストが「魔法リスト」と出た (実機スクショ)。
## 開く時点では直前のコマンド (cast) からしか決められないが、
## サーバはリストの後に「〜を選択して下さい」の文を送るので、
## それが届いたら見出しを付け直す。

var _checks := 0
var _failures := 0


func check(cond: bool, label: String) -> void:
	_checks += 1
	if not cond:
		_failures += 1
		print("FAIL: ", label)


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	# プロンプト文からの種類名 (静的関数)
	check(PhiCharacter.list_title_for_command("", "DM > 外す装備を選択して下さい. ") == "装備リスト", "prompt: unequip")
	check(PhiCharacter.list_title_for_command("", "魔法を選択するか呪文を入力して下さい") == "魔法リスト", "prompt: magic")
	check(PhiCharacter.list_title_for_command("", "拾うアイテムを選択して下さい") == "アイテムリスト", "prompt: item")
	# 魔法でも中身が持ち物のリストになるもの (サーバの実際の文言)
	check(PhiCharacter.list_title_for_command("", "DM > 壊すアイテムを選択して下さい. ") == "アイテムリスト", "prompt: Destroy selects an item")
	check(PhiCharacter.list_title_for_command("", "DM > 材料にするアイテムを選択して下さい. ") == "アイテムリスト", "prompt: Create selects an item")
	check(PhiCharacter.list_title_for_command("", "DM > 鑑定するアイテムを選択して下さい. ") == "アイテムリスト", "prompt: Detect selects an item")
	check(PhiCharacter.list_title_for_command("", "DM > 封印する魔法を選択して下さい. ") == "魔法リスト", "prompt: ChargeSpell selects a spell")
	check(PhiCharacter.list_title_for_command("", "DM > 封印する宝石を選択して下さい. ") == "アイテムリスト", "prompt: ChargeSpell first selects a jewel")
	check(PhiCharacter.list_title_for_command("", "DM > 忘れる魔法を選択して下さい. ") == "魔法リスト", "prompt: Forget selects a spell")
	check(PhiCharacter.list_title_for_command("", "DM > 複製するアイテムを選択して下さい. ") == "アイテムリスト", "prompt: Duplicate selects an item")
	check(PhiCharacter.list_title_for_command("", "DM > 分析する魔法を選択して下さい. ") == "魔法リスト", "prompt: Analyze selects a spell")
	check(PhiCharacter.list_title_for_command("cast") == "魔法リスト", "command: cast unchanged")

	var ps := load("res://main.tscn") as PackedScene
	var main: Node = ps.instantiate()
	root.add_child(main)
	await create_timer(1.0).timeout
	var tab: PhiCharacter = main.call("_create_tab")
	main.call("_activate_tab", tab)
	var header: Label = tab.get("_list_header")

	# cast の後で届いた装備リスト: 最初は魔法リスト、選択の文で
	# 装備リストに直る
	tab.send_text("cast")
	tab.call("_on_event", {"type": "list", "active": true, "lines": ["[ 1] High Soldier's Crest    Wp : 4 [Acr]"]})
	check(header.text == "魔法リスト", "initial title from command (got %s)" % header.text)
	tab.call("_on_event", {"type": "message", "channel": "log", "text": "/*color=gray*/DM > 外す装備を選択して下さい. "})
	check(header.text == "装備リスト", "retitled by the prompt (got %s)" % header.text)

	# 選択の文でない装備の行では付け直さない
	tab.call("_on_event", {"type": "list", "active": true, "lines": ["[ 1] High Soldier's Crest    Wp : 4 [Acr]"]})
	check(header.text == "魔法リスト", "reopened title from command")
	tab.call("_on_event", {"type": "message", "channel": "log", "text": "/*color=gray*/DM > KURO は High Soldier's Crest を装備した. "})
	check(header.text == "魔法リスト", "equip message does not retitle (got %s)" % header.text)

	# リストが閉じていれば付け直さない
	tab.call("_on_event", {"type": "list", "active": false})
	tab.call("_on_event", {"type": "message", "channel": "log", "text": "/*color=gray*/DM > 外す装備を選択して下さい. "})
	check(header.text == "魔法リスト", "no retitle while closed (got %s)" % header.text)

	main.queue_free()
	print("stage46: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)
