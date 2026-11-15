"""絵を歪ませずに立体感を出す、試しの描画です。

クオータービューは、床の絵を斜めに潰すのでドット絵が崩れました。
こちらは床を1ドットも動かさず、代わりに次の3つで高さを出します。

- 壁や木の「高さの部分」(チップの上16px)だけを縦に引き伸ばす。
  縦の伸ばしは横の絵を壊しません。
- キャラとアイテムの足元に、落ち影を落とす。
- 壁の下の床に、接した影(コンタクトシャドウ)を落とす。

引数と返り値は ``map_graphics.render_map_image`` と同じです。
``height_stretch`` で高さの伸ばし具合を変えられます(1.0 が平面と同じ)。
"""

from __future__ import annotations

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
    ITEM_Y_ABOVE_FLOOR,
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

__all__ = ["render_depth_image"]

# 背が高いとみなすチップのバイト。壁・家・木などです。
# (本当は絵の中身を見ないと分からないので、見た目からの決め打ちです)
_TALL_CHIPS = frozenset(b"@#H=[{|%TI")


def _shadow_image(width: int, height: int, strength: int) -> RgbaImage:
    """楕円の落ち影。真ん中が一番濃く、縁へ向けて薄くなります。"""
    img = RgbaImage(width, height, fill=(0, 0, 0, 0))
    cx, cy = (width - 1) / 2, (height - 1) / 2
    for y in range(height):
        for x in range(width):
            dx = (x - cx) / (width / 2)
            dy = (y - cy) / (height / 2)
            d = dx * dx + dy * dy
            if d < 1:
                alpha = round(strength * (1 - d) ** 1.5)
                img.set_pixel(x, y, (0, 0, 0, alpha))
    return img


def _shade_rect(img: RgbaImage, x: int, y: int, w: int, h: int, alpha: int) -> None:
    """矩形を黒へ近づけます(接した影)。"""
    keep = 255 - alpha
    for py in range(max(0, y), min(img.height, y + h)):
        for px in range(max(0, x), min(img.width, x + w)):
            i = (py * img.width + px) * 4
            img.pixels[i] = img.pixels[i] * keep // 255
            img.pixels[i + 1] = img.pixels[i + 1] * keep // 255
            img.pixels[i + 2] = img.pixels[i + 2] * keep // 255


