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

## 修飾なしの操作。値は送る行(`\n` 区切りで複数行)。試作では send のみ扱う。
const _NONE_SEND := {
	"KeyA": "read",
	"KeyB": "board",
	"KeyC": "use",
	"KeyD": "erase",
	"KeyF": "floor item",
	"KeyH": "hi",
	"KeyM": "check\nlook",
	"KeyN": "n",
	"KeyQ": "equip",
	"KeyR": "spells",
	"KeyV": "sort",
	"KeyW": "unequip",
	"KeyX": "put",
	"KeyY": "y",
	"KeyZ": "get",
	"Period": ".",
	"Space": "hit",
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
	"Home": "equip\nsort",
	"End": "unequip\n1",
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
	"KeyT": "#ex-map style=turn",
}

const _SHIFT_SEND := {
	"Space": "hit",
	"KeyT": "#ex-map style=solid",
	"Digit5": "#ex-map size=40",
	"Numpad5": "#ex-map size=40",
	"Digit7": "#ex-map size=57",
	"Numpad7": "#ex-map size=57",
}

const _CTRL_SEND := {
	"Numpad1": "hit",
	"Numpad3": "cast",
	"Space": "hit",
}


## Godot のキーコード → Philly のコード名。対応が無ければ ""。
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
	return ""
