extends SceneTree
## 第73段: 洪水時は行ごとの演出照合を止める。浮き数字・戦闘
## 演出・吹き出し・効果音・画像参照集めは 1 行ごとに全文を
## 何度も走査するので、大量行では受信を滞らせる。ログ自体は
## 通常どおり残る。あわせて PhiTags.plain_text にタグ無し
## 行の高速路を入れた。

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
	# --- plain_text の高速路 (結果は従来と同じ) ---
	check(PhiTags.plain_text("タグなしの行です") == "タグなしの行です",
		"plain_text identity for tagless line")
	check(PhiTags.plain_text("/*color=red*/赤/*.*/") == "赤",
		"plain_text still strips tags")
	check(PhiTags.plain_text("はーと") == "♥", "plain_text still converts heart")

	var main: Node = Main.new()
	var iso := ProjectSettings.globalize_path("user://stage73_tabs.ini")
	OS.execute("rm", ["-f", iso])
	main.set("_tab_session_path", "user://stage73_tabs.ini")
	var isoc := ProjectSettings.globalize_path("user://stage73_cfg.ini")
	OS.execute("rm", ["-f", isoc])
	main.set("_config_path", "user://stage73_cfg.ini")
	root.add_child(main)
	await process_frame
	await process_frame
	var tab: Variant = main.call("_active_tab")
	var tsession: Variant = tab.get("session")

	# --- 通常時: 画像参照が集まる ---
	var refs0 := (tab.get("_image_refs") as Array).size()
	tab.call("_on_event", {"type": "message", "channel": "log",
		"text": "see http://example.com/a.png", "markup": false})
	check((tab.get("_image_refs") as Array).size() == refs0 + 1,
		"image ref collected normally")

	# --- 洪水時: 演出照合は止まるが、ログには残る ---
	var pending: Array[PackedByteArray] = []
	for i in 400:
		pending.append("dummy".to_ascii_buffer())
	tsession.set("_pending_lines", pending)
	check(bool(tab.call("_flooding")) == true, "flooding detected")
	var rec0 := (tab.get("_log_lines") as Array).size()
	tab.call("_on_event", {"type": "message", "channel": "log",
		"text": "see http://example.com/b.png", "markup": false})
	check((tab.get("_image_refs") as Array).size() == refs0 + 1,
		"image ref NOT collected while flooding")
	check((tab.get("_log_lines") as Array).size() == rec0 + 1,
		"line still logged while flooding")
	var empty_pending: Array[PackedByteArray] = []
	tsession.set("_pending_lines", empty_pending)

	# --- 洪水が終わればまた集まる ---
	tab.call("_on_event", {"type": "message", "channel": "log",
		"text": "see http://example.com/c.png", "markup": false})
	check((tab.get("_image_refs") as Array).size() == refs0 + 2,
		"image ref collected after flood")

	print("test_stage73: ", _checks, " checks, ", _failures, " failures")
	quit(1 if _failures > 0 else 0)
