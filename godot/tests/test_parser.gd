extends SceneTree
## パーサの golden テスト。wphi の parser.json と出力を比べる。
##
## 使い方: godot --headless --path . -s tests/test_parser.gd
## 終了コード 0 = 全一致、1 = 不一致あり。

const FIXTURE := "/home/hatch/workspace/phi-client-py/tests/fixtures/parser.json"


func _deep_equal(a: Variant, b: Variant) -> bool:
	if a is Dictionary and b is Dictionary:
		if a.size() != b.size():
			return false
		for key in a:
			if not b.has(key):
				return false
			if not _deep_equal(a[key], b[key]):
				return false
		return true
	if a is Array and b is Array:
		if a.size() != b.size():
			return false
		for i in a.size():
			if not _deep_equal(a[i], b[i]):
				return false
		return true
	if (a is int or a is float) and (b is int or b is float):
		return float(a) == float(b)
	return a == b


func _initialize() -> void:
	Cp932.ensure_loaded()
	var text := FileAccess.get_file_as_string(FIXTURE)
	if text.is_empty():
		printerr("fixture が読めません: ", FIXTURE)
		quit(2)
		return
	var golden = JSON.parse_string(text)
	if not (golden is Array):
		printerr("fixture の JSON が壊れています")
		quit(2)
		return
	var failures := 0
	var steps_total := 0
	for scenario in golden:
		var parser := PhiParser.new()
		var name := str(scenario.get("name", "?"))
		var scenario_fail := 0
		for i in (scenario.get("steps", []) as Array).size():
			steps_total += 1
			var step: Dictionary = scenario["steps"][i]
			var line := str(step["line"]).hex_decode()
			var got: Array = []
			for event in parser.feed(line):
				got.append(event)
			var want: Array = step["events"]
			if not _deep_equal(got, want):
				failures += 1
				scenario_fail += 1
				if scenario_fail <= 3:
					print("FAIL %s[%d]" % [name, i])
					print("  want ", JSON.stringify(want))
					print("  got  ", JSON.stringify(got))
		if scenario_fail == 0:
			print("OK ", name)
		else:
			print("FAIL ", name, " (", scenario_fail, " steps)")
	print("steps: %d, failures: %d" % [steps_total, failures])
	quit(1 if failures > 0 else 0)
