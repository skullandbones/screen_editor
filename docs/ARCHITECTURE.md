# SE.COM Architecture Specification

This document provides a comprehensive technical overview of the architecture,
subsystems, memory organization, and data flows of **`SE.COM`** (Screen
Editor) and its multi-platform targets (8-bit CP/M-80 on **RomWBW v3.5+** and
**ZX Spectrum Next**, 16-bit CP/M-86 `SE.CMD`, and 64-bit Linux ports).

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

## 3. Banked Memory Subsystem (RomWBW HBIOS v3.5+ & Next MMU)

To overcome the 64KB Z80 address barrier, `SE.COM` interfaces directly with
RomWBW HBIOS firmware services via `RST 08H` (RomWBW v3.5 or later) or the ZX
Spectrum Next MMU slot registers (`NEXTREG 0x50..0x53` on `SE_NEXT.COM`).

### 3.1 HBIOS & MMU Bank Operations

* **Probe Banks (`BF_SYSGET`)**: Detects total physical banks, current bank,
  RAM drive bounds, and application bank configuration.
* **Bank Copy (`BF_SYSSETCPY` `0xF4` / `BF_SYSBNKCPY` `0xF5`)**: High-speed
  inter-bank block memory transfer between Upper Common RAM (`0x8000..0xFFFF`)
  and 32KB Far RAM banks (`0x0000..0x7FFF`).
* **Bank Switch & Call (`HB_BNKSEL` `0xFFF3` / `HB_BNKCALL` `0xFFF9`)**: Fast
  mapping and cross-bank execution of 32KB physical banks (mirrored by
  `NEXT_BNKSEL` and `NEXT_BNKCALL` on ZX Spectrum Next).

### 3.2 Bank Allocation Strategy

RomWBW typically provides up to 512KB (16 x 32KB banks) of banked RAM:
* **Bank 0 (`80h`)**: HBIOS System Firmware.
* **TPA Bank (`8Eh` / `8Fh`)**: Primary CP/M System RAM (TPA + BDOS + BIOS).
* **Line Table Bank(s)**: Stores 16-bit physical line slot descriptors for up
  to 16,384 lines (1 bank) or 32,768 document lines (2 banks).
* **Document Buffer Banks (`EXT_BANK_TABLE`)**: Pools remaining 32KB Far RAM
  banks for document text storage in multi-stride 128-byte slots.
* **Plugin Manager & Far RAM Plugin Banks**: `PLUGIN.PRL` occupies a dedicated
  32KB Far RAM bank (`PLUGIN_MGR_BANK`), and loaded plugins dynamically borrow
  32KB Far RAM banks (`BORROW_NEW_FAR_BANK`) from `EXT_BANK_TABLE`.

### 3.3 RAM Drive Detection & Protection Modes

RomWBW allocates intermediate RAM banks (`81h..88h`) for an in-memory RAM disk
(e.g. Drive `B:` or `A:` / `MD0:`). `SE.COM` detects the RAM disk and provides
three configurable protection strategies:
1. **Preserve Mode (`Protected`, Default)**: Protects the RAM disk completely.
   `SE.COM` restricts its bank allocation to the HBIOS application banks.
2. **Hibernate Mode (`Hibernate`)**: Saves the RAM disk banks to a temporary
   image file (`RAMDRV.IMG`) via `HIBERN.OVL`, reclaims the banks for document
   editing, and restores the RAM disk upon exit.
3. **Overwrite Mode (`Enabled`)**: Uses the RAM disk banks directly to provide
   maximum editing capacity (~384KB to 448KB Far RAM).

---

## 4. Document Model & Virtual Storage Engine

`SE.COM` represents documents as an indexed sequence of variable-length
null-terminated text lines up to 1,000 characters per line
(`MAX_LINE_CHARS = 1000`).

### 4.1 Slot-Based Far RAM Storage Architecture

```text
Document Line Index (0 .. Total Lines - 1)
       |
       v
+-----------------------+
| Line Slot Descriptor  | -> Slot Index (16-bit) & Stride Count
+-----------------------+
       |
       +---> [Physical 32KB Bank in Far RAM (EXT_BANK_TABLE)]
```

