"""3Dレンダラの試作。BMP の絵を3Dの面に貼って描きます。

クオータービューは絵を2Dで歪ませるので崩れましたが、こちらは絵を
歪ませません。床・壁・キャラを3Dの形にし、透視投影で写すので、絵は
質感としてそのまま残ります。描画は純粋な Python のソフトウェア処理で、
1枚の描画に数秒かかります。静止画の試し用で、動かす画面には向きません。

世界の向き: x は列(東)、y は行の逆向き(北が +y)、z は上です。
1マスが 1x1 です。カメラは地図の南側から見ます
(方位角 0 度が南、90 度が東)。

形の作り方は2つあります。``boxes`` は、背の高いチップを高さ 0.5 の
箱にして、絵を面に貼ります。``extrude`` は、絵の輪郭をそのまま厚みの
ある立体物に押し出します。前と後ろは絵そのもの、側面は輪郭の画素の
色になるので、どの角度から見ても絵の形のままです。壁や家は箱、扉は
壁の厚みの中央に来る板で、扉のマスの床は地面の絵にします。宝箱は
上の蓋が開いた形、開いている箱は開口のある箱形、岩はすぼまった
岩形にします。キャラは元の絵をカメラの方へ向けた板のままにします。
"""

from __future__ import annotations

import math
from dataclasses import dataclass

from .bmp import RgbaImage
from .map_graphics import (
    CHARA_H,
    EAGLE_EYE_ITEM_CHIP,
    FALLBACK_CHIP_COLORS,
    FALLBACK_CHIP_DEFAULT,
    ITEM_SPRITE_SIZE,
    Label,
    Placeholder,
    RenderedMap,
    arrange_row,
    board_chip_index,
    build_water_grid,
    chara_src_rect,
    chip_quarter_src_rect,
    chip_src_rect,
    has_board,
    has_item,
    item_no,
    water_quarter_chip,
    water_quarter_patterns,
)
from .map_text import chip_indices
from .parser import Cell, Chara
from .tags import strip_tags

__all__ = ["Camera", "render_3d_image"]


@dataclass(frozen=True)
class Camera:
    """カメラの位置と画角。"""

    azimuth: float = 0.0  # 度。0 が南、90 が東、180 が北
    elevation: float = 38.0  # 度。水平から見上げる角度
    distance: float = 8.5  # 地図の中心からの距離(マス単位)
    fov: float = 45.0  # 度。縦の画角
    width: int = 320
    height: int = 240

    def clamped(self) -> "Camera":
        elevation = min(max(self.elevation, 5.0), 85.0)
        distance = max(self.distance, 1.0)
        fov = min(max(self.fov, 10.0), 120.0)
        if (elevation, distance, fov) == (self.elevation, self.distance, self.fov):
            return self
        return Camera(self.azimuth, elevation, distance, fov, self.width, self.height)


# 壁の高さ(マス単位)。チップの高さ 16px / 32px です
_WALL_H = 0.5
# 手前すぎる頂点の切り捨て。カメラの近くの面が裏返るのを防ぎます
_NEAR = 0.05
# 面の明るさ(256 がそのまま)。向きで変えて、形が読めるようにします
_BRIGHT_FLOOR = 256
_BRIGHT_TOP = 256
_BRIGHT_SOUTH = 240
_BRIGHT_NORTH = 205
_BRIGHT_SIDE = 215
_BRIGHT_BOARD = 256
_BRIGHT_ITEM = 256
_BRIGHT_CHARA = 256
# 空の色(上)と地平線の色(下)
_SKY_TOP = (28, 40, 68)
_SKY_BOTTOM = (8, 10, 18)
# 地図の外の地面の色
_GROUND_COLOR = (22, 30, 20)


def _norm(v: tuple[float, float, float]) -> tuple[float, float, float]:
    size = math.sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2])
    if size == 0:
        return (0.0, 0.0, 0.0)
    return (v[0] / size, v[1] / size, v[2] / size)


def _cross(a, b):
    return (
        a[1] * b[2] - a[2] * b[1],
        a[2] * b[0] - a[0] * b[2],
        a[0] * b[1] - a[1] * b[0],
    )


def _camera_basis(camera: Camera, dim: int):
    """(位置, 右向き, 上向き, 前向き, 焦点距離, 中心x, 中心y)を返します。"""
    camera = camera.clamped()
    target = (dim / 2, -dim / 2, 0.0)
    el = math.radians(camera.elevation)
    az = math.radians(camera.azimuth)
    d = camera.distance
    offset = (
        d * math.cos(el) * math.sin(az),
        -d * math.cos(el) * math.cos(az),
        d * math.sin(el),
    )
    pos = (target[0] + offset[0], target[1] + offset[1], target[2] + offset[2])
    backward = _norm((pos[0] - target[0], pos[1] - target[1], pos[2] - target[2]))
    right = _norm(_cross((0.0, 0.0, 1.0), backward))
    up = _cross(backward, right)
    forward = (-backward[0], -backward[1], -backward[2])
    focal = (camera.height / 2) / math.tan(math.radians(camera.fov) / 2)
    return pos, right, up, forward, focal, camera.width / 2, camera.height / 2


def _project(point, pos, right, up, forward, focal, cx, cy):
    """世界の点を画面に写します。(x, y, 奥行き)か、近すぎれば None です。"""
    rx, ry, rz = point[0] - pos[0], point[1] - pos[1], point[2] - pos[2]
    xc = rx * right[0] + ry * right[1] + rz * right[2]
    yc = rx * up[0] + ry * up[1] + rz * up[2]
    zc = rx * forward[0] + ry * forward[1] + rz * forward[2]
    if zc <= _NEAR:
        return None
    scale = focal / zc
    return (cx + xc * scale, cy - yc * scale, zc)


