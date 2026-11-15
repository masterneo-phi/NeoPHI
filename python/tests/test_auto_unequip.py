import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from neophi.auto_unequip import (
    CAST_PREFIX,
    AutoUnequip,
    first_equipment,
)

WEAPON = "     [ 1] ロングソード                    Wp  :  5 [Wpn]"
WEAPON_TAGGED = (
    "     [/*color=cyan*/ 1/*.*/] ロングソード"
    "                    Wp  :  5 [/*color=red*/Wpn/*.*/]"
)
ARMOR = "     [ 1] 革の鎧                      Wp  :  3 [Arm]"


class TestFirstEquipment(unittest.TestCase):
    def test_weapon_with_tags(self):
        # タグを除いた行で読む。セッションが strip_tags してから渡す
        from neophi.tags import strip_tags

        self.assertEqual(
            first_equipment(strip_tags(WEAPON_TAGGED)), ("ロングソード", "Wpn")
        )

    def test_weapon_plain(self):
        self.assertEqual(first_equipment(WEAPON), ("ロングソード", "Wpn"))

    def test_armor(self):
        self.assertEqual(first_equipment(ARMOR), ("革の鎧", "Arm"))

    def test_second_line_is_not_first(self):
        self.assertIsNone(first_equipment("[ 2] 革の盾   Wp  :  2 [Arm]"))

    def test_no_kind(self):
        self.assertIsNone(first_equipment("[ 1] 木の剣"))


class TestAutoUnequip(unittest.TestCase):
    def _start(self, cast="cast\twizard eye", reequip=False):
        auto = AutoUnequip()
        flag = "1" if reequip else "0"
        self.assertEqual(auto.start(f"{CAST_PREFIX}{flag} {cast}", 0.0), "unequip")
        return auto

    def _run(self, auto, lines, now=0.0):
        shown: list[str] = []
        replies: list[str] = []
        for line in lines:
            hidden, reply = auto.filter(line, now)
            replies.extend(reply)
            if not hidden:
                shown.append(line)
        return shown, replies

    def test_weapon_flow(self):
        auto = self._start()
        shown, replies = self._run(auto, [
            "#list", WEAPON, "#end-list", "外す装備を選択して下さい",
            "DM > wizard eye を唱えた。",
        ])
        self.assertEqual(replies, ["1", "cast", "wizard eye"])
        # 装備のリストと選択の促しは画面に出ない。唱えた後の行は出る
        self.assertEqual(shown, ["DM > wizard eye を唱えた。"])

    def test_armor_flow_cancels(self):
        auto = self._start(cast="cast\tdetect")
        _, replies = self._run(auto, ["#list", ARMOR, "#end-list"])
        self.assertEqual(replies, [".", "cast", "detect"])

    def test_no_equipment_casts_at_once(self):
        auto = self._start()
        shown, replies = self._run(auto, ["なにも装備していません"])
        self.assertEqual(replies, ["cast", "wizard eye"])
        self.assertEqual(shown, [])

    def test_cannot_unequip_variants(self):
        for text in ("装備を外せません", "Can not unequip."):
            auto = self._start()
            _, replies = self._run(auto, [text])
            self.assertEqual(replies, ["cast", "wizard eye"])

    def test_unreadable_first_line_cancels(self):
        auto = self._start()
        _, replies = self._run(auto, [
            "#list", "[ 2] 革の盾   Wp  :  2 [Arm]", "#end-list",
        ])
        self.assertEqual(replies, [".", "cast", "wizard eye"])

    def test_timeout_forgets_cast(self):
        auto = self._start()
        # 5秒を過ぎてから #list が来ても、横取りしないし唱えない
        shown, replies = self._run(auto, ["#list", WEAPON, "#end-list"], now=6.0)
        self.assertEqual(replies, [])
        self.assertEqual(shown, ["#list", WEAPON, "#end-list"])

    def test_english_prompt_hidden(self):
        auto = self._start()
        shown, replies = self._run(auto, [
            "#list", WEAPON, "#end-list", "Input item number to unequip.",
        ])
        self.assertEqual(replies, ["1", "cast", "wizard eye"])
        self.assertEqual(shown, [])

    def test_reequip_hides_equipped_line(self):
        auto = self._start(cast="cast\teagle eye", reequip=True)
        shown, replies = self._run(auto, [
            "#list", WEAPON, "#end-list",
            "ロングソードを装備した",
        ])
        self.assertEqual(
            replies, ["1", "cast", "eagle eye", "equip ロングソード"]
        )
        self.assertEqual(shown, [])

    def test_reequip_flag_off_by_default(self):
        auto = AutoUnequip()
        auto.start(f"{CAST_PREFIX}0 cast\twizard eye", 0.0)
        _, replies = self._run(auto, ["#list", WEAPON, "#end-list"])
        self.assertEqual(replies, ["1", "cast", "wizard eye"])

    def test_unrelated_lines_pass_through(self):
        auto = self._start()
        shown, replies = self._run(auto, ["誰か > こんにちは"])
        self.assertEqual(replies, [])
        self.assertEqual(shown, ["誰か > こんにちは"])

    def test_start_rejects_other_lines(self):
        auto = AutoUnequip()
        self.assertIsNone(auto.start("cast", 0.0))
        self.assertEqual(auto.cast, [])


if __name__ == "__main__":
    unittest.main()
