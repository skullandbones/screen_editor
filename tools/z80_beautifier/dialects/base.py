"""
Abstract base class for Z80 assembler dialects.
Defines syntax rules, directive translation, literal formatting,
and construct compatibility validation.
"""

from abc import ABC, abstractmethod
from typing import List, Optional

class Dialect(ABC):
    """Abstract interface defining syntactic rules for an assembler dialect."""

    @property
    @abstractmethod
    def name(self) -> str:
        """Name of the dialect."""
        pass

    @abstractmethod
    def format_directive(self, mnemonic: str) -> str:
        """Translate a canonical directive (ORG, EQU, DB, DW, DS, etc.) into dialect syntax."""
        pass

    @abstractmethod
    def format_number(self, value: int, base: int, original_text: str = "") -> str:
        """Format a numeric literal in the dialect's expected syntax."""
        pass

    @abstractmethod
    def format_string(self, value: str, is_char: bool = False) -> str:
        """Format a string or character literal with proper quoting and escape handling."""
        pass

    @abstractmethod
    def format_operator(self, op: str) -> str:
        """Format a binary or unary operator (e.g. AND vs &, SHL vs <<)."""
        pass

    @abstractmethod
    def format_location_counter(self) -> str:
        """Return the symbol for the current program counter ($ or *)."""
        pass

    @abstractmethod
    def format_label(self, name: str, has_colon: bool, is_public: bool = False, is_local: bool = False) -> str:
        """Format a label declaration according to dialect conventions."""
        pass

    @abstractmethod
    def format_indexed(self, base_reg: str, disp_str: str) -> str:
        """Format an indexed register memory operand: (IX+d), (IY-d)."""
        pass

    def format_identifier(self, name: str) -> str:
        """Format an identifier reference (translating local label prefix if applicable)."""
        return name

    def get_prologue(self) -> List[str]:
        """Optional header directives (e.g. .Z80 for M80)."""
        return []

    def get_epilogue(self) -> List[str]:
        """Optional footer directives (e.g. END or .END)."""
        return []

    def validate_instruction(self, mnemonic: str, operands: list) -> List[str]:
        """Validate if instruction and operands are supported in this dialect. Returns warnings/errors."""
        return []
