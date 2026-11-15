"""吹き出しの本文と折り返し、置く場所、輪郭。

発言の行から吹き出しに出す本文を抜き、幅に収まる行に分け、他の
吹き出しと重ならない場所を決め、角の丸い輪郭を作ります。NPCの
発言や action の行から、話し手と本文を抜くこともします。Tkinter
に頼らないので、テストで確かめられます。
"""

import math
import re

__all__ = [
    "bubble_body",
    "bubble_from_action_line",
    "bubble_from_log_line",
    "bubble_outline",
    "place_bubble_rect",
    "wrap_bubble_lines",
]


def bubble_body(text: str) -> str:
    """発言の行から本文だけを抜きます。

    talk の ``名前 > 本文`` と priv の ``[送り主] > 本文`` のどちらも、
    最初の ``> `` の後ろが本文です。本文に ``> `` があっても、最初の
    区切りだけを使います。
    """
    _, sep, body = text.partition("> ")
    if not sep:
        return ""
    return body.strip()


#: NPCや大声などの発言の形。名前は #user に無いので、logの行に来ます。
#: 通常 ``名前 > 本文``、大声 ``(名前) > 本文``、エリア ``{名前} > 本文``、
#: パーティ ``"名前" > 本文``。
_SPEECH = re.compile(
    r"^(?:\(([^)]+)\)|\{([^}]+)\}|\"([^\"]+)\"|([^>]+?)) > (.+)$"
)


def bubble_from_log_line(text: str, names) -> tuple[str, str] | None:
    """logの行から、地図に見えるキャラの発言を抜きます。

    ``text`` はタグを除いた後の行、``names`` は見えるキャラの名前です。
    話し手が ``names`` に無ければ、発言とは見なしません。
    """
    hit = _SPEECH.match(text.strip())
    if hit is None:
        return None
    name = next(group for group in hit.groups()[:4] if group is not None).strip()
    body = hit.group(5).strip()
    if name in names and body:
        return name, body
    return None


def bubble_from_action_line(text: str, names) -> tuple[str, str] | None:
    """action の行から、地図に見えるキャラの動作を抜きます。

    ``text`` はタグを除いた後の ``DM > 名前 本文`` の行です。名前は
    長いものから当てはめます(「案内」と「案内人」の取り違えを防ぎます)。
    """
    stripped = text.strip()
    if not stripped.startswith("DM > "):
        return None
    rest = stripped[5:]
    for name in sorted(names, key=len, reverse=True):
        if rest.startswith(name + " "):
            body = rest[len(name) + 1 :].strip()
            if body:
                return name, body
    return None


def wrap_bubble_lines(text, measure, max_width, max_lines=3):
    """本文を幅に収まる行に分けます。

    ``measure`` は文字列を受けて幅を返す関数です。1文字ずつ足して
    幅を超えたら改行します。行数が ``max_lines`` を超えたら、最後の
    行の末尾を ``…`` にして、はみ出した分がある事を示します。
    """
    if max_lines < 1 or not text.strip():
        return []
    lines = []
    for part in text.split("\n"):
        current = ""
        for ch in part:
            if current and measure(current + ch) > max_width:
                lines.append(current)
                current = ch
            else:
                current += ch
        if current or not part:
            lines.append(current)
    if len(lines) > max_lines:
        lines = lines[:max_lines]
        last = lines[-1]
        while last and measure(last + "…") > max_width:
            last = last[:-1]
        lines[-1] = last + "…"
    return lines


def place_bubble_rect(cx, tip_y, w, h, canvas_width, tail_h, occupied):
    """吹き出しの箱の場所を決めます。

    ``cx`` は話し手の頭の中心、``tip_y`` はしっぽの先の位置です。
    箱は頭の上に置き、左右は画面の中に収めます。他の吹き出しの箱
    (``occupied`` は ``(x0, y0, w, h)`` の並び)と重なれば、上へ
    ずらします。戻り値は ``(x0, y0, stacked)`` で、``stacked`` は
    上にずらしたかどうかです。
    """
    x0 = min(max(cx - w // 2, 0), max(canvas_width - w, 0))
    y0 = tip_y - tail_h - h
    if y0 < 0:
        y0 = 0
    stacked = False
    for _ in range(5):
        clash = None
        for ox0, oy0, ow, oh in occupied:
            if x0 < ox0 + ow and ox0 < x0 + w and y0 < oy0 + oh and oy0 < y0 + h:
                clash = (ox0, oy0, ow, oh)
                break
        if clash is None or y0 <= 0:
            break
        y0 = max(0, clash[1] - h - tail_h)
        stacked = True
    return x0, y0, stacked


def bubble_outline(x0, y0, x1, y1, radius, base_x, tail_w, tip_x, tip_y):
    """角の丸い吹き出しの輪郭を、点の並びで返します。

    箱の四隅を半径 ``radius`` の円弧にし、下の辺の途中にしっぽの
    三角を付けます。点は時計回りで、左上の円弧から始まります。
    箱が狭い時は、円弧が収まるよう半径を小さくします。
    """
    w = x1 - x0
    h = y1 - y0
    r = max(1, min(radius, w // 2 - tail_w - 1, h // 2 - 1))
    # しっぽの付け根は、下の辺の円弧の間に収めます
    right = min(max(base_x + tail_w, x0 + r), x1 - r)
    left = min(max(base_x - tail_w, x0 + r), x1 - r)
    if left > right:
        left = right
    tip_x = min(max(tip_x, x0), x1)

    def arc(cx, cy, start_deg):
        points = []
        for step in range(5):
            angle = math.radians(start_deg + 90 * step / 4)
            points.append((cx + r * math.cos(angle), cy + r * math.sin(angle)))
        return points

    points = []
    points.extend(arc(x0 + r, y0 + r, 180))  # 左上
    points.extend(arc(x1 - r, y0 + r, 270))  # 右上
    points.extend(arc(x1 - r, y1 - r, 0))  # 右下
    points.append((right, y1))
    points.append((tip_x, tip_y))
    points.append((left, y1))
    points.extend(arc(x0 + r, y1 - r, 90))  # 左下
    return points
