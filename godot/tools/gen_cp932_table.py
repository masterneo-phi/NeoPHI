"""Python の cp932 コーデックから変換表を作る。Godot 版の cp932_table.json 用。

使い方: python3 tools/gen_cp932_table.py
出力: cp932_table.json（プロジェクト直下）
"""
import json
from pathlib import Path

LEADS = list(range(0x81, 0xA0)) + list(range(0xE0, 0xFD))

single = {}
failed_single = []
for b in range(256):
    try:
        text = bytes([b]).decode("cp932", errors="strict")
    except UnicodeDecodeError:
        failed_single.append(b)
        continue
    assert len(text) == 1, (b, text)
    single[b] = ord(text)

assert failed_single == LEADS, f"lead byte の集合が想定と違う: {failed_single}"

double = {}
for lead in LEADS:
    for trail in range(256):
        try:
            text = bytes([lead, trail]).decode("cp932", errors="strict")
        except UnicodeDecodeError:
            continue
        assert len(text) == 1, (lead, trail, text)
        double[(lead << 8) | trail] = ord(text)

encode = {}
for cp in range(0x10000):
    if 0xD800 <= cp <= 0xDFFF:
        continue
    try:
        raw = chr(cp).encode("cp932", errors="strict")
    except UnicodeEncodeError:
        continue
    assert len(raw) in (1, 2), (cp, raw)
    seq = raw[0] if len(raw) == 1 else (raw[0] << 8) | raw[1]
    encode[cp] = seq

table = {
    "single": {str(k): v for k, v in single.items()},
    "double": {str(k): v for k, v in double.items()},
    "encode": {str(k): v for k, v in encode.items()},
}
out = Path(__file__).resolve().parent.parent / "cp932_table.json"
out.write_text(json.dumps(table, separators=(",", ":")), encoding="utf-8")
print(f"single={len(single)} double={len(double)} encode={len(encode)} -> {out} ({out.stat().st_size} bytes)")
