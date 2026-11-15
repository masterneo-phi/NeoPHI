"""地図を擬似3Dのクオータービューで描く、試しの描画です。

平面の描画(``map_graphics``)と同じ絵を使い、床を斜めに潰した
平行四辺形に写し、高さの部分とキャラは垂直に立てて描きます。
写し方は2つの基底ベクトル ``u``(x方向の1マス)と ``v``(y方向の1マス)
で決まり、3つの見方を用意しています。

- ``tilt``: 床を縦に半分に潰すだけの見方。``u=(32, 0)``、``v=(0, 16)``。
- ``oblique``: 斜め45度にずらす見方。``u=(32, 0)``、``v=(16, 16)``。
- ``iso``: ダイヤ型の見方。``u=(16, 8)``、``v=(-16, 8)``。

チップは、胴体(下32px)を床に、高さ(上16px)を垂直な面に分けて描きます。
描く順は、奥のマス(``x + y`` の小さい方)から手前へ1マスずつで、
手前の壁が奥のキャラを隠すようにします。キャラと看板は立てたまま描き、
アイテムは床に寝かせて描きます。
"""

from __future__ import annotations

import math
from dataclasses import dataclass

from .bmp import RgbaImage
from .map_graphics import (
    CHARA_H,
    CHARA_Y_ABOVE_FLOOR,
    CHIP_HEIGHT,
    CHIP_SIZE,
    EAGLE_EYE_ITEM_CHIP,
    FALLBACK_CHIP_COLORS,
    FALLBACK_CHIP_DEFAULT,
    ITEM_CLIP_H,
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
    is_circle_chip,
    item_no,
    magnified_dst,
    water_quarter_chip,
    water_quarter_patterns,
)
from .map_text import chip_indices
from .parser import Cell, Chara
from .tags import strip_tags

__all__ = [
    "PRESETS",
    "QuarterView",
    "quarter_geometry",
    "quarter_pick",
    "render_quarter_image",
]


@dataclass(frozen=True)
class QuarterView:
    """クオータービューの写し方。"""

    name: str
    u: tuple[float, float]
    v: tuple[float, float]
    # 一番奥の行の上にある余白(px)。キャラの頭と壁の高さの分。
    headroom: int = 40


PRESETS: dict[str, QuarterView] = {
    "tilt": QuarterView("tilt", (32, 0), (0, 16)),
    "oblique": QuarterView("oblique", (32, 0), (16, 16)),
    "iso": QuarterView("iso", (16, 8), (-16, 8)),
}

# 左右の余白(px)。巨大化したキャラのはみ出しの分。
_SIDE_MARGIN = 24
# 下の余白(px)。
_BOTTOM_MARGIN = 8


def quarter_geometry(dim: int, view: QuarterView) -> tuple[int, int, int, int]:
    """(原点のx, 原点のy, 幅, 高さ)を返します。

    原点はマス (0, 0) の床の奥の角です。
    """
    ux, uy = view.u
    vx, vy = view.v
    min_x = min_y = math.inf
    max_x = max_y = -math.inf
    for y in range(dim):
        for x in range(dim):
            ox, oy = x * ux + y * vx, x * uy + y * vy
            for cx, cy in ((ox, oy), (ox + ux, oy + uy), (ox + vx, oy + vy),
                           (ox + ux + vx, oy + uy + vy)):
                min_x = min(min_x, cx)
                max_x = max(max_x, cx)
                min_y = min(min_y, cy)
                max_y = max(max_y, cy)
    width = math.ceil(max_x - min_x) + _SIDE_MARGIN * 2
    height = math.ceil(max_y - min_y) + view.headroom + _BOTTOM_MARGIN
    base_x = math.ceil(-min_x) + _SIDE_MARGIN
    base_y = math.ceil(-min_y) + view.headroom
    return base_x, base_y, width, height


def quarter_pick(
    view: QuarterView, dim: int, base_x: int, base_y: int, px: float, py: float
) -> tuple[int, int] | None:
    """画面の点がどのマスか。マスの外なら None です。"""
    ux, uy = view.u
    vx, vy = view.v
    det = ux * vy - uy * vx
    if det == 0:
        return None
    dx, dy = px - base_x, py - base_y
    fx = (dx * vy - dy * vx) / det
    fy = (ux * dy - uy * dx) / det
    if 0 <= fx < dim and 0 <= fy < dim:
        return int(fx), int(fy)
    return None


