"""
Configuration options for the Z80 source code beautifier and reformatter.
Provides independent control over column alignment, case conventions,
tabs/spaces, indentation, and field schemas.
"""

from dataclasses import dataclass, field
import re
from typing import Literal, Tuple, Optional

CaseOption = Literal['upper', 'lower', 'preserve']

@dataclass
class FieldSep:
    """
    Field separator specifier: [count][unit][mode]
    - count: integer (e.g. 0, 1, 8, 9, 17, 24, 41)
    - unit: 's' for spaces, 't' for tabs
    - mode: 'A' for absolute column, 'R' for relative
    """
    count: int = 1
    unit: str = 's'       # 's' or 't'
    mode: str = 'R'       # 'A' (absolute) or 'R' (relative)

    @classmethod
    def parse(cls, text: str) -> "FieldSep":
        raw = text.strip()
        if raw.startswith(";"):
            raw = raw[1:].strip()
        m = re.match(r"^(\d+)([stST])([aArR]?)$", raw)
        if not m:
            return cls(count=1, unit='s', mode='R')
        cnt = int(m.group(1))
        unit = m.group(2).lower()
        mode = m.group(3).upper() if m.group(3) else 'R'
        return cls(count=cnt, unit=unit, mode=mode)

    def to_string(self, is_comment: bool = False) -> str:
        prefix = ";" if is_comment else ""
        mode_str = self.mode if self.mode == 'A' else ""
        return f"{prefix}{self.count}{self.unit}{mode_str}"

    def __str__(self) -> str:
        return self.to_string()


@dataclass
class StmtSchema:
    """
    FMT_STMT: <Sep_Mnem> <Sep_Op1> <Sep_Op2> ;<Sep_Comm>
    e.g. '1t 1s 0s ;32tA' or '9sA 17sA 0s ;41sA'
    """
    mnem: FieldSep = field(default_factory=lambda: FieldSep(9, 's', 'A'))
    op1: FieldSep = field(default_factory=lambda: FieldSep(17, 's', 'A'))
    op2: FieldSep = field(default_factory=lambda: FieldSep(0, 's', 'R'))
    comm: FieldSep = field(default_factory=lambda: FieldSep(41, 's', 'A'))

    @classmethod
    def parse(cls, text: str) -> "StmtSchema":
        cleaned = text.strip()
        # Find comment part starting with ';'
        comm_idx = cleaned.find(";")
        if comm_idx != -1:
            tokens_part = cleaned[:comm_idx].strip()
            comm_part = cleaned[comm_idx:].strip()
        else:
            tokens_part = cleaned
            comm_part = ";41sA"

        # Split tokens_part by whitespace or regex if glued
        tokens = [t for t in re.findall(r"\d+[stST][aArR]?", tokens_part)]
        mnem_sep = FieldSep.parse(tokens[0]) if len(tokens) > 0 else FieldSep(9, 's', 'A')
        op1_sep = FieldSep.parse(tokens[1]) if len(tokens) > 1 else FieldSep(17, 's', 'A')
        op2_sep = FieldSep.parse(tokens[2]) if len(tokens) > 2 else FieldSep(0, 's', 'R')
        comm_sep = FieldSep.parse(comm_part) if comm_part else FieldSep(41, 's', 'A')

        return cls(mnem=mnem_sep, op1=op1_sep, op2=op2_sep, comm=comm_sep)

    def to_string(self) -> str:
        return f"{self.mnem.to_string()} {self.op1.to_string()} {self.op2.to_string()} {self.comm.to_string(is_comment=True)}"

    def __str__(self) -> str:
        return self.to_string()


@dataclass
class LabelSchema:
    """
    FMT_LABEL: <Col_Spec> <Colon_Rule> <Placement_Rule>
    e.g. '1sA : S' or '1sA : O'
    Colon_Rule: ':' (ensure), '-' (strip), '?' (preserve)
    Placement_Rule: 'S' (same line), 'N' (next line), 'O' (overflow)
    """
    col: FieldSep = field(default_factory=lambda: FieldSep(1, 's', 'A'))
    colon: str = ':'       # ':', '-', '?'
    placement: str = 'S'   # 'S', 'N', 'O'

    @classmethod
    def parse(cls, text: str) -> "LabelSchema":
        raw = text.strip()
        col_m = re.search(r"(\d+[stST][aArR]?)", raw)
        col = FieldSep.parse(col_m.group(1)) if col_m else FieldSep(1, 's', 'A')

        colon = ':'
        if '-' in raw or '_' in raw:
            colon = '-'
        elif '?' in raw:
            colon = '?'

        placement = 'S'
        if re.search(r"\b[nN]\b", raw):
            placement = 'N'
        elif re.search(r"\b[oO]\b", raw):
            placement = 'O'
        elif re.search(r"\b[sS]\b", raw):
            placement = 'S'

        return cls(col=col, colon=colon, placement=placement)

    def to_string(self) -> str:
        return f"{self.col.to_string()} {self.colon} {self.placement}"

    def __str__(self) -> str:
        return self.to_string()


