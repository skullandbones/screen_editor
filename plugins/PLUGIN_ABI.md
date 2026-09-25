# SE.COM Plugin Architecture & Application Binary Interface (ABI) Specification
**Version 1.3 (2026-09-25)**
*Modular Far RAM Slots (4K, 8K, 16K, 32K), CP/M 3 Standard & Headless VFS ABI*

This document specifies the technical architecture, binary packaging standards,
execution lifecycles, and Application Binary Interface (ABI) for modular plugins
running under **`SE.COM`** (the CP/M full-screen editor for RomWBW / RC2014).

---

## 1. Architectural Overview

`SE.COM` implements a modular plugin architecture based on the Digital Research
CP/M 3 (CP/M Plus) **Page-Relocatable (`.PRL`)** and **Overlay (`.OVL`)** binary
format standards.

```
+-------------------------------------------------------------------------+
| RomWBW Upper Common RAM (> 0x8000)                                      |
| - Fixed resident across all bank switches                               |
| - PLUGIN_HOST_API Vector Table & Inter-Bank Trampolines                 |
| - PLUGIN_REGISTRY (8 slots x 32 bytes = 256 bytes)                      |
| - ACTIVE_LINE_BUF (1,024 bytes) & ACTIVE_LINE_LEN                       |
+-------------------------------------------------------------------------+
                                   |
         +-------------------------+-------------------------+
         |                                                   |
         v                                                   v
+------------------------------------+   +------------------------------------+
| 0x0000 .. 0x7FFF: TPA Slot (4KB)   |   | 0x0000 .. 0x7FFF: Far RAM Banks    |
| - Overlays LINE_STORAGE (5,120 B)  |   | - Borrowed on-demand (32KB Banks)  |
| - Strictly restricted to 4KB size  |   | - 4K: Sub-allocated 8 x 4KB slots  |
| - Zero extra bytes of TPA RAM      |   | - 8K/16K/32K: Dedicated 32KB bank  |
| - On-the-fly PRL page relocation   |   | - Direct execution via RomWBW      |
| - Relocates to high_byte(TPA_SLOT) |   |   HB_BNKCALL proxy (0xFFF9)        |
+------------------------------------+   +------------------------------------+
```

### Execution Models & Size Classes

Plugins declare their size class in header metadata (`CAPABILITIES` bits 7..6):
- **4KB Plugins (`CAP_SIZE_4K = 0x0000`, `00b`)**: Payload <= 4096 bytes.
  Can execute either in the 4KB TPA overlay slot (`CAP_TPA_EXEC`) or in Far RAM
  (`CAP_FAR_EXEC`). Multiple 4KB plugins share a single 32KB Far RAM bank,
  sub-allocated into 4KB slots (`0x0000, 0x1000, 0x2000, ...`).
- **8KB Plugins (`CAP_SIZE_8K = 0x0040`, `01b`)**: Payload <= 8192 bytes.
  Strictly restricted from TPA overlay execution. Dynamically allocated a
  dedicated 32KB Far RAM bank borrowed on-demand from `EXT_BANK_TABLE`. Always
  executes at base page `0x00` (entry point `0x0100`).
- **16KB Plugins (`CAP_SIZE_16K = 0x0080`, `10b`)**: Payload <= 16384 bytes.
  Strictly restricted from TPA overlay execution. Dynamically allocated a
  dedicated 32KB Far RAM bank borrowed on-demand from `EXT_BANK_TABLE`. Always
  executes at base page `0x00` (entry point `0x0100`).
- **32KB Plugins (`CAP_SIZE_32K = 0x00C0`, `11b`)**: Payload <= 32768 bytes.
  Heavyweight plugins (such as FAT filesystem drivers) requiring full 32KB
  Far RAM banks. Strictly restricted from TPA overlay execution. Dynamically
  allocated a dedicated 32KB Far RAM bank borrowed on-demand. Always executes
  at base page `0x00` (entry point `0x0100`).

---

## 2. CP/M 3 Binary File Format & Header Specification

All plugins are standard Digital Research CP/M 3 binary files consisting of:
1. **256-Byte Header** (`0x0000 .. 0x00FF`)
2. **Code & Initialized Data Image** (`PROG_SIZE` bytes, origin `0x0100`)
3. **Relocation Bitmap** (`.PRL` files only, `(PROG_SIZE + 7) // 8` bytes)

### 256-Byte Header Map