def _blit_affine(
    dst: RgbaImage,
    src: RgbaImage,
    sx: int,
    sy: int,
    sw: int,
    sh: int,
    ox: float,
    oy: float,
    ux: float,
    uy: float,
    vx: float,
    vy: float,
) -> None:
    """元の矩形を、原点と2つの基底で決まる平行四辺形に写して重ねます。"""
    det = ux * vy - uy * vx
    if det == 0 or sw <= 0 or sh <= 0:
        return
    # 軸に平行なら、整数の拡大・縮小で速く描けます
    if uy == 0 and vx == 0 and ux > 0 and vy > 0:
        dst.blit_scaled(src, sx, sy, sw, sh, round(ox), round(oy),
                        round(ux), round(vy))
        return
    corners = [(ox, oy), (ox + ux, oy + uy), (ox + vx, oy + vy),
               (ox + ux + vx, oy + uy + vy)]
    x0 = max(0, math.floor(min(c[0] for c in corners)))
    x1 = min(dst.width, math.ceil(max(c[0] for c in corners)))
    y0 = max(0, math.floor(min(c[1] for c in corners)))
    y1 = min(dst.height, math.ceil(max(c[1] for c in corners)))
    if x1 <= x0 or y1 <= y0:
        return
    # 画素の中心から元の位置を求めます。1画素ごとの増分だけを使います
    da_dx = vy / det
    da_dy = -vx / det
    db_dx = -uy / det
    db_dy = ux / det
    sdata = src.pixels
    ddata = dst.pixels
    dw = dst.width
    swd = src.width
    for py in range(y0, y1):
        dx = (x0 + 0.5) - ox
        dy = (py + 0.5) - oy
        a = dx * da_dx + dy * da_dy
        b = dx * db_dx + dy * db_dy
        di = (py * dw + x0) * 4
        for _ in range(x0, x1):
            if 0 <= a < 1 and 0 <= b < 1:
                src_x = sx + int(a * sw)
                src_y = sy + int(b * sh)
                si = (src_y * swd + src_x) * 4
                sa = sdata[si + 3]
                if sa == 255:
                    ddata[di : di + 4] = sdata[si : si + 4]
                elif sa:
                    inv = 255 - sa
                    ddata[di] = (sdata[si] * sa + ddata[di] * inv) // 255
                    ddata[di + 1] = (sdata[si + 1] * sa + ddata[di + 1] * inv) // 255
                    ddata[di + 2] = (sdata[si + 2] * sa + ddata[di + 2] * inv) // 255
                    ddata[di + 3] = max(ddata[di + 3], sa)
            a += da_dx
            b += db_dx
            di += 4


def _fill_affine(
    dst: RgbaImage,
    ox: float,
    oy: float,
    ux: float,
    uy: float,
    vx: float,
    vy: float,
    color: tuple[int, int, int],
) -> None:
    """平行四辺形を1色で塗ります(絵が無い時の代わり)。"""
    det = ux * vy - uy * vx
    if det == 0:
        return
    if uy == 0 and vx == 0 and ux > 0 and vy > 0:
        dst.fill_rect(round(ox), round(oy), round(ux), round(vy), (*color, 255))
        return
    corners = [(ox, oy), (ox + ux, oy + uy), (ox + vx, oy + vy),
               (ox + ux + vx, oy + uy + vy)]
    x0 = max(0, math.floor(min(c[0] for c in corners)))
    x1 = min(dst.width, math.ceil(max(c[0] for c in corners)))
    y0 = max(0, math.floor(min(c[1] for c in corners)))
    y1 = min(dst.height, math.ceil(max(c[1] for c in corners)))
    da_dx = vy / det
    da_dy = -vx / det
    db_dx = -uy / det
    db_dy = ux / det
    rgba = bytes((*color, 255))
    for py in range(y0, y1):
        dx = (x0 + 0.5) - ox
        dy = (py + 0.5) - oy
        a = dx * da_dx + dy * da_dy
        b = dx * db_dx + dy * db_dy
        di = (py * dst.width + x0) * 4
        for _ in range(x0, x1):
            if 0 <= a < 1 and 0 <= b < 1:
                dst.pixels[di : di + 4] = rgba
            a += da_dx
            b += db_dx
            di += 4