@dataclass
class CommentSchema:
    """
    FMT_COMMENT: <Col1_Rule> <Indented_Rule>
    e.g. '1sA M'
    Col1_Rule: '1sA' / '0s' / 'keep'
    Indented_Rule: 'M' (align to mnemonic), 'N' (nearest boundary), 'P' (preserve)
    """
    col1: str = '1sA'
    indented: str = 'M'

    @classmethod
    def parse(cls, text: str) -> "CommentSchema":
        tokens = text.strip().split()
        col1 = tokens[0] if len(tokens) > 0 else '1sA'
        indented = tokens[1].upper() if len(tokens) > 1 else 'M'
        return cls(col1=col1, indented=indented)

    def to_string(self) -> str:
        return f"{self.col1} {self.indented}"

    def __str__(self) -> str:
        return self.to_string()


@dataclass
class CaseSchema:
    """
    FMT_CASE: m<Case> o<Case> l<Case> c<Case>
    e.g. 'mU oU lP cU' or 'm:U o:U l:P c:U'
    Case: 'U' (upper), 'L' (lower), 'P' (preserve)
    - m: Mnemonic
    - o: Operands (registers & conditions)
    - l: Labels
    - c: Constants & Directives / EQU keywords
    """
    mnemonic: CaseOption = 'upper'
    operand: CaseOption = 'upper'
    label: CaseOption = 'preserve'
    constant: CaseOption = 'upper'

    @staticmethod
    def _parse_opt(ch: str) -> CaseOption:
        c = ch.upper()
        if c == 'U': return 'upper'
        if c == 'L': return 'lower'
        return 'preserve'

    @staticmethod
    def _to_code(opt: CaseOption) -> str:
        if opt == 'upper': return 'U'
        if opt == 'lower': return 'L'
        return 'P'

    @classmethod
    def parse(cls, text: str) -> "CaseSchema":
        raw = text.strip()
        mnem, op, lbl, const = 'upper', 'upper', 'preserve', 'upper'

        # Look for m, o, l, c keyed tokens e.g. mU, m:U, m=U
        m_match = re.search(r"\b[mM][:=-]?([uUlLpP\-])", raw)
        o_match = re.search(r"\b[oOrR][:=-]?([uUlLpP\-])", raw)
        l_match = re.search(r"\b[lL][:=-]?([uUlLpP\-])", raw)
        c_match = re.search(r"\b[cCdD][:=-]?([uUlLpP\-])", raw)

        if m_match: mnem = cls._parse_opt(m_match.group(1))
        if o_match: op = cls._parse_opt(o_match.group(1))
        if l_match: lbl = cls._parse_opt(l_match.group(1))
        if c_match: const = cls._parse_opt(c_match.group(1))

        # Also support positional format 'U U P U'
        if not (m_match or o_match or l_match or c_match):
            tokens = raw.split()
            if len(tokens) >= 1: mnem = cls._parse_opt(tokens[0])
            if len(tokens) >= 2: op = cls._parse_opt(tokens[1])
            if len(tokens) >= 3: lbl = cls._parse_opt(tokens[2])
            if len(tokens) >= 4: const = cls._parse_opt(tokens[3])

        return cls(mnemonic=mnem, operand=op, label=lbl, constant=const)

    def to_string(self) -> str:
        return f"m{self._to_code(self.mnemonic)} o{self._to_code(self.operand)} l{self._to_code(self.label)} c{self._to_code(self.constant)}"

    def __str__(self) -> str:
        return self.to_string()