* **Multi-Stride Slot Allocation**: Lines are stored in 128-byte base slots in
  32KB Far RAM banks (`256` slots per 32KB bank), automatically spanning up to
  8 contiguous slots (`1,024` bytes) for lines up to 1,000 characters.
* **Two-Level Table**:
  - The Line Pointer Table (`LINE_TABLE_BANK` / `LINE_TABLE_BANK_1`) maps each
    document line number (`0..16,383` or `0..32,767`) to its Far RAM bank and
    slot descriptor.
  - Per-bank allocation bitmaps track free vs. occupied 128-byte slots across
    all active document banks in `EXT_BANK_TABLE`.

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

* **Classic Retro (`80x24`, Option 1 — Universal Default)**: Standard VT100 80
  columns by 24 rows. Default mode across all SE platforms and targets.
* **Modern Widescreen (`120x40`, Option 2)**: Optional wide console mode for
  modern terminal emulators (Minicom, PuTTY, Windows Terminal) providing 120
  columns by 40 rows.
* **Native Host Terminal (`Native`, Option 3)**: Dynamic host terminal sizing on
  native OS ports (`se-linux`, `se-py`, `se-rs`, etc.).
* **Horizontal Panning**: Lines longer than the active screen width trigger
  automatic viewport horizontal panning (`[Pan +N]` in 40-column increments up
  to 1,000 characters).

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

## 7. Plugin Mechanisms & CP/M-80 Modular Plugin Architecture

While `docs/UI_UX_DESIGN.md` (Section 14.8) defines the cross-platform UI/UX
boundaries between loadable and builtin plugin managers (`PLUGIN.PRL` on <64 KB
8-bit CP/M-80 targets vs. builtin plugin managers on CP/M-86 `SE.CMD` and
non-CP/M targets), this section specifies the concrete plugin mechanism and ABI
implemented by 8-bit CP/M-80 systems (`SE.COM` on RomWBW CP/M-80 and
`SE_NEXT.COM` on ZX Spectrum Next CP/M-80).

### 7.1 Architectural Overview (`SE.COM` & `SE_NEXT.COM`)

On 8-bit Z80 CP/M-80 systems, the 64 KB CPU address space is split into a Lower
32 KB Transient Program Area / Banked window (`0x0000..0x7FFF`) and an Upper
32 KB Common RAM region (`0x8000..0xFFFF`, capped below BDOS at `0xD800`).
To maximize TPA headroom while supporting up to 8 concurrent plugins (`4 KB` to
`32 KB` each), CP/M-80 SE uses a two-tier architecture:
1. **Host Kernel (`src/core/plugin_mgr.asm` & `src/core/plugin_tramp.asm`)**:
   Resident inside `SE.COM` / `SE_NEXT.COM`. Maintains the 8-slot
   `PLUGIN_REGISTRY` (`256` bytes), the Far RAM bank/page allocator, the `.PRL`
   and `.OVL` binary loader and byte-level relocator, and the Upper Common RAM
   (`>= 0x8000`) `PLUGIN_HOST_API` jump vector and cross-bank trampolines.
2. **External Plugin Manager Overlay (`PLUGIN.PRL`, `plugins/plugin.asm`)**:
   Loaded into a dedicated 32 KB Far RAM bank (`PLUGIN_MGR_BANK`) either at
   startup (`PLUGIN=AUTOLOAD` in `SE.CFG`) or on first invocation
   (`PLUGIN=ONDEMAND`). `PLUGIN.PRL` implements the interactive Tier 1 Plugin
   Manager workspace (`[P]`), the Tier 2 Context-Aware Plugin Palette
   (`Ctrl+P`), and `PLUGIN.CFG` slot persistence (`SLOT0=..SLOT7=`).
