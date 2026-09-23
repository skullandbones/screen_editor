"""
Dialect-to-Dialect Source Code Reformatter.
Transforms Z80 source code from one assembler dialect to another
via the Common IR AST while preserving exact program semantics,
labels, and comments.
"""

from typing import List, Optional, Tuple
from .config import FormatterConfig
from .dialects import get_dialect, Dialect
from .ir import Program, StatementLine, Node, BlankLine, CommentLine
from .parser import Parser
from .formatter import Formatter

class Reformatter:
    """Orchestrates parsing, AST transformation, and dialect-specific emission."""

    def __init__(
        self,
        source_dialect: str = "z88dk",
        target_dialect: str = "z88dk",
        config: Optional[FormatterConfig] = None
    ):
        self.source_dialect_name = source_dialect
        self.target_dialect_name = target_dialect
        self.source_dialect = get_dialect(source_dialect)
        self.target_dialect = get_dialect(target_dialect)
        self.config = config or FormatterConfig()

    def reformat(self, source_text: str) -> Tuple[str, List[str]]:
        """
        Reformat source code to target dialect and style.
        Returns: (reformatted_source_code, list_of_warnings)
        """
        warnings: List[str] = []

        # 1. Parse into Common IR AST
        parser = Parser(default_dialect=self.source_dialect_name)
        program = parser.parse_source(source_text)

        # 2. Validate instructions against target dialect
        for node in program.lines:
            if isinstance(node, StatementLine) and node.mnemonic:
                node_warnings = self.target_dialect.validate_instruction(
                    node.mnemonic, node.operands
                )
                warnings.extend(node_warnings)

        # 3. Add dialect prologue if required
        prologue_lines = self.target_dialect.get_prologue()
        if prologue_lines:
            # Check if prologue already present in source
            has_prologue = any(
                isinstance(n, StatementLine) and n.mnemonic and
                n.mnemonic.upper().lstrip('.') == prologue_lines[0].strip().upper().lstrip('.')
                for n in program.lines
            )
            if not has_prologue:
                prologue_nodes = [parser.parse_line(pl) for pl in prologue_lines]
                program.lines = prologue_nodes + program.lines

        # 4. Add dialect epilogue if required
        epilogue_lines = self.target_dialect.get_epilogue()
        if epilogue_lines:
            has_end = any(
                isinstance(n, StatementLine) and n.mnemonic and
                n.mnemonic.upper().lstrip('.') == 'END'
                for n in program.lines
            )
            if not has_end:
                epilogue_nodes = [parser.parse_line(el) for el in epilogue_lines]
                program.lines.extend(epilogue_nodes)

        # 5. Format to target dialect using Formatter
        formatter = Formatter(config=self.config, dialect=self.target_dialect)
        output_text = formatter.format_program(program)

        return output_text, warnings
