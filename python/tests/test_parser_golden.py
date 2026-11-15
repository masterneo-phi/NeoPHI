"""wphi の golden データと出力を比べる。

``tests/fixtures/parser.json`` は s7k/wphi の
``crates/phi-proto/tests/golden/parser.json`` (MIT)をそのまま写したもの。
phi-client-web の Python パーサの出力を正解として作られている。
"""

import json
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from neophi.parser import Parser


class TestGolden(unittest.TestCase):
    def test_matches_golden(self):
        fixture = Path(__file__).resolve().parent / "fixtures" / "parser.json"
        golden = json.loads(fixture.read_text(encoding="utf-8"))
        failures: list[str] = []
        for scenario in golden:
            name = scenario["name"]
            parser = Parser()
            for i, step in enumerate(scenario["steps"]):
                line = bytes.fromhex(step["line"])
                got = [event.to_json() for event in parser.feed(line)]
                if got != step["events"]:
                    failures.append(
                        f"{name}[{i}]\n  want {step['events']}\n  got  {got}"
                    )
        self.assertEqual(failures, [])


if __name__ == "__main__":
    unittest.main()
