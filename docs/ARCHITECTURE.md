# SE.COM Architecture Specification

This document provides a comprehensive technical overview of the architecture,
subsystems, memory organization, and data flows of **`SE.COM`** (Screen
Editor), a high-performance text editor for CP/M 2.2 / 3.0 systems running on
the **RomWBW v3.6.0+** firmware platform (Z80 and Z180 processors).

---

## 1. Architectural Goals & Design Philosophy

`SE.COM` was engineered from the ground up in pure Z80 assembly language to
reconcile two conflicting requirements:
1. **Classic CP/M Memory Budget**: Fit comfortably inside standard 64KB CP/M
   Transient Program Area (TPA) with positive headroom below BDOS entry
   points (0xD800 on RomWBW RC2014, 0xDC00 on standard 64K CP/M).
2. **Modern Large-Document Editing**: Support multi-thousand-line source files
   (up to 32,768 lines, ~8.3 MB virtual capacity) through banked memory
   switching and swap-file paging.

Key design principles:
* **Terminal-First & Geometry-Bound**: ANSI/VT100 serial console compatibility
  across standard retro 80x24 and modern widescreen 120x40 display modes.
* **Deterministic Resource Consumption**: Code and static data are strictly
  budgeted; all dynamic buffers reside in controlled BSS regions or Far RAM.
* **Universal Status Bar & Surface Taxonomy**: Bottom status bar is present on
  every screen; column 0 tildes denote unallocated display rows; modal dialogs
  use strict ASCII box framing and centering arithmetic.
* **Modular Extensibility**: A zero-overhead plugin architecture supporting
  both in-TPA transient overlays and Far RAM resident modules via an Upper
  RAM Host API vector table.

---

## 2. CP/M TPA Memory Layout & Footprint

Standard CP/M maps 64KB address space with Page 0 (0x0000..0x00FF) reserved for
system vectors, TPA beginning at 0x0100, and BDOS/BIOS residing in high memory.

```text
+-----------------------------------------------------------------------+
| 0x0000 - 0x00FF : CP/M Page 0 (Warm Boot, BDOS Entry 0x0005, FCBs)    |
+-----------------------------------------------------------------------+
| 0x0100 - 0xBC00 : SE.COM Binary (Code, Constants, Static Jump Tables)  |
|                   Size: 47,872 bytes (46.75 KB)                       |
+-----------------------------------------------------------------------+
| 0xBC00 - 0xD000 : BSS Buffers / Plugin Overlay Slot                   |
|                   Size: 5,120 bytes (5.00 KB)                         |
|                   Top of Memory: 0xD000 (53,248)                      |
+-----------------------------------------------------------------------+
| 0xD000 - 0xD800 : Free TPA Headroom (+2,048 bytes / +2.00 KB margin)  |
+-----------------------------------------------------------------------+
| 0xD800 - 0xE600 : RomWBW BDOS                                         |
+-----------------------------------------------------------------------+
| 0xE600 - 0xFFFF : RomWBW CBIOS                                        |
+-----------------------------------------------------------------------+
```

### 2.1 BSS Buffer Allocation & Overlay Reuse

Memory between `0xBC00` and `0xD000` is shared dynamically based on active
subsystem state:
* **TPA Plugin Overlay Slot** (`0xBC00..0xD000`, 5,120 bytes): Transient
  plugins (`.OVL`, `.PRL`) load directly into this region when active.
* **Editor Working Storage**: When editing, line cache buffers, split-line
  temporaries, and directory structures reuse this space safely without
  encroaching on code space.
* **Upper Memory Host Vector**: `PLUGIN_HOST_API` is situated at `ALIGN 4` in
  high code space (> 0x8000), ensuring it remains permanently mapped and
  visible regardless of which lower/middle RAM banks are switched.

---

## 3. Banked Memory Subsystem (RomWBW HBIOS v3.6.0+)

To overcome the 64KB Z80 address barrier, `SE.COM` interfaces directly with
RomWBW HBIOS firmware services via `RST 08H` (strictly requiring RomWBW v3.6.0
or later).

