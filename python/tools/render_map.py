"""地図の描画を PNG で確かめる道具。GUI を開かずに絵を見られます。

色々な地形・看板・アイテム・キャラを並べた見本の地図と EagleEye の盤面を
描き、PNG で残します。

使い方:
    python tools/render_map.py --assets-dir <Philly のフォルダ> --out-dir /tmp/maps
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from neophi.assets import Assets  # noqa: E402
from neophi.map_graphics import (  # noqa: E402
    eagle_board,
    grid_dim,
    render_map_image,
)
from neophi.parser import Cell, Chara, EagleEyeEvent, Magnify, MapEvent  # noqa: E402
from neophi.png import encode_png  # noqa: E402


def sample_map() -> MapEvent:
    """色々な地形とキャラを並べた 7x7 の地図。"""
    chips = [
        " ", ":", "+", "T", "_", "o", "@",
        "#", "H", "I", "=", "[", "{", "|",
        "x", "%", "/", ">", "?", "s", " ",
        "_", "_", "T", ":", "+", "o", "@",
        "#", "H", "I", "=", "[", "{", "|",
        "x", "%", "/", ">", "?", "s", " ",
        " ", ":", "+", "T", "_", "o", "@",
    ]
    cells = []
    for i, ch in enumerate(chips):
        attr = 0
        if i in (3, 10, 24):  # 看板
            attr |= 0x08
        if i in (5, 17, 31):  # アイテム
            attr |= 0x30
        if i == 14:  # 防御円の上のアイテム
            attr |= 0x50
        cells.append(Cell(chip=ord(ch), attr=attr))
    chars = [
        Chara(id=1, x=3, y=3, dir="B", name="自分", gra="t_man", gigant="#",
              layer=0, default=0x00),
        Chara(id=2, x=4, y=3, dir="L", name="モック太郎", gra="npc2", gigant="#",
              layer=1, default=0x01),
        Chara(id=3, x=4, y=3, dir="F", name="モック花子", gra="t_elf", gigant="#",
              layer=2, default=0x01),
        Chara(id=4, x=2, y=2, dir="R", name="大きな犬", gra="t_dog", gigant="*",
              layer=0, default=0x02),
        Chara(id=5, x=5, y=5, dir="F", name="看板", gra="", gigant="#",
              layer=0, default=0x81),
        Chara(id=6, x=1, y=5, dir="B", name="巨大な像", gra="t_golem1",
              gigant="*", layer=0, default=0x04,
              magnify=Magnify(w=64, h=64, z=8)),
        Chara(id=7, x=0, y=0, dir="F", name="無いグラ", gra="no-such-gra",
              gigant="#", layer=0, default=0x01),
    ]
    return MapEvent(size=7, dir=0, cells=cells, chars=chars, style="solid")


def sample_eagle_eye() -> EagleEyeEvent:
    cells = []
    for y in range(9):
        for x in range(9):
            chip = ord("_") if (x + y) % 4 == 0 else ord(":")
            attr = 0x58 if (x, y) == (6, 2) else 0
            if (x, y) == (2, 6):
                attr = 0x20
            cells.append(Cell(chip=chip, attr=attr))
    return EagleEyeEvent(width=9, height=9, cells=cells)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="見本の地図を PNG で描きます")
    parser.add_argument("--assets-dir", action="append", default=[],
                        help="Philly のフォルダ(繰り返し指定でき、先が優先)")
    parser.add_argument("--skin", default="Mine")
    parser.add_argument("--out-dir", default=".", help="PNG を置くフォルダ")
    parser.add_argument("--anim-frame", type=int, default=0, choices=(0, 1))
    args = parser.parse_args(argv)

    assets = Assets(args.assets_dir, skin=args.skin)
    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    event = sample_map()
    rendered = render_map_image(
        event.cells, event.chars, grid_dim(event.size),
        [assets.chip(""), assets.chip(""), assets.chip(""), assets.chip("")],
        assets.items(),
        lambda ch: assets.chara(ch.name, ch.gra, ch.default),
        anim_frame=args.anim_frame,
    )
    map_path = out_dir / "map.png"
    map_path.write_bytes(encode_png(rendered.image))
    print(f"地図: {map_path} ({rendered.image.width}x{rendered.image.height})")

    eagle = sample_eagle_eye()
    dim, cells, chars = eagle_board(eagle)
    rendered_eagle = render_map_image(
        cells, chars, dim,
        [assets.chip(""), assets.chip(""), assets.chip(""), assets.chip("")],
        assets.items(),
        lambda ch: assets.chara(ch.name, ch.gra, ch.default),
        anim_frame=args.anim_frame, eagle_eye=True,
    )
    eagle_path = out_dir / "eagleeye.png"
    eagle_path.write_bytes(encode_png(rendered_eagle.image))
    print(f"EagleEye: {eagle_path} ({rendered_eagle.image.width}x{rendered_eagle.image.height})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
