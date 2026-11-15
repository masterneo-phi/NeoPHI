"""戦闘の演出のもとになる読み取りと形のテスト。"""

import math
import unittest

from neophi.combat_fx import (
    CasterTracker,
    comet_tail_points,
    parse_attack,
    parse_chant,
    parse_chant_stop,
    parse_kill,
    radial_spark_points,
    slash_points,
    streak_points,
)


class ParseAttackTest(unittest.TestCase):
    def test_physical(self):
        event = parse_attack(
            "DM > Guest は Human を 拳 で攻撃した. [6 hp]")
        self.assertIsNotNone(event)
        self.assertEqual(event.attacker, "Guest")
        self.assertEqual(event.target, "Human")
        self.assertEqual(event.weapon, "拳")

    def test_mp_damage(self):
        event = parse_attack(
            "DM > Human は Dog を Insane で攻撃した. [127 mp]")
        self.assertIsNotNone(event)
        self.assertEqual(event.attacker, "Human")
        self.assertEqual(event.target, "Dog")
        self.assertEqual(event.weapon, "Insane")

    def test_weapon_with_spaces(self):
        event = parse_attack(
            "DM > Guest は Human を ロングソード で攻撃した. [43 hp]")
        self.assertEqual(event.weapon, "ロングソード")

    def test_no_match(self):
        self.assertIsNone(parse_attack(
            "DM > Guest が Cure によって回復した. [40 hp]"))
        self.assertIsNone(parse_attack(
            "DM > Guest は罠からダメージを受けた. [10 hp]"))
        self.assertIsNone(parse_attack("ただのログ"))


class ParseChantTest(unittest.TestCase):
    def test_cast(self):
        self.assertEqual(
            parse_chant("DM > Human は魔法を唱えている... "), "Human")

    def test_special(self):
        self.assertEqual(
            parse_chant("DM > Human は力を集中している... "), "Human")

    def test_no_match(self):
        self.assertIsNone(parse_chant("DM > Guest は Human を攻撃した."))
        self.assertIsNone(parse_chant("DM > 詠唱を止めました. "))


class ParseChantStopTest(unittest.TestCase):
    def test_stop(self):
        self.assertTrue(parse_chant_stop("DM > 詠唱を止めました. "))

    def test_incomplete(self):
        self.assertTrue(parse_chant_stop("DM > 詠唱は完了しなかった. "))

    def test_no_match(self):
        self.assertFalse(parse_chant_stop("DM > Human は魔法を唱えている... "))


class CasterTrackerTest(unittest.TestCase):
    def test_consume_once(self):
        tracker = CasterTracker(window=5.0)
        tracker.note("Human", 100.0)
        self.assertTrue(tracker.consume("Human", 102.0))
        self.assertFalse(tracker.consume("Human", 103.0))

    def test_expired(self):
        tracker = CasterTracker(window=5.0)
        tracker.note("Human", 100.0)
        self.assertFalse(tracker.consume("Human", 106.0))

    def test_clear(self):
        tracker = CasterTracker()
        tracker.note("Guest", 100.0)
        tracker.clear("Guest")
        self.assertFalse(tracker.consume("Guest", 101.0))

    def test_other_names(self):
        tracker = CasterTracker()
        tracker.note("Human", 100.0)
        self.assertFalse(tracker.consume("Guest", 101.0))
        self.assertTrue(tracker.consume("Human", 101.0))


class SlashPointsTest(unittest.TestCase):
    def test_count_and_bounds(self):
        points = slash_points(100.0, 100.0, 2.0)
        self.assertEqual(len(points), 28)  # 14点
        xs = points[0::2]
        ys = points[1::2]
        self.assertLess(min(xs), 100.0)
        self.assertGreater(max(xs), 100.0)
        self.assertLess(min(ys), 100.0)
        self.assertGreater(max(ys), 100.0)

    def test_starts_top_right(self):
        points = slash_points(100.0, 100.0, 1.0)
        # 最初の点は右上にあります
        self.assertGreater(points[0], 100.0)
        self.assertLess(points[1], 100.0)


