"""戦闘の演出のもとになる、ログの読み取りと形の計算。

攻撃の行から攻撃者と対象を抜き、詠唱の行を覚えて、物理攻撃か
魔法攻撃かを見分けます。剣の軌跡の形もここで作ります。Tkinter
に頼らないので、テストで確かめられます。
"""

from __future__ import annotations

import math
import re
from dataclasses import dataclass

__all__ = [
    "CasterTracker",
    "CombatEvent",
    "comet_tail_points",
    "parse_attack",
    "parse_chant",
    "parse_chant_stop",
    "parse_kill",
    "radial_spark_points",
    "slash_points",
    "streak_points",
]


@dataclass(frozen=True)
class CombatEvent:
    """攻撃1回。"""

    attacker: str
    target: str
    weapon: str  # 武器か魔法の名前


_NUM = r"([\d,]+)"
# 名前は、文の区切りと、行頭の「DM > 」の区切りを含まない範囲にします
# (float_text.py と同じ決め方です)。
_NAME = r"([^\s。！!、,\n>][^。！!、,\n>]*?)"

#: 全角の数字とカンマを半角にそろえます。
_FULLWIDTH = str.maketrans("０１２３４５６７８９，", "0123456789,")


def _normalize(text: str) -> str:
    return text.translate(_FULLWIDTH)


#: 攻撃: 「X は Y を W で攻撃した. [N hp]」または「[N mp]」
_ATTACK = re.compile(
    _NAME + r" は " + _NAME + r" を (.+?)で攻撃した\. \[" + _NUM + r" (?:hp|mp)\]"
)
#: 詠唱: 「X は魔法を唱えている...」「X は力を集中している...」
_CHANT = re.compile(_NAME + r" は(?:魔法を唱えている|力を集中している)")
#: 詠唱の中止と失敗: 名前が無いので、自分だけのものとして扱います
_CHANT_STOP = re.compile(r"詠唱を止めました|詠唱は完了しなかった")


def parse_attack(text: str) -> CombatEvent | None:
    """攻撃の行から、攻撃者・対象・武器(魔法名)を抜きます。"""
    hit = _ATTACK.search(_normalize(text))
    if hit is None:
        return None
    attacker = hit.group(1).strip()
    target = hit.group(2).strip()
    weapon = hit.group(3).strip()
    if not attacker or not target:
        return None
    return CombatEvent(attacker=attacker, target=target, weapon=weapon)


def parse_chant(text: str) -> str | None:
    """詠唱を始めた行から、唱えた人の名前を抜きます。"""
    hit = _CHANT.search(text)
    if hit is None:
        return None
    name = hit.group(1).strip()
    return name or None


def parse_chant_stop(text: str) -> bool:
    """詠唱を止めた・失敗した行かどうかを返します。"""
    return _CHANT_STOP.search(text) is not None


#: 他殺の行(DMM_KILL_BY_OTHER / DMM_KILL_BY_PK)。PK版はタグを除くと同形です。
_KILL_BY_OTHER_RE = re.compile(r"^DM > ([^>\s][^>]*?) は .+? に殺された\.")
#: 自殺の行(DMM_KILL_SELF)。「X は 毒で死んだ.」の形です。
_KILL_SELF_RE = re.compile(r"^DM > ([^>\s][^>]*?) は .+で死んだ\.")
#: 自分の死亡の行(DMM_DEAD)。
_DEAD_SELF_RE = re.compile(r"^DM > あなたは死にました")


def parse_kill(text: str) -> str | None:
    """死亡の行から、倒れた人の名前を返します。

    自分の死亡の行は、名前の代わりに ``あなた`` を返します。
    """
    stripped = text.strip()
    if _DEAD_SELF_RE.match(stripped):
        return "あなた"
    hit = _KILL_BY_OTHER_RE.match(stripped)
    if hit is not None:
        return hit.group(1).strip()
    hit = _KILL_SELF_RE.match(stripped)
    if hit is not None:
        return hit.group(1).strip()
    return None


