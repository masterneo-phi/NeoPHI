"""PHI サーバのモック。テストと手元の動作確認用。実サーバではない。

cp932・改行区切りの行プロトコルで、ログイン・移動・リスト・看板・EagleEye
の返事をする。``hit`` には実サーバと同じ形のダメージ付き戦闘ログを返す
(練習相手のモック猫が正面にいる。3回に1回は反撃し、3回目の反撃は
MP ダメージ。10回に1回は猫が倒れ、次の hit か移動で生き返る)。``cast`` の一覧には harm
(詠唱＋魔法の攻撃行)・cure（回復）・mana（MP回復）を追加。発言は
``/**/モック太郎 > 本文`` の形で送り返し、3回に1回は案内人が返事をする。
``priv`` と入れると案内人から priv が来る。受けた行を ``received`` に
残す。キャラ ID は画面に出さない。

回転マップ(``#ex-map style=turn``)にも対応する。実サーバ
(``phi_m57.c`` の ``set_view7`` / ``print_m57``)と同じ規則で、turn の間は
向きが上になるよう 7x7 の窓を取り直し(前4・後2、自キャラは画面の
(3,4))、キャラの座標と向きコード(``BRFL`` をカメラ方向で回す)も
変換する。ログイン時に ``style=turn`` を送られた場合も最初の地図から
回転する。受け付けない style には実サーバと同じく ``#ex-map style=no``
と返す。5x5 地図は従来どおり回転しない(実サーバの 5x5 は常に向き
基準だが、モックの 5x5 は元々簡略化してある)。

使い方::

    python tools/mock_server.py --port 21000

看板(``read``)の本文には、わざと ``#ch-srv`` や ``#x`` の行を入れてある。
正しいクライアントは ``#more`` の間はこれらをコマンドとして実行しない。
"""

from __future__ import annotations

import argparse
import asyncio
import sys


def _pad_cp932(text: str, width: int) -> bytes:
    """cp932 で ``width`` バイトに切り、空白で埋める。文字の途中で切らない。"""
    out = bytearray()
    for ch in text:
        encoded = ch.encode("cp932", errors="replace")
        if len(out) + len(encoded) > width:
            break
        out.extend(encoded)
    out.extend(b" " * (width - len(out)))
    return bytes(out)


def build_m57_m(dir_char: str, cells: list[tuple[int, int]]) -> bytes:
    """``#m57 M`` の1行。cells は (chip, attr) が49個。"""
    header = b"#m57 M " + dir_char.encode("ascii") + b" 00000000:"
    assert len(header) == 18
    body = b"".join(bytes([chip, attr]) for chip, attr in cells)
    assert len(body) == 98
    return header + body


def build_m57_o(
    *,
    layer: int,
    char_id: int,
    x: int,
    y: int,
    dir_char: str,
    name: str,
    gra: str,
    status: int,
    gigant: str,
    default: int,
) -> bytes:
    """``#m57 O`` の1行(74バイト)。固定位置の欄に合わせる。"""
    line = (
        b"#m57 O "
        + f"{layer:X}".encode("ascii")
        + f"{char_id:04X}".encode("ascii")
        + b":"
        + str(x).encode("ascii")
        + b" "
        + str(y).encode("ascii")
        + b" "
        + dir_char.encode("ascii")
        + b" "
        + _pad_cp932(name, 31)
        + b" "
        + f"{status:02X}".encode("ascii")
        + b" "
        + _pad_cp932(gra, 15)
        + b" "
        + gigant.encode("ascii")
        + b" "
        + f"{default:02X}".encode("ascii")
    )
    assert len(line) == 74, len(line)
    return line


def build_m57_w(first: bytes, second: bytes) -> bytes:
    """``#m57 W`` の1行(142バイト)。O の行の形が2つ続く。"""
    return b"#m57 W " + first[7:74] + b" " + second[7:74]


