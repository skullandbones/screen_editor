# SE.COM — UI/UX Design System & Specification
================================================================================
Canonical UI/UX Specification for Cross-Platform Implementations of SE
================================================================================

1. Scope, Purpose & Invariance Mandate
--------------------------------------------------------------------------------
This specification establishes the authoritative visual layout, terminal
interaction protocols, surface hierarchy, and keybinding behaviors of the
classic CP/M Screen Editor (`SE.COM`) and its modular plugins.

All native and multi-platform ports—including the Linux C executable
(`se-linux`), the Python 3 implementation (`se-py`), future Rust (`se-rs`),
CP/M-86 (`SE.CMD`), and ZX Spectrum Next (`SE_NEXT.COM`, `SE.NEX`, `.se`)
variants—must conform 100% to this specification.

All AI agents and human developers modifying or creating user interfaces in
this codebase must adhere strictly to these principles.

The overarching design objective is Zero Cognitive Friction:
A user transitioning between 8-bit CP/M hardware and a modern 64-bit Linux
workstation or Raspberry Pi must encounter an identical visual aesthetic,
identical screen geometry, identical modal lifecycles, and identical canonical
keybindings.

Keybinding Discipline & WordStar Diamond Deprecation:
All SE implementations adhere strictly to the canonical keybinding matrix
(Section 10). Directional navigation is provided exclusively by standard
ANSI VT100 arrow keys and standard navigation shortcuts. Legacy WordStar
diamond directional navigation (`^S`, `^D`, `^E`, `^X`) is strictly not
supported across any surface or modal dialog to eliminate command collision
with Save, Delete, End, and Cut.

Build Profile Divergence & Conditional Directives Mandate:
Across shared source modules (such as portable C core files in `src/core/` and
shared Z80 assembly components in `src/`), source code conditional compilation
directives (`#ifdef __CPM__`, `#ifndef __CPM__`) and conditional assembly
directives (`IFDEF`, `IFNDEF`, `ELSE`, `ENDIF`) shall strictly be used to
accommodate platform-specific divergence between build profiles and targets
(Section 14.5). Developers and automated agents must never globally modify
shared code to satisfy constraints of one build profile if doing so impairs or
breaks another.

2. Terminal Architecture, Geometries & Character Budget
--------------------------------------------------------------------------------
1. Standard Screen Geometries:
   - Option 1 — Standard Terminal (Default): 80 columns x 24 rows (`80x24`).
     - Rows 1 to 23: Workspace / Document text viewport.
     - Row 24: Universal Status Bar (fixed bottom anchor).
     - Universal baseline standard and default screen size across all SE
       implementations and hardware targets because 80x24 is supported on all
       systems.
     - On splash screens, hotkey `1` is universally assigned to `80x24`.
   - Option 2 — Wide Console (if supported): 120 columns x 40 rows (`120x40`).
     - Rows 1 to 39: Workspace / Document text viewport.
     - Row 40: Universal Status Bar (fixed bottom anchor).
     - On platforms supporting 120x40 wide console mode, hotkey `2` is
       assigned to `120x40`.
     - If 120x40 screen size is not supported on a target platform, Option 2 on
       the splash screen will not be shown and 120x40 screen size will not be
       supported on that target.
   - Option 3 — Native Host Terminal (if supported):
     - Dynamic host terminal dimensions (`HOST_COLS x HOST_ROWS`).
     - Supported on native platforms (Linux, POSIX, macOS) capable of querying
       actual terminal emulator dimensions (via `ioctl(TIOCGWINSZ)` or
       `os.get_terminal_size()`).
     - On platforms supporting dynamic native resizing, hotkey `3` is assigned
       to `Native` mode.
     - If dynamic host sizing is not supported on a target platform, Option 3
       will not be shown on the splash screen.
   - Screen Switching Debris Prevention Mandate:
     Prior to switching screen sizes (between 80x24, 120x40, or Native), the
     terminal screen must be explicitly cleared (emitting ANSI clear sequence
     `\x1b[2J\x1b[H` / `TERM_INIT`) so that no character artifacts, margin
     remnants, or status bar ghosts are left as debris on the screen.

2. Coordinate System:
   - All screen positioning uses 1-based ANSI terminal coordinates:
     `(Row, Column)` where `(1, 1)` is the top-left character cell.
   - `Row` spans `1 .. HOST_ROWS` (24 or 40).
   - `Column` spans `1 .. HOST_COLS` (80 or 120).

3. Character Budgeting & Zero Unplanned Scrolling:
   - The terminal must never emit unchecked carriage returns or line feeds
     at `Row == HOST_ROWS` that induce hardware scrolling.
   - Every single character cell on the screen is strictly budgeted.
   - Output lines must never exceed `HOST_COLS` characters.

4. Standard ANSI / VT100 Control Sequences:
   - Cursor locate        : `\x1b[{row};{col}H`
   - Inverse video enable : `\x1b[7m`
   - Inverse video disable: `\x1b[0m`
   - Clear entire screen  : `\x1b[2J\x1b[H`
   - Clear to end of line : `\x1b[K`
   - Hide cursor          : `\x1b[?25l`
   - Show cursor          : `\x1b[?25h`

5. Terminal Lifecycle, Session Startup & Exit Discipline:
   - Startup Screen Clear & Initialization:
     On launch, SE initializes the terminal subsystem via `TERM_INIT`:
     1. Disables reverse video and resets text rendition (`\x1b[0m`).
     2. Ensures the hardware cursor is visible (`\x1b[?25h`).
     3. Clears the entire terminal screen and homes cursor to `(1, 1)`
        via ANSI escape sequence (`\x1b[2J\x1b[H`).
     This guarantees that any preceding shell command output, scrollback, or
     stray attributes are completely wiped before rendering the initial
     workspace or splash screen.
   - Clean Session Exit & Exit Message:
     On program termination (e.g. `Ctrl+K X` or `Ctrl+Q` exit confirmed), SE
     restores host terminal discipline via `EXIT_PROGRAM`:
     1. Flushes buffers and cleans up temporary swap files.
     2. Clears the entire terminal screen via `TERM_INIT`
        (`\x1b[0m\x1b[?25h\x1b[2J\x1b[H`).
     3. Emits the canonical exit message string followed by CRLF:
        `\r\nExiting <BINARY>. Returned to CP/M.\r\n` (on CP/M targets, e.g.
        `SE.COM`, `SE_NEXT.COM`, or `SE.CMD`), or
        `\r\nExiting SE. Returned to OS prompt.\r\n` (on host/Linux targets).
     4. Explicitly restores hardware cursor visibility (`TERM_SHOW_CURSOR`).
     5. Restores original host/CP/M environment state (user area, RAM drive,
        saved stack pointer) and exits cleanly.
     Under no circumstances may an SE port terminate leaving dirty viewport
     contents, hidden cursors, or unreset video attributes in the terminal.

6. VT100 & ASCII Terminal Encoding Mandate (UTF-8 Prohibition):
   If the terminal is VT100, VT102, or a similar CRT/serial terminal (standard
   across 8-bit CP/M and retro hardware), the use of UTF-8 (such as Unicode
   em-dashes `—`, curly quotes, or multi-byte glyphs) is strictly not allowed
   to be used by the editor. All text and control output must strictly adhere
   to standard 7-bit ASCII (`0x20`–`0x7E`). Application titles must use the
   ASCII hyphen-minus `-` (`0x2D`), e.g. `SE - Screen Editor`.

7. Version Number Harmonization Mandate:
   All SE variants across all target platforms (CP/M, ZX Spectrum Next, Linux,
   Python, etc.) must use the exact same release version number as canonical
   SE.COM (e.g. `v1.1.0`). Independent or divergent versioning across ports is
   strictly prohibited.

3. Screen Surface Taxonomy (The Three Tiers)
--------------------------------------------------------------------------------
Every visual surface in SE belongs strictly to one of three tiers. Ports must
never blur or blend elements across tiers.

- Tier 1: Full-Screen Workspaces
  - Dedicated surfaces replacing the document viewport.
  - Examples: Active Document Editor, Splash Screen, File Open / Save UI,
    Configuration Manager, Help Workspace, Directory Browser.
  - Characteristics: Non-document workspaces are centered horizontally and
    vertically, framed by column 0 tildes (`~`) on empty margin rows, and
    anchored by the Tier 3 status bar on the bottom row.

- Tier 2: Centered Boxed Modal Pop-ups
  - Centered ASCII framed overlay dialogs.
  - Examples: Status Event Notifications, Query/Confirmation Modals, Text Input
    Prompts, Selection Menus (Plugin Palette).
  - Characteristics: Distinct ASCII borders (`+---+`, `|   |`), mathematically
    centered in 1-based coords, single-level visibility with child isolation.

- Tier 3: Universal Status Bar
  - Persistent, single-line inverse video banner anchored on `HOST_ROWS`.
  - Characteristics: 100% presence on all screens (including pop-up screens).
    Strictly displays persistent document and system state; never status events.

4. Universal Status Bar Specification
--------------------------------------------------------------------------------
The status bar is the sole fixed screen anchor in SE.

1. Universal Presence Mandate:
   - The status bar shall be displayed on the bottom row (`HOST_ROWS`) of all
     screens without exception.
   - It appears on the Splash Screen, Editor Workspace, Help Screen, Config
     Manager, Directory Browsers, and behind Tier 2 pop-up screens.
   - On non-document screens, the status bar reflects the last document status
     of the active editing session.

2. Visual Presentation:
   - Inverse Video: Rendered entirely in reverse video (`\x1b[7m ... \x1b[0m`).
   - No Column 0 Tilde: Column 0 of the status bar row never contains a tilde.
   - Centering / Padding: On terminal geometries wider than the formatted text,
     the status bar text is centered or evenly padded across the full row.

3. Field Layout & Structure (80-Column Budget):
   The status bar consists of 5 fixed functional fields enclosed within outer
   separators, totaling exactly 78 reverse-video characters centered on screen
   (1 leading space, 78 enclosed characters, 1 trailing space = 80 columns):

   +-----------------------------------------------------------------------+
   | | FILENAME.EXT* |  80x24 | CP/M  | ^K: Editor keys | Line   1/1 Col 0 | |
   +-----------------------------------------------------------------------+

   - Enclosure & Alignment Budget:
     - Symmetrical Margin Padding:
       `LeftPad = RightPad = (ACTIVE_COLS - 78) / 2`
       On 80-column screens: 1 space left, 1 space right (`1 + 78 + 1 = 80`).
       On 120-column screens: 21 spaces left, 21 spaces right.
     - Extreme Left Enclosure (2 chars): `| `
     - Extreme Right Enclosure (2 chars): ` |`
     - Total Enclosed Width (`STATUS_ENCLOSED_WIDTH`): exactly 78 characters.

   - Editor Name & Version Exclusion Mandate:
     The status bar does NOT show 'SE.COM' or the version number. Field 1
     strictly displays the active document filename `{name}{mod}`. Port
     implementations must never replace Field 1 with application banners.

   - Field 1 (Filename, 17 chars: 14 chars name + ` | ` separator):
     - `{name}`: Active filename (e.g. `README.TXT`, `C:MAIN.C`, `(Untitled)`).
     - `{mod}`: `*` if document has unsaved modifications; space otherwise.
     - Filename content (`{name}{mod}`) is padded with spaces or truncated to
       strictly 14 characters (`%-14.14s`) so long filenames on host OS
       targets never expand Field 1 or push Field 5 off an 80-column screen.
     - Followed by field separator: ` | ` (3 chars). Total: 17 characters.

   - Field 2 (Geometry, 9 chars): ` {geom} | `
     - Formatted string: ` 80x24 | ` (1 leading space) or `120x40 | `
       (0 leading spaces). Total: exactly 9 characters.

   - Field 3 (Operating Environment / Format, 8 chars): ` {fmt} | `
     - Formatted string: `CP/M  | ` (default CP/M 2.2), `Linux | `, or spaces
       during file loading (`      | `).
     - Total: exactly 8 characters.

   - Field 4 (Dynamic Context / Mode, 18 chars: 15 chars content + ` | `):
     Field 4 is a dedicated 15-character contextual slot followed by separator
     ` | ` (18 characters total). It operates under a strict priority hierarchy
     applicable across all SE variants:
     1. Splash Screen, Directory Browsers & Far Plugin Execution:
        Displays free document memory in whole KB: `Free: <N> KB` padded with
        spaces to 15 characters, followed by ` | ` (e.g. `Free: 48 KB    | `).
        Tier 1 Directory Browser Workspaces (Open File, File Insert, Save File,
        and Block Save) operate as overlay surfaces displaying free memory (or
        blank per the fallback rule), strictly prohibiting editor mode cues
        (`^K: Editor keys`).
        - Variant Free Memory Reading Fallback Rule:
          If a port, target platform, or variant does not support a free memory
          reading method (or dynamic TPA/heap query), the free memory status on
          the status bar shall be left blank (15 spaces + separator:
          `               | `).
     2. Active Dynamic Block Selection (`BLOCK_ACTIVE == 1`):
        Displays live selection size metrics padded to 15 characters + ` | `:
        - Single-line: `Sel: <N> char | ` (1 char) or `Sel: <N> chars | `
        - Multi-line: `Sel: <N> line | ` (1 line) or `Sel: <N> lines | `
     3. Solidified Block Selection (`BLOCK_ACTIVE == 2`):
        Displays locked block size metrics padded to 15 characters + ` | `:
        - Single-line: `Block: <N> char | ` / `Block: <N> chars | ` (or
          `Block: <N>c   | ` if characters >= 100)
        - Multi-line: `Block: <N> line | ` / `Block: <N> lines | ` (or
          `Block: <N>L    | ` if lines >= 100)
     4. Horizontal Viewport Panning (`VIEW_LEFT_COL > 0`, normal keys):
        Displays `[Pan +<offset>]` padded with spaces to 15 characters + ` | `
        (e.g. `[Pan +40]      | `).
     5. Overwrite Mode (`!INSERT_MODE`):
        Displays `Overwrite mode  | ` (15 chars content + separator).
     6. Default Editor Help Hint (Normal Insert Mode):
        Displays `^K: Editor keys | ` (15 chars content + separator).

   - Field 5 (Fixed Cursor Coordinates, 24 chars: 22 chars content + ` |`):
     Field 5 is a fixed-width, jitter-free coordinate anchor strictly dedicated
     to cursor coordinates:
     - Fixed Content (22 chars): `Line <cur:4>/<tot:4> Col <col:3>`
       - `"Line "` (5 chars label)
       - `<cur:4>`: Current document line (1-indexed), right-justified in 4
         characters (`   1` .. `9999`)
       - `"/"` (1 char fixed delimiter)
       - `<tot:4>`: Total document lines, left-justified in 4 characters
         (`1   ` .. `9999`)
       - `" Col "` (5 chars fixed delimiter)
       - `<col:3>`: Visual column (0-indexed, tabs expanded), left-justified in
         3 characters (`0  ` .. `999`)
     - Followed by Extreme Right Enclosure: ` |` (2 chars).
     - Loading State: During asynchronous loading, displays
       `Line    1/---- Col   0 |`.
     - Fixed-Width Jitter-Free Mandate:
       Field 5 MUST NOT contain variable-length tags, mode indicators, or pan
       offsets (`[SEL]`, `[BLK LOCK]`, `[Pan +40]`). Appending variable-length
       tags to Field 5 causes severe cursor coordinate jitter, destroys column
       alignment, and exceeds the 78-character enclosed width (Anti-Pattern #3:
       Terminal Column Spill). All mode and contextual indicators belong
       strictly in Field 4.

