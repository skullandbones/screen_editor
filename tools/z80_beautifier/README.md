# Z80 Assembly Source Beautifier & Multi-Dialect Reformatter

A modular, AST-based source code beautifier and assembler-dialect reformatter for Z80 assembly code.

## Key Features

- **Common IR AST**: Operates on an Intermediate Representation rather than superficial textual regex substitution, preserving exact program semantics, label hierarchies, and comments.
- **Independent Column Formatting**: Independently configure label, opcode, operand, and inline comment column alignments.
- **Multi-Dialect Translation**: Translate source code losslessly between:
  - `z88dk` (`z88dk-z80asm`)
  - `sjasmplus` (modern Linux cross-assembler)
  - `tasm` (`TASM 3.2` / `uz80as`)
  - `slr` (`SLR Systems Z80ASM` / `ZMAC`)
  - `m80` (`Microsoft Macro-80`)
- **Semantic & Machine Code Equivalence**: Verified via automated multi-assembler test harnesses (`z88dk-z80asm`, `uz80as`, `Z80ASM.COM`, `M80.COM`).

---

## Command-Line Usage

```bash
# Basic beautification (z88dk style with default 1, 9, 17, 41 columns)
python3 -m tools.z80_beautifier.cli input.asm -o formatted.asm

# Convert z88dk source to sjasmplus syntax
python3 -m tools.z80_beautifier.cli input.asm -d z88dk -t sjasmplus -o output_sjasm.asm

# Convert z88dk source to TASM / uz80as syntax
python3 -m tools.z80_beautifier.cli input.asm -d z88dk -t tasm -o output_tasm.asm

# Convert to SLR Z80ASM syntax with tab-aligned columns
python3 -m tools.z80_beautifier.cli input.asm -d z88dk -t slr --tabs --tab-width 8 -o output_slr.z80

# Convert to Microsoft M80 syntax (.Z80 header, 0...H hex numbers)
python3 -m tools.z80_beautifier.cli input.asm -d z88dk -t m80 -o output_m80.mac

# In-place beautification with custom columns
python3 -m tools.z80_beautifier.cli myfile.asm -i --opcode-col 16 --operand-col 24 --comment-col 48
```

---

## Python API Usage

```python
from tools.z80_beautifier import FormatterConfig, Reformatter

config = FormatterConfig(
    label_col=1,
    opcode_col=9,
    operand_col=17,
    comment_col=41,
    use_tabs=False,
    instruction_case='upper',
    directive_case='upper',
    register_case='upper',
    label_case='preserve'
)

# Convert z88dk assembly to TASM / uz80as syntax
reformatter = Reformatter(
    source_dialect='z88dk',
    target_dialect='tasm',
    config=config
)

tasm_source, warnings = reformatter.reformat(z88dk_source)
```

---

## Dialect Documentation

See [`DIALECTS.md`](DIALECTS.md) for full syntactic comparisons, directive mappings, operator precedence notes, and unsupported construct catalogs.