| Offset | Size | Type | Name | Description |
| :---: | :---: | :---: | :--- | :--- |
| `00h` | 1 | Byte | `RESERVED` | Zero |
| `01h..02h` | 2 | Word | `PROG_SIZE` | Code + Data size in bytes |
| `03h` | 1 | Byte | `RESERVED` | Zero |
| `04h..05h` | 2 | Word | `BSS_SIZE` | Uninitialized BSS size in bytes |
| `06h` | 1 | Byte | `RESERVED` | Zero |
| `07h..08h` | 2 | Word | `LOAD_ADDR` | `0000h` for PRL; base for OVL |
| `09h` | 1 | Byte | `RESERVED` | Zero |
| `0Ah..0Bh` | 2 | Word | `BIOS_LINK` | Zero (`0000h`) |
| `0Ch..1Bh` | 16 | String | `NAME` | ASCII uppercase plugin name |
| `1Ch..1Dh` | 2 | Word | `CAPABILITIES` | Capability bitflags |
| `1Eh..1Fh` | 2 | Word | `RESERVED` | Zero (`0000h`) |
| `20h..FFh` | 224 | Bytes | `PADDING` | Zero-filled padding to 256B |

### Capabilities Bitflags (`1Ch..1Dh`)

```
Bit: 15..9   8    7..6   5     4     3     2     1     0
    +------+----+------+-----+-----+-----+-----+-----+-----+
    | Rsvd |VFS | SIZE |CONF |ABOUT|MODAL|MUTAT| FAR | TPA |
    +------+----+------+-----+-----+-----+-----+-----+-----+
```

| Flag | Value | Description |
| :--- | :---: | :--- |
| `CAP_TPA_EXEC` | `0x0001` | Runs in 4KB TPA overlay slot (4KB only). |
| `CAP_FAR_EXEC` | `0x0002` | Executes in Far RAM via `HB_BNKCALL`. |
| `CAP_DOC_MUTATE`| `0x0004` | Mutates document lines (re-render). |
| `CAP_MODAL_UI` | `0x0008` | Renders modal UI dialog or summary box. |
| `CAP_HAS_ABOUT`| `0x0010` | Implements modal About Screen (`ENTRY+3`).|
| `CAP_HAS_CONFIG`| `0x0020`| Implements Config Screen (`ENTRY+6`). |
| `CAP_SIZE_4K`  | `0x0000` | 4KB size class (<= 4096B payload, 00b). |
| `CAP_SIZE_8K`  | `0x0040` | 8KB size class (<= 8192B payload, 01b). |
| `CAP_SIZE_16K` | `0x0080` | 16KB size class (<= 16384B payload, 10b). |
| `CAP_SIZE_32K` | `0x00C0` | 32KB size class (<= 32768B payload, 11b). |
| `CAP_SIZE_MASK`| `0x00C0` | Mask for size class bits 7..6. |
| `CAP_HAS_VFS`  | `0x0100` | Implements Headless VFS Vector (`ENTRY+9`). |

### Relocation Bitmap (`.PRL` Only)

Following the code image is a bitstream of length `(PROG_SIZE + 7) // 8` bytes.
- Bit 7 of byte 0 corresponds to the first code byte (`ENTRY + 0`).
- Bit 0 of byte 0 corresponds to the eighth code byte (`ENTRY + 7`).
- A bit set to `1` indicates an **address high-byte** requiring relocation:
  $$\text{CodeByte} \leftarrow \text{CodeByte} + (\text{TargetPage} - 1)$$
  Where $\text{TargetPage} = \text{HighByte}(\text{LoadAddress})$.

---

## 3. Plugin Registry & Dynamic Far RAM Sub-Allocation

`SE.COM` maintains an active plugin registry in resident Common RAM
(`PLUGIN_REGISTRY`, 256 bytes). The table supports up to 8 loaded plugins
simultaneously (`PLUGIN_MAX_SLOTS = 8`), each described by a 32-byte descriptor.

### 32-Byte Registry Entry Layout

