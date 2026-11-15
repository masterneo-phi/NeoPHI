"""平面と、絵を歪ませない立体感の描画を比べる道具。

見本の地図を、平面と高さの伸ばし具合の違う描画で出し、PNG で残します。
比べやすいよう、縦に並べた1枚も作ります。

使い方:
    python tools/render_depth.py --assets-dir <Philly のフォルダ> --out-dir /tmp/depth
"""

from __future__ import annotations

import argparse
import importlib.util
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from neophi.assets import Assets  # noqa: E402
from neophi.bmp import RgbaImage  # noqa: E402
from neophi.map_depth import render_depth_image  # noqa: E402
from neophi.map_graphics import grid_dim, render_map_image  # noqa: E402
from neophi.png import encode_png  # noqa: E402


def _load_sample():
    path = Path(__file__).resolve().parent / "render_map.py"
    spec = importlib.util.spec_from_file_location("render_map", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module.sample_map(), module.sample_eagle_eye()


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="平面と立体感の描画を比べます")
    parser.add_argument("--assets-dir", action="append", default=[],
                        help="Philly のフォルダ(繰り返し指定でき、先が優先)")
    parser.add_argument("--skin", default="Mine")
    parser.add_argument("--out-dir", default=".", help="PNG を置くフォルダ")
    parser.add_argument("--anim-frame", type=int, default=0, choices=(0, 1))
    parser.add_argument("--stretches", default="1.5,2,3",
                        help="高さの伸ばし具合を , 区切りで(既定: 1.5,2,3)")
    parser.add_argument("--no-shadows", action="store_true",
                        help="落ち影を無しにします")
    parser.add_argument("--no-shade", action="store_true",
                        help="壁の下の影を無しにします")
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
    for text in args.stretches.split(","):
        try:
            stretch = float(text)
        except ValueError:
            print(f"伸ばし具合は数で指定してください: {text}", file=sys.stderr)
            return 2
        rendered = render_depth_image(
            event.cells, event.chars, grid_dim(event.size),
            sheets(), assets.items(), chara_image,
            anim_frame=args.anim_frame, height_stretch=stretch,
            shadows=not args.no_shadows, contact_shade=not args.no_shade,
        )
        name = f"depth{stretch:g}"
        images.append((name, rendered.image))

    for name, image in images:
        path = out_dir / f"{name}.png"
        path.write_bytes(encode_png(image))
        print(f"{name}: {path} ({image.width}x{image.height})")

    gap = 8
    width = max(image.width for _, image in images)
    height = sum(image.height for _, image in images) + gap * (len(images) - 1)
    combined = RgbaImage(width, height, fill=(0, 0, 0, 255))
    y = 0
    for _, image in images:
        combined.blit(image, 0, 0, image.width, image.height, 0, y)
        y += image.height + gap
    path = out_dir / "depth_compare.png"
    path.write_bytes(encode_png(combined))
    print(f"比べ用: {path} ({width}x{height})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
