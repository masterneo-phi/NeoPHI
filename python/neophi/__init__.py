"""PHI (v5y) クライアントの Python 実装。標準ライブラリのみで動く。

仕様は s7k/wphi の ``docs/04-client-spec.md`` に基づく。プロトコル層
(``codec`` / ``line_buffer`` / ``parser``)は I/O を持たない純粋な処理だけを
置き、接続は ``session`` が持つ。wphi の ``crates/phi-proto`` に対応する。
"""

from .codec import decode, encode
from .line_buffer import MAX_LINE, LineBuffer
from .parser import Parser

__all__ = ["decode", "encode", "LineBuffer", "MAX_LINE", "Parser"]
