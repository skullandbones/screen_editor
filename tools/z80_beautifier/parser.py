"""
Z80 Assembly Multi-Dialect Parser.
Parses lines of assembly source code into the Common IR AST.
Recognizes instructions, directives, labels, operands, and expressions.
"""

from typing import List, Optional, Tuple
from .lexer import Lexer, Token, TokenType
from .ir import (
    Node, BlankLine, CommentLine, StatementLine, Label, Comment,
    Operand, RegisterOperand, IndexedOperand, ConditionOperand, ExpressionOperand,
    Expression, NumberLiteral, StringLiteral, Identifier, LocationCounter,
    UnaryOp, BinaryOp, Parenthesized,
    Z80_REGISTERS, Z80_CONDITIONS, COMMON_DIRECTIVES, Program
)

# Instructions where first operand can be a condition code
CONDITIONAL_INSTRUCTIONS = {'JP', 'JR', 'CALL', 'RET'}

class ExpressionParser:
    """Parses operand expressions into an Expression AST."""

    def __init__(self, tokens: List[Token]):
        self.tokens = tokens
        self.pos = 0

    def current_token(self) -> Optional[Token]:
        if self.pos < len(self.tokens):
            return self.tokens[self.pos]
        return None

    def match(self, token_type: str, value: any = None) -> bool:
        tok = self.current_token()
        if not tok:
            return False
        if tok.type != token_type:
            return False
        if value is not None and tok.value != value:
            return False
        self.pos += 1
        return True

    def parse(self) -> Expression:
        return self.parse_bitwise_or()

    def parse_bitwise_or(self) -> Expression:
        node = self.parse_bitwise_xor()
        while True:
            tok = self.current_token()
            if tok and (tok.type == TokenType.OPERATOR and tok.value in ('|', '||') or
                        tok.type == TokenType.IDENTIFIER and tok.value.upper() == 'OR'):
                self.pos += 1
                right = self.parse_bitwise_xor()
                node = BinaryOp(left=node, op='OR', right=right)
            else:
                break
        return node

    def parse_bitwise_xor(self) -> Expression:
        node = self.parse_bitwise_and()
        while True:
            tok = self.current_token()
            if tok and (tok.type == TokenType.OPERATOR and tok.value in ('^', '^^') or
                        tok.type == TokenType.IDENTIFIER and tok.value.upper() == 'XOR'):
                self.pos += 1
                right = self.parse_bitwise_and()
                node = BinaryOp(left=node, op='XOR', right=right)
            else:
                break
        return node

    def parse_bitwise_and(self) -> Expression:
        node = self.parse_shift()
        while True:
            tok = self.current_token()
            if tok and (tok.type == TokenType.OPERATOR and tok.value in ('&', '&&') or
                        tok.type == TokenType.IDENTIFIER and tok.value.upper() == 'AND'):
                self.pos += 1
                right = self.parse_shift()
                node = BinaryOp(left=node, op='AND', right=right)
            else:
                break
        return node

    def parse_shift(self) -> Expression:
        node = self.parse_additive()
        while True:
            tok = self.current_token()
            if tok and tok.type == TokenType.OPERATOR and tok.value in ('<<', '>>'):
                op = 'SHL' if tok.value == '<<' else 'SHR'
                self.pos += 1
                right = self.parse_additive()
                node = BinaryOp(left=node, op=op, right=right)
            elif tok and tok.type == TokenType.IDENTIFIER and tok.value.upper() in ('SHL', 'SHR'):
                op = tok.value.upper()
                self.pos += 1
                right = self.parse_additive()
                node = BinaryOp(left=node, op=op, right=right)
            else:
                break
        return node

    def parse_additive(self) -> Expression:
        node = self.parse_multiplicative()
        while True:
            tok = self.current_token()
            if tok and tok.type == TokenType.OPERATOR and tok.value in ('+', '-'):
                op = tok.value
                self.pos += 1
                right = self.parse_multiplicative()
                node = BinaryOp(left=node, op=op, right=right)
            else:
                break
        return node

    def parse_multiplicative(self) -> Expression:
        node = self.parse_unary()
        while True:
            tok = self.current_token()
            if tok and tok.type == TokenType.OPERATOR and tok.value in ('*', '/', '%'):
                op = 'MOD' if tok.value == '%' else tok.value
                self.pos += 1
                right = self.parse_unary()
                node = BinaryOp(left=node, op=op, right=right)
            elif tok and tok.type == TokenType.IDENTIFIER and tok.value.upper() == 'MOD':
                self.pos += 1
                right = self.parse_unary()
                node = BinaryOp(left=node, op='MOD', right=right)
            else:
                break
        return node

    def parse_unary(self) -> Expression:
        tok = self.current_token()
        if tok and tok.type == TokenType.OPERATOR and tok.value in ('+', '-', '~', '!'):
            op = tok.value
            self.pos += 1
            operand = self.parse_unary()
            return UnaryOp(op=op, operand=operand)
        if tok and tok.type == TokenType.IDENTIFIER and tok.value.upper() == 'NOT':
            self.pos += 1
            operand = self.parse_unary()
            return UnaryOp(op='NOT', operand=operand)
        return self.parse_primary()

    def parse_primary(self) -> Expression:
        tok = self.current_token()
        if not tok:
            return NumberLiteral(value=0, base=10, original_text="0")

        # Parenthesized expression: ( expr )
        if tok.type in (TokenType.LPAREN, TokenType.LBRACKET):
            close_type = TokenType.RPAREN if tok.type == TokenType.LPAREN else TokenType.RBRACKET
            self.pos += 1
            inner = self.parse()
            self.match(close_type)
            return Parenthesized(expr=inner)

        # Numbers
        if tok.type == TokenType.NUMBER:
            self.pos += 1
            return NumberLiteral(value=tok.value, base=tok.base, original_text=tok.raw)

        # Strings & Character literals
        if tok.type in (TokenType.STRING, TokenType.CHAR):
            self.pos += 1
            quote = "'" if tok.raw.startswith("'") else '"'
            return StringLiteral(value=tok.value, quote_char=quote, is_char_const=(tok.type == TokenType.CHAR))

        # Location counter ($ or *)
        if tok.type == TokenType.IDENTIFIER and tok.value in ('$', 'ASMPC'):
            self.pos += 1
            return LocationCounter(symbol='$')

        # Generic symbol / identifier
        if tok.type == TokenType.IDENTIFIER:
            self.pos += 1
            return Identifier(name=tok.value)

        # Fallback
        self.pos += 1
        return Identifier(name=tok.raw)