def _has_overhang(sheet: RgbaImage, index: int, cache: dict) -> bool:
    """チップの高さの部分に、不透明な画素があるかどうか。"""
    key = (id(sheet), index)
    hit = cache.get(key)
    if hit is not None:
        return hit
    rect = chip_src_rect(index)
    result = False
    if rect is not None:
        sx, sy, _, _ = rect
        data = sheet.pixels
        width = sheet.width
        for y in range(sy, sy + 16):
            row = (y * width + sx) * 4
            for x in range(32):
                if data[row + x * 4 + 3] > 0:
                    result = True
                    break
            if result:
                break
    cache[key] = result
    return result


def _silhouette_runs(sheet: RgbaImage, rect):
    """絵の輪郭を、辺ごとの色のまとまりに分けます。

    返り値は、``left`` / ``right`` / ``top`` / ``bottom`` の4つの表です。
    1つのまとまりは ``(固定する位置, 始め, 終わり, 色)`` で、``left`` と
    ``right`` は行の範囲、``top`` と ``bottom`` は列の範囲です。透明な
    画素は輪郭に含めません。
    """
    sx, sy, sw, sh = rect
    data = sheet.pixels
    width = sheet.width

    def pixel(i: int, j: int):
        k = ((sy + j) * width + (sx + i)) * 4
        return data[k], data[k + 1], data[k + 2], data[k + 3]

    def opaque(i: int, j: int) -> bool:
        return pixel(i, j)[3] >= 128

    def group(lines):
        runs = []
        current = None
        for fixed, start, color in lines:
            if (
                current is not None
                and current[0] == fixed
                and current[3] == color
                and current[2] == start
            ):
                current = (fixed, current[1], start + 1, color)
            else:
                if current is not None:
                    runs.append(current)
                current = (fixed, start, start + 1, color)
        if current is not None:
            runs.append(current)
        return runs

    left_lines = []
    right_lines = []
    for j in range(sh):
        first = next((i for i in range(sw) if opaque(i, j)), None)
        if first is not None:
            left_lines.append((first, j, pixel(first, j)[:3]))
        last = next((i for i in range(sw - 1, -1, -1) if opaque(i, j)), None)
        if last is not None:
            right_lines.append((last, j, pixel(last, j)[:3]))
    top_lines = []
    bottom_lines = []
    for i in range(sw):
        first = next((j for j in range(sh) if opaque(i, j)), None)
        if first is not None:
            top_lines.append((first, i, pixel(i, first)[:3]))
        last = next((j for j in range(sh - 1, -1, -1) if opaque(i, j)), None)
        if last is not None:
            bottom_lines.append((last, i, pixel(i, last)[:3]))
    return {
        "left": group(left_lines),
        "right": group(right_lines),
        "top": group(top_lines),
        "bottom": group(bottom_lines),
    }


def _body_is_opaque(sheet: RgbaImage, rect) -> bool:
    """チップの胴体(下32行)が、ほぼ不透明な絵かどうかを調べます。

    胴体が不透明なチップ(壁や家)は、壁の板にします。胴体に透明な
    部分があるチップ(木など)は、輪郭を押し出した方がらしく見えます。
    """
    sx, sy, sw, _sh = rect
    data = sheet.pixels
    width = sheet.width
    total = 0
    opaque = 0
    for j in range(16, 48):
        base = (sy + j) * width + sx
        for i in range(sw):
            total += 1
            if data[(base + i) * 4 + 3] >= 128:
                opaque += 1
    return opaque >= total * 0.99


def _chip_shape(sheet: RgbaImage, index: int) -> str:
    """チップの番号から、立体物の作り方を決めます。

    扉は板一枚、宝箱や箱は箱形、開いている箱は開口のある箱形、岩は
    すぼまった岩形にします。それ以外は、胴体が不透明なら壁の板、
    輪郭のある絵なら十字の押し出しです。番号はチップの絵の並びの
    位置で、スキンが変わっても同じです。
    """
    if index in _PLANK_CHIPS:
        return "plank"
    if index in _OPEN_CHEST_CHIPS:
        return "open_chest"
    if index in _CHEST_CHIPS:
        return "chest"
    if index in _ROCK_CHIPS:
        return "rock"
    rect = chip_src_rect(index)
    if rect is not None and not _body_is_opaque(sheet, rect):
        return "cross"
    return "wall"


#: 扉のチップ。板一枚にします。
_PLANK_CHIPS = frozenset({11, 12})
#: 開いている箱のチップ。開口のある箱形にします。
_OPEN_CHEST_CHIPS = frozenset({14, 21})
#: 閉じている宝箱や箱のチップ。箱形の立体物にします。
_CHEST_CHIPS = frozenset({15, 22})
#: 岩のチップ。すぼまった岩形にします。
_ROCK_CHIPS = frozenset({6})

#: 開いている箱の絵の、開口の位置と大きさ(絵の中の画素数)。
#: 既定のスキンの絵に合わせています。使う前に絵を確かめます。
_OPEN_CHEST_HOLE = (6, 17, 21, 14)


def _opening_looks_right(sheet: RgbaImage, rect) -> bool:
    """開いている箱の絵が、開口のある絵かどうかを確かめます。

    開口の中が暗く、その上の枠が明るければ、開口のある絵とします。
    違うスキンで絵が違う時は、普通の箱形にします。
    """
    sx, sy, _, _ = rect
    hx, hy, hw, hh = _OPEN_CHEST_HOLE
    data = sheet.pixels
    width = sheet.width

    def mean_brightness(x0: int, y0: int, w: int, h: int) -> float:
        total = 0
        count = 0
        for j in range(y0, y0 + h):
            base = ((sy + j) * width + (sx + x0)) * 4
            for i in range(w):
                k = base + i * 4
                if data[k + 3] >= 128:
                    total += data[k] + data[k + 1] + data[k + 2]
                    count += 1
        if count == 0:
            return 255.0
        return total / (count * 3)

    hole = mean_brightness(hx, hy, hw, hh)
    frame = mean_brightness(hx, hy - 1, hw, 1)
    return hole < 120.0 and frame > hole + 30.0


