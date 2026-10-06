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
- [x] Restore horizontal and vertical centering for Help workspace.
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
- [x] Replace full-screen error dump with a Tier 2 centered modal pop-up when
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
- [x] Eliminate raw terminal text printing upon overwrite cancellation.
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
- [x] Standardize single-key dismissal statements across all full-screen and
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
- [x] Bring FAT plugin about and configuration dialogs into compliance with
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

### 2.24 Right-Border Misalignment & Overflow in Save & Overwrite Modals
- [x] Correct string length and trailing margin in `STR_POPUP_SAVE_KEYS`.
  - In `src/se.asm:23364`, `STR_POPUP_SAVE_KEYS` is defined as:
    `"|        [Y]es      [N]o      [ESC]=Cancel        |"`
    which contains 51 characters (8 leading spaces, 33 characters of option
    text, 8 trailing spaces, plus 2 border characters).
  - The standard modal pop-up box width is strictly 50 columns (defined by
    `STR_POPUP_BORDER` at `src/se.asm:23354`).
  - Emitting `STR_POPUP_SAVE_KEYS` in `DO_SAVE_CHANGES_POPUP`
    (`src/se.asm:1321`) and `DRAW_OVERWRITE_POPUP` (`src/se.asm:16618`) causes
    the closing `|` border on Row 6 to print at column 51, pushing 1 column
    past the right edge of all other rows and corrupting the vertical border
    alignment.
  - Reduce trailing padding by 1 space (from 8 spaces to 7 spaces) so the
    string is exactly 50 characters, matching `STR_UNLOAD_KEYS` in
    `plugins/plugin.asm:2417`.
- *Key Sequence (from splash)*:
  - Sequence A (Overwrite pop-up): Press `S` -> type `TODO.MD` -> `Enter`.
    Observe the "Overwrite File" pop-up: on Row 6, the right border `|`
    protrudes 1 column past rows 1-5 and 7.
  - Sequence B (Save Changes pop-up): Press `E` -> type `X` -> `Ctrl+Q`.
    Observe the "Unsaved Modifications" pop-up: on Row 6, the right border `|`
    protrudes 1 column past rows 1-5 and 7.
- *Justification* (`docs/UI_UX_DESIGN.md` Section 1.1, 2.2, 7.8):
  > Pop-up boxes belong to Tier 2 centered boxed modal pop-ups with exact ASCII
  > frame dimensions. Character emissions must not exceed budgeted geometry or
  > distort modal border boundaries.

### 2.25 Missing Description Line and Asymmetric Spacing in Find Modal Pop-up
- [x] Bring Find modal pop-up layout and alignment into compliance with query
  pop-up design standards.
  - In `src/se.asm:10714-10754` (`DRAW_FIND_POPUP_BODY`) and
    `src/se.asm:23414-23425` (`STR_FIND_POPUP_*`):
    - Row 4 (first body line) renders match mode (`Match: [Case Sensitive  ]`)
      instead of a descriptive query explanation (e.g.
      `Enter search pattern to find in document`), omitting the required
      description line that exists in Replace (`STR_REPLACE_POPUP_MSG`) and Goto
      Line (`STR_GOTO_POPUP_MSG`).
    - Row 5 (query line) uses `|     Find: [` (5 leading spaces) and `]      |`
      (6 trailing spaces), resulting in 1-space horizontal asymmetry around the
      29-character input box. Symmetrical centering requires 6 spaces on both
      sides.
    - Row 6 (query options) `| [Enter]=Find  [Tab]=Toggle Case  [ESC]=Cancel  |`
      has 1 leading space and 2 trailing spaces, violating horizontal
      center-justification.
- *Key Sequence (from splash)*:
  - Press `E` -> `Ctrl+F`.
  - Observe the "Find Text" pop-up: Row 4 shows match mode instead of query
    description, Row 5 has asymmetric padding (`Find: [` 5 spaces left vs 6
    right), and Row 6 has asymmetric padding (1 space left vs 2 right).
