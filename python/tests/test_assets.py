"""アセット探索のテスト。Philly のフォルダを仮に作って確かめます。"""

import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
sys.path.insert(0, str(Path(__file__).resolve().parent))

from bmp_helper import make_bmp, solid_rows  # noqa: E402
from neophi.assets import Assets, is_lanu, safe_rel  # noqa: E402
from neophi.bmp import colorkey  # noqa: E402

RED = (255, 0, 0)
GREEN = (0, 255, 0)
BLUE = (0, 0, 255)
TEAL = (0, 128, 128)


def _chara_bmp(color):
    rows = solid_rows(96, 160, color)
    rows[0][0] = TEAL  # 透過色の画素
    return make_bmp(96, 160, 24, rows)


def _chip_bmp(color):
    # 1024x96 の8ビット。左半分が画像、右半分がマスク(白)。
    palette = [color, (255, 255, 255), (0, 0, 0)]
    rows = []
    for _ in range(96):
        rows.append([0] * 512 + [1] * 512)
    return make_bmp(1024, 96, 8, rows, palette=palette)


def _items_bmp(color):
    palette = [color, (255, 255, 255), (0, 0, 0)]
    rows = [[0] * 960 for _ in range(32)] + [[1] * 960 for _ in range(32)]
    return make_bmp(960, 64, 8, rows, palette=palette)