def _add_open_chest(builder: "_Builder", sheet: RgbaImage, rect,
                    cx: float, cy: float) -> None:
    """開いている箱を、実際の開口のある箱形にします。

    前面に開口の穴を開け、中に暗い空洞を作ります。空洞の奥の壁には
    開口の絵(中身も含みます)を描きます。絵が開口のある絵でなければ、
    普通の箱形にします。
    """
    width, height, depth = 0.98, 1.5, 0.55
    if not _opening_looks_right(sheet, rect):
        _extrude_vertical(builder, sheet, rect, cx, cy, 0.0,
                          width, height, depth, 0.0)
        return
    # 後面と側面は、普通の押し出しと同じです
    _extrude_vertical(builder, sheet, rect, cx, cy, 0.0,
                      width, height, depth, 0.0, skip_front=True)
    sx, sy, sw, sh = rect
    hx, hy, hw, hh = _OPEN_CHEST_HOLE
    px_w, px_h = width / sw, height / sh
    hw2, hd = width / 2, depth / 2
    x0, x1 = cx - hw2, cx + hw2
    yf = cy - hd
    hx0, hx1 = x0 + hx * px_w, x0 + (hx + hw) * px_w
    hz0, hz1 = height - (hy + hh) * px_h, height - hy * px_h
    # 前面の、開口の周りの4つの枠
    builder.quad(
        [(x0, yf, hz1), (x1, yf, hz1), (x1, yf, height), (x0, yf, height)],
        [(sx, sy + hy), (sx + sw, sy + hy), (sx + sw, sy), (sx, sy)],
        sheet, 256,
    )
    builder.quad(
        [(x0, yf, 0.0), (x1, yf, 0.0), (x1, yf, hz0), (x0, yf, hz0)],
        [(sx, sy + sh), (sx + sw, sy + sh),
         (sx + sw, sy + hy + hh), (sx, sy + hy + hh)],
        sheet, 256,
    )
    builder.quad(
        [(x0, yf, hz0), (hx0, yf, hz0), (hx0, yf, hz1), (x0, yf, hz1)],
        [(sx, sy + hy + hh), (sx + hx, sy + hy + hh),
         (sx + hx, sy + hy), (sx, sy + hy)],
        sheet, 256,
    )
    builder.quad(
        [(hx1, yf, hz0), (x1, yf, hz0), (x1, yf, hz1), (hx1, yf, hz1)],
        [(sx + hx + hw, sy + hy + hh), (sx + sw, sy + hy + hh),
         (sx + sw, sy + hy), (sx + hx + hw, sy + hy)],
        sheet, 256,
    )
    # 空洞の中。奥の壁には開口の絵を、周りは暗い色にします。
    yb = yf + 0.3
    builder.quad(
        [(hx0, yb, hz0), (hx1, yb, hz0), (hx1, yb, hz1), (hx0, yb, hz1)],
        [(sx + hx, sy + hy + hh), (sx + hx + hw, sy + hy + hh),
         (sx + hx + hw, sy + hy), (sx + hx, sy + hy)],
        sheet, 200,
    )
    k = ((sy + hy) * sheet.width + (sx + hx)) * 4
    shade = (sheet.pixels[k], sheet.pixels[k + 1], sheet.pixels[k + 2])
    zero_uvs = [(0, 0), (0, 0), (0, 0), (0, 0)]
    builder.quad(
        [(hx0, yf, hz1), (hx1, yf, hz1), (hx1, yb, hz1), (hx0, yb, hz1)],
        zero_uvs, None, 180, color=shade,
    )
    builder.quad(
        [(hx0, yb, hz0), (hx1, yb, hz0), (hx1, yf, hz0), (hx0, yf, hz0)],
        zero_uvs, None, 220, color=shade,
    )
    builder.quad(
        [(hx0, yf, hz0), (hx0, yb, hz0), (hx0, yb, hz1), (hx0, yf, hz1)],
        zero_uvs, None, 200, color=shade,
    )
    builder.quad(
        [(hx1, yb, hz0), (hx1, yf, hz0), (hx1, yf, hz1), (hx1, yb, hz1)],
        zero_uvs, None, 200, color=shade,
    )


def _tall_index(builder: "_Builder", sheet: RgbaImage, cell: Cell):
    """背の高いチップの番号(高さのある絵の最後のもの)。なければ None。"""
    found = None
    for chip_index in chip_indices(cell.chip):
        if builder.has_overhang(sheet, chip_index):
            found = chip_index
    return found


def _is_wall_line(builder: "_Builder", cells: list[Cell], dim: int,
                  sheets: list, row: int, col: int) -> bool:
    """そのマスが、壁の並びの一員(壁の板か扉)かどうかを調べます。"""
    if not (0 <= row < dim and 0 <= col < dim):
        return False
    idx = row * dim + col
    if idx >= len(cells):
        return False
    cell = cells[idx]
    sheet = sheets[cell.attr & 0x03]
    if sheet is None:
        return False
    tall = _tall_index(builder, sheet, cell)
    if tall is None:
        return False
    return _chip_shape(sheet, tall) in ("wall", "plank")


def _door_floor_index(builder: "_Builder", cells: list[Cell], dim: int,
                      sheets: list, row: int, col: int) -> int:
    """扉のマスの床に使う、地面のチップの番号を決めます。

    南・北・東・西の順に、床だけのマスを探して、その一番下のチップ
    を使います。なければ、地面のチップ(0番)を使います。
    """
    for nr, nc in ((row + 1, col), (row - 1, col),
                   (row, col + 1), (row, col - 1)):
        if not (0 <= nr < dim and 0 <= nc < dim):
            continue
        idx = nr * dim + nc
        if idx >= len(cells):
            continue
        cell = cells[idx]
        sheet = sheets[cell.attr & 0x03]
        if sheet is None:
            continue
        indices = chip_indices(cell.chip)
        if indices and not builder.has_overhang(sheet, indices[0]):
            return indices[0]
    return 0


def _rect_has_opaque(sheet: RgbaImage, rect) -> bool:
    """絵の範囲に、不透明な画素があるかどうか。"""
    sx, sy, sw, sh = rect
    data = sheet.pixels
    width = sheet.width
    for j in range(sh):
        base = ((sy + j) * width + sx) * 4
        for i in range(sw):
            if data[base + i * 4 + 3] >= 128:
                return True
    return False


