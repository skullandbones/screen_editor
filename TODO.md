# SE.COM — Development To-Do & Roadmap (Post v1.0.0)

This file tracks pending enhancement tasks, architectural optimizations, and
upcoming milestones for SE.COM post v1.0.0. All completed v1.0.0 development
tasks have been archived.

---

## 1. Tooling & Environment Enhancements

*(No pending tasks. Task 1.1 completed in v1.0.0).*

---

## 2. BUGS

### 2.36 [Reserved for Next Bug Report]
- [ ] Reserved to prevent duplicate bug numbering (Bugs 2.1–2.35 resolved
  in v1.0.0).

---

## 3. RAM Headroom & Memory Optimization

### 3.1 ~~Relocate Clipboard to Far RAM (+1.5 KB TPA)~~
- [ ] ~~Move `COPY_BLK_BUF` (1,024 B), `COPY_TAIL_BUF` (256 B), and
  `COPY_SLOTS_BUF` (256 B) from Common RAM into Far RAM Bank 0 or a
  dedicated Far RAM buffer.~~
- [ ] ~~Expand clipboard capacity from 1 KB up to 8 KB / 16 KB in Far RAM.~~
- *Reason*: Copy block must work without using Far RAM.

### 3.2 Right-Size Workspace Scratch Buffers (+1.5 KB TPA)
- [ ] Reduce `ACTIVE_LINE_BUF` (1,024 B) and `SPLIT_LINE_TEMP` (1,024 B) to
  256 bytes to match maximum line width (120 columns).

### 3.3 ~~Modularize Auxiliary Screens into Overlays (+3.0 KB to +4.0 KB TPA)~~
- [ ] ~~Convert Memory Info screen (`'m'`) into `plugins/MEMINFO.OVL`.~~
- [ ] ~~Convert Configuration Manager (`'c'`) into `plugins/CONFIG.OVL`.~~
- [ ] ~~Move About screen (`'a'`) into `plugins/HELP.OVL` or
  `plugins/ABOUT.OVL`.~~
- *Reason*: These screens must work without using Far RAM.

### 3.4 Optimize Working Cache (`LINE_STORAGE`) (+1.0 KB to +2.0 KB TPA)
- [ ] Evaluate reducing `CACHE_SIZE_LINES` from 40 to 32 lines (+1,024 B) or
  24 lines (+2,048 B) in 80x24 mode.

### 3.5 Relocate FATFS VFS Path Parsing into `FATFS.PRL` (+2.5 KB to +3.5 KB)
- [ ] Move FAT path string parser, unit mappings, and hook dispatchers from
  `SE.COM` core into the 32 KB Far RAM `FATFS.PRL` binary.
  - Retain a lightweight 128-byte trampoline in `SE.COM`.

---

## 4. UI/UX Design System Audits & Enhancements (`docs/UI_UX_DESIGN.md`)

### 4.1 Audit Column 0 Tilde Discipline on File & Block Screens
- [ ] Verify column 0 tildes (`~`) are rendered on all unallocated margin
  rows across Open File, Save File, and Block selection screens.
  - *Identified Bug*: Bug 2.5 (Open, Save, and Block screens missing top
    margin tildes).
- *Justification* (`docs/UI_UX_DESIGN.md` Section 1.3):
  > *"Tildes in column 0 are used on all screens without exception
  > (including file open, save, and block screens)."*

### 4.2 Audit Center Justification in Remaining Query Pop-ups
- [ ] Audit all Tier 2 query pop-ups to ensure text lines (description, query,
  and options) are centre justified with space-separated options.
  - *Identified Bugs*: Bug 2.7 (Option delimiters `/` in pop-up prompts),
    Bug 2.8 (Non-ESC `[Q]uit` cancellation), and Bug 2.10 (Left-justified text
    and non-standard dismissals in plugin pop-ups).
- *Justification* (`docs/UI_UX_DESIGN.md` Section 1.4 & 1.6):
  > *"Query pop-up format shall have a title line box, the pop-up body first
  > line shall be the description, then the query line followed by the query
  > options. All text is centre justified."*
  >
  > *"Pop-up decision options shall not have any delimiters such as `/` and
  > `|` and instead should have sufficient spaces to separate the options
  > nicely (e.g. `[Y]es   [N]o   [ESC]=Cancel`)."*

### 4.3 Verify Single-Level Pop-up Visibility Across Nested Dialogs
- [ ] Verify parent pop-ups are hidden before child pop-ups display and
  correctly redrawn when child pop-ups are dismissed.
  - *Identified Bug*: Bug 2.11 (Child pop-ups rendered over unhidden parent
    pop-ups in plugin manager).
- *Justification* (`docs/UI_UX_DESIGN.md` Section 1.5):
  > *"When a child pop-up is to be shown, the parent pop-up shall be taken
  > off the screen (hidden) and the parent pop-up is redrawn when the child
  > pop-up no longer exists (child pop-up no longer shown)."*

---

## 5. Test Automation & Verification

