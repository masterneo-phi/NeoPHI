"""テスト用の BMP を作る道具。"""

import struct


def make_bmp(width, height, bpp, rows, palette=None, top_down=False):
    """BMP のバイト列を作ります。

    ``rows`` は上から下への画素の行で、24/32bpp なら (r, g, b) の組、
    1/4/8bpp ならパレットの番号です。``palette`` は (r, g, b) の列です。
    """
    colors = palette or []
    header_size = 40
    palette_size = len(colors) * 4 if bpp <= 8 else 0
    offset = 14 + header_size + palette_size
    stride = ((bpp * width + 31) // 32) * 4
    body = bytearray()
    ordered = rows if top_down else list(reversed(rows))
    for row in ordered:
        line = bytearray()
        if bpp == 24:
            for r, g, b in row:
                line += bytes([b, g, r])
        elif bpp == 32:
            for r, g, b in row:
                line += bytes([b, g, r, 255])
        elif bpp == 8:
            line += bytes(row)
        elif bpp == 4:
            for i in range(0, width, 2):
                hi = row[i]
                lo = row[i + 1] if i + 1 < width else 0
                line.append((hi << 4) | lo)
        elif bpp == 1:
            for i in range(0, width, 8):
                byte = 0
                for k in range(8):
                    if i + k < width:
                        byte |= row[i + k] << (7 - k)
                line.append(byte)
        else:
            raise ValueError(bpp)
        line += b"\x00" * (stride - len(line))
        body += line
    dib_height = -height if top_down else height
    header = struct.pack(
        "<IiiHHIIiiII", header_size, width, dib_height, 1, bpp, 0,
        len(body), 0, 0, len(colors), 0,
    )
    palette_bytes = b"".join(bytes([b, g, r, 0]) for r, g, b in colors)
    file_header = b"BM" + struct.pack("<IHHI", offset + len(body), 0, 0, offset)
    return file_header + header + palette_bytes + bytes(body)


def solid_rows(width, height, value):
    return [[value] * width for _ in range(height)]
