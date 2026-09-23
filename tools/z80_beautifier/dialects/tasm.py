"""
TASM / uz80as Dialect Implementation.
Used by RomWBW BIOSes (CBIOS, HBIOS) and ROM images.
"""

from typing import List
from .base import Dialect

class TasmDialect(Dialect):
    """Dialect module for TASM 3.2 and uz80as."""

    @property
    def name(self) -> str:
        return "tasm"

    def format_directive(self, mnemonic: str) -> str:
        up = mnemonic.upper().lstrip('.')
        mapping = {
            'ORG': '.ORG',
            'EQU': '.EQU',
            'SET': '.SET',
            'DEFL': '.SET',
            'DB': '.BYTE',
            'DEFB': '.BYTE',
            'BYTE': '.BYTE',
            'TEXT': '.TEXT',
            'DW': '.WORD',
            'DEFW': '.WORD',
            'WORD': '.WORD',
            'DS': '.BLOCK',
            'DEFS': '.BLOCK',
            'BLOCK': '.BLOCK',
            'FILL': '.FILL',
            'ALIGN': '.ALIGN',
            'END': '.END',
            'MODULE': '.MODULE',
            'ECHO': '.ECHO'
        }
        return mapping.get(up, '.' + up)

    def format_number(self, value: int, base: int, original_text: str = "") -> str:
        if base == 16:
            return f"${value:04X}" if value > 0xFF else f"${value:02X}"
        elif base == 2:
            return f"%{value:b}"
        elif base == 8:
            return f"@{value:o}"
        return str(value)

    def format_string(self, value: str, is_char: bool = False) -> str:
        # TASM supports double quotes with escapes
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
        clean_name = name
        if is_local:
            if not clean_name.startswith('_'):
                clean_name = '_' + clean_name.lstrip('@.')
        # Colons are standard and accepted
        return f"{clean_name}:"

    def format_indexed(self, base_reg: str, disp_str: str) -> str:
        # Stock TASM requires explicit displacement, so d=0 -> +0
        if not disp_str or disp_str in ('0', '+0', '$0'):
            return f"({base_reg}+0)"
        if not disp_str.startswith(('+', '-')):
            disp_str = '+' + disp_str
        return f"({base_reg}{disp_str})"

    def get_epilogue(self) -> List[str]:
        return ["\t.END"]
