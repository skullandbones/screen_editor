# SE.COM Plugin Architecture & Application Binary Interface (ABI) Specification
**Version 1.1 (2026-09-23) — Digital Research CP/M 3 PRL & OVL Standard**

This document specifies the technical architecture, binary packaging standards, execution lifecycles, and Application Binary Interface (ABI) for modular plugins running under **`SE.COM`** (the CP/M full-screen screen editor for RomWBW / RC2014 systems).

---

## 1. Architectural Overview

`SE.COM` implements a modular plugin architecture based on the Digital Research CP/M 3 (CP/M Plus) **Page-Relocatable (`.PRL`)** and **Overlay (`.OVL`)** binary format standards.

```
+-------------------------------------------------------------------------+
| RomWBW Upper Common RAM (> 0x8000)                                      |
| - Fixed resident across all bank switches                               |
| - PLUGIN_HOST_API Vector Table & Inter-Bank Trampolines                 |
| - PLUGIN_REGISTRY (8 slots x 24 bytes)                                  |
| - ACTIVE_LINE_BUF (1,024 bytes) & ACTIVE_LINE_LEN                       |
+-------------------------------------------------------------------------+
                                   |
         +-------------------------+-------------------------+
         |                                                   |
         v                                                   v
+------------------------------------+   +------------------------------------+
| 0x0000 .. 0x7FFF: TPA Slot (4KB)   |   | 0x0000 .. 0x7FFF: Far RAM Bank     |
| - Overlays LINE_STORAGE (5,120 B)  |   | - Borrowed on-demand (32KB Bank)   |
| - Zero extra bytes of TPA RAM      |   | - 8 x 4KB modular plugin slots     |
| - On-the-fly PRL page relocation   |   | - Direct execution via RomWBW      |
| - Relocates to high_byte(TPA_SLOT) |   |   HB_BNKCALL proxy (0xFFF9)        |
+------------------------------------+   +------------------------------------+
```

### Dual Execution Models

1. **Far RAM Execution (`CAP_FAR_EXEC = 0x0002`)**:
   - The plugin resides in an upper 32KB Far RAM bank borrowed on-demand from RomWBW's memory pool (`BORROW_PLUGIN_BANK`).
   - The 32KB bank is divided into **8 modular slots of 4KB each** (`0x0000`, `0x1000`, `0x2000`, ..., `0x7000`).
   - Execution occurs directly inside the Far RAM bank via RomWBW's standard inter-bank procedure call vector (`HB_BNKCALL` at `0xFFF9`).
   - Zero TPA memory is consumed during execution; document cache remains undisturbed.

2. **TPA Cache Overlay Execution (`CAP_TPA_EXEC = 0x0001`)**:
   - The plugin is loaded into a 4KB execution slot that overlays the editor's resident `LINE_STORAGE` cache buffer (5,120 bytes at `BSS_START`).
   - Prior to execution, modified cache lines are committed to Far RAM (`FLUSH_DIRTY_CACHE`).
   - If the plugin is in `.PRL` format, `SE.COM` relocates all absolute address references on-the-fly using the embedded relocation bitmap.
   - After plugin return, `SE.COM` reloads the active line cache window (`RELOAD_CACHE_WINDOW_FORCE`).
   - Reclaims 100% of the plugin footprint when execution finishes; zero permanent TPA overhead.

---

## 2. CP/M 3 Binary File Format & Header Specification

All plugins are standard Digital Research CP/M 3 binary files consisting of:
1. **256-Byte Header** (`0x0000 .. 0x00FF`)
2. **Code & Initialized Data Image** (`PROG_SIZE` bytes, assembled origin `0x0100`)
3. **Relocation Bitmap** (`.PRL` files only, `(PROG_SIZE + 7) // 8` bytes)

### 256-Byte Header Map

