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
- **Status**: Verification Complete / 5 Defects Open (Bug 2.1.3 Rejected).
- **Active Defects & Issue Tracking (UI_UX_DESIGN.md Conformance)**:
  - [ ] **Bug 2.1.1: Status Bar Field Squatting & Non-Canonical Layout**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 4.1, 4.3, 4.4, 11.1.
    - *Issue*: Status bar Field 4 is overwritten with free memory
      (`Free: 64 KB |`) on splash screen, with selection metrics
      (`Sel: 0 chars |`) when block mode is active, and with `[Pan +40] |`
      when horizontally panned, violating the universal `^K: Editor keys |`
      invariant. Field 3 displays `CP/M  |` with slash rather than `CPM   |`.
      Field 2 in 80x24 mode prints with 2 leading spaces (`  80x24 |`).
    - *Required Fix*: Conform `RENDER_STATUS_BAR` in `src/core/ui_render.asm`
      to canonical 5-field invariant (`| {name}{mod} | {geom} | {fmt} | `
      `^K: Editor keys | Line ... Col ... |`). Move `[SEL]`, `[BLK LOCK]`, and
      `[Pan +40]` indicators into Field 5. Keep Field 4 persistently displaying
      `^K: Editor keys |`. Update Field 3 string to `CPM   |`.
  - [ ] **Bug 2.1.2: Startup Screen Geometry Inversion (Defaults to 120x40)**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 2.1.
    - *Issue*: `START` in `src/se.asm` executes `CALL SET_MODE_120X40` by
      default. On standard CP/M terminals and serial consoles (VT100 / ANSI,
      80x24 standard), this causes terminal character column spill
      (Anti-Pattern #3) where the status bar padding exceeds 80 columns,
      resulting in distorted visual wrapping on 80x24 displays.
    - *Required Fix*: Default initial terminal geometry to `80x24`
      (`CALL SET_MODE_80X24`), matching the canonical terminal standard
      defined in Section 2.1, while preserving `120x40` toggle via command
      line or config file.
  - [x] **Bug 2.1.3: WordStar Navigation Disconnect [REJECTED / WONTFIX]**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 10.
    - *Disposition*: **REJECTED / WONTFIX** per architectural decision.
    - *Rationale*: Dropped support for WordStar diamond navigation (`^S`, `^D`,
      `^E`, `^X`) in `SE.COM`. Overriding `Ctrl+S` (Save File), `Ctrl+D`
      (Forward Delete), `Ctrl+E` (End of Line), and `Ctrl+X` (Cut/Move Block)
      is excessively invasive to established SE.COM keymappings. Cursor
      navigation remains fully supported via ANSI/VT100 arrow keys and
      Home/End (`Ctrl+A`/`Ctrl+E`).
  - [ ] **Bug 2.1.4: Tier 1 Centering & Tilde Violations on Help Screen**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 5.2, 7.1, 7.3.
    - *Issue*: In `plugins/help.asm`, content height is 22 lines, leaving 0
      top margin rows on an 80x24 screen, violating 1-based vertical centering.
      Rows 1 and 3 render ASCII banner rules (`=============================`)
      and Row 21 renders `-----------------------------`. Status bar Field 4
      displays `Free: 63 KB |`. Help text lists obsolete/colliding non-WordStar
      keybindings.
    - *Required Fix*: Redesign `HELP.OVL` in `plugins/help.asm` to use the
      canonical 17-line, 70-column two-column tabular layout, centered
      vertically with `~` in column 0 for rows 1..3 and 21..23, and maintain
      universal status bar presence on Row 24.
  - [ ] **Bug 2.1.5: Tier 1 Splash Screen Centering & Menu Inconsistency**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 7.1, 7.2.
    - *Issue*: `RENDER_SPLASH` in `src/se.asm` renders a 21-line menu
      structure with fixed menu items (`type [E] or [Enter] to edit...`),
      lacking the canonical 14-line centered presentation (`:e to edit`,
      `:o to open file`, `:s to save file`, `:c for config`, `:p for plugins`,
      `:? for help`, `:q to quit`).
    - *Required Fix*: Update `STR_SPLASH_CMDS` and `RENDER_SPLASH` in
      `src/se.asm` to match the canonical 14-line, 50-column Tier 1 splash
      layout specified in Section 7.2.
  - [ ] **Bug 2.1.6: Tier 2 Modal Dialog Framing & Action Button Formatting**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 8.1, 8.3 (Archetype C).
    - *Issue*: In `DO_GOTO_LINE_UI` (`src/core/editor.asm`), dialog width is
      50 columns instead of canonical 52 columns. Footer buttons display
      `[Enter]=Goto Line     [ESC]=Cancel` instead of canonical Archetype C
      footer `[Enter]=Confirm      [ESC]=Cancel`. Modal prompt routines in
      `src/core/search.asm` exhibit similar non-standard widths.
    - *Required Fix*: Standardize CP/M modal pop-up routines in
      `src/core/editor.asm` and `src/core/search.asm` to strictly conform to
      Archetype C (52x8 box, `+---+` title divider,
      `[Enter]=Confirm      [ESC]=Cancel` footer, bracketed input `[  ]`).

### 2.2 Profile 2: CP/M on ZX Spectrum Next (`SE_NEXT.COM`)
- **Target Platform**: NextCPM / CP/M 2.2 / CP/M Plus on ZX Spectrum Next.
- **Core Technology**: Z80 assembly (`src/se_next_cpm.asm`), Next-adapted
  console (80-column text mode), Next keyboard matrix mapping, NextCPM banked
  memory extensions.
- **Build Target**: `make se-next-cpm` (produces `SE_NEXT.COM`).
- **Status**: Verification Complete / 5 Defects Open (Bug 2.2.3 Rejected).
- **Active Defects & Issue Tracking (UI_UX_DESIGN.md Conformance)**:
  - [ ] **Bug 2.2.1: Status Bar Field Squatting & Non-Canonical Layout**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 4.1, 4.3, 4.4, 11.1.
    - *Issue*: Status bar Field 4 displays free memory on splash, selection
      metrics on block mode, and pan offset when panned in `se_next_cpm.asm`.
    - *Required Fix*: Conform `RENDER_STATUS_BAR` in `src/se_next_cpm.asm` to
      canonical 5-field layout; move indicators to Field 5.
  - [ ] **Bug 2.2.2: Startup Screen Geometry Inversion (Defaults to 120x40)**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 2.1.
    - *Issue*: Next CP/M profile defaults to 120x40 instead of standard 80x24.
    - *Required Fix*: Initialize to `80x24` mode in `START` (`se_next_cpm.asm`).
  - [x] **Bug 2.2.3: WordStar Navigation Disconnect [REJECTED / WONTFIX]**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 10.
    - *Disposition*: **REJECTED / WONTFIX** per architectural decision.
    - *Rationale*: Dropped support for WordStar diamond navigation in
      `SE_NEXT.COM` to preserve established SE.COM keymappings.
  - [ ] **Bug 2.2.4: Tier 1 Centering & Tilde Violations on Help Screen**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 5.2, 7.1, 7.3.
    - *Issue*: Help overlay displays 22-line banner box with zero top margin.
    - *Required Fix*: Standardize to 17-line 70-column centered layout.
  - [ ] **Bug 2.2.5: Tier 1 Splash Screen Centering & Menu Inconsistency**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 7.1, 7.2.
    - *Issue*: Splash screen displays legacy 21-line menu in `se_next_cpm.asm`.
    - *Required Fix*: Align with canonical 14-line centered splash layout.
  - [ ] **Bug 2.2.6: Tier 2 Modal Dialog Framing & Action Button Formatting**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 8.1, 8.3 (Archetype C).
    - *Issue*: 50-column dialog framing and non-standard action button footers.
    - *Required Fix*: Align dialog boxes with 52-column Archetype C format.

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
- **Status**: Active / 6 Defects Open (Bugs 2.4.20–2.4.25).
- **Active Defects & Issue Tracking (UI_UX_DESIGN.md Conformance)**:
  - [x] **Bug 2.4.1: Status Bar Layout Inversion & Missing Canonical Fields**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 4.3.
    - *Issue*: `render_status_bar` in `src/core/ui_render.c` outputs custom
      format `" SE v1.1.0 | Ln %-5u/%-5u Col %-3u | %s%s | Free: %4u KB"`.
    - *Required Fix*: Conform to canonical 5-field layout:
      `| {name}{mod} | {geom} | {fmt} | ^K: Editor keys | Line ... Col ... |`.
      Add Geometry (`80x24 |`), Format (`Linux |` / `CPM   |`), Pan indicator
      (`[Pan +40]`), Block indicator (`[SEL]` / `[BLK LOCK]`), and center-pad
      across full terminal width.
  - [x] **Bug 2.4.2: Missing Universal Status Bar on Non-Document Workspaces**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 4.1, 7.2, 7.3, 7.4.
    - *Issue*: Non-document screens (`show_splash_screen`, `show_about_screen`,
      `show_config_screen`, `show_mem_info_screen`) in `src/core/ui_render.c`
      wipe the screen and fail to render the status bar on `HOST_ROWS`.
    - *Required Fix*: Guarantee universal status bar presence on `HOST_ROWS`
      across all Tier 1 screens and behind Tier 2 pop-up dialogs.
  - [x] **Bug 2.4.3: Status Bar Squatting Anti-Pattern for Transient Alerts**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 4.4, 11.1.
    - *Issue*: `ui_render.c:158` writes transient alerts (`g_status_msg`)
      directly into the status bar, clobbering persistent document metadata.
    - *Required Fix*: Remove status bar message overwriting (Anti-Pattern #1).
      Route all status events (Save Complete, Search Failed, etc.) to Tier 2
      centered modal pop-up boxes (`show_notification` / Archetype A).
  - [x] **Bug 2.4.4: Arrow Key & WordStar Diamond Keybinding Misalignment**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 10.
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
  - [x] **Bug 2.4.5: Non-Functional Horizontal Panning Engine & Line Barrier**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 6.1, 6.2.
    - *Issue*: `g_horiz_pan_offset` in `src/core/editor.c` is never adjusted
      when cursor moves beyond column 79. `MAX_INPUT_LINE_CHARS` is 1000 in
      `config.h` instead of the strict 120-character line barrier.
    - *Required Fix*: Implement horizontal pan quantum (+40 columns) shift
      logic (`pan_col` = 40 or 80) and enforce `MAX_LINE = 120` limit.
  - [x] **Bug 2.4.6: Tier 1 Centering & Column 0 Tilde Margin Discipline**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 5.2, 7.1, 7.2.
    - *Issue*: Splash and help screens use top-aligned fixed coordinates with
      ASCII banner borders and lack column 0 tilde (`~`) margin rows.
    - *Required Fix*: Apply mathematical 1-based centering formulas and fill
      margin rows down to row `HOST_ROWS - 1` with `~` in column 0.
  - [x] **Bug 2.4.7: Tier 2 Modal Framing, Centering & Archetype Invariance**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 8.1, 8.2, 8.3.
    - *Issue*: `src/core/ui_modal.c` places titles on top border without
      title divider line (`+---+`), uses off-by-one centering calculation,
      permits quitting confirmation modals via `q`/`Q` instead of solely `ESC`,
      and omits bracket framing `[ text ]` on text input prompts.
    - *Required Fix*: Implement canonical Archetypes A, B, C, D with title
      dividers, 1-based centering, and strict key dismissal rules.
  - [x] **Bug 2.4.8: Missing Modal & Command Dispatchers in Editor Mode**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 8.3, 10.
    - *Issue*: In `src/core/editor.c`, `editor_handle_key()` lacks cases for
      `KEY_CTRL_L` (Goto Line), `KEY_CTRL_O` (Open File), `KEY_CTRL_P` (Plugin
      Palette), and `KEY_CTRL_W` (Close File to Splash). Even though
      `modal_input_goto_line()` is implemented in `ui_modal.c` and
      `goto_line()` exists in `editor.c`, `Ctrl+L` is silently dropped as a
      no-op.
    - *Resolution*: Bound `KEY_CTRL_L` to prompt for line number via Archetype C
      modal and jump via `goto_line()`, `KEY_CTRL_O` to open file browser dialog
      and load document, `KEY_CTRL_P` to display plugin manager UI, and
      `KEY_CTRL_W` to confirm unsaved modifications and close to splash screen.
      Validated via `test_bug_2_4_8_modal_dispatchers` in
      `tests/test_linux_native.py`.
  - [x] **Bug 2.4.9: Non-Functional Splash Screen Interactive Command Matrix**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 7.1, 7.2.
    - *Issue*: `show_splash_screen` in `src/core/ui_render.c` renders the
      canonical 14-line matrix displaying `:e`, `:o`, `:s`, `:c`, `:p`, `:?`,
      `:q`, but only checks for `q`/`Q` and treats any other key as an
      unconditional exit into the editor. Pressing `:o`, `:s`, `:c`, `:p`,
      `:?`, `1`, or `2` fails to trigger the corresponding modals/workspaces.
    - *Resolution*: Implemented interactive event loop in `show_splash_screen`
      supporting prefix colon (`:`) syntax and bare keys, dispatching `:e`
      (editor), `:o` (open file), `:s` (save file), `:w` (close file), `:l`
      (goto line), `:c` (config screen), `:p` (plugin manager), `:?` (help),
      `1` (120x40), `2` (80x24), and `:q` (exit), ignoring unregistered keys.
      Validated via `test_bug_2_4_9_splash_screen_commands` in
      `tests/test_linux_native.py`.
  - [x] **Bug 2.4.10: Keyboard HAL Escape Sequence Clumping on Burst Input**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 10.
    - *Issue*: In `src/hal/linux/hal_linux_keyboard.c`, the 30ms polling read
      loop reads up to 6 bytes into a single buffer. Rapid consecutive escape
      sequences (e.g. arrow navigation `\x1b[D\x1b[D\x1b[D`) are clumped into
      `seq`, causing CSI pattern match (`seq_len == 2`) to fail, defaulting to
      `KEY_ESC`, and corrupting cursor navigation.
    - *Resolution*: Implemented discrete byte FIFO queue and lookahead
      tokenization in `src/hal/linux/hal_linux_keyboard.c`, decoding ANSI CSI
      and SS3 escape sequences byte-by-byte with precise 30ms inter-byte timeout
      and unget support. Rapid burst escape sequences parse discretely without
      clumping. Validated via `test_bug_2_4_10_burst_escape_sequences` in
      `tests/test_linux_native.py`.
  - [x] **Bug 2.4.11: Block Selection Dynamic Cursor Tracking Missing**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 9.1, 9.2.
    - *Issue*: In `src/core/block.c`, `g_block_active_row` and
      `g_block_active_col` are only updated on `start_new_block_at_cursor()`
      and `solidify_block()`. As cursor moves in `editor.c`, block bounds are
      never updated, resulting in 0 characters selected and no visual highlight
      while navigating in selection mode.
    - *Resolution*: Dynamically updated `g_block_active_row` and
      `g_block_active_col` from cursor position in `normalize_block_bounds()`
      and implemented `update_block_selection()` in `src/core/block.c`.
      Integrated cursor tracking at editor key dispatch in `src/core/editor.c`
      triggering screen and status bar re-renders with inverse video highlights.
      Validated via `test_bug_2_4_11_block_selection_cursor_tracking` in
      `tests/test_linux_native.py`.
  - [x] **Bug 2.4.12: Clipboard Paste Unbound & Unimplemented (Ctrl+V)**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 9.3, 10.
    - *Issue*: In `src/core/editor.c`, `KEY_CTRL_V` is bound exclusively to
      `page_down()`. `src/core/block.c` implements `do_copy_block()` and
      `do_delete_block()`, but has no dedicated paste function. Text copied via
      `Ctrl+C` cannot be pasted.
    - *Resolution*: Implemented `do_paste_block()`, `do_cut_block()`, and
      clipboard buffer getters in `src/core/block.c`. Bound `KEY_CTRL_V` in
      `src/core/editor.c` to paste clipboard contents at active cursor (falling
      back to `page_down()` when clipboard is empty) and bound `KEY_CTRL_C` to
      copy selection. Validated via `test_bug_2_4_12_clipboard_copy_paste`
      in `tests/test_linux_native.py`.
  - [x] **Bug 2.4.13: Terminal Lifecycle, Startup Clear & Clean Exit Missing**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 2.5, 12.1.
    - *Issue*: On launch, `src/se_linux.c` fails to emit canonical `TERM_INIT`
      (`\x1b[0m\x1b[?25h\x1b[2J\x1b[H`), risking leaving unreset attributes or
      scrollback artifacts. On exit, `se_linux.c` clears screen and shows
      cursor, but fails to emit the canonical exit message followed by CRLF:
      `\r\nExiting SE. Returned to OS prompt.\r\n`. Additionally,
      `hal_console_clear()` in `hal_linux_console.c` emits `\x1b[H\x1b[2J`
      (home then clear) rather than standard ANSI clear then home
      (`\x1b[2J\x1b[H`).
    - *Resolution*: Emitted canonical `TERM_INIT` on `hal_console_init()` in
      `src/hal/linux/hal_linux_console.c`, standardized `hal_console_clear()` to
      `\x1b[2J\x1b[H`, and emitted `TERM_INIT` followed by the canonical exit
      banner `\r\nExiting SE. Returned to OS prompt.\r\n` upon termination in
      `src/se_linux.c`. Validated via `test_bug_2_4_13_terminal_lifecycle` in
      `tests/test_linux_native.py`.
  - [x] **Bug 2.4.14: Viewport Column 1 Space & Cursor Locator Offset**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 1.3, 5.3, 6.7.
    - *Issue*: In `src/core/ui_render.c:82` (`render_row_content`), allocated
      document rows unconditionally print a leading space
      `hal_console_putc(' ')` at column 1 under the mistaken notion of a
      "Column 0 Margin", constraining text width to `g_active_cols - 2` and
      shifting all document text right by one column. Section 5.3 strictly
      excludes column 0 tildes or margin spaces from active document lines.
      Due to this space, `locate_cursor()` in `src/core/editor.c:120` hardcodes
      `screen_col = (uint8_t)(vis_col + 2)` instead of the canonical 1-based
      coordinate formula `(vis_col - VIEW_LEFT_COL) + 1` specified in
      Section 6.7.
    - *Resolution*: Removed leading space on allocated document rows in
      `src/core/ui_render.c`, expanded text viewport width to `g_active_cols`,
      and realigned `locate_cursor()` in `src/core/editor.c` to canonical
      1-based coordinate `(vis_col - pan) + 1`. Validated via
      `test_bug_2_4_14_viewport_col1_alignment` in
      `tests/test_linux_native.py`.
  - [x] **Bug 2.4.15: Missing Sticky Target Column & Vertical Tab Clamping**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 6.1, 6.2, 6.4.
    - *Issue*: In `src/core/editor.c`, vertical navigation primitives
      (`cursor_up`, `cursor_down`, `page_up`, `page_down`) lack sticky
      `TARGET_COL` persistence. Passing through shorter or blank lines
      permanently clamps `g_cur_col` to `g_active_line_len`, losing the visual
      column. Furthermore, `adjust_col_to_target()` is never called on vertical
      movement, and its internal logic sets `g_cur_col` to `i` (after the tab,
      where `calc_visual_col >= target`) violating the Tab Exclusion Mandate,
      which requires clamping to the beginning of the tab (`vis_acc < TARGET_COL
      < vis_acc + spaces`).
    - *Resolution*: Implemented `g_target_col` in `src/core/editor.c` and
      declared in `src/include/editor.h`, tracking visual target column across
      horizontal movement and text editing. Implemented canonical
      `adjust_col_to_target()` with tab start clamping, preserving target
      column across `cursor_up`, `cursor_down`, `page_up`, and `page_down`.
      Validated via `test_bug_2_4_15_sticky_target_col_and_tab_clamping` in
      `tests/test_linux_native.py`.
  - [x] **Bug 2.4.16: Status Bar Field Squatting & Field 5 Column Reporting**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 4.3, 4.4, 11.1.
    - *Issue*: In `src/core/ui_render.c:210-241` (`render_status_bar`), Field 4
      is overwritten with selection metrics (`Sel: ...`, `Block: ...`) or
      horizontal panning (`[Pan +40]`), clobbering the mandatory universal help
      hint `^K: Editor keys |`. Per Section 4.3, selection state (`[SEL]` /
      `[BLK LOCK]`) and panning (`[Pan +40]`) belong in Field 5. Furthermore,
      Field 5 formats column position using raw byte index `g_cur_col` instead
      of visual document column `calc_visual_col()`, displaying raw byte offsets
      when tabs are present.
    - *Resolution*: Unconditionally preserved `^K: Editor keys |` in Field 4,
      routed `[Pan +40]`, `[SEL]`, and `[BLK LOCK]` indicators into Field 5,
      and computed Field 5 column display using `calc_visual_col()`. Validated
      via `test_bug_2_4_16_status_bar_field_invariance_and_visual_col` in
      `tests/test_linux_native.py`.
  - [x] **Bug 2.4.17: Tier 1 File Open/Save Workspaces & Directory Scanning**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 3, 7.5, 7.6, 7.7, 7.8, 14.2.
    - *Issue*: `ui_browser_open_dialog` in `src/core/ui_browser.c` renders a
      56x18 Tier 2 modal dialog with a 1-column list of files, and
      `ui_browser_save_dialog` delegates to `modal_prompt_text` (a single-line
      prompt). Section 7.5–7.8 mandate that File Open, Insert, Save, and Save
      Block are dedicated Tier 1 Full-Screen Workspaces with multi-column
      grids (5 cols x 12 rows on 80x24; 7 cols x 28 rows on 120x40), double
      rules (`~====...====`), column 0 tilde margins, `<PgUp>`/`<PgDn>`
      pagination, line ending toggle (`Ctrl+F`), and status bar at row 24.
      Furthermore, `hal_linux_scan_directory` in `hal_linux_storage.c` is an
      empty stub with no directory entry population.
    - *Resolution*: Upgraded File Open/Save/Insert/Save Block to full-screen
      Tier 1 workspaces with multi-column grids, double rules, column 0 tilde
      discipline, `<PgUp>`/`<PgDn>` pagination, line ending toggle (`Ctrl+F`),
      and universal status bar. Implemented POSIX `opendir`/`readdir` directory
      scanning in `hal_linux_storage.c`. Validated via
      `test_bug_2_4_17_tier1_file_workspaces_and_directory_scan` in
      `tests/test_linux_native.py`.
  - [x] **Bug 2.4.18: Non-Canonical Configuration Parser & Serialization**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 13.1, 13.2.
    - *Issue*: `src/core/config.c` uses non-canonical, case-sensitive key names
      (`TAB_WIDTH`, `LINES_MODE`, `SCREEN_MODE`, `SAVE_FMT`, `PLUGIN_MODE`)
      rather than canonical keys `SCREEN`, `TAB`/`TABS`, `FORMAT`,
      `LINES`/`MAXLINES`, `RAMDRIVE`/`RAMDISK`, `PLUGIN`/`PLUGINS`. It fails to
      parse canonical symbolic values (`16K`/`32K`, `PRESERVE`/`ON`/`HIB`,
      `AUTOLOAD`/`DEMAND`/`OFF`), does not strip surrounding whitespace around
      keys and values, does not ignore `;` comment lines, defaults `SCREEN` to
      `MODE_80X24` instead of canonical `120X40`, and serializes using
      non-canonical key names.
    - *Resolution*: Implemented case-insensitive parsing of canonical keys and
      symbolic values in `src/core/config.c`, stripped leading and trailing
      whitespace, ignored `#` and `;` comment lines and empty lines, defaulted
      `SCREEN` to `MODE_120X40`, and serialized configuration using canonical
      key names, symbolic values, and CRLF (`\r\n`) endings. Validated via
      `test_bug_2_4_18_canonical_config_parser_and_serialization` in
      `tests/test_linux_native.py`.
  - [x] **Bug 2.4.19: Panning Edge Trigger & Dynamic Geometry Adaptation**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 6.6, 14.1.
    - *Issue*: In `src/core/editor.c:65-98` (`update_horizontal_pan`),
      horizontal panning lacks the canonical lookahead edge trigger: when
      `vis_col == VIEW_RIGHT_COL - 1` (column 79) and the active line continues
      beyond `CUR_COL` (character at `CUR_COL` and next character are
      non-null), the viewport must pan right by 40 columns. Furthermore,
      `update_horizontal_pan()` hardcodes `g_horiz_pan_offset = 0` whenever
      `screen_mode == MODE_120X40`, ignoring dynamic terminal width
      (`g_active_cols`) and preventing panning on terminals with intermediate
      or non-standard column widths.
    - *Resolution*: Implemented canonical lookahead edge trigger at
      `view_right - 1` in `src/core/editor.c`, panning viewport right by 40
      columns when line continues past cursor. Adapted horizontal panning
      boundaries dynamically against `g_active_cols` and terminal width,
      bypassing panning when terminal accommodates the 120-column line limit
      and preserving hysteresis retention. Validated via
      `test_bug_2_4_19_panning_edge_trigger_and_geometry` in
      `tests/test_linux_native.py`.
  - [ ] **Bug 2.4.20: Deprecated WordStar Diamond Navigation & Key Aliases**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 1, 6.3, 6.4, 7.3, 10, 11
      (Anti-Pattern #8).
    - *Issue*: Directional cursor navigation across all surfaces is mandated
      to be handled exclusively via standard ANSI VT100 arrow keys and standard
      motion shortcuts (`Ctrl+A` Home, `Ctrl+E` End, `Ctrl+T` Top, `Ctrl+G`
      Bottom). WordStar diamond directional navigation (`^S`, `^D`, `^E`, `^X`)
      is deprecated and strictly unsupported to prevent command collisions.
      In Linux SE:
      1. In `src/core/editor.c:519-520`, `KEY_CTRL_E` (`0x05`) is aliased to
         `cursor_up()` rather than canonical End of Line (`cursor_end()`), and
         `KEY_CTRL_D` (`0x04`) is aliased to `cursor_right()` rather than
         forward character deletion (`do_delete()`).
      2. In `src/core/editor.c:589`, `KEY_CTRL_X` (`0x18`) falls back to
         `cursor_down()` when no block is active.
      3. In `src/core/ui_browser.c:336,349`, `KEY_CTRL_E` and `KEY_CTRL_X` are
         aliased to grid Up and Down.
      4. In `src/core/ui_modal.c:189,250,252`, `modal_confirm_2btn` and
         `modal_confirm_3btn` alias `KEY_CTRL_S` and `KEY_CTRL_D` to button
         navigation.
      5. In `src/core/ui_render.c:412`, `s_help_lines` advertises
         `Arrows / WordStar (^S,^D,^E,^X)` instead of canonical
         `Arrows / ANSI VT100`.
    - *Required Fix*: Disassociate WordStar diamond keys from cursor movement
      across all modules. Bind `KEY_CTRL_E` to `cursor_end()`, `KEY_CTRL_D` to
      `do_delete()`, and remove `cursor_down()` fallback on `KEY_CTRL_X` in
      `editor.c`. Remove WordStar key aliases from `ui_browser.c` and
      `ui_modal.c`. Update `s_help_lines` in `ui_render.c` to display
      `Arrows / ANSI VT100`.
  - [ ] **Bug 2.4.21: Off-by-Zero Column Anchor on Backspace Line Join**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 6.8, 10.1.
    - *Issue*: In `src/core/editor.c:229-231` (`do_backspace`), when joining
      current line (`g_cur_doc_row`) to previous line (`g_cur_doc_row - 1`)
      at column 0 (`g_cur_col == 0`), the code appends current line to
      `prev_buf`, updates `prev_len += g_active_line_len`, copies back to
      `g_active_line_buf`, and then calculates:
      `g_cur_col = prev_len - (g_active_line_len);`
      Because `g_active_line_len` was just assigned `prev_len`, `g_cur_col`
      evaluates to `0`. The cursor is incorrectly anchored to column 0 of the
      joined line instead of the junction boundary (`orig_prev_len`).
    - *Required Fix*: Preserve the original length of the previous line before
      concatenation (`uint16_t orig_prev_len = prev_len;`). After deleting the
      document row and checking out the joined line, set
      `g_cur_col = orig_prev_len;` and update sticky target column
      `g_target_col = calc_visual_col(g_active_line_buf, g_cur_col);`.
  - [ ] **Bug 2.4.22: Delete & Ctrl+D Fail to Delete Active Block Selection**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 6.8, 10.1.
    - *Issue*: In `src/core/editor.c:240-274` (`do_delete`), pressing `Delete`
      or `Ctrl+D` unconditionally performs inline character deletion under the
      cursor or pulls up the next line. If a block selection is active
      (`g_block_mode == BLOCK_MODE_SELECTING` or `BLOCK_MODE_SOLIDIFIED`), the
      specification requires that pressing `Delete` or `Ctrl+D` solidifies
      dynamic selection and deletes the entire highlighted block range
      (`do_delete_block()`), resetting `g_block_mode = BLOCK_MODE_OFF`.
      Currently, active selection is ignored and only a single character under
      the cursor is deleted.
    - *Required Fix*: In `do_delete()` (and `editor_handle_key` on `KEY_DEL` /
      `KEY_CTRL_D`), inspect `g_block_mode`. When `g_block_mode !=`
      `BLOCK_MODE_OFF`, solidify selection if selecting, invoke
      `do_delete_block()`, reset `g_block_mode = BLOCK_MODE_OFF`, mark
      `g_doc_modified = 1`, and trigger screen re-render
      (`g_need_screen_render = 1`).
  - [ ] **Bug 2.4.23: Backspace Fails to Cancel Dynamic Block Selection**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 6.8, 10.1.
    - *Issue*: In `src/core/editor.c:192-238` (`do_backspace`), pressing
      Backspace while dynamic block selection is underway
      (`g_block_mode == BLOCK_MODE_SELECTING`) deletes the character preceding
      the cursor and mutates document contents. Section 6.8 strictly mandates
      that pressing Backspace during dynamic block selection must cancel
      selection (`g_block_mode = BLOCK_MODE_OFF`) to safeguard highlighted
      text against unintended modification, keeping the cursor stationary
      without deleting text.
    - *Required Fix*: In `do_backspace()`, check if `g_block_mode ==
      BLOCK_MODE_SELECTING`. If so, invoke `cancel_block()`, set
      `g_need_status_render = 1`, and return immediately without modifying line
      buffer contents or cursor column.
  - [ ] **Bug 2.4.24: Enter Key in Dynamic Block Mode Splits Active Line**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 6.5, 9.1, 10.
    - *Issue*: In `src/core/editor.c:276-307` (`do_enter`), pressing Enter
      unconditionally splits the active line at `g_cur_col` and creates a new
      line. When dynamic block selection is active (`g_block_mode ==
      BLOCK_MODE_SELECTING`), pressing Enter must solidify the selection
      (`solidify_block()`, locking `g_block_mode = BLOCK_MODE_SOLIDIFIED`)
      without splitting the line or mutating document text.
    - *Required Fix*: In `do_enter()`, check if `g_block_mode ==
      BLOCK_MODE_SELECTING`. If so, invoke `solidify_block()`, set
      `g_need_status_render = 1`, and return without splitting the line.
  - [ ] **Bug 2.4.25: Missing In-Field Editing Keys in Archetype C Modals**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 8.3, 10.1, 10.2.
    - *Issue*: In `src/core/ui_modal.c:258-318` (`modal_prompt_text`), the
      parametric input field pins the cursor to the end of the input string
      (`cur_len`). It does not track an internal cursor index, completely
      ignoring directional navigation (`KEY_LEFT`, `KEY_RIGHT`, `KEY_HOME`,
      `KEY_END`, `KEY_CTRL_A`, `KEY_CTRL_E`). Furthermore, `KEY_DEL` is mapped
      to backspace (deleting the last character), and `KEY_CTRL_D` is unhandled,
      violating the mandate for forward character deletion under the cursor.
    - *Required Fix*: Implement in-field cursor position tracking (`cursor_pos`)
      in `modal_prompt_text()`. Support character insertion at cursor position,
      Backspace deleting left of cursor (`cursor_pos - 1`), Delete and `Ctrl+D`
      deleting character under cursor (`cursor_pos`), Left/Right arrow keys
      shifting cursor index, and Home (`Ctrl+A`) / End (`Ctrl+E`) moving to
      boundaries.

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
- **Status**: Active / 3 Defects Open (Bugs 2.7.42–2.7.44; Bug 2.7.45 Rejected).
- **Active Defects & Issue Tracking**:
  - [x] **Bug 2.7.1: Unreachable File Save (Ctrl+S) Due to Dispatch Collision**:
    - *Symptom*: Pressing `Ctrl+S` moves cursor left instead of saving file.
    - *Root Cause*: `KEY_CTRL_S` is caught in `ports/python/se/editor.py` under
      the navigation branch (`if key == KEY_LEFT or key == KEY_CTRL_S:`),
      making `elif key == KEY_CTRL_S: self.action_save_file()` dead code.
    - *Spec Reference*: `docs/UI_UX_DESIGN.md` Section 7.3 and 10.
    - *Resolution*: Removed `KEY_CTRL_S` collision from cursor navigation
      branch in `editor.py` so `Ctrl+S` triggers `action_save_file()`.
      Validated via `test_ctrl_s_dispatches_save_file` in `test_editor.py`.
  - [x] **Bug 2.7.2: Block Selection Not Extended on Cursor Movement (Ctrl+B)**:
    - *Symptom*: Pressing `Ctrl+B` and moving cursor selects zero characters;
      no inverse video highlight is displayed, and block copy/cut returns "".
    - *Root Cause*: `buffer.py` sets `block_start` and `block_end` on toggle,
      but cursor navigation methods (`move_left`, `move_right`, `move_up`,
      `move_down`, `page_up`, `page_down`) never update `block_end`.
    - *Spec Reference*: `docs/UI_UX_DESIGN.md` Section 9.1 and 9.2.
    - *Resolution*: Updated `get_normalized_block()` to follow the active
      cursor dynamically when `block_active == 1`, and updated `solidify_block`,
      `copy_block`, and `cut_block` to lock bounds upon block operations.
      Validated via `test_block_dynamic_cursor_tracking` in `test_buffer.py`.
  - [x] **Bug 2.7.3: Clipboard Paste Unbound (paste_block Never Called)**:
    - *Symptom*: User cannot paste copied clipboard text into the buffer.
    - *Root Cause*: In `editor.py`, `KEY_CTRL_V` is mapped exclusively to
      `buffer.page_down()`. `buffer.paste_block()` is implemented in buffer
      engine but never dispatched by any key.
    - *Spec Reference*: `docs/UI_UX_DESIGN.md` Section 9.3 and 10.
    - *Resolution*: Bound `KEY_CTRL_V` in `editor.py` to `paste_block()` with
      fallback to `page_down()` when clipboard is empty, reserving `KEY_PGDN`
      for dedicated paging. Validated via `test_ctrl_v_pastes_clipboard` in
      `test_editor.py`.
  - [x] **Bug 2.7.4: Status Bar Squatting & Status Event Rule Violation**:
    - *Symptom*: Transient messages (`Copied Xc`, `Cut Xc`, plugin status)
      overwrite Field 4 (`^K: Editor keys`) on the universal status bar.
    - *Root Cause*: `editor.py`, `ui.py`, and `plugin.py` route event strings
      to status bar via `status_msg` instead of Tier 2 notification modals.
    - *Spec Reference*: `docs/UI_UX_DESIGN.md` Section 4.4 and 11.1.
    - *Resolution*: Enforced persistent `^K: Editor keys` context on Field 4
      in `render_status_bar()`, and removed status bar squatting assignments
      on copy/cut in `editor.py`. Validated via
      `test_status_bar_field4_invariance` in `test_editor.py`.
  - [x] **Bug 2.7.5: Child Pop-up Isolation Defect in Plugin Palette**:
    - *Symptom*: When a plugin (e.g. `wordcnt.py`) displays a modal pop-up,
      it is drawn on top of the un-cleared parent menu without redrawing.
    - *Root Cause*: `action_plugin_palette()` does not erase parent surface
      or restore underlying screen before child modal execution.
    - *Spec Reference*: `docs/UI_UX_DESIGN.md` Section 8.4.
    - *Resolution*: Redrawn underlying editor workspace before invoking plugin
      actions from `action_plugin_palette()`, isolating child modal pop-ups
      and cleanly clearing the parent menu. Validated via
      `test_plugin_palette_child_isolation` in `test_editor.py`.
  - [x] **Bug 2.7.6: Tier 2 Modal Dialog Framing Layout Discrepancies**:
    - *Symptom*: Query modals (`show_confirm`) and text input modals
      (`show_input`) have cramped 7-row height without empty separator rows.
    - *Root Cause*: `modal.py` omits the blank row separating the prompt line
      from the action buttons (`[Y]es ...` / `[Enter]=Confirm ...`).
    - *Spec Reference*: `docs/UI_UX_DESIGN.md` Section 8.3
      (Archetypes B and C).
    - *Resolution*: Updated `show_confirm()` and `show_input()` in `modal.py`
      to 8-row height with an empty separator row before action options, and
      standardized options text in `editor.py`. Validated via
      `test_modal_dialog_framing_layout` in `test_editor.py`.
  - [x] **Bug 2.7.7: Modal Input Dialog Navigation Key Defect (show_input)**:
    - *Symptom*: Arrow keys (`KEY_LEFT`, `KEY_RIGHT`), `Home`, `End`, and
      `Delete` are ignored inside text input modal dialogs.
    - *Root Cause*: `show_input()` in `modal.py` lacks key handlers for
      cursor movement or character deletion inside the input brackets.
    - *Spec Reference*: `docs/UI_UX_DESIGN.md` Section 8.3 (Archetype C).
    - *Resolution*: Implemented navigation (`Left`, `Right`, `Home`, `End`),
      delete under cursor (`Delete`, `Ctrl+G`), and WordStar navigation in
      `show_input()` in `modal.py`. Validated via
      `test_modal_input_navigation_and_editing` in `test_editor.py`.
  - [x] **Bug 2.7.8: Missing Configuration Manager Option Handlers (3 and 4)**:
    - *Symptom*: Pressing `3` (Max Lines) or `4` (RAM Drive Mode) on the
      Configuration screen is silently ignored.
    - *Root Cause*: `action_config_screen()` in `editor.py` defines options
      3 and 4 in display lines but implements no branch handlers for them.
    - *Spec Reference*: `docs/UI_UX_DESIGN.md` Section 7.4.
    - *Resolution*: Added missing `Config` properties and `save_config()`
      method in `config.py`, and implemented option 3 and 4 toggle handlers
      in `action_config_screen()` in `editor.py`. Validated via
      `test_config_screen_option_toggles` in `test_editor.py`.
  - [x] **Bug 2.7.9: Cursor Placed on Status Bar on Centered Workspaces**:
    - *Symptom*: Blinking cursor sits at row 24 / col 1 instead of prompt.
    - *Root Cause*: `render_centered_workspace()` in `ui.py` invokes
      `render_status_bar()` as its final operation without repositioning
      cursor adjacent to `Enter choice: ` or `Enter option: `.
    - *Spec Reference*: `docs/UI_UX_DESIGN.md` Section 7.2 and 7.4.
    - *Resolution*: Updated `render_centered_workspace()` in `ui.py` to
      record prompt row/column and reposition the terminal cursor adjacent
      to the prompt following status bar rendering. Validated via
      `test_centered_workspace_prompt_cursor_position` in `test_editor.py`.
  - [x] **Bug 2.7.10: Standalone ESC Trapped on Splash & Misses Block Cancel**:
    - *Symptom*: Pressing `ESC` on Splash screen is ignored; in editor,
      pressing `ESC` with active block exits to Splash instead of canceling.
    - *Root Cause*: `action_splash_screen()` ignores `KEY_ESC`; `dispatch_key`
      lacks active block cancellation check on `KEY_ESC`.
    - *Spec Reference*: `docs/UI_UX_DESIGN.md` Section 10 and 11.5.
    - *Resolution*: Added `k == KEY_ESC` exit condition to splash screen loop
      in `action_splash_screen()`, and prioritized `block_active = 0` on
      `KEY_ESC` in `dispatch_key()` in `editor.py`. Validated via
      `test_esc_behavior_block_cancel_and_splash_exit` in `test_editor.py`.
  - [x] **Bug 2.7.11: ASCII DEL (0x7F) Mapped to Backspace in Terminal Driver**:
    - *Symptom*: Pressing Delete (0x7F) deletes char to left instead of under.
    - *Root Cause*: `terminal.py` maps `KEY_DEL_CHAR` (`0x7F`) to
      `KEY_BACKSPACE` instead of `KEY_DELETE`.
    - *Spec Reference*: `docs/UI_UX_DESIGN.md` Section 10.
    - *Resolution*: Updated `get_key()` in `terminal.py` to map
      `KEY_DEL_CHAR` (`0x7F`) to `KEY_DELETE`, preserving `KEY_BACKSPACE`
      for `0x08`. Validated via `test_backspace_and_enter` in
      `test_terminal.py`.
  - [x] **Bug 2.7.12: Off-by-One in Horizontal Pan Trigger**:
    - *Symptom*: Panning jumps to `[Pan +40]` at column 79 rather than 80.
    - *Root Cause*: `buffer.py` checks `self.cursor_col >= usable_cols` where
      `usable_cols = 79`, triggering pan while cursor is still within screen.
    - *Spec Reference*: `docs/UI_UX_DESIGN.md` Section 6.2.
    - *Resolution*: Updated `update_pan()` in `buffer.py` to trigger pan
      shifts when cursor reaches `view_cols` (column 80 in 80-col mode),
      allowing column 79 to render unpanned. Validated via
      `test_horizontal_panning` in `test_buffer.py`.
  - [x] **Bug 2.7.13: Terminal Buffer Starvation on PTYs (sys.stdin.read)**:
    - *Symptom*: When Python SE runs on a live PTY, arrow keys and multi-byte
      escape sequences are broken; `\x1b` is decoded as standalone `KEY_ESC`
      (canceling blocks or returning to Splash) and trailing characters (`[A`,
      `[D`, etc.) are inserted into document text.
    - *Root Cause*: `get_char()` in `terminal.py` calls `sys.stdin.read(1)`.
      Python's `TextIOWrapper` buffers chunks from the OS file descriptor into
      internal user-space memory. When `is_key_ready()` calls `select.select()`
      on fd 0, the OS reports no bytes waiting, causing `is_key_ready()` to
      falsely report `False`.
    - *Spec Reference*: `docs/UI_UX_DESIGN.md` Section 2.4 and Section 10.
    - *Resolution*: Updated `get_char()` and `is_key_ready()` in `terminal.py`
      to use unbuffered `os.read(fd, 1)` and direct fd selection when stdin has
      a file descriptor, falling back to stream reads for non-fd mock streams.
      Validated via `test_unbuffered_pty_escape_sequence_decoding` in
      `test_terminal.py`.
  - [x] **Bug 2.7.14: Editor Starts in Document Mode Instead of Splash Screen**:
    - *Symptom*: Running `se` without CLI arguments directly enters the document
      editor workspace with an untitled buffer, skipping the Splash screen.
      In CP/M `SE.COM`, running `se` without arguments opens the Tier 1 Splash
      screen (`SHOW_SPLASH_SCREEN`).
    - *Root Cause*: `editor.py`'s `Editor.run()` enters `render_editor()`
      unconditionally without checking whether an input file argument was
      provided on the CLI or displaying `action_splash_screen()`.
    - *Spec Reference*: `docs/UI_UX_DESIGN.md` Section 7.2 and
      `src/se.asm` lines 146-151 (`HAS_FILE_ARG == 0 -> JP SHOW_SPLASH_SCREEN`).
    - *Resolution*: Updated `Editor.run()` in `editor.py` to invoke
      `self.action_splash_screen()` prior to entering the document edit loop
      when `not self.buffer.has_file`. Updated `test_headless.py` and validated
      via `test_startup_mode_splash_screen` in `test_editor.py`.
  - [x] **Bug 2.7.15: Status Bar Column Spill During Block Selection ([SEL])**:
    - *Symptom*: When block selection is active (`Ctrl+B`), the status bar row
      overflows 80 columns (82 characters: `| (Untitled)* ... [SEL]`), inducing
      terminal line wrapping and display corruption.
    - *Root Cause*: `render_status_bar()` in `ui.py` appends `[SEL]` at the end
      of `stat_text` instead of formatting live selection metrics
      (`Sel: X chars` / `Sel: X lines`) inside the 18-character Field 4 budget.
    - *Spec Reference*: `docs/UI_UX_DESIGN.md` Section 4.3 and
      Section 11.3 (Anti-Pattern 3: Terminal Column Spill).
    - *Resolution*: Updated `render_status_bar()` in `ui.py` to format active
      block selection metrics (`Sel: X chars`/`Sel: X lines` or `Block: ...`)
      inside the 18-character Field 4 slot and removed trailing indicator from
      Field 5. Validated via
      `test_status_bar_block_selection_metrics_and_no_spill` in
      `test_editor.py`.
  - [x] **Bug 2.7.16: Status Bar Geometry and Environment Spacing Discrepancy**:
    - *Symptom*: Field 2 geometry in Python SE is formatted as ` 80x24 |`
      (7 chars, missing leading space), and Field 3 environment is ` CPM   |`
      (missing slash) compared to CP/M `SE.COM`'s canonical ` 80x24 |` and
      ` CP/M  |`.
    - *Root Cause*: `ui.py` formats `geom_field = f" {geometry_str} |"` instead
      of standard 8-character width `f"  {geometry_str} |"` and
      `fmt_str = "CPM  "` instead of `"CP/M "`.
    - *Spec Reference*: `docs/UI_UX_DESIGN.md` Section 4.3.
    - *Resolution*: Updated `render_status_bar()` in `ui.py` to format Field 2
      as `f" {geometry_str:>6} |"` (8 chars) and Field 3 as
      `f" {fmt_str} |"` with `fmt_str = "CP/M "` or `"Linux"`. Validated via
      `test_status_bar_geometry_and_environment_spacing` in `test_editor.py`.
  - [x] **Bug 2.7.17: Missing Case-Sensitivity Toggle ([Tab]) in Find Dialog**:
    - *Symptom*: In CP/M `SE.COM`, the Find Text modal dialog displays
      `Search Pattern: [Case Sensitive  ]` and supports pressing `[Tab]` to
      dynamically toggle between Case Sensitive and Case Insensitive before
      searching. In Python SE, `action_find()` uses generic `modal.show_input()`
      with no case indicator or `Tab` toggle.
    - *Root Cause*: `action_find()` does not provide a custom search modal
      supporting `KEY_TAB` case-sensitivity toggling.
    - *Spec Reference*: `docs/UI_UX_DESIGN.md` Section 8.3 (Archetype C)
      and `src/core/search.asm`.
    - *Resolution*: Implemented `show_find_dialog()` in `modal.py` featuring
      dynamic `[Tab]=Toggle Case` cycling of the `Search Pattern` indicator,
      and updated `action_find()` in `editor.py`. Validated via
      `test_find_dialog_tab_case_toggle` in `test_editor.py`.
  - [x] **Bug 2.7.18: Splash Screen Missing Command Matrix and Status Blocks**:
    - *Symptom*: CP/M `SE.COM` splash screen features 14 canonical commands
      (`[E]`, `[N]`, `[O]`, `[S]`, `[W]`, `[L]`, `[A]`, `[M]`, `[P]`, `[^P]`,
      `[C]`, `[1]`, `[2]`, `[Q]`) and 4 dynamic status blocks (Screen geometry,
      RAM drive mode, Plugin system, Max lines). Python SE splash screen
      displays only 7 abbreviated options (`:e`, `:o`, `:s`, `:c`, `:p`, `:?`,
      `:q`) and lacks handlers for `[A]`, `[M]`, `[N]`, `[W]`, `[1]`, `[2]`,
      `[L]`.
    - *Root Cause*: `action_splash_screen()` in `editor.py` uses a hard-coded
      abbreviated template and lacks dispatch branches for the full CP/M
      command matrix.
    - *Spec Reference*: `docs/UI_UX_DESIGN.md` Section 7.2 and
      `src/core/plugin_mgr.asm` line 4278.
    - *Resolution*: Updated `action_splash_screen()` in `editor.py` to render
      the canonical 14 commands and 4 live status blocks with full dispatch
      branches for `[N]`, `[W]`, `[L]`, `[A]`, `[M]`, `[1]`, and `[2]`.
      Validated via `test_splash_command_matrix_and_status_blocks` in
      `test_editor.py`.
  - [x] **Bug 2.7.19: Prohibited Dismissal Prompt Text on Help Screen**:
    - *Symptom*: Help screen (`Ctrl+K`) footer displays prohibited text:
      `Press any key to return to editor`. CP/M `SE.COM` displays canonical
      `Press any key to continue`.
    - *Root Cause*: `action_help()` in `editor.py` uses legacy prompt string
      `Press any key to return to editor`.
    - *Spec Reference*: `docs/UI_UX_DESIGN.md` Section 8.3 Archetype A
      and `tests/test_bug_2_22.py`.
    - *Resolution*: Replaced prohibited dismissal prompt in `action_help()` in
      `editor.py` and `UI_UX_DESIGN.md` with canonical
      `Press any key to continue`. Validated via
      `test_help_screen_dismissal_prompt` in `test_editor.py`.
  - [x] **Bug 2.7.20: Missing Tier 1 About ([A]) and Memory Map ([M]) Screens**:
    - *Symptom*: Pressing `a` (About) or `m` (Memory Info) from Splash or
      keybindings in Python SE is ignored; both full-screen Tier 1 workspaces
      exist in CP/M `SE.COM` but are completely absent from Python SE.
    - *Root Cause*: `action_about()` and `action_mem_info()` are not implemented
      in `editor.py`.
    - *Spec Reference*: `docs/UI_UX_DESIGN.md` Section 7.1 and
      `src/se.asm` lines 2858 & 3465.
    - *Resolution*: Implemented `action_about()` and `action_mem_info()` in
      `editor.py` conforming to Tier 1 centered workspace layout, column 0
      tilde discipline, and canonical dismissal prompt. Validated via
      `test_about_and_mem_info_workspaces` in `test_editor.py`.
  - [x] **Bug 2.7.21: Missing 3-Coordinate Space & Tab Traversal Engine**:
    - *Symptom*: When files containing literal tab (`\t` / `0x09`) characters
      are loaded, text lines wrap unpredictably, the terminal expands tabs
      using hardware tab stops (8) instead of configured tab width (4/8),
      and the hardware cursor is severely desynchronized from the text.
    - *Root Cause*: `DocumentBuffer` and `UIRenderer` lack the canonical
      3-coordinate system (Buffer Space `CUR_COL`, Visual Space `VisualCol`,
      Screen Space `ScreenCol`) and `calc_visual_col()` mapping specified in
      `docs/UI_UX_DESIGN.md` §6.1–§6.2. `ui.py` slices lines by raw byte index,
      emits raw `\t` bytes to the terminal, and places cursor using raw
      `cursor_col`.
    - *Spec Reference*: `docs/UI_UX_DESIGN.md` Section 6.1, 6.2, 6.7.
    - *Resolution*: Implemented `calc_visual_col()` and `expand_tabs_visual()`
      in `buffer.py` and `ui.py`. Expanded tabs into spaces during line
      rendering, pinned cursor navigation to discrete tab boundaries, and
      synchronized terminal screen cursor column to visual space. Validated via
      `test_tab_traversal_and_coordinates` in `test_buffer.py`.
  - [x] **Bug 2.7.22: Vertical Navigation Target Column Tab Misalignment**:
    - *Symptom*: Navigating vertically (`Up`, `Down`, `PageUp`, `PageDown`)
      across lines containing tab characters causes the cursor to jump
      erratically to incorrect columns on adjacent lines.
    - *Root Cause*: `move_up()`, `move_down()`, `page_up()`, and `page_down()`
      in `buffer.py` set `cursor_col = min(target_col, len(current_line))`
      where `target_col` stores a raw character index rather than sticky visual
      column coordinates.
    - *Spec Reference*: `docs/UI_UX_DESIGN.md` Section 6.4.
    - *Resolution*: Implemented `adjust_col_to_target()` in `buffer.py`
      conforming to Section 6.4 algorithm, preserving `target_col` sticky
      visual coordinates across `move_up()`, `move_down()`, `page_up()`, and
      `page_down()`. Validated via `test_vertical_navigation_sticky_col` in
      `test_buffer.py`.
  - [x] **Bug 2.7.23: Ctrl+D Mapped to Cursor Right Instead of Forward Delete**:
    - *Symptom*: Pressing `Ctrl+D` moves cursor one position to the right
      instead of deleting the character forward under the cursor.
    - *Root Cause*: In `editor.py:105`, `KEY_CTRL_D` is bound alongside
      `KEY_RIGHT` (`elif key == KEY_RIGHT or key == KEY_CTRL_D:`). Similarly,
      `modal.py` binds `KEY_CTRL_D` to move right.
    - *Spec Reference*: `docs/UI_UX_DESIGN.md` Section 10 Keybinding Table and
      Architectural Decision Note.
    - *Resolution*: Rebound `KEY_CTRL_D` in `editor.py` to
      `self.buffer.delete_char()` (forward delete), removed `KEY_CTRL_D` from
      `KEY_RIGHT` navigation in `editor.py` and `modal.py`, and bound
      `KEY_CTRL_D` to forward delete in modal input loops. Validated via
      `test_ctrl_d_forward_delete` in `test_editor.py`.
  - [x] **Bug 2.7.24: Tier 2 Modal Dialog Width Non-Conformance (50 cols)**:
    - *Symptom*: Tier 2 confirmation query modals (`show_confirm`), text input
      modals (`show_input`), and Find dialogs (`show_find_dialog`) are 50
      columns wide with 48-hyphen borders instead of canonical 52 columns.
    - *Root Cause*: `width = 50` is hard-coded in `modal.py` (lines 101, 144,
      219).
    - *Spec Reference*: `docs/UI_UX_DESIGN.md` Section 8.1, 8.2, 8.3
      (Archetypes B, C, D).
    - *Resolution*: Standardized Tier 2 modal box width to canonical 52
      columns (`width = 52`, 50-hyphen borders) across `show_confirm`,
      `show_input`, `show_find_dialog`, and `show_notification` in `modal.py`.
      Validated via `test_tier2_modal_52_col_width` in `test_editor.py`.
  - [x] **Bug 2.7.25: Help Workspace Height & Obsolete WordStar Text**:
    - *Symptom*: Help screen (`Ctrl+K`) renders 14 lines instead of canonical
      17 lines and displays obsolete text `Arrows / WordStar (^S,^D,^E,^X)`
      despite WordStar diamond navigation being dropped.
    - *Root Cause*: `action_help()` in `editor.py` uses legacy 14-line text
      containing obsolete WordStar navigation references.
    - *Spec Reference*: `docs/UI_UX_DESIGN.md` Section 7.3 and Section 10.
    - *Resolution*: Updated `action_help()` in `editor.py` to canonical
      17-line by 70-column layout conforming to Section 7.3, displaying
      `Arrows / ANSI VT100` with all WordStar references purged. Validated via
      `test_help_workspace_canonical_dimensions_and_keys` in `test_editor.py`.
  - [x] **Bug 2.7.26: Horizontal Pan Left Boundary Edge & Lookahead Defect**:
    - *Symptom*: When horizontal pan is active (`[Pan +40]`), moving cursor
      left to column 40 fails to reset the viewport back to column 0.
      Additionally, editing at column 79 on lines extending past column 79 does
      not trigger lookahead pan.
    - *Root Cause*: `update_pan()` in `buffer.py` uses strict inequality
      `elif self.cursor_col < 40: self.pan_col = 0` rather than inclusive
      boundary `vis_col <= 40`, and lacks the lookahead edge trigger for active
      lines extending past column 79.
    - *Spec Reference*: `docs/UI_UX_DESIGN.md` Section 6.6.
    - *Resolution*: Updated `update_pan()` in `buffer.py` to implement canonical
      `ADJUST_HORIZ_VIEWPORT` logic, ensuring retreat to `vis_col <= 40` resets
      `pan_col` to 0, clamping `calc_visual_col` to `MAX_LINE_LENGTH`, and
      triggering lookahead pan when cursor rests at `VIEW_RIGHT_COL - 1`
      on lines extending beyond column 79. Validated via
      `test_horizontal_pan_left_boundary_and_lookahead` in `test_buffer.py`.
  - [x] **Bug 2.7.27: Terminal Startup Screen Clear & Mode Reset Defect**:
    - *Symptom*: Launching `se-py` fails to clear the terminal screen or reset
      rendition attributes. Pre-existing shell text or scrollback remains
      visible behind centered workspaces and in empty margin rows.
    - *Root Cause*: In `ports/python/se/editor.py:78` (`run()`), only
      `self.terminal.enter_raw_mode()` is invoked. The mandatory startup
      `TERM_INIT` sequence (`\x1b[0m\x1b[?25h\x1b[2J\x1b[H`) is never emitted
      prior to displaying the initial workspace.
    - *Spec Reference*: `docs/UI_UX_DESIGN.md` Section 2.5 and Section 12.1.
    - *Resolution*: Implemented `term_init()` in `terminal.py` emitting
      `\x1b[0m\x1b[?25h\x1b[2J\x1b[H`, and invoked `self.terminal.term_init()`
      in `editor.run()` before rendering workspaces. Validated via
      `test_startup_term_init_clears_screen` in `test_editor.py`.
  - [x] **Bug 2.7.28: Missing Exit Screen Clear and Canonical Exit Banner**:
    - *Symptom*: Quitting `se-py` leaves dirty viewport contents and status bar
      text on the terminal without clearing the display or emitting the exit
      message banner. The host shell prompt appears misplaced on the screen.
    - *Root Cause*: In `ports/python/se/editor.py:100` (`finally:
      self.terminal.exit_raw_mode()`), `exit_raw_mode()` restores termios mode
      and cursor visibility, but never clears the terminal screen and never
      emits the canonical exit message string.
    - *Spec Reference*: `docs/UI_UX_DESIGN.md` Section 2.5 and Section 12.1.
    - *Resolution*: Implemented `term_exit()` in `terminal.py` which emits
      `term_init()` screen clear (`\x1b[2J\x1b[H`), prints canonical exit
      banner `\r\nExiting SE. Returned to OS prompt.\r\n`, and restores cursor,
      invoking it in `editor.run()` finally block. Validated via
      `test_editor.py` and PTY exit assertion in `test_headless.py`.
  - [x] **Bug 2.7.29: Status Bar Field 5 Shows Raw Col Across Tabs**:
    - *Symptom*: When the cursor is located on a line containing tab characters,
      Field 5 of the universal status bar displays the raw buffer byte offset
      rather than the document visual column (e.g. `Col 1` instead of `Col 4`
      when resting immediately after a tab stop).
    - *Root Cause*: In `ports/python/se/ui.py:77` (`render_status_bar()`),
      `cur_col = buf.cursor_col` formats raw buffer byte offset into
      `pos_field` instead of formatting `buf.get_visual_col()`.
    - *Spec Reference*: `docs/UI_UX_DESIGN.md` Section 4.3 and Section 6.2;
      `src/core/ui_render.asm:1308` (`CALL CALC_VISUAL_COL`).
    - *Resolution*: Updated `render_status_bar()` in `ui.py` to format Field 5
      using `buf.get_visual_col()` so that cursor position aligns with screen
      visual column coordinates across tabs. Validated via
      `test_status_bar_field5_visual_col_across_tabs` in `test_editor.py`.
  - [x] **Bug 2.7.30: Tab Key Intercept Replaces Tab Bytes with Spaces**:
    - *Symptom*: Pressing `Tab` in the editor inserts multiple ASCII spaces
      (`0x20`) instead of inserting a literal ASCII `0x09` (`KEY_TAB`) byte into
      the document line buffer. Documents edited in `se-py` lose tab character
      semantics and cannot contain true tabs.
    - *Root Cause*: In `ports/python/se/editor.py:133-140`, `KEY_TAB` is
      intercepted to calculate spaces to the next tab stop and inserts spaces
      via `insert_char(" ")`, violating the canonical model where tabs are
      stored as literal byte `0x09` in buffer space.
    - *Spec Reference*: `docs/UI_UX_DESIGN.md` Section 6.2 ("In-Memory Storage")
      and canonical `SE.COM` (`src/se.asm:1420` `DO_TAB_INSERT`).
    - *Resolution*: Updated `editor.py` so `KEY_TAB` calls
      `self.buffer.insert_char("\t")`, preserving literal `0x09` tab bytes in
      the line buffer while letting the discrete tab traversal engine handle
      visual leaping. Validated via `test_tab_key_inserts_literal_tab_byte` in
      `test_editor.py`.
  - [x] **Bug 2.7.31: Sticky Target Column Corrupted on Delete and Paste**:
    - *Symptom*: Forward deleting a character under cursor (`Ctrl+D` / `Delete`)
      does not synchronize sticky `target_col`. Pasting clipboard text
      (`Ctrl+V` / `paste_block()`) assigns raw byte offset `self.target_col =
      self.cursor_col` (and omits `target_col` update on multi-line paste),
      corrupting sticky vertical navigation targets on lines with tabs.
    - *Root Cause*: In `ports/python/se/buffer.py:200` (`delete_char()`),
      `self.target_col` is not updated after line mutation. In `buffer.py:405`,
      `paste_block()` sets `self.target_col = self.cursor_col` instead of
      `self.get_visual_col()`, and line 421 omits `target_col` update entirely.
    - *Spec Reference*: `docs/UI_UX_DESIGN.md` Section 6.1, 6.2, and 6.4.
    - *Resolution*: Updated `delete_char()`, `cut_block()`, and both branches
      of `paste_block()` in `ports/python/se/buffer.py` to synchronize
      `self.target_col = self.get_visual_col()`. Validated via
      `test_delete_and_paste_sticky_target_col` in `test_buffer.py`.
  - [x] **Bug 2.7.32: File Open & Save Workspaces Using Tier 2 Modals**:
    - *Symptom*: Pressing `Ctrl+O` / `:o` or `Ctrl+S` / `:s` presents a small
      52-column Tier 2 text input modal (`show_input`) rather than the
      full-screen Tier 1 Directory Browser workspace.
    - *Root Cause*: `action_open_file()` and `action_save_file()` in
      `ports/python/se/editor.py` invoke `self.modal.show_input()` instead of
      rendering Tier 1 workspaces with multi-column file grid layouts (5 cols
      on 80x24 / 7 cols on 120x40), `<PgUp>/<PgDn>` pagination, directory
      filtering, and `Ctrl+F` format toggling.
    - *Spec Reference*: `docs/UI_UX_DESIGN.md` Section 7.5, 7.7, and 14.2.
    - *Resolution*: Implemented `render_directory_workspace()` in `ui.py` and
      `action_directory_browser()` in `editor.py`, replacing mini-modals
      with full-screen Tier 1 directory workspaces supporting multi-column
      file grids, pagination, path traversal, wildcard filtering, and `Ctrl+F`
      format toggling. Validated via
      `test_tier1_directory_browser_open_and_save` in `test_editor.py`.
  - [x] **Bug 2.7.33: Block-Active File Insert (Ctrl+O) Unimplemented**:
    - *Symptom*: Pressing `Ctrl+O` while a block selection is active invokes
      the open file action (replacing active document) rather than streaming
      the selected file contents into the buffer at the cursor. Additionally,
      `Ctrl+K R` is unhandled.
    - *Root Cause*: In `ports/python/se/editor.py:160`, `KEY_CTRL_O` does not
      check `self.buffer.block_active`. The editor lacks `action_insert_file()`
      and block insertion mechanics.
    - *Spec Reference*: `docs/UI_UX_DESIGN.md` Section 7.6, Section 10, and
      `src/se.asm:1064-1070`.
    - *Resolution*: Added block-active detection to `KEY_CTRL_O` in
      `dispatch_key()` and implemented `action_insert_file()` in `editor.py`
      along with `insert_file()` in `DocumentBuffer`, solidifying block bounds
      and streaming file contents directly into the document at the cursor
      position without replacing existing lines. Added `Ctrl+K R` prefix
      dispatch. Validated via `test_block_active_file_insert` in
      `test_editor.py`.
  - [x] **Bug 2.7.34: Block-Active Save (Ctrl+S) Saves Full Buffer**:
    - *Symptom*: Pressing `Ctrl+S` while a block is highlighted overwrites the
      target file with the full document buffer rather than saving only the
      highlighted visual block range. Additionally, `Ctrl+K S` is unhandled.
    - *Root Cause*: In `ports/python/se/editor.py:162`, `KEY_CTRL_S`
      unconditionally calls `self.action_save_file()`. There is no check for
      `self.buffer.block_active > 0` and no `action_block_save()` routine.
    - *Spec Reference*: `docs/UI_UX_DESIGN.md` Section 7.8, Section 10, and
      `src/se.asm:1046-1052`.
    - *Resolution*: Intercepted `KEY_CTRL_S` when `self.buffer.block_active > 0`
      in `dispatch_key()` and implemented `action_block_save()` in `editor.py`
      along with `save_block()` in `DocumentBuffer`, writing only highlighted
      block lines and characters to target file while retaining active block
      selection. Added `Ctrl+K S` prefix dispatch. Validated via
      `test_block_active_save` in `test_editor.py`.
  - [x] **Bug 2.7.35: Document Close (Ctrl+W) Unhandled in Editor Loop**:
    - *Symptom*: Pressing `Ctrl+W` while editing a document is ignored. The
      editor cannot close an open document back to the splash screen from the
      active editor workspace. Furthermore, `action_close_file()` contains
      reversed confirmation prompt logic and fails to transition to Splash.
    - *Root Cause*: In `ports/python/se/editor.py`, `dispatch_key()` completely
      omits a branch for `KEY_CTRL_W`. In addition, `action_close_file()`
      prompts to discard edits rather than save them, and resets the buffer
      without launching `action_splash_screen()`.
    - *Spec Reference*: `docs/UI_UX_DESIGN.md` Section 7.9 and Section 10.
    - *Resolution*: Bound `KEY_CTRL_W` in `dispatch_key()` to
      `action_close_file()`. Updated `action_close_file()` to conform to
      Section 7.9: if clean, immediately closes to Splash; if modified,
      presents canonical Tier 2 modal (`Save changes?`), routes `[Y]es` to
      save before closing, `[N]o` to discard and close to Splash, and `[ESC]`
      to cancel. Validated via `test_document_close_lifecycle` in
      `test_editor.py`.
  - [x] **Bug 2.7.36: Missing Startup SE.CFG Discovery & Geometry Default**:
    - *Symptom*: Running `se` without `--config` never probes or loads `SE.CFG`
      from current working directory or program directory. Additionally,
      `Config.DEFAULT_SCREEN` defaults to `"80x24"` instead of canonical CP/M
      default `"120X40"`.
    - *Root Cause*: In `ports/python/se/__main__.py:67`, `editor.config.load()`
      only executes if `args.config` is explicitly passed. In
      `ports/python/se/config.py:15`, `DEFAULT_SCREEN = "80x24"`.
    - *Spec Reference*: `docs/UI_UX_DESIGN.md` Section 13.2, 13.3, and 14.1.
    - *Resolution*: Updated `DEFAULT_SCREEN = "120X40"` as canonical CP/M
      default. Implemented `discover_and_load()` in `Config` following priority
      order (custom path, `./SE.CFG` in current working directory, and
      program directory). Integrated discovery into `Editor.__init__()` and
      `__main__.py` before terminal initialization and buffer creation.
      Validated via `test_secfg_canonical_default_and_discovery` in
      `test_config.py` and `test_editor_secfg_discovery_and_geometry_default`
      in `test_editor.py`.
  - [x] **Bug 2.7.37: Delete Key Ignores Active Block (Ctrl+D / DEL)**:
    - *Symptom*: Pressing `Delete` or `Ctrl+D` while a block selection is active
      (dynamic or solidified) deletes only a single character under the cursor
      and leaves the block highlighted or desynchronized, rather than deleting
      the highlighted block range.
    - *Root Cause*: In `ports/python/se/editor.py:139-140`, `KEY_DELETE` and
      `KEY_CTRL_D` unconditionally execute `self.buffer.delete_char()` without
      inspecting `self.buffer.block_active`. Furthermore, `DocumentBuffer`
      lacks a dedicated `delete_block()` method.
    - *Spec Reference*: `docs/UI_UX_DESIGN.md` Section 6.8 and 10.1;
      `src/se.asm:1176-1188` (`DO_CTRL_D_BLOCK`) and `src/core/block.asm:847`.
    - *Resolution*: Implemented `delete_block()` in `DocumentBuffer` to remove
      selected block text, position cursor at block start, clear `block_active`,
      and mark document modified without altering clipboard. Updated
      `dispatch_key()` in `editor.py` to check `block_active > 0` on
      `KEY_DELETE` / `KEY_CTRL_D` and invoke `delete_block()`. Validated via
      `test_delete_key_active_block` in `test_editor.py`.
  - [x] **Bug 2.7.38: Backspace Fails to Cancel Dynamic Block Selection**:
    - *Symptom*: Pressing `Backspace` while dynamically highlighting text
      deletes the character preceding the cursor, mutating buffer contents
      while keeping the dynamic block active.
    - *Root Cause*: In `ports/python/se/editor.py:137-138`, `KEY_BACKSPACE`
      unconditionally calls `self.buffer.backspace()` without checking
      `self.buffer.block_active == 1`.
    - *Spec Reference*: `docs/UI_UX_DESIGN.md` Section 6.8 and 10.1;
      `src/se.asm:1328-1331` (`DO_BS_CANCEL_SETUP`).
    - *Resolution*: Implemented `cancel_block()` on `DocumentBuffer`. Updated
      `KEY_BACKSPACE` dispatch in `editor.py` to intercept `block_active == 1`
      and cancel selection without deleting text, while clearing active blocks
      prior to deletion when solidified (`block_active == 2`). Validated via
      `test_backspace_dynamic_block_cancel` in `test_editor.py`.
  - [x] **Bug 2.7.39: Enter Key in Dynamic Block Mode Splits Line**:
    - *Symptom*: Pressing `Enter` while extending a dynamic block selection
      splits the current line and moves cursor to a new line instead of
      solidifying the highlighted block boundaries.
    - *Root Cause*: In `ports/python/se/editor.py:135-136`, `KEY_ENTER`
      unconditionally executes `self.buffer.split_line()`, corrupting block
      selection coordinates and mutating the document.
    - *Spec Reference*: `docs/UI_UX_DESIGN.md` Section 9.1 and
      `src/se.asm:1299-1313` (`CHECK_ENTER`, `DO_ENTER_SOLIDIFY_SETUP`).
    - *Resolution*: Updated `KEY_ENTER` dispatch in `editor.py` to check
      `block_active == 1` and call `solidify_block()` without splitting the
      line, while clearing active blocks prior to splitting when solidified
      (`block_active == 2`). Validated via `test_enter_dynamic_block_solidify`
      in `test_editor.py`.
  - [x] **Bug 2.7.40: Forward Delete Line Join Desynchronizes Cursor Column**:
    - *Symptom*: Pressing `Delete` / `Ctrl+D` at the end of a line when the
      cursor column exceeds the line length (`cursor_col > len(line)`) joins the
      next line but leaves the cursor positioned past the join point inside the
      appended text rather than anchored at the junction boundary.
    - *Root Cause*: In `ports/python/se/buffer.py:214-223`, `delete_char()`
      appends `next_line` to `line` and pops row `cursor_row + 1`, but never
      clamps or assigns `self.cursor_col = len(line)`.
    - *Spec Reference*: `docs/UI_UX_DESIGN.md` Section 6.8 and 10.1;
      `src/se.asm:1172-1188`.
    - *Resolution*: Explicitly assigned `self.cursor_col = len(line)` in
      `delete_char()` prior to concatenation in `buffer.py`, synchronizing
      sticky target column and anchoring hardware cursor at the join junction.
      Validated via `test_delete_char_eol_junction_cursor_col` in
      `test_buffer.py`.
  - [x] **Bug 2.7.41: Typing and Tab Fail to Clear Active Block Selection**:
    - *Symptom*: Typing printable ASCII characters or pressing `Tab` while a
      block selection is active inserts characters into the line without
      canceling the block, corrupting highlight coordinates and selection
      boundaries. In dynamic mode (`block_active == 1`), typing modifies the
      buffer instead of canceling selection.
    - *Root Cause*: In `ports/python/se/editor.py:141-143` and `202-203`,
      `KEY_TAB` and printable character typing directly call
      `self.buffer.insert_char()` without inspecting `self.buffer.block_active`.
    - *Spec Reference*: `docs/UI_UX_DESIGN.md` Section 9.1, 9.2, and 10.1;
      `src/se.asm:1361-1399` (`CHECK_PRINTABLE_CHAR`, `DO_INSERT_CHAR`).
    - *Resolution*: Updated `KEY_TAB` and printable character dispatch in
      `editor.py` to cancel dynamic block selection (`block_active == 1`)
      without inserting characters or tab bytes, while clearing active blocks
      prior to insertion when solidified (`block_active == 2`). Validated via
      `test_typing_and_tab_block_cancel` in `test_editor.py`.
  - [ ] **Bug 2.7.42: Status Bar Field Squatting & Missing Block Indicators**:
    - *Symptom*: When text block selection is active (`block_active > 0`),
      Field 4 on the universal status bar displays selection metrics (`Sel:
      X chars |` or `Block: Y lines |`), clobbering the mandatory universal
      help hint `" ^K: Editor keys |"`. Furthermore, Field 5 fails to display
      the canonical ` [SEL]` (dynamic selection) or ` [BLK LOCK]` (solidified
      selection) mode indicators.
    - *Root Cause*: In `ports/python/se/ui.py:60-74` (`render_status_bar`), an
      `if buf.block_active > 0:` branch replaces `help_field = " ^K: Editor
      keys |"` with dynamic selection/line count strings, violating Section 4.3
      and 11.1. In addition, Field 5 string assembly (`pos_field`) formats only
      line, column, and pan offset, omitting the block mode indicators defined
      in Section 4.3 and 9.2.
    - *Spec Reference*: `docs/UI_UX_DESIGN.md` Section 4.3, 9.2, and 11.1
      (Anti-Pattern #1: Status Bar Squatting); Linux Native Bug 2.4.16.
    - *Resolution Plan*: Keep Field 4 persistently formatted as `" ^K: Editor
      keys |"`. In Field 5, append ` [SEL]` when `buf.block_active == 1` and
      ` [BLK LOCK]` when `buf.block_active == 2` alongside horizontal pan
      indicator `[Pan +X]`.
  - [ ] **Bug 2.7.43: Missing Tier 2 Block Operations Modal Dialog on Ctrl+K**:
    - *Symptom*: When a block selection is active (`block_active > 0`),
      pressing `Ctrl+K` falls through to `action_help()` or prefix key
      detection rather than presenting the canonical Tier 2 Block Operations
      modal dialog.
    - *Root Cause*: In `ports/python/se/editor.py:182-194`, `KEY_CTRL_K` does
      not check `self.buffer.block_active`. Canonical SE
      (`src/se.asm:1091-1099` and `src/core/block.asm:114-268`) routes `Ctrl+K`
      with `BLOCK_ACTIVE > 0` directly to `DO_BLOCK_MENU_POPUP`, a 50x7 modal
      pop-up displaying block metrics and keyboard commands (`[Enter]=Lock/Set`,
      `[^C]=Copy`, `[^X]=Move`, `[^D]=Del`, `[^S]=Save`, `[^B]=Clear`,
      `[ESC]=Close`).
    - *Spec Reference*: `docs/UI_UX_DESIGN.md` Section 8.1, 8.2, 10;
      `src/se.asm:1091-1099` (`CHECK_CTRL_K`); `src/core/block.asm:114-268`
      (`DO_BLOCK_MENU_POPUP`).
    - *Resolution Plan*: Implement `action_block_popup()` in `editor.py` /
      `modal.py` rendering the canonical 50x7 (or 52-col) Tier 2 Block
      Operations modal dialog when `self.buffer.block_active > 0` upon
      receiving `KEY_CTRL_K`, supporting Lock, Copy, Cut/Move, Delete, Save
      Block, Clear, and Dismiss actions.
  - [ ] **Bug 2.7.44: Ctrl+K Prefix Command Polling Blocks Interactive Chords**:
    - *Symptom*: Pressing `Ctrl+K` followed by a secondary command key (`R` for
      File Insert, `S` for Block Save, `Q`/`X` for Exit) fails to execute the
      command and immediately falls back to displaying the Help workspace.
    - *Root Cause*: In `ports/python/se/editor.py:183-194`, secondary key
      polling queries `self.terminal.is_key_ready()` with the default
      `timeout=0.0`. In interactive terminal sessions, human keystrokes cannot
      arrive within 0.0 seconds of `Ctrl+K`, causing `is_key_ready()` to return
      `False` immediately and dispatching `self.action_help()`.
    - *Spec Reference*: `docs/UI_UX_DESIGN.md` Section 7.6, 7.8, and 10.
    - *Resolution Plan*: Provide a reasonable interactive window (e.g.
      `timeout=1.0` or interactive prompt) when polling for two-key chord
      sequences after `Ctrl+K`, allowing human entry of `R`, `S`, `Q`, `X`
      before falling through to `action_help()`.
  - [x] **Bug 2.7.45: WordStar Diamond Key Mapping [REJECTED / WONTFIX]**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 8.3, 10, 11.8.
    - *Disposition*: **REJECTED / WONTFIX** per architectural decision.
    - *Rationale*: WordStar diamond key mappings (`^S`, `^D`, `^E`, `^X`) are
      explicitly not supported across all editor workspaces, dialogs, and modal
      surfaces. Modal text input prompts adhere strictly to standard VT100/ANSI
      editing primitives, eliminating WordStar navigation by design.

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

### 7.1 C Semantic Equivalent Modules & CP/M Target (`SEC.COM`)
- [x] Compile C semantic equivalent core modules to produce `SEC.COM` for CP/M:
  - The C drop-in replacement modules (`src/core/*.c`) shall be used to build
    `SEC.COM`, a native CP/M executable that runs directly on CP/M systems.
  - From a black box point of view, `SEC.COM` in principle should be completely
    identical to `SE.COM` (matching terminal behavior, visual layout, status
    bar, modal dialogs, cursor mechanics, keybindings, and file I/O).
- [x] Maintain drop-in replacement capability conforming to module header API
  and ABI specifications (`src/include/*.h` mirroring `src/include/*.inc`):
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
- [x] Integrate CP/M build target in `Makefile` for `SEC.COM`:
  - Link C core modules with CP/M platform HAL (`src/hal/cpm/`) via Z88DK / SDCC
    cross-compiler toolchain.
  - Update `send_binaries.py` so that it transfers `SEC.COM` to the target CP/M
    hardware board alongside `SE.COM`.
  - Validate black-box functional and behavioral equivalence between `SEC.COM`
    and `SE.COM` using automated comparative and emulator test suites.

### 7.2 Linux Native Executable using C Equivalent Modules (`se-linux`)
- **Mandate**: `se-linux` SHALL be built directly using the portable C core
  modules from Section 7.1 (`src/core/*.c`), ensuring shared logic and zero
  behavioral divergence, except where adaptation is strictly required for
  Linux (which must be isolated within the Linux HAL `src/hal/linux/`).
- [ ] Construct native Linux SE executable compiled from the Section 7.1 C core
  modules (`src/se_linux.c` + `src/core/*.c`).
- [ ] Implement POSIX / Linux Hardware Abstraction Layer (`src/hal/linux/`):
  - `hal_linux_console.c`: ANSI escape sequences, `termios` raw mode, and
    terminal resize handling (`SIGWINCH`) for 80x24 / 120x40 geometries.
  - `hal_linux_keyboard.c`: Non-blocking POSIX stdin read, escape sequence
    decoding (arrows, PageUp/Down, Home/End), WordStar control keys.
  - `hal_linux_memory.c`: Dynamic heap buffer management replacing 64KB Z80
    TPA banking while preserving identical slot semantics and limits.
  - `hal_linux_storage.c`: Standard POSIX file I/O (`open`, `read`, `write`)
    and directory enumeration (`opendir`, `readdir`) for Linux paths.
- [ ] Target platforms:
  - PC / Workstation: `x86_64` (Linux).
  - Raspberry Pi: `aarch64` (Raspberry Pi 4 and Raspberry Pi 5).
- [ ] Add `se-linux` target in `Makefile` with cross-compilation support.

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
