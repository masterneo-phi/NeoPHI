"""受信行を解析してイベントにする。仕様書 §3・§5・§8.3。

wphi の ``crates/phi-proto/src/parser.rs`` の移植。イベントの形(``to_json``)
は Rust 版の serde 出力と同じにし、``tests/fixtures/parser.json`` (wphi の
golden データ)で出力を比べる。

マップは ``M``(地形)・``O``(キャラ)・``.``(確定)の複数行に分かれて届くので、
確定行が来るまでパーサがフレームを溜める。
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field

from .codec import decode

__all__ = [
    "Cell",
    "Chara",
    "CondEvent",
    "ConnectionEvent",
    "EagleEyeEvent",
    "EditEvent",
    "Event",
    "InternalEvent",
    "ListEvent",
    "Magnify",
    "MapEvent",
    "MessageEvent",
    "ModeEvent",
    "NoticeEvent",
    "Parser",
    "Pos",
    "StatusEvent",
    "User",
    "UserListEvent",
    "WorldTransferEvent",
]

_MAP_CELLS = 49
_M57_DIRECTION_OFFSET = 7
_M57_CHIP_OFFSET = 18
_MAP_CHIP_BYTES = _MAP_CELLS * 2
_MAX_EAGLE_EYE = 15
_MAX_LIST_LINES = 1000
_MAX_MAP_CHARS = 1000

_INT_RE = re.compile(r"^[+-]?[0-9]+$")
_HEX_RE = re.compile(r"^\+?[0-9a-fA-F]+$")
_I64_MIN = -(2**63)
_I64_MAX = 2**63 - 1


def _py_int(s: str) -> int | None:
    """Python の ``int(s)`` 相当。Rust の ``i64`` の parse に合わせる。"""
    t = s.strip()
    if not _INT_RE.match(t):
        return None
    try:
        value = int(t, 10)
    except ValueError:
        return None
    if value < _I64_MIN or value > _I64_MAX:
        return None
    return value


def _ascii_uint(s: str) -> int | None:
    """ASCII の数字だけの時だけ数値にする。"""
    if not s or not all("0" <= ch <= "9" for ch in s):
        return None
    return _py_int(s)


def _hex_u32(raw: bytes) -> int | None:
    """ASCII の16進文字列を数値にする。読めなければ None。"""
    try:
        text = raw.decode("ascii")
    except UnicodeDecodeError:
        return None
    if not all(ord(ch) < 128 for ch in text):
        return None
    t = text.strip()
    if not _HEX_RE.match(t):
        return None
    try:
        value = int(t, 16)
    except ValueError:
        return None
    if value > 0xFFFFFFFF:
        return None
    return value


def _dir_to_num(b: int) -> int:
    """自キャラの向きの文字を N=0 から時計回りの数値にする。知らない文字は 0。"""
    return {ord("E"): 2, ord("S"): 4, ord("W"): 6}.get(b, 0)


def _split_ws_max(text: str, max_splits: int) -> list[str]:
    """空白で最大 ``max_splits`` 回だけ分ける。最後の要素は残りそのまま。"""
    return text.split(None, max_splits)


# ---------------------------------------------------------------------------
# イベント
# ---------------------------------------------------------------------------


@dataclass
class NoticeEvent:
    name: str | None = None
    mapset: str | None = None
    world: str | None = None
    area: str | None = None
    mapset_define: tuple[int, str] | None = None

    def to_json(self) -> dict:
        out: dict = {"type": "notice"}
        if self.name is not None:
            out["name"] = self.name
        if self.mapset is not None:
            out["mapset"] = self.mapset
        if self.world is not None:
            out["world"] = self.world
        if self.area is not None:
            out["area"] = self.area
        if self.mapset_define is not None:
            out["mapsetDefine"] = [self.mapset_define[0], self.mapset_define[1]]
        return out


@dataclass
class StatusEvent:
    """``#status 名前 : HP : ...``。数値に出来ない項目は省く。"""

    name: str | None = None
    hp: int | None = None
    max_hp: int | None = None
    mp: int | None = None
    max_mp: int | None = None
    exp: int | None = None
    gp: int | None = None
    f: int | None = None
    w: int | None = None
    m: int | None = None
    c: int | None = None

    def to_json(self) -> dict:
        out: dict = {"type": "status"}
        for key, value in (
            ("name", self.name),
            ("hp", self.hp),
            ("maxHp", self.max_hp),
            ("mp", self.mp),
            ("maxMp", self.max_mp),
            ("exp", self.exp),
            ("gp", self.gp),
            ("f", self.f),
            ("w", self.w),
            ("m", self.m),
            ("c", self.c),
        ):
            if value is not None:
                out[key] = value
        return out


