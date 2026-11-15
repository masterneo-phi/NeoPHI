"""3Dレンダラのテスト。写し方・奥行き・絵の貼り方を確かめます。"""

import sys
import time
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from neophi.bmp import RgbaImage  # noqa: E402
from neophi.map_3d import (  # noqa: E402
    Camera,
    _body_is_opaque,
    _camera_basis,
    _chip_shape,
    _opening_looks_right,
    _project,
    _rasterize,
    _silhouette_runs,
    render_3d_image,
)
from neophi.parser import Cell, Chara  # noqa: E402
from neophi.png import encode_png  # noqa: E402

BUNDLED = Path.home() / "workspace" / "wphi-source" / "resources" / "phi"


def _chip_sheet():
    """0番と1番は平ら、7番だけ背が高いシート。"""
    sheet = RgbaImage(512, 96, fill=(0, 0, 0, 0))
    for index in range(32):
        col, row = index % 16, index // 16
        x0, y0 = col * 32, row * 48
        sheet.fill_rect(x0, y0 + 16, 32, 32, (index, 100, 200, 255))
    sheet.fill_rect(7 * 32, 0, 32, 16, (200, 7, 50, 255))
    return sheet


def _cells(chips, attrs=None):
    attrs = attrs or [0] * len(chips)
    return [Cell(chip=ord(c), attr=a) for c, a in zip(chips, attrs)]


class TestCamera(unittest.TestCase):
    def test_center_projects_to_screen_center(self):
        camera = Camera(width=320, height=240)
        basis = _camera_basis(camera, 7)
        point = _project((3.5, -3.5, 0.0), *basis)
        self.assertIsNotNone(point)
        self.assertAlmostEqual(point[0], 160.0, places=6)
        self.assertAlmostEqual(point[1], 120.0, places=6)

    def test_east_is_right_and_north_is_up(self):
        basis = _camera_basis(Camera(width=320, height=240), 7)
        center = _project((3.5, -3.5, 0.0), *basis)
        east = _project((6.5, -3.5, 0.0), *basis)
        north = _project((3.5, -0.5, 0.0), *basis)
        self.assertGreater(east[0], center[0])
        self.assertLess(north[1], center[1])

    def test_nearer_is_smaller_depth(self):
        basis = _camera_basis(Camera(width=320, height=240), 7)
        near = _project((3.5, -6.5, 0.0), *basis)
        far = _project((3.5, -0.5, 0.0), *basis)
        self.assertLess(near[2], far[2])

    def test_behind_camera_is_none(self):
        basis = _camera_basis(Camera(width=320, height=240), 7)
        # カメラの後ろ(南のずっと先)の点は写りません
        self.assertIsNone(_project((3.5, -100.0, 0.0), *basis))

    def test_opposite_azimuth_flips_left_right(self):
        south = _camera_basis(Camera(azimuth=0, width=320, height=240), 7)
        north = _camera_basis(Camera(azimuth=180, width=320, height=240), 7)
        east_from_south = _project((6.5, -3.5, 0.0), *south)
        east_from_north = _project((6.5, -3.5, 0.0), *north)
        self.assertGreater(east_from_south[0], 160)
        self.assertLess(east_from_north[0], 160)


class TestRasterize(unittest.TestCase):
    def _tri(self, corners, z, color):
        iz = 1.0 / z
        verts = [(x, y, iz, 0.0, 0.0) for x, y in corners]
        return (verts[0], verts[1], verts[2], (None, 0, 0, *color), 256)

    def test_nearer_triangle_wins_regardless_of_order(self):
        corners = [(10, 10), (90, 10), (10, 90)]
        near = self._tri(corners, 5.0, (255, 0, 0))
        far = self._tri(corners, 10.0, (0, 0, 255))
        for tris in ([near, far], [far, near]):
            img = RgbaImage(100, 100, fill=(0, 0, 0, 255))
            _rasterize(img, tris)
            self.assertEqual(img.pixel(30, 30), (255, 0, 0, 255))
            self.assertEqual(img.pixel(95, 95), (0, 0, 0, 255))

    def test_texture_sampling_and_transparency(self):
        tex = RgbaImage(2, 2, fill=(0, 0, 0, 0))
        tex.set_pixel(0, 0, (255, 0, 0, 255))
        tex.set_pixel(1, 0, (0, 255, 0, 255))
        tex.set_pixel(0, 1, (0, 0, 255, 255))
        # (1,1) は透明のまま
        corners = [(0, 0), (64, 0), (64, 64), (0, 64)]
        uvs = [(0, 0), (2, 0), (2, 2), (0, 2)]
        iz = 1.0 / 5.0
        verts = [(x, y, iz, u * iz, v * iz) for (x, y), (u, v) in zip(corners, uvs)]
        payload = (tex.pixels, tex.width, tex.height, 0, 0, 0)
        tris = [
            (verts[0], verts[1], verts[2], payload, 256),
            (verts[0], verts[2], verts[3], payload, 256),
        ]
        img = RgbaImage(64, 64, fill=(9, 9, 9, 255))
        _rasterize(img, tris)
        self.assertEqual(img.pixel(5, 5), (255, 0, 0, 255))
        self.assertEqual(img.pixel(50, 5), (0, 255, 0, 255))
        self.assertEqual(img.pixel(5, 50), (0, 0, 255, 255))
        # 透明な絵の所は、背景が残ります
        self.assertEqual(img.pixel(40, 40), (9, 9, 9, 255))