| Field | Offset | Size | Description |
| :--- | :---: | :---: | :--- |
| `NAME` | `+0` | 16B | ASCII uppercase plugin name, null-padded |
| `PROG_SIZE` | `+16` | Word | Code + Data size in bytes (little-endian) |
| `CAPABILITIES` | `+18` | Word | 16-bit capability flags |
| `FILE_TYPE` | `+20` | Byte | `0` = PRL, `1` = OVL |
| `SLOT_INDEX` | `+21` | Byte | Registry slot index (`0`..`7`) |
| `SLOT_STATE` | `+22` | Byte | `0` = Free, `1` = Active/Loaded |
| `EXEC_MODE` | `+23` | Byte | `0` = TPA Overlay, `1` = Far RAM |
| `FAR_BANK` | `+24` | Byte | Assigned RomWBW Far RAM Bank ID |
| `BASE_PAGE` | `+25` | Byte | Base page in bank (`00h`, `10h`, etc.) |
| `SIZE_CLASS` | `+26` | Byte | `0` = 4KB, `1` = 8KB, `2` = 16KB, `3` = 32KB |
| `PAGE_COUNT` | `+27` | Byte | Allocated 256B pages (16, 32, 64, or 128) |
| `RESERVED` | `+28` | 4B | Reserved padding (zero-filled) |

### Dynamic Multi-Bank Allocation Algorithm

When a plugin is loaded (`LOAD_PLUGIN_BY_NAME` / `ALLOC_FAR_PLUGIN_SLOT`):
1. **Determine Page Requirement**:
   - 4KB class (`SIZE_CLASS 0`): 16 pages (4,096 bytes).
   - 8KB class (`SIZE_CLASS 1`): 32 pages (8,192 bytes).
   - 16KB class (`SIZE_CLASS 2`): 64 pages (16,384 bytes).
   - 32KB class (`SIZE_CLASS 3`): 128 pages (32,768 bytes).
2. **Sub-Allocation for 4KB Plugins**:
   - The editor scans all currently borrowed Far RAM banks recorded in
     `BORROWED_BANKS_TBL`.
   - For each bank, candidate 4KB page boundaries (`0x00, 0x10, ..., 0x70`)
     are checked against active slots using `IS_RANGE_FREE_IN_BANK`.
   - If a free 16-page slot is found, the plugin is assigned to that bank and
     base page.
   - If all borrowed banks are full (or none borrowed yet), a new 32KB bank is
     borrowed via `BORROW_NEW_FAR_BANK` from RomWBW `EXT_BANK_TABLE` and base
     page `0x00` is allocated.
3. **Dedicated Bank Allocation for 8KB, 16KB & 32KB Plugins**:
   - Dedicated plugins require dedicated 32KB banks to avoid address
     conflicts and eliminate the need for run-time code relocation.
   - The editor checks if any borrowed bank is completely free (`C=0, E=128`).
   - If not, a new 32KB bank is borrowed from `EXT_BANK_TABLE`.
   - The plugin is always placed at base page `0x00` (`LOAD_BASE_PAGE = 0`).
   - Because standard CP/M 3 `.PRL` files are assembled at origin `0100H`,
     executing at Far RAM `0x0000 + 0x0100 = 0x0100` allows the code to run
     directly with zero on-the-fly patching or relocation bias.

### Dynamic Bank Release Algorithm

When a plugin is unloaded (`UNLOAD_PLUGIN_SLOT`):
1. The 32-byte registry slot is cleared to zero and marked free.
2. The released slot's `FAR_BANK` identifier is retrieved.
3. All remaining active slots in `PLUGIN_REGISTRY` are scanned.
4. If any other active plugin still uses that Far RAM bank, the bank remains
   retained.
5. If no other active plugin uses the bank, `RELEASE_FAR_BANK` returns the
   32KB bank to RomWBW's `EXT_BANK_TABLE` and updates `BORROWED_BANKS_TBL`.
   This guarantees zero Far RAM leakage across load and unload cycles.

---

## 4. Plugin Calling Convention & Entry Jump Table

Plugins export entry points through a standard 3-entry or 4-entry jump table
located at the beginning of the code image (`base + 0x0100`):

```z80
    ORG 0100H

ENTRY:
    JP  PLUGIN_EXECUTE      ; +0: Main execution (Action 0)
    JP  PLUGIN_ABOUT        ; +3: Display About Screen (Action 1)
    JP  PLUGIN_CONFIG       ; +6: Display Configuration Screen (Action 2)
    JP  PLUGIN_VFS          ; +9: Headless VFS Operations (Action 3, Optional)
```

### Jump Table Offsets

| Offset | Action | Handler | Description | Required |
| :---: | :---: | :--- | :--- | :---: |
| `+0` | `0` | `PLUGIN_EXECUTE` | Default action | **Yes** |
| `+3` | `1` | `PLUGIN_ABOUT` | Modal About dialog | Optional |
| `+6` | `2` | `PLUGIN_CONFIG` | Interactive configuration screen | Optional |
| `+9` | `3` | `PLUGIN_VFS` | Headless VFS operations dispatcher | Optional |

