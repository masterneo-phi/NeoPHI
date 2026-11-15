"""1キャラ分のレガシーサーバへの接続。仕様書 §1・§2。

受信行は :class:`neophi.parser.Parser` で解析してイベントにし、``#lag``
などの自動応答はここで返す。送信も受信も1つのタスクが持つ。wphi の
``src-tauri/src/session.rs`` の ``run`` に対応する。

世界移動(``#ch-srv``、仕様書 §8.4)も行う。今と違うホストへ移る時は、
``#reserve`` でキャラ ID を送る前に :class:`TransferConfirmEvent` を UI へ
出し、利用者の答え(``#wphi-transfer yes`` / ``no``)を待つ。移動の手順は
wphi の ``src-tauri/src/session.rs`` の ``transfer`` と同じ。
"""

from __future__ import annotations

import asyncio
import socket
import sys
import time
from collections import deque
from dataclasses import dataclass
from pathlib import Path

from .auto_unequip import CAST_PREFIX, AutoUnequip
from .codec import decode, encode
from .line_buffer import LineBuffer
from .parser import Event, InternalEvent, MessageEvent, Parser, WorldTransferEvent
from .tags import strip_tags

__all__ = [
    "CONNECT_TIMEOUT",
    "KEEPALIVE_AFTER",
    "TRANSFER_NO",
    "TRANSFER_TIMEOUT",
    "TRANSFER_YES",
    "PhiSession",
    "SessionClosedEvent",
    "SessionErrorEvent",
    "TransferConfirmEvent",
    "WARN_AFTER",
    "WRITE_TIMEOUT",
    "login_lines",
    "transfer_target",
]

CONNECT_TIMEOUT = 10.0
WRITE_TIMEOUT = 30.0
#: 無受信がこの時間続いたら ``#code-sjis`` を送る
KEEPALIVE_AFTER = 120.0
#: 無受信がこの時間続いたら警告を出す
WARN_AFTER = 180.0
#: 世界移動の確認と各待ちの期限
TRANSFER_TIMEOUT = 300.0
#: 世界移動の確認の答え。UI が送る行
TRANSFER_YES = "#wphi-transfer yes"
TRANSFER_NO = "#wphi-transfer no"


@dataclass
class SessionErrorEvent:
    """接続できない、切れた、応答が無いなど。"""

    message: str


@dataclass
class SessionClosedEvent:
    """接続が閉じた。"""

    pass


@dataclass
class TransferConfirmEvent:
    """違うホストへの世界移動の確認。UI が利用者に確かめて答える。"""

    host: str
    port: int


@dataclass
class _CloseList:
    pass


@dataclass
class _Disconnect:
    graceful: bool = True


def login_lines(char_id: str | None) -> list[str]:
    """Philly のログイン時の送信。値は Philly の既定値。

    世界移動の後は ``#open`` を送らない(移動先へは ``#reserve`` で ID を
    渡してある)ので、その時は ``char_id=None`` で呼ぶ。
    """
    lines: list[str] = []
    if char_id is not None:
        lines.append(f"#open {char_id}")
    lines.extend(
        [
            "#version-cli 05107100",
            "#map-iv 2",
            "#status-iv 2",
            "#ex-switch eagleeye=form",
            "#ex-map size=57",
            "#ex-map style=solid",
            "#ex-switch ex-move-recv=true",
            "#ex-switch ex-list-mode-end=true",
            "#ex-switch ex-disp-magic=false",
            "#ex-switch ex-abspos=true",
        ]
    )
    return lines


def transfer_target(server: str) -> tuple[str, int] | None:
    """``#ch-srv`` の移動先。ポートが読めない・範囲外なら None。"""
    host, sep, port_text = server.rpartition(":")
    if not sep or not host:
        return None
    try:
        port = int(port_text, 10)
    except ValueError:
        return None
    if port < 0 or port > 65535:
        return None
    return host, port


def _system(text: str) -> MessageEvent:
    """クライアント内の知らせ。ログに混ぜて出す。"""
    return MessageEvent(channel="system", text=text)


