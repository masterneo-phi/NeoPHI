import asyncio
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
sys.path.insert(0, str(ROOT / "tools"))

import mock_server
from neophi.combat_fx import parse_attack, parse_chant, parse_kill
from neophi.float_text import parse_floats
from neophi.parser import ListEvent, MapEvent, MessageEvent, ModeEvent
from neophi.session import (
    PhiSession,
    SessionClosedEvent,
    SessionErrorEvent,
    login_lines,
)
from neophi.tags import plain_text


class TestLoginLines(unittest.TestCase):
    def test_login_lines_order(self):
        lines = login_lines("MYID")
        self.assertEqual(lines[0], "#open MYID")
        self.assertEqual(lines[1], "#version-cli 05107100")
        self.assertEqual(lines[2], "#map-iv 2")
        self.assertEqual(lines[5], "#ex-map size=57")
        self.assertEqual(lines[6], "#ex-map style=solid")
        self.assertEqual(len(lines), 11)
        self.assertNotIn("\r", "".join(lines))
        self.assertNotIn("\n", "".join(lines))

    def test_login_lines_without_open(self):
        lines = login_lines(None)
        self.assertEqual(len(lines), 10)
        self.assertFalse(any(line.startswith("#open") for line in lines))


class TestSessionMock(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.server = mock_server.MockServer("127.0.0.1", 0)
        await self.server.start()
        self.host, self.port = self.server.address

    async def asyncTearDown(self):
        await self.server.stop()

    async def _collect_until(self, session, predicate, timeout=5.0):
        events = []
        deadline = asyncio.get_running_loop().time() + timeout
        while asyncio.get_running_loop().time() < deadline:
            try:
                event = await asyncio.wait_for(session.events.get(), timeout=0.5)
            except TimeoutError:
                continue
            events.append(event)
            if predicate(event, events):
                return events
        return events

    async def test_connect_login_and_lag(self):
        session = PhiSession(self.host, self.port, "TESTID")
        task = asyncio.create_task(session.run())
        try:
            events = await self._collect_until(
                session, lambda ev, evs: isinstance(ev, MapEvent)
            )
            self.assertTrue(any(isinstance(ev, MapEvent) for ev in events))
            # ログインの11行が届いている(#open の ID はモックが伏せる)
            expected = login_lines("TESTID")
            self.assertEqual(self.server.received[0], "#open <ID>")
            self.assertEqual(self.server.received[1:11], expected[1:])
            # #lag の返事が届いている
            await asyncio.sleep(0.3)
            self.assertTrue(self.server.lag_ok)
            self.assertIn("#end-lag", self.server.received)
        finally:
            await session.disconnect(graceful=True)
            await asyncio.wait_for(task, timeout=5.0)
        self.assertIn("#x", self.server.received)

    async def test_move_and_list(self):
        session = PhiSession(self.host, self.port, "TESTID")
        task = asyncio.create_task(session.run())
        try:
            await self._collect_until(
                session, lambda ev, evs: isinstance(ev, MapEvent)
            )
            await session.send("go N")
            events = await self._collect_until(
                session, lambda ev, evs: isinstance(ev, MapEvent)
            )
            self.assertTrue(any(isinstance(ev, MapEvent) for ev in events))
            self.assertIn("go N", self.server.received)

            await session.send("get")
            events = await self._collect_until(
                session,
                lambda ev, evs: isinstance(ev, ListEvent) and ev.lines,
            )
            list_events = [ev for ev in events if isinstance(ev, ListEvent)]
            self.assertTrue(list_events[-1].lines)
            await session.send("1")
            await session.close_list()
            events = await self._collect_until(
                session,
                lambda ev, evs: isinstance(ev, MessageEvent)
                and "拾いました" in plain_text(ev.text),
            )
            self.assertTrue(
                any(
                    isinstance(ev, MessageEvent)
                    and "拾いました" in plain_text(ev.text)
                    for ev in events
                )
            )
        finally:
            await session.disconnect(graceful=True)
            await asyncio.wait_for(task, timeout=5.0)

    async def test_put_and_use_answers(self):
        session = PhiSession(self.host, self.port, "TESTID")
        task = asyncio.create_task(session.run())
        try:
            await self._collect_until(
                session, lambda ev, evs: isinstance(ev, MapEvent)
            )
            for command, verb in (("put", "置きました"), ("use", "使いました")):
                await session.send(command)
                await self._collect_until(
                    session,
                    lambda ev, evs: isinstance(ev, ListEvent) and ev.lines,
                )
                await session.send("1")
                await session.close_list()
                events = await self._collect_until(
                    session,
                    lambda ev, evs: isinstance(ev, MessageEvent)
                    and verb in plain_text(ev.text),
                )
                self.assertTrue(
                    any(
                        isinstance(ev, MessageEvent)
                        and verb in plain_text(ev.text)
                        for ev in events
                    )
                )
        finally:
            await session.disconnect(graceful=True)
            await asyncio.wait_for(task, timeout=5.0)

    async def test_board_body_commands_not_executed(self):
        session = PhiSession(self.host, self.port, "TESTID")
        task = asyncio.create_task(session.run())
        try:
            await self._collect_until(
                session, lambda ev, evs: isinstance(ev, MapEvent)
            )
            await session.send("read")
            events = await self._collect_until(
                session,
                lambda ev, evs: isinstance(ev, ModeEvent) and not ev.more,
                timeout=5.0,
            )
            texts = [
                ev.text for ev in events if isinstance(ev, MessageEvent)
            ]
            self.assertIn("#ch-srv 192.0.2.1 9000", texts)
            # 看板の #x で切れていない
            self.assertFalse(
                any(isinstance(ev, SessionClosedEvent) for ev in events)
            )
            self.assertFalse(task.done())
        finally:
            await session.disconnect(graceful=True)
            await asyncio.wait_for(task, timeout=5.0)

    async def test_keepalive_and_warning(self):
        session = PhiSession(
            self.host, self.port, "TESTID",
            keepalive_after=0.2, warn_after=0.4,
        )
        task = asyncio.create_task(session.run())
        try:
            await self._collect_until(
                session, lambda ev, evs: isinstance(ev, MapEvent)
            )
            # モックは #code-sjis に #code-sjis-ok を返すので、受信があって
            # 警告は出ない。まず keepalive が送られる事を確かめる
            await asyncio.sleep(0.5)
            self.assertIn("#code-sjis", self.server.received)
        finally:
            await session.disconnect(graceful=True)
            await asyncio.wait_for(task, timeout=5.0)

    async def test_system_magic_auto_unequip(self):
        session = PhiSession(self.host, self.port, "TESTID")
        task = asyncio.create_task(session.run())
        try:
            await self._collect_until(
                session, lambda ev, evs: isinstance(ev, MapEvent)
            )
            await session.send_system_magic("cast\nwizard eye", reequip=False)
            events = await self._collect_until(
                session,
                lambda ev, evs: isinstance(ev, MessageEvent)
                and "唱えた" in plain_text(ev.text),
            )
            self.assertTrue(
                any(
                    isinstance(ev, MessageEvent)
                    and "唱えた" in plain_text(ev.text)
                    for ev in events
                )
            )
            # unequip → 1 → cast → wizard eye の順に送られている
            received = self.server.received
            order = [
                received.index("unequip"),
                received.index("1"),
                received.index("cast"),
                received.index("wizard eye"),
            ]
            self.assertEqual(order, sorted(order))
            # 装備のリストと「外す装備を選択して下さい」は画面に出ない
            self.assertFalse(
                any(
                    isinstance(ev, ListEvent)
                    and any("ロングソード" in line for line in (ev.lines or []))
                    for ev in events
                )
            )
            self.assertFalse(
                any(
                    isinstance(ev, MessageEvent)
                    and "外す装備を選択して下さい" in plain_text(ev.text)
                    for ev in events
                )
            )
        finally:
            await session.disconnect(graceful=True)
            await asyncio.wait_for(task, timeout=5.0)

    async def test_system_magic_without_auto_unequip(self):
        session = PhiSession(
            self.host, self.port, "TESTID", auto_unequip=False
        )
        task = asyncio.create_task(session.run())
        try:
            await self._collect_until(
                session, lambda ev, evs: isinstance(ev, MapEvent)
            )
            await session.send_system_magic("cast\nwizard eye", reequip=False)
            await self._collect_until(
                session,
                lambda ev, evs: isinstance(ev, MessageEvent)
                and "唱えた" in plain_text(ev.text),
            )
            self.assertNotIn("unequip", self.server.received)
            self.assertIn("cast", self.server.received)
            self.assertIn("wizard eye", self.server.received)
        finally:
            await session.disconnect(graceful=True)
            await asyncio.wait_for(task, timeout=5.0)

    async def _cast_spell(self, session, answer):
        await session.send("cast")
        await self._collect_until(
            session,
            lambda ev, evs: isinstance(ev, MessageEvent)
            and "魔法を選んで下さい" in plain_text(ev.text),
        )
        await session.send(answer)

    async def test_hit_emits_combat_lines(self):
        session = PhiSession(self.host, self.port, "TESTID")
        task = asyncio.create_task(session.run())
        try:
            await self._collect_until(
                session, lambda ev, evs: isinstance(ev, MapEvent)
            )
            await session.send("hit")
            events = await self._collect_until(
                session,
                lambda ev, evs: isinstance(ev, MessageEvent)
                and "攻撃した" in plain_text(ev.text),
            )
            texts = [
                plain_text(ev.text)
                for ev in events
                if isinstance(ev, MessageEvent)
            ]
            attack = next(t for t in texts if "攻撃した" in t)
            self.assertIn("モック猫", attack)
            # 浮き数字と斬撃のもとになる行であること
            self.assertTrue(parse_floats(attack))
            self.assertIsNotNone(parse_attack(attack))
            # 3回目の hit ではモック猫が反撃する
            await session.send("hit")
            await session.send("hit")
            events = await self._collect_until(
                session,
                lambda ev, evs: isinstance(ev, MessageEvent)
                and "Fang" in plain_text(ev.text),
            )
            self.assertTrue(
                any(
                    "Fang" in plain_text(ev.text)
                    for ev in events
                    if isinstance(ev, MessageEvent)
                )
            )
        finally:
            await session.disconnect(graceful=True)
            await asyncio.wait_for(task, timeout=5.0)

    async def test_speech_echoes_as_talk(self):
        session = PhiSession(self.host, self.port, "TESTID")
        task = asyncio.create_task(session.run())
        try:
            await self._collect_until(
                session, lambda ev, evs: isinstance(ev, MapEvent)
            )
            await session.send("こんにちは")
            events = await self._collect_until(
                session,
                lambda ev, evs: isinstance(ev, MessageEvent)
                and ev.channel == "talk",
            )
            talks = [
                ev for ev in events
                if isinstance(ev, MessageEvent) and ev.channel == "talk"
            ]
            self.assertTrue(talks)
            self.assertEqual(talks[-1].from_, "モック太郎")
            self.assertIn("こんにちは", plain_text(talks[-1].text))
            # コマンドの言葉は発言にならない
            await session.send("sort")
            events = await self._collect_until(
                session,
                lambda ev, evs: isinstance(ev, MessageEvent)
                and "受けました" in plain_text(ev.text),
            )
            self.assertTrue(
                any(
                    "受けました" in plain_text(ev.text)
                    for ev in events
                    if isinstance(ev, MessageEvent)
                )
            )
        finally:
            await session.disconnect(graceful=True)
            await asyncio.wait_for(task, timeout=5.0)

    async def test_cast_harm_emits_chant_and_magic_attack(self):
        session = PhiSession(self.host, self.port, "TESTID")
        task = asyncio.create_task(session.run())
        try:
            await self._collect_until(
                session, lambda ev, evs: isinstance(ev, MapEvent)
            )
            await self._cast_spell(session, "harm")
            events = await self._collect_until(
                session,
                lambda ev, evs: isinstance(ev, MessageEvent)
                and "攻撃した" in plain_text(ev.text),
            )
            texts = [
                plain_text(ev.text)
                for ev in events
                if isinstance(ev, MessageEvent)
            ]
            chant = next(t for t in texts if "唱えている" in t)
            self.assertEqual(parse_chant(chant), "モック太郎")
            attack = next(t for t in texts if "攻撃した" in t)
            combat = parse_attack(attack)
            self.assertEqual((combat.attacker, combat.target), ("モック太郎", "モック猫"))
            self.assertEqual(combat.weapon, "Harm")
            self.assertTrue(parse_floats(attack))
        finally:
            await session.disconnect(graceful=True)
            await asyncio.wait_for(task, timeout=5.0)

    async def test_cast_cure_and_mana_emit_heal_lines(self):
        session = PhiSession(self.host, self.port, "TESTID")
        task = asyncio.create_task(session.run())
        try:
            await self._collect_until(
                session, lambda ev, evs: isinstance(ev, MapEvent)
            )
            await self._cast_spell(session, "cure")
            events = await self._collect_until(
                session,
                lambda ev, evs: isinstance(ev, MessageEvent)
                and "回復した" in plain_text(ev.text),
            )
            texts = [
                plain_text(ev.text)
                for ev in events
                if isinstance(ev, MessageEvent)
            ]
            heal = next(t for t in texts if "回復した" in t)
            self.assertTrue(
                any(f.kind == "heal" for f in parse_floats(heal))
            )
            await self._cast_spell(session, "mana")
            events = await self._collect_until(
                session,
                lambda ev, evs: isinstance(ev, MessageEvent)
                and "回復した" in plain_text(ev.text),
            )
            texts = [
                plain_text(ev.text)
                for ev in events
                if isinstance(ev, MessageEvent)
            ]
            mana = next(t for t in texts if "回復した" in t)
            self.assertTrue(any(f.kind == "mp" for f in parse_floats(mana)))
        finally:
            await session.disconnect(graceful=True)
            await asyncio.wait_for(task, timeout=5.0)

    async def test_cast_accepts_spell_numbers(self):
        session = PhiSession(self.host, self.port, "TESTID")
        task = asyncio.create_task(session.run())
        try:
            await self._collect_until(
                session, lambda ev, evs: isinstance(ev, MapEvent)
            )
            await self._cast_spell(session, "3")
            events = await self._collect_until(
                session,
                lambda ev, evs: isinstance(ev, MessageEvent)
                and "攻撃した" in plain_text(ev.text),
            )
            self.assertTrue(
                any(
                    "Harm" in plain_text(ev.text)
                    for ev in events
                    if isinstance(ev, MessageEvent)
                )
            )
        finally:
            await session.disconnect(graceful=True)
            await asyncio.wait_for(task, timeout=5.0)

    async def test_repeated_hits_kill_cat_and_deal_mp_damage(self):
        session = PhiSession(self.host, self.port, "TESTID")
        task = asyncio.create_task(session.run())
        try:
            await self._collect_until(
                session, lambda ev, evs: isinstance(ev, MapEvent)
            )
            texts = []
            for _ in range(10):
                await session.send("hit")
                events = await self._collect_until(
                    session,
                    lambda ev, evs: isinstance(ev, MessageEvent)
                    and "攻撃した" in plain_text(ev.text),
                )
                texts.extend(
                    plain_text(ev.text)
                    for ev in events
                    if isinstance(ev, MessageEvent)
                )
            # 最後の hit の後続の行を拾うため、地図を1回もらう
            await session.send("look")
            events = await self._collect_until(
                session, lambda ev, evs: isinstance(ev, MapEvent)
            )
            texts.extend(
                plain_text(ev.text)
                for ev in events
                if isinstance(ev, MessageEvent)
            )
            self.assertTrue(any(parse_kill(t) == "モック猫" for t in texts))
            self.assertTrue(any("[4 mp]" in t for t in texts))
        finally:
            await session.disconnect(graceful=True)
            await asyncio.wait_for(task, timeout=5.0)

    async def test_kill_sends_map_without_cat_then_cat_returns(self):
        session = PhiSession(self.host, self.port, "TESTID")
        task = asyncio.create_task(session.run())
        try:
            await self._collect_until(
                session, lambda ev, evs: isinstance(ev, MapEvent)
            )
            for _ in range(10):
                await session.send("hit")
                await self._collect_until(
                    session,
                    lambda ev, evs: isinstance(ev, MessageEvent)
                    and "攻撃した" in plain_text(ev.text),
                )
            # 倒れた直後の地図には猫がいない
            events = await self._collect_until(
                session, lambda ev, evs: isinstance(ev, MapEvent)
            )
            maps = [ev for ev in events if isinstance(ev, MapEvent)]
            self.assertTrue(maps)
            self.assertFalse(
                any(c.name == "モック猫" for c in maps[-1].chars)
            )
            # 次の地図では猫が戻る
            await session.send("look")
            events = await self._collect_until(
                session, lambda ev, evs: isinstance(ev, MapEvent)
            )
            maps = [ev for ev in events if isinstance(ev, MapEvent)]
            self.assertTrue(
                any(c.name == "モック猫" for c in maps[-1].chars)
            )
        finally:
            await session.disconnect(graceful=True)
            await asyncio.wait_for(task, timeout=5.0)

    async def test_cat_revives_on_next_hit(self):
        session = PhiSession(self.host, self.port, "TESTID")
        task = asyncio.create_task(session.run())
        try:
            await self._collect_until(
                session, lambda ev, evs: isinstance(ev, MapEvent)
            )
            for _ in range(10):
                await session.send("hit")
                await self._collect_until(
                    session,
                    lambda ev, evs: isinstance(ev, MessageEvent)
                    and "攻撃した" in plain_text(ev.text),
                )
            # 倒れた直後の地図には猫がいない
            events = await self._collect_until(
                session, lambda ev, evs: isinstance(ev, MapEvent)
            )
            maps = [ev for ev in events if isinstance(ev, MapEvent)]
            self.assertFalse(
                any(c.name == "モック猫" for c in maps[-1].chars)
            )
            # 次の hit では生き返ってから攻撃の行が来る
            await session.send("hit")
            events = await self._collect_until(
                session,
                lambda ev, evs: isinstance(ev, MessageEvent)
                and "攻撃した" in plain_text(ev.text),
            )
            texts = [
                plain_text(ev.text)
                for ev in events
                if isinstance(ev, MessageEvent)
            ]
            self.assertTrue(any("生き返った" in t for t in texts))
            maps = [ev for ev in events if isinstance(ev, MapEvent)]
            self.assertTrue(maps)
            self.assertTrue(
                any(c.name == "モック猫" for c in maps[-1].chars)
            )
            attack = next(t for t in texts if "攻撃した" in t)
            self.assertTrue(parse_floats(attack))
        finally:
            await session.disconnect(graceful=True)
            await asyncio.wait_for(task, timeout=5.0)

    async def test_guide_replies_to_third_speech(self):
        session = PhiSession(self.host, self.port, "TESTID")
        task = asyncio.create_task(session.run())
        try:
            await self._collect_until(
                session, lambda ev, evs: isinstance(ev, MapEvent)
            )
            await session.send("あ")
            await session.send("い")
            await session.send("う")
            events = await self._collect_until(
                session,
                lambda ev, evs: isinstance(ev, MessageEvent)
                and ev.channel == "talk"
                and ev.from_ == "案内人",
            )
            self.assertTrue(
                any(
                    isinstance(ev, MessageEvent)
                    and ev.channel == "talk"
                    and ev.from_ == "案内人"
                    for ev in events
                )
            )
        finally:
            await session.disconnect(graceful=True)
            await asyncio.wait_for(task, timeout=5.0)

    async def test_priv_trigger_sends_guide_priv(self):
        session = PhiSession(self.host, self.port, "TESTID")
        task = asyncio.create_task(session.run())
        try:
            await self._collect_until(
                session, lambda ev, evs: isinstance(ev, MapEvent)
            )
            await session.send("priv")
            events = await self._collect_until(
                session,
                lambda ev, evs: isinstance(ev, MessageEvent)
                and ev.channel == "priv",
            )
            privs = [
                ev for ev in events
                if isinstance(ev, MessageEvent) and ev.channel == "priv"
            ]
            self.assertTrue(privs)
            self.assertEqual(privs[-1].from_, "案内人")
            self.assertIn("ひそひそ", plain_text(privs[-1].text))
        finally:
            await session.disconnect(graceful=True)
            await asyncio.wait_for(task, timeout=5.0)

    async def test_send_rejects_newline(self):
        session = PhiSession(self.host, self.port, "TESTID")
        with self.assertRaises(ValueError):
            await session.send("a\nb")
        with self.assertRaises(ValueError):
            await session.send("a\rb")


# 回転マップの規則は実サーバ(127.0.0.1:20017、guest)で実測して確認した:
# 地形は3方向(N/E/S)とも式どおり(不一致0)、自キャラは turn で (3,4)・
# 向きコードは常時 B、他キャラの向きコードも BRFL の回転どおりだった。
_TURN_PX = (0, 1, 0, -1)
_TURN_PY = (-1, 0, 1, 0)
_TURN_RDC = "BRFL"


def _expected_cells(pos, cam, turn):
    """モックの地形関数から、style とカメラ方向に対する画面の49マスを
    実サーバの規則で組み立てる。"""
    cells = []
    for wy in range(7):
        for wx in range(7):
            if turn:
                vx, vy = wx - 3, 4 - wy
                dx = _TURN_PX[cam] * vy - _TURN_PY[cam] * vx
                dy = _TURN_PY[cam] * vy + _TURN_PX[cam] * vx
            else:
                dx, dy = wx - 3, wy - 3
            cells.append(mock_server._terrain(pos[0] + dx, pos[1] + dy))
    return cells


def _char_tuple(event, name):
    char = next(c for c in event.chars if c.name == name)
    return char.x, char.y, char.dir


class TestMockTurnMap(unittest.IsolatedAsyncioTestCase):
    """モックの回転マップ(style=turn)。実サーバで実測した規則に合わせる。"""

    async def asyncSetUp(self):
        self.server = mock_server.MockServer("127.0.0.1", 0)
        await self.server.start()
        self.host, self.port = self.server.address

    async def asyncTearDown(self):
        await self.server.stop()

    async def _collect_until(self, session, predicate, timeout=5.0):
        events = []
        deadline = asyncio.get_running_loop().time() + timeout
        while asyncio.get_running_loop().time() < deadline:
            try:
                event = await asyncio.wait_for(session.events.get(), timeout=0.5)
            except TimeoutError:
                continue
            events.append(event)
            if predicate(event, events):
                return events
        return events

    async def _next_map(self, session):
        events = await self._collect_until(
            session, lambda ev, evs: isinstance(ev, MapEvent)
        )
        maps = [ev for ev in events if isinstance(ev, MapEvent)]
        self.assertTrue(maps)
        return maps[-1]

    async def test_turn_rotation_all_directions(self):
        session = PhiSession(self.host, self.port, "TESTID")
        task = asyncio.create_task(session.run())
        try:
            base = await self._next_map(session)
            pos = (base.pos.x, base.pos.y)
            # solid の従来どおりの姿(回帰防止)
            self.assertEqual(base.dir, 0)
            self.assertEqual(_char_tuple(base, "モック太郎"), (3, 3, "B"))
            self.assertEqual(_char_tuple(base, "案内人"), (4, 3, "L"))
            self.assertEqual(_char_tuple(base, "モック猫"), (3, 2, "F"))
            self.assertEqual(
                [(c.chip, c.attr) for c in base.cells],
                _expected_cells(pos, 0, False),
            )

            await session.send("#ex-map style=turn")
            # 向きごとの (自キャラ, 案内人, モック猫) の画面座標と向き
            # コード。実サーバの規則から手で計算した値。
            expected_chars = {
                0: ((3, 4, "B"), (4, 4, "L"), (3, 3, "F")),
                1: ((3, 4, "B"), (3, 3, "F"), (2, 4, "R")),
                2: ((3, 4, "B"), (2, 4, "R"), (3, 5, "B")),
                3: ((3, 4, "B"), (3, 5, "B"), (4, 4, "L")),
            }
            for cam in range(4):
                if cam:
                    await session.send("turn r")
                event = await self._next_map(session)
                self.assertEqual(event.style, "turn")
                self.assertEqual(event.dir, cam * 2)
                self.assertEqual(
                    [(c.chip, c.attr) for c in event.cells],
                    _expected_cells(pos, cam, True),
                )
                me, guide, cat = expected_chars[cam]
                self.assertEqual(_char_tuple(event, "モック太郎"), me)
                self.assertEqual(_char_tuple(event, "案内人"), guide)
                self.assertEqual(_char_tuple(event, "モック猫"), cat)

            # solid に戻すと最初の地図と一致する
            await session.send("#ex-map style=solid")
            event = await self._next_map(session)
            self.assertEqual(event.style, "solid")
            self.assertEqual(_char_tuple(event, "モック太郎"), (3, 3, "B"))
            self.assertEqual(
                [(c.chip, c.attr) for c in event.cells],
                [(c.chip, c.attr) for c in base.cells],
            )
        finally:
            await session.disconnect(graceful=True)
            await asyncio.wait_for(task, timeout=5.0)

    async def test_login_with_turn_style(self):
        # ログインの行に style=turn を入れたら、最初の地図から回転する
        # (実サーバもログイン時の style を最初の地図に反映する)。
        # PhiSession は style=solid 固定なので raw でつなぐ。
        reader, writer = await asyncio.open_connection(self.host, self.port)
        try:
            lines = login_lines("TESTID")
            lines[6] = "#ex-map style=turn"
            for line in lines:
                writer.write(line.encode("cp932") + b"\n")
            await writer.drain()
            raw_lines = []
            deadline = asyncio.get_running_loop().time() + 5.0
            while asyncio.get_running_loop().time() < deadline:
                raw = await asyncio.wait_for(reader.readline(), timeout=5.0)
                if not raw:
                    break
                raw_lines.append(raw.rstrip(b"\r\n"))
                if raw_lines[-1] == b"#m57 .":
                    break
            m_line = next(l for l in raw_lines if l.startswith(b"#m57 M "))
            self.assertEqual(chr(m_line[7]), "N")
            cells = [
                (m_line[18 + i * 2], m_line[19 + i * 2]) for i in range(49)
            ]
            pos_line = next(l for l in raw_lines if l.startswith(b"#ex-pos "))
            _, px, py = pos_line.decode("ascii").split()
            self.assertEqual(
                cells, _expected_cells((int(px), int(py)), 0, True)
            )

            def parse_body(body):
                return (
                    int(body[6:7]), int(body[8:9]),
                    body[10:11].decode("ascii"),
                    body[12:43].decode("cp932").strip(),
                )

            chars = {}
            for raw in raw_lines:
                if raw.startswith(b"#m57 O "):
                    x, y, d, name = parse_body(raw[7:74])
                    chars[name] = (x, y, d)
                elif raw.startswith(b"#m57 W "):
                    for start in (7, 75):
                        x, y, d, name = parse_body(raw[start:start + 67])
                        chars[name] = (x, y, d)
            self.assertEqual(chars["モック太郎"], (3, 4, "B"))
            self.assertEqual(chars["案内人"], (4, 4, "L"))
            self.assertEqual(chars["モック猫"], (3, 3, "F"))
        finally:
            writer.close()
            await writer.wait_closed()

    async def test_invalid_style_is_rejected(self):
        session = PhiSession(self.host, self.port, "TESTID")
        task = asyncio.create_task(session.run())
        try:
            await self._next_map(session)
            await session.send("#ex-map style=turn")
            await self._next_map(session)
            await session.send("#ex-map style=bogus")
            # 実サーバは style=no と返すだけで地図は送らない
            events = []
            try:
                while True:
                    ev = await asyncio.wait_for(
                        session.events.get(), timeout=0.7
                    )
                    events.append(ev)
            except TimeoutError:
                pass
            self.assertFalse(
                any(isinstance(ev, MapEvent) for ev in events)
            )
            self.assertEqual(self.server._map_style, "turn")
            # 状態は turn のままなので、次の地図も回転している
            await session.send("#map")
            event = await self._next_map(session)
            self.assertEqual(_char_tuple(event, "モック太郎"), (3, 4, "B"))
        finally:
            await session.disconnect(graceful=True)
            await asyncio.wait_for(task, timeout=5.0)

    async def test_effects_still_work_in_turn(self):
        session = PhiSession(self.host, self.port, "TESTID")
        task = asyncio.create_task(session.run())
        try:
            await self._next_map(session)
            await session.send("#ex-map style=turn")
            await self._next_map(session)

            await session.send("hit")
            events = await self._collect_until(
                session,
                lambda ev, evs: isinstance(ev, MessageEvent)
                and "攻撃した" in plain_text(ev.text),
            )
            attack = next(
                plain_text(ev.text)
                for ev in events
                if isinstance(ev, MessageEvent) and "攻撃した" in plain_text(ev.text)
            )
            self.assertTrue(parse_floats(attack))
            self.assertIsNotNone(parse_attack(attack))

            await session.send("cast")
            await self._collect_until(
                session,
                lambda ev, evs: isinstance(ev, ListEvent) and ev.lines,
            )
            await session.send("3")
            await session.close_list()
            events = await self._collect_until(
                session,
                lambda ev, evs: isinstance(ev, MessageEvent)
                and "Harm" in plain_text(ev.text),
            )
            harm = next(
                plain_text(ev.text)
                for ev in events
                if isinstance(ev, MessageEvent) and "Harm" in plain_text(ev.text)
            )
            self.assertTrue(parse_floats(harm))
            self.assertIsNotNone(parse_attack(harm))

            await session.send("priv")
            events = await self._collect_until(
                session,
                lambda ev, evs: isinstance(ev, MessageEvent)
                and ev.channel == "priv",
            )
            privs = [
                ev for ev in events
                if isinstance(ev, MessageEvent) and ev.channel == "priv"
            ]
            self.assertTrue(privs)
            self.assertEqual(privs[-1].from_, "案内人")
        finally:
            await session.disconnect(graceful=True)
            await asyncio.wait_for(task, timeout=5.0)


if __name__ == "__main__":
    unittest.main()