| Offset | Size | Type | Name | Description |
| :---: | :---: | :---: | :--- | :--- |
| `00h` | 1 | Byte | `RESERVED` | Zero |
| `01h..02h` | 2 | Word | `PROG_SIZE` | Code + Data size in bytes (little-endian) |
| `03h` | 1 | Byte | `RESERVED` | Zero |
| `04h..05h` | 2 | Word | `BSS_SIZE` | Uninitialized BSS size in bytes (little-endian) |
| `06h` | 1 | Byte | `RESERVED` | Zero |
| `07h..08h` | 2 | Word | `LOAD_ADDR` | `0000h` for Page-Relocatable (`.PRL`); target base address for Overlay (`.OVL`) |
| `09h` | 1 | Byte | `RESERVED` | Zero |
| `0Ah..0Bh` | 2 | Word | `BIOS_LINK` | Zero (`0000h`) |
| `0Ch..1Bh` | 16 | String | `NAME` | ASCII uppercase plugin name, null-padded |
| `1Ch..1Dh` | 2 | Word | `CAPABILITIES`| 16-bit capability bitflags (see below) |
| `1Eh..1Fh` | 2 | Word | `RESERVED` | Zero (`0000h`) |
| `20h..FFh` | 224 | Bytes| `PADDING` | Zero-filled padding to 256 bytes |

### Capabilities Bitflags (`1Ch..1Dh`)

```
Bit:   15 ... 6     5       4       3       2       1       0
     +----------+-------+-------+-------+-------+-------+-------+
     | Reserved | CONF  | ABOUT | MODAL | MUTAT | FAR   |  TPA  |
     +----------+-------+-------+-------+-------+-------+-------+
```

| Flag | Value | Description |
| :--- | :---: | :--- |
| `CAP_TPA_EXEC` | `0x0001` | Plugin can execute in the 4KB TPA overlay slot over `LINE_STORAGE`. |
| `CAP_FAR_EXEC` | `0x0002` | Plugin can execute directly inside Far RAM via RomWBW `HB_BNKCALL`. |
| `CAP_DOC_MUTATE`| `0x0004` | Plugin mutates document lines (signals editor to re-render buffer). |
| `CAP_MODAL_UI` | `0x0008` | Plugin renders its own modal UI dialog or summary box. |
| `CAP_HAS_ABOUT`| `0x0010` | Plugin implements an embedded modal **About Screen** (`ENTRY + 3`). |
| `CAP_HAS_CONFIG`| `0x0020`| Plugin implements an embedded interactive **Configuration Screen** (`ENTRY + 6`). |

### Relocation Bitmap (`.PRL` Only)

Following the code image is a bitstream of length `(PROG_SIZE + 7) // 8` bytes.
- Bit 7 of byte 0 corresponds to the first code byte (`ENTRY + 0`).
- Bit 0 of byte 0 corresponds to the eighth code byte (`ENTRY + 7`).
- A bit set to `1` indicates that the corresponding byte is an **address high-byte** requiring relocation:
  $$\text{CodeByte} \leftarrow \text{CodeByte} + (\text{TargetPage} - 1)$$
  Where $\text{TargetPage} = \text{HighByte}(\text{LoadAddress})$.

---

## 3. Plugin Calling Convention & Entry Jump Table

Plugins export their entry points through a standard 3-entry jump table located at the very beginning of the code image (`base + 0x0100`):

```z80
    ORG 0100H

ENTRY:
    JP  PLUGIN_EXECUTE      ; +0: Main execution (Action 0)
    JP  PLUGIN_ABOUT        ; +3: Display About Screen (Action 1)
    JP  PLUGIN_CONFIG       ; +6: Display Configuration Screen (Action 2)
```

### Jump Table Offsets

| Offset | Action Index | Handler | Description | Required |
| :---: | :---: | :--- | :--- | :---: |
| `+0` | `0` | `PLUGIN_EXECUTE` | Default plugin action (e.g. format file, cipher line, count words). | **Yes** |
| `+3` | `1` | `PLUGIN_ABOUT` | Modal About dialog displaying version, author, and capabilities. | Optional (`CAP_HAS_ABOUT`) |
| `+6` | `2` | `PLUGIN_CONFIG` | Interactive configuration screen for user preferences. | Optional (`CAP_HAS_CONFIG`) |

If a plugin does not implement `PLUGIN_ABOUT` or `PLUGIN_CONFIG`, its jump slot must contain:
```z80
    SCF                     ; Carry = 1 (Not implemented)
    RET
```
and the corresponding capability bit (`CAP_HAS_ABOUT` or `CAP_HAS_CONFIG`) must be left cleared (`0`) in the header.

