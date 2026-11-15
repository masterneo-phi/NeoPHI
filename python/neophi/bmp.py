"""BMP の読み込みと、透過を付けた RGBA 画像。

Philly のグラフィックスは BMP だけです。標準ライブラリだけで読むために、
ここで BMP を直接解釈します。対応するのは無圧縮(BI_RGB)の
1/4/8 ビット(パレット付き)と 24/32 ビットで、上下どちらの向きにも対応します。
同梱のグラフィックスはすべてこの範囲です(BITMAPINFOHEADER・無圧縮・下から上)。

透過の付け方は wphi の ``src-tauri/src/assets.rs`` と同じです。
"""

from __future__ import annotations

import struct

__all__ = [
    "BmpError",
    "RgbaImage",
    "colorkey",
    "decode_bmp",
    "mask_h",
    "mask_v",
]

# マスクの白の閾値。超えたら不透明(assets.rs の MASK_WHITE)。
MASK_WHITE = 200
# キャラグラの透過色(assets.rs の TEAL)。
TEAL = (0, 128, 128)


class BmpError(ValueError):
    """読めない BMP です。"""


class RgbaImage:
    """RGBA の画素列。一番上の行から順に、1画素 4 バイトで並べます。"""

    __slots__ = ("width", "height", "pixels")

    def __init__(
        self,
        width: int,
        height: int,
        pixels: bytes | bytearray | None = None,
        fill: tuple[int, int, int, int] = (0, 0, 0, 255),
    ) -> None:
        self.width = width
        self.height = height
        if pixels is not None:
            data = bytearray(pixels)
            if len(data) != width * height * 4:
                raise ValueError("画素列の大きさが合いません")
            self.pixels = data
        else:
            self.pixels = bytearray(fill * (width * height))

    def pixel(self, x: int, y: int) -> tuple[int, int, int, int]:
        i = (y * self.width + x) * 4
        p = self.pixels
        return p[i], p[i + 1], p[i + 2], p[i + 3]

    def set_pixel(self, x: int, y: int, rgba: tuple[int, int, int, int]) -> None:
        i = (y * self.width + x) * 4
        self.pixels[i : i + 4] = bytes(rgba)

    def fill_rect(
        self, x: int, y: int, w: int, h: int, rgba: tuple[int, int, int, int]
    ) -> None:
        x0, y0 = max(0, x), max(0, y)
        x1, y1 = min(self.width, x + w), min(self.height, y + h)
        if x1 <= x0 or y1 <= y0:
            return
        row = bytes(rgba) * (x1 - x0)
        for yy in range(y0, y1):
            i = (yy * self.width + x0) * 4
            self.pixels[i : i + len(row)] = row

    def blit(
        self,
        src: RgbaImage,
        sx: int,
        sy: int,
        sw: int,
        sh: int,
        dx: int,
        dy: int,
    ) -> None:
        """``src`` の矩形を重ねます。はみ出た分は切り、透明な画素は飛ばします。"""
        if sx < 0:
            dx -= sx
            sw += sx
            sx = 0
        if sy < 0:
            dy -= sy
            sh += sy
            sy = 0
        if dx < 0:
            sx -= dx
            sw += dx
            dx = 0
        if dy < 0:
            sy -= dy
            sh += dy
            dy = 0
        sw = min(sw, src.width - sx, self.width - dx)
        sh = min(sh, src.height - sy, self.height - dy)
        if sw <= 0 or sh <= 0:
            return
        dst = self.pixels
        sdata = src.pixels
        dw = self.width
        swd = src.width
        for row in range(sh):
            si = ((sy + row) * swd + sx) * 4
            di = ((dy + row) * dw + dx) * 4
            for _ in range(sw):
                sa = sdata[si + 3]
                if sa == 255:
                    dst[di : di + 4] = sdata[si : si + 4]
                elif sa:
                    # src-over。半透明はグラフィックスには無いが、念のため混ぜる
                    inv = 255 - sa
                    dst[di] = (sdata[si] * sa + dst[di] * inv) // 255
                    dst[di + 1] = (sdata[si + 1] * sa + dst[di + 1] * inv) // 255
                    dst[di + 2] = (sdata[si + 2] * sa + dst[di + 2] * inv) // 255
                    dst[di + 3] = max(dst[di + 3], sa)
                si += 4
                di += 4

    def blit_scaled(
        self,
        src: RgbaImage,
        sx: int,
        sy: int,
        sw: int,
        sh: int,
        dx: int,
        dy: int,
        dw: int,
        dh: int,
    ) -> None:
        """最も近い画素で拡大・縮小して重ねます(magnify 用)。"""
        if sw <= 0 or sh <= 0 or dw <= 0 or dh <= 0:
            return
        for row in range(dh):
            yy = dy + row
            if yy < 0 or yy >= self.height:
                continue
            src_y = sy + (row * sh) // dh
            if src_y < 0 or src_y >= src.height:
                continue
            for col in range(dw):
                xx = dx + col
                if xx < 0 or xx >= self.width:
                    continue
                src_x = sx + (col * sw) // dw
                if src_x < 0 or src_x >= src.width:
                    continue
                i = (src_y * src.width + src_x) * 4
                sa = src.pixels[i + 3]
                if sa == 255:
                    j = (yy * self.width + xx) * 4
                    self.pixels[j : j + 4] = src.pixels[i : i + 4]
                elif sa:
                    j = (yy * self.width + xx) * 4
                    inv = 255 - sa
                    p = self.pixels
                    p[j] = (src.pixels[i] * sa + p[j] * inv) // 255
                    p[j + 1] = (src.pixels[i + 1] * sa + p[j + 1] * inv) // 255
                    p[j + 2] = (src.pixels[i + 2] * sa + p[j + 2] * inv) // 255
                    p[j + 3] = max(p[j + 3], sa)


