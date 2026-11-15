"""PHI の発言タグ(``/*...*/``)を、端末に表示できる素の文字にする。仕様書 §4。

wphi はタグを HTML に変えるが、このクライアントは端末表示なのでタグを除く。
画像の URL は文字として出すだけで、取得はしない(取得すると、受けた人の環境
から LAN の機器へ要求を出させてしまう)。``/*to=名前*/`` は表示からは除き、
宛先の一覧は :func:`extract_to_names` で別に取る。
"""

import re

__all__ = ["extract_to_names", "plain_text", "strip_tags"]

_BR_RE = re.compile(r"/\*br\*/", re.IGNORECASE)
_IMG_RE = re.compile(r"/\*img=(.*?)\*/", re.IGNORECASE)
_IMG_WND_RE = re.compile(r"/\*img_wnd=.*?\*/", re.IGNORECASE)
_TAG_RE = re.compile(r"/\*.*?\*/")
_TO_RE = re.compile(r"/\*to=(.*?)\*/", re.IGNORECASE)


def _img_placeholder(match: re.Match[str]) -> str:
    body = match.group(1).strip()
    # /*img=URL align=.. width=.. height=..*/ の先頭が URL
    url = body.split()[0] if body.split() else ""
    if url:
        return f"[画像: {url}]"
    return "[画像]"


def plain_text(text: str) -> str:
    """タグを除いた表示用の文字を返す。``/*br*/`` は改行になる。"""
    out = _BR_RE.sub("\n", text)
    out = _IMG_WND_RE.sub("", out)
    out = _IMG_RE.sub(_img_placeholder, out)
    out = _TAG_RE.sub("", out)
    out = out.replace("はーと", "♥")
    return out


def strip_tags(text: str) -> str:
    """タグをすべて除く。リストの行の番号読み取りなど、表示しない用途向け。"""
    out = _BR_RE.sub("", text)
    out = _TAG_RE.sub("", out)
    return out


def extract_to_names(text: str) -> list[str]:
    """``/*to=名前*/`` の名前を、現れた順に返す。"""
    return [m.group(1).strip() for m in _TO_RE.finditer(text)]