3. **Runtime Banking Auto-Detection**:
   The CP/M-80 plugin subsystem auto-detects the underlying hardware banking
   mechanism at runtime:
   - **RomWBW HBIOS (`SE.COM`)**: Uses `RST 08H` (`BF_SYSSETCPY` `0xF4` /
     `BF_SYSBNKCPY` `0xF5`) for inter-bank DMA copies, `HB_BNKCALL` (`0xFFF9`)
     for Far RAM entry execution, and `HB_BNKSEL` (`0xFFF3`) inside Upper RAM
     trampolines.
   - **ZX Spectrum Next MMU (`SE_NEXT.COM`)**: Uses NextReg MMU slot registers
     `0x50..0x53` (`0x0000..0x7FFF`) via `NEXT_SYSSETCPY`, `NEXT_SYSBNKCPY`,
     `NEXT_BNKCALL`, and `NEXT_BNKSEL`.

### 7.2 Relationship to Standard CP/M 3 / MP/M II Mechanisms

The CP/M-80 plugin architecture is a **hybrid** that pairs the standard
**MP/M II / CP/M 3 (CP/M Plus) Page Relocatable (`.PRL`) binary file format and
bit-vector relocation algorithm** with a **custom SE-specific runtime loader,
extended header contract, and direct hardware bank switcher**:
1. **Standard CP/M 3 / MP/M II `.PRL` Format & Relocation**:
   - Uses the canonical Digital Research 256-byte (`0x0100`) file header
     (`PROG_SIZE` at `+0x01..0x02`, `BSS_SIZE` at `+0x04..0x05`) followed by the
     code/data image (`ORG 0x0100`) and a bit-packed relocation bitmap of
     `(PROG_SIZE + 7) // 8` bytes.
   - Applies the standard bit-serial page relocation algorithm
     (`RELOCATE_PRL_LOOP` in `src/core/plugin_mgr.asm`) where each `1` bit
     (MSB `0x80` down to LSB `0x01`) adds an 8-bit page relocation bias
     (`(target_load_address >> 8) - 1`) to the high byte of a 16-bit address in
     the code image.
   - Standard Digital Research `LINK` (`[OP]` / PRL output) or the repository's
     two-pass `ORG 0x0100` vs. `ORG 0x0200` builder builds compliant `.PRL`
     files.
2. **Custom SE Runtime Loader (Compatible with Unbanked CP/M 2.2 BDOS)**:
   - Standard CP/M 3 relies on **BDOS Function 59 (`L_OVL` / Load Overlay)** or
     **BDOS Function 60 (RSX — Resident System Extension)** to load relocatable
     modules via the OS.
   - Because `SE.COM` targets **CP/M 2.2** (e.g. RomWBW CP/M 2.2) as well as
     CP/M 3 / Next, it does **not** depend on CP/M 3 BDOS calls. Instead, SE
     streams `.PRL`/`.OVL` files via standard CP/M 2.2 sequential FCB reads
     (`BDOS 15` / `BDOS 20`) and executes its own Z80 relocation loop.
3. **Extended Header Metadata & Direct Hardware Bank Switching**:
   - Standard `.PRL` headers leave bytes `+0x0A..0xFF` unused (`0x00`); SE
     places `PLUGIN_NAME` (`+0x0C..0x1B`) and `CAPABILITIES` (`+0x1C..0x1D`) in
     those reserved header bytes.
   - Rather than using CP/M 3 BIOS `SELMEM` (which is internal to the CP/M 3
     BDOS/BIOS), SE's plugin manager controls the platform banking hardware
     directly (RomWBW HBIOS `BNKCPY`/`BNKCALL` or ZX Spectrum Next MMU
     `NEXTREG 0x50..0x53`) to stage and execute plugins in 32 KB Far RAM banks
     (`0x0000..0x7FFF`) while keeping Upper Common RAM (`0x8000..0xFFFF`)
     mapped.

### 7.3 Plugin Binary Formats (`.PRL` & `.OVL`) & 256-Byte Header Contract

All CP/M-80 plugins (validated by `check_plugin.py`) begin with a mandatory
256-byte header (`0x0000..0x00FF` on disk) followed immediately by the Z80 code
and data payload assembled at origin `0x0100`:
* `+0x01..0x02` (`PROG_SIZE`, 16-bit LE): Code + initialized data byte length.
* `+0x04..0x05` (`BSS_SIZE`, 16-bit LE): Uninitialized BSS bytes required
  immediately following `PROG_SIZE`.