@dataclass
class CondEvent:
    poison: bool = False
    palsy: bool = False
    panic: bool = False
    confuse: bool = False
    berserk: bool = False
    silence: bool = False
    blind: bool = False

    def to_json(self) -> dict:
        return {
            "type": "cond",
            "poison": self.poison,
            "palsy": self.palsy,
            "panic": self.panic,
            "confuse": self.confuse,
            "berserk": self.berserk,
            "silence": self.silence,
            "blind": self.blind,
        }


@dataclass
class ConnectionEvent:
    state: str = "closed"

    def to_json(self) -> dict:
        return {"type": "connection", "state": self.state}


@dataclass
class InternalEvent:
    """サーバへ自動で返す行。セッション層が応答し、UI には渡さない。"""

    action: str  # "lag" | "remap"

    def to_json(self) -> dict:
        return {"type": "_internal", "action": self.action}


@dataclass
class ModeEvent:
    attack: bool = False
    magic: bool = False
    list: bool = False
    more: bool = False

    def to_json(self) -> dict:
        return {
            "type": "mode",
            "attack": self.attack,
            "magic": self.magic,
            "list": self.list,
            "more": self.more,
        }


@dataclass
class ListEvent:
    active: bool
    lines: list[str] | None = None

    def to_json(self) -> dict:
        out: dict = {"type": "list", "active": self.active}
        if self.lines is not None:
            out["lines"] = list(self.lines)
        return out


@dataclass
class EditEvent:
    mode: str  # "single" | "multi" | "end"

    def to_json(self) -> dict:
        return {"type": "edit", "mode": self.mode}


@dataclass
class User:
    key: str
    name: str

    def to_json(self) -> dict:
        return {"key": self.key, "name": self.name}


@dataclass
class UserListEvent:
    users: list[User] = field(default_factory=list)

    def to_json(self) -> dict:
        return {"type": "userList", "users": [u.to_json() for u in self.users]}


@dataclass
class MessageEvent:
    channel: str  # "log" | "priv" | "talk" | "system"
    text: str
    from_: str | None = None
    markup: bool = False

    def to_json(self) -> dict:
        out: dict = {"type": "message", "channel": self.channel, "text": self.text}
        if self.from_ is not None:
            out["from"] = self.from_
        out["markup"] = self.markup
        return out


@dataclass
class Cell:
    chip: int = 0
    attr: int = 0

    def to_json(self) -> dict:
        return {"chip": self.chip, "attr": self.attr}


@dataclass
class Pos:
    x: int = 0
    y: int = 0

    def to_json(self) -> dict:
        return {"x": self.x, "y": self.y}


@dataclass
class Magnify:
    w: int = 0
    h: int = 0
    z: int = 0

    def to_json(self) -> dict:
        return {"w": self.w, "h": self.h, "z": self.z}


@dataclass
class Chara:
    id: int = 0
    x: int = 0
    y: int = 0
    dir: str = "B"
    name: str = ""
    gra: str = ""
    status: int = 0
    gigant: str = "#"
    layer: int = 0
    default: int = 0
    magnify: Magnify | None = None

    def to_json(self) -> dict:
        out: dict = {
            "id": self.id,
            "x": self.x,
            "y": self.y,
            "dir": self.dir,
            "name": self.name,
            "gra": self.gra,
            "status": self.status,
            "gigant": self.gigant,
            "layer": self.layer,
            "default": self.default,
        }
        if self.magnify is not None:
            out["magnify"] = self.magnify.to_json()
        return out


@dataclass
class MapEvent:
    size: int = 7
    dir: int = 0
    cells: list[Cell] = field(default_factory=list)
    chars: list[Chara] = field(default_factory=list)
    style: str | None = None
    pos: Pos | None = None

    def to_json(self) -> dict:
        out: dict = {
            "type": "map",
            "size": self.size,
            "dir": self.dir,
            "cells": [c.to_json() for c in self.cells],
            "chars": [c.to_json() for c in self.chars],
        }
        if self.style is not None:
            out["style"] = self.style
        if self.pos is not None:
            out["pos"] = self.pos.to_json()
        return out


