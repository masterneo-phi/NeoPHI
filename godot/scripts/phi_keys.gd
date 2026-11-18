class_name PhiKeys
extends RefCounted
## Philly のキー操作。仕様書 §7・§10 と Python 版 neophi/keys.py の移植。
##
## キーは入力欄の外にフォーカスがある時だけ操作にする。判定はキーコード名
## (`ArrowUp` や `KeyZ`)で行い、文字そのものでは判定しない。
## Godot のキーコードからコード名への変換は `code_name` が行う。

## テンキーと矢印キー → 移動キー
const MOVE_KEYS := {
	"Numpad2": "2",
	"Numpad4": "4",
	"Numpad5": "5",
	"Numpad6": "6",
	"Numpad7": "7",
	"Numpad8": "8",
	"Numpad9": "9",
	"ArrowUp": "up",
	"ArrowDown": "down",
	"ArrowLeft": "left",
	"ArrowRight": "right",
}

## フルキー → テンキー(Alt を押していない時に読み替える)
const FULL_KEY_MOVE := {
	"KeyM": "Numpad0",
	"KeyJ": "Numpad1",
	"KeyK": "Numpad2",
	"KeyL": "Numpad3",
	"KeyU": "Numpad4",
	"KeyI": "Numpad5",
	"KeyO": "Numpad6",
	"Digit7": "Numpad7",
	"Digit8": "Numpad8",
	"Digit9": "Numpad9",
	"Minus": "NumpadSubtract",
	"Semicolon": "NumpadAdd",
	"Slash": "NumpadDivide",
	"Quote": "NumpadMultiply",
}

const _TURN := {
	"none": {
		"2": "go b", "4": "go l", "5": "turn b", "6": "go r",
		"7": "turn l", "8": "go", "9": "turn r",
		"down": "go b", "up": "go", "left": "go l", "right": "go r",
	},
	"shift": {
		"2": "go b", "4": "go l", "5": "turn b", "6": "go r",
		"7": "turn l", "8": "go", "9": "turn r",
		"down": "go b", "up": "go", "left": "turn l", "right": "turn r",
	},
	"ctrl": {
		"2": "turn s", "4": "turn w", "5": "turn n", "6": "turn e",
		"7": "turn l", "8": "turn n", "9": "turn r",
		"down": "turn s", "up": "turn n", "left": "turn w", "right": "turn e",
	},
}

const _NORTH_FIX := {
	"none": {
		"2": "go S", "4": "go W", "5": "turn b", "6": "go E",
		"7": "turn l", "8": "go N", "9": "turn r",
		"down": "go S", "up": "go N", "left": "go W", "right": "go E",
	},
	"shift": {
		"2": "go S", "4": "go W", "5": "turn b", "6": "go E",
		"7": "turn l", "8": "go N", "9": "turn r",
		"down": "go b", "up": "go", "left": "turn l", "right": "turn r",
	},
	"ctrl": {
		"2": "go s", "4": "go w", "5": "turn b", "6": "go e",
		"7": "turn l", "8": "go n", "9": "turn r",
		"down": "go s", "up": "go n", "left": "go w", "right": "go e",
	},
}

## 送信キーの割り当て (第111段の最終決定、ユーザーの指示)。
## 基本はバグ報告前の割り当て (Philly どおり) に戻す。
## 1文字コマンド (拾う・置く・使う・読む・書く等) は今までの
## 操作性を壊すため変えない。変えるのは Shift を使うものと
## 後付けのものだけ: 回転/北固定 (T / Shift+T) と話しかける
## (H) とマップサイズ (Shift+5/7/9) は Option 系へ移した
## (Option+T はトグル、handle_key が処理)。入力中の誤爆対策
## はメニューのアクセラレータを Alt 系のみにしたことが担う。
## 値は送る行 (`\n` 区切りで複数行)。
const _NONE_SEND := {
	"KeyA": "read",
	"KeyB": "board",
	"KeyC": "use",
	"KeyD": "erase",
	"KeyF": "floor item",
	"KeyM": "check\nlook",
	"KeyN": "n",
	"KeyQ": "equip",
	"KeyR": "spells",
	"KeyS": "write",
	"KeyV": "sort",
	"KeyW": "unequip",
	"KeyX": "put",
	"KeyY": "y",
	"KeyZ": "get",
	"Period": ".",
	"Space": "hit",
	"Home": "equip\nsort",
	"End": "unequip\n1",
	"Digit1": "1",
	"Digit2": "2",
	"Digit3": "3",
	"Digit4": "4",
	"Digit5": "5",
	"Digit6": "6",
	"Digit7": "7",
	"Digit8": "8",
	"Digit9": "9",
	"Digit0": ".",
	"Numpad0": "check\nlook",
	"Numpad1": "hit",
	"Numpad3": "cast",
	"NumpadAdd": "get",
	"NumpadSubtract": "put",
	"NumpadEnter": "cast",
	"NumpadDivide": "equip",
	"NumpadMultiply": "use",
	"NumpadDecimal": ".",
	"F1": "cast\n1",
	"F2": "cast\n2",
	"F3": "cast\n3",
	"F4": "cast\n4",
	"F5": "cast\n5",
	"F6": "cast\n6",
	"F7": "cast\n7",
}

