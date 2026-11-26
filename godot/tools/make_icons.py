#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""NeoPHI 用 Mine スキンの不足アイコン (20x20 BMP) を生成する。

Philly の Mine スキンには Index.txt に項目が無い / 項目はあるが BMP が
無いアクションがあり、NeoPHI では代替絵 (NoImage.bmp) で表示されて
しまう。本スクリプトはその不足分を、既存アイコンの画風
(Teal 透過・濃い輪郭・鮮やかな色のドット絵) に寄せて描く。

使い方:
    python3 make_icons.py           # BMP を生成して Buttons/ に置く
    python3 make_icons.py --check   # 代替絵に落ちるアクションを数えるだけ

出力形式は既存 BMP と同一: 32bpp BGRA (A=0)、下から上、1654 バイト。
"""

import math
import os
import re
import struct
import sys

from PIL import Image, ImageDraw

BUTTONS = os.path.expanduser(
    "~/workspace/philly-source/PhillySrc/Philly/Skins/Mine/Buttons")
ACTIONS_GD = os.path.expanduser(
    "~/workspace/neophi-godot/scripts/phi_actions.gd")

TEAL = (0, 128, 128)          # 透過色
K = (26, 22, 30)              # 輪郭 (ほぼ黒)
WHITE = (242, 242, 242)
LGRAY = (198, 200, 208)
GRAY = (128, 130, 140)
DGRAY = (70, 72, 82)
STEEL = (172, 182, 198)
STEEL_D = (96, 106, 128)
RED = (216, 52, 44)
RED_D = (150, 26, 22)
ORANGE = (242, 144, 34)
YELLOW = (250, 210, 52)
GOLD = (206, 156, 30)
GREEN = (62, 178, 66)
GREEN_D = (30, 104, 42)
LGREEN = (148, 226, 124)
BLUE = (50, 98, 218)
BLUE_D = (26, 50, 122)
LBLUE = (108, 172, 250)
CYAN = (70, 202, 228)
PURPLE = (154, 82, 204)
PURPLE_D = (94, 42, 146)
LPURPLE = (208, 196, 236)
PINK = (242, 122, 182)
BROWN = (148, 98, 50)
BROWN_D = (96, 60, 28)
TAN = (219, 178, 122)
SKIN = (249, 201, 152)
PAPER = (240, 226, 182)

# 3x5 ドット文字 (数字と少しの記号)
FONT35 = {
    "0": ("111", "101", "101", "101", "111"),
    "1": ("010", "110", "010", "010", "111"),
    "2": ("111", "001", "111", "100", "111"),
    "3": ("111", "001", "111", "001", "111"),
    "4": ("101", "101", "111", "001", "001"),
    "5": ("111", "100", "111", "001", "111"),
    "6": ("111", "100", "111", "101", "111"),
    "7": ("111", "001", "001", "010", "010"),
    "F": ("111", "100", "110", "100", "100"),
    "N": ("101", "111", "101", "101", "101"),
    "I": ("111", "010", "010", "010", "111"),
    "O": ("011", "101", "101", "101", "110"),
    "U": ("101", "101", "101", "101", "111"),
    "T": ("111", "010", "010", "010", "010"),
    "!": ("010", "010", "010", "000", "010"),
    "?": ("111", "001", "011", "000", "010"),
    "+": ("000", "010", "111", "010", "000"),
    "x": ("000", "101", "010", "101", "000"),
    "i": ("010", "000", "110", "010", "111"),
}


def canvas():
    im = Image.new("RGB", (20, 20), TEAL)
    return im, ImageDraw.Draw(im)


def text35(im, x, y, s, color, scale=1):
    """3x5 ドット文字を描く。"""
    px = im.load()
    cx = x
    for ch in s:
        glyph = FONT35[ch]
        for gy, row in enumerate(glyph):
            for gx, bit in enumerate(row):
                if bit == "1":
                    for dy in range(scale):
                        for dx in range(scale):
                            xx, yy = cx + gx * scale + dx, y + gy * scale + dy
                            if 0 <= xx < 20 and 0 <= yy < 20:
                                px[xx, yy] = color
        cx += (3 + 1) * scale


def sparkle(d, cx, cy, r, color):
    """4方向の魔法のきらめき。"""
    pts = [(cx, cy - r), (cx + 1, cy - 1), (cx + r, cy), (cx + 1, cy + 1),
           (cx, cy + r), (cx - 1, cy + 1), (cx - r, cy), (cx - 1, cy - 1)]
    d.polygon(pts, fill=color, outline=K)


def star(d, cx, cy, r_out, r_in, color):
    """5芒星。"""
    pts = []
    for i in range(10):
        r = r_out if i % 2 == 0 else r_in
        a = -math.pi / 2 + i * math.pi / 5
        pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    d.polygon(pts, fill=color, outline=K)


def person(d, cx, top, head_r, body_top, body_half, color):
    """頭+肩の人物シルエット。"""
    d.ellipse([cx - head_r, top, cx + head_r, top + head_r * 2],
              fill=color, outline=K)
    d.rectangle([cx - body_half, body_top, cx + body_half, 18],
                fill=color, outline=K)
    # 肩の角を落とす
    d.point([(cx - body_half, body_top)], fill=color)


def wand(d, x0, y0, x1, y1):
    """杖 (輪郭つきの斜め線)。"""
    d.line([x0, y0, x1, y1], fill=K, width=3)
    d.line([x0, y0, x1, y1], fill=BROWN, width=1)


def arrowhead(d, cx, cy, ang_deg, color, size=3):
    """円弧の接線方向を向く矢じり。ang は PIL 角度 (時計回り)。"""
    a = math.radians(ang_deg)
    # 進行方向 (時計回り接線)
    tx, ty = -math.sin(a), math.cos(a)
    tip = (cx + tx * size, cy + ty * size)
    # 垂直方向
    px_, py_ = math.cos(a), math.sin(a)
    b1 = (cx - tx * 1 + px_ * size * 0.8, cy - ty * 1 + py_ * size * 0.8)
    b2 = (cx - tx * 1 - px_ * size * 0.8, cy - ty * 1 - py_ * size * 0.8)
    d.polygon([tip, b1, b2], fill=color, outline=K)


def gear(d, cx, cy, r, color):
    """小さな歯車。"""
    for dx, dy in [(0, -r), (0, r), (-r, 0), (r, 0),
                   (-r + 1, -r + 1), (r - 1, -r + 1),
                   (-r + 1, r - 1), (r - 1, r - 1)]:
        d.rectangle([cx + dx - 1, cy + dy - 1, cx + dx, cy + dy], fill=color)
    d.ellipse([cx - r + 1, cy - r + 1, cx + r - 1, cy + r - 1],
              fill=color, outline=K)
    d.ellipse([cx - 1, cy - 1, cx + 1, cy + 1], fill=WHITE, outline=K)


def page(d, x0=3, y0=2, x1=14, y1=17, fill=WHITE):
    """折り目つきの書類ページ。"""
    d.rectangle([x0, y0, x1, y1], fill=fill, outline=K)
    fold = min(3, x1 - x0 - 2)
    d.polygon([(x1 - fold, y0), (x1, y0 + fold), (x1 - fold, y0 + fold)],
              fill=LGRAY, outline=K)


# ---------------------------------------------------------------- 個別の絵

def icon_hit():
    im, d = canvas()
    # 剣: 刃 (右上→左下)
    d.line([17, 1, 9, 9], fill=K, width=4)
    d.line([17, 1, 9, 9], fill=(216, 222, 232), width=2)
    # 鍔 (金)
    d.line([5, 8, 11, 14], fill=K, width=4)
    d.line([5, 8, 11, 14], fill=YELLOW, width=2)
    # 柄と柄頭
    d.line([8, 11, 5, 14], fill=BROWN_D, width=3)
    d.ellipse([2, 14, 5, 17], fill=GOLD, outline=K)
    # 切っ先の火花
    d.line([18, 4, 19, 4], fill=ORANGE)
    d.line([16, 0, 16, 1], fill=YELLOW)
    d.point([(19, 1)], fill=ORANGE)
    return im


def icon_check():
    im, d = canvas()
    # レンズ
    d.ellipse([2, 2, 13, 13], fill=(172, 222, 246), outline=K)
    d.ellipse([4, 3, 7, 6], fill=(225, 245, 255))
    # 中のチェック印
    d.line([4, 8, 7, 11], fill=GREEN_D, width=2)
    d.line([7, 11, 12, 5], fill=GREEN_D, width=2)
    # 柄
    d.line([12, 12, 18, 18], fill=K, width=4)
    d.line([12, 12, 18, 18], fill=BROWN, width=2)
    return im


def icon_skills():
    im, d = canvas()
    d.ellipse([2, 2, 17, 17], fill=BLUE, outline=K)
    d.ellipse([4, 4, 15, 15], outline=BLUE_D)
    star(d, 10, 10, 6, 2.6, YELLOW)
    return im


def icon_party_eye():
    im, d = canvas()
    # 左右の小さい人 (先に描く)
    person(d, 4, 5, 2, 11, 3, GREEN)
    person(d, 16, 5, 2, 11, 3, ORANGE)
    # 中央の大きい人
    person(d, 10, 2, 3, 10, 5, BLUE)
    return im


def icon_new_tab():
    im, d = canvas()
    page(d)
    d.ellipse([10, 10, 18, 18], fill=GREEN, outline=K)
    d.rectangle([13, 12, 14, 16], fill=WHITE)
    d.rectangle([12, 13, 16, 14], fill=WHITE)
    return im


def icon_close_tab():
    im, d = canvas()
    page(d)
    d.ellipse([10, 10, 18, 18], fill=RED, outline=K)
    d.line([12, 12, 16, 16], fill=WHITE, width=2)
    d.line([16, 12, 12, 16], fill=WHITE, width=2)
    return im


def icon_say_all_tabs():
    im, d = canvas()
    # 後ろのタブ (ページ) 2枚
    d.rectangle([9, 1, 18, 11], fill=LGRAY, outline=K)
    d.rectangle([6, 3, 15, 13], fill=WHITE, outline=K)
    # 前の吹き出し
    d.rounded_rectangle([1, 8, 12, 16], radius=2, fill=WHITE, outline=K)
    d.polygon([(3, 16), (6, 16), (3, 19)], fill=WHITE, outline=K)
    d.line([3, 16, 6, 16], fill=WHITE)
    for cx in (4, 7, 10):
        d.rectangle([cx - 1, 11, cx, 12], fill=BLUE)
    return im


def icon_talk():
    im, d = canvas()
    # 大きな吹き出し1つ (話しかける)
    d.rounded_rectangle([1, 2, 18, 14], radius=3, fill=WHITE, outline=K)
    d.polygon([(4, 14), (8, 14), (4, 18)], fill=WHITE, outline=K)
    d.line([4, 14, 8, 14], fill=WHITE)
    for cx in (5, 9, 13):
        d.rectangle([cx - 1, 7, cx, 8], fill=BLUE)
    return im


def icon_log_image():
    im, d = canvas()
    # 写真の額 (山と太陽)
    d.rectangle([1, 2, 18, 17], fill=WHITE, outline=K)
    d.polygon([(3, 15), (8, 8), (11, 15)], fill=GREEN, outline=K)
    d.polygon([(9, 15), (13, 10), (16, 15)], fill=GREEN_D, outline=K)
    d.ellipse([13, 4, 16, 7], fill=YELLOW, outline=K)
    return im


def icon_smooth_scroll():
    im, d = canvas()
    # 右へ滑る地図 (格子の四角 + 左に動きの矢印)
    d.rectangle([6, 2, 19, 17], fill=WHITE, outline=K)
    d.line([10, 2, 10, 17], fill=LGRAY)
    d.line([15, 2, 15, 17], fill=LGRAY)
    d.line([6, 7, 19, 7], fill=LGRAY)
    d.line([6, 12, 19, 12], fill=LGRAY)
    d.rectangle([11, 8, 14, 11], fill=GREEN, outline=K)
    # 動きを表す二重のシェブロン
    d.line([0, 5, 3, 8], fill=BLUE, width=2)
    d.line([3, 8, 0, 11], fill=BLUE, width=2)
    d.line([1, 10, 4, 13], fill=BLUE, width=2)
    d.line([4, 13, 1, 16], fill=BLUE, width=2)
    return im


def icon_disp_magic():
    im, d = canvas()
    wand(d, 3, 17, 12, 8)
    d.line([12, 8, 14, 6], fill=K, width=3)
    d.line([12, 8, 14, 6], fill=YELLOW, width=1)
    sparkle(d, 15, 4, 3, PURPLE)
    sparkle(d, 18, 10, 2, CYAN)
    sparkle(d, 9, 3, 2, YELLOW)
    d.point([(17, 16), (5, 6)], fill=PURPLE)
    return im


def icon_disp_map():
    im, d = canvas()
    # 小さな地図 (草と壁と木) + 目のバッジ
    d.rectangle([1, 1, 18, 15], fill=(196, 222, 156), outline=K)
    d.rectangle([2, 8, 7, 14], fill=BROWN, outline=K)
    d.ellipse([11, 2, 17, 9], fill=GREEN_D)
    d.rectangle([13, 8, 14, 11], fill=BROWN)
    d.ellipse([9, 11, 19, 18], fill=WHITE, outline=K)
    d.ellipse([12, 12, 16, 17], fill=BLUE_D)
    d.ellipse([13, 13, 15, 15], fill=K)
    return im


def icon_log_delete_filter():
    im, d = canvas()
    # 上から落ちる点 (ログ行)
    for x, y in ((5, 0), (10, 1), (15, 0)):
        d.rectangle([x, y, x + 1, y + 1], fill=GRAY)
    # 漏斗
    d.rectangle([2, 4, 18, 6], fill=STEEL, outline=K)
    d.polygon([(3, 7), (17, 7), (12, 12), (12, 18), (8, 18), (8, 12)],
              fill=(96, 148, 205), outline=K)
    d.line([6, 9, 14, 9], fill=WHITE)
    return im


def icon_image_window():
    im, d = canvas()
    d.rectangle([2, 3, 17, 16], fill=BROWN, outline=K)
    d.rectangle([4, 5, 15, 14], fill=(122, 192, 246))
    d.ellipse([11, 6, 14, 9], fill=YELLOW)
    d.polygon([(4, 14), (8, 9), (11, 14)], fill=GREEN_D)
    d.polygon([(9, 14), (13, 10), (15, 14)], fill=GREEN)
    return im


def icon_shortcut_config():
    im, d = canvas()
    # キーキャップ
    d.rounded_rectangle([2, 4, 17, 16], radius=2, fill=(228, 231, 238),
                        outline=K)
    d.line([4, 14, 15, 14], fill=GRAY)
    # F の字
    d.rectangle([5, 6, 6, 13], fill=BLUE_D)
    d.rectangle([5, 6, 11, 7], fill=BLUE_D)
    d.rectangle([5, 9, 10, 10], fill=BLUE_D)
    # 歯車 (設定) バッジ
    gear(d, 14, 12, 3, STEEL_D)
    return im


def icon_open_config_folder():
    im, d = canvas()
    # 中の紙
    d.rectangle([5, 2, 14, 8], fill=WHITE, outline=K)
    # フォルダ背面とタブ
    d.rectangle([2, 5, 17, 16], fill=(216, 164, 44), outline=K)
    d.rectangle([2, 3, 8, 6], fill=(216, 164, 44), outline=K)
    d.line([2, 6, 17, 6], fill=(216, 164, 44))
    # 前面 (少し開いた台形)
    d.polygon([(2, 9), (17, 9), (16, 16), (3, 16)],
              fill=(248, 203, 74), outline=K)
    return im


def icon_version_info():
    im, d = canvas()
    d.ellipse([2, 2, 17, 17], fill=(50, 112, 222), outline=K)
    d.ellipse([5, 4, 8, 7], fill=LBLUE)
    d.rectangle([9, 5, 10, 7], fill=WHITE)
    d.rectangle([9, 9, 10, 15], fill=WHITE)
    return im


def icon_read_config_file():
    im, d = canvas()
    page(d, 3, 1, 13, 18)
    for y in (7, 10, 13):
        d.line([5, y, 11, y], fill=GRAY)
    # 歯車バッジ
    d.ellipse([11, 11, 18, 18], fill=LGRAY, outline=K)
    gear(d, 14, 14, 3, STEEL_D)
    return im


def icon_initialize_config():
    im, d = canvas()
    # 戻す円弧 (リング状、右上に隙間と矢じり)
    d.pieslice([1, 1, 18, 18], start=325, end=275, fill=BLUE, outline=K)
    d.ellipse([5, 5, 14, 14], fill=TEAL, outline=K)
    d.polygon([(17, 3), (10, 0), (10, 6)], fill=BLUE, outline=K)
    # 中心のダイヤル
    d.ellipse([8, 8, 11, 11], fill=STEEL_D)
    d.point([(9, 9)], fill=WHITE)
    return im


def icon_initialize_gra_cache():
    im, d = canvas()
    # 小さい絵タイル
    d.rectangle([1, 2, 14, 15], fill=BROWN, outline=K)
    d.rectangle([3, 4, 12, 13], fill=(122, 192, 246))
    d.polygon([(3, 13), (6, 8), (9, 13)], fill=GREEN_D)
    d.polygon([(7, 13), (10, 9), (12, 13)], fill=GREEN)
    # リセットバッジ
    d.ellipse([11, 11, 18, 18], fill=BLUE, outline=K)
    d.arc([12, 12, 17, 17], start=330, end=280, fill=WHITE, width=1)
    d.polygon([(15, 11), (17, 13), (13, 13)], fill=WHITE)
    return im


def icon_exit():
    im, d = canvas()
    # 扉
    d.rectangle([3, 2, 12, 17], fill=BROWN, outline=K)
    d.rectangle([5, 4, 10, 15], fill=TAN, outline=BROWN_D)
    d.point([(10, 10), (11, 10)], fill=GOLD)
    # 外へ出る矢印
    d.polygon([(11, 8), (15, 8), (15, 6), (19, 10), (15, 14), (15, 12),
               (11, 12)], fill=RED, outline=K)
    return im


def icon_board():
    im, d = canvas()
    # 支柱
    d.rectangle([9, 10, 10, 18], fill=BROWN_D, outline=K)
    # 看板
    d.rectangle([2, 2, 17, 10], fill=(203, 152, 86), outline=K)
    d.line([2, 6, 17, 6], fill=BROWN)
    # !
    d.rectangle([9, 3, 10, 6], fill=RED_D)
    d.rectangle([9, 8, 10, 9], fill=RED_D)
    return im


def icon_sort():
    im, d = canvas()
    # 並んだ品物
    for y, color in ((2, (232, 122, 92)), (8, (124, 204, 122)),
                     (14, (124, 164, 242))):
        d.rectangle([2, y, 7, y + 4], fill=color, outline=K)
    # 上下矢印
    d.line([13, 4, 13, 16], fill=K, width=3)
    d.line([13, 4, 13, 16], fill=STEEL_D, width=1)
    d.polygon([(13, 1), (10, 5), (16, 5)], fill=STEEL, outline=K)
    d.polygon([(13, 19), (10, 15), (16, 15)], fill=STEEL, outline=K)
    return im


def icon_floor_item():
    im, d = canvas()
    # 地面
    d.line([1, 16, 18, 16], fill=K, width=2)
    d.line([3, 18, 5, 18], fill=K)
    d.line([14, 18, 16, 18], fill=K)
    # 薬瓶
    d.rectangle([8, 5, 11, 7], fill=TAN, outline=K)
    d.ellipse([6, 7, 13, 16], fill=(222, 62, 72), outline=K)
    d.ellipse([7, 9, 9, 12], fill=(246, 140, 140))
    # 上からの注目マーカー
    d.polygon([(15, 1), (19, 1), (17, 5)], fill=YELLOW, outline=K)
    return im


def icon_identify():
    im, d = canvas()
    # 人物
    d.ellipse([3, 2, 10, 9], fill=SKIN, outline=K)
    d.rectangle([1, 13, 12, 18], fill=BLUE, outline=K)
    d.rectangle([1, 13, 12, 14], fill=BLUE)
    # 虫眼鏡
    d.ellipse([10, 9, 17, 16], fill=(172, 222, 246), outline=K)
    d.line([16, 15, 19, 18], fill=K, width=3)
    d.line([16, 15, 19, 18], fill=BROWN, width=1)
    return im


def icon_forget():
    im, d = canvas()
    # 本の表紙
    d.polygon([(2, 8), (9, 6), (9, 17), (2, 15)], fill=RED_D, outline=K)
    d.polygon([(17, 8), (10, 6), (10, 17), (17, 15)], fill=RED_D, outline=K)
    # ページ
    d.polygon([(3, 8), (9, 6), (9, 16), (3, 14)], fill=WHITE, outline=K)
    d.polygon([(16, 8), (10, 6), (10, 16), (16, 14)], fill=WHITE, outline=K)
    # 消えていく渦 (記憶)
    d.arc([6, 0, 13, 6], start=180, end=360, fill=GRAY, width=1)
    d.point([(14, 2), (16, 1)], fill=GRAY)
    return im


def icon_call():
    im, d = canvas()
    # 魔法陣 (刻印)
    d.ellipse([1, 1, 18, 18], outline=PURPLE_D, width=1)
    d.ellipse([2, 2, 17, 17], outline=PURPLE, width=2)
    d.ellipse([5, 5, 14, 14], outline=PURPLE, width=1)
    d.polygon([(10, 4), (4, 14), (16, 14)], outline=PURPLE_D)
    d.polygon([(10, 16), (4, 6), (16, 6)], outline=PURPLE_D)
    d.ellipse([9, 9, 10, 10], fill=GOLD)
    return im


def icon_return():
    im, d = canvas()
    # 戻る矢印 (左上への弧)
    d.arc([4, 2, 17, 15], start=90, end=180, fill=K, width=5)
    d.arc([4, 2, 17, 15], start=90, end=180, fill=BLUE, width=3)
    d.polygon([(4, 2), (1, 8), (7, 8)], fill=BLUE, outline=K)
    # 刻印 (戻り先)
    d.ellipse([12, 13, 17, 18], outline=PURPLE, width=1)
    d.ellipse([14, 15, 15, 16], fill=PURPLE)
    return im


def icon_eagle_eye_text():
    im, d = canvas()
    # 羊皮紙
    d.rectangle([3, 2, 16, 17], fill=PAPER, outline=K)
    d.line([3, 3, 16, 3], fill=BROWN)
    d.line([3, 16, 16, 16], fill=BROWN)
    # 目
    d.ellipse([6, 4, 13, 8], fill=WHITE, outline=K)
    d.ellipse([8, 5, 11, 8], fill=BLUE, outline=K)
    # 文字の行
    d.line([5, 11, 14, 11], fill=BROWN_D)
    d.line([5, 14, 12, 14], fill=BROWN_D)
    return im


def icon_list():
    im, d = canvas()
    page(d, 3, 1, 16, 18)
    for i, (y, color) in enumerate(((6, RED), (10, GREEN), (14, BLUE))):
        d.ellipse([5, y - 1, 7, y + 1], fill=color, outline=K)
        d.rectangle([9, y - 1, 14, y], fill=LGRAY)
    return im


def icon_destroy():
    im, d = canvas()
    # ハンマー
    d.line([13, 5, 6, 14], fill=K, width=4)
    d.line([13, 5, 6, 14], fill=BROWN, width=2)
    d.rectangle([10, 1, 18, 7], fill=STEEL, outline=K)
    d.rectangle([10, 1, 12, 7], fill=STEEL_D, outline=K)
    # 衝撃の火花
    for pts in ([(2, 12), (4, 14)], [(1, 16), (4, 16)], [(3, 18), (5, 17)]):
        d.line(pts, fill=ORANGE, width=1)
    d.point([(2, 14)], fill=YELLOW)
    return im


def icon_charge_spell():
    im, d = canvas()
    # 宝石
    d.polygon([(5, 5), (14, 5), (17, 9), (10, 17), (3, 9)],
              fill=(84, 204, 238), outline=K)
    d.line([3, 9, 17, 9], fill=(200, 242, 252))
    d.line([5, 5, 7, 9, 10, 17], fill=(200, 242, 252))
    d.line([14, 5, 12, 9, 10, 17], fill=(200, 242, 252))
    d.polygon([(5, 5), (14, 5), (12, 9), (7, 9)], fill=(168, 230, 250))
    # 封印のきらめき
    sparkle(d, 17, 3, 2, PURPLE)
    sparkle(d, 3, 16, 2, GOLD)
    return im


def icon_appear():
    im, d = canvas()
    sparkle(d, 3, 3, 2, GOLD)
    sparkle(d, 17, 4, 2, CYAN)
    # 召還される人物 (頭 + ローブ型の体)
    d.ellipse([7, 3, 12, 8], fill=(172, 122, 232), outline=K)
    d.polygon([(8, 9), (11, 9), (14, 17), (5, 17)],
              fill=(172, 122, 232), outline=K)
    d.line([7, 14, 12, 14], fill=GOLD)
    sparkle(d, 16, 15, 2, PURPLE)
    d.point([(3, 12)], fill=GOLD)
    return im


def icon_disappear():
    im, d = canvas()
    # 薄れていく人物 (薄色 + 右側に消えかけの点)
    col = (186, 176, 224)
    line = (110, 100, 150)
    d.ellipse([4, 3, 10, 9], fill=col, outline=line)
    d.rectangle([2, 12, 12, 17], fill=col, outline=line)
    for x, y in ((12, 5), (13, 8), (12, 13), (13, 16)):
        d.point([(x, y)], fill=TEAL)
    # 下向き矢印 (還す)
    d.rectangle([15, 5, 17, 11], fill=BLUE, outline=K)
    d.polygon([(13, 11), (19, 11), (16, 16)], fill=BLUE, outline=K)
    return im


def icon_cast_n(n):
    im, d = canvas()
    d.rounded_rectangle([1, 1, 18, 18], radius=3, fill=(96, 54, 168),
                        outline=K)
    d.rounded_rectangle([2, 2, 17, 9], radius=3, fill=(116, 72, 190))
    sparkle(d, 4, 4, 2, GOLD)
    text35(im, 7, 5, str(n), WHITE, scale=2)
    d.point([(16, 16)], fill=CYAN)
    return im


def icon_m5x5():
    im, d = canvas()
    d.rectangle([2, 2, 17, 17], fill=(236, 241, 246), outline=K)
    for p in (5, 8, 11, 14):
        d.line([p, 2, p, 17], fill=(122, 132, 142))
        d.line([2, p, 17, p], fill=(122, 132, 142))
    d.rectangle([8, 8, 10, 10], fill=LGREEN)
    return im


def icon_m7x7():
    im, d = canvas()
    d.rectangle([1, 1, 18, 18], fill=(236, 241, 246), outline=K)
    for p in (3, 6, 9, 12, 15):
        d.line([p, 1, p, 18], fill=(122, 132, 142))
        d.line([1, p, 18, p], fill=(122, 132, 142))
    d.rectangle([10, 10, 11, 11], fill=LGREEN)
    return im


def icon_m9x9():
    im, d = canvas()
    d.rectangle([1, 1, 18, 18], fill=(236, 241, 246), outline=K)
    for p in (3, 5, 7, 9, 11, 13, 15, 17):
        d.line([p, 1, p, 18], fill=(122, 132, 142))
        d.line([1, p, 18, p], fill=(122, 132, 142))
    d.rectangle([9, 9, 10, 10], fill=LGREEN)
    return im


def icon_check_update():
    im, d = canvas()
    # 青い円盤に白い下矢印 (新しい版を取りに行く印)
    d.ellipse([2, 2, 17, 17], fill=(50, 112, 222), outline=K)
    d.ellipse([5, 4, 8, 7], fill=LBLUE)
    d.rectangle([9, 5, 10, 11], fill=WHITE)
    d.polygon([(6, 11), (13, 11), (10, 15)], fill=WHITE, outline=K)
    return im


def ring_segment(im, cx, cy, r_in, r_out, a0, a1, color):
    """距離ベースでリングの一部を描く (角度は PIL 式: 右=0、下=90)。"""
    px = im.load()
    for y in range(20):
        for x in range(20):
            dx, dy = x - cx, y - cy
            r = math.hypot(dx, dy)
            if r < r_in or r > r_out:
                continue
            ang = math.degrees(math.atan2(dy, dx)) % 360
            if a0 <= a1:
                inside = a0 <= ang <= a1
            else:
                inside = ang >= a0 or ang <= a1
            if not inside:
                continue
            edge = (r - r_in < 0.9 or r_out - r < 0.9)
            px[x, y] = K if edge else color


def icon_mturn():
    im, d = canvas()
    # 回転サイクル (上の緑と下の青のリング + 矢じり)
    ring_segment(im, 9.5, 9.5, 5.6, 8.4, 185, 335, GREEN)
    ring_segment(im, 9.5, 9.5, 5.6, 8.4, 5, 155, BLUE)
    d.polygon([(17, 10), (18, 5), (13, 7)], fill=GREEN, outline=K)
    d.polygon([(2, 9), (1, 14), (6, 12)], fill=BLUE, outline=K)
    # 中央の小さい地図
    d.rectangle([6, 6, 13, 13], fill=(236, 241, 246), outline=K)
    d.line([10, 6, 10, 13], fill=GRAY)
    d.line([6, 10, 13, 10], fill=GRAY)
    return im


def icon_msolid():
    im, d = canvas()
    # 北の印
    d.polygon([(10, 0), (8, 3), (12, 3)], fill=RED, outline=K)
    # 等角立方体
    d.polygon([(10, 3), (16, 6), (10, 9), (4, 6)], fill=(152, 192, 242),
              outline=K)
    d.polygon([(4, 6), (10, 9), (10, 16), (4, 13)], fill=(72, 112, 192),
              outline=K)
    d.polygon([(10, 9), (16, 6), (16, 13), (10, 16)], fill=(44, 74, 150),
              outline=K)
    return im


def icon_ssmap():
    im, d = canvas()
    # カメラ
    d.rectangle([7, 4, 12, 7], fill=(92, 97, 112), outline=K)
    d.rectangle([2, 7, 17, 17], fill=(92, 97, 112), outline=K)
    d.rectangle([14, 5, 16, 6], fill=YELLOW, outline=K)
    d.rectangle([3, 8, 5, 10], fill=(242, 242, 205), outline=K)
    d.ellipse([6, 9, 13, 16], fill=(40, 45, 62), outline=K)
    d.ellipse([8, 11, 11, 14], fill=(92, 172, 238))
    d.point([(8, 10)], fill=WHITE)
    return im


def icon_log_save():
    im, d = canvas()
    # ログのページ (3行) + 保存の下矢印バッジ
    page(d, 3, 1, 13, 18)
    for y in (6, 9, 12):
        d.line([5, y, 11, y], fill=GRAY)
    d.ellipse([10, 10, 18, 18], fill=GREEN, outline=K)
    d.rectangle([13, 11, 14, 15], fill=WHITE)
    d.polygon([(11, 14), (16, 14), (13, 17)], fill=WHITE)
    return im


def icon_talk_add():
    im, d = canvas()
    # 吹き出し (3点) + 追加の + バッジ
    d.rounded_rectangle([1, 2, 15, 12], radius=2, fill=WHITE, outline=K)
    d.polygon([(4, 12), (7, 12), (4, 15)], fill=WHITE, outline=K)
    d.line([4, 12, 7, 12], fill=WHITE)
    for cx in (4, 7, 11):
        d.rectangle([cx - 1, 6, cx, 7], fill=BLUE)
    d.ellipse([11, 11, 18, 18], fill=GREEN, outline=K)
    d.rectangle([14, 12, 15, 16], fill=WHITE)
    d.rectangle([12, 14, 17, 15], fill=WHITE)
    return im


def icon_unew_panel():
    im, d = canvas()
    # マップチップの格子 (草・道・水・壁) + 取得の下矢印バッジ
    d.rectangle([1, 1, 9, 9], fill=GREEN, outline=K)
    d.rectangle([10, 1, 18, 9], fill=(0xB0, 0x7A, 0x3F), outline=K)
    d.rectangle([1, 10, 9, 18], fill=BLUE, outline=K)
    d.rectangle([10, 10, 18, 18], fill=GRAY, outline=K)
    d.ellipse([10, 10, 18, 18], fill=GREEN, outline=K)
    d.rectangle([13, 11, 14, 15], fill=WHITE)
    d.polygon([(11, 14), (16, 14), (13, 17)], fill=WHITE)
    return im


def icon_play_bgm():
    im, d = canvas()
    # 金の八分音符 (右上に小さな音符も添える)
    d.polygon([(13, 3), (18, 5), (18, 10), (13, 8)], fill=GOLD, outline=K)
    d.rectangle([12, 3, 13, 13], fill=GOLD, outline=K)
    d.ellipse([4, 11, 12, 17], fill=YELLOW, outline=K)
    d.point([(6, 13)], fill=WHITE)
    d.rectangle([17, 9, 17, 15], fill=STEEL, outline=K)
    d.ellipse([14, 13, 18, 17], fill=STEEL, outline=K)
    return im


def icon_v6_bag():
    im, d = canvas()
    # 取っ手
    d.rectangle([8, 1, 11, 3], fill=BROWN, outline=K)
    # 本体 (革の鞄)
    d.rounded_rectangle([4, 3, 15, 17], radius=2, fill=TAN, outline=K)
    # 蓋
    d.rectangle([4, 3, 15, 8], fill=BROWN, outline=K)
    d.point([(6, 5), (13, 5)], fill=TAN)
    # 中央のベルトと金の留め具
    d.rectangle([9, 8, 10, 17], fill=BROWN_D)
    d.rectangle([8, 11, 11, 13], fill=GOLD, outline=K)
    return im


def icon_v6_trade():
    im, d = canvas()
    # 交換の矢印 (上: 右向き橙、下: 左向き青)
    d.polygon([(2, 5), (12, 5), (12, 3), (18, 6), (12, 9), (12, 7),
               (2, 7)], fill=ORANGE, outline=K)
    d.polygon([(17, 12), (7, 12), (7, 10), (1, 13), (7, 16), (7, 14),
               (17, 14)], fill=BLUE, outline=K)
    return im


def icon_v6_quests():
    im, d = canvas()
    # 巻物の紙
    d.rectangle([5, 3, 14, 16], fill=PAPER, outline=K)
    # 上下の巻き
    d.rectangle([4, 2, 15, 4], fill=TAN, outline=K)
    d.rectangle([4, 15, 15, 17], fill=TAN, outline=K)
    # 依頼文の行
    d.line([7, 8, 12, 8], fill=BROWN_D)
    d.line([7, 11, 10, 11], fill=BROWN_D)
    # 朱の封印
    d.ellipse([11, 11, 15, 15], fill=RED, outline=K)
    d.line([12, 13, 14, 13], fill=WHITE)
    return im


# アクション名 -> (ファイル名, 生成関数)
def globe(d, x0, y0, x1, y1):
    """接続系アイコンの地球 (Open/Close の画風)。"""
    d.ellipse([x0, y0, x1, y1], fill=LBLUE, outline=K)
    cx, cy = (x0 + x1) // 2, (y0 + y1) // 2
    r = max(2, (x1 - x0) // 4)
    d.ellipse([cx - r, cy - r, cx, cy + 1], fill=GREEN)
    d.ellipse([cx, cy + 1, cx + r, cy + r + 1], fill=GREEN_D)


def icon_force_close():
    im, d = canvas()
    globe(d, 3, 1, 16, 14)
    # 強制 = 稲妻
    d.polygon([(12, 5), (7, 12), (10, 12), (8, 18), (14, 10), (11, 10)],
              fill=YELLOW, outline=K)
    return im


def icon_open_all():
    im, d = canvas()
    globe(d, 1, 2, 10, 12)
    globe(d, 9, 2, 18, 12)
    text35(im, 7, 14, "IN", RED)
    return im


def icon_close_all():
    im, d = canvas()
    globe(d, 1, 2, 10, 12)
    globe(d, 9, 2, 18, 12)
    text35(im, 4, 14, "OUT", ORANGE)
    return im


def icon_create_character():
    im, d = canvas()
    person(d, 9, 1, 4, 9, 6, BLUE)
    # 新規 = 緑の + バッジ
    d.ellipse([11, 11, 18, 18], fill=GREEN, outline=K)
    d.line([14, 12, 14, 17], fill=WHITE, width=2)
    d.line([12, 14, 17, 14], fill=WHITE, width=2)
    return im


def icon_import_character():
    im, d = canvas()
    # フォルダ (キャラデータの置き場所)
    d.polygon([(2, 5), (8, 5), (10, 7), (18, 7), (18, 16), (2, 16)],
              fill=(240, 196, 84), outline=K)
    d.line([2, 7, 18, 7], fill=(206, 156, 30), width=1)
    # 読み込み = 下向き矢印のバッジ
    d.ellipse([10, 9, 19, 18], fill=BLUE, outline=K)
    d.line([14, 11, 14, 15], fill=WHITE, width=2)
    d.polygon([(12, 14), (17, 14), (14, 17)], fill=WHITE)
    return im


def icon_chara_entry():
    im, d = canvas()
    d.rounded_rectangle([2, 1, 17, 18], radius=2, fill=(52, 56, 72),
                        outline=K)
    person(d, 9, 3, 3, 10, 5, GOLD)
    return im


def icon_next_tab():
    im, d = canvas()
    d.rectangle([7, 2, 17, 12], fill=LGRAY, outline=K)
    d.rectangle([2, 5, 12, 16], fill=WHITE, outline=K)
    d.polygon([(12, 7), (18, 11), (12, 15)], fill=ORANGE, outline=K)
    return im


def icon_prev_tab():
    im, d = canvas()
    d.rectangle([2, 2, 12, 12], fill=LGRAY, outline=K)
    d.rectangle([7, 5, 17, 16], fill=WHITE, outline=K)
    d.polygon([(7, 7), (1, 11), (7, 15)], fill=ORANGE, outline=K)
    return im


def icon_mm_move():
    im, d = canvas()
    d.line([2, 6, 6, 6], fill=CYAN, width=2)
    d.line([2, 13, 6, 13], fill=CYAN, width=2)
    d.polygon([(5, 4), (12, 9), (5, 14)], fill=CYAN, outline=K)
    d.polygon([(11, 4), (18, 9), (11, 14)], fill=LBLUE, outline=K)
    return im


def icon_mm_normal():
    im, d = canvas()
    wand(d, 4, 16, 12, 8)
    star(d, 15, 5, 4, 2, GOLD)
    sparkle(d, 8, 4, 2, LPURPLE)
    return im


def icon_mm_operate():
    im, d = canvas()
    gear(d, 10, 10, 7, STEEL)
    sparkle(d, 10, 10, 3, PURPLE)
    return im


def icon_mm_create():
    im, d = canvas()
    d.rectangle([3, 2, 12, 7], fill=STEEL, outline=K)
    d.line([8, 7, 13, 16], fill=BROWN_D, width=3)
    d.line([8, 7, 13, 16], fill=BROWN, width=1)
    sparkle(d, 16, 4, 2, GOLD)
    sparkle(d, 5, 12, 2, CYAN)
    return im


def icon_mm_world_stop():
    im, d = canvas()
    d.rectangle([5, 1, 14, 3], fill=GOLD, outline=K)
    d.rectangle([5, 16, 14, 18], fill=GOLD, outline=K)
    d.polygon([(6, 3), (13, 3), (10, 9)], fill=LBLUE, outline=K)
    d.polygon([(6, 16), (13, 16), (10, 10)], fill=LBLUE, outline=K)
    d.polygon([(8, 16), (12, 16), (10, 12)], fill=PURPLE)
    return im


def icon_play_se():
    im, d = canvas()
    # スピーカー
    d.rectangle([2, 8, 6, 12], fill=STEEL, outline=K)
    d.polygon([(6, 8), (11, 4), (11, 16), (6, 12)], fill=STEEL, outline=K)
    # 音の波
    d.arc([11, 6, 17, 14], start=-60, end=60, fill=CYAN, width=2)
    d.arc([13, 4, 19, 16], start=-60, end=60, fill=LBLUE, width=2)
    return im


def icon_sound_test():
    im, d = canvas()
    # スピーカー
    d.rectangle([1, 8, 4, 12], fill=STEEL, outline=K)
    d.polygon([(4, 8), (8, 5), (8, 15), (4, 12)], fill=STEEL, outline=K)
    # 音符
    d.ellipse([11, 11, 15, 14], fill=GOLD, outline=K)
    d.line([14, 11, 14, 4], fill=GOLD, width=2)
    d.line([14, 4, 17, 5], fill=GOLD, width=2)
    return im


def icon_chip_viewer():
    im, d = canvas()
    # 2x2 のチップ
    d.rectangle([1, 1, 9, 9], fill=GREEN, outline=K)
    d.rectangle([10, 1, 18, 9], fill=BLUE, outline=K)
    d.rectangle([1, 10, 9, 18], fill=(150, 100, 60), outline=K)
    d.rectangle([10, 10, 18, 18], fill=(90, 140, 70), outline=K)
    d.ellipse([12, 11, 16, 15], fill=(40, 110, 40), outline=K)
    return im


def icon_chara_viewer():
    im, d = canvas()
    # 人物 (キャラグラ)
    d.ellipse([6, 1, 12, 7], fill=SKIN, outline=K)
    d.rectangle([5, 7, 13, 14], fill=LBLUE, outline=K)
    d.line([6, 14, 6, 18], fill=K, width=2)
    d.line([12, 14, 12, 18], fill=K, width=2)
    d.line([5, 9, 2, 12], fill=K, width=2)
    d.line([13, 9, 16, 12], fill=K, width=2)
    return im


def icon_master_magic():
    im, d = canvas()
    d.ellipse([4, 3, 15, 14], fill=PURPLE, outline=K)
    d.ellipse([6, 5, 9, 8], fill=LPURPLE)
    sparkle(d, 16, 4, 2, GOLD)
    sparkle(d, 3, 15, 2, CYAN)
    return im


def icon_master_magic_always():
    im, d = canvas()
    # 超魔法の紫のオーブ + 「常に出す」の目バッジ
    d.ellipse([2, 2, 13, 13], fill=PURPLE, outline=K)
    d.ellipse([4, 4, 7, 7], fill=LPURPLE)
    sparkle(d, 15, 3, 2, GOLD)
    # 目 (常に表示)
    d.ellipse([9, 11, 19, 18], fill=WHITE, outline=K)
    d.ellipse([12, 12, 16, 17], fill=BLUE_D)
    d.ellipse([13, 13, 15, 15], fill=K)
    return im


def icon_ui_style_float():
    ## 新スタイル: 地図 (地) の上に窓が浮く。
    im, d = canvas()
    d.rectangle([1, 5, 13, 18], fill=DGRAY, outline=K)
    d.rectangle([6, 1, 18, 12], fill=WHITE, outline=K)
    d.rectangle([7, 2, 17, 4], fill=GOLD)
    d.rectangle([6, 1, 18, 12], outline=K)
    return im


def _align_icon(inner):
    im, d = canvas()
    d.rectangle([1, 3, 18, 16], fill=LGRAY, outline=K)
    d.rectangle(inner, fill=BLUE, outline=K)
    return im


def icon_map_align_center():
    return _align_icon([7, 7, 12, 12])


def icon_map_align_left():
    return _align_icon([2, 7, 7, 12])


def icon_map_align_right():
    return _align_icon([12, 7, 17, 12])


def icon_layout_all_tabs():
    ## 同じ窓が3つ = 全タブにそろえる。
    im, d = canvas()
    for x0 in (0, 7, 14):
        d.rectangle([x0, 6, x0 + 5, 13], fill=WHITE, outline=K)
        d.rectangle([x0 + 1, 7, x0 + 4, 8], fill=GOLD)
    return im


ICONS = {
    "Hit": ("Hit.bmp", icon_hit),
    "UiStyleFloat": ("UiStyleFloat.bmp", icon_ui_style_float),
    "MapAlignCenter": ("MapAlignCenter.bmp", icon_map_align_center),
    "MapAlignLeft": ("MapAlignLeft.bmp", icon_map_align_left),
    "MapAlignRight": ("MapAlignRight.bmp", icon_map_align_right),
    "LayoutToAllTabs": ("LayoutToAllTabs.bmp", icon_layout_all_tabs),
    "Check": ("Check.bmp", icon_check),
    "Skills": ("Skills.bmp", icon_skills),
    "PartyEye": ("PartyEye.bmp", icon_party_eye),
    "NewTab": ("NewTab.bmp", icon_new_tab),
    "CloseTab": ("CloseTab.bmp", icon_close_tab),
    "SayAllTabs": ("SayAllTabs.bmp", icon_say_all_tabs),
    "Talk": ("Talk.bmp", icon_talk),
    "LogImage": ("LogImage.bmp", icon_log_image),
    "SmoothScroll": ("SmoothScroll.bmp", icon_smooth_scroll),
    "DispMagic": ("DispMagic.bmp", icon_disp_magic),
    "DispMap": ("DispMap.bmp", icon_disp_map),
    "LogDeleteFilter": ("LogDeleteFilter.bmp", icon_log_delete_filter),
    "LogSave": ("LogSave.bmp", icon_log_save),
    "ImageWindow": ("ImageWindow.bmp", icon_image_window),
    "ShortcutConfig": ("ShortcutConfig.bmp", icon_shortcut_config),
    "OpenConfigFolder": ("OpenConfigFolder.bmp", icon_open_config_folder),
    "VersionInfo": ("VersionInfo.bmp", icon_version_info),
    "ReadConfigFile": ("ReadConfigFile.bmp", icon_read_config_file),
    "InitializeConfig": ("InitializeConfig.bmp", icon_initialize_config),
    "InitializeGraCache": ("InitializeGraCache.bmp",
                           icon_initialize_gra_cache),
    "Exit": ("Exit.bmp", icon_exit),
    "Board": ("Board.bmp", icon_board),
    "Sort": ("Sort.bmp", icon_sort),
    "FloorItem": ("FloorItem.bmp", icon_floor_item),
    "Identify": ("Identify.bmp", icon_identify),
    "Forget": ("Forget.bmp", icon_forget),
    "Call": ("Call.bmp", icon_call),
    "Return": ("Return.bmp", icon_return),
    "EagleEyeText": ("EagleEyeText.bmp", icon_eagle_eye_text),
    "List": ("List.bmp", icon_list),
    "Destroy": ("Destroy.bmp", icon_destroy),
    "ChargeSpell": ("ChargeSpell.bmp", icon_charge_spell),
    "Appear": ("Appear.bmp", icon_appear),
    "Disappear": ("Disappear.bmp", icon_disappear),
    "M5x5": ("M5x5.bmp", icon_m5x5),
    "M7x7": ("M7x7.bmp", icon_m7x7),
    "M9x9": ("M9x9.bmp", icon_m9x9),
    "CheckUpdate": ("CheckUpdate.bmp", icon_check_update),
    "MTurn": ("MTurn.bmp", icon_mturn),
    "MSolid": ("MSolid.bmp", icon_msolid),
    "SSMap": ("SSMap.bmp", icon_ssmap),
    "TalkAdd": ("TalkAdd.bmp", icon_talk_add),
    "PlayBGM": ("PlayBGM.bmp", icon_play_bgm),
    "UnewPanel": ("UnewPanel.bmp", icon_unew_panel),
    "ForceClose": ("ForceClose.bmp", icon_force_close),
    "OpenAll": ("OpenAll.bmp", icon_open_all),
    "CloseAll": ("CloseAll.bmp", icon_close_all),
    "CreateCharacter": ("CreateCharacter.bmp", icon_create_character),
    "ImportCharacter": ("ImportCharacter.bmp", icon_import_character),
    "NextTab": ("NextTab.bmp", icon_next_tab),
    "PrevTab": ("PrevTab.bmp", icon_prev_tab),
    "CharaEntry": ("CharaEntry.bmp", icon_chara_entry),
    "MMMove": ("MMMove.bmp", icon_mm_move),
    "MMNormal": ("MMNormal.bmp", icon_mm_normal),
    "MMOperate": ("MMOperate.bmp", icon_mm_operate),
    "MMCreate": ("MMCreate.bmp", icon_mm_create),
    "MMWorldStop": ("MMWorldStop.bmp", icon_mm_world_stop),
    "MasterMagic": ("MasterMagic.bmp", icon_master_magic),
    "MasterMagicAlways": ("MasterMagicAlways.bmp", icon_master_magic_always),
    "PlaySE": ("PlaySE.bmp", icon_play_se),
    "SoundTest": ("SoundTest.bmp", icon_sound_test),
    "ChipViewer": ("ChipViewer.bmp", icon_chip_viewer),
    "CharaViewer": ("CharaViewer.bmp", icon_chara_viewer),
    "V6Bag": ("V6Bag.bmp", icon_v6_bag),
    "V6Trade": ("V6Trade.bmp", icon_v6_trade),
    "V6Quests": ("V6Quests.bmp", icon_v6_quests),
}
for _n in range(1, 8):
    ICONS["Cast%d" % _n] = ("Cast%d.bmp" % _n,
                            (lambda n: (lambda: icon_cast_n(n)))(_n))

# Index.txt に項目自体が無いアクション (行を追加する)
NEW_INDEX_ACTIONS = [
    "Hit", "Check", "Skills", "PartyEye", "NewTab", "SayAllTabs",
    "Talk", "LogImage", "SmoothScroll",
    "DispMagic", "DispMap", "LogDeleteFilter", "LogSave", "TalkAdd",
    "ImageWindow", "ShortcutConfig",
    "OpenConfigFolder", "VersionInfo", "PlayBGM", "UnewPanel",
    "M9x9", "CheckUpdate",
    "OpenAll", "CloseAll", "PrevTab", "CharaEntry", "ImportCharacter",
    "MMMove", "MMNormal", "MMOperate", "MMCreate", "MMWorldStop",
    "MasterMagic", "MasterMagicAlways", "PlaySE", "SoundTest",
    "ChipViewer", "CharaViewer",
    "UiStyleFloat", "MapAlignCenter", "MapAlignLeft", "MapAlignRight",
    "LayoutToAllTabs",
    "V6Bag", "V6Trade", "V6Quests",
]

# 既存の BMP を別名で使うアクション (Index.txt に行だけ足す)
INDEX_ALIASES = {
    "ForceCloseAll": "AllForceClose.bmp",
}


def save_bmp(im, path):
    """既存アイコンと同一形式 (32bpp BGRA, A=0, 下から上) で保存。"""
    w, h = im.size
    px = im.load()
    rows = bytearray()
    for y in range(h - 1, -1, -1):
        for x in range(w):
            r, g, b = px[x, y]
            rows += bytes((b, g, r, 0))
    header = b"BM" + struct.pack("<IHHI", 54 + len(rows), 0, 0, 54)
    header += struct.pack("<IiiHHIIiiII", 40, w, h, 1, 32, 0,
                          len(rows), 0, 0, 0, 0)
    with open(path, "wb") as f:
        f.write(header + bytes(rows))


def displayed_actions():
    """phi_actions.gd の MENUS と TOOLBAR に出るアクション名の集合。"""
    with open(ACTIONS_GD, encoding="utf-8") as f:
        src = f.read()
    names = set()
    for const in ("MENUS", "TOOLBAR"):
        m = re.search(r"const %s := (.*?)\n\n" % const, src, re.S)
        if not m:
            raise RuntimeError("const %s が見つからない" % const)
        for token in re.findall(r'"([A-Za-z0-9]+)"', m.group(1)):
            if token not in ("name", "items"):
                names.add(token)
    # MENUS の "name"/"items" キーとメニュー名 (日本語) は正規表現で
    # 拾わない。念のため既知のキー名を除外する。
    names.discard("name")
    names.discard("items")
    # phi_actions.gd の外でメニューに出る項目 (キャラクターメニューと
    # 超魔法メニュー) も数える。
    names |= {
        "ForceCloseAll", "CreateCharacter", "ImportCharacter", "NextTab", "PrevTab",
        "CharaEntry", "MMMove", "MMNormal", "MMOperate", "MMCreate",
        "MMWorldStop", "MasterMagic",
    }
    return names


def index_map():
    """Index.txt (cp932) を {アクション: ファイル名} で読む。"""
    path = os.path.join(BUTTONS, "Index.txt")
    with open(path, "rb") as f:
        text = f.read().decode("cp932")
    out = {}
    for line in text.split("\n"):
        line = line.strip()
        if not line or line.startswith("//") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        out[key.strip()] = value.strip()
    return out


def fallback_actions():
    """button_icon() が NoImage に落ちる表示アクションの一覧。"""
    idx = index_map()
    bad = []
    for action in sorted(displayed_actions()):
        fname = idx.get(action)
        if not fname or not os.path.exists(os.path.join(BUTTONS, fname)):
            bad.append(action)
    return bad


def update_index():
    """Index.txt に無いアクションの行を末尾に追加 (cp932・CRLF 維持)。"""
    path = os.path.join(BUTTONS, "Index.txt")
    with open(path, "rb") as f:
        raw = f.read()
    text = raw.decode("cp932")
    have = index_map()
    lines = []
    for action in NEW_INDEX_ACTIONS:
        if action in have:
            continue
        fname = ICONS[action][0]
        tabs = "\t" * max(1, (24 - len(action) + 7) // 8)
        lines.append("%s%s= %s\r\n" % (action, tabs, fname))
    for action, fname in INDEX_ALIASES.items():
        if action in have:
            continue
        tabs = "\t" * max(1, (24 - len(action) + 7) // 8)
        lines.append("%s%s= %s\r\n" % (action, tabs, fname))
    if not lines:
        return 0
    if not text.endswith("\r\n"):
        lines.insert(0, "\r\n")
    with open(path, "wb") as f:
        f.write(raw + "".join(lines).encode("cp932"))
    return len(lines)


def main():
    if "--check" in sys.argv:
        bad = fallback_actions()
        print("代替絵に落ちる表示アクション: %d 件" % len(bad))
        for action in bad:
            print("  -", action)
        return
    before = fallback_actions()
    print("生成前: 代替絵 %d 件" % len(before))
    for action, (fname, fn) in sorted(ICONS.items()):
        save_bmp(fn(), os.path.join(BUTTONS, fname))
    added = update_index()
    print("BMP %d 件を生成、Index.txt に %d 行追加" % (len(ICONS), added))
    after = fallback_actions()
    print("生成後: 代替絵 %d 件" % len(after))
    for action in after:
        print("  残り:", action)


if __name__ == "__main__":
    main()
