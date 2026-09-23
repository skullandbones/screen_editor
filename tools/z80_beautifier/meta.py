"""
Meta file loader and parser for SE.CFG and *.DIA files.
Enables bidirectional sharing of configuration and dialect definitions
between CP/M SE.COM and Linux Python tools.
"""

import os
from typing import Dict, List, Optional
from .config import FormatterConfig, StmtSchema, LabelSchema, CommentSchema, CaseSchema
from .dialects.base import Dialect

def parse_key_value_file(filepath: str) -> Dict[str, str]:
    """Parse plain-text CP/M 8.3 KEY = VALUE file with # and ; comments."""
    data: Dict[str, str] = {}
    if not os.path.exists(filepath):
        return data

    with open(filepath, 'r', encoding='utf-8', errors='replace') as f:
        for line in f:
            stripped = line.strip()
            if not stripped or stripped.startswith(('#', ';')):
                continue

            if '=' in stripped:
                key, val = stripped.split('=', 1)
                key = key.strip().upper()
                val = val.strip()
                # Do not strip ';' from FMT_STMT as it denotes comment separator
                if key != 'FMT_STMT':
                    if '#' in val:
                        val = val.split('#')[0].strip()
                    if ';' in val:
                        val = val.split(';')[0].strip()
                data[key] = val

    return data

def load_se_cfg(filepath: str) -> FormatterConfig:
    """Load FormatterConfig from SE.CFG or BEAUTIFY.CFG."""
    data = parse_key_value_file(filepath)

    cfg = FormatterConfig()

    # 1. Parse modern 4-line schemas if present
    if 'FMT_STMT' in data:
        cfg.stmt_schema = StmtSchema.parse(data['FMT_STMT'])
    if 'FMT_LABEL' in data:
        cfg.label_schema = LabelSchema.parse(data['FMT_LABEL'])
    if 'FMT_COMMENT' in data:
        cfg.comment_schema = CommentSchema.parse(data['FMT_COMMENT'])
    if 'FMT_CASE' in data:
        cfg.case_schema = CaseSchema.parse(data['FMT_CASE'])

    # 1b. Parse BEAUTIFY.CFG keys if present
    if 'COLUMNS' in data:
        col = data['COLUMNS'].upper()
        if col.startswith('C'):
            cfg.opcode_col = 8
            cfg.operand_col = 16
            cfg.comment_col = 36
        elif col.startswith('W'):
            cfg.opcode_col = 10
            cfg.operand_col = 20
            cfg.comment_col = 48
        else:
            cfg.opcode_col = 9
            cfg.operand_col = 17
            cfg.comment_col = 41

    if 'MNEMONICS' in data:
        m = data['MNEMONICS'].lower()
        if m.startswith('l'): cfg.instruction_case = 'lower'
        elif m.startswith('a') or m.startswith('p'): cfg.instruction_case = 'preserve'
        else: cfg.instruction_case = 'upper'

    if 'REGISTERS' in data:
        r = data['REGISTERS'].lower()
        if r.startswith('l'): cfg.register_case = 'lower'
        elif r.startswith('a') or r.startswith('p'): cfg.register_case = 'preserve'
        else: cfg.register_case = 'upper'

    # 2. Legacy key-value overrides for backward compatibility
    if 'LABEL_COL' in data:
        try: cfg.label_col = int(data['LABEL_COL'])
        except ValueError: pass

    if 'OPCODE_COL' in data:
        try: cfg.opcode_col = int(data['OPCODE_COL'])
        except ValueError: pass

    if 'OPERAND_COL' in data:
        try: cfg.operand_col = int(data['OPERAND_COL'])
        except ValueError: pass

    if 'COMMENT_COL' in data:
        try: cfg.comment_col = int(data['COMMENT_COL'])
        except ValueError: pass

    if 'USE_TABS' in data:
        cfg.use_tabs = data['USE_TABS'].upper() in ('1', 'YES', 'TRUE')

    if 'TAB_WIDTH' in data:
        try: cfg.tab_width = int(data['TAB_WIDTH'])
        except ValueError: pass
    elif 'TAB' in data:
        try: cfg.tab_width = int(data['TAB'])
        except ValueError: pass

    if 'COMMA_SPACE' in data:
        cfg.space_after_comma = data['COMMA_SPACE'].upper() in ('1', 'YES', 'TRUE')

    if 'CASE_INSN' in data:
        val = data['CASE_INSN'].lower()
        if val in ('upper', 'lower', 'preserve'): cfg.instruction_case = val
    elif 'INSTRUCTION_CASE' in data:
        val = data['INSTRUCTION_CASE'].lower()
        if val in ('upper', 'lower', 'preserve'): cfg.instruction_case = val

    if 'CASE_DIR' in data:
        val = data['CASE_DIR'].lower()
        if val in ('upper', 'lower', 'preserve'): cfg.directive_case = val
    elif 'DIRECTIVE_CASE' in data:
        val = data['DIRECTIVE_CASE'].lower()
        if val in ('upper', 'lower', 'preserve'): cfg.directive_case = val

    if 'CASE_REG' in data:
        val = data['CASE_REG'].lower()
        if val in ('upper', 'lower', 'preserve'): cfg.register_case = val
    elif 'REGISTER_CASE' in data:
        val = data['REGISTER_CASE'].lower()
        if val in ('upper', 'lower', 'preserve'): cfg.register_case = val

    if 'CASE_LABEL' in data:
        val = data['CASE_LABEL'].lower()
        if val in ('preserve', 'upper', 'lower'): cfg.label_case = val
    elif 'LABEL_CASE' in data:
        val = data['LABEL_CASE'].lower()
        if val in ('preserve', 'upper', 'lower'): cfg.label_case = val

    return cfg

