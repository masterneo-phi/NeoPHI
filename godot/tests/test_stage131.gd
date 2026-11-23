extends SceneTree
## 第131段: Metro 表記の台詞行 (DM > 名前「台詞」) の吹き出し。
## (1) 抽出 (PhiBubbles.bubble_from_dialogue_line): 名前の直後に
##     「が付く行だけを台詞行とし、刻文 (『…』や地の文の引用) や
##     通常の DM 文は対象にしない。
## (2) 吹き出しの位置: 名前が地図に見えるキャラと一致すれば
##     そのキャラの基準点、一致しなければ (人形オブジェ) 自キャラ
##     が向いているマスの基準点を使う。
## (3) 向き → 隣接マスのオフセット (MapView.facing_offset) と、
##     set_map が作る正面の基準点。
## (4) 地図に居ない話し手 (人形オブジェ) の 名前 > 本文 の行も、
##     正面のマスの基準点に吹き出しを付ける。話し手が "DM" の行と
##     括弧付きの話し手は対象にしない。

var _checks := 0
var _failures := 0


func check(cond: bool, label: String) -> void:
	_checks += 1
	if not cond:
		_failures += 1
		print("FAIL: ", label)


func check_eq(a: Variant, b: Variant, label: String) -> void:
	_checks += 1
	if a != b:
		_failures += 1
		print("FAIL: ", label, " (got ", a, ", want ", b, ")")


func _initialize() -> void:
	_run.call_deferred()


func _test_extract() -> void:
	var hit: Variant = PhiBubbles.bubble_from_dialogue_line(
		"DM > 案内人「ダンジョン探索で一番大切なことはわかりますか？」")
	check(hit != null, "台詞行が抜ける")
	if hit != null:
		check_eq(str(hit[0]), "案内人", "話し手は案内人")
		check_eq(str(hit[1]), "ダンジョン探索で一番大切なことはわかりますか？", "台詞が抜ける")
	hit = PhiBubbles.bubble_from_dialogue_line("DM > Village Elder「よく来たな」")
	check(hit != null and str(hit[0]) == "Village Elder", "空白を含む名前も話し手になる")
	hit = PhiBubbles.bubble_from_dialogue_line("DM > 案内人「彼は「行け」と言った」")
	check(hit != null and str(hit[1]) == "彼は「行け」と言った", "台詞の中の「」は最後の」まで含める")
	# 対象外の行
	check(PhiBubbles.bubble_from_dialogue_line("DM > 「台詞」") == null,
		"名前の無い「」は台詞行ではない")
	check(PhiBubbles.bubble_from_dialogue_line("DM > 石碑には、こう刻まれている。『眠れる石は眠っている』") == null,
		"刻文 (『』) は対象外")
	check(PhiBubbles.bubble_from_dialogue_line("DM > 石碑には、こう刻まれている。「扉は開かない」") == null,
		"地の文の後の引用は対象外")
	check(PhiBubbles.bubble_from_dialogue_line("DM > 扉が開いた。") == null,
		"通常の DM 文は対象外")
	check(PhiBubbles.bubble_from_dialogue_line("DM > 案内人 「台詞」") == null,
		"名前と「の間に空白がある行は対象外")
	check(PhiBubbles.bubble_from_dialogue_line("DM > 案内人「台詞") == null,
		"閉じ」の無い行は対象外")
	check(PhiBubbles.bubble_from_dialogue_line("DM > 案内人「」") == null,
		"空の台詞は対象外")
	check(PhiBubbles.bubble_from_dialogue_line("案内人 > 台詞") == null,
		"DM > で始まらない行は対象外")


func _test_facing_offset() -> void:
	check_eq(MapView.facing_offset("B"), Vector2i(0, -1), "B は北")
	check_eq(MapView.facing_offset("R"), Vector2i(1, 0), "R は東")
	check_eq(MapView.facing_offset("F"), Vector2i(0, 1), "F は南")
	check_eq(MapView.facing_offset("L"), Vector2i(-1, 0), "L は西")
	check_eq(MapView.facing_offset("?"), Vector2i(0, 1), "知らない値は南に倒す")


func _flat_cells(dim: int) -> Array:
	var cells: Array = []
	for i in range(dim * dim):
		cells.append({"chip": 0x3A, "attr": 0x80})
	return cells


func _char(name: String, x: int, y: int, dir: String) -> Dictionary:
	return {"name": name, "x": x, "y": y, "dir": dir, "gra": "",
		"status": "", "gigant": "", "layer": 12, "default": 0}


