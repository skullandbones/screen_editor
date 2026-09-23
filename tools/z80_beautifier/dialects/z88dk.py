"""
z88dk-z80asm Dialect Implementation.
Used by SE.COM and standard z88dk projects.
"""

from typing import List
from .base import Dialect

class Z88dkDialect(Dialect):
    """Dialect module for z88dk-z80asm."""

    @property
    def name(self) -> str:
        return "z88dk"

    def format_directive(self, mnemonic: str) -> str:
        up = mnemonic.upper().lstrip('.')
        # Directives mapping
        mapping = {
            'BYTE': 'DB',
            'TEXT': 'DB',
            'WORD': 'DW',
            'BLOCK': 'DS',
            'FILL': 'DS',
            'SET': 'DEFL',
        }
        return mapping.get(up, up)

    def format_number(self, value: int, base: int, original_text: str = "") -> str:
        # If original text is valid in z88dk ($FF, 0xFF, 0FFH, %1010, 1010B), preserve it
        if original_text:
            ot = original_text.strip()
            if ot.startswith('$') or ot.startswith('0x') or ot.startswith('0X') or \
               ot.endswith(('h', 'H')) or ot.startswith('%') or ot.endswith(('b', 'B')) or ot.isdigit():
                return ot

        if base == 16:
            return f"${value:04X}" if value > 0xFF else f"${value:02X}"
        elif base == 2:
            return f"%{value:b}"
        elif base == 8:
            return f"@{value:o}"
        return str(value)

    def format_string(self, value: str, is_char: bool = False) -> str:
        if is_char and len(value) == 1:
            if value == "'":
                return "'\\''"
            return f"'{value}'"

        # Double quotes with C-style escapes
        escaped = []
        for c in value:
            if c == '\n': escaped.append('\\n')
            elif c == '\r': escaped.append('\\r')
            elif c == '\t': escaped.append('\\t')
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
        # z88dk mandates colons on labels
        clean_name = name
        if is_local:
            if not clean_name.startswith('@'):
                clean_name = '@' + clean_name.lstrip('._')
        return f"{clean_name}:"

    def format_indexed(self, base_reg: str, disp_str: str) -> str:
        if not disp_str or disp_str in ('0', '+0', '$0'):
            return f"({base_reg})"
        if not disp_str.startswith(('+', '-')):
            disp_str = '+' + disp_str
        return f"({base_reg}{disp_str})"

    def format_identifier(self, name: str) -> str:
        if name.startswith(('.', '_')):
            return '@' + name.lstrip('._@')
        return name
