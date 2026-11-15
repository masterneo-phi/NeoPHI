"""地図の描画のテスト。色で区別できる仮の絵で、画素の位置を確かめます。"""

import sys
import time
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from neophi.bmp import RgbaImage  # noqa: E402
from neophi.map_graphics import (  # noqa: E402
    MAP_TOP,
    arrange_row,
    build_water_grid,
    chara_src_rect,
    chip_src_rect,
    eagle_board,
    magnified_dst,
    render_map_image,
    water_quarter_chip,
    water_quarter_patterns,
)
from neophi.parser import Cell, Chara, EagleEyeEvent, Magnify  # noqa: E402


def _chip_sheet():
    """チップindexごとに色の違うシート。胴体と、はみ出しの色も分けます。"""
    sheet = RgbaImage(512, 96, fill=(0, 0, 0, 255))
    for index in range(32):
        col, row = index % 16, index // 16
        x0, y0 = col * 32, row * 48
        # はみ出し(上16px)
        sheet.fill_rect(x0, y0, 32, 16, (200, index, 50, 255))
        # 胴体(下32px)
        sheet.fill_rect(x0, y0 + 16, 32, 32, (index, 100, 200, 255))
    # 水縁チップ 24 の4つの四半分は別々の色にする
    quarters = [(10, 20, 30), (40, 50, 60), (70, 80, 90), (100, 110, 120)]
    x0, y0 = 8 * 32, 1 * 48 + 16
    for q, color in enumerate(quarters):
        sheet.fill_rect(x0 + (q & 1) * 16, y0 + ((q >> 1) & 1) * 16, 16, 16,
                        (*color, 255))
    return sheet


def _items_sheet():
    sheet = RgbaImage(960, 32, fill=(0, 0, 0, 255))
    for n in range(30):
        sheet.fill_rect(n * 32, 0, 32, 32, (n * 30 % 256, 200, 100, 255))
    # 5番と6番は先頭5pxが空き
    for n in (5, 6):
        sheet.fill_rect(n * 32, 0, 32, 5, (0, 0, 0, 255))
        sheet.fill_rect(n * 32, 5, 32, 27, (150, 200, 100, 255))
    return sheet


def _chara_sheet():
    """(向き, フレーム)ごとに色の違うシート。"""
    sheet = RgbaImage(96, 160, fill=(0, 0, 0, 255))
    frames = [(0, 16), (16, 16), (32, 32), (64, 32)]
    for row in range(4):
        for frame, (x0, w) in enumerate(frames):
            sheet.fill_rect(x0, row * 32, w, 32, (row * 60 + 10, frame * 80 + 10, 150, 255))
    return sheet


def _solid_chara(color):
    return RgbaImage(96, 160, fill=(*color, 255))


def _cells(chips, attrs=None):
    attrs = attrs or [0] * len(chips)
    return [Cell(chip=ord(c), attr=a) for c, a in zip(chips, attrs)]