def render_depth_image(
    cells: list[Cell],
    chars: list[Chara],
    dim: int,
    chip_sheets: list[RgbaImage | None],
    items: RgbaImage | None,
    chara_image,
    anim_frame: int = 0,
    eagle_eye: bool = False,
    height_stretch: float = 2.0,
    shadows: bool = True,
    contact_shade: bool = True,
) -> RenderedMap:
    """地図を、床を歪ませずに立体感を付けて描きます。"""
    overhang = CHIP_HEIGHT - CHIP_SIZE  # 16
    top = max(overhang, round(overhang * height_stretch))
    height = dim * CHIP_SIZE + top
    img = RgbaImage(dim * CHIP_SIZE, height, fill=(0, 0, 0, 255))
    sheets = list(chip_sheets) + [None] * (4 - len(chip_sheets))

    def chip_for(cell: Cell) -> RgbaImage | None:
        return sheets[cell.attr & 0x03]

    any_sheet = any(s is not None for s in sheets)
    water = build_water_grid(cells, dim) if any_sheet else None
    shadow = _shadow_image(24, 8, 110) if shadows else None
    item_shadow = _shadow_image(20, 6, 90) if shadows else None

    def draw_chip(sheet: RgbaImage, index: int, x: int, y: int) -> None:
        rect = chip_src_rect(index)
        if rect is None:
            return
        sx, sy, _, _ = rect
        # 高さの部分は縦に引き伸ばして、床の上に立てます(下端を床の上端に合わせる)
        img.blit_scaled(sheet, sx, sy, CHIP_SIZE, overhang,
                        x, y, CHIP_SIZE, top)
        # 胴体はそのままの大きさで、床に置きます
        img.blit(sheet, sx, sy + overhang, CHIP_SIZE, CHIP_SIZE, x, y + top)

    chars_by_row: dict[int, list[Chara]] = {}
    for ch in chars:
        if 0 <= ch.x < dim and 0 <= ch.y < dim:
            chars_by_row.setdefault(ch.y, []).append(ch)

    labels: list[Label] = []
    placeholders: list[Placeholder] = []
    per_cell_label: dict[tuple[int, int], Label] = {}

    for row in range(dim):
        # 1. ベースチップ
        for col in range(dim):
            idx = row * dim + col
            if idx >= len(cells):
                continue
            cell = cells[idx]
            sheet = chip_for(cell)
            if sheet is None:
                indices = chip_indices(cell.chip)
                color = FALLBACK_CHIP_COLORS.get(indices[0], FALLBACK_CHIP_DEFAULT)
                img.fill_rect(col * CHIP_SIZE, row * CHIP_SIZE + top,
                              CHIP_SIZE, CHIP_SIZE, (*color, 255))
            else:
                for chip_index in chip_indices(cell.chip):
                    draw_chip(sheet, chip_index, col * CHIP_SIZE, row * CHIP_SIZE)
        # 1.5 壁の下の接した影
        if contact_shade and row > 0:
            for col in range(dim):
                idx = row * dim + col
                above = cells[(row - 1) * dim + col] if idx < len(cells) else None
                if above is None:
                    continue
                if above.chip in _TALL_CHIPS or has_board(above.attr):
                    _shade_rect(img, col * CHIP_SIZE, row * CHIP_SIZE + top,
                                CHIP_SIZE, 6, 70)
        # 2. 水縁
        if water is not None:
            for col in range(dim):
                idx = row * dim + col
                if idx >= len(cells):
                    continue
                cell = cells[idx]
                if cell.chip != ord("_"):
                    continue
                sheet = chip_for(cell)
                if sheet is None:
                    continue
                patterns = water_quarter_patterns(water, row, col)
                for q in range(4):
                    hit = water_quarter_chip(q, patterns[q])
                    if hit is None:
                        continue
                    rect = chip_quarter_src_rect(hit[0], hit[1])
                    if rect is None:
                        continue
                    img.blit(
                        sheet, rect[0], rect[1], rect[2], rect[3],
                        col * CHIP_SIZE + (q & 1) * 16,
                        row * CHIP_SIZE + top + ((q >> 1) & 1) * 16,
                    )
        # 3. 看板
        for col in range(dim):
            idx = row * dim + col
            if idx >= len(cells):
                continue
            cell = cells[idx]
            if not has_board(cell.attr):
                continue
            sheet = chip_for(cell)
            if sheet is not None:
                draw_chip(sheet, board_chip_index(cell.chip),
                          col * CHIP_SIZE, row * CHIP_SIZE)
        # 4. アイテム
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
                    draw_chip(sheet, EAGLE_EYE_ITEM_CHIP,
                              col * CHIP_SIZE, row * CHIP_SIZE)
                continue
            if items is None:
                img.fill_rect(col * CHIP_SIZE + 8, row * CHIP_SIZE + top + 8,
                              16, 16, (255, 255, 200, 255))
                continue
            no = item_no(cell.attr)
            s = ITEM_SPRITE_SIZE
            if item_shadow is not None:
                img.blit(item_shadow, 0, 0, item_shadow.width, item_shadow.height,
                         col * CHIP_SIZE + 6, row * CHIP_SIZE + top + 18)
            if is_circle_chip(cell.chip):
                src_y = 5 if no in (5, 6) else 0
                img.blit(items, no * s, src_y, s, ITEM_CLIP_H,
                         col * CHIP_SIZE, row * CHIP_SIZE + top - ITEM_Y_ABOVE_FLOOR)
            else:
                img.blit(items, no * s, 0, s, s,
                         col * CHIP_SIZE, row * CHIP_SIZE + top - ITEM_Y_ABOVE_FLOOR)
        # 5. キャラ
        for ch, dx in arrange_row(chars_by_row.get(row, [])):
            rect = chara_src_rect(ch.dir, ch.gigant, anim_frame)
            sx, sy, sw, sh = rect
            base_x = ch.x * CHIP_SIZE + (CHIP_SIZE - sw) // 2 + dx
            base_y = ch.y * CHIP_SIZE + top - CHARA_Y_ABOVE_FLOOR
            if eagle_eye:
                base_y = ch.y * CHIP_SIZE + top
            if shadow is not None:
                img.blit(shadow, 0, 0, shadow.width, shadow.height,
                         base_x + sw // 2 - shadow.width // 2, base_y + sh - 6)
            sprite = chara_image(ch)
            if sprite is None:
                img.fill_rect(base_x, base_y, sw, sh, (255, 255, 0, 255))
                placeholders.append(
                    Placeholder(
                        x=base_x + sw // 2, y=base_y + sh // 2,
                        name=strip_tags(ch.name).strip(),
                    )
                )
            elif ch.magnify is not None:
                d = magnified_dst(base_x, base_y, ch.magnify)
                img.blit_scaled(sprite, sx, sy, sw, sh, d[0], d[1], d[2], d[3])
            else:
                img.blit(sprite, sx, sy, sw, sh, base_x, base_y)
            name = strip_tags(ch.name).strip()
            if name:
                per_cell_label[(ch.x, ch.y)] = Label(
                    x=ch.x * CHIP_SIZE + CHIP_SIZE // 2,
                    y=ch.y * CHIP_SIZE + top + int(CHIP_SIZE * 0.6),
                    name=name,
                )

    cx = dim // 2
    cy = dim // 2
    labels = [label for (x, y), label in per_cell_label.items()
              if not (x == cx and y == cy)]
    return RenderedMap(image=img, labels=labels, placeholders=placeholders)
