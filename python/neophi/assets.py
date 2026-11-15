"""Philly の BMP を探して、透過を付けた画像で返します。

wphi の ``src-tauri/src/assets.rs`` の移植です。探す場所は、利用者の
Philly フォルダ(先に渡した方を優先)です。Philly と同じフォルダ構成を前提に、
大文字と小文字を無視して探します。グラフィックス自体はこのリポジトリには
含めていません。

名前やグラ名は他のプレイヤーやサーバが決めるので、探す場所の外を指す
パス(``..`` や ``\\`` など)は読みません。LANU 系のグラフィックスも
読みません(2026-11-07 に作者が指定)。
"""

from __future__ import annotations

import os
from pathlib import Path

from .bmp import RgbaImage, colorkey, decode_bmp, mask_h, mask_v
from .codec import decode as decode_cp932

__all__ = ["Assets", "DEFAULT_GRA", "is_lanu", "safe_rel"]

# 使っているスキン(Philly.ini の `SkinName`)。
DEFAULT_SKIN = "Mine"

# `#m57 O` の種別 → スキンの `Chara/Index.txt` のキー
# (Philly `Const.cpp` の SKIN_CHARA_GRA)。
DEFAULT_GRA: tuple[tuple[int, str], ...] = (
    (0x00, "人・銅像"),
    (0x01, "知的生物"),
    (0x02, "獣"),
    (0x03, "狂戦士"),
    (0x04, "魔法生物"),
    (0x05, "アンデッド"),
    (0x06, "精神体"),
    (0x07, "イレイザー"),
    (0x40, "setcg使用キャラ"),
    (0x80, "生物"),
    (0x81, "看板"),
    (0x82, "魔法エフェクト"),
    (0x70, "アニメオブジェ"),
    (0x75, "アニメなしオブジェ"),
)

# 問い合わせの覚えの上限。超えたら全部捨てる(変換済みは残るので変換し直さない)。
_CACHE_LIMIT = 4096


def is_lanu(rel: str) -> bool:
    """LANU 系のグラフィックスか。どこにあっても読みません。"""
    return rel.rsplit("/", 1)[-1].lower().startswith("lanu_")


def safe_rel(rel: str) -> bool:
    """探す場所の外を指さない相対パスか。"""
    return all(
        part and part not in (".", "..") and "\\" not in part and ":" not in part and "\0" not in part
        for part in rel.split("/")
    )


def _find_path(root: Path, rel: str) -> Path | None:
    """``root`` からの相対パスを、大文字と小文字を無視して探します。"""
    path = root
    for part in rel.split("/"):
        exact = path / part
        if exact.exists():
            path = exact
            continue
        lower = part.lower()
        try:
            entries = list(os.scandir(path))
        except OSError:
            return None
        for entry in entries:
            if entry.name.lower() == lower:
                path = Path(entry.path)
                break
        else:
            return None
    return path


def _load_aliases(roots: list[Path]) -> dict[str, str]:
    """``chara/*.ali`` の各行 ``<グラ名> <別名>`` を読みます。

    先に探す場所の定義を優先します。
    """
    aliases: dict[str, str] = {}
    for root in reversed(roots):
        chara_dir = _find_path(root, "chara")
        if chara_dir is None:
            continue
        try:
            entries = list(os.scandir(chara_dir))
        except OSError:
            continue
        for entry in entries:
            if not entry.name.lower().endswith(".ali"):
                continue
            try:
                data = Path(entry.path).read_bytes()
            except OSError:
                continue
            for line in decode_cp932(data).splitlines():
                parts = line.strip().split(None, 1)
                if len(parts) == 2:
                    aliases[parts[1].strip()] = parts[0]
    return aliases