* `+0x07..0x08` (`LOAD_ADDR`, 16-bit LE):
  - `0x0000` for Digital Research CP/M 3 Page-Relocatable (`.PRL`) binaries.
    A bit-packed relocation bitmap of `(PROG_SIZE + 7) // 8` bytes follows the
    code payload on disk (`1` bit per payload byte; MSB first; `1` indicates a
    high-page address byte requiring relocation bias addition).
  - Non-zero fixed execution address (e.g. `0x0100`) for absolute Overlay
    (`.OVL`) binaries (no trailing relocation bitmap).
* `+0x0C..0x1B` (`PLUGIN_NAME`, 16 bytes): Null-padded ASCII identifier
  (e.g. `"ROT13"`, `"WORDCNT"`, `"BEAUTIFY"`, `"FATFS"`).
* `+0x1C..0x1D` (`CAPABILITIES`, 16-bit LE bitmask):
  - `CAP_TPA_EXEC` (`0x0001`): Can execute in the 5,120-byte TPA overlay slot
    (`LINE_STORAGE`) and be sub-allocated by page in shared Far RAM banks.
  - `CAP_FAR_EXEC` (`0x0002`): Executes directly in its Far RAM bank at `0x0100`
    via bank switching (`HB_BNKCALL` / `NEXT_BNKCALL`).
  - `CAP_DOC_MUTATE` (`0x0004`): Mutates active document lines.
  - `CAP_MODAL_UI` (`0x0008`): Renders an interactive modal dialog or screen.
  - `CAP_HAS_ABOUT` (`0x0010`): Implements Action 1 (`ENTRY+3`, About dialog).
  - `CAP_HAS_CONFIG` (`0x0020`): Implements Action 2 (`ENTRY+6`, Config UI).
  - `CAP_SIZE_MASK` (`0x00C0`, bits 7..6): Size class ceiling:
    - `CAP_SIZE_4K` (`0x0000`): $\le 4,096$ B (`16` pages).
    - `CAP_SIZE_8K` (`0x0040`): $\le 8,192$ B (`32` pages; TPA execution allowed
      only if `256 + PROG_SIZE + BSS_SIZE + bitmap <= 5,120` B).
    - `CAP_SIZE_16K` (`0x0080`): $\le 16,384$ B (`64` pages; Far RAM only).
    - `CAP_SIZE_32K` (`0x00C0`): $\le 32,768$ B (`128` pages; Far RAM only).
  - `CAP_HAS_VFS` (`0x0100`): Implements Action 3 (`ENTRY+9`, Headless VFS
    driver dispatcher, e.g. `FATFS.PRL`).

### 7.4 Standard Jump Vector Table at `0x0100`

Every plugin payload begins at `0x0100` (`ENTRY`) with up to four 3-byte Z80
jump vectors (`JP xxxxH` or `SCF ; RET ; NOP` if unimplemented):
* `ENTRY + 0` (`0x0100`, Action 0 — `EXECUTE`): Primary plugin execution entry.
* `ENTRY + 3` (`0x0103`, Action 1 — `ABOUT`): Modal About dialog
  (`CAP_HAS_ABOUT`).
* `ENTRY + 6` (`0x0106`, Action 2 — `CONFIG`): Plugin configuration screen
  (`CAP_HAS_CONFIG`).
* `ENTRY + 9` (`0x0109`, Action 3 — `VFS` / `AUTOLOAD`): Headless VFS request
  dispatcher (`CAP_HAS_VFS`, receiving `DE = VFS_REQ_PKT`) or `PLUGIN.PRL`
  startup autoload hook (`DO_AUTOLOAD_PLUGINS` reading `PLUGIN.CFG`).

Upon entry, `IX` and `IY` point to `PLUGIN_HOST_API` in Upper Common RAM.
On return from Action 0..2, `Carry = 0` indicates success and register `A`
specifies post-execution document state:
* `A = 0`: Clean return (document unmodified).
* `A = 1`: Active line modified in `ACTIVE_LINE_BUF` (host commits line, sets
  `DOC_MODIFIED = 1`, and redraws viewport and status bar).
