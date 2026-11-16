#!/usr/bin/env python3
"""金属風テクスチャ(ガンメタル〜スチール)を手続き的に生成する。

出力: assets/metal.png (512x512)
使い方: python3 tools/make_metal_texture.py

暗い UI の上で文字が読めるよう、濃いめの金属にする。
横方向のブラシ目(細い横線の集まり)と細かい粒子ノイズで
質感を出し、上端に寄せた光と下端の影でベベルの感じも付ける。
横線は画面端まで伸ばすので、横方向にタイル状に並べても
継ぎ目が出ない。
アプリ側は assets/metal.png を防御的に読み込むので
(UiStyle.metal_texture)、この PNG が無くても動く。
"""

import random
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

W = 512
H = 512
SEED = 20261116

TOP = (63, 68, 76)     # 上端: スチール寄り
BOTTOM = (39, 43, 50)  # 下端: ガンメタル寄り


def main() -> None:
    rng = random.Random(SEED)

    # 地: 縦のグラデーション＋上端の光・下端の影(ベベル感)。
    img = Image.new("RGB", (W, H))
    px = img.load()
    for y in range(H):
        t = y / (H - 1)
        lift = 6.0 * max(0.0, 1.0 - y / 90.0) - 5.0 * max(0.0, (y - (H - 90)) / 90.0)
        row = tuple(int(TOP[i] + (BOTTOM[i] - TOP[i]) * t + lift) for i in range(3))
        for x in range(W):
            px[x, y] = row

    # 細かいノイズ(金属の粒子)。明暗を ±10 程度うねらせる。
    noise = Image.effect_noise((W, H), 30)
    npx = noise.load()
    for y in range(H):
        for x in range(W):
            d = int((npx[x, y] - 128) * 0.3)
            r, g, b = px[x, y]
            px[x, y] = (r + d, g + d, b + d)

    draw = ImageDraw.Draw(img, "RGBA")

    # ブラシ目: 細い横線を多数。明るい線と暗い線を混ぜる。
    for _ in range(2600):
        y = rng.randrange(H)
        alpha = rng.randint(3, 13)
        color = (235, 240, 248, alpha) if rng.random() < 0.5 else (0, 0, 0, alpha)
        # ほとんどは端から端まで(横タイルで継ぎ目なし)、
        # 一部は途中で切れる線にして単調さを避ける。
        if rng.random() < 0.75:
            x0, x1 = 0, W - 1
        else:
            x0 = rng.randrange(W)
            x1 = min(W - 1, x0 + rng.randint(30, 220))
        draw.line([(x0, y), (x1, y)], fill=color)

    # 少し太い、弱いうねり(研磨の跡)。
    for _ in range(90):
        y = rng.randrange(H)
        h = rng.randint(2, 5)
        alpha = rng.randint(3, 8)
        color = (220, 228, 238, alpha) if rng.random() < 0.5 else (0, 0, 0, alpha)
        draw.rectangle([0, y, W - 1, y + h - 1], fill=color)

    img = img.filter(ImageFilter.GaussianBlur(0.4))

    out = Path(__file__).resolve().parent.parent / "assets" / "metal.png"
    img.save(out)
    print(f"wrote {out} ({out.stat().st_size} bytes)")


if __name__ == "__main__":
    main()
