"""地図を BMP の絵で描きます。

wphi の ``ui/src/mapRender.ts`` と ``ui/src/drawMap.ts`` の移植です。
Canvas ではなく画素列(``bmp.RgbaImage``)に描くので、Tkinter でも
PNG の書き出しでも同じ絵になります。拡大表示は描く側で画像を拡大する
前提で、ここでは等倍(1マス 32px)だけを描きます。

名前のラベルと、絵がまだ無い時の頭文字は文字の描画が必要なので、
ここでは位置だけを返し、描くのは呼び出し側に任せます。
"""

from __future__ import annotations

from dataclasses import dataclass, field

from .bmp import RgbaImage
from .map_text import CHIP_BYTE_TO_INDEX, chip_indices
from .parser import Cell, Chara, EagleEyeEvent, Magnify
from .tags import strip_tags

__all__ = [
    "CHIP_COUNT",
    "CHIP_HEIGHT",
    "CHIP_SIZE",
    "MAP_TOP",
    "Anchor",
    "Label",
    "Placeholder",
    "RenderedMap",
    "arrange_row",
    "board_chip_index",
    "build_water_grid",
    "chara_src_rect",
    "chip_quarter_src_rect",
    "chip_src_rect",
    "eagle_board",
    "grid_dim",
    "has_board",
    "has_item",
    "item_draw_rect",
    "item_no",
    "magnified_dst",
    "render_map_image",
    "water_quarter_chip",
    "water_quarter_patterns",
]

# チップ画面セルサイズ(px)。
CHIP_SIZE = 32
# チップシート1セルの高さ(px)。上16px透過。
CHIP_HEIGHT = 48
# マップの上の余白(px)。一番上の行のチップのはみ出しの分。
MAP_TOP = CHIP_HEIGHT - CHIP_SIZE
# チップ総数。
CHIP_COUNT = 32
# チップシート1行あたりの列数。
CHIPS_PER_ROW = 16

# 看板overlay用チップ。
BOARD_CHIP_SOFT = 18
BOARD_CHIP_HARD = 20
_HARD_BOARD_CHIPS = frozenset(b"@#H=[{|%")

# アイテムスプライト1枚サイズ(px)。
ITEM_SPRITE_SIZE = 32
# 防御円チップbyte('x'=14, '%'=15)。
_CIRCLE_CHIPS = frozenset(b"x%")
# アイテムを床の上端から上げる量(px)。
ITEM_Y_ABOVE_FLOOR = 8
# キャラを床の上端から上げる量(px)。
CHARA_Y_ABOVE_FLOOR = 11
# アイテムクリップ高(円内に収める可視高 = 32-11)。
ITEM_CLIP_H = ITEM_SPRITE_SIZE - 11

# キャラ通常フレーム幅(px)。
CHARA_W_NORMAL = 16
# キャラ巨大フレーム幅(px)。
CHARA_W_GIANT = 32
# キャラ1フレーム高(px)。
CHARA_H = 32

_DIR_TO_ROW = {"B": 0, "R": 1, "F": 2, "L": 3}
_DIR_NUM_TO_CHAR = {0: "B", 1: "B", 2: "R", 3: "F", 4: "F", 5: "F", 6: "L", 7: "B"}

# 水縁チップのベースindex。
WATER_CHIP_BASE = 23
# 水チップのbyte('_')。
WATER_BYTE = ord("_")

# EagleEye でアイテムのマスに描くマップチップ。
EAGLE_EYE_ITEM_CHIP = 19
# EagleEye で人がいるマスの属性。
PERSON_ATTR = 0x58
# 人のマスに描くキャラグラ。
PERSON_GRA = "t_man"

# 水縁 quarter 描画テーブル。添字 = quarter(0=TL,1=TR,2=BL,3=BR)。
# 各 quarter で 3bit パターン → (chip_offset, src_quarter)。
Q_TABLE: tuple[dict[int, tuple[int, int]], ...] = (
    {0x00: (1, 0), 0x01: (1, 0), 0x02: (0, 0), 0x03: (0, 0), 0x04: (0, 2), 0x05: (0, 2), 0x06: (2, 3)},
    {0x00: (1, 1), 0x01: (1, 1), 0x02: (0, 1), 0x03: (0, 1), 0x04: (0, 2), 0x05: (0, 2), 0x06: (2, 2)},
    {0x00: (1, 2), 0x01: (1, 2), 0x02: (0, 0), 0x03: (0, 0), 0x04: (0, 3), 0x05: (0, 3), 0x06: (2, 1)},
    {0x00: (1, 3), 0x01: (1, 3), 0x02: (0, 1), 0x03: (0, 1), 0x04: (0, 3), 0x05: (0, 3), 0x06: (2, 0)},
)

