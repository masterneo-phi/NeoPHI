extends SceneTree
## 第45段: 魔法表示 (#ex-disp-magic) の受信側パイプライン確認。
## Philly 形式の行を、パーサ→イベント→MapView の表示登録まで
## 通す。サーバが送ってくれば表示できる状態であることを固定する。

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
	# Philly 形式 (16進、効果文字+引数) の解析
	var data: Variant = PhiDispMagic.parse("#ex-disp-magic 1 0 a 4 4 C0 4 3 H0")
	check(data != null, "parse canonical line")
	if data != null:
		check(int(data["start"]["x"]) == 4 and int(data["start"]["y"]) == 4, "start cell")
		check(str(data["start"]["effect"]) == "C", "start effect C")
		check(int(data["end"]["x"]) == 4 and int(data["end"]["y"]) == 3, "end cell")
		check(str(data["end"]["effect"]) == "H", "end effect H")
		# 段階ごとの描画セル: 0=発射、1/2=命中
		var p0 := PhiDispMagic.phase_cells(data, 0)
		check(p0.size() == 1 and int(p0[0][1]) == PhiDispMagic.CELL_CAST, "phase 0 is cast cell")
		var p1 := PhiDispMagic.phase_cells(data, 1)
		check(p1.size() == 1 and int(p1[0][1]) == PhiDispMagic.CELL_PASS, "phase 1 is hit cell")
		var p2 := PhiDispMagic.phase_cells(data, 2)
		check(p2.size() == 1 and int(p2[0][1]) == PhiDispMagic.CELL_PASS, "phase 2 is hit cell")
	# 効果と引数の間に空白があっても読める
	check(PhiDispMagic.parse("#ex-disp-magic 1 0 a 4 4 C 0 4 3 H 0") != null, "parse spaced effects")
	# 読めない行は null
	check(PhiDispMagic.parse("#ex-disp-magic zz") == null, "parse garbage is null")
	check(PhiDispMagic.parse("#ex-disp-magic") == null, "parse bare header is null")

	# パーサがイベントにする
	var parser := PhiParser.new()
	var events := parser.feed(Cp932.encode("#ex-disp-magic 1 0 a 4 4 C0 4 3 H0"))
	check(events.size() == 1 and str(events[0].get("type", "")) == "dispMagic", "parser emits dispMagic event")

	# MapView に登録される
	var ps := load("res://main.tscn") as PackedScene
	var main: Node = ps.instantiate()
	root.add_child(main)
	await create_timer(1.0).timeout
	var tab: PhiCharacter = main.call("_create_tab")
	main.call("_activate_tab", tab)
	tab.map_view.spawn_disp_magic(data)
	check(tab.map_view.debug_disp_magic_count() == 1, "map view registers the effect")
	main.queue_free()

	print("stage45: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)
