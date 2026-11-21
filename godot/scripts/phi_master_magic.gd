class_name PhiMasterMagic
extends RefCounted
## 超魔法メニュー。Philly の `Config/MasterMagicMenu.xml` を読む。
##
## 戻りは {"caption": "超魔法", "menus": [{"caption": ..., "hint": ...,
## "items": [{"caption": ..., "hint": ..., "steps": [...]}, ...]}, ...]}。
## 区切りは {"separator": true}。step は {"kind": "send" /
## "ok_dialog" / "int_dialog" / "string_dialog", "text": ...}。
## `<send>` の `list` 属性も残す。`list="no"` の send では、サーバが
## 返すリスト (魔法選択など) を表示しない (答えは後続の send で送る)。
## XML が無ければ Philly の既定内容を組み込む。

## 1つの項目で有効な `<send>` の数(Philly の仕様)。
const MAX_SENDS := 5

## マスターの EXP。これ以外のキャラは超魔法を使えない (仕様書 §9.1)。
const MASTER_EXP := 99999999

const DEFAULT_XML := "<?xml version=\"1.0\" encoding= \"Shift_JIS\"?>\n<!-- mastermagic タグ -->\n<!--   マスター魔法の親メニュー（メインメニューの直系の子要素） -->\n<!--   caption:メニューのキャプション -->\n<!--   hint:メニューにカーソルを合わせた時のヒント -->\n\n<!-- menu タグ -->\n<!--   サブメニュー要素 -->\n<!--   caption:メニューのキャプション -->\n<!--   hint:メニューにカーソルを合わせた時のヒント -->\n<!--   サブメニューを持つメニュー要素 -->\n<!--   子要素は item のみ -->\n\n<!-- item タグ -->\n<!--   caption:メニューのキャプション -->\n<!--   hint:メニューにカーソルを合わせた時のヒント -->\n<!--   タグ内の直系の子要素を前から順番に実行していく -->\n<!--   item caption=\"-\"/ でセパレーター -->\n\n<!-- send タグ（item の直系の子要素） -->\n<!--   送信内容（１つの item 内に ５個まで有効） -->\n<!--   %int    は直前の int_dialog    が返した内容に置換される -->\n<!--   %string は直前の string_dialog が返した内容に置換される -->\n\n<!-- ok_dialog タグ（item の直系の子要素） -->\n<!--    ok cancel を選択できるダイアログを表示する -->\n<!--    タグ内のテキストはダイアログのメッセージ -->\n<!--    ダイアログのメッセージには改行「&amp;#xa;」を入れる事が可能 -->\n<!--    cancel を選択した場合は、以下の要素は実行されない -->\n\n<!-- int_dialog タグ（item の直系の子要素） -->\n<!--    整数型を返すダイアログを表示する -->\n<!--    タグ内のテキストはダイアログのタイトル -->\n<!--    ダイアログでキャンセルした場合は、以下の要素は実行されない -->\n\n<!-- string_dialog タグ（item の直系の子要素） -->\n<!--    文字列を返すダイアログを表示する -->\n<!--    タグ内のテキストはダイアログのメッセージ -->\n<!--    ダイアログのメッセージには改行「&amp;#xa;」を入れる事が可能 -->\n<!--    ダイアログでキャンセルした場合は、以下の要素は実行されない -->\n\n<mastermagic caption=\"超魔法(&amp;S)\" hint=\"マスター魔法\">\n\n  <menu caption=\"移動魔法\" hint=\"自分もしくは相手を移動する魔法\">\n    <item caption=\"jump\" hint=\"対象 PC の所に移動する\">\n      <send list=\"no\">cast</send>\n      <send>list</send>\n      <int_dialog>対象の No を指定してください</int_dialog>\n      <send list=\"no\">cast</send>\n      <send>jump %int</send>\n    </item>\n\n    <item caption=\"draw\" hint=\"対象 PC を呼び寄せる\">\n      <send list=\"no\">cast</send>\n      <send>list</send>\n      <int_dialog>対象の No を指定してください</int_dialog>\n      <send list=\"no\">cast</send>\n      <send>draw %int</send>\n    </item>\n\n    <item caption=\"-\"/>\n\n    <item caption=\"malor\" hint=\"指定座標に移動する\">\n      <string_dialog>移動先座標を指定してください&amp;#xa;xx yy</string_dialog>\n      <send list=\"no\">cast</send>\n      <send>malor</send>\n      <send>%string</send>\n    </item>\n\n    <item caption=\"basi rurla\" hint=\"対象を指定座標に移動する\">\n      <send list=\"no\">cast</send>\n      <send>list</send>\n      <string_dialog>対象と移動先座標を指定してください&amp;#xa;n xx yy</string_dialog>\n      <send list=\"no\">cast</send>\n      <send>basi Rurla %string</send>\n    </item>\n\n    <item caption=\"-\"/>\n\n    <item caption=\"Pass wall\" hint=\"壁を通過できるようになる\">\n      <send list=\"no\">cast</send>\n      <send>Pass wall</send>\n    </item>\n\n  </menu>\n\n  <menu caption=\"遠隔魔法\" hint=\"離れた場所や相手に作用する魔法\">\n    <item caption=\"Remote lock\" hint=\"指定座標の扉やサークルに鍵を掛ける\">\n      <string_dialog>座標を指定してください&#xa;xx yy</string_dialog>\n      <send list=\"no\">cast</send>\n      <send>Remote lock</send>\n      <send>%string</send>\n    </item>\n\n    <item caption=\"Remote unlock\" hint=\"指定座標の扉やサークルの鍵を外す\">\n      <string_dialog>座標を指定してください&#xa;xx yy</string_dialog>\n      <send list=\"no\">cast</send>\n      <send>Remote unlock</send>\n      <send>%string</send>\n    </item>\n\n    <item caption=\"Remote boards\" hint=\"指定座標の看板を読む\">\n      <string_dialog>座標を指定してください&#xa;xx yy</string_dialog>\n      <send list=\"no\">cast</send>\n      <send>Remote boards</send>\n      <send>%string</send>\n    </item>\n\n    <item caption=\"Remote erase\" hint=\"指定座標の看板を消す\">\n      <string_dialog>座標を指定してください&#xa;xx yy</string_dialog>\n      <send list=\"no\">cast</send>\n      <send>Remote erase</send>\n      <send>%string</send>\n    </item>\n\n    <item caption=\"-\"/>\n\n    <item caption=\"Thunder of Zeus\" hint=\"指定した相手に神の雷を落として即死させる\">\n      <int_dialog>雷を落とす相手の No を入力してください</int_dialog>\n      <send list=\"no\">cast</send>\n      <send>Thunder of Zeus</send>\n      <send>%int</send>\n    </item>\n\n    <item caption=\"Hammer of Ares\" hint=\"指定した相手のアイテムと魔法を全て破壊する\">\n      <int_dialog>鉄槌を振り下ろす相手の No を入力してください</int_dialog>\n      <send list=\"no\">cast</send>\n      <send>Hammer of Ares</send>\n      <send>%int</send>\n    </item>\n  </menu>\n\n  <menu caption=\"通常魔法\" hint=\"世界 を制御する魔法\">\n    <item caption=\"Eye of the Yog=Sothoth\" hint=\"クリーチャーの位置を知る\">\n      <send list=\"no\">cast</send>\n      <send>Eye of the Yog=Sothoth</send>\n    </item>\n\n    <item caption=\"Book of the Yog=Sothoth\" hint=\"クリーチャーの位置を知り phied.log に書き出される\">\n      <send list=\"no\">cast</send>\n      <send>Book of the Yog=Sothoth</send>\n    </item>\n\n    <item caption=\"Dumapic\" hint=\"自分の絶対座標を知る\">\n      <send list=\"no\">cast</send>\n      <send>Dumapic</send>\n    </item>\n\n    <item caption=\"Flag\" hint=\"汎用フラグを表示する\">\n      <send list=\"no\">cast</send>\n      <send>Flag</send>\n    </item>\n\n    <item caption=\"Variable\" hint=\"汎用変数の内容を表示する\">\n      <send list=\"no\">cast</send>\n      <send>Variable</send>\n    </item>\n\n    <item caption=\"-\"/>\n\n    <item caption=\"Cache\" hint=\"所持金 ⇔ TAX\">\n      <send list=\"no\">cast</send>\n      <send>Cache</send>\n    </item>\n\n    <item caption=\"Metamorphosis\" hint=\"FLV, WLV, MLV, CLV, MHp, MMp, karma の値を変更する\">\n      <send list=\"no\">cast</send>\n      <send>Metamorphosis</send>\n    </item>\n\n    <item caption=\"Restoration\" hint=\"Hp と Mp を最大値に回復し、一時的な負のステータスを回復する\">\n      <send list=\"no\">cast</send>\n      <send>Restoration</send>\n    </item>\n\n    <item caption=\"Adjustment inflation\" hint=\"tax および taxbase(taxの景気への影響度合)の設定。\">\n      <send list=\"no\">cast</send>\n      <send>Adjustment inflation</send>\n    </item>\n\n    <item caption=\"-\"/>\n\n    <item caption=\"Master list\" hint=\"接続中の一覧を表示する\">\n      <send list=\"no\">cast</send>\n      <send>Master list</send>\n    </item>\n\n    <item caption=\"Master search\" hint=\"phi.sd の最新100件 (看板・ロック) を表示する\">\n      <send list=\"no\">cast</send>\n      <send>Master search</send>\n    </item>\n\n    <item caption=\"Aegis of Athena\" hint=\"一定時間、ダメージを受けなくなる\">\n      <send list=\"no\">cast</send>\n      <send>Aegis of Athena</send>\n    </item>\n\n    <item caption=\"-\"/>\n\n    <item caption=\"Deny PK\" hint=\"PK を禁止する\">\n      <send list=\"no\">cast</send>\n      <send>Deny PK</send>\n    </item>\n\n    <item caption=\"Permit PK\" hint=\"PK を許可する\">\n      <send list=\"no\">cast</send>\n      <send>Permit PK</send>\n    </item>\n\n    <item caption=\"-\"/>\n\n    <item caption=\"Open box of Pandora\" hint=\"パンドラの箱を開ける\">\n      <send list=\"no\">cast</send>\n      <send>Open box of Pandora</send>\n    </item>\n\n    <item caption=\"Close box of Pandora\" hint=\"パンドラの箱を閉じる\">\n      <send list=\"no\">cast</send>\n      <send>Close box of Pandora</send>\n    </item>\n\n    <item caption=\"-\"/>\n\n    <item caption=\"DM setup check\" hint=\"DM の設定をチェックする (マスター専用コマンド)\">\n      <send>dmsetupcheck</send>\n    </item>\n\n    <item caption=\"gfakeaction\" hint=\"DMメッセージを全体に発信する (マスター専用コマンド)\">\n      <string_dialog>全体に発信する内容を入力してください</string_dialog>\n      <send>gfakeaction %string</send>\n    </item>\n  </menu>\n\n  <menu caption=\"操作魔法\" hint=\"ファイル を制御する魔法\">\n    <item caption=\"Load td\" hint=\"phi.td を読み込む\">\n      <send list=\"no\">cast</send>\n      <send>Load td</send>\n    </item>\n\n    <item caption=\"Load swt\" hint=\"phi.swt を読み込む\">\n      <send list=\"no\">cast</send>\n      <send>Load swt</send>\n    </item>\n\n    <item caption=\"Load fd\" hint=\"phi.fd を読み込む\">\n      <send list=\"no\">cast</send>\n      <send>Load fd</send>\n    </item>\n\n    <item caption=\"Load ed\" hint=\"phi.ed を読み込む\">\n      <send list=\"no\">cast</send>\n      <send>Load ed</send>\n    </item>\n\n    <item caption=\"Load dd\" hint=\"phi.dd を読み込む\">\n      <send list=\"no\">cast</send>\n      <send>Load dd</send>\n    </item>\n\n    <item caption=\"Load ddx\" hint=\"phi.ddx を読み込む\">\n      <send list=\"no\">cast</send>\n      <send>Load ddx</send>\n    </item>\n\n    <item caption=\"Load ex\" hint=\"phi.ex を読み込む\">\n      <send list=\"no\">cast</send>\n      <send>Load ex</send>\n    </item>\n\n    <item caption=\"Load sd\" hint=\"phi.sd を読み込む\">\n      <send list=\"no\">cast</send>\n      <send>Load sd</send>\n    </item>\n\n    <item caption=\"Load crt\" hint=\"phi.crt を読み込む\">\n      <send list=\"no\">cast</send>\n      <send>Load crt</send>\n    </item>\n\n    <item caption=\"Save id\" hint=\"キャラデータをセーブする\">\n      <send list=\"no\">cast</send>\n      <send>Save id</send>\n    </item>\n\n    <item caption=\"-\"/>\n\n    <item caption=\"Load gate\" hint=\"ゲート情報を読み込む\">\n      <send list=\"no\">cast</send>\n      <send>Load gate</send>\n    </item>\n\n    <item caption=\"Close gate\" hint=\"ゲートを閉じる\">\n      <send list=\"no\">cast</send>\n      <send>Close gate</send>\n    </item>\n\n    <item caption=\"Load ban\" hint=\"phi.ban を読み込む\">\n      <send list=\"no\">cast</send>\n      <send>Load ban</send>\n    </item>\n\n    <item caption=\"Load cmd\" hint=\"phi.cmd を読み込む\">\n      <send list=\"no\">cast</send>\n      <send>Load cmd</send>\n    </item>\n\n    <item caption=\"Load obj\" hint=\"オブジェデータを読み込む\">\n      <send list=\"no\">cast</send>\n      <send>Load obj</send>\n    </item>\n  </menu>\n\n  <menu caption=\"創造魔法\" hint=\"DM を制御する魔法\">\n    <item caption=\"Resource\" hint=\"地形を変化する\">\n      <string_dialog>地形を入れてください&amp;#xa;aa bb</string_dialog>\n      <send list=\"no\">cast</send>\n      <send>Resource %string</send>\n    </item>\n\n    <item caption=\"-\"/>\n\n    <item caption=\"Wish\" hint=\"アイテムを作成する\">\n      <string_dialog>アイテム性能を入れてください&amp;#xa;aaa  0000 00 n 00 00 00 00 00</string_dialog>\n      <send list=\"no\">cast</send>\n      <send>Wish %string</send>\n    </item>\n\n    <item caption=\"Dup\" hint=\"アイテムを複製する\">\n      <send list=\"no\">cast</send>\n      <send>Dup</send>\n    </item>\n\n    <item caption=\"-\"/>\n\n    <item caption=\"Createobj\" hint=\"オブジェデータを作成する\">\n      <string_dialog>オブジェデータを入れてください&amp;#xa;t_woman  SDK \"表示名\"</string_dialog>\n      <send list=\"no\">cast</send>\n      <send>Createobj %string</send>\n    </item>\n\n    <item caption=\"Eraseobj\" hint=\"オブジェデータを消去する\">\n      <string_dialog>座標を入れてください&amp;#xa;xx yy</string_dialog>\n      <send list=\"no\">cast</send>\n      <send>Eraseobj %string</send>\n    </item>\n\n    <item caption=\"Save obj\" hint=\"オブジェデータをセーブする\">\n      <send list=\"no\">cast</send>\n      <send>Save obj</send>\n    </item>\n  </menu>\n\n  <menu caption=\"世界停止魔法\" hint=\"DM を制御する魔法\">\n    <item caption=\"Evil wind from Malaika\" hint=\"世界を停止させる\">\n      <ok_dialog>世界を停止させます。&amp;#xa;よろしいですか？</ok_dialog>\n      <send list=\"no\">cast</send>\n      <send>Evil wind from Malaika</send>\n    </item>\n\n    <item caption=\"Evil wind from Hyades\" hint=\"世界を停止させる\">\n      <ok_dialog>世界を停止させます。&#xa;よろしいですか？</ok_dialog>\n      <send list=\"no\">cast</send>\n      <send>Evil wind from Hyades</send>\n    </item>\n  </menu>\n\n</mastermagic>\n"


