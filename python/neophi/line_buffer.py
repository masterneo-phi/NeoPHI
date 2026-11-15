"""受信バイト列を ``\\n`` で行に分ける。仕様書 §1 と wphi の LineBuffer の移植。

cp932 の2バイト目に 0x0A は現れないので、``\\n`` で切っても2バイト文字は
割れない。行末の ``\\r`` を1つ落とし、空の行は捨てる。1行の上限は 64KiB で、
超えた行は次の ``\\n`` まで丸ごと捨てる。
"""

__all__ = ["MAX_LINE", "LineBuffer"]

#: 1行の上限(バイト)。超えた行は丸ごと捨てる。
MAX_LINE = 64 * 1024


class LineBuffer:
    """未確定の受信分を持ち越し、確定した行を返す。"""

    def __init__(self) -> None:
        self._partial = bytearray()
        #: 上限を超えた行の残りを、次の ``\\n`` まで捨てている
        self._discarding = False

    def feed(self, data: bytes) -> list[bytes]:
        """``data`` を足し、確定した行(``\\n`` を含まない)を返す。"""
        last_nl = data.rfind(b"\n")
        if last_nl < 0:
            self._keep(data)
            return []
        # 最初の部分は、捨てている途中の行の残り
        skip_first = self._discarding
        self._discarding = False
        done = bytes(self._partial) + data[:last_nl]
        self._partial = bytearray()
        self._keep(data[last_nl + 1 :])
        lines = done.split(b"\n")
        if skip_first:
            lines = lines[1:]
        out: list[bytes] = []
        for line in lines:
            if len(line) > MAX_LINE:
                continue
            if line.endswith(b"\r"):
                line = line[:-1]
            if not line:
                continue
            out.append(line)
        return out

    def _keep(self, data: bytes) -> None:
        """未確定分に足す。上限を超えたら、その行を次の ``\\n`` まで捨てる。"""
        if self._discarding:
            return
        if len(self._partial) + len(data) > MAX_LINE:
            self._partial = bytearray()
            self._discarding = True
        else:
            self._partial.extend(data)

    def reset(self) -> None:
        """持ち越し中の未確定分を捨てる(再接続時)。"""
        self._partial = bytearray()
        self._discarding = False