### 3.1 HBIOS Bank Operations

* **Probe Banks (`BF_SYSGET`)**: Detects total physical banks, current bank,
  and user area configuration.
* **Bank Copy (`BF_SYSCOPY`)**: High-speed inter-bank block memory transfer
  between Common RAM (0x8000..0xFFFF) and Far RAM banks without CPU-driven
  byte loops.
* **Bank Switch (`BF_SYSSET`)**: Fast mapping of 32KB / 64KB physical banks.

### 3.2 Bank Allocation Strategy

RomWBW typically provides up to 512KB (or more) of banked RAM divided into
physical 32KB/64KB banks:
* **Bank 0**: Primary CP/M System RAM (TPA + BDOS + BIOS).
* **Bank 1**: Line Pointer Table (stores 16-bit physical line slot descriptors
  for up to 16,384 or 32,768 document lines).
* **Banks 2..N**: Document Page Storage (caches document text in 128-byte
  virtual slots).
* **Plugin Banks**: Far RAM resident plugins (`BIGPLUG.PRL`, `FATFS.PRL`,
  `HALFPLUG.PRL`) execute in dedicated Far RAM banks above document storage.

### 3.3 RAM Drive Detection & Protection Modes

RomWBW often allocates high RAM banks for an in-memory RAM disk (typically
Drive `A:`). `SE.COM` detects the RAM disk and provides three configurable
protection strategies:
1. **Preserve Mode**: Protects the RAM disk completely. `SE.COM` restricts its
   bank allocation ceiling below the RAM disk boundary.
2. **Hibernate Mode**: Backs up RAM disk directory and allocation tables to a
   temporary swap file, reclaims the banks for document editing, and restores
   the RAM disk upon exit.
3. **Overwrite Mode**: Sacrifices RAM disk data to provide maximum editing
   headroom (~384KB to 512KB Far RAM).

---

## 4. Document Model & Virtual Storage Engine

`SE.COM` represents documents as an indexed sequence of variable-length
null-terminated text lines.

### 4.1 Slot-Based Virtual Storage Architecture

```text
Document Line Index (0 .. Total Lines - 1)
       |
       v
+-----------------------+
| Line Slot Descriptor  | -> Slot Index (16-bit)
+-----------------------+
       |
       +---> [Physical Bank in Far RAM] (if cached in RAM)
       |
       +---> [Swap File `$$$SE$$$.SWP`] (if paged out to disk)
```

* **Slot Size**: Lines are stored in 128-byte fixed records. Lines up to 120
  characters fit in a single slot.
* **Two-Level Table**:
  - The Line Table maps each document line number to a virtual slot index.
  - The Slot Allocation Bitmap tracks free vs occupied physical slots in Far
    RAM.
* **Swap Paging Engine**: When total document size exceeds available Far RAM
  banks, `SE.COM` activates its LRU (Least Recently Used) disk paging system,
  streaming inactive 128-byte slots to the hidden file `$$$SE$$$.SWP` on the
  current drive and retrieving them transparently upon navigation.

### 4.2 Local Working Cache (`LINE_STORAGE`)

To eliminate bank-switching overhead during interactive character typing and
cursor navigation:
* A local contiguous cache (`CACHE_SIZE_LINES = 40`) is kept in TPA RAM.
* `ACTIVE_LINE_BUF` (1,024 bytes) holds the currently edited line in local RAM.
* Keystrokes modify `ACTIVE_LINE_BUF` directly. Upon cursor row change or
  scrolling, the dirty line is flushed back to its Far RAM slot.

---

## 5. Visual Block Subsystem

`SE.COM` features a visual block selection and manipulation engine supporting
both dynamic range selection and solidified block operations:

### 5.1 Block Lifecycle & State Machine