---

## 4. Register State on Entry & Exit

### Entry Register State

| Register | State on Entry |
| :---: | :--- |
| `IX` | Pointer to `PLUGIN_HOST_API` vector table in Upper Common RAM (`> 0x8000`). |
| `IY` | Pointer to `PLUGIN_HOST_API` vector table (identical to `IX` for convenience). |
| `SP` | Valid host stack pointer in Upper Common RAM. |
| `AF`, `BC`, `DE`, `HL` | Undefined (may be used immediately without preserving). |

### Exit Register State

| Register | Expected Return State |
| :---: | :--- |
| `A` | **Buffer Modification Status Code**: |
| | `0x00`: Clean / Success. Document buffer was not modified (e.g. About, Config, Stats). |
| | `0x01`: Single Line Modified. Active line in `ACTIVE_LINE_BUF` was changed. |
| | `0x02`: Document Modified. Multiple lines or entire file modified; triggers full re-render. |
| | `0xFF`: Error / Aborted by user. |
| `CY` | **Carry Flag (Success/Failure)**: |
| | `CY = 0`: Successful execution. |
| | `CY = 1`: Error occurred (A contains error code). |
| `BC`, `DE`, `HL`, `IX`, `IY` | Scratch (do not need to be preserved by plugin). |
| `SP` | Must be restored to the entry stack position. |

---

## 5. Host API Specification (`PLUGIN_HOST_API`)

`SE.COM` provides a fixed-structure API vector table residing in Upper Common RAM (`> 0x8000`), guaranteed to remain mapped and valid across all Far RAM bank switches.

```
PLUGIN_HOST_API (+0):
+-------------------------------------------------------------------------+
| Magic: "SE" (2B) | Version: 0097h (2B) | Active Line Ptrs & Lens (8B)   |
| Viewport Metrics: Cols, Rows (4B)                                       |
| Inter-Bank Trampolines: CHECKOUT, COMMIT, PUTC, PRINT_STR, GET_KEY...   |
| Block Selection Bounds & Configuration Pointers                         |
+-------------------------------------------------------------------------+
```

### Complete Host API Field & Vector Map

| Offset | Type | Name | Description |
| :---: | :---: | :--- | :--- |
| `+0` | String | `API_MAGIC` | Constant ASCII `"SE"` (`0x53, 0x45`). |
| `+2` | Word | `API_VERSION` | Host editor version (`0x0097` = v0.9.7). |
| `+4` | Word | `PTR_ACTIVE_LINE` | Pointer to 1,024-byte null-terminated active line buffer. |
| `+6` | Word | `PTR_LINE_LEN` | Pointer to 16-bit word containing active line length. |
| `+8` | Word | `PTR_CUR_ROW` | Pointer to 16-bit word containing current document line (0-indexed). |
| `+10` | Word | `PTR_TOTAL_LINES` | Pointer to 16-bit word containing total document line count. |
| `+12` | Word | `PTR_CUR_COL` | Pointer to 16-bit word containing current cursor column. |
| `+14` | Byte | `ACTIVE_COLS` | Screen width (`80` or `120`). |
| `+15` | Byte | `RESERVED` | Zero padding. |
| `+16` | Byte | `ACTIVE_ROWS` | Screen height (`24` or `40`). |
| `+17` | Byte | `RESERVED` | Zero padding. |
| `+18` | Vector | `CALL_CHECKOUT_LINE` | `JP TRAMP_CHECKOUT_LINE`: Checkout document line `HL` into buffer `DE`. |
| `+21` | Vector | `CALL_COMMIT_LINE` | `JP TRAMP_COMMIT_LINE`: Commit line `HL` from buffer `DE` (length `BC`). |
| `+24` | Vector | `CALL_PUTC` | `JP TRAMP_PUTC`: Output character in `A` to console. |
| `+27` | Vector | `CALL_PRINT_STR` | `JP TRAMP_PRINT_STR`: Output '$'-terminated string at `DE` to console. |
| `+30` | Vector | `CALL_GET_KEY` | `JP TRAMP_GET_KEY`: Blocking console input; returns character in `A`. |
| `+33` | Vector | `CALL_SET_STATUS` | `JP TRAMP_SET_STATUS_MSG`: Display status message at `DE` on status bar. |
| `+36` | Word | `PTR_BLOCK_ACTIVE` | Pointer to byte: `0`=inactive, `1`=dynamic selection, `2`=locked. |
| `+38` | Word | `PTR_BLOCK_START` | Pointer to 16-bit word containing start line of selected block. |
| `+40` | Word | `PTR_BLOCK_END` | Pointer to 16-bit word containing end line of selected block. |
| `+42` | Word | `PTR_TAB_WIDTH` | Pointer to byte containing active tab width (`4` or `8`). |
| `+44` | Word | `PTR_BEAUTIFY_CFG` | Pointer to 24-byte beautifier configuration structure. |
| `+46` | Vector | `CALL_CHECK_KEY` | `JP TRAMP_CHECK_KEY`: Non-blocking key check. Returns `Z=1` (none), `NZ=1` (key ready). |

