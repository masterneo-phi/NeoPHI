extends SceneTree
## 第60段: 9x9 の Eagle eye は 20x20 (ユーザーの仕様変更)。
## パーサの上限を 15 から 20 へ広げ、20x20 の #ex-eagleeye を
## 全マス取り込めること、従来の 15x15 がそのままなこと、
## Eagle ビューが 20 マスで盤面を作ることを確かめる。

var _checks := 0
var _failures := 0


func check(cond: bool, label: String) -> void:
	_checks += 1
	if not cond:
		_failures += 1
		print("FAIL: ", label)


func _eagle_block(size_field: int, count: int) -> Array[PackedByteArray]:
	var lines: Array[PackedByteArray] = []
	lines.append("#ex-eagleeye start".to_ascii_buffer())
	for y in range(count):
		var row := "#ex-eagleeye M %2.2d %2.2d " % [size_field, y]
		var bytes := row.to_ascii_buffer()
		for x in range(count):
			bytes.append(30 + x)
			bytes.append(0x40)
		bytes.append(0x20)
		lines.append(bytes)
	lines.append("#ex-eagleeye end".to_ascii_buffer())
	return lines


func _feed_all(parser: PhiParser, lines: Array[PackedByteArray]) -> Array:
	var events: Array = []
	for l in lines:
		events.append_array(parser.feed(l))
	return events


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var parser := PhiParser.new()
	var ev20 := _feed_all(parser, _eagle_block(19, 20))
	check(ev20.size() == 1 and ev20[0].get("type") == "eagleEye", "20x20 eagle event emitted")
	if ev20.size() == 1:
		check(int(ev20[0]["width"]) == 20 and int(ev20[0]["height"]) == 20, "20x20 dims (got %sx%s)" % [ev20[0]["width"], ev20[0]["height"]])
		check((ev20[0]["cells"] as Array).size() == 400, "400 cells")
		# 右下のマス (19,19) のチップが届いている (打ち切りなし)。
		check(int(ev20[0]["cells"][399]["chip"]) == 30 + 19, "far corner cell present")
	var parser2 := PhiParser.new()
	var ev15 := _feed_all(parser2, _eagle_block(14, 15))
	check(ev15.size() == 1 and int(ev15[0]["width"]) == 15 and int(ev15[0]["height"]) == 15, "15x15 unchanged")
	# ビュー: 20 マスの盤面になる。
	var view := PhiEagleView.new()
	root.add_child(view)
	if ev20.size() == 1:
		view.set_event(ev20[0], null, "", 1.0, {})
		check(view.board_dim() == 20, "eagle view dim 20 (got %d)" % view.board_dim())
	view.queue_free()

	print("stage60: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)
