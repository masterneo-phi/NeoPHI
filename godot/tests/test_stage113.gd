extends SceneTree
## 第113段: 特殊カラータグ (+hp/-hp/+mp/-mp) の表示対応。
## Philly ではスキンの Log.css の .color__hp 等で色が決まる。
## NeoPHI でも同じ色で出す (スキン優先、無ければ Philly 既定色)。

var _checks := 0
var _failures := 0


func check(cond: bool, label: String) -> void:
	_checks += 1
	if not cond:
		_failures += 1
		print("FAIL: ", label)


func _initialize() -> void:
	# 既定色 (Philly 既定スキン: +hp=green, -hp=red, +mp=blue, -mp=red)
	check(PhiTags.to_bbcode("/*color=+hp*/回復/*.*/", 16) == "[color=#008000]回復[/color]", "+hp は緑")
	check(PhiTags.to_bbcode("/*color=-hp*/傷/*.*/", 16) == "[color=#ff0000]傷[/color]", "-hp は赤")
	check(PhiTags.to_bbcode("/*color=+mp*/魔回/*.*/", 16) == "[color=#0000ff]魔回[/color]", "+mp は青")
	check(PhiTags.to_bbcode("/*color=-mp*/魔減/*.*/", 16) == "[color=#ff0000]魔減[/color]", "-mp は赤")
	check(PhiTags.to_bbcode("/*cl=+mp*/別名/*.*/", 16) == "[color=#0000ff]別名[/color]", "cl= でも効く")
	# スキンの色定義が優先する
	check(PhiTags.to_bbcode("/*color=+hp*/回復/*.*/", 16, {"+hp": "#00ff00"}) == "[color=#00ff00]回復[/color]", "スキン色が優先")
	check(PhiTags.to_bbcode("/*color=white*/白/*.*/", 16, {"white": "#d0d0ff"}) == "[color=#d0d0ff]白[/color]", "色名もスキン定義で")
	# 未知の特殊値は従来どおり落とす
	check(PhiTags.to_bbcode("/*color=+zz*/謎/*.*/", 16) == "謎", "未知の + 値は落とす")
	# 通常の色名はそのまま
	check(PhiTags.to_bbcode("/*color=teal*/青緑/*.*/", 16) == "[color=teal]青緑[/color]", "通常色名は不変")
	# Log.css から対応表を作る
	var css := SkinFiles.parse_log_css(".color__hp { color:green; } .color_-mp { color:red; } .color_white { color:#d0d0ff; } .color_a_ { color:aqua; } .cl__mp { color:navy; }")
	var map := SkinFiles.tag_colors_from_css(css)
	check(map.get("+hp") == "#008000", "css +hp: %s" % str(map))
	check(map.get("-mp") == "#ff0000", "css -mp")
	check(map.get("white") == "#d0d0ff", "css white")
	check(map.get("a") == "#00ffff", "css 1文字色 a")
	check(map.get("+mp") == "#000080", "css cl__mp (navy)")
	print("test_stage113: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)
