"""curses の TUI クライアント。macOS・Linux の端末で動く。

画面は、状態の行・ログ・地図・入力欄に分かれる。Philly と同じく、入力欄の
外にフォーカスがある時だけキーを操作に使う。``Esc`` で操作へ、``Tab`` で
入力欄へ移る。

使い方::

    python -m neophi.tui --host 127.0.0.1 --port 21000
    python -m neophi.tui --host <ホスト> --port <ポート> --id <キャラID>

``Ctrl+Q`` か、入力欄で ``/quit`` と打つと終わる。
"""

from __future__ import annotations

import argparse
import asyncio
import getpass
import locale
import os
import queue
import sys
import threading
import time
import unicodedata
from collections import deque
from dataclasses import dataclass, field

try:
    import curses
except ImportError:  # Windows の標準の Python には curses が無い
    curses = None  # type: ignore[assignment]

from .cli import board_lines, prepare_line
from .keys import KeyAction, key_action, list_key_action, move_command, move_input
from .list_state import (
    ListFlow,
    ListState,
    list_no,
    list_ok,
    more_no,
    move_list_cursor,
    page_top,
    receive_list,
)
from .map_text import render_eagle_eye, render_map
from .parser import (
    CondEvent,
    ConnectionEvent,
    EagleEyeEvent,
    EditEvent,
    ListEvent,
    MapEvent,
    MessageEvent,
    ModeEvent,
    NoticeEvent,
    StatusEvent,
    UserListEvent,
)
from .session import (
    TRANSFER_NO,
    TRANSFER_YES,
    PhiSession,
    SessionClosedEvent,
    SessionErrorEvent,
    TransferConfirmEvent,
)
from .tags import plain_text

__all__ = ["main"]

_HELP_TEXT = [
    "操作: 矢印/テンキーで移動、Z 拾う、X 置く、C 使う、Space 攻撃",
    "Tab で入力欄へ、Esc で操作へ。Ctrl+Q で終わる。",
    "入力欄の命令: /help /quit /force /loud /ulist /map",
]


def _set_locale() -> None:
    """日本語の入出力が出来るロケールにする。C ロケールのままだと
    ``get_wch`` が UTF-8 を1文字として読めない。"""
    try:
        locale.setlocale(locale.LC_ALL, "")
    except locale.Error:
        pass
    encoding = locale.getpreferredencoding(False).lower().replace("-", "")
    if encoding != "utf8":
        for name in ("C.UTF-8", "en_US.UTF-8", "ja_JP.UTF-8"):
            try:
                locale.setlocale(locale.LC_ALL, name)
            except locale.Error:
                continue
            break


def _display_width(text: str) -> int:
    """端末での表示幅。全角は2、結合文字などは0として数える。"""
    width = 0
    for ch in text:
        if unicodedata.combining(ch):
            continue
        width += 2 if unicodedata.east_asian_width(ch) in ("W", "F") else 1
    return width


def _truncate(text: str, width: int) -> str:
    """表示幅が ``width`` を超えないよう切る。"""
    out: list[str] = []
    used = 0
    for ch in text:
        w = 0 if unicodedata.combining(ch) else (
            2 if unicodedata.east_asian_width(ch) in ("W", "F") else 1
        )
        if used + w > width:
            break
        out.append(ch)
        used += w
    return "".join(out)


@dataclass
class _KeyPress:
    code: str | None = None  # keys.ts のコード名(ArrowUp・KeyZ など)
    shift: bool = False
    ctrl: bool = False
    alt: bool = False
    text: str = ""  # 打った文字(入力欄用)
    kind: str = "key"  # enter/tab/backspace/delete/left/right/home/end/pageup/pagedown/resize/escape/char


@dataclass
class _InputLine:
    buffer: str = ""
    cursor: int = 0
    history: list[str] = field(default_factory=list)
    history_index: int = -1
    saved: str = ""

    def insert(self, text: str) -> None:
        self.buffer = self.buffer[: self.cursor] + text + self.buffer[self.cursor :]
        self.cursor += len(text)
        self.history_index = -1

    def backspace(self) -> None:
        if self.cursor > 0:
            self.buffer = self.buffer[: self.cursor - 1] + self.buffer[self.cursor :]
            self.cursor -= 1

    def delete(self) -> None:
        if self.cursor < len(self.buffer):
            self.buffer = self.buffer[: self.cursor] + self.buffer[self.cursor + 1 :]

    def clear(self) -> None:
        self.buffer = ""
        self.cursor = 0

    def take(self) -> str:
        text = self.buffer
        if text:
            self.history.append(text)
        self.clear()
        self.history_index = -1
        return text

    def history_prev(self) -> None:
        if not self.history:
            return
        if self.history_index == -1:
            self.saved = self.buffer
            self.history_index = len(self.history) - 1
        elif self.history_index > 0:
            self.history_index -= 1
        self.buffer = self.history[self.history_index]
        self.cursor = len(self.buffer)

    def history_next(self) -> None:
        if self.history_index == -1:
            return
        if self.history_index < len(self.history) - 1:
            self.history_index += 1
            self.buffer = self.history[self.history_index]
        else:
            self.history_index = -1
            self.buffer = self.saved
        self.cursor = len(self.buffer)


