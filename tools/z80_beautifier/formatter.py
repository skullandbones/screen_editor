"""
Source code formatter for Z80 assembly.
Serializes Common IR AST nodes into formatted assembly source code
according to FormatterConfig schemas (FMT_STMT, FMT_LABEL, FMT_COMMENT, FMT_CASE).
"""

from typing import Optional, List
from .ir import (
    Program, Node, BlankLine, CommentLine, StatementLine,
    Operand, RegisterOperand, IndexedOperand, ConditionOperand, ExpressionOperand,
    Expression, NumberLiteral, StringLiteral, Identifier, LocationCounter,
    UnaryOp, BinaryOp, Parenthesized
)
from .config import FormatterConfig
from .dialects.base import Dialect
from .dialects.z88dk import Z88dkDialect

class Formatter:
    """Serializes AST into formatted text lines according to configuration schemas."""

    def __init__(self, config: Optional[FormatterConfig] = None, dialect: Optional[Dialect] = None):
        self.config = config or FormatterConfig()
        self.dialect = dialect or Z88dkDialect()

    def format_program(self, program: Program) -> str:
        """Format an entire Program AST into a source code string."""
        formatted_lines = []
        for line_node in program.lines:
            f_line = self.format_node(line_node)
            formatted_lines.append(f_line)
        return "\n".join(formatted_lines) + "\n"

    def format_node(self, node: Node) -> str:
        """Format a single AST node into its text line."""
        if isinstance(node, BlankLine):
            return ""

        if isinstance(node, CommentLine):
            return self.format_comment_line(node)

        if isinstance(node, StatementLine):
            return self.format_statement(node)

        return ""

    def format_comment_line(self, node: CommentLine) -> str:
        """Format a standalone comment line according to FMT_COMMENT schema."""
        c_schema = self.config.comment_schema
        if not node.indent:
            # Comment started at column 1 (banner / section header)
            if c_schema.col1 in ('1sA', '0s', 'keep'):
                return f"{node.delimiter}{node.text}"
            else:
                indent, _ = self.config.emit_separator(1, self.config.stmt_schema.mnem)
                return f"{indent}{node.delimiter}{node.text}"
        else:
            # Indented comment
            if c_schema.indented == 'M':
                indent, _ = self.config.emit_separator(1, self.config.stmt_schema.mnem)
                return f"{indent}{node.delimiter}{node.text}"
            elif c_schema.indented == 'P':
                return f"{node.indent}{node.delimiter}{node.text}"
            elif c_schema.indented == 'N':
                # Align to nearest tab stop
                col = 1
                for ch in node.indent:
                    col = ((col - 1) // self.config.tab_width + 1) * self.config.tab_width + 1 if ch == '\t' else col + 1
                target_col = ((col - 1) // self.config.tab_width + 1) * self.config.tab_width + 1
                indent, _ = self.config.emit_separator(1, self.config.stmt_schema.mnem)
                return f"{indent}{node.delimiter}{node.text}"
            else:
                indent, _ = self.config.emit_separator(1, self.config.stmt_schema.mnem)
                return f"{indent}{node.delimiter}{node.text}"

    def format_statement(self, stmt: StatementLine) -> str:
        """
        Format a statement line respecting the 4 unified schemas:
        FMT_LABEL -> FMT_STMT (mnem, op1, op2, comm) -> FMT_CASE.
        """
        out = []
        col = 1  # 1-based column tracker

        # 1. Format Label
        if stmt.label:
            # Position to label column
            if self.config.label_schema.col.count > 1 or self.config.label_schema.col.mode == 'A':
                if col < self.config.label_schema.col.count:
                    ws, col = self.config.emit_separator(col, self.config.label_schema.col)
                    out.append(ws)

            # Colon rule: ':', '-', '?'
            c_rule = self.config.label_schema.colon
            has_colon = stmt.label.has_colon
            if c_rule == ':':
                has_colon = True
            elif c_rule == '-':
                has_colon = False

            lbl_text = self.dialect.format_label(
                stmt.label.name,
                has_colon,
                stmt.label.is_public,
                stmt.label.is_local
            )
            lbl_formatted = self.config.format_case(lbl_text, self.config.case_schema.label)
            out.append(lbl_formatted)
            col += len(lbl_formatted)

            # Placement rule: 'S' (same line), 'N' (next line), 'O' (next line on overflow)
            p_rule = self.config.label_schema.placement
            if stmt.mnemonic:
                mnem_target = self.config.stmt_schema.mnem.count if self.config.stmt_schema.mnem.mode == 'A' else 9
                if p_rule == 'N' or (p_rule == 'O' and col >= mnem_target):
                    out.append("\n")
                    col = 1

        # 2. Format Mnemonic / Directive
        if stmt.mnemonic:
            ws, col = self.config.emit_separator(col, self.config.stmt_schema.mnem)
            out.append(ws)

            if stmt.is_directive:
                raw_dir = self.dialect.format_directive(stmt.mnemonic)
                mnem_formatted = self.config.format_case(raw_dir, self.config.case_schema.constant)
            else:
                mnem_formatted = self.config.format_case(stmt.mnemonic, self.config.case_schema.mnemonic)

            out.append(mnem_formatted)
            col += len(mnem_formatted)

        # 3. Format Operands
        if stmt.operands:
            ws, col = self.config.emit_separator(col, self.config.stmt_schema.op1)
            out.append(ws)

            sep_op2_str, _ = self.config.emit_separator(0, self.config.stmt_schema.op2)
            delim = f",{sep_op2_str}"
            op_strs = [self.format_operand(op) for op in stmt.operands]
            operands_text = delim.join(op_strs)
            out.append(operands_text)
            col += len(operands_text)

        # 4. Format Inline Comment
        if stmt.comment:
            ws, col = self.config.emit_separator(col, self.config.stmt_schema.comm)
            out.append(ws)

            c_text = f"{stmt.comment.delimiter}{stmt.comment.text}"
            out.append(c_text)
            col += len(c_text)

        return "".join(out).rstrip()

    def format_operand(self, op: Operand) -> str:
        """Format an operand AST node."""
        if isinstance(op, RegisterOperand):
            reg = self.config.format_case(op.name, self.config.case_schema.operand)
            return f"({reg})" if op.is_indirect else reg

        if isinstance(op, IndexedOperand):
            base_reg = self.config.format_case(op.base, self.config.case_schema.operand)
            disp_str = self.format_expression(op.displacement)
            return self.dialect.format_indexed(base_reg, disp_str)

        if isinstance(op, ConditionOperand):
            return self.config.format_case(op.code, self.config.case_schema.operand)

        if isinstance(op, ExpressionOperand):
            expr_str = self.format_expression(op.expr)
            return f"({expr_str})" if op.is_indirect else expr_str

        return ""

    def format_expression(self, expr: Expression) -> str:
        """Format an expression AST node."""
        if isinstance(expr, NumberLiteral):
            formatted_num = self.dialect.format_number(expr.value, expr.base, expr.original_text)
            if self.config.case_schema.constant == 'lower':
                return formatted_num.lower()
            elif self.config.case_schema.constant == 'upper':
                return formatted_num.upper()
            return formatted_num

        if isinstance(expr, StringLiteral):
            return self.dialect.format_string(expr.value, is_char=expr.is_char_const)

        if isinstance(expr, Identifier):
            id_name = self.dialect.format_identifier(expr.name)
            return self.config.format_case(id_name, self.config.case_schema.label)

        if isinstance(expr, LocationCounter):
            return self.dialect.format_location_counter()

        if isinstance(expr, UnaryOp):
            formatted_op = self.dialect.format_operator(expr.op)
            if self.config.case_schema.constant == 'lower':
                formatted_op = formatted_op.lower()
            elif self.config.case_schema.constant == 'upper':
                formatted_op = formatted_op.upper()
            inner = self.format_expression(expr.operand)
            space = " " if formatted_op.isalpha() else ""
            return f"{formatted_op}{space}{inner}"

        if isinstance(expr, BinaryOp):
            left_str = self.format_expression(expr.left)
            right_str = self.format_expression(expr.right)
            formatted_op = self.dialect.format_operator(expr.op)
            if self.config.case_schema.constant == 'lower':
                formatted_op = formatted_op.lower()
            elif self.config.case_schema.constant == 'upper':
                formatted_op = formatted_op.upper()
            return f"{left_str} {formatted_op} {right_str}"

        if isinstance(expr, Parenthesized):
            inner = self.format_expression(expr.expr)
            return f"({inner})"

        return ""
