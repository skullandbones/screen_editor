# SE.COM — Development To-Do & Roadmap (Post v1.0.0)

This file tracks pending enhancement tasks, architectural optimizations, and
upcoming milestones for SE.COM post v1.0.0. All completed v1.0.0 development
tasks have been archived.

---

## 1. Tooling & Environment Enhancements

*(No pending tasks. Task 1.1 completed in v1.0.0).*

---

## 2. Bug Tracking & Known Issues by Build Variant

This section tracks open defects, platform-specific anomalies, edge cases,
and verification tasks categorized by operating profile and build variant.
Completed bug reports from v1.0.0 (Bugs 2.1–2.35) and post-v1.0.0 (Bug 2.36)
have been resolved and archived.

### 2.1 Profile 1: Standard CP/M 2.2 / 3.0 (`SE.COM`)
- **Target Platform**: Standard CP/M 2.2 / 3.0 (RomWBW v3.6.0+, RC2014, SC126,
  Zeta 2, standard 64KB TPA).
- **Core Technology**: 100% Z80 assembly (`src/se.asm`), RomWBW HBIOS 512KB
  Far RAM banking (`RST 08H`), BDOS console & FCB file storage.
- **Build Target**: `make SE.COM` (or `make`).
- **Status**: Stable / Production.
- **Active Defects & Issue Tracking**:
  - [ ] *(No active bugs open; report new Profile 1 defects here).*

### 2.2 Profile 2: CP/M on ZX Spectrum Next (`SE_NEXT.COM`)
- **Target Platform**: NextCPM / CP/M 2.2 / CP/M Plus on ZX Spectrum Next.
- **Core Technology**: Z80 assembly (`src/se_next_cpm.asm`), Next-adapted
  console (80-column text mode), Next keyboard matrix mapping, NextCPM banked
  memory extensions.
- **Build Target**: `make se-next-cpm` (produces `SE_NEXT.COM`).
- **Status**: Active / Verification in Progress.
- **Active Defects & Issue Tracking**:
  - [ ] *(No active bugs open; report new Profile 2 defects here).*

### 2.3 Profile 3: Native ZX Spectrum Next (`SE.NEX` & `.se` Dot Command)
- **Target Platform**: NextZXOS / ESXDOS standalone browser executable and
  `/dot` command on SD card.
- **Core Technology**: Z80 assembly (`src/se_next.asm`), native Next hardware
  tile/text layer (80x25 / 80x32), NextRegs MMU 8KB SRAM banking (1MB/2MB),
  NextZXOS filesystem API (`RST 08h`).
- **Build Target**: `make se-next-native` (produces `SE.NEX` and `.se`).
- **Status**: Active / Verification in Progress.
- **Active Defects & Issue Tracking**:
  - [ ] *(No active bugs open; report new Profile 3 defects here).*

### 2.4 Profile 4: Linux Native C Profile (`se-linux`)
- **Target Platform**: Linux PC / Workstation (`x86_64`) and Raspberry Pi 4/5
  (`aarch64`).
- **Core Technology**: Portable C core modules (`src/core/*.c`), POSIX
  Hardware Abstraction Layer (`src/hal/linux/`), `termios` raw mode ANSI
  terminal I/O, dynamic heap buffer management.