* `A = 2`: Full document modified via `HOST_COMMIT_LINE` / `HOST_CLEAR_DOCUMENT`
  (host invalidates line cache, constrains cursor, and redraws editor).

### 7.5 Far RAM Bank Borrowing, Page Sub-Allocation & Dual Execution Modes

1. **8-Slot Registry (`PLUGIN_REGISTRY`)**:
   Maintains 8 descriptors of 32 bytes each (`0..7`), recording `PLUGIN_NAME`
   (`+0..15`), `PROG_SIZE` (`+16`), `LOAD_ADDR` (`+18`), `CAPABILITIES` (`+20`),
   `SLOT_STATE` (`+22`), `EXEC_MODE` (`+23`), `FAR_BANK` (`+24`), `BASE_PAGE`
   (`+25`), `SIZE_CLASS` (`+26`), `PAGE_COUNT` (`+27`), and file type
   `'P'`/`'O'` (`+28`).
2. **Dynamic Far RAM Bank Borrowing (`BORROW_NEW_FAR_BANK` /
   `RELEASE_FAR_BANK`)**:
   - Plugins are staged in 32 KB Far RAM banks (`0x0000..0x7FFF`, 128 pages of
     256 bytes each) borrowed dynamically from `EXT_BANK_TABLE` (requiring at
     least 1 bank to remain reserved for document storage while editing).
   - **Sub-Allocated Plugins (`CAP_TPA_EXEC` set)**: Multiple small `.PRL` /
     `.OVL` plugins pack contiguously into shared borrowed Far RAM banks at
     arbitrary 256-byte page boundaries (`BASE_PAGE = 0..127`), maximizing
     memory density.
   - **Dedicated-Bank Plugins (`CAP_FAR_EXEC` without `CAP_TPA_EXEC`, e.g. 16 KB
     and 32 KB plugins)**: Allocated at `BASE_PAGE = 0` (`0x0000` header,
     `0x0100` entry) in an unshared Far RAM bank.
   - When the last plugin occupying a borrowed Far RAM bank is unloaded
     (`UNLOAD_PLUGIN_SLOT`), the bank is automatically returned to
     `EXT_BANK_TABLE` for document line storage.
3. **Dual Execution Modes (`EXEC_PLUGIN_TPA` vs. `EXEC_PLUGIN_FAR`)**:
   - **Mode 0 — TPA Overlay Execution (`EXEC_PLUGIN_TPA`)**:
     Used for sub-allocated TPA plugins (or when `BASE_PAGE != 0`). The host
     flushes dirty editor cache lines (`FLUSH_DIRTY_CACHE`), copies the plugin's
     staged pages (`256`-byte header + code + `.PRL` bitmap) from Far RAM into
     the 5,120-byte `LINE_STORAGE` BSS buffer in Base TPA, applies byte-wise
     page relocation (`RELOC_BIAS = high_byte(LINE_STORAGE + 256) - 1`) via
     `RELOCATE_PRL_LOOP` if `LOAD_ADDR == 0`, calls `LINE_STORAGE + 256 + 3*C`,
     and reloads the editor line cache window upon return.
   - **Mode 1 — Direct Far RAM Bank Execution (`EXEC_PLUGIN_FAR`)**:
     Used when `CAP_FAR_EXEC` is set and the plugin resides at `BASE_PAGE == 0`
     (or has a non-zero fixed `.OVL` `LOAD_ADDR`). The plugin executes directly
     in its 32 KB Far RAM bank at `(BASE_PAGE + 1) * 256 + 3*C` (`0x0100 + 3*C`)
     via `HB_BNKCALL` (`0xFFF9`) or `NEXT_BNKCALL` without evicting
     `LINE_STORAGE` or performing runtime relocation.

### 7.6 Upper Memory `PLUGIN_HOST_API` Table & Cross-Bank Trampolines

