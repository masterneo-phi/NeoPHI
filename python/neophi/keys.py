"""Philly のキー操作。仕様書 §7・§10 と wphi の ``ui/src/keys.ts`` の移植。

キーは入力欄の外にフォーカスがある時だけ操作にする。判定はキーコード名
(``ArrowUp`` や ``KeyZ``)で行い、文字そのものでは判定しない。端末のキーから
コード名への変換は TUI 側(``tui.py``)が行う。
"""

from __future__ import annotations

from dataclasses import dataclass, field

__all__ = [
    "AskOptions",
    "KeyAction",
    "ListKeyAction",
    "key_action",
    "list_key_action",
    "move_command",
    "move_input",
]

# テンキーと矢印キー → 移動キー
MOVE_KEYS: dict[str, str] = {
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

# フルキー → テンキー(Alt を押していない時に読み替える)
FULL_KEY_MOVE: dict[str, str] = {
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

_TURN: dict[str, dict[str, str]] = {
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

_NORTH_FIX: dict[str, dict[str, str]] = {
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


@dataclass
class AskOptions:
    title: str
    label: str
    numeric: bool = False
    initial: str = ""


@dataclass
class KeyAction:
    """キーに対する操作。``send`` は ``\\n`` 区切りで複数行を送る。"""

    send: str | None = None
    confirm: str | None = None
    cancel_list: int = 0
    system_magic: str | None = None  # "reequip" | "keep"
    ask: AskOptions | None = None
    write: bool = False
    focus_input: bool = False
    next_tab: bool = False
    toggle_map: bool = False
    menu: str | None = None


def _send(text: str, **kw) -> KeyAction:
    return KeyAction(send=text, **kw)


def _magic(text: str, kind: str, confirm: str | None = None) -> KeyAction:
    return KeyAction(send=text, cancel_list=1, system_magic=kind, confirm=confirm)


_NONE: dict[str, KeyAction] = {
    "Pause": KeyAction(menu="force-close"),
    "KeyA": _send("read"),
    "KeyB": _send("board"),
    "KeyC": _send("use"),
    "KeyD": _send("erase"),
    "KeyF": _send("floor item"),
    "KeyH": _send("hi"),
    "KeyM": _send("check\nlook"),
    "KeyN": _send("n"),
    "KeyP": KeyAction(
        ask=AskOptions(title="支払い金額", label="支払う金額", numeric=True),
        send="pay {}",
    ),
    "KeyQ": _send("equip"),
    "KeyR": _send("spells"),
    "KeyS": KeyAction(write=True),
    "KeyT": _send("#ex-map style=turn"),
    "KeyV": _send("sort"),
    "KeyW": _send("unequip"),
    "KeyX": _send("put"),
    "KeyY": _send("y"),
    "KeyZ": _send("get"),
    "Period": _send("."),
    "Space": _send("hit"),
    "Digit1": _send("1"),
    "Digit2": _send("2"),
    "Digit3": _send("3"),
    "Digit4": _send("4"),
    "Digit5": _send("5"),
    "Digit6": _send("6"),
    "Digit7": _send("7"),
    "Digit8": _send("8"),
    "Digit9": _send("9"),
    "Digit0": _send("."),
    "Tab": KeyAction(focus_input=True),
    "Home": _send("equip\nsort"),
    "End": _send("unequip\n1", cancel_list=1),
    "Numpad0": _send("check\nlook"),
    "Numpad1": _send("hit"),
    "Numpad3": _send("cast"),
    "NumpadAdd": _send("get"),
    "NumpadSubtract": _send("put"),
    "NumpadEnter": _send("cast"),
    "NumpadDivide": _send("equip"),
    "NumpadMultiply": _send("use"),
    "NumpadDecimal": _send("."),
}
for _n in range(1, 8):
    _NONE[f"F{_n}"] = _send(f"cast\n{_n}", cancel_list=1)

_SHIFT: dict[str, KeyAction] = {
    "F5": KeyAction(toggle_map=True),
    "F1": KeyAction(menu="force-close"),
    "Space": _send("hit"),
    "KeyT": _send("#ex-map style=solid"),
    "Digit5": _send("#ex-map size=40"),
    "Numpad5": _send("#ex-map size=40"),
    "Digit7": _send("#ex-map size=57"),
    "Numpad7": _send("#ex-map size=57"),
}

_ALT: dict[str, KeyAction] = {
    "Pause": KeyAction(menu="all-force-close"),
    "KeyA": _magic("cast\nanalyze", "keep"),
    "KeyB": _magic(
        "cast\ncall", "reequip",
        "現在の位置を call します。\nReturn や死んでしまって再接続するときはこの位置になります。\nよろしいですか？",
    ),
    "KeyC": _magic("cast\ncreate", "keep"),
    "KeyD": _magic("cast\ndetect", "keep"),
    "KeyE": _magic("cast\neagle eye", "reequip"),
    "KeyF": _magic("cast\nforget", "keep"),
    "KeyI": _magic("cast\nidentify", "reequip"),
    "KeyL": _magic("cast\nwizard lock\nsee", "reequip"),
    "KeyP": _magic("cast\nparty eye", "reequip"),
    "KeyR": _magic(
        "cast\nreturn", "reequip",
        "call 位置に帰還します。\n持っているアイテムを失う可能性があります。\nよろしいですか？",
    ),
    "KeyS": KeyAction(
        ask=AskOptions(title="看板検索", label="検索する言葉を入力してください"),
        send="cast\nsearch\n{}", cancel_list=1,
    ),
    "KeyU": _magic("cast\nunlock\nsee", "reequip"),
    "KeyW": _magic("cast\nwizard eye", "reequip"),
}
for _n in range(1, 8):
    _ALT[f"Digit{_n}"] = _send(f"cast\n{_n}", cancel_list=1)

_SHIFT_ALT: dict[str, KeyAction] = {
    "KeyW": _magic("cast\nwizard light", "reequip"),
    "KeyE": _magic(
        "#ex-switch eagleeye=text\ncast\neagle eye\n#ex-switch eagleeye=form",
        "reequip",
    ),
    "KeyL": _magic("cast\nlist", "reequip"),
    "KeyD": _magic("cast\ndestroy", "keep"),
    "KeyC": _magic("cast\ncharge spell", "keep"),
    "KeyA": KeyAction(
        ask=AskOptions(title="召喚", label="召喚するNPCの名前を入力してください"),
        send="cast\nappear {}", cancel_list=1,
    ),
    "KeyU": KeyAction(
        ask=AskOptions(title="送喚", label="送喚するNPCの名前を入力してください"),
        send="cast\ndisappear {}", cancel_list=1,
    ),
}

_CTRL: dict[str, KeyAction] = {
    "Numpad1": _send("hit"),
    "Numpad3": _send("cast"),
    "Space": _send("hit"),
    "Tab": KeyAction(next_tab=True),
}

_TABLES: dict[str, dict[str, KeyAction]] = {
    "none": _NONE,
    "shift": _SHIFT,
    "ctrl": _CTRL,
    "alt": _ALT,
    "shiftAlt": _SHIFT_ALT,
}


def _normalize(
    code: str, *, shift: bool, ctrl: bool, alt: bool, meta: bool, full_key_move: bool
) -> tuple[str, str] | None:
    if meta or (ctrl and (shift or alt)):
        return None
    if alt:
        mods = "shiftAlt" if shift else "alt"
    elif shift:
        mods = "shift"
    elif ctrl:
        mods = "ctrl"
    else:
        mods = "none"
    if full_key_move and not alt:
        code = FULL_KEY_MOVE.get(code, code)
    return code, mods


def move_input(
    code: str,
    *,
    shift: bool = False,
    ctrl: bool = False,
    alt: bool = False,
    meta: bool = False,
    full_key_move: bool = True,
) -> tuple[str, str] | None:
    """移動キーなら ``(移動キー, 修飾)`` を返す。Shift の 5 と 7 は移動ではない。"""
    norm = _normalize(code, shift=shift, ctrl=ctrl, alt=alt, meta=meta, full_key_move=full_key_move)
    if norm is None:
        return None
    norm_code, mods = norm
    if mods in ("alt", "shiftAlt"):
        return None
    if mods == "shift" and norm_code in _SHIFT:
        return None
    key = MOVE_KEYS.get(norm_code)
    if key is None:
        return None
    return key, mods


def move_command(key: str, mods: str, north_fix: bool) -> str:
    """移動キーのコマンド。"""
    return (_NORTH_FIX if north_fix else _TURN)[mods][key]


def key_action(
    code: str,
    *,
    shift: bool = False,
    ctrl: bool = False,
    alt: bool = False,
    meta: bool = False,
    full_key_move: bool = True,
) -> KeyAction | None:
    """移動以外の操作。操作でなければ None。"""
    norm = _normalize(code, shift=shift, ctrl=ctrl, alt=alt, meta=meta, full_key_move=full_key_move)
    if norm is None:
        return None
    norm_code, mods = norm
    if mods == "shift" and norm_code in _SHIFT:
        return _SHIFT[norm_code]
    if norm_code in MOVE_KEYS and mods not in ("alt", "shiftAlt"):
        return None
    return _TABLES[mods].get(norm_code)


@dataclass
class ListKeyAction:
    send: str | None = None
    list_no: int | None = None
    list_ok: bool = False
    list_toggle: bool = False
    list_cursor: int = 0
    focus_input: bool = False


_LIST: dict[str, ListKeyAction] = {
    "Digit0": ListKeyAction(send="."),
    "Numpad0": ListKeyAction(send="."),
    "Escape": ListKeyAction(send="."),
    "Period": ListKeyAction(send="."),
    "NumpadDecimal": ListKeyAction(send="."),
    "ArrowLeft": ListKeyAction(send="."),
    "ArrowRight": ListKeyAction(send="."),
    "NumpadAdd": ListKeyAction(send="-"),
    "Minus": ListKeyAction(send="-"),
    "Enter": ListKeyAction(list_ok=True),
    "NumpadEnter": ListKeyAction(list_ok=True),
    "Space": ListKeyAction(list_toggle=True),
    "ArrowUp": ListKeyAction(list_cursor=-1),
    "ArrowDown": ListKeyAction(list_cursor=1),
    "Tab": ListKeyAction(focus_input=True),
}


def list_key_action(
    code: str,
    *,
    shift: bool = False,
    ctrl: bool = False,
    alt: bool = False,
    meta: bool = False,
    full_key_move: bool = True,
) -> ListKeyAction | None:
    """リスト表示中のキー。リストの操作でなければ None(通常のキー操作へ回す)。"""
    norm = _normalize(code, shift=shift, ctrl=ctrl, alt=alt, meta=meta, full_key_move=full_key_move)
    if norm is None:
        return None
    norm_code, mods = norm
    if mods != "none":
        return None
    for prefix in ("Digit", "Numpad"):
        if norm_code.startswith(prefix):
            rest = norm_code[len(prefix) :]
            if rest in "123456789":
                return ListKeyAction(list_no=int(rest))
    return _LIST.get(norm_code)