- **Build Target**: `make se-linux` (verified via `make test-linux`).
- **Status**: Active / Look & Feel Conformance Audit Complete.
- **Active Defects & Issue Tracking (LOOK_AND_FEEL_SPEC.md Conformance)**:
  - [x] **Bug 2.4.1: Status Bar Layout Inversion & Missing Canonical Fields**:
    - *Reference*: `docs/LOOK_AND_FEEL_SPEC.md` Section 4.3.
    - *Issue*: `render_status_bar` in `src/core/ui_render.c` outputs custom
      format `" SE v1.1.0 | Ln %-5u/%-5u Col %-3u | %s%s | Free: %4u KB"`.
    - *Required Fix*: Conform to canonical 5-field layout:
      `| {name}{mod} | {geom} | {fmt} | ^K: Editor keys | Line ... Col ... |`.
      Add Geometry (`80x24 |`), Format (`Linux |` / `CPM   |`), Pan indicator
      (`[Pan +40]`), Block indicator (`[SEL]` / `[BLK LOCK]`), and center-pad
      across full terminal width.
  - [ ] **Bug 2.4.2: Missing Universal Status Bar on Non-Document Workspaces**:
    - *Reference*: `docs/LOOK_AND_FEEL_SPEC.md` Section 4.1, 7.2, 7.3, 7.4.
    - *Issue*: Non-document screens (`show_splash_screen`, `show_about_screen`,
      `show_config_screen`, `show_mem_info_screen`) in `src/core/ui_render.c`
      wipe the screen and fail to render the status bar on `HOST_ROWS`.
    - *Required Fix*: Guarantee universal status bar presence on `HOST_ROWS`
      across all Tier 1 screens and behind Tier 2 pop-up dialogs.
  - [ ] **Bug 2.4.3: Status Bar Squatting Anti-Pattern for Transient Alerts**:
    - *Reference*: `docs/LOOK_AND_FEEL_SPEC.md` Section 4.4, 11.1.
    - *Issue*: `ui_render.c:158` writes transient alerts (`g_status_msg`)
      directly into the status bar, clobbering persistent document metadata.
    - *Required Fix*: Remove status bar message overwriting (Anti-Pattern #1).
      Route all status events (Save Complete, Search Failed, etc.) to Tier 2
      centered modal pop-up boxes (`show_notification` / Archetype A).
  - [ ] **Bug 2.4.4: Arrow Key & WordStar Diamond Keybinding Misalignment**:
    - *Reference*: `docs/LOOK_AND_FEEL_SPEC.md` Section 10.
    - *Issue*: In `src/hal/linux/hal_linux_keyboard.c`, arrow keys decode to
      `KEY_CTRL_E` (Up), `KEY_CTRL_X` (Down), `KEY_CTRL_S` (Left), and
      `KEY_CTRL_D` (Right). In `src/core/editor.c:414`, `KEY_CTRL_E` dispatches
      to `cursor_end()`, `KEY_CTRL_X` dispatches to `do_move_block()`, and
      `KEY_CTRL_S` dispatches to `file_save()`. Up moves to End-of-Line,
      Down cuts block, and Left saves file. `cursor_up()` and `cursor_down()`
      are completely missing from `editor_handle_key`.
    - *Required Fix*: Implement distinct keycodes for navigation vs commands,
      bind `cursor_up()` and `cursor_down()`, and restore authentic WordStar
      diamond navigation and ANSI cursor key parity.
  - [ ] **Bug 2.4.5: Non-Functional Horizontal Panning Engine & Line Barrier**:
    - *Reference*: `docs/LOOK_AND_FEEL_SPEC.md` Section 6.1, 6.2.
    - *Issue*: `g_horiz_pan_offset` in `src/core/editor.c` is never adjusted
      when cursor moves beyond column 79. `MAX_INPUT_LINE_CHARS` is 1000 in
      `config.h` instead of the strict 120-character line barrier.
    - *Required Fix*: Implement horizontal pan quantum (+40 columns) shift
      logic (`pan_col` = 40 or 80) and enforce `MAX_LINE = 120` limit.
  - [ ] **Bug 2.4.6: Tier 1 Centering & Column 0 Tilde Margin Discipline**:
    - *Reference*: `docs/LOOK_AND_FEEL_SPEC.md` Section 5.2, 7.1, 7.2.
    - *Issue*: Splash and help screens use top-aligned fixed coordinates with
      ASCII banner borders and lack column 0 tilde (`~`) margin rows.
    - *Required Fix*: Apply mathematical 1-based centering formulas and fill
      margin rows down to row `HOST_ROWS - 1` with `~` in column 0.
  - [ ] **Bug 2.4.7: Tier 2 Modal Framing, Centering & Archetype Invariance**:
    - *Reference*: `docs/LOOK_AND_FEEL_SPEC.md` Section 8.1, 8.2, 8.3.
    - *Issue*: `src/core/ui_modal.c` places titles on top border without
      title divider line (`+---+`), uses off-by-one centering calculation,
      permits quitting confirmation modals via `q`/`Q` instead of solely `ESC`,
      and omits bracket framing `[ text ]` on text input prompts.
    - *Required Fix*: Implement canonical Archetypes A, B, C, D with title
      dividers, 1-based centering, and strict key dismissal rules.

### 2.5 Profile 5: CP/M-86 Profile (`SE.CMD`)
- **Target Platform**: 8086 / 8088 Personal Computer & CP/M-86 environments.
- **Core Technology**: Portable C core modules (`src/core/*.c`), CP/M-86
  Hardware Abstraction Layer (`src/hal/cpm86/`), segmented 8086 memory
  allocation, CP/M-86 BDOS console and FCB file system calls.
- **Build Target**: `make se-cpm86` (produces `SE.CMD`).
- **Status**: Implementation Pending (Roadmap Item 7.3).
- **Active Defects & Issue Tracking**:
  - [ ] *(No active bugs open; implementation pending).*

### 2.6 Profile 6: Linux Native Rust Profile (`ports/rust/`)
- **Target Platform**: Linux PC / Workstation (`x86_64-unknown-linux-gnu`) and
  Raspberry Pi 4/5 (`aarch64-unknown-linux-gnu`).
- **Core Technology**: Idiomatic Rust implementation (`ports/rust/`),
  terminal engine (`crossterm` / raw `termios`), piece table or line-slot
  cache buffer, WordStar / SE keybindings, `SE.CFG` parser.
- **Build Target**: `cargo build --release` (or `make se-rust`).
- **Status**: Implementation Pending (Roadmap Item 7.4).
- **Active Defects & Issue Tracking**:
  - [ ] *(No active bugs open; implementation pending).*

### 2.7 Profile 7: Linux Native Python Profile (`ports/python/`)
- **Target Platform**: Linux PC / Workstation (`x86_64`) and Raspberry Pi 4/5
  (`aarch64`) running Python 3.10+.
- **Core Technology**: Python 3 standard library package (`ports/python/se`),
  `termios` / `tty` raw terminal driver, object-based line buffer paging,
  `SE.CFG` reader/writer, modular Python plugins.
- **Build Target**: `make se-py` (verified via `make test-py`).
- **Status**: Active / Fully Tested.
- **Active Defects & Issue Tracking**:
  - [ ] *(No active bugs open; report new Profile 7 defects here).*

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

### 3.6 Right-Size / Overlay Clipboard Buffers (+0.75 KB to +1.5 KB TPA)
- [ ] Reduce `COPY_BLK_BUF` from 1,024 B to 256 B to match maximum line
  length (+768 B).
- [ ] Alternatively, overlay clipboard onto `LINE_STORAGE` during block
  operations without using Far RAM (+1,536 B).

### 3.7 Consolidate Transient File Control Blocks (+144 B TPA)
- [ ] Unify mutually exclusive FCBs (`DIR_TEMP_FCB`, `SHARED_TEMP_FCB`,
  `INSERT_FCB`, `PLUGIN_FCB`) into a single 36-byte `SCRATCH_FCB`.

### 3.8 Unify Modal Pop-up Message Buffers (+150 B TPA)
- [ ] Share a single 64-byte `MODAL_MSG_BUF` across replace, block, and
  plugin modal dialog formatters.

### 3.9 Dynamic Working Cache Sizing for 80x24 Mode (+2.0 KB TPA)
- [ ] Dynamically size `LINE_STORAGE` to 24 lines (3,072 B) when
  operating in 80x24 mode to recover +2,048 B of TPA headroom.

### 3.10 Banked / Streamed Static UI Strings (+1.5 KB to +2.5 KB TPA)
- [ ] Relocate static Help, About, and Memory screen strings to Far RAM
  Bank 0 or stream on demand when displayed.

---

## 4. Test Automation & Verification

### 4.1 Drunken Monkey Chaos Testing (`tests/test_drunken_monkey.py`)
- [ ] Run long-duration chaos sessions with randomized keystrokes.
- [ ] Verify stability across memory profiles (`128k`, `512k`, `preserve`,
  `overwrite`, `hibernate`) and plugin states (`autoload`, `disabled`).

### 4.2 Automated Headroom & Footprint Regression Tracking
- [ ] Track TPA headroom margins and plugin slot usage across commits via
  `python3 check_tpa.py SE.COM`.

---

## 5. Post-v1.0.0 Milestones & Roadmap

- [x] Define feature scope and architectural targets for SE.COM v1.1.0 release.
- [x] Milestone: Modularize `se.asm` into functional sub-systems and port to
  ZX Spectrum Next (supporting both Native Next and CP/M on the Next,
  detailed in Section 6).


---

## 6. Modular Architecture Refactoring & ZX Spectrum Next Port Plan

### 6.1 Target Architecture & Port Variants
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

### 6.2 Architecture & Header API Strategy
- [ ] Define sub-system API header standards (`include/*.inc`) with clear
  register calling conventions (inputs, outputs, clobbered registers).
- [ ] Establish strict data encapsulation so platform-agnostic core logic
  never accesses platform-specific hardware registers or BDOS calls directly.
- [ ] Maintain deterministic memory layout across modules to preserve TPA
  headroom margins on CP/M while allowing flexible banking on other targets.

### 6.3 Sub-system API Header Specifications (`include/`)
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

### 6.4 Platform Abstraction Layer (HAL / PAL) Architecture
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

### 6.5 Core Editor Sub-system Decomposition (`src/core/`)
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

### 6.6 Target Coordinators & Build Pipeline
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

## 7. Multi-Language & Multi-Platform Profiles

### 7.1 C Semantic Equivalent Implementations (Drop-in Replacement Modules)
- [x] Write C semantic equivalent implementations for each modular Z80 assembly
  component (`src/core/*.asm`):
  - `src/core/buffer.c`: Document line cache, slot indexing, split/join logic.
  - `src/core/memory.c`: Virtual slot allocation, cache eviction, swap paging.
  - `src/core/editor.c`: Command dispatch, cursor navigation, text editing.
  - `src/core/block.c`: Block markers, cut/copy/paste, indentation adjustment.
  - `src/core/search.c`: String search, case-sensitivity, replace loop.
  - `src/core/ui_render.c`: Screen refresh, status bar, column 0 tilde margin.
  - `src/core/ui_modal.c`: Tier 1 alerts, Tier 2 query modals, frame borders.
  - `src/core/ui_browser.c`: File selection and directory pagination modals.
  - `src/core/config.c`: `SE.CFG` reader, parser, serializer, and defaults.
  - `src/core/plugin_mgr.c`: Relocation loader, slot table, host API bridge.
  - `src/core/beautify.c`: Z80 assembly code formatter and operand aligner.
- [x] Maintain drop-in replacement capability conforming to module header API
  and ABI specifications (`src/include/*.h` mirroring `src/include/*.inc`):
  - Function signatures, parameter passing, and return codes must match.
  - Support hybrid linking (e.g. C core modules with Z80 HAL or vice-versa
    under Z88DK / SDCC / GCC).
  - Ensure zero behavioral deviation across line limits and modal layouts.

### 7.2 Linux Native Executable using C Equivalent Modules
- [x] Construct native Linux SE executable compiled from the C core modules.
- [x] Implement POSIX / Linux Hardware Abstraction Layer (`src/hal/linux/`):
  - `hal_linux_console.c`: ANSI escape sequences, `termios` raw mode, and
    terminal resize handling (`SIGWINCH`) for 80x24 / 120x40 geometries.
  - `hal_linux_keyboard.c`: Non-blocking POSIX stdin read, escape sequence
    decoding (arrows, PageUp/Down, Home/End), WordStar control keys.
  - `hal_linux_memory.c`: Dynamic heap buffer management replacing 64KB Z80
    TPA banking while preserving identical slot semantics and limits.
  - `hal_linux_storage.c`: Standard POSIX file I/O (`open`, `read`, `write`)
    and directory enumeration (`opendir`, `readdir`) for Linux paths.
- [x] Target platforms:
  - PC / Workstation: `x86_64` (Linux).
  - Raspberry Pi: `aarch64` (Raspberry Pi 4 and Raspberry Pi 5).
- [x] Add `se-linux` target in `Makefile` with cross-compilation support.

### 7.3 CP/M-86 Executable using C Modules
- [ ] Construct CP/M-86 executable (`SE.CMD`) compiled from C core modules.
- [ ] Implement CP/M-86 Hardware Abstraction Layer (`src/hal/cpm86/`):
  - `hal_cpm86_console.c`: CP/M-86 BDOS console calls and terminal escape
    sequence handling.
  - `hal_cpm86_keyboard.c`: CP/M-86 console status polling and input read.
  - `hal_cpm86_memory.c`: 8086 segmented memory allocation utilizing CP/M-86
    memory models for buffer expansion beyond 64KB.
  - `hal_cpm86_storage.c`: CP/M-86 BDOS FCB disk I/O, user areas, drives.
- [ ] Configure toolchain integration (GCC-IA16 / Open Watcom / Digital Research
  C for CP/M-86).
- [ ] Add `se-cpm86` build target in `Makefile` producing `SE.CMD`.

### 7.4 Rust Native Implementation for Linux
- [ ] Construct a native SE editor implementation in Rust for Linux.
- [ ] Implement idiomatic Rust architecture mirroring SE UI/UX specification:
  - Terminal engine using `crossterm`, `termion`, or raw `termios`.
  - Tier 1 full-screen workspaces, Tier 2 centered modal pop-up dialogs,
    and Tier 3 persistent status bar strictly matching `docs/UI_UX_DESIGN.md`.
  - High-performance text buffer engine (piece table or line-slot cache).
  - WordStar / SE keybindings (`Ctrl+K`, `Ctrl+Q`, `Ctrl+F`, `Ctrl+R`).
  - Compatible `SE.CFG` configuration parsing and serialization.
- [ ] Target platforms:
  - PC: `x86_64-unknown-linux-gnu`.
  - Raspberry Pi: `aarch64-unknown-linux-gnu` (RPi 4 / RPi 5).
- [ ] Add Cargo workspace / package configuration under `ports/rust/` or
  `src/rust/`.

### 7.5 Python Native Implementation for Linux
- [x] Construct a native SE editor implementation in Python 3 for Linux.
- [x] Implement full feature parity and UI/UX fidelity:
  - [x] Terminal I/O using standard library `termios` / `tty` or `curses`.
  - [x] Centered boxed modal dialogs, status bar, and WordStar keybindings.
  - [x] Compatible `SE.CFG` reader, parser, and default settings engine.
  - [x] Python-based plugin loading architecture reflecting Host API vectors.
- [x] Target platforms:
  - Python 3.10+ on PC (`x86_64`) and Raspberry Pi 4 / 5 (`aarch64`).
- [x] Add executable script and package setup under `ports/python/`.
