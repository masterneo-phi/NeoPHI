"""3Dレンダラの試し描きの道具。

見本の地図を3Dで描き、PNG で残します。カメラの角度・高さ・距離・
画角を変えられます。--turntable で、地図の周りを回る絵も作れます。

使い方:
    python tools/render_3d.py --assets-dir <Philly のフォルダ> --out-dir /tmp/3d
    python tools/render_3d.py --assets-dir <Philly のフォルダ> --out-dir /tmp/3d --turntable 8
"""

from __future__ import annotations

import argparse
import importlib.util
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from neophi.assets import Assets  # noqa: E402
from neophi.bmp import RgbaImage  # noqa: E402
from neophi.map_3d import Camera, render_3d_image  # noqa: E402
from neophi.map_graphics import grid_dim  # noqa: E402
from neophi.png import encode_png  # noqa: E402


def _load_sample():
    path = Path(__file__).resolve().parent / "render_map.py"
    spec = importlib.util.spec_from_file_location("render_map", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module.sample_map(), module.sample_eagle_eye()


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="見本の地図を3Dで描きます")
    parser.add_argument("--assets-dir", action="append", default=[],
                        help="Philly のフォルダ(繰り返し指定でき、先が優先)")
    parser.add_argument("--skin", default="Mine")
    parser.add_argument("--out-dir", default=".", help="PNG を置くフォルダ")
    parser.add_argument("--anim-frame", type=int, default=0, choices=(0, 1))
    parser.add_argument("--azimuth", type=float, default=0.0,
                        help="カメラの方位角(度)。0 が南、90 が東(既定: 0)")
    parser.add_argument("--elevation", type=float, default=38.0,
                        help="カメラの見上げ角(度。既定: 38)")
    parser.add_argument("--distance", type=float, default=8.5,
                        help="地図の中心からの距離(既定: 8.5)")
    parser.add_argument("--fov", type=float, default=45.0,
                        help="縦の画角(度。既定: 45)")
    parser.add_argument("--width", type=int, default=320)
    parser.add_argument("--height", type=int, default=240)
    parser.add_argument("--turntable", type=int, default=0, metavar="N",
                        help="地図の周りを N 枚で回る絵も作ります")
    parser.add_argument("--style", default="extrude", choices=("boxes", "extrude"),
                        help="形の作り方(既定: extrude)。boxes は箱に絵を貼り、"
                        "extrude は絵の輪郭を立体物に押し出します")
    args = parser.parse_args(argv)

    assets = Assets(args.assets_dir, skin=args.skin)
    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    event, _eagle = _load_sample()
    dim = grid_dim(event.size)

    def sheets():
        return [assets.chip("")] * 4

    def chara_image(ch):
        return assets.chara(ch.name, ch.gra, ch.default)

    def render(camera: Camera, name: str) -> RgbaImage:
        start = time.monotonic()
        rendered = render_3d_image(
            event.cells, event.chars, dim,
            sheets(), assets.items(), chara_image, camera,
            anim_frame=args.anim_frame, style=args.style,
        )
        elapsed = time.monotonic() - start
        path = out_dir / f"{name}.png"
        path.write_bytes(encode_png(rendered.image))
        print(f"{name}: {path} ({rendered.image.width}x{rendered.image.height}, "
              f"{elapsed:.1f}秒)")
        return rendered.image

    base = Camera(
        azimuth=args.azimuth, elevation=args.elevation,
        distance=args.distance, fov=args.fov,
        width=args.width, height=args.height,
    )
    render(base, "view3d")

    if args.turntable > 0:
        frames = []
        for i in range(args.turntable):
            azimuth = i * 360.0 / args.turntable
            camera = Camera(
                azimuth=azimuth, elevation=args.elevation,
                distance=args.distance, fov=args.fov,
                width=args.width, height=args.height,
            )
            frames.append(render(camera, f"turn_{i:02d}"))
        gap = 8
        strip = RgbaImage(
            sum(f.width for f in frames) + gap * (len(frames) - 1),
            max(f.height for f in frames), fill=(0, 0, 0, 255),
        )
        x = 0
        for frame in frames:
            strip.blit(frame, 0, 0, frame.width, frame.height, x, 0)
            x += frame.width + gap
        path = out_dir / "turntable_strip.png"
        path.write_bytes(encode_png(strip))
        print(f"回転: {path} ({strip.width}x{strip.height})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
