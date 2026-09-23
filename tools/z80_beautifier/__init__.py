"""
Z80 Assembly Beautifier and Multi-Dialect Reformatter Package.
"""

from .config import FormatterConfig
from .ir import Program, StatementLine, CommentLine, BlankLine
from .lexer import Lexer, Token, TokenType
from .parser import Parser
from .formatter import Formatter
from .reformatter import Reformatter
from .dialects import get_dialect, Dialect

__version__ = "1.0.0"
__all__ = [
    "FormatterConfig",
    "Program",
    "StatementLine",
    "CommentLine",
    "BlankLine",
    "Lexer",
    "Token",
    "TokenType",
    "Parser",
    "Formatter",
    "Reformatter",
    "get_dialect",
    "Dialect",
]
