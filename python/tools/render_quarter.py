"""平面とクオータービューの見え方を比べる道具。

見本の地図を、平面と3つのクオータービュー(tilt / oblique / iso)で描き、
PNG で残します。比べやすいよう、縦に並べた1枚も作ります。

使い方:
    python tools/render_quarter.py --assets-dir <Philly のフォルダ> --out-dir /tmp/quarter
"""

from __future__ import annotations

import argparse
import importlib.util
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from neophi.assets import Assets  # noqa: E402
from neophi.bmp import RgbaImage  # noqa: E402
from neophi.map_graphics import grid_dim, render_map_image  # noqa: E402
from neophi.map_quarter import PRESETS, QuarterView, render_quarter_image  # noqa: E402
from neophi.png import encode_png  # noqa: E402


def _load_sample():
    """render_map.py の見本の場面を使います。"""
    path = Path(__file__).resolve().parent / "render_map.py"
    spec = importlib.util.spec_from_file_location("render_map", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module.sample_map(), module.sample_eagle_eye()


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="平面とクオータービューを比べます")
    parser.add_argument("--assets-dir", action="append", default=[],
                        help="Philly のフォルダ(繰り返し指定でき、先が優先)")
    parser.add_argument("--skin", default="Mine")
    parser.add_argument("--out-dir", default=".", help="PNG を置くフォルダ")
    parser.add_argument("--anim-frame", type=int, default=0, choices=(0, 1))
    parser.add_argument("--presets", default="tilt,oblique,iso",
                        help="描く見方を , 区切りで(既定: tilt,oblique,iso)")
    parser.add_argument("--u", default=None, metavar="X,Y",
                        help="自分で試す写し方の x 方向の基底(例: 32,0)")
    parser.add_argument("--v", default=None, metavar="X,Y",
                        help="自分で試す写し方の y 方向の基底(例: 8,20)")
    args = parser.parse_args(argv)

    assets = Assets(args.assets_dir, skin=args.skin)
    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    event, _eagle = _load_sample()

    def sheets():
        return [assets.chip("")] * 4

    def chara_image(ch):
        return assets.chara(ch.name, ch.gra, ch.default)

    images: list[tuple[str, RgbaImage]] = []
    flat = render_map_image(
        event.cells, event.chars, grid_dim(event.size),
        sheets(), assets.items(), chara_image, anim_frame=args.anim_frame,
    )
    images.append(("flat", flat.image))
    for name in args.presets.split(","):
        name = name.strip()
        if name not in PRESETS:
            print(f"知らない見方です: {name}", file=sys.stderr)
            return 2
        rendered = render_quarter_image(
            event.cells, event.chars, grid_dim(event.size),
            sheets(), assets.items(), chara_image, PRESETS[name],
            anim_frame=args.anim_frame,
        )
        images.append((name, rendered.image))
    if args.u is not None or args.v is not None:
        if args.u is None or args.v is None:
            print("--u と --v は両方指定してください", file=sys.stderr)
            return 2
        try:
            u = tuple(float(v) for v in args.u.split(","))
            v = tuple(float(v) for v in args.v.split(","))
        except ValueError:
            print("--u / --v は X,Y の数で指定してください", file=sys.stderr)
            return 2
        if len(u) != 2 or len(v) != 2:
            print("--u / --v は X,Y の2数で指定してください", file=sys.stderr)
            return 2
        custom = QuarterView("custom", u, v)
        rendered = render_quarter_image(
            event.cells, event.chars, grid_dim(event.size),
            sheets(), assets.items(), chara_image, custom,
            anim_frame=args.anim_frame,
        )
        images.append(("custom", rendered.image))

    for name, image in images:
        path = out_dir / f"quarter_{name}.png"
        path.write_bytes(encode_png(image))
        print(f"{name}: {path} ({image.width}x{image.height})")

    # 縦に並べた比べ用の1枚
    gap = 8
    width = max(image.width for _, image in images)
    height = sum(image.height for _, image in images) + gap * (len(images) - 1)
    combined = RgbaImage(width, height, fill=(0, 0, 0, 255))
    y = 0
    for _, image in images:
        combined.blit(image, 0, 0, image.width, image.height, 0, y)
        y += image.height + gap
    path = out_dir / "quarter_compare.png"
    path.write_bytes(encode_png(combined))
    print(f"比べ用: {path} ({width}x{height})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
