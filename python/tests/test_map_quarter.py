"""クオータービューの描画のテスト。色で区別できる仮の絵で確かめます。"""

import sys
import time
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from neophi.bmp import RgbaImage  # noqa: E402
from neophi.map_quarter import (  # noqa: E402
    PRESETS,
    quarter_geometry,
    quarter_pick,
    render_quarter_image,
)
from neophi.parser import Cell, Chara  # noqa: E402

BUNDLED = Path.home() / "workspace" / "wphi-source" / "resources" / "phi"


def _chip_sheet():
    """チップindexごとに、胴体と高さの色を分けたシート。"""
    sheet = RgbaImage(512, 96, fill=(0, 0, 0, 255))
    for index in range(32):
        col, row = index % 16, index // 16
        x0, y0 = col * 32, row * 48
        # 0番(空の床)は、実物の平らなチップと同じく高さが透明です。
        # 透明でないと、手前の壁が奥の床を全部隠してしまいます
        overhang = (0, 0, 0, 0) if index == 0 else (200, index, 50, 255)
        sheet.fill_rect(x0, y0, 32, 16, overhang)
        sheet.fill_rect(x0, y0 + 16, 32, 32, (index, 100, 200, 255))
    quarters = [(10, 20, 30), (40, 50, 60), (70, 80, 90), (100, 110, 120)]
    x0, y0 = 8 * 32, 1 * 48 + 16
    for q, color in enumerate(quarters):
        sheet.fill_rect(x0 + (q & 1) * 16, y0 + ((q >> 1) & 1) * 16, 16, 16,
                        (*color, 255))
    return sheet


def _chara_sheet():
    sheet = RgbaImage(96, 160, fill=(0, 0, 0, 255))
    frames = [(0, 16), (16, 16), (32, 32), (64, 32)]
    for row in range(4):
        for frame, (x0, w) in enumerate(frames):
            sheet.fill_rect(x0, row * 32, w, 32, (row * 60 + 10, frame * 80 + 10, 150, 255))
    return sheet


def _cells(chips, attrs=None):
    attrs = attrs or [0] * len(chips)
    return [Cell(chip=ord(c), attr=a) for c, a in zip(chips, attrs)]


class TestGeometry(unittest.TestCase):
    def test_dims(self):
        self.assertEqual(quarter_geometry(7, PRESETS["tilt"]), (24, 40, 272, 160))
        self.assertEqual(quarter_geometry(7, PRESETS["oblique"]), (24, 40, 384, 160))
        self.assertEqual(quarter_geometry(7, PRESETS["iso"]), (136, 40, 272, 160))
        self.assertEqual(quarter_geometry(5, PRESETS["tilt"]), (24, 40, 208, 128))

    def test_pick_round_trip(self):
        for view in PRESETS.values():
            base_x, base_y, width, height = quarter_geometry(7, view)
            ux, uy = view.u
            vx, vy = view.v
            for y in range(7):
                for x in range(7):
                    px = base_x + (x + 0.5) * ux + (y + 0.5) * vx
                    py = base_y + (x + 0.5) * uy + (y + 0.5) * vy
                    self.assertEqual(
                        quarter_pick(view, 7, base_x, base_y, px, py), (x, y),
                        (view.name, x, y),
                    )
            self.assertIsNone(quarter_pick(view, 7, base_x, base_y, 0, 0))
            self.assertIsNone(quarter_pick(view, 7, base_x, base_y, base_x, height - 1))