#: 宝箱の絵の、蓋の部分の行(始まりと行数)。既定のスキンの絵に
#: 合わせています。使う前に絵を確かめます。
_CHEST_LID_ROWS = {15: (13, 15), 22: (10, 18)}
#: 宝箱の絵の、胴体の始まりの行。ここから下が胴体です。
_CHEST_BODY_TOP_ROW = 28


def _add_chest(builder: "_Builder", sheet: RgbaImage, rect, index: int,
               cx: float, cy: float) -> None:
    """宝箱を、上の蓋が開いた形にします。

    胴体は絵の下の部分だけの箱にし、蓋は絵の上の部分の板を、胴体の
    後ろ上の縁を軸に後ろへ傾けて立てます。胴体の上には、暗い開口を
    置きます。絵が蓋と胴体に分かれていなければ、普通の箱形にします。
    """
    width, depth = 0.98, 0.55
    sx, sy, _, _ = rect
    lid_start, lid_rows = _CHEST_LID_ROWS.get(index, (13, 15))
    lid_rect = (sx, sy + lid_start, 32, lid_rows)
    body_rows = 48 - _CHEST_BODY_TOP_ROW
    body_rect = (sx, sy + _CHEST_BODY_TOP_ROW, 32, body_rows)
    if not (_rect_has_opaque(sheet, lid_rect)
            and _rect_has_opaque(sheet, body_rect)):
        _extrude_vertical(builder, sheet, rect, cx, cy, 0.0,
                          width, 1.5, depth, 0.0)
        return
    body_h = body_rows / 32
    _extrude_vertical(builder, sheet, body_rect, cx, cy, 0.0,
                      width, body_h, depth, 0.0)
    lid_h = lid_rows / 32
    _extrude_vertical(builder, sheet, lid_rect,
                      cx, cy + depth / 2, body_h,
                      width, lid_h, 0.08, 0.0, pitch=-40.0)
    # 胴体の上の、暗い開口です
    inset = 0.12
    top = body_h + 0.01
    builder.quad(
        [(cx - width / 2 + inset, cy + depth / 2 - inset, top),
         (cx + width / 2 - inset, cy + depth / 2 - inset, top),
         (cx + width / 2 - inset, cy - depth / 2 + inset, top),
         (cx - width / 2 + inset, cy - depth / 2 + inset, top)],
        [(0, 0), (0, 0), (0, 0), (0, 0)],
        None, 200, color=(35, 24, 18),
    )


def _add_frustum(builder: "_Builder", sheet: RgbaImage, index: int,
                 cx: float, cy: float) -> None:
    """岩を、上へすぼまる岩形の立体物にします。

    側面は胴体の絵、上面は胴体の上の方の絵です。下は0.85マス、上は
    0.45マス、高さは0.55です。
    """
    rect = chip_src_rect(index)
    if rect is None:
        return
    sx, sy, _, _ = rect
    bw, tw, height = 0.85, 0.45, 0.55
    x0, x1 = cx - bw / 2, cx + bw / 2
    y0, y1 = cy - bw / 2, cy + bw / 2
    tx0, tx1 = cx - tw / 2, cx + tw / 2
    ty0, ty1 = cy - tw / 2, cy + tw / 2
    body_uvs = [(sx, sy + 48), (sx + 32, sy + 48),
                (sx + 32, sy + 16), (sx, sy + 16)]
    # 南面・北面・東面・西面
    builder.quad([(x0, y0, 0.0), (x1, y0, 0.0), (tx1, ty0, height), (tx0, ty0, height)],
                 body_uvs, sheet, 240)
    builder.quad([(x1, y1, 0.0), (x0, y1, 0.0), (tx0, ty1, height), (tx1, ty1, height)],
                 body_uvs, sheet, 205)
    builder.quad([(x1, y0, 0.0), (x1, y1, 0.0), (tx1, ty1, height), (tx1, ty0, height)],
                 body_uvs, sheet, 215)
    builder.quad([(x0, y1, 0.0), (x0, y0, 0.0), (tx0, ty0, height), (tx0, ty1, height)],
                 body_uvs, sheet, 215)
    # 上面は、胴体の上の方の絵です
    builder.quad([(tx0, ty0, height), (tx1, ty0, height),
                  (tx1, ty1, height), (tx0, ty1, height)],
                 [(sx + 8, sy + 16), (sx + 24, sy + 16),
                  (sx + 24, sy + 28), (sx + 8, sy + 28)],
                 sheet, 256)


