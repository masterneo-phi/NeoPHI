"""CLI とモックサーバを別プロセスで動かす、端から端までの確認。"""

import os
import subprocess
import sys
import time
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


class TestCliMock(unittest.TestCase):
    def test_cli_connects_moves_and_quits(self):
        env = dict(os.environ)
        env["PHI_ID"] = "TESTID"
        env["PYTHONPATH"] = str(ROOT)
        mock = subprocess.Popen(
            [sys.executable, str(ROOT / "tools" / "mock_server.py"),
             "--host", "127.0.0.1", "--port", "0"],
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
            text=True, env=env,
        )
        try:
            # モックは --port 0 だと実際のポートを出す
            line = mock.stdout.readline()
            self.assertIn("待っています", line)
            port = int(line.rsplit(":", 1)[1].split()[0])
            cli = subprocess.Popen(
                [sys.executable, "-m", "neophi.cli",
                 "--host", "127.0.0.1", "--port", str(port)],
                stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                stderr=subprocess.PIPE, text=True, env=env,
            )
            # 人が打つ間隔で送る。全部を一度に送ると、/quit の切断が
            # サーバの返事より先に処理されてしまう事がある
            assert cli.stdin is not None
            for line in ("go N", "get", "1", "/quit"):
                cli.stdin.write(line + "\n")
                cli.stdin.flush()
                time.sleep(0.4)
            out, err = cli.communicate(timeout=20)
            self.assertIn("サーバーに接続します", out)
            self.assertIn("モックサーバへようこそ", out)
            self.assertIn("地図 7x7", out)
            self.assertIn("拾いました", out)
            self.assertIn("切断しました", out)
            self.assertEqual(cli.returncode, 0, err)
        finally:
            mock.terminate()
            try:
                mock.wait(timeout=5)
            except subprocess.TimeoutExpired:
                mock.kill()
            if mock.stdout is not None:
                mock.stdout.close()

    def test_cli_help_and_tui_help(self):
        env = dict(os.environ)
        env["PYTHONPATH"] = str(ROOT)
        for module in ("neophi.cli", "neophi.tui"):
            proc = subprocess.run(
                [sys.executable, "-m", module, "--help"],
                capture_output=True, text=True, timeout=10, env=env,
            )
            self.assertEqual(proc.returncode, 0, proc.stderr)
            self.assertIn("--host", proc.stdout)


if __name__ == "__main__":
    unittest.main()
