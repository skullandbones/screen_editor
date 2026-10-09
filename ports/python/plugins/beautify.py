"""
Z80 assembly code formatter and beautifier plugin for Python SE editor.
Formats labels, opcodes, operands, and comments into aligned columns.
"""

import re
from se.plugin import PluginBase, HostAPI


def beautify_asm_line(line: str) -> str:
    """Format single line of Z80 assembly code into standard columns."""
    stripped = line.strip()
    if not stripped or stripped.startswith(";"):
        return line

    # Extract comment if present
    comment = ""
    if ";" in line:
        code_part, comment_part = line.split(";", 1)
        comment = ";" + comment_part
        line_code = code_part.rstrip()
    else:
        line_code = line.rstrip()

    if not line_code:
        return f"\t\t\t\t{comment}" if comment else ""

    tokens = line_code.split()
    if not tokens:
        return line

    # Check for label (starts at col 0 or ends with ':')
    label = ""
    opcode = ""
    operands = ""

    if line[0] not in (" ", "\t") or tokens[0].endswith(":"):
        label = tokens[0]
        rem = tokens[1:]
    else:
        rem = tokens

    if rem:
        opcode = rem[0].upper()
        if len(rem) > 1:
            operands = " ".join(rem[1:])

    # Format into columns: Label (col 0), Opcode (col 16), Operands (col 24)
    res = label.ljust(16) if label else (" " * 16)
    if opcode:
        res += opcode.ljust(8)
    if operands:
        res += operands.ljust(16)
    if comment:
        res = res.rstrip() + "    " + comment

    return res.rstrip()


class BeautifyPlugin(PluginBase):
    """Z80 Assembly Beautifier Plugin."""

    NAME = "BEAUTIFY"
    DESCRIPTION = "Align Z80 assembly labels, opcodes, and comments"

    def run(self, api: HostAPI) -> bool:
        """Format active block selection or entire document."""
        bounds = api.get_block_bounds()
        if bounds:
            r1, _, r2, _ = bounds
            for r in range(r1, r2 + 1):
                raw = api.checkout_line(r)
                api.commit_line(r, beautify_asm_line(raw))
            api.set_status_msg("Beautified block")
        else:
            for r in range(api.get_total_lines()):
                raw = api.checkout_line(r)
                api.commit_line(r, beautify_asm_line(raw))
            api.set_status_msg("Beautified document")
        return True