## Shift+キー。Shift を使うショートカット (北固定 Shift+T、
## マップサイズ Shift+5/7/9) は第111段で廃止し、Option 系へ
## 移した (ユーザーの指示)。残るのは Space (攻撃) だけ。
const _SHIFT_SEND := {
	"Space": "hit",
}

const _CTRL_SEND := {
	"Numpad1": "hit",
	"Numpad3": "cast",
	"Space": "hit",
}

## Alt+キー (送信系の追加分。魔法系は PhiActions の Alt 表が
## 担う)。ユーザーの指定: 話しかけるは Option+H。Alt+数字は
## Philly 本来の詠唱 (Main が処理) に空けるため、マップ
## サイズは Option+Shift+数字へ移した。回転/北固定の切替
## (Alt+T) は表ではなく handle_key のトグル処理が担う。
const _ALT_SEND := {
	"KeyH": "hi",
}

## Shift+Alt+キー。マップサイズ (ユーザーの指定:
## Option+Shift+5/7/9)。
const _SHIFT_ALT_SEND := {
	"Digit5": "#ex-map size=40",
	"Numpad5": "#ex-map size=40",
	"Digit7": "#ex-map size=57",
	"Numpad7": "#ex-map size=57",
	"Digit9": "#ex-map size=81",
	"Numpad9": "#ex-map size=81",
}


## Godot のキーコード → Philly のコード名。対応が無ければ ""。
static func code_name_for(keycode: Key, physical: Key, unicode: int) -> String:
	## イベントからキー名を決める。確定文字 (unicode) を持つ
	## イベントでは、物理キーの名前を信用しない (第88段)。
	## Windows の IME は全角スペースの確定を physical=Pause・
	## unicode=U+3000 で届けることがあり、物理キー優先だと
	## 強制切断キーと取り違える (実測: wire ログの KEY 行)。
	## 文字としての名前が付くものはそちらを正とする。
	if unicode >= 0x20 and unicode != 0x7F:
		var by_char := _code_name_for_char(unicode)
		if not by_char.is_empty():
			return by_char
	var code := code_name(physical)
	if code.is_empty():
		code = code_name(keycode)
	return code


static func _code_name_for_char(unicode: int) -> String:
	## 文字コードから付けられるキー名。付けられない文字は ""。
	if unicode == 0x20 or unicode == 0x3000:
		return "Space"
	if unicode >= 0x61 and unicode <= 0x7A: # a-z
		return "Key" + String.chr(unicode - 0x20)
	if unicode >= 0x41 and unicode <= 0x5A: # A-Z
		return "Key" + String.chr(unicode)
	if unicode >= 0x30 and unicode <= 0x39: # 0-9
		return "Digit" + String.chr(unicode)
	return ""


static func code_name(keycode: Key) -> String:
	match keycode:
		KEY_UP:
			return "ArrowUp"
		KEY_DOWN:
			return "ArrowDown"
		KEY_LEFT:
			return "ArrowLeft"
		KEY_RIGHT:
			return "ArrowRight"
		KEY_KP_0:
			return "Numpad0"
		KEY_KP_1:
			return "Numpad1"
		KEY_KP_2:
			return "Numpad2"
		KEY_KP_3:
			return "Numpad3"
		KEY_KP_4:
			return "Numpad4"
		KEY_KP_5:
			return "Numpad5"
		KEY_KP_6:
			return "Numpad6"
		KEY_KP_7:
			return "Numpad7"
		KEY_KP_8:
			return "Numpad8"
		KEY_KP_9:
			return "Numpad9"
		KEY_KP_ADD:
			return "NumpadAdd"
		KEY_KP_SUBTRACT:
			return "NumpadSubtract"
		KEY_KP_MULTIPLY:
			return "NumpadMultiply"
		KEY_KP_DIVIDE:
			return "NumpadDivide"
		KEY_KP_ENTER:
			return "NumpadEnter"
		KEY_KP_PERIOD:
			return "NumpadDecimal"
		KEY_SPACE:
			return "Space"
		KEY_TAB:
			return "Tab"
		KEY_HOME:
			return "Home"
		KEY_END:
			return "End"
		KEY_PAUSE:
			return "Pause"
		KEY_MINUS:
			return "Minus"
		KEY_SEMICOLON:
			return "Semicolon"
		KEY_SLASH:
			return "Slash"
		KEY_APOSTROPHE:
			return "Quote"
		KEY_PERIOD:
			return "Period"
		KEY_F1:
			return "F1"
		KEY_F2:
			return "F2"
		KEY_F3:
			return "F3"
		KEY_F4:
			return "F4"
		KEY_F5:
			return "F5"
		KEY_F6:
			return "F6"
		KEY_F7:
			return "F7"
		KEY_F8:
			return "F8"
		KEY_F9:
			return "F9"
		KEY_F10:
			return "F10"
		KEY_F11:
			return "F11"
		KEY_F12:
			return "F12"
	if keycode >= KEY_A and keycode <= KEY_Z:
		return "Key" + String.chr(0x41 + (keycode - KEY_A))
	if keycode >= KEY_0 and keycode <= KEY_9:
		return "Digit" + String.chr(0x30 + (keycode - KEY_0))
	return ""


