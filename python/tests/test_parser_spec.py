import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from neophi.parser import (
    ConnectionEvent,
    ListEvent,
    MapEvent,
    MessageEvent,
    ModeEvent,
    Parser,
    WorldTransferEvent,
)


class TestParserSpec(unittest.TestCase):
    def _feed_user(self, p, number, name):
        p.feed(b"#user " + f"{number:04d} ".encode("ascii")
               + name.encode("cp932").ljust(31))

    def test_talk_with_noop_tag_prefix(self):
        # 実サーバは発言の行の頭に /**/ を付けます
        p = Parser()
        self._feed_user(p, 12, "Guest")
        events = p.feed("/**/Guest > こんにちは".encode("cp932"))
        self.assertEqual(len(events), 1)
        self.assertIsInstance(events[0], MessageEvent)
        self.assertEqual(events[0].channel, "talk")
        self.assertEqual(events[0].from_, "Guest")
        self.assertEqual(events[0].text, "/**/Guest > こんにちは")

    def test_noop_tag_prefix_unknown_name_is_log(self):
        # 名前が #user に無ければ、/**/ が付いてもログのままです
        p = Parser()
        self._feed_user(p, 12, "Guest")
        events = p.feed("/**/Human > Insane".encode("cp932"))
        self.assertEqual(len(events), 1)
        self.assertIsInstance(events[0], MessageEvent)
        self.assertEqual(events[0].channel, "log")
        self.assertIsNone(events[0].from_)

    def test_commands_inside_more_are_log(self):
        p = Parser()
        p.feed(b"#more")
        for line in [
            b"#ch-srv 192.0.2.1 9000",
            b"#x",
            b"[evil] > fake priv",
            b"#m57 M N 00:",
        ]:
            events = p.feed(line)
            self.assertEqual(len(events), 1)
            self.assertIsInstance(events[0], MessageEvent)
            self.assertEqual(events[0].channel, "log")
        events = p.feed(b"#end-more")
        self.assertEqual(events, [ModeEvent()])
        events = p.feed(b"#ch-srv 192.0.2.1 9000")
        self.assertEqual(len(events), 1)
        self.assertIsInstance(events[0], WorldTransferEvent)

    def test_end_list_closes_and_emits_mode(self):
        p = Parser()
        p.feed(b"#list")
        p.feed("アイテム".encode("cp932"))
        events = p.feed(b"#end-list")
        self.assertEqual(events, [ListEvent(active=True, lines=["アイテム"])])
        events = p.end_list()
        self.assertEqual(
            events, [ListEvent(active=False), ModeEvent()]
        )

    def test_close_commands(self):
        p = Parser()
        self.assertEqual(p.feed(b"#close"), [ConnectionEvent()])
        self.assertEqual(p.feed(b"#x"), [ConnectionEvent()])

    def test_hash_lines_are_not_commands(self):
        p = Parser()
        for line in [b"## not a command", b"# not a command", b"#"]:
            events = p.feed(line)
            self.assertEqual(len(events), 1)
            self.assertIsInstance(events[0], MessageEvent)
            self.assertEqual(events[0].channel, "log")

    def test_map_without_m_line_has_empty_cells(self):
        p = Parser()
        events = p.feed(b"#m57 .")
        self.assertEqual(len(events), 1)
        self.assertIsInstance(events[0], MapEvent)
        self.assertEqual(events[0].cells, [])
        self.assertEqual(events[0].size, 7)

    def test_user_list_and_clear(self):
        p = Parser()
        raw = b"#user " + b"0012 " + "花子".encode("cp932").ljust(31, b" ")
        events = p.feed(raw)
        self.assertEqual(len(events), 1)
        self.assertEqual(p.user_no("花子"), 12)
        p.clear_users()
        self.assertIsNone(p.user_no("花子"))

    def test_unknown_hash_lines_ignored(self):
        p = Parser()
        self.assertEqual(p.feed(b"#bgm something"), [])
        self.assertEqual(p.feed(b"#ex-map size=57"), [])


if __name__ == "__main__":
    unittest.main()
