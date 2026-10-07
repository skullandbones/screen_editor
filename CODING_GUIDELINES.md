# Coding Guidelines & Formatting Standards

This document establishes the official coding, formatting, and stylistic
standards for the **SE** (Screen Editor) project across both **ANSI C** and
**Z80 Assembly** language components.

---

## 1. General Principles & Environment

* **File Format**: Strict Unix/Linux `LF` (`\n`) line endings only. Never use
  MS-DOS `CRLF` (`\r\n`) in repository source files.
* **Line Length**:
  * Source code (C and Assembly): Maximum **80 columns** recommended.
  * Git commit titles: Maximum **72 characters**.
  * Git commit body lines: Maximum **80 characters** with brief summary of
    the *how* and *why*.
* **Character Encoding**: UTF-8 without BOM for documentation, plain 7-bit
  ASCII for all C source and Assembly files.

---

## 2. ANSI C Formatting Guidelines

The project uses standard modern **ANSI C (C89 / C99)** targeting `z88dk`
and standard host compilers. Avoid K&R C conventions at all times.

### 2.1 Indentation & Whitespace
* **Indentation**: 4 spaces per indentation level. Do not use hard tabs in
  C source files.
* **Brace Style (1TBS / K&R style)**:
  * Opening brace `{` on the same line for control statements (`if`, `for`,
    `while`, `switch`).
  * Opening brace `{` on a new line for function definitions.
  * Always use braces for control blocks, even for single-statement bodies.

```c
/* Function definition: opening brace on new line */
int buffer_get_line(uint16_t row, char *out_text, uint16_t *out_len)
{
    if (row >= g_buf.total_lines) {
        *out_len = 0;
        out_text[0] = '\0';
        return 0;
    }

    /* Block statement */
    if (out_text != NULL) {
        /* ... */
    }

    return 1;
}
```

### 2.2 Naming Conventions
* **Types & Structs**: `PascalCase` or `snake_case_t` (e.g. `EditorBuffer`,
  `LineRef`, `FarPtr`).
* **Functions**: `snake_case` with a clear module prefix (e.g.
  `buffer_insert_line`, `term_move_cursor`, `hbios_copy`).
* **Variables**: `snake_case` (e.g. `cursor_row`, `total_lines`, `line_len`).
* **Globals / Module State**: Prefix with `g_` for globals or `s_` for static
  file-scope variables (e.g. `g_app`, `g_buf`, `s_cpm_user_bank`).
* **Constants & Macros**: `UPPER_SNAKE_CASE` (e.g. `MAX_LINES`, `SCREEN_ROWS`).

### 2.3 Types & Portability
* Always use fixed-width integer types from `<stdint.h>` (`uint8_t`,
  `int8_t`, `uint16_t`, `int16_t`, `uint32_t`, `int32_t`).
* Use `<stdbool.h>` (`bool`, `true`, `false`) for boolean states.
* Explicitly qualify prototypes with `void` when taking no arguments:
  ```c
  void term_init(void);  /* Good */
  void term_init();      /* Avoid */
  ```

---

## 3. Z80 Assembly Formatting Guidelines

The assembly style is tailored for RomWBW HBIOS interfacing, `uz80as`,
and `z88dk-z80asm`.

### 3.1 Mnemonics & Registers
* **Case**: All Z80 instruction mnemonics and register names **MUST be in
  UPPERCASE** (e.g. `LD`, `PUSH`, `POP`, `CALL`, `RET`, `RST`, `JR`, `JP`,
  `INC`, `DEC`, `ADD`, `OR`, `BC`, `DE`, `HL`, `IX`, `SP`).
* **Directives**: Standard assembler directives in UPPERCASE (e.g.
  `.ORG`, `.EQU`, `.DB`, `.DW`, `.DS`, `.END`, `SECTION`, `PUBLIC`).

### 3.2 Operand Spacing & Formatting
* **Indentation**: Indent instruction mnemonics by 8 columns (or 1 tab).
* **Opcode to Operand Spacing**: Use a **single space** between the opcode /
  instruction mnemonic and its operand(s), **not a tab** (e.g. `CALL PRINT`,
  `LD A,0`, `JP MAIN_LOOP`).
* **Comma Spacing**: **NO space** after commas between operands (e.g. `LD A,0`,
  `LD B,0F3H`, `LD D,(IX+4)`, `ADD HL,BC`).

```z80
; Good Z80 formatting (single space between opcode and operand):
	LD A,0			; Clear accumulator
	LD B,0F3H		; HBIOS function code
	LD D,(IX+4)		; Fetch destination bank parameter
	CALL PRINT		; Call print routine (space, not tab)
	RST 08H			; Execute HBIOS system call

; Avoid:
	LD	A,0		; (Avoid tab between opcode and operand)
	CALL	PRINT		; (Avoid tab between opcode and operand)
	ld	a, 0		; (Avoid lowercase and spaced commas)
```

### 3.3 Hexadecimal Literals
* Hex constants should be suffixed with `H` or prefixed with `$`, using
  uppercase hex letters `A-F`.
* If a hex number starts with a letter, prefix with a leading zero `0` to
  distinguish from symbols (e.g. `0F3H`, `0FFH`, `0A0H`).

### 3.4 Labels & Comments
* **Labels**: Uppercase or snake_case followed by a colon `:` on the left
  margin (column 1).
* **Local Labels**: Prefix with dot `.` (e.g. `.not_found:`, `.done:`).
* **Comments**: Start with a semicolon `;` and align neatly.

```z80
;------------------------------------------------------------------------------
; HBIOS Bank Copy Primitive
;------------------------------------------------------------------------------
HBIOS_COPY:
	PUSH BC
	PUSH DE
	LD B,0F4H		; SYSSETCPY
	RST 08H
	OR A
	JR NZ,.copy_error
	LD HL,1
	JR .copy_done

.copy_error:
	LD HL,0

.copy_done:
	POP DE
	POP BC
	RET
```

---

## 4. Summary Quick Reference

| Feature | ANSI C Rule | Z80 Assembly Rule |
| :--- | :--- | :--- |
| **Line Ending** | Unix `LF` (`\n`) | Unix `LF` (`\n`) |
| **Max Width** | 80 columns | 80 columns |
| **Keyword Case**| lowercase (`int`, `void`, `for`) | UPPERCASE (`LD`, `CALL`, `RET`) |
| **Opcode Separator** | N/A | Space, not tab (`CALL PRINT`) |
| **Operand Comma** | `func(a, b)` | `LD A,0` (no comma space) |
| **Indentation** | 4 spaces | 8 spaces / 1 tab for mnemonics |
| **Hex Format** | `0xF3`, `0x0080` | `0F3H` or `$F3` |
| **Types** | `uint8_t`, `uint16_t`, `bool` | Byte (`.DB`), Word (`.DW`) |
