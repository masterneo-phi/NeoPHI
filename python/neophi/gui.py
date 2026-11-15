"""Tkinter の GUI クライアント。BMP の絵で地図を描きます。

画面は、道具の行・状態の行・地図・ログ・リスト・入力欄です。地図は
``map_graphics`` で画素列に描き、PNG にして Tkinter に渡します。
セッションは別のスレッドで動かし、出来事をキューで受け取ります
(TUI と同じ橋渡しです)。Tkinter はメインスレッドで動かす必要があります。

キー操作は Philly と同じです。地図にフォーカスがある時はキーが操作に
なり、入力欄にフォーカスがある時は文字が打てます。地図のクリックでも
移動できます(左が移動、右が攻撃)。表示ボタンで、平面・傾け・斜め・立体
(クオータービュー)の見方を切り替えられます。
"""

from __future__ import annotations

import argparse
import asyncio
import base64
import getpass
import math
import os
import queue
import random
import sys
import threading
import time
from pathlib import Path

try:
    import tkinter as tk
    import tkinter.font as tkfont
    from tkinter import messagebox, simpledialog
except ImportError:  # tkinter が無い環境
    tk = None  # type: ignore[assignment]
    tkfont = None  # type: ignore[assignment]

from .assets import Assets
from .bmp import fade_alpha
from .bubbles import (
    bubble_body,
    bubble_from_action_line,
    bubble_from_log_line,
    bubble_outline,
    place_bubble_rect,
    wrap_bubble_lines,
)
from .cli import board_lines, prepare_line
from .combat_fx import (
    CasterTracker,
    CombatEvent,
    comet_tail_points,
    parse_attack,
    parse_chant,
    parse_chant_stop,
    parse_kill,
    radial_spark_points,
    slash_points,
    streak_points,
)
from .float_text import parse_floats
from .keys import KeyAction, key_action, list_key_action, move_command, move_input
from .list_state import (
    ListFlow,
    ListState,
    list_no,
    list_ok,
    move_list_cursor,
    receive_list,
)
from .map_graphics import MAP_TOP, eagle_board, grid_dim, render_map_image
from .map_quarter import PRESETS, quarter_geometry, quarter_pick, render_quarter_image
from .mouse import mouse_dir, north_fix_turn
from .parser import (
    Chara,
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
from .png import encode_png
from .session import (
    TRANSFER_NO,
    TRANSFER_YES,
    PhiSession,
    SessionClosedEvent,
    SessionErrorEvent,
    TransferConfirmEvent,
)
from .tags import plain_text, strip_tags

__all__ = ["main"]

# Philly のキャラのアニメ周期(500ms)。
_ANIMATION_MS = 500
# フロート表示: 上げる回数と間隔、試し表示の間隔
_FLOAT_STEPS = 30
_FLOAT_STEP_MS = 30
_FLOAT_DEMO_MS = 2500
#: フロートの数字の色(種類ごと)
_FLOAT_COLORS = {
    "dealt": "#FFD23F",
    "taken": "#FF5252",
    "heal": "#69F0AE",
    "mp": "#4FC3F7",
    "mpdmg": "#4FC3F7",
}
# 吹き出し: 本文の幅(地図の絵の座標)、行数、表示時間
_BUBBLE_MAX_WIDTH = 132
_BUBBLE_MAX_LINES = 3
_BUBBLE_BASE_MS = 2500
_BUBBLE_PER_CHAR_MS = 60
_BUBBLE_MAX_MS = 8000
# 戦闘の演出: 剣の軌跡のコマ数と間隔、魔法弾の歩数と間隔、着弾の輪の広がり
_SLASH_FRAMES = 5
_SLASH_FRAME_MS = 36
_SLASH_COLORS = ("white", "white", "#E3F2FD", "#BBDEFB", "#90CAF9")
# 斬撃の軌跡: コマ数と間隔、振り始めの向きと振る角度、風切りの線
# (円の半径、後れ、太さ)。白い主線の後を、青い線が追います。
_SWING_FRAMES = 6
_SWING_FRAME_MS = 30
_SWING_COLORS = ("white", "#E3F2FD", "#BBDEFB", "#90CAF9", "#64B5F6", "#42A5F5")
_SWING_START = -1.9
_SWING_SWEEP = 2.6
_SWING_STREAKS = ((21.0, 0.0, 3.0), (16.0, 0.3, 2.0), (25.0, 0.55, 1.5))
# 倒れたキャラの消滅: 段階の数と間隔
_GHOST_STEPS = 8
_GHOST_STEP_MS = 80
_BOLT_STEPS = 10
_BOLT_STEP_MS = 28
_BOLT_COLOR = "#4FC3F7"
_BOLT_TAIL_LEN = 42.0
_BOLT_TAIL_WIDTH = 7.0
_BOLT_ORBIT_R = 7.0
_BOLT_ORBIT_STEP = 1.1
# 着弾: コマ数と間隔、火花の数
_IMPACT_FRAMES = 6
_IMPACT_FRAME_MS = 30
_IMPACT_COLORS = ("white", "#E1F5FE", "#B3E5FC", "#81D4FA", "#4FC3F7", "#29B6F6")
_IMPACT_SPARKS = 8
# 試し表示で吹き出しに出す言葉
_BUBBLE_DEMO_PHRASES = (
    "こんにちは",
    "いらっしゃい",
    "今日はいい天気だね",
    "一緒に冒険しない？",
    "この先の洞窟には強いモンスターがいるから気をつけてね",
)
# 出来事の確認の間隔。
_PUMP_MS = 30

_DIR_NAMES = {0: "N", 2: "E", 4: "S", 6: "W"}

# 地図の見方の表示名。表示ボタンと /view で切り替えます
_VIEW_LABELS = {"flat": "平面", "tilt": "傾け", "oblique": "斜め", "iso": "立体"}
_VIEW_ORDER = ["flat", "tilt", "oblique", "iso"]

# Tk の keysym → WPHI のコード名。
_KEYSYMS: dict[str, str] = {
    "Up": "ArrowUp", "Down": "ArrowDown", "Left": "ArrowLeft", "Right": "ArrowRight",
    "KP_0": "Numpad0", "KP_1": "Numpad1", "KP_2": "Numpad2", "KP_3": "Numpad3",
    "KP_4": "Numpad4", "KP_5": "Numpad5", "KP_6": "Numpad6", "KP_7": "Numpad7",
    "KP_8": "Numpad8", "KP_9": "Numpad9", "KP_Begin": "Numpad5",
    "KP_Add": "NumpadAdd", "KP_Subtract": "NumpadSubtract",
    "KP_Divide": "NumpadDivide", "KP_Multiply": "NumpadMultiply",
    "KP_Decimal": "NumpadDecimal", "KP_Enter": "NumpadEnter",
    "KP_Insert": "Numpad0", "KP_End": "Numpad1", "KP_Next": "Numpad3",
    "KP_Home": "Numpad7", "KP_Prior": "Numpad9",
    "Prior": "PageUp", "Next": "PageDown", "Home": "Home", "End": "End",
    "BackSpace": "Backspace", "Delete": "Delete", "Escape": "Escape",
    "Return": "Enter", "Tab": "Tab", "space": "Space",
    "period": "Period", "minus": "Minus", "equal": "Equal",
    "semicolon": "Semicolon", "slash": "Slash", "apostrophe": "Quote",
    "quoteright": "Quote", "bracketleft": "BracketLeft",
    "bracketright": "BracketRight", "backslash": "Backslash",
    "grave": "Backquote", "comma": "Comma",
    # Shift を押した時の記号は、元のキーに戻す
    "exclam": "Digit1", "at": "Digit2", "numbersign": "Digit3",
    "dollar": "Digit4", "percent": "Digit5", "asciicircum": "Digit6",
    "ampersand": "Digit7", "asterisk": "Digit8", "parenleft": "Digit9",
    "parenright": "Digit0", "underscore": "Minus", "plus": "Equal",
    "colon": "Semicolon", "question": "Slash", "quotedbl": "Quote",
    "braceleft": "BracketLeft", "braceright": "BracketRight",
    "bar": "Backslash", "asciitilde": "Backquote", "less": "Comma",
    "greater": "Period",
}
for _n in range(1, 13):
    _KEYSYMS[f"F{_n}"] = f"F{_n}"

# mouseDir のカーソル名 → Tk のカーソル名。
_CURSORS: dict[str, str] = {
    "n-resize": "top_side", "s-resize": "bottom_side",
    "w-resize": "left_side", "e-resize": "right_side",
    "nw-resize": "top_left_corner", "ne-resize": "top_right_corner",
    "sw-resize": "bottom_left_corner", "se-resize": "bottom_right_corner",
}

_HELP_TEXT = [
    "入力欄の命令: /help /quit /force /loud /ulist /map /status /zoom /view",
    "地図にフォーカスがある時、矢印キーで移動、Tab で入力欄へ。",
    "地図の左クリックで移動、右クリックで攻撃。Shift+クリック(北固定)は向く。",
    "/view で地図の見方を切り替えます(平面/傾け/斜め/立体)。",
]


def _keysym_to_code(keysym: str) -> str | None:
    if keysym in _KEYSYMS:
        return _KEYSYMS[keysym]
    if len(keysym) == 1 and keysym.isalpha() and keysym.isascii():
        return f"Key{keysym.upper()}"
    if len(keysym) == 1 and keysym.isdigit():
        return f"Digit{keysym}"
    return None


class _GUI:
    def __init__(
        self,
        host: str,
        port: int,
        char_id: str,
        *,
        assets_dirs: list[str],
        skin: str = "Mine",
        record_dir: str | None = None,
        zoom: int = 2,
        auto_quit: float | None = None,
        snapshot: str | None = None,
        view_mode: str = "flat",
        float_demo: bool = False,
        auto_unequip: bool = True,
        auto_equip: bool = False,
    ) -> None:
        self._session = PhiSession(
            host, port, char_id, record_dir=record_dir,
            auto_unequip=auto_unequip, auto_equip=auto_equip,
        )
        self._assets = Assets(assets_dirs, skin=skin)
        self._loop: asyncio.AbstractEventLoop | None = None
        self._loop_ready = threading.Event()
        self._event_queue: queue.Queue = queue.Queue()
        self._session_thread: threading.Thread | None = None

        self._status: StatusEvent | None = None
        self._cond: CondEvent | None = None
        self._map: MapEvent | None = None
        self._eagle: EagleEyeEvent | None = None
        self._name = ""
        self._world = ""
        self._area = ""
        self._mapset = ""
        self._defines: dict[int, str] = {}
        self._users: list[str] = []
        self._mode: ModeEvent | None = None
        self._list_state: ListState | None = None
        self._list_flow = ListFlow()
        self._map_visible = True

        # 入力の状態: command | editor_single | editor_multi
        # (通常の入力は Entry にフォーカスがあるかどうかで見分けます)
        self._editor_state: str | None = None
        self._editor_lines: list[str] = []
        self._loud = False
        self._loud_warned = False
        self._history: list[str] = []
        self._history_index = 0

        self._zoom = max(1, min(3, zoom))
        self._anim_frame = 0
        self._map_photo = None
        self._map_photo_zoomed = None
        self._eagle_photo = None
        self._eagle_photo_zoomed = None
        self._eagle_window = None
        self._eagle_canvas = None
        self._eagle_image_item = None
        self._fonts: dict[tuple[int, str], object] = {}
        self._snapshot = snapshot
        self._snapshot_done = False
        self._auto_quit = auto_quit
        self._last_turn: str | None = None
        self._view_mode = view_mode if view_mode in _VIEW_LABELS else "flat"
        self._map_geom: tuple[int, int] | None = None  # クオータービューの原点
        self._view_button = None
        self._float_demo = float_demo
        self._anchors: dict[str, tuple[int, int]] = {}
        self._center_anchor: tuple[int, int] | None = None
        # 倒れたキャラの残像と、ひとつ前の地図のキャラ(消えた人の分を残します)
        self._ghosts: list[dict] = []
        self._ghost_tick_active = False
        self._last_charas: dict[str, Chara] = {}
        self._prev_charas: dict[str, Chara] = {}
        self._float_seq = 0
        # 吹き出しの状態: 話し手の名前 -> 本文・世代・描いた部品
        self._bubbles: dict[str, dict] = {}
        self._bubble_gen = 0
        # 詠唱を始めた人の記録(物理攻撃と魔法攻撃の見分けに使います)
        self._caster_tracker = CasterTracker()
        # ダメージ演出の状態
        self._shake_active = False
        self._shake_step = 0
        self._shake_offset = (0, 0)

        self._closed = False
        self._exiting = False
        self._root: tk.Tk | None = None

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
        if self._closed:
            return
        self._exiting = True
        self._submit(self._session.disconnect(graceful=graceful))
        # 切断の知らせが来なくても、3秒後には窓を閉じます
        if self._root is not None:
            self._root.after(3000, self._destroy_if_exiting)

    def _destroy_if_exiting(self) -> None:
        if self._exiting and self._root is not None:
            try:
                self._root.destroy()
            except tk.TclError:
                pass

    # -- 画面 -----------------------------------------------------------------

    def run(self) -> int:
        root = tk.Tk()
        self._root = root
        root.title("NeoPHI")
        root.protocol("WM_DELETE_WINDOW", self._on_close)

        toolbar = tk.Frame(root)
        toolbar.pack(fill=tk.X)
        tk.Button(toolbar, text="拡大", command=self._cycle_zoom).pack(side=tk.LEFT)
        self._view_button = tk.Button(
            toolbar, text=f"表示: {_VIEW_LABELS[self._view_mode]}",
            command=self._cycle_view,
        )
        self._view_button.pack(side=tk.LEFT)
        tk.Button(toolbar, text="地図", command=self._toggle_map).pack(side=tk.LEFT)
        tk.Button(toolbar, text="終了", command=self._on_close).pack(side=tk.LEFT)
        self._status_label = tk.Label(toolbar, text="", anchor=tk.W)
        self._status_label.pack(side=tk.LEFT, fill=tk.X, expand=True)

        main = tk.Frame(root)
        main.pack(fill=tk.BOTH, expand=True)
        self._map_frame = tk.Frame(main)
        self._map_frame.pack(side=tk.LEFT, fill=tk.Y)
        self._canvas = tk.Canvas(self._map_frame, width=224, height=240, bg="black",
                                 highlightthickness=0)
        self._canvas.pack()
        self._canvas_image = self._canvas.create_image(0, 0, anchor=tk.NW)
        self._canvas.bind("<Button-1>", self._on_map_click)
        self._canvas.bind("<Button-2>", self._on_map_right_click)
        self._canvas.bind("<Button-3>", self._on_map_right_click)
        self._canvas.bind("<Motion>", self._on_map_motion)
        self._canvas.bind("<FocusIn>", lambda e: self._update_status())
        self._canvas.focus_set()

        log_frame = tk.Frame(main)
        log_frame.pack(side=tk.LEFT, fill=tk.BOTH, expand=True)
        self._log = tk.Text(log_frame, bg="black", fg="white", state=tk.DISABLED,
                            wrap=tk.WORD, width=60)
        self._log.pack(side=tk.LEFT, fill=tk.BOTH, expand=True)
        scrollbar = tk.Scrollbar(log_frame, command=self._log.yview)
        scrollbar.pack(side=tk.RIGHT, fill=tk.Y)
        self._log.config(yscrollcommand=scrollbar.set)
        self._log.tag_config("priv", foreground="#ff9fff")
        self._log.tag_config("talk", foreground="#9fff9f")
        self._log.tag_config("system", foreground="#ffff9f")
        self._log.tag_config("list", foreground="#9fdfff")

        self._list_frame = tk.Frame(root)
        self._listbox = tk.Listbox(self._list_frame, height=9)
        self._listbox.pack(fill=tk.X)
        self._listbox.bind("<Button-1>", self._on_list_click)
        self._listbox.bind("<Double-Button-1>", self._on_list_pick)

        entry_frame = tk.Frame(root)
        entry_frame.pack(fill=tk.X)
        tk.Label(entry_frame, text=">").pack(side=tk.LEFT)
        self._entry = tk.Entry(entry_frame)
        self._entry.pack(side=tk.LEFT, fill=tk.X, expand=True)
        self._entry.bind("<Return>", self._on_entry_return)
        self._entry.bind("<Escape>", self._on_entry_escape)
        self._entry.bind("<Up>", self._on_entry_history_prev)
        self._entry.bind("<Down>", self._on_entry_history_next)

        root.bind_all("<KeyPress>", self._on_key)
        root.after(_PUMP_MS, self._pump)
        root.after(_ANIMATION_MS, self._anim_tick)
        if self._float_demo:
            root.after(2000, self._float_demo_tick)
        if self._auto_quit is not None:
            root.after(int(self._auto_quit * 1000),
                       lambda: self._request_disconnect(graceful=True))

        self._add_log("system", "サーバーに接続します...")
        if self._assets.chip("") is None and self._assets.items() is None:
            self._add_log(
                "system",
                "グラフィックスが見つかりません。--assets-dir で Philly の "
                "フォルダを指定すると、絵の地図になります。",
            )
        self._session_thread = threading.Thread(
            target=self._session_main, daemon=True
        )
        self._session_thread.start()
        try:
            root.mainloop()
        except KeyboardInterrupt:
            self._request_disconnect(graceful=True)
        return 0

    def _on_close(self) -> None:
        if self._closed:
            self._destroy_if_exiting()
            return
        self._request_disconnect(graceful=True)

    def _cycle_zoom(self) -> None:
        self._zoom = self._zoom % 3 + 1
        self._redraw_map()
        self._redraw_eagle()

    def _set_view(self, mode: str) -> None:
        if mode not in _VIEW_LABELS:
            return
        self._view_mode = mode
        if self._view_button is not None:
            self._view_button.config(text=f"表示: {_VIEW_LABELS[mode]}")
        self._redraw_map()
        self._update_status()

    def _cycle_view(self) -> None:
        index = _VIEW_ORDER.index(self._view_mode)
        self._set_view(_VIEW_ORDER[(index + 1) % len(_VIEW_ORDER)])

    def _toggle_map(self) -> None:
        self._map_visible = not self._map_visible
        if self._map_visible:
            self._map_frame.pack(side=tk.LEFT, fill=tk.Y, before=self._log.master)
        else:
            self._map_frame.pack_forget()

    # -- ログと状態 -------------------------------------------------------------

    def _add_log(self, channel: str, text: str) -> None:
        stamp = time.strftime("%H:%M")
        at_bottom = self._log.yview()[1] >= 0.999
        self._log.config(state=tk.NORMAL)
        for line in text.split("\n"):
            self._log.insert(tk.END, f"[{stamp}] {line}\n", channel)
        self._log.config(state=tk.DISABLED)
        if at_bottom:
            self._log.see(tk.END)

    def _add_local(self, text: str) -> None:
        self._add_log("system", text)

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
        if self._map is not None:
            direction = _DIR_NAMES.get(self._map.dir, "?")
            parts.append(f"地図 {self._map.size}x{self._map.size} 向き={direction}")
            parts.append(f"表示 {_VIEW_LABELS[self._view_mode]}")
        if self._mode is not None:
            tags = []
            if self._mode.attack:
                tags.append("戦闘")
            if self._mode.magic:
                tags.append("魔法")
            if tags:
                parts.append(" ".join(tags))
        if self._list_state is not None:
            parts.append("リスト表示中")
        if self._editor_state == "editor_multi":
            parts.append("看板を書いています('.' で終わり)")
        elif self._editor_state == "editor_single":
            parts.append("答えを入力してください")
        if self._closed:
            parts.append("切断")
        return " | ".join(parts)

    def _update_status(self) -> None:
        self._status_label.config(text=self._status_text())
        title = "NeoPHI"
        if self._name:
            title += f" - {self._name}"
        if self._world or self._area:
            title += " " + "/".join(p for p in (self._world, self._area) if p)
        if self._root is not None:
            self._root.title(title)

    # -- 出来事 ---------------------------------------------------------------

    def _pump(self) -> None:
        while True:
            try:
                event = self._event_queue.get_nowait()
            except queue.Empty:
                break
            self._handle_event(event)
        if self._root is not None:
            self._root.after(_PUMP_MS, self._pump)

    def _handle_event(self, event) -> None:
        if isinstance(event, MessageEvent):
            text = plain_text(event.text)
            self._add_log(event.channel, text)
            if event.channel == "log":
                self._spawn_floats(text)
                self._spawn_combat_fx(text)
                self._spawn_death_fx(text)
                self._show_log_bubble(event.text, text)
            elif event.channel in ("talk", "priv") and event.from_:
                body = bubble_body(text)
                if body:
                    self._show_bubble(event.from_, body)
        elif isinstance(event, StatusEvent):
            self._status = event
            if event.name:
                self._name = event.name
            self._update_status()
        elif isinstance(event, CondEvent):
            self._cond = event
            self._update_status()
        elif isinstance(event, MapEvent):
            self._map = event
            self._redraw_map()
            self._update_status()
        elif isinstance(event, EagleEyeEvent):
            self._eagle = event
            self._redraw_eagle()
        elif isinstance(event, ListEvent):
            result = receive_list(
                self._list_flow, event.active, event.lines, self._list_state
            )
            if result == "close":
                self._list_state = None
                self._refresh_listbox()
            elif isinstance(result, ListState):
                self._list_state = result
                self._refresh_listbox()
            self._update_status()
        elif isinstance(event, EditEvent):
            if event.mode == "single":
                self._editor_state = "editor_single"
                self._entry.delete(0, tk.END)
                self._entry.focus_set()
                self._add_local("[入力] 1行の答えを打ってください。")
            elif event.mode == "multi":
                self._editor_state = "editor_multi"
                self._editor_lines = []
                self._entry.delete(0, tk.END)
                self._entry.focus_set()
                self._add_local("[看板] 本文を打ってください。'.' で終わり、'.!' で取り消し。")
            else:
                if self._editor_state is not None:
                    self._editor_state = None
                self._add_local("[エディタ] 閉じました。")
            self._update_status()
        elif isinstance(event, NoticeEvent):
            if event.name:
                self._name = event.name
            if event.world:
                self._world = event.world
            if event.area:
                self._area = event.area
            if event.mapset:
                self._mapset = event.mapset
            if event.mapset_define is not None:
                no, name = event.mapset_define
                self._defines[no] = name
            self._update_status()
        elif isinstance(event, ModeEvent):
            self._mode = event
            self._update_status()
        elif isinstance(event, UserListEvent):
            self._users = [u.name for u in event.users]
        elif isinstance(event, TransferConfirmEvent):
            answer = messagebox.askyesno(
                "世界移動",
                f"別のホスト {event.host}:{event.port} へ"
                "キャラIDを送って移動しますか？",
            )
            self._send_text(TRANSFER_YES if answer else TRANSFER_NO)
        elif isinstance(event, ConnectionEvent):
            self._add_local("サーバーから切断されました。")
        elif isinstance(event, SessionErrorEvent):
            self._add_local(f"[エラー] {event.message}")
        elif isinstance(event, SessionClosedEvent):
            self._closed = True
            self._add_local("--- 切断しました ---")
            self._entry.config(state=tk.DISABLED)
            self._update_status()
            if self._exiting:
                self._destroy_if_exiting()

    def _anim_tick(self) -> None:
        self._anim_frame ^= 1
        if self._map is not None:
            self._redraw_map()
        if self._eagle is not None and self._eagle_window is not None:
            self._redraw_eagle()
        if self._root is not None:
            self._root.after(_ANIMATION_MS, self._anim_tick)

    # -- 地図の描画 -------------------------------------------------------------

    def _chip_sheets(self, mapset: str | None = None) -> list:
        base = self._mapset if mapset is None else mapset
        sheets = [self._assets.chip(base)]
        for d in (1, 2, 3):
            sheets.append(self._assets.chip(self._defines.get(d, "")))
        return sheets

    def _photo(self, image) -> tk.PhotoImage:
        png = encode_png(image)
        return tk.PhotoImage(data=base64.b64encode(png).decode("ascii"))

    def _bold_font(self, size: int, weight: str = "bold"):
        """既定のフォントを指定の太さにしたもの。大きさごとに覚えておきます。"""
        key = (size, weight)
        font = self._fonts.get(key)
        if font is None:
            font = tkfont.nametofont("TkDefaultFont").copy()
            font.configure(size=size, weight=weight)
            self._fonts[key] = font
        return font

    def _redraw_map(self) -> None:
        if self._map is None or self._root is None:
            return
        dim = grid_dim(self._map.size)
        chara_image = lambda ch: self._assets.chara(ch.name, ch.gra, ch.default)
        ghost_draws = [(g["chara"], g["faded"]) for g in self._ghosts]
        if self._view_mode == "flat":
            self._map_geom = None
            rendered = render_map_image(
                self._map.cells, self._map.chars, dim,
                self._chip_sheets(), self._assets.items(), chara_image,
                anim_frame=self._anim_frame, ghosts=ghost_draws,
            )
        else:
            view = PRESETS[self._view_mode]
            base_x, base_y, _, _ = quarter_geometry(dim, view)
            self._map_geom = (base_x, base_y)
            rendered = render_quarter_image(
                self._map.cells, self._map.chars, dim,
                self._chip_sheets(), self._assets.items(), chara_image,
                view, anim_frame=self._anim_frame, ghosts=ghost_draws,
            )
        # フロート表示の基準点を覚えます
        self._prev_charas = self._last_charas
        self._last_charas = {
            strip_tags(ch.name).strip(): ch for ch in self._map.chars
        }
        self._anchors = {a.name: (a.x, a.y) for a in rendered.anchors}
        self._center_anchor = None
        for a in rendered.anchors:
            if a.cell_x == dim // 2 and a.cell_y == dim // 2:
                self._center_anchor = (a.x, a.y)
        if self._snapshot is not None and not self._snapshot_done:
            self._snapshot_done = True
            try:
                Path(self._snapshot).write_bytes(encode_png(rendered.image))
            except OSError as exc:
                self._add_local(f"[エラー] 画像を残せませんでした: {exc}")
        self._map_photo = self._photo(rendered.image)
        zoomed = self._map_photo.zoom(self._zoom) if self._zoom > 1 else self._map_photo
        self._map_photo_zoomed = zoomed
        width = rendered.image.width * self._zoom
        height = rendered.image.height * self._zoom
        self._canvas.config(width=width, height=height)
        self._canvas.itemconfig(self._canvas_image, image=zoomed)
        self._canvas.delete("overlay")
        z = self._zoom
        for label in rendered.labels:
            x, y = label.x * z, label.y * z
            font = self._bold_font(9 * z)
            for dx, dy in ((-1, 0), (1, 0), (0, -1), (0, 1)):
                self._canvas.create_text(
                    x + dx * z, y + dy * z, text=label.name, fill="black",
                    font=font, anchor=tk.N, tags="overlay",
                )
            self._canvas.create_text(
                x, y, text=label.name, fill="white", font=font,
                anchor=tk.N, tags="overlay",
            )
        for holder in rendered.placeholders:
            initial = strip_tags(holder.name)[:1] or "?"
            self._canvas.create_text(
                holder.x * z, holder.y * z, text=initial, fill="yellow",
                font=self._bold_font(14 * z), tags="overlay",
            )
        self._redraw_bubbles()

    # -- フロート表示 -------------------------------------------------------------

    def _float_position(self, target: str | None) -> tuple[int, int] | None:
        """フロートを出す位置(地図の絵の中の座標)を決めます。"""
        if target is None or target == self._name or target in ("あなた", "自分"):
            return self._center_anchor
        return self._anchors.get(target)

    def _spawn_floats(self, text: str) -> None:
        """ログの行から数字を抜き、地図に浮かべます。"""
        canvas = getattr(self, "_canvas", None)
        if self._root is None or canvas is None:
            return
        for line in text.split("\n"):
            for event in parse_floats(line):
                pos = self._float_position(event.target)
                if pos is None:
                    continue
                self._float_seq += 1
                z = self._zoom
                # 続けて出る数字が重ならないよう、少しだけ横にずらします
                x = pos[0] * z + ((self._float_seq % 3) - 1) * 4 * z
                # 頭に少し重なるところから出て、上がっていきます
                y = pos[1] * z + 4 * z
                label = f"+{event.amount}" if event.kind in ("heal", "mp") else str(event.amount)
                # 攻撃の数字でも、自分が受けた時は赤にします
                kind = event.kind
                if kind == "dealt" and self._center_anchor is not None and pos == self._center_anchor:
                    kind = "taken"
                color = _FLOAT_COLORS[kind]
                font = self._bold_font(7 * z, "normal")
                items = []
                for dx, dy in ((-1, 0), (1, 0), (0, -1), (0, 1)):
                    items.append(canvas.create_text(
                        x + dx * z, y + dy * z, text=label, fill="black",
                        font=font, anchor=tk.S, tags="float",
                    ))
                items.append(canvas.create_text(
                    x, y, text=label, fill=color, font=font,
                    anchor=tk.S, tags="float",
                ))
                self._float_tick(items, 0)
                if kind in ("dealt", "taken", "mpdmg"):
                    self._flash_target(pos, kind)
                    if kind == "taken":
                        self._shake_map()

    def _flash_target(self, pos: tuple[int, int], kind: str) -> None:
        """ダメージを受けたキャラを、短く点滅させます。"""
        canvas = getattr(self, "_canvas", None)
        if self._root is None or canvas is None:
            return
        z = self._zoom
        color = {"dealt": "white", "taken": "#FF5252", "mpdmg": "#4FC3F7"}[kind]
        try:
            item = canvas.create_rectangle(
                (pos[0] - 16) * z, pos[1] * z,
                (pos[0] + 16) * z, (pos[1] + 32) * z,
                fill=color, outline="", stipple="gray50", tags="flash",
            )
        except tk.TclError:
            return
        self._flash_tick(item, 0)

    def _flash_tick(self, item: int, step: int) -> None:
        """点滅を3回繰り返して消します。"""
        canvas = getattr(self, "_canvas", None)
        if self._root is None or canvas is None:
            return
        try:
            if not canvas.winfo_exists():
                return
            if step >= 6:
                canvas.delete(item)
                return
            canvas.itemconfig(item, state="hidden" if step % 2 else "normal")
        except tk.TclError:
            return
        self._root.after(60, self._flash_tick, item, step + 1)

    _SHAKE_PATTERN = ((3, 0), (-3, 1), (2, -2), (-2, 0), (1, 1), (0, 0))

    def _shake_map(self) -> None:
        """自分がダメージを受けた時、地図を少し揺らします。"""
        if self._root is None or getattr(self, "_canvas", None) is None:
            return
        if self._shake_active:
            self._shake_step = 0
            return
        self._shake_active = True
        self._shake_step = 0
        self._shake_offset = (0, 0)
        self._shake_tick()

    def _shake_tick(self) -> None:
        """揺れを1コマ進め、最後に元の位置へ戻します。"""
        canvas = getattr(self, "_canvas", None)
        if self._root is None or canvas is None:
            self._shake_active = False
            return
        try:
            if not canvas.winfo_exists():
                self._shake_active = False
                return
            z = self._zoom
            if self._shake_step >= len(self._SHAKE_PATTERN):
                ox, oy = self._shake_offset
                canvas.move("all", -ox, -oy)
                self._shake_offset = (0, 0)
                self._shake_active = False
                return
            dx, dy = self._SHAKE_PATTERN[self._shake_step]
            dx *= z
            dy *= z
            ox, oy = self._shake_offset
            canvas.move("all", dx - ox, dy - oy)
            self._shake_offset = (dx, dy)
        except tk.TclError:
            self._shake_active = False
            return
        self._shake_step += 1
        self._root.after(50, self._shake_tick)

    # -- 戦闘の演出 -----------------------------------------------------------

    def _spawn_combat_fx(self, text: str) -> None:
        """戦闘の演出を出します。詠唱の行は、魔法の見分けに覚えます。"""
        if self._root is None or getattr(self, "_canvas", None) is None:
            return
        now = time.monotonic()
        for line in text.split("\n"):
            chant = parse_chant(line)
            if chant is not None:
                self._caster_tracker.note(chant, now)
                continue
            if parse_chant_stop(line):
                self._caster_tracker.clear(self._name)
                continue
            attack = parse_attack(line)
            if attack is not None:
                self._combat_fx(attack, now)

    def _combat_fx(self, attack: CombatEvent, now: float) -> None:
        """攻撃1回に、斬撃の軌跡か魔法弾の演出を出します。"""
        target_pos = self._float_position(attack.target)
        if target_pos is None:
            return
        if self._caster_tracker.consume(attack.attacker, now):
            attacker_pos = self._float_position(attack.attacker)
            if attacker_pos is not None and attacker_pos != target_pos:
                self._bolt_fx(attacker_pos, target_pos)
            else:
                self._impact(target_pos)
        else:
            attacker_pos = self._float_position(attack.attacker)
            if attacker_pos is not None:
                self._swing_sword(attacker_pos, target_pos)
            else:
                # 攻撃する人が見えなければ、対象に軌跡だけ出します
                self._slash_target(target_pos)

    def _sprite_center(self, pos: tuple[int, int]) -> tuple[float, float]:
        """キャラの絵の中心を、画面の座標で返します。"""
        z = self._zoom
        return pos[0] * z, (pos[1] + 16) * z

    def _swing_sword(self, from_pos: tuple[int, int], to_pos: tuple[int, int]) -> None:
        """攻撃する人から、対象の向きへ斬撃の軌跡を走らせます。"""
        canvas = getattr(self, "_canvas", None)
        if self._root is None or canvas is None:
            return
        try:
            if not canvas.winfo_exists():
                return
            z = self._zoom
            cx, cy = self._sprite_center(from_pos)
            tx, ty = self._sprite_center(to_pos)
            if (tx, ty) == (cx, cy):
                facing = -math.pi / 2
            else:
                facing = math.atan2(ty - cy, tx - cx)
            # 軌跡の中心は、体の中心から対象の向きへ少し寄せます
            px = cx + 6 * z * math.cos(facing)
            py = cy + 6 * z * math.sin(facing)
            start = facing + _SWING_START
            items = []
            for radius, lag, thickness in _SWING_STREAKS:
                items.append(canvas.create_polygon(
                    streak_points(px, py, z, radius, start, start + 0.12, thickness),
                    fill="white", outline="", tags="swing",
                ))
        except tk.TclError:
            return
        self._swing_tick(tuple(items), px, py, start, 0)

    def _swing_tick(self, items: tuple[int, ...], px: float, py: float,
                    start: float, step: int) -> None:
        """風切りの線を振り進め、薄くして消します。"""
        canvas = getattr(self, "_canvas", None)
        if self._root is None or canvas is None:
            return
        try:
            if not canvas.winfo_exists():
                return
            if step >= _SWING_FRAMES:
                for item in items:
                    canvas.delete(item)
                return
            z = self._zoom
            front = start + _SWING_SWEEP * step / (_SWING_FRAMES - 1)
            for i, item in enumerate(items):
                radius, lag, thickness = _SWING_STREAKS[i]
                end = max(front - lag, start + 0.12)
                canvas.coords(
                    item,
                    streak_points(px, py, z, radius, start, end, thickness))
                color_step = min(step + (0 if i == 0 else 1), _SWING_FRAMES - 1)
                canvas.itemconfig(item, fill=_SWING_COLORS[color_step])
        except tk.TclError:
            return
        self._root.after(
            _SWING_FRAME_MS, self._swing_tick, items, px, py, start, step + 1)

    def _slash_target(self, pos: tuple[int, int]) -> None:
        """対象のキャラに、剣の軌跡を重ねます。"""
        canvas = getattr(self, "_canvas", None)
        if self._root is None or canvas is None:
            return
        try:
            if not canvas.winfo_exists():
                return
            z = self._zoom
            cx, cy = self._sprite_center(pos)
            main = canvas.create_polygon(
                slash_points(cx, cy, z), fill="white", outline="",
                tags="slash",
            )
            echo = canvas.create_polygon(
                slash_points(cx + 3 * z, cy - 3 * z, z, 0.7),
                fill="#E3F2FD", outline="", tags="slash",
            )
        except tk.TclError:
            return
        self._slash_tick((main, echo), cx, cy, 0)

    def _slash_tick(self, items: tuple[int, int], cx: float, cy: float, step: int) -> None:
        """軌跡を少し広げながら薄くし、最後に消します。"""
        canvas = getattr(self, "_canvas", None)
        if self._root is None or canvas is None:
            return
        try:
            if not canvas.winfo_exists():
                return
            if step >= _SLASH_FRAMES:
                for item in items:
                    canvas.delete(item)
                return
            main, echo = items
            canvas.itemconfig(main, fill=_SLASH_COLORS[step])
            canvas.itemconfig(echo, fill=_SLASH_COLORS[min(step + 1, _SLASH_FRAMES - 1)])
            for item in items:
                canvas.scale(item, cx, cy, 1.04, 1.04)
        except tk.TclError:
            return
        self._root.after(_SLASH_FRAME_MS, self._slash_tick, items, cx, cy, step + 1)

    def _bolt_fx(self, from_pos: tuple[int, int], to_pos: tuple[int, int]) -> None:
        """術師から対象へ、尾を引く魔法弾を飛ばします。"""
        canvas = getattr(self, "_canvas", None)
        if self._root is None or canvas is None:
            return
        try:
            if not canvas.winfo_exists():
                return
            z = self._zoom
            x0, y0 = self._sprite_center(from_pos)
            x1, y1 = self._sprite_center(to_pos)
            tail = canvas.create_polygon(
                x0, y0, x0, y0, x0, y0,
                fill=_BOLT_COLOR, outline="", tags="bolt",
            )
            tail_core = canvas.create_polygon(
                x0, y0, x0, y0, x0, y0,
                fill="white", outline="", tags="bolt",
            )
            halo = canvas.create_oval(
                x0 - 5 * z, y0 - 5 * z, x0 + 5 * z, y0 + 5 * z,
                fill=_BOLT_COLOR, outline="", tags="bolt",
            )
            core = canvas.create_oval(
                x0 - 2 * z, y0 - 2 * z, x0 + 2 * z, y0 + 2 * z,
                fill="white", outline="", tags="bolt",
            )
            sparks = []
            for color in ("white", "#B3E5FC"):
                sparks.append(canvas.create_oval(
                    x0 - 1.5 * z, y0 - 1.5 * z, x0 + 1.5 * z, y0 + 1.5 * z,
                    fill=color, outline="", tags="bolt",
                ))
        except tk.TclError:
            return
        dx = (x1 - x0) / _BOLT_STEPS
        dy = (y1 - y0) / _BOLT_STEPS
        parts = {
            "tail": tail, "tail_core": tail_core, "halo": halo,
            "core": core, "sparks": sparks,
        }
        self._bolt_tick(parts, (x0, y0), dx, dy, (x1, y1), 0)

    def _bolt_tick(self, parts: dict, start: tuple[float, float],
                   dx: float, dy: float, end: tuple[float, float],
                   step: int) -> None:
        """魔法弾を1歩進め、着いたら閃光と火花を出します。"""
        canvas = getattr(self, "_canvas", None)
        if self._root is None or canvas is None:
            return
        try:
            if not canvas.winfo_exists():
                return
            if step >= _BOLT_STEPS:
                for item in (parts["tail"], parts["tail_core"],
                             parts["halo"], parts["core"], *parts["sparks"]):
                    canvas.delete(item)
                self._impact_at(end)
                return
            z = self._zoom
            hx = start[0] + dx * (step + 1)
            hy = start[1] + dy * (step + 1)
            canvas.coords(parts["halo"],
                          hx - 5 * z, hy - 5 * z, hx + 5 * z, hy + 5 * z)
            canvas.coords(parts["core"],
                          hx - 2 * z, hy - 2 * z, hx + 2 * z, hy + 2 * z)
            # 尾は、進んだ分だけ後ろへ伸ばし、長さに上限を付けます
            dist = math.hypot(dx, dy)
            if dist > 1e-6:
                ux, uy = dx / dist, dy / dist
            else:
                ux, uy = 1.0, 0.0
            traveled = math.hypot(hx - start[0], hy - start[1])
            tail_len = min(traveled, _BOLT_TAIL_LEN * z)
            tx, ty = hx - ux * tail_len, hy - uy * tail_len
            canvas.coords(parts["tail"], comet_tail_points(
                hx, hy, tx, ty, z, _BOLT_TAIL_WIDTH))
            inner_len = tail_len * 0.55
            canvas.coords(parts["tail_core"], comet_tail_points(
                hx, hy, hx - ux * inner_len, hy - uy * inner_len,
                z, _BOLT_TAIL_WIDTH * 0.45))
            # 火花は、弾の周りを回ります
            for spark, phase in zip(parts["sparks"], (0.0, math.pi)):
                angle = step * _BOLT_ORBIT_STEP + phase
                sx = hx + _BOLT_ORBIT_R * z * math.cos(angle)
                sy = hy + _BOLT_ORBIT_R * z * math.sin(angle)
                canvas.coords(spark,
                              sx - 1.5 * z, sy - 1.5 * z,
                              sx + 1.5 * z, sy + 1.5 * z)
        except tk.TclError:
            return
        self._root.after(
            _BOLT_STEP_MS, self._bolt_tick, parts, start, dx, dy, end, step + 1)

    def _impact(self, pos: tuple[int, int]) -> None:
        """対象の位置で、着弾の閃光と火花を出します。"""
        self._impact_at(self._sprite_center(pos))

    def _impact_at(self, center: tuple[float, float]) -> None:
        """指定の位置で、着弾の閃光と火花を出します。"""
        canvas = getattr(self, "_canvas", None)
        if self._root is None or canvas is None:
            return
        try:
            if not canvas.winfo_exists():
                return
            z = self._zoom
            cx, cy = center
            flash = canvas.create_oval(
                cx - 9 * z, cy - 9 * z, cx + 9 * z, cy + 9 * z,
                fill="white", outline="", tags="burst",
            )
            ring1 = canvas.create_oval(
                cx - 4 * z, cy - 4 * z, cx + 4 * z, cy + 4 * z,
                fill="", outline="white", width=2 * z, tags="burst",
            )
            ring2 = canvas.create_oval(
                cx, cy, cx, cy,
                fill="", outline=_BOLT_COLOR, width=z, tags="burst",
            )
            sparks = []
            for _ in range(_IMPACT_SPARKS):
                sparks.append(canvas.create_polygon(
                    cx, cy, cx, cy, cx, cy, cx, cy,
                    fill="white", outline="", tags="burst",
                ))
        except tk.TclError:
            return
        parts = {"flash": flash, "ring1": ring1, "ring2": ring2, "sparks": sparks}
        self._impact_tick(parts, center, 0)

    def _impact_tick(self, parts: dict, center: tuple[float, float],
                     step: int) -> None:
        """閃光をしぼめ、輪を広げ、火花を散らして消します。"""
        canvas = getattr(self, "_canvas", None)
        if self._root is None or canvas is None:
            return
        try:
            if not canvas.winfo_exists():
                return
            if step >= _IMPACT_FRAMES:
                items = [parts["ring1"], parts["ring2"], *parts["sparks"]]
                if parts["flash"] is not None:
                    items.append(parts["flash"])
                for item in items:
                    canvas.delete(item)
                return
            z = self._zoom
            cx, cy = center
            color = _IMPACT_COLORS[step]
            if parts["flash"] is not None:
                if step >= 3:
                    canvas.delete(parts["flash"])
                    parts["flash"] = None
                else:
                    r = (9 - 2 * step) * z
                    canvas.coords(parts["flash"],
                                  cx - r, cy - r, cx + r, cy + r)
                    canvas.itemconfig(parts["flash"], fill=color)
            r1 = (4 + 4 * step) * z
            canvas.coords(parts["ring1"],
                          cx - r1, cy - r1, cx + r1, cy + r1)
            canvas.itemconfig(parts["ring1"], outline=color,
                              width=max(1, 2 * z - step * z // 2))
            if step >= 1:
                r2 = (4 + 3 * (step - 1)) * z
                canvas.coords(parts["ring2"],
                              cx - r2, cy - r2, cx + r2, cy + r2)
                canvas.itemconfig(parts["ring2"], outline=color)
            for i, spark in enumerate(parts["sparks"]):
                angle = i * math.pi * 2 / _IMPACT_SPARKS
                canvas.coords(spark, radial_spark_points(
                    cx, cy, z, angle, 6 + 3 * step, 1.2))
                canvas.itemconfig(spark, fill=color)
        except tk.TclError:
            return
        self._root.after(_IMPACT_FRAME_MS, self._impact_tick, parts, center, step + 1)

    # -- 倒れたキャラの消滅 ---------------------------------------------------

    def _spawn_death_fx(self, text: str) -> None:
        """死亡の行から、倒れたキャラのゆっくり消える演出を出します。"""
        victim = parse_kill(text)
        if victim is None:
            return
        if victim == "あなた" and self._name:
            victim = self._name
        ch = self._last_charas.get(victim)
        if ch is None:
            ch = self._prev_charas.get(victim)
        if ch is None:
            return
        sheet = self._assets.chara(ch.name, ch.gra, ch.default)
        if sheet is None:
            return
        self._ghosts = [g for g in self._ghosts if g["name"] != victim]
        self._ghosts.append({
            "name": victim, "chara": ch, "sheet": sheet,
            "faded": sheet, "step": 0, "spawned": time.monotonic(),
        })
        self._redraw_map()
        self._schedule_ghost_tick()

    def _schedule_ghost_tick(self) -> None:
        """残像を薄くする刻みを、まだ無ければ予定します。"""
        if self._root is None or self._ghost_tick_active or not self._ghosts:
            return
        self._ghost_tick_active = True
        self._root.after(_GHOST_STEP_MS, self._ghost_tick_all)

    def _ghost_tick_all(self) -> None:
        """残像を一段薄くして描き直し、消え切ったものを外します。"""
        self._ghost_tick_active = False
        if self._root is None:
            self._ghosts = []
            return
        try:
            if not self._root.winfo_exists():
                self._ghosts = []
                return
            remaining = []
            now = time.monotonic()
            for ghost in self._ghosts:
                # 描き直しが重くても、壁時計どおりの速さで薄くします
                step = int((now - ghost["spawned"]) / (_GHOST_STEP_MS / 1000.0))
                if step >= _GHOST_STEPS:
                    continue
                ghost["step"] = step
                if step > 0:
                    ghost["faded"] = fade_alpha(
                        ghost["sheet"], 1.0 - step / _GHOST_STEPS)
                remaining.append(ghost)
            self._ghosts = remaining
            self._redraw_map()
        except tk.TclError:
            return
        self._schedule_ghost_tick()

    # -- 吹き出し -------------------------------------------------------------

    def _show_log_bubble(self, raw_text: str, plain: str) -> None:
        """NPCの発言や action の行を、吹き出しで出します。"""
        names = set(self._anchors)
        if self._name:
            names.add(self._name)
        found = None
        if "/*act*/" in raw_text:
            found = bubble_from_action_line(plain, names)
        if found is None:
            found = bubble_from_log_line(plain, names)
        if found is not None:
            speaker, body = found
            self._show_bubble(speaker, body)

    def _show_bubble(self, speaker: str, body: str) -> None:
        """話し手の頭の上に、発言の吹き出しを出します。"""
        canvas = getattr(self, "_canvas", None)
        if self._root is None or canvas is None:
            return
        old = self._bubbles.get(speaker)
        if old is not None:
            for item in old["items"]:
                canvas.delete(item)
        self._bubble_gen += 1
        gen = self._bubble_gen
        occupied = [
            state["rect"] for name, state in self._bubbles.items()
            if name != speaker and state["rect"] is not None
        ]
        items, rect = self._draw_bubble(speaker, body, occupied)
        self._bubbles[speaker] = {
            "text": body, "gen": gen, "items": items, "rect": rect,
        }
        ms = min(
            _BUBBLE_MAX_MS, _BUBBLE_BASE_MS + _BUBBLE_PER_CHAR_MS * len(body)
        )
        self._root.after(ms, self._expire_bubble, speaker, gen)

    def _expire_bubble(self, speaker: str, gen: int) -> None:
        """時間が来た吹き出しを消します。新しい発言があれば残します。"""
        state = self._bubbles.get(speaker)
        if state is None or state["gen"] != gen:
            return
        canvas = getattr(self, "_canvas", None)
        if canvas is not None:
            for item in state["items"]:
                canvas.delete(item)
        del self._bubbles[speaker]

    def _redraw_bubbles(self) -> None:
        """地図を描き直した後、残っている吹き出しを描き直します。"""
        canvas = getattr(self, "_canvas", None)
        if canvas is None:
            return
        canvas.delete("bubble")
        occupied = []
        for speaker, state in self._bubbles.items():
            items, rect = self._draw_bubble(speaker, state["text"], occupied)
            state["items"] = items
            state["rect"] = rect
            if rect is not None:
                occupied.append(rect)

    def _draw_bubble(self, speaker: str, body: str, occupied=()) -> tuple:
        """吹き出しを描き、作った部品と箱の場所を返します。

        話し手が見えなければ、部品も場所も空です。
        """
        canvas = getattr(self, "_canvas", None)
        photo = getattr(self, "_map_photo_zoomed", None)
        if self._root is None or canvas is None or photo is None:
            return [], None
        pos = self._float_position(speaker)
        if pos is None:
            return [], None
        try:
            if not canvas.winfo_exists():
                return [], None
            z = self._zoom
            font = self._bold_font(6 * z, "normal")
            pad = 4 * z
            width = photo.width()
            max_text = min(_BUBBLE_MAX_WIDTH * z, width - 2 * pad)
            if max_text <= 0:
                return [], None
            lines = wrap_bubble_lines(body, font.measure, max_text, _BUBBLE_MAX_LINES)
            if not lines:
                return [], None
            line_height = font.metrics("linespace")
            text_w = max(font.measure(line) for line in lines)
            w = text_w + 2 * pad
            h = line_height * len(lines) + 2 * pad
            cx = pos[0] * z
            tail_h = 6 * z
            tail_w = 5 * z
            # しっぽの先は頭の少し上、箱はその上に置きます
            tip_y = pos[1] * z - z
            x0, y0, stacked = place_bubble_rect(
                cx, tip_y, w, h, width, tail_h, occupied)
            y1 = y0 + h
            tip_x = min(max(cx, x0 + 1), x0 + w - 1)
            base_x = min(max(cx, x0 + tail_w), x0 + w - tail_w)
            # 上にずらした時は、しっぽは短く下向きにだけ出します
            tail_tip_y = y1 + tail_h if stacked else tip_y
            outline = bubble_outline(
                x0, y0, x0 + w, y1, 6 * z, base_x, tail_w, tip_x, tail_tip_y,
            )
            flat = [coord for point in outline for coord in point]
            items = []
            items.append(canvas.create_polygon(
                flat, fill="white", outline="black",
                width=z, joinstyle="round", tags="bubble",
            ))
            items.append(canvas.create_text(
                x0 + pad, y0 + pad, text="\n".join(lines), fill="black",
                font=font, anchor=tk.NW, justify="left", tags="bubble",
            ))
            rect = (x0, y0, w, h + tail_h) if stacked else (x0, y0, w, h)
            return items, rect
        except tk.TclError:
            return [], None

    def _float_tick(self, items: list[int], step: int) -> None:
        """数字を少しずつ上げ、最後に消します。"""
        canvas = getattr(self, "_canvas", None)
        if self._root is None or canvas is None:
            return
        try:
            if not canvas.winfo_exists():
                return
        except tk.TclError:
            return
        if step >= _FLOAT_STEPS:
            for item in items:
                canvas.delete(item)
            return
        for item in items:
            canvas.move(item, 0, -self._zoom)
        self._root.after(_FLOAT_STEP_MS, self._float_tick, items, step + 1)

    def _float_demo_tick(self) -> None:
        """試し表示: 地図のキャラを使い、戦闘のログと発言を定期的に出します。"""
        if self._map is not None and self._map.chars:
            dim = grid_dim(self._map.size)
            center = (dim // 2, dim // 2)
            foes = [
                strip_tags(c.name).strip() for c in self._map.chars
                if (c.x, c.y) != center and strip_tags(c.name).strip()
            ]
            names = [
                strip_tags(c.name).strip() for c in self._map.chars
                if strip_tags(c.name).strip()
            ]
            center_names = {
                strip_tags(c.name).strip() for c in self._map.chars
                if (c.x, c.y) == center and strip_tags(c.name).strip()
            }
            if names and random.random() < 0.33:
                speaker = random.choice(names)
                phrase = random.choice(_BUBBLE_DEMO_PHRASES)
                if random.random() < 0.5:
                    # NPCの発言の形(logの行)でも吹き出しが出ます
                    self._event_queue.put(MessageEvent(
                        channel="log", text=f"{speaker} > {phrase}"))
                else:
                    self._event_queue.put(MessageEvent(
                        channel="talk", text=f"{speaker} > {phrase}",
                        from_=speaker))
            elif names and random.random() < 0.3:
                attacker = random.choice(names)
                target = random.choice(names)
                amount = random.randint(5, 120)
                self._event_queue.put(MessageEvent(
                    channel="log",
                    text=f"DM > {attacker} は魔法を唱えている... "))
                self._event_queue.put(MessageEvent(
                    channel="log",
                    text=f"DM > {attacker} は {target} を Harm で攻撃した. [{amount} hp]"))
            else:
                kind = random.choice(["dealt", "taken", "heal"])
                amount = random.randint(5, 120)
                me = self._name or (
                    next(iter(center_names)) if center_names else "あなた")
                if kind == "dealt" and foes:
                    line = f"DM > {me} は {random.choice(foes)} を ロングソード で攻撃した. [{amount} hp]"
                elif kind == "taken":
                    attacker = random.choice(foes) if foes else "モンスター"
                    line = f"DM > {attacker} は {me} を 牙 で攻撃した. [{amount} hp]"
                elif names:
                    target = random.choice(names)
                    healer = random.choice(names)
                    line = f"DM > {healer} は {target} を キュアー で回復した. [{amount} hp]"
                else:
                    line = f"DM > {me} が キュアー によって回復した. [{amount} hp]"
                self._event_queue.put(MessageEvent(channel="log", text=line))
        if self._root is not None:
            self._root.after(_FLOAT_DEMO_MS, self._float_demo_tick)

    def _redraw_eagle(self) -> None:
        if self._eagle is None or self._root is None:
            return
        dim, cells, chars = eagle_board(self._eagle)
        rendered = render_map_image(
            cells, chars, dim,
            self._chip_sheets(self._eagle.mapset), self._assets.items(),
            lambda ch: self._assets.chara(ch.name, ch.gra, ch.default),
            anim_frame=self._anim_frame, eagle_eye=True,
        )
        if self._eagle_window is None or not self._eagle_window.winfo_exists():
            window = tk.Toplevel(self._root)
            window.title("EagleEye")
            window.protocol("WM_DELETE_WINDOW", window.destroy)
            canvas = tk.Canvas(window, bg="black", highlightthickness=0)
            canvas.pack()
            self._eagle_window = window
            self._eagle_canvas = canvas
            self._eagle_image_item = canvas.create_image(0, 0, anchor=tk.NW)
        self._eagle_photo = self._photo(rendered.image)
        zoomed = self._eagle_photo.zoom(self._zoom) if self._zoom > 1 else self._eagle_photo
        self._eagle_photo_zoomed = zoomed
        self._eagle_canvas.config(
            width=dim * 32 * self._zoom, height=(dim * 32 + MAP_TOP) * self._zoom
        )
        self._eagle_canvas.itemconfig(self._eagle_image_item, image=zoomed)

    # -- リスト ---------------------------------------------------------------

    def _refresh_listbox(self) -> None:
        state = self._list_state
        if state is None:
            self._list_frame.pack_forget()
            return
        self._list_frame.pack(fill=tk.X, before=self._entry.master)
        self._listbox.delete(0, tk.END)
        for i, line in enumerate(state.lines):
            check = "✓ " if state.checked[i] else "  "
            self._listbox.insert(tk.END, f"{check}{plain_text(line)}")
        self._listbox.config(height=min(9, max(1, len(state.lines))))
        self._listbox.selection_clear(0, tk.END)
        if state.lines:
            self._listbox.selection_set(state.cursor)
            self._listbox.see(state.cursor)

    def _on_list_click(self, event) -> None:
        index = self._listbox.nearest(event.y)
        state = self._list_state
        if state is None or not (0 <= index < len(state.lines)):
            return
        checked = list(state.checked)
        checked[index] = not checked[index]
        self._list_state = ListState(
            lines=list(state.lines), checked=checked, cursor=index,
            offset=state.offset, start=state.start, waiting=state.waiting,
        )
        self._refresh_listbox()

    def _on_list_pick(self, event) -> None:
        index = self._listbox.nearest(event.y)
        if self._list_state is None or not (0 <= index < len(self._list_state.lines)):
            return
        state = move_list_cursor(
            self._list_state, cursor_delta=index - self._list_state.cursor
        )
        self._send_and_close_list(list_ok(state))
        self._list_state = None
        self._refresh_listbox()
        self._update_status()

    def _handle_list_key(self, action) -> None:
        state = self._list_state
        if state is None:
            return
        if action.focus_input:
            self._entry.focus_set()
            return
        if action.send is not None:
            self._send_and_close_list(action.send)
            self._list_state = None
            self._refresh_listbox()
            self._update_status()
            return
        if action.list_no is not None:
            result = list_no(state, action.list_no)
            if result is None:
                return
            text, close = result
            if close:
                self._send_and_close_list(text)
                self._list_state = None
                self._refresh_listbox()
            else:
                self._send_text(text)
                state.waiting = True
            self._update_status()
            return
        if action.list_ok:
            self._send_and_close_list(list_ok(state))
            self._list_state = None
            self._refresh_listbox()
            self._update_status()
            return
        if action.list_toggle:
            self._list_state = move_list_cursor(state, toggle=True)
            self._refresh_listbox()
            return
        if action.list_cursor:
            self._list_state = move_list_cursor(state, cursor_delta=action.list_cursor)
            self._refresh_listbox()
            return

    # -- キー -------------------------------------------------------------------

    def _north_fix(self) -> bool:
        if self._map is None:
            return True
        return self._map.size == 7 and self._map.style != "turn"

    def _on_key(self, event) -> str | None:
        # 終わるキーは、どこにフォーカスがあっても効かせます
        is_cmd_q = (
            sys.platform == "darwin"
            and bool(event.state & 0x10)
            and event.keysym.lower() == "q"
        )
        if (bool(event.state & 0x4) and event.keysym.lower() == "q") or is_cmd_q:
            self._request_disconnect(graceful=True)
            return "break"
        if event.widget is self._entry:
            return None
        code = _keysym_to_code(event.keysym)
        if code is None:
            return None
        shift = bool(event.state & 0x1)
        ctrl = bool(event.state & 0x4)
        alt = bool(event.state & 0x8)
        meta = bool(event.state & 0x10) if sys.platform == "darwin" else bool(event.state & 0x40)
        if code == "PageUp":
            self._log.yview_scroll(-10, "units")
            return "break"
        if code == "PageDown":
            self._log.yview_scroll(10, "units")
            return "break"
        if code == "Enter":
            self._entry.focus_set()
            return "break"
        if code == "Escape":
            return "break"

        if self._list_state is not None:
            list_action = list_key_action(
                code, shift=shift, ctrl=ctrl, alt=alt, meta=meta
            )
            if list_action is not None:
                self._handle_list_key(list_action)
                return "break"
        moved = move_input(code, shift=shift, ctrl=ctrl, alt=alt, meta=meta)
        if moved is not None:
            key, mods = moved
            self._send_text(move_command(key, mods, self._north_fix()))
            return "break"
        action = key_action(code, shift=shift, ctrl=ctrl, alt=alt, meta=meta)
        if action is not None:
            self._execute_action(action)
            return "break"
        return None

    def _execute_action(self, action: KeyAction) -> None:
        if action.ask is not None:
            ask = action.ask
            while True:
                answer = simpledialog.askstring(ask.title, ask.label,
                                                initialvalue=ask.initial)
                if answer is None or answer == "":
                    return
                if ask.numeric and not answer.isdigit():
                    messagebox.showerror(ask.title, "数を入力してください。")
                    continue
                break
            if action.cancel_list:
                self._list_flow.cancel += action.cancel_list
            if action.send is not None:
                self._send_text(action.send.replace("{}", answer))
            return
        if action.confirm is not None:
            if not messagebox.askyesno("確認", action.confirm):
                return
            self._send_action(
                KeyAction(
                    send=action.send, cancel_list=action.cancel_list,
                    system_magic=action.system_magic,
                )
            )
            return
        self._send_action(action)

    def _send_action(self, action: KeyAction) -> None:
        if action.send is not None:
            if action.cancel_list:
                self._list_flow.cancel += action.cancel_list
            if action.system_magic is not None:
                # 系統魔法はセッションへ渡し、unequip を先に送らせる。
                # 開いているリストは、唱える行を送る前に閉じる
                close_list = self._list_state is not None
                self._list_state = None
                self._refresh_listbox()
                self._send_system_magic(
                    action.send, action.system_magic == "reequip", close_list
                )
            elif self._list_state is not None:
                self._send_and_close_list(action.send)
                self._list_state = None
                self._refresh_listbox()
            else:
                self._send_text(action.send)
        if action.write:
            self._send_text("write")
        if action.focus_input:
            self._entry.focus_set()
        if action.toggle_map:
            self._toggle_map()
        if action.menu in ("force-close", "all-force-close"):
            self._request_disconnect(graceful=False)

    # -- 入力欄 ---------------------------------------------------------------

    def _on_entry_return(self, event) -> str:
        line = self._entry.get()
        self._entry.delete(0, tk.END)
        if self._editor_state == "editor_single":
            self._send_text(line if line != "" else " ")
            self._editor_state = None
            self._canvas.focus_set()
            self._update_status()
            return "break"
        if self._editor_state == "editor_multi":
            if line == ".":
                self._send_text("\n".join(board_lines(self._editor_lines)))
                self._editor_state = None
                self._editor_lines = []
                self._canvas.focus_set()
            elif line == ".!":
                self._send_text(".!")
                self._editor_state = None
                self._editor_lines = []
                self._canvas.focus_set()
            else:
                self._editor_lines.append(line)
                self._add_log("log", f"[看板] {line}")
            self._update_status()
            return "break"
        if line:
            self._history.append(line)
        self._history_index = len(self._history)
        self._submit_input_line(line)
        return "break"

    def _on_entry_escape(self, event) -> str:
        if self._editor_state is not None:
            # 取り消してエディタを出ます
            self._send_text(".!")
            self._editor_state = None
            self._editor_lines = []
            self._update_status()
        self._canvas.focus_set()
        return "break"

    def _on_entry_history_prev(self, event) -> str:
        if self._history and self._history_index > 0:
            self._history_index -= 1
            self._entry.delete(0, tk.END)
            self._entry.insert(0, self._history[self._history_index])
        return "break"

    def _on_entry_history_next(self, event) -> str:
        if self._history and self._history_index < len(self._history):
            self._history_index += 1
            self._entry.delete(0, tk.END)
            if self._history_index < len(self._history):
                self._entry.insert(0, self._history[self._history_index])
        return "break"

    def _submit_input_line(self, line: str) -> None:
        if line.startswith("/"):
            if self._handle_local_command(line):
                return
        prepared = prepare_line(line, loud=self._loud)
        if prepared is not None:
            if self._list_state is not None:
                self._send_and_close_list(prepared)
                self._list_state = None
                self._refresh_listbox()
                self._update_status()
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
        if cmd == "zoom":
            if len(parts) >= 2 and parts[1] in ("1", "2", "3"):
                self._zoom = int(parts[1])
                self._redraw_map()
                self._redraw_eagle()
                self._add_local(f"地図の拡大率: {self._zoom}倍")
            else:
                self._add_local(f"地図の拡大率: {self._zoom}倍")
            return True
        if cmd == "view":
            if len(parts) >= 2 and parts[1] in _VIEW_LABELS:
                self._set_view(parts[1])
            elif len(parts) >= 2:
                self._add_local("見方は flat / tilt / oblique / iso のどれかです。")
            else:
                self._cycle_view()
            self._add_local(f"地図の見方: {_VIEW_LABELS[self._view_mode]}")
            return True
        self._add_local(f"知らない命令です: /{cmd} (/help で一覧)")
        return True

    # -- マウス -----------------------------------------------------------------

    def _map_coords(self, event) -> tuple[float, float, int] | None:
        if self._map is None:
            return None
        dim = grid_dim(self._map.size)
        x = event.x / self._zoom
        y = event.y / self._zoom
        if self._map_geom is not None and self._view_mode != "flat":
            # クオータービューでは、点のあるマスを拾い、平面の同じマスの
            # 中心に読み替えて、向きの計算を流用します
            view = PRESETS[self._view_mode]
            base_x, base_y = self._map_geom
            picked = quarter_pick(view, dim, base_x, base_y, x, y)
            if picked is None:
                return None
            return (picked[0] + 0.5) * 32, (picked[1] + 0.5) * 32, dim
        return x, y - MAP_TOP, dim

    def _on_map_click(self, event) -> None:
        self._canvas.focus_set()
        coords = self._map_coords(event)
        if coords is None:
            return
        x, y, dim = coords
        size = dim * 32
        north_fix = self._north_fix()
        shift_or_ctrl = bool(event.state & 0x1) or bool(event.state & 0x4)
        if north_fix and shift_or_ctrl:
            to = north_fix_turn(x, y, size, size)
            if to is not None:
                self._send_text(f"turn {to}")
            return
        direction = mouse_dir(x, y, size, size, north_fix, shift_or_ctrl)
        if direction is None:
            return
        # 斜めは2方向を1歩ずつ送り、斜めに1マス進みます
        commands = [move_command(k, "none", north_fix) for k in direction.keys]
        self._send_text("\n".join(commands))

    def _on_map_right_click(self, event) -> None:
        self._canvas.focus_set()
        self._send_text("hit")

    def _on_map_motion(self, event) -> None:
        coords = self._map_coords(event)
        if coords is None or self._map is None:
            return
        x, y, dim = coords
        size = dim * 32
        north_fix = self._north_fix()
        shift_or_ctrl = bool(event.state & 0x1) or bool(event.state & 0x4)
        if north_fix and shift_or_ctrl:
            # マウスの方を向きます。同じ向きは続けて送りません
            to = north_fix_turn(x, y, size, size)
            center = dim // 2
            own = next(
                (c for c in self._map.chars if c.x == center and c.y == center), None
            )
            facing = {"B": "n", "R": "e", "F": "s", "L": "w"}.get(own.dir if own else "")
            key = f"{to}:{facing}" if to else None
            if to is not None and to != facing and key != self._last_turn:
                self._last_turn = key
                self._send_text(f"turn {to}")
            return
        direction = mouse_dir(x, y, size, size, north_fix, shift_or_ctrl)
        cursor = _CURSORS.get(direction.cursor, "") if direction else ""
        self._canvas.config(cursor=cursor)


def main(argv: list[str] | None = None) -> int:
    if tk is None:
        print(
            "tkinter がありません。GUI クライアントは使えません。"
            "行単位のクライアント(`python -m neophi cli`)を使ってください。",
            file=sys.stderr,
        )
        return 1
    parser = argparse.ArgumentParser(
        prog="neophi.gui", description="NeoPHI (GUI・地図は BMP の絵)"
    )
    parser.add_argument("--host", required=True, help="サーバのホスト")
    parser.add_argument("--port", required=True, type=int, help="サーバのポート")
    parser.add_argument("--id", dest="char_id", default=None,
                        help="キャラID(省略すると PHI_ID か入力で聞きます)")
    parser.add_argument("--record-dir", default=None,
                        help="受信した生のバイト列を残すフォルダ")
    parser.add_argument("--assets-dir", action="append", default=[],
                        help="Philly のフォルダ(繰り返し指定でき、先が優先)。無ければ絵は色で代用します")
    parser.add_argument("--skin", default="Mine", help="スキン名(既定: Mine)")
    parser.add_argument("--zoom", type=int, default=2, choices=(1, 2, 3),
                        help="地図の拡大率(既定: 2)")
    parser.add_argument("--view", default="flat",
                        choices=("flat", "tilt", "oblique", "iso"),
                        help="地図の見方(既定: flat)。tilt/oblique/iso はクオータービューです")
    parser.add_argument("--auto-quit", type=float, default=None,
                        help="開発用: 指定した秒後に終わります")
    parser.add_argument("--snapshot", default=None,
                        help="開発用: 最初に描いた地図を PNG で残します")
    parser.add_argument("--float-demo", action="store_true",
                        help="開発用: 戦闘のログを定期的に出し、数字の浮かび方を試します")
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

    app = _GUI(
        args.host, args.port, char_id,
        assets_dirs=args.assets_dir, skin=args.skin,
        record_dir=args.record_dir, zoom=args.zoom,
        auto_quit=args.auto_quit, snapshot=args.snapshot,
        view_mode=args.view, float_demo=args.float_demo,
        auto_unequip=args.auto_unequip, auto_equip=args.auto_equip,
    )
    return app.run()


if __name__ == "__main__":
    sys.exit(main())