# 絵が無い時にマスを塗る色(チップindexごと)。グラフィックスが無くても
# 地形の違いが分かるようにするためのもので、Philly の色ではありません。
FALLBACK_CHIP_COLORS: dict[int, tuple[int, int, int]] = {
    0: (40, 40, 40),
    1: (86, 122, 58),
    2: (110, 140, 70),
    3: (52, 92, 40),
    4: (48, 96, 160),
    5: (120, 96, 64),
    6: (150, 150, 150),
    7: (96, 96, 96),
    8: (140, 80, 60),
    9: (160, 140, 90),
    10: (180, 160, 120),
    11: (90, 110, 130),
    12: (130, 90, 110),
    13: (170, 170, 170),
    14: (70, 130, 130),
    15: (130, 70, 130),
    16: (190, 180, 140),
    17: (150, 110, 70),
    31: (20, 20, 20),
}
FALLBACK_CHIP_DEFAULT = (64, 64, 64)


def chip_src_rect(index: int) -> tuple[int, int, int, int] | None:
    """チップシート上の index → 矩形(sx, sy, sw, sh)。範囲外は None。"""
    if not isinstance(index, int) or index < 0 or index >= CHIP_COUNT:
        return None
    col = index % CHIPS_PER_ROW
    row = index // CHIPS_PER_ROW
    return (col * CHIP_SIZE, row * CHIP_HEIGHT, CHIP_SIZE, CHIP_HEIGHT)


def has_board(attr: int) -> bool:
    return (attr & 0x08) != 0


def board_chip_index(chip_byte: int) -> int:
    """看板overlayに使うチップindex(下地が硬質面か否かで分岐)。"""
    return BOARD_CHIP_HARD if chip_byte in _HARD_BOARD_CHIPS else BOARD_CHIP_SOFT


def has_item(attr: int) -> bool:
    return (attr & 0x70) != 0


def item_no(attr: int) -> int:
    return (attr & 0x70) >> 4


def is_circle_chip(chip_byte: int) -> bool:
    return chip_byte in _CIRCLE_CHIPS


def item_draw_rect(
    no: int, chip_byte: int, dst_x: int, dst_y: int
) -> tuple[int, int, int, int, int, int, int, int]:
    """アイテム描画の src/dst 矩形(sx, sy, sw, sh, dx, dy, dw, dh)。"""
    s = ITEM_SPRITE_SIZE
    src_x = no * s
    draw_y = dst_y - ITEM_Y_ABOVE_FLOOR
    if is_circle_chip(chip_byte):
        src_y = 5 if no in (5, 6) else 0
        return (src_x, src_y, s, ITEM_CLIP_H, dst_x, draw_y, s, ITEM_CLIP_H)
    return (src_x, 0, s, s, dst_x, draw_y, s, s)


def dir_to_row(dir_value: str | int) -> int:
    """キャラdir(文字/数値) → チップシート行(0-3)。既定は F(2, 正面)。"""
    if isinstance(dir_value, int):
        return _DIR_TO_ROW[_DIR_NUM_TO_CHAR.get(dir_value & 7, "F")]
    return _DIR_TO_ROW.get(dir_value, _DIR_TO_ROW["F"])


def is_giant(gigant: str | None) -> bool:
    return gigant == "*"


def arrange_row(chars: list[Chara]) -> list[tuple[Chara, int]]:
    """1行のキャラを描く順と、横にずらす量(px)。(x, layer) の順に描きます。"""
    ordered = sorted(chars, key=lambda c: (c.x, c.layer))
    out: list[tuple[Chara, int]] = []
    i = 0
    while i < len(ordered):
        j = i
        while j < len(ordered) and ordered[j].x == ordered[i].x:
            j += 1
        cell = ordered[i:j]
        i = j
        if len(cell) == 2:
            a, b = cell
            ga, gb = is_giant(a.gigant), is_giant(b.gigant)
            if not ga and not gb:
                out.append((a, -8))
                out.append((b, 8))
                continue
            if ga != gb:
                big, small = (a, b) if ga else (b, a)
                out.append((big, 0))
                out.append((small, 8))
                continue
        for ch in cell:
            out.append((ch, 0))
    return out