```text
[Inactive] (BLOCK_ACTIVE = 0)
    |
    | <Ctrl+B>
    v
[Dynamic Selection] (BLOCK_ACTIVE = 1)
    |
    +--- Cursor Move ----------> Expands/contracts selection
    |                            (Status: "Sel: <N> char(s)/line(s)")
    |
    +--- <Ctrl+B> -------------> Cancel / clear selection -> [Inactive]
    |
    +--- <Enter> --------------> Solidify block -> [Solidified Block]
    |
    +--- <Ctrl+K> -------------> Open Block Operations Modal Dialog
                                  |
                                  +--- <ESC>  -> Close modal (keep dynamic)
                                  +--- <^B>   -> Clear block -> [Inactive]
                                  +--- <Enter>-> Solidify -> [Solidified]
                                  +--- <^C/^X/^D/^S> -> Execute action
```

```text
[Solidified Block] (BLOCK_ACTIVE = 2)
    |
    | (Status: "Block: <N> char(s)/line(s)")
    |
    +--- Cursor Move ----------> Free cursor travel without altering block
    |
    +--- <Ctrl+B> -------------> Clear solidified block -> [Inactive]
    |
    +--- <Del> / <Ctrl+D> -----> Delete solidified block
    |
    +--- <Ctrl+C> -------------> Copy block to current cursor position
    |
    +--- <Ctrl+X> -------------> Cut/move block to current cursor position
    |
    +--- <Ctrl+S> -------------> Save block to disk file
    |
    +--- <Ctrl+K> -------------> Open Block Operations Modal Dialog
```

### 5.2 Status Bar Reporting (Field 4)

Field 4 of the status bar is strictly padded to 15 characters to prevent visual
debris:
* Single-line dynamic: `Sel: <N> char(s)`
* Multi-line dynamic: `Sel: <N> line(s)`
* Single-line solidified: `Block: <N> chars`
* Multi-line solidified: `Block: <N> lines` or `Block: <N>L` (if count > 999)

---

## 6. Display Engine & Terminal Subsystem

The display subsystem targets ANSI / VT100 / VT102 compatible terminals over
serial lines or memory-mapped hardware consoles.

### 6.1 Geometry Modes

* **Modern Widescreen (120x40)**: Default mode for modern terminal emulators
  (Minicom, PuTTY, Windows Terminal) providing 120 columns by 40 rows.
* **Classic Retro (80x24)**: Standard VT100 80 columns by 24 rows.
* **Horizontal Panning**: In 80x24 mode, lines longer than 80 columns trigger
  automatic viewport horizontal panning (`[Pan +N]`) with column 79
  continuation indicators.

### 6.2 UI/UX Hierarchy & Rules

* **Tier 1 (Full-Screen Workspaces)**: Splash Screen, Document Editor, Open
  File, Save File, Configuration Manager, Memory Map, and Help Screen. All
  workspaces center content horizontally and vertically.
* **Tier 2 (Centered Boxed Modal Pop-ups)**: Fixed 50-column ASCII boxes
  centered horizontally (`(ACTIVE_COLS - 50) / 2 + 1`) and vertically. Used
  for Find/Replace, Progress Tickers, File Overwrite, Block Operations, and
  Error Notifications.
* **Column 0 Tilde Discipline**: Non-document body and margin rows display a
  tilde (`~`) in column 0.
* **Anchored Status Bar**: Row `HOST_ROWS` is reserved for the inverse-video
  status bar:
  `| Filename[*] | Geometry | Format | Field 4 Status | Cursor Position |`

---

## 7. Modular Plugin Architecture & ABI

`SE.COM` includes an open plugin architecture detailed in
[`plugins/PLUGIN_ABI.md`](../plugins/PLUGIN_ABI.md).

### 7.1 Plugin Execution Modes

1. **TPA Overlay Plugins (`.OVL`, `.PRL`)**:
   - Loaded into the 5,120-byte overlay slot at `0xBC00`.
   - Used for quick transient tasks (e.g. `WORDCNT.OVL`, `ROT13.PRL`,
     `HELP.OVL`).
2. **Far RAM Banked Plugins (`.PRL`)**:
   - Executed in dedicated Far RAM banks (up to 32KB per plugin).
   - Enables heavy subsystems like the FAT32/SD-card VFS driver (`FATFS.PRL`)
     and assembly code reformatters (`BEAUTIFY.PRL`) without depleting TPA.

