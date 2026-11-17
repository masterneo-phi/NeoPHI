extends SceneTree
## 第67段: (1) スクロール中の壁紙マスクを、セル・キャラの直後
## (ラベル・吹き出し・演出より奥) で掛けるよう描画順を変更
## (マスク自体の幾何は第65段のテストで担保)。(2) 初回起動時の
## 未接続の空タブが、キャラ接続や新規作成の後も残り続ける
## 問題: 未使用の空タブがあれば最初の接続で使い回す。

const Main := preload("res://scripts/main.gd")

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
	var main: Node = Main.new()
	var iso := ProjectSettings.globalize_path("user://stage67_tabs.ini")
	OS.execute("rm", ["-f", iso])
	main.set("_tab_session_path", "user://stage67_tabs.ini")
	root.add_child(main)
	await process_frame
	await process_frame
	var tabs: Array = main.get("_tabs")
	check(tabs.size() == 1, "one startup tab")
	var first: Variant = tabs[0]
	check(str(first.get("host")).is_empty(), "startup tab is unconnected")
	check(main.call("_take_pristine_tab") == first, "pristine tab found")

	# 最初のキャラ接続は空タブを使い回す (タブは増えない)
	var used: Variant = main.call("_connect_character", "example.com", 20019, "CLTEST1", "01_KURO")
	check(used == first, "first connect reuses the empty tab")
	check((main.get("_tabs") as Array).size() == 1, "still one tab after first connect")
	check(str(first.get("host")) == "example.com", "tab bound to host")
	check(str(first.get("session").char_id) == "CLTEST1", "tab bound to char id")
	check(main.call("_take_pristine_tab") == null, "no pristine tab remains")

	# 別のキャラは新しいタブになる
	var second: Variant = main.call("_connect_character", "example.com", 20019, "CLTEST2", "02_ENIGMA")
	check(second != first, "second character gets its own tab")
	check((main.get("_tabs") as Array).size() == 2, "two tabs after second connect")

	# 同じキャラの再接続はタブを増やさない
	var again: Variant = main.call("_connect_character", "example.com", 20019, "CLTEST1", "01_KURO")
	check(again == first, "reconnect finds the same tab")
	check((main.get("_tabs") as Array).size() == 2, "still two tabs after reconnect")

	print("test_stage67: ", _checks, " checks, ", _failures, " failures")
	quit(1 if _failures > 0 else 0)
