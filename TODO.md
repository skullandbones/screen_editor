# SE.COM — Development To-Do & Roadmap

This file tracks pending enhancement tasks, architectural optimizations, and
upcoming milestones for SE.COM.

---

## 1. AGENTS.md Enhancements

### 1.1 Prohibit "python -c" in AGENTS.md
- [x] Enhancement: Be explicit that "python -c" shall not be used and instead
  construct and run python scripts.

---

## 2. BUGS

### 2.1 Memory Screen Misreports Loaded Plugin Banks as Free / Unallocated
- [x] The memory screen erroneously shows "Free / Unallocated" when a plugin
  has been loaded. Update bank role and usage detection in the memory info
  screen ('m') to indicate that the memory bank is being used for plugins.

### 2.2 System Hangs When Loading Large Files with 32K Available RAM
- [x] When only 32K of RAM is available (reported on the status line), loading
  of large files hangs the system.

### 2.3 Status Events Displayed on Status Bar Instead of Tier 2 Modal Pop-ups
- [x] Refactor status event notifications to use Tier 2 centered modal
  pop-ups instead of writing directly to the bottom status bar row.
  - Remove `STATUS_OOM_FLAG` text ("* Out of memory *") from status bar
    (`src/se.asm:5756, 5949`); replace with centered Tier 2 status pop-up.
  - Remove `IS_LOADING_FILE` and `IS_SAVING_FILE` progress messages from status
    bar (`src/se.asm:5735, 5739, 5954, 5959`).
  - Deprecate `PLUGIN_STATUS_MSG_PTR` and `TRAMP_SET_STATUS_MSG` status bar
    squatting (`src/se.asm:5751, 23996`); plugins (`plugins/rot13.asm:104`,
    `plugins/beautify.asm:177`) must use Tier 2 status pop-ups.
  - Fix `plugins/plugin.asm:399, 525, 551` which directly prints `[No About]`,
    `[No Config]`, and `[All Slots Full]` to the status bar.
- *Justification* (`docs/UI_UX_DESIGN.md` Section 1.2, 2.2, 7.1):
  > *"The status bar no longer shows status events. Pop-ups are now used for
  > all status events."*
- *Clarification on Load/Save Progress & ESC Handling*:
  - **Progress Display**: Transient Tier 2 centered modal pop-ups display
    file loading and saving progress. The line counter increments inside the
    pop-up box (updating line count text) rather than on the status bar.
  - **ESC During Save**: Saving cannot be cancelled or aborted mid-stream by
    pressing ESC (preventing disk corruption). The save runs to completion,
    and any queued keystrokes are drained upon finish.
  - **ESC During Load**: Loading is non-interactive batch I/O running to
    completion. Keystrokes entered during load are drained upon finish so
    ESC does not trigger an accidental exit to the splash screen.
  - **ESC on Event Pop-ups**: For completion and error modals (e.g. Out of
    Memory, File Truncated, File Not Found), ESC or any key cleanly
    dismisses the pop-up and restores the editor screen.

### 2.4 Status Bar Free Memory Display on Non-Editing Screens
- [x] Confirmed and closed: On non-editing screens (Splash, About, Config,
  Memory Info, File Open, Save, and Block screens), the status bar indicates
  the last status of the editing screen while displaying free memory in
  Field 4.
  - Confirmed that `SHOW_STATUS_SPLASH_MEM` (`src/se.asm:5872, 5976`) only
    replaces Field 4 (`^K: Editor keys`) with `Free: <N> KB | `, while
    preserving all document editing status fields (Filename, Modified `*`,
    Geometry, Format, and Cursor Position `Line <cur>/<total> Col <col>`).
  - Showing free memory on non-editing screens is canonical behavior per
    `docs/UI_UX_DESIGN.md` Section 3 ("free memory") and verified by
    automated regression tests (Steps 25, 64, 70, 74).

### 2.5 Missing Centering on Open, Save, and Block Screens
- [x] Center screen content dynamically vertically above the status bar
  (`HOST_ROWS`), with top and bottom margin rows padded with column 0 tildes.
  - `DO_OPEN_FILE_UI` (`src/se.asm:15165`), `DO_SAVE_FILE_UI_IMPL`
    (`src/se.asm:16242`), and Block screens are top-aligned at Row 1-3 with all
    tildes appended at the bottom in `FINISH_UI_PAGE_AND_STATUS` (line 18551).
  - Add top margin tildes and calculate dynamic vertical starting row.
  - Dynamically center directory table columns horizontally for `HOST_COLS`.