class TestRects(unittest.TestCase):
    def test_chip_src_rect(self):
        self.assertEqual(chip_src_rect(0), (0, 0, 32, 48))
        self.assertEqual(chip_src_rect(17), (32, 48, 32, 48))
        self.assertIsNone(chip_src_rect(32))
        self.assertIsNone(chip_src_rect(-1))

    def test_chara_src_rect(self):
        # 正面(F=行2)、通常、フレーム0
        self.assertEqual(chara_src_rect("F", "#", 0), (0, 64, 16, 32))
        # 正面、通常、フレーム1
        self.assertEqual(chara_src_rect("F", "#", 1), (16, 64, 16, 32))
        # 背面(B=行0)、巨大、フレーム1
        self.assertEqual(chara_src_rect("B", "*", 1), (64, 0, 32, 32))
        # 数値の向き(2=E → R=行1)
        self.assertEqual(chara_src_rect(2, "#", 0), (0, 32, 16, 32))

    def test_magnified_dst(self):
        self.assertEqual(
            magnified_dst(40, 50, Magnify(w=64, h=64, z=8)), (24, 16, 64, 64)
        )

    def test_arrange_row(self):
        a = Chara(x=2, layer=0, gigant="#")
        b = Chara(x=2, layer=1, gigant="#")
        self.assertEqual(arrange_row([b, a]), [(a, -8), (b, 8)])
        big = Chara(x=2, layer=0, gigant="*")
        small = Chara(x=2, layer=1, gigant="#")
        self.assertEqual(arrange_row([small, big]), [(big, 0), (small, 8)])

    def test_water_patterns(self):
        water = build_water_grid(_cells(["_"] * 9), 3)
        # 全部水なら、真ん中のマスのパターンは全部 0x07
        patterns = water_quarter_patterns(water, 1, 1)
        self.assertEqual(patterns, (7, 7, 7, 7))
        self.assertIsNone(water_quarter_chip(0, 7))
        # 孤立した水はパターン 0 → チップ24
        water2 = build_water_grid(_cells([" "] * 8 + ["_"]), 3)
        patterns2 = water_quarter_patterns(water2, 2, 2)
        self.assertEqual(patterns2, (0, 0, 0, 0))
        self.assertEqual(water_quarter_chip(0, 0), (24, 0))
        self.assertEqual(water_quarter_chip(3, 0), (24, 3))


