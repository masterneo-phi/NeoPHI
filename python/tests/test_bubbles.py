"""吹き出しの本文と折り返しのテスト。"""

import math
import unittest

from neophi.bubbles import (
    bubble_body,
    bubble_from_action_line,
    bubble_from_log_line,
    bubble_outline,
    place_bubble_rect,
    wrap_bubble_lines,
)


def _measure_10(text):
    """1文字を幅10とする、テスト用の幅の測り方。"""
    return len(text) * 10


class BubbleBodyTest(unittest.TestCase):
    def test_talk(self):
        self.assertEqual(bubble_body("案内人 > こんにちは"), "こんにちは")

    def test_priv(self):
        self.assertEqual(bubble_body("[案内人] > こんにちは"), "こんにちは")

    def test_body_with_separator(self):
        # 本文の中の "> " は区切りにしない
        self.assertEqual(bubble_body("A > a > b"), "a > b")

    def test_no_separator(self):
        self.assertEqual(bubble_body("ただのログ"), "")

    def test_strips_spaces(self):
        self.assertEqual(bubble_body("A >  こんにちは  "), "こんにちは")


class WrapBubbleLinesTest(unittest.TestCase):
    def test_short_text(self):
        self.assertEqual(
            wrap_bubble_lines("こんにちは", _measure_10, 100), ["こんにちは"])

    def test_empty(self):
        self.assertEqual(wrap_bubble_lines("", _measure_10, 100), [])
        self.assertEqual(wrap_bubble_lines("   ", _measure_10, 100), [])

    def test_wraps_at_width(self):
        # 幅30なら3文字ごと
        self.assertEqual(
            wrap_bubble_lines("あいうえおかき", _measure_10, 30),
            ["あいう", "えおか", "き"])

    def test_exact_fit(self):
        self.assertEqual(
            wrap_bubble_lines("あいう", _measure_10, 30), ["あいう"])

    def test_truncates_with_ellipsis(self):
        lines = wrap_bubble_lines("あいうえおかきくけこ", _measure_10, 30, 2)
        self.assertEqual(len(lines), 2)
        self.assertTrue(lines[1].endswith("…"))
        for line in lines:
            self.assertLessEqual(_measure_10(line), 30)

    def test_single_wide_char_kept(self):
        # 1文字だけで幅を超えても、その文字は残す
        self.assertEqual(
            wrap_bubble_lines("あ", _measure_10, 5), ["あ"])

    def test_newlines_split(self):
        self.assertEqual(
            wrap_bubble_lines("あい\nうえ", _measure_10, 100), ["あい", "うえ"])

    def test_max_lines_zero(self):
        self.assertEqual(
            wrap_bubble_lines("あいう", _measure_10, 30, 0), [])


class PlaceBubbleRectTest(unittest.TestCase):
    def test_centered_above_head(self):
        x0, y0, stacked = place_bubble_rect(100, 200, 60, 40, 400, 10, [])
        self.assertEqual((x0, y0, stacked), (70, 150, False))

    def test_left_edge(self):
        x0, _, _ = place_bubble_rect(10, 200, 60, 40, 400, 10, [])
        self.assertEqual(x0, 0)

    def test_right_edge(self):
        x0, _, _ = place_bubble_rect(390, 200, 60, 40, 400, 10, [])
        self.assertEqual(x0, 340)

    def test_top_edge(self):
        _, y0, _ = place_bubble_rect(100, 30, 60, 40, 400, 10, [])
        self.assertEqual(y0, 0)

    def test_stacked_above_occupied(self):
        occupied = [(70, 150, 60, 40)]
        x0, y0, stacked = place_bubble_rect(100, 200, 60, 40, 400, 10, occupied)
        self.assertTrue(stacked)
        # 重なった箱の上に、しっぽの分だけ空けて置く
        self.assertEqual(y0, 100)
        self.assertEqual(x0, 70)

    def test_no_stack_without_overlap(self):
        occupied = [(200, 150, 60, 40)]
        _, _, stacked = place_bubble_rect(100, 200, 60, 40, 400, 10, occupied)
        self.assertFalse(stacked)

    def test_stacked_twice(self):
        occupied = [(70, 150, 60, 40), (70, 100, 60, 40)]
        _, y0, stacked = place_bubble_rect(100, 200, 60, 40, 400, 10, occupied)
        self.assertTrue(stacked)
        self.assertEqual(y0, 50)