- *Justification* (`docs/UI_UX_DESIGN.md` Section 1.4, 2.1):
  > *"Screen content shall be centered horizontally and vertically including
  > file open, close, etc. screens."*

### 2.6 Angle Bracket Hotkey Syntax (`<ESC>=Cancel`) in File/Directory Screens
- [x] Replace prohibited angle bracket `< >` notation with canonical `[ ]`
  bracket notation on file open, save, and block screens.
  - In `src/se.asm:23523` (`STR_ESC_CANCEL`), change `<ESC>=Cancel` to
    `[ESC]=Cancel`.
- *Justification* (`docs/UI_UX_DESIGN.md` Section 1.6, 4.1):
  > *"Variable parameters, slot indexes, list selectors, and action hotkeys
  > shall be expressed inside [ ] pairs (e.g. [Y]es   [N]o   [ESC]=Cancel)."*

### 2.7 Option Delimiters (`/`) in Context Pop-up Prompts
- [x] Remove slash delimiters (`/`) from selection hotkey options in
  pop-ups and command bars; separate choices with whitespace.
  - In `plugins/plugin.asm:2090` (`STR_POPUP_PROMPT_MATCH`), replace
    `[Up]/[Down]=Select` with `[Up]   [Down]=Select`.
  - In `plugins/plugin.asm:2108` (`STR_PLUG_CMDS_PRE`), replace
    `[Up]/[Down]=Select` with `[Up]   [Down]=Select`.
- *Justification* (`docs/UI_UX_DESIGN.md` Section 1.6, 4.3, 7.4):
  > *"Pop-up decision options shall not have any delimiters such as / and |
  > and instead should have sufficient spaces to separate the options nicely."*

### 2.8 Non-ESC Cancellation (`[Q]uit`) in Interactive Replace Confirmation
- [x] Remove `[Q]uit` from interactive replace confirmation pop-up so `ESC`
  is the exclusive cancellation trigger.
  - In `src/se.asm:23121` (`STR_REP_CONFIRM_KEYS`), update prompt from
    `| [Y]es [N]o [A]ll [Q]uit [R]everse [ESC]=Cancel |` to space-separated
    options omitting `[Q]uit`.
  - Update `src/se.asm:12130` key handling to cancel solely on `ESC`.
- *Justification* (`docs/UI_UX_DESIGN.md` Section 1.7, 3, 7.5):
  > *"If a pop-up needs user input such as yes or no, then only ESC can cancel
  > the pop-up (no use of Ctrl-C or q key)."*

### 2.9 Column 0 Tilde Discipline Violations on Header Rows in Help Plugin
- [x] Closed: The requirement for fixed non-tilde header rows was deleted from
  `docs/UI_UX_DESIGN.md`. Non-editor full-screen workspaces use centered
  content blocks with centered screen titles; only the bottom status bar
  (`HOST_ROWS`) is strictly non-tilde.
- *Justification* (`docs/UI_UX_DESIGN.md` Section 1.3, 5.2):
  > *"Note that the status bar does not have a column 0 tilde."*

### 2.10 Non-Standard Dismissals & Left-Justified Text in Plugin Pop-ups
- [x] Standardize dismissal prompts and centre-justify all content lines across
  plugin about and information dialogs.
  - Replace `"Press any key to return"` with `"Press any key to continue"`
    or `"Press any key"` in `plugins/plugin.asm:1661`,
    `plugins/beautify.asm:1702`, `plugins/bigplug.asm:194`,
    `plugins/halfplug.asm:194`, `plugins/midplug.asm:194`,
    `plugins/rot13.asm:245`, and `plugins/wordcnt.asm:466`.
  - In `plugins/plugin.asm:2088`, replace `"Press any key to dismiss"` with
    `"Press any key to continue"`.
  - Centre-justify text body lines inside 50-col and 38-col dialog boxes
    (currently left-justified in `plugins/plugin.asm:1658-1660`,
    `plugins/beautify.asm:1696-1701`, etc.).
