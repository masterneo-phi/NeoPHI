"""マップ上のマウスの位置から移動の向きを決めます。

wphi の ``ui/src/mouseDir.ts`` の移植です(Philly の MapForm.cpp)。
"""

from __future__ import annotations

import math
from dataclasses import dataclass

__all__ = ["MouseDir", "mouse_dir", "north_fix_turn"]

_PI_8 = math.pi / 8


@dataclass(frozen=True)
class MouseDir:
    """押した時に押したことにする移動キーと、その向きを示すカーソル名。"""

    keys: tuple[str, ...]
    cursor: str


def mouse_dir(
    x: float,
    y: float,
    w: float,
    h: float,
    north_fix: bool,
    shift_or_ctrl: bool,
) -> MouseDir | None:
    """マップの左上を原点にした ``(x, y)`` から向きを決めます。

    マップの中心と外は None です。回転マップでは、上の 50px の左右の端と、
    Shift か Ctrl を押している間の左右の半分が回転になります。
    """
    if x < 0 or x > w or y < 0 or y > h:
        return None
    dx = x - w / 2
    dy = y - h / 2
    if dx == 0 and dy == 0:
        return None
    turn_left = MouseDir(("7",), "w-resize")
    turn_right = MouseDir(("9",), "e-resize")
    if not north_fix and shift_or_ctrl:
        return turn_left if x < w / 2 else turn_right
    if not north_fix and y < 50:
        if x < 50:
            return turn_left
        if x > w - 50:
            return turn_right
    t = math.atan2(dy, dx)
    if t < -7 * _PI_8:
        return MouseDir(("4",), "w-resize")
    if t < -5 * _PI_8:
        return MouseDir(("8", "4"), "nw-resize")
    if t < -3 * _PI_8:
        return MouseDir(("8",), "n-resize")
    if t < -1 * _PI_8:
        return MouseDir(("8", "6"), "ne-resize")
    if t < 1 * _PI_8:
        return MouseDir(("6",), "e-resize")
    if t < 3 * _PI_8:
        return MouseDir(("2", "6"), "se-resize")
    if t < 5 * _PI_8:
        return MouseDir(("2",), "s-resize")
    if t < 7 * _PI_8:
        return MouseDir(("2", "4"), "sw-resize")
    return MouseDir(("4",), "w-resize")


def north_fix_turn(
    x: float, y: float, w: float, h: float
) -> str | None:
    """北固定で Shift か Ctrl を押しながらマウスを向けた時に向く方角。

    中心から縦横とも 20px 以内なら None です。
    """
    dx = x - w / 2
    dy = y - h / 2
    if abs(dx) <= 20 and abs(dy) <= 20:
        return None
    t = math.atan2(dy, dx)
    if t < (-3 * math.pi) / 4:
        return "w"
    if t < -math.pi / 4:
        return "n"
    if t < math.pi / 4:
        return "e"
    if t < (3 * math.pi) / 4:
        return "s"
    return "w"
