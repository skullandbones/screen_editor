"""
Command-line entry point for native Python SE editor.
Supports syntax: se [filename[:line]] [-l line] [--config path]
"""

import argparse
import os
import sys
from se import __version__
from se.editor import Editor


def parse_filename_and_line(arg: str):
    """Parse 'filename:line' syntax if present."""
    if ":" in arg:
        parts = arg.rsplit(":", 1)
        if parts[1].isdigit():
            return parts[0], int(parts[1])
    return arg, None


def main():
    """Main CLI entry function."""
    parser = argparse.ArgumentParser(
        prog="se",
        description="SE — Screen Editor (Native Python 3 Port for Linux)",
    )
    parser.add_argument(
        "file",
        nargs="?",
        default=None,
        help="Target file to open (supports 'file:line' syntax)",
    )
    parser.add_argument(
        "-l",
        "--line",
        type=int,
        default=None,
        help="Target line number to jump to on start",
    )
    parser.add_argument(
        "--config",
        type=str,
        default=None,
        help="Path to custom SE.CFG configuration file",
    )
    parser.add_argument(
        "-v",
        "--version",
        action="version",
        version=f"%(prog)s {__version__}",
    )

    args = parser.parse_args()

    filename = None
    target_line = args.line

    if args.file:
        parsed_name, parsed_line = parse_filename_and_line(args.file)
        filename = parsed_name
        if parsed_line is not None and target_line is None:
            target_line = parsed_line

    editor = Editor(filename=filename)

    if args.config and os.path.isfile(args.config):
        editor.config.load(args.config)

    if target_line is not None and target_line > 0:
        editor.buffer.cursor_row = max(
            0, min(editor.buffer.total_lines - 1, target_line - 1)
        )

    try:
        editor.run()
    except KeyboardInterrupt:
        pass
    sys.exit(0)


if __name__ == "__main__":
    main()
