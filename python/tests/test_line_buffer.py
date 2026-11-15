import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from neophi.line_buffer import MAX_LINE, LineBuffer


class TestLineBuffer(unittest.TestCase):
    def test_splits_across_chunks(self):
        lb = LineBuffer()
        # 「あ」(82 A0)の途中で割れても、行が確定するまで持ち越す
        self.assertEqual(lb.feed(b"#name \x82"), [])
        self.assertEqual(
            lb.feed(b"\xa0\r\n\n#x\nrest"),
            [b"#name \x82\xa0", b"#x"],
        )
        self.assertEqual(lb.feed(b"\n"), [b"rest"])
        lb.feed(b"junk")
        lb.reset()
        self.assertEqual(lb.feed(b"ok\n"), [b"ok"])

    def test_drops_too_long_lines(self):
        lb = LineBuffer()
        chunk = b"a" * (MAX_LINE // 2 + 1)
        self.assertEqual(lb.feed(chunk), [])
        self.assertEqual(lb.feed(chunk), [])
        self.assertEqual(lb.feed(b"tail\nnext\n"), [b"next"])
        big = b"b" * (MAX_LINE + 1) + b"\nok\n"
        self.assertEqual(lb.feed(big), [b"ok"])

    def test_strips_one_cr_and_drops_empty(self):
        lb = LineBuffer()
        self.assertEqual(lb.feed(b"a\r\n\r\n\nb\n"), [b"a", b"b"])
        # 末尾の \r は1つだけ落とす
        self.assertEqual(lb.feed(b"c\r\r\n"), [b"c\r"])

    def test_discarding_line_tail_is_skipped(self):
        lb = LineBuffer()
        lb.feed(b"x" * (MAX_LINE + 1))
        # 上限を超えた行の残りは捨て、次の行から戻る
        self.assertEqual(lb.feed(b"tail\nok\n"), [b"ok"])


if __name__ == "__main__":
    unittest.main()
