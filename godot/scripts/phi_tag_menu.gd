class_name PhiTagMenu
extends RefCounted
## タグ挿入メニュー。Philly の `Config/TagMenu.xml` を読む。
##
## 戻りは木構造: {"kind": "menu", "caption": ..., "children": [...]}。
## 葉は {"kind": "item", "caption": ..., "tag": ..., "closetag": ...}。
## キャプションの `(&X)`(ニーモニック)は表示用に取る。
## XML が無ければ Philly の既定内容を組み込む。

const DEFAULT_XML := "<?xml version=\"1.0\" encoding= \"Shift_JIS\" ?>\n<menu caption=\"タグ\">\n  <menu caption=\"色タグ(&amp;C)\">\n    <item caption=\"Custom(&amp;U)\" tag=\"/*color=#\" closetag=\"*//*.*/\" />\n    <item caption=\"Red(&amp;R)\" tag=\"/*color=red*/\" closetag=\"/*.*/\" />\n    <item caption=\"Blue(&amp;B)\" tag=\"/*color=blue*/\" closetag=\"/*.*/\" />\n    <item caption=\"Cyan(&amp;C)\" tag=\"/*color=cyan*/\" closetag=\"/*.*/\" />\n    <item caption=\"Magenta(&amp;M)\" tag=\"/*color=magenta*/\" closetag=\"/*.*/\" />\n    <item caption=\"Navy(&amp;N)\" tag=\"/*color=navy*/\" closetag=\"/*.*/\" />\n    <item caption=\"Lime(&amp;L)\" tag=\"/*color=lime*/\" closetag=\"/*.*/\" />\n    <item caption=\"Purple(&amp;P)\" tag=\"/*color=purple*/\" closetag=\"/*.*/\" />\n    <item caption=\"Yellow(&amp;Y)\" tag=\"/*color=yellow*/\" closetag=\"/*.*/\" />\n    <item caption=\"Silver(&amp;S)\" tag=\"/*color=silver*/\" closetag=\"/*.*/\" />\n    <item caption=\"Olieve(&amp;O)\" tag=\"/*color=olieve*/\" closetag=\"/*.*/\" />\n    <item caption=\"Teal(&amp;T)\" tag=\"/*color=teal*/\" closetag=\"/*.*/\" />\n    <item caption=\"Maroon(&amp;A)\" tag=\"/*color=maroon*/\" closetag=\"/*.*/\" />\n    <item caption=\"White(&amp;W)\" tag=\"/*color=white*/\" closetag=\"/*.*/\" />\n    <item caption=\"Green(&amp;E)\" tag=\"/*color=green*/\" closetag=\"/*.*/\" />\n    <item caption=\"Gray(&amp;G)\" tag=\"/*color=gray*/\" closetag=\"/*.*/\" />\n  </menu>\n  <menu caption=\"サイズタグ(&amp;S)\">\n    <item caption=\"Large(&amp;L)\" tag=\"/*size=large*/\" closetag=\"/*.*/\" />\n    <item caption=\"Small(&amp;S)\" tag=\"/*size=small*/\" closetag=\"/*.*/\" />\n  </menu>\n  <menu caption=\"スタイルタグ(&amp;S)\">\n    <item caption=\"Bold(&amp;B)\" tag=\"/*style=bold*/\" closetag=\"/*.*/\" />\n    <item caption=\"Italic(&amp;I)\" tag=\"/*style=italic*/\" closetag=\"/*.*/\" />\n    <item caption=\"Strike(&amp;S)\" tag=\"/*style=strike*/\" closetag=\"/*.*/\" />\n    <item caption=\"Under(&amp;N)\" tag=\"/*style=under*/\" closetag=\"/*.*/\" />\n    <item caption=\"Sup(&amp;P)\" tag=\"/*style=sup*/\" closetag=\"/*.*/\" />\n    <item caption=\"Sub(&amp;U)\" tag=\"/*style=sub*/\" closetag=\"/*.*/\" />\n  </menu>\n  <menu caption=\"フォントタグ(&amp;F)\">\n    <item caption=\"フォント種別(&amp;F)\" tag=\"/*font=\" closetag=\"*//*.*/\" />\n  </menu>\n</menu>"


static func strip_mnemonic(caption: String) -> String:
	var re := RegEx.new()
	re.compile("\\(&[^)]*?\\)")
	return re.sub(caption, "").strip_edges()


static func _strip_prolog(text: String) -> String:
	## `<?xml ...?>` の宣言を取る。Shift_JIS 宣言のまま UTF-8 の
	## バッファを渡すと、パーサが文字コードを誤解するため。
	var out := text.strip_edges()
	if out.begins_with("<?"):
		var close := out.find("?>")
		if close >= 0:
			out = out.substr(close + 2).strip_edges()
	return out


static func parse(text: String) -> Dictionary:
	var parser := XMLParser.new()
	if parser.open_buffer(_strip_prolog(text).to_utf8_buffer()) != OK:
		return {}
	var root := {}
	var stack: Array[Dictionary] = []
	while true:
		# 読めない入力では止める。ERR_FILE_EOF 以外のエラーでも
		# read() を繰り返すと終わらないため。
		if parser.read() != OK:
			break
		var node_type := parser.get_node_type()
		if node_type == XMLParser.NODE_ELEMENT:
			var node_name := parser.get_node_name()
			if node_name != "menu" and node_name != "item":
				continue
			var attrs := {}
			for i in range(parser.get_attribute_count()):
				attrs[parser.get_attribute_name(i)] = parser.get_attribute_value(i)
			var node := {
				"kind": node_name,
				"caption": strip_mnemonic(str(attrs.get("caption", ""))),
				"children": [],
			}
			if node_name == "item":
				node["tag"] = str(attrs.get("tag", ""))
				node["closetag"] = str(attrs.get("closetag", ""))
			if stack.is_empty():
				root = node
			else:
				(stack[stack.size() - 1]["children"] as Array).append(node)
			if not parser.is_empty():
				stack.append(node)
		elif node_type == XMLParser.NODE_ELEMENT_END:
			if not stack.is_empty():
				stack.pop_back()
	return root


## 挿入するタグの組を、木から平らにして返す。
## 要素は {"path": ["色タグ", "Red"], "tag": ..., "closetag": ...}。
static func flatten(tree: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	_flatten_into(tree, [], out)
	return out


static func _flatten_into(node: Dictionary, path: Array[String], out: Array[Dictionary]) -> void:
	var caption := str(node.get("caption", ""))
	if str(node.get("kind", "")) == "item":
		var item_path := path.duplicate()
		item_path.append(caption)
		out.append({
			"path": item_path,
			"tag": str(node.get("tag", "")),
			"closetag": str(node.get("closetag", "")),
		})
		return
	var child_path := path.duplicate()
	if not caption.is_empty():
		child_path.append(caption)
	for child_var in node.get("children", []):
		_flatten_into(child_var, child_path, out)
