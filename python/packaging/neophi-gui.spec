# -*- mode: python ; coding: utf-8 -*-
# NeoPHI (GUI) 用の PyInstaller 仕様ファイル。Windows と macOS の両方で使います。
# 使い方: ソースのトップフォルダで `pyinstaller packaging/neophi-gui.spec`
# PyInstaller はクロスコンパイルできないので、Windows 用は Windows で、
# macOS 用は macOS でビルドしてください。
import os
import sys

block_cipher = None
ROOT = os.path.abspath(os.path.join(SPECPATH, ".."))

a = Analysis(
    [os.path.join(SPECPATH, "run_gui.py")],
    pathex=[ROOT],
    binaries=[],
    datas=[],
    hiddenimports=[],
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=[],
    win_no_prefer_redirects=False,
    win_private_assemblies=False,
    cipher=block_cipher,
    noarchive=False,
)
pyz = PYZ(a.pure, a.zipped_data, cipher=block_cipher)

exe = EXE(
    pyz,
    a.scripts,
    [],
    exclude_binaries=True,
    name="NeoPHI",
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=False,
    console=False,
    disable_windowed_traceback=False,
    argv_emulation=False,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
)
coll = COLLECT(
    exe,
    a.binaries,
    a.zipfiles,
    a.datas,
    strip=False,
    upx=False,
    upx_exclude=[],
    name="NeoPHI",
)
if sys.platform == "darwin":
    app = BUNDLE(
        coll,
        name="NeoPHI.app",
        icon=None,
        # 任意の識別子です。公開する時は自分のものに変えてください。
        bundle_identifier="com.example.neophi",
        info_plist={
            "CFBundleName": "NeoPHI",
            "CFBundleDisplayName": "NeoPHI",
            "NSHighResolutionCapable": "True",
        },
    )