### 5.1 Drunken Monkey Chaos Testing (`tests/test_drunken_monkey.py`)
- [ ] Run long-duration chaos sessions with randomized keystrokes.
- [ ] Verify stability across memory profiles (`128k`, `512k`, `preserve`,
  `overwrite`, `hibernate`) and plugin states (`autoload`, `disabled`).

### 5.2 Automated Headroom & Footprint Regression Tracking
- [ ] Track TPA headroom margins and plugin slot usage across commits via
  `python3 check_tpa.py SE.COM`.

---

## 6. Post-v1.0.0 Milestones & Roadmap

- [ ] Define feature scope and architectural targets for SE.COM v1.1.0 release.
- [ ] Milestone: Modularize `se.asm` into functional sub-systems and port to
  ZX Spectrum Next (supporting both Native Next and CP/M on the Next,
  detailed in Section 7).

---

## 7. Modular Architecture Refactoring & ZX Spectrum Next Port Plan

### 7.1 Target Architecture & Port Variants
The refactoring defines a clean separation between core editor logic and
platform hardware abstraction, targeting three primary operating profiles:
- **Profile 1: Standard CP/M 2.2 / 3.0** (RomWBW / RC2014 / Standard TPA):
  Standard CP/M `.COM` binary using BDOS calls, VT100/ANSI terminal over
  serial/console, RomWBW HBIOS bank switching, and BDOS FCB storage.
- **Profile 2: CP/M on ZX Spectrum Next** (NextCPM / CP/M 2.2 / CP/M Plus):
  CP/M `.COM` binary running inside the Next's CP/M environments (e.g.
  NextCPM by Garry Lancaster). Uses CP/M TPA and BDOS vectors ($0005), but
  leverages Next-adapted console drivers (NextCPM 80-column text mode,
  VT52/ANSI, or direct screen RAM), Next keyboard mapping, and NextCPM
  banked memory extensions if available.
- **Profile 3: Native ZX Spectrum Next** (NextZXOS / ESXDOS / Standalone):
  Native Next binary running without CP/M. Directly leverages Next hardware:
  hardware tile/text mode (80x25 or 80x32) or Layer 2 (640x256), Next MMU
  8KB banking (NextRegs `0x50`–`0x57`) across 1MB/2MB SRAM, and NextZXOS
  filesystem API (`RST 08h`). Packaged as both a standalone `SE.NEX` and a
  `/dot` command (e.g. `.se <filename>`).

### 7.2 Architecture & Header API Strategy
- [ ] Define sub-system API header standards (`include/*.inc`) with clear
  register calling conventions (inputs, outputs, clobbered registers).
- [ ] Establish strict data encapsulation so platform-agnostic core logic
  never accesses platform-specific hardware registers or BDOS calls directly.
- [ ] Maintain deterministic memory layout across modules to preserve TPA
  headroom margins on CP/M while allowing flexible banking on other targets.

### 7.3 Sub-system API Header Specifications (`include/`)
- [ ] `include/config.inc`: Global editor constants, keycodes, geometry,
  line limits, and configuration defaults.
- [ ] `include/hal.inc`: Hardware Abstraction Layer API defining console,
  keyboard, memory banking, and storage function signatures.
- [ ] `include/buffer.inc`: Document buffer engine API (line cache indexing,
  line split/join, active line unpacking, virtual slot mapping).
- [ ] `include/editor.inc`: Core editor command dispatch API, cursor
  movement, character insertion, deletion, and word-wrap primitives.
- [ ] `include/block.inc`: Block selection, copy/cut/paste, and clipboard
  buffer management API.
- [ ] `include/search.inc`: Text search, replace, and case-sensitivity API.
- [ ] `include/ui.inc`: Modal dialog engine, Tier 1 status alerts, Tier 2
  query pop-ups, status bar rendering, and frame styling API.
- [ ] `include/file_io.inc`: High-level file open, save, backup, and
  directory enumeration API.
- [ ] `include/plugin.inc`: Far RAM plugin manager, slot allocation table,
  and Upper Memory Host API vector definitions (`PLUGIN_HOST_API`).
- [ ] `include/beautify.inc`: Z80 assembly formatter & alignment engine API.

### 7.4 Platform Abstraction Layer (HAL / PAL) Architecture
- [ ] Decouple all BDOS calls, VT100 ANSI sequences, and RomWBW HBIOS bank
  switching from core editor logic into platform-specific HAL modules.
- [ ] Implement Standard CP/M Platform Layer (`hal/cpm/`):
  - `hal/cpm/hal_cpm_console.asm`: VT100 / ANSI terminal escape sequences,
    cursor positioning, attribute styling, and BDOS console character I/O.
  - `hal/cpm/hal_cpm_memory.asm`: RomWBW HBIOS 512K bank switching and CP/M 3
    banked memory drivers for Far RAM paging.
  - `hal/cpm/hal_cpm_storage.asm`: BDOS FCB operations, CP/M drive & user
    area switching, and swap file (`$$$SE$$$.SWP`) random record I/O.