- *Justification* (`docs/UI_UX_DESIGN.md` Section 1.4, 1.7, 4.4, 7.9):
  > *"All text is centre justified. Every line inside the pop-up must be
  > horizontally centered within the box borders."*
  >
  > *"Press any key statements must not be inside [ ] or ( ) pairs and do not
  > have ... (Allowed: Press any key to continue, Press any key)."*

### 2.11 Child Pop-ups Rendered Over Unhidden Parent Pop-ups in Plugin Manager
- [x] Enforce single-level pop-up visibility lifecycle in `plugins/plugin.asm`.
  - When spawning child pop-ups (e.g. `DO_PLUGIN_ABOUT` at line 1604 or
    `CONFIRM_UNLOAD_SLOT` at line 962) from the Ctrl+P context pop-up
    (`DO_CONTEXT_POPUP`), hide/erase the parent pop-up first.
  - Redraw parent pop-up upon dismissal of the child pop-up.
- *Justification* (`docs/UI_UX_DESIGN.md` Section 1.5, 6.2, 7.3):
  > *"When a child pop-up is to be shown, the parent pop-up shall be taken off
  > the screen (hidden) and the parent pop-up is redrawn when the child pop-up
  > no longer exists (child pop-up no longer shown)."*

### 2.12 Misalignment of Splash Screen Menu (First Item Extra Space)
- [x] Align the first splash screen command line with subsequent menu items.
  - In `src/se.asm:23341` (`STR_SPLASH_CMDS`), the first entry
    `"  type   [E]  or  [Enter] to edit"` was aligned to 17 characters for the
    trigger segment, aligning `"to edit"` with column 26 matching all
    subsequent rows.
- *Justification* (`docs/UI_UX_DESIGN.md` Section 1.4, 4.3):
  > *"All text is centre justified."* Screen content and tabular command lists
  > shall maintain strict vertical column alignment across items.

### 2.13 Configure & Plugin Screens Top-Aligned with Big Space Before Footer
- [x] Restore horizontal and vertical centering for Configuration and Plugin
  Manager screens.
  - Currently, `SHOW_CONFIG_SCREEN` (`src/se.asm:2308`) and
    `RENDER_PLUGIN_SCREEN` (`plugins/plugin.asm:565`) top-align the title and
    settings/slots (Rows 1..9 in Config, Rows 1..14 in Plugin Manager), followed
    by a large gap of blank tilde lines in the middle, with the footer pinned
    to the bottom (`ACTIVE_ROWS - 1`).
  - Screen content and commands must be centered horizontally and vertically
    between the top margin and status bar, with symmetrical top and bottom
    margin padding rows, rather than top-aligning content with a large gap
    before the bottom footer.
- *Justification* (`docs/UI_UX_DESIGN.md` Section 1.4, 2.1):
  > *"Screen content shall be centered horizontally and vertically including
  > file open, close, etc. screens."*

### 2.14 Missing Estimated Maximum Editor Lines on Splash Screen
- [x] Add a status line on the splash screen displaying an estimate of the
  maximum number of editor lines supported under the current configuration.
  - In `src/se.asm` (`RENDER_SPLASH`), add a fourth configuration status row
    below Plugin System status (`SPLASH_MENU_LINES` = 20) in the centered splash
    content block showing the estimated maximum editor line capacity.
  - Dynamically compute the line ceiling:
    - If `EXT_BANK_COUNT < 2`: paging is inactive (Bank 0 pinned), estimating
      256 lines (e.g. `Max Lines      : [256 lines (RAM)]`).
    - If `EXT_BANK_COUNT >= 2`: paging into `$$$SE$$$.SWP` is active,
      estimating either 16,384 lines (16K mode) or 32,768 lines (32K mode)
      based on `MAX_DOC_LINES_LIMIT` (e.g. `Max Lines      : [16,384 lines]`).
  - Align label and bracketed value with existing status rows (Screen Mode,
    RAM Disk, Plugin System).
  - Per `docs/UI_UX_DESIGN.md` Section 2, updating `SPLASH_MENU_LINES` maintains
    dynamic vertical centering without hardcoded row numbers.
