"""
Common Intermediate Representation (AST / IR) for Z80 assembly source code.
Captures programs at a semantic level independent of specific assembler dialects.
Preserves labels, comments, expressions, and operand structures.
"""

from dataclasses import dataclass, field
from typing import List, Optional, Union

# Standard Z80 registers
Z80_REGISTERS = {
    'A', 'B', 'C', 'D', 'E', 'H', 'L',
    'BC', 'DE', 'HL', 'SP', 'AF', "AF'",
    'IX', 'IY', 'I', 'R',
    'IXH', 'IXL', 'IYH', 'IYL'  # Undocumented half-registers
}

# Jump/Call condition codes
Z80_CONDITIONS = {'NZ', 'Z', 'NC', 'C', 'PO', 'PE', 'P', 'M'}

# Standard assembly directives across dialects
COMMON_DIRECTIVES = {
    'ORG', '.ORG', 'EQU', '.EQU', '=', 'SET', '.SET', 'DEFL',
    'DB', 'DEFB', '.DB', '.BYTE', 'DEFM', '.TEXT',
    'DW', 'DEFW', '.DW', '.WORD',
    'DS', 'DEFS', '.DS', '.BLOCK', '.FILL',
    'ALIGN', '.ALIGN', 'END', '.END',
    'CSEG', 'DSEG', 'ASEG', 'COMMON', 'PUBLIC', 'EXTRN', 'GLOBAL',
    'PHASE', '.PHASE', 'DEPHASE', '.DEPHASE', '.Z80', '.8080',
    'MODULE', '.MODULE', 'MACLIB', 'INCLUDE', '#INCLUDE', '#DEFINE'
}

# ---------------------------------------------------------------------------
# AST Expression Hierarchy
# ---------------------------------------------------------------------------

class Expression:
    """Base class for all expression nodes."""
    pass

@dataclass
class NumberLiteral(Expression):
    """Numeric constant with preserved base and value."""
    value: int
    base: int = 10                     # 16=hex, 10=dec, 2=bin, 8=oct
    original_text: str = ""

@dataclass
class StringLiteral(Expression):
    """String or character literal."""
    value: str
    quote_char: str = '"'              # '"' or "'"
    is_char_const: bool = False        # True if single character constant like 'A'

@dataclass
class Identifier(Expression):
    """Symbol or label reference."""
    name: str

@dataclass
class LocationCounter(Expression):
    """Current program counter symbol ($ or *)."""
    symbol: str = "$"

@dataclass
class UnaryOp(Expression):
    """Unary operation (e.g. -X, ~X, NOT X)."""
    op: str
    operand: Expression

@dataclass
class BinaryOp(Expression):
    """Binary operation (e.g. A + B, X * Y, M AND N, L << 4)."""
    left: Expression
    op: str
    right: Expression

@dataclass
class Parenthesized(Expression):
    """Explicitly grouped expression: ( expr )."""
    expr: Expression

# ---------------------------------------------------------------------------
# AST Operand Hierarchy
# ---------------------------------------------------------------------------

class Operand:
    """Base class for instruction/directive operands."""
    pass

@dataclass
class RegisterOperand(Operand):
    """Register operand, either direct or indirect."""
    name: str                          # e.g. 'A', 'HL', 'BC'
    is_indirect: bool = False          # True for (HL), (BC), (DE), (SP), (C)

@dataclass
class IndexedOperand(Operand):
    """Indexed memory operand: (IX+d), (IY-d), (IX)."""
    base: str                          # 'IX' or 'IY'
    displacement: Expression           # NumberLiteral(0) if no displacement

@dataclass
class ConditionOperand(Operand):
    """Condition code operand: NZ, Z, NC, C, PO, PE, P, M."""
    code: str

@dataclass
class ExpressionOperand(Operand):
    """Direct value / memory address / immediate expression operand."""
    expr: Expression
    is_indirect: bool = False          # True for memory indirection (nn)

# ---------------------------------------------------------------------------
# AST Line & Statement Hierarchy
# ---------------------------------------------------------------------------

class Node:
    """Base class for line-level AST nodes."""
    pass

@dataclass
class BlankLine(Node):
    """Preserves blank lines in source."""
    raw_text: str = ""

@dataclass
class CommentLine(Node):
    """Full-line standalone comment."""
    indent: str                        # Original whitespace before delimiter
    delimiter: str                     # ';', '//', or '*'
    text: str                          # Comment text following delimiter

@dataclass
class Label:
    """Label declaration on a line."""
    name: str
    has_colon: bool = True
    is_local: bool = False
    local_prefix: str = ""             # '@', '_', '.'
    is_public: bool = False            # True if declared with '::'

@dataclass
class Comment:
    """Inline comment trailing a statement."""
    delimiter: str = ";"
    text: str = ""

@dataclass
class StatementLine(Node):
    """
    Complete assembly statement.
    Contains optional label, optional mnemonic/directive, operands, and comment.
    """
    label: Optional[Label] = None
    mnemonic: Optional[str] = None     # e.g. 'LD', 'CALL', 'ORG', 'EQU'
    is_directive: bool = False         # True if assembler directive
    operands: List[Operand] = field(default_factory=list)
    comment: Optional[Comment] = None
    indent: str = ""                   # Original indentation before mnemonic
    raw_line: str = ""                 # Original source line

@dataclass
class Program:
    """Top-level container for an assembly file AST."""
    lines: List[Node] = field(default_factory=list)
    source_dialect: Optional[str] = None