4. Status Event Prohibition:
   - The status bar shall NEVER display status events (e.g. "File saved",
     "Search string not found", "Pattern replaced").
   - All status events MUST be presented as Tier 2 centered modal pop-up boxes.
   - Hard Rule: Never implement interactive multi-character input loops
     directly on the status row (Anti-Pattern #1: Status Bar Squatting).

5. Column 0 Tilde (~) Discipline
--------------------------------------------------------------------------------
1. Purpose & Semantic Meaning:
   - A tilde (`~`) in column 0 signifies unallocated, non-document buffer space
     or background margin rows. It prevents visual ambiguity between empty
     lines of a document and lines that do not exist in the buffer.

2. Mandatory Tilde Locations:
   - Editor Workspace: Every screen row below the final line of the document
     must display a `~` in column 0, followed by blank space to `HOST_COLS`.
   - Centered Tier 1 Workspaces (Splash, Help, Config, File Dialogs): Every
     top margin row above the centered content block and every bottom margin row
     below the content block (down to row `HOST_ROWS - 1`) must display a `~` in
     column 0.
   - Pop-up Backgrounds: Any unallocated background row behind a modal dialog
     must retain its column 0 tilde.

3. Strict Tilde Exclusions:
   - The status bar row (`HOST_ROWS`) never has a tilde.
   - Rows containing active document lines never have a column 0 tilde.
   - Rows inside Tier 2 modal pop-up dialog boxes never have a column 0 tilde.

6. Editor Viewport Cursor Mechanics & Horizontal Panning
--------------------------------------------------------------------------------
Porting SE.COM cursor handling requires conforming 100% to the exact state
machine, coordinate spaces, tab expansion rules, sticky target columns, and
viewport panning algorithms defined in `src/core/editor.asm` and
`src/core/ui_render.asm`.

1. Architectural State Variables & Coordinate Spaces:
   The editor controller maintains six fundamental position variables:
   - `CUR_DOC_ROW` (16-bit): 0-indexed document line number
     (`0 .. DOC_TOTAL_LINES - 1`).
   - `TOP_DOC_ROW` (16-bit): 0-indexed document line number aligned with
     the top row of the visible text viewport (Screen Row 1).
   - `CUR_COL` (16-bit): 0-indexed byte/character offset within the active
     line buffer (`0 .. line_len`). In lines containing tabs, this is the raw
     character index, NOT the visual column.
   - `TARGET_COL` (16-bit): 0-indexed sticky visual target column
     (`0 .. MAX_LINE_CHARS - 1`). Updated only by horizontal movements
     (Left, Right, Home, End) or text edits; preserved across vertical
     movements (Up, Down, PgUp, PgDn).
   - `VIEW_LEFT_COL` (16-bit): 0-indexed visual column currently aligned
     with the leftmost text column of the viewport (0, 40, 80...).
   - `VIEW_RIGHT_COL` (16-bit): `VIEW_LEFT_COL + ACTIVE_COLS` (80, 120...).

   These variables map across three distinct coordinate spaces:
   - Buffer Space: `(CUR_DOC_ROW, CUR_COL)` — 0-indexed character offsets.
   - Document Visual Space: `(CUR_DOC_ROW, VisualCol)` — 0-indexed column
     coordinates with all tab characters fully expanded to tab stops.
   - Terminal Screen Space: `(ScreenRow, ScreenCol)` — 1-indexed ANSI
     coordinates dispatched to hardware via `\x1b[{row};{col}H`.

2. Tab Character Representation, Expansion & Traversal:
   - In-Memory Storage:
     Tab characters are stored as literal ASCII byte `0x09` (`KEY_TAB`) in
     document line buffers. A tab occupies exactly 1 byte in `CUR_COL`.
   - Tab Stop Quantum Formula (`GET_TAB_SPACES`):
     Tab stops occur at intervals of `CFG_TAB_WIDTH` (default 8 columns,
     configurable to 4 across all SE variants). From any visual column `col`,
     the number of space columns required to advance to the next tab stop is:
     `tab_spaces = tab_width - (col % tab_width)`
   - Visual Column Mapping (`CALC_VISUAL_COL`):
     To map buffer offset `CUR_COL` to document visual column `VisualCol`:
     1. Initialize `vis_col = 0`.
     2. For each byte offset `i` from `0` to `CUR_COL - 1`:
        - If `line[i] == 0x09` (`KEY_TAB`):
          `vis_col += tab_width - (vis_col % tab_width)`.
        - Else:
          `vis_col += 1`.
     3. Clamp `vis_col` to `MAX_LINE_CHARS - 1`.
   - Discrete Traversal & Tab Exclusion Mandate:
     The cursor is pinned strictly to discrete character boundaries in buffer
     space. The cursor jumps over tabs and can NEVER be within a tab:
     - Discrete Jump Over Tabs: In buffer space, a tab is a single byte at
       offset `CUR_COL`. In visual and screen space, a tab expands across
       `tab_spaces` display cells. The cursor always jumps over the entire tab
       in a single keypress leap rather than stepping through spaces.
     - Tab Interior Exclusion: The cursor can NEVER be positioned, placed,
       or rest within an expanded tab. No valid cursor coordinate exists
       between `vis_col + 1` and `vis_col + tab_spaces - 1`.
     - Moving Right: Advancing past a tab leaps the cursor forward from
       `vis_col` across the full tab width to `vis_col + tab_spaces` in
       a single keypress.
     - Moving Left: Retreating over a tab leaps the cursor backward from
       `vis_col + tab_spaces` to the visual column preceding the tab in a
       single keypress.
     - Universal Exclusion: All navigation modes (horizontal arrows, word
       skips, vertical line navigation, and horizontal panning) must preserve
       this rule. The cursor must never land inside a tab.
     - Vertical Alignment Clamping (`ADJUST_COL_TO_TARGET`): If the sticky
       target column `TARGET_COL` falls within the span of an expanded tab
       (`vis_acc < TARGET_COL < vis_acc + spaces`), the editor employs
       snap-forward alignment: the cursor snaps forward to the discrete
       character boundary directly following the tab (`vis_acc + spaces`),
       preserving the Tab Exclusion Mandate while keeping the cursor adjacent
       to indented code rather than retreating to the margin.

3. Horizontal Navigation (Left, Right, Home, End) & Line Wrapping:
   Horizontal cursor movements update both `CUR_COL` and sticky `TARGET_COL`.
   Directional movement is handled exclusively by ANSI VT100 arrow keys;
   legacy WordStar diamond navigation (`Ctrl+S` left, `Ctrl+D` right) is
   unsupported to prevent collisions with Save File and Forward Delete.
   - Cursor Left (`CURSOR_LEFT` / Arrow Left):
     - If `CUR_COL > 0`: `CUR_COL -= 1`.
     - If `CUR_COL == 0` and `CUR_DOC_ROW > 0`:
       Wrap to end of previous line:
       `CUR_DOC_ROW -= 1`.
       `CUR_COL = len(line[CUR_DOC_ROW])`.
       If `CUR_DOC_ROW < TOP_DOC_ROW`: Viewport scrolls up:
       `TOP_DOC_ROW = CUR_DOC_ROW`.
     - If `CUR_COL == 0` and `CUR_DOC_ROW == 0`: Blocked (no-op).
     - Update sticky target: `TARGET_COL = CALC_VISUAL_COL(CUR_COL)`.
   - Cursor Right (`CURSOR_RIGHT` / Arrow Right):
     - Let `line_len = len(line[CUR_DOC_ROW])`.
     - If `CUR_COL < line_len`:
       `CUR_COL += 1`.
     - If `CUR_COL >= line_len` and `CUR_DOC_ROW + 1 < DOC_TOTAL_LINES`:
       Wrap to beginning of next line:
       `CUR_DOC_ROW += 1`.
       `CUR_COL = 0`.
       Screen row = `CUR_DOC_ROW - TOP_DOC_ROW`.
       If `ScreenRow > ACTIVE_ROWS - 2`: Viewport scrolls down:
       `TOP_DOC_ROW += 1`.
     - If at end of last document line: Blocked (no-op).
     - Update sticky target: `TARGET_COL = CALC_VISUAL_COL(CUR_COL)`.
   - Cursor Home (`CURSOR_HOME` / `Ctrl+A`):
     - `CUR_COL = 0`.
     - `TARGET_COL = 0`.
   - Cursor End (`CURSOR_END` / `Ctrl+E`):
     - `CUR_COL = len(line[CUR_DOC_ROW])` (clamped to `MAX_LINE_CHARS - 1`).
     - `TARGET_COL = CALC_VISUAL_COL(CUR_COL)`.

4. Vertical Navigation & Sticky Visual Column (`TARGET_COL`):
   Vertical cursor movement preserves `TARGET_COL` across line boundaries.
   Directional movement is handled exclusively by ANSI VT100 arrow keys;
   legacy WordStar diamond navigation (`Ctrl+E` up, `Ctrl+X` down) is
   unsupported to prevent collisions with End of Line and Cut/Move Block.
   Clamping cursor position when passing through shorter lines does NOT mutate
   `TARGET_COL`, allowing the cursor to return to its original visual column
   when encountering subsequent longer lines.
   - Column Target Clamping Algorithm (`ADJUST_COL_TO_TARGET`):
     Given the destination line and sticky `TARGET_COL`:
     1. Initialize `char_idx = 0` and `vis_acc = 0`.
     2. While `char_idx < len(line)` and `vis_acc < TARGET_COL`:
        - If `line[char_idx] == 0x09` (`KEY_TAB`):
          `spaces = tab_width - (vis_acc % tab_width)`.
          Advance across tab (snap-forward): `vis_acc += spaces`,
          `char_idx += 1`.
        - Else:
          `vis_acc += 1`.
          `char_idx += 1`.
     3. Set `CUR_COL = char_idx`.
     Note: When `TARGET_COL` falls across an expanded tab, the loop advances
     through the tab to snap-forward to the character immediately following
     the tab, preserving tab exclusion and keeping cursor on indented text.
   - Cursor Up (`CURSOR_UP` / Arrow Up):
     - If `CUR_DOC_ROW == 0`: Blocked (no-op).
     - `CUR_DOC_ROW -= 1`.
     - Viewport scroll: If `CUR_DOC_ROW < TOP_DOC_ROW`:
       `TOP_DOC_ROW = CUR_DOC_ROW`.
     - Realign: `ADJUST_COL_TO_TARGET()`.
   - Cursor Down (`CURSOR_DOWN` / Arrow Down):
     - If `CUR_DOC_ROW >= DOC_TOTAL_LINES - 1`: Blocked (no-op).
     - `CUR_DOC_ROW += 1`.
     - Viewport scroll: If `CUR_DOC_ROW - TOP_DOC_ROW > ACTIVE_ROWS - 2`:
       `TOP_DOC_ROW += 1`.
     - Realign: `ADJUST_COL_TO_TARGET()`.
   - Page Up (`PAGE_UP` / `Ctrl+U` / dedicated `PgUp` key):
     - `step = ACTIVE_ROWS - 2` (22 on 80x24; 38 on 120x40).
     - `CUR_DOC_ROW = max(0, CUR_DOC_ROW - step)`.
     - `TOP_DOC_ROW = max(0, TOP_DOC_ROW - step)`.
     - Clamp: Ensure `TOP_DOC_ROW <= CUR_DOC_ROW`.
     - Realign: `ADJUST_COL_TO_TARGET()`.
   - Page Down (`PAGE_DOWN` / `Ctrl+V` / dedicated `PgDn` key):
     - `step = ACTIVE_ROWS - 2`.
     - `max_row = max(0, DOC_TOTAL_LINES - 1)`.
     - `CUR_DOC_ROW = min(max_row, CUR_DOC_ROW + step)`.
     - If `CUR_DOC_ROW >= TOP_DOC_ROW + step`:
       `TOP_DOC_ROW = min(max_row, TOP_DOC_ROW + step)`.
     - Realign: `ADJUST_COL_TO_TARGET()`.
   - Boundary Clamping Status Bar Refresh:
     - Cursor navigation movements (Arrow Up, Down, Left, Right, Home, End,
       Page Up, Page Down) unconditionally set `NEED_STATUS_RENDER = 1`.
     - Even when movement is clamped at document boundaries (e.g. Line 0,
       EOF, Col 0, EOL at EOF), the status bar is refreshed upon console
       idle to synchronize terminal state with the active position.

5. Viewport Window Scrolling & Boundary Constraints:
   - Document Viewport Boundaries:
     - Visible document rows span `ScreenRow = 1 .. ACTIVE_ROWS - 1`
       (Rows 1..23 on 80x24; Rows 1..39 on 120x40).
     - Row 24 (or Row 40) is unconditionally reserved for Universal Status Bar.
   - Screen Viewport Constraint (`CONSTRAIN_CURSOR_VIEWPORT`):
     Whenever the terminal is resized, documents loaded, or windows switched:
     - `max_vis_row = TOP_DOC_ROW + (ACTIVE_ROWS - 2)`.
     - If `CUR_DOC_ROW > max_vis_row`: `CUR_DOC_ROW = max_vis_row`.
     - If `CUR_DOC_ROW < TOP_DOC_ROW`: `CUR_DOC_ROW = TOP_DOC_ROW`.
     - Realign `CUR_COL` via `ADJUST_COL_TO_TARGET()`.

6. Horizontal Panning Engine (`[Pan +40]`) & Line Capacity Limit:
   - Line Capacity Limit:
     - Maximum visual/input line length is 1,000 characters
       (`MAX_INPUT_LINE_CHARS = 1000`, `MAX_LINE_CHARS = 1000`).
     - Backed by dynamic multi-stride Far RAM allocation and 1,024-byte
       active line buffers. Character insertion beyond 1,000 is blocked.
   - Horizontal Pan Quantum (+40 Columns):
     - On standard 80-column screens, columns beyond column 79 are accessed via
       horizontal viewport panning in increments of 40 columns.
     - `VIEW_LEFT_COL` operates in steps of 40 columns (`0, 40, 80`).
   - Panning Shift Logic (`ADJUST_HORIZ_VIEWPORT`):
     Let `vis_col = CALC_VISUAL_COL(CUR_COL)`:
     - Pan Right:
       - If `vis_col >= VIEW_RIGHT_COL`: Increment `VIEW_LEFT_COL` by 40
         until `VIEW_RIGHT_COL > vis_col`.
       - Edge Trigger: If `vis_col == VIEW_RIGHT_COL - 1` and the active line
         continues beyond `CUR_COL` (character at `CUR_COL` and next character
         are non-null), pan right by 40 columns.
     - Pan Left:
       - If `VIEW_LEFT_COL > 0` and `vis_col <= VIEW_LEFT_COL`:
         `VIEW_LEFT_COL = ((vis_col - 1) / 40) * 40` (rounds down to multiple
         of 40).
   - Status Bar Pan Indicator:
     - When `VIEW_LEFT_COL > 0`, Status Bar Field 4 (Context / Mode field)
       displays `[Pan +{VIEW_LEFT_COL}]` padded with spaces to 15 characters
       plus separator ` | ` (e.g. `[Pan +40]      | `).
     - When `VIEW_LEFT_COL == 0`, Field 4 reverts to normal mode cues or
       the default help key hint `^K: Editor keys | `.
     - Field 5 remains strictly reserved for cursor coordinates, ensuring
       jitter-free coordinate tracking without column spill.

7. Terminal Hardware Cursor Placement (`LOCATE_CURSOR`):
   After all navigation, panning, or editing steps, the hardware cursor is
   positioned on the terminal using 1-based ANSI escape codes:
   - `ScreenRow = (CUR_DOC_ROW - TOP_DOC_ROW) + 1`
     - Clamped to: `1 <= ScreenRow <= ACTIVE_ROWS - 1`.
   - `ScreenCol = (CALC_VISUAL_COL(CUR_COL) - VIEW_LEFT_COL) + 1`
     - Clamped to: `1 <= ScreenCol <= ACTIVE_COLS`.
   - Hardware Escape Sequence:
     `\x1b[{ScreenRow};{ScreenCol}H`.
   Because `ScreenCol` derives strictly from `CALC_VISUAL_COL(CUR_COL)` where
   `CUR_COL` is an integer byte offset, the hardware cursor always aligns to
   discrete character boundaries and can never be positioned within a tab.

8. Deletion Operations & Line Joining Dynamics (Backspace & Delete):
   Deletion mechanics govern both inline character removal and line structure
   mutations across buffer rows. All variants must implement identical
   boundary, joining, and cursor synchronization rules:
   - Backward Deletion (`BACKSPACE` / `KEY_BACKSPACE` / `0x08` / `Ctrl+H`):
     - Inline Deletion (`CUR_COL > 0`):
       - Removes character immediately preceding cursor (`CUR_COL - 1`).
       - Characters from `CUR_COL` to end of line shift left by one column.
       - Cursor decrements: `CUR_COL -= 1`.
       - Updates sticky visual column: `TARGET_COL = CALC_VISUAL_COL(CUR_COL)`.
       - Marks document modified: `MODIFIED = 1`.
       - Redraws active line (`NEED_LINE_RENDER = 1`) and updates status bar.
     - Column 0 Line Joining (`CUR_COL == 0`):
       - If `CUR_DOC_ROW > 0`:
         - Let `prev_len = len(line[CUR_DOC_ROW - 1])` and
           `cur_len = len(line[CUR_DOC_ROW])`.
         - Combined Length Barrier Check:
           If `prev_len + cur_len <= MAX_INPUT_LINE_CHARS` (1,000 chars):
           - Appends current line contents to previous line:
             `line[CUR_DOC_ROW - 1] += line[CUR_DOC_ROW]`.
           - Deletes row `CUR_DOC_ROW` from document line pointer table.
           - Decrements total lines: `DOC_TOTAL_LINES -= 1`.
           - Moves cursor up to previous row: `CUR_DOC_ROW -= 1`.
           - Positions cursor at exact junction boundary: `CUR_COL = prev_len`.
           - Updates sticky target: `TARGET_COL = CALC_VISUAL_COL(CUR_COL)`.
           - Marks document modified: `MODIFIED = 1`.
           - Triggers full viewport re-render (`NEED_SCREEN_RENDER = 1`).
           - Viewport Scroll: If `CUR_DOC_ROW < TOP_DOC_ROW`, scrolls up:
             `TOP_DOC_ROW = CUR_DOC_ROW`.
           If `prev_len + cur_len > MAX_INPUT_LINE_CHARS`:
           - Join is inhibited (no-op) to enforce the 1,000-character line
             limit and prevent buffer overflow.
       - If `CUR_DOC_ROW == 0` (top of document):
         - Blocked (no-op; beginning of file reached).
     - Block Mode Interaction:
       - If dynamic block selection is active (`BLOCK_ACTIVE == 1`), pressing
         Backspace cancels selection (`BLOCK_ACTIVE = 0`) to safeguard
         unintended content modification.
   - Forward Deletion (`DELETE` / `KEY_DELETE` / `0x7F` / `Ctrl+D` / `0x04`):
     - Inline Deletion (`CUR_COL < len(line[CUR_DOC_ROW])`):
       - Removes the character directly under the cursor (`CUR_COL`).
       - Characters following `CUR_COL` shift left by one column.
       - Cursor position remains stationary (`CUR_COL` unchanged).
       - Updates sticky visual column: `TARGET_COL = CALC_VISUAL_COL(CUR_COL)`.
       - Marks document modified: `MODIFIED = 1`.
       - Redraws active line (`NEED_LINE_RENDER = 1`) and updates status bar.
     - End of Line Pull-Up / Joining (`CUR_COL >= len(line[CUR_DOC_ROW])`):
       - If `CUR_DOC_ROW + 1 < DOC_TOTAL_LINES`:
         - Let `cur_len = len(line[CUR_DOC_ROW])` and
           `next_len = len(line[CUR_DOC_ROW + 1])`.
         - Combined Length Barrier Check:
           If `cur_len + next_len <= MAX_INPUT_LINE_CHARS` (1,000 chars):
           - Appends next line contents to current line:
             `line[CUR_DOC_ROW] += line[CUR_DOC_ROW + 1]`.
           - Deletes row `CUR_DOC_ROW + 1` from document pointer table.
           - Decrements total lines: `DOC_TOTAL_LINES -= 1`.
           - Cursor remains stationary at `CUR_COL = cur_len` (junction point).
           - Updates sticky target: `TARGET_COL = CALC_VISUAL_COL(CUR_COL)`.
           - Marks document modified: `MODIFIED = 1`.
           - Triggers full viewport re-render (`NEED_SCREEN_RENDER = 1`).
           If `cur_len + next_len > MAX_INPUT_LINE_CHARS`:
           - Pull-up is inhibited (no-op) to preserve 1,000-character limit.
       - If `CUR_DOC_ROW + 1 >= DOC_TOTAL_LINES` (end of document):
         - Blocked (no-op; end of file reached).
     - Block Mode Interaction:
       - If a block is active (`BLOCK_ACTIVE == 1` or `2`):
         - Pressing `Delete` or `Ctrl+D` solidifies dynamic selection and
           deletes the entire highlighted block range (`DO_DELETE_BLOCK`).
         - Resets `BLOCK_ACTIVE = 0`, repositions cursor at block start,
           marks `MODIFIED = 1`, and re-renders the screen.

7. Tier 1 Centered Workspaces
--------------------------------------------------------------------------------
Non-document full-screen workspaces are rendered as mathematically centered
content blocks rather than top-aligned text.

1. Mathematical Centering Formulas (1-Based Coordinates):
   - `AvailRows = HOST_ROWS - 1` (excludes Row 24 status bar).
   - `TopRow = max(1, ((AvailRows - ContentHeight) // 2) + 1)`
   - `LeftCol = max(2, ((HOST_COLS - ContentWidth) // 2) + 1)`

2. Splash Screen Layout (Tier 1):
   - Canonical Template: Canonical `SE.COM` serves as the authoritative splash
     screen template for all SE variants across all target platforms.
   - Content Height: 21 lines, Content Width: 50 columns.
   - All rows above `TopRow` and below `TopRow + 21` (up to Row 23) display `~`.
   - Screen Geometry Option Presentation:
     80x24 is the default screen size because it is supported on all systems.
     Going forward, splash screen geometry options are standardized to:
     - `Option 1`: Standard `80x24` classic terminal mode (universal baseline
       and default on all systems). Hotkey `1` (`DO_SET_80X24`).
     - `Option 2`: Wide `120x40` modern console mode (if supported). Hotkey `2`
       (`DO_SET_120X40`). Note: If 120x40 screen size is not supported on the
       target platform, Option 2 on the splash screen will not be shown and
       120x40 screen size will not be supported on that target.
     - `Option 3`: Native host terminal mode (if supported). Hotkey `3`
       (`DO_SET_NATIVE`). Added to the splash screen only when dynamic host
       terminal sizing is supported (e.g. on native Linux/POSIX ports).
   - Visual Structure (Canonical SE.COM v1.1.4 80x24 Template — see Section 15.1
     for full 1:1 grid and profile adaptation rules):
```text
~
~                              SE - Screen Editor
~
~                     type   [E]  or  [Enter] to edit
~                     type   [N]              to new file
~                     type   [O]  or  [^O]    to open file
~                     type   [S]  or  [^S]    to save file
~                     type   [W]  or  [^W]    to close file
~                     type   [L]  or  [^L]    to goto line
~                     type   [A]              for about
~                     type   [M]              for memory info
~                     type   [P]              for plugins
~                     type   [^P]             for context plugin menu
~                     type   [C]              to configure
~                     type   [1]              set 80x24
~                     type   [2]              set 120x40
~                     type   [Q]  or  [^Q]    to exit
~
~                   Active Screen : [80x24 (Classic Terminal)] 
~                   RAM Drive (B:): [Preserved (Active)]
~                   Plugin System : [Operational]
~                   Max Lines     : [16,384 lines]
~
 | (Untitled)     |  80x24 | CP/M  | Free: 64 KB     | Line    1/1    Col 0   | 
```
   - Dynamic Diagnostic Status Line Strings (Screen Rows 19..22 in 80x24; see
     Section 15.1.5 for profile-specific adaptations and omissions):
     - `Active Screen`:
       - `80x24` mode: `Active Screen : [80x24 (Classic Terminal)] `
       - `120x40` mode: `Active Screen : [120x40 (Modern Default)]`
       - `Native` mode: `Active Screen : [Native (Dynamic Console)]` (or
         `[<Cols>x<Rows> (Native Terminal)]`)
     - `RAM Drive (<drv>:)` (where `<drv>` is detected RAM drive, e.g. `A:` or
       `B:`):
       - Protected / Preserve: `RAM Drive (B:): [Preserved (Active)]`
       - Enabled / Overwrite: `RAM Drive (B:): [Overwritten (Max RAM)]`
       - Hibernate: `RAM Drive (B:): [Hibernated (Temp Image)]`
       - None detected: `RAM Drive     : [None Detected]`
     - `Plugin System`:
       - Autoload (CP/M-80 Resident `PLUGIN.PRL`):
         `Plugin System : [Operational]`
       - Demand (CP/M-80 On-Demand `PLUGIN.PRL`):
         `Plugin System : [On Demand]`
       - Disabled (CP/M-80): `Plugin System : [Disabled]`
       - Builtin (Non-CP/M systems & CP/M-86 `SE.CMD`):
         `Plugin System : [Builtin]`
     - `Max Lines`:
       - `16K` mode (default): `Max Lines     : [16,384 lines]`
       - `32K` mode: `Max Lines     : [32,768 lines]`
       - Conventional RAM fallback: `Max Lines     : [256 lines (RAM)]`
   - Instant Single-Keystroke Protocol & "Enter Option" Exclusion:
     - The splash screen dispatches commands immediately on a single keystroke.
     - The hardware terminal cursor must remain hidden (`\x1b[?25l`).
     - Under NO circumstances may an interactive prompt (such as
       `Enter option: _` or `Enter choice: _`) be displayed on the splash
       screen. Any such query which has appeared in some SE variants is
       strictly prohibited and removed.
   - Clean Header Mandate (No Version or Language on Splash):
     - Row 1 displays `SE - Screen Editor` using ASCII hyphen `-` (never UTF-8
       `—`).
     - The splash screen does not display the release version number or the
       predominant programming language. Those details are consolidated
       exclusively onto the About screen (`[A]`).
   - Keyboard Dispatch & Keystroke Protocol:
     - Document Entry Keys: Only `E` / `e` or `Enter` (`KEY_ENTER`) may
       enter or resume the editor workspace.
     - Direct Action Hotkeys:
       - `N` / `n`: Create new empty document (`HANDLE_SPLASH_NEW`).
       - `O` / `o` / `Ctrl+O`: Open File browser (`HANDLE_SPLASH_OPEN`).
       - `S` / `s` / `Ctrl+S`: Save File workspace (`DO_SPLASH_SAVE`).
       - `W` / `w` / `Ctrl+W`: Close active file (`HANDLE_SPLASH_CLOSE`).
       - `L` / `l` / `Ctrl+L`: Goto Line prompt (`DO_SPLASH_GOTO_LINE`).
       - `A` / `a`: Show About dialog (`DO_ABOUT_SCREEN`).
       - `M` / `m`: Show Memory Map screen (`DO_MEM_INFO_SCREEN`).
       - `P` / `p`: Show Plugin Manager screen (`DO_SPLASH_PLUGIN_SCREEN`).
       - `Ctrl+P`: Context-Aware Plugin Palette (`DO_CONTEXT_PLUGIN_POPUP`).
       - `C` / `c`: Open Configuration Manager (`DO_CONFIG_SCREEN`).
       - `1`: Set 80x24 classic terminal mode (`DO_SET_80X24`). Universal
         baseline standard and default screen size across all platforms.
       - `2`: Set 120x40 modern console mode (`DO_SET_120X40`), if supported
         on the target platform. If unsupported, Option 2 is omitted.
       - `3`: Set Native dynamic terminal mode (`DO_SET_NATIVE`), if supported
         on the target platform (e.g. Linux native ports). If dynamic resizing
         is unsupported, Option 3 is omitted.
       - `Q` / `q` / `Ctrl+Q`: Safe quit / exit back to OS.
     - Non-Entry Key Exclusion & Silent Rejection Mandate:
       - The Space bar (`0x20`), ANSI cursor arrow keys (`Up`, `Down`, `Left`,
         `Right`), and all unassigned keystrokes MUST NOT enter editor mode.
         They must be silently ignored without altering document or buffer
         state and without re-rendering the splash workspace or emitting
         terminal escape sequences.
     - Screen Switching Debris Prevention & Clearance Discipline:
       Prior to switching screen sizes (upon receiving hotkey `1`, `2`, or `3`),
       the editor must explicitly clear the entire terminal screen (emitting
       ANSI clear sequence `\x1b[2J\x1b[H` / `TERM_INIT`) before applying new
       dimensions and re-rendering the workspace. This guarantees that no
       visual artifacts, stale column tildes, clipped text lines, or previous
       status bar remnants are left as debris on the screen.


3. Help Screen Layout (`Ctrl+K`):
   - Canonical Template: Canonical `SE.COM` (`plugins/help.asm` / `HELP.OVL`)
     serves as the authoritative Editor Mode Keys Help screen template for all
     SE variants across all target platforms.
   - Content Dimensions: Content Height: exactly 22 lines (`HELP_LINES = 22`).
     Content Width: 80 columns baseline (79 content chars + column 0 tilde `~`).
   - Activation Protocol:
     - In editor mode with no active block (`BLOCK_ACTIVE == 0`): `Ctrl+K`
       loads and displays the full-screen Help workspace.
     - Note: When a block is actively marked (`BLOCK_ACTIVE != 0`), `Ctrl+K`
       instead opens the Tier 2 Block Operations modal dialog
       (`DO_BLOCK_MENU_POPUP`) per Section 9.3.
   - Visual Structure (Canonical SE.COM Template):
     ```text
     ~========================================================================
     ~                               EDITOR MODE KEYS
     ~========================================================================
     ~  FILE & SYSTEM:
     ~    Ctrl+O           Open file screen      Ctrl+S         Save file screen
     ~    Ctrl+W           Close file to splash  Ctrl+Q         Quit to CP/M
     ~    Ctrl+K           Help / Solidify block Ctrl+P         Plugins pop-up
     ~  NAVIGATION & SEARCH:
     ~    Arrow Keys      Move cursor            Ctrl+A / Home  Start of line
     ~    Ctrl+U / PgUp   Page Up                Ctrl+E / End   End of line
     ~    Ctrl+V / PgDn   Page Down              Ctrl+T / ^Home Top of file
     ~    Ctrl+L          Goto line number       Ctrl+G / ^End  Bottom of file
     ~    Ctrl+F          Find text              Ctrl+N         Find next
     ~    Ctrl+R          Search and Replace     Ctrl+I / Tab   Toggle find case
     ~  EDITING & BLOCK:
     ~    Insert          Toggle Insert/Ovr      Enter          New line
     ~    ASCII 32..126   Insert/Overwrite text  Backspace      Delete left/join
     ~    Delete / Ctrl+D Delete char or block   Ctrl+B         Start/Toggle blk
     ~    Ctrl+C          Copy solidified block  Ctrl+K         Solidify block
     ~    Ctrl+X          Move solidified block  ESC            Clear block
     ~------------------------------------------------------------------------
     ~                          Press any key to continue
     ~
     [STATUS BAR AT ROW 24]
     ```
   - Layout Structure & Line Composition (22 Lines Total):
     - Row 1: Full-width horizontal rule of `'='` across columns 1..79.
     - Row 2: Centered Title `EDITOR MODE KEYS` (31 leading spaces in 80 cols,
       51 spaces in 120 cols). Application banners and executable name prefixes
       (e.g. `SE.COM — ` or `SE - `) are strictly PROHIBITED per Section 7.1.
     - Row 3: Full-width horizontal rule of `'='`.
     - Rows 4..20: Help Key Descriptions (17 lines) grouped under 3 functional
       category headers (`FILE & SYSTEM:`, `NAVIGATION & SEARCH:`,
       `EDITING & BLOCK:`).
     - Row 21: Full-width horizontal dash rule of `'-'`.
     - Row 22: Centered Return Prompt: `Press any key to continue` (26 leading
       spaces in 80 columns). Standardized phrasing without trailing ellipsis.
   - Column Grid & Key Alignment (Two-Column Layout across Columns 4..78):
     - Column 1 Key begins at Column 4 (4 leading spaces).
     - Column 1 Description begins at Column 21 (11 spaces following 6-char
       keys like `Ctrl+O`, `Ctrl+W`, `Ctrl+K`, `Ctrl+L`, `Ctrl+F`, `Ctrl+R`).
     - Column 2 Key begins at Column 45.
     - Column 2 Description begins at Column 61 (10 spaces following
       `Ctrl+S`, `Ctrl+Q`, `Ctrl+P`).
   - Symmetrical Centering & Tilde Discipline:
     - In 80x24 Geometry:
       - Available text rows: 23 (`HOST_ROWS - 1`, excluding status bar).
       - Vertical top padding: `(23 - 22) / 2 = 0` margin rows. The content
         block begins directly on Screen Row 1.
       - Vertical bottom padding: `23 - 0 - 22 = 1` row (Screen Row 23 displays
         `~` in column 0).
       - Row 24 displays the Universal Status Bar.
     - In 120x40 Geometry:
       - Available text rows: 39 (`HOST_ROWS - 1`).
       - Vertical top padding: `(39 - 22) / 2 = 8` margin rows. Rows 1..8
         display `~` in column 0.
       - Content block occupies Rows 9..30.
       - Vertical bottom padding: `39 - 8 - 22 = 9` margin rows (Rows 31..39
         display `~` in column 0).
       - Horizontal left padding: `(120 - 80) / 2 = 20` spaces after column 0
         `~` on body rows.
       - Full-width rules extend across columns 1..119 (119 characters).
       - Row 40 displays the Universal Status Bar.
     - Column 0 Tilde Mandate:
       Every single line of the Help screen (margin rows, horizontal rules,
       title, headers, key description rows, footer prompt, and bottom margin
       rows) strictly displays `~` in column 0. Only the status bar row has no
       tilde.
   - Dismissal & Key Dispatch Protocol:
     - Single-Key Dismissal: Pressing any regular key dismisses the Help
       screen and immediately returns to the editor (or originating screen).
     - Standalone `ESC`: Drains any trailing ANSI escape sequence bytes before
       returning cleanly to editor mode.
     - `Ctrl+P`: Dispatches the context plugin pop-up palette
       (`PLUG_CTX_HELP`), restoring and re-rendering the Help workspace upon
       dismissal.
   - Universal Status Bar Presence:
     The Universal Status Bar is persistently displayed on Row `HOST_ROWS`. On
     variants supporting dynamic memory queries (such as `SE.COM`), Field 4
     displays free document memory (`Free: <N> KB | `) during Help overlay
     execution. On variants lacking dynamic memory reading, Field 4 is left
     blank (`               | `), conforming strictly to Section 4.3.

4. Configuration Manager Workspace (`[C]` from Splash):
   - Displays active parameters, config file origin, and instant hotkey
     toggling:
     ```text
     ~
     ~                      SE - Configuration Manager
     ~
     ~                   Config Status: Loaded from A:SE.CFG
     ~
     ~                   1. Screen Geometry  : 80x24
     ~                   2. RAM Drive Mode   : Protected
     ~                   3. Max Doc Lines    : 32K
     ~                   4. Tab Width        : 8
     ~                   5. Plugin Manager   : Autoload
     ~
     ~             [1-5]=Toggle Option  [S]=Save Config  [ESC]=Exit
     ~
     [STATUS BAR AT ROW 24]
     ```
   - Option Display Labels & Toggle Cycles:
     - `Config Status`: `Defaults` (when no `SE.CFG` was loaded) or
       `Loaded from SE.CFG` / `Loaded from A:SE.CFG` (once loaded or saved).
     - `1. Screen Geometry`: Cycles `80x24` / `80x24 (Classic)` ->
       `120x40` / `120x40 (Wide)` -> `Native` (on platforms supporting
       dynamic host sizing) -> `80x24`. Clears screen (`TERM_INIT`) prior to
       switching geometry.
     - `2. RAM Drive Mode`: Cycles `Protected` (`PRESERVE`) -> `Enabled` (`ON`)
       -> `Hibernate` (`HIB`) -> `Protected` (or `Protected` <-> `Disabled` on
       host ports without banked RAM).
     - `3. Max Doc Lines`: Toggles `16K` <-> `32K`.
     - `4. Tab Width`: Toggles `4` <-> `8`.
     - `5. Plugin Manager`: On <64KB CP/M-80 systems (`SE.COM`, `SE_NEXT.COM`)
       where `PLUGIN.PRL` is dynamically loaded, cycles `Autoload`
       (`AUTO` / `AUTOLOAD`) -> `Demand` (`DEMAND` / `ONDEMAND`) -> `Disabled`
       (`OFF` / `DISABLED`) -> `Autoload`. On non-CP/M systems (and CP/M-86
       `SE.CMD`), the plugin manager is builtin and cannot be disabled via the
       Configure screen or `SE.CFG` (see Section 14.8).
   - Instant Keystroke Dispatch Protocol:
     - Keys `1` through `5` immediately toggle the corresponding configuration
       parameter and redraw the workspace.
     - Key `S` / `s` immediately saves active settings to `SE.CFG` and updates
       `Config Status` to `Loaded from SE.CFG` in-place without opening a
       blocking confirmation or notification modal pop-up.
     - `ESC`, `Q` / `q`, or `Enter` immediately exits back to the Splash
       screen.
     - The workspace operates as a non-buffered, instant-response hotkey menu.
       An `Enter option: _` prompt line is strictly prohibited and the
       terminal hardware cursor is cleanly hidden (`TERM_HIDE_CURSOR`).

5. File Open Workspace (`Ctrl+O` in Editor / `O` or `Ctrl+O` from Splash):
   - Full-screen Tier 1 directory browser listing files on current drive/user.
   - Screen mode capacity:
     - 80x24 mode: 5 columns x 12 rows (60 files/page), column width 15 chars,
       2-space left margin after `~` (`DIR_LEFT_PAD = 2`).
     - 120x40 mode: 7 columns x 28 rows (196 files/page), column width 16 chars,
       3-space left margin after `~` (`DIR_LEFT_PAD = 3`).
   - Paging navigation via `<PgUp>` and `<PgDn>` when file count exceeds page.
   - Inverse-video prompt label (`Enter filename to open:`) followed by a
     20-character bracketed input field (`[J0:                 ]`) and mode
     hint.
   - Directory highlight bar navigation via `TAB` (`[TAB]=Select File` <->
     `[TAB]=Edit Name  [Enter]=OK`).
   - Single-Page vs. Multi-Page Invariant:
     - When `total_pages <= 1` (single-page mode), the pagination footer row
       (`[Page %d/%d]  <PgUp>/<PgDn>=Page`) is suppressed to avoid premature
       pagination prompts.
     - When `total_pages > 1` (multi-page mode), the pagination footer row
       displays `[Page %d/%d]  <PgUp>/<PgDn>=Page` immediately below the `---`
       divider rule.
   - Visual Structure (Canonical SE.COM 80x24 Template — see Section 15.3 for
     full 1:1 grid and profile adaptation rules):
```text
~
~
~
~==============================================================================
~                       OPEN FILE (DIRECTORY - DRIVE J:)
~==============================================================================
~  1.TXT          10.TXT         2.TXT          20.TXT         30.TXT         
~  3328.TXT       40.TXT         50.TXT         BEAUTIFY.PRL   BIGPLUG.PRL    
~  DIAGBNK.COM    DIGIT5.AS      DIGIT5.ASM     DIGIT5.CPM     FATFS.PRL      
~  FATTEST.COM    HALFPLUG.PRL   HELP.OVL       HELPNEXT.OVL   HIBERN.OVL     
~  MIDPLUG.PRL    OUTPUT.TXT     PLUGBAD.CFG    PLUGIN.CFG     PLUGIN.PRL     
~  ROT13.PRL      SE.ASM         SE.CFG         SE.COM         SEBIG.ASM      
~  SEC.COM        SE_NEXT.COM    SNIP.TXT       TE.BKP         TEMP.TXT       
~  TEMP2.TXT      TEST.TXT       TODO.MD        UP.SUB         VFSTEST.COM    
~  WORDCNT.OVL    ZMC.COM        
~
~------------------------------------------------------------------------------
~  [ESC]=Cancel  Enter [d:][u:][pattern] to list (e.g. B:, C1:, 1C:, *.TXT)
~  Enter filename to open: [J0:                 ]  [TAB]=Select File          
~
~
~
~
 | (Untitled)     |  80x24 | CP/M  | Free: 288 KB    | Line    1/1    Col 0   | 
```
   - Universal Status Bar Presence:
     The Universal Status Bar is persistently displayed on Row `HOST_ROWS`. On
     variants supporting dynamic memory queries (such as `SE.COM`), Field 4
     displays free document memory (`Free: <N> KB | `) during Open File
     directory browser execution. On variants lacking dynamic memory reading,
     Field 4 is left blank (`               | `), conforming strictly to
     Section 4.3.

6. File Insert Workspace (`Ctrl+O` with Active Block):
   - Invoked when block selection is active in the editor (`DO_BLOCK_INSERT`).
   - Solidifies dynamic block bounds and opens directory browser in insert mode.
   - Streams selected file content into document at cursor without replacing
     existing document lines.
   - Shares the identical 5-column x 15-char directory grid, 78-char `===`/`---`
     rules, 20-char bracketed input field, and `[TAB]=Select File` highlight
     navigation as the Open File workspace (Section 15.3).
   - Visual Structure (80x24 Mode, Single-Page Example):
```text
~==============================================================================
~                      INSERT FILE (DIRECTORY - DRIVE A:)
~==============================================================================
~  DATA.DAT       HEADER.INC     MACROS.LIB     MANUAL.TXT     PROG.PAS       
~  SE.COM         SNIPPET.ASM    TEST.C         
~
~------------------------------------------------------------------------------
~  [ESC]=Cancel  Enter [d:][u:][pattern] to list (e.g. B:, C1:, 1C:, *.TXT)
~  Enter filename to insert: [A0:HEADER.INC       ]  [TAB]=Select File        
~
[STATUS BAR AT ROW 24]
```
   - Universal Status Bar Presence:
     The Universal Status Bar is persistently displayed on Row `HOST_ROWS`. On
     variants supporting dynamic memory queries (such as `SE.COM`), Field 4
     displays free document memory (`Free: <N> KB | `) during File Insert
     directory browser execution. On variants lacking dynamic memory reading,
     Field 4 is left blank (`               | `), conforming strictly to
     Section 4.3.

7. Save File Workspace (`Ctrl+S` in Editor / `S` or `Ctrl+S` from Splash):
   - Full-screen Tier 1 save workspace displaying directory contents, target
     filename input box, and line ending format indicator.
   - Document End-of-Line Handling Specification (All Variants):
     Text file line ending format is strictly managed per-document across all
     SE variants (CP/M, ZX Spectrum Next, Linux, Python, Rust):
     - Native Default for New Files: When saving a newly created document
       (`(Untitled)`), the editor defaults to the host platform's native text
       file format:
       - CP/M & Next targets (`SE.COM`, `SE_NEXT.COM`, `SE.CMD`): Defaults to
         native CP/M format (`CRLF`, `0x0D, 0x0A`).
       - Linux & POSIX targets (`se-linux`, `se-py`, `se-rs`): Defaults to
         native Linux format (`LF`, `0x0A`).
     - Line Ending Preservation for Existing Files: When opening an existing
       file from storage, the editor automatically inspects line terminators
       and preserves the file's current end-of-line markers (CRLF or LF)
       throughout all editing operations. An open file continues to use its
       detected line ending format upon save unless explicitly overridden.
     - Save Screen Format Override (`Ctrl+F`): The Save File screen explicitly
       displays the active save format (`Format: [CP/M]` or `Format: [Linux]`).
       The user can press `Ctrl+F` (`[^F]=Toggle Format`) to toggle and
       override the line ending format for that specific save. Status bar
       Field 3 immediately updates to reflect the active format.
   - Pre-fills active filename if document already has an associated file.
   - Visual Structure (80x24 Mode):
```text
~==============================================================================
~                       SAVE FILE (DIRECTORY - DRIVE A:)
~==============================================================================
~  DATA.DAT       FILE1.TXT      FILE2.ASM      MANUAL.TXT     PROG.PAS       
~  README.DOC     SE.COM         TEST.C         
~
~------------------------------------------------------------------------------
~  [ESC]=Cancel  Enter [d:][u:][pattern] to list (e.g. B:, C1:, 1C:, *.TXT)
~  Format: [CP/M]   [^F]=Toggle Format
~  Enter filename to save: [A0:MYPROG.ASM       ]  [TAB]=Select File          
~
[STATUS BAR AT ROW 24]
```
   - Universal Status Bar Presence:
     The Universal Status Bar is persistently displayed on Row `HOST_ROWS`. On
     variants supporting dynamic memory queries (such as `SE.COM`), Field 4
     displays free document memory (`Free: <N> KB | `) during Save File
     directory browser execution. On variants lacking dynamic memory reading,
     Field 4 is left blank (`               | `), conforming strictly to
     Section 4.3.

8. Block Save Workspace (`Ctrl+S` with Active Block):
   - Invoked when block selection is active in the editor (`DO_BLOCK_SAVE`).
   - Solidifies dynamic block bounds and opens save dialog in block mode.
   - Writes only the highlighted block lines and characters to target file.
   - Retains block selection state upon completion for subsequent editing.
   - Visual Structure (80x24 Mode):
```text
~==============================================================================
~                      SAVE BLOCK (DIRECTORY - DRIVE A:)
~==============================================================================
~  DATA.DAT       FILE1.TXT      FILE2.ASM      MANUAL.TXT     PROG.PAS       
~  README.DOC     SE.COM         TEST.C         
~
~------------------------------------------------------------------------------
~  [ESC]=Cancel  Enter [d:][u:][pattern] to list (e.g. B:, C1:, 1C:, *.TXT)
~  Format: [CP/M]   [^F]=Toggle Format
~  Enter filename to save: [A0:SNIPPET.TXT      ]  [TAB]=Select File          
~
[STATUS BAR AT ROW 24]
```
   - Universal Status Bar Presence:
     The Universal Status Bar is persistently displayed on Row `HOST_ROWS`. On
     variants supporting dynamic memory queries (such as `SE.COM`), Field 4
     displays free document memory (`Free: <N> KB | `) during Block Save
     directory browser execution. On variants lacking dynamic memory reading,
     Field 4 is left blank (`               | `), conforming strictly to
     Section 4.3.

9. Directory Screen Filename Input Line Editing:
   The filename input fields across all directory workspaces (Open File,
   File Insert, Save File, and Block Save) support full in-field cursor
   navigation and editing identically across all SE variants:
   - Left and Right cursor keys: `<Left>` and `<Right>` arrow keys move the
     insertion cursor horizontally within the input box without erasing
     characters.
   - Delete key: `<Del>` (or `<Ctrl+D>`) deletes the character directly under
     the cursor, shifting following characters leftward.
   - Backspace key: `<BS>` (`0x08`, `0x7F`) deletes the character immediately
     to the left of the cursor, shifting following characters leftward.
   - Home and End keys: `<Home>` (or `<Ctrl+A>`) repositions the cursor at the
     start of the input box; `<End>` (or `<Ctrl+E>`) positions the cursor
     directly after the last character in the buffer.
   - In-Place Character Insertion: Typing printable characters when the cursor
     is positioned within existing text shifts trailing characters rightward,
     inserting without overwriting existing input.
   - Confirmation and Cancellation: `<Enter>` confirms the filename; `<ESC>`
     cancels the directory workspace and returns to the previous screen.
   - Directory Listing Highlight Bar Navigation (`<Tab>`):
     - Dynamic On-Screen Mode Hint: To the right of the filename input box,
       the prompt line displays `[TAB]=Select File` when editing the filename
       box, and dynamically updates in-place to `[TAB]=Edit Name  [Enter]=OK`
       while the directory highlight bar is active.
     - Pressing `<Tab>` while in the filename input box activates a reverse-
       video highlight bar (`12` columns wide) in the directory listing view,
       starting at the top-left entry (index `0`) when at least one file is
       present on the page, and hides the hardware cursor (`TERM_HIDE_CURSOR`).
     - The filename input box is automatically populated in-place with the
       currently highlighted filename (prefixed with the active `<Drive><User>:`
       in CP/M mode).
     - The highlight bar can be navigated across the multi-column file grid
       using the cursor keys (`<Left>`, `<Right>`, `<Up>`, `<Down>`), updating
       both the highlighted cell and the filename text box in-place without
       full-screen redraws.
     - Multi-Page Highlight Paging (`<PgUp>` / `<PgDn>`): When the directory
       listing spans multiple pages (`DIR_PAGE_COUNT >= 2`) and the highlight
       bar is active, pressing `<PgDn>` advances to the next page and places
       the highlight bar on the top-left file (index `0`), while pressing
       `<PgUp>` moves to the previous page and places the highlight bar on the
       bottom-right (last) file on that page.
     - Pressing `<Enter>` while the highlight bar is active immediately accepts
       and uses the highlighted filename (identical to pressing `<Enter>` in
       the filename text box).
     - Pressing `<Tab>` while the highlight bar is active erases the highlight
       bar, restores the hardware cursor at the end of the filename in the
       text box (`TERM_SHOW_CURSOR`), and returns control to the filename text
       box so the user can continue editing the filename.

10. Workspace Prompt Input & Keystroke Rendering Discipline (SE.COM Parity):
    When entering filenames, paths, or drive specs in Tier 1 directory browsers
    (File Open, Insert, Save, Save Block):
    - In-Place Character Echo (Reference Architecture):
      - As ASCII keystrokes (`0x20..0x7E`) are received, they are appended or
        inserted into `INPUT_FILENAME_BUF` and echoed directly to the console
        at the current hardware cursor position (`PUTC`), advancing
        `cursor_pos`.
      - Inline deletions (`Backspace` deleting left of cursor, `Delete`
        deleting character under cursor) and in-place insertions redraw only
        the bracketed input field on the prompt row and reposition the cursor
        via `\x1b[{row};{col}H`.
      - Directional navigation (`Left`, `Right`, `Home`, `End`) repositions the
        hardware cursor within the bracket boundaries without emitting text.
    - Prohibition of Full-Screen Redraw During Typing:
      - Implementations MUST NOT re-render the 24-row (or 40-row) screen,
        file grid, borders, or Row 24 status bar upon receiving individual
        text input keystrokes.
      - Re-emitting the status bar or repainting the file grid on every
        keystroke creates severe display flicker and serial latency on
        4–10 MHz Z80 CP/M systems, overflows input FIFO buffers during rapid
        typing, and emits premature status bar updates (e.g. `Line    1/1`)
        that break automated test harness synchronization.
    - Discrete Full-Screen Redraw Triggers:
      - Full-screen re-renders (`RENDER_SAVE_PAGE`, `RENDER_OPEN_PAGE`) are
        strictly reserved for macroscopic state changes:
        1. Initial entry into the workspace.
        2. Page changes via `<PgUp>` or `<PgDn>`.
        3. Drive, user, or wildcard filter pattern changes applied upon
           pressing `Enter` (e.g. `B:`, `1C:`, `*.TXT`).
        4. Line ending format toggling via `Ctrl+F` in the Save workspace.
        5. Dismissal of child modal dialogs (e.g. Overwrite Confirmation).

11. Document Close Lifecycle (`Ctrl+W` in Editor / `W` or `Ctrl+W` from Splash):
    - Closing an active document returns the user directly to the Tier 1
      Splash Screen workspace.
    - Clean Document (`DOC_MODIFIED == 0`):
      Immediately closes the active file, frees working buffers, and displays
      the Splash Screen workspace without prompting.
    - Modified Document (`DOC_MODIFIED == 1`):
      Intercepts close and presents a Tier 2 Centered Boxed Modal Pop-up
      querying whether to save unsaved modifications:
      ```text
      +--------------------------------------------------+
      |              Unsaved Modifications               |
      +--------------------------------------------------+
      |   Any unsaved edits will be lost if discarded.   |
      |                  Save changes?                   |
      |                                                  |
      |        [Y]es      [N]o      [ESC]=Cancel         |
      +--------------------------------------------------+
      ```
      - Response `[Y]es`: Transitions to Save File workspace to write changes,
        then closes document to Splash Screen.
      - Response `[N]o`: Discards unsaved modifications and closes document to
        Splash Screen.
      - Response `[ESC]=Cancel`: Cancels close request and returns directly to
        the active editor workspace with document state intact.

12. About Screen Layout (`[A]` from Splash):
    - Content Height: 9 lines (`ABOUT_MENU_LINES = 9`), max line width: 49
      columns (`PRINT_ABOUT_LINE` centers each line individually via
      `LeftPad = (ACTIVE_COLS - 1 - len(str)) / 2`).
    - All rows above `TopRow` (Rows 1..7 in 80x24) and below `TopRow + 9`
      (Rows 17..23 in 80x24) display `~`.
    - Visual Structure (Canonical SE.COM v1.1.4 80x24 Template — see
      Section 15.2 for full 1:1 24-row grid):
```text
~
~
~
~
~
~
~
~                              SE - Screen Editor
~                   version 1.1.4 (2026-10-18) (Z80 Assembly)
~                                by Dean Jenkins
~
~               Google Antigravity 2.23.0 & Gemini 4 Argon Medium
~
~                  Open source software under the MIT License
~
~                           Press any key to continue
~
~
~
~
~
~
~
 | (Untitled)     |  80x24 | CP/M  | Free: 64 KB     | Line    1/1    Col 0   | 
```
    - Predominant Programming Language Display Mandate:
      Content Row 2 (Screen Row 9 in 80x24) of the About screen displays the
      release version number, build date, and the predominant programming
      language used to create that specific SE port or binary, formatted as
      `version <version> (<date>) (<Language>)`:
      - 8-bit CP/M (`SE.COM`):
        `version 1.1.4 (2026-10-18) (Z80 Assembly)`
      - ZX Spectrum Next (`SE_NEXT.COM` / `SE.NEX` / `.se`):
        `version 1.1.4 (2026-10-18) (Z80 Assembly)`
      - 16-bit CP/M-86 (`SE.CMD`):
        `version 1.1.4 (2026-10-18) (x86 Assembly)` (or `(C)`)
      - Linux Native C / CP/M C port (`se-linux` / `SEC.COM`):
        `version 1.1.4 (2026-10-18) (C)`
      - Linux Native Python port (`se-py`):
        `version 1.1.4 (2026-10-18) (Python)`
      - Future Rust port (`se-rs`):
        `version 1.1.4 (2026-10-18) (Rust)`
      Generic host OS labels (such as `(Linux)`) must not be used; each
      binary shall clearly state its predominant programming language on the
      About screen.
    - Version Harmonization: All SE variants share the exact same release
      version number as canonical `SE.COM` (e.g. `v1.1.4`).
    - Dismissal: Any key press dismisses the About screen and returns to the
      Splash Screen.

8. Tier 2 Centered Boxed Modal Pop-ups
--------------------------------------------------------------------------------
Modal pop-ups appear centered over the active screen surface to request input
or display notifications.

1. Mathematical Centering Formulas (1-Based Coordinates):
   - `TopRow = max(1, ((HOST_ROWS - PopupHeight) // 2) + 1)`
   - `LeftCol = max(1, ((HOST_COLS - PopupWidth) // 2) + 1)`

2. Framing Structure & Formatting Discipline:
   - Outer Box: Drawn with standard ASCII borders:
     `+--------------------------------------------------+`
     `|                                                  |`
     `+--------------------------------------------------+`
   - Title Separator: Title row separated by divider line (`+---+`).
   - Centering: All text inside the pop-up box is centre justified across
     the interior width (`width - 2`).
   - Query Body Structure:
     - First body line: Description (explaining reason, context, or danger).
     - Second body line: Query line (input prompt or question).
     - Third body line: Decision options or action triggers.
   - Bracket Notation for Options & Inputs:
     - Interactive options and inputs use bracket notation `[ ]`
       (e.g. `[Y]es   [N]o   [ESC]=Cancel`).
     - Legacy `Y:Yes, N:No` forms are strictly prohibited.
     - Never use `/` or `|` delimiters between options; separate choices with
       sufficient spacing.
   - Dismissal & Cancellation Semantics:
     - Informational Pop-ups (no user input): Dismissible by ANY key.
     - "Press any key" statement: Unbracketed without ellipsis
       (`Press any key to continue`).
     - Interactive Pop-ups (user input / binary decision): Cancelable solely
       via `ESC`. Prohibit `Ctrl-C` or `q`/`Q` for cancellation.

3. Four Standard Modal Archetypes:

   Archetype A: Status Event Notification (`show_notification`)
     Used for notifications (Save Complete, Search Failed, Replace Done).
     Dismissible by ANY key.
     Notice: "Press any key to continue" does NOT have brackets or ellipses.
     ```text
     +--------------------------------------------------+
     |                   Save Complete                  |
     +--------------------------------------------------+
     |             Saved to /path/to/file.txt           |
     |                                                  |
     |            Press any key to continue             |
     +--------------------------------------------------+
     ```

     File Not Found Modal Alert (50 cols x 7 rows):
     ```text
     +--------------------------------------------------+
     |                  File Not Found                  |
     +--------------------------------------------------+
     |            'FILENAME' was not found.             |
     |        Specified file not found on disk.         |
     |            Press any key to continue             |
     +--------------------------------------------------+
     ```
     - Displays upon attempting to open or insert a non-existent file.
     - Dismissible by any keystroke; returns user directly back to the
       open or insert directory browser workspace with input buffer preserved.

   Archetype B: Confirmation Query (`show_confirm`)
     Used for binary decisions (Save modifications?, Overwrite file?).
     Options formatted with spaces only—no slashes `/` or pipes `|`.
     Interactive cursor positioned next to query text.
     Cancelable solely by `ESC` (not `Ctrl+C` or `q`).
     ```text
     +--------------------------------------------------+
     |               Unsaved Modifications              |
     +--------------------------------------------------+
     |   Any unsaved edits will be lost if discarded.   |
     |                  Save changes?                   |
     |                                                  |
     |           [Y]es      [N]o      [ESC]=Cancel      |
     +--------------------------------------------------+
     ```
     Overwrite File Modal Dialog (50 cols x 7 rows):
     ```text
     +--------------------------------------------------+
     |                  Overwrite File                  |
     +--------------------------------------------------+
     |       Existing file contents will be lost        |
     |         File already exists. Overwrite?          |
     |          [Y]es      [N]o      [ESC]=Cancel       |
     +--------------------------------------------------+
     ```
     - Displays upon attempting to save to an existing destination file.
     - Terminal cursor positioned directly on prompt line after `Overwrite? `
       (Col 40).
     - Confirmed via `Y`/`y`, cancelled via `N`/`n` or `ESC`.

     Replace Confirmation Modal Dialog (50 cols x 7 rows):
     ```text
     +------------------------------------------------+
     |              Replace Confirmation              |
     +------------------------------------------------+
     |     Match found for search pattern in text     |
     |            Replace this occurrence?            |
     |  [Y]es  [N]o  [A]ll  [R]everse   [ESC]=Cancel  |
     +------------------------------------------------+
     ```
     - Displays for each interactive match during Search & Replace (`Ctrl+R`).
     - Confirmed via `Y`/`y`/`Enter`, skipped via `N`/`n`, switched to
       unprompted Replace All via `A`/`a`, direction-reversed via `R`/`r`
       (or `P`/`p`), and cancelled via `ESC` (`[Q]uit` is prohibited).

   Archetype C: Single-Line Text Input (`show_input`)
     Used for text parameters (Find string, Replace string, Goto Line).
     Target input field enclosed in bracket pair `[  text  ]`.
     Terminal cursor placed directly inside bracket field.
     In-field cursor movement behaviors are identical across all SE variants.
     Unlike Tier 1 directory filename fields (Section 7.9) which provide full
     in-field cursor navigation, Archetype C modals operate strictly as
     lightweight, append/backspace linear input fields across all variants:
     - Character entry: Printable characters append to the end of the buffer.
     - Backspace / Delete: Erases character directly preceding the cursor.
     - Confirmation: `<Enter>` confirms and submits the input buffer.
     - Cancellation: Standalone `<ESC>` cancels and dismisses the dialog.
     - Unexpected Keystroke Protection Mandate:
       Modals MUST NOT be cancelled or dismissed by unexpected keys or escape
       sequences (such as cursor arrow keys, `PgUp`/`PgDn`, function keys, or
       stray control keys). Any unexpected sequences received while an input
       modal is active must be discarded without altering the modal's input
       buffer, without moving the underlying document cursor, and without
       cancelling the dialog.
     Find Text Modal Dialog (50 cols x 7 rows):
     ```text
     +------------------------------------------------+
     |                   Find Text                    |
     +------------------------------------------------+
     |       Search Pattern: [Case Sensitive  ]       |
     |      Find: [                            ]      |
     | [Enter]=Find   [Tab]=Toggle Case   [ESC]=Cancel |
     +------------------------------------------------+
     ```
     - Toggle case mode with Tab / Ctrl+I (switches between `[Case Sensitive  ]`
       and `[Case Insensitive]`).
     - Terminal cursor positioned directly inside `Find: [ ... ]` at insertion
       offset.
     - When opened with an active block, the selection text is pre-filled.
     - Solidified Match Highlighting & Wrap-Around Search:
       - Whenever a match is found by Find (`Ctrl+F`), Find Next (`Ctrl+N`),
         or Replace (`Ctrl+R`), the matched substring `[match_col, match_col +
         search_len)` on the matched row is automatically highlighted as a
         solidified block (`BLOCK_ACTIVE == 2`, displaying `Block: <N> char(s)`
         in Status Bar Field 4) and the cursor is positioned immediately past
         the end of the matched block (`CUR_COL = match_col + search_len`).
       - Pressing `<Enter>` on an empty `Find: [ ... ]` input field repeats the
         most recent search pattern if one is stored (`SEARCH_LEN > 0`).
       - Both forward and reverse searches wrap around the document boundary
         (`DOC_TOTAL_LINES - 1 -> 0` or `0 -> DOC_TOTAL_LINES - 1`) back to the
         search start origin. If no occurrence of the pattern was ever found in
         the current search session, the `"Pattern Not Found"` modal alert
         (`"Pattern not found."`) is displayed and any active block is cleared;
         if at least one occurrence was previously matched, the `"Search
         Completed"` modal alert (`"Search completed."`) is displayed while
         preserving the solidified block highlight on the last match.

     Goto Line Modal Dialog (50 cols x 7 rows):
     ```text
     +------------------------------------------------+
     |                   Goto Line                    |
     +------------------------------------------------+
     |          Enter line number to jump to          |
     |               Goto line: [     ]               |
     |       [Enter]=Goto Line     [ESC]=Cancel       |
     +------------------------------------------------+
     ```
     - Canonical Template: Canonical `SE.COM` (`src/core/editor.asm:1466-1518`
       and `src/core/plugin_mgr.asm:4170-4180`) defines the authoritative
       Goto Line modal dialog for all SE variants.
     - Exact Dimensions: 50 columns wide by 7 rows high (`50 cols x 7 rows`).
       Framed with outer ASCII box, title separator `+---+`, 3 query body lines
       (description, query prompt, action footer), and bottom border.
     - Action Footer Phrasing:
       The action footer strictly displays `[Enter]=Goto Line     [ESC]=Cancel`,
       utilizing the explicit action verb `Goto Line` (matching the specific
       action button style of Find Text `[Enter]=Find` and Replace
       `[Enter]=Replace`) rather than generic `[Enter]=Confirm`.
     - Input Field & Buffer:
       The numeric line buffer is a 5-digit field enclosed in brackets
       `Goto line: [     ]`. Hardware cursor is placed directly at the first
       digit offset inside the bracketed field (`POPUP_COL + 28`).
     - Keystroke Rendering Discipline (In-Place Echo):
       Adheres strictly to the in-place character echo discipline defined in
       Section 7.10: typed digits ('0'..'9') append to the buffer and echo
       directly at the cursor; Backspace/Delete emits `\x08 \x20 \x08`. Frame
       borders and prompt text MUST NOT be repainted on individual keystrokes.
     - Submission & Cancellation:
       `<Enter>` confirms the line number, jumps to the target line, and
       redraws the editor and status bar smoothly without a screen flash.
       Pressing `<Enter>` with an empty buffer or pressing `<ESC>` cancels and
       dismisses the modal cleanly without moving the document cursor.

   Archetype D: Selection Menu (`show_menu` / Plugin Palette, 50 cols)
     Used for choosing from a dynamic list (Plugin Palette).
     Exact Width: 50 columns (`+` + 48 `-` + `+`), height `len(items) + 6`.
     Numbered items (`1..N`) with active selection indicator (`> `).
     Built-in plugins are listed in canonical slot order:
     Slot 1 `ROT13`, Slot 2 `WORDCNT`, Slot 3 `BEAUTIFY`.
     Navigation with Up/Down arrows, Enter to run, or direct digit key (`1..9`).
     ```text
     +------------------------------------------------+
     |                 Plugin Palette                 |
     +------------------------------------------------+
     |          Select a plugin to execute:           |
     |  > 1. ROT13    - Rotate letters by 13          |
     |    2. WORDCNT  - Document word, line, count    |
     |    3. BEAUTIFY - Align Z80 assembly labels     |
     |                                                |
     |  [Up/Down]=Select   [Enter]=Run   [ESC]=Cancel |
     +------------------------------------------------+
     ```

4. Child Pop-up Isolation Protocol:
   When an active modal opens a child modal (e.g. Plugin Palette opening an
   Unload Confirmation query or Word Count statistics):
   - Step 1: Hide the parent modal from the terminal surface.
   - Step 2: Render the child modal centered on the underlying screen.
   - Step 3: Keep the child modal active until dismissed or confirmed.
   - Step 4: Restore and cleanly redraw the parent modal.
   - Rule: Multiple overlapping or stacked pop-up layers are prohibited.

9. Block Selection & Highlighting
--------------------------------------------------------------------------------
1. Block Marker Model:
   - Half-open interval: `[StartRow:StartCol, EndRow:EndCol)`.
   - Forward vs. Backwards Normalization (`NORMALIZE_BLOCK_BOUNDS`):
     - Forward selection (`Anchor <= Cursor`): `Start = Anchor` (inclusive),
       `End = Cursor` (exclusive).
     - Backwards selection (`Cursor < Anchor`): The cursor position is excluded
       and the anchor character is included:
       `Start = (CursorRow, CursorCol + 1)`, `End = (AnchorRow, AnchorCol + 1)`.
       This ensures the cursor position immediately to the left of the selected
       span lies outside `[StartCol, EndCol)` so `Ctrl+C` / `Ctrl+X` can paste
       at the cursor position after solidifying.
   - Multi-Line Count Rule (`GET_BLOCK_BOUNDS`):
     - When `EndRow > StartRow`, the multi-line count is
       `(EndRow - StartRow) + (1 if EndCol > 0 else 0)`. When `EndCol == 0`,
       `EndRow` is exclusive (contributes 0 characters on `EndRow`), so a
       selection from `(Row 1, Col 0)` to `(Row 2, Col 0)` spans `1 line`.
   - Toggled via `Ctrl+B`.
   - Cursor movement extends selection range.
   - `Shift + Arrow` Keys (`KEY_SHIFT_UP`, `KEY_SHIFT_DOWN`, `KEY_SHIFT_LEFT`,
     `KEY_SHIFT_RIGHT` — ANSI `\x1b[1;2A`..`\x1b[1;2D`, `\x1b[2A`..`\x1b[2D`,
     `\x1b[a`..`\x1b[d`): Always start a fresh dynamic block selection anchored
     at the current cursor position (`START_NEW_BLOCK_AT_CURSOR`, replacing any
     prior active or solidified block) and immediately move the cursor one step
     in the arrow direction. Subsequent unshifted arrow keys continue extending
     that dynamic selection.

2. Visual Presentation:
   - Highlighting is rendered using ANSI Inverse Video (`\x1b[7m`).
   - Contiguous Inverse Span & Tab Expansion Highlighting:
     - Inverse video (`\x1b[7m` .. `\x1b[0m`) is toggled only at the boundaries
       of a highlighted span on a row (not wrapped individually around each
       character), preventing per-character escape bloat.
     - When a Tab character (`0x09`) falls inside the half-open block interval
       `[StartRow:StartCol, EndRow:EndCol)`, all of its expanded visual spaces
       are rendered inside the inverse-video span. On the final row of a block
       (`EndRow`), a Tab at `EndCol` is NOT highlighted until the cursor moves
       past it (`EndCol > tab_index`).
   - Status Bar Field 4 dynamically displays selection metrics:
     - Dynamic Selection (`BLOCK_ACTIVE == 1`): `Sel: <N> char(s)` (single-line)
       or `Sel: <N> line(s)` (multi-line) padded to 15 chars + ` | `.
     - Solidified Block (`BLOCK_ACTIVE == 2`): `Block: <N> char(s)` / `<N>c` or
       `Block: <N> line(s)` / `<N>L` padded to 15 chars + ` | `.
   - Status Bar Field 5 retains fixed-width cursor coordinates without jitter.

3. Direct In-Place Block Manipulation Mandate:
   All SE implementations across all target platforms (CP/M Z80 `SE.COM`,
   NextCPM `SE_NEXT.COM`, Native Next `SE.NEX`, Linux C `se-linux`, Python
   `se-py`, and future ports) must strictly implement Direct In-Place Block
   Manipulation.

   - Prohibition of Intermediary Clipboards:
     The use of an intermediary clipboard buffer (copying text to a detached
     clipboard storage followed by an asynchronous paste step) is strictly
     PROHIBITED across all SE implementations. All block manipulations operate
     directly between the active marked block and the current cursor position
     in document memory. Intermediary clipboard buffers waste memory, break
     CP/M TPA budget constraints, and introduce state desynchronization.

   - Canonical Block Operation Key Combinations (from `SE.COM`):
     - `Ctrl+B`: Toggle block selection mode. If inactive (0), anchors
       selection at current cursor (dynamic selection). If active (1 or 2),
       cancels block selection (`CANCEL_BLOCK`).
     - `Enter`: Solidify/lock dynamic block selection (`SOLIDIFY_BLOCK`).
       Freezes normalized `START` and `END` boundaries (solidified block),
       allowing free cursor navigation without moving boundaries.
     - `Ctrl+C`: Copy marked block directly to cursor (`DO_COPY_BLOCK`). If
       dynamic selection is active (1), implies solidify first. Injects block
       text into the document at the active cursor position without modifying
       or clearing the source block.
     - `Ctrl+X`: Move marked block directly to cursor (`DO_MOVE_BLOCK`). If
       dynamic selection is active (1), implies solidify first. Relocates block
       text to destination cursor location and deletes the original block,
       re-establishing block bounds around the moved text at destination.
     - `Ctrl+D` / `Delete`: Delete marked block range (`DO_DELETE_BLOCK`).
       Deletes all characters and lines within the highlighted block, closes
       the gap, returns cursor to block start, and clears block selection.
     - `Ctrl+K`: Open Block Operations Modal Dialog (`DO_BLOCK_MENU_POPUP`).
       Centered 50x7 modal pop-up displaying block metrics and action hotkeys:
       `[Enter]=Lock  [C]opy  [X]Move  [D]el  [S]ave  [B]Clear  [ESC]=Exit`.
     - `Ctrl+S`: Save marked block to disk (`DO_BLOCK_SAVE_FILE`). Solidifies
       block and opens save dialog in block mode, saving only highlighted text.
     - `Ctrl+O`: Insert file at cursor into block (`DO_BLOCK_INSERT_FILE`).
       Solidifies block and streams selected file content at cursor position.
     - `Ctrl+Y`: Beautify marked block (`DO_CTRL_Y_BEAUTIFY`). Runs source code
       formatter restricted to the highlighted line range.
     - `ESC`: Clear/cancel active block selection and restore normal editing.

10. Canonical Keybinding Matrix & Behavior
--------------------------------------------------------------------------------
| Key Sequence | ASCII | Symbolic Name | Functional Action in SE             |
| :---         | :---  | :---          | :---                                |
| `Ctrl+A`     | `0x01`| `KEY_CTRL_A`  | Jump to beginning of line (Home)    |
| `Ctrl+B`     | `0x02`| `KEY_CTRL_B`  | Toggle block selection mode         |
| `Ctrl+C`     | `0x03`| `KEY_CTRL_C`  | Copy block directly to cursor       |
| `Ctrl+D`     | `0x04`| `KEY_CTRL_D`  | Delete character forward (DEL)      |
| `Ctrl+E`     | `0x05`| `KEY_CTRL_E`  | Jump to end of line (End)           |
| `Ctrl+F`     | `0x06`| `KEY_CTRL_F`  | Open Find Text modal dialog         |
| `Ctrl+G`     | `0x07`| `KEY_CTRL_G`  | Jump to Bottom of document (EOF)    |
| `Ctrl+K`     | `0x0B`| `KEY_CTRL_K`  | Display full-screen Help workspace  |
| `Ctrl+L`     | `0x0C`| `KEY_CTRL_L`  | Open Goto Line Number modal dialog  |
| `Ctrl+N`     | `0x0E`| `KEY_CTRL_N`  | Find Next search match              |
| `Ctrl+O`     | `0x0F`| `KEY_CTRL_O`  | Open File directory browser         |
| `Ctrl+P`     | `0x10`| `KEY_CTRL_P`  | Open context-aware Plugin Palette   |
| `Ctrl+Q`     | `0x11`| `KEY_CTRL_Q`  | Safe exit (prompts if unsaved edits)|
| `Ctrl+R`     | `0x12`| `KEY_CTRL_R`  | Open Search & Replace modal dialog  |
| `Ctrl+S`     | `0x13`| `KEY_CTRL_S`  | Save File to disk                   |
| `Ctrl+T`     | `0x14`| `KEY_CTRL_T`  | Jump to Top of document (Row 0)     |
| `Ctrl+U`     | `0x15`| `KEY_CTRL_U`  | Page Up (viewport rows - 2)         |
| `Ctrl+V`     | `0x16`| `KEY_CTRL_V`  | Page Down (viewport rows - 2)       |
| `Ctrl+X`     | `0x18`| `KEY_CTRL_X`  | Move block directly to cursor       |
| `Ctrl+Y`     | `0x19`| `KEY_CTRL_Y`  | Run BEAUTIFY code formatter plugin  |
| `ESC`        | `0x1B`| `KEY_ESC`     | Return to Splash / Cancel modal     |
| `Enter`      | `0x0D`| `KEY_ENTER`   | Split line at cursor / Confirm modal|
| `Backspace`  | `0x08`| `KEY_BACKSPACE`| Delete char left / join line       |
| `Delete`     | `0x7F`| `KEY_DELETE`  | Delete char under cursor / join line|
| `Tab`        | `0x09`| `KEY_TAB`     | Insert spaces to next tab stop (8/4)|
| `Up Arrow`   | ANSI  | `KEY_UP`      | Move cursor Up one line             |
| `Down Arrow` | ANSI  | `KEY_DOWN`    | Move cursor Down one line           |
| `Left Arrow` | ANSI  | `KEY_LEFT`    | Move cursor Left one character      |
| `Right Arrow`| ANSI  | `KEY_RIGHT`   | Move cursor Right one character     |
| `PgUp`       | ANSI  | `KEY_PGUP`    | Page Up (viewport rows - 2)         |
| `PgDn`       | ANSI  | `KEY_PGDN`    | Page Down (viewport rows - 2)       |

> [!IMPORTANT]
> Architectural Policy on Navigation Keys & WordStar Diamond Deprecation:
> Canonical SE mappings designate `Ctrl+S` for Save File, `Ctrl+D` for Delete
> Forward, `Ctrl+E` for End of Line, and `Ctrl+X` for Move Block.
> Directional cursor navigation across all variants and surfaces is provided
> exclusively via standard ANSI VT100 arrow keys (`Up`, `Down`, `Left`,
> `Right`), dedicated paging keys (`PgUp`, `PgDn`), paging control aliases
> (`Ctrl+U` Page Up, `Ctrl+V` Page Down), and standard motion shortcuts
> (`Ctrl+A` Home, `Ctrl+E` End, `Ctrl+T` Top, `Ctrl+G` Bottom). Legacy
> intermediary `Ctrl+V` clipboard paste is eliminated across all variants in
> favor of direct in-place block manipulation and Page Down.
>
> WordStar diamond directional navigation (`^S`, `^D`, `^E`, `^X`) is strictly
> NOT supported anywhere in SE (including the Document Editor, Centered
> Workspaces, Directory Browsers, and Tier 2 Modal Dialogs). Implementations
> must never alias WordStar diamond keys to directional navigation, as doing
> so creates fatal command collisions with Save, Delete, End, and Cut.

1. Operational Descriptions for Deletion Keys:
   Canonical SE distinguishes between backward deletion, forward deletion, and
   block range deletion across the primary editor, active blocks, Tier 1
   directory filename boxes, and Tier 2 modal dialogs:

   - `Backspace` (`KEY_BACKSPACE`, `0x08`, `Ctrl+H`):
     - Editor Workspace: Deletes character to the left of the cursor
       (`CUR_COL - 1`) and moves cursor left. When pressed at column 0
       (`CUR_COL == 0`), joins the current line to the previous line (landing
       the cursor at the junction column) provided the combined line length
       does not exceed MAX_INPUT_LINE_CHARS (1,000 chars); blocked at Row 0.
     - Block-Active Context: Cancels dynamic block (`BLOCK_ACTIVE = 0`)
       to safeguard highlighted text against accidental deletion.
     - Tier 1 Directory Filename Input Boxes (Section 7.9): Deletes the
       character preceding the cursor inside `[  ]`, shifting trailing text
       left and decrementing cursor index; blocked at index 0.
     - Tier 2 Modal Input Dialogs (Archetype C, Section 8.3): Erases the last
       character in the linear append/backspace input buffer; blocked at
       index 0.

   - `Delete` (`KEY_DELETE`, `0x7F`, ANSI `\x1b[3~`) & `Ctrl+D` (`0x04`):
     - Editor Workspace: Deletes the character directly under the cursor
       without altering cursor column. When pressed at the end of a line
       (`CUR_COL >= len(line)`), pulls up and joins the next line to the
       current line provided the combined length does not exceed
       MAX_INPUT_LINE_CHARS (1,000 chars); blocked at the end of the file.
     - Block-Active Context: Solidifies selection and deletes the entire
       highlighted block range (`DO_DELETE_BLOCK`), resetting block mode and
       moving following text up to the block start.
     - Tier 1 Directory Filename Input Boxes (Section 7.9): Deletes the
       character directly under the cursor inside `[  ]`, shifting trailing
       text left without moving the cursor index; blocked at end of input text.
     - Tier 2 Modal Input Dialogs (Archetype C, Section 8.3): `Delete` (`0x7F`)
       acts as Backspace, erasing the character preceding the cursor in the
       linear input buffer.

2. Operational Descriptions for Directional Navigation:
   Directional navigation across all surfaces is performed exclusively with
   standard VT100 ANSI arrow keys and dedicated motion shortcuts:
   - `Up Arrow` (`KEY_UP`): Moves cursor up one row; realigns to sticky
     `TARGET_COL`. Blocked at top of document.
   - `Down Arrow` (`KEY_DOWN`): Moves cursor down one row; realigns to sticky
     `TARGET_COL`. Blocked at bottom of document.
   - `Left Arrow` (`KEY_LEFT`): Moves cursor left one column; wraps to previous
     line at column 0. In Tier 1 directory filename boxes (Section 7.9), shifts
     cursor index left.
   - `Right Arrow` (`KEY_RIGHT`): Moves cursor right one column; wraps to next
     line at end of line. In Tier 1 directory filename boxes (Section 7.9),
     shifts cursor index right.
   - Paging Keys & Shortcuts: Dedicated `PgUp` (`KEY_PGUP`, ANSI `\x1b[5~`) and
     `Ctrl+U` (`KEY_CTRL_U`, `0x15`) perform Page Up (`ACTIVE_ROWS - 2` rows);
     dedicated `PgDn` (`KEY_PGDN`, ANSI `\x1b[6~`) and `Ctrl+V` (`KEY_CTRL_V`,
     `0x16`) perform Page Down (`ACTIVE_ROWS - 2` rows).
   - Motion Shortcuts: `Ctrl+A` / `Home` (Start of line / Start of directory
     filename input), `Ctrl+E` / `End` (End of line / End of directory filename
     input), `Ctrl+T` / `^Home` (Top of document), `Ctrl+G` / `^End` (Bottom of
     document).
   - WordStar Prohibition: WordStar diamond navigation keys (`Ctrl+S`,
     `Ctrl+D`, `Ctrl+E`, `Ctrl+X`) are strictly not supported for navigation
     in any editor workspace or modal input dialog.

3. Escape Sequence Tokenization & Leakage Prevention:
   - Atomic Escape Sequence Parsing:
     All terminal implementations (CP/M BIOS, Linux POSIX stdin, Next)
     must discretely tokenize multi-byte escape sequences (e.g. `\x1b[A`,
     `\x1b[B`, `\x1b[C`, `\x1b[D`, `\x1b[1~`..`\x1b[6~`, `\x1bOA`..`\x1bOF`).
   - Anti-Leakage Invariant:
     When an escape sequence begins with `ESC` followed by `[` or `O`, the
     input decoder must wait with sufficient timeout to assemble the entire
     sequence. If an incomplete or unrecognized escape sequence is received
     (such as unhandled function keys F5–F12 emitting `\x1b[15~`..`\x1b[24~`,
     mouse tracking events, or bracketed paste markers), the input decoder
     must drain and discard all sequence bytes atomically until the sequence
     terminator (e.g. `~`, `A`–`Z`, `a`–`z`, or timeout). Under NO
     circumstances may trailing sequence characters (such as `~` or trailing
     parameters) be leaked back into the console stream as regular typed
     keystrokes, as doing so corrupts document text buffers.

4. Using the Non-Standard ZX Spectrum Next Keyboard:
   Unlike standard PC or VT100 terminal keyboards that provide dedicated
   `Ctrl`, `Esc`, `Tab`, `Home`, `End`, `PgUp`, `PgDn`, and separate
   `Backspace` / `Delete` keys, the ZX Spectrum Next features a non-standard
   58-key keyboard layout routed through the classic 8x5 Sinclair ULA hardware
   matrix (`ports 0xFEFE..0x7FFE`). Dedicated Next keys (`EDIT`, `BREAK`,
   `DELETE`, `EXTEND`, and the four directional arrow keys) are synthesized in
   hardware as `Caps Shift` (`CS`) and `Symbol Shift` (`SS`) matrix chords.

   - Control Key Modifier (`EXTEND` = `Ctrl`):
     On the ZX Spectrum Next keyboard, holding the **`EXTEND`** (`Extend Mode`)
     key—or holding **`Caps Shift + Symbol Shift`** simultaneously on a 48K
     layout—acts as the universal **`Ctrl`** modifier for all ASCII control
     commands `Ctrl+A` (`0x01`) through `Ctrl+Z` (`0x1A`).
   - Escape Key (`EDIT` = `ESC`):
     Pressing the dedicated **`EDIT`** key (or **`Caps Shift + 1`**) generates
     `ESC` (`0x1B`), returning to the Splash Screen from the editor or
     canceling active block selections and modal dialogs.
   - Copy / Break Key (`BREAK` = `Ctrl+C`):
     Pressing **`BREAK`** (or **`Caps Shift + Space`**) generates `Ctrl+C`
     (`0x03`), copying a marked block in the editor.
   - Tab Key (`TRUE VIDEO` / `EXTEND + I` = `Tab`):
     Pressing the dedicated **`TRUE VIDEO`** key (`Caps Shift + 3`),
     **`EXTEND + I`** (`Ctrl+I`), or **`Symbol Shift + I`** (in native mode)
     generates `Tab` (`0x09`). Under NextCPM (`SE_NEXT.COM`), the BIOS emits
     `0x13` for `TRUE VIDEO`; `HAL_KEYBOARD_TRANSLATE` checks ULA Row 1
     (`port 0xFDFE`, bit 1 = `'S'`) to translate `TRUE VIDEO` into `Tab`
     (`0x09`) while preserving **`EXTEND + S`** (`Ctrl+S` Save File).
   - Page Up & Page Down Keys (`INV VIDEO` = `PgUp`, `GRAPH` = `PgDn`):
     Pressing the dedicated **`INV VIDEO`** key (`Caps Shift + 4`) or
     **`EXTEND + U`** (`Ctrl+U`) performs **Page Up** (`0x15`). Pressing the
     dedicated **`GRAPH`** key (`Caps Shift + 9`) or **`EXTEND + V`**
     (`Ctrl+V`) performs **Page Down** (`0x16`). Original **`EXTEND + T`**
     (`Ctrl+T` Top of File), **`EXTEND + G`** (`Ctrl+G` Bottom of File),
     **`EXTEND + U`**, and **`EXTEND + V`** mappings remain intact.
   - Backspace vs. Forward Delete (`DELETE` vs. `EXTEND + D`):
     Pressing the dedicated **`DELETE`** key (or **`Caps Shift + 0`**) deletes
     the character to the left of the cursor (`Backspace` / `0x08` in NextCPM)
     or under the cursor. Pressing **`EXTEND + H`** (`Ctrl+H`) always performs
     backward deletion (`Backspace`), and pressing **`EXTEND + D`** (`Ctrl+D`)
     always performs forward character deletion or marked block deletion.
   - Directional Cursor Keys & Hardware ULA Matrix Disambiguation:
     The ZX Spectrum Next provides dedicated **`Up`**, **`Down`**, **`Left`**,
     and **`Right`** arrow keys (mapped in the ULA matrix to `Caps Shift` +
     `7`, `6`, `5`, and `8`). Under NextCPM (`SE_NEXT.COM`), the CP/M Plus
     BIOS translates these arrow keys into single-byte control codes (`Right`
     = `0x06`, `Left` = `0x01`/`0x08`, `Up` = `0x05`/`0x1F`/`0x0B`, `Down` =
     `0x18`/`0x1E`/`0x0A`) that overlap with `Ctrl+F` (Find), `Ctrl+A` (Home),
     `Ctrl+E` (End), `Ctrl+K` (Help), and `Ctrl+X` (Move Block). To prevent
     command collisions, `SE_NEXT.COM` (`hal_nextcpm_keyboard.asm`) samples the
     physical ULA keyboard matrix (`port 0x00FE`) when these bytes arrive: if
     the letter key (`F`, `A`, `E`, `K`, `X`) is not physically pressed, the
     input is decoded as an ANSI arrow escape sequence (`\x1b[A`..`\x1b[D`); if
     the letter key is physically held with `EXTEND`, the editor command
     executes normally.
   - Native Target `Symbol Shift` Shortcuts (`SE.NEX` / `.se`):
     In the standalone Next native targets (`SE.NEX` and `.se`), `Symbol Shift`
     also provides single-modifier shortcuts for common control keys:
     `Symbol Shift + Q` (`Ctrl+Q`), `Symbol Shift + W` (`Ctrl+W`),
     `Symbol Shift + E` (`Ctrl+E`), `Symbol Shift + X` (`Ctrl+X`),
     `Symbol Shift + C` (`Ctrl+C`), and `Symbol Shift + I` (`Tab`).
   - External PS/2 Keyboard Support:
     When an external PS/2 keyboard is attached to the ZX Spectrum Next,
     standard `Ctrl+<Key>`, `Esc`, `Tab`, `Backspace`, `Delete`, and arrow
     keys operate directly as labeled.

   - Standard SE Keyboard Keys vs. ZX Spectrum Next SE Keys:

   | Standard SE Key | ZX Spectrum Next SE Key            | Functional Action |
   | :---            | :---                               | :---              |
   | `Up Arrow`      | `Up` (`Caps Shift + 7`)            | Cursor Up 1 row   |
   | `Down Arrow`    | `Down` (`Caps Shift + 6`)          | Cursor Down 1 row |
   | `Left Arrow`    | `Left` (`Caps Shift + 5`)          | Cursor Left 1 col |
   | `Right Arrow`   | `Right` (`Caps Shift + 8`)         | Cursor Right 1 col|
   | `PgUp` (`^U`)   | `INV VIDEO` (`CS+4`) / `EXTEND+U`  | Page Up           |
   | `PgDn` (`^V`)   | `GRAPH` (`CS+9`) / `EXTEND+V`      | Page Down         |
   | `ESC`           | `EDIT` (`Caps Shift + 1`)          | Splash / Cancel   |
   | `Enter`         | `Enter`                            | New line / Confirm|
   | `Backspace`     | `DELETE` (`Caps Shift + 0`) / `^H` | Delete char left  |
   | `Delete` (`^D`) | `EXTEND + D` (`CS + SS + D`)       | Delete char/block |
   | `Tab` (`^I`)    | `TRUE VIDEO` (`CS+3`) / `EXTEND+I` | Insert tab spaces |
   | `Ctrl+A` (`Home`)| `EXTEND + A` (`CS + SS + A`)      | Start of line     |
   | `Ctrl+B`        | `EXTEND + B` (`CS + SS + B`)       | Toggle block mode |
   | `Ctrl+C`        | `BREAK` (`CS + Space`) / `EXT + C` | Copy marked block |
   | `Ctrl+D`        | `EXTEND + D` (`CS + SS + D`)       | Delete char/block |
   | `Ctrl+E` (`End`)| `EXTEND + E` (`Sym Shift + E`)     | End of line (End) |
   | `Ctrl+F`        | `EXTEND + F` (`CS + SS + F`)       | Find text modal   |
   | `Ctrl+G`        | `EXTEND + G` (`CS + SS + G`)       | Bottom of file    |
   | `Ctrl+H`        | `EXTEND + H` (`CS + SS + H`)       | Backspace left    |
   | `Ctrl+I` (`Tab`)| `TRUE VIDEO` (`CS+3`) / `EXTEND+I` | Tab / Toggle case |
   | `Ctrl+K`        | `EXTEND + K` (`CS + SS + K`)       | Help / Block menu |
   | `Ctrl+L`        | `EXTEND + L` (`CS + SS + L`)       | Goto line number  |
   | `Ctrl+N`        | `EXTEND + N` (`CS + SS + N`)       | Find next match   |
   | `Ctrl+O`        | `EXTEND + O` (`CS + SS + O`)       | Open file browser |
   | `Ctrl+P`        | `EXTEND + P` (`CS + SS + P`)       | Plugin palette    |
   | `Ctrl+Q`        | `EXTEND + Q` (`Sym Shift + Q`)     | Safe exit to OS   |
   | `Ctrl+R`        | `EXTEND + R` (`CS + SS + R`)       | Search & Replace  |
   | `Ctrl+S`        | `EXTEND + S` (`CS + SS + S`)       | Save file to disk |
   | `Ctrl+T`        | `EXTEND + T` (`CS + SS + T`)       | Top of file (Row0)|
   | `Ctrl+U` (`PgUp`)| `INV VIDEO` (`CS+4`) / `EXTEND+U` | Page Up           |
   | `Ctrl+V` (`PgDn`)| `GRAPH` (`CS+9`) / `EXTEND+V`     | Page Down         |
   | `Ctrl+W`        | `EXTEND + W` (`Sym Shift + W`)     | Close to splash   |
   | `Ctrl+X`        | `EXTEND + X` (`Sym Shift + X`)     | Move marked block |
   | `Ctrl+Y`        | `EXTEND + Y` (`CS + SS + Y`)       | Beautify code     |
   | `Ctrl+Z`        | `EXTEND + Z` (`CS + SS + Z`)       | Plugin Manager    |

11. The Ten UI/UX Anti-Patterns Checklist
--------------------------------------------------------------------------------
Port authors and maintainers must audit all visual routines against these
ten anti-patterns:

1. Status Bar Squatting:
   - Writing command prompts, text inputs, or alerts on Row 24 / Row 40.
   - Remedy: Move prompts and alerts into Tier 2 centered modal boxes.

2. Blind / Static Footers:
   - Emitting static command options or mode cues (such as `^K: Editor keys`
     on status bar Field 4) during overlay workspaces (like Directory
     Browsers) where editor keystrokes do not apply.
   - Remedy: Ensure footers and status bar contextual slots dynamically
     reflect active context (e.g. Free Memory during overlays).

3. Terminal Column Spill:
   - Emitting strings or line data exceeding terminal column bounds, inducing
     unwanted wraps or scrolling.
   - Remedy: Budget every string length; clip lines at `HOST_COLS`.

4. Inverted Hierarchy:
   - Asking a query before explaining the reason, context, or danger.
   - Remedy: Display descriptive context first, then query, then options.

5. Missing Dual-Exit:
   - Trapping user in menus requiring specific keys while ignoring `ESC` or `Q`.
   - Remedy: Always provide `ESC` to cancel or return to previous surface.

6. Buffer Pointer Clobber:
   - Allowing temporary UI string formatting to corrupt document line caches.
   - Remedy: Use isolated scratch buffers for string formatting and modals.

7. Pop-up Stacking / Ghosting:
   - Drawing a child pop-up directly over an unhidden parent pop-up.
   - Remedy: Hide parent before showing child; redraw parent on child close.

8. Legacy Hotkey Forms & WordStar Aliasing:
   - Using `Y:Yes, N:No` forms or delimiters like `/` and `|` between choices.
   - Aliasing legacy WordStar diamond navigation keys (`^S`, `^D`, `^E`, `^X`)
     to cursor movement in editor or modal input loops, colliding with Save,
     Forward Delete, End of Line, and Cut.
   - Remedy: Format options with brackets `[Y]es   [N]o` separated by spaces;
     restrict directional navigation strictly to standard ANSI arrow keys.

9. Non-ESC Cancellation & Status Pop-up Lock:
   - Using `Ctrl+C` or `q`/`Q` to cancel inputs, or requiring specific keys
     for status pop-ups.
   - Remedy: Enforce `ESC` as sole cancellation for input modals; allow any
     key to dismiss non-input status pop-ups.

10. Column 0 Tilde Inconsistency:
    - Omitting `~` on unallocated body/margin rows or drawing `~` on status bar.
    - Remedy: Display `~` on column 0 of all non-document margin and unallocated
      rows; exclude from status bar and modal dialog interiors.

12. Verification & Conformance Testing
--------------------------------------------------------------------------------
Every ported SE variant must include automated test harnesses verifying UI/UX
design and look-and-feel compliance:

1. Headless PTY Verification:
   - Must boot the editor inside a real pseudo-terminal (`openpty`).
   - Must verify terminal startup clear sequence (`\x1b[2J\x1b[H`).
   - Must verify universal status bar presence on `HOST_ROWS`.
   - Must verify column 0 tilde filling on empty rows.
   - Must verify modal dialog centering, border framing, and child isolation.
   - Must verify tab jump mechanics and tab exclusion (cursor never within
     a tab).
   - Must verify clean shutdown, exit screen clear, exit message banner, and
     exit code 0.

2. Comparative & Emulator Testing:
   - Parallel comparative tests (`compare_cpm_linux.py`, `compare_parallel.py`)
     asserting visual parity between CP/M and ported targets.
   - Automated CP/M emulator sanity test suite (`test_sanity.py`).

3. Code Formatting & Line Width Enforcement:
   - All source code, documentation, and test scripts must strictly satisfy
     the visual line length limit: $\le 80$ characters per line.
   - Verified via:
     ```bash
     python3 check_line_length.py
     ```

4. Buffer Capacity & Scratch Isolation Audit:
   - Ensure `SCRATCH_BUF` and local formatting buffers have adequate capacity
     for the maximum formatted string length plus null terminator.

13. SE.CFG Configuration System & Canonical Defaults (SE.COM CP/M)
--------------------------------------------------------------------------------
The persistent configuration file `SE.CFG` defines startup settings, memory
allocations, screen mode, tab stops, and subsystem behaviors.

1. Configuration File Format:
   - Plain ASCII text with key-value pairs formatted as `KEY=VALUE`.
   - Keys are case-insensitive (`SCREEN`, `Screen`, `screen`).
   - Leading and trailing whitespace around keys and values are ignored.
   - Lines beginning with `#` or `;` are treated as comments and ignored.
   - Blank lines are ignored.
   - Stored on disk using standard CP/M CRLF line endings (`\r\n`).

2. Canonical CP/M Defaults in SE.COM:
   | Parameter | Default | Values | Description |
   | :--- | :--- | :--- | :--- |
   | `SCREEN` | `80X24` | `80X24`, `120X40` | Screen geometry mode |
   | `TAB` | `8` | `4`, `8` | Tab stop spacing |
   | `LINES` | `16K` | `16K`, `32K` | Document line ceiling |
   | `RAMDRIVE` | `PRESERVE` | `PRESERVE`, `ON`, `HIB` | Far RAM bank usage |
   | `PLUGIN` | `AUTOLOAD` | `AUTO`, `DEMAND`, `OFF` | Plugin loading mode |

   - `SCREEN` (Default: `80X24`):
     Geometry mode in `config.inc`. Standard classic 80-column terminal mode
     is selected by default (`MODE_80X24` = 1).
   - `TAB` / `TABS` (Default: `8`):
     Tab stop column interval (`4` or `8`). Applicable across all SE variants;
     default is 8 (`CFG_TAB_WIDTH = 8`, mask = 7), configurable to 4.
   - Document Line Ending Format Exclusion:
     Text file line ending format (`CP/M` CRLF vs `Linux` LF) is NOT an
     `SE.CFG` configuration setting. As specified in Section 7.7, line
     endings are governed per-document: new files default to host native
     format, opened files preserve their existing end-of-line markers, and
     format can be toggled per-file in the Save File screen via `Ctrl+F`.
   - `LINES` / `MAXLINES` (Default: `16K`):
     Maximum document line pointer table capacity (`16K` = 16,384 lines,
     `32K` = 32,768 lines).
   - `RAMDRIVE` / `RAMDISK` (Default: `PRESERVE`):
     Far RAM banking discipline:
     - `PRESERVE` (`0`): Preserves RomWBW RAM disk banks 0x81..0x88.
     - `ON` (`1`): Uses all 12 Far RAM banks (384 KB) for editor buffer heap.
     - `HIBERNATE` (`2`): Automatically dumps RAM disk to `RAMDRV.IMG` on
       startup and restores on exit.
   - `PLUGIN` / `PLUGINS` (Default: `AUTOLOAD` on CP/M-80):
     Plugin subsystem dispatch on <64KB CP/M-80 systems (`SE.COM`,
     `SE_NEXT.COM`) that load `PLUGIN.PRL`:
     - `AUTOLOAD` (`1`): Automatically loads `PLUGIN.PRL` at boot.
     - `ONDEMAND` (`2`): Loads `PLUGIN.PRL` on demand when a plugin is invoked.
     - `DISABLED` (`0`): Plugin manager completely disabled.
     - Note for Non-CP/M Systems & CP/M-86 (`SE.CMD`): On non-CP/M systems and
       CP/M-86 (`SE.CMD`), the plugin manager is builtin
       (`Plugin System : [Builtin]`), and neither the Configure screen nor
       `SE.CFG` can disable the plugin manager (see Section 14.8).

3. Discovery & Persistence Rules:
   - Loading Priority:
     1. Probes the current logged-in default drive first (`0:SE.CFG`).
     2. If not found on default drive, probes the program drive where the
        executable (`SE.COM` or `SE_NEXT.COM`) was executed.
     3. If no `SE.CFG` exists on either drive, internal hardcoded defaults
        are activated.
   - Local Binary Renaming & Dynamic Executable Name Detection (`SE_NEXT.COM` /
     `SE.COM`):
     - On ZX Spectrum Next under NextCPM, the build artifact `SE_NEXT.COM` may
       be deployed as `SE_NEXT.COM` or locally renamed on disk to `SE.COM` for
       typing convenience at the CP/M prompt.
     - During startup (`PROBE_PROGRAM_DRIVE`), `SE_NEXT.COM` probes for both
       `"SE_NEXT COM"` and `"SE      COM"` across the current and logged-in
       drives so program-drive discovery of `SE.CFG` and `.OVL` overlays works
       transparently under either filename, and records the matched executable
       name for UI titles (`Extended Memory Map`) and the exit banner.
   - Saving Destination:
     - Saving configuration (via Configuration Manager `[S]` or programmatic
       save) always writes to the current logged-in default drive (`SE.CFG`),
       preserving the program directory's template file if launched from a
       shared drive.

14. Cross-Platform Implementation Differences & Hardware Adaptation
--------------------------------------------------------------------------------
While cross-platform ports must preserve 100% visual and behavioral parity
with canonical `SE.COM`, hardware and operating system differences require
specific architectural adaptations.

1. Terminal Dimensions & Dynamic Resizing:
   - CP/M Fixed Geometries:
     8-bit CP/M systems communicate with physical CRT or serial terminals having
     fixed screen dimensions (classic `80x24` VT100 / Wyse / Kaypro or `120x40`
     wide console). Screen modes are switched via escape sequences or hardware
     switchers.
   - Modern Native Terminal Dimensions:
     Modern POSIX, Linux, macOS, and container environments run inside
     dynamically resizable terminal emulators (e.g. `xterm`, `tmux`, `kitty`,
     `alacritty`, `gnome-terminal`).
   - Implementation Adaptation:
     - Native ports (C, Python, Rust) query actual terminal dimensions on
       startup via `ioctl(TIOCGWINSZ)` or standard libraries (e.g.
       `os.get_terminal_size()`) instead of being constrained strictly to
       120x40 or 80x24.
     - Universal Status Bar is dynamically anchored to `Row == HOST_ROWS`.
     - Centered workspaces (Splash, Help, Configuration Manager, File
       browsers) recalculate top and left padding dynamically using:
       `TopRow = max(1, ((HOST_ROWS - 1 - ContentHeight) // 2) + 1)`
       `LeftCol = max(2, ((HOST_COLS - ContentWidth) // 2) + 1)`
     - Horizontal viewport panning adapts its right edge threshold to
       `view_cols = HOST_COLS`.
     - Explicit fixed geometry emulation (`80x24` or `120x40`) can still be
       selected via `SE.CFG` (`SCREEN=80x24`) to reproduce retro CRT
       fidelity.
     - Screen Geometry Options & Platform Support:
       - Option 1 (`80x24`): Standard baseline geometry supported across
         all platforms.
       - Option 2 (`120x40`): Wide console mode. Note: If 120x40 screen size
         is not supported on a target platform, option 2 on the splash screen
         will not be shown and 120x40 screen size will not be supported.
       - Option 3 (`Native`): Added to the splash screen when a native screen
         size is also supported (e.g. Linux native ports querying terminal
         dimensions dynamically). Allows users who switched to retro fixed
         modes (80x24 or 120x40) to revert directly back to their native
         terminal window dimensions.
     - Screen Clear on Geometry Switch:
       Prior to switching screen sizes (Option 1, 2, or 3), the screen must
       be explicitly cleared (emitting `\x1b[2J\x1b[H` / `TERM_INIT`) so that
       no artifacts or stale debris remain on the screen.

2. Native Filesystem Differences vs. CP/M:
   - CP/M Flat Drive/User Namespace:
     CP/M BDOS organizes storage into drive letters (`A:`..`P:`) and user
     areas (`0`..`15`) containing 8.3 uppercase filenames. There are no
     hierarchical subdirectories.
   - Host POSIX Hierarchical Filesystems:
     Linux and modern OSes use hierarchical directory trees (`/path/to/dir`),
     case-sensitive long filenames, symlinks, and arbitrary path extensions.
   - File Selection UI Adaptation:
     - Native ports adapt the canonical Open/Save directory browser interface
       to support navigating hierarchical paths or entering host paths while
       retaining identical visual styling (double horizontal rules, tildes,
       bracketed inputs).
     - Status bar and title bars display truncated or normalized relative
       pathnames to respect character budgets and prevent line spill.

3. Foreign Filesystems via Modular Plugins:
   - Different platforms operate on different native filesystems, but foreign
     filesystems are supported across all architectures via modular plugins:
     - CP/M FAT Plugin (`FATFS.PRL` / `FAT12.PRL`):
       Enables 8-bit CP/M systems to mount and browse FAT12, FAT16, and FAT32
       partitions on SD cards, CompactFlash, or IDE hard disks via RomWBW.
       Maps foreign volumes to virtual drives (e.g. `U0:/SUBDIR/FILE.TXT`) with
       directory browsing and file loading directly inside SE.
     - Native Host Plugins (Retro VFS):
       On modern platforms (Linux, macOS), plugins can mount virtual CP/M disk
       images (`.DSK`, `.IMG`), retro archives (`.LBR`, `.ARK`), or remote
       VFS streams, rendering them through SE's canonical directory browser.

4. CP/M Binary Footprint, TPA Headroom & BSS Trimming:
   - Load Origin & BDOS Boundary:
     On CP/M systems, `.COM` executables load at `0x0100` in the Transient
     Program Area (TPA). The execution space is bounded by the BDOS entry
     vector at `0x0006`, pointing to the base of BDOS (e.g. `0xD800` on
     RomWBW RC2014 CP/M 2.2, giving a maximum capacity of 55,040 bytes /
     53.75 KB).
   - CCP Command Loading Safeguards:
     When executing a command, the CP/M Console Command Processor (CCP) loads
     the binary sequentially into the TPA. If the disk binary size extends to
     or past the CCP/BDOS boundary, CCP rejects the command with `BAD LOAD`.
   - BSS Separation & Memory Discipline:
     All CP/M ports (`SE.COM`, `SEC.COM`) must ensure uninitialized buffers
     (BSS) are not emitted as zero-fill bytes into the disk executable.
     For C-based builds (`SEC.COM`), BSS trimming must be enabled
     (`CRT_TRIM_BSS=1`) and total combined runtime memory (Code + Data + BSS)
     must fit strictly below BDOS (`0xD800`), guaranteeing positive TPA
     headroom.

5. Source Code Conditional Compilation & Assembly Directives:
   - Architectural Principle & Divergence Accommodation:
     The SE architecture spans multiple distinct build profiles and execution
     targets across disparate hardware generations—ranging from 8-bit Z80
     CP/M 2.2 / 3.0 (`SE.COM`, `SEC.COM`) and ZX Spectrum Next (`SE_NEXT.COM`,
     `SE.NEX`, `.se`) to modern 64-bit Linux native workstations (`se-linux`)
     and Python (`se-py`).
     Because multiple build profiles share common core implementation files
     (such as the C core modules in `src/core/*.c` shared between `SEC.COM` and
     `se-linux`, or assembly modules in `src/` shared across CP/M and Next
     targets), source code conditional compilation directives (in C: `#ifdef`,
     `#ifndef`, `#if`, `#else`, `#endif`) and conditional assembly directives
     (in Z80 assembly: `IFDEF`, `IFNDEF`, `IF`, `ELSE`, `ENDIF`) SHALL be used
     to accommodate all divergence between SE build profiles and targets.
   - Isolation of Target-Specific Constraints:
     Developers and automated agents must never globally modify shared source
     files to satisfy the constraints, compiler peculiarities, or test harness
     requirements of a single build profile if doing so degrades, violates
     invariants of, or breaks compilation on another profile.
     All platform-specific adaptations must be encapsulated within conditional
     directives:
     - CP/M C Profile (`SEC.COM`):
       Compiled with `z88dk` (`zcc +cpm -O3`), which automatically predefines
       `__CPM__`. Constrained to a ~48 KB TPA and minimal call stack space.
       Conditional compilation directives (`#ifdef __CPM__`) must gate:
       - Compact stack array allocations (e.g. `raw_name[32]`, `core[128]`).
       - Symmetrical 78-column status bar core formatting for 80x24 terminals.
       - TPA-fitted line capacity, stride, and slot sizes (in `config.h`).
       - Headless test harness flow requirements (e.g. silent save returns
         without interactive blocking modal notifications).
     - Linux Native Profile (`se-linux`):
       Compiled with GCC using strict flags (`-Wall -Wextra -Werror -O2`).
       Must NOT be subjected to CP/M stack buffer reductions that trigger
       GCC `-Werror=format-truncation` warnings.
       Conditional compilation directives (`#ifndef __CPM__` or `#ifdef
       __linux__`) must gate:
       - Full-sized stack buffers (`raw_name[80]`, `core[256]`, `full_bar[256]`)
         preventing string format truncation.
       - Canonical Field 4 contextual hierarchy (help key hint, mode cues,
         block metrics, pan indicator, or free memory) and Field 5 fixed
         coordinate anchor per Section 4.3.
       - Tier 2 centered modal save notifications (`Save Complete`, `Export
         Complete`) per Section 4.4 and Section 11.1.
       - POSIX directory scanning and dynamic terminal size querying.
     - ZX Spectrum Next Profiles (`SE.NEX`, `.se`, `SE_NEXT.COM`):
       Conditional assembly directives (`IFDEF NEXT_DOT_COMMAND`, `IFNDEF
       NEXT_DOT_COMMAND`, etc.) must gate:
       - Execution entry origins (`0x2000` for NextOS dot commands vs
         `0x0100` for CP/M TPA vs `0x6000` / `0x8000` for Next native `.nex`).
       - Hardware MMU memory banking and copper/layer 2 configurations vs
         standard CP/M BDOS memory and console calls.

6. About Screen Implementation Language Identification:
   All cross-platform ports and binaries of SE must display the programming
   language predominantly used to create that specific port appended to the
   version number and build date line on the Tier 1 About screen
   (Section 7.12). For example:
   - `SE.COM` / `SE_NEXT.COM` / `SE.NEX` / `.se`:
     `version 1.1.4 (2026-10-18) (Z80 Assembly)`
   - `SE.CMD`:
     `version 1.1.4 (2026-10-18) (x86 Assembly)` (or `(C)`)
   - `se-linux` / `SEC.COM`:
     `version 1.1.4 (2026-10-18) (C)`
   - `se-py`:
     `version 1.1.4 (2026-10-18) (Python)`
   - `se-rs`:
     `version 1.1.4 (2026-10-18) (Rust)`
   All SE variants shall share the identical version number as canonical
   `SE.COM` (e.g. `v1.1.4`). Generic host OS labels (such as `(Linux)`) must
   not be used; each binary shall clearly state its predominant programming
   language on the About screen.

7. Executable Binary Name Discovery & Local Renaming (`SE_NEXT.COM` / `SE.COM`):
   - On ZX Spectrum Next under NextCPM, the build target produces `SE_NEXT.COM`
     to distinguish it from the standard RomWBW `SE.COM` binary in multi-target
     build directories and SD card images. However, on actual ZX Spectrum Next
     hardware, users frequently rename `SE_NEXT.COM` locally to `SE.COM` so the
     editor can be launched simply by typing `SE` at the CP/M prompt.
   - Therefore, `SE_NEXT.COM` must not hardcode `"SE_NEXT.COM"` or `"SE.COM"`
     to the exclusion of the other:
     - Program Drive & Overlay Discovery (`PROBE_PROGRAM_DRIVE`): When searching
       for the program drive (to locate `SE.CFG`, `HELPNEXT.OVL`, or
       `PLUGIN.PRL`), the editor probes each candidate drive for both
       `"SE_NEXT COM"` and `"SE      COM"`.
     - Runtime Binary Name Display: Screen titles and banners that display the
       executable binary name (such as the Extended Memory Map header
       `<BINARY> - Extended Memory Map`, column header `<BINARY> Usage`, and
       the OS exit message `Exiting <BINARY>. Returned to CP/M.`) dynamically
       display the actual detected binary name (`SE_NEXT.COM` or `SE.COM`).

8. Plugin Manager Architecture, Module ABI & Builtin vs. Loadable Systems:
   - Loadable `PLUGIN.PRL` vs. Builtin Plugin Manager:
     - The external `PLUGIN.PRL` relocatable overlay file is only loadable into
       systems constrained to less than 64 KB of base addressable TPA memory—
       specifically 8-bit CP/M-80 systems (`SE.COM` on RomWBW CP/M-80 and
       `SE_NEXT.COM` on Next CP/M-80).
     - The CP/M-80 plugin manager (`PLUGIN.PRL`) auto-detects the underlying
       hardware banking mechanism at runtime (e.g. RomWBW HBIOS bank switching
       vs. ZX Spectrum Next MMU banking).
     - All other SE variants (including CP/M-86 `SE.CMD`, native ZX Spectrum
       Next `SE.NEX` and `.se`, Linux C `se-linux`, Linux Python `se-py`, and
       Linux Rust `se-rs`) have a builtin plugin manager integrated directly
       into the main executable.
   - Plugin Module Non-Interchangeability & API / ABI Boundaries:
     - Non-CP/M plugin modules are not interchangeable with CP/M plugin modules.
     - CP/M-80 plugin modules (`.PRL` / `.OVL` 8-bit Z80 binaries) may share a
       common 8-bit API / ABI (the Z80 `PLUGIN_HOST_API` jump table and
       `.PRL` / `.OVL` binary header contract).
     - CP/M-86 (`SE.CMD`) defines its own 16-bit x86 API / ABI for plugins that
       is not interchangeable with CP/M-80 or non-CP/M systems.
     - Non-CP/M plugin modules may share a common 64-bit API / ABI (e.g. a C
       ABI shared object interface across native C and Rust builds); otherwise,
       each 64-bit programming language (such as C, Rust, or Python) defines
       its own language-specific plugin API / ABI.
   - Builtin Plugin Manager Splash Screen, Configure Screen & `SE.CFG` Behavior:
     - Splash Screen Status: On non-CP/M systems (and CP/M-86 `SE.CMD` with its
       builtin plugin manager), the Splash Screen diagnostic line for the
       plugin subsystem shall display:
       `Plugin System : [Builtin]`
     - Configure Screen & `SE.CFG` Invariance: On non-CP/M systems (and CP/M-86
       `SE.CMD`), because the plugin manager is permanently builtin, neither
       the Configure screen (`[C]`) nor `SE.CFG` (`PLUGIN=...`) can disable the
       plugin manager.

15. Canonical Screen Layouts (SE.COM & Target Profiles)
--------------------------------------------------------------------------------
This section records the exact, row-by-row and column-by-column terminal screen
layouts rendered by canonical CP/M-80 `SE.COM` (`src/se.asm` and `src/core/`)
and its target profiles.

15.1 CP/M-80 `SE.COM` — Startup Splash Screen Layout (`RENDER_SPLASH`)
--------------------------------------------------------------------------------
1. Source Reference:
   - Renderer: `RENDER_SPLASH` (`src/se.asm:2558-2748`)
   - String Constants: `STR_SPLASH_*` (`src/core/plugin_mgr.asm:4263-4306`)
   - Menu Line Count: `SPLASH_MENU_LINES = 21` (`src/include/ui.inc:30`)

2. Vertical & Horizontal Geometry Metrics:
   - Available Workspace Rows: `AvailRows = ACTIVE_ROWS - 1` (`23` in `80x24`,
     `39` in `120x40`).
   - Top Padding (`SPLASH_TOP_PAD_COUNT = (AvailRows - 21) / 2`):
     - `80x24` mode: `1` row (Screen Row 1 displays `~`).
     - `120x40` mode: `9` rows (Screen Rows 1..9 display `~`).
   - Content Block Rows (`21` rows total):
     - `80x24` mode: Screen Rows `2..22`.
     - `120x40` mode: Screen Rows `10..30`.
   - Bottom Padding (`AvailRows - SPLASH_TOP_PAD_COUNT - 21`):
     - `80x24` mode: `1` row (Screen Row 23 displays `~`).
     - `120x40` mode: `9` rows (Screen Rows 31..39 display `~`).
   - Universal Status Bar:
     - Rendered in ANSI inverse video (`\x1b[7m`) on Screen Row `24` (`80x24`)
       or Screen Row `40` (`120x40`), with `1` leading/trailing margin space in
       `80x24` or `21` leading/trailing margin spaces in `120x40` around the
       78-column enclosed status bar (`STATUS_ENCLOSED_WIDTH = 78`).
   - Horizontal Left Padding (`PRINT_SPLASH_PREFIX`):
     - Column 1 of every workspace row (`1..AvailRows`) is `~`.
     - `PRINT_SPLASH_PREFIX` emits `~` followed by `19` spaces in `80x24` mode
       (1-based Column 21) or `39` spaces in `120x40` mode (1-based Column 41).
     - Title row (`STR_SPLASH_TITLE_PAD`) adds `11` further spaces before
       `SE - Screen Editor` (`30` spaces after `~` in `80x24`; `50` spaces
       after `~` in `120x40`).
     - Command rows (`STR_SPLASH_CMDS`) include `2` leading spaces before
       `type` (`21` spaces after `~` in `80x24`; `41` spaces after `~` in
       `120x40`).
     - Diagnostic status rows (`Rows 19..22` in `80x24`) begin directly after
       `PRINT_SPLASH_PREFIX` (`19` spaces after `~` in `80x24`; `39` spaces
       after `~` in `120x40`).

3. Exact 80x24 Screen Layout (1:1 Character Grid, Rows 1..24, SE.COM v1.1.4):
```text
~
~                              SE - Screen Editor
~
~                     type   [E]  or  [Enter] to edit
~                     type   [N]              to new file
~                     type   [O]  or  [^O]    to open file
~                     type   [S]  or  [^S]    to save file
~                     type   [W]  or  [^W]    to close file
~                     type   [L]  or  [^L]    to goto line
~                     type   [A]              for about
~                     type   [M]              for memory info
~                     type   [P]              for plugins
~                     type   [^P]             for context plugin menu
~                     type   [C]              to configure
~                     type   [1]              set 80x24
~                     type   [2]              set 120x40
~                     type   [Q]  or  [^Q]    to exit
~
~                   Active Screen : [80x24 (Classic Terminal)] 
~                   RAM Drive (B:): [Preserved (Active)]
~                   Plugin System : [Operational]
~                   Max Lines     : [16,384 lines]
~
 | (Untitled)     |  80x24 | CP/M  | Free: 64 KB     | Line    1/1    Col 0   | 
```

4. Dynamic Diagnostic Row Permutations (`SE.COM`, Screen Rows 19..22 in 80x24):
   - Screen Row 19 (`Active Screen`):
     - `80x24` mode: `Active Screen : [80x24 (Classic Terminal)] `
     - `120x40` mode: `Active Screen : [120x40 (Modern Default)]`
   - Screen Row 20 (`RAM Drive`, where `<drv>` is detected RAM drive letter,
     e.g. `B:` or `A:`):
     - Protected (default): `RAM Drive (B:): [Preserved (Active)]`
     - Hibernated: `RAM Drive (B:): [Hibernated (Temp Image)]`
     - Overwritten: `RAM Drive (B:): [Overwritten (Max RAM)]`
     - No RAM drive detected: `RAM Drive     : [None Detected]`
   - Screen Row 21 (`Plugin System`):
     - Resident (`PLUGIN_MGR_LOADED == 1`): `Plugin System : [Operational]`
     - On-Demand (`EXT_BANK_COUNT >= 2`, not resident):
       `Plugin System : [On Demand]`
     - Disabled or `< 2` Far RAM banks: `Plugin System : [Disabled]`
   - Screen Row 22 (`Max Lines`):
     - 16K mode (`EXT_BANK_COUNT >= 2`, default):
       `Max Lines     : [16,384 lines]`
     - 32K mode (`EXT_BANK_COUNT >= 2`, `MAX_DOC_LINES_LIMIT == 32768`):
       `Max Lines     : [32,768 lines]`
     - Conventional RAM fallback (`EXT_BANK_COUNT < 2`):
       `Max Lines     : [256 lines (RAM)]`

5. Notes for Other Profiles:
   While canonical CP/M-80 `SE.COM` defines the baseline Splash Screen layout,
   alternative SE profiles adapt specific menu and diagnostic rows to match
   underlying hardware, memory, and OS capabilities:
   - Supported Screen Geometries (`80x24`, `120x40`, and `Native`):
     - `[1] set 80x24` is the universal baseline default present across all
       profiles.
     - `[2] set 120x40` is displayed only on targets that support 120x40 wide
       console geometry. On fixed-geometry hardware such as ZX Spectrum Next
       (`SE_NEXT.COM`, `SE.NEX`, `.se`, where the hardware console is fixed at
       80x24 via `IFDEF TARGET_NEXT`), Option `[2]` is omitted.
     - `[3] set native` (or dynamic host terminal sizing) is supported on
       native host OS profiles (`se-linux`, `se-py`, `se-rs`) capable of
       querying live terminal dimensions (`ioctl(TIOCGWINSZ)` or
       `os.get_terminal_size()`). When active, `Active Screen` reflects the
       native console geometry (e.g. `[Native (Dynamic Console)]` or
       `[<Cols>x<Rows> (Native Terminal)]`).
   - RAM Drive Support (`RAM Drive`):
     - RomWBW RAM drive management (`Preserve`, `Hibernate`, `Overwrite`) is
       specific to RomWBW HBIOS CP/M-80 systems where upper 32KB RAM banks are
       shared between RAM disk `A:` and editor Far RAM.
     - On profiles where a hardware/firmware RAM drive is not applicable (such
       as native Linux ports `se-linux`, `se-py`, `se-rs`, generic CP/M C
       `SEC.COM`, or ZX Spectrum Next native modes), RAM drive support is not
       applicable; the `RAM Drive` diagnostic line either reports
       `[None Detected]` or is omitted.
   - Plugin Manager & Plugin Subsystem (`Plugin System`):
     - `PLUGIN.PRL` is only loadable into systems limited to less than 64 KB of
       base TPA memory, specifically CP/M-80 (RomWBW CP/M-80 `SE.COM` and Next
       CP/M-80 `SE_NEXT.COM`), where it auto-detects the banking mechanism
       (e.g. RomWBW vs. Next) and the Splash Screen displays `[Operational]`,
       `[On Demand]`, or `[Disabled]` (or `[Disabled]` on unbanked `SEC.COM`).
     - All other variants (including CP/M-86 `SE.CMD` with its own 16-bit
       plugin API/ABI, and non-CP/M `SE.NEX`, `.se`, `se-linux`, `se-py`,
       `se-rs`) have a builtin plugin manager. On these systems, the Splash
       Screen displays `Plugin System : [Builtin]`, and neither the Configure
       screen nor `SE.CFG` can disable the plugin manager (see Section 14.8).
   - Maximum Document Lines (`Max Lines`):
     - On 8-bit banked and non-banked systems (`SE.COM`, `SE_NEXT.COM`,
       `SE.NEX`, `.se`, `SEC.COM`), document line capacity is bounded by
       physical RAM/bank tables (`16,384`, `32,768`, or `256` lines).
     - On large-memory host machines (`se-linux`, `se-py`, `se-rs`), a fixed
       maximum line limit is hypothetical (bounded only by host virtual memory),
       so the `Max Lines` diagnostic line may be omitted.
   - Status Bar Free Memory Indication (Field 4):
     - On CP/M-80 `SE.COM` and memory-constrained targets, Status Bar Field 4
       on the Splash Screen displays free document memory (`Free: <N> KB`).
     - On large-memory host machines (or profiles without a bounded document
       memory pool), the free memory indication in Status Bar Field 4 may be
       omitted (rendered as a blank 15-character field `               | ` per
       Section 4.3).

15.2 CP/M-80 `SE.COM` — About Screen Layout (`SHOW_ABOUT_SCREEN`)
--------------------------------------------------------------------------------
1. Source Reference:
   - Renderer: `SHOW_ABOUT_SCREEN` & `PRINT_ABOUT_LINE`
     (`src/se.asm:2777-2922`)
   - String Constants: `STR_ABOUT_*` (`src/core/plugin_mgr.asm:4376-4386`)
   - Content Line Count: `ABOUT_MENU_LINES = 9` (`src/include/ui.inc:31`)

2. Vertical & Horizontal Geometry Metrics:
   - Available Workspace Rows: `AvailRows = ACTIVE_ROWS - 1` (`23` in `80x24`,
     `39` in `120x40`).
   - Top Padding (`ABOUT_TOP_PAD_COUNT = (AvailRows - 9) / 2`):
     - `80x24` mode: `7` rows (Screen Rows `1..7` display `~`).
     - `120x40` mode: `15` rows (Screen Rows `1..15` display `~`).
   - Content Block Rows (`9` rows total):
     - `80x24` mode: Screen Rows `8..16`.
     - `120x40` mode: Screen Rows `16..24`.
   - Bottom Padding (`AvailRows - ABOUT_TOP_PAD_COUNT - 9`):
     - `80x24` mode: `7` rows (Screen Rows `17..23` display `~`).
     - `120x40` mode: `15` rows (Screen Rows `25..39` display `~`).
   - Per-Line Symmetrical Centering (`PRINT_ABOUT_LINE`):
     - Each text line begins with `~` in Column 1, followed by
       `LeftPad = (ACTIVE_COLS - 1 - len(str)) / 2` spaces:
       - Screen Row 8 (`"SE - Screen Editor"`, 18 chars): `30` spaces (`80x24`)
         or `50` spaces (`120x40`).
       - Screen Row 9 (`"version 1.1.4 (2026-10-18) (Z80 Assembly)"`, 41 chars):
         `19` spaces (`80x24`) or `39` spaces (`120x40`).
       - Screen Row 10 (`"by Dean Jenkins"`, 15 chars): `32` spaces (`80x24`)
         or `52` spaces (`120x40`).
       - Screen Row 11: `~` (blank line).
       - Screen Row 12 (`"Google Antigravity 2.23.0 & Gemini 4 Argon Medium"`,
         49 chars): `15` spaces (`80x24`) or `35` spaces (`120x40`).
       - Screen Row 13: `~` (blank line).
       - Screen Row 14 (`"Open source software under the MIT License"`, 42
         chars): `18` spaces (`80x24`) or `38` spaces (`120x40`).
       - Screen Row 15: `~` (blank line).
       - Screen Row 16 (`"Press any key to continue"`, 25 chars): `27` spaces
         (`80x24`) or `47` spaces (`120x40`).
   - Universal Status Bar:
     - Rendered on Screen Row `24` (`80x24`) or Screen Row `40` (`120x40`).

3. Exact 80x24 Screen Layout (1:1 Character Grid, Rows 1..24, SE.COM v1.1.4):
```text
~
~
~
~
~
~
~
~                              SE - Screen Editor
~                   version 1.1.4 (2026-10-18) (Z80 Assembly)
~                                by Dean Jenkins
~
~               Google Antigravity 2.23.0 & Gemini 4 Argon Medium
~
~                  Open source software under the MIT License
~
~                           Press any key to continue
~
~
~
~
~
~
~
 | (Untitled)     |  80x24 | CP/M  | Free: 64 KB     | Line    1/1    Col 0   | 
```

4. Notes for Other Profiles:
   - Predominant Programming Language Tag (Content Row 2 / Screen Row 9):
     All SE variants share the identical release version number and date as
     canonical `SE.COM` (e.g. `version 1.1.4 (2026-10-18)`), appending their
     predominant implementation language in parentheses:
     - `SE.COM`, `SE_NEXT.COM`, `SE.NEX`, `.se`: `(Z80 Assembly)`
     - `SE.CMD`: `(x86 Assembly)` (or `(C)`)
     - `se-linux`, `SEC.COM`: `(C)`
     - `se-py`: `(Python)`
     - `se-rs`: `(Rust)`
   - Status Bar Free Memory Indication (Field 4):
     As on the Splash Screen (Section 15.1.5), large-memory host profiles may
     omit `Free: <N> KB` in Status Bar Field 4 (rendering a blank 15-character
     field `               | `).

15.3 CP/M-80 `SE.COM` — Open File Screen Layout (`DO_OPEN_FILE_UI`)
--------------------------------------------------------------------------------
1. Source Reference:
   - Entry Point & Page Loop: `DO_OPEN_FILE_UI` / `RENDER_OPEN_PAGE`
     (`src/core/ui_browser.asm:4621-4745`)
   - Layout & Rendering Routines: `INIT_DIR_LAYOUT`, `CALC_DIR_BODY_ROWS`,
     `CALC_DIR_TOP_PAD`, `RENDER_DIR_TITLE`, `DISPLAY_DIR_PAGE`,
     `DISPLAY_OPEN_PROMPT`, `DRAW_FILENAME_BOX`, `FINISH_UI_PAGE_AND_STATUS`
     (`src/core/ui_browser.asm:3002-3553, 5200-5568`)
   - Directory Highlight Bar Navigation (`[TAB]`): `INPUT_TAB_TO_DIR_NAV`,
     `DIR_NAV_LOOP`, `DRAW_HL_ON`, `DRAW_HL_OFF`
     (`src/core/ui_browser.asm:6254-6520`)
   - String Constants: `STR_TITLE_OPEN_PRE`, `STR_OPEN_PROMPT_TXT`,
     `STR_ESC_CANCEL_TXT`, `STR_TAB_SELECT_HINT`, `STR_TAB_EDIT_HINT`,
     `STR_PAGE_*` (`src/core/plugin_mgr.asm:4497-4543`)

2. Vertical & Horizontal Geometry Metrics:
   - Available Workspace Rows: `AvailRows = ACTIVE_ROWS - 1` (`23` in `80x24`,
     `39` in `120x40`).
   - Dynamic Vertical Centering (`CALC_DIR_BODY_ROWS` & `CALC_DIR_TOP_PAD`):
     - `FileRows = ceil(PageFiles / DIR_COLS_PER_ROW) + 1` (includes `1`
       trailing blank `~` row after the last file row; or `2` rows when `0`
       files are found).
     - `PromptRows = 3` in single-page mode (`DIR_PAGE_COUNT <= 1`) or `4` in
       multi-page mode (`DIR_PAGE_COUNT >= 2`).
     - `BodyRows = FileRows + PromptRows`; total content block height is
       `3 + BodyRows` rows (including the 3-row title header).
     - `DIR_TOP_PAD_COUNT = max(0, (ACTIVE_ROWS - 4 - BodyRows) / 2)` blank `~`
       rows emitted above the top `===` border.
     - Remaining rows between the prompt line (`UI_CUR_ROW`) and
       `ACTIVE_ROWS - 1` are filled with `~` by `FINISH_UI_PAGE_AND_STATUS`.
   - Title Header Block (`3` rows):
     - Top & Bottom Rules (`PRINT_HR_EQUAL`): `~` in Column 1 followed by
       `ACTIVE_COLS - 2` (`78` in `80x24`, `118` in `120x40`) `=` characters
       (1-based Columns `2..79` in `80x24`).
     - Centered Title Row (`RENDER_TITLE_COMMON`): `~` in Column 1 followed by
       `(ACTIVE_COLS - TitleLen) / 2 - 1` spaces (`23` spaces after `~` in
       `80x24` for the 32-char `"OPEN FILE (DIRECTORY - DRIVE J:)"`).
       - User Area & Filter Suffixes: Appends user number when
         `CURRENT_DIR_USER > 0` (e.g. `DRIVE J1:`) and `: [<filter>]` when a
         wildcard filter is active (e.g. `DRIVE J: [*.TXT])`).
   - Directory Entry Grid (`DISPLAY_DIR_PAGE`):
     - `80x24` mode: `DIR_COLS_PER_ROW = 5` columns, `DIR_COL_WIDTH = 15`
       characters per column, up to `12` file rows (`DIR_PAGE_CAPACITY = 60`
       files/page), `DIR_LEFT_PAD = 2` spaces after `~` (grid starts at 1-based
       Column 4).
     - `120x40` mode: `DIR_COLS_PER_ROW = 7` columns, `DIR_COL_WIDTH = 16`
       characters per column, up to `28` file rows (`DIR_PAGE_CAPACITY = 196`
       files/page), `DIR_LEFT_PAD = 3` spaces after `~` (grid starts at 1-based
       Column 5).
     - Entry Formatting (`FORMAT_DIR_ENTRY_HL`): Compact `NAME.EXT` string
       (padding spaces stripped from 8.3 FCB fields) right-padded with spaces
       to `DIR_COL_WIDTH` (`15` chars in `80x24`).
   - Prompt & Input Footer Block (`DISPLAY_OPEN_PROMPT`):
     - Dash Divider Rule (`PRINT_HR_DASH`): `~` in Column 1 followed by
       `ACTIVE_COLS - 2` (`78` in `80x24`) `-` characters.
     - Optional Pagination Row (shown only when `DIR_PAGE_COUNT >= 2`):
       `~  [Page <cur>/<total>]  <PgUp>/<PgDn>=Page`
     - Command & Filter Hint Row (`STR_ESC_CANCEL_TXT`, prefixed by `~  `):
       `[ESC]=Cancel  Enter [d:][u:][pattern] to list`
       `(e.g. B:, C1:, 1C:, *.TXT)`
     - Filename Input Row (`DRAW_FILENAME_BOX`):
       - Starts with `~  `, followed by `Enter filename to open:` rendered in
         ANSI inverse video (`\x1b[7mEnter filename to open:\x1b[0m`), then
         ` [` + 20-character input field (preloaded with `<Drive><User>:`, e.g.
         `J0:                 `) + mode hint:
         - Text Input Mode (default): `]  [TAB]=Select File          ` (hardware
           cursor visible inside the bracketed box at
           `Col = 27 + DIR_LEFT_PAD + INPUT_CURSOR_POS`, i.e. Column 32 after
           `J0:` in `80x24`).
         - Directory Highlight Mode (toggled via `TAB`):
           `]  [TAB]=Edit Name  [Enter]=OK` (hardware cursor hidden; active
           12-char file cell in the directory grid highlighted in inverse video
           and copied into the input box).
   - Universal Status Bar:
     - Rendered on Screen Row `24` (`80x24`) or Screen Row `40` (`120x40`), with
       Status Bar Field 4 displaying `Free: <N> KB`.

3. Exact 80x24 Screen Layout (1:1 Character Grid, Rows 1..24, SE.COM v1.1.4,
   42 Files on Drive J:, Single-Page):
```text
~
~
~
~==============================================================================
~                       OPEN FILE (DIRECTORY - DRIVE J:)
~==============================================================================
~  1.TXT          10.TXT         2.TXT          20.TXT         30.TXT         
~  3328.TXT       40.TXT         50.TXT         BEAUTIFY.PRL   BIGPLUG.PRL    
~  DIAGBNK.COM    DIGIT5.AS      DIGIT5.ASM     DIGIT5.CPM     FATFS.PRL      
~  FATTEST.COM    HALFPLUG.PRL   HELP.OVL       HELPNEXT.OVL   HIBERN.OVL     
~  MIDPLUG.PRL    OUTPUT.TXT     PLUGBAD.CFG    PLUGIN.CFG     PLUGIN.PRL     
~  ROT13.PRL      SE.ASM         SE.CFG         SE.COM         SEBIG.ASM      
~  SEC.COM        SE_NEXT.COM    SNIP.TXT       TE.BKP         TEMP.TXT       
~  TEMP2.TXT      TEST.TXT       TODO.MD        UP.SUB         VFSTEST.COM    
~  WORDCNT.OVL    ZMC.COM        
~
~------------------------------------------------------------------------------
~  [ESC]=Cancel  Enter [d:][u:][pattern] to list (e.g. B:, C1:, 1C:, *.TXT)
~  Enter filename to open: [J0:                 ]  [TAB]=Select File          
~
~
~
~
 | (Untitled)     |  80x24 | CP/M  | Free: 288 KB    | Line    1/1    Col 0   | 
```

4. Notes for Other Profiles:
   - Native Path & Filter Hint Adaptation:
     - Standard CP/M profiles (`SE.COM`, `SE_NEXT.COM`, `SEC.COM`) display
       CP/M drive, user area, and wildcard syntax (`[d:][u:][pattern]`) and
       preload `<Drive><User>:` (e.g. `J0:`) in the 20-character input box.
     - Native ZX Spectrum Next (`SE.NEX`, `.se`): Under `IFDEF
       TARGET_NEXT_NATIVE`, CP/M user areas do not exist; the hint line adapts
       to `[ESC]=Cancel  Enter [path][pattern] to list (e.g. /dot/, *.TXT)`.
     - Linux / POSIX Native Profiles (`se-linux`, `se-py`, `se-rs`): Display the
       host directory path in the title banner and accept standard POSIX paths
       and filenames without a CP/M `<Drive><User>:` prefix.
   - Status Bar Free Memory Indication (Field 4):
     As on the Splash and About screens (Sections 15.1.5 & 15.2.4), large-memory
     host profiles may omit `Free: <N> KB` in Status Bar Field 4.