class TestRender(unittest.TestCase):
    def setUp(self):
        self.sheet = _chip_sheet()
        self.chara = RgbaImage(96, 160, fill=(220, 30, 30, 255))

    def _render(self, cells, chars, dim=3, camera=None):
        return render_3d_image(
            cells, chars, dim, [self.sheet] * 4, None,
            lambda ch: self.chara,
            camera or Camera(width=160, height=120, distance=5.0),
        )

    def _count(self, image, color):
        data = image.pixels
        return sum(
            1 for i in range(0, len(data), 4)
            if (data[i], data[i + 1], data[i + 2]) == color
        )

    def test_dims_and_determinism(self):
        out1 = self._render(_cells([" "] * 9), [])
        out2 = self._render(_cells([" "] * 9), [])
        self.assertEqual((out1.image.width, out1.image.height), (160, 120))
        self.assertEqual(encode_png(out1.image), encode_png(out2.image))

    def test_floor_wall_and_chara_colors(self):
        chips = [" "] * 9
        chips[4] = "#"  # 真ん中に背の高いチップ
        chars = [Chara(x=1, y=2, dir="F", name="あいう", gigant="#")]
        out = self._render(_cells(chips), chars)
        # 床の色
        self.assertGreater(self._count(out.image, (0, 100, 200)), 100)
        # 壁の南面の色(明るさ 240/256)
        south = (200 * 240 >> 8, 7 * 240 >> 8, 50 * 240 >> 8)
        self.assertGreater(self._count(out.image, south), 10)
        # キャラの色
        self.assertGreater(self._count(out.image, (220, 30, 30)), 50)
        # ラベルは、頭の上に1つ
        self.assertEqual(len(out.labels), 1)
        self.assertEqual(out.labels[0].name, "あいう")

    def test_empty_map_is_background_only(self):
        out = self._render([], [])
        self.assertEqual(self._count(out.image, (0, 100, 200)), 0)

    def test_fallback_without_graphics(self):
        out = render_3d_image(
            _cells([" "] * 9), [], 3, [None] * 4, None,
            lambda ch: None, Camera(width=160, height=120, distance=5.0),
        )
        self.assertGreater(self._count(out.image, (40, 40, 40)), 100)

    def test_render_is_fast_enough(self):
        chars = [Chara(x=i % 3, y=i // 3, dir="F", name=f"c{i}", gigant="#")
                 for i in range(4)]
        start = time.monotonic()
        self._render(_cells(["T", "_", "#", " ", ":", "o", "H", "=", "{"]), chars)
        self.assertLess(time.monotonic() - start, 5.0)


class TestSilhouetteRuns(unittest.TestCase):
    def _image(self, rows):
        img = RgbaImage(len(rows[0]), len(rows), fill=(0, 0, 0, 0))
        colors = {"R": (255, 0, 0, 255), "G": (0, 255, 0, 255),
                  "B": (0, 0, 255, 255)}
        for j, row in enumerate(rows):
            for i, mark in enumerate(row):
                if mark in colors:
                    img.set_pixel(i, j, colors[mark])
        return img

    def test_diamond_runs(self):
        img = self._image([".RR.", "RGGR", ".RR."])
        runs = _silhouette_runs(img, (0, 0, 4, 3))
        red = (255, 0, 0)
        self.assertEqual(runs["left"],
                         [(1, 0, 1, red), (0, 1, 2, red), (1, 2, 3, red)])
        self.assertEqual(runs["right"],
                         [(2, 0, 1, red), (3, 1, 2, red), (2, 2, 3, red)])
        self.assertEqual(runs["top"],
                         [(1, 0, 1, red), (0, 1, 3, red), (1, 3, 4, red)])
        self.assertEqual(runs["bottom"],
                         [(1, 0, 1, red), (2, 1, 3, red), (1, 3, 4, red)])

    def test_color_change_splits_runs(self):
        img = self._image(["RR", "BB"])
        runs = _silhouette_runs(img, (0, 0, 2, 2))
        self.assertEqual(runs["left"],
                         [(0, 0, 1, (255, 0, 0)), (0, 1, 2, (0, 0, 255))])

    def test_transparent_has_no_runs(self):
        img = RgbaImage(4, 4, fill=(0, 0, 0, 0))
        runs = _silhouette_runs(img, (0, 0, 4, 4))
        self.assertEqual(runs, {"left": [], "right": [],
                                "top": [], "bottom": []})


class TestBodyOpaqueAndChipShape(unittest.TestCase):
    def test_body_opaque(self):
        sheet = RgbaImage(32, 48, fill=(9, 9, 9, 255))
        self.assertTrue(_body_is_opaque(sheet, (0, 0, 32, 48)))
        sheet.fill_rect(0, 16, 32, 1, (0, 0, 0, 0))
        self.assertFalse(_body_is_opaque(sheet, (0, 0, 32, 48)))

    def test_chip_shape_overrides(self):
        sheet = RgbaImage(512, 96, fill=(9, 9, 9, 255))
        self.assertEqual(_chip_shape(sheet, 11), "plank")
        self.assertEqual(_chip_shape(sheet, 12), "plank")
        self.assertEqual(_chip_shape(sheet, 14), "open_chest")
        self.assertEqual(_chip_shape(sheet, 21), "open_chest")
        self.assertEqual(_chip_shape(sheet, 15), "chest")
        self.assertEqual(_chip_shape(sheet, 22), "chest")
        self.assertEqual(_chip_shape(sheet, 6), "rock")
        self.assertEqual(_chip_shape(sheet, 7), "wall")

    def test_chip_shape_cross_for_open_body(self):
        sheet = RgbaImage(512, 96, fill=(9, 9, 9, 255))
        # 3番の胴体を透明にすると、十字の押し出しになります
        sheet.fill_rect(3 * 32, 16, 32, 32, (0, 0, 0, 0))
        self.assertEqual(_chip_shape(sheet, 3), "cross")


class TestExtrudeRender(unittest.TestCase):
    def setUp(self):
        # 7番:高さは左が赤・右が青、胴体は真ん中の緑の幹だけです
        self.sheet = RgbaImage(512, 96, fill=(0, 0, 0, 0))
        self.sheet.fill_rect(7 * 32, 0, 16, 16, (255, 0, 0, 255))
        self.sheet.fill_rect(7 * 32 + 16, 0, 16, 16, (0, 0, 255, 255))
        self.sheet.fill_rect(7 * 32 + 14, 16, 4, 32, (0, 200, 0, 255))
        self.sheet.fill_rect(0, 16, 32, 32, (0, 100, 200, 255))
        # キャラの絵:左が赤・右が青で、向きで見え方が変わります
        self.chara = RgbaImage(96, 160, fill=(0, 0, 0, 0))
        self.chara.fill_rect(0, 0, 48, 160, (255, 0, 0, 255))
        self.chara.fill_rect(48, 0, 48, 160, (0, 0, 255, 255))

    def _render(self, cells, chars, style, camera=None):
        return render_3d_image(
            cells, chars, 3, [self.sheet] * 4, None,
            lambda ch: self.chara,
            camera or Camera(width=160, height=120, distance=5.0),
            style=style,
        )

    def _count(self, image, color):
        data = image.pixels
        return sum(
            1 for i in range(0, len(data), 4)
            if (data[i], data[i + 1], data[i + 2]) == color
        )

    def test_extrude_shows_front_and_trunk(self):
        chips = [" "] * 9
        chips[4] = "#"
        out = self._render(_cells(chips), [], "extrude")
        self.assertGreater(self._count(out.image, (255, 0, 0)), 20)
        self.assertGreater(self._count(out.image, (0, 0, 255)), 20)
        self.assertGreater(self._count(out.image, (0, 200, 0)), 10)

    def test_extrude_side_visible_from_diagonal(self):
        chips = [" "] * 9
        chips[4] = "#"
        camera = Camera(width=160, height=120, distance=5.0, azimuth=45.0)
        out = self._render(_cells(chips), [], "extrude", camera)
        # 東側の側面は、青を暗くした色です
        self.assertGreater(self._count(out.image, (0, 0, 214)), 5)

    def test_extrude_differs_from_boxes(self):
        chips = [" "] * 9
        chips[4] = "#"
        boxes = self._render(_cells(chips), [], "boxes")
        extruded = self._render(_cells(chips), [], "extrude")
        self.assertNotEqual(encode_png(boxes.image), encode_png(extruded.image))
        again = self._render(_cells(chips), [], "extrude")
        self.assertEqual(encode_png(extruded.image), encode_png(again.image))

    def test_opaque_body_stays_a_box(self):
        # 胴体が不透明なチップは、extrude でも元の厚みの箱になります
        sheet = _chip_sheet()
        out = render_3d_image(
            _cells([" "] * 4 + ["#"] + [" "] * 4), [], 3,
            [sheet] * 4, None, lambda ch: None,
            Camera(width=160, height=120, distance=5.0), style="extrude",
        )
        south = (200 * 240 >> 8, 7 * 240 >> 8, 50 * 240 >> 8)
        self.assertGreater(self._count(out.image, south), 10)

    def test_wall_is_as_tall_as_door(self):
        # 壁の箱は、扉と同じ高さ(1.0)です
        sheet = RgbaImage(512, 96, fill=(0, 0, 0, 0))
        for index in (7, 11):
            sheet.fill_rect(index * 32, 0, 32, 16, (200, 7, 50, 255))
            sheet.fill_rect(index * 32, 16, 32, 32, (7, 100, 200, 255))
        sheet.fill_rect(0, 16, 32, 32, (0, 100, 200, 255))

        def top_row(cells, color):
            out = render_3d_image(
                cells, [], 1, [sheet] * 4, None, lambda ch: None,
                Camera(width=160, height=120, distance=5.0), style="extrude",
            )
            data = out.image.pixels
            rows = [i // (160 * 4) for i in range(0, len(data), 4)
                    if (data[i], data[i + 1], data[i + 2]) == color]
            return min(rows) if rows else None

        south = (200 * 240 >> 8, 7 * 240 >> 8, 50 * 240 >> 8)
        top_wall = top_row(_cells(["#"]), south)
        top_door = top_row(_cells(["["]), (200, 7, 50))
        self.assertIsNotNone(top_wall)
        self.assertIsNotNone(top_door)
        # 同じ高さでも、箱の前面は扉より手前なので、少し下に出ます
        self.assertLessEqual(abs(top_wall - top_door), 12)

    def test_door_follows_wall_run(self):
        # 南北に並んだ扉も、壁の並びに沿って向きます
        sheet = RgbaImage(512, 96, fill=(0, 0, 0, 0))
        sheet.fill_rect(11 * 32, 0, 32, 16, (0, 0, 255, 255))
        sheet.fill_rect(11 * 32, 16, 32, 32, (255, 0, 0, 255))
        sheet.fill_rect(0, 16, 32, 32, (0, 100, 200, 255))

        def render(cells):
            return render_3d_image(
                cells, [], 3, [sheet] * 4, None, lambda ch: None,
                Camera(width=160, height=120, distance=5.0), style="extrude",
            )

        single = render(_cells([" "] * 4 + ["["] + [" "] * 4))
        paired = render(_cells([" ", "[", " ", " ", "[", " ", " ", " ", " "]))
        self.assertNotEqual(encode_png(single.image), encode_png(paired.image))

    def test_chara_facing_changes_render(self):
        # 行ごとに色の違うキャラの絵では、向きで絵が変わります
        sheet = RgbaImage(96, 160, fill=(0, 0, 0, 255))
        sheet.fill_rect(0, 0, 96, 32, (255, 0, 0, 255))
        sheet.fill_rect(0, 32, 96, 32, (0, 255, 0, 255))
        sheet.fill_rect(0, 64, 96, 32, (0, 0, 255, 255))
        sheet.fill_rect(0, 96, 96, 32, (255, 255, 0, 255))

        def render(direction):
            return render_3d_image(
                _cells([" "] * 9),
                [Chara(x=1, y=1, dir=direction, name="a", gigant="#")],
                3, [self.sheet] * 4, None, lambda ch: sheet,
                Camera(width=160, height=120, distance=5.0), style="extrude",
            )

        front = render("F")
        right = render("R")
        back = render("B")
        self.assertNotEqual(encode_png(front.image), encode_png(right.image))
        self.assertNotEqual(encode_png(front.image), encode_png(back.image))

    def test_plank_shows_top_of_art_at_chara_height(self):
        # 扉は絵の上32行だけを板にし、高さはキャラと同じ1.0です。
        # 下16行(壁の下地)は板に出ず、床にだけ描かれます。
        sheet = RgbaImage(512, 96, fill=(0, 0, 0, 0))
        sheet.fill_rect(11 * 32, 0, 32, 16, (0, 0, 255, 255))
        sheet.fill_rect(11 * 32, 16, 32, 32, (255, 0, 0, 255))
        sheet.fill_rect(0, 16, 32, 32, (0, 100, 200, 255))

        def render(style, cells):
            return render_3d_image(
                cells, [], 3, [sheet] * 4, None, lambda ch: None,
                Camera(width=160, height=120, distance=5.0), style=style,
            )

        cells = _cells([" "] * 4 + ["["] + [" "] * 4)
        out = render("extrude", cells)
        self.assertGreater(self._count(out.image, (0, 0, 255)), 20)
        self.assertGreater(self._count(out.image, (255, 0, 0)), 20)
        self.assertNotEqual(encode_png(out.image),
                            encode_png(render("boxes", cells).image))
        # 扉1マスだけの地図で、板の一番上の高さを確かめます。
        # 高さ1.0なら一番上の青は33行目あたり、1.5なら18行目あたりです。
        single = render_3d_image(
            _cells(["["]), [], 1, [sheet] * 4, None, lambda ch: None,
            Camera(width=160, height=120, distance=5.0), style="extrude",
        )
        data = single.image.pixels
        top_blue = min(
            (i // (160 * 4) for i in range(0, len(data), 4)
             if (data[i], data[i + 1], data[i + 2]) == (0, 0, 255)),
            default=None,
        )
        self.assertIsNotNone(top_blue)
        self.assertGreater(top_blue, 25)

    def test_chest_lid_is_raised(self):
        # 宝箱は、蓋が後ろへ傾いて立ち上がり、胴体の上に暗い開口があります
        sheet = RgbaImage(512, 96, fill=(0, 0, 0, 0))
        sheet.fill_rect(15 * 32, 13, 32, 15, (255, 0, 0, 255))
        sheet.fill_rect(15 * 32, 28, 32, 20, (150, 100, 50, 255))
        sheet.fill_rect(0, 16, 32, 32, (0, 100, 200, 255))
        out = render_3d_image(
            _cells([" "] * 4 + ["%"] + [" "] * 4), [], 3,
            [sheet] * 4, None, lambda ch: None,
            Camera(width=160, height=120, distance=5.0, azimuth=45.0),
            style="extrude",
        )
        self.assertGreater(self._count(out.image, (255, 0, 0)), 20)
        self.assertGreater(self._count(out.image, (214, 0, 0)), 5)
        opening = (35 * 200 >> 8, 24 * 200 >> 8, 18 * 200 >> 8)
        self.assertGreater(self._count(out.image, opening), 5)
        data = out.image.pixels
        top_red = min(
            (i // (160 * 4) for i in range(0, len(data), 4)
             if (data[i], data[i + 1], data[i + 2]) == (255, 0, 0)),
            default=None,
        )
        top_brown = min(
            (i // (160 * 4) for i in range(0, len(data), 4)
             if (data[i], data[i + 1], data[i + 2]) == (150, 100, 50)),
            default=None,
        )
        self.assertIsNotNone(top_red)
        self.assertIsNotNone(top_brown)
        # 蓋の赤は、胴体の茶色より上にあります
        self.assertLess(top_red, top_brown)

    def test_chest_falls_back_without_lid_art(self):
        # 蓋の絵がなければ、普通の箱形になります
        sheet = RgbaImage(512, 96, fill=(0, 0, 0, 0))
        sheet.fill_rect(15 * 32, 28, 32, 20, (150, 100, 50, 255))
        sheet.fill_rect(0, 16, 32, 32, (0, 100, 200, 255))
        out = render_3d_image(
            _cells([" "] * 4 + ["%"] + [" "] * 4), [], 3,
            [sheet] * 4, None, lambda ch: None,
            Camera(width=160, height=120, distance=5.0), style="extrude",
        )
        self.assertGreater(self._count(out.image, (150, 100, 50)), 10)
        opening = (35 * 200 >> 8, 24 * 200 >> 8, 18 * 200 >> 8)
        self.assertEqual(self._count(out.image, opening), 0)

    def test_door_floor_is_ground(self):
        # 扉のマスの床は、扉の下地ではなく地面の絵になります
        sheet = RgbaImage(512, 96, fill=(0, 0, 0, 0))
        sheet.fill_rect(11 * 32, 0, 32, 16, (0, 0, 255, 255))
        sheet.fill_rect(11 * 32, 16, 32, 16, (0, 200, 0, 255))
        sheet.fill_rect(11 * 32, 32, 32, 16, (255, 0, 0, 255))
        sheet.fill_rect(0, 16, 32, 32, (0, 100, 200, 255))
        out = render_3d_image(
            _cells([" "] * 4 + ["["] + [" "] * 4), [], 3,
            [sheet] * 4, None, lambda ch: None,
            Camera(width=160, height=120, distance=5.0), style="extrude",
        )
        # 扉の板は出ていますが、床に下地の赤は出ません
        self.assertGreater(self._count(out.image, (0, 200, 0)), 20)
        self.assertEqual(self._count(out.image, (255, 0, 0)), 0)

    def test_door_floor_falls_back_to_ground_chip(self):
        # 床だけの隣がなければ、地面のチップ(0番)の絵になります
        sheet = RgbaImage(512, 96, fill=(0, 0, 0, 0))
        sheet.fill_rect(11 * 32, 0, 32, 16, (0, 0, 255, 255))
        sheet.fill_rect(11 * 32, 16, 32, 16, (0, 200, 0, 255))
        sheet.fill_rect(11 * 32, 32, 32, 16, (255, 0, 0, 255))
        sheet.fill_rect(7 * 32, 0, 32, 16, (128, 128, 128, 255))
        sheet.fill_rect(7 * 32, 16, 32, 32, (200, 200, 0, 255))
        sheet.fill_rect(0, 16, 32, 32, (0, 100, 200, 255))
        out = render_3d_image(
            _cells(["#", "#", "#", "#", "[", "#", "#", "#", "#"]), [], 3,
            [sheet] * 4, None, lambda ch: None,
            Camera(width=160, height=120, distance=6.0, elevation=60.0),
            style="extrude",
        )
        self.assertGreater(self._count(out.image, (0, 100, 200)), 0)
        self.assertEqual(self._count(out.image, (255, 0, 0)), 0)

    def test_rock_is_a_frustum(self):
        # 岩はすぼまった形で、箱とは違う絵になります
        sheet = RgbaImage(512, 96, fill=(0, 0, 0, 0))
        sheet.fill_rect(6 * 32, 12, 32, 4, (128, 128, 128, 255))
        sheet.fill_rect(6 * 32, 16, 32, 32, (128, 128, 128, 255))
        sheet.fill_rect(0, 16, 32, 32, (0, 100, 200, 255))

        def render(style):
            return render_3d_image(
                _cells([" "] * 4 + ["@"] + [" "] * 4), [], 3,
                [sheet] * 4, None, lambda ch: None,
                Camera(width=160, height=120, distance=5.0), style=style,
            )

        out = render("extrude")
        self.assertGreater(self._count(out.image, (120, 120, 120)), 20)
        self.assertGreater(self._count(out.image, (128, 128, 128)), 10)
        self.assertNotEqual(encode_png(out.image),
                            encode_png(render("boxes").image))


    def test_open_chest_has_a_real_opening(self):
        # 開いている箱は、前面に穴が開き、奥に暗い空洞が見えます
        sheet = RgbaImage(512, 96, fill=(0, 0, 0, 0))
        sheet.fill_rect(14 * 32, 0, 32, 48, (200, 160, 100, 255))
        sheet.fill_rect(14 * 32 + 6, 17, 21, 14, (100, 60, 30, 255))
        sheet.fill_rect(0, 16, 32, 32, (0, 100, 200, 255))
        out = render_3d_image(
            _cells([" "] * 4 + ["x"] + [" "] * 4), [], 3,
            [sheet] * 4, None, lambda ch: None,
            Camera(width=160, height=120, distance=5.0), style="extrude",
        )
        # 空洞の奥の壁の色(暗くした開口の色)が出ます
        cavity = (100 * 200 >> 8, 60 * 200 >> 8, 30 * 200 >> 8)
        self.assertGreater(self._count(out.image, cavity), 5)

    def test_open_chest_falls_back_without_opening_art(self):
        # 開口のある絵でなければ、普通の箱形になります
        sheet = RgbaImage(512, 96, fill=(0, 0, 0, 0))
        sheet.fill_rect(14 * 32, 0, 32, 48, (200, 160, 100, 255))
        sheet.fill_rect(0, 16, 32, 32, (0, 100, 200, 255))
        out = render_3d_image(
            _cells([" "] * 4 + ["x"] + [" "] * 4), [], 3,
            [sheet] * 4, None, lambda ch: None,
            Camera(width=160, height=120, distance=5.0), style="extrude",
        )
        cavity = (100 * 200 >> 8, 60 * 200 >> 8, 30 * 200 >> 8)
        self.assertEqual(self._count(out.image, cavity), 0)

    def test_opening_looks_right(self):
        sheet = RgbaImage(512, 96, fill=(0, 0, 0, 0))
        sheet.fill_rect(14 * 32, 0, 32, 48, (200, 160, 100, 255))
        sheet.fill_rect(14 * 32 + 6, 17, 21, 14, (100, 60, 30, 255))
        self.assertTrue(_opening_looks_right(sheet, (14 * 32, 0, 32, 48)))
        sheet.fill_rect(14 * 32 + 6, 17, 21, 14, (200, 160, 100, 255))
        self.assertFalse(_opening_looks_right(sheet, (14 * 32, 0, 32, 48)))
        empty = RgbaImage(512, 96, fill=(0, 0, 0, 0))
        self.assertFalse(_opening_looks_right(empty, (14 * 32, 0, 32, 48)))


@unittest.skipUnless(BUNDLED.exists(), "wphi の resources/phi がありません")
class TestRealAssets(unittest.TestCase):
    def test_real_assets_render(self):
        from neophi.assets import Assets

        assets = Assets([str(BUNDLED)])
        cells = _cells(["T", "_", "#", " ", ":", "o", "H"] * 7)
        chars = [Chara(x=3, y=3, dir="F", name="自分", gra="npc2", gigant="#"),
                 Chara(x=4, y=3, dir="B", name="犬", gra="t_dog", gigant="*")]
        start = time.monotonic()
        rendered = render_3d_image(
            cells, chars, 7, [assets.chip("")] * 4, assets.items(),
            lambda ch: assets.chara(ch.name, ch.gra, ch.default),
            Camera(width=320, height=240),
        )
        elapsed = time.monotonic() - start
        self.assertLess(elapsed, 10.0)
        self.assertEqual((rendered.image.width, rendered.image.height), (320, 240))
        data = rendered.image.pixels
        non_black = sum(
            1 for i in range(0, len(data), 4)
            if (data[i], data[i + 1], data[i + 2]) != (0, 0, 0)
        )
        self.assertGreater(non_black, 10000)
        self.assertEqual(len(rendered.labels), 1)
        self.assertEqual(rendered.labels[0].name, "犬")

    def test_real_assets_extrude_render(self):
        from neophi.assets import Assets

        assets = Assets([str(BUNDLED)])
        cells = _cells(["T", "_", "#", " ", ":", "o", "H"] * 7)
        chars = [Chara(x=3, y=3, dir="F", name="自分", gra="npc2", gigant="#"),
                 Chara(x=4, y=3, dir="B", name="犬", gra="t_dog", gigant="*")]
        start = time.monotonic()
        rendered = render_3d_image(
            cells, chars, 7, [assets.chip("")] * 4, assets.items(),
            lambda ch: assets.chara(ch.name, ch.gra, ch.default),
            Camera(width=320, height=240), style="extrude",
        )
        elapsed = time.monotonic() - start
        self.assertLess(elapsed, 10.0)
        data = rendered.image.pixels
        non_black = sum(
            1 for i in range(0, len(data), 4)
            if (data[i], data[i + 1], data[i + 2]) != (0, 0, 0)
        )
        self.assertGreater(non_black, 10000)


if __name__ == "__main__":
    unittest.main()