class BubbleOutlineTest(unittest.TestCase):
    def test_stays_in_bounds(self):
        points = bubble_outline(10, 20, 110, 60, 8, 60, 6, 60, 72)
        for x, y in points:
            self.assertGreaterEqual(x, 10)
            self.assertLessEqual(x, 110)
            self.assertGreaterEqual(y, 20)
            self.assertLessEqual(y, 72)

    def test_corners_are_rounded(self):
        points = bubble_outline(10, 20, 110, 60, 8, 60, 6, 60, 72)
        # 角の近くは通りません(円弧で切り落としています)
        for cx, cy in ((10, 20), (110, 20), (10, 60), (110, 60)):
            nearest = min(math.hypot(x - cx, y - cy) for x, y in points)
            self.assertGreater(nearest, 2)
        # 上の辺と左の辺には、円弧の端の点があります
        self.assertTrue(any(
            abs(y - 20) < 1e-9 and 10 < x < 110 for x, y in points))
        self.assertTrue(any(
            abs(x - 10) < 1e-9 and 20 < y < 60 for x, y in points))

    def test_tail_tip_present(self):
        points = bubble_outline(10, 20, 110, 60, 8, 60, 6, 55, 72)
        self.assertIn((55.0, 72.0), points)

    def test_narrow_box(self):
        # 狭い箱でも、収まる範囲で丸くします
        points = bubble_outline(10, 20, 30, 60, 8, 20, 6, 20, 72)
        self.assertTrue(points)
        for x, y in points:
            self.assertGreaterEqual(x, 10)
            self.assertLessEqual(x, 30)


class BubbleFromLogLineTest(unittest.TestCase):
    NAMES = {"案内人", "Human", "Guest"}

    def test_npc_talk(self):
        self.assertEqual(
            bubble_from_log_line("案内人 > いらっしゃい", self.NAMES),
            ("案内人", "いらっしゃい"))

    def test_shout(self):
        self.assertEqual(
            bubble_from_log_line("(Human) > I won!", self.NAMES),
            ("Human", "I won!"))

    def test_area(self):
        self.assertEqual(
            bubble_from_log_line("{Human} > 助けて", self.NAMES),
            ("Human", "助けて"))

    def test_party(self):
        self.assertEqual(
            bubble_from_log_line('"Guest" > 行くよ', self.NAMES),
            ("Guest", "行くよ"))

    def test_dm_line_is_not_speech(self):
        self.assertIsNone(bubble_from_log_line(
            "DM > Human は Dog を攻撃した.", self.NAMES))

    def test_unknown_name(self):
        self.assertIsNone(bubble_from_log_line(
            "見知らぬ人 > こんにちは", self.NAMES))

    def test_empty_body(self):
        self.assertIsNone(bubble_from_log_line("案内人 >   ", self.NAMES))

    def test_body_with_separator(self):
        self.assertEqual(
            bubble_from_log_line("案内人 > a > b", self.NAMES),
            ("案内人", "a > b"))


class BubbleFromActionLineTest(unittest.TestCase):
    NAMES = {"案内", "案内人", "Guest"}

    def test_action(self):
        self.assertEqual(
            bubble_from_action_line("DM > Guest 手を振った", self.NAMES),
            ("Guest", "手を振った"))

    def test_longest_name_first(self):
        # 「案内」と「案内人」では、長い方を名前とします
        self.assertEqual(
            bubble_from_action_line("DM > 案内人 おじぎをした", self.NAMES),
            ("案内人", "おじぎをした"))

    def test_no_dm_prefix(self):
        self.assertIsNone(bubble_from_action_line(
            "Guest 手を振った", self.NAMES))

    def test_unknown_name(self):
        self.assertIsNone(bubble_from_action_line(
            "DM > 見知らぬ人 手を振った", self.NAMES))

    def test_empty_body(self):
        self.assertIsNone(bubble_from_action_line("DM > Guest ", self.NAMES))


if __name__ == "__main__":
    unittest.main()
