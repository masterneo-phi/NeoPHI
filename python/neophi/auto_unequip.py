"""系統魔法の前に武器を外す(仕様書 §7.1)。wphi の ``src-tauri/src/auto_unequip.rs`` の移植。

UI が ``#wphi-cast <1|0> <唱える行をタブで繋いだもの>`` を送ると、セッションは
``unequip`` だけを先に送って唱える行を覚える。届いた装備のリストは画面に出さず
横取りし、1番が武器なら ``1`` を、防具か装身具なら ``.`` を送ってから唱える。
何も装備していなければそのまま唱える。唱える行は5秒で忘れる(wphi と同じ)。

装備し直すかどうかは ``reequip`` の印(``1``)で決める。Philly の
AutoEquipSystemMagic と同じく、既定では装備し直さない。装備し直す時は
``equip <名前>`` を唱える行の後に送り、「を装備した」の1行を出さない。
"""

from __future__ import annotations

__all__ = ["CAST_PREFIX", "AutoUnequip", "first_equipment"]

#: UI から届く、系統魔法を唱える行の頭。サーバへは送らない
CAST_PREFIX = "#wphi-cast "

#: 唱える魔法を覚えておく時間(秒。Philly の AUTO_UNEQUIP__TIME)
KEEP = 5.0

#: 装備が無い時にサーバが返す文言。この行は出さずにそのまま唱える
_NO_EQUIP = ("装備を外せません", "なにも装備していません", "Can not unequip.")

#: リストの後の「外す装備を選択して下さい」。出さない
_PROMPT = ("外す装備を選択して下さい", "Input item number to unequip.")


def first_equipment(text: str) -> tuple[str, str] | None:
    """装備のリストの1番。名前と、Wpn・Arm・Acr のどれかを返す。

    v5y の行は ``     [/*color=cyan*/ 1/*.*/] 名前  Wp  :  5 [/*color=red*/Wpn/*.*/]``
    で、行頭に空白が付く。タグを除いた行の途中から探す(Philly の
    ``\\[ 1\\] (.{0,32})Wp.*?\\[(Wpn|Arm|Acr)\\]``)。``text`` はタグを除いた行。
    """
    idx = text.find("[ 1] ")
    if idx < 0:
        return None
    rest = text[idx + len("[ 1] ") :]
    # v5y は「Wp  : 5」と書く。名前に Wp を含んでも、この欄を使う。
    # 無ければ Philly と同じく最初の Wp
    wp = rest.rfind("Wp  :")
    if wp < 0:
        wp = rest.find("Wp")
    if wp < 0:
        return None
    for kind in ("Wpn", "Arm", "Acr"):
        if f"[{kind}]" in rest[wp:]:
            return rest[:wp].strip(), kind
    return None


class AutoUnequip:
    """唱える行を覚えて、装備のリストを横取りする状態機械。I/O は持たない。"""

    def __init__(self) -> None:
        self.cast: list[str] = []
        self.reequip = False
        #: これより前なら、unequip の返事を待っている
        self.until: float | None = None
        #: 横取りしている装備のリストの中
        self.list_on = False
        #: リストの後の「外す装備を選択して下さい」を出さない
        self.skip_prompt = False
        #: 装備し直した時の「を装備した」を出さない
        self.hide_equipped_until: float | None = None

    def start(self, line: str, now: float) -> str | None:
        """UI の ``#wphi-cast`` の行なら、覚えて先に送る ``unequip`` を返す。"""
        rest = line[len(CAST_PREFIX) :] if line.startswith(CAST_PREFIX) else None
        if rest is None:
            return None
        flag, _, cast = rest.partition(" ")
        self.cast = [c for c in cast.split("\t") if c]
        self.reequip = flag == "1"
        self.until = now + KEEP
        self.list_on = False
        self.skip_prompt = False
        self.hide_equipped_until = None
        return "unequip"

    def enabled(self, now: float) -> bool:
        return self.until is not None and now < self.until

    def active(self, now: float) -> bool:
        """横取りしているか。何もしていない時は、受信の行を文字にせずに済ませる。"""
        return (
            self.enabled(now)
            or self.list_on
            or self.skip_prompt
            or (
                self.hide_equipped_until is not None
                and now < self.hide_equipped_until
            )
        )

    def filter(self, text: str, now: float) -> tuple[bool, list[str]]:
        """受けた行(タグを除いた文字)。出さない行なら True。送る行を返す。

        ``#end-list`` の代わりに ``#ex-list-mode-end`` が来ても、装備の
        リストの終わりとして同じく扱う(このクライアントのパーサも両方を
        リストの終わりにする)。
        """
        reply: list[str] = []
        if self.skip_prompt:
            self.skip_prompt = False
            if any(p in text for p in _PROMPT):
                return True, reply
        if self.enabled(now) and not self.list_on:
            if text == "#list":
                self.list_on = True
                return True, reply
            if any(s in text for s in _NO_EQUIP):
                self._cast_now(None, reply)
                return True, reply
        if self.list_on:
            if text == "#end-list" or text == "#ex-list-mode-end":
                self.list_on = False
                self.skip_prompt = True
                # 1番を読めなかった時も、選ぶのを取り消して唱える。待ったままだと、
                # 5秒の間に届く次のリスト(アイテムを拾う時など)まで横取りしてしまう
                if self.enabled(now):
                    self._cast_now(".", reply)
            elif self.enabled(now):
                found = first_equipment(text)
                if found is not None:
                    name, kind = found
                    if kind == "Wpn":
                        if self.reequip:
                            self.hide_equipped_until = now + KEEP
                        equip = f"equip {name}" if self.reequip else None
                        self._cast_now("1", reply)
                        if equip is not None:
                            reply.append(equip)
                    else:
                        self._cast_now(".", reply)
            return True, reply
        if (
            self.hide_equipped_until is not None
            and now < self.hide_equipped_until
            and "を装備した" in text
        ):
            self.hide_equipped_until = None
            return True, reply
        return False, reply

    def _cast_now(self, answer: str | None, reply: list[str]) -> None:
        if answer is not None:
            reply.append(answer)
        reply.extend(self.cast)
        self.cast = []
        self.until = None