Because Far RAM plugins map their own 32 KB bank into `0x0000..0x7FFF` (hiding
Base TPA bank 0), `PLUGIN_HOST_API` and all shared editor state buffers
(`ACTIVE_LINE_BUF`, `PLUGIN_REGISTRY`, `VFS_REQ_PKT`) reside in Upper Common RAM
(`>= 0x8000`), which remains mapped across all banks. Each API function entry in
`PLUGIN_HOST_API` is a `JP` instruction to a cross-bank trampoline
(`TRAMP_*` in `src/core/plugin_tramp.asm`) that switches `0x0000..0x7FFF` back
to `CPM_USER_BANK`, invokes the host routine in `SE.COM`, and restores
`PLUGIN_FAR_BANK` before returning to the plugin:
* `+0x00` (`MAGIC`, 2B): `"SE"` signature (`0x53, 0x45`).
* `+0x02` (`VERSION`, 2B): Host ABI version word (`0x0114` = v1.1.4).
* `+0x04` (`LINE_BUF`, 2B): Pointer to 1,024-byte `ACTIVE_LINE_BUF`.
* `+0x06` (`LINE_LEN`, 2B): Pointer to 16-bit `ACTIVE_LINE_LEN`.
* `+0x08` (`CUR_ROW`, 2B): Pointer to 0-based `CUR_DOC_ROW`.
* `+0x0A` (`TOTAL_LINES`, 2B): Pointer to 16-bit `DOC_TOTAL_LINES`.
* `+0x0C` (`CUR_COL`, 2B): Pointer to 0-based `CUR_COL`.
* `+0x0E..0x11` (4B): `HOST_API_COLS` (`+14`), `HOST_API_CONTEXT` (`+15`,
  `0..6`), `HOST_API_ROWS` (`+16`), `HOST_API_MGR_SLOT` (`+17`).
* `+0x12` (`+18`, `JP TRAMP_CHECKOUT_LINE`): Checkout line `HL` into
  `ACTIVE_LINE_BUF` (returns length in `BC`).
* `+0x15` (`+21`, `JP TRAMP_COMMIT_LINE`): Commit `BC` bytes at `DE` (Common
  RAM) to document row `HL` (overwrites if `HL < DOC_TOTAL_LINES`, appends if
  `HL == DOC_TOTAL_LINES`).
* `+0x18` (`+24`, `JP TRAMP_PUTC`): Emit character in `A` to terminal.
* `+0x1B` (`+27`, `JP TRAMP_PRINT_STR`): Print null/`$`-terminated string at
  `DE` (safely streams byte-by-byte even when `DE` points into Far RAM).
* `+0x1E` (`+30`, `JP TRAMP_GET_KEY`): Blocking key read (returns key in `A`).
* `+0x21` (`+33`, `JP TRAMP_SET_STATUS_MSG`): Display Tier 2 notification modal.
* `+0x24..0x2D` (`+36..+45`, five 2B pointers): `BLOCK_ACTIVE` (`+36`),
  `BLOCK_START_ROW` (`+38`), `BLOCK_END_ROW` (`+40`), `CFG_TAB_WIDTH` (`+42`),
  `PLUGIN_REGISTRY` (`+44`).
* `+0x2E` (`+46`, `JP TRAMP_CHECK_KEY`): Non-blocking console key ready poll.
* `+0x31` (`+49`, `JP TRAMP_CLEAR_DOCUMENT`): Reset document to empty state.
* `+0x34` (`+52`, `JP TRAMP_LOCATE_RC`): Position cursor at 1-based `H=Row,
  L=Col`.
* `+0x37` (`+55`, `JP TRAMP_LOAD_PLUGIN`): Load `.PRL`/`.OVL` named at `DE`.
* `+0x3A` (`+58`, `JP TRAMP_UNLOAD_SLOT`): Unload plugin slot `A` (`0..7`).
* `+0x3D` (`+61`, `JP TRAMP_REDRAW_BASE`): Repaint underlying screen for
  context `A` (`0..6`).
* `+0x40` (`+64`, `JP TRAMP_OPEN_PLUGIN_UI`): Open interactive `.PRL`/`.OVL`
  directory browser to load a plugin.