- *Justification* (`docs/UI_UX_DESIGN.md` Section 1.2, 2.1):
  > Providing explicit document line capacity on the splash screen informs the
  > user of their memory constraints and paging capabilities before loading.

### 2.15 Target Filename Missing from Open and Save Progress Pop-ups
- [x] Display the target filename in the Tier 2 progress modal pop-up for file
  load, file save, block insert, and block save operations.
  - In `src/se.asm`, update `INIT_LOAD_PROGRESS` (line 14865),
    `INIT_SAVE_PROGRESS` (line 19546), and their block variants
    (`DO_BLOCK_INSERT_FILE`, `DO_BLOCK_SAVE_FILE`) to format and render the
    active target filename inside the 50x7 modal pop-up box (e.g. replacing
    or augmenting the generic description line with
    `File: <DRIVE>:<FILENAME>`).
  - Ensure the target filename line is horizontally centre justified within
    the 50-column box borders per `docs/UI_UX_DESIGN.md` Section 1.4 and 2.2.
  - *Rationale*: During file open, save-as, block insert, and block save
    operations, the target file being read from or written to storage can be
    completely different from the currently open document. Displaying the
    explicit target filename inside the pop-up confirms which file is actively
    being accessed.

### 2.16 Progress Pop-up Uses "Loading" Instead of "Opening" and "Inserting"
- [x] Update Tier 2 progress pop-up terminology to reflect the specific file
  operation being executed ("Opening" for file open, "Inserting" for block
  insert).
  - In `src/se.asm`, the progress modal currently displays a generic
    "Loading File" title in `STR_POPUP_LOAD_TITLE` (line 23021).
  - For normal file open operations (`LOAD_FILE`, `DO_OPEN_FILE_UI`), the
    action is an Open File operation; the pop-up should say "Opening File"
    (or "Opening") rather than "Loading".
  - For block file insert operations (`DO_BLOCK_INSERT_FILE`,
    `DO_PARSE_AND_INSERT`), the action is an Insert File operation; the
    pop-up should say "Inserting File" (or "Inserting") rather than
    "Loading".
  - Update `DRAW_LOADING_SCREEN` / `DO_PARSE_AND_INSERT` to pass dedicated
    title and description strings (e.g. `STR_POPUP_OPEN_TITLE` /
    `STR_POPUP_OPEN_DESC` for open; `STR_POPUP_INSERT_TITLE` /
    `STR_POPUP_INSERT_DESC` for block insert).

### 2.17 Plugin Screen 'A' (About) Clears Screen Instead of Centered Pop-up
- [x] On the Plugin Manager screen, pressing 'A' for plugin about erroneously
  clears the screen (`TERM_CLEAR_SCREEN` in `DO_PLUGIN_SCREEN` at
  `src/se.asm:21226`) and renders the about text at the top-left rather than
  displaying a centered Tier 2 modal pop-up over the current screen.
  - Pressing 'A' must render the plugin about dialog as a Tier 2 modal pop-up
    in the centre of the screen without clearing the Plugin Manager background.
  - Upon dismissal, the Plugin Manager screen must remain intact or be redrawn
    cleanly.
- *Justification* (`docs/UI_UX_DESIGN.md` Section 1.4, 2.2, 7.2):
  > *"All pop-ups shall be shown in the centre of the screen both
  > horizontally and vertically, calculated dynamically from HOST_COLS and
  > HOST_ROWS in 1-based ANSI coordinates."*
  >
  > Embedded about dialogs belong to Tier 2 centered boxed modal pop-ups;
  > clearing the screen background or displaying dialogs in the top-left
  > violates modal presentation standards.

### 2.18 Pinned Top Header Rows 1-3 on File Open, Save, and Block Screens
- [x] Unify screen title, directory listing, and input prompt into a centered
  content block on File Open, Save, and Block selection screens.
  - Currently in `src/se.asm:16740, 16764, 16783, 16794`, `RENDER_TITLE_COMMON`
    pins a 3-row header (`=`, centered title, `=`) at Rows 1-3, inserting
    `DIR_TOP_PAD_COUNT` blank tilde rows *after* the header rather than before.
  - Render top margin tildes (`DIR_TOP_PAD_COUNT`) before the title block so
    the title is the top element of a unified content block centered
    horizontally and vertically above the status bar (`HOST_ROWS`).