@dataclass
class EagleEyeEvent:
    width: int = 0
    height: int = 0
    self_pos: Pos = field(default_factory=Pos)
    cells: list[Cell] = field(default_factory=list)
    mapset: str | None = None

    def to_json(self) -> dict:
        out: dict = {
            "type": "eagleEye",
            "width": self.width,
            "height": self.height,
            "self": self.self_pos.to_json(),
            "cells": [c.to_json() for c in self.cells],
        }
        if self.mapset is not None:
            out["mapset"] = self.mapset
        return out


@dataclass
class WorldTransferEvent:
    state: str = "start"
    server: str = ""

    def to_json(self) -> dict:
        return {"type": "worldTransfer", "state": self.state, "server": self.server}


Event = (
    NoticeEvent
    | StatusEvent
    | CondEvent
    | ConnectionEvent
    | InternalEvent
    | ModeEvent
    | ListEvent
    | EditEvent
    | UserListEvent
    | MessageEvent
    | MapEvent
    | EagleEyeEvent
    | WorldTransferEvent
)


def _message(channel: str, text: str, from_: str | None) -> MessageEvent:
    return MessageEvent(channel=channel, text=text, from_=from_, markup="/*" in text)


def _parse_status(text: str) -> StatusEvent:
    body = text[len("#status") :].lstrip()
    parts = body.split(":")
    nums = [_py_int(parts[i + 1]) if i + 1 < len(parts) else None for i in range(10)]
    name = parts[0].strip() if parts else ""
    return StatusEvent(
        name=name or None,
        hp=nums[0],
        max_hp=nums[1],
        mp=nums[2],
        max_mp=nums[3],
        exp=nums[4],
        gp=nums[5],
        f=nums[6],
        w=nums[7],
        m=nums[8],
        c=nums[9],
    )


def _parse_cond(text: str) -> CondEvent:
    flags = [ch == "*" for ch in text[6:13]]
    while len(flags) < 7:
        flags.append(False)
    return CondEvent(
        poison=flags[0],
        palsy=flags[1],
        panic=flags[2],
        confuse=flags[3],
        berserk=flags[4],
        silence=flags[5],
        blind=flags[6],
    )


class _EagleEyeAccum:
    """``#ex-eagleeye start`` から ``end`` までの行を溜める。"""

    def __init__(self) -> None:
        self.reset()

    def reset(self) -> None:
        self.grid: list[list[Cell]] = [
            [Cell() for _ in range(_MAX_EAGLE_EYE)] for _ in range(_MAX_EAGLE_EYE)
        ]
        self.size_x = 0
        self.size_y = 0
        self.pos = Pos()

    def feed_line(self, raw: bytes) -> None:
        if len(raw) < 14:
            return
        tail = raw[13:]
        if tail.startswith(b"start"):
            self.reset()
        elif tail[:1] == b"M":
            self._parse_row(raw)
        elif tail.startswith(b"pos"):
            self._parse_pos(raw)

    def _parse_row(self, raw: bytes) -> None:
        header_bytes = raw[: min(len(raw), 21)]
        if any(b >= 128 for b in header_bytes):
            return
        try:
            header = header_bytes.decode("ascii")
        except UnicodeDecodeError:
            return
        parts = header.split()
        if len(parts) < 4:
            return
        size = _py_int(parts[2])
        y = _py_int(parts[3])
        if size is None or y is None:
            return
        if not 0 <= y < _MAX_EAGLE_EYE:
            return
        self.size_y = max(self.size_y, y + 1)
        self.size_x = min(size + 1, _MAX_EAGLE_EYE)
        for x in range(max(self.size_x, 0)):
            i = 21 + x * 2
            if i + 1 >= len(raw):
                break
            self.grid[y][x] = Cell(chip=raw[i], attr=raw[i + 1])

    def _parse_pos(self, raw: bytes) -> None:
        if any(b >= 128 for b in raw):
            return
        try:
            text = raw.decode("ascii")
        except UnicodeDecodeError:
            return
        parts = text.split()
        if len(parts) < 4:
            return
        x = _py_int(parts[2])
        if x is None:
            return
        self.pos.x = x
        y = _py_int(parts[3])
        if y is None:
            return
        self.pos.y = y

    def build(self, mapset: str | None) -> EagleEyeEvent:
        w = max(self.size_x, 0)
        h = max(self.size_y, 0)
        cells = [self.grid[y][x] for y in range(h) for x in range(w)]
        return EagleEyeEvent(
            width=self.size_x, height=self.size_y, self_pos=Pos(self.pos.x, self.pos.y),
            cells=cells, mapset=mapset,
        )