### 7.2 Upper Memory Vector Table (`PLUGIN_HOST_API`)

Resident in Upper Memory above `0x8000`:
* Offset `+0`: Magic `"SE"`
* Offset `+2`: Host Version (e.g. `0103H` for `v1.0.3`)
* Offset `+4`: Pointers to `ACTIVE_LINE_BUF`, `ACTIVE_LINE_LEN`, `CUR_DOC_ROW`,
  `DOC_TOTAL_LINES`, `CUR_COL`, `ACTIVE_COLS`, `ACTIVE_ROWS`.
* Function Dispatch Table: Terminal I/O, cursor locate, modal rendering, line
  insert/delete/replace, and file I/O callbacks.

---

## 8. Modular Multi-Platform Architecture & Hardware Abstraction Layer (HAL)

Starting with v1.1.0, `SE` features a decoupled, modular architecture that
separates platform-specific hardware control (console I/O, keyboard decoding,
memory paging, and mass storage) from editor core logic (document line buffers,
gap buffers, viewport rendering, search, config, and plugins).

### 8.1 Modular Directory & Source Organization

The codebase is organized into three distinct tiers:

1. **Subsystem Headers (`src/include/*.inc`)**:
   - `config.inc`: Screen dimensions, buffer sizes, and configuration offsets.
   - `hal.inc`: Hardware abstraction interface constants and vector jumps.
   - `buffer.inc`: Line pointer tables, document buffers, and edit records.
   - `editor.inc`: Mode flags, cursor state, navigation, and key commands.
   - `block.inc`: Block anchor coordinates, selection state, and clipboard.
   - `search.inc`: Search patterns, case flags, and match coordinators.
   - `ui.inc`: Modal dialog geometries, palette attributes, and status rows.
   - `file_io.inc`: FCB layouts, sector transfer buffers, and error codes.
   - `plugin.inc`: Far RAM plugin slots, jump tables, and host ABI hooks.
   - `beautify.inc`: Assembly formatter state and indentation parameters.

2. **Hardware Abstraction Platform Drivers (`src/hal/`)**:
   - `src/hal/cpm/`:
     - `hal_cpm_console.asm`: CP/M BDOS/BIOS character I/O and VT100 control.
     - `hal_cpm_memory.asm`: RomWBW HBIOS `RST 08H` Far RAM bank switching.
     - `hal_cpm_storage.asm`: BDOS 2.2/3.0 FCB record access and disk I/O.
   - `src/hal/next_cpm/`:
     - `hal_nextcpm_console.asm`: NextCPM 80-column console output driver.
     - `hal_nextcpm_keyboard.asm`: Next keyboard translation to WordStar codes.
     - `hal_nextcpm_memory.asm`: NextCPM banked memory mapping driver.
     - `hal_nextcpm_storage.asm`: NextCPM CP/M 2.2-compatible storage services.
   - `src/hal/next_native/`:
     - `hal_next_console.asm`: NextReg `0x07` 28 MHz turbo & RST 10h stream.
     - `hal_next_keyboard.asm`: Port `0xFE` scanning & cursor key translation.
     - `hal_next_memory.asm`: NextReg `0x50`–`0x57` MMU 8KB SRAM page banking.
     - `hal_next_storage.asm`: NextZXOS / ESXDOS `RST 08H` FAT file operations.

3. **Core Subsystems (`src/core/*.asm`)**:
   - `buffer.asm`: Gap buffer insertion, line deletion, and text indexing.
   - `block.asm`: Block selection, marking, cut, copy, paste, and formatting.
   - `search.asm`: Fast substring search, replace, and wrap handling.
   - `editor.asm`: Keystroke dispatch table, command routing, and edit loops.
   - `ui_render.asm`: Viewport line drawing, tilde margins, and line numbers.
   - `ui_browser.asm`: Centered modal dialogs, file pickers, and pop-ups.
   - `config.asm`: Options persistence, geometry switching, and `SE.CFG`.
   - `memory.asm`: Far RAM paging manager, bank pool, and swap handling.
   - `plugin_mgr.asm`: Dynamic plugin loader, slot binder, and menu pop-ups.
   - `plugin_tramp.asm`: Upper memory vector table (`PLUGIN_HOST_API`).
   - `beautify.asm`: Built-in Z80 code beautification coordinator.

