"""
SLR Systems Z80ASM / ZMAC Dialect Implementation.
Used by RomWBW ZSDOS, ZDE, and CP/M system utilities.
"""

from typing import List
from .base import Dialect

class SlrDialect(Dialect):
    """Dialect module for SLR Systems Z80ASM and ZMAC."""

    @property
    def name(self) -> str:
        return "slr"

    def format_directive(self, mnemonic: str) -> str:
        up = mnemonic.upper().lstrip('.')
        mapping = {
            'BYTE': 'DEFB',
            'TEXT': 'DEFM',
            'WORD': 'DEFW',
            'BLOCK': 'DEFS',
            'FILL': 'DEFS',
            'SET': 'DEFL',
            'DS': 'DEFS',
            'DB': 'DEFB',
            'DW': 'DEFW',
        }
        return mapping.get(up, up)

    def format_number(self, value: int, base: int, original_text: str = "") -> str:
        if base == 16:
            hex_str = f"{value:X}"
            if hex_str[0] in 'ABCDEF':
                hex_str = '0' + hex_str
            return hex_str + 'H'
        elif base == 2:
            return f"{value:b}B"
        elif base == 8:
            return f"{value:o}O"
        return str(value)

    def format_string(self, value: str, is_char: bool = False) -> str:
        # SLR uses single quotes with doubled quotes for escaping
        escaped = value.replace("'", "''")
        return f"'{escaped}'"

    def format_operator(self, op: str) -> str:
        up = op.upper()
        mapping = {
            '&': 'AND',
            '|': 'OR',
            '^': 'XOR',
            '~': 'NOT',
            '<<': 'SHL',
            '>>': 'SHR',
            '%': 'MOD'
        }
        return mapping.get(up, up)

    def format_location_counter(self) -> str:
        return "$"

    def format_label(self, name: str, has_colon: bool, is_public: bool = False, is_local: bool = False) -> str:
        clean = name.lstrip('@._')
        return f"{clean}:"

    def format_indexed(self, base_reg: str, disp_str: str) -> str:
        if not disp_str or disp_str in ('0', '+0', '$0'):
            return f"({base_reg}+0)"
        if not disp_str.startswith(('+', '-')):
            disp_str = '+' + disp_str
        return f"({base_reg}{disp_str})"

    def get_epilogue(self) -> List[str]:
        return ["\tEND"]
