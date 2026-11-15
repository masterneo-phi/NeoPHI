"""地図を文字で描く。仕様書 §5。

地形の1マスはチップの文字と属性の組で表す。文字の地図では、チップの文字を
そのまま出し、キャラは重ねて記号で出す。BMP の絵による描画は後の段階で行う。
"""

from __future__ import annotations

from .parser import Cell, EagleEyeEvent, MapEvent

__all__ = ["CHIP_BYTE_TO_INDEX", "chip_indices", "render_eagle_eye", "render_map"]

#: チップの文字 → チップの絵の番号(wphi の CHIP_BYTE_TO_INDEX と同じ)。
CHIP_BYTE_TO_INDEX: dict[int, int | list[int]] = {
    ord(" "): 0,
    ord(":"): 1,
    ord("+"): 2,
    ord("T"): [1, 3],
    ord("_"): 4,
    ord("o"): 5,
    ord("@"): 6,
    ord("#"): 7,
    ord("H"): 8,
    ord("I"): 9,
    ord("="): 10,
    ord("["): 11,
    ord("{"): 12,
    ord("|"): 13,
    ord("x"): 14,
    ord("%"): 15,
    ord("/"): 16,
    ord(">"): 17,
    ord("?"): 31,
    ord("s"): 0,
}


def chip_indices(chip_byte: int) -> list[int]:
    """チップのバイト → 描くチップの番号の配列。知らないバイトは 0。"""
    value = CHIP_BYTE_TO_INDEX.get(chip_byte, 0)
    return value if isinstance(value, list) else [value]


# 自分の向き。端末での幅が1文字と決まっている ASCII の矢印を使う
# (▲などの記号は、端末やフォントで幅が1か2か変わり、地図がずれる)。
_DIR_ARROWS = {0: "^", 2: ">", 4: "v", 6: "<"}
_DIR_NAMES = {0: "N", 2: "E", 4: "S", 6: "W"}


def _chip_char(chip: int) -> str:
    if chip == ord("s"):
        return " "
    if 32 <= chip < 127:
        return chr(chip)
    return "·"


def _cell_char(cell: Cell) -> str:
    if cell.attr & 0x08:
        return "!"
    item_no = (cell.attr & 0x70) >> 4
    if item_no:
        return str(item_no)
    return _chip_char(cell.chip)


def render_map(event: MapEvent) -> list[str]:
    """地図イベントを、文字の行の配列にする。"""
    size = event.size
    cells = list(event.cells)
    if len(cells) < size * size:
        cells += [Cell(chip=ord("?"), attr=0)] * (size * size - len(cells))
    by_pos: dict[tuple[int, int], list] = {}
    for chara in event.chars:
        by_pos.setdefault((chara.x, chara.y), []).append(chara)

    center = (size // 2, size // 2)
    lines: list[str] = []
    for y in range(size):
        row: list[str] = []
        for x in range(size):
            stacked = by_pos.get((x, y), [])
            if (x, y) == center and size == 7:
                row.append(_DIR_ARROWS.get(event.dir, "?"))
            elif len(stacked) > 1:
                row.append("+")
            elif len(stacked) == 1:
                row.append("*" if stacked[0].gigant == "*" else "@")
            else:
                row.append(_cell_char(cells[y * size + x]))
        lines.append("".join(row))

    header = f"地図 {size}x{size} 向き={_DIR_NAMES.get(event.dir, str(event.dir))}"
    if event.style:
        header += f" {event.style}"
    if event.pos is not None:
        header += f" 座標=({event.pos.x},{event.pos.y})"
    out = [header, *lines]
    if event.chars:
        out.append("--- キャラ ---")
        for chara in sorted(event.chars, key=lambda c: (c.layer, c.y, c.x, c.name)):
            out.append(f"({chara.x},{chara.y}) {chara.name} [{chara.gra}] {chara.dir}")
    return out


def render_eagle_eye(event: EagleEyeEvent) -> list[str]:
    """EagleEye の図を、文字の行の配列にする。属性 0x58 のマスは人がいる所。"""
    out = [f"EagleEye {event.width}x{event.height}"]
    if event.mapset:
        out[0] += f" {event.mapset}"
    for y in range(event.height):
        row: list[str] = []
        for x in range(event.width):
            idx = y * event.width + x
            cell = event.cells[idx] if idx < len(event.cells) else Cell()
            if (x, y) == (event.self_pos.x, event.self_pos.y):
                row.append("@")
            elif cell.attr == 0x58:
                row.append("P")
            else:
                row.append(_chip_char(cell.chip))
        out.append("".join(row))
    return out