* `+0x43` (`+67`, `JP TRAMP_SAVE_PLUGIN_CFG`): Write 128-byte buffer at `DE` to
  `PLUGIN.CFG`.
* `+0x46` (`+70`, `JP TRAMP_LOAD_PLUGIN_CFG`): Read 128-byte `PLUGIN.CFG` into
  buffer at `DE`.
* `+0x49` (`+73`, `JP TRAMP_RENDER_STATUS_BAR`): Render Universal Status Bar.
* `+0x4C` (`+76`, `JP TRAMP_HIDE_CURSOR`) & `+0x4F` (`+79`,
  `JP TRAMP_SHOW_CURSOR`): Hide/show hardware terminal cursor.

### 7.7 Linux 64-Bit Plugin Mechanism (`x86_64` & `ARM64` / `aarch64`)

On 64-bit Linux systems (`x86_64` and `ARM64` / `aarch64`), all `SE` port
implementations (C `se-linux`, Python `se-py`, Rust `se-rs`, Ada `se-ada`,
Algol 68 `se-a68`, Pascal `se-pas`, etc.) include a **builtin Plugin Manager**
(reported as `Plugin System: Builtin` on the Splash Screen and locked on in
Configure / `SE.CFG`).

To allow any 64-bit host implementation to load plugins written in any of these
languages interchangeably on the same CPU architecture (`x86_64` or `aarch64`),
the primary plugin mechanism standardizes on **POSIX dynamic shared objects
(`.so` ELF libraries loaded via `dlopen` / `dlsym` / `dlclose`)** exposing a
canonical **64-bit System V C ABI**. Where a language or runtime cannot emit or
consume a `dlopen`-compatible shared library, a **language-specific fallback
plugin mechanism** is permitted.

#### 1. Primary Cross-Language Mechanism: `dlopen()` Shared Libraries (`.so`)
Every compiled or C-ABI-capable language on 64-bit Linux can both load `.so`
shared libraries (via `dlopen`/`dlsym`) and export unmangled System V C ABI
symbols:
* **C (`gcc` / `clang`)**: Native `-shared -fPIC` `.so` generation and
  `<dlfcn.h>` `dlopen()` / `dlsym()` host loading.
* **Rust (`rustc` / `cargo`)**: Builds plugins as `crate-type = ["cdylib"]` with
  `#[no_mangle] pub extern "C" fn ...` and `#[repr(C)]` structs; loads `.so`
  plugins in `se-rs` via `libloading` / `dlopen`.
* **Python (`CPython`)**: `se-py` loads native `.so` plugins directly via
  `ctypes.CDLL` or `cffi` (calling `dlopen` under the hood) and passes
  `ctypes.CFUNCTYPE` callback pointers in the `se_host_api_t` struct. Python
  plugins can also be compiled to `.so` via **Cython** (`cython --embed` / PIC
  shared object) or wrapped by a thin C/CPython bridge `.so`.
* **Ada (`GNAT`)**: Exports and imports C ABI symbols and structs via
  `pragma Export (C, ...)` / `pragma Import (C, ...)` and `pragma Convention
  (C, ...)` (`Interfaces.C` / `Interfaces.C.Pointers`), linking as a relocatable
  shared library (`LIBRARY_TYPE=relocatable`).
* **Algol 68 (`a68g` / `ga68` GCC front-end)**: GNU Algol 68 (`ga68`) and C-FFI
  wrappers compile position-independent code (`-fPIC -shared`) and bind to the C
  ABI descriptor and `dlopen` symbols via thin C thunks.
* **Pascal (`Free Pascal` / `fpc`)**: Compiles shared libraries via the
  `library` keyword (`-Cg` / PIC enabled) with `cdecl; export;` routines and
  `packrecords C` records, and loads `.so` plugins via the `dynlibs` unit
  (`LoadLibrary` / `GetProcedureAddress`).

