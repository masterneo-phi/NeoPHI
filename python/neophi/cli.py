"""行単位のクライアント。curses が使えない環境でも動く。

受信した出来事をそのまま出し、打った行をそのまま送る。移動は ``go N`` の
ように打つ。TUI(``neophi.tui``)が本命で、こちらは確認と予備の用途。

使い方::

    python -m neophi.cli --host 127.0.0.1 --port 21000
    python -m neophi.cli --host <ホスト> --port <ポート> --id <キャラID>

行の頭が ``/`` のものはクライアント内の命令(``/help`` で一覧)。それ以外は
サーバへ送る。
"""

from __future__ import annotations

import argparse
import asyncio
import getpass
import os
import queue
import sys
import threading
import time
from dataclasses import dataclass, field

from .list_state import ListFlow, ListState, add_page, list_no, more_no, receive_list
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

__all__ = ["main", "prepare_line"]

HELP = """\
命令(行の頭に / を付ける):
  /help            この一覧を出す
  /quit            #x を送って切断して終わる
  /force           #x を送らずに切断して終わる
  /loud [on|off]   大声モードの切り替え(今の状態を出すだけなら引数なし)
  /ulist           接続者の一覧を頼む
  /map             地図を取り直す(#map)
  /status          最後に届いた状態と地図を出し直す
それ以外は、そのままサーバへ送ります。
"""


def prepare_line(text: str, *, loud: bool) -> str | None:
    """入力欄の行を送る形にする。送らない時は None。仕様書 §11。

    空の行は送らない。大声モードなら頭に ``*`` を付ける。大声モードでない
    のに ``*`` で始まる行は、頭に ``/**/`` を付けて大声にしない。
    """
    if text == "":
        return None
    if loud:
        return f"*{text}"
    if text.startswith("*"):
        return f"/**/{text}"
    return text


def board_lines(lines: list[str]) -> list[str]:
    """看板の送る行。空の行は空白1つにし、最後に ``.`` を足す。"""
    return [(line if line != "" else " ") for line in lines] + ["."]


@dataclass
class _State:
    status: StatusEvent | None = None
    cond: CondEvent | None = None
    map_event: MapEvent | None = None
    users: list[str] = field(default_factory=list)
    list_state: ListState | None = None
    list_flow: ListFlow = field(default_factory=ListFlow)
    editor: str | None = None  # "single" | "multi" | None
    editor_lines: list[str] = field(default_factory=list)
    loud: bool = False
    transfer_confirm: tuple[str, int] | None = None
    last_status_key: tuple | None = None
    last_cond: CondEvent | None = None
    last_mode: ModeEvent | None = None


def _stamp() -> str:
    return time.strftime("%H:%M:%S")


def _print(text: str) -> None:
    print(text, flush=True)


def _print_status(state: _State, event: StatusEvent) -> None:
    state.status = event
    key = (event.name, event.hp, event.max_hp, event.mp, event.max_mp, event.exp, event.gp)
    if key == state.last_status_key:
        return
    state.last_status_key = key
    parts = []
    if event.name:
        parts.append(event.name)
    if event.hp is not None:
        parts.append(f"HP {event.hp}/{event.max_hp}")
    if event.mp is not None:
        parts.append(f"MP {event.mp}/{event.max_mp}")
    if event.exp is not None:
        parts.append(f"Exp {event.exp}")
    if event.gp is not None:
        parts.append(f"GP {event.gp}")
    if parts:
        _print(f"[{_stamp()}] [状態] {' '.join(parts)}")


_COND_NAMES = ["毒", "麻痺", "恐慌", "混乱", "狂戦士", "沈黙", "盲目"]


def _print_cond(state: _State, event: CondEvent) -> None:
    if event == state.last_cond:
        return
    state.last_cond = event
    flags = [event.poison, event.palsy, event.panic, event.confuse,
             event.berserk, event.silence, event.blind]
    active = [name for name, on in zip(_COND_NAMES, flags) if on]
    _print(f"[{_stamp()}] [状態異常] {' '.join(active) if active else 'なし'}")


def _print_mode(state: _State, event: ModeEvent) -> None:
    prev = state.last_mode
    state.last_mode = event
    if prev is None:
        return
    if event.attack != prev.attack:
        _print(f"[{_stamp()}] [戦闘] {'開始' if event.attack else '終了'}")
    if event.magic != prev.magic:
        _print(f"[{_stamp()}] [魔法] {'選択中' if event.magic else '終了'}")


