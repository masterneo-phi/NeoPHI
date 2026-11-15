"""BMP の読み込みと透過のテスト。"""

import struct
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
sys.path.insert(0, str(Path(__file__).resolve().parent))

from bmp_helper import make_bmp, solid_rows  # noqa: E402
from neophi.bmp import (  # noqa: E402
    BmpError,
    RgbaImage,
    colorkey,
    decode_bmp,
    fade_alpha,
    mask_h,
    mask_v,
)


class TestDecodeBmp(unittest.TestCase):
    def test_24bpp_bottom_up(self):
        data = make_bmp(2, 2, 24, [
            [(255, 0, 0), (0, 255, 0)],
            [(0, 0, 255), (255, 255, 255)],
        ])
        img = decode_bmp(data)
        self.assertEqual((img.width, img.height), (2, 2))
        self.assertEqual(img.pixel(0, 0), (255, 0, 0, 255))
        self.assertEqual(img.pixel(1, 0), (0, 255, 0, 255))
        self.assertEqual(img.pixel(0, 1), (0, 0, 255, 255))
        self.assertEqual(img.pixel(1, 1), (255, 255, 255, 255))

    def test_24bpp_top_down(self):
        data = make_bmp(2, 1, 24, [[(10, 20, 30), (40, 50, 60)]], top_down=True)
        img = decode_bmp(data)
        self.assertEqual(img.pixel(0, 0), (10, 20, 30, 255))
        self.assertEqual(img.pixel(1, 0), (40, 50, 60, 255))

    def test_32bpp_ignores_alpha(self):
        data = make_bmp(1, 1, 32, [[(9, 8, 7)]])
        img = decode_bmp(data)
        self.assertEqual(img.pixel(0, 0), (9, 8, 7, 255))

    def test_8bpp_palette(self):
        palette = [(255, 0, 0), (0, 255, 0), (0, 0, 255)]
        data = make_bmp(3, 1, 8, [[0, 1, 2]], palette=palette)
        img = decode_bmp(data)
        self.assertEqual(img.pixel(0, 0), (255, 0, 0, 255))
        self.assertEqual(img.pixel(1, 0), (0, 255, 0, 255))
        self.assertEqual(img.pixel(2, 0), (0, 0, 255, 255))

    def test_4bpp_palette(self):
        palette = [(i * 16, 0, 0) for i in range(16)]
        data = make_bmp(4, 1, 4, [[1, 2, 3, 4]], palette=palette)
        img = decode_bmp(data)
        self.assertEqual(img.pixel(0, 0), (16, 0, 0, 255))
        self.assertEqual(img.pixel(3, 0), (64, 0, 0, 255))

    def test_1bpp_palette(self):
        palette = [(0, 0, 0), (255, 255, 255)]
        data = make_bmp(8, 1, 1, [[0, 1, 0, 1, 1, 0, 0, 1]], palette=palette)
        img = decode_bmp(data)
        self.assertEqual(img.pixel(1, 0), (255, 255, 255, 255))
        self.assertEqual(img.pixel(2, 0), (0, 0, 0, 255))

    def test_row_padding(self):
        # 幅3の24bppは1行9バイト→12バイトに詰め物が入る
        data = make_bmp(3, 2, 24, [
            [(1, 2, 3), (4, 5, 6), (7, 8, 9)],
            [(11, 12, 13), (14, 15, 16), (17, 18, 19)],
        ])
        img = decode_bmp(data)
        self.assertEqual(img.pixel(2, 1), (17, 18, 19, 255))

    def test_not_bmp(self):
        with self.assertRaises(BmpError):
            decode_bmp(b"not a bmp file at all, definitely not")

    def test_compressed_rejected(self):
        data = bytearray(make_bmp(1, 1, 24, [[(0, 0, 0)]]))
        struct.pack_into("<I", data, 30, 1)  # BI_RLE8
        with self.assertRaises(BmpError):
            decode_bmp(bytes(data))

    def test_truncated_rejected(self):
        data = make_bmp(4, 4, 24, solid_rows(4, 4, (1, 2, 3)))
        with self.assertRaises(BmpError):
            decode_bmp(data[:60])


