import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from neophi.codec import decode, encode


class TestCodec(unittest.TestCase):
    def test_round_trip(self):
        self.assertEqual(decode(encode("港町の酒場①")), "港町の酒場①")

    def test_unmappable_to_question(self):
        self.assertEqual(encode("😀X"), b"?X")

    def test_long_input(self):
        long = "あ" * 2000
        self.assertEqual(decode(encode(long)), long)

    def test_invalid_bytes_to_replacement(self):
        # 途中で切れた2バイト文字は置換文字になる
        text = decode(b"\x82")
        self.assertIn("\ufffd", text)


if __name__ == "__main__":
    unittest.main()
