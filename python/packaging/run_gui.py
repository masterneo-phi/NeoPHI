"""PyInstaller 用の入り口。GUI クライアントを起動します。"""

import sys

from neophi.gui import main

if __name__ == "__main__":
    sys.exit(main())
