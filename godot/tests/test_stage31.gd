extends SceneTree
## 第31段: 看板エディタのタグツールバーとプレビューのタグ変換。
## PhiTags.to_bbcode の変換規則と、ツールバーの挿入動作を見る。

var _checks := 0
var _failures := 0


func check(cond: bool, label: String) -> void:
	_checks += 1
	if not cond:
		_failures += 1
		print("FAIL: ", label)


func _buttons(node: Node, out: Array) -> void:
	if node is Button:
		out.append(node)
	for child in node.get_children():
		_buttons(child, out)


func _initialize() -> void:
	# -- to_bbcode --
	check(PhiTags.to_bbcode("素の文", 16) == "素の文", "タグ無しはそのまま")
	check(PhiTags.to_bbcode("/*color=red*/赤/*.*/", 16) == "[color=red]赤[/color]", "色タグ")
	check(PhiTags.to_bbcode("/*color=olieve*/緑/*.*/", 16) == "[color=olive]緑[/color]", "olieve は olive で描く")
	check(PhiTags.to_bbcode("/*style=bold*/太/*.*/細", 16) == "[b]太[/b]細", "太字")
	check(PhiTags.to_bbcode("/*size=large*/大/*.*/", 16) == "[font_size=24]大[/font_size]", "large は +8")
	check(PhiTags.to_bbcode("/*size=small*/小/*.*/", 16) == "[font_size=12]小[/font_size]", "small は -4")
	check(PhiTags.to_bbcode("/*color=red*//*style=bold*/両方/*.*/", 16) == "[color=red][b]両方[/b][/color]", "閉じは全部を逆順に")
	check(PhiTags.to_bbcode("/*color=red*/閉じ忘れ", 16) == "[color=red]閉じ忘れ[/color]", "閉じ忘れは末尾で閉じる")
	check(PhiTags.to_bbcode("/*font=Meiryo*/字/*.*/", 16) == "字", "フォントタグは落とす")
	check(PhiTags.to_bbcode("/*img=http://x/y.png*/", 16) == "", "画像タグは落とす")
	check(PhiTags.to_bbcode("a/*br*/b", 16) == "a\nb", "br は改行")
	check(PhiTags.to_bbcode("[b]偽タグ", 16) == "[lb]b[rb]偽タグ", "角括弧はエスケープ")
	check(PhiTags.to_bbcode("/*style=sup*/上/*.*/", 16) == "[font_size=12]上[/font_size]", "sup は小さく")
	check(PhiTags.to_bbcode("/*color=#ff8800*/橙/*.*/", 16) == "[color=#ff8800]橙[/color]", "16進の色")

	# -- ツールバー --
	var win := PhiMEditWindow.new()
	root.add_child(win)
	win.show_editor("モック太郎")
	var edit := win.get("_edit") as TextEdit
	var buttons: Array = []
	_buttons(win, buttons)
	var red: Button = null
	var bold: Button = null
	var fontb: Button = null
	for b in buttons:
		if (b as Button).tooltip_text == "red":
			red = b
		if (b as Button).text == "B":
			bold = b
		if (b as Button).text == "フォント":
			fontb = b
	check(red != null and bold != null and fontb != null, "色・太字・フォントのボタンがある")
	red.pressed.emit()
	check(edit.text == "/*color=red*//*.*/", "色ボタンでタグが入る: %s" % edit.text)
	check(edit.get_caret_column() == "/*color=red*/".length(), "キャレットはタグの間")
	edit.text = ""
	edit.set_caret_column(0)
	edit.select(0, 0, 0, 0)
	edit.insert_text_at_caret("対象")
	edit.select(0, 0, 0, 2)
	bold.pressed.emit()
	check(edit.text == "/*style=bold*/対象/*.*/", "選択はタグで囲む: %s" % edit.text)
	fontb.pressed.emit()
	check(edit.text.contains("/*font=") and edit.text.contains("*//*.*/"), "フォントの骨組みが入る")
	# プレビューに色が付く (BBCode 化されている)。
	# text_changed は実機では打鍵で出るが、ここでは明示的に発火する。
	edit.text_changed.emit()
	var preview := win.get("_preview") as RichTextLabel
	check(preview.text.contains("[b]対象[/b]"), "プレビューが BBCode 化: %s" % preview.text.right(60))
	win.close_silent()
	print("test_stage31: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)