class CasterTracker:
    """詠唱を始めた人を、しばらく覚えておきます。

    攻撃の行が来た時、唱えたばかりの人なら魔法攻撃と分かります。
    """

    def __init__(self, window: float = 5.0):
        self._window = window
        self._noted: dict[str, float] = {}

    def note(self, name: str, now: float) -> None:
        """詠唱を始めたことを覚えます。古い記録は捨てます。"""
        self._noted = {
            n: t for n, t in self._noted.items() if now - t <= self._window
        }
        self._noted[name] = now

    def clear(self, name: str | None) -> None:
        """その人の詠唱の記録を消します。"""
        if name is not None:
            self._noted.pop(name, None)

    def consume(self, name: str, now: float) -> bool:
        """唱えたばかりなら True を返し、記録を使い切ります。"""
        noted = self._noted.pop(name, None)
        if noted is None:
            return False
        return now - noted <= self._window


def slash_points(cx: float, cy: float, z: float, scale: float = 1.0) -> list[float]:
    """剣の軌跡の多角形を、座標の平らな並びで返します。

    右上から左下へ、少し弓なりに曲がり、先へいくほど細くなる形です。
    ``(cx, cy)`` は対象の中心、``z`` は拡大率です。
    """
    # 対角線の方向と、その垂直方向
    dx, dy = -32.0, 36.0
    length = math.hypot(dx, dy)
    nx, ny = -dy / length, dx / length
    left: list[tuple[float, float]] = []
    right: list[tuple[float, float]] = []
    steps = 6
    for i in range(steps + 1):
        t = i / steps
        # 中心線: 右上から左下へ
        x = 16.0 - 32.0 * t
        y = -18.0 + 36.0 * t
        # 弓なり
        bow = math.sin(math.pi * t) * 4.0
        x += nx * bow
        y += ny * bow
        # 先へいくほど細く
        half = (6.0 * (1.0 - t) + 1.5) / 2.0
        left.append((cx + (x + nx * half) * z * scale,
                     cy + (y + ny * half) * z * scale))
        right.append((cx + (x - nx * half) * z * scale,
                      cy + (y - ny * half) * z * scale))
    points = left + right[::-1]
    return [coord for point in points for coord in point]


def streak_points(cx, cy, z, radius, start_rad, end_rad, thickness):
    """風切りの線を、座標の平らな並びで返します。

    ``radius`` の円弧に沿う、両端の細い線です。真ん中が一番太く、
    両端へ向けて細くなります。角度の決め方は、0が右・正が下向きです。
    """
    span = abs(end_rad - start_rad)
    steps = max(2, int(span / 0.12))
    outer = []
    inner = []
    for i in range(steps + 1):
        u = i / steps
        angle = start_rad + (end_rad - start_rad) * u
        half = thickness * z * 0.5 * math.sin(math.pi * u)
        cos_a = math.cos(angle)
        sin_a = math.sin(angle)
        outer.append((cx + (radius * z + half) * cos_a,
                      cy + (radius * z + half) * sin_a))
        inner.append((cx + (radius * z - half) * cos_a,
                      cy + (radius * z - half) * sin_a))
    points = outer + inner[::-1]
    return [coord for point in points for coord in point]


def comet_tail_points(hx, hy, tx, ty, z, head_width):
    """彗星の尾を、座標の平らな並びで返します。

    ``(hx, hy)`` が頭、``(tx, ty)`` が尾の先です。頭が太く、
    尾の先へ向けて細くなる三角形です。
    """
    dx, dy = tx - hx, ty - hy
    length = math.hypot(dx, dy)
    if length < 1e-6:
        return [hx, hy, hx, hy, hx, hy]
    nx, ny = -dy / length, dx / length
    half = head_width * z * 0.5
    return [hx + half * nx, hy + half * ny,
            tx, ty,
            hx - half * nx, hy - half * ny]


def radial_spark_points(cx, cy, z, angle_rad, length, half_width):
    """放射状の火花を、座標の平らな並びで返します。

    中心から ``angle_rad`` の向きへ伸びる、両端の細いひし形です。
    角度の決め方は :func:`streak_points` と同じです。
    """
    dx, dy = math.cos(angle_rad), math.sin(angle_rad)
    nx, ny = -dy, dx
    mid = 0.45
    mx = cx + length * z * mid * dx
    my = cy + length * z * mid * dy
    tip_x = cx + length * z * dx
    tip_y = cy + length * z * dy
    return [cx, cy,
            mx + half_width * z * nx, my + half_width * z * ny,
            tip_x, tip_y,
            mx - half_width * z * nx, my - half_width * z * ny]
