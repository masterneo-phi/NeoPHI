"""cp932 と UTF-8 の変換。仕様書 §1。

受信で読めないバイトは U+FFFD にし、送信で変換できない文字は ``?`` 1つにする。
Python の ``cp932`` コーデックは phi-client-web と同じ表を使う。wphi (Rust の
``encoding_rs``)とは一部の文字でバイト表現が違う(例: 「髙」は Python が
``EE E0``、Rust が ``FB FC``)。どちらもサーバ側では同じ文字として扱われる
前提だが、気になる場合は実サーバで照合すること。
"""

__all__ = ["decode", "encode"]


def decode(raw: bytes) -> str:
    """cp932 → str。読めないバイトは U+FFFD にする。"""
    return raw.decode("cp932", errors="replace")


def encode(text: str) -> bytes:
    """str → cp932。変換できない文字は ``?`` にする。"""
    return text.encode("cp932", errors="replace")
