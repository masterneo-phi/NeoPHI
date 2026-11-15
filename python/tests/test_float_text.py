import unittest

from neophi.float_text import FloatEvent, parse_floats
from neophi.map_graphics import render_map_image
from neophi.parser import Cell, Chara


class TestParseFloats(unittest.TestCase):
    """実サーバ (rel5g MasterGate / dm_msg_jp.h) の文面。タグを除いた後の形。"""

    def test_attack_hp(self):
        self.assertEqual(
            parse_floats("DM > モック太郎 は モック花子 を ロングソード で攻撃した. [12 hp]"),
            [FloatEvent("dealt", "モック花子", 12)],
        )

    def test_attack_mp(self):
        self.assertEqual(
            parse_floats("DM > モック太郎 は モック花子 を ロングソード で攻撃した. [8 mp]"),
            [FloatEvent("mpdmg", "モック花子", 8)],
        )

    def test_magic_hp(self):
        self.assertEqual(
            parse_floats("DM > モック太郎 は ドラゴン を ファイアーボール で攻撃した. [30 hp]"),
            [FloatEvent("dealt", "ドラゴン", 30)],
        )

    def test_attack_on_you(self):
        self.assertEqual(
            parse_floats("DM > ドラゴン は あなた を 牙 で攻撃した. [9 hp]"),
            [FloatEvent("dealt", "あなた", 9)],
        )

    def test_absorb_attack(self):
        self.assertEqual(
            parse_floats("DM > モック花子 は モック太郎 の ロングソード による攻撃を吸収した. [5 hp]"),
            [FloatEvent("heal", "モック花子", 5)],
        )

    def test_absorb_magic(self):
        self.assertEqual(
            parse_floats("DM > モック花子 は モック太郎 の ファイアーボール を吸収した. [7 mp]"),
            [FloatEvent("mp", "モック花子", 7)],
        )

    def test_absorb_trap(self):
        self.assertEqual(
            parse_floats("DM > モック花子 は 落とし穴 を吸収した. [7 mp]"),
            [FloatEvent("mp", "モック花子", 7)],
        )

    def test_trap_hp(self):
        self.assertEqual(
            parse_floats("DM > モック太郎 は 落とし穴 からダメージを受けた. [10 hp]"),
            [FloatEvent("taken", "モック太郎", 10)],
        )

    def test_trap_mp(self):
        self.assertEqual(
            parse_floats("DM > モック太郎 は 毒の罠 からダメージを受けた. [10 mp]"),
            [FloatEvent("mpdmg", "モック太郎", 10)],
        )

    def test_burst_sphere(self):
        self.assertEqual(
            parse_floats("DM > モック太郎 は 魔法の暴発でダメージを受けた. [15 hp]"),
            [FloatEvent("taken", "モック太郎", 15)],
        )

    def test_burst_self(self):
        self.assertEqual(
            parse_floats("DM > 暴発! ダメージ 20 hp."),
            [FloatEvent("taken", None, 20)],
        )

    def test_cure_self(self):
        self.assertEqual(
            parse_floats("DM > モック花子 が キュアー によって回復した. [25 hp]"),
            [FloatEvent("heal", "モック花子", 25)],
        )

    def test_cure_other(self):
        self.assertEqual(
            parse_floats("DM > モック太郎 は モック花子 を キュアー で回復した. [25 hp]"),
            [FloatEvent("heal", "モック花子", 25)],
        )

    def test_cure_other_mp(self):
        self.assertEqual(
            parse_floats("DM > モック太郎 は モック花子 を キュアー で回復した. [10 mp]"),
            [FloatEvent("mp", "モック花子", 10)],
        )

    def test_food_sphere(self):
        self.assertEqual(
            parse_floats("DM > モック太郎 は パン で回復した. [6 mp]"),
            [FloatEvent("mp", "モック太郎", 6)],
        )

    def test_food_self(self):
        self.assertEqual(
            parse_floats("DM > モック太郎 は 6 mp 回復した."),
            [FloatEvent("mp", "モック太郎", 6)],
        )

    def test_food_iron_stomach(self):
        # 「しかし」が頭に付いても、名前はその後のキャラです
        self.assertEqual(
            parse_floats("DM > しかし モック太郎 は 6 mp 回復した."),
            [FloatEvent("mp", "モック太郎", 6)],
        )

    def test_food_damage_sphere(self):
        self.assertEqual(
            parse_floats("DM > モック太郎 は 毒キノコ でダメージを受けた. [4 mp]"),
            [FloatEvent("mpdmg", "モック太郎", 4)],
        )

    def test_food_damage_self(self):
        # 「は食中毒」の後は空白がありません
        self.assertEqual(
            parse_floats("DM > モック太郎 は食中毒でダメージを受けた. [4 mp]"),
            [FloatEvent("mpdmg", "モック太郎", 4)],
        )

    def test_comma_number(self):
        self.assertEqual(
            parse_floats("DM > モック太郎 は ドラゴン を ロングソード で攻撃した. [1,200 hp]"),
            [FloatEvent("dealt", "ドラゴン", 1200)],
        )

    def test_no_match(self):
        self.assertEqual(parse_floats("DM > モック太郎 はミスした."), [])
        self.assertEqual(parse_floats("DM > クリティカル!"), [])
        self.assertEqual(parse_floats("DM > 12/100 hp left."), [])
        self.assertEqual(parse_floats("DM > モック太郎 は 3 lv の毒を受けた."), [])
        self.assertEqual(parse_floats("DM > 攻撃力が 5 point 上がった."), [])
        self.assertEqual(parse_floats("DM > 30 秒間 HPが回復します."), [])
        self.assertEqual(parse_floats("DM > モック太郎 は モック花子 に殺された."), [])
        self.assertEqual(parse_floats("DM > モック太郎 は ALL mp 回復した."), [])
        self.assertEqual(parse_floats("こんにちは。"), [])
        self.assertEqual(parse_floats(""), [])


class TestAnchors(unittest.TestCase):
    def test_anchors_include_center_chara(self):
        cells = [Cell(chip=ord(" "), attr=0) for _ in range(9)]
        chars = [
            Chara(name="自分", x=1, y=1),
            Chara(name="モック太郎", x=0, y=0),
            Chara(name="モック花子", x=2, y=2),
        ]
        rendered = render_map_image(
            cells, chars, 3, [None] * 4, None, lambda ch: None
        )
        by_name = {a.name: a for a in rendered.anchors}
        self.assertEqual(set(by_name), {"自分", "モック太郎", "モック花子"})
        # 中心のキャラも基準点があります
        center = by_name["自分"]
        self.assertEqual((center.cell_x, center.cell_y), (1, 1))
        self.assertEqual((center.x, center.y), (1 * 32 + 16, 1 * 32 + 5))
        # ラベルは中心を除きますが、基準点は除きません
        self.assertEqual(
            {label.name for label in rendered.labels},
            {"モック太郎", "モック花子"},
        )

    def test_anchors_skip_empty_names(self):
        cells = [Cell(chip=ord(" "), attr=0) for _ in range(9)]
        chars = [Chara(name="  ", x=0, y=0), Chara(name="モック太郎", x=9, y=9)]
        rendered = render_map_image(
            cells, chars, 3, [None] * 4, None, lambda ch: None
        )
        self.assertEqual(rendered.anchors, [])


if __name__ == "__main__":
    unittest.main()