async def _wait_dst_line(
    reader: asyncio.StreamReader,
    ok: bytes,
    ng: tuple[bytes, ...],
    deadline: float,
) -> bool:
    """移動先から ``ok`` の行を待つ。``ng`` の行・切断・期限切れなら False。

    それ以外の行は捨てる。
    """
    loop = asyncio.get_running_loop()
    while True:
        remaining = deadline - loop.time()
        if remaining <= 0:
            return False
        try:
            raw = await asyncio.wait_for(reader.readline(), timeout=remaining)
        except (TimeoutError, OSError, ValueError):
            return False
        if not raw:
            return False
        if raw.endswith(b"\n"):
            raw = raw[:-1]
        if raw.endswith(b"\r"):
            raw = raw[:-1]
        if raw == ok:
            return True
        if raw in ng:
            return False


def _validate_line(line: str) -> None:
    """送る1行に ``\\r`` や ``\\n`` を入れてはいけない。"""
    if "\r" in line or "\n" in line:
        raise ValueError("送る1行に改行を含める事はできません")


def _tune_socket(sock: socket.socket | None) -> None:
    if sock is None:
        return
    try:
        sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
    except OSError:
        pass
    _quickack(sock)


def _quickack(sock: socket.socket | None) -> None:
    """Linux の TCP_QUICKACK。カーネルが戻すので、受けるたびに付け直す。"""
    if sock is None or not sys.platform.startswith("linux"):
        return
    try:
        sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_QUICKACK, 1)
    except (OSError, AttributeError):
        pass