If a plugin does not implement an optional action, its jump slot must contain:
```z80
    SCF                     ; Carry = 1 (Not implemented)
    RET
```
and the corresponding capability bit (`CAP_HAS_ABOUT`, `CAP_HAS_CONFIG`, or
`CAP_HAS_VFS`) must be left cleared (`0`) in the header.

---

## 5. Register State on Entry & Exit

### Entry Register State (Actions 0, 1, 2: Interactive / Modal)

| Register | State on Entry |
| :---: | :--- |
| `IX` | Pointer to `PLUGIN_HOST_API` vector table in Upper Common RAM. |
| `IY` | Pointer to `PLUGIN_HOST_API` vector table (identical to `IX`). |
| `SP` | Valid host stack pointer in Upper Common RAM. |
| `AF`, `BC`, `DE`, `HL` | Undefined (may be used without preserving). |

### Entry Register State (Action 3: Headless VFS Dispatcher)

| Register | State on Entry |
| :---: | :--- |
| `DE` | Pointer to 16-byte `FatVfsRequest` packet in Upper Common RAM. |
| `IX` | Entry address in Far RAM (`base + 0x0109`). |
| `IY` | Pointer to `PLUGIN_HOST_API` vector table. |
| `A` | Assigned Far RAM Bank ID (used by `HB_BNKCALL`). |
| `SP` | Valid host stack pointer in Upper Common RAM. |

### Exit Register State (All Actions)

| Register | Expected Return State |
| :---: | :--- |
| `A` | **Status / Buffer Modification Code**: |
| | Actions 0..2: `0x00`=Clean, `0x01`=Line, `0x02`=Doc, `0xFF`=Err. |
| | Action 3: `VFS_STAT_OK` (`0x00`), or error code (`0x01`..`0xFF`). |
| `CY` | **Carry Flag (Success/Failure)**: |
| | `CY = 0`: Successful execution. |
| | `CY = 1`: Error occurred (`A` contains error code). |
| `BC`, `DE`, `HL`, `IX`, `IY` | Scratch (do not need to be preserved). |
| `SP` | Must be restored to the entry stack position. |

---

## 6. Host API Specification (`PLUGIN_HOST_API`)

`SE.COM` provides a fixed-structure API vector table residing in Upper Common
RAM (`> 0x8000`), guaranteed to remain mapped across all Far RAM bank switches.

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
| `+2` | Word | `API_VERSION` | Host editor version (`0x0097`). |
| `+4` | Word | `PTR_ACTIVE_LINE` | Pointer to 1KB active line buffer. |
| `+6` | Word | `PTR_LINE_LEN` | Pointer to active line length word. |
| `+8` | Word | `PTR_CUR_ROW` | Pointer to current line word (0-based). |
| `+10` | Word | `PTR_TOTAL_LINES` | Pointer to total line count word. |
| `+12` | Word | `PTR_CUR_COL` | Pointer to cursor column word. |
| `+14` | Byte | `ACTIVE_COLS` | Screen width (`80` or `120`). |
| `+15` | Byte | `ACTIVE_CONTEXT` | Screen context ID (`0`..`6`: Editor, Splash, Config, Mem, Mgr, Help, About). |
| `+16` | Byte | `ACTIVE_ROWS` | Screen height (`24` or `40`). |
| `+17` | Byte | `PLUGIN_MGR_SLOT`| Plugin manager slot index (`0`..`7`, or `0xFF` if dedicated). |
| `+18` | Vector | `CALL_CHECKOUT_LINE` | Checkout document line `HL` to `DE`. |
| `+21` | Vector | `CALL_COMMIT_LINE` | Commit line `HL` from `DE` (len `BC`).|
| `+24` | Vector | `CALL_PUTC` | Output character in `A` to console. |
| `+27` | Vector | `CALL_PRINT_STR` | Output '$'-string at `DE` to console. |
| `+30` | Vector | `CALL_GET_KEY` | Blocking console key input into `A`. |
| `+33` | Vector | `CALL_SET_STATUS` | Set status bar message from `DE`. |
| `+36` | Word | `PTR_BLOCK_ACTIVE` | Pointer to block selection state byte. |
| `+38` | Word | `PTR_BLOCK_START` | Pointer to block start line word. |
| `+40` | Word | `PTR_BLOCK_END` | Pointer to block end line word. |
| `+42` | Word | `PTR_TAB_WIDTH` | Pointer to tab width byte (`4` or `8`).|
| `+44` | Word | `PTR_REGISTRY` | Pointer to 256B `PLUGIN_REGISTRY` table. |
| `+46` | Vector | `CALL_CHECK_KEY` | Non-blocking key check (`Z`/`NZ`). |
| `+49` | Vector | `CALL_CLEAR_DOCUMENT`| Reset document slots & buffer. |
| `+52` | Vector | `CALL_LOCATE_RC` | Move hardware cursor to Row `H`, Col `L`. |
| `+55` | Vector | `CALL_LOAD_PLUGIN` | Load plugin from disk (`DE` = filename). |
| `+58` | Vector | `CALL_UNLOAD_SLOT` | Unload plugin in slot `A` (`0`..`7`). |
| `+61` | Vector | `CALL_REDRAW_BASE` | Redraw host screen for context in `A`. |