class Assets:
    """グラフィックスの探し場所と、変換した画像の覚え。"""

    def __init__(self, roots: list[str | Path], skin: str = DEFAULT_SKIN) -> None:
        # `roots` は先に探す方から並べます。
        self.roots = [Path(r) for r in roots]
        self.skin = skin
        self._aliases = _load_aliases(self.roots)
        # 問い合わせ(種類・名前・グラ・種別・マップセット) → 画像
        self._cache: dict[str, RgbaImage] = {}
        # 元のファイル(相対パス) → 変換済みの画像
        self._converted: dict[str, RgbaImage] = {}
        # フォルダ → その中の名前(小文字) → パス。一度読んだフォルダは読み直さない
        self._dirs: dict[Path, dict[str, Path]] = {}

    # -- 探す ---------------------------------------------------------------

    def _find(self, root: Path, rel: str) -> Path | None:
        """``root`` からの相対パスを、大文字と小文字を無視して探します。"""
        path = root
        for part in rel.split("/"):
            listing = self._dirs.get(path)
            if listing is None:
                listing = {}
                try:
                    for entry in os.scandir(path):
                        listing[entry.name.lower()] = Path(entry.path)
                except OSError:
                    pass
                self._dirs[path] = listing
            found = listing.get(part.lower())
            if found is None:
                return None
            path = found
        return path

    def exists(self, rel: str) -> bool:
        return safe_rel(rel) and not is_lanu(rel) and any(
            self._find(root, rel) is not None for root in self.roots
        )

    def read(self, rel: str) -> bytes | None:
        if not safe_rel(rel) or is_lanu(rel):
            return None
        for root in self.roots:
            path = self._find(root, rel)
            if path is None:
                continue
            try:
                return path.read_bytes()
            except OSError:
                continue
        return None

    def _open(self, rel: str, convert) -> RgbaImage | None:
        done = self._converted.get(rel)
        if done is not None:
            return done
        data = self.read(rel)
        if data is None:
            return None
        try:
            img = convert(decode_bmp(data))
        except ValueError:
            return None
        self._converted[rel] = img
        return img

    def _remember(self, key: str, img: RgbaImage) -> RgbaImage:
        if len(self._cache) >= _CACHE_LIMIT:
            self._cache.clear()
        self._cache[key] = img
        return img

    # -- 種類ごと -----------------------------------------------------------

    def chara(self, name: str, gra: str, code: int) -> RgbaImage | None:
        """キャラグラの画像(Philly `GraCache.cpp` の解決の順番)。

        setcg(0x40)はグラ名 → 別名 → キャラ名、それ以外は別名 → グラ名 →
        キャラ名の順に探し、無ければ種別ごとの既定グラにします。
        """
        key = f"chara?{name}&{gra}&{code}&"
        cached = self._cache.get(key)
        if cached is not None:
            return cached
        rel = self._chara_rel(name, gra, code)
        if rel is None:
            return None
        img = self._open(rel, colorkey)
        if img is None:
            return None
        return self._remember(key, img)

    def _chara_rel(self, name: str, gra: str, code: int) -> str | None:
        alias = self._aliases.get(name)
        if code == 0x40:
            order = [gra, alias, name]
        else:
            order = [alias, gra, name]
        for candidate in order:
            if not candidate:
                continue
            rel = f"chara/{candidate}.bmp"
            if self.exists(rel):
                return rel
        return self._default_chara_rel(code)

    def _default_chara_rel(self, code: int) -> str | None:
        """種別の既定グラのファイル。スキンの `Chara/Index.txt` を見ます。"""
        key = next((k for c, k in DEFAULT_GRA if c == code), "知的生物")
        index_rel = f"Skins/{self.skin}/Chara/Index.txt"
        for root in self.roots:
            path = self._find(root, index_rel)
            if path is None:
                continue
            try:
                data = path.read_bytes()
            except OSError:
                continue
            file = _index_value(decode_cp932(data), key)
            if file is None:
                continue
            for rel in (
                f"Skins/{self.skin}/Chara/{file}",
                f"chara/{file}",
            ):
                if self.exists(rel):
                    return rel
        return None

    def chip(self, mapset: str) -> RgbaImage | None:
        """マップチップの画像。``chip/<mapset>.bmp`` が無ければ既定のチップ。"""
        key = f"chip?&&&{mapset}"
        cached = self._cache.get(key)
        if cached is not None:
            return cached
        rel = None
        if mapset:
            candidate = f"chip/{mapset}.bmp"
            if self.exists(candidate):
                rel = candidate
        if rel is None:
            rel = f"Skins/{self.skin}/chip/Default.bmp"
        img = self._open(rel, mask_h)
        if img is None:
            return None
        return self._remember(key, img)

    def items(self) -> RgbaImage | None:
        """アイテムの画像(``Skins/<skin>/Images/Items.bmp``)。"""
        key = "items?&&&"
        cached = self._cache.get(key)
        if cached is not None:
            return cached
        img = self._open(f"Skins/{self.skin}/Images/Items.bmp", mask_v)
        if img is None:
            return None
        return self._remember(key, img)


def _index_value(index_text: str, key: str) -> str | None:
    for line in index_text.splitlines():
        if line.lstrip().startswith("//"):
            continue
        if "=" not in line:
            continue
        k, _, v = line.partition("=")
        if k.strip() == key:
            return v.strip()
    return None
