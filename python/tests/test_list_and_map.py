import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from neophi.list_state import (
    ListFlow,
    add_page,
    has_more,
    list_no,
    list_ok,
    more_no,
    move_list_cursor,
    new_list,
    receive_list,
)
from neophi.map_text import render_eagle_eye, render_map
from neophi.parser import Cell, Chara, EagleEyeEvent, MapEvent, Pos


class TestListState(unittest.TestCase):
    def test_new_list_offset_from_first_number(self):
        state = new_list(["[ 9] 続き", "[10] 次"])
        self.assertEqual(state.offset, 8)
        self.assertEqual(state.start, 8)

    def test_new_list_offset_ignores_tags(self):
        state = new_list(["[/*color=cyan*/ 1/*.*/] 剣"])
        self.assertEqual(state.offset, 0)

    def test_add_page_appends_continuation(self):
        first = new_list([f"[ {i}] 品物{i}" for i in range(1, 10)])
        second = add_page(first, [f"[ {i}] 品物{i}" for i in range(9, 18)])
        self.assertEqual(len(second.lines), 17)
        self.assertEqual(second.start, 0)
        self.assertEqual(second.offset, 8)
        self.assertEqual(second.cursor, 8)

    def test_add_page_new_list_when_not_continuation(self):
        first = new_list(["[ 1] a", "[ 2] b"])
        second = add_page(first, ["[ 1] x", "[ 2] y"])
        self.assertEqual(second.lines, ["[ 1] x", "[ 2] y"])

    def test_list_no(self):
        state = new_list(["[ 1] a", "[ 2] b", "[ 3] c"])
        self.assertEqual(list_no(state, 2), ("2", True))
        # 範囲外は取り消し
        self.assertEqual(list_no(state, 4), (".", True))
        # 9件なければ 9 は何もしない
        self.assertIsNone(list_no(state, 9))

    def test_list_no_more(self):
        state = new_list([f"[ {i}] a" for i in range(1, 10)])
        self.assertTrue(has_more(state))
        self.assertEqual(more_no(state), "9")
        self.assertEqual(list_no(state, 9), ("9", False))
        state.waiting = True
        self.assertIsNone(list_no(state, 9))

    def test_list_ok(self):
        state = new_list(["[ 1] a", "[ 2] b", "[ 3] c"])
        state.checked[0] = True
        state.checked[2] = True
        self.assertEqual(list_ok(state), "1 3")
        state.checked = [False, False, False]
        state.cursor = 1
        self.assertEqual(list_ok(state), "2")

    def test_move_list_cursor_toggle(self):
        state = new_list(["[ 1] a", "[ 2] b"])
        moved = move_list_cursor(state, toggle=True)
        self.assertTrue(moved.checked[0])
        self.assertEqual(moved.cursor, 1)
        moved = move_list_cursor(moved, cursor_delta=-1)
        self.assertEqual(moved.cursor, 0)

    def test_receive_list_flow(self):
        flow = ListFlow()
        self.assertIsNone(receive_list(flow, True, [], None))
        state = receive_list(flow, True, ["[ 1] a"], None)
        self.assertIsNotNone(state)
        self.assertEqual(receive_list(flow, False, None, state), "close")

    def test_receive_list_cancel(self):
        flow = ListFlow(cancel=1)
        self.assertIsNone(receive_list(flow, True, [], None))
        self.assertIsNone(receive_list(flow, True, ["[ 1] a"], None))
        self.assertEqual(flow.cancel, 0)


class TestMapText(unittest.TestCase):
    def test_render_map_center_arrow_and_chars(self):
        cells = [Cell(chip=ord(" "), attr=0)] * 49
        cells[0] = Cell(chip=ord("#"), attr=0)
        cells[1] = Cell(chip=ord(" "), attr=0x08)
        cells[2] = Cell(chip=ord(" "), attr=0x20)
        chars = [
            Chara(id=1, x=3, y=3, dir="B", name="自分", gra="g", status=0,
                  gigant="#", layer=0, default=0),
            Chara(id=2, x=4, y=3, dir="F", name="案内人", gra="g", status=0,
                  gigant="#", layer=1, default=0),
        ]
        lines = render_map(MapEvent(size=7, dir=0, cells=cells, chars=chars))
        self.assertIn("向き=N", lines[0])
        # 中心は向きの矢印、その右はキャラ
        self.assertEqual(lines[1 + 3][3], "^")
        self.assertEqual(lines[1 + 3][4], "@")
        self.assertEqual(lines[1][0], "#")
        self.assertEqual(lines[1][1], "!")
        self.assertEqual(lines[1][2], "2")

    def test_render_eagle_eye(self):
        event = EagleEyeEvent(
            width=3, height=2, self_pos=Pos(1, 1),
            cells=[Cell(chip=ord(" "), attr=0)] * 5 + [Cell(chip=ord(" "), attr=0x58)],
        )
        lines = render_eagle_eye(event)
        self.assertEqual(lines[2][1], "@")
        self.assertEqual(lines[2][2], "P")


if __name__ == "__main__":
    unittest.main()