def _extrude_vertical(builder: "_Builder", sheet: RgbaImage, rect,
                      cx: float, cy: float, bottom: float,
                      width: float, height: float, depth: float,
                      angle: float, skip_front: bool = False,
                      pitch: float = 0.0) -> None:
    """絵を、厚みのある立てた立体物にします。

    前と後ろは絵そのもの、側面と上面・下面は輪郭の画素の色です。
    ``angle`` は向いている方向で、0 度が南向きです。``skip_front`` を
    付けると、前面だけ描かず、後面と側面だけにします(開いている箱の
    ように、前面を別に作る時に使います)。``pitch`` は前後の傾きで、
    マイナスにすると後ろへ倒れます(宝箱の開いた蓋に使います)。
    """
    runs = _silhouette_runs(sheet, rect)
    if not any(runs.values()):
        return
    sx, sy, sw, sh = rect
    theta = math.radians(angle)
    cos_a, sin_a = math.cos(theta), math.sin(theta)
    theta_p = math.radians(pitch)
    cos_p, sin_p = math.cos(theta_p), math.sin(theta_p)

    def place(lx: float, ly: float, lz: float):
        ry = ly * cos_p - lz * sin_p
        rz = ly * sin_p + lz * cos_p
        return (
            cx + lx * cos_a - ry * sin_a,
            cy + lx * sin_a + ry * cos_a,
            bottom + rz,
        )

    hw, hd = width / 2, depth / 2
    uvs = [(sx, sy + sh), (sx + sw, sy + sh), (sx + sw, sy), (sx, sy)]
    # 前面(向いている側)。開いている箱では、別に作るので描きません。
    if not skip_front:
        builder.quad(
            [place(-hw, -hd, 0), place(hw, -hd, 0),
             place(hw, -hd, height), place(-hw, -hd, height)],
            uvs, sheet, 256,
        )
    # 後面(少し暗くします)
    builder.quad(
        [place(-hw, hd, 0), place(hw, hd, 0),
         place(hw, hd, height), place(-hw, hd, height)],
        uvs, sheet, 220,
    )
    px_w, px_h = width / sw, height / sh
    zero_uvs = [(0, 0), (0, 0), (0, 0), (0, 0)]
    for fixed, start, end, color in runs["left"]:
        lx = -hw + fixed * px_w
        z0, z1 = height - end * px_h, height - start * px_h
        builder.quad(
            [place(lx, -hd, z0), place(lx, hd, z0),
             place(lx, hd, z1), place(lx, -hd, z1)],
            zero_uvs, None, 215, color=color,
        )
    for fixed, start, end, color in runs["right"]:
        lx = -hw + (fixed + 1) * px_w
        z0, z1 = height - end * px_h, height - start * px_h
        builder.quad(
            [place(lx, -hd, z0), place(lx, hd, z0),
             place(lx, hd, z1), place(lx, -hd, z1)],
            zero_uvs, None, 215, color=color,
        )
    for fixed, start, end, color in runs["top"]:
        z = height - fixed * px_h
        x0, x1 = -hw + start * px_w, -hw + end * px_w
        builder.quad(
            [place(x0, -hd, z), place(x1, -hd, z),
             place(x1, hd, z), place(x0, hd, z)],
            zero_uvs, None, 256, color=color,
        )
    for fixed, start, end, color in runs["bottom"]:
        z = height - (fixed + 1) * px_h
        x0, x1 = -hw + start * px_w, -hw + end * px_w
        builder.quad(
            [place(x0, -hd, z), place(x1, -hd, z),
             place(x1, hd, z), place(x0, hd, z)],
            zero_uvs, None, 180, color=color,
        )


def _extrude_flat(builder: "_Builder", sheet: RgbaImage, rect,
                  x0: float, y_top: float, size: float, thickness: float) -> None:
    """絵を、床に置いた薄い浮き彫りにします。上面が絵そのものです。"""
    runs = _silhouette_runs(sheet, rect)
    if not any(runs.values()):
        return
    sx, sy, sw, sh = rect
    px, py = size / sw, size / sh
    x1, y_bot = x0 + size, y_top - size
    builder.quad(
        [(x0, y_top, thickness), (x1, y_top, thickness),
         (x1, y_bot, thickness), (x0, y_bot, thickness)],
        [(sx, sy), (sx + sw, sy), (sx + sw, sy + sh), (sx, sy + sh)],
        sheet, 256,
    )
    zero_uvs = [(0, 0), (0, 0), (0, 0), (0, 0)]
    for fixed, start, end, color in runs["left"]:
        x = x0 + fixed * px
        ya, yb = y_top - end * py, y_top - start * py
        builder.quad(
            [(x, ya, 0), (x, yb, 0), (x, yb, thickness), (x, ya, thickness)],
            zero_uvs, None, 215, color=color,
        )
    for fixed, start, end, color in runs["right"]:
        x = x0 + (fixed + 1) * px
        ya, yb = y_top - end * py, y_top - start * py
        builder.quad(
            [(x, ya, 0), (x, yb, 0), (x, yb, thickness), (x, ya, thickness)],
            zero_uvs, None, 215, color=color,
        )
    for fixed, start, end, color in runs["top"]:
        y = y_top - fixed * py
        xa, xb = x0 + start * px, x0 + end * px
        builder.quad(
            [(xa, y, 0), (xb, y, 0), (xb, y, thickness), (xa, y, thickness)],
            zero_uvs, None, 205, color=color,
        )
    for fixed, start, end, color in runs["bottom"]:
        y = y_top - (fixed + 1) * py
        xa, xb = x0 + start * px, x0 + end * px
        builder.quad(
            [(xa, y, 0), (xb, y, 0), (xb, y, thickness), (xa, y, thickness)],
            zero_uvs, None, 240, color=color,
        )


class _Builder:
    """三角形の集まりを作ります。"""

    def __init__(self, camera: Camera, dim: int):
        self._basis = _camera_basis(camera, dim)
        self.tris: list[tuple] = []
        self._overhang_cache: dict = {}

    def project(self, point):
        pos, right, up, forward, focal, cx, cy = self._basis
        return _project(point, pos, right, up, forward, focal, cx, cy)

    @property
    def right(self):
        return self._basis[1]

    def has_overhang(self, sheet: RgbaImage, index: int) -> bool:
        return _has_overhang(sheet, index, self._overhang_cache)

    def quad(self, corners, uvs, tex: RgbaImage | None, bright: int,
             color: tuple[int, int, int] | None = None) -> None:
        """4つの角(世界座標と絵の位置)から、三角形を2つ作ります。"""
        projected = [self.project(p) for p in corners]
        if any(p is None for p in projected):
            return
        verts = []
        for (sx, sy, z), (u, v) in zip(projected, uvs):
            iz = 1.0 / z
            verts.append((sx, sy, iz, u * iz, v * iz))
        if tex is None:
            assert color is not None
            r = color[0] * bright >> 8
            g = color[1] * bright >> 8
            b = color[2] * bright >> 8
            payload = (None, 0, 0, r, g, b)
        else:
            payload = (tex.pixels, tex.width, tex.height, 0, 0, 0)
        self.tris.append((verts[0], verts[1], verts[2], payload, bright))
        self.tris.append((verts[0], verts[2], verts[3], payload, bright))