class MetaDialect(Dialect):
    """Dynamic Dialect instantiated from a .DIA definition file."""

    def __init__(self, dia_path: str):
        self.dia_path = dia_path
        self.data = parse_key_value_file(dia_path)
        self._name = self.data.get('NAME', os.path.splitext(os.path.basename(dia_path))[0]).lower()

        # Directive mappings: DIR_BYTE -> DB, DIR_WORD -> DW, etc.
        self.directives_map = {
            'BYTE': self.data.get('DIR_BYTE', 'DB'),
            'DEFB': self.data.get('DIR_BYTE', 'DB'),
            'WORD': self.data.get('DIR_WORD', 'DW'),
            'DEFW': self.data.get('DIR_WORD', 'DW'),
            'BLOCK': self.data.get('DIR_BLOCK', 'DS'),
            'DEFS': self.data.get('DIR_BLOCK', 'DS'),
            'DS': self.data.get('DIR_BLOCK', 'DS'),
            'DB': self.data.get('DIR_BYTE', 'DB'),
            'DW': self.data.get('DIR_WORD', 'DW'),
            'EQU': self.data.get('DIR_EQU', 'EQU'),
            'SET': self.data.get('DIR_VAR', 'DEFL'),
            'DEFL': self.data.get('DIR_VAR', 'DEFL'),
            'ORG': self.data.get('DIR_ORG', 'ORG'),
            'END': self.data.get('DIR_END', 'END'),
            'ALIGN': self.data.get('DIR_ALIGN', 'ALIGN')
        }

        # Operator mappings
        self.ops_map = {
            'AND': self.data.get('OP_AND', '&'),
            'OR': self.data.get('OP_OR', '|'),
            'XOR': self.data.get('OP_XOR', '^'),
            'NOT': self.data.get('OP_NOT', '~'),
            'SHL': self.data.get('OP_SHL', '<<'),
            'SHR': self.data.get('OP_SHR', '>>'),
            'MOD': self.data.get('OP_MOD', '%')
        }

        self.hex_prefix = self.data.get('HEX_PREFIX', '$')
        self.hex_suffix = self.data.get('HEX_SUFFIX', '')
        self.bin_prefix = self.data.get('BIN_PREFIX', '%')
        self.bin_suffix = self.data.get('BIN_SUFFIX', '')
        self.oct_prefix = self.data.get('OCT_PREFIX', '@')
        self.oct_suffix = self.data.get('OCT_SUFFIX', '')
        self.local_prefix = self.data.get('LOCAL_PREFIX', '')
        self.loc_counter = self.data.get('LOCATION_COUNTER', '$')
        self.prologue = self.data.get('PROLOGUE', '')
        self.epilogue = self.data.get('EPILOGUE', '')

    @property
    def name(self) -> str:
        return self._name

    def format_directive(self, mnemonic: str) -> str:
        up = mnemonic.upper().lstrip('.')
        return self.directives_map.get(up, mnemonic)

    def format_number(self, value: int, base: int, original_text: str = "") -> str:
        if base == 16:
            hex_digits = f"{value:X}"
            # If suffix mode (like 0FFH), ensure leading zero if starting with A-F
            if self.hex_suffix and hex_digits[0] in 'ABCDEF' and not self.hex_prefix:
                hex_digits = '0' + hex_digits
            return f"{self.hex_prefix}{hex_digits}{self.hex_suffix}"
        elif base == 2:
            return f"{self.bin_prefix}{value:b}{self.bin_suffix}"
        elif base == 8:
            return f"{self.oct_prefix}{value:o}{self.oct_suffix}"
        return str(value)

    def format_string(self, value: str, is_char: bool = False) -> str:
        if self.hex_suffix and not self.hex_prefix:
            # SLR/M80 style single quotes with doubled single quotes
            escaped = value.replace("'", "''")
            return f"'{escaped}'"
        # C-style double quotes
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
        return self.ops_map.get(up, op)

    def format_location_counter(self) -> str:
        return self.loc_counter

    def format_label(self, name: str, has_colon: bool, is_public: bool = False, is_local: bool = False) -> str:
        clean = name
        if is_local and self.local_prefix:
            if not clean.startswith(self.local_prefix):
                clean = self.local_prefix + clean.lstrip('._@')
        return f"{clean}:"

    def format_identifier(self, name: str) -> str:
        if name.startswith(('@', '.', '_')) and self.local_prefix:
            return self.local_prefix + name.lstrip('._@')
        return name

    def format_indexed(self, base_reg: str, disp_str: str) -> str:
        if not disp_str or disp_str in ('0', '+0', '$0'):
            return f"({base_reg})"
        if not disp_str.startswith(('+', '-')):
            disp_str = '+' + disp_str
        return f"({base_reg}{disp_str})"

    def get_prologue(self) -> List[str]:
        if self.prologue:
            return [f"\t{self.prologue}"]
        return []

    def get_epilogue(self) -> List[str]:
        if self.epilogue:
            return [f"\t{self.epilogue}"]
        return []

def load_dialect_dia(filepath: str) -> Dialect:
    """Load a Dialect instance from a .DIA file."""
    return MetaDialect(filepath)