class _TUI:
    def __init__(
        self, host: str, port: int, char_id: str, *, record_dir: str | None = None,
        auto_unequip: bool = True, auto_equip: bool = False,
    ) -> None:
        self._session = PhiSession(
            host, port, char_id, record_dir=record_dir,
            auto_unequip=auto_unequip, auto_equip=auto_equip,
        )
        self._loop: asyncio.AbstractEventLoop | None = None
        self._loop_ready = threading.Event()
        self._event_queue: queue.Queue = queue.Queue()
        self._session_thread: threading.Thread | None = None

        self._log: deque[tuple[str, str, str]] = deque(maxlen=1000)
        self._scroll_offset = 0
        self._status: StatusEvent | None = None
        self._cond: CondEvent | None = None
        self._map: MapEvent | None = None
        self._eagle: EagleEyeEvent | None = None
        self._map_seq = 0
        self._eagle_seq = 0
        self._name = ""
        self._world = ""
        self._area = ""
        self._mapset = ""
        self._users: list[str] = []
        self._mode: ModeEvent | None = None
        self._list_state: ListState | None = None
        self._list_flow = ListFlow()
        self._map_visible = True

        # 入力の状態: command | input | ask | confirm | editor_single | editor_multi
        self._input_state = "command"
        self._input = _InputLine()
        self._ask_action: KeyAction | None = None
        self._ask_error = ""
        self._confirm_action: KeyAction | None = None
        self._confirm_message = ""
        self._transfer_confirm: tuple[str, int] | None = None
        self._editor_lines: list[str] = []
        self._loud = False
        self._loud_warned = False

        self._closed = False
        self._exiting = False
        self._should_exit = False

    # -- セッションとの橋渡し -------------------------------------------------

    def _session_main(self) -> None:
        loop = asyncio.new_event_loop()
        asyncio.set_event_loop(loop)
        self._loop = loop
        self._loop_ready.set()

        async def _forward() -> None:
            while True:
                event = await self._session.events.get()
                self._event_queue.put(event)
                if isinstance(event, SessionClosedEvent):
                    return

        async def _main() -> None:
            forwarder = asyncio.create_task(_forward())
            await self._session.run()
            await forwarder

        try:
            loop.run_until_complete(_main())
        finally:
            loop.close()

    def _submit(self, coro) -> None:
        if not self._loop_ready.wait(timeout=5.0) or self._loop is None:
            return
        future = asyncio.run_coroutine_threadsafe(coro, self._loop)

        def _done(fut) -> None:
            try:
                fut.result()
            except Exception as exc:  # noqa: BLE001 - 画面に出すだけ
                self._event_queue.put(SessionErrorEvent(f"送信に失敗しました: {exc}"))

        future.add_done_callback(_done)

    def _send_text(self, text: str) -> None:
        self._submit(self._session.send_text(text))

    def _send_and_close_list(self, text: str) -> None:
        async def _do() -> None:
            await self._session.send_text(text)
            await self._session.close_list()

        self._submit(_do())

    def _send_system_magic(self, text: str, reequip: bool, close_list: bool) -> None:
        """系統魔法を唱える。リストを閉じてからセッションへ渡す。"""

        async def _do() -> None:
            if close_list:
                await self._session.close_list()
            await self._session.send_system_magic(text, reequip)

        self._submit(_do())

    def _close_list(self) -> None:
        self._submit(self._session.close_list())

    def _request_disconnect(self, graceful: bool) -> None:
        self._exiting = True
        self._submit(self._session.disconnect(graceful=graceful))

    # -- ログ -----------------------------------------------------------------

    def _add_log(self, channel: str, text: str) -> None:
        stamp = time.strftime("%H:%M")
        lines = text.split("\n")
        for line in lines:
            self._log.append((channel, line, stamp))
        if self._scroll_offset > 0:
            self._scroll_offset += len(lines)

    def _add_local(self, text: str) -> None:
        self._add_log("system", text)

    # -- イベント ---------------------------------------------------------------

    def _drain_events(self) -> None:
        while True:
            try:
                event = self._event_queue.get_nowait()
            except queue.Empty:
                return
            self._handle_event(event)

    def _handle_event(self, event) -> None:
        if isinstance(event, MessageEvent):
            self._add_log(event.channel, plain_text(event.text))
        elif isinstance(event, StatusEvent):
            self._status = event
            if event.name:
                self._name = event.name
        elif isinstance(event, CondEvent):
            self._cond = event
        elif isinstance(event, MapEvent):
            self._map = event
            self._map_seq += 1
        elif isinstance(event, EagleEyeEvent):
            self._eagle = event
            self._eagle_seq += 1
        elif isinstance(event, ListEvent):
            result = receive_list(
                self._list_flow, event.active, event.lines, self._list_state
            )
            if result == "close":
                self._list_state = None
            elif isinstance(result, ListState):
                self._list_state = result
        elif isinstance(event, EditEvent):
            if event.mode == "single":
                self._input_state = "editor_single"
                self._input.clear()
                self._add_local("[入力] 1行の答えを打ってください。")
            elif event.mode == "multi":
                self._input_state = "editor_multi"
                self._editor_lines = []
                self._input.clear()
                self._add_local("[看板] 本文を打ってください。'.' で終わり、'.!' で取り消し。")
            else:
                if self._input_state in ("editor_single", "editor_multi"):
                    self._input_state = "command"
                self._add_local("[エディタ] 閉じました。")
        elif isinstance(event, NoticeEvent):
            if event.name:
                self._name = event.name
            if event.world:
                self._world = event.world
            if event.area:
                self._area = event.area
            if event.mapset:
                self._mapset = event.mapset
        elif isinstance(event, ModeEvent):
            self._mode = event
        elif isinstance(event, UserListEvent):
            self._users = [u.name for u in event.users]
        elif isinstance(event, TransferConfirmEvent):
            self._transfer_confirm = (event.host, event.port)
            self._confirm_action = None
            self._confirm_message = (
                f"別のホスト {event.host}:{event.port} へ"
                "キャラIDを送って移動しますか？"
            )
            self._input_state = "confirm"
        elif isinstance(event, ConnectionEvent):
            self._add_local("サーバーから切断されました。")
        elif isinstance(event, SessionErrorEvent):
            self._add_local(f"[エラー] {event.message}")
        elif isinstance(event, SessionClosedEvent):
            self._closed = True
            self._add_local("--- 切断しました ---")
            if self._exiting:
                self._should_exit = True

    # -- キー -------------------------------------------------------------------

    def _decode_wch(self, key, *, alt: bool) -> _KeyPress:
        if isinstance(key, int):
            mapping = {
                curses.KEY_UP: ("ArrowUp", "up"),
                curses.KEY_DOWN: ("ArrowDown", "down"),
                curses.KEY_LEFT: ("ArrowLeft", "left"),
                curses.KEY_RIGHT: ("ArrowRight", "right"),
                curses.KEY_HOME: ("Home", "home"),
                curses.KEY_END: ("End", "end"),
                curses.KEY_PPAGE: ("PageUp", "pageup"),
                curses.KEY_NPAGE: ("PageDown", "pagedown"),
                curses.KEY_BACKSPACE: ("Backspace", "backspace"),
                curses.KEY_DC: ("Delete", "delete"),
                curses.KEY_RESIZE: ("Resize", "resize"),
                curses.KEY_ENTER: ("Enter", "enter"),
            }
            if key in mapping:
                code, kind = mapping[key]
                return _KeyPress(code=code, alt=alt, kind=kind)
            for n in range(1, 13):
                if key == curses.KEY_F(n):
                    return _KeyPress(code=f"F{n}", alt=alt)
            return _KeyPress(code=None, alt=alt, kind="key")
        # str
        if key in ("\n", "\r"):
            return _KeyPress(code="Enter", alt=alt, kind="enter")
        if key == "\t":
            return _KeyPress(code="Tab", alt=alt, kind="tab")
        if key in ("\x7f", "\b"):
            return _KeyPress(code="Backspace", alt=alt, kind="backspace")
        if key == "\x1b":
            return _KeyPress(code="Escape", alt=alt, kind="escape")
        if len(key) == 1 and ord(key) < 32:
            # Ctrl+文字。Ctrl+Q(0x11)は終わる時に使う
            letter = chr(ord(key) + 64)
            return _KeyPress(code=f"Key{letter}", ctrl=True, alt=alt, text=key)
        if len(key) == 1 and key.isalpha() and key.isascii():
            return _KeyPress(
                code=f"Key{key.upper()}", shift=key.isupper(), alt=alt, text=key
            )
        if len(key) == 1 and key.isdigit():
            return _KeyPress(code=f"Digit{key}", alt=alt, text=key)
        shifted_digits = dict(zip("!@#$%^&*()", "1234567890"))
        if key in shifted_digits:
            return _KeyPress(code=f"Digit{shifted_digits[key]}", shift=True, alt=alt, text=key)
        punct = {
            ".": "Period", "-": "Minus", "=": "Equal", ";": "Semicolon",
            "/": "Slash", "'": "Quote", "[": "BracketLeft", "]": "BracketRight",
            "\\": "Backslash", "`": "Backquote", ",": "Comma", " ": "Space",
        }
        if key in punct:
            return _KeyPress(code=punct[key], alt=alt, text=key)
        if key == "_":
            return _KeyPress(code="Minus", shift=True, alt=alt, text=key)
        if key == "+":
            return _KeyPress(code="Equal", shift=True, alt=alt, text=key)
        if key == ":":
            return _KeyPress(code="Semicolon", shift=True, alt=alt, text=key)
        if key == "?":
            return _KeyPress(code="Slash", shift=True, alt=alt, text=key)
        if key == '"':
            return _KeyPress(code="Quote", shift=True, alt=alt, text=key)
        # 日本語などの文字は、入力欄でそのまま使う
        return _KeyPress(code=None, alt=alt, text=key, kind="char")

    def _read_key(self, stdscr) -> _KeyPress | None:
        try:
            key = stdscr.get_wch()
        except curses.error:
            return None
        if key == -1:
            return None
        if key == "\x1b":
            # Alt+キーか、Esc 単独かを見る
            stdscr.nodelay(True)
            try:
                try:
                    key2 = stdscr.get_wch()
                except curses.error:
                    key2 = None
            finally:
                stdscr.nodelay(False)
                stdscr.timeout(50)
            if key2 is None or key2 == -1:
                return _KeyPress(code="Escape", kind="escape")
            return self._decode_wch(key2, alt=True)
        return self._decode_wch(key, alt=False)

    def _north_fix(self) -> bool:
        if self._map is None:
            return True
        return self._map.size == 7 and self._map.style != "turn"

    def _execute_action(self, action: KeyAction, answer: str | None = None) -> None:
        if action.ask is not None:
            # 質問の答えを待つ状態へ移る
            self._ask_action = action
            self._ask_error = ""
            self._input_state = "ask"
            self._input.clear()
            return
        if action.confirm is not None:
            # 世界移動の確認が出ている間は、そちらを優先します
            if self._transfer_confirm is not None:
                return
            self._confirm_action = action
            self._confirm_message = action.confirm
            self._input_state = "confirm"
            return
        self._send_action(action, answer)

    def _send_action(self, action: KeyAction, answer: str | None = None) -> None:
        if action.send is not None:
            text = action.send
            if answer is not None:
                text = text.replace("{}", answer)
            if action.cancel_list:
                self._list_flow.cancel += action.cancel_list
            if action.system_magic is not None:
                # 系統魔法はセッションへ渡し、unequip を先に送らせる。
                # 開いているリストは、唱える行を送る前に閉じる
                close_list = self._list_state is not None
                self._list_state = None
                self._send_system_magic(
                    text, action.system_magic == "reequip", close_list
                )
            elif self._list_state is not None:
                self._send_and_close_list(text)
                self._list_state = None
            else:
                self._send_text(text)
        if action.write:
            self._send_text("write")
        if action.focus_input:
            self._input_state = "input"
        if action.toggle_map:
            self._map_visible = not self._map_visible
        if action.menu in ("force-close", "all-force-close"):
            self._request_disconnect(graceful=False)

    def _handle_command_key(self, press: _KeyPress) -> None:
        if press.ctrl and press.code == "KeyQ":
            self._request_disconnect(graceful=True)
            return
        if press.kind == "pageup":
            self._scroll_offset += 10
            return
        if press.kind == "pagedown":
            self._scroll_offset = max(0, self._scroll_offset - 10)
            return
        if press.kind == "escape":
            self._scroll_offset = 0
            return
        if press.kind == "enter":
            self._input_state = "input"
            return
        if press.code is None:
            return

        if self._list_state is not None:
            list_action = list_key_action(
                press.code, shift=press.shift, ctrl=press.ctrl, alt=press.alt
            )
            if list_action is not None:
                self._handle_list_key(list_action)
                return

        moved = move_input(
            press.code, shift=press.shift, ctrl=press.ctrl, alt=press.alt
        )
        if moved is not None:
            key, mods = moved
            self._send_text(move_command(key, mods, self._north_fix()))
            return
        action = key_action(
            press.code, shift=press.shift, ctrl=press.ctrl, alt=press.alt
        )
        if action is not None:
            self._execute_action(action)

    def _handle_list_key(self, action) -> None:
        state = self._list_state
        if state is None:
            return
        if action.focus_input:
            self._input_state = "input"
            return
        if action.send is not None:
            self._send_and_close_list(action.send)
            self._list_state = None
            return
        if action.list_no is not None:
            result = list_no(state, action.list_no)
            if result is None:
                return
            text, close = result
            if close:
                self._send_and_close_list(text)
                self._list_state = None
            else:
                self._send_text(text)
                state.waiting = True
            return
        if action.list_ok:
            self._send_and_close_list(list_ok(state))
            self._list_state = None
            return
        if action.list_toggle:
            self._list_state = move_list_cursor(state, toggle=True)
            return
        if action.list_cursor:
            self._list_state = move_list_cursor(state, cursor_delta=action.list_cursor)
            return

    def _edit_key(self, press: _KeyPress, *, history: bool = False) -> bool:
        """入力欄の編集キー。編集したら True。"""
        if press.kind == "backspace":
            self._input.backspace()
            return True
        if press.kind == "delete":
            self._input.delete()
            return True
        if press.kind == "left":
            self._input.cursor = max(0, self._input.cursor - 1)
            return True
        if press.kind == "right":
            self._input.cursor = min(len(self._input.buffer), self._input.cursor + 1)
            return True
        if press.kind == "home":
            self._input.cursor = 0
            return True
        if press.kind == "end":
            self._input.cursor = len(self._input.buffer)
            return True
        if press.kind == "up" and history:
            self._input.history_prev()
            return True
        if press.kind == "down" and history:
            self._input.history_next()
            return True
        if press.text == "\x15":  # Ctrl+U
            self._input.clear()
            return True
        if press.text == "\x17":  # Ctrl+W
            before = self._input.buffer[: self._input.cursor].rstrip()
            cut = before.rfind(" ") + 1
            self._input.buffer = before[:cut] + self._input.buffer[self._input.cursor :]
            self._input.cursor = cut
            return True
        if press.text and press.kind == "char":
            self._input.insert(press.text)
            return True
        if press.text and len(press.text) == 1 and press.text.isprintable() and not press.ctrl and not press.alt:
            self._input.insert(press.text)
            return True
        return False

    def _handle_input_key(self, press: _KeyPress) -> None:
        if press.ctrl and press.code == "KeyQ":
            self._request_disconnect(graceful=True)
            return
        if press.kind == "escape":
            self._input_state = "command"
            return
        if press.kind == "enter":
            line = self._input.take()
            self._submit_input_line(line)
            return
        self._edit_key(press, history=True)

    def _submit_input_line(self, line: str) -> None:
        if line.startswith("/"):
            if self._handle_local_command(line):
                return
        prepared = prepare_line(line, loud=self._loud)
        if prepared is not None:
            if self._list_state is not None:
                self._send_and_close_list(prepared)
                self._list_state = None
            else:
                self._send_text(prepared)

    def _handle_local_command(self, line: str) -> bool:
        parts = line[1:].split()
        cmd = parts[0] if parts else ""
        if cmd in ("quit", "q"):
            self._request_disconnect(graceful=True)
            return True
        if cmd == "force":
            self._request_disconnect(graceful=False)
            return True
        if cmd == "help":
            for text in _HELP_TEXT:
                self._add_local(text)
            return True
        if cmd == "loud":
            if len(parts) >= 2:
                if parts[1] == "on" and not self._loud and not self._loud_warned:
                    self._add_local(
                        "大声で発言します。この世界にいる全員に聞こえます。"
                    )
                    self._loud_warned = True
                self._loud = parts[1] == "on"
            self._add_local(f"大声モード: {'on' if self._loud else 'off'}")
            return True
        if cmd == "ulist":
            self._send_text("#ulist")
            return True
        if cmd == "map":
            self._send_text("#map")
            return True
        if cmd == "status":
            self._add_local(f"接続者: {', '.join(self._users) if self._users else '(なし)'}")
            return True
        self._add_local(f"知らない命令です: /{cmd} (/help で一覧)")
        return True

    def _handle_ask_key(self, press: _KeyPress) -> None:
        action = self._ask_action
        if action is None or action.ask is None:
            self._input_state = "command"
            return
        if press.kind == "escape":
            self._ask_action = None
            self._input_state = "command"
            return
        if press.kind == "enter":
            answer = self._input.take()
            if answer == "":
                self._ask_action = None
                self._input_state = "command"
                return
            if action.ask.numeric and not answer.isdigit():
                self._ask_error = "数を入力してください。"
                self._input.buffer = answer
                self._input.cursor = len(answer)
                return
            self._ask_action = None
            self._input_state = "command"
            if action.cancel_list:
                self._list_flow.cancel += action.cancel_list
            if action.send is not None:
                self._send_text(action.send.replace("{}", answer))
            return
        self._edit_key(press)

    def _handle_confirm_key(self, press: _KeyPress) -> None:
        if self._transfer_confirm is not None:
            if press.kind == "escape" or press.text in ("n", "N"):
                self._transfer_confirm = None
                self._input_state = "command"
                self._send_text(TRANSFER_NO)
            elif press.text in ("y", "Y"):
                self._transfer_confirm = None
                self._input_state = "command"
                self._send_text(TRANSFER_YES)
            return
        if press.kind == "escape":
            self._confirm_action = None
            self._input_state = "command"
            return
        if press.text in ("y", "Y"):
            action = self._confirm_action
            self._confirm_action = None
            self._input_state = "command"
            if action is not None:
                # 確かめ済みなので、send だけを送る
                self._send_action(
                    KeyAction(
                        send=action.send, cancel_list=action.cancel_list,
                        system_magic=action.system_magic,
                    )
                )
            return
        if press.text in ("n", "N"):
            self._confirm_action = None
            self._input_state = "command"
            return

    def _handle_editor_key(self, press: _KeyPress) -> None:
        if press.ctrl and press.code == "KeyQ":
            self._request_disconnect(graceful=True)
            return
        if press.kind == "escape":
            # 取り消してエディタを出る
            self._send_text(".!")
            self._input_state = "command"
            self._editor_lines = []
            return
        if press.kind == "enter":
            line = self._input.take()
            if self._input_state == "editor_single":
                self._send_text(line if line != "" else " ")
                self._input_state = "command"
                return
            if line == ".":
                self._send_text("\n".join(board_lines(self._editor_lines)))
                self._input_state = "command"
                self._editor_lines = []
                return
            if line == ".!":
                self._send_text(".!")
                self._input_state = "command"
                self._editor_lines = []
                return
            self._editor_lines.append(line)
            self._add_log("log", f"[看板] {line}")
            return
        self._edit_key(press)

    # -- 描画 -------------------------------------------------------------------

    def _status_text(self) -> str:
        parts: list[str] = []
        if self._name:
            parts.append(self._name)
        status = self._status
        if status is not None:
            if status.hp is not None:
                parts.append(f"HP {status.hp}/{status.max_hp}")
            if status.mp is not None:
                parts.append(f"MP {status.mp}/{status.max_mp}")
            if status.exp is not None:
                parts.append(f"Exp {status.exp}")
            if status.gp is not None:
                parts.append(f"GP {status.gp}")
        if self._cond is not None:
            names = ["毒", "麻痺", "恐慌", "混乱", "狂戦士", "沈黙", "盲目"]
            flags = [self._cond.poison, self._cond.palsy, self._cond.panic,
                     self._cond.confuse, self._cond.berserk, self._cond.silence,
                     self._cond.blind]
            active = [n for n, on in zip(names, flags) if on]
            if active:
                parts.append(" ".join(active))
        if self._world or self._area:
            parts.append("/".join(p for p in (self._world, self._area) if p))
        if self._mode is not None:
            tags = []
            if self._mode.attack:
                tags.append("戦闘")
            if self._mode.magic:
                tags.append("魔法")
            if tags:
                parts.append(" ".join(tags))
        if self._closed:
            parts.append("切断")
        return " | ".join(parts)

    def _map_lines(self) -> list[str]:
        if self._eagle is not None and self._eagle_seq > self._map_seq:
            return [*render_eagle_eye(self._eagle), "(次の地図で戻ります)"]
        if self._map is not None:
            return render_map(self._map)
        return ["(地図はまだ届いていません)"]

    def _list_lines(self, width: int) -> list[str]:
        state = self._list_state
        if state is None:
            return []
        out = ["--- リスト ---"]
        top = page_top(state)
        start = min(top, max(0, state.cursor - 2))
        for i in range(start, len(state.lines)):
            number = state.start + i + 1
            cursor = ">" if i == state.cursor else " "
            check = "x" if state.checked[i] else " "
            text = plain_text(state.lines[i])
            out.append(_truncate(f"{cursor}[{check}] ({number}) {text}", width))
        out.append("1-9 選ぶ / Space チェック / Enter 決定 / . 取消")
        return out

    def _render(self, stdscr) -> None:
        height, width = stdscr.getmaxyx()
        stdscr.erase()
        if height < 10 or width < 40:
            self._safe_addstr(stdscr, 0, 0, "窓が小さすぎます。広げてください。")
            stdscr.refresh()
            return
        map_width = 34 if (self._map_visible and width >= 70) else 0
        log_width = width - map_width
        content_top = 1
        input_row = height - 2
        help_row = height - 1
        content_height = input_row - content_top

        # 状態の行
        self._safe_addstr(
            stdscr, 0, 0, _truncate(self._status_text(), width),
            curses.A_REVERSE,
        )

        # ログ
        visible = list(self._log)
        end = len(visible) - self._scroll_offset
        start = max(0, end - content_height)
        channel_attr = {
            "log": 0,
            "talk": curses.color_pair(2) if curses.has_colors() else 0,
            "priv": curses.color_pair(3) if curses.has_colors() else 0,
            "system": curses.color_pair(4) if curses.has_colors() else 0,
        }
        for row, (channel, text, stamp) in enumerate(visible[start:end]):
            line = f"[{stamp}] {text}"
            attr = channel_attr.get(channel, 0)
            if text.startswith("("):
                attr |= curses.A_BOLD
            self._safe_addstr(
                stdscr, content_top + row, 0, _truncate(line, log_width - 1), attr
            )
        if self._scroll_offset > 0:
            self._safe_addstr(
                stdscr, content_top, log_width - 8, "[さかのぼり中]",
                curses.A_REVERSE,
            )

        # 地図とリスト
        if map_width:
            lines = self._map_lines()
            if self._list_state is not None:
                lines += self._list_lines(map_width - 1)
            for row, line in enumerate(lines[:content_height]):
                self._safe_addstr(
                    stdscr, content_top + row, log_width,
                    _truncate(line, map_width - 1),
                )

        # 入力欄
        prefix, show_cursor = self._input_prefix()
        self._safe_addstr(stdscr, input_row, 0, _truncate(prefix, width - 1))
        if show_cursor:
            buffer_text = _truncate(
                self._input.buffer, width - _display_width(prefix) - 1
            )
            self._safe_addstr(
                stdscr, input_row, _display_width(prefix), buffer_text
            )
            try:
                stdscr.move(
                    input_row,
                    _display_width(prefix)
                    + _display_width(self._input.buffer[: self._input.cursor]),
                )
                curses.curs_set(1)
            except curses.error:
                pass
        else:
            try:
                curses.curs_set(0)
            except curses.error:
                pass

        # 助けの行
        self._safe_addstr(stdscr, help_row, 0, _truncate(self._help_text(), width - 1))
        stdscr.refresh()

    def _input_prefix(self) -> tuple[str, bool]:
        if self._closed:
            return "[切断] 任意のキーで終了します。", False
        if self._input_state == "confirm":
            first = self._confirm_message.split("\n")[0]
            return f"[確認] {first} (y/n) ", False
        if self._input_state == "ask" and self._ask_action is not None and self._ask_action.ask is not None:
            ask = self._ask_action.ask
            error = f" {self._ask_error}" if self._ask_error else ""
            return f"[{ask.title}] {ask.label}:{error} ", True
        if self._input_state == "editor_multi":
            return f"[看板 {len(self._editor_lines)}行] ", True
        if self._input_state == "editor_single":
            return "[入力] ", True
        if self._input_state == "input":
            return ("*> " if self._loud else "> "), True
        suffix = " (リスト表示中)" if self._list_state is not None else ""
        return f"[操作] Tab=入力 Esc=さかのぼり解除{suffix}", False

    def _help_text(self) -> str:
        if self._input_state == "command":
            return "矢印/テンキー:移動 Z:拾う X:置く C:使う Space:攻撃 T:回転 Shift+T:北固定 PgUp/PgDn:さかのぼる Ctrl+Q:終わる"
        if self._input_state == "input":
            return "Enter:送る Esc:操作へ ↑↓:履歴 /help:命令の一覧"
        if self._input_state in ("editor_single", "editor_multi"):
            return "Enter:次の行へ Esc:取り消す(看板は .! を送る)"
        if self._input_state == "ask":
            return "Enter:答える Esc:やめる"
        if self._input_state == "confirm":
            return "y:はい n:いいえ"
        return ""

    @staticmethod
    def _safe_addstr(stdscr, y: int, x: int, text: str, attr: int = 0) -> None:
        try:
            stdscr.addstr(y, x, text, attr)
        except curses.error:
            pass

    # -- 実行 -------------------------------------------------------------------

    def run(self) -> int:
        if curses is None:
            print(
                "curses が使えません。行単位のクライアントを使ってください:\n"
                "  python -m neophi.cli --host <ホスト> --port <ポート>",
                file=sys.stderr,
            )
            return 2
        self._session_thread = threading.Thread(
            target=self._session_main, daemon=True
        )
        self._session_thread.start()
        self._add_local("サーバーに接続します...")
        _set_locale()

        def _main(stdscr) -> None:
            curses.curs_set(0)
            stdscr.keypad(True)
            stdscr.timeout(50)
            # Ctrl+Q がフロー制御(XON)に取られないようにする
            try:
                import termios

                fd = sys.stdin.fileno()
                attrs = termios.tcgetattr(fd)
                attrs[0] &= ~termios.IXON
                termios.tcsetattr(fd, termios.TCSANOW, attrs)
            except Exception:  # noqa: BLE001 - 出来なくても動く
                pass
            if curses.has_colors():
                curses.start_color()
                curses.use_default_colors()
                try:
                    curses.init_pair(2, curses.COLOR_CYAN, -1)
                    curses.init_pair(3, curses.COLOR_MAGENTA, -1)
                    curses.init_pair(4, curses.COLOR_YELLOW, -1)
                except curses.error:
                    pass
            while not self._should_exit:
                self._drain_events()
                self._render(stdscr)
                press = self._read_key(stdscr)
                if press is None:
                    continue
                if self._closed and not self._exiting:
                    self._should_exit = True
                    break
                if press.kind == "resize":
                    continue
                # どの状態でも Ctrl+Q / Ctrl+C で終わる
                if press.ctrl and press.code in ("KeyQ", "KeyC"):
                    self._request_disconnect(graceful=True)
                    continue
                if self._input_state == "command":
                    self._handle_command_key(press)
                elif self._input_state == "input":
                    self._handle_input_key(press)
                elif self._input_state == "ask":
                    self._handle_ask_key(press)
                elif self._input_state == "confirm":
                    self._handle_confirm_key(press)
                elif self._input_state in ("editor_single", "editor_multi"):
                    self._handle_editor_key(press)

        try:
            curses.wrapper(_main)
        except KeyboardInterrupt:
            self._request_disconnect(graceful=True)
        if self._session_thread is not None:
            self._session_thread.join(timeout=5.0)
        return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="NeoPHI の TUI クライアント")
    parser.add_argument("--host", required=True, help="サーバのホスト")
    parser.add_argument("--port", required=True, type=int, help="サーバのポート")
    parser.add_argument("--id", dest="char_id", default=None,
                        help="キャラID(省略時は PHI_ID か入力で指定)")
    parser.add_argument("--record-dir", default=None,
                        help="受信した生のバイト列を書くフォルダ(開発用)")
    parser.add_argument("--no-auto-unequip", dest="auto_unequip",
                        action="store_false",
                        help="系統魔法の前に武器を外さない(既定では外す)")
    parser.add_argument("--auto-equip", action="store_true",
                        help="系統魔法の後に武器を装備し直す(既定では直さない)")
    args = parser.parse_args(argv)
    char_id = args.char_id or os.environ.get("PHI_ID")
    if not char_id:
        char_id = getpass.getpass("キャラID: ")
    if not char_id:
        print("キャラIDが必要です。", file=sys.stderr)
        return 2
    return _TUI(args.host, args.port, char_id, record_dir=args.record_dir,
                auto_unequip=args.auto_unequip, auto_equip=args.auto_equip).run()


if __name__ == "__main__":
    sys.exit(main())