static func _normalize(code: String, shift: bool, ctrl: bool, alt: bool, meta: bool, full_key_move: bool) -> Variant:
	if meta or (ctrl and (shift or alt)):
		return null
	var mods := "none"
	if alt:
		mods = "shiftAlt" if shift else "alt"
	elif shift:
		mods = "shift"
	elif ctrl:
		mods = "ctrl"
	if full_key_move and not alt:
		code = FULL_KEY_MOVE.get(code, code)
	return [code, mods]


## 移動キーなら `[移動キー, 修飾]` を返す。Shift の 5 と 7 は移動ではない。
static func move_input(code: String, shift: bool = false, ctrl: bool = false, alt: bool = false, meta: bool = false, full_key_move: bool = true) -> Variant:
	var norm: Variant = _normalize(code, shift, ctrl, alt, meta, full_key_move)
	if norm == null:
		return null
	var norm_code: String = norm[0]
	var mods: String = norm[1]
	if mods == "alt" or mods == "shiftAlt":
		return null
	if mods == "shift" and _SHIFT_SEND.has(norm_code):
		return null
	var key: Variant = MOVE_KEYS.get(norm_code)
	if key == null:
		return null
	return [key, mods]


## 移動キーのコマンド。
static func move_command(key: String, mods: String, north_fix: bool) -> String:
	var table: Dictionary = _NORTH_FIX if north_fix else _TURN
	return (table[mods] as Dictionary)[key]


static func _direction_of(key: String) -> String:
	## 方向キーの方位 (N/S/W/E)。回転系などは ""。
	match key:
		"8", "up":
			return "N"
		"2", "down":
			return "S"
		"4", "left":
			return "W"
		"6", "right":
			return "E"
	return ""


static func compose_held(held: Array) -> Array:
	## 押し続けている移動キー (押した順の [{key, mods}]) から、
	## 送る移動キーの並び [[key, mods], ...] を決める
	## (Philly classMoveCommand の同時押し合成)。
	## - 回転系 (7/9/5) があれば、最後に押された回転系だけ
	##   (回転系は優先処理される)。
	## - 方向系は最後の2つを見る: 直交なら斜め (縦→横の順で
	##   両方、マウスと同じ)、相反・同一方向なら新しい方だけ。
	## - 方向系が1つならそれだけ。
	if held.is_empty():
		return []
	for i in range(held.size() - 1, -1, -1):
		if str(held[i]["key"]) in ["7", "9", "5"]:
			return [[str(held[i]["key"]), str(held[i]["mods"])]]
	var dirs: Array = []
	for entry in held:
		if not _direction_of(str(entry["key"])).is_empty():
			dirs.append(entry)
	if dirs.is_empty():
		return []
	var last: Dictionary = dirs[dirs.size() - 1]
	if dirs.size() == 1:
		return [[str(last["key"]), str(last["mods"])]]
	var prev: Dictionary = dirs[dirs.size() - 2]
	var d_last := _direction_of(str(last["key"]))
	var d_prev := _direction_of(str(prev["key"]))
	var last_vertical := d_last == "N" or d_last == "S"
	var prev_vertical := d_prev == "N" or d_prev == "S"
	if last_vertical != prev_vertical:
		# 直交 → 斜め。縦→横の順。
		if prev_vertical:
			return [[str(prev["key"]), str(prev["mods"])], [str(last["key"]), str(last["mods"])]]
		return [[str(last["key"]), str(last["mods"])], [str(prev["key"]), str(prev["mods"])]]
	# 同じ軸 (相反・同一方向) は新しい方だけ。
	return [[str(last["key"]), str(last["mods"])]]


## 移動以外の操作で送る行。操作でなければ ""。Tab は入力欄へ行く合図で別扱い。
static func key_send(code: String, shift: bool = false, ctrl: bool = false, alt: bool = false, meta: bool = false, full_key_move: bool = true) -> String:
	var norm: Variant = _normalize(code, shift, ctrl, alt, meta, full_key_move)
	if norm == null:
		return ""
	var norm_code: String = norm[0]
	var mods: String = norm[1]
	if mods == "shift" and _SHIFT_SEND.has(norm_code):
		return _SHIFT_SEND[norm_code]
	if MOVE_KEYS.has(norm_code) and mods != "alt" and mods != "shiftAlt":
		return ""
	if mods == "none":
		return _NONE_SEND.get(norm_code, "")
	if mods == "ctrl":
		return _CTRL_SEND.get(norm_code, "")
	if mods == "alt":
		return _ALT_SEND.get(norm_code, "")
	if mods == "shiftAlt":
		return _SHIFT_ALT_SEND.get(norm_code, "")
	return ""