class TestTransparency(unittest.TestCase):
    def test_colorkey(self):
        img = RgbaImage(2, 1, fill=(0, 128, 128, 255))
        img.set_pixel(1, 0, (10, 20, 30, 255))
        out = colorkey(img)
        self.assertEqual(out.pixel(0, 0), (0, 0, 0, 0))
        self.assertEqual(out.pixel(1, 0), (10, 20, 30, 255))

    def test_mask_h(self):
        # 左が画像、右がマスク(白=不透明、黒=透明)
        img = RgbaImage(4, 1, fill=(0, 0, 0, 255))
        img.set_pixel(0, 0, (200, 0, 0, 255))
        img.set_pixel(1, 0, (0, 200, 0, 255))
        img.set_pixel(2, 0, (255, 255, 255, 255))
        img.set_pixel(3, 0, (0, 0, 0, 255))
        out = mask_h(img)
        self.assertEqual((out.width, out.height), (2, 1))
        self.assertEqual(out.pixel(0, 0), (200, 0, 0, 255))
        self.assertEqual(out.pixel(1, 0), (0, 0, 0, 0))

    def test_mask_v(self):
        img = RgbaImage(1, 4, fill=(0, 0, 0, 255))
        img.set_pixel(0, 0, (200, 0, 0, 255))
        img.set_pixel(0, 1, (0, 200, 0, 255))
        img.set_pixel(0, 2, (255, 255, 255, 255))
        img.set_pixel(0, 3, (100, 100, 100, 255))  # 閾値以下は透明
        out = mask_v(img)
        self.assertEqual((out.width, out.height), (1, 2))
        self.assertEqual(out.pixel(0, 0), (200, 0, 0, 255))
        self.assertEqual(out.pixel(0, 1), (0, 0, 0, 0))


class TestFadeAlpha(unittest.TestCase):
    def test_scales_alpha_only(self):
        img = RgbaImage(2, 1, bytes([10, 20, 30, 200, 40, 50, 60, 0]))
        faded = fade_alpha(img, 0.5)
        self.assertEqual(faded.pixel(0, 0), (10, 20, 30, 100))
        self.assertEqual(faded.pixel(1, 0), (40, 50, 60, 0))
        # 元の画像は変えません
        self.assertEqual(img.pixel(0, 0), (10, 20, 30, 200))

    def test_zero_is_transparent(self):
        img = RgbaImage(1, 1, bytes([10, 20, 30, 255]))
        self.assertEqual(fade_alpha(img, 0.0).pixel(0, 0), (10, 20, 30, 0))


class TestBlit(unittest.TestCase):
    def test_blit_clips_and_skips_transparent(self):
        dst = RgbaImage(3, 3, fill=(0, 0, 0, 255))
        src = RgbaImage(2, 2, fill=(255, 0, 0, 255))
        src.set_pixel(1, 1, (0, 0, 0, 0))
        dst.blit(src, 0, 0, 2, 2, 2, 2)
        self.assertEqual(dst.pixel(2, 2), (255, 0, 0, 255))
        self.assertEqual(dst.pixel(0, 0), (0, 0, 0, 255))

    def test_blit_scaled_nearest(self):
        dst = RgbaImage(4, 4, fill=(0, 0, 0, 255))
        src = RgbaImage(2, 2, fill=(0, 0, 0, 255))
        src.set_pixel(0, 0, (255, 0, 0, 255))
        src.set_pixel(1, 1, (0, 0, 255, 255))
        dst.blit_scaled(src, 0, 0, 2, 2, 0, 0, 4, 4)
        self.assertEqual(dst.pixel(1, 1), (255, 0, 0, 255))
        self.assertEqual(dst.pixel(3, 3), (0, 0, 255, 255))


if __name__ == "__main__":
    unittest.main()