def build_map_m_5x5(
    dir_char: str, chips: list[int], items: set[int], boards: set[int]
) -> bytes:
    """``#map M`` の1行(138バイト)。"""
    header = b"#map M " + dir_char.encode("ascii") + b" 000000000"
    assert len(header) == 18
    region = bytearray(b"\x00" * 50)
    for i, chip in enumerate(chips):
        region[i * 2] = chip
    flags = bytearray(b" " * 70)
    for i in items:
        flags[i * 2] = ord(".")
    for i in boards:
        flags[i * 2 + 1] = ord("-")
    return header + bytes(region) + bytes(flags)


def build_eagleeye_row(size: int, y: int, cells: list[tuple[int, int]]) -> bytes:
    """``#ex-eagleeye M`` の1行。幅は ``size + 1``。"""
    header = f"#ex-eagleeye M {size:02d} {y:02d} ".encode("ascii")
    assert len(header) == 21
    body = b"".join(bytes([chip, attr]) for chip, attr in cells)
    return header + body


def _terrain(world_x: int, world_y: int) -> tuple[int, int]:
    """絶対座標から地形を決める。決まった模様を返すだけ。"""
    if (world_x + world_y) % 11 == 0:
        return ord("#"), 0
    if (world_x * 3 + world_y) % 7 == 0:
        return ord("T"), 0
    if (world_x + world_y * 2) % 9 == 0:
        return ord("_"), 0
    if world_x % 5 == 0 and world_y % 5 == 0:
        return ord(":"), 0
    if (world_x, world_y) == (12, 10):
        return ord(" "), 0x08  # 看板
    if (world_x, world_y) == (11, 11):
        return ord(" "), 0x20  # アイテム2番
    return ord(" "), 0


_DIR_CHARS = "NESW"
_DIR_VECTORS = [(0, -1), (1, 0), (0, 1), (-1, 0)]

# 実サーバの px[] / py[](方向 0=N 1=E 2=S 3=W の単位ベクトル)。
# 回転マップの座標変換に使う。
_PX = (0, 1, 0, -1)
_PY = (-1, 0, 1, 0)
# 向きコード。``(キャラの絶対方向 - カメラ方向) % 4`` の位置の文字で、
# 0=後ろ姿(B) 1=右向き(R) 2=正面(F) 3=左向き(L)。
_RDC = "BRFL"

# モックがコマンドとして扱う言葉。ここに無い行は発言として送り返す。
# アクションキーで送られる1語が、吹き出しの発言にならないようにする。
_COMMAND_WORDS = frozenset({
    "board", "erase", "floor item", "hi", "n", "equip", "spells",
    "sort", "y", ".", "1", "2", "3", "4", "5", "6", "7", "8", "9",
})


