"""
Command-Line Interface for the Z80 Assembly Beautifier and Reformatter.
"""

import sys
import argparse
from typing import List
from .config import FormatterConfig
from .reformatter import Reformatter
from .dialects import DIALECTS

def main(args: List[str] = None):
    parser = argparse.ArgumentParser(
        description="Z80 Assembly Source Beautifier and Multi-Dialect Reformatter"
    )
    parser.add_argument("input_file", nargs="?", help="Input assembly source file (default: stdin)")
    parser.add_argument("-o", "--output", help="Output file (default: stdout)")
    parser.add_argument("-i", "--in-place", action="store_true", help="Reformat file in-place")

    # Dialect Selection
    parser.add_argument("-d", "--dialect", default="z88dk",
                        choices=list(DIALECTS.keys()), help="Source assembler dialect (default: z88dk)")
    parser.add_argument("-t", "--target-dialect", default=None,
                        choices=list(DIALECTS.keys()), help="Target assembler dialect (default: same as source)")

    # Column Alignment Options
    parser.add_argument("--label-col", type=int, default=1, help="1-based label column (default: 1)")
    parser.add_argument("--opcode-col", type=int, default=9, help="1-based opcode column (default: 9)")
    parser.add_argument("--operand-col", type=int, default=17, help="1-based operand column (default: 17)")
    parser.add_argument("--comment-col", type=int, default=41, help="1-based inline comment column (default: 41)")

    # Whitespace & Tabs
    parser.add_argument("--tabs", action="store_true", help="Use hard tabs for column alignment")
    parser.add_argument("--tab-width", type=int, default=8, help="Tab stop width (default: 8)")
    parser.add_argument("--comma-space", action="store_true", help="Insert space after comma in operands")

    # Case Formatting
    parser.add_argument("--case-insn", choices=['upper', 'lower', 'preserve'], default='upper',
                        help="Case for instruction mnemonics (default: upper)")
    parser.add_argument("--case-dir", choices=['upper', 'lower', 'preserve'], default='upper',
                        help="Case for directives (default: upper)")
    parser.add_argument("--case-reg", choices=['upper', 'lower', 'preserve'], default='upper',
                        help="Case for registers (default: upper)")
    parser.add_argument("--case-label", choices=['preserve', 'upper', 'lower'], default='preserve',
                        help="Case for labels (default: preserve)")
    parser.add_argument("-c", "--config", help="Configuration file (SE.CFG or BEAUTIFY.CFG)")

    parsed_args = parser.parse_args(args)

    target_dialect = parsed_args.target_dialect or parsed_args.dialect

    if parsed_args.config:
        from .meta import load_se_cfg
        config = load_se_cfg(parsed_args.config)
        # Allow CLI flags to override config if explicitly specified
        if parsed_args.label_col != 1: config.label_col = parsed_args.label_col
        if parsed_args.opcode_col != 9: config.opcode_col = parsed_args.opcode_col
        if parsed_args.operand_col != 17: config.operand_col = parsed_args.operand_col
        if parsed_args.comment_col != 41: config.comment_col = parsed_args.comment_col
        if parsed_args.tabs: config.use_tabs = True
        if parsed_args.tab_width != 8: config.tab_width = parsed_args.tab_width
        if parsed_args.comma_space: config.space_after_comma = True
    else:
        config = FormatterConfig(
            label_col=parsed_args.label_col,
            opcode_col=parsed_args.opcode_col,
            operand_col=parsed_args.operand_col,
            comment_col=parsed_args.comment_col,
            use_tabs=parsed_args.tabs,
            tab_width=parsed_args.tab_width,
            instruction_case=parsed_args.case_insn,
            directive_case=parsed_args.case_dir,
            register_case=parsed_args.case_reg,
            label_case=parsed_args.case_label,
            space_after_comma=parsed_args.comma_space
        )

    # Read input
    if parsed_args.input_file:
        with open(parsed_args.input_file, 'r', encoding='utf-8', errors='replace') as f:
            source_text = f.read()
    else:
        source_text = sys.stdin.read()

    # Reformat
    reformatter = Reformatter(
        source_dialect=parsed_args.dialect,
        target_dialect=target_dialect,
        config=config
    )
    result_text, warnings = reformatter.reformat(source_text)

    # Output warnings to stderr
    for w in warnings:
        sys.stderr.write(f"[WARN] {w}\n")

    # Write output
    if parsed_args.in_place and parsed_args.input_file:
        with open(parsed_args.input_file, 'w', encoding='utf-8') as f:
            f.write(result_text)
    elif parsed_args.output:
        with open(parsed_args.output, 'w', encoding='utf-8') as f:
            f.write(result_text)
    else:
        sys.stdout.write(result_text)

if __name__ == '__main__':
    main()
