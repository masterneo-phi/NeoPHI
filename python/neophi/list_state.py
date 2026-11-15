"""リスト(``#list`` 〜 ``#end-list``)の番号の扱い。仕様書 §6 と wphi の list.ts。

サーバは続きのページを前のページの続きの番号で送る。1ページ目が 1〜9 なら
2ページ目は 9〜17。画面の番号(1〜9)にページの先頭のずれを足した番号を送る。
続きのページは前のページの下に足していく。
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field

from .tags import strip_tags

__all__ = ["ListFlow", "ListState", "add_page", "has_more", "list_no", "list_ok", "more_no", "move_list_cursor", "new_list", "page_top", "receive_list"]

_NUMBER_RE = re.compile(r"[0-9]+")


@dataclass
class ListState:
    """溜めた全部の行。前のページの行も残す。"""

    lines: list[str] = field(default_factory=list)
    checked: list[bool] = field(default_factory=list)
    cursor: int = 0
    #: 今のページの先頭の行の番号 - 1
    offset: int = 0
    #: 溜めた先頭の行の番号 - 1。溜めた中の i 番目の行の番号は start + i + 1
    start: int = 0
    #: 続きのページを頼んで、届くのを待っている。待つ間は 9 を受け付けない
    waiting: bool = False


def new_list(lines: list[str]) -> ListState:
    """届いたページからリストを作る。ずれは先頭の行の最初の数から取る。"""
    first_text = strip_tags(lines[0]) if lines else ""
    match = _NUMBER_RE.search(first_text)
    offset = max(int(match.group(0)) - 1, 0) if match else 0
    return ListState(
        lines=list(lines), checked=[False] * len(lines),
        cursor=0, offset=offset, start=offset,
    )


def add_page(prev: ListState | None, lines: list[str]) -> ListState:
    """届いたページを、前のリストの続きなら下に足す。

    前のリストの最後の行(9 番目の「続き」)は除く。続きでなければ新しい
    リストにする。
    """
    page = new_list(lines)
    if prev is None or not prev.lines:
        return page
    if page.offset + 1 != prev.start + len(prev.lines):
        return page
    kept = len(prev.lines) - 1
    return ListState(
        lines=[*prev.lines[:kept], *lines],
        checked=[*prev.checked[:kept], *[False] * len(lines)],
        cursor=kept, offset=page.offset, start=prev.start,
    )


def page_top(state: ListState) -> int:
    """今のページの先頭の行の、溜めた中の位置。"""
    return state.offset - state.start


def _page_count(state: ListState) -> int:
    return len(state.lines) - page_top(state)


def has_more(state: ListState) -> bool:
    """9 件目は続きのページの印。"""
    return _page_count(state) >= 9


def more_no(state: ListState) -> str:
    """続きのページを頼む番号。"""
    return str(state.offset + 9)


def list_ok(state: ListState) -> str:
    """チェックした番号を空白区切りで。無ければカーソルの行の番号。"""
    nos = [str(state.start + i + 1) for i, c in enumerate(state.checked) if c]
    return " ".join(nos) if nos else str(state.start + state.cursor + 1)


def list_no(state: ListState, n: int) -> tuple[str, bool] | None:
    """番号キー n(1〜9)を押した時。``(送る番号, 送った後に閉じるか)``。

    9 は続きのページで、続きが無ければ何もしない。範囲外の番号は取り消し
    (``.``)にする。WPHI と同じく、範囲外を OK にして1番を送る事はしない。
    """
    if n == 9:
        if has_more(state) and not state.waiting:
            return more_no(state), False
        return None
    if n > _page_count(state):
        return ".", True
    return str(state.offset + n), True


def move_list_cursor(state: ListState, *, cursor_delta: int = 0, toggle: bool = False) -> ListState:
    """カーソルを動かすか、カーソルの行のチェックを切り替えて次の行へ進む。"""
    last = max(len(state.lines) - 1, 0)
    checked = list(state.checked)
    cursor = state.cursor
    if toggle:
        if 0 <= cursor < len(checked):
            checked[cursor] = not checked[cursor]
        cursor = min(cursor + 1, last)
    else:
        cursor = min(max(cursor + cursor_delta, 0), last)
    return ListState(
        lines=list(state.lines), checked=checked, cursor=cursor,
        offset=state.offset, start=state.start, waiting=state.waiting,
    )


@dataclass
class ListFlow:
    """リストの受信の状態。``cancel`` は次に届くリストを出さない数。"""

    cancel: int = 0
    started: bool = False


def receive_list(
    flow: ListFlow, active: bool, lines: list[str] | None, prev: ListState | None = None
) -> ListState | str | None:
    """list イベントを受けた時。

    ``#list`` と ``#end-list`` はどちらも active で届くので、交互に来る事で
    見分ける。出すリストか、閉じる(``"close"``)か、何もしない(None)を返す。
    """
    if not active:
        flow.started = False
        return "close"
    if not flow.started:
        flow.started = True
        return None
    flow.started = False
    cancel = flow.cancel > 0
    if cancel:
        flow.cancel -= 1
    if not lines or cancel:
        return None
    return add_page(prev, lines)
