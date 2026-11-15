#!/bin/sh
# macOS で NeoPHI.app を作ります。
# python.org 版の Python 3.11+ が必要です(Homebrew 版の場合は tcl-tk も)。
set -e
cd "$(dirname "$0")/.."
python3 -m pip install --upgrade pyinstaller
python3 -m PyInstaller packaging/neophi-gui.spec --noconfirm
echo "できました: dist/NeoPHI.app"
echo "署名なしビルドのため、初回は右クリック→「開く」で起動してください。"