class Parser:
    """Parses Z80 source lines into Common IR AST nodes."""

    def __init__(self, default_dialect: Optional[str] = None):
        self.default_dialect = default_dialect

    def parse_source(self, text: str) -> Program:
        """Parse an entire multi-line source string into a Program AST."""
        program = Program(source_dialect=self.default_dialect)
        for line in text.splitlines(keepends=False):
            node = self.parse_line(line)
            program.lines.append(node)
        return program

    def parse_line(self, line_text: str) -> Node:
        """Parse a single line of assembly code into an AST node."""
        stripped = line_text.strip()
        if not stripped:
            return BlankLine(raw_text=line_text)

        lexer = Lexer(line_text)
        tokens, comment_token = lexer.tokenize_line()

        # Check for full-line comment
        if not tokens and comment_token:
            # Measure leading indentation
            indent_len = comment_token.col - 1
            indent = line_text[:indent_len]
            delim = comment_token.raw[:2] if comment_token.raw.startswith('//') else comment_token.raw[0]
            return CommentLine(indent=indent, delimiter=delim, text=comment_token.value)

        if not tokens:
            return BlankLine(raw_text=line_text)

        # Parse Statement Line (label, mnemonic, operands, comment)
        pos = 0
        total_tokens = len(tokens)
        label: Optional[Label] = None
        mnemonic: Optional[str] = None
        operands: List[Operand] = []

        # 1. Parse optional label
        first_tok = tokens[0]
        has_label = False

        if total_tokens > 1 and tokens[1].type in (TokenType.COLON, TokenType.DOUBLE_COLON):
            # Explicit label: LABEL: or LABEL::
            is_pub = (tokens[1].type == TokenType.DOUBLE_COLON)
            lbl_name = first_tok.value
            is_loc, prefix = self._detect_local_label(lbl_name)
            label = Label(name=lbl_name, has_colon=True, is_local=is_loc, local_prefix=prefix, is_public=is_pub)
            pos = 2
            has_label = True
        elif first_tok.col == 1 and first_tok.type == TokenType.IDENTIFIER:
            # Column 1 identifier without colon:
            # Check if next token is an EQU/SET directive or an instruction
            is_loc, prefix = self._detect_local_label(first_tok.value)
            if total_tokens > 1:
                next_val = tokens[1].value.upper() if isinstance(tokens[1].value, str) else ""
                if next_val in COMMON_DIRECTIVES or next_val == '=':
                    # e.g. "VAR EQU 5" or "VAR = 5"
                    label = Label(name=first_tok.value, has_colon=False, is_local=is_loc, local_prefix=prefix)
                    pos = 1
                    has_label = True
                elif next_val and self._is_z80_instruction(next_val):
                    # e.g. "START NOP"
                    label = Label(name=first_tok.value, has_colon=False, is_local=is_loc, local_prefix=prefix)
                    pos = 1
                    has_label = True
                elif not self._is_z80_instruction(first_tok.value.upper()):
                    # Lone label in column 1
                    if total_tokens == 1:
                        label = Label(name=first_tok.value, has_colon=False, is_local=is_loc, local_prefix=prefix)
                        pos = 1
                        has_label = True

        # 2. Parse optional mnemonic / directive
        if pos < total_tokens:
            tok = tokens[pos]
            mnemonic = tok.value
            pos += 1

        # 3. Parse comma-separated operands
        if pos < total_tokens and mnemonic:
            operands = self._parse_operands(mnemonic.upper(), tokens[pos:])

        # 4. Attach inline comment
        comment = None
        if comment_token:
            delim = comment_token.raw[:2] if comment_token.raw.startswith('//') else comment_token.raw[0]
            comment = Comment(delimiter=delim, text=comment_token.value)

        # Detect directive
        is_dir = False
        if mnemonic:
            upper_mnem = mnemonic.upper()
            if upper_mnem == 'SET':
                # Z80 bit set instruction takes 2 operands: SET bit, target
                # Directive SET takes a label and 1 operand: LABEL SET expr
                is_dir = (len(operands) != 2)
            else:
                is_dir = (upper_mnem in COMMON_DIRECTIVES or upper_mnem == '=' or upper_mnem.startswith('.'))

        return StatementLine(
            label=label,
            mnemonic=mnemonic,
            is_directive=is_dir,
            operands=operands,
            comment=comment,
            indent="",
            raw_line=line_text
        )

    def _detect_local_label(self, name: str) -> Tuple[bool, str]:
        """Detect local label indicators (@, _, .)."""
        if name.startswith('@'):
            return True, '@'
        if name.startswith('_'):
            return True, '_'
        if name.startswith('.'):
            return True, '.'
        return False, ""

    def _is_z80_instruction(self, mnemonic: str) -> bool:
        """Check if mnemonic is a recognized Z80 CPU instruction."""
        return mnemonic in {
            'NOP', 'LD', 'INC', 'DEC', 'ADD', 'ADC', 'SUB', 'SBC',
            'AND', 'XOR', 'OR', 'CP', 'RLCA', 'RRCA', 'RLA', 'RRA',
            'DAA', 'CPL', 'SCF', 'CCF', 'HALT', 'EXX', 'DI', 'EI',
            'NEG', 'IM', 'RETN', 'RETI', 'RRD', 'RLD',
            'JP', 'JR', 'CALL', 'RET', 'RST', 'PUSH', 'POP',
            'EX', 'IN', 'OUT', 'LDI', 'CPI', 'INI', 'OUTI',
            'LDD', 'CPD', 'IND', 'OUTD', 'LDIR', 'CPIR', 'INIR', 'OTIR',
            'LDDR', 'CPDR', 'INDR', 'OTDR', 'RLC', 'RRC', 'RL', 'RR',
            'SLA', 'SRA', 'SRL', 'SLL', 'BIT', 'SET', 'RES', 'DJNZ'
        }

    def _parse_operands(self, upper_mnem: str, operand_tokens: List[Token]) -> List[Operand]:
        """Split operand tokens by comma and parse each into an Operand AST."""
        groups: List[List[Token]] = []
        current: List[Token] = []
        paren_depth = 0
        bracket_depth = 0

        for tok in operand_tokens:
            if tok.type == TokenType.LPAREN:
                paren_depth += 1
            elif tok.type == TokenType.RPAREN:
                paren_depth = max(0, paren_depth - 1)
            elif tok.type == TokenType.LBRACKET:
                bracket_depth += 1
            elif tok.type == TokenType.RBRACKET:
                bracket_depth = max(0, bracket_depth - 1)

            if tok.type == TokenType.COMMA and paren_depth == 0 and bracket_depth == 0:
                groups.append(current)
                current = []
            else:
                current.append(tok)
        if current:
            groups.append(current)

        operands: List[Operand] = []
        for i, grp in enumerate(groups):
            if not grp:
                continue
            op = self._parse_single_operand(upper_mnem, i, grp)
            operands.append(op)

        return operands
 
    def _is_enclosed_in_parens(self, toks: List[Token]) -> bool:
        """Check if toks is enclosed in a single outermost pair of parentheses or brackets."""
        if len(toks) < 2:
            return False
        open_tok = toks[0].type
        close_tok = toks[-1].type
        if open_tok == TokenType.LPAREN and close_tok != TokenType.RPAREN:
            return False
        if open_tok == TokenType.LBRACKET and close_tok != TokenType.RBRACKET:
            return False
        if open_tok not in (TokenType.LPAREN, TokenType.LBRACKET):
            return False

        depth = 0
        for i, t in enumerate(toks):
            if t.type in (TokenType.LPAREN, TokenType.LBRACKET):
                depth += 1
            elif t.type in (TokenType.RPAREN, TokenType.RBRACKET):
                depth -= 1
                if depth == 0 and i < len(toks) - 1:
                    return False
        return depth == 0

    def _parse_single_operand(self, upper_mnem: str, op_idx: int, toks: List[Token]) -> Operand:
        """Parse one operand token sequence into an Operand object."""
        # 1. Condition code check (e.g. JP NZ, addr or RET C)
        if upper_mnem in CONDITIONAL_INSTRUCTIONS and op_idx == 0 and len(toks) == 1:
            tok = toks[0]
            if tok.type == TokenType.IDENTIFIER and tok.value.upper() in Z80_CONDITIONS:
                return ConditionOperand(code=tok.value.upper())

        # 2. Direct Register check (A, BC, HL, IX, SP, AF', etc.)
        if len(toks) == 1 and toks[0].type == TokenType.IDENTIFIER:
            upper_val = toks[0].value.upper()
            if upper_val in Z80_REGISTERS:
                return RegisterOperand(name=upper_val, is_indirect=False)

        # 3. Indirection: ( ... ) or [ ... ]
        if self._is_enclosed_in_parens(toks):
            inner_toks = toks[1:-1]

            # Check for simple register indirection: (HL), (BC), (DE), (SP), (C)
            if len(inner_toks) == 1 and inner_toks[0].type == TokenType.IDENTIFIER:
                upper_inner = inner_toks[0].value.upper()
                if upper_inner in ('HL', 'BC', 'DE', 'SP', 'C', 'IX', 'IY'):
                    if upper_inner in ('IX', 'IY'):
                        # (IX) without displacement is equivalent to (IX+0)
                        return IndexedOperand(base=upper_inner, displacement=NumberLiteral(0, 10, "0"))
                    return RegisterOperand(name=upper_inner, is_indirect=True)

            # Check for Indexed indirection: (IX + d), (IY - d), (IX + 4)
            if len(inner_toks) >= 3 and inner_toks[0].type == TokenType.IDENTIFIER:
                base_reg = inner_toks[0].value.upper()
                if base_reg in ('IX', 'IY') and inner_toks[1].type == TokenType.OPERATOR and inner_toks[1].value in ('+', '-'):
                    sign = inner_toks[1].value
                    disp_expr = ExpressionParser(inner_toks[2:]).parse()
                    if sign == '-':
                        disp_expr = UnaryOp(op='-', operand=disp_expr)
                    return IndexedOperand(base=base_reg, displacement=disp_expr)

            # Generic memory indirection: (nn) or (addr + offset)
            expr = ExpressionParser(inner_toks).parse()
            return ExpressionOperand(expr=expr, is_indirect=True)

        # 4. Immediate / Expression operand
        expr = ExpressionParser(toks).parse()
        return ExpressionOperand(expr=expr, is_indirect=False)