def fade_alpha(image: RgbaImage, factor: float) -> RgbaImage:
    """不透明度を ``factor`` 倍にしたコピーを返します。色は変えません。"""
    pixels = bytearray(image.pixels)
    for i in range(3, len(pixels), 4):
        pixels[i] = int(pixels[i] * factor)
    return RgbaImage(image.width, image.height, pixels)


def decode_bmp(data: bytes) -> RgbaImage:
    """BMP のバイト列を RGB の画像にします。アルファはすべて不透明です。"""
    if len(data) < 54 or data[:2] != b"BM":
        raise BmpError("BMP ではありません")
    offset = struct.unpack_from("<I", data, 10)[0]
    header_size = struct.unpack_from("<I", data, 14)[0]
    if header_size < 40:
        raise BmpError(f"対応していない BMP ヘッダです: {header_size}")
    width = struct.unpack_from("<i", data, 18)[0]
    height = struct.unpack_from("<i", data, 22)[0]
    bpp = struct.unpack_from("<H", data, 28)[0]
    compression = struct.unpack_from("<I", data, 30)[0]
    if compression != 0:
        raise BmpError(f"圧縮された BMP には対応していません: {compression}")
    if width <= 0 or height == 0:
        raise BmpError(f"変な大きさです: {width}x{height}")
    top_down = height < 0
    height = abs(height)
    if bpp not in (1, 4, 8, 24, 32):
        raise BmpError(f"対応していない色数です: {bpp}bpp")

    palette: list[tuple[int, int, int]] = []
    if bpp <= 8:
        count = struct.unpack_from("<I", data, 46)[0] or (1 << bpp)
        pal_off = 14 + header_size
        for i in range(count):
            j = pal_off + i * 4
            if j + 4 > len(data):
                raise BmpError("パレットが途中で切れています")
            b, g, r = data[j], data[j + 1], data[j + 2]
            palette.append((r, g, b))

    stride = ((bpp * width + 31) // 32) * 4
    if offset + stride * height > len(data):
        raise BmpError("画素データが途中で切れています")
    img = RgbaImage(width, height)
    out = img.pixels
    for row in range(height):
        # 下から上の BMP は、読む行を逆にする
        src_row = row if top_down else height - 1 - row
        base = offset + src_row * stride
        di = row * width * 4
        if bpp == 24:
            for x in range(width):
                j = base + x * 3
                out[di] = data[j + 2]
                out[di + 1] = data[j + 1]
                out[di + 2] = data[j]
                out[di + 3] = 255
                di += 4
        elif bpp == 32:
            for x in range(width):
                j = base + x * 4
                out[di] = data[j + 2]
                out[di + 1] = data[j + 1]
                out[di + 2] = data[j]
                out[di + 3] = 255
                di += 4
        elif bpp == 8:
            for x in range(width):
                r, g, b = palette[data[base + x]]
                out[di] = r
                out[di + 1] = g
                out[di + 2] = b
                out[di + 3] = 255
                di += 4
        elif bpp == 4:
            for x in range(width):
                byte = data[base + x // 2]
                idx = (byte >> 4) if x % 2 == 0 else (byte & 0x0F)
                r, g, b = palette[idx]
                out[di] = r
                out[di + 1] = g
                out[di + 2] = b
                out[di + 3] = 255
                di += 4
        else:  # 1bpp
            for x in range(width):
                byte = data[base + x // 8]
                idx = (byte >> (7 - x % 8)) & 1
                r, g, b = palette[idx]
                out[di] = r
                out[di + 1] = g
                out[di + 2] = b
                out[di + 3] = 255
                di += 4
    return img


def colorkey(img: RgbaImage, key: tuple[int, int, int] = TEAL) -> RgbaImage:
    """``key`` の色を透明にします(キャラグラ)。"""
    out = RgbaImage(img.width, img.height, pixels=img.pixels)
    p = out.pixels
    kr, kg, kb = key
    for i in range(0, len(p), 4):
        if p[i] == kr and p[i + 1] == kg and p[i + 2] == kb:
            p[i] = 0
            p[i + 1] = 0
            p[i + 2] = 0
            p[i + 3] = 0
    return out


def _masked(rgb: tuple[int, int, int], mask: tuple[int, int, int]) -> tuple[int, int, int, int]:
    if all(m > MASK_WHITE for m in mask):
        return (*rgb, 255)
    return (0, 0, 0, 0)


def mask_h(img: RgbaImage) -> RgbaImage:
    """左半分が画像、右半分がマスク(マップチップ)。"""
    w = img.width // 2
    out = RgbaImage(w, img.height, fill=(0, 0, 0, 0))
    for y in range(img.height):
        for x in range(w):
            r, g, b, _ = img.pixel(x, y)
            mr, mg, mb, _ = img.pixel(x + w, y)
            out.set_pixel(x, y, _masked((r, g, b), (mr, mg, mb)))
    return out


def mask_v(img: RgbaImage) -> RgbaImage:
    """上半分が画像、下半分がマスク(Items.bmp)。"""
    h = img.height // 2
    out = RgbaImage(img.width, h, fill=(0, 0, 0, 0))
    for y in range(h):
        for x in range(img.width):
            r, g, b, _ = img.pixel(x, y)
            mr, mg, mb, _ = img.pixel(x, y + h)
            out.set_pixel(x, y, _masked((r, g, b), (mr, mg, mb)))
    return out