def _draw_chip(
    img: RgbaImage, sheet: RgbaImage, index: int,
    ox: float, oy: float, view: QuarterView,
) -> None:
    """1チップを描きます。胴体は床に、高さは垂直な面に写します。"""
    rect = chip_src_rect(index)
    if rect is None:
        return
    sx, sy, _, _ = rect
    ux, uy = view.u
    vx, vy = view.v
    height = CHIP_HEIGHT - CHIP_SIZE  # 16
    # 胴体(下32px) → 床
    _blit_affine(img, sheet, sx, sy + height, CHIP_SIZE, CHIP_SIZE,
                 ox, oy, ux, uy, vx, vy)
    # 高さ(上16px) → 垂直な面
    _blit_affine(img, sheet, sx, sy, CHIP_SIZE, height,
                 ox, oy, ux, uy, 0, -height)


def render_quarter_image(
    cells: list[Cell],
    chars: list[Chara],
    dim: int,
    chip_sheets: list[RgbaImage | None],
    items: RgbaImage | None,
    chara_image,
    view: QuarterView,
    anim_frame: int = 0,
    eagle_eye: bool = False,
    ghosts: list[tuple[Chara, RgbaImage]] | None = None,
) -> RenderedMap:
    """地図をクオータービューの1枚の画像に描きます。

    引数は ``map_graphics.render_map_image`` と同じで、写し方 ``view`` が
    増えただけです。名前のラベルと頭文字の位置も同じ形で返します。
    ``ghosts`` は倒れたキャラの残像で、同じマスのキャラの後で描きます。
    """
    base_x, base_y, width, height = quarter_geometry(dim, view)
    img = RgbaImage(width, height, fill=(0, 0, 0, 255))
    ux, uy = view.u
    vx, vy = view.v
    # 奥行きの潰れ具合(1マスの画面上の高さ / 32)。足の上げ幅に使います
    squash = (uy + vy) / CHIP_SIZE
    raise_px = 0 if eagle_eye else round(CHARA_Y_ABOVE_FLOOR * squash)
    item_shift = round(8 * squash)

    sheets = list(chip_sheets) + [None] * (4 - len(chip_sheets))

    def chip_for(cell: Cell) -> RgbaImage | None:
        return sheets[cell.attr & 0x03]

    any_sheet = any(s is not None for s in sheets)
    water = build_water_grid(cells, dim) if any_sheet else None

    by_cell: dict[tuple[int, int], list[Chara]] = {}
    for ch in chars:
        if 0 <= ch.x < dim and 0 <= ch.y < dim:
            by_cell.setdefault((ch.x, ch.y), []).append(ch)
    ghost_by_cell: dict[tuple[int, int], list[tuple[Chara, RgbaImage]]] = {}
    for ghost_ch, ghost_sheet in ghosts or []:
        if 0 <= ghost_ch.x < dim and 0 <= ghost_ch.y < dim:
            ghost_by_cell.setdefault((ghost_ch.x, ghost_ch.y), []).append(
                (ghost_ch, ghost_sheet))

    labels: list[Label] = []
    placeholders: list[Placeholder] = []
    per_cell_label: dict[tuple[int, int], Label] = {}

    # 奥(x + y が小さい)から手前へ1マスずつ描きます
    for total in range(2 * dim - 1):
        for x in range(dim):
            y = total - x
            if not (0 <= y < dim):
                continue
            idx = y * dim + x
            if idx >= len(cells):
                continue
            cell = cells[idx]
            ox = base_x + x * ux + y * vx
            oy = base_y + x * uy + y * vy
            sheet = chip_for(cell)
            # 1. ベースチップ
            if sheet is None:
                indices = chip_indices(cell.chip)
                color = FALLBACK_CHIP_COLORS.get(indices[0], FALLBACK_CHIP_DEFAULT)
                _fill_affine(img, ox, oy, ux, uy, vx, vy, color)
            else:
                for chip_index in chip_indices(cell.chip):
                    _draw_chip(img, sheet, chip_index, ox, oy, view)
            # 1.5 水縁overlay
            if water is not None and sheet is not None and cell.chip == ord("_"):
                patterns = water_quarter_patterns(water, y, x)
                for q in range(4):
                    hit = water_quarter_chip(q, patterns[q])
                    if hit is None:
                        continue
                    rect = chip_quarter_src_rect(hit[0], hit[1])
                    if rect is None:
                        continue
                    qx = ox + (q & 1) * ux / 2 + ((q >> 1) & 1) * vx / 2
                    qy = oy + (q & 1) * uy / 2 + ((q >> 1) & 1) * vy / 2
                    _blit_affine(img, sheet, rect[0], rect[1], rect[2], rect[3],
                                 qx, qy, ux / 2, uy / 2, vx / 2, vy / 2)
            # 2. 看板overlay
            if sheet is not None and has_board(cell.attr):
                _draw_chip(img, sheet, board_chip_index(cell.chip), ox, oy, view)
            # 3. アイテムoverlay
            if has_item(cell.attr):
                if eagle_eye:
                    if sheet is not None:
                        _draw_chip(img, sheet, EAGLE_EYE_ITEM_CHIP, ox, oy, view)
                elif items is not None:
                    no = item_no(cell.attr)
                    s = ITEM_SPRITE_SIZE
                    if is_circle_chip(cell.chip):
                        src_y = 5 if no in (5, 6) else 0
                        _blit_affine(img, items, no * s, src_y, s, ITEM_CLIP_H,
                                     ox, oy - item_shift,
                                     ux, uy, vx * ITEM_CLIP_H / s, vy * ITEM_CLIP_H / s)
                    else:
                        _blit_affine(img, items, no * s, 0, s, s,
                                     ox, oy - item_shift, ux, uy, vx, vy)
                else:
                    _fill_affine(img, ox + ux / 4 + vx / 4, oy + uy / 4 + vy / 4,
                                 ux / 2, uy / 2, vx / 2, vy / 2, (255, 255, 200))
            # 4. キャラ(このマス)
            feet_x = ox + (ux + vx) / 2
            feet_y = oy + uy + vy - raise_px
            for ch, dx in arrange_row(by_cell.get((x, y), [])):
                _draw_chara_quarter(
                    img, ch, feet_x + dx, feet_y, anim_frame,
                    chara_image, placeholders,
                )
                name = strip_tags(ch.name).strip()
                if name:
                    per_cell_label[(x, y)] = Label(
                        x=round(feet_x), y=round(feet_y - 20), name=name
                    )
            # 4.5 残像(このマス)。ずらさず、名札は出しません。
            for ghost_ch, ghost_sheet in ghost_by_cell.get((x, y), []):
                _draw_chara_quarter(
                    img, ghost_ch, feet_x, feet_y, anim_frame,
                    lambda _ch, sheet=ghost_sheet: sheet, placeholders,
                )

    cx = dim // 2
    cy = dim // 2
    labels = [label for (x, y), label in per_cell_label.items()
              if not (x == cx and y == cy)]
    return RenderedMap(image=img, labels=labels, placeholders=placeholders)


def _draw_chara_quarter(
    img: RgbaImage,
    ch: Chara,
    feet_x: float,
    feet_y: float,
    anim_frame: int,
    chara_image,
    placeholders: list[Placeholder],
) -> None:
    """キャラを立てたまま描きます。足の位置が床の上の足場です。"""
    rect = chara_src_rect(ch.dir, ch.gigant, anim_frame)
    sx, sy, sw, sh = rect
    base_x = round(feet_x - sw / 2)
    base_y = round(feet_y - CHARA_H)
    sprite = chara_image(ch)
    if sprite is None:
        img.fill_rect(base_x, base_y, sw, sh, (255, 255, 0, 255))
        placeholders.append(
            Placeholder(
                x=base_x + sw // 2, y=base_y + sh // 2,
                name=strip_tags(ch.name).strip(),
            )
        )
        return
    if ch.magnify is not None:
        d = magnified_dst(base_x, base_y, ch.magnify)
        img.blit_scaled(sprite, sx, sy, sw, sh, d[0], d[1], d[2], d[3])
        return
    img.blit(sprite, sx, sy, sw, sh, base_x, base_y)
