"""
Z80 Assembly Lexer supporting multi-dialect tokenization.
Handles various hexadecimal, binary, and octal notations, strings,
operators, and comment conventions across z88dk, TASM, SLR, and M80.
"""

import re
from dataclasses import dataclass
from typing import List, Optional, Tuple

class TokenType:
    IDENTIFIER = 'IDENTIFIER'
    NUMBER = 'NUMBER'
    STRING = 'STRING'
    CHAR = 'CHAR'
    COMMA = 'COMMA'
    COLON = 'COLON'
    DOUBLE_COLON = 'DOUBLE_COLON'
    LPAREN = 'LPAREN'
    RPAREN = 'RPAREN'
    LBRACKET = 'LBRACKET'
    RBRACKET = 'RBRACKET'
    OPERATOR = 'OPERATOR'
    COMMENT = 'COMMENT'
    EOF = 'EOF'

@dataclass
class Token:
    type: str
    value: any
    raw: str
    col: int                           # 1-based start column
    base: int = 10                     # For NUMBER tokens (16, 10, 2, 8)

class Lexer:
    """Tokenizes a single line or stream of Z80 assembly code."""

    def __init__(self, line: str):
        self.line = line
        self.pos = 0
        self.length = len(line)

    def current_char(self) -> Optional[str]:
        if self.pos < self.length:
            return self.line[self.pos]
        return None

    def peek_char(self, offset: int = 1) -> Optional[str]:
        p = self.pos + offset
        if p < self.length:
            return self.line[p]
        return None

    def skip_whitespace(self):
        while self.pos < self.length and self.line[self.pos] in ' \t\r\n':
            self.pos += 1

    def tokenize_line(self) -> Tuple[List[Token], Optional[Token]]:
        """
        Tokenize line into statement tokens and an optional trailing comment token.
        """
        tokens: List[Token] = []
        comment_token: Optional[Token] = None

        self.skip_whitespace()
        if self.pos >= self.length:
            return tokens, None

        # Check for full-line comment (including * in col 0)
        first_char = self.line[self.pos]
        if first_char == ';' or self.line[self.pos:self.pos+2] == '//' or (self.pos == 0 and first_char == '*'):
            delim = '//' if self.line[self.pos:self.pos+2] == '//' else first_char
            c_text = self.line[self.pos + len(delim):].rstrip('\r\n')
            comment_token = Token(TokenType.COMMENT, c_text, self.line[self.pos:], self.pos + 1)
            return tokens, comment_token

        while self.pos < self.length:
            self.skip_whitespace()
            if self.pos >= self.length:
                break

            ch = self.line[self.pos]
            start_col = self.pos + 1

            # Inline comments
            if ch == ';' or self.line[self.pos:self.pos+2] == '//':
                delim = '//' if self.line[self.pos:self.pos+2] == '//' else ';'
                c_text = self.line[self.pos + len(delim):].rstrip('\r\n')
                comment_token = Token(TokenType.COMMENT, c_text, self.line[self.pos:], start_col)
                break

            # Colons (: and ::)
            if ch == ':':
                if self.peek_char() == ':':
                    self.pos += 2
                    tokens.append(Token(TokenType.DOUBLE_COLON, '::', '::', start_col))
                else:
                    self.pos += 1
                    tokens.append(Token(TokenType.COLON, ':', ':', start_col))
                continue

            # Commas
            if ch == ',':
                self.pos += 1
                tokens.append(Token(TokenType.COMMA, ',', ',', start_col))
                continue

            # Parentheses and Brackets
            if ch == '(':
                self.pos += 1
                tokens.append(Token(TokenType.LPAREN, '(', '(', start_col))
                continue
            if ch == ')':
                self.pos += 1
                tokens.append(Token(TokenType.RPAREN, ')', ')', start_col))
                continue
            if ch == '[':
                self.pos += 1
                tokens.append(Token(TokenType.LBRACKET, '[', '[', start_col))
                continue
            if ch == ']':
                self.pos += 1
                tokens.append(Token(TokenType.RBRACKET, ']', ']', start_col))
                continue

            # Strings and Character Literals
            if ch in ('"', "'"):
                token = self._lex_string(ch)
                tokens.append(token)
                continue

            # Number literals (hex $FF, 0xFF, %1010, @077, 1234, 0FFFFH)
            if ch == '$' and self.peek_char() and self.peek_char() in '0123456789abcdefABCDEF':
                token = self._lex_dollar_hex()
                tokens.append(token)
                continue

            if ch == '%' and self.peek_char() and self.peek_char() in '01':
                token = self._lex_percent_bin()
                tokens.append(token)
                continue

            if ch == '@' and self.peek_char() and self.peek_char() in '01234567':
                token = self._lex_at_octal()
                tokens.append(token)
                continue

            if ch.isdigit():
                token = self._lex_number_or_ident()
                tokens.append(token)
                continue

            # Location counter symbol ($ or * as standalone symbol)
            if ch in ('$', '*'):
                # Distinguish * operator from location counter
                # If * or $ followed by identifier/alphanumeric, lex as identifier
                # Otherwise, if standalone:
                if ch == '$':
                    if not (self.peek_char() and (self.peek_char().isalnum() or self.peek_char() == '_')):
                        self.pos += 1
                        tokens.append(Token(TokenType.IDENTIFIER, '$', '$', start_col))
                        continue
                elif ch == '*':
                    # Operator *
                    self.pos += 1
                    tokens.append(Token(TokenType.OPERATOR, '*', '*', start_col))
                    continue

            # Multi-character operators
            two_chars = self.line[self.pos:self.pos+2]
            if two_chars in ('<<', '>>', '<=', '>=', '==', '!=', '&&', '||'):
                self.pos += 2
                tokens.append(Token(TokenType.OPERATOR, two_chars, two_chars, start_col))
                continue

            # Single-character operators
            if ch in '+-/<>&|^~=!':
                self.pos += 1
                tokens.append(Token(TokenType.OPERATOR, ch, ch, start_col))
                continue

            # Identifiers and keywords (including directives with leading dot or hash)
            if ch.isalpha() or ch in '_@.#?':
                token = self._lex_identifier()
                tokens.append(token)
                continue

            # Unknown character: treat as operator
            self.pos += 1
            tokens.append(Token(TokenType.OPERATOR, ch, ch, start_col))

        return tokens, comment_token

    def _lex_string(self, quote: str) -> Token:
        start_col = self.pos + 1
        self.pos += 1  # Skip opening quote
        chars = []
        is_escaped = False

        while self.pos < self.length:
            c = self.line[self.pos]
            if is_escaped:
                if c == 'n': chars.append('\n')
                elif c == 'r': chars.append('\r')
                elif c == 't': chars.append('\t')
                elif c == '0': chars.append('\0')
                elif c == '\\': chars.append('\\')
                elif c == quote: chars.append(quote)
                else: chars.append(c)
                is_escaped = False
                self.pos += 1
            elif c == '\\':
                is_escaped = True
                self.pos += 1
            elif c == quote:
                # Check for doubled quote (e.g. '' in M80/SLR)
                if self.peek_char() == quote:
                    chars.append(quote)
                    self.pos += 2
                else:
                    self.pos += 1  # Closing quote
                    break
            else:
                chars.append(c)
                self.pos += 1

        val = "".join(chars)
        raw = self.line[start_col-1:self.pos]
        if quote == "'" and len(val) == 1:
            return Token(TokenType.CHAR, val, raw, start_col)
        return Token(TokenType.STRING, val, raw, start_col)

    def _lex_dollar_hex(self) -> Token:
        start_col = self.pos + 1
        self.pos += 1  # Skip '$'
        start = self.pos
        while self.pos < self.length and self.line[self.pos] in '0123456789abcdefABCDEF':
            self.pos += 1
        raw_digits = self.line[start:self.pos]
        val = int(raw_digits, 16)
        raw = '$' + raw_digits
        return Token(TokenType.NUMBER, val, raw, start_col, base=16)

    def _lex_percent_bin(self) -> Token:
        start_col = self.pos + 1
        self.pos += 1  # Skip '%'
        start = self.pos
        while self.pos < self.length and self.line[self.pos] in '01':
            self.pos += 1
        raw_digits = self.line[start:self.pos]
        val = int(raw_digits, 2)
        raw = '%' + raw_digits
        return Token(TokenType.NUMBER, val, raw, start_col, base=2)

    def _lex_at_octal(self) -> Token:
        start_col = self.pos + 1
        self.pos += 1  # Skip '@'
        start = self.pos
        while self.pos < self.length and self.line[self.pos] in '01234567':
            self.pos += 1
        raw_digits = self.line[start:self.pos]
        val = int(raw_digits, 8)
        raw = '@' + raw_digits
        return Token(TokenType.NUMBER, val, raw, start_col, base=8)

    def _lex_number_or_ident(self) -> Token:
        start_col = self.pos + 1
        start = self.pos

        # Check for 0x prefix
        if self.line[self.pos:self.pos+2].lower() == '0x':
            self.pos += 2
            while self.pos < self.length and self.line[self.pos] in '0123456789abcdefABCDEF':
                self.pos += 1
            raw = self.line[start:self.pos]
            val = int(raw[2:], 16)
            return Token(TokenType.NUMBER, val, raw, start_col, base=16)

        # Check for 0b prefix
        if self.line[self.pos:self.pos+2].lower() == '0b':
            self.pos += 2
            while self.pos < self.length and self.line[self.pos] in '01':
                self.pos += 1
            raw = self.line[start:self.pos]
            val = int(raw[2:], 2)
            return Token(TokenType.NUMBER, val, raw, start_col, base=2)

        # Read alphanumeric sequence
        while self.pos < self.length and (self.line[self.pos].isalnum() or self.line[self.pos] in '_$'):
            self.pos += 1
        raw = self.line[start:self.pos]
        upper = raw.upper()

        # Check suffix H (hex)
        if upper.endswith('H') and all(c in '0123456789ABCDEF' for c in upper[:-1]):
            val = int(upper[:-1], 16)
            return Token(TokenType.NUMBER, val, raw, start_col, base=16)

        # Check suffix B (binary)
        if upper.endswith('B') and all(c in '01' for c in upper[:-1]):
            val = int(upper[:-1], 2)
            return Token(TokenType.NUMBER, val, raw, start_col, base=2)

        # Check suffix O or Q (octal)
        if (upper.endswith('O') or upper.endswith('Q')) and all(c in '01234567' for c in upper[:-1]):
            val = int(upper[:-1], 8)
            return Token(TokenType.NUMBER, val, raw, start_col, base=8)

        # Plain decimal
        if raw.isdigit():
            val = int(raw, 10)
            return Token(TokenType.NUMBER, val, raw, start_col, base=10)

        # Identifier starting with digit (rare, but supported in some symbol tables)
        return Token(TokenType.IDENTIFIER, raw, raw, start_col)

    def _lex_identifier(self) -> Token:
        start_col = self.pos + 1
        start = self.pos
        # Allow leading dots (e.g. .ORG, .EQU), hash (#IFDEF), @, ?, $
        if self.line[self.pos] in '.#@?':
            self.pos += 1
        while self.pos < self.length and (self.line[self.pos].isalnum() or self.line[self.pos] in '_$@?.'):
            self.pos += 1
        raw = self.line[start:self.pos]
        # Check if immediately followed by apostrophe for prime register (e.g. AF')
        if self.pos < self.length and self.line[self.pos] == "'":
            candidate = (raw + "'").upper()
            if candidate in ('AF\'', 'BC\'', 'DE\'', 'HL\'', 'A\'', 'F\''):
                self.pos += 1
                raw = raw + "'"
        return Token(TokenType.IDENTIFIER, raw, raw, start_col)