### 8.2 Hardware Abstraction Layer (HAL) Contract

All core subsystems interact with platform peripherals exclusively through
jump vectors defined in `hal.inc` and implemented by the active HAL driver:

* **Console Vector Table**:
  - `HAL_CONSOLE_INIT`: Initialize screen mode, cursor, and terminal stream.
  - `HAL_RAW_CONIN`: Blocking read of an unbuffered input character.
  - `HAL_RAW_CONOUT`: Direct output of an ASCII byte or escape code.
  - `HAL_RAW_CONST`: Poll for console input readiness (non-blocking).
  - `HAL_CONSOLE_RESTORE`: Clean up screen and restore host OS terminal state.

* **Keyboard Vector Table**:
  - `HAL_KBD_INIT`: Set up keyboard scanning hardware and repeat counters.
  - `HAL_KBD_POLL`: Check for keypress activity.
  - `HAL_KBD_READ`: Read key event and translate to unified ASCII/WordStar.
  - `HAL_KBD_RESTORE`: Restore standard keyboard scanning configuration.

* **Memory Management Vector Table**:
  - `HAL_MEM_INIT`: Detect available physical memory banks and capacity.
  - `HAL_MEM_QUERY`: Return available Far RAM bank count and bank IDs.
  - `HAL_BANK_MAP`: Page an 8KB/16KB logical Far RAM bank into view window.
  - `HAL_BANK_RESTORE`: Restore host OS default memory bank configuration.

* **Storage Vector Table**:
  - `HAL_STORAGE_INIT`: Initialize filesystem subsystem and working drive.
  - `HAL_FILE_OPEN`: Open document file by name with read/write access.
  - `HAL_FILE_CLOSE`: Flush buffers, update directory record, and close file.
  - `HAL_FILE_READ`: Sequential record read into active line buffer.
  - `HAL_FILE_WRITE`: Sequential record write from buffer to media.

### 8.3 Supported Target Profiles

The build system (`Makefile`) compiles the unified codebase into four distinct
distribution artifacts:

| Binary | Target Platform | Base | Size | Primary Use Case |
| :--- | :--- | :--- | :--- | :--- |
| `SE.COM` | RomWBW CP/M 2.2/3.0 | 0x0100 | 47,872 B | Standard CP/M SBCs |
| `SE_NEXT.COM` | NextCPM (ZX Next) | 0x0100 | 47,872 B | CP/M on Next |
| `SE.NEX` | ZX Next Standalone | 0x4000 | 49,664 B | NextZXOS Browser App |
| `.se` / `SE` | NextZXOS Dot Cmd | 0x2000 | 48,128 B | NextZXOS CLI Tool |



- **`SE.COM`**: Standard CP/M binary targeting RomWBW systems. Retains 100%
  byte-for-byte binary invariance against golden baselines and guarantees
  +2,048 B TPA headroom margin below `0xD800`.
- **`SE_NEXT.COM`**: Drop-in executable for NextCPM environments. Uses NextCPM
  80-column console output and Sinclair keyboard translation while maintaining
  CP/M BDOS filesystem compatibility.
- **`SE.NEX`**: Packaged executable for the ZX Spectrum Next. Features a
  512-byte `.NEX` header, pre-maps 3 $\times$ 16KB SRAM banks (Banks 0, 2, 5),
  switches the Z80N CPU to 28 MHz turbo mode via NextReg `0x07`, and routes ANSI
  text through `RST 10H`.
- **`.se` / `SE`**: Compact NextZXOS dot command installed to `/dot/` on the
  Next SD card. Executes directly at `0x2000` from the NextZXOS CLI with file
  path arguments (e.g. `.se autoexec.bas`).

