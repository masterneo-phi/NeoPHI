"""世界移動(#ch-srv)のテスト。偽の移動元・移動先サーバを使います。"""

import asyncio
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from neophi.parser import MessageEvent  # noqa: E402
from neophi.session import (  # noqa: E402
    TRANSFER_NO,
    TRANSFER_YES,
    PhiSession,
    SessionClosedEvent,
    TransferConfirmEvent,
    login_lines,
    transfer_target,
)


class FakeServer:
    """1接続を受ける偽サーバ。送られた行を記録し、決めた行を返します。"""

    def __init__(self) -> None:
        self.received: list[str] = []
        self.connections = 0
        self.to_send: asyncio.Queue[str] = asyncio.Queue()
        self._server: asyncio.AbstractServer | None = None
        self.port = 0

    async def start(self) -> None:
        self._server = await asyncio.start_server(
            self._handle, "127.0.0.1", 0
        )
        sock = self._server.sockets[0]
        self.port = sock.getsockname()[1]

    async def stop(self) -> None:
        if self._server is not None:
            self._server.close()
            await self._server.wait_closed()

    async def send(self, line: str) -> None:
        await self.to_send.put(line)

    async def _handle(
        self, reader: asyncio.StreamReader, writer: asyncio.StreamWriter
    ) -> None:
        self.connections += 1

        async def _send_loop() -> None:
            try:
                while True:
                    line = await self.to_send.get()
                    writer.write(line.encode("cp932") + b"\n")
                    await writer.drain()
            except (ConnectionError, asyncio.CancelledError):
                pass

        sender = asyncio.create_task(_send_loop())
        try:
            while True:
                raw = await reader.readline()
                if not raw:
                    break
                self.received.append(raw.decode("cp932", "replace").rstrip("\r\n"))
        except (ConnectionError, asyncio.CancelledError):
            pass
        finally:
            sender.cancel()
            await asyncio.gather(sender, return_exceptions=True)
            try:
                writer.close()
            except OSError:
                pass


async def wait_for(predicate, timeout: float = 5.0) -> bool:
    """条件が満たされるまで待つ。"""
    deadline = asyncio.get_running_loop().time() + timeout
    while asyncio.get_running_loop().time() < deadline:
        if predicate():
            return True
        await asyncio.sleep(0.01)
    return predicate()


class TestTransferTarget(unittest.TestCase):
    def test_valid(self):
        self.assertEqual(
            transfer_target("example.com:20017"), ("example.com", 20017)
        )
        self.assertEqual(transfer_target("127.0.0.1:09000"), ("127.0.0.1", 9000))

    def test_invalid(self):
        self.assertIsNone(transfer_target("example.com"))
        self.assertIsNone(transfer_target("example.com:abc"))
        self.assertIsNone(transfer_target("example.com:99999"))
        self.assertIsNone(transfer_target("example.com:-1"))
        self.assertIsNone(transfer_target(":20017"))


