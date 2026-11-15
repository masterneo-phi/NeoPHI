"""PNG の書き出しのテスト。"""

import struct
import sys
import unittest
import zlib
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from neophi.bmp import RgbaImage  # noqa: E402
from neophi.png import encode_png  # noqa: E402


def _chunks(data):
    assert data[:8] == b"\x89PNG\r\n\x1a\n"
    pos = 8
    out = []
    while pos < len(data):
        length = struct.unpack(">I", data[pos : pos + 4])[0]
        kind = data[pos + 4 : pos + 8]
        body = data[pos + 8 : pos + 8 + length]
        crc = struct.unpack(">I", data[pos + 8 + length : pos + 12 + length])[0]
        assert zlib.crc32(kind + body) & 0xFFFFFFFF == crc, kind
        out.append((kind, body))
        pos += 12 + length
    return out


class TestPng(unittest.TestCase):
    def test_round_trip_pixels(self):
        img = RgbaImage(3, 2, fill=(0, 0, 0, 255))
        img.set_pixel(0, 0, (255, 0, 0, 255))
        img.set_pixel(2, 1, (1, 2, 3, 4))
        data = encode_png(img)
        chunks = _chunks(data)
        kinds = [k for k, _ in chunks]
        self.assertEqual(kinds[0], b"IHDR")
        self.assertEqual(kinds[-1], b"IEND")
        ihdr = chunks[0][1]
        width, height, depth, color = struct.unpack(">IIBB", ihdr[:10])
        self.assertEqual((width, height, depth, color), (3, 2, 8, 6))
        raw = zlib.decompress(b"".join(b for k, b in chunks if k == b"IDAT"))
        stride = 3 * 4
        self.assertEqual(len(raw), 2 * (stride + 1))
        self.assertEqual(raw[0], 0)
        self.assertEqual(raw[1 : 1 + 4], bytes((255, 0, 0, 255)))
        row1 = stride + 1  # フィルタ1バイト + 1行分
        self.assertEqual(raw[row1 + 1 + 2 * 4 : row1 + 1 + 3 * 4], bytes((1, 2, 3, 4)))


if __name__ == "__main__":
    unittest.main()