class TestRender(unittest.TestCase):
    def setUp(self):
        self.sheet = _chip_sheet()
        self.items = _items_sheet()
        self.chara = _chara_sheet()

    def _render(self, cells, chars, dim=7, anim_frame=0, eagle_eye=False,
                sheets=None, items="default", chara_image=None, ghosts=None):
        return render_map_image(
            cells, chars, dim,
            sheets if sheets is not None else [self.sheet] * 4,
            self.items if items == "default" else items,
            (lambda ch: self.chara) if chara_image is None else chara_image,
            anim_frame=anim_frame, eagle_eye=eagle_eye, ghosts=ghosts,
        )

    def test_canvas_size(self):
        out = self._render(_cells([" "] * 49), [])
        self.assertEqual((out.image.width, out.image.height), (224, 224 + MAP_TOP))
        out5 = self._render(_cells([" "] * 25), [], dim=5)
        self.assertEqual((out5.image.width, out5.image.height), (160, 160 + MAP_TOP))

    def test_chip_body_and_overhang(self):
        # (0,0) は ':' = index 1
        out = self._render(_cells([":"] + [" "] * 48), [])
        # 胴体の中心
        self.assertEqual(out.image.pixel(16, 24), (1, 100, 200, 255))
        # はみ出し(1行目の上)
        self.assertEqual(out.image.pixel(16, 8), (200, 1, 50, 255))

    def test_ghost_feet_hidden_behind_wall_below(self):
        # 残像は(3,0)、壁はその下の(3,1)。足の所は壁の色、上の所は残像の色。
        chips = [" "] * 49
        chips[10] = ":"
        ghost = Chara(x=3, y=0, dir="F", name="ghost", gigant="#")
        out = self._render(
            _cells(chips), [],
            ghosts=[(ghost, _solid_chara((9, 9, 9)))],
        )
        self.assertEqual(out.image.pixel(112, 35), (200, 1, 50, 255))
        self.assertEqual(out.image.pixel(112, 20), (9, 9, 9, 255))
        # 残像は名札も基準点も出しません
        self.assertEqual(out.labels, [])
        self.assertEqual(out.anchors, [])

    def test_ghost_does_not_shift_live_chara(self):
        # 生きているキャラと残像が同じマスでも、キャラは横にずれません
        chips = [" "] * 49
        live = Chara(x=3, y=2, dir="F", name="a", gigant="#")
        ghost = Chara(x=3, y=2, dir="F", name="ghost", gigant="#")
        out = self._render(
            _cells(chips), [live],
            ghosts=[(ghost, _solid_chara((9, 9, 9)))],
        )
        # ずれたらキャラの色になる所が、床の色のままです
        self.assertEqual(out.image.pixel(100, 84), (0, 100, 200, 255))
        # 残像はキャラの上に重なります
        self.assertEqual(out.image.pixel(112, 84), (9, 9, 9, 255))
        # 名札は生きているキャラの分だけです
        self.assertEqual([label.name for label in out.labels], ["a"])

    def test_composite_chip_draws_over(self):
        # 'T' は [1, 3] の合成で、3 が上に来る
        out = self._render(_cells(["T"] + [" "] * 48), [])
        self.assertEqual(out.image.pixel(16, 24), (3, 100, 200, 255))

    def test_board_overlay(self):
        # 軟質の床の看板はチップ18、硬質の壁の看板はチップ20
        cells = _cells([" ", "#"] + [" "] * 47, [0x08, 0x08] + [0] * 47)
        out = self._render(cells, [])
        self.assertEqual(out.image.pixel(16, 24), (18, 100, 200, 255))
        self.assertEqual(out.image.pixel(48, 24), (20, 100, 200, 255))

    def test_item_overlay(self):
        cells = _cells([" "] * 49, [0x30] + [0] * 48)
        out = self._render(cells, [])
        # アイテム3番の色が床の上に出る
        self.assertEqual(out.image.pixel(16, 24), (90, 200, 100, 255))

    def test_item_on_circle_clips(self):
        cells = _cells(["x"] + [" "] * 48, [0x50] + [0] * 48)
        out = self._render(cells, [])
        # 5番は src の5行目から描く。描き始めの画素は5行目の色
        self.assertEqual(out.image.pixel(16, 24), (150, 200, 100, 255))
        # アイテムの下(21px分を過ぎた所)はチップの色に戻る
        self.assertEqual(out.image.pixel(16, 30), (14, 100, 200, 255))

    def test_chara_frame_and_dir(self):
        chars = [Chara(x=3, y=3, dir="F", name="a", gigant="#")]
        out0 = self._render(_cells([" "] * 49), chars, anim_frame=0)
        out1 = self._render(_cells([" "] * 49), chars, anim_frame=1)
        # 正面・通常・フレーム0/1 の色
        self.assertEqual(out0.image.pixel(112, 117), (130, 10, 150, 255))
        self.assertEqual(out1.image.pixel(112, 117), (130, 90, 150, 255))

    def test_giant_chara(self):
        chars = [Chara(x=1, y=1, dir="B", name="g", gigant="*")]
        out = self._render(_cells([" "] * 49), chars)
        self.assertEqual(out.image.pixel(48, 53), (10, 170, 150, 255))

    def test_two_chars_same_cell_offset(self):
        def image_for(ch):
            return _solid_chara((200, 10, 10) if ch.gra == "a" else (10, 200, 10))

        chars = [
            Chara(x=2, y=2, dir="F", name="a", gra="a", gigant="#", layer=0),
            Chara(x=2, y=2, dir="F", name="b", gra="b", gigant="#", layer=1),
        ]
        out = self._render(_cells([" "] * 49), chars, chara_image=image_for)
        self.assertEqual(out.image.pixel(72, 85), (200, 10, 10, 255))
        self.assertEqual(out.image.pixel(88, 85), (10, 200, 10, 255))

    def test_magnify(self):
        chars = [Chara(x=1, y=1, dir="B", name="m", gigant="*",
                       magnify=Magnify(w=64, h=64, z=8))]
        out = self._render(
            _cells([" "] * 49), chars,
            chara_image=lambda ch: _solid_chara((220, 180, 40)),
        )
        self.assertEqual(out.image.pixel(48, 35), (220, 180, 40, 255))

    def test_labels_exclude_center_and_strip_tags(self):
        chars = [
            Chara(x=3, y=3, dir="F", name="自分", gigant="#"),
            Chara(x=1, y=1, dir="F", name="/*x*/あいう", gigant="#"),
            Chara(x=1, y=1, dir="F", name="後勝ち", gigant="#"),
        ]
        out = self._render(_cells([" "] * 49), chars)
        self.assertEqual(len(out.labels), 1)
        label = out.labels[0]
        self.assertEqual((label.x, label.y, label.name), (48, 67, "後勝ち"))

    def test_missing_chara_is_placeholder(self):
        chars = [Chara(x=2, y=2, dir="F", name="だれか", gigant="#")]
        out = self._render(_cells([" "] * 49), chars, chara_image=lambda ch: None)
        self.assertEqual(out.image.pixel(80, 85), (255, 255, 0, 255))
        self.assertEqual(len(out.placeholders), 1)
        holder = out.placeholders[0]
        self.assertEqual((holder.x, holder.y, holder.name), (80, 85, "だれか"))

    def test_water_edge_quarters(self):
        # 孤立した水のマス(1,2)。4つの四半分がチップ24の色になる
        chips = [" "] * 9
        chips[7] = "_"
        out = self._render(_cells(chips), [], dim=3)
        self.assertEqual(out.image.pixel(40, 88), (10, 20, 30, 255))
        self.assertEqual(out.image.pixel(56, 88), (40, 50, 60, 255))
        self.assertEqual(out.image.pixel(40, 104), (70, 80, 90, 255))
        self.assertEqual(out.image.pixel(56, 104), (100, 110, 120, 255))

    def test_water_surrounded_has_no_edge(self):
        out = self._render(_cells(["_"] * 9), [], dim=3)
        self.assertEqual(out.image.pixel(48, 56), (4, 100, 200, 255))

    def test_eagle_eye_item_chip(self):
        cells = _cells([" "] * 9, [0x20] + [0] * 8)
        out = self._render(cells, [], dim=3, eagle_eye=True)
        self.assertEqual(out.image.pixel(16, 24), (19, 100, 200, 255))

    def test_fallback_without_graphics(self):
        out = self._render(
            _cells([":"] + [" "] * 48, [0x30] + [0] * 48), [],
            sheets=[None, None, None, None], items=None,
            chara_image=lambda ch: None,
        )
        # チップ1番の代わりの色
        self.assertEqual(out.image.pixel(48, 24), (40, 40, 40, 255))
        # アイテムの代わりの明るい四角
        self.assertEqual(out.image.pixel(16, 24), (255, 255, 200, 255))

    def test_define_sheet_per_attr(self):
        other = RgbaImage(512, 96, fill=(9, 9, 9, 255))
        cells = _cells([" "] * 49, [1] + [0] * 48)
        out = self._render(cells, [], sheets=[self.sheet, other, None, None])
        # attr の下位2ビットが1のマスは2枚目のシート
        self.assertEqual(out.image.pixel(16, 24), (9, 9, 9, 255))
        self.assertEqual(out.image.pixel(48, 24), (0, 100, 200, 255))

    def test_render_is_fast_enough(self):
        chars = [Chara(x=i % 7, y=i // 7, dir="F", name=f"c{i}", gigant="#")
                 for i in range(10)]
        start = time.monotonic()
        self._render(_cells(["T", "_", "#", " "] * 12 + [" "]), chars)
        self.assertLess(time.monotonic() - start, 1.0)


class TestEagleBoard(unittest.TestCase):
    def test_person_becomes_chara(self):
        cells = [Cell(chip=ord(":"), attr=0) for _ in range(6)]
        cells[4] = Cell(chip=ord(":"), attr=0x58)
        ev = EagleEyeEvent(width=3, height=2, cells=cells)
        dim, out_cells, chars = eagle_board(ev)
        self.assertEqual(dim, 3)
        self.assertEqual(out_cells[4], Cell(chip=ord(":"), attr=0))
        self.assertEqual(len(chars), 1)
        ch = chars[0]
        self.assertEqual((ch.x, ch.y, ch.dir, ch.gra, ch.gigant, ch.default),
                         (1, 1, "F", "t_man", "*", 0x40))
        # 盤面の外は「不明な場所」
        self.assertEqual(out_cells[8].chip, ord("?"))


if __name__ == "__main__":
    unittest.main()
