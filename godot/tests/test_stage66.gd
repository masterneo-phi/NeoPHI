extends SceneTree
## 第66段: 5x5 (クラシック地図) の実サーバ不具合 2 件。
## (1) 分身: 7x7 から 5x5 へ切り替えると、前のモードのキャラ行
##     (自分) が残って (3,3) に表示され、さらに #name でグラ名が
##     届いて自分の名前がグラ名に化け、合成した自分が (2,3) に
##     グラ名ラベルで出る。対策: 地図の大きさが変わったら前
##     フレームのキャラ行を捨てる / グラ名と一致する名前は
##     プレイヤー名として取り込まない / 自分行の判定にグラ名
##     行も含める。
## (2) 9x9 へ戻れない: 9x9 未対応サーバ (rel5g 系は size=81 を
##     無視する) では、明示的に 9x9 を要求した時も応答が無い
##     ので 7x7 へ落とし直す必要がある。対策: 送った
##     #ex-map size= をセッションが覚え、落とし直しの判断に使う。

const Main := preload("res://scripts/main.gd")

var _checks := 0
var _failures := 0


func check(cond: bool, label: String) -> void:
	_checks += 1
	if not cond:
		_failures += 1
		print("FAIL: ", label)


func _pad_bytes(text: String, width: int) -> PackedByteArray:
	var b := Cp932.encode(text)
	while b.size() < width:
		b.append(0x20)
	return b


func _m57_m() -> PackedByteArray:
	var b := PackedByteArray()
	b.append_array("#m57 M S 00000000:".to_ascii_buffer())
	for i in 49:
		b.append(0x2E)
		b.append(0x80)
	b.append(0x20)
	return b


func _m57_o(id: int, x: int, y: int, name: String, gra: String) -> PackedByteArray:
	var b := PackedByteArray()
	b.append_array(("#m57 O C%04x:%d %d %s " % [id, x, y, "B"]).to_ascii_buffer())
	b.append_array(_pad_bytes(name, 31))
	b.append_array(" 40 ".to_ascii_buffer())
	b.append_array(_pad_bytes(gra, 15))
	b.append_array(" # 40 ".to_ascii_buffer())
	return b


func _classic_m() -> PackedByteArray:
	var b := PackedByteArray()
	b.append_array("#map M W 00000000:".to_ascii_buffer())
	for i in 25:
		b.append(0x2E)
		b.append(0x2E)
	for i in 50:
		b.append(0x20)
	return b


func _classic_c(index: int, x: int, y: int, name: String, gra: String) -> PackedByteArray:
	var b := PackedByteArray()
	b.append_array(("#map C%02d:%d %d %s " % [index, x, y, "B"]).to_ascii_buffer())
	b.append_array(_pad_bytes(name, 31))
	b.append_array(" 40 ".to_ascii_buffer())
	b.append_array(_pad_bytes(gra, 15))
	b.append_array(" # 40 ".to_ascii_buffer())
	return b


func _feed_all(parser: PhiParser, lines: Array) -> Array:
	var events: Array = []
	for line in lines:
		events.append_array(parser.feed(line))
	return events


