"""GUI を仮想ディスプレイで動かす確認。起動・描画・終了だけを見ます。"""

import os
import shutil
import struct
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BUNDLED = Path.home() / "workspace" / "wphi-source" / "resources" / "phi"


def _tkinter_ok():
    try:
        import tkinter  # noqa: F401

        return True
    except ImportError:
        return False


@unittest.skipUnless(_tkinter_ok(), "tkinter がありません")
@unittest.skipUnless(shutil.which("xvfb-run"), "xvfb-run がありません")
class TestGuiSmoke(unittest.TestCase):
    def _start_mock(self, env):
        mock = subprocess.Popen(
            [sys.executable, str(ROOT / "tools" / "mock_server.py"),
             "--host", "127.0.0.1", "--port", "0"],
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
            text=True, env=env,
        )
        line = mock.stdout.readline()
        self.assertIn("待っています", line)
        port = int(line.rsplit(":", 1)[1].split()[0])
        return mock, port

    def _stop_mock(self, mock):
        mock.terminate()
        try:
            mock.wait(timeout=5)
        except subprocess.TimeoutExpired:
            mock.kill()
        if mock.stdout is not None:
            mock.stdout.close()

    def _run_gui(self, port, snapshot, extra_args, env):
        cmd = [
            "xvfb-run", "-a", sys.executable, "-m", "neophi.gui",
            "--host", "127.0.0.1", "--port", str(port),
            "--auto-quit", "3", "--snapshot", str(snapshot),
        ]
        if BUNDLED.exists():
            cmd += ["--assets-dir", str(BUNDLED)]
        cmd += extra_args
        proc = subprocess.run(
            cmd, capture_output=True, text=True, env=env, timeout=30
        )
        self.assertEqual(proc.returncode, 0, proc.stderr[-2000:])
        self.assertNotIn("Traceback", proc.stderr)
        return proc

    def _snapshot_dims(self, snapshot):
        data = snapshot.read_bytes()
        self.assertTrue(data.startswith(b"\x89PNG\r\n\x1a\n"))
        return struct.unpack(">II", data[16:24])

    def test_gui_runs_renders_and_quits(self):
        env = dict(os.environ)
        env["PHI_ID"] = "TESTID"
        env["PYTHONPATH"] = str(ROOT)
        mock, port = self._start_mock(env)
        try:
            with tempfile.TemporaryDirectory() as tmp:
                snapshot = Path(tmp) / "map.png"
                self._run_gui(port, snapshot, [], env)
                self.assertTrue(snapshot.exists())
                # モックの地図は 7x7
                self.assertEqual(self._snapshot_dims(snapshot), (224, 240))
        finally:
            self._stop_mock(mock)

    def test_gui_quarter_view_renders(self):
        env = dict(os.environ)
        env["PHI_ID"] = "TESTID"
        env["PYTHONPATH"] = str(ROOT)
        mock, port = self._start_mock(env)
        try:
            with tempfile.TemporaryDirectory() as tmp:
                snapshot = Path(tmp) / "map.png"
                self._run_gui(port, snapshot, ["--view", "iso"], env)
                self.assertTrue(snapshot.exists())
                # 7x7 の立体(iso)の大きさ
                self.assertEqual(self._snapshot_dims(snapshot), (272, 160))
        finally:
            self._stop_mock(mock)


class TestKeysymMapping(unittest.TestCase):
    def test_keysym_to_code(self):
        from neophi.gui import _keysym_to_code

        self.assertEqual(_keysym_to_code("Up"), "ArrowUp")
        self.assertEqual(_keysym_to_code("KP_8"), "Numpad8")
        self.assertEqual(_keysym_to_code("a"), "KeyA")
        self.assertEqual(_keysym_to_code("Z"), "KeyZ")
        self.assertEqual(_keysym_to_code("5"), "Digit5")
        self.assertEqual(_keysym_to_code("F5"), "F5")
        self.assertEqual(_keysym_to_code("exclam"), "Digit1")
        self.assertEqual(_keysym_to_code("space"), "Space")
        self.assertIsNone(_keysym_to_code("Meta_L"))


if __name__ == "__main__":
    unittest.main()