- [ ] Implement CP/M on ZX Spectrum Next Platform Layer (`hal/next_cpm/`):
  - `hal/next_cpm/hal_nextcpm_console.asm`: NextCPM-optimized console driver
    utilizing NextCPM 80-column display modes, fast screen updates, and
    Next terminal escape codes.
  - `hal/next_cpm/hal_nextcpm_keyboard.asm`: Key translation adapter for
    Next keyboard layouts and extra function/cursor keys under NextCPM.
  - `hal/next_cpm/hal_nextcpm_memory.asm`: Far RAM paging adapter using
    NextCPM banked memory services or direct Next MMU paging when permitted
    by the host CP/M environment.
  - `hal/next_cpm/hal_nextcpm_storage.asm`: Standard CP/M BDOS FCB storage
    operating across NextCPM virtual and physical SD card drive mappings.
- [ ] Implement Native ZX Spectrum Next Platform Layer (`hal/next_native/`):
  - `hal/next_native/hal_next_console.asm`: Direct hardware text mode driver
    (80x25 or 80x32 using Next tile/text layer or Layer 2 640x256 font
    rendering) providing instant flicker-free updates without terminal
    overhead.
  - `hal/next_native/hal_next_keyboard.asm`: Native Next matrix and PS/2
    keyboard scanner supporting dedicated arrow keys, PageUp, PageDown,
    Home, and End.
  - `hal/next_native/hal_next_memory.asm`: Next MMU memory management via
    NextRegs `0x50`–`0x57` mapping 8KB SRAM pages into upper slots
    ($8000–$FFFF or $4000–$7FFF) to access 1024 KB / 2048 KB on-board SRAM.
  - `hal/next_native/hal_next_storage.asm`: NextZXOS / ESXDOS storage driver
    via `RST 08h` (`M_GETSETDRV`, `F_OPEN`, `F_READ`, `F_WRITE`, `F_CLOSE`,
    `F_SEEK`, `F_OPENDIR`) supporting native FAT16/FAT32 paths on SD card.

### 7.5 Core Editor Sub-system Decomposition (`src/core/`)
- [ ] `src/core/buffer.asm`: Extract line cache (`LINE_STORAGE`), line split
  and join operations, and virtual slot index tables from `se.asm`.
- [ ] `src/core/memory.asm`: Extract virtual memory paging coordinator,
  cache eviction logic, and swap page tracking.
- [ ] `src/core/editor.asm`: Extract interactive key dispatch table, cursor
  navigation, text editing primitives, and auto-indent.
- [ ] `src/core/block.asm`: Extract block highlight calculations, clipboard
  buffering, block cut/copy/paste, and block indentation.
- [ ] `src/core/search.asm`: Extract search string matching, forward find,
  and search-and-replace loop.
- [ ] `src/core/ui_render.asm`: Extract screen repaint engine, status bar
  rendering (`STR_STATUS_PREFIX`), and column 0 tilde margin discipline.
- [ ] `src/core/ui_modal.asm`: Extract Tier 1 notification pop-ups, Tier 2
  query pop-ups, centered frame drawing, and button selectors.
- [ ] `src/core/ui_browser.asm`: Extract file selection and directory
  browser modal screens.
- [ ] `src/core/config.asm`: Extract `SE.CFG` reader, parser, serializer, and
  default settings table.
- [ ] `src/core/plugin_mgr.asm`: Extract PRL/OVL relocation loader, Far RAM
  slot manager, and Host API trampoline table.
- [ ] `src/core/beautify.asm`: Extract Z80 code beautifier and column
  alignment subsystem (`DO_CTRL_Y_BEAUTIFY`).

### 7.6 Target Coordinators & Build Pipeline
- [ ] `src/se.asm`: Refactor top-level Standard CP/M coordinator to include
  headers (`include/*.inc`), CP/M HAL (`hal/cpm/*.asm`), and core
  modules (`core/*.asm`).
- [ ] Verify binary invariance: Ensure modular CP/M build matches original
  monolithic `SE.COM` functionality and preserves TPA headroom (+2,048 B).
- [ ] `src/se_next_cpm.asm`: Create top-level CP/M on Next coordinator
  combining NextCPM HAL (`hal/next_cpm/*.asm`) with core modules.
  Produces `SE_NEXT.COM` for deployment under NextCPM.
- [ ] `src/se_next.asm`: Create top-level Native ZX Spectrum Next coordinator
  combining Next Native HAL (`hal/next_native/*.asm`) with core modules.
- [ ] Create Next build targets in `Makefile` to produce:
  - `SE_NEXT.COM`: CP/M executable tailored for NextCPM environment.
  - `SE.NEX`: Standalone ZX Spectrum Next executable runnable from NextZXOS
    browser (setting CPU speed to 14/28 MHz and configuring MMU).
  - `.se` / `SE`: NextZXOS dot command installed into `/dot` on SD card
    allowing direct CLI invocation (e.g. `.se readme.txt`).
- [ ] Establish automated testing for Next targets using CSpect or ZEsarUX
  emulator harnesses.
