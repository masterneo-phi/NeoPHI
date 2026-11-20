extends SceneTree
## 第120段: 滑らかスクロール中に中央へ留めるのは自キャラの
## 行だけ。同じマスに乗った家具などのオブジェ行 (種別 B)
## まで留めてしまい、家具が一瞬動いて見えた不具合の回帰
## テスト (_mark_self の印付け)。

var _checks := 0
var _failures := 0


func check(cond: bool, label: String) -> void:
	_checks += 1
	if not cond:
		_failures += 1
		print("FAIL: ", label)


func _ch(x: int, y: int, layer: int, name: String) -> Dictionary:
	return {"id": 1, "x": x, "y": y, "layer": layer, "name": name, "gra": "g"}


func _initialize() -> void:
	var v := MapView.new()
	v.self_name = "01_Tester"
	# 中央マスに自キャラ (種別 C=12) と家具 (種別 B=11) が重なる
	var me := _ch(3, 3, 12, "01_Tester")
	var table := _ch(3, 3, 11, "")
	var npc := _ch(2, 3, 12, "Villager")
	var ev := {"size": 7, "chars": [me, table, npc]}
	v._mark_self(ev, 7)
	check(bool(me.get("__self", false)), "self entry marked")
	check(not bool(table.get("__self", false)), "furniture on the same cell is not marked")
	check(not bool(npc.get("__self", false)), "npc elsewhere is not marked")
	# 家具だけが中央にある (自キャラ行が無い) 場合は誰も留めない
	var table2 := _ch(3, 3, 11, "")
	var ev2 := {"size": 7, "chars": [table2]}
	v._mark_self(ev2, 7)
	check(not bool(table2.get("__self", false)), "furniture alone at center is not marked")
	# 名前がまだ分からない時は中央のキャラ行 (種別 C) で代用する
	v.self_name = ""
	var me2 := _ch(3, 3, 12, "01_Tester")
	var table3 := _ch(3, 3, 11, "")
	var ev3 := {"size": 7, "chars": [table3, me2]}
	v._mark_self(ev3, 7)
	check(bool(me2.get("__self", false)), "fallback marks the center character")
	check(not bool(table3.get("__self", false)), "fallback does not mark furniture")
	print("stage120: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)
