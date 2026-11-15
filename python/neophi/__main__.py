"""``python -m neophi`` の入り口。既定は行単位のクライアント。"""

from __future__ import annotations

import sys


def main(argv: list[str] | None = None) -> int:
    args = list(sys.argv[1:] if argv is None else argv)
    if args and args[0] == "tui":
        from .tui import main as tui_main

        return tui_main(args[1:])
    if args and args[0] == "gui":
        from .gui import main as gui_main

        return gui_main(args[1:])
    if args and args[0] == "cli":
        from .cli import main as cli_main

        return cli_main(args[1:])
    from .cli import main as cli_main

    return cli_main(args)


if __name__ == "__main__":
    sys.exit(main())