class TestRender(unittest.TestCase):
    def setUp(self):
        self.sheet = _chip_sheet()
        self.chara = _chara_sheet()

    def _render(self, cells, chars, view, dim=7, anim_frame=0, eagle_eye=False,
                sheets=None, items=None, chara_image=None, ghosts=None):
        return render_quarter_image(
            cells, chars, dim,
            [self.sheet] * 4 if sheets is None else sheets,
            items, (lambda ch: self.chara) if chara_image is None else chara_image,
            view, anim_frame=anim_frame, eagle_eye=eagle_eye, ghosts=ghosts,
        )

    def test_tilt_floor_and_height(self):
        chips = [" "] * 49
        chips[42] = ":"  # (0,6) 最後の行
        out = self._render(_cells(chips), [], PRESETS["tilt"])
        self.assertEqual((out.image.width, out.image.height), (272, 160))
        self.assertEqual(out.image.pixel(40, 144), (1, 100, 200, 255))
        self.assertEqual(out.image.pixel(40, 128), (200, 1, 50, 255))
        self.assertEqual(out.image.pixel(0, 0), (0, 0, 0, 255))

    def test_oblique_floor_and_height(self):
        chips = [" "] * 49
        chips[42] = ":"
        out = self._render(_cells(chips), [], PRESETS["oblique"])
        self.assertEqual(out.image.pixel(144, 144), (1, 100, 200, 255))
        self.assertEqual(out.image.pixel(136, 128), (200, 1, 50, 255))

    def test_iso_floor_and_height(self):
        chips = [":"] + [" "] * 48
        out = self._render(_cells(chips), [], PRESETS["iso"])
        self.assertEqual(out.image.pixel(136, 48), (1, 100, 200, 255))
        self.assertEqual(out.image.pixel(144, 36), (200, 1, 50, 255))

    def test_front_wall_hides_back_chara(self):
        chips = [" "] * 49
        chips[7] = "#"  # (0,1) 手前の壁
        chars = [Chara(x=0, y=0, dir="F", name="a", gigant="#")]
        out = self._render(
            _cells(chips), chars, PRESETS["tilt"],
            chara_image=lambda ch: RgbaImage(96, 160, fill=(200, 10, 10, 255)),
        )
        # 重なる所は壁の色、キャラだけの所はキャラの色
        self.assertEqual(out.image.pixel(40, 45), (200, 7, 50, 255))
        self.assertEqual(out.image.pixel(40, 30), (200, 10, 10, 255))

    def test_ghost_feet_hidden_behind_wall_below(self):
        # 残像も、生きているキャラと同じ奥行きの順で描かれます
        chips = [" "] * 49
        chips[7] = "#"  # (0,1) 手前の壁
        ghost = Chara(x=0, y=0, dir="F", name="ghost", gigant="#")
        out = self._render(
            _cells(chips), [], PRESETS["tilt"],
            ghosts=[(ghost, RgbaImage(96, 160, fill=(200, 10, 10, 255)))],
        )
        self.assertEqual(out.image.pixel(40, 45), (200, 7, 50, 255))
        self.assertEqual(out.image.pixel(40, 30), (200, 10, 10, 255))
        self.assertEqual(out.labels, [])

    def test_chara_is_upright_and_animates(self):
        chars = [Chara(x=3, y=3, dir="F", name="a", gigant="#")]
        out0 = self._render(_cells([" "] * 49), chars, PRESETS["tilt"], anim_frame=0)
        out1 = self._render(_cells([" "] * 49), chars, PRESETS["tilt"], anim_frame=1)
        # 縦の列は同じ色(潰れていない)
        self.assertEqual(out0.image.pixel(136, 70), (130, 10, 150, 255))
        self.assertEqual(out0.image.pixel(136, 80), (130, 10, 150, 255))
        # フレームで色が変わる
        self.assertEqual(out1.image.pixel(136, 70), (130, 90, 150, 255))

    def test_labels(self):
        chars = [
            Chara(x=3, y=3, dir="F", name="自分", gigant="#"),
            Chara(x=1, y=1, dir="F", name="/*x*/あいう", gigant="#"),
        ]
        out = self._render(_cells([" "] * 49), chars, PRESETS["tilt"])
        self.assertEqual(len(out.labels), 1)
        label = out.labels[0]
        self.assertEqual((label.x, label.y, label.name), (72, 46, "あいう"))

    def test_water_quarters(self):
        chips = [" "] * 49
        chips[42] = "_"
        out = self._render(_cells(chips), [], PRESETS["tilt"])
        self.assertEqual(out.image.pixel(32, 140), (10, 20, 30, 255))
        self.assertEqual(out.image.pixel(48, 140), (40, 50, 60, 255))
        self.assertEqual(out.image.pixel(32, 148), (70, 80, 90, 255))
        self.assertEqual(out.image.pixel(48, 148), (100, 110, 120, 255))

    def test_eagle_eye_item_chip(self):
        cells = _cells([" "] * 49, [0] * 42 + [0x20] + [0] * 6)
        out = self._render(cells, [], PRESETS["tilt"], eagle_eye=True)
        self.assertEqual(out.image.pixel(40, 144), (19, 100, 200, 255))

    def test_fallback_without_graphics(self):
        cells = _cells([" "] * 49, [0] * 42 + [0x30] + [0] * 6)
        out = self._render(
            cells, [], PRESETS["tilt"],
            sheets=[None, None, None, None], items=None,
            chara_image=lambda ch: None,
        )
        self.assertEqual(out.image.pixel(40, 144), (255, 255, 200, 255))
        plain = self._render(
            _cells([" "] * 49), [], PRESETS["tilt"],
            sheets=[None, None, None, None], items=None,
            chara_image=lambda ch: None,
        )
        self.assertEqual(plain.image.pixel(40, 144), (40, 40, 40, 255))

    def test_render_is_fast_enough(self):
        chars = [Chara(x=i % 7, y=i // 7, dir="F", name=f"c{i}", gigant="#")
                 for i in range(10)]
        start = time.monotonic()
        self._render(_cells(["T", "_", "#", " "] * 12 + [" "]), chars,
                     PRESETS["iso"])
        self.assertLess(time.monotonic() - start, 2.0)


@unittest.skipUnless(BUNDLED.exists(), "wphi の resources/phi がありません")
class TestRealAssets(unittest.TestCase):
    def test_real_assets_render(self):
        from neophi.assets import Assets
        from neophi.map_graphics import grid_dim, render_map_image
        from neophi.png import encode_png

        assets = Assets([str(BUNDLED)])
        cells = _cells(["T", "_", "#", " ", ":", "o", "H"] * 7)
        chars = [Chara(x=3, y=3, dir="F", name="自分", gra="npc2", gigant="#"),
                 Chara(x=4, y=3, dir="B", name="犬", gra="t_dog", gigant="*")]
        flat = render_map_image(
            cells, chars, grid_dim(7), [assets.chip("")] * 4, assets.items(),
            lambda ch: assets.chara(ch.name, ch.gra, ch.default),
        )
        for view in PRESETS.values():
            rendered = render_quarter_image(
                cells, chars, 7, [assets.chip("")] * 4, assets.items(),
                lambda ch: assets.chara(ch.name, ch.gra, ch.default), view,
            )
            _, _, width, height = quarter_geometry(7, view)
            self.assertEqual((rendered.image.width, rendered.image.height),
                             (width, height))
            non_black = sum(
                1 for i in range(0, len(rendered.image.pixels), 4)
                if rendered.image.pixels[i : i + 3] != b"\x00\x00\x00"
            )
            self.assertGreater(non_black, 1000, view.name)
            self.assertNotEqual(encode_png(rendered.image), encode_png(flat.image))


if __name__ == "__main__":
    unittest.main()