func _head_anchor(cx: int, cy: int) -> Vector2:
	var head_top := (MapView.CHIP_SIZE - MapView.CHARA_H) / 2 \
		- MapView.CHARA_Y_ABOVE_FLOOR + MapView.MAP_TOP
	return Vector2(cx * MapView.CHIP_SIZE + MapView.CHIP_SIZE / 2,
		cy * MapView.CHIP_SIZE + head_top)


func _test_map_bubbles() -> void:
	var assets := GameAssets.new()
	assets.setup([], [], [], "Mine")
	var mv := MapView.new()
	root.add_child(mv)
	mv.size = Vector2(224, 240)
	mv.self_name = "テスト"
	mv.player_name = "テスト"
	var cells := _flat_cells(7)
	# 自キャラは中心 (3,3) で北向き、村人は (3,1)。
	var ev := {"size": 7, "cells": cells, "chars": [
		_char("テスト", 3, 3, "B"), _char("村人", 3, 1, "F")]}
	mv.set_map(ev, assets, "")
	check_eq(mv.debug_faced_anchor(), _head_anchor(3, 2), "北向きの正面は (3,2)")
	check(mv.debug_anchors().has("村人"), "村人の基準点がある")
	# 地図に居るキャラの台詞は、そのキャラの吹き出しになる。
	mv.show_log_bubble("", "DM > 村人「こんにちは」")
	var bubbles: Dictionary = mv.get("_bubbles")
	check(bubbles.has("村人"), "村人の台詞が吹き出しになる")
	if bubbles.has("村人"):
		check_eq(str(bubbles["村人"][0].get("text", "")), "こんにちは", "村人の台詞の本文")
	check(mv.debug_dialogue_anchors().is_empty(), "キャラの台詞では正面の基準点を使わない")
	# 地図に居ない話し手 (人形オブジェ) は正面のマスに付く。
	mv.show_log_bubble("", "DM > 案内人「ダンジョン探索で一番大切なことはわかりますか？」")
	bubbles = mv.get("_bubbles")
	check(bubbles.has("案内人"), "案内人の台詞が吹き出しになる")
	check_eq(mv.debug_dialogue_anchors().get("案内人"), _head_anchor(3, 2),
		"案内人の基準点は正面のマス")
	check_eq(mv._bubble_position("案内人"), _head_anchor(3, 2), "吹き出し位置は正面のマス")
	check_eq(mv._bubble_position("村人"), mv.debug_anchors().get("村人"), "吹き出し位置は村人の基準点")
	# 喋らないものはログのまま (吹き出しにしない)。
	var before := bubbles.keys()
	mv.show_log_bubble("", "DM > 石碑には、こう刻まれている。『眠れる石は、その身を削る』")
	mv.show_log_bubble("", "DM > 扉が開いた。")
	check_eq(mv.get("_bubbles").keys(), before, "刻文と地の文は吹き出しにならない")
	# 南向きに変えると正面は (3,4) になり、前の基準点は消える。
	var ev2 := {"size": 7, "cells": cells, "chars": [
		_char("テスト", 3, 3, "F"), _char("村人", 3, 1, "F")]}
	mv.set_map(ev2, assets, "")
	check_eq(mv.debug_faced_anchor(), _head_anchor(3, 4), "南向きの正面は (3,4)")
	check(mv.debug_dialogue_anchors().is_empty(), "地図の差し替えで台詞の基準点は消える")
	# 自キャラが居ない地図では、正面が分からないので付けない。
	var ev3 := {"size": 7, "cells": cells, "chars": []}
	mv.set_map(ev3, assets, "")
	check(mv.debug_faced_anchor() == null, "自キャラ不在では正面は不明")
	mv.show_log_bubble("", "DM > 受付「ようこそ」")
	check(not mv.get("_bubbles").has("受付"), "正面が不明なら吹き出しを付けない")
	mv.free()