def _print_list(state: _State, list_state: ListState) -> None:
    state.list_state = list_state
    _print(f"[{_stamp()}] [リスト]")
    for i, line in enumerate(list_state.lines):
        number = list_state.start + i + 1
        mark = ">" if i == list_state.cursor else " "
        check = "x" if list_state.checked[i] else " "
        _print(f"  {mark}[{check}] ({number}) {plain_text(line)}")
    _print("  番号を打って選びます。'.' で取り消し、'-' ですべて。")


async def _handle_event(state: _State, session: PhiSession, event) -> bool:
    """イベントを出し、終わったら True を返す。"""
    if isinstance(event, MessageEvent):
        for line in plain_text(event.text).split("\n"):
            tag = {"log": "", "talk": "[発言] ", "priv": "[priv] ",
                   "system": "[案内] "}.get(event.channel, "")
            _print(f"[{_stamp()}] {tag}{line}")
    elif isinstance(event, StatusEvent):
        _print_status(state, event)
    elif isinstance(event, CondEvent):
        _print_cond(state, event)
    elif isinstance(event, MapEvent):
        state.map_event = event
        for line in render_map(event):
            _print(line)
    elif isinstance(event, EagleEyeEvent):
        for line in render_eagle_eye(event):
            _print(line)
    elif isinstance(event, ListEvent):
        result = receive_list(state.list_flow, event.active, event.lines, state.list_state)
        if result == "close":
            state.list_state = None
        elif isinstance(result, ListState):
            _print_list(state, result)
    elif isinstance(event, EditEvent):
        if event.mode == "single":
            state.editor = "single"
            _print(f"[{_stamp()}] [入力] 1行の答えを打ってください。")
        elif event.mode == "multi":
            state.editor = "multi"
            state.editor_lines = []
            _print(f"[{_stamp()}] [看板] 本文を打ってください。'.' だけの行で終わり、'.!' で取り消し。")
        else:
            state.editor = None
            state.editor_lines = []
            _print(f"[{_stamp()}] [エディタ] 閉じました。")
    elif isinstance(event, NoticeEvent):
        parts = []
        if event.name:
            parts.append(f"名前={event.name}")
        if event.world:
            parts.append(f"世界={event.world}")
        if event.area:
            parts.append(f"地域={event.area}")
        if event.mapset:
            parts.append(f"マップセット={event.mapset}")
        if parts:
            _print(f"[{_stamp()}] [お知らせ] {' '.join(parts)}")
    elif isinstance(event, ModeEvent):
        _print_mode(state, event)
    elif isinstance(event, UserListEvent):
        state.users = [u.name for u in event.users]
        _print(f"[{_stamp()}] [接続者] {', '.join(state.users)}")
    elif isinstance(event, TransferConfirmEvent):
        state.transfer_confirm = (event.host, event.port)
        _print(f"[{_stamp()}] [世界移動] 別のホスト {event.host}:{event.port} へ"
               "キャラIDを送って移動しますか？ (y/n)")
    elif isinstance(event, ConnectionEvent):
        _print(f"[{_stamp()}] サーバーから切断されました。")
    elif isinstance(event, SessionErrorEvent):
        _print(f"[{_stamp()}] [エラー] {event.message}")
    elif isinstance(event, SessionClosedEvent):
        _print("--- 切断しました ---")
        return True
    return False


def _start_stdin_reader() -> queue.Queue[str | None]:
    """標準入力を読むデーモンスレッドを立てる。EOF なら None を入れる。"""
    input_queue: queue.Queue[str | None] = queue.Queue()

    def _reader() -> None:
        while True:
            try:
                line = sys.stdin.readline()
            except (OSError, ValueError):
                line = ""
            if not line:
                input_queue.put(None)
                return
            input_queue.put(line.rstrip("\n").rstrip("\r"))

    threading.Thread(target=_reader, daemon=True).start()
    return input_queue


