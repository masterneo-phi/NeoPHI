import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from neophi.keys import key_action, list_key_action, move_command, move_input


class TestKeys(unittest.TestCase):
    def test_move_north_fix(self):
        self.assertEqual(move_command("8", "none", True), "go N")
        self.assertEqual(move_command("2", "none", True), "go S")
        self.assertEqual(move_command("up", "none", True), "go N")
        self.assertEqual(move_command("8", "ctrl", True), "go n")
        self.assertEqual(move_command("up", "shift", True), "go")

    def test_move_turn(self):
        self.assertEqual(move_command("8", "none", False), "go")
        self.assertEqual(move_command("2", "none", False), "go b")
        self.assertEqual(move_command("left", "shift", False), "turn l")
        self.assertEqual(move_command("5", "ctrl", False), "turn n")

    def test_move_input_full_key(self):
        # フルキー移動: I はテンキー5
        self.assertEqual(move_input("KeyI"), ("5", "none"))
        self.assertEqual(move_input("Digit8"), ("8", "none"))
        self.assertEqual(move_input("ArrowUp"), ("up", "none"))
        # Shift の 5 と 7 はマップの大きさを変えるので移動ではない
        self.assertIsNone(move_input("Digit5", shift=True))
        self.assertIsNone(move_input("Digit7", shift=True))
        # Alt は移動ではない
        self.assertIsNone(move_input("ArrowUp", alt=True))

    def test_key_action_basic(self):
        self.assertEqual(key_action("KeyZ").send, "get")
        self.assertEqual(key_action("KeyX").send, "put")
        self.assertEqual(key_action("KeyC").send, "use")
        self.assertEqual(key_action("Space").send, "hit")
        self.assertEqual(key_action("KeyT").send, "#ex-map style=turn")
        self.assertEqual(key_action("KeyT", shift=True).send, "#ex-map style=solid")
        # 移動キーは通常の操作ではない
        self.assertIsNone(key_action("ArrowUp"))
        self.assertIsNone(key_action("Numpad8"))

    def test_key_action_magic(self):
        action = key_action("KeyW", alt=True)
        self.assertEqual(action.send, "cast\nwizard eye")
        self.assertEqual(action.cancel_list, 1)
        self.assertEqual(action.system_magic, "reequip")
        self.assertIsNotNone(key_action("KeyB", alt=True).confirm)
        self.assertIsNotNone(key_action("KeyP").ask)

    def test_key_action_f_keys(self):
        self.assertEqual(key_action("F1").send, "cast\n1")
        self.assertEqual(key_action("F7").send, "cast\n7")

    def test_list_key_action(self):
        self.assertEqual(list_key_action("Digit3").list_no, 3)
        self.assertEqual(list_key_action("Numpad9").list_no, 9)
        self.assertEqual(list_key_action("Digit0").send, ".")
        self.assertEqual(list_key_action("Escape").send, ".")
        self.assertEqual(list_key_action("NumpadAdd").send, "-")
        # Minus はフルキー移動が off の時だけ「すべて」。on の時は
        # NumpadSubtract へ読み替えられ、リストの操作にはならない(wphi と同じ)
        self.assertEqual(
            list_key_action("Minus", full_key_move=False).send, "-"
        )
        self.assertIsNone(list_key_action("Minus"))
        self.assertTrue(list_key_action("Enter").list_ok)
        self.assertTrue(list_key_action("Space").list_toggle)
        self.assertEqual(list_key_action("ArrowUp").list_cursor, -1)
        self.assertEqual(list_key_action("ArrowDown").list_cursor, 1)
        # 文字のキーはリストの操作ではない(通常の操作へ回す)
        self.assertIsNone(list_key_action("KeyZ"))
        # 修飾キーのある時はリストの操作ではない
        self.assertIsNone(list_key_action("Digit3", shift=True))


if __name__ == "__main__":
    unittest.main()