class Parser:
    """状態を持つ行パーサ。1行から0個以上のイベントを返す。"""

    def __init__(self) -> None:
        self._mode = ModeEvent()
        self._in_more = False
        self._in_list = False
        self._list_lines: list[str] = []
        self._map_size = 7
        self._map_dir = 0
        self._map_cells: list[Cell] | None = None
        self._map_chars: list[Chara] = []
        # 次フレームの最初の O 行で map_chars を空にする
        self._chara_clear_pending = False
        self._name_magnify: list[tuple[str, Magnify]] = []
        # #user の名前 → 番号。届いた順を保つ
        self._ulist: list[tuple[str, int]] = []
        self._eagle = _EagleEyeAccum()
        self._mapset: str | None = None
        self._map_style: str | None = None
        self._abs_pos: Pos | None = None

    def in_more(self) -> bool:
        """``#more`` 〜 ``#end-more`` の中か。"""
        return self._in_more

    def clear_users(self) -> None:
        """``#ulist`` を送る時に呼ぶ。届き直す ``#user`` だけの一覧にする。"""
        self._ulist.clear()

    def user_no(self, name: str) -> int | None:
        """``#user`` で届いた名前のユーザ番号。priv の宛先を決める為に使う。"""
        for n, no in self._ulist:
            if n == name:
                return no
        return None

    def feed(self, raw: bytes) -> list[Event]:
        if not raw:
            return []
        # #more 〜 #end-more は #end-more 以外をログにする。看板に #ch-srv など
        # が書かれても、コマンドとして実行しない為である。
        if self._in_more:
            if raw.startswith(b"#end-more"):
                self._in_more = False
                return self._set_mode(more=False)
            return [_message("log", decode(raw), None)]

        is_command = raw[0:1] == b"#" and len(raw) > 1 and raw[1:2] not in (b"#", b" ")
        if is_command:
            # 地形はバイナリなのでデコードしない
            if raw.startswith(b"#m57 M"):
                self._parse_m57_m(raw)
                return []
            if raw.startswith(b"#map M"):
                self._parse_map_m(raw)
                return []
            return self._dispatch_command(decode(raw), raw)

        if self._in_list:
            if len(self._list_lines) < _MAX_LIST_LINES:
                self._list_lines.append(decode(raw))
            return []

        text = decode(raw)
        # "[送り主] > 本文" は priv
        if raw[0:1] == b"[":
            end = text.find("]")
            if end > 0 and text[end + 1 :].lstrip().startswith(">"):
                return [_message("priv", text, text[1:end])]
        # 行頭の /**/ は何もしないタグです。実サーバは発言の行の頭に
        # /**/ を付けるので、分類の時だけ取り除きます。
        classify = text[4:] if text.startswith("/**/") else text
        # "名前 > 本文" で名前が #user にあればプレイヤーの発言
        idx = classify.find(" > ")
        if idx > 0 and self.user_no(classify[:idx]) is not None:
            return [_message("talk", text, classify[:idx])]
        return [_message("log", text, None)]

    def end_list(self) -> list[Event]:
        """リストを閉じる。選択・取消の送信時にも呼ぶ。"""
        self._in_list = False
        self._list_lines = []
        events: list[Event] = [ListEvent(active=False)]
        events.extend(self._set_mode(list_=False))
        return events

    # -- 内部処理 -----------------------------------------------------------

    def _set_mode(
        self,
        *,
        attack: bool | None = None,
        magic: bool | None = None,
        list_: bool | None = None,
        more: bool | None = None,
    ) -> list[Event]:
        before = ModeEvent(
            attack=self._mode.attack, magic=self._mode.magic,
            list=self._mode.list, more=self._mode.more,
        )
        if attack is not None:
            self._mode.attack = attack
        if magic is not None:
            self._mode.magic = magic
        if list_ is not None:
            self._mode.list = list_
        if more is not None:
            self._mode.more = more
        if before == self._mode:
            return []
        return [ModeEvent(
            attack=self._mode.attack, magic=self._mode.magic,
            list=self._mode.list, more=self._mode.more,
        )]

    def _dispatch_command(self, text: str, raw: bytes) -> list[Event]:
        if text.startswith("#name "):
            return [NoticeEvent(name=text[len("#name ") :])]
        if text.startswith("#status ") or text == "#status":
            return [StatusEvent(**_parse_status(text).__dict__)]
        if text.startswith("#cond "):
            return [_parse_cond(text)]
        if text in ("#close", "#x"):
            return [ConnectionEvent()]
        if text == "#lag":
            return [InternalEvent(action="lag")]
        if text == "#remap":
            return [InternalEvent(action="remap")]
        if text == "#more":
            self._in_more = True
            return self._set_mode(more=True)
        if text == "#end-more":
            self._in_more = False
            return self._set_mode(more=False)
        if text == "#list":
            self._in_list = True
            self._list_lines = []
            events = self._set_mode(list_=True)
            events.append(ListEvent(active=True, lines=[]))
            return events
        if text == "#attack":
            return self._set_mode(attack=True)
        if text == "#end-at":
            return self._set_mode(attack=False)
        if text == "#magic":
            return self._set_mode(magic=True)
        if text == "#end-mg":
            return self._set_mode(magic=False)
        if text == "#ex-list-mode-end":
            return self.end_list()
        if text == "#m57 .":
            self._map_size = 7
            return self._finish_map()
        if text == "#map .":
            self._map_size = 5
            return self._finish_map()
        if text == "#ex-eagleeye end":
            return [self._eagle.build(self._mapset)]
        if text == "#m-edit":
            return [EditEvent(mode="multi")]
        if text == "#s-edit":
            return [EditEvent(mode="single")]
        if text == "#.":
            return [EditEvent(mode="end")]
        if text in ("#ex-map style=turn", "#ex-map style=solid"):
            self._map_style = text[len("#ex-map style=") :]
            return []
        if text.startswith("#end-list"):
            self._in_list = False
            lines, self._list_lines = self._list_lines, []
            return [ListEvent(active=True, lines=lines)]
        if raw.startswith(b"#m57 O "):
            self._parse_m57_o(raw)
            return []
        if raw.startswith(b"#m57 W "):
            for start, end in ((7, 74), (75, 142)):
                if len(raw) >= end:
                    self._parse_m57_o(b"#m57 O " + raw[start:end])
            return []
        if text.startswith("#ex-eagleeye "):
            self._eagle.feed_line(raw)
            return []
        if text.startswith("#ex-obj S "):
            self._parse_ex_obj(text)
            return []
        if text.startswith("#user "):
            event = self._parse_user(raw)
            return [event] if event is not None else []
        if text.startswith("#ex-chr-conflict"):
            return [_message("system", "3重状態で消えています。移動してください", None)]
        if text.startswith("#mapset "):
            mapset = text[len("#mapset ") :].strip()
            self._mapset = mapset
            return [NoticeEvent(mapset=mapset)]
        if text.startswith("#mapset-define "):
            parts = text[len("#mapset-define ") :].split()
            if len(parts) >= 2:
                no = _py_int(parts[0])
                if no is not None and 0 <= no <= 255:
                    return [NoticeEvent(mapset_define=(no % 4, parts[1]))]
            return []
        if text.startswith("#ex-notice land="):
            return [NoticeEvent(world=text[len("#ex-notice land=") :])]
        if text.startswith("#ex-notice area="):
            return [NoticeEvent(area=text[len("#ex-notice area=") :])]
        if text.startswith("#ex-pos "):
            parts = text.split()
            if len(parts) >= 3:
                x = _ascii_uint(parts[1])
                y = _ascii_uint(parts[2])
                if x is not None and y is not None:
                    self._abs_pos = Pos(x, y)
            return []
        if text.startswith("#ch-srv "):
            parts = text.split()
            if len(parts) >= 3:
                port = _py_int(parts[2])
                if port is not None:
                    return [WorldTransferEvent(server=f"{parts[1]}:{port}")]
            return []
        # #bgm・#ex-map size= などの既知の行も、未知の行も無視する
        return []

    def _parse_user(self, raw: bytes) -> UserListEvent | None:
        # raw[6..10] = 4桁の番号、raw[11..42] = 31バイトの名前
        if len(raw) < 42:
            return None
        try:
            no_text = raw[6:10].decode("ascii")
        except UnicodeDecodeError:
            return None
        if any(ord(ch) >= 128 for ch in no_text):
            return None
        no = _py_int(no_text)
        if no is None:
            return None
        name = decode(raw[11:42]).rstrip()
        if not name:
            return None
        for i, (n, _) in enumerate(self._ulist):
            if n == name:
                self._ulist[i] = (name, no)
                break
        else:
            self._ulist.append((name, no))
        users = [User(key=f"u{no}", name=n) for n, no in self._ulist]
        return UserListEvent(users=users)

    def _parse_ex_obj(self, text: str) -> None:
        parts = _split_ws_max(text, 5)
        if len(parts) != 6:
            return
        w = _py_int(parts[2])
        h = _py_int(parts[3])
        z = _py_int(parts[4])
        if w is None or h is None or z is None:
            return
        name = parts[5].strip()
        if not name:
            return
        magnify = Magnify(w=w, h=h, z=z)
        for i, (n, _) in enumerate(self._name_magnify):
            if n == name:
                self._name_magnify[i] = (name, magnify)
                return
        self._name_magnify.append((name, magnify))

    def _parse_m57_m(self, raw: bytes) -> None:
        """``#m57 M``。raw[18..116] に (chip, attr) が49組並ぶ。"""
        self._map_size = 7
        if len(raw) > _M57_DIRECTION_OFFSET:
            self._map_dir = _dir_to_num(raw[_M57_DIRECTION_OFFSET])
        end = _M57_CHIP_OFFSET + _MAP_CHIP_BYTES
        if len(raw) < end:
            self._map_cells = None
            return
        chunk = raw[_M57_CHIP_OFFSET:end]
        self._map_cells = [
            Cell(chip=chunk[i], attr=chunk[i + 1]) for i in range(0, len(chunk), 2)
        ]

    def _parse_map_m(self, raw: bytes) -> None:
        """``#map M``(5x5)。本体が ``-`` なら前フレームのまま。"""
        self._map_size = 5
        body = raw[7:]
        body_end = 0
        for i, b in enumerate(body):
            if b not in (0x0D, 0x0A):
                body_end = i + 1
        if body[:body_end] == b"-":
            return
        if len(raw) > _M57_DIRECTION_OFFSET:
            self._map_dir = _dir_to_num(raw[_M57_DIRECTION_OFFSET])
        cells: list[Cell] = []
        for i in range(25):
            chip_idx = 18 + i * 2
            chip = raw[chip_idx] if chip_idx < len(raw) else 0
            attr = 0
            if chip_idx + 50 < len(raw) and raw[chip_idx + 50] == ord("."):
                attr |= 0x60
            if chip_idx + 51 < len(raw) and raw[chip_idx + 51] == ord("-"):
                attr |= 0x08
            cells.append(Cell(chip=chip, attr=attr))
        self._map_cells = cells

    def _parse_m57_o(self, raw: bytes) -> None:
        """``#m57 O`` の固定位置の欄を読む。

        [7]層 [8..12]ID(16進) [13]X [15]Y [17]向き [19..50]名前
        [51..53]状態(16進) [54..69]グラ名 [70]Gigant [72..74]種別(16進)
        """
        if len(raw) < 74:
            return
        layer_ch = chr(raw[7])
        try:
            layer = int(layer_ch, 16)
        except ValueError:
            return
        char_id = _hex_u32(raw[8:12])
        x_ch, y_ch = chr(raw[13]), chr(raw[15])
        if not ("0" <= x_ch <= "9" and "0" <= y_ch <= "9"):
            return
        status = _hex_u32(raw[51:53])
        default = _hex_u32(raw[72:74])
        if char_id is None or status is None or default is None:
            return
        name = decode(raw[19:50]).rstrip()
        gra = decode(raw[54:69]).rstrip()
        if self._chara_clear_pending:
            self._map_chars = []
            self._chara_clear_pending = False
        magnify = next(
            (m for n, m in self._name_magnify if n == name), None
        )
        if len(self._map_chars) >= _MAX_MAP_CHARS:
            return
        self._map_chars.append(
            Chara(
                id=char_id, x=int(x_ch), y=int(y_ch), dir=chr(raw[17]),
                name=name, gra=gra, status=status, gigant=chr(raw[70]),
                layer=layer, default=default, magnify=magnify,
            )
        )

    def _finish_map(self) -> list[Event]:
        event = MapEvent(
            size=self._map_size,
            dir=self._map_dir,
            cells=list(self._map_cells) if self._map_cells is not None else [],
            chars=list(self._map_chars),
            style=self._map_style,
            pos=self._abs_pos,
        )
        self._abs_pos = None
        # chars は次フレームの最初の O 行が来るまで残す
        self._chara_clear_pending = True
        return [event]
