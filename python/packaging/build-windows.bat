@echo off
REM Windows で NeoPHI.exe を作ります。
REM python.org 版の Python 3.11+ が必要です(Tkinter 付きでインストールしてください)。
cd /d %~dp0..
py -3 -m pip install --upgrade pyinstaller
py -3 -m PyInstaller packaging\neophi-gui.spec --noconfirm
echo できました: dist\NeoPHI\NeoPHI.exe
pause