class MockServer:
    """1つの接続を受けて、決まった返事をするモックサーバ。"""

    def __init__(self, host: str = "127.0.0.1", port: int = 21000) -> None:
        self.host = host
        self.port = port
        self.received: list[str] = []
        self.lag_ok = False
        self._server: asyncio.AbstractServer | None = None
        self._abs_x = 10
        self._abs_y = 10
        self._dir = 0  # 0=N 1=E 2=S 3=W
        self._map_size = 7
        self._map_style = "solid"
        self._pending_list: str | None = None
        self._board_mode = False
        self._board_lines: list[str] = []
        self._hit_count = 0
        self._speech_count = 0
        self._spell_count = 0
        self._cat_dead = False

    async def start(self) -> None:
        self._server = await asyncio.start_server(
            self._handle, self.host, self.port
        )

    async def stop(self) -> None:
        if self._server is not None:
            self._server.close()
            await self._server.wait_closed()

    @property
    def address(self) -> tuple[str, int]:
        if self._server and self._server.sockets:
            sock = self._server.sockets[0]
            addr = sock.getsockname()
            return str(addr[0]), int(addr[1])
        return self.host, self.port

    async def _handle(
        self, reader: asyncio.StreamReader, writer: asyncio.StreamWriter
    ) -> None:
        async def send_text(text: str) -> None:
            writer.write(text.encode("cp932", errors="replace") + b"\n")
            await writer.drain()

        async def send_raw(data: bytes) -> None:
            writer.write(data + b"\n")
            await writer.drain()

        async def send_user(number: int, name: str) -> None:
            # raw[6..10]=番号、raw[11..42]=31バイトの名前
            await send_raw(
                b"#user " + f"{number:04d} ".encode("ascii") + _pad_cp932(name, 31)
            )

        async def send_map(include_cat: bool = True) -> None:
            if include_cat:
                # 猫のいる地図を送ったら、猫は生き返ったことにする
                self._cat_dead = False
            await send_text(f"#ex-pos {self._abs_x} {self._abs_y}")
            if self._map_size == 5:
                chips: list[int] = []
                items: set[int] = set()
                boards: set[int] = set()
                for yy in range(5):
                    for xx in range(5):
                        chip, attr = _terrain(
                            self._abs_x + xx - 2, self._abs_y + yy - 2
                        )
                        chips.append(chip)
                        if attr & 0x08:
                            boards.add(yy * 5 + xx)
                        if (attr & 0x70) >> 4:
                            items.add(yy * 5 + xx)
                await send_raw(
                    build_map_m_5x5(_DIR_CHARS[self._dir], chips, items, boards)
                )
                await send_text("#map .")
                return
            turn = self._map_style == "turn"
            cam = self._dir
            cells: list[tuple[int, int]] = []
            if turn:
                # 回転マップ。画面の (wx, wy) は、右を vx・前を vy とする
                # オフセット (vx, 4 - wy) に対応する。実サーバの式で
                # 絶対座標へ回す。窓は前4・後2になる。
                for wy in range(7):
                    for wx in range(7):
                        vx, vy = wx - 3, 4 - wy
                        dx = _PX[cam] * vy - _PY[cam] * vx
                        dy = _PY[cam] * vy + _PX[cam] * vx
                        cells.append(
                            _terrain(self._abs_x + dx, self._abs_y + dy)
                        )
            else:
                for yy in range(7):
                    for xx in range(7):
                        cells.append(
                            _terrain(self._abs_x + xx - 3, self._abs_y + yy - 3)
                        )
            await send_raw(build_m57_m(_DIR_CHARS[self._dir], cells))
            # 自キャラは solid で (3, 3)、turn で (3, 4)。向きコードは
            # 両 style とも "B"(turn では自分がカメラなので、実サーバ
            # でも (自分の向き - カメラ) = 0 で B になる)。
            me_x, me_y = (3, 4) if turn else (3, 3)
            me = build_m57_o(
                layer=0, char_id=1, x=me_x, y=me_y, dir_char="B",
                name="モック太郎", gra="t_Lord", status=0x40,
                gigant="#", default=0x40,
            )
            npc_x, npc_y, npc_dir = self._chara_wire(1, 0, "L")
            npc = build_m57_o(
                layer=1, char_id=0x2A, x=npc_x, y=npc_y, dir_char=npc_dir,
                name="案内人", gra="t_Residents", status=0,
                gigant="#", default=0x05,
            )
            await send_raw(build_m57_w(me, npc))
            if include_cat:
                # 練習相手のモック猫。正面(北)に置く。hit の対象になる。
                cat_x, cat_y, cat_dir = self._chara_wire(0, -1, "F")
                cat = build_m57_o(
                    layer=2, char_id=0x2B, x=cat_x, y=cat_y, dir_char=cat_dir,
                    name="モック猫", gra="t_catW", status=0,
                    gigant="#", default=0x05,
                )
                await send_raw(cat)
            await send_text("#m57 .")

        async def send_status() -> None:
            await send_text(
                "#status モック太郎 : 100 : 100 : 50 : 50 : 1234 : 567 : 10 : 11 : 12 : 13"
            )
            await send_text("#cond -------")

        # ログインの行を読み、#open を確かめる(値は出さない)
        got_open = False
        for _ in range(20):
            raw = await reader.readline()
            if not raw:
                writer.close()
                return
            line = raw.rstrip(b"\r\n").decode("cp932", errors="replace")
            if line.startswith("#open "):
                got_open = True
                self.received.append("#open <ID>")
            else:
                self.received.append(line)
            if line.startswith("#ex-map style="):
                # ログイン時の style 指定も受け付ける(実サーバは
                # 最初の地図からその style で送る)
                value = line.split("=", 1)[1]
                if value in ("turn", "solid"):
                    self._map_style = value
            if line.startswith("#ex-switch ex-abspos"):
                break
        if not got_open:
            writer.close()
            return

        await send_text("#name モック太郎")
        await send_status()
        await send_text("#ex-notice land=モックの世界")
        await send_text("#ex-notice area=モックの酒場")
        await send_text("#mapset default")
        await send_user(12, "モック太郎")
        await send_user(3, "案内人")
        await send_text("DM > モックサーバへようこそ。")
        await send_map()
        await send_text("#lag")

        while True:
            raw = await reader.readline()
            if not raw:
                break
            line = raw.rstrip(b"\r\n").decode("cp932", errors="replace")
            if line.startswith("#open "):
                self.received.append("#open <ID>")
                continue
            self.received.append(line)

            if self._board_mode:
                if line == ".":
                    self._board_mode = False
                    await send_text("#.")
                    await send_text("DM > 看板に書きました。")
                elif line == ".!":
                    self._board_mode = False
                    await send_text("#.")
                    await send_text("DM > 看板をやめました。")
                else:
                    self._board_lines.append(line)
                continue

            if line == "#end-lag":
                self.lag_ok = True
                continue
            if line == "#x":
                break
            if line == "#code-sjis":
                await send_text("#code-sjis-ok")
                continue
            if line == "#map":
                await send_map()
                continue
            if line == "#ulist":
                await send_user(12, "モック太郎")
                await send_user(3, "案内人")
                continue
            if line.startswith("#ex-map style="):
                value = line.split("=", 1)[1]
                if value in ("turn", "solid"):
                    self._map_style = value
                    await send_text(f"#ex-map style={value}")
                    await send_map()
                else:
                    # 実サーバは受け付けない style には no と返し、
                    # 地図は送り直さない
                    await send_text("#ex-map style=no")
                continue
            if line.startswith("#ex-map size="):
                self._map_size = 7 if "57" in line else 5
                await send_map()
                continue
            if line.startswith("#ex-switch"):
                continue
            if line == "MOCK_CH_SRV":
                await send_text("#ch-srv 127.0.0.1 29999")
                continue
            if line == "#no-srv":
                await send_text("DM > 留まりました。")
                continue

            if self._pending_list == "unequip":
                self._pending_list = None
                # "1" で1番の武器を外す、"." でやめる。どちらも返事は要らない
                continue
            if self._pending_list in ("items_get", "items_put", "items_use"):
                verb = {
                    "items_get": "拾いました",
                    "items_put": "置きました",
                    "items_use": "使いました",
                }[self._pending_list]
                self._pending_list = None
                if line == ".":
                    await send_text("DM > やめました。")
                else:
                    await send_text(f"DM > {line} 番を{verb}。")
                continue
            if self._pending_list == "spells":
                self._pending_list = None
                # 番号でも名前でも選べる。実サーバは両方を受け付ける。
                name = {
                    "1": "wizard eye", "2": "eagle eye", "3": "harm",
                    "4": "cure", "5": "mana",
                }.get(line, line)
                if name == "eagle eye":
                    await send_text("#ex-eagleeye start")
                    await send_raw(
                        build_eagleeye_row(4, 0, [(ord(" "), 0)] * 5)
                    )
                    await send_raw(
                        build_eagleeye_row(
                            4, 1, [(ord(" "), 0), (ord("#"), 0), (ord(" "), 0x58),
                                   (ord(" "), 0), (ord("T"), 0)]
                        )
                    )
                    await send_raw(
                        build_eagleeye_row(4, 2, [(ord("_"), 0)] * 5)
                    )
                    await send_text("#ex-eagleeye pos 2 1")
                    await send_text("#ex-eagleeye end")
                elif name == "harm":
                    # 詠唱の行の直後に魔法の攻撃行。クライアントは
                    # 詠唱を覚えていて、魔法弾と着弾の演出を出す。
                    self._spell_count += 1
                    damage = (12, 15, 11, 14, 13)[(self._spell_count - 1) % 5]
                    await send_text("DM > モック太郎 は魔法を唱えている...")
                    await send_text(
                        "DM > モック太郎 は モック猫 を Harm で攻撃した."
                        f" [{damage} hp]"
                    )
                elif name == "cure":
                    self._spell_count += 1
                    amount = (40, 35, 45)[(self._spell_count - 1) % 3]
                    await send_text(
                        "DM > モック太郎 が Cure によって回復した."
                        f" [{amount} hp]"
                    )
                elif name == "mana":
                    self._spell_count += 1
                    amount = (20, 25, 18)[(self._spell_count - 1) % 3]
                    await send_text(f"DM > モック太郎 は {amount} mp 回復した.")
                else:
                    await send_text(f"DM > {name} を唱えた。")
                continue

            if line == "unequip":
                # v5y の装備のリストと同じ形。1番は武器
                self._pending_list = "unequip"
                await send_text("#list")
                await send_text(
                    "     [/*color=cyan*/ 1/*.*/] ロングソード"
                    "                    Wp  :  5 [/*color=red*/Wpn/*.*/]"
                )
                await send_text("#end-list")
                await send_text("外す装備を選択して下さい")
                continue
            if line in ("get", "put", "use"):
                self._pending_list = "items_" + line
                await send_text("#list")
                await send_text("[ 1] 木の剣")
                await send_text("[ 2] 革の盾")
                await send_text("[ 3] 薬草")
                await send_text("#end-list")
                await send_text("DM > 選んで下さい.")
                continue
            if line == "cast":
                self._pending_list = "spells"
                await send_text("#list")
                await send_text("[ 1] wizard eye")
                await send_text("[ 2] eagle eye")
                await send_text("[ 3] harm")
                await send_text("[ 4] cure")
                await send_text("[ 5] mana")
                await send_text("#end-list")
                await send_text("DM > 魔法を選んで下さい.")
                continue
            if line == "hit":
                # 実サーバと同じ形の戦闘ログを返す。ダメージの数字は
                # 決まった順で回し、3回に1回はモック猫が反撃する
                # （3回目の反撃は MP ダメージ）。10回に1回は猫が
                # 倒れ、次の hit で生き返る（猫がいないと数字も
                # 斬撃も出る場所が無くなるため）。
                # クライアントはこの行から浮き数字と斬撃を出す。
                if self._cat_dead:
                    self._cat_dead = False
                    await send_text("DM > モック猫 が生き返った。")
                    await send_map()
                self._hit_count += 1
                damage = (6, 8, 5, 9, 7)[(self._hit_count - 1) % 5]
                await send_text("#attack")
                await send_text(
                    "DM > モック太郎 は モック猫 を 拳 で攻撃した."
                    f" [{damage} hp]"
                )
                if self._hit_count % 3 == 0:
                    counter, unit = ((3, "hp"), (5, "hp"), (4, "mp"))[
                        (self._hit_count // 3 - 1) % 3
                    ]
                    await send_text(
                        "DM > モック猫 は モック太郎 を Fang で攻撃した."
                        f" [{counter} {unit}]"
                    )
                killed = self._hit_count % 10 == 0
                if killed:
                    self._cat_dead = True
                    await send_text("DM > モック猫 は モック太郎 に殺された.")
                await send_text("#end-at")
                if killed:
                    # 倒れた猫のいない地図を送る。クライアントは直前の
                    # 地図から残像を作って薄く消す。次の地図では猫は戻る。
                    await send_map(include_cat=False)
                continue
            if line in ("check", "look", "see"):
                await send_status()
                await send_map()
                continue
            if line == "write":
                self._board_mode = True
                self._board_lines = []
                await send_text("#m-edit")
                continue
            if line == "read":
                await send_text("#more")
                await send_text("看板の本文です。")
                await send_text("#ch-srv 192.0.2.1 9000")
                await send_text("#x")
                await send_text("#end-more")
                continue
            if line.startswith("go ") or line == "go" or line.startswith("turn "):
                self._apply_move(line)
                await send_map()
                continue
            if line == "priv" or line.startswith("priv "):
                # 案内人からの priv。クライアントは [priv] として出し、
                # 案内人の頭の上に吹き出しも出す。
                await send_text("[案内人] > ひそひそ… ようこそ、モック太郎。")
                continue
            if line.startswith("#"):
                continue
            if line in _COMMAND_WORDS:
                # ゲームのコマンドは実行したことにする
                await send_text("DM > 受けました。")
                continue
            # 発言は実サーバと同じ形で送り返す。自分の発言も talk として
            # 届き、クライアントは話し手の頭の上に吹き出しを出す。
            # 3回に1回は案内人が返事をする。
            await send_text(f"/**/モック太郎 > {line}")
            self._speech_count += 1
            if self._speech_count % 3 == 0:
                reply = ("いらっしゃい。", "今日はいい天気だね。",
                         "猫と遊んでいきなよ。")[
                    (self._speech_count // 3 - 1) % 3
                ]
                await send_text(f"/**/案内人 > {reply}")

        writer.close()
        try:
            await writer.wait_closed()
        except OSError:
            pass

    def _chara_wire(self, dx: int, dy: int, solid_code: str) -> tuple[int, int, str]:
        """NPC の画面座標と向きコードを、現在の style で返す。

        ``(dx, dy)`` は自キャラからの絶対オフセット、``solid_code`` は
        solid(カメラ=北)の時の向きコード。solid ではそのまま
        ``(dx + 3, dy + 3, solid_code)``。turn では実サーバと同じく、
        オフセットをカメラ(=自分の向き)基準に回して自キャラが
        (3, 4) になる位置に置き、向きコードは絶対方向
        (solid はカメラが北なので ``_RDC`` の位置がそのまま絶対方向)
        からカメラ方向を引いて回す。自キャラ自身には使わない
        (自キャラの向きコードは両 style とも "B" で固定)。
        """
        if self._map_style != "turn":
            return dx + 3, dy + 3, solid_code
        cam = self._dir
        vx = -_PY[cam] * dx + _PX[cam] * dy
        vy = _PX[cam] * dx + _PY[cam] * dy
        abs_dir = _RDC.index(solid_code)
        return vx + 3, 4 - vy, _RDC[(abs_dir - cam) % 4]

    def _apply_move(self, line: str) -> None:
        if line == "go":
            arg = ""
        elif line.startswith("go "):
            arg = line[3:]
        else:
            arg = line[5:]
        if line.startswith("turn "):
            if arg == "b":
                self._dir = (self._dir + 2) % 4
            elif arg == "l":
                self._dir = (self._dir - 1) % 4
            elif arg == "r":
                self._dir = (self._dir + 1) % 4
            elif arg in ("n", "s", "w", "e"):
                self._dir = {"n": 0, "e": 1, "s": 2, "w": 3}[arg]
            return
        # go
        if arg in ("N", "S", "E", "W"):
            self._dir = {"N": 0, "E": 1, "S": 2, "W": 3}[arg]
            dx, dy = _DIR_VECTORS[self._dir]
        elif arg in ("n", "s", "e", "w"):
            facing = {"n": 0, "e": 1, "s": 2, "w": 3}[arg]
            dx, dy = _DIR_VECTORS[facing]
        elif arg == "b":
            dx, dy = _DIR_VECTORS[(self._dir + 2) % 4]
        elif arg == "l":
            dx, dy = _DIR_VECTORS[(self._dir - 1) % 4]
        elif arg == "r":
            dx, dy = _DIR_VECTORS[(self._dir + 1) % 4]
        else:
            dx, dy = _DIR_VECTORS[self._dir]
        # 壁・木・水は通れない（本物のサーバと同じ）。向きだけ変わる。
        chip, _attr = _terrain(self._abs_x + dx, self._abs_y + dy)
        if chip in (ord("#"), ord("T"), ord("_")):
            return
        self._abs_x += dx
        self._abs_y += dy


async def _amain(host: str, port: int) -> None:
    server = MockServer(host, port)
    await server.start()
    addr = server.address
    print(f"モックサーバ: {addr[0]}:{addr[1]} で待っています。Ctrl+C で止めます。", flush=True)
    try:
        while True:
            await asyncio.sleep(3600)
    except asyncio.CancelledError:
        pass
    finally:
        await server.stop()


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="PHI サーバのモック")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=21000)
    args = parser.parse_args(argv)
    try:
        asyncio.run(_amain(args.host, args.port))
    except KeyboardInterrupt:
        pass
    return 0


if __name__ == "__main__":
    sys.exit(main())
