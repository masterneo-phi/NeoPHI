class_name PhiInputHistory
extends RefCounted
## 入力欄の履歴境界。入力欄は「送信済みの履歴部分＋編集中の
## 下書き部分」の2領域を持ち、境界を文字オフセットで持つ。
## 送信は行単位で、Enter を押した行だけが発言として送られる
## (phi_character の submit_input がキャレット行を取り出す)。
## 境界は、履歴のクリアと追加発言の対象範囲を決めるための
## 記録として残し、送信のたびに末尾まで進める。

## 履歴を残す行数の上限。超えたら古い行から切り捨てる。
const MAX_LINES := 200


static func clamp_boundary(text: String, boundary: int) -> int:
	return clampi(boundary, 0, text.length())


static func line_at(text: String, line_index: int) -> String:
	## line_index 行目の文(改行を含まない)。送信の単位はこちら。
	## 範囲外の行番号は端の行に寄せる。
	if text.is_empty():
		return ""
	var lines := text.split("\n")
	return lines[clampi(line_index, 0, lines.size() - 1)]


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
