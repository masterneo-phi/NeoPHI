"""TUI を擬似端末で動かす確認。起動・描画・入力・終了だけを見る。

curses は差分だけを書き出すので、打った文字列がバイト列にそのまま
現れる事はない。1文字ずつ出ている事と、入力欄の助けの行が出る事で確かめる。
"""

import fcntl
import os
import select
import struct
import subprocess
import sys
import termios
import time
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


@unittest.skipUnless(sys.platform != "win32", "pty が必要")
class TestTuiSmoke(unittest.TestCase):
    def test_tui_starts_types_and_quits(self):
        env = dict(os.environ)
        env["PHI_ID"] = "TESTID"
        env["PYTHONPATH"] = str(ROOT)
        env["TERM"] = "xterm"
        mock = subprocess.Popen(
            [sys.executable, str(ROOT / "tools" / "mock_server.py"),
             "--host", "127.0.0.1", "--port", "0"],
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
            text=True, env=env,
        )
        try:
            line = mock.stdout.readline()
            self.assertIn("待っています", line)
            port = int(line.rsplit(":", 1)[1].split()[0])
            master, slave = os.openpty() if hasattr(os, "openpty") else (None, None)
            # openpty が無ければ pty モジュールを使う
            if master is None:
                import pty

                master, slave = pty.openpty()
            fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 30, 100, 0, 0))
            proc = subprocess.Popen(
                [sys.executable, "-m", "neophi.tui",
                 "--host", "127.0.0.1", "--port", str(port)],
                stdin=slave, stdout=slave, stderr=slave, env=env, close_fds=True,
            )
            os.close(slave)
            out = bytearray()

            def drain(seconds: float) -> None:
                end = time.time() + seconds
                while time.time() < end:
                    ready, _, _ = select.select([master], [], [], 0.1)
                    if ready:
                        try:
                            data = os.read(master, 65536)
                        except OSError:
                            break
                        if not data:
                            break
                        out.extend(data)

            try:
                drain(1.5)
                self.assertIn("地図".encode(), bytes(out))
                os.write(master, b"\t")  # 入力欄へ
                drain(0.4)
                for ch in "hi":
                    os.write(master, ch.encode())
                    drain(0.2)
                for ch in "こん":
                    os.write(master, ch.encode("utf-8"))
                    drain(0.2)
                blob = bytes(out)
                self.assertIn("送る".encode(), blob)
                for ch in "hiこん":
                    self.assertIn(ch.encode("utf-8"), blob)
                self.assertNotIn(b"Traceback", blob)
                os.write(master, b"\r")
                drain(0.4)
                os.write(master, b"\x11")  # Ctrl+Q
                rc = proc.wait(timeout=8)
                self.assertEqual(rc, 0)
            finally:
                if proc.poll() is None:
                    proc.kill()
                try:
                    os.close(master)
                except OSError:
                    pass
        finally:
            mock.terminate()
            try:
                mock.wait(timeout=5)
            except subprocess.TimeoutExpired:
                mock.kill()
            if mock.stdout is not None:
                mock.stdout.close()


if __name__ == "__main__":
    unittest.main()
