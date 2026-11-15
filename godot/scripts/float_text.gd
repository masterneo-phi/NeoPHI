class_name PhiFloatText
extends RefCounted
## ログの行から、戦闘の数字を抜き出します。
##
## Python 版 neophi/float_text.py の移植。実サーバ (rel5g MasterGate) の
## メッセージ集 dm_msg_jp.h の文面に合わせています。タグを除いた後の行を
## 見ます。数字は行末の `[N hp]` や `[N mp]` に出ます。

const _NUM := "([\\d,]+)"
# 名前は、文の区切りと、行頭の「DM > 」の区切りを含まない範囲にします。
# 頭の空白は含めないので、「しかし X は ...」の「しかし」を名前に含みません。
const _NAME := "([^\\s。！!、,\\n>][^。！!、,\\n>]*?)"

const _FULLWIDTH := ["０", "１", "２", "３", "４", "５", "６", "７", "８", "９", "，"]
const _HALFWIDTH := ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9", ","]

static var _patterns: Array = []


static func _ensure_patterns() -> void:
	if not _patterns.is_empty():
		return
	# (種類, 文面の型, 名前の組, 数字の組)。名前の組が -1 なら自分です。
	# 順番に意味があります。治療(他)を食べ物の回復より先に見ないと、
	# 治療の行を術者の回復と読み違えます。
	var defs := [
		# 攻撃 (物理・魔法): 「X は Y を W で攻撃した. [N hp]」→ Y
		["dealt", _NAME + " は " + _NAME + " を .+?で攻撃した\\. \\[" + _NUM + " hp\\]", 2, 3],
		# 攻撃 (MP): 「X は Y を W で攻撃した. [N mp]」→ Y
		["mpdmg", _NAME + " は " + _NAME + " を .+?で攻撃した\\. \\[" + _NUM + " mp\\]", 2, 3],
		# 吸収 (攻撃): 「Y は X の W による攻撃を吸収した. [N hp]」→ Y
		["heal", _NAME + " は " + _NAME + " の .+?による攻撃を吸収した\\. \\[" + _NUM + " hp\\]", 1, 3],
		# 吸収 (魔法・罠): 「Y は ... を吸収した. [N mp]」→ Y
		["mp", _NAME + " は .+? を吸収した\\. \\[" + _NUM + " mp\\]", 1, 2],
		# 罠: 「Y は S からダメージを受けた. [N hp]」
		["taken", _NAME + " は .+? からダメージを受けた\\. \\[" + _NUM + " hp\\]", 1, 2],
		# 罠 (MP)
		["mpdmg", _NAME + " は .+? からダメージを受けた\\. \\[" + _NUM + " mp\\]", 1, 2],
		# 暴発 (周囲): 「X は 魔法の暴発でダメージを受けた. [N hp]」
		["taken", _NAME + " は 魔法の暴発でダメージを受けた\\. \\[" + _NUM + " hp\\]", 1, 2],
		# 暴発 (自分): 「暴発! ダメージ N hp.」
		["taken", "暴発! ダメージ\\s*" + _NUM + "\\s*hp", -1, 1],
		# 治療 (自分): 「X が S によって回復した. [N hp]」
		["heal", _NAME + " が .+?によって回復した\\. \\[" + _NUM + " hp\\]", 1, 2],
		# 治療 (他): 「X は Y を S で回復した. [N hp]」→ Y
		["heal", _NAME + " は " + _NAME + " を .+?で回復した\\. \\[" + _NUM + " hp\\]", 2, 3],
		# 治療 (他・MP)
		["mp", _NAME + " は " + _NAME + " を .+?で回復した\\. \\[" + _NUM + " mp\\]", 2, 3],
		# 食べ物 (MP回復・周囲): 「X は S で回復した. [N mp]」
		["mp", _NAME + " は .+?で回復した\\. \\[" + _NUM + " mp\\]", 1, 2],
		# 食べ物 (MP回復・自分): 「(しかし) X は N mp 回復した.」
		["mp", "(?:しかし )?" + _NAME + " は " + _NUM + "\\s*mp 回復した", 1, 2],
		# 食べ物 (食中毒): 「X は食中毒でダメージを受けた. [N mp]」
		["mpdmg", _NAME + " は食中毒でダメージを受けた\\. \\[" + _NUM + " mp\\]", 1, 2],
		# 食べ物 (ダメージ・周囲): 「X は S でダメージを受けた. [N mp]」
		["mpdmg", _NAME + " は .+?でダメージを受けた\\. \\[" + _NUM + " mp\\]", 1, 2],
	]
	for d in defs:
		var rx := RegEx.new()
		var err := rx.compile(d[1])
		if err != OK:
			printerr("float pattern compile failed: ", d[1])
			continue
		_patterns.append({"kind": d[0], "rx": rx, "name_group": d[2], "amount_group": d[3]})


static func _normalize(text: String) -> String:
	var out := text
	for i in _FULLWIDTH.size():
		out = out.replace(_FULLWIDTH[i], _HALFWIDTH[i])
	return out


## ログの1行から、浮かべる数字を抜き出します。
##
## 当てはまる型がなければ、空の表を返します。1行に1つまでです。
## 戻り値は {"kind": 種類, "target": 名前か null (自分), "amount": 数字} の表です。
static func parse_floats(text: String) -> Array:
	_ensure_patterns()
	var norm := _normalize(text)
	for p in _patterns:
		var rx: RegEx = p["rx"]
		var hit := rx.search(norm)
		if hit == null:
			continue
		var target: Variant = null
		var name_group: int = p["name_group"]
		if name_group >= 0:
			target = hit.get_string(name_group).strip_edges()
			if (target as String).is_empty():
				continue
		var amount := int(hit.get_string(int(p["amount_group"])).replace(",", ""))
		return [{"kind": p["kind"], "target": target, "amount": amount}]
	return []