class StreakTest(unittest.TestCase):
    def test_stays_near_radius(self):
        points = streak_points(100.0, 100.0, 2.0, 20.0, -1.0, 1.0, 3.0)
        self.assertEqual(len(points) % 2, 0)
        self.assertGreaterEqual(len(points), 6)
        for x, y in zip(points[0::2], points[1::2]):
            dist = ((x - 100.0) ** 2 + (y - 100.0) ** 2) ** 0.5
            self.assertLessEqual(dist, 43.0 + 1e-6)
            self.assertGreaterEqual(dist, 37.0 - 1e-6)

    def test_pointed_ends_and_thick_middle(self):
        points = streak_points(100.0, 100.0, 1.0, 20.0, -1.0, 1.0, 4.0)
        count = len(points) // 2
        half = count // 2
        outer = [(points[i * 2], points[i * 2 + 1]) for i in range(half)]
        inner = [(points[i * 2], points[i * 2 + 1])
                 for i in range(count - 1, half - 1, -1)]
        # 両端は外側と内側が重なります
        self.assertAlmostEqual(outer[0][0], inner[0][0])
        self.assertAlmostEqual(outer[0][1], inner[0][1])
        self.assertAlmostEqual(outer[-1][0], inner[-1][0])
        self.assertAlmostEqual(outer[-1][1], inner[-1][1])
        # 真ん中は太さの分だけ開きます
        mid = half // 2
        gap = ((outer[mid][0] - inner[mid][0]) ** 2
               + (outer[mid][1] - inner[mid][1]) ** 2) ** 0.5
        self.assertAlmostEqual(gap, 4.0, places=1)


class CometTailTest(unittest.TestCase):
    def test_head_width_and_tail_tip(self):
        points = comet_tail_points(100.0, 100.0, 60.0, 100.0, 2.0, 7.0)
        self.assertEqual(len(points), 6)
        # 頭の2点は、進行方向と直角に太さの分だけ開きます
        head_gap = ((points[0] - points[4]) ** 2
                    + (points[1] - points[5]) ** 2) ** 0.5
        self.assertAlmostEqual(head_gap, 14.0)
        # 尾の先は指定の点です
        self.assertEqual((points[2], points[3]), (60.0, 100.0))

    def test_degenerate(self):
        self.assertEqual(
            comet_tail_points(100.0, 100.0, 100.0, 100.0, 1.0, 7.0),
            [100.0, 100.0, 100.0, 100.0, 100.0, 100.0])


class RadialSparkTest(unittest.TestCase):
    def test_tip_and_width(self):
        points = radial_spark_points(100.0, 100.0, 1.0, 0.0, 20.0, 2.0)
        self.assertEqual(len(points), 8)
        # 先は右へ長さの分だけ伸びます
        self.assertAlmostEqual(points[4], 120.0)
        self.assertAlmostEqual(points[5], 100.0)
        # 真ん中は太さの分だけ開きます
        mid_gap = ((points[2] - points[6]) ** 2
                   + (points[3] - points[7]) ** 2) ** 0.5
        self.assertAlmostEqual(mid_gap, 4.0)


class ParseKillTest(unittest.TestCase):
    def test_killed_by_other(self):
        self.assertEqual(
            parse_kill("DM > Dog は Human に殺された. "), "Dog")

    def test_killed_by_pk(self):
        # PK版はタグを除くと他殺と同じ形です
        self.assertEqual(
            parse_kill("DM > Guest は Human に殺された. "), "Guest")

    def test_killed_self(self):
        self.assertEqual(
            parse_kill("DM > Guest は 毒で死んだ. "), "Guest")

    def test_dead_self(self):
        self.assertEqual(
            parse_kill("DM > あなたは死にました... "), "あなた")

    def test_no_match(self):
        self.assertIsNone(parse_kill(
            "DM > Human は Cat を Knife で攻撃した. [43 hp]"))
        self.assertIsNone(parse_kill(
            "DM > 死んだ時のメッセージを入力して下さい. "))
        self.assertIsNone(parse_kill(
            "DM > Guest が Cure によって回復した. [40 hp]"))


if __name__ == "__main__":
    unittest.main()
