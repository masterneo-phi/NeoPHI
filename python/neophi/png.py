"""RGBA 画像を PNG のバイト列にします。標準ライブラリだけで書いています。"""

from __future__ import annotations

import struct
import zlib

from .bmp import RgbaImage

__all__ = ["encode_png"]


def _chunk(kind: bytes, data: bytes) -> bytes:
    return (
        struct.pack(">I", len(data))
        + kind
        + data
        + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)
    )


def encode_png(img: RgbaImage) -> bytes:
    """8 ビット RGBA の PNG を作ります。フィルタは使いません。"""
    raw = bytearray()
    stride = img.width * 4
    for y in range(img.height):
        raw.append(0)
        raw += img.pixels[y * stride : (y + 1) * stride]
    ihdr = struct.pack(">IIBBBBB", img.width, img.height, 8, 6, 0, 0, 0)
    return (
        b"\x89PNG\r\n\x1a\n"
        + _chunk(b"IHDR", ihdr)
        + _chunk(b"IDAT", zlib.compress(bytes(raw), level=6))
        + _chunk(b"IEND", b"")
    )