---

## 7. Host Callback Function Details

### 1. `CHECKOUT_LINE` (`IX + 18`)
Fetches a line from the Far RAM document buffer into a designated RAM buffer.
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
  - `Z = 1`: No character ready.
  - `NZ = 1`: Key is waiting in console buffer.
- **Preserves**: `BC`, `DE`, `HL`, `IX`, `IY`.

### 7. `SET_STATUS_MSG` (`IX + 33`)
Updates the status bar notification area with a custom message.
- **Input**:
  - `DE` = Pointer to null-terminated ASCII string (max 32 chars).
- **Preserves**: `IX`, `IY`.

### 8. `CLEAR_DOCUMENT` (`IX + 49`)
Resets the document slot allocator, sets `DOC_TOTAL_LINES` to 0, resets cursor,
clears dirty flags and line cache, preparing the host editor for streaming a
fresh document into Far RAM (e.g. via `COMMIT_LINE`).
- **Preserves**: `IX`, `IY`.

---

## 8. Plugin Authoring Guide & Template

Below is a complete, minimal template for a Z80 plugin implementing the
standard jump table with Execute, About, and Config screens:

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

## 9. Building & Packaging Plugins

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
    --size 16k \
    --caps 0x0077
```

---

## 10. Headless VFS Application Binary Interface (Action 3)

Heavyweight storage drivers (such as `FATFS.PRL`) export a headless Virtual
File System (VFS) interface at `ENTRY + 9` (Action 3). This enables `SE.COM`
to perform background filesystem operations (directory enumeration, file load,
file save, block insert, and block save) without lower TPA RAM consumption.

### 16-Byte `FatVfsRequest` Packet Map

| Offset | Type | Field | Description |
| :---: | :---: | :--- | :--- |
| `+0` | Byte | `cmd` | Command opcode (`VFS_CMD_*`). |
| `+1` | Byte | `unit` | HBIOS disk unit (`0`..`7`, or `0xFF` for default). |
| `+2` | Byte | `status` | Output return status code (`VFS_STAT_*`). |
| `+3` | Byte | `flags` | Option flags (`VFS_FLAG_*`). |
| `+4` | Word | `path` | Pointer to null-terminated DOS path in Upper RAM. |
| `+6` | Word | `buffer` | Pointer to data buffer in Upper RAM (`> 0x8000`). |
| `+8` | Word | `buffer_size` | Maximum capacity (in bytes or entry count). |
| `+10` | Word | `count` | Output count (entries read, lines read/written). |
| `+12` | Word | `start_line` | Range start line (0-indexed) for block save. |
| `+14` | Word | `end_line` | Range end line (inclusive) for block save. |

### VFS Command Opcodes (`cmd`)

| Code | Constant | Description |
| :---: | :--- | :--- |
| `0` | `VFS_CMD_PROBE_MOUNT` | Probe/mount filesystem on requested unit. |
| `1` | `VFS_CMD_LIST_DIR` | Enumerate directory entries into 13B records. |
| `2` | `VFS_CMD_LOAD_FILE` | Stream text file lines into host document. |
| `3` | `VFS_CMD_SAVE_FILE` | Export entire host document to text file. |
| `4` | `VFS_CMD_SAVE_RANGE` | Export line range start_line..end_line. |
| `5` | `VFS_CMD_OPEN_FILE` | Open file for sector/chunk streaming. |
| `6` | `VFS_CMD_READ_CHUNK` | Read up to buffer_size bytes into buffer. |
| `7` | `VFS_CMD_CLOSE_FILE` | Close active streaming file handle. |
| `8` | `VFS_CMD_GET_DEF_UNIT` | Query default HBIOS unit into unit field. |
| `9` | `VFS_CMD_SET_DEF_UNIT` | Set default HBIOS unit from unit field. |

### VFS Return Status Codes (`status`)

| Code | Constant | Description |
| :---: | :--- | :--- |
| `0` | `VFS_STAT_OK` | Operation completed successfully. |
| `1` | `VFS_STAT_NOT_FOUND` | Specified file or directory path was not found. |
| `2` | `VFS_STAT_DISK_ERR` | Physical media error or FatFs error. |
| `3` | `VFS_STAT_BUFFER_FULL`| Output buffer capacity reached. |
| `4` | `VFS_STAT_INV_UNIT` | Specified HBIOS unit index is invalid. |
| `5` | `VFS_STAT_READ_ONLY` | Volume or file is write-protected. |
| `6` | `VFS_STAT_EOF` | End of file reached during chunk streaming. |
| `255` | `VFS_STAT_UNSUPPORTED`| Unrecognized command opcode. |

### 13-Byte Directory Record Format

When executing `VFS_CMD_LIST_DIR`, entries are written sequentially into
`buffer` as 13-byte fixed records:
- **Files**: 8 characters name (space-padded), `.` at offset 8, 3 characters
  extension (space-padded), null (`\0`) at offset 12.
- **Directories**: 8 characters name (space-padded), `/` at offset 8, 3 spaces,
  null (`\0`) at offset 12.
- **Parent Directory**: If not in the root directory, `"..      /   \0"` is
  provided for navigating up the directory tree.

---

## 11. Standalone Far RAM Modular Subsystem: Plugin Manager (`PLUGIN.PRL`)

To maximize available TPA RAM for text editing and reduce core binary footprint,
the full-screen interactive **Plugin Manager UI** and the **Context-Aware `Ctrl+P`
Modal Subsystem** are extracted from `SE.COM` into a standalone 8KB Far RAM
modular plugin: **`PLUGIN.PRL`**.

### Architecture & Capabilities

`PLUGIN.PRL` is packaged as an 8KB Far RAM modular plugin:
```bash
python3 tools/mkprl.py -n PLUGIN -o plugins/PLUGIN.PRL \
    --size 8k --far --modal --has-about --bss 128 \
    plugins/plugin_100.bin plugins/plugin_200.bin