class TestWorldTransfer(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.src = FakeServer()
        self.dst = FakeServer()
        await self.src.start()
        await self.dst.start()
        self.session: PhiSession | None = None
        self.task: asyncio.Task | None = None

    async def asyncTearDown(self):
        if self.task is not None and not self.task.done():
            self.task.cancel()
            await asyncio.gather(self.task, return_exceptions=True)
        await self.src.stop()
        await self.dst.stop()

    def _start_session(self, **kwargs) -> PhiSession:
        self.session = PhiSession(
            "127.0.0.1", self.src.port, "TESTID", **kwargs
        )
        self.task = asyncio.create_task(self.session.run())
        return self.session

    async def _collect_until(self, predicate, timeout: float = 5.0):
        events = []
        deadline = asyncio.get_running_loop().time() + timeout
        while asyncio.get_running_loop().time() < deadline:
            try:
                event = await asyncio.wait_for(
                    self.session.events.get(), timeout=0.2
                )
            except TimeoutError:
                continue
            events.append(event)
            if predicate(event, events):
                return events
        return events

    async def _wait_login(self, server: FakeServer) -> None:
        ok = await wait_for(lambda: "#open TESTID" in server.received)
        self.assertTrue(ok, f"ログインが届きません: {server.received}")

    async def test_transfer_succeeds_same_host(self):
        """同じホストなら確認なしで移動し、#open を送らない。"""
        session = self._start_session()
        await self._wait_login(self.src)
        await self.src.send(
            f"#ch-srv 127.0.0.1 {self.dst.port}\nDM > after-ch-srv"
        )
        ok = await wait_for(lambda: "#reserve TESTID" in self.dst.received)
        self.assertTrue(ok, f"reserve が届きません: {self.dst.received}")
        await self.dst.send("#rsv-ok")
        ok = await wait_for(
            lambda: any(line.startswith("#trans ") for line in self.src.received)
        )
        self.assertTrue(ok, f"trans が届きません: {self.src.received}")
        self.assertIn(f"#trans 127.0.0.1 {self.dst.port}", self.src.received)
        await self.src.send("#trs-ok")
        ok = await wait_for(lambda: len(self.dst.received) >= 12)
        self.assertTrue(ok, f"移動先への送信が足りません: {self.dst.received}")
        self.assertEqual(
            self.dst.received,
            ["#reserve TESTID", "#ch-srv-ok"] + login_lines(None),
        )
        await self.dst.send("DM > moved-ok")
        events = await self._collect_until(
            lambda e, _: isinstance(e, MessageEvent)
            and "moved-ok" in e.text
        )
        self.assertTrue(
            any(isinstance(e, MessageEvent) and "moved-ok" in e.text for e in events),
            f"移動先の行が届きません: {events}",
        )
        # 確認は出ない(同じホスト)、#ch-srv の後の行は捨てる
        self.assertFalse(any(isinstance(e, TransferConfirmEvent) for e in events))
        self.assertFalse(any(
            isinstance(e, MessageEvent) and "after-ch-srv" in e.text for e in events
        ))
        self.assertEqual(session.host, "127.0.0.1")
        self.assertEqual(session.port, self.dst.port)

    async def test_transfer_confirm_no(self):
        """違うホストでは確認し、断れば #no-srv で留まる。"""
        session = self._start_session()
        await self._wait_login(self.src)
        await self.src.send(f"#ch-srv localhost {self.dst.port}")
        events = await self._collect_until(
            lambda e, _: isinstance(e, TransferConfirmEvent)
        )
        confirm = next(
            e for e in events if isinstance(e, TransferConfirmEvent)
        )
        self.assertEqual(confirm.host, "localhost")
        self.assertEqual(confirm.port, self.dst.port)
        # 確認の前には、移動先へ繋がない
        self.assertEqual(self.dst.connections, 0)
        await session.send(TRANSFER_NO)
        ok = await wait_for(lambda: "#no-srv" in self.src.received)
        self.assertTrue(ok, f"#no-srv が届きません: {self.src.received}")
        await self.src.send("DM > still-here")
        events = await self._collect_until(
            lambda e, _: isinstance(e, MessageEvent) and "still-here" in e.text
        )
        self.assertTrue(any(
            isinstance(e, MessageEvent) and "still-here" in e.text for e in events
        ))

    async def test_transfer_confirm_yes(self):
        """違うホストでも、認めれば移動する。"""
        session = self._start_session()
        await self._wait_login(self.src)
        await self.src.send(f"#ch-srv localhost {self.dst.port}")
        await self._collect_until(
            lambda e, _: isinstance(e, TransferConfirmEvent)
        )
        await session.send(TRANSFER_YES)
        ok = await wait_for(lambda: "#reserve TESTID" in self.dst.received)
        self.assertTrue(ok, f"reserve が届きません: {self.dst.received}")
        await self.dst.send("#rsv-ok")
        ok = await wait_for(
            lambda: any(line.startswith("#trans ") for line in self.src.received)
        )
        self.assertTrue(ok)
        await self.src.send("#trs-ok")
        ok = await wait_for(lambda: "#ch-srv-ok" in self.dst.received)
        self.assertTrue(ok)
        self.assertEqual(session.host, "localhost")

    async def test_transfer_rsv_no_stays(self):
        """#rsv-no なら #no-srv で留まり、後の行も処理する。"""
        self._start_session()
        await self._wait_login(self.src)
        await self.src.send(
            f"#ch-srv 127.0.0.1 {self.dst.port}\nDM > after-ch-srv"
        )
        ok = await wait_for(lambda: "#reserve TESTID" in self.dst.received)
        self.assertTrue(ok)
        await self.dst.send("#rsv-no")
        ok = await wait_for(lambda: "#no-srv" in self.src.received)
        self.assertTrue(ok, f"#no-srv が届きません: {self.src.received}")
        events = await self._collect_until(
            lambda e, _: isinstance(e, MessageEvent)
            and "after-ch-srv" in e.text
        )
        self.assertTrue(any(
            isinstance(e, MessageEvent) and "after-ch-srv" in e.text for e in events
        ))

    async def test_transfer_trs_no_stays(self):
        """#trs-no なら #ch-srv-no で留まる。"""
        self._start_session()
        await self._wait_login(self.src)
        await self.src.send(f"#ch-srv 127.0.0.1 {self.dst.port}")
        ok = await wait_for(lambda: "#reserve TESTID" in self.dst.received)
        self.assertTrue(ok)
        await self.dst.send("#rsv-ok")
        ok = await wait_for(
            lambda: any(line.startswith("#trans ") for line in self.src.received)
        )
        self.assertTrue(ok)
        await self.src.send("#trs-no")
        ok = await wait_for(lambda: "#ch-srv-no" in self.src.received)
        self.assertTrue(ok, f"#ch-srv-no が届きません: {self.src.received}")
        await self.src.send("DM > still-here")
        events = await self._collect_until(
            lambda e, _: isinstance(e, MessageEvent) and "still-here" in e.text
        )
        self.assertTrue(any(
            isinstance(e, MessageEvent) and "still-here" in e.text for e in events
        ))

    async def test_transfer_dst_unreachable(self):
        """移動先に繋がらなければ #no-srv で留まる。"""
        probe = await asyncio.start_server(lambda r, w: None, "127.0.0.1", 0)
        closed_port = probe.sockets[0].getsockname()[1]
        probe.close()
        await probe.wait_closed()
        self._start_session()
        await self._wait_login(self.src)
        await self.src.send(f"#ch-srv 127.0.0.1 {closed_port}")
        ok = await wait_for(lambda: "#no-srv" in self.src.received)
        self.assertTrue(ok, f"#no-srv が届きません: {self.src.received}")
        await self.src.send("DM > still-here")
        events = await self._collect_until(
            lambda e, _: isinstance(e, MessageEvent) and "still-here" in e.text
        )
        self.assertTrue(any(
            isinstance(e, MessageEvent) and "still-here" in e.text for e in events
        ))

    async def test_transfer_confirm_timeout(self):
        """確認に答えなければ、やめる扱いになる。"""
        self._start_session(transfer_timeout=0.2)
        await self._wait_login(self.src)
        await self.src.send(f"#ch-srv localhost {self.dst.port}")
        await self._collect_until(
            lambda e, _: isinstance(e, TransferConfirmEvent)
        )
        ok = await wait_for(lambda: "#no-srv" in self.src.received)
        self.assertTrue(ok, f"#no-srv が届きません: {self.src.received}")
        self.assertEqual(self.dst.connections, 0)

    async def test_transfer_discards_typed_lines(self):
        """移動の間に打った行は捨てる。"""
        session = self._start_session()
        await self._wait_login(self.src)
        await self.src.send(f"#ch-srv localhost {self.dst.port}")
        await self._collect_until(
            lambda e, _: isinstance(e, TransferConfirmEvent)
        )
        await session.send("hello-during-transfer")
        await session.send(TRANSFER_NO)
        ok = await wait_for(lambda: "#no-srv" in self.src.received)
        self.assertTrue(ok)
        self.assertNotIn("hello-during-transfer", self.src.received)

    async def test_transfer_disconnect_during_confirm(self):
        """確認の間に切断を頼めば、閉じる。"""
        session = self._start_session()
        await self._wait_login(self.src)
        await self.src.send(f"#ch-srv localhost {self.dst.port}")
        await self._collect_until(
            lambda e, _: isinstance(e, TransferConfirmEvent)
        )
        await session.disconnect(graceful=True)
        events = await self._collect_until(
            lambda e, _: isinstance(e, SessionClosedEvent)
        )
        self.assertTrue(any(isinstance(e, SessionClosedEvent) for e in events))
        self.assertIn("#x", self.src.received)


if __name__ == "__main__":
    unittest.main()