func _map_events(events: Array) -> Array:
	var out: Array = []
	for e in events:
		if str(e.get("type", "")) == "map":
			out.append(e)
	return out


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	# --- (1a) モード切替で前フレームのキャラ行が残らない ---
	var parser := PhiParser.new()
	var ev57 := _map_events(_feed_all(parser, [
		_m57_m(), _m57_o(1, 3, 3, "KURO", "elb_cat"), "#m57 .".to_ascii_buffer()]))
	check(ev57.size() == 1 and int(ev57[0]["size"]) == 7, "m57 frame parsed")
	check((ev57[0]["chars"] as Array).size() == 1, "m57 self row present")
	# 5x5 へ切替: クラシックフレームにキャラ行が無ければ残らない
	var ev5 := _map_events(_feed_all(parser, [
		_classic_m(), "#map .".to_ascii_buffer()]))
	check(ev5.size() == 1 and int(ev5[0]["size"]) == 5, "classic frame parsed")
	check((ev5[0]["chars"] as Array).size() == 0, "stale chars cleared on size change")
	# 同じモードの間は、行が来ないフレームでもキャラを引き継ぐ
	var ev5b := _map_events(_feed_all(parser, [
		_classic_c(0, 0, 0, "OTHER", "t_man"), _classic_m(), "#map .".to_ascii_buffer()]))
	check((ev5b[0]["chars"] as Array).size() == 1, "classic char row parsed")
	var ev5c := _map_events(_feed_all(parser, [
		_classic_m(), "#map .".to_ascii_buffer()]))
	check((ev5c[0]["chars"] as Array).size() == 1, "chars persist within classic mode")
	# 7x7 へ戻す時も残らない
	var ev57b := _map_events(_feed_all(parser, [
		_m57_m(), "#m57 .".to_ascii_buffer()]))
	check((ev57b[0]["chars"] as Array).size() == 0, "stale chars cleared returning to m57")

	# --- (2a) セッションが要求した大きさを覚える ---
	var session := PhiSession.new()
	session.send_text("#ex-map size=81")
	check(session.map_size == 81, "session tracks size=81 request")
	session.send_line("#ex-map size=40")
	check(session.map_size == 40, "session tracks size=40 request")
	session.send_text("hello")
	check(session.map_size == 40, "plain text does not change tracked size")

	# --- Main を立てる (タブ復元は隔離) ---
	var main: Node = Main.new()
	var iso := ProjectSettings.globalize_path("user://stage66_tabs.ini")
	OS.execute("rm", ["-f", iso])
	main.set("_tab_session_path", "user://stage66_tabs.ini")
	root.add_child(main)
	await process_frame
	await process_frame
	var tab: Variant = main.call("_active_tab")

	# --- (1b) グラ名はプレイヤー名にならない ---
	tab.call("_on_event", {"type": "status", "name": "KURO"})
	check(str(tab.call("player_name")) == "KURO", "player name from status")
	tab.set("_self_gra", "elb_cat")
	tab.call("_on_event", {"type": "notice", "name": "elb_cat"})
	check(str(tab.call("player_name")) == "KURO", "#name gra does not poison player name")
	tab.call("_on_event", {"type": "status", "name": "elb_cat"})
	check(str(tab.call("player_name")) == "KURO", "status gra does not poison player name")
	tab.call("_on_event", {"type": "notice", "name": "KURO"})
	check(str(tab.call("player_name")) == "KURO", "real name still accepted")

	# --- (1c) 自分行 (グラ名入り) は自分として扱い、分身しない ---
	var cells5: Array = []
	for i in 25:
		cells5.append({"chip": 2, "attr": 0})
	var ev_fix: Dictionary = {"type": "map", "size": 5, "cells": cells5,
		"chars": [{"id": 0, "x": 2, "y": 3, "dir": "B", "name": "elb_cat",
			"gra": "elb_cat", "status": 0x40, "gigant": "#", "layer": 0, "default": 0x40}]}
	tab.call("_fixup_classic_self", ev_fix)
	check((ev_fix["chars"] as Array).size() == 1, "gra-named self row not duplicated")
	check(str(ev_fix["chars"][0]["name"]) == "KURO", "gra-named self row renamed to player name")
	var ev_syn: Dictionary = {"type": "map", "size": 5, "cells": cells5, "chars": []}
	tab.call("_fixup_classic_self", ev_syn)
	check((ev_syn["chars"] as Array).size() == 1, "self synthesized when no row")
	check(str(ev_syn["chars"][0]["name"]) == "KURO", "synthesized self uses player name")

	# --- (2b) 明示的に 9x9 を要求したら、未対応サーバでは 7x7 へ ---
	var tsession: Variant = tab.get("session")
	tsession.map_size = 57
	tab.call("do_send_action", "M9x9")
	check(int(tsession.map_size) == 81, "M9x9 request tracked in session")
	var ev_classic: Dictionary = {"type": "map", "size": 5, "cells": cells5, "chars": [], "dir": 4}
	tab.call("_on_event", ev_classic)
	check(int(tsession.map_size) == 57, "fallback re-requests 57 on non-9x9 frame")

	# --- (3) 洪水時はログの切り詰めを後回しにせず即行う ---
	for i in 5:
		tab.call("log_message", "log", "flood line %d" % i)
	var hist := (tab.get("_log_lines") as Array).size()
	tab.call("_flush_log_batch")
	check(int(tab.get("_log_view_lines")) == hist, "log view has rendered lines")
	var pend: Array[PackedByteArray] = []
	for i in 250:
		pend.append("dummy".to_ascii_buffer())
	tsession.set("_pending_lines", pend)
	tab.set("_log_view_lines", 9999)
	tab.call("_rebuild_log_view")
	check(bool(tab.get("_img_rebuild_queued")) == true, "rebuild deferred while flooding")
	check(int(tab.get("_log_view_lines")) == 9999, "deferred rebuild did not run")
	tab.call("_rebuild_log_view", true)
	check(int(tab.get("_log_view_lines")) == hist, "forced rebuild trims during flood")
	check(bool(tab.get("_img_rebuild_queued")) == false, "forced rebuild clears queue flag")
	var empty_pend: Array[PackedByteArray] = []
	tsession.set("_pending_lines", empty_pend)

	print("test_stage66: ", _checks, " checks, ", _failures, " failures")
	quit(1 if _failures > 0 else 0)