```
- **Capabilities Word**: `0x005A`
  (`CAP_FAR_EXEC | CAP_MODAL_UI | CAP_HAS_ABOUT | CAP_SIZE_8K`).
- **Memory Allocation**: Resident in a dedicated 32KB Far RAM bank
  (`PLUGIN_MGR_BANK`), borrowed on-demand via `BORROW_PLUGIN_MGR_BANK`
  from RomWBW's `EXT_BANK_TABLE`.
- **Bank Isolation**: `PLUGIN_MGR_BANK` is strictly isolated from
  `BORROWED_BANKS_TBL` and protected by an explicit guard in
  `IS_RANGE_FREE_IN_BANK`. User plugin slots (`0`..`7`) never allocate within
  `PLUGIN_MGR_BANK`, preventing bank collisions and in-place corruption during
  concurrent plugin loading.
- **Dynamic Bank Stealing Policy**: RomWBW systems provide up to 4 application
  banks. `BORROW_NEW_FAR_BANK` allows borrowing down to 0 extra document banks
  when no document is actively being edited (`IN_EDITOR_MODE == 0`). When
  actively editing (`IN_EDITOR_MODE != 0`), Bank 0 (`EXT_BANK_TABLE[0]`) is
  strictly preserved for resident text storage.
- **Entry Jump Table**:
  - `ENTRY + 0`: Action 0 — Full-Screen Interactive Plugin Manager
    (`DO_PLUGIN_MANAGER`).
  - `ENTRY + 3`: Action 1 — Context-Aware Modal Dialog (`DO_CONTEXT_POPUP`).
  - `ENTRY + 6`: Action 2 — Modal About Dialog (`DO_PLUGIN_ABOUT`).
- **Trampoline Context Switching**: Host trampolines (`TRAMP_LOAD_PLUGIN`,
  `TRAMP_UNLOAD_SLOT`, `TRAMP_REDRAW_BASE`) preserve caller Far RAM banks
  across inter-bank transitions to guarantee re-entrant execution between
  `PLUGIN.PRL` and user plugin slots.