func _test_object_speech_extract() -> void:
	var hit: Variant = PhiBubbles.bubble_from_object_speech_line(
		"緑川 > いらっしゃいませ。Murder Club へようこそ")
	check(hit != null, "オブジェの発言が抜ける")
	if hit != null:
		check_eq(str(hit[0]), "緑川", "話し手は緑川")
		check_eq(str(hit[1]), "いらっしゃいませ。Murder Club へようこそ", "本文が抜ける")
	hit = PhiBubbles.bubble_from_object_speech_line("Master Sherlock Holmes > 本文です")
	check(hit != null and str(hit[0]) == "Master Sherlock Holmes", "空白を含む名前も話し手になる")
	hit = PhiBubbles.bubble_from_object_speech_line("緑川 > あれ > それ")
	check(hit != null and str(hit[1]) == "あれ > それ", "本文の中の > は最初の区切りだけ使う")
	# 地図に見えるキャラの名前が要る従来の抽出では抜けない (隙間)。
	check(PhiBubbles.bubble_from_log_line("緑川 > 台詞", ["村人", "テスト"]) == null,
		"従来の抽出は地図に居ない話し手を抜けない")
	# 対象外の行
	check(PhiBubbles.bubble_from_object_speech_line("DM > 扉が開いた。") == null,
		"話し手が DM の行は対象外")
	check(PhiBubbles.bubble_from_object_speech_line("DM > 案内人「台詞」") == null,
		"台詞行 (DM > 名前「」) は横取りしない")
	check(PhiBubbles.bubble_from_object_speech_line("(緑川) > 本文") == null,
		"括弧付きの話し手は対象外")
	check(PhiBubbles.bubble_from_object_speech_line("{緑川} > 本文") == null,
		"波括弧付きの話し手は対象外")
	check(PhiBubbles.bubble_from_object_speech_line("\"緑川\" > 本文") == null,
		"引用符付きの話し手は対象外")
	check(PhiBubbles.bubble_from_object_speech_line("石碑には、こう刻まれている。 > 続きの文") == null,
		"名前に文の区切りが混ざる行は対象外")
	check(PhiBubbles.bubble_from_object_speech_line("緑川 >") == null,
		"空の本文は対象外")
	check(PhiBubbles.bubble_from_object_speech_line("緑川") == null,
		"区切りの無い行は対象外")


func _test_object_speech_map() -> void:
	var assets := GameAssets.new()
	assets.setup([], [], [], "Mine")
	var mv := MapView.new()
	root.add_child(mv)
	mv.size = Vector2(224, 240)
	mv.self_name = "テスト"
	mv.player_name = "テスト"
	var cells := _flat_cells(7)
	# 自キャラは中心 (3,3) で北向き、村人は (3,1)。
	var ev := {"size": 7, "cells": cells, "chars": [
		_char("テスト", 3, 3, "B"), _char("村人", 3, 1, "F")]}
	mv.set_map(ev, assets, "")
	# (a) 地図に居ない話し手 (人形オブジェ) は正面のマスに付く。
	mv.show_log_bubble("", "緑川 > いらっしゃいませ。Murder Club へようこそ")
	var bubbles: Dictionary = mv.get("_bubbles")
	check(bubbles.has("緑川"), "オブジェの発言が吹き出しになる")
	if bubbles.has("緑川"):
		check_eq(str(bubbles["緑川"][0].get("text", "")),
			"いらっしゃいませ。Murder Club へようこそ", "オブジェの発言の本文")
	check_eq(mv.debug_dialogue_anchors().get("緑川"), _head_anchor(3, 2),
		"オブジェの基準点は正面のマス")
	check_eq(mv._bubble_position("緑川"), _head_anchor(3, 2), "吹き出し位置は正面のマス")
	# (b) DM の文は吹き出しにならない。
	mv.show_log_bubble("", "DM > 扉が開いた。")
	mv.show_log_bubble("", "DM > 何かの知らせです")
	check(not mv.get("_bubbles").has("DM"), "DM の文は吹き出しにならない")
	# 括弧付きの話し手も、地図に居なければ付けない。
	mv.show_log_bubble("", "(支配人) > ようこそ")
	check(not mv.get("_bubbles").has("支配人"), "括弧付きの話し手は付けない")
	# (c) 地図に居るキャラの発言は従来どおり、そのキャラの頭上。
	mv.show_log_bubble("", "村人 > こんにちは")
	bubbles = mv.get("_bubbles")
	check(bubbles.has("村人"), "村人の発言が吹き出しになる")
	check_eq(mv._bubble_position("村人"), mv.debug_anchors().get("村人"),
		"村人の吹き出し位置は村人の基準点")
	check(not mv.debug_dialogue_anchors().has("村人"),
		"キャラの発言では正面の基準点を使わない")
	# 自キャラが居ない地図では、正面が分からないので付けない。
	var ev2 := {"size": 7, "cells": cells, "chars": []}
	mv.set_map(ev2, assets, "")
	mv.show_log_bubble("", "受付 > ようこそ")
	check(not mv.get("_bubbles").has("受付"), "正面が不明ならオブジェの発言も付けない")
	mv.free()


func _run() -> void:
	_test_extract()
	_test_facing_offset()
	_test_map_bubbles()
	_test_object_speech_extract()
	_test_object_speech_map()
	print("test_stage131: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)