def _rasterize(img: RgbaImage, tris: list[tuple]) -> None:
    """三角形を、奥行きつきで1枚に描きます。"""
    width, height = img.width, img.height
    pixels = img.pixels
    depth = [math.inf] * (width * height)
    for v0, v1, v2, payload, bright in tris:
        (x0, y0, iz0, u0, vv0) = v0
        (x1, y1, iz1, u1, vv1) = v1
        (x2, y2, iz2, u2, vv2) = v2
        area = (x2 - x0) * (y1 - y0) - (y2 - y0) * (x1 - x0)
        if area == 0:
            continue
        if area < 0:
            (x1, y1, iz1, u1, vv1), (x2, y2, iz2, u2, vv2) = (
                (x2, y2, iz2, u2, vv2),
                (x1, y1, iz1, u1, vv1),
            )
            area = -area
        x_lo = max(0, math.floor(min(x0, x1, x2)))
        x_hi = min(width, math.ceil(max(x0, x1, x2)))
        y_lo = max(0, math.floor(min(y0, y1, y2)))
        y_hi = min(height, math.ceil(max(y0, y1, y2)))
        if x_hi <= x_lo or y_hi <= y_lo:
            continue
        # 辺の関数の、画素ごとの増分
        de0dx, de0dy = y2 - y1, -(x2 - x1)
        de1dx, de1dy = y0 - y2, -(x0 - x2)
        de2dx, de2dy = y1 - y0, -(x1 - x0)
        px0, py0 = x_lo + 0.5, y_lo + 0.5
        e0 = (px0 - x1) * de0dx + (py0 - y1) * de0dy
        e1 = (px0 - x2) * de1dx + (py0 - y2) * de1dy
        e2 = (px0 - x0) * de2dx + (py0 - y0) * de2dy
        inv_area = 1.0 / area
        d_adx = (de0dx * iz0 + de1dx * iz1 + de2dx * iz2) * inv_area
        d_ady = (de0dy * iz0 + de1dy * iz1 + de2dy * iz2) * inv_area
        d_bdx = (de0dx * u0 + de1dx * u1 + de2dx * u2) * inv_area
        d_bdy = (de0dy * u0 + de1dy * u1 + de2dy * u2) * inv_area
        d_cdx = (de0dx * vv0 + de1dx * vv1 + de2dx * vv2) * inv_area
        d_cdy = (de0dy * vv0 + de1dy * vv1 + de2dy * vv2) * inv_area
        a_row = (e0 * iz0 + e1 * iz1 + e2 * iz2) * inv_area
        b_row = (e0 * u0 + e1 * u1 + e2 * u2) * inv_area
        c_row = (e0 * vv0 + e1 * vv1 + e2 * vv2) * inv_area
        tex, tw, th, cr, cg, cb = payload
        for py in range(y_lo, y_hi):
            e0r, e1r, e2r = e0, e1, e2
            a, b, c = a_row, b_row, c_row
            di = py * width + x_lo
            pi = di * 4
            for _ in range(x_lo, x_hi):
                if e0r >= 0 and e1r >= 0 and e2r >= 0:
                    z = 1.0 / a
                    if z < depth[di]:
                        if tex is None:
                            pixels[pi] = cr
                            pixels[pi + 1] = cg
                            pixels[pi + 2] = cb
                            pixels[pi + 3] = 255
                            depth[di] = z
                        else:
                            iu = int(b * z)
                            iv = int(c * z)
                            if iu < 0:
                                iu = 0
                            elif iu >= tw:
                                iu = tw - 1
                            if iv < 0:
                                iv = 0
                            elif iv >= th:
                                iv = th - 1
                            ti = (iv * tw + iu) * 4
                            if tex[ti + 3] >= 128:
                                pixels[pi] = tex[ti] * bright >> 8
                                pixels[pi + 1] = tex[ti + 1] * bright >> 8
                                pixels[pi + 2] = tex[ti + 2] * bright >> 8
                                pixels[pi + 3] = 255
                                depth[di] = z
                e0r += de0dx
                e1r += de1dx
                e2r += de2dx
                a += d_adx
                b += d_bdx
                c += d_cdx
                di += 1
                pi += 4
            e0 += de0dy
            e1 += de1dy
            e2 += de2dy
            a_row += d_ady
            b_row += d_bdy
            c_row += d_cdy


def _fill_sky(img: RgbaImage) -> None:
    """空のグラデーションで塗ります。"""
    width, height = img.width, img.height
    data = img.pixels
    for y in range(height):
        t = y / max(1, height - 1)
        r = round(_SKY_TOP[0] + (_SKY_BOTTOM[0] - _SKY_TOP[0]) * t)
        g = round(_SKY_TOP[1] + (_SKY_BOTTOM[1] - _SKY_TOP[1]) * t)
        b = round(_SKY_TOP[2] + (_SKY_BOTTOM[2] - _SKY_TOP[2]) * t)
        row = bytes((r, g, b, 255)) * width
        start = y * width * 4
        data[start : start + width * 4] = row


