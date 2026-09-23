#!/usr/bin/env python3
"""
Comprehensive Regression Test Suite for Z80 Source Beautifier and Reformatter.
Verifies:
  1. Configurable column alignment (label, opcode, operand, comment)
  2. Tab and space expansion
  3. Case conversion (instruction, directive, register, label)
  4. Comment and label preservation
  5. Multi-dialect reformatting (z88dk, tasm/uz80as, slr, m80)
  6. Machine code byte-for-byte equivalence across assemblers:
     Source -> Parse -> Reformat -> Assemble -> Compare Binaries
  7. Unsupported / ambiguous construct diagnostics
"""

import os
import sys
import tempfile
import subprocess
import unittest

# Ensure tools/ package is importable
repo_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if repo_root not in sys.path:
    sys.path.insert(0, repo_root)

from tools.z80_beautifier import (
    FormatterConfig, Formatter, Reformatter, Parser, Lexer, TokenType, Program, get_dialect
)
from tools.z80_beautifier.ir import StatementLine, CommentLine, BlankLine

class TestZ80Beautifier(unittest.TestCase):

    def setUp(self):
        self.workspace_root = os.path.abspath(os.path.join(repo_root, "..", ".."))
        self.z88dk_bin = os.path.join(self.workspace_root, "tools", "z88dk", "bin", "z88dk-z80asm")
        self.uz80as_bin = os.path.join(self.workspace_root, "tools", "romwbw_src", "Tools", "Linux", "uz80as")
        self.zxcc_bin = os.path.join(self.workspace_root, "tools", "romwbw_src", "Tools", "Linux", "zxcc")
        self.cpm_dir = os.path.join(self.workspace_root, "tools", "romwbw_src", "Tools", "cpm")

    # -------------------------------------------------------------------------
    # 1. Lexer & Parser Tests
    # -------------------------------------------------------------------------

    def test_lexer_number_formats(self):
        """Test recognition of various hexadecimal, binary, and octal notations."""
        line = "LD A,$FF \t LD B,0x2A \t LD C,0A0H \t LD D,%10101010 \t LD E,1100B"
        lexer = Lexer(line)
        tokens, comment = lexer.tokenize_line()
        numbers = [t for t in tokens if t.type == TokenType.NUMBER]
        self.assertEqual(len(numbers), 5)
        self.assertEqual(numbers[0].value, 0xFF)
        self.assertEqual(numbers[0].base, 16)
        self.assertEqual(numbers[1].value, 0x2A)
        self.assertEqual(numbers[1].base, 16)
        self.assertEqual(numbers[2].value, 0xA0)
        self.assertEqual(numbers[2].base, 16)
        self.assertEqual(numbers[3].value, 0xAA)
        self.assertEqual(numbers[3].base, 2)
        self.assertEqual(numbers[4].value, 12)
        self.assertEqual(numbers[4].base, 2)

    def test_lexer_strings_and_escapes(self):
        """Test string literals with C-escapes and doubled quotes."""
        line = 'DB "Hello\\nWorld", \'Single Quote\'\'\', 0'
        lexer = Lexer(line)
        tokens, comment = lexer.tokenize_line()
        strings = [t for t in tokens if t.type == TokenType.STRING]
        self.assertEqual(len(strings), 2)
        self.assertEqual(strings[0].value, "Hello\nWorld")
        self.assertEqual(strings[1].value, "Single Quote'")

    def test_parser_instructions_and_operands(self):
        """Test parsing of complex Z80 addressing modes and expressions."""
        parser = Parser()
        prog = parser.parse_source("""
START:
\tLD\tA,(HL)
\tLD\t(IX+4),12H
\tJP\tNZ,TARGET
\tRET
""")
        stmts = [n for n in prog.lines if isinstance(n, StatementLine)]
        self.assertEqual(len(stmts), 5)
        self.assertEqual(stmts[0].label.name, "START")
        self.assertEqual(stmts[1].mnemonic, "LD")
        self.assertEqual(stmts[1].operands[0].name, "A")
        self.assertTrue(stmts[1].operands[1].is_indirect)
        self.assertEqual(stmts[1].operands[1].name, "HL")
        self.assertEqual(stmts[2].operands[0].base, "IX")
        self.assertEqual(stmts[3].mnemonic, "JP")
        self.assertEqual(stmts[3].operands[0].code, "NZ")

    # -------------------------------------------------------------------------
    # 2. Configurable Column Beautification Tests
    # -------------------------------------------------------------------------

    def test_column_alignment_standard(self):
        """Verify column placement: label=1, opcode=9, operand=17, comment=41."""
        source = "START: LD A,5 ; load accumulator\n NOP ; no-op"
        config = FormatterConfig(label_col=1, opcode_col=9, operand_col=17, comment_col=41, use_tabs=False)
        reformatter = Reformatter(config=config)
        out, _ = reformatter.reformat(source)
        lines = out.strip().split("\n")

        # Line 1: START:  at col 1, LD at col 9, A,5 at col 17, ; at col 41
        line1 = lines[0]
        self.assertTrue(line1.startswith("START:"))
        self.assertEqual(line1[8:10], "LD")
        self.assertEqual(line1[16:19], "A,5")
        self.assertEqual(line1.find(";"), 40)  # 0-indexed 40 is col 41

    def test_column_alignment_wide(self):
        """Verify wide column placement: label=1, opcode=16, operand=24, comment=48."""
        source = "LOOP: INC BC ; increment counter"
        config = FormatterConfig(label_col=1, opcode_col=16, operand_col=24, comment_col=48, use_tabs=False)
        reformatter = Reformatter(config=config)
        out, _ = reformatter.reformat(source)
        line = out.strip()

        self.assertTrue(line.startswith("LOOP:"))
        self.assertEqual(line[15:18], "INC")
        self.assertEqual(line[23:25], "BC")
        self.assertEqual(line.find(";"), 47)  # 0-indexed 47 is col 48

    def test_tabs_mode(self):
        """Verify tab character emission when use_tabs is enabled."""
        source = "START:\n\tNOP\t; comment"
        config = FormatterConfig(use_tabs=True, tab_width=8)
        reformatter = Reformatter(config=config)
        out, _ = reformatter.reformat(source)
        self.assertIn("\t", out)

    def test_case_conversions(self):
        """Verify instruction, register, and directive case options."""
        source = "entry: ld a, 0ffh \n db 1, 2"
        # Uppercase all
        cfg_upper = FormatterConfig(instruction_case='upper', directive_case='upper', register_case='upper')
        out_upper, _ = Reformatter(config=cfg_upper).reformat(source)
        self.assertIn("LD", out_upper)
        self.assertIn("A", out_upper)
        self.assertIn("DB", out_upper)

        # Lowercase all
        cfg_lower = FormatterConfig(instruction_case='lower', directive_case='lower', register_case='lower')
        out_lower, _ = Reformatter(config=cfg_lower).reformat(source)
        self.assertIn("ld", out_lower)
        self.assertIn("a", out_lower)
        self.assertIn("db", out_lower)

    def test_comment_preservation(self):
        """Verify standalone comments, empty lines, and banner preservation."""
        source = """;==============================================================================
; Main Subroutine Header
;==============================================================================

START:
\tNOP\t\t; Inline comment

; Section Footer
"""
        reformatter = Reformatter()
        out, _ = reformatter.reformat(source)
        self.assertIn("; Main Subroutine Header", out)
        self.assertIn("; Section Footer", out)
        self.assertIn("; Inline comment", out)
        # Check blank line preserved
        self.assertIn("\n\nSTART:", out)

    # -------------------------------------------------------------------------
    # 3. Dialect Translation Tests
    # -------------------------------------------------------------------------

    def test_z88dk_to_tasm_translation(self):
        """Verify translation of directives and hex numbers from z88dk to TASM."""
        source = """
\tORG\t$0100
START:
\tLD\tA,042H
\tLD\tHL,1234H
\tDB\t1,2,3
\tDW\t1000H
\tDS\t16
\tRET
"""
        reformatter = Reformatter(source_dialect="z88dk", target_dialect="tasm")
        out, _ = reformatter.reformat(source)
        self.assertIn(".ORG", out)
        self.assertIn(".BYTE", out)
        self.assertIn(".WORD", out)
        self.assertIn(".BLOCK", out)
        self.assertIn(".END", out)

    def test_z88dk_to_slr_translation(self):
        """Verify translation of directives and hex numbers to SLR Z80ASM."""
        source = """
\tORG\t$0100
START:
\tLD\tA,$42
\tLD\tHL,$1234
\tDB\t'A'
\tDS\t8
\tRET
"""
        reformatter = Reformatter(source_dialect="z88dk", target_dialect="slr")
        out, _ = reformatter.reformat(source)
        self.assertIn("ORG", out)
        self.assertIn("42H", out)
        self.assertIn("1234H", out)
        self.assertIn("DEFB", out)
        self.assertIn("DEFS", out)
        self.assertIn("END", out)

    def test_z88dk_to_m80_translation(self):
        """Verify translation to Microsoft M80 (.Z80 mode and 0...H hex)."""
        source = """
\tORG\t$0100
START:
\tLD\tA,$FF
\tRET
"""
        reformatter = Reformatter(source_dialect="z88dk", target_dialect="m80")
        out, _ = reformatter.reformat(source)
        self.assertIn(".Z80", out)
        self.assertIn("0FFH", out)
        self.assertIn("END", out)

    def test_z88dk_to_sjasmplus_translation(self):
        """Verify translation from z88dk to sjasmplus (directives, local labels, C-style ops)."""
        source = """
\tORG\t$0100
LOOP:
\tLD\tA,(HL)
\tCP\t$00
\tJR\tZ,@EXIT
\tINC\tHL
\tJR\tLOOP
@EXIT:
\tRET
"""
        reformatter = Reformatter(source_dialect="z88dk", target_dialect="sjasmplus")
        out, _ = reformatter.reformat(source)
        self.assertIn("ORG", out)
        # In sjasmplus, local labels start with dot .EXIT:
        self.assertIn(".EXIT:", out)
        # References to local labels should also be translated: @EXIT -> .EXIT
        self.assertIn("JR      Z,.EXIT", out)
        self.assertIn("RET", out)

    def test_sjasmplus_to_z88dk_translation(self):
        """Verify translation from sjasmplus to z88dk (.local -> @local)."""
        source = """
\tORG\t$0100
MAIN:
\tLD\tB,10
.LOOP:
\tDJNZ\t.LOOP
\tRET
"""
        reformatter = Reformatter(source_dialect="sjasmplus", target_dialect="z88dk")
        out, _ = reformatter.reformat(source)
        self.assertIn("MAIN:", out)
        self.assertIn("@LOOP:", out)
        self.assertIn("DJNZ    @LOOP", out)
        self.assertIn("RET", out)



    # -------------------------------------------------------------------------
    # 4. Machine Code Equivalence Across Assemblers (Requirements 8 & 9)
    # -------------------------------------------------------------------------

    def test_z88dk_and_uz80as_machine_code_equivalence(self):
        """
        Assemble original source with z88dk-z80asm.
        Reformat to TASM syntax and assemble with uz80as.
        Verify that both produce 100% identical machine code binaries.
        """
        source = """
\tORG\t$0100
START:
\tNOP
\tLD\tA,042H
\tLD\tB,A
\tLD\tC,05H
\tLD\tHL,1234H
\tLD\tDE,5678H
\tADD\tHL,DE
\tADC\tA,B
\tSUB\tC
\tXOR\tA
\tOR\t0FH
\tCP\t80H
\tINC\tA
\tDEC\tB
\tRLCA
\tRRCA
\tRLA
\tRRA
\tCPL
\tSCF
\tCCF
\tEX\tDE,HL
\tEX\tAF,AF'
\tEXX
\tPUSH\tBC
\tPOP\tDE
\tLD\tA,(HL)
\tLD\t(HL),A
\tLD\tA,(IX+4)
\tLD\t(IY-2),10H
\tBIT\t3,A
\tSET\t7,B
\tRES\t0,C
\tJR\tNZ,SKIP_JP
SKIP_JP:
\tJP\tC,DONE
DONE:
\tRET
"""
        with tempfile.TemporaryDirectory() as tmpdir:
            z88_src = os.path.join(tmpdir, "orig_z88.asm")
            z88_bin = os.path.join(tmpdir, "orig_z88.bin")
            with open(z88_src, "w") as f:
                f.write(source)

            # 1. Assemble with z88dk-z80asm
            cmd_z88 = [self.z88dk_bin, "-b", f"-o={z88_bin}", z88_src]
            res_z88 = subprocess.run(cmd_z88, capture_output=True, text=True)
            self.assertEqual(res_z88.returncode, 0, f"z88dk failed: {res_z88.stderr}")

            # 2. Reformat to TASM syntax
            reformatter = Reformatter(source_dialect="z88dk", target_dialect="tasm")
            tasm_source, warnings = reformatter.reformat(source)

            tasm_src = os.path.join(tmpdir, "tasm_converted.asm")
            tasm_bin = os.path.join(tmpdir, "tasm_converted.bin")
            tasm_lst = os.path.join(tmpdir, "tasm_converted.lst")
            with open(tasm_src, "w") as f:
                f.write(tasm_source)

            # 3. Assemble with uz80as
            cmd_uz = [self.uz80as_bin, "-t", "z88", tasm_src, tasm_bin, tasm_lst]
            # uz80as uses target z80
            cmd_uz = [self.uz80as_bin, "-t", "z80", tasm_src, tasm_bin, tasm_lst]
            res_uz = subprocess.run(cmd_uz, capture_output=True, text=True)
            self.assertEqual(res_uz.returncode, 0, f"uz80as failed: {res_uz.stderr}")

            # 4. Compare machine code byte-for-byte!
            with open(z88_bin, "rb") as f1, open(tasm_bin, "rb") as f2:
                bytes_z88 = f1.read()
                bytes_tasm = f2.read()

            self.assertEqual(len(bytes_z88), len(bytes_tasm))
            self.assertEqual(bytes_z88, bytes_tasm, "Machine code mismatch between z88dk and uz80as!")

    def test_z88dk_and_slr_machine_code_equivalence(self):
        """
        Assemble original source with z88dk-z80asm.
        Reformat to SLR Z80ASM syntax and assemble with SLR Z80ASM.COM under zxcc.
        Verify byte-for-byte machine code equivalence.
        """
        source = """
\tORG\t$0100
START:
\tNOP
\tLD\tA,042H
\tLD\tB,A
\tLD\tHL,1234H
\tADD\tHL,BC
\tXOR\tA
\tRET
"""
        with tempfile.TemporaryDirectory() as tmpdir:
            z88_src = os.path.join(tmpdir, "orig.asm")
            z88_bin = os.path.join(tmpdir, "orig.bin")
            with open(z88_src, "w") as f:
                f.write(source)

            # 1. Assemble with z88dk
            cmd_z88 = [self.z88dk_bin, "-b", f"-o={z88_bin}", z88_src]
            res_z88 = subprocess.run(cmd_z88, capture_output=True, text=True)
            self.assertEqual(res_z88.returncode, 0, f"z88dk assembly failed: {res_z88.stderr}")

            with open(z88_bin, "rb") as f:
                expected_bytes = f.read()

            # 2. Reformat to SLR syntax
            reformatter = Reformatter(source_dialect="z88dk", target_dialect="slr")
            slr_source, _ = reformatter.reformat(source)

            slr_src = os.path.join(tmpdir, "TESTSLR.Z80")
            with open(slr_src, "w") as f:
                f.write(slr_source)

            # 3. Assemble with SLR Z80ASM.COM under zxcc
            env = os.environ.copy()
            env["CPMDIR80"] = self.cpm_dir
            z80asm_com = os.path.join(self.cpm_dir, "bin80", "Z80ASM.COM")
            cmd_slr = [self.zxcc_bin, z80asm_com, "-TESTSLR/F"]
            res_slr = subprocess.run(cmd_slr, cwd=tmpdir, env=env, capture_output=True, text=True)
            self.assertEqual(res_slr.returncode, 0, f"SLR Z80ASM failed: {res_slr.stderr}\n{res_slr.stdout}")

            # SLR Z80ASM outputs TESTSLR.COM (padded to CP/M 128-byte record)
            slr_com = os.path.join(tmpdir, "testslr.com")
            if not os.path.exists(slr_com):
                slr_com = os.path.join(tmpdir, "TESTSLR.COM")

            with open(slr_com, "rb") as f:
                slr_bytes = f.read()

            # Verify machine code payload matches exactly
            self.assertEqual(slr_bytes[:len(expected_bytes)], expected_bytes)

    # -------------------------------------------------------------------------
    # 5. Unsupported / Ambiguous Construct Diagnostics (Requirement 11)
    # -------------------------------------------------------------------------

    def test_unsupported_half_registers_in_m80_warning(self):
        """Verify warning emitted when using IXH/IXL with target dialect M80."""
        source = """
START:
\tLD\tIXH,A
\tRET
"""
        reformatter = Reformatter(source_dialect="z88dk", target_dialect="m80")
        out, warnings = reformatter.reformat(source)
        self.assertTrue(any("IXH" in w for w in warnings))

    # -------------------------------------------------------------------------
    # 6. Expression Operator Translation & CLI Tests
    # -------------------------------------------------------------------------

    def test_expression_operator_translation(self):
        """Verify operators translate between C-style (&, |, ^) and keyword-style (AND, OR, XOR)."""
        source = "\tLD\tA,(10H & 0FH) | (20H ^ 04H)\n"
        # TASM uses C-style &, |, ^
        ref_tasm = Reformatter(source_dialect="z88dk", target_dialect="tasm")
        out_tasm, _ = ref_tasm.reformat(source)
        self.assertIn("&", out_tasm)
        self.assertIn("|", out_tasm)
        self.assertIn("^", out_tasm)

        # M80 uses keyword-style AND, OR, XOR
        ref_m80 = Reformatter(source_dialect="z88dk", target_dialect="m80")
        out_m80, _ = ref_m80.reformat(source)
        self.assertIn("AND", out_m80)
        self.assertIn("OR", out_m80)
        self.assertIn("XOR", out_m80)

    def test_cli_invocation(self):
        """Verify CLI file processing with arguments."""
        from tools.z80_beautifier.cli import main
        with tempfile.TemporaryDirectory() as tmpdir:
            in_file = os.path.join(tmpdir, "input.asm")
            out_file = os.path.join(tmpdir, "output.asm")
            with open(in_file, "w") as f:
                f.write("start:\n\tld a, 42h\n\tret\n")

            main([
                in_file,
                "-o", out_file,
                "--label-col", "1",
                "--opcode-col", "12",
                "--operand-col", "20",
                "--case-insn", "upper",
                "--case-reg", "upper",
                "--case-label", "upper"
            ])

            self.assertTrue(os.path.exists(out_file))
            with open(out_file, "r") as f:
                content = f.read()
            self.assertIn("START:", content)
            self.assertIn("LD", content)
            self.assertIn("A", content)

    def test_meta_se_cfg_loader(self):
        """Verify parsing of SE.CFG and BEAUTIFY.CFG into FormatterConfig."""
        from tools.z80_beautifier.meta import load_se_cfg
        meta_cfg = os.path.join(repo_root, "tools", "z80_beautifier", "meta", "BEAUTIFY.CFG")
        cfg = load_se_cfg(meta_cfg)
        self.assertEqual(cfg.label_col, 1)
        self.assertEqual(cfg.opcode_col, 9)
        self.assertEqual(cfg.operand_col, 17)
        self.assertEqual(cfg.comment_col, 41)
        self.assertEqual(cfg.instruction_case, 'upper')

    def test_meta_dia_dialects(self):
        """Verify dynamic MetaDialect loading from .DIA files."""
        from tools.z80_beautifier.meta import load_dialect_dia
        meta_dir = os.path.join(repo_root, "tools", "z80_beautifier", "meta")
        for dia_name in ["Z88DK.DIA", "SJASM.DIA", "TASM.DIA", "SLR.DIA", "M80.DIA"]:
            dia_path = os.path.join(meta_dir, dia_name)
            dialect = load_dialect_dia(dia_path)
            self.assertIsNotNone(dialect)
            # Test basic directive mapping
            self.assertTrue(dialect.format_directive("ORG").upper().endswith("ORG"))

    def test_unified_4line_schemas(self):
        """Verify 4-line field beautification and case schemas."""
        from tools.z80_beautifier.config import StmtSchema, LabelSchema, CommentSchema, CaseSchema
        from tools.z80_beautifier.parser import Parser

        # 1. Test parsing schema strings
        stmt = StmtSchema.parse("1t 1s 0s ;32tA")
        self.assertEqual(stmt.mnem.count, 1)
        self.assertEqual(stmt.mnem.unit, 't')
        self.assertEqual(stmt.mnem.mode, 'R')
        self.assertEqual(stmt.op1.count, 1)
        self.assertEqual(stmt.op1.unit, 's')
        self.assertEqual(stmt.op2.count, 0)
        self.assertEqual(stmt.comm.count, 32)
        self.assertEqual(stmt.comm.unit, 't')
        self.assertEqual(stmt.comm.mode, 'A')

        lbl = LabelSchema.parse("1sA : O")
        self.assertEqual(lbl.col.count, 1)
        self.assertEqual(lbl.colon, ':')
        self.assertEqual(lbl.placement, 'O')

        comm = CommentSchema.parse("1sA M")
        self.assertEqual(comm.col1, '1sA')
        self.assertEqual(comm.indented, 'M')

        case = CaseSchema.parse("mU oU lP cU")
        self.assertEqual(case.mnemonic, 'upper')
        self.assertEqual(case.operand, 'upper')
        self.assertEqual(case.label, 'preserve')
        self.assertEqual(case.constant, 'upper')

        # 2. Test formatting with tabbed schema (1t 1s 0s ;32tA)
        cfg_tab = FormatterConfig(
            stmt_schema=stmt,
            label_schema=lbl,
            comment_schema=comm,
            case_schema=case,
        )
        source = (
            "; Header comment\n"
            "start: ld a,10 ; initial counter\n"
            "loop: inc a\n"
            " cp 20 ; check limit\n"
            " jr nz,loop ; repeat\n"
            " ret\n"
        )
        ast = Parser().parse_source(source)
        fmt = Formatter(cfg_tab)
        out = fmt.format_program(ast)

        lines = out.strip().split("\n")
        self.assertEqual(lines[0], "; Header comment")
        # Line 1: 'start:\tLD A,10\t\t\t; initial counter' (tabbed to col 32, pure tabs, no spaces before comment)
        self.assertEqual(lines[1], "start:\tLD A,10\t\t\t; initial counter")
        self.assertEqual(lines[3], "\tCP 20\t\t\t; check limit")
        self.assertEqual(lines[4], "\tJR NZ,loop\t\t; repeat")
        # Line 2: 'loop:\tINC A'
        self.assertTrue(lines[2].startswith("loop:\tINC A"))
        # Line 4: '	JR NZ,loop'
        self.assertTrue(lines[4].startswith("\tJR NZ,loop"))

        # 3. Test lowercase case schema (mL oL lP cL)
        cfg_lower = FormatterConfig(
            case_schema=CaseSchema.parse("mL oL lP cL")
        )
        out_lower = Formatter(cfg_lower).format_program(ast)
        self.assertIn("start:  ld      a,10", out_lower)
        self.assertIn("loop:   inc     a", out_lower)
        self.assertIn("        jr      nz,loop", out_lower)

        # 4. Test label placement overflow (O)
        long_lbl_src = "very_long_label_exceeding_col9: ld a,1"
        ast_long = Parser().parse_source(long_lbl_src)
        out_long = fmt.format_program(ast_long)
        self.assertTrue(out_long.startswith("very_long_label_exceeding_col9:\n"))

if __name__ == '__main__':
    unittest.main()
