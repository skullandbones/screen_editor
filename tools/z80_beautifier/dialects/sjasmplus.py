"""
sjasmplus Dialect Implementation.
Modern cross-assembler for Z80 with multi-pass evaluation, local labels,
C-style expressions, and flexible directive formatting.
"""

from typing import List
from .base import Dialect

class SjasmplusDialect(Dialect):
    """Dialect module for sjasmplus."""

    @property
    def name(self) -> str:
        return "sjasmplus"

    def format_directive(self, mnemonic: str) -> str:
        up = mnemonic.upper().lstrip('.')
        mapping = {
            'DEFB': 'DB',
            'BYTE': 'DB',
            'DEFBYTE': 'DB',
            'TEXT': 'DB',
            'DEFW': 'DW',
            'WORD': 'DW',
            'DEFWORD': 'DW',
            'DEFS': 'DS',
            'BLOCK': 'DS',
            'FILL': 'DS',
            'SET': 'EQU',
            'DEFL': 'EQU',
            'GLOBAL': 'PUBLIC'
        }
        return mapping.get(up, up)

    def format_number(self, value: int, base: int, original_text: str = "") -> str:
        # sjasmplus accepts 0x..., $..., ...h, %..., 0b...
        if original_text:
            ot = original_text.strip()
            if ot.startswith(('$', '0x', '0X', '%', '0b', '0B')) or \
               ot.endswith(('h', 'H', 'b', 'B', 'o', 'O', 'q', 'Q')) or ot.isdigit():
                return ot

        if base == 16:
            return f"${value:04X}" if value > 0xFF else f"${value:02X}"
        elif base == 2:
            return f"%{value:b}"
        elif base == 8:
            return f"0o{value:o}"
        return str(value)

    def format_string(self, value: str, is_char: bool = False) -> str:
        if is_char and len(value) == 1:
            if value == "'":
                return "'\\''"
            return f"'{value}'"

        escaped = []
        for c in value:
            if c == '\n': escaped.append('\\n')
            elif c == '\r': escaped.append('\\r')
            elif c == '\t': escaped.append('\\t')
            elif c == '\0': escaped.append('\\0')
            elif c == '\\': escaped.append('\\\\')
            elif c == '"': escaped.append('\\"')
            else: escaped.append(c)
        return f'"{"".join(escaped)}"'

    def format_operator(self, op: str) -> str:
        up = op.upper()
        mapping = {
            'AND': '&',
            'OR': '|',
            'XOR': '^',
            'NOT': '~',
            'SHL': '<<',
            'SHR': '>>',
            'MOD': '%'
        }
        return mapping.get(up, op)

    def format_location_counter(self) -> str:
        return "$"

    def format_label(self, name: str, has_colon: bool, is_public: bool = False, is_local: bool = False) -> str:
        # sjasmplus uses .local for local labels, and colons are standard
        clean = name
        if is_local:
            if not clean.startswith('.'):
                clean = '.' + clean.lstrip('@_')
        return f"{clean}:"

    def format_indexed(self, base_reg: str, disp_str: str) -> str:
        if not disp_str or disp_str in ('0', '+0', '$0'):
            return f"({base_reg})"
        if not disp_str.startswith(('+', '-')):
            disp_str = '+' + disp_str
        return f"({base_reg}{disp_str})"

    def format_identifier(self, name: str) -> str:
        if name.startswith(('@', '_')):
            return '.' + name.lstrip('._@')
        return name