class TestAssets(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        root = Path(self._tmp.name)
        (root / "chara").mkdir()
        (root / "chip").mkdir()
        (root / "Skins" / "Mine" / "chip").mkdir(parents=True)
        (root / "Skins" / "Mine" / "Images").mkdir(parents=True)
        (root / "Skins" / "Mine" / "chara").mkdir(parents=True)
        (root / "chara" / "hero.bmp").write_bytes(_chara_bmp(RED))
        (root / "chara" / "dog.bmp").write_bytes(_chara_bmp(GREEN))
        (root / "chara" / "default_elf.bmp").write_bytes(_chara_bmp(BLUE))
        (root / "chara" / "names.ali").write_bytes(
            "dog わんこ\n".encode("cp932")
        )
        (root / "Skins" / "Mine" / "chara" / "Index.txt").write_bytes(
            "// 既定グラ\n知的生物 = default_elf.bmp\nsetcg使用キャラ = default_elf.bmp\n".encode("cp932")
        )
        (root / "Skins" / "Mine" / "chip" / "Default.bmp").write_bytes(_chip_bmp(RED))
        (root / "chip" / "forest.bmp").write_bytes(_chip_bmp(GREEN))
        (root / "Skins" / "Mine" / "Images" / "Items.bmp").write_bytes(_items_bmp(BLUE))
        self.root = root
        self.assets = Assets([root])

    def tearDown(self):
        self._tmp.cleanup()

    def test_chara_by_gra(self):
        img = self.assets.chara("だれか", "hero", 0x01)
        self.assertIsNotNone(img)
        self.assertEqual((img.width, img.height), (96, 160))
        self.assertEqual(img.pixel(10, 10), (*RED, 255))
        # 透過色は透明になる
        self.assertEqual(img.pixel(0, 0), (0, 0, 0, 0))

    def test_chara_alias_wins_over_gra(self):
        # 名前「わんこ」の別名は dog。グラ名 hero より別名が先
        img = self.assets.chara("わんこ", "hero", 0x01)
        self.assertEqual(img.pixel(10, 10), (*GREEN, 255))

    def test_chara_setcg_gra_first(self):
        # setcg(0x40)はグラ名が別名より先
        img = self.assets.chara("わんこ", "hero", 0x40)
        self.assertEqual(img.pixel(10, 10), (*RED, 255))

    def test_chara_name_fallback(self):
        # グラ名が無ければキャラ名のファイル
        img = self.assets.chara("dog", "no-such", 0x01)
        self.assertEqual(img.pixel(10, 10), (*GREEN, 255))

    def test_chara_default_from_index(self):
        # どれも無ければ種別の既定グラ(Index.txt)
        img = self.assets.chara("だれか", "no-such", 0x01)
        self.assertEqual(img.pixel(10, 10), (*BLUE, 255))

    def test_chara_case_insensitive(self):
        img = self.assets.chara("だれか", "HERO", 0x01)
        self.assertIsNotNone(img)
        self.assertEqual(img.pixel(10, 10), (*RED, 255))

    def test_chip_mapset_and_default(self):
        forest = self.assets.chip("forest")
        self.assertEqual(forest.pixel(0, 0), (*GREEN, 255))
        default = self.assets.chip("no-such-mapset")
        self.assertEqual(default.pixel(0, 0), (*RED, 255))
        self.assertEqual((forest.width, forest.height), (512, 96))

    def test_items(self):
        items = self.assets.items()
        self.assertEqual((items.width, items.height), (960, 32))
        self.assertEqual(items.pixel(0, 0), (*BLUE, 255))

    def test_missing_everything_returns_none(self):
        empty = Assets([])
        self.assertIsNone(empty.chara("x", "y", 0x01))
        self.assertIsNone(empty.chip("forest"))
        self.assertIsNone(empty.items())

    def test_same_gra_shares_converted_image(self):
        a = self.assets.chara("a", "hero", 0x01)
        b = self.assets.chara("b", "hero", 0x01)
        self.assertIs(a, b)

    def test_first_root_wins(self):
        with tempfile.TemporaryDirectory() as other:
            other_root = Path(other)
            (other_root / "chara").mkdir()
            (other_root / "chara" / "hero.bmp").write_bytes(_chara_bmp(BLUE))
            assets = Assets([other_root, self.root])
            img = assets.chara("x", "hero", 0x01)
            self.assertEqual(img.pixel(10, 10), (*BLUE, 255))

    def test_lanu_never_read(self):
        (self.root / "chara" / "LANU_test.bmp").write_bytes(_chara_bmp(RED))
        # LANU のグラ名でも既定グラになる
        img = self.assets.chara("x", "LANU_test", 0x01)
        self.assertEqual(img.pixel(10, 10), (*BLUE, 255))
        self.assertTrue(is_lanu("chara/lanu_x.bmp"))
        self.assertFalse(is_lanu("chara/hero.bmp"))

    def test_path_traversal_rejected(self):
        self.assertFalse(safe_rel("../outside"))
        self.assertFalse(safe_rel("chara/../../outside"))
        self.assertFalse(safe_rel("chara\\hero"))
        self.assertFalse(safe_rel("C:/x"))
        self.assertFalse(safe_rel(""))
        self.assertTrue(safe_rel("chara/hero.bmp"))
        # 危険なグラ名でも既定グラになり、外のファイルは読まない
        for gra in ["../../outside", "..\\..\\outside", "C:/x"]:
            img = self.assets.chara("x", gra, 0x40)
            self.assertIsNotNone(img)
            self.assertEqual(img.pixel(10, 10), (*BLUE, 255))


class TestRealBundledAssets(unittest.TestCase):
    """wphi の同梱グラフィックスがあれば、実物でも確かめます。"""

    BUNDLED = Path.home() / "workspace" / "wphi-source" / "resources" / "phi"

    @unittest.skipUnless(
        (Path.home() / "workspace" / "wphi-source" / "resources" / "phi").exists(),
        "wphi のソースがありません",
    )
    def test_dimensions_match_wphi(self):
        assets = Assets([self.BUNDLED])
        chip = assets.chip("no-such-mapset")
        self.assertEqual((chip.width, chip.height), (512, 96))
        items = assets.items()
        self.assertEqual((items.width, items.height), (960, 32))
        npc = assets.chara("x", "npc2", 0x01)
        self.assertEqual((npc.width, npc.height), (96, 160))
        # 透明と不透明の両方がある
        alphas = {chip.pixel(x, y)[3] for y in range(0, 96, 7) for x in range(0, 512, 13)}
        self.assertIn(0, alphas)
        self.assertIn(255, alphas)
        # 看板の既定グラは Defboardobj.bmp
        board = assets.chara("x", "none", 0x81)
        direct = assets._open("Skins/Mine/Chara/Defboardobj.bmp", colorkey)
        self.assertEqual(board.pixels, direct.pixels)


if __name__ == "__main__":
    unittest.main()