---

## 6. Host Callback Function Details

### 1. `CHECKOUT_LINE` (`IX + 18`)
Fetches an arbitrary line from the Far RAM document buffer into a designated RAM buffer.
- **Input**:
  - `HL` = Line index (`0` .. `DOC_TOTAL_LINES - 1`).
  - `DE` = Destination buffer address (must be in Common RAM `> 0x8000`).
- **Output**:
  - `BC` = Line length in bytes.
  - Line text copied to `DE`, terminated with null (`0x00`).
  - `CY = 0` on success; `CY = 1` if line index is out of bounds.

### 2. `COMMIT_LINE` (`IX + 21`)
Writes modified line text back into the Far RAM document buffer.
- **Input**:
  - `HL` = Line index (`0` .. `DOC_TOTAL_LINES - 1`).
  - `DE` = Source text buffer address (Common RAM `> 0x8000`).
  - `BC` = Line length in bytes.
- **Output**:
  - `CY = 0` on success; `CY = 1` on memory allocation failure.

### 3. `PUTC` (`IX + 24`)
Emits a single character to the console terminal.
- **Input**:
  - `A` = ASCII character code.
- **Preserves**: `BC`, `DE`, `HL`, `IX`, `IY`.

### 4. `PRINT_STR` (`IX + 27`)
Emits a string to the console terminal.
- **Input**:
  - `DE` = Pointer to string terminated with `$` (`0x24`).
- **Preserves**: `IX`, `IY`.

### 5. `GET_KEY` (`IX + 30`)
Reads a single character from the console (blocking).
- **Output**:
  - `A` = Character read.
- **Preserves**: `BC`, `DE`, `HL`, `IX`, `IY`.

### 6. `CHECK_KEY` (`IX + 46`)
Polls console for keyboard readiness without blocking.
- **Output**:
  - `Z = 1` (Zero flag set): No character ready.
  - `NZ = 1` (Zero flag clear): Key is waiting in console buffer.
- **Preserves**: `BC`, `DE`, `HL`, `IX`, `IY`.

### 7. `SET_STATUS_MSG` (`IX + 33`)
Updates the status bar notification area with a custom message.
- **Input**:
  - `DE` = Pointer to null-terminated ASCII string (max 32 chars).
- **Preserves**: `IX`, `IY`.

---

## 7. Plugin Authoring Guide & Template

Below is a complete, minimal template for a Z80 plugin implementing the standard jump table with Execute, About, and Config screens:

```z80
;==============================================================================
; DEMOPLUG.ASM - Minimal SE.COM Plugin Example
;==============================================================================
    ORG 0100H

;------------------------------------------------------------------------------
; Standard 3-Entry Jump Table
;------------------------------------------------------------------------------
ENTRY:
    JP  CMD_EXECUTE         ; +0: Main Run Action
    JP  CMD_ABOUT           ; +3: Modal About Screen
    JP  CMD_CONFIG          ; +6: Interactive Config Screen

;------------------------------------------------------------------------------
; Action 0: Main Execution
;------------------------------------------------------------------------------
CMD_EXECUTE:
    ; Verify Host API Magic "SE"
    LD  A,(IX+0)
    CP  'S'
    JR  NZ,EXEC_ERR
    LD  A,(IX+1)
    CP  'E'
    JR  NZ,EXEC_ERR

    ; Example: Display status message
    LD  DE,STR_MSG_DONE
    CALL CALL_HOST_STATUS

    XOR A                   ; A = 0 (Clean, document unmodified)
    OR  A                   ; CY = 0 (Success)
    RET

EXEC_ERR:
    LD  A,0FFH
    SCF                     ; CY = 1 (Error)
    RET

;------------------------------------------------------------------------------
; Action 1: Modal About Screen
;------------------------------------------------------------------------------
CMD_ABOUT:
    LD  DE,STR_ABOUT_BOX
    CALL CALL_HOST_PRINT
    CALL CALL_HOST_GETKEY   ; Wait for user keypress

    XOR A                   ; A = 0 (Clean)
    OR  A                   ; CY = 0 (Success)
    RET

;------------------------------------------------------------------------------
; Action 2: Interactive Configuration Screen
;------------------------------------------------------------------------------
CMD_CONFIG:
    LD  DE,STR_CONFIG_BOX
    CALL CALL_HOST_PRINT
    CALL CALL_HOST_GETKEY   ; Process configuration input

    XOR A                   ; A = 0 (Clean)
    OR  A                   ; CY = 0 (Success)
    RET

;------------------------------------------------------------------------------
; Helper Wrappers for Host API (via IX)
;------------------------------------------------------------------------------
CALL_HOST_PRINT:
    PUSH IX
    POP  HL
    LD   BC,27              ; Offset +27: PRINT_STR
    ADD  HL,BC
    JP   (HL)

CALL_HOST_GETKEY:
    PUSH IX
    POP  HL
    LD   BC,30              ; Offset +30: GET_KEY
    ADD  HL,BC
    JP   (HL)

CALL_HOST_STATUS:
    PUSH IX
    POP  HL
    LD   BC,33              ; Offset +33: SET_STATUS_MSG
    ADD  HL,BC
    JP   (HL)

;------------------------------------------------------------------------------
; Strings & UI Data
;------------------------------------------------------------------------------
STR_MSG_DONE:   DB  "[Demo Plugin Executed]", 0

STR_ABOUT_BOX:
    DB  13,10,"  +------------------------------------+"
    DB  13,10,"  |        Demo Plugin for SE.COM      |"
    DB  13,10,"  +------------------------------------+"
    DB  13,10,"  | Version: v0.1.0 (2026-09-23)       |"
    DB  13,10,"  | Compatible with SE.COM >= v0.9.7   |"
    DB  13,10,"  +------------------------------------+"
    DB  13,10,"  |    [Press any key to return]       |"
    DB  13,10,"  +------------------------------------+",13,10,"$"

STR_CONFIG_BOX:
    DB  13,10,"  +------------------------------------+"
    DB  13,10,"  |       Demo Plugin Configuration    |"
    DB  13,10,"  +------------------------------------+"
    DB  13,10,"  | 1. Option A : [ON]                 |"
    DB  13,10,"  | 2. Option B : [OFF]                |"
    DB  13,10,"  +------------------------------------+"
    DB  13,10,"  |    [Press any key to return]       |"
    DB  13,10,"  +------------------------------------+",13,10,"$"

    END
```

---

## 8. Building & Packaging Plugins

Plugins are compiled and packaged using the project's build utilities:

```bash
# 1. Dual assembly for relocation bitmap generation:
../../tools/romwbw_src/Tools/Linux/uz80as -q plugin.asm plugin_100.bin
# (Assemble identical source at ORG 0200H)
../../tools/romwbw_src/Tools/Linux/uz80as -q plugin_200.asm plugin_200.bin

# 2. Package into Digital Research CP/M 3 .PRL with capabilities:
python3 tools/mkprl.py \
    --name MYPLUGIN \
    --code-100 plugin_100.bin \
    --code-200 plugin_200.bin \
    --output MYPLUGIN.PRL \
    --has-about \
    --has-config \
    --caps 0x0037
```
