"""
Microsoft Macro-80 (M80) Dialect Implementation.
Used by RomWBW .mac files (ZCPR-DJ, QPM, Survey).
"""

from typing import List
from .base import Dialect
from ..ir import RegisterOperand

class M80Dialect(Dialect):
    """Dialect module for Microsoft Macro-80."""

    @property
    def name(self) -> str:
        return "m80"

    def format_directive(self, mnemonic: str) -> str:
        up = mnemonic.upper().lstrip('.')
        mapping = {
            'BYTE': 'DB',
            'TEXT': 'DB',
            'WORD': 'DW',
            'BLOCK': 'DS',
            'FILL': 'DS',
            'DEFB': 'DB',
            'DEFW': 'DW',
            'DEFS': 'DS',
            'SET': 'DEFL',
            'PHASE': '.PHASE',
            'DEPHASE': '.DEPHASE',
            'Z80': '.Z80',
            '8080': '.8080'
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
            return f"{value:o}Q"
        return str(value)

    def format_string(self, value: str, is_char: bool = False) -> str:
        # M80 uses single quotes with doubled quotes for escaping
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
        if is_public:
            return f"{clean}::"
        return f"{clean}:"

    def format_indexed(self, base_reg: str, disp_str: str) -> str:
        if not disp_str or disp_str in ('0', '+0', '$0'):
            return f"({base_reg}+0)"
        if not disp_str.startswith(('+', '-')):
            disp_str = '+' + disp_str
        return f"({base_reg}{disp_str})"

    def get_prologue(self) -> List[str]:
        # M80 requires .Z80 to enable Zilog mnemonics
        return ["\t.Z80"]

    def get_epilogue(self) -> List[str]:
        return ["\tEND"]

    def validate_instruction(self, mnemonic: str, operands: list) -> List[str]:
        warnings = []
        # M80 rejects undocumented half registers IXH, IXL, IYH, IYL
        for op in operands:
            if isinstance(op, RegisterOperand) and op.name in ('IXH', 'IXL', 'IYH', 'IYL'):
                warnings.append(
                    f"Warning: Undocumented half-register '{op.name}' in '{mnemonic}' is rejected by Microsoft M80."
                )
        return warnings