- *Justification* (`docs/UI_UX_DESIGN.md` Section 1.4, 2.2, 7.9):
  > *"Query pop-up format shall have a title line box, the pop-up body first
  > line shall be the description, then the query line followed by the query
  > options. All text is centre justified."*

### 2.26 Asymmetric Left-Aligned Messages in Truncated & Error Modal Pop-ups
- [x] Horizontally center informational messages in Tier 2 status and error
  pop-ups.
  - In `src/se.asm:23372` (`STR_POPUP_TRUNC_MSG2`):
    `"| Save is disabled to protect data on disk.      |"` has 1 leading space
    and 6 trailing spaces for a 41-character message inside a 48-column
    interior. It is heavily left-biased by 5 characters instead of centered
    with 3 leading and 4 trailing spaces.
  - In `src/se.asm:23453` (`STR_POPUP_NOT_FOUND_MSG1`):
    `"|              Pattern not found.                |"` has 14 leading spaces
    and 16 trailing spaces for an 18-character message. The 30 remaining spaces
    divide evenly into 15 leading and 15 trailing spaces.
  - In `src/se.asm:23471` (`STR_POPUP_TOO_LONG_MSG2`):
    `"|      Line length limit exceeded on replace.    |"` has 6 leading spaces
    and 4 trailing spaces for a 38-character message. The 10 remaining spaces
    divide evenly into 5 leading and 5 trailing spaces.
- *Key Sequence (from splash)*:
  - Press `E` -> `Ctrl+F` -> type `ZZZ` -> `Enter`.
  - Observe the "Pattern Not Found" pop-up: Row 4 (`Pattern not found.`) has
    14 spaces left and 16 spaces right, left-biased instead of 15 and 15.
- *Justification* (`docs/UI_UX_DESIGN.md` Section 1.4, 2.2, 7.9):
  > *"All text is centre justified. Every line inside the pop-up (title,
  > description, query line, and query options) must be horizontally centered
  > within the box borders."*

### 2.27 Configuration Screen Footer Uses Prohibited Slash Delimiter
- [x] Replace slash delimiter and non-standard casing in Configuration screen
  footer.
  - In `src/se.asm:23648-23650` (`STR_CONFIG_FOOTER`):
    `"[1-5]=Toggle Option   [S]=Save Config   [Q]/[ESC]=return to splash..."`
  - Remove prohibited slash delimiter in `[Q]/[ESC]` in favor of space-separated
    triggers or canonical exit command `[ESC]=Exit` (matching splash and
    plugin screens).
  - Update `return to splash screen` to standard Title Case (e.g.
    `Return to Splash` or `Exit`).
- *Key Sequence (from splash)*:
  - Press `C`.
  - Observe Configuration screen footer:
    `[1-5]=Toggle Option   [S]=Save Config   [Q]/[ESC]=return to splash screen`
    contains prohibited slash delimiter `[Q]/[ESC]` and lowercase text.
- *Justification* (`docs/UI_UX_DESIGN.md` Section 1.6, 4.3, 7.4):
  > *"Pop-up decision options shall not have any delimiters such as `/` and `|`
  > and instead should have sufficient spaces to separate the options nicely
  > (e.g. `[Y]es   [N]o   [ESC]=Cancel`)."*

### 2.28 Save File UI Format Option Uses Parenthesized Colon Hotkey
- [x] Standardize Save File UI line ending format hotkey into bracket notation.
  - In `src/se.asm:23832` (`STR_SAVE_FMT_SUFFIX`), rendered by
    `PRINT_SAVE_FMT_INFO` (`src/se.asm:18075-18094`):
    `"]  (^F: toggle format)"` prints `Format: [CP/M]  (^F: toggle format)`.
  - This uses parentheses `( )` and legacy colon syntax `^F: toggle format`.
  - Refactor to canonical bracket notation:
    `Format: [CP/M]   [^F]=Toggle Format` (or `[^F]=Toggle`).