def chara_src_rect(
    dir_value: str | int, gigant: str | None, anim_frame: int = 0, large: bool = False
) -> tuple[int, int, int, int]:
    """キャラスプライトのソース矩形。

    96px幅レイアウト: [小frame0=16][小frame1=16][大frame0=32][大frame1=32]。
    行 = dir(B/R/F/L)。frame = anim(0/1)。
    """
    row = dir_to_row(dir_value)
    frame = anim_frame & 1
    sy = row * CHARA_H
    if large or is_giant(gigant):
        sx = CHARA_W_NORMAL * 2 + frame * CHARA_W_GIANT
        return (sx, sy, CHARA_W_GIANT, CHARA_H)
    return (frame * CHARA_W_NORMAL, sy, CHARA_W_NORMAL, CHARA_H)


def magnified_dst(
    base_x: int, base_y: int, m: Magnify
) -> tuple[int, int, int, int]:
    """magnify 適用後の描画矩形(dx, dy, dw, dh)。"""
    dx = base_x - (m.w - CHARA_H) // 2
    dy = base_y - (((m.h - CHARA_H) * 5) // 6 + m.z)
    return (dx, dy, m.w, m.h)


def water_quarter_patterns(
    water: list[list[int]], wy: int, wx: int
) -> tuple[int, int, int, int]:
    """水セルの周りの水有無から各 quarter の3bitパターンを計算します。"""
    return (
        water[wy][wx] | (water[wy][wx + 1] << 1) | (water[wy + 1][wx] << 2),
        water[wy][wx + 2] | (water[wy][wx + 1] << 1) | (water[wy + 1][wx + 2] << 2),
        water[wy + 2][wx] | (water[wy + 2][wx + 1] << 1) | (water[wy + 1][wx] << 2),
        water[wy + 2][wx + 2] | (water[wy + 2][wx + 1] << 1) | (water[wy + 1][wx + 2] << 2),
    )


def water_quarter_chip(
    q_index: int, pattern: int
) -> tuple[int, int] | None:
    """quarter のパターンから描画する水縁チップを解決します。

    (chipIndex, srcQuarter) か、overlay不要なら None です。
    """
    entry = Q_TABLE[q_index].get(pattern)
    if entry is None:
        return None
    return (WATER_CHIP_BASE + entry[0], entry[1])


def chip_quarter_src_rect(
    chip_index: int, quarter: int
) -> tuple[int, int, int, int] | None:
    """チップindex + quarter(0=TL,1=TR,2=BL,3=BR) → シート上の16×16矩形。"""
    base = chip_src_rect(chip_index)
    if base is None:
        return None
    half = CHIP_SIZE // 2
    sx = base[0] + (quarter & 1) * half
    sy = base[1] + (CHIP_HEIGHT - CHIP_SIZE) + ((quarter >> 1) & 1) * half
    return (sx, sy, half, half)


def build_water_grid(cells: list[Cell], dim: int) -> list[list[int]]:
    """水有無の (dim+2)×(dim+2) 配列を作ります(枠=0)。"""
    water = [[0] * (dim + 2) for _ in range(dim + 2)]
    for r in range(dim):
        for c in range(dim):
            cell = cells[r * dim + c] if r * dim + c < len(cells) else None
            if cell is not None and cell.chip == WATER_BYTE:
                water[r + 1][c + 1] = 1
    return water


def grid_dim(size: int) -> int:
    return 5 if size == 5 else 7


def eagle_board(ev: EagleEyeEvent) -> tuple[int, list[Cell], list[Chara]]:
    """EagleEye のマスを正方形の盤面にします。

    人のマスは属性を消して、既定グラの人を置きます。盤面の外は
    「不明な場所」のチップで埋めます。
    """
    dim = max(ev.width, ev.height, 1)
    unknown = ord("?")
    cells = [Cell(chip=unknown, attr=0) for _ in range(dim * dim)]
    chars: list[Chara] = []
    for y in range(ev.height):
        for x in range(ev.width):
            idx = y * ev.width + x
            if idx >= len(ev.cells):
                continue
            c = ev.cells[idx]
            if c.attr == PERSON_ATTR:
                cells[y * dim + x] = Cell(chip=c.chip, attr=0)
                chars.append(
                    Chara(
                        id=0, x=x, y=y, dir="F", name="", gra=PERSON_GRA,
                        status=0, gigant="*", layer=0, default=0x40,
                    )
                )
            else:
                cells[y * dim + x] = c
    return dim, cells, chars


@dataclass
class Label:
    """キャラ名ラベルの位置。``x`` は中心、``y`` は上の端です。"""

    x: int
    y: int
    name: str


@dataclass
class Placeholder:
    """絵が無いキャラの頭文字の位置。``x`` と ``y`` は中心です。"""

    x: int
    y: int
    name: str


@dataclass
class Anchor:
    """フロート表示の基準点。``x`` は中心、``y`` はキャラの頭の上です。"""

    x: int
    y: int
    name: str
    cell_x: int
    cell_y: int


@dataclass
class RenderedMap:
    image: RgbaImage
    labels: list[Label]
    placeholders: list[Placeholder]
    anchors: list[Anchor] = field(default_factory=list)


def _draw_chip(
    img: RgbaImage, sheet: RgbaImage, index: int, col: int, row: int
) -> None:
    """1チップを1セルへ描きます。等倍なので stretch 描画だけです。"""
    rect = chip_src_rect(index)
    if rect is None:
        return
    sx, sy, sw, sh = rect
    overhang = CHIP_HEIGHT - CHIP_SIZE
    img.blit(sheet, sx, sy, sw, sh, col * CHIP_SIZE, row * CHIP_SIZE - overhang + MAP_TOP)


def _fallback_cell(img: RgbaImage, cell: Cell, col: int, row: int) -> None:
    """絵が無い時、マスをチップindexの色で塗ります。"""
    indices = chip_indices(cell.chip)
    color = FALLBACK_CHIP_COLORS.get(indices[0], FALLBACK_CHIP_DEFAULT)
    img.fill_rect(
        col * CHIP_SIZE, row * CHIP_SIZE + MAP_TOP, CHIP_SIZE, CHIP_SIZE, (*color, 255)
    )


def render_map_image(
    cells: list[Cell],
    chars: list[Chara],
    dim: int,
    chip_sheets: list[RgbaImage | None],
    items: RgbaImage | None,
    chara_image,
    anim_frame: int = 0,
    eagle_eye: bool = False,
    ghosts: list[tuple[Chara, RgbaImage]] | None = None,
) -> RenderedMap:
    """地図を1枚の画像に描きます。

    ``chip_sheets`` は属性の下位2ビット(#mapset-define の番号)ごとの
    チップシート4枚です。無いものは None で、色で塗る代わりにします。
    ``chara_image`` はキャラから画像を返す関数で、無い時は None を返します。
    ``ghosts`` は倒れたキャラの残像で、(キャラ, あらかじめ薄くした絵)の
    並びです。同じ行のキャラの後で描くので、下の行の壁の後ろに足が
    隠れます。ずらさず、名札も基準点も出しません。
    """
    img = RgbaImage(dim * CHIP_SIZE, dim * CHIP_SIZE + MAP_TOP, fill=(0, 0, 0, 255))
    labels: list[Label] = []
    placeholders: list[Placeholder] = []
    sheets = list(chip_sheets) + [None] * (4 - len(chip_sheets))

    def chip_for(cell: Cell) -> RgbaImage | None:
        return sheets[cell.attr & 0x03]

    any_sheet = any(s is not None for s in sheets)
    water = build_water_grid(cells, dim) if any_sheet else None
    half = CHIP_SIZE // 2
    ghosts_by_row: dict[int, list[tuple[Chara, RgbaImage]]] = {}
    for ghost_ch, ghost_sheet in ghosts or []:
        if 0 <= ghost_ch.x < dim and 0 <= ghost_ch.y < dim:
            ghosts_by_row.setdefault(ghost_ch.y, []).append((ghost_ch, ghost_sheet))

    for row in range(dim):
        # 1. ベースチップ
        for col in range(dim):
            idx = row * dim + col
            if idx >= len(cells):
                continue
            cell = cells[idx]
            sheet = chip_for(cell)
            if sheet is None:
                _fallback_cell(img, cell, col, row)
                continue
            for chip_index in chip_indices(cell.chip):
                _draw_chip(img, sheet, chip_index, col, row)
        # 1.5 水縁overlay
        if water is not None:
            for col in range(dim):
                idx = row * dim + col
                if idx >= len(cells):
                    continue
                cell = cells[idx]
                sheet = chip_for(cell)
                if sheet is None or cell.chip != WATER_BYTE:
                    continue
                patterns = water_quarter_patterns(water, row, col)
                cell_x = col * CHIP_SIZE
                cell_y = row * CHIP_SIZE + MAP_TOP
                for q in range(4):
                    hit = water_quarter_chip(q, patterns[q])
                    if hit is None:
                        continue
                    rect = chip_quarter_src_rect(hit[0], hit[1])
                    if rect is None:
                        continue
                    img.blit(
                        sheet, rect[0], rect[1], rect[2], rect[3],
                        cell_x + (q & 1) * half, cell_y + ((q >> 1) & 1) * half,
                    )
        # 2. 看板overlay
        for col in range(dim):
            idx = row * dim + col
            if idx >= len(cells):
                continue
            cell = cells[idx]
            if not has_board(cell.attr):
                continue
            sheet = chip_for(cell)
            if sheet is not None:
                _draw_chip(img, sheet, board_chip_index(cell.chip), col, row)
        # 3. アイテムoverlay
        for col in range(dim):
            idx = row * dim + col
            if idx >= len(cells):
                continue
            cell = cells[idx]
            if not has_item(cell.attr):
                continue
            if eagle_eye:
                sheet = chip_for(cell)
                if sheet is not None:
                    _draw_chip(img, sheet, EAGLE_EYE_ITEM_CHIP, col, row)
            elif items is not None:
                r = item_draw_rect(
                    item_no(cell.attr), cell.chip,
                    col * CHIP_SIZE, row * CHIP_SIZE + MAP_TOP,
                )
                img.blit(items, r[0], r[1], r[2], r[3], r[4], r[5])
            else:
                img.fill_rect(
                    col * CHIP_SIZE + 8, row * CHIP_SIZE + MAP_TOP + 8, 16, 16,
                    (255, 255, 200, 255),
                )
        # 4. キャラ(この行)
        row_chars = [c for c in chars if c.y == row and 0 <= c.x < dim]
        for ch, dx in arrange_row(row_chars):
            _draw_chara(img, ch, dx, anim_frame, chara_image, eagle_eye, placeholders)
        # 4.5 残像(この行)。ずらさず、この行のキャラの上に重ねます。
        for ghost_ch, ghost_sheet in ghosts_by_row.get(row, []):
            _draw_chara(
                img, ghost_ch, 0, anim_frame,
                lambda _ch, sheet=ghost_sheet: sheet,
                eagle_eye, placeholders,
            )

    # 5. キャラ名ラベル(中心=自キャラは除外)。同じマスは後勝ちです。
    cx = dim // 2
    cy = dim // 2
    per_cell: dict[tuple[int, int], Label] = {}
    for c in chars:
        if not (0 <= c.x < dim and 0 <= c.y < dim):
            continue
        if c.x == cx and c.y == cy:
            continue
        name = strip_tags(c.name).strip()
        if not name:
            continue
        per_cell[(c.x, c.y)] = Label(
            x=c.x * CHIP_SIZE + CHIP_SIZE // 2,
            y=c.y * CHIP_SIZE + int(CHIP_SIZE * 0.6) + MAP_TOP,
            name=name,
        )
    labels = list(per_cell.values())
    # フロート表示の基準点(中心の自キャラも含みます)。頭の上です。
    head_top = (CHIP_SIZE - CHARA_H) // 2 - CHARA_Y_ABOVE_FLOOR + MAP_TOP
    anchors: list[Anchor] = []
    for c in chars:
        if not (0 <= c.x < dim and 0 <= c.y < dim):
            continue
        name = strip_tags(c.name).strip()
        if not name:
            continue
        anchors.append(Anchor(
            x=c.x * CHIP_SIZE + CHIP_SIZE // 2,
            y=c.y * CHIP_SIZE + head_top,
            name=name, cell_x=c.x, cell_y=c.y,
        ))
    return RenderedMap(image=img, labels=labels, placeholders=placeholders,
                       anchors=anchors)


def _draw_chara(
    img: RgbaImage,
    ch: Chara,
    dx: int,
    anim_frame: int,
    chara_image,
    eagle_eye: bool,
    placeholders: list[Placeholder],
) -> None:
    rect = chara_src_rect(ch.dir, ch.gigant, anim_frame)
    sx, sy, sw, sh = rect
    raise_px = 0 if eagle_eye else CHARA_Y_ABOVE_FLOOR
    base_x = ch.x * CHIP_SIZE + (CHIP_SIZE - sw) // 2 + dx
    base_y = ch.y * CHIP_SIZE + (CHIP_SIZE - CHARA_H) // 2 - raise_px + MAP_TOP
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