def render_3d_image(
    cells: list[Cell],
    chars: list[Chara],
    dim: int,
    chip_sheets: list[RgbaImage | None],
    items: RgbaImage | None,
    chara_image,
    camera: Camera,
    anim_frame: int = 0,
    eagle_eye: bool = False,
    style: str = "boxes",
) -> RenderedMap:
    """地図を3Dの1枚の画像に描きます。

    引数は ``map_graphics.render_map_image`` と同じで、カメラが増えた
    だけです。名前のラベルは、頭の位置を画面に写した場所で返します。
    ``style`` は ``boxes``(箱に絵を貼る)か ``extrude``(絵の輪郭を
    立体物に押し出す)です。
    """
    camera = camera.clamped()
    img = RgbaImage(camera.width, camera.height, fill=(0, 0, 0, 255))
    _fill_sky(img)
    builder = _Builder(camera, dim)
    sheets = list(chip_sheets) + [None] * (4 - len(chip_sheets))

    def chip_for(cell: Cell) -> RgbaImage | None:
        return sheets[cell.attr & 0x03]

    any_sheet = any(s is not None for s in sheets)
    water = build_water_grid(cells, dim) if any_sheet else None

    # 地図の外の地面
    builder.quad(
        [(-dim, dim, -0.02), (2 * dim, dim, -0.02),
         (2 * dim, -2 * dim, -0.02), (-dim, -2 * dim, -0.02)],
        [(0, 0), (0, 0), (0, 0), (0, 0)],
        None, 256, color=_GROUND_COLOR,
    )

    for row in range(dim):
        for col in range(dim):
            idx = row * dim + col
            if idx >= len(cells):
                continue
            cell = cells[idx]
            sheet = chip_for(cell)
            x0, x1 = float(col), float(col + 1)
            y0, y1 = float(-row), float(-row - 1)  # 北端と南端
            # 床
            if sheet is None:
                indices = chip_indices(cell.chip)
                color = FALLBACK_CHIP_COLORS.get(indices[0], FALLBACK_CHIP_DEFAULT)
                builder.quad(
                    [(x0, y0, 0.0), (x1, y0, 0.0), (x1, y1, 0.0), (x0, y1, 0.0)],
                    [(0, 0), (0, 0), (0, 0), (0, 0)],
                    None, _BRIGHT_FLOOR, color=color,
                )
            else:
                box_index = _tall_index(builder, sheet, cell)
                shape = (_chip_shape(sheet, box_index)
                         if box_index is not None else None)
                # 扉のマスの床は、扉の下地ではなく地面の絵にします
                if shape == "plank":
                    floor_indices = [_door_floor_index(
                        builder, cells, dim, sheets, row, col)]
                else:
                    floor_indices = chip_indices(cell.chip)
                for k, chip_index in enumerate(floor_indices):
                    rect = chip_src_rect(chip_index)
                    if rect is None:
                        continue
                    sx, sy, _, _ = rect
                    z = 0.01 * k
                    builder.quad(
                        [(x0, y0, z), (x1, y0, z), (x1, y1, z), (x0, y1, z)],
                        [(sx, sy + 16), (sx + 32, sy + 16),
                         (sx + 32, sy + 48), (sx, sy + 48)],
                        sheet, _BRIGHT_FLOOR,
                    )
                # 背の高いチップは、形に合った立体物にします
                if box_index is not None:
                    if style == "extrude":
                        rect = chip_src_rect(box_index)
                        if rect is not None:
                            if shape == "plank":
                                # 扉は絵の上32行だけを板にします。
                                # 下16行は壁の下地で、床に描かれる分だけで
                                # 十分です。板の高さはキャラと同じ1.0です。
                                # 南北に壁が並んでいれば東西を向き、壁の
                                # 厚みの中央に来ます。
                                sx, sy, _, _ = rect
                                north = _is_wall_line(
                                    builder, cells, dim, sheets, row - 1, col)
                                south = _is_wall_line(
                                    builder, cells, dim, sheets, row + 1, col)
                                angle = 90.0 if (north or south) else 0.0
                                _extrude_vertical(
                                    builder, sheet, (sx, sy, 32, 32),
                                    col + 0.5, -row - 0.5, 0.0,
                                    0.98, 1.0, 0.15, angle,
                                )
                            elif shape == "open_chest":
                                _add_open_chest(builder, sheet, rect,
                                                col + 0.5, -row - 0.5)
                            elif shape == "chest":
                                _add_chest(builder, sheet, rect, box_index,
                                           col + 0.5, -row - 0.5)
                            elif shape == "rock":
                                _add_frustum(builder, sheet, box_index,
                                             col + 0.5, -row - 0.5)
                            elif shape == "cross":
                                for angle in (0.0, 90.0):
                                    _extrude_vertical(
                                        builder, sheet, rect,
                                        col + 0.5, -row - 0.5, 0.0,
                                        0.98, 1.5, 0.48, angle,
                                    )
                            else:
                                # 壁や家は、元の厚みで扉と同じ高さの箱です
                                _add_box(builder, sheet, box_index,
                                         x0, x1, y0, y1, height=1.0)
                    else:
                        _add_box(builder, sheet, box_index, x0, x1, y0, y1)
            # 水縁
            if water is not None and sheet is not None and cell.chip == ord("_"):
                patterns = water_quarter_patterns(water, row, col)
                for q in range(4):
                    hit = water_quarter_chip(q, patterns[q])
                    if hit is None:
                        continue
                    rect = chip_quarter_src_rect(hit[0], hit[1])
                    if rect is None:
                        continue
                    qx, qy = q & 1, (q >> 1) & 1
                    qa0, qa1 = x0 + qx * 0.5, x0 + (qx + 1) * 0.5
                    qb0, qb1 = y0 - qy * 0.5, y0 - (qy + 1) * 0.5
                    rx, ry, _, _ = rect
                    builder.quad(
                        [(qa0, qb0, 0.012), (qa1, qb0, 0.012),
                         (qa1, qb1, 0.012), (qa0, qb1, 0.012)],
                        [(rx, ry), (rx + 16, ry), (rx + 16, ry + 16), (rx, ry + 16)],
                        sheet, _BRIGHT_FLOOR,
                    )
            # 看板は、前に向けた板か押し出しの立体物にします
            if sheet is not None and has_board(cell.attr):
                rect = chip_src_rect(board_chip_index(cell.chip))
                if rect is not None:
                    if style == "extrude":
                        _extrude_vertical(
                            builder, sheet, rect,
                            col + 0.5, -row - 0.5, 0.0,
                            0.98, 1.5, 0.25, 0.0,
                        )
                    else:
                        sx, sy, _, _ = rect
                        ym = (y0 + y1) / 2
                        builder.quad(
                            [(x0, ym, 0.0), (x1, ym, 0.0),
                             (x1, ym, 1.5), (x0, ym, 1.5)],
                            [(sx, sy + 48), (sx + 32, sy + 48),
                             (sx + 32, sy), (sx, sy)],
                            sheet, _BRIGHT_BOARD,
                        )
            # アイテムは、床に置いた絵にします
            if has_item(cell.attr):
                if eagle_eye:
                    if sheet is not None:
                        rect = chip_src_rect(EAGLE_EYE_ITEM_CHIP)
                        if rect is not None:
                            sx, sy, _, _ = rect
                            builder.quad(
                                [(x0, y0, 0.03), (x1, y0, 0.03),
                                 (x1, y1, 0.03), (x0, y1, 0.03)],
                                [(sx, sy + 16), (sx + 32, sy + 16),
                                 (sx + 32, sy + 48), (sx, sy + 48)],
                                sheet, _BRIGHT_FLOOR,
                            )
                elif items is not None:
                    no = item_no(cell.attr)
                    s = ITEM_SPRITE_SIZE
                    if style == "extrude":
                        _extrude_flat(
                            builder, items, (no * s, 0, s, s),
                            x0 + 0.1, y0 - 0.1, 0.8, 0.12,
                        )
                    else:
                        builder.quad(
                            [(x0 + 0.1, y0 - 0.1, 0.03), (x1 - 0.1, y0 - 0.1, 0.03),
                             (x1 - 0.1, y1 + 0.1, 0.03), (x0 + 0.1, y1 + 0.1, 0.03)],
                            [(no * s, 0), (no * s + s, 0),
                             (no * s + s, s), (no * s, s)],
                            items, _BRIGHT_ITEM,
                        )
                else:
                    builder.quad(
                        [(x0 + 0.25, y0 - 0.25, 0.03), (x1 - 0.25, y0 - 0.25, 0.03),
                         (x1 - 0.25, y1 + 0.25, 0.03), (x0 + 0.25, y1 + 0.25, 0.03)],
                        [(0, 0), (0, 0), (0, 0), (0, 0)],
                        None, _BRIGHT_ITEM, color=(255, 255, 200),
                    )

    # キャラは、カメラの方を向く看板にします
    chars_by_row: dict[int, list[Chara]] = {}
    for ch in chars:
        if 0 <= ch.x < dim and 0 <= ch.y < dim:
            chars_by_row.setdefault(ch.y, []).append(ch)
    labels: list[Label] = []
    placeholders: list[Placeholder] = []
    per_cell_label: dict[tuple[int, int], Label] = {}
    right = builder.right
    for row, row_chars in chars_by_row.items():
        for ch, dx in arrange_row(row_chars):
            rect = chara_src_rect(ch.dir, ch.gigant, anim_frame)
            sx, sy, sw, sh = rect
            cx, cy = ch.x + 0.5, -ch.y - 0.5
            if ch.magnify is not None:
                half_w = (ch.magnify.w / 32) / 2
                height = ch.magnify.h / 32
                bottom = ch.magnify.z / 32
            else:
                half_w = (sw / 32) / 2
                height = CHARA_H / 32
                bottom = 0.0
            # キャラは元の絵を、カメラの方へ向けた板のままにします
            ox, oy = right[0] * (dx / 32), right[1] * (dx / 32)
            cx += ox
            cy += oy
            rx, ry = right[0] * half_w, right[1] * half_w
            corners = [
                (cx - rx, cy - ry, bottom),
                (cx + rx, cy + ry, bottom),
                (cx + rx, cy + ry, bottom + height),
                (cx - rx, cy - ry, bottom + height),
            ]
            uvs = [(sx, sy + sh), (sx + sw, sy + sh), (sx + sw, sy), (sx, sy)]
            sprite = chara_image(ch)
            if sprite is None:
                builder.quad(corners, uvs, None, _BRIGHT_CHARA,
                             color=(255, 255, 0))
                head = builder.project((cx, cy, bottom + height / 2))
                if head is not None:
                    placeholders.append(
                        Placeholder(x=round(head[0]), y=round(head[1]),
                                    name=strip_tags(ch.name).strip())
                    )
            else:
                builder.quad(corners, uvs, sprite, _BRIGHT_CHARA)
            name = strip_tags(ch.name).strip()
            if name:
                head = builder.project((cx, cy, bottom + height + 0.15))
                if head is not None:
                    per_cell_label[(ch.x, ch.y)] = Label(
                        x=round(head[0]), y=round(head[1]), name=name
                    )

    _rasterize(img, builder.tris)
    cx = dim // 2
    cy = dim // 2
    labels = [label for (x, y), label in per_cell_label.items()
              if not (x == cx and y == cy)]
    return RenderedMap(image=img, labels=labels, placeholders=placeholders)