- *Key Sequence (from splash)*:
  - Press `S`.
  - Observe Save File screen: the format row displays
    `Format: [CP/M]  (^F: toggle format)` using parenthesized colon syntax
    `(^F: toggle format)` rather than bracket notation `[^F]=Toggle Format`.
- *Justification* (`docs/UI_UX_DESIGN.md` Section 1.6, 4.1, 7.4):
  > *"Action hotkeys shall be expressed inside `[ ]` pairs (e.g. `[Y]es   [N]o
  > [ESC]=Cancel`). The `Y:Yes, N:No` forms are no longer allowed."* Action
  > triggers must not use `( )` or colon syntax.

### 2.29 Plugin Configuration Pop-ups Omit Toggle Hotkeys and Delimiters
- [x] Bring plugin configuration dialog footers and option labels into UI/UX
  compliance.
  - In `plugins/beautify.asm:1711-1724` (`STR_BTC_L4`..`STR_BTC_L9`) and
    `plugins/wordcnt.asm:480-484` (`STR_WCC_L4`..`STR_WCC_L7`):
    - Footers (`STR_BTC_L9`, `STR_WCC_L7`) display
      `| [Enter]=Save & Exit   [ESC]=Cancel |` but omit the numeric hotkeys
      (`[1]`, `[2]`, `[3]`, `[4]`) used to toggle individual settings.
    - Setting rows use unbracketed labels (`1. Columns   : [`,
      `1. Count Blank Lines  : [`) rather than bracketed option selectors
      (`[1] Columns: [`, `[1] Count Blank: [`).
    - In `plugins/wordcnt.asm:480-483`, closing brackets on setting rows
      (`YES]     |` vs `YES]       |`) are horizontally misaligned.
- *Key Sequence (from splash)*:
  - Press `P` -> `C` (with Beautify in Slot 0).
  - Observe Beautify configuration pop-up: footer displays
    `| [Enter]=Save & Exit   [ESC]=Cancel |` omitting toggle keys `[1]`-`[4]`,
    and option rows use unbracketed labels `1.`, `2.`, `3.`, `4.`.
- *Justification* (`docs/UI_UX_DESIGN.md` Section 1.6, 2.2, 4.1, 7.4):
  > Selectors and action hotkeys must be bracketed (`[1]`), options footers
  > must document valid hotkeys, and dialog fields must maintain clean
  > vertical column alignment.

### 2.30 Misalignment of Splash Screen "Active Screen" Status Bracket
- [ ] Align opening bracket of "Active Screen" status row with subsequent
  status lines on splash screen.
  - In `src/se.asm:23592`, `STR_SPLASH_CUR_MODE` is defined as:
    `STR_SPLASH_CUR_MODE: DB "Active Screen: [$"`
    which contains 15 characters before the opening bracket `[` (13 characters
    for `"Active Screen"`, 1 colon, and 1 space).
  - In contrast, all subsequent status rows rendered by `RENDER_SPLASH`
    (`src/se.asm:2014-2112`) contain exactly 16 characters before the opening
    bracket `[`:
    - `STR_SPLASH_RAM_PRE` + `STR_SPLASH_RAM_LTR`: `"RAM Drive (A:): ["` (16)
    - `STR_SPLASH_RAM_NONE`: `"RAM Drive     : ["` (16)
    - `STR_SPLASH_PLUG_PRE`: `"Plugin System : ["` (16)
    - `STR_SPLASH_LINES_PRE`: `"Max Lines     : ["` (16)
  - Because `STR_SPLASH_CUR_MODE` has no space before the colon
    (`"Active Screen: ["` instead of `"Active Screen : ["`), the opening
    bracket `[` on the Active Screen row starts at column 16 instead of column
    17, starting 1 space to the left of all subsequent status indicators and
    breaking vertical column alignment.
  - Add 1 space before the colon (`"Active Screen : [$"`) so the label is 16
    characters and the bracket aligns with column 17 matching all status rows.
- *Key Sequence (from splash)*:
  - Launch `SE.COM` (or return to splash screen).
  - Observe the four status rows beneath the command list: the opening bracket
    `[` on `Active Screen: [` starts 1 character to the left of the brackets on
    `RAM Drive (A:): [`, `Plugin System : [`, and `Max Lines     : [`.
- *Justification* (`docs/UI_UX_DESIGN.md` Section 1.4, 4.3):
  > Screen content, tabular command lists, and parameter fields shall maintain
  > strict vertical column alignment across rows.

### 2.31 Remove Visible Cursor from Save Changes and Unload Plugin Modals
- [ ] Suppress visible blinking cursor in single-keystroke choice pop-ups.
  - In `src/se.asm:1326-1335` and `1379-1385` (`DO_SAVE_CHANGES_POPUP`), the
    "Unsaved Modifications" modal explicitly positions and enables the
    terminal cursor on the query line after `"Save changes? "`
    (`Row = POPUP_SAVE_START_ROW + 4, Col = POPUP_COL + 32`, followed by
    `CALL TERM_SHOW_CURSOR`).
  - In `plugins/plugin.asm:1069-1080` (`SHOW_UNLOAD_CONFIRM`), the "Unload
    Plugin" modal similarly positions the cursor after `"Unload Slot N? "`
    and emits `STR_SHOW_CURSOR`.
  - Unlike text-entry dialogs (Find, Replace, Goto Line) where an active
    cursor is required inside a bracketed input field, both "Unsaved
    Modifications" and "Unload Plugin" are single-keystroke choice dialogs
    (`[Y]es   [N]o   [ESC]=Cancel`).
  - Displaying a blinking cursor on the prompt line creates visual clutter
    and is inconsistent with other modal query and status dialogs.
  - Remove `TERM_SHOW_CURSOR` emissions and ensure the terminal cursor remains
    hidden throughout both modal query loops.
- *Key Sequence (from splash)*:
  - Sequence A (Unsaved Modifications): Press `E` -> type `X` -> `Ctrl+Q`.
    Observe Row 5: a blinking cursor appears after `"Save changes? "`.
  - Sequence B (Unload Plugin): Press `P` -> `Enter` (on occupied slot).
    Observe Row 5: a blinking cursor appears after `"Unload Slot 0? "`.
- *Justification* (`docs/UI_UX_DESIGN.md` Section 1.4, 2.2):
  > Modal presentation for single-key decision pop-ups must eliminate visual
  > clutter. Blinking cursors belong inside or adjacent to text input fields,
  > not trailing static query prompts.

### 2.32 Redundant "SE.COM" Prefix in Open, Save, Help, Insert & Block Screens
- [ ] Remove "SE.COM" from screen titles in file open, save, help, insert, and
  block selection workspaces.
  - In `src/se.asm:23796-23808`, directory screen title prefixes include the
    executable binary filename `"SE.COM - "`:
    - `STR_TITLE_OPEN_PRE`: `"SE.COM - OPEN FILE (DIRECTORY - DRIVE "`
    - `STR_TITLE_SAVE_PRE`: `"SE.COM - SAVE FILE (DIRECTORY - DRIVE "`
    - `STR_TITLE_BLOCK_SAVE_PRE`: `"SE.COM - SAVE BLOCK (DIRECTORY - DRIVE "`
    - `STR_TITLE_INSERT_PRE`: `"SE.COM - INSERT FILE (DIRECTORY - DRIVE "`
    - `STR_TITLE_PLUG_LOAD_PRE`: `"SE.COM - LOAD PLUGIN (DIRECTORY - DRIVE "`
  - In `plugins/help.asm:370`, the Ctrl+K editor keys help screen title
    `STR_HELP_TITLE` is defined as `"SE.COM - EDITOR MODE KEYS"`, and centered
    via hardcoded length `SUB 25` in `RENDER_HELP_TITLE`
    (`plugins/help.asm:283`).
  - Displaying the binary program filename `"SE.COM"` in workspace headers is
    redundant and inconsistent with other screens (e.g. Splash:
    `"SE - Screen Editor"`, Config: `"SE - Screen Editor Configuration"`,
    Plugin Manager: `"SE - Plugin Manager"`). It also consumes horizontal
    space needed for directory paths and filters.
  - Remove `"SE.COM - "` from the title string constants, and adjust base
    title length constants in `RENDER_TITLE_COMMON` (`src/se.asm:17031-17049`)
    from 41..43 down to 32..34 and in `plugins/help.asm:283` from 25 to 16
    so dynamic horizontal centering remains exact.
- *Key Sequence (from splash)*:
  - Sequence A (Open File screen): Press `O`.
    Observe screen title: `SE.COM - OPEN FILE (DIRECTORY - DRIVE A:)`
    redundantly displays `"SE.COM - "`.
  - Sequence B (Save File screen): Press `S`.
    Observe screen title: `SE.COM - SAVE FILE (DIRECTORY - DRIVE A:)`
    redundantly displays `"SE.COM - "`.
  - Sequence C (Insert File screen): Press `E` -> `Ctrl+R`.
    Observe screen title: `SE.COM - INSERT FILE (DIRECTORY - DRIVE A:)`.
  - Sequence D (Block Save screen): Press `E` -> `Ctrl+K` -> `Ctrl+S`.
    Observe screen title: `SE.COM - SAVE BLOCK (DIRECTORY - DRIVE A:)`.
  - Sequence E (Help screen): Press `E` -> `Ctrl+K` (without block selection).
    Observe screen title: `SE.COM - EDITOR MODE KEYS`.
- *Justification* (`docs/UI_UX_DESIGN.md` Section 1.4, 2):
  > Screen titles must be concise and uncluttered, centered as the top element
  > of the content block without redundant executable binary artifacts.

### 2.33 Splash Screen Omits Ctrl+P Context-Aware Plugin Menu Command
- [ ] Document `[^P]` context-aware plugin menu shortcut in splash screen
  command list.
  - In `src/se.asm:398-406`, the splash screen event loop already supports
    `Ctrl+P` (`KEY_CTRL_P`) to open the context-aware plugin modal menu
    (`DO_CONTEXT_PLUGIN_POPUP` with `PLUG_CTX_SPLASH`).
  - However, in `src/se.asm:23576-23590` (`STR_SPLASH_CMDS`), the splash
    command menu only documents `[P]` (`"  type   [P]              for plugins"`
    to open the Plugin Manager), completely omitting the `[^P]` shortcut that
    opens the context-aware plugin menu palette.
  - Users on the splash screen are given no visual indication that `Ctrl+P` is
    an available command.
  - Add an entry in `STR_SPLASH_CMDS` for `[^P]` (e.g.
    `"  type   [^P]             for context plugin menu"`), and update
    `SPLASH_MENU_LINES` (`src/se.asm:1905`) from 20 to 21 to maintain dynamic
    vertical centering with symmetrical 1-row padding on 80x24 geometry.
- *Key Sequence (from splash)*:
  - Launch `SE.COM` (or return to splash screen).
  - Observe the command list: `[P]` is shown for plugins, but `[^P]` is absent.
  - Press `Ctrl+P`: the context-aware plugin menu pop-up appears immediately,
    demonstrating that the feature exists but is omitted from the splash menu.
- *Justification* (`docs/UI_UX_DESIGN.md` Section 1.4, 2.1):
  > Primary actions and modal shortcuts supported by full-screen workspaces
  > must be discoverable and documented in the screen command list.

### 2.34 "Opening File" Progress Dialog Line Counter Leaks Debris Trailing Zero
- [ ] Fix unoverwritten trailing zero debris causing 1,000-line counter jumps in
  file progress modal dialogs.
  - In `src/se.asm:23402-23403`, the initial modal line template is defined
    in `STR_POPUP_PROGRESS_LINE`:
    `"|                   Line      0                  |"`
    The `"Line "` prefix occupies box columns 21..25, followed by 5 spaces
    (columns 26..30) and an initial `'0'` at column 31 (box relative offset 30).
  - In `src/se.asm:15228-15256` (`UPDATE_LOAD_PROGRESS`), dynamic progress
    updates locate the cursor at box column 21 (`POPUP_COL + 20`), print
    `STR_PROGRESS_LINE_LBL` (`"Line "`), and right-justify the line count in
    a 5-character field (`5 - digits` spaces + decimal digits).
  - This 5-character field strictly spans columns 26..30. The routine never
    overwrites or clears column 31.
  - When loading a file, `FILE_LOAD_LOOP` (`src/se.asm:14800-14807`) triggers
    an update every 100 lines. At 100 lines, `UPDATE_LOAD_PROGRESS` writes
    `"  100"` across columns 26..30. Because column 31 retains the initial
    template `'0'`, the screen displays `"  1000"`.
  - At 200 lines, it writes `"  200"`, which combines with the trailing debris
    zero to display as `"  2000"`. The counter appears to count up in jumps of
    1000 instead of 100. The same defect affects file insertion
    (`src/se.asm:16234`) and file saving (`src/se.asm:19947`).
  - Adjust `STR_POPUP_PROGRESS_LINE` to align the initial `'0'` at column 30
    (4 spaces after `"Line "` instead of 5) or blank the field with spaces, and
    ensure `UPDATE_LOAD_PROGRESS` clears/overwrites the entire field width.
- *Key Sequence (from splash)*:
  - Press `O` -> select or type a file with >= 200 lines (e.g. `A:SE.ASM`) ->
    press `Enter`.
  - Observe the centered "Opening File" progress modal dialog: during load,
    the counter increments in apparent steps of 1000 (`1000`, `2000`, `3000`...)
    instead of 100 (`100`, `200`, `300`...) due to the unoverwritten trailing
    zero at column 31.
- *Justification* (`docs/UI_UX_DESIGN.md` Section 1.4, 2.2):
  > Modal dialogs and status displays must present accurate numerical values
  > without residual visual artifacts, character debris, or unoverwritten
  > positions from static background templates.

### 2.35 "File Not Found" Modal Pop-up Omits Target Filename
- [ ] Dynamically display the target filename enclosed in single quotes `' '` in
  the "File Not Found" status modal pop-up.
  - In `src/se.asm:11673-11677` (`SHOW_POPUP_FILE_NOT_FOUND`), when a file
    fails to open in `DO_OPEN_FILE_UI` (`src/se.asm:15547`), plugin loading
    (`src/se.asm:15610`), or document loading (`src/se.asm:22264`), the modal
    displays static pre-baked strings from `src/se.asm:23529-23535`:
    - Title: `"|                 File Not Found                 |"`
    - Msg 1: `"|               File was not found.              |"`
    - Msg 2: `"|        Specified file not found on disk.       |"`
  - Both message lines are completely generic boilerplate and provide no
    feedback as to which file could not be located.
  - In contrast, other error dialogs (such as `HELP.OVL was not found.` in
    `STR_POPUP_HELP_MISS_MSG1` and file progress headers formatted by
    `FORMAT_PROGRESS_FILE_LINE`) explicitly state the filename.
  - Update `SHOW_POPUP_FILE_NOT_FOUND` to dynamically format the requested
    target filename (from `INPUT_FILENAME_BUF` / `WORK_FCB` / `FAT_DOC_FNAME`)
    enclosed in single quotes (e.g. `'NOFILE.TXT' was not found.` or
    `File 'NOFILE.TXT' was not found.`), centered horizontally within the
    50-column Tier 2 modal box.
- *Key Sequence (from splash)*:
  - Press `O` -> type `NOFILE.TXT` in the filename edit box -> press `Enter`.
  - Observe the centered "File Not Found" pop-up: Line 4 displays generic
    `File was not found.` without showing `'NOFILE.TXT'`.
- *Justification* (`docs/UI_UX_DESIGN.md` Section 1.4, 2.2):
  > Status event pop-ups must provide meaningful, specific context for the
  > failed operation. Error notifications for missing files must identify
  > the target resource by name rather than generic static boilerplate.

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