class FormatterConfig:
    """
    Configuration options for source beautification.
    All column numbers are 1-based (standard text editor indexing).
    """
    def __init__(
        self,
        stmt_schema: Optional[StmtSchema] = None,
        label_schema: Optional[LabelSchema] = None,
        comment_schema: Optional[CommentSchema] = None,
        case_schema: Optional[CaseSchema] = None,
        label_col: int = 1,
        opcode_col: int = 9,
        operand_col: int = 17,
        comment_col: int = 41,
        use_tabs: bool = False,
        tab_width: int = 8,
        indent_spaces: int = 8,
        instruction_case: CaseOption = 'upper',
        directive_case: CaseOption = 'upper',
        register_case: CaseOption = 'upper',
        label_case: CaseOption = 'preserve',
        space_after_comma: bool = False,
        preserve_blank_lines: bool = True,
        pad_comment_if_overflow: bool = True,
    ):
        self.use_tabs = use_tabs
        self.tab_width = tab_width
        self.preserve_blank_lines = preserve_blank_lines
        self.pad_comment_if_overflow = pad_comment_if_overflow

        unit = 't' if use_tabs else 's'
        if stmt_schema is not None:
            self.stmt_schema = stmt_schema
        else:
            self.stmt_schema = StmtSchema(
                mnem=FieldSep(opcode_col, unit, 'A'),
                op1=FieldSep(operand_col, unit, 'A'),
                op2=FieldSep(1 if space_after_comma else 0, 's', 'R'),
                comm=FieldSep(comment_col, unit, 'A'),
            )

        if label_schema is not None:
            self.label_schema = label_schema
        else:
            self.label_schema = LabelSchema(
                col=FieldSep(label_col, 's', 'A'),
                colon=':',
                placement='S',
            )

        if comment_schema is not None:
            self.comment_schema = comment_schema
        else:
            self.comment_schema = CommentSchema(col1='1sA', indented='M')

        if case_schema is not None:
            self.case_schema = case_schema
        else:
            self.case_schema = CaseSchema(
                mnemonic=instruction_case,
                operand=register_case,
                label=label_case,
                constant=directive_case,
            )

    @property
    def label_col(self) -> int:
        return self.label_schema.col.count

    @label_col.setter
    def label_col(self, val: int):
        self.label_schema.col = FieldSep(val, 's', 'A')

    @property
    def opcode_col(self) -> int:
        return self.stmt_schema.mnem.count

    @opcode_col.setter
    def opcode_col(self, val: int):
        self.stmt_schema.mnem = FieldSep(val, 't' if self.use_tabs else 's', 'A')

    @property
    def operand_col(self) -> int:
        return self.stmt_schema.op1.count

    @operand_col.setter
    def operand_col(self, val: int):
        self.stmt_schema.op1 = FieldSep(val, 't' if self.use_tabs else 's', 'A')

    @property
    def comment_col(self) -> int:
        return self.stmt_schema.comm.count

    @comment_col.setter
    def comment_col(self, val: int):
        self.stmt_schema.comm = FieldSep(val, 't' if self.use_tabs else 's', 'A')

    @property
    def space_after_comma(self) -> bool:
        return self.stmt_schema.op2.count > 0

    @space_after_comma.setter
    def space_after_comma(self, val: bool):
        self.stmt_schema.op2 = FieldSep(1 if val else 0, 's', 'R')

    @property
    def instruction_case(self) -> CaseOption:
        return self.case_schema.mnemonic

    @instruction_case.setter
    def instruction_case(self, val: CaseOption):
        self.case_schema.mnemonic = val

    @property
    def register_case(self) -> CaseOption:
        return self.case_schema.operand

    @register_case.setter
    def register_case(self, val: CaseOption):
        self.case_schema.operand = val

    @property
    def label_case(self) -> CaseOption:
        return self.case_schema.label

    @label_case.setter
    def label_case(self, val: CaseOption):
        self.case_schema.label = val

    @property
    def directive_case(self) -> CaseOption:
        return self.case_schema.constant

    @directive_case.setter
    def directive_case(self, val: CaseOption):
        self.case_schema.constant = val

    def emit_separator(self, current_col: int, sep: FieldSep) -> Tuple[str, int]:
        """
        Calculate separator whitespace string and new 1-based column position.
        Supports both spaces ('s') and tabs ('t') in Absolute ('A') and Relative ('R') modes.
        """
        unit = 't' if (sep.unit == 't' or self.use_tabs) else 's'
        if sep.mode == 'A':
            target_col = sep.count
            if current_col >= target_col:
                # Overflow: emit minimum 1 unit so tokens never merge
                emitted = "\t" if unit == 't' else " "
                col = ((current_col - 1) // self.tab_width + 1) * self.tab_width + 1 if unit == 't' else current_col + 1
                return emitted, col

            if unit == 't':
                result = []
                col = current_col
                while col < target_col:
                    result.append("\t")
                    col = ((col - 1) // self.tab_width + 1) * self.tab_width + 1
                return "".join(result), col
            else:
                spaces = " " * (target_col - current_col)
                return spaces, target_col
        else:
            # Relative mode
            if unit == 't':
                emitted = "\t" * sep.count
                col = current_col
                for _ in range(sep.count):
                    col = ((col - 1) // self.tab_width + 1) * self.tab_width + 1
                return emitted, col
            else:
                emitted = " " * sep.count
                return emitted, current_col + sep.count

    def get_column_whitespace(self, current_col: int, target_col: int) -> str:
        """Legacy helper for column alignment."""
        sep = FieldSep(count=target_col, unit='t' if self.use_tabs else 's', mode='A')
        s, _ = self.emit_separator(current_col, sep)
        return s

    def format_case(self, text: str, option: CaseOption) -> str:
        """Format string according to CaseOption."""
        if option == 'upper':
            return text.upper()
        elif option == 'lower':
            return text.lower()
        return text