def _add_box(builder: _Builder, sheet: RgbaImage, index: int,
             x0: float, x1: float, y0: float, y1: float,
             height: float = _WALL_H) -> None:
    """チップを、高さのある箱にします。

    側面は絵の上の部分(高さの分だけ)、上面は胴体の絵です。高さ 0.5
    なら側面は上の16行、高さ 1.0 なら上の32行で、絵は歪みません。
    """
    rect = chip_src_rect(index)
    if rect is None:
        return
    sx, sy, _, _ = rect
    z0, z1 = 0.0, height
    side_rows = round(height * 32)
    side_uvs = [(sx, sy + side_rows), (sx + 32, sy + side_rows),
                (sx + 32, sy), (sx, sy)]
    # 南面(カメラ側)
    builder.quad(
        [(x0, y1, z0), (x1, y1, z0), (x1, y1, z1), (x0, y1, z1)],
        side_uvs, sheet, _BRIGHT_SOUTH,
    )
    # 北面
    builder.quad(
        [(x1, y0, z0), (x0, y0, z0), (x0, y0, z1), (x1, y0, z1)],
        side_uvs, sheet, _BRIGHT_NORTH,
    )
    # 西面
    builder.quad(
        [(x0, y0, z0), (x0, y1, z0), (x0, y1, z1), (x0, y0, z1)],
        side_uvs, sheet, _BRIGHT_SIDE,
    )
    # 東面
    builder.quad(
        [(x1, y1, z0), (x1, y0, z0), (x1, y0, z1), (x1, y1, z1)],
        side_uvs, sheet, _BRIGHT_SIDE,
    )
    # 上面
    builder.quad(
        [(x0, y0, z1), (x1, y0, z1), (x1, y1, z1), (x0, y1, z1)],
        [(sx, sy + 16), (sx + 32, sy + 16),
         (sx + 32, sy + 48), (sx, sy + 48)],
        sheet, _BRIGHT_TOP,
    )