- *Justification* (`docs/UI_UX_DESIGN.md` Section 2):
  > *"Layout: Screen content is a unified content block centered horizontally
  > and vertically above the status bar, padded with column 0 tildes (`~`)
  > on top and bottom margin rows. Screen Title: Centered as the top element
  > of the content block (not as a fixed Row 1 header row)... Note: There is
  > no fixed Row 1 header row on any screen."*

### 2.19 Help Screen Top-Aligned at Row 1 Without Symmetrical Margins
- [ ] Restore horizontal and vertical centering for Help workspace.
  - In `plugins/help.asm:116` (`RENDER_HELP_SCREEN`), the help screen starts
    at Row 1 with zero top margin padding, dumping all unused rows (1 row on
    80x24, 17 rows on 120x40) at the bottom.
  - On 120x40 geometry, `STR_HELP_BODY` lines (`plugins/help.asm:294`) are
    left-aligned after column 0 tildes without horizontal centering padding.
  - Compute dynamic vertical top and bottom margin padding rows
    (`((HELP_ROWS - 1) - HELP_LINES) / 2`) and horizontally center the help
    body table in 120x40 mode.
- *Justification* (`docs/UI_UX_DESIGN.md` Section 1.4, 2.1):
  > *"Screen content is a unified content block centered horizontally and
  > vertically above the status bar, padded with column 0 tildes (`~`) on
  > top and bottom margin rows."*

### 2.20 Truncated File Save Blocked Uses Screen Dump Instead of Pop-up
- [ ] Replace full-screen error dump with a Tier 2 centered modal pop-up when
  save is blocked on a truncated document.
  - In `src/se.asm:16049` (`DO_SAVE_FILE_UI`), detecting
    `FILE_IS_TRUNCATED != 0` invokes `SHOW_TRUNCATED_SAVE_BLOCKED`
    (line 16074), which clears the screen and dumps an ancient 12-line raw
    text block (`STR_TRUNC_SAVE_BLOCKED`).
  - Replace with a standard Tier 2 centered boxed modal pop-up (reusing
    `SHOW_FILE_TRUNCATED_POPUP` or similar 50x7 modal), maintaining the
    background screen and persistent status bar without full-screen clearing.
- *Justification* (`docs/UI_UX_DESIGN.md` Section 1.2, 2.2, 7.1):
  > *"Pop-ups are now used for all status events (the status bar no longer
  > shows status events)."* Error and status notifications must use Tier 2
  > centered boxed modal pop-ups rather than screen clears or text dumps.

### 2.21 Overwrite Cancellation Emits Raw CRLF Text Causing Display Corruption
- [ ] Eliminate raw terminal text printing upon overwrite cancellation.
  - In `src/se.asm:16322` (`DO_OVERWRITE_CANCELLED`), cancelling overwrite
    emits `STR_SAVE_CANCELLED` (`13, 10, "~  Save cancelled.", 13, 10`)
    directly from the pop-up cursor coordinates without redrawing the screen.
  - Remove `STR_SAVE_CANCELLED` emission and restore the underlying screen
    cleanly without emitting stray line feeds.
- *Justification* (`docs/UI_UX_DESIGN.md` Section 1.1, 1.5, 7.3):
  > *"Zero Unplanned Scrolling: No screen, dialog, or prompt may ever exceed
  > terminal bounds or emit unchecked line feeds that push screen content off
  > the screen."*

### 2.22 Non-Standard Dismissal Prompts in About, Memory, Help, and FAT Plugin
- [ ] Standardize single-key dismissal statements across all full-screen and
  modal surfaces.
  - Update `STR_ABOUT_RETURN` (`src/se.asm:23472`: `"Press any key to return
    to splash"`), `STR_MEM_RETURN_PROMPT` (`src/se.asm:23490`: `"Press any key
    to return to splash screen"`), `STR_HELP_RETURN_PROMPT`
    (`plugins/help.asm:327`: `"Press any key to return to editor"`), and
    `plugins/fat/fat_plugin.c:164` (`"Press any key to close"`).
  - Replace non-standard suffixes with canonical `"Press any key to continue"`
    or `"Press any key"`.
