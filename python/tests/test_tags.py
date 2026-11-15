import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from neophi.tags import extract_to_names, plain_text, strip_tags


class TestTags(unittest.TestCase):
    def test_plain_text_removes_tags(self):
        self.assertEqual(
            plain_text("/*color=red*/警告/*.*/ です"), "警告 です"
        )
        self.assertEqual(plain_text("/**/こんにちは"), "こんにちは")
        self.assertEqual(plain_text("a/*br*/b"), "a\nb")

    def test_plain_text_img(self):
        self.assertEqual(
            plain_text("見て /*img=http://example.com/a.png width=10*/"),
            "見て [画像: http://example.com/a.png]",
        )
        self.assertEqual(plain_text("/*img_wnd=foo*/x"), "x")

    def test_plain_text_heart(self):
        self.assertEqual(plain_text("はーと"), "♥")

    def test_unclosed_tag_left_as_is(self):
        self.assertEqual(plain_text("/*color=red 警告"), "/*color=red 警告")

    def test_strip_tags(self):
        self.assertEqual(
            strip_tags("[/*color=cyan*/ 1/*.*/] ロングソード"),
            "[ 1] ロングソード",
        )

    def test_extract_to_names(self):
        self.assertEqual(
            extract_to_names("/*to=A*//*to=B*/こんにちは"), ["A", "B"]
        )
        self.assertEqual(extract_to_names("こんにちは"), [])


if __name__ == "__main__":
    unittest.main()