class PhiSession:
    """1キャラ分の接続。``run`` を1つのタスクで動かす。"""

    def __init__(
        self,
        host: str,
        port: int,
        char_id: str,
        *,
        keepalive_after: float = KEEPALIVE_AFTER,
        warn_after: float = WARN_AFTER,
        connect_timeout: float = CONNECT_TIMEOUT,
        write_timeout: float = WRITE_TIMEOUT,
        transfer_timeout: float = TRANSFER_TIMEOUT,
        record_dir: str | Path | None = None,
        auto_unequip: bool = True,
        auto_equip: bool = False,
    ) -> None:
        self.host = host
        self.port = port
        self.char_id = char_id
        self.keepalive_after = keepalive_after
        self.warn_after = warn_after
        self.connect_timeout = connect_timeout
        self.write_timeout = write_timeout
        self.transfer_timeout = transfer_timeout
        self.record_dir = Path(record_dir) if record_dir else None
        #: 系統魔法の前に武器を外す(Philly の AutoUnequipSystemMagic、既定 on)。
        #: 装備し直すのは AutoEquipSystemMagic、既定 off
        self.auto_unequip = auto_unequip
        self.auto_equip = auto_equip
        self._auto_unequip = AutoUnequip()
        self.events: asyncio.Queue[
            Event | SessionErrorEvent | SessionClosedEvent | TransferConfirmEvent
        ] = asyncio.Queue()
        self._send_queue: asyncio.Queue[str | _CloseList | _Disconnect] = asyncio.Queue()

    # -- UI から呼ぶ送信 ----------------------------------------------------

    async def send(self, line: str) -> None:
        """1行を送る。``\\r`` や ``\\n`` を含む行は送らない。"""
        _validate_line(line)
        await self._send_queue.put(line)

    async def send_lines(self, lines: list[str]) -> None:
        for line in lines:
            await self.send(line)

    async def send_text(self, text: str) -> None:
        """``\\n`` 区切りの複数行を、行に分けて送る。"""
        lines = text.split("\n")
        if text.endswith("\n") and lines and lines[-1] == "":
            lines.pop()
        await self.send_lines(lines)

    async def send_system_magic(self, text: str, reequip: bool) -> None:
        """系統魔法を唱える行を送る。

        自動装備外しが on なら、唱える行を ``#wphi-cast`` の1行にまとめて
        送る。セッションが ``unequip`` だけを先に送り、装備のリストを見て
        から唱える(仕様書 §7.1)。off なら行をそのまま送る。
        """
        if not self.auto_unequip:
            await self.send_text(text)
            return
        flag = "1" if (reequip and self.auto_equip) else "0"
        await self.send(CAST_PREFIX + flag + " " + "\t".join(text.split("\n")))

    async def close_list(self) -> None:
        """リストを閉じた事をパーサへ伝える。サーバへは何も送らない。"""
        await self._send_queue.put(_CloseList())

    async def disconnect(self, graceful: bool = True) -> None:
        """切断を頼む。graceful なら ``#x`` を送ってから閉じる。"""
        await self._send_queue.put(_Disconnect(graceful=graceful))

    def send_nowait(self, line: str) -> None:
        """同じスレッド・同じループから呼ぶ、待たない送信。"""
        _validate_line(line)
        self._send_queue.put_nowait(line)

    async def _wait_transfer_answer(self) -> bool | None:
        """移動の確認の答えを待つ。True=行く、False=やめる、None=切断。

        期限切れはやめる扱い。答え以外の行は、移動の間に打ったものとして
        捨てる。
        """
        loop = asyncio.get_running_loop()
        deadline = loop.time() + self.transfer_timeout
        while True:
            remaining = deadline - loop.time()
            if remaining <= 0:
                return False
            try:
                item = await asyncio.wait_for(
                    self._send_queue.get(), timeout=remaining
                )
            except TimeoutError:
                return False
            if isinstance(item, _Disconnect):
                return None
            if isinstance(item, str):
                if item == TRANSFER_YES:
                    return True
                if item == TRANSFER_NO:
                    return False

    # -- 接続の実行 ----------------------------------------------------------

    async def run(self) -> None:
        """接続し、切れるまで送受信を続ける。終わったら Closed を出す。"""
        loop = asyncio.get_running_loop()
        try:
            reader, writer = await asyncio.wait_for(
                asyncio.open_connection(self.host, self.port),
                timeout=self.connect_timeout,
            )
        except TimeoutError:
            self.events.put_nowait(SessionErrorEvent("接続がタイムアウトしました"))
            self.events.put_nowait(SessionClosedEvent())
            return
        except OSError as exc:
            self.events.put_nowait(SessionErrorEvent(f"接続出来ません: {exc}"))
            self.events.put_nowait(SessionClosedEvent())
            return

        sock = writer.get_extra_info("socket")
        _tune_socket(sock)
        record_file = self._open_record()

        login_data = b"".join(encode(line) + b"\n" for line in login_lines(self.char_id))
        try:
            writer.write(login_data)
            await asyncio.wait_for(writer.drain(), timeout=self.write_timeout)
        except (TimeoutError, OSError) as exc:
            self.events.put_nowait(SessionErrorEvent(f"送信に失敗しました: {exc}"))
            self._close_writer(writer)
            self._close_record(record_file)
            self.events.put_nowait(SessionClosedEvent())
            return

        recv_queue: asyncio.Queue[bytes | None | Exception] = asyncio.Queue()

        async def _start_reader(
            stream_reader: asyncio.StreamReader,
            queue: asyncio.Queue[bytes | None | Exception],
        ) -> None:
            try:
                while True:
                    chunk = await stream_reader.read(32 * 1024)
                    if not chunk:
                        await queue.put(None)
                        return
                    await queue.put(chunk)
            except OSError as exc:
                await queue.put(exc)

        reader_task = asyncio.create_task(_start_reader(reader, recv_queue))
        lines = LineBuffer()
        parser = Parser()
        last_recv = loop.time()
        keepalive_sent = False
        warned = False

        def process_line(line: bytes, reply: list[str]) -> str | None:
            """1行を処理する。世界移動の要求なら移動先を返す。"""
            # 地形はバイナリなので、装備外しの判定には掛けない
            if not (line.startswith(b"#m57 M") or line.startswith(b"#map M")):
                hidden, auto_reply = self._auto_unequip.filter(
                    strip_tags(decode(line)), loop.time()
                )
                if hidden:
                    reply.extend(auto_reply)
                    return None
            for event in parser.feed(line):
                if isinstance(event, InternalEvent):
                    if event.action == "lag":
                        reply.append("#end-lag")
                    elif event.action == "remap":
                        reply.append("#map")
                elif isinstance(event, WorldTransferEvent):
                    return event.server
                else:
                    self.events.put_nowait(event)
            return None

        async def wait_src_line(
            ok: bytes, ng: tuple[bytes, ...], deadline: float
        ) -> tuple[bool | str, list[bytes]]:
            """移動元から ``ok`` の行を待つ。返りは(成否, 途中の行)。

            成否が ``"closed"`` なら、待つ間に切断を頼まれた。途中の行は、
            移動に失敗した時に処理し直す。打った行は捨てる。
            """
            skipped: list[bytes] = []
            while True:
                remaining = deadline - loop.time()
                if remaining <= 0:
                    return False, skipped
                recv_get = asyncio.create_task(recv_queue.get())
                send_get = asyncio.create_task(self._send_queue.get())
                done, pending = await asyncio.wait(
                    {recv_get, send_get},
                    timeout=remaining,
                    return_when=asyncio.FIRST_COMPLETED,
                )
                if not done:
                    for task in pending:
                        task.cancel()
                    await asyncio.gather(*pending, return_exceptions=True)
                    return False, skipped
                for task in pending:
                    task.cancel()
                await asyncio.gather(*pending, return_exceptions=True)
                if send_get in done:
                    item = send_get.result()
                    if isinstance(item, _Disconnect):
                        return "closed", skipped
                if recv_get in done:
                    item = recv_get.result()
                    if item is None or isinstance(item, Exception):
                        return False, skipped
                    for line in lines.feed(item):
                        if line == ok:
                            return True, skipped
                        if line in ng:
                            return False, skipped
                        skipped.append(line)

        async def do_transfer(server: str) -> tuple[str, list[bytes]]:
            """世界移動の手順。返りは("moved"/"stay"/"closed", 途中の行)。

            成功したら接続を差し替え、失敗したら移動元に留まる。
            """
            nonlocal reader, writer, recv_queue, reader_task, lines, parser
            nonlocal last_recv, keepalive_sent, warned
            target = transfer_target(server)
            if target is not None and target[0].lower() != self.host.lower():
                # 今と違うホストへは、キャラ ID を送る前に確かめる
                self.events.put_nowait(
                    TransferConfirmEvent(host=target[0], port=target[1])
                )
                answer = await self._wait_transfer_answer()
                if answer is None:
                    await self._write_best_effort(writer, ["#x"], timeout=5.0)
                    return "closed", []
                if not answer:
                    self.events.put_nowait(_system("世界移動をやめました"))
                    await self._write_best_effort(writer, ["#no-srv"], timeout=5.0)
                    last_recv = loop.time()
                    return "stay", []
            self.events.put_nowait(_system("転送先世界へゲート接続開始..."))
            dst_reader: asyncio.StreamReader | None = None
            dst_writer: asyncio.StreamWriter | None = None
            try:
                if target is None:
                    raise OSError("移動先が分かりません")
                host, port = target
                dst_reader, dst_writer = await asyncio.wait_for(
                    asyncio.open_connection(host, port),
                    timeout=self.connect_timeout,
                )
            except (TimeoutError, OSError):
                self.events.put_nowait(_system("転送先の世界が見つかりません"))
                await self._write_best_effort(writer, ["#no-srv"], timeout=5.0)
                last_recv = loop.time()
                return "stay", []
            _tune_socket(dst_writer.get_extra_info("socket"))
            swapped = False
            try:
                self.events.put_nowait(_system("転送先世界に転送準備要求..."))
                if (
                    await self._write(dst_writer, [f"#reserve {self.char_id}"])
                    is not None
                ):
                    reserved = False
                else:
                    reserved = await _wait_dst_line(
                        dst_reader,
                        b"#rsv-ok",
                        (b"#rsv-no", b"#x"),
                        loop.time() + self.transfer_timeout,
                    )
                if not reserved:
                    await self._write_best_effort(writer, ["#no-srv"], timeout=5.0)
                    self.events.put_nowait(
                        _system(
                            "転送準備失敗。転送先の世界で同時接続数を"
                            "オーバーしている可能性があります。"
                        )
                    )
                    last_recv = loop.time()
                    return "stay", []
                self.events.put_nowait(_system("転送元世界に転送要求..."))
                if (
                    await self._write(writer, [f"#trans {host} {port}"])
                    is not None
                ):
                    accepted: bool | str = False
                    skipped: list[bytes] = []
                else:
                    accepted, skipped = await wait_src_line(
                        b"#trs-ok",
                        (b"#trs-no",),
                        loop.time() + self.transfer_timeout,
                    )
                if accepted == "closed":
                    await self._write_best_effort(writer, ["#x"], timeout=5.0)
                    return "closed", []
                if not accepted:
                    await self._write_best_effort(
                        writer, ["#ch-srv-no"], timeout=5.0
                    )
                    self.events.put_nowait(_system("転送失敗"))
                    last_recv = loop.time()
                    return "stay", skipped
                if (
                    await self._write(
                        dst_writer, ["#ch-srv-ok"] + login_lines(None)
                    )
                    is not None
                ):
                    self.events.put_nowait(
                        _system("転送先世界への送信に失敗しました")
                    )
                    last_recv = loop.time()
                    return "stay", skipped
                self.events.put_nowait(_system("転送完了"))
                old_task = reader_task
                old_writer = writer
                new_queue: asyncio.Queue[bytes | None | Exception] = asyncio.Queue()
                reader_task = asyncio.create_task(
                    _start_reader(dst_reader, new_queue)
                )
                recv_queue = new_queue
                reader = dst_reader
                writer = dst_writer
                lines = LineBuffer()
                parser = Parser()
                self.host, self.port = host, port
                # 移動の間に打った行は捨てる
                while True:
                    try:
                        self._send_queue.get_nowait()
                    except asyncio.QueueEmpty:
                        break
                last_recv = loop.time()
                keepalive_sent = False
                warned = False
                old_task.cancel()
                await asyncio.gather(old_task, return_exceptions=True)
                self._close_writer(old_writer)
                swapped = True
                return "moved", []
            finally:
                if not swapped and dst_writer is not None:
                    self._close_writer(dst_writer)
        try:
            while True:
                now = loop.time()
                if warned:
                    timeout: float | None = None
                elif keepalive_sent:
                    timeout = max(0.0, last_recv + self.warn_after - now)
                else:
                    timeout = max(0.0, last_recv + self.keepalive_after - now)

                recv_get = asyncio.create_task(recv_queue.get())
                send_get = asyncio.create_task(self._send_queue.get())
                done, pending = await asyncio.wait(
                    {recv_get, send_get},
                    timeout=timeout,
                    return_when=asyncio.FIRST_COMPLETED,
                )
                if not done:
                    for task in pending:
                        task.cancel()
                    await asyncio.gather(*pending, return_exceptions=True)
                    if not keepalive_sent:
                        keepalive_sent = True
                        if await self._write(writer, ["#code-sjis"]) is not None:
                            self.events.put_nowait(
                                SessionErrorEvent("送信に失敗しました")
                            )
                            break
                    elif not warned:
                        warned = True
                        self.events.put_nowait(
                            SessionErrorEvent("サーバから3分間応答がありません")
                        )
                    continue

                for task in pending:
                    task.cancel()
                await asyncio.gather(*pending, return_exceptions=True)

                reply: list[str] = []
                closed = False
                moved_connection = False
                disconnect: _Disconnect | None = None
                for task in done:
                    item = task.result()
                    if task is recv_get:
                        if isinstance(item, Exception):
                            self.events.put_nowait(
                                SessionErrorEvent(f"受信に失敗しました: {item}")
                            )
                            closed = True
                            continue
                        if item is None:
                            closed = True
                            continue
                        _quickack(writer.get_extra_info("socket"))
                        last_recv = loop.time()
                        keepalive_sent = False
                        warned = False
                        if record_file is not None:
                            try:
                                record_file.write(item)
                            except OSError:
                                pass
                        pending_lines: deque[bytes] = deque(lines.feed(item))
                        while pending_lines:
                            transfer_server = process_line(
                                pending_lines.popleft(), reply
                            )
                            if transfer_server is None:
                                continue
                            # 返信を先に送ってから、移動の手順へ
                            if reply:
                                error = await self._write(writer, reply)
                                reply = []
                                if error is not None:
                                    self.events.put_nowait(
                                        SessionErrorEvent(error)
                                    )
                                    closed = True
                                    pending_lines.clear()
                                    break
                            outcome, skipped = await do_transfer(transfer_server)
                            if outcome == "closed":
                                closed = True
                                pending_lines.clear()
                                break
                            if outcome == "moved":
                                # 移動元で受けていた残りの行は捨てる
                                moved_connection = True
                                pending_lines.clear()
                                break
                            # 失敗して留まる時は、途中の行も処理し直す
                            pending_lines.extend(skipped)
                    else:
                        if isinstance(item, _Disconnect):
                            disconnect = item
                        elif isinstance(item, _CloseList):
                            for event in parser.end_list():
                                self.events.put_nowait(event)
                        elif isinstance(item, str) and not moved_connection:
                            if item.startswith(CAST_PREFIX):
                                # 系統魔法の唱える行。unequip だけを先に送る
                                first = self._auto_unequip.start(item, loop.time())
                                if first is not None:
                                    reply.append(first)
                                continue
                            if item.startswith("#wphi-"):
                                # セッション内部の接頭辞。サーバへは送らない
                                continue
                            if item == "#ulist":
                                parser.clear_users()
                            reply.append(item)

                if disconnect is not None:
                    if disconnect.graceful:
                        await self._write_best_effort(writer, ["#x"], timeout=5.0)
                    break
                if reply:
                    error = await self._write(writer, reply)
                    if error is not None:
                        self.events.put_nowait(SessionErrorEvent(error))
                        break
                if closed:
                    break
        finally:
            reader_task.cancel()
            await asyncio.gather(reader_task, return_exceptions=True)
            self._close_writer(writer)
            self._close_record(record_file)
            self.events.put_nowait(SessionClosedEvent())

    async def _write(self, writer: asyncio.StreamWriter, lines: list[str]) -> str | None:
        """行を送る。失敗したら文言を返す。"""
        data = b"".join(encode(line) + b"\n" for line in lines)
        try:
            writer.write(data)
            await asyncio.wait_for(writer.drain(), timeout=self.write_timeout)
        except TimeoutError:
            return "送信に失敗しました: 送信がタイムアウトしました"
        except OSError as exc:
            return f"送信に失敗しました: {exc}"
        return None

    async def _write_best_effort(
        self, writer: asyncio.StreamWriter, lines: list[str], *, timeout: float
    ) -> None:
        try:
            writer.write(b"".join(encode(line) + b"\n" for line in lines))
            await asyncio.wait_for(writer.drain(), timeout=timeout)
        except (TimeoutError, OSError):
            pass

    def _open_record(self):
        if self.record_dir is None:
            return None
        try:
            self.record_dir.mkdir(parents=True, exist_ok=True)
            name = f"{self.host}_{self.port}_{int(time.time())}.bin"
            return open(self.record_dir / name, "ab")
        except OSError:
            return None

    @staticmethod
    def _close_record(record_file) -> None:
        if record_file is not None:
            try:
                record_file.close()
            except OSError:
                pass

    @staticmethod
    def _close_writer(writer: asyncio.StreamWriter) -> None:
        try:
            writer.close()
        except OSError:
            pass
