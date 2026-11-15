class_name PhiShortcuts
extends RefCounted
## F1〜F12 のショートカットと発言の変換。Philly の `Command.cpp`・
## `classCommand`・`MainForm.cpp` の送信処理にあたる。
## 画面を持たない純粋な関数だけなので、単体テストしやすい。


static func magic_text(no: int, fix: bool, spell: String) -> String:
	## F1〜F7 が送る行。`no` は 1〜7。
	## FuncKeyMagicFix が off なら `cast\n<番号>`。
	## on なら `cast\n<魔法名>`。魔法名が空なら何も送らない。
	if no < 1 or no > 7:
		return ""
	if fix:
		var name := spell.strip_edges()
		if name.is_empty():
			return ""
		return "cast\n" + name
	return "cast\n" + str(no)


static func shortcut_text(text: String, list_text: String, list_mode: bool) -> String:
	## F8〜F12 が送る行。
	## リストの間はリスト用文字列をそのまま、それ以外は `\n` の
	## 文字(バックスラッシュ + n)を改行に置き換えた自由文字列を送る。
	if list_mode:
		return list_text
	return text.replace("\\n", "\n")


static func list_number(line: String, index: int) -> String:
	## リストの行から番号を取り出す。行頭の `[  2]` のような
	## `[数字]` 記法があればその数字、無ければ 1 始まりの行番号。
	## 数字の前の空白は詰める。
	var stripped := line.strip_edges()
	if stripped.begins_with("["):
		var close := stripped.find("]")
		if close > 1:
			var inner := stripped.substr(1, close - 1).strip_edges()
			if inner.is_valid_int():
				return str(int(inner))
	return str(index + 1)


static func user_number(key: String) -> int:
	## `#user` の鍵 (`u12` 形式)から priv 番号を取り出す。
	## 形が違えば -1。
	if not key.begins_with("u"):
		return -1
	var rest := key.substr(1)
	if not rest.is_valid_int():
		return -1
	var no := int(rest)
	if no <= 0:
		return -1
	return no


static func speech_transform(
	text: String,
	ctrl: bool,
	loud: bool,
	loud_all: bool,
	loudly_by_asterisk: int,
	party_by_ctrl: bool,
) -> Dictionary:
	## 送信する発言を Philly の順序で変換する。
	## 戻りは `{"text": 送る行, "need_confirm": 大声の確認が要るか}`。
	## 順序: (1)大声ボタン → (2)行頭 `*` → (3)パーティー `+`。
	## 大声ボタンが on で、まだ「すべて大声」になっていなければ
	## 確認ダイアログが要る。確認で「はい」なら `*` を付けて送る。
	## 行頭 `*` は LoudlyByAsterisk で扱いが変わる。
	## 0: `/**/` を頭に差し込んで大声を消す。
	## 1: Ctrl+Enter の時だけ大声(そのまま送る)。
	## 2: いつでも大声(そのまま送る)。
	## パーティーは Ctrl+Enter で `+` を付ける。
	## 空行は `/**/` にする(Philly EditSendNullLine)。
	if text.is_empty():
		return {"text": "/**/", "need_confirm": false}
	if loud:
		if loud_all:
			return {"text": "*" + text, "need_confirm": false}
		return {"text": text, "need_confirm": true}
	if text.begins_with("*"):
		match loudly_by_asterisk:
			0:
				return {"text": "/**/" + text, "need_confirm": false}
			1:
				if not ctrl:
					return {"text": "/**/" + text, "need_confirm": false}
			_:
				pass
		return {"text": text, "need_confirm": false}
	if ctrl and party_by_ctrl:
		return {"text": "+" + text, "need_confirm": false}
	return {"text": text, "need_confirm": false}
