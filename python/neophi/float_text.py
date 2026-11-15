"""ログの行から、戦闘の数字を抜き出します。

実サーバ (rel5g MasterGate) のメッセージ集 ``dm_msg_jp.h`` の文面に
合わせています。タグを除いた後の行を見ます。数字は行末の ``[N hp]``
や ``[N mp]`` に出ます。
"""

from __future__ import annotations

import re
from dataclasses import dataclass

__all__ = ["FloatEvent", "parse_floats"]


@dataclass(frozen=True)
class FloatEvent:
    """地図に浮かべる数字1つ。"""

    kind: str  # "dealt" | "taken" | "heal" | "mp" | "mpdmg"
    target: str | None  # 名前。None は自分です。
    amount: int


_NUM = r"([\d,]+)"
# 名前は、文の区切りと、行頭の「DM > 」の区切りを含まない範囲にします。
# 頭の空白は含めないので、「しかし X は ...」の「しかし」を名前に含みません。
_NAME = r"([^\s。！!、,\n>][^。！!、,\n>]*?)"

#: 全角の数字とカンマを半角にそろえます。
_FULLWIDTH = str.maketrans("０１２３４５６７８９，", "0123456789,")


def _normalize(text: str) -> str:
    return text.translate(_FULLWIDTH)


#: (種類, 文面の型, 名前の組, 数字の組)。名前の組が None なら自分です。
#: 順番に意味があります。治療(他)を食べ物の回復より先に見ないと、
#: 治療の行を術者の回復と読み違えます。
_PATTERNS: list[tuple[str, "re.Pattern[str]", int | None, int]] = [
    # 攻撃 (物理・魔法): 「X は Y を W で攻撃した. [N hp]」→ Y
    ("dealt", re.compile(_NAME + r" は " + _NAME + r" を .+?で攻撃した\. \[" + _NUM + r" hp\]"), 2, 3),
    # 攻撃 (MP): 「X は Y を W で攻撃した. [N mp]」→ Y
    ("mpdmg", re.compile(_NAME + r" は " + _NAME + r" を .+?で攻撃した\. \[" + _NUM + r" mp\]"), 2, 3),
    # 吸収 (攻撃): 「Y は X の W による攻撃を吸収した. [N hp]」→ Y
    ("heal", re.compile(_NAME + r" は " + _NAME + r" の .+?による攻撃を吸収した\. \[" + _NUM + r" hp\]"), 1, 3),
    # 吸収 (魔法・罠): 「Y は ... を吸収した. [N mp]」→ Y
    ("mp", re.compile(_NAME + r" は .+? を吸収した\. \[" + _NUM + r" mp\]"), 1, 2),
    # 罠: 「Y は S からダメージを受けた. [N hp]」
    ("taken", re.compile(_NAME + r" は .+? からダメージを受けた\. \[" + _NUM + r" hp\]"), 1, 2),
    # 罠 (MP)
    ("mpdmg", re.compile(_NAME + r" は .+? からダメージを受けた\. \[" + _NUM + r" mp\]"), 1, 2),
    # 暴発 (周囲): 「X は 魔法の暴発でダメージを受けた. [N hp]」
    ("taken", re.compile(_NAME + r" は 魔法の暴発でダメージを受けた\. \[" + _NUM + r" hp\]"), 1, 2),
    # 暴発 (自分): 「暴発! ダメージ N hp.」
    ("taken", re.compile(r"暴発! ダメージ\s*" + _NUM + r"\s*hp"), None, 1),
    # 治療 (自分): 「X が S によって回復した. [N hp]」
    ("heal", re.compile(_NAME + r" が .+?によって回復した\. \[" + _NUM + r" hp\]"), 1, 2),
    # 治療 (他): 「X は Y を S で回復した. [N hp]」→ Y
    ("heal", re.compile(_NAME + r" は " + _NAME + r" を .+?で回復した\. \[" + _NUM + r" hp\]"), 2, 3),
    # 治療 (他・MP)
    ("mp", re.compile(_NAME + r" は " + _NAME + r" を .+?で回復した\. \[" + _NUM + r" mp\]"), 2, 3),
    # 食べ物 (MP回復・周囲): 「X は S で回復した. [N mp]」
    ("mp", re.compile(_NAME + r" は .+?で回復した\. \[" + _NUM + r" mp\]"), 1, 2),
    # 食べ物 (MP回復・自分): 「(しかし) X は N mp 回復した.」
    ("mp", re.compile(r"(?:しかし )?" + _NAME + r" は " + _NUM + r"\s*mp 回復した"), 1, 2),
    # 食べ物 (食中毒): 「X は食中毒でダメージを受けた. [N mp]」
    ("mpdmg", re.compile(_NAME + r" は食中毒でダメージを受けた\. \[" + _NUM + r" mp\]"), 1, 2),
    # 食べ物 (ダメージ・周囲): 「X は S でダメージを受けた. [N mp]」
    ("mpdmg", re.compile(_NAME + r" は .+?でダメージを受けた\. \[" + _NUM + r" mp\]"), 1, 2),
]


def parse_floats(text: str) -> list[FloatEvent]:
    """ログの1行から、浮かべる数字を抜き出します。

    当てはまる型がなければ、空の表を返します。1行に1つまでです。
    """
    text = _normalize(text)
    for kind, pattern, name_group, amount_group in _PATTERNS:
        hit = pattern.search(text)
        if hit is None:
            continue
        target = None
        if name_group is not None:
            target = hit.group(name_group).strip()
            if not target:
                continue
        amount = int(hit.group(amount_group).replace(",", ""))
        return [FloatEvent(kind=kind, target=target, amount=amount)]
    return []
