class_name PhiAutoUnequip
extends RefCounted
## 系統魔法の前に武器を外す (仕様書 §7.1)。Python 版
## neophi/auto_unequip.py の移植 (wphi の auto_unequip.rs が原型)。
##
## UI が `#wphi-cast <1|0> <唱える行をタブで繋いだもの>` を送ると、
## セッションは `unequip` だけを先に送って唱える行を覚える。届いた
## 装備のリストは画面に出さず横取りし、1番が武器なら `1` を、防具か
## 装身具なら `.` を送ってから唱える。何も装備していなければそのまま
## 唱える。唱える行は5秒で忘れる (wphi と同じ)。
##
## 装備し直すかどうかは `reequip` の印 (`1`) で決める。Philly の
## AutoEquipSystemMagic と同じく、既定では装備し直さない。装備し直す
## 時は `equip <名前>` を唱える行の後に送り、「を装備した」の1行を
## 出さない。

## UI から届く、系統魔法を唱える行の頭。サーバへは送らない。
const CAST_PREFIX := "#wphi-cast "
## 唱える魔法を覚えておく時間 (秒。Philly の AUTO_UNEQUIP__TIME)。
const KEEP := 5.0
## 装備が無い時にサーバが返す文言。この行は出さずにそのまま唱える。
const _NO_EQUIP := ["装備を外せません", "なにも装備していません", "Can not unequip."]
## リストの後の「外す装備を選択して下さい」。出さない。
const _PROMPT := ["外す装備を選択して下さい", "Input item number to unequip."]

var cast: Array[String] = []
var reequip := false
## これより前なら、unequip の返事を待っている。-1 は無効。
var until := -1.0
## 横取りしている装備のリストの中か。
var list_on := false
## リストの後の「外す装備を選択して下さい」を出さない。
var skip_prompt := false
## 装備し直した時の「を装備した」を出さない期限。-1 は無効。
var hide_equipped_until := -1.0


static func first_equipment(text: String) -> Variant:
	## 装備のリストの1番。[名前, Wpn・Arm・Acr のどれか] か null。
	## `text` はタグを除いた行。Philly の
	## `\[ 1\] (.{0,32})Wp.*?\[(Wpn|Arm|Acr)\]` に相当する。
	var idx := text.find("[ 1] ")
	if idx < 0:
		return null
	var rest := text.substr(idx + 5)
	# v5y は「Wp  : 5」と書く。名前に Wp を含んでも、この欄を使う。
	# 無ければ Philly と同じく最初の Wp。
	var wp := rest.rfind("Wp  :")
	if wp < 0:
		wp = rest.find("Wp")
	if wp < 0:
		return null
	var tail := rest.substr(wp)
	for kind in ["Wpn", "Arm", "Acr"]:
		if tail.contains("[" + kind + "]"):
			return [rest.substr(0, wp).strip_edges(), kind]
	return null


## UI の `#wphi-cast` の行なら、覚えて先に送る `unequip` を返す。
## 違う行なら ""。
func start(line: String, now: float) -> String:
	if not line.begins_with(CAST_PREFIX):
		return ""
	var rest := line.substr(CAST_PREFIX.length())
	var sp := rest.find(" ")
	var flag := rest if sp < 0 else rest.substr(0, sp)
	var cast_text := "" if sp < 0 else rest.substr(sp + 1)
	cast.clear()
	for c in cast_text.split("\t"):
		if c != "":
			cast.append(c)
	reequip = flag == "1"
	until = now + KEEP
	list_on = false
	skip_prompt = false
	hide_equipped_until = -1.0
	return "unequip"


func enabled(now: float) -> bool:
	return until >= 0.0 and now < until


## 受けた行 (タグを除いた文字) を判定する。
## {"hidden": 出さない行か, "reply": 送る行} を返す。
## `#end-list` の代わりに `#ex-list-mode-end` が来ても、装備の
## リストの終わりとして同じく扱う。
func filter(text: String, now: float) -> Dictionary:
	var reply: Array[String] = []
	if skip_prompt:
		skip_prompt = false
		if _contains_any(text, _PROMPT):
			return {"hidden": true, "reply": reply}
	if enabled(now) and not list_on:
		if text == "#list":
			list_on = true
			return {"hidden": true, "reply": reply}
		if _contains_any(text, _NO_EQUIP):
			_cast_now("", reply)
			return {"hidden": true, "reply": reply}
	if list_on:
		if text == "#end-list" or text == "#ex-list-mode-end":
			list_on = false
			skip_prompt = true
			# 1番を読めなかった時も、選ぶのを取り消して唱える。
			# 待ったままだと、5秒の間に届く次のリスト (アイテムを
			# 拾う時など) まで横取りしてしまう。
			if enabled(now):
				_cast_now(".", reply)
		elif enabled(now):
			var found: Variant = first_equipment(text)
			if found != null:
				var item_name := str(found[0])
				var kind := str(found[1])
				if kind == "Wpn":
					if reequip:
						hide_equipped_until = now + KEEP
					_cast_now("1", reply)
					if reequip:
						reply.append("equip " + item_name)
				else:
					_cast_now(".", reply)
		return {"hidden": true, "reply": reply}
	if hide_equipped_until >= 0.0 and now < hide_equipped_until and text.contains("を装備した"):
		hide_equipped_until = -1.0
		return {"hidden": true, "reply": reply}
	return {"hidden": false, "reply": reply}


func _cast_now(answer: String, reply: Array[String]) -> void:
	if answer != "":
		reply.append(answer)
	reply.append_array(cast)
	cast.clear()
	until = -1.0


static func _contains_any(text: String, needles: Array) -> bool:
	for needle in needles:
		if text.contains(str(needle)):
			return true
	return false