#### 2. Canonical 64-Bit C ABI Contract (`se_plugin_abi.h`)
A compliant 64-bit `.so` plugin exports a single well-known symbol
`se_plugin_get_descriptor` resolved via `dlsym(handle,
"se_plugin_get_descriptor")`:
* **Plugin Descriptor (`se_plugin_desc_t`, `#[repr(C)]`)**:
  - `uint32_t magic`: `"SEPL"` (`0x4C504553` LE).
  - `uint16_t abi_version`: `0x0114` (matches the functional host API contract).
  - `uint16_t capabilities`: Same semantic bitmask (`CAP_DOC_MUTATE`,
    `CAP_MODAL_UI`, `CAP_HAS_ABOUT`, `CAP_HAS_CONFIG`, `CAP_HAS_VFS`). Memory
    size ceiling bits (`CAP_TPA_EXEC`, `CAP_FAR_EXEC`, `CAP_SIZE_*`) are ignored
    on 64-bit virtual-memory systems.
  - `char name[16]`: Null-terminated ASCII plugin name (e.g. `"ROT13"`).
  - Entry point function pointers
    (`int (*)(const se_host_api_t *host, void *arg)`):
    - `execute`: Action 0 primary execution (returns `0` clean, `1` active line
      modified, `2` full document modified, `< 0` error).
    - `about`: Action 1 modal About dialog (`NULL` if unimplemented).
    - `config`: Action 2 plugin configuration UI (`NULL` if unimplemented).
    - `vfs_dispatch`: Action 3 VFS request dispatcher (`NULL` if unimplemented).
* **Host API Table (`se_host_api_t`, `#[repr(C)]`)**:
  Passed by pointer (`const se_host_api_t *host`) to every plugin entry point,
  providing 64-bit C function pointers and state accessors strictly mirroring
  the CP/M-80 `PLUGIN_HOST_API` semantics (`checkout_line`, `commit_line`,
  `clear_document`, `putc`, `print_str`, `get_key`, `check_key`, `locate_rc`,
  `set_status_msg`, `redraw_base`, `render_status_bar`, `hide_cursor`,
  `show_cursor`, plus pointers to `active_line_buf`, `active_line_len`,
  `cur_row`, `cur_col`, `total_lines`, and block selection state).
* **Architecture Neutrality (`x86_64` vs. `aarch64`)**:
  Because the interface uses fixed-width integer types (`uint16_t`, `uint32_t`,
  `size_t`) and standard System V AMD64 / AAPCS64 calling conventions, the same
  source-level ABI definition works identically on 64-bit x86 (`x86_64`) and
  64-bit ARM (`aarch64`), with `.so` binaries interchangeable across all host
  languages compiled for the same CPU target.

#### 3. Language-Specific Fallback Plugin Mechanisms
When a target environment or language implementation cannot use `dlopen` shared
libraries (for example, pure interpreted `se-py` loading `.py` scripts without a
C compiler, or an interpreter without native C FFI support), the builtin Plugin
Manager may support a **language-specific plugin mechanism** alongside or in
place of `.so` loading:
* **Python Native Modules (`.py`)**: Imported dynamically by `se-py` via
  `importlib.util.spec_from_file_location()`, exposing an `SEPlugin` class or
  module-level `execute(host)` / `about(host)` / `config(host)` functions.
* **Subprocess / IPC Pipe Fallback (Universal Fallback for Interpreted Ports)**:
  For languages or runtimes where in-process `dlopen` FFI is unavailable (such
  as standalone interpreted Algol 68 `a68g` scripts), the host can invoke
  external plugin executables over a structured stdin/stdout RPC pipe framing
  the `PLUGIN_HOST_API` calls.
* **Non-Interchangeability Note**: While `dlopen` `.so` plugins compiled to the
  64-bit System V C ABI are interchangeable across C, Rust, Python (`ctypes`),
  Ada, Algol 68 (`ga68`), and Free Pascal on the same CPU architecture (`x86_64`
  or `aarch64`), language-specific fallback plugins (such as pure `.py` modules)
  are specific to their respective language runtime and are not interchangeable
  with CP/M-80 `.PRL`/`.OVL` or CP/M-86 `.PRL`/`.OVL` plugins.

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
   - `block.inc`: Block anchor coordinates, selection state, and in-place block
     operations.
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