- *Justification* (`docs/UI_UX_DESIGN.md` Section 1.7, 4.4, 7.4):
  > *"Press any key statements must not be inside [ ] or ( ) pairs and do
  > not have ... (Allowed: Press any key to continue, Press any key)."*

### 2.23 FAT Plugin Dialogs Use Hardcoded Coords, Screen Clears, and Delimiters
- [ ] Bring FAT plugin about and configuration dialogs into compliance with
  UI/UX design system specifications.
  - In `plugins/fat/fat_plugin.c:140-218` (`fat_plugin_about` and
    `fat_plugin_config`):
    - Replace hardcoded cursor coordinates (`vt_cursor(6, 16)`) with dynamic
      centering from `HOST_ROWS` and `HOST_COLS`.
    - Remove `vt_clear_screen()` calls that destroy underlying screens.
    - Remove slash delimiter from `[ESC]/[Q]` in favor of space-separated
      options (`[ESC]=Cancel`).
    - Enforce `ESC` as the sole cancellation key for the configuration dialog
      (prohibit `[Q]` cancellation).
- *Justification* (`docs/UI_UX_DESIGN.md` Section 1.4, 1.6, 1.7, 2.2):
  > Pop-ups must be dynamically centered from terminal geometry, decision
  > options must be space-separated without slash delimiters, and interactive
  > dialogs must be cancellable only by ESC.

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

### 3.6 Deduplicate Strings & ANSI Sequences (+0.5 KB to +1.0 KB) [PRIORITY]
- [x] **[PRIORITY]** Centralize repeated terminal escape sequences
  (`\x1b[7m`, `\x1b[0m`, `\x1b[K`, cursor addressing) into shared helper
  routines.

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

### 4.4 Enhancement to UI_UX_DESIGN.md
- [x] Ensure all screens including pop-up only screens have tildes in col 0
  and have the status bar present.
- *Justification* (`docs/UI_UX_DESIGN.md` Section 1.2 & 1.3):
  > *"All screens including pop-up only screens shall have the status bar
  > present."*
  >
  > *"All screens including pop-up only screens shall have tildes in
  > column 0."*

### 4.5 Enhancement to UI_UX_DESIGN.md
- [x] Screen content shall be centered horizontally and vertically including
  file open, close, etc. screens.
- *Justification* (`docs/UI_UX_DESIGN.md` Section 1.4):
  > *"Screen content shall be centered horizontally and vertically including
  > file open, close, etc. screens."*

---

## 5. Test Automation & Verification

### 5.1 Drunken Monkey Chaos Testing (`tests/test_drunken_monkey.py`)
- [ ] Run long-duration chaos sessions with randomized keystrokes.
- [ ] Verify stability across memory profiles (`128k`, `512k`, `preserve`,
  `overwrite`, `hibernate`) and plugin states (`autoload`, `disabled`).

### 5.2 Automated Headroom & Footprint Regression Tracking
- [ ] Track TPA headroom margins and plugin slot usage across commits via
  `python3 check_tpa.py SE.COM`.

### 5.3 Periodic UI/UX Compliance Audit (`docs/UI_UX_DESIGN.md`)
- [x] Periodically check SE.COM complies with the `docs/UI_UX_DESIGN.md` file
  and append a resolution task list into Section 2 (BUGS).

### 5.4 74-Step Conformity Regression Test Suite
- [x] Run the complete 74-step regression test suite on the RC2014 RomWBW
  emulator (`tests/test_editor_headless.py`).
- [x] Isolate and resolve all step failures (Steps 66, 68, 70, 73, 74) in
  individual atomic commits adhering to <= 80 chars per line and <= 72 chars
  commit subject line conventions, pushed to `colossus/agy1_dev_branch`.

---

## 6. Preparations for Releasing SE.COM v1.0.0

### 6.1 Create Documentation Suite
- [ ] Create documents including architecture, setup build environment, and
  user guide.

### 6.2 Review and Enhance Subroutine Comments in `SE.ASM`
- [ ] Review and enhance the comments in `SE.ASM` to provide information on
  subroutine call usage and purpose of the subroutine.
