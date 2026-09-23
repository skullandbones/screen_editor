# Z80 Assembler Dialects: Comparative Specification & Compatibility Guide

This document catalogs the syntactic differences, directive mappings, literal formats, and architectural nuances across the primary Z80 assembler dialects relevant to **SE.COM** and the **RomWBW** ecosystem.

---

## 1. Dialect Overview & Ecosystem Usage

| Dialect | Primary Tools | Typical Extensions | Real-World Usage in RomWBW / SE.COM |
| :--- | :--- | :--- | :--- |
| **`z88dk`** | `z88dk-z80asm` | `.asm` | `SE.COM` (Screen Editor) core source code |
| **`sjasmplus`**| `sjasmplus` | `.asm`, `.s` | Modern Linux cross-assembler (ZX Spectrum, MSX, CP/M) |
| **`tasm`** | `TASM 3.2`, `uz80as` | `.asm` | RomWBW CBIOS, HBIOS, System ROM loaders, diagnostics |
| **`slr`** | `SLR Systems Z80ASM`, `ZMAC` | `.z80` | RomWBW ZSDOS 2.2, ZDE editor, ZCPR33 |
| **`m80`** | `Microsoft Macro-80` (`M80.COM`) | `.mac` | RomWBW QP/M clock utilities, ZCPR-DJ, Survey |

---

## 2. Syntax Comparison Matrix

### 2.1 Directive Mappings

| Purpose | `z88dk` | `sjasmplus` | `tasm` (`uz80as`) | `slr` (`Z80ASM`) | `m80` (`Macro-80`) |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Origin** | `ORG $0100` | `ORG $0100` | `.ORG $0100` | `ORG 0100H` | `ORG 0100H` |
| **Equate Constant** | `LABEL EQU expr` | `LABEL EQU expr` | `LABEL .EQU expr` | `LABEL EQU expr` | `LABEL EQU expr` |
| **Redefinable Variable** | `VAR DEFL expr` | `VAR EQU expr` / `=` | `VAR .SET expr` | `VAR DEFL expr` / `SET` | `VAR DEFL expr` / `SET` |
| **Data Byte(s)** | `DB`, `DEFB` | `DB`, `BYTE`, `DEFB` | `.BYTE`, `.DB`, `.TEXT` | `DEFB`, `DB`, `DEFM` | `DB`, `DEFB` |
| **Data Word(s)** | `DW`, `DEFW` | `DW`, `WORD`, `DEFW` | `.WORD`, `.DW` | `DEFW`, `DW` | `DW`, `DEFW` |
| **Reserve Memory** | `DS count`, `DEFS` | `DS count`, `BLOCK` | `.BLOCK count`, `.FILL` | `DEFS count`, `DS` | `DS count`, `DEFS count, fill` |
| **CPU Mode** | Implicit Z80 | Implicit Z80 | Implicit Z80 | Implicit Z80 | `.Z80` (enables Z80 mode) |
| **Phase Execution** | `PHASE addr` | `DISP addr` / `PHASE` | *(manual offset)* | `PHASE addr` | `.PHASE addr` (leading dot) |
| **End of File** | Optional (`END`) | Optional (`END`) | `.END` | `END` | `END` |

---

### 2.2 Number Literal Notations

| Base | `z88dk` | `sjasmplus` | `tasm` | `slr` | `m80` | Universal Portable Syntax |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **Hexadecimal** | `$1234`, `0x1234`, `1234H` | `$1234`, `0x1234`, `1234H` | `$1234`, `1234H` | `1234H` (`0...H`) | `1234H` (`0...H`) | `01234H` (leading digit `0` mandatory if starting with `A-F`) |
| **Binary** | `%1010`, `1010B`, `0b1010` | `%1010`, `0b1010`, `1010B` | `%1010`, `1010B` | `1010B` | `1010B` | `1010B` |
| **Octal** | `\077`, `@077` | `0o077`, `@077`, `077O` | `@077`, `077O`, `077Q` | `077O`, `077Q` | `077Q`, `077O` | `077Q` |
| **Decimal** | `1234` | `1234` | `1234` | `1234` | `1234` | `1234` |

---

### 2.3 Expression Operators & Precedence

| Operation | `z88dk` | `sjasmplus` | `tasm` | `slr` | `m80` |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Bitwise AND** | `&` | `&` | `&` | `AND` | `AND` |
| **Bitwise OR** | `|` | `|` | `|` | `OR` | `OR` |
| **Bitwise XOR** | `^` | `^` | `^` | `XOR` | `XOR` |
| **Bitwise NOT** | `~` | `~` | `~` | `NOT` | `NOT` |
| **Shift Left** | `<<` | `<<` | `<<` | `SHL` | `SHL` |
| **Shift Right** | `>>` | `>>` | `>>` | `SHR` | `SHR` |
| **Modulo** | `%` | `%` | `%` | `MOD` | `MOD` |
| **Evaluation Precedence** | Standard C precedence | Standard C precedence | **NONE! (Strict Left-to-Right)** | Standard Assembler | Standard Assembler (8 levels) |

> [!WARNING]
> **The TASM Left-to-Right Evaluation Trap**:
> In `TASM 3.2` and `uz80as`, expressions have **no operator precedence**. For example, `1 + 2 * 3` evaluates as `(1 + 2) * 3 = 9`, rather than `1 + (2 * 3) = 7`.
> When reformatting expressions targeting `tasm`, always wrap multiplicative and bitwise subexpressions in explicit parentheses `(...)` to guarantee semantic equivalence.

---

### 2.4 Label and Comment Conventions

| Feature | `z88dk` | `sjasmplus` | `tasm` | `slr` | `m80` |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Label Colon** | Mandatory (`LABEL:`) | Optional in Col 1; colon standard | Optional in Col 1; colon permitted | Optional in Col 1; colon permitted | Optional in Col 1; `::` exports public |
| **Local Labels** | `@local` | `.local` | `_local` (scoped to `.MODULE`) | Macro-only (`LOCAL`) | Macro-only (`LOCAL`) |
| **Comments** | `;` and `//` | `;` and `//` | `;` and `*` in Col 1 | `;` strictly | `;` strictly |

---

## 3. Ambiguous and Unsupported Constructs (Requirement 11)

When translating between dialects, certain language constructs cannot be directly converted without semantic or assembler limitations:

1. **Undocumented Z80 Instructions & Half-Registers**:
   - `IXH`, `IXL`, `IYH`, `IYL`: Supported in `z88dk`, `uz80as`, and `SLR180`. **Rejected as syntax errors by Microsoft M80**.
   - Instructions like `SLL r` (shift left logical with bit 0 set): Supported in `z88dk` and `uz80as`; not recognized by standard M80.
2. **Double Quotes in Single-Quote Assemblers**:
   - In DRI MAC/RMAC, double quotes `"` are not recognized as string delimiters.
   - The reformatter converts double-quoted strings `"TEXT"` to single-quoted strings `'TEXT'` when targeting `slr` or `m80`, escaping internal single quotes as `''`.
3. **Location Counter `$` as a Character in Identifiers**:
   - In DRI MAC/RMAC, `$` is a valid internal identifier separator (e.g. `SCB$BASE`).
   - In `z88dk`, `tasm`, `slr`, and `m80`, `$` represents the current program counter. Embedding `$` inside identifiers can lead to parsing ambiguities.
4. **Relocatable Segment Directives (`CSEG`, `DSEG`, `COMMON`)**:
   - Fully supported in `slr` and `m80` when outputting `.REL` files.
   - Ignored or rejected in flat binary absolute assemblers like `TASM` without a linker.
