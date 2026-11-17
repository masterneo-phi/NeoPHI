class_name PhiInputHistory
extends RefCounted
## 入力欄の履歴境界。入力欄は「送信済みの履歴部分＋編集中の
## 下書き部分」の2領域を持ち、境界を文字オフセットで持つ。
## 送信は下書き部分だけを送り、送った文は入力欄に残して
## 境界を末尾まで進める。履歴部分を書き換えると、その行が
## 下書きに戻る(境界がその行の先頭まで戻る)。

## 履歴を残す行数の上限。超えたら古い行から切り捨てる。
const MAX_LINES := 200


static func clamp_boundary(text: String, boundary: int) -> int:
	return clampi(boundary, 0, text.length())


static func retreat_boundary(old_text: String, new_text: String, boundary: int) -> int:
	## 編集で履歴部分(境界より前)が書き換えられたら、書き換わった
	## 行の先頭まで境界を戻し、その行を下書きに含める。送信済みの
	## 行を書き換えて Enter を押せば、書き換えた文が送られる。
	## 下書き部分だけの編集では境界は動かない(クランプのみ)。
	var b := clamp_boundary(new_text, boundary)
	if old_text == new_text:
		return b
	var limit := mini(old_text.length(), new_text.length())
	var diff := 0
	while diff < limit and old_text[diff] == new_text[diff]:
		diff += 1
	if diff >= b:
		return b
	return new_text.left(diff).rfind("\n") + 1


static func draft_of(text: String, boundary: int) -> String:
	## 下書き部分(境界から末尾まで)。
	var b := clamp_boundary(text, boundary)
	return text.substr(b)


static func advance(text: String, boundary: int) -> Dictionary:
	## 送信後の状態。末尾に改行を足して次の下書きを新しい行から
	## 始め、境界を末尾まで進め、古い行を切り捨てる。
	## 戻りは {"text": 新しい全文, "boundary": 新しい境界}。
	var out := text
	if not out.is_empty() and not out.ends_with("\n"):
		out += "\n"
	var b := out.length()
	return trim_old_lines(out, b)


static func trim_old_lines(text: String, boundary: int, max_lines: int = MAX_LINES) -> Dictionary:
	## 行数が上限を超えたら、古い行から切り捨てる。境界もずらす。
	var out := text
	var b := clamp_boundary(text, boundary)
	while out.split("\n").size() > max_lines:
		var nl := out.find("\n")
		if nl < 0:
			break
		var drop := nl + 1
		out = out.substr(drop)
		b = maxi(b - drop, 0)
	return {"text": out, "boundary": b}


static func clear_history(text: String, boundary: int) -> Dictionary:
	## 履歴部分だけを消し、下書きだけを残す。
	## 戻りは {"text": 下書き, "boundary": 0}。
	return {"text": draft_of(text, boundary), "boundary": 0}