async def _run(host: str, port: int, char_id: str, record_dir: str | None) -> int:
    _print("サーバーに接続します...")
    session = PhiSession(host, port, char_id, record_dir=record_dir)
    state = _State()
    session_task = asyncio.create_task(session.run())
    input_queue = _start_stdin_reader()
    input_closed = False
    try:
        while True:
            try:
                event = await asyncio.wait_for(session.events.get(), timeout=0.05)
            except TimeoutError:
                event = None
            if event is not None and await _handle_event(state, session, event):
                break
            if not input_closed:
                while True:
                    try:
                        item = input_queue.get_nowait()
                    except queue.Empty:
                        break
                    if item is None:
                        input_closed = True
                        await session.disconnect(graceful=True)
                        break
                    await _handle_input(state, session, item)
            if session_task.done():
                while not session.events.empty():
                    item = session.events.get_nowait()
                    await _handle_event(state, session, item)
                break
    finally:
        if not session_task.done():
            session_task.cancel()
            await asyncio.gather(session_task, return_exceptions=True)
    return 0


async def _handle_input(state: _State, session: PhiSession, line: str) -> bool:
    """打った行を処理する。終わる時は True(切断は頼み済み)。"""
    if state.transfer_confirm is not None:
        state.transfer_confirm = None
        answer = TRANSFER_YES if line.strip().lower() in ("y", "yes") else TRANSFER_NO
        await session.send(answer)
        return False
    if state.editor == "multi":
        if line == ".":
            await session.send_lines(board_lines(state.editor_lines))
            state.editor = None
            state.editor_lines = []
        elif line == ".!":
            await session.send(".!")
            state.editor = None
            state.editor_lines = []
        else:
            state.editor_lines.append(line)
        return False
    if state.editor == "single":
        await session.send(line if line != "" else " ")
        state.editor = None
        return False

    if line.startswith("/"):
        parts = line[1:].split()
        cmd = parts[0] if parts else ""
        if cmd in ("quit", "q"):
            await session.disconnect(graceful=True)
            return True
        if cmd == "force":
            await session.disconnect(graceful=False)
            return True
        if cmd == "help":
            _print(HELP.rstrip("\n"))
            return False
        if cmd == "loud":
            if len(parts) >= 2:
                if parts[1] == "on" and not state.loud:
                    _print("大声で発言します。この世界にいる全員に聞こえます。")
                state.loud = parts[1] == "on"
            _print(f"大声モード: {'on' if state.loud else 'off'}")
            return False
        if cmd == "ulist":
            await session.send("#ulist")
            return False
        if cmd == "map":
            await session.send("#map")
            return False
        if cmd == "status":
            if state.status is not None:
                state.last_status_key = None
                _print_status(state, state.status)
            if state.map_event is not None:
                for text in render_map(state.map_event):
                    _print(text)
            return False
        _print(f"知らない命令です: /{cmd} (/help で一覧)")
        return False

    if state.list_state is not None:
        stripped = line.strip()
        if stripped in (".", "-") or all(
            part.isdigit() for part in stripped.split()
        ) and stripped:
            await session.send(stripped)
            # 続きのページを頼んだ時はリストを開いたままにする
            if stripped != more_no(state.list_state):
                await session.close_list()
                state.list_state = None
            else:
                state.list_state.waiting = True
            return False
        # リストの間に打った文字のキーは、そのまま送る(リストは取り消される)
        await session.send(line)
        await session.close_list()
        state.list_state = None
        return False

    prepared = prepare_line(line, loud=state.loud)
    if prepared is not None:
        await session.send(prepared)
    return False


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="NeoPHI の行単位クライアント")
    parser.add_argument("--host", required=True, help="サーバのホスト")
    parser.add_argument("--port", required=True, type=int, help="サーバのポート")
    parser.add_argument("--id", dest="char_id", default=None,
                        help="キャラID(省略時は PHI_ID か入力で指定)")
    parser.add_argument("--record-dir", default=None,
                        help="受信した生のバイト列を書くフォルダ(開発用)")
    args = parser.parse_args(argv)
    char_id = args.char_id or os.environ.get("PHI_ID")
    if not char_id:
        char_id = getpass.getpass("キャラID: ")
    if not char_id:
        print("キャラIDが必要です。", file=sys.stderr)
        return 2
    try:
        return asyncio.run(_run(args.host, args.port, char_id, args.record_dir))
    except KeyboardInterrupt:
        print("\n--- 切断しました ---", flush=True)
        return 0


if __name__ == "__main__":
    sys.exit(main())
