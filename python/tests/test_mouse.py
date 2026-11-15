"""マウスの向きのテスト。"""

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from neophi.mouse import mouse_dir, north_fix_turn  # noqa: E402


class TestMouseDir(unittest.TestCase):
    def test_eight_directions(self):
        size = 224
        cases = [
            ((112, 10), ("8",)),    # 上
            ((200, 10), ("8", "6")),  # 右上
            ((220, 112), ("6",)),   # 右
            ((200, 210), ("2", "6")),  # 右下
            ((112, 220), ("2",)),   # 下
            ((10, 210), ("2", "4")),  # 左下
            ((10, 112), ("4",)),    # 左
            ((10, 10), ("8", "4")),  # 左上…ただし上の端は回転になるので別に見る
        ]
        for (x, y), keys in cases[:-1]:
            result = mouse_dir(x, y, size, size, True, False)
            self.assertIsNotNone(result, (x, y))
            self.assertEqual(result.keys, keys, (x, y))

    def test_center_and_outside_are_none(self):
        self.assertIsNone(mouse_dir(112, 112, 224, 224, True, False))
        self.assertIsNone(mouse_dir(-1, 100, 224, 224, True, False))
        self.assertIsNone(mouse_dir(100, 300, 224, 224, True, False))

    def test_turn_zones_in_turn_mode(self):
        # 回転マップの上の端の左右は回転
        self.assertEqual(
            mouse_dir(10, 10, 224, 224, False, False).keys, ("7",)
        )
        self.assertEqual(
            mouse_dir(214, 10, 224, 224, False, False).keys, ("9",)
        )
        # 北固定なら回転にならない
        self.assertEqual(
            mouse_dir(10, 10, 224, 224, True, False).keys, ("8", "4")
        )

    def test_shift_or_ctrl_turns_in_turn_mode(self):
        self.assertEqual(
            mouse_dir(50, 150, 224, 224, False, True).keys, ("7",)
        )
        self.assertEqual(
            mouse_dir(180, 150, 224, 224, False, True).keys, ("9",)
        )


class TestNorthFixTurn(unittest.TestCase):
    def test_quadrants(self):
        self.assertEqual(north_fix_turn(112, 10, 224, 224), "n")
        self.assertEqual(north_fix_turn(220, 112, 224, 224), "e")
        self.assertEqual(north_fix_turn(112, 220, 224, 224), "s")
        self.assertEqual(north_fix_turn(10, 112, 224, 224), "w")

    def test_dead_zone(self):
        self.assertIsNone(north_fix_turn(112, 112, 224, 224))
        self.assertIsNone(north_fix_turn(125, 125, 224, 224))


if __name__ == "__main__":
    unittest.main()