static func strip_mnemonic(caption: String) -> String:
	var re := RegEx.new()
	re.compile("\\(&[^)]*?\\)")
	return re.sub(caption, "").strip_edges()


static func _strip_prolog(text: String) -> String:
	var out := text.strip_edges()
	if out.begins_with("<?"):
		var close := out.find("?>")
		if close >= 0:
			out = out.substr(close + 2).strip_edges()
	return out


static func _normalize_text(raw: String) -> String:
	## ダイアログの文言などの正規化。Philly の XML は改行を
	## `&amp;#xa;` と書くので、パーサを通ると文字 `&#xa;` になる。
	## それを改行に戻す。
	var out := raw.replace("&#xa;", "\n").replace("&#xA;", "\n")
	return out.strip_edges()


static func parse(text: String) -> Dictionary:
	var parser := XMLParser.new()
	if parser.open_buffer(_strip_prolog(text).to_utf8_buffer()) != OK:
		return {}
	var root := {"caption": "", "menus": []}
	var current_menu := {}
	var current_item := {}
	var current_step := {}
	var step_kinds := ["send", "ok_dialog", "int_dialog", "string_dialog"]
	while true:
		# 読めない入力では止める。ERR_FILE_EOF 以外のエラーでも
		# read() を繰り返すと終わらないため。
		if parser.read() != OK:
			break
		var node_type := parser.get_node_type()
		if node_type == XMLParser.NODE_ELEMENT:
			var node_name := parser.get_node_name()
			var attrs := {}
			for i in range(parser.get_attribute_count()):
				attrs[parser.get_attribute_name(i)] = parser.get_attribute_value(i)
			if node_name == "mastermagic":
				root["caption"] = strip_mnemonic(str(attrs.get("caption", "")))
			elif node_name == "menu":
				current_menu = {
					"caption": strip_mnemonic(str(attrs.get("caption", ""))),
					"hint": str(attrs.get("hint", "")),
					"items": [],
				}
				(root["menus"] as Array).append(current_menu)
			elif node_name == "item":
				var caption := str(attrs.get("caption", ""))
				if caption == "-":
					current_item = {"separator": true, "steps": []}
				else:
					current_item = {
						"caption": strip_mnemonic(caption),
						"hint": str(attrs.get("hint", "")),
						"steps": [],
					}
				if not current_menu.is_empty():
					(current_menu["items"] as Array).append(current_item)
				if parser.is_empty():
					current_item = {}
			elif step_kinds.has(node_name):
				current_step = {"kind": node_name, "text": ""}
				if node_name == "send":
					current_step["list"] = str(attrs.get("list", ""))
				if not current_item.is_empty():
					(current_item["steps"] as Array).append(current_step)
				if parser.is_empty():
					current_step = {}
		elif node_type == XMLParser.NODE_TEXT:
			if not current_step.is_empty():
				current_step["text"] = str(current_step["text"]) + parser.get_node_data()
		elif node_type == XMLParser.NODE_ELEMENT_END:
			var node_name := parser.get_node_name()
			if step_kinds.has(node_name):
				if not current_step.is_empty():
					current_step["text"] = _normalize_text(str(current_step["text"]))
				current_step = {}
			elif node_name == "item":
				current_item = {}
			elif node_name == "menu":
				current_menu = {}
	return root


static func substitute(text: String, int_val: String, string_val: String) -> String:
	## `%int` / `%string` を直前のダイアログの答えに置き換える。
	return text.replace("%int", int_val).replace("%string", string_val)


static func effective_steps(steps: Array) -> Array:
	## 実行する step の一覧。`<send>` は5個まで有効。
	var out: Array = []
	var sends := 0
	for step_var in steps:
		var step: Dictionary = step_var
		if str(step.get("kind", "")) == "send":
			sends += 1
			if sends > MAX_SENDS:
				continue
		out.append(step)
	return out
