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

2. Terminal Architecture, Geometries & Character Budget
--------------------------------------------------------------------------------
1. Standard Screen Geometries:
   - Standard Terminal: 80 columns x 24 rows (`80x24`).
     - Rows 1 to 23: Workspace / Document text viewport.
     - Row 24: Universal Status Bar (fixed bottom anchor).
   - Wide Console: 120 columns x 40 rows (`120x40`).
     - Rows 1 to 39: Workspace / Document text viewport.
     - Row 40: Universal Status Bar (fixed bottom anchor).

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
        `\r\nExiting SE.COM. Returned to CP/M.\r\n` (on CP/M targets), or
        `\r\nExiting SE. Returned to OS prompt.\r\n` (on host/Linux targets).
     4. Explicitly restores hardware cursor visibility (`TERM_SHOW_CURSOR`).
     5. Restores original host/CP/M environment state (user area, RAM drive,
        saved stack pointer) and exits cleanly.
     Under no circumstances may an SE port terminate leaving dirty viewport
     contents, hidden cursors, or unreset video attributes in the terminal.

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
   The status bar consists of 5 fixed functional fields separated by `|`:

   +-------------------------------------------------------------------------+
   | | FILENAME.EXT* | 80x24 | Linux | ^K: Editor keys | Line   1 Col  0 |   |
   +-------------------------------------------------------------------------+

   - Field 1 (Filename, 16 chars): `| {name}{mod} |`
     - `{name}`: Active filename (e.g. `README.TXT`, `C:MAIN.C`, `(Untitled)`).
     - `{mod}`: `*` if document has unsaved modifications; space otherwise.
     - Padded to exactly 14 characters plus surrounding spaces.
   - Field 2 (Geometry, 8 chars): ` {geom} |`
     - E.g. ` 80x24 |` or ` 120x40 |`.
   - Field 3 (Operating Environment / Format, 8 chars): ` {fmt} |`
     - E.g. ` CPM   |` or ` Linux |`.
   - Field 4 (Help Hint / Context, 18 chars): ` ^K: Editor keys |`
     - Shows default help key hint.
   - Field 5 (Cursor & Mode Indicator, variable):
     - Line & col: `Line {cur_line:>4}/{tot_lines:<4} Col {col:<3}`
     - Horizontal pan indicator (when `pan_col > 0`): ` [Pan +{pan_col}]`
     - Block mode indicator: ` [SEL]` (active selection) or ` [BLK LOCK]`

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
     Tab stops occur at intervals of `CFG_TAB_WIDTH` (default 4 columns,
     configurable to 8). From any visual column `col`, the number of space
     columns required to advance to the next tab stop is:
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
       (`vis_acc < TARGET_COL < vis_acc + spaces`), the cursor must clamp to
       the beginning of the tab (`char_idx` / `vis_acc`) rather than resting
       within the tab.

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
          If `vis_acc + spaces > TARGET_COL`: Break (stop at tab boundary).
          `vis_acc += spaces`.
          `char_idx += 1`.
        - Else:
          `vis_acc += 1`.
          `char_idx += 1`.
     3. Set `CUR_COL = char_idx`.
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
   - Page Up (`PAGE_UP` / `Ctrl+U`):
     - `step = ACTIVE_ROWS - 2` (22 on 80x24; 38 on 120x40).
     - `CUR_DOC_ROW = max(0, CUR_DOC_ROW - step)`.
     - `TOP_DOC_ROW = max(0, TOP_DOC_ROW - step)`.
     - Clamp: Ensure `TOP_DOC_ROW <= CUR_DOC_ROW`.
     - Realign: `ADJUST_COL_TO_TARGET()`.
   - Page Down (`PAGE_DOWN` / `Ctrl+V` without block):
     - `step = ACTIVE_ROWS - 2`.
     - `max_row = max(0, DOC_TOTAL_LINES - 1)`.
     - `CUR_DOC_ROW = min(max_row, CUR_DOC_ROW + step)`.
     - If `CUR_DOC_ROW >= TOP_DOC_ROW + step`:
       `TOP_DOC_ROW = min(max_row, TOP_DOC_ROW + step)`.
     - Realign: `ADJUST_COL_TO_TARGET()`.

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

6. Horizontal Panning Engine (`[Pan +40]`) & 120-Column Line Barrier:
   - Physical Line Length Barrier:
     - Maximum physical line length is strictly 120 characters
       (`MAX_LINE = 120`). Character insertion beyond 120 is blocked.
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
     - When `VIEW_LEFT_COL > 0`, Status Bar Field 5 displays
       `[Pan +{VIEW_LEFT_COL}]` (e.g. `[Pan +40]`, `[Pan +80]`).
     - When `VIEW_LEFT_COL == 0`, the indicator is cleared.

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
           If `prev_len + cur_len <= 120` (canonical `MAX_LINE` limit):
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
           If `prev_len + cur_len > 120`:
           - Join is inhibited (no-op) to enforce the 120-column line limit
             and prevent buffer overflow or unplanned line truncation.
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
           If `cur_len + next_len <= 120` (canonical `MAX_LINE` limit):
           - Appends next line contents to current line:
             `line[CUR_DOC_ROW] += line[CUR_DOC_ROW + 1]`.
           - Deletes row `CUR_DOC_ROW + 1` from document pointer table.
           - Decrements total lines: `DOC_TOTAL_LINES -= 1`.
           - Cursor remains stationary at `CUR_COL = cur_len` (junction point).
           - Updates sticky target: `TARGET_COL = CALC_VISUAL_COL(CUR_COL)`.
           - Marks document modified: `MODIFIED = 1`.
           - Triggers full viewport re-render (`NEED_SCREEN_RENDER = 1`).
           If `cur_len + next_len > 120`:
           - Pull-up is inhibited (no-op) to preserve 120-column line limit.
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
   - Content Height: 14 lines, Content Width: 50 columns.
   - All rows above `TopRow` and below `TopRow + 14` (up to Row 23) display `~`.
   - Visual Structure:
     ```text
     ~
     ~                SE — Screen Editor
     ~              Version v1.1.0 (Linux)
     ~
     ~       Free Memory: [Dynamic Heap]   Lines: [32K Max]
     ~
     ~                     :e to edit
     ~                     :o to open file
     ~                     :s to save file
     ~                     :c for config
     ~                     :p for plugins
     ~                     :? for help
     ~                     :q to quit
     ~
     ~                   Enter choice: _
     ~
     [STATUS BAR AT ROW 24]
     ```
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
       - `1`: Toggle 120x40 modern terminal mode (`DO_SET_120X40`).
       - `2`: Toggle 80x24 classic terminal mode (`DO_SET_80X24`).
       - `Q` / `q` / `Ctrl+Q`: Safe quit / exit back to OS.
     - Non-Entry Key Exclusion Mandate:
       - The Space bar (`0x20`), ANSI cursor arrow keys (`Up`, `Down`, `Left`,
         `Right`), and all unassigned keystrokes MUST NOT enter editor mode.
         They must be ignored without altering document or buffer state.


3. Help Screen Layout (`Ctrl+K`):
   - Content Width: 70 columns, Content Height: 17 lines.
   - Arranged in two clean tabular columns:
     ```text
     ~
     ~                       SE.COM — EDITOR MODE KEYS
     ~
     ~  Cursor Navigation:                 Block Operations:
     ~    Arrows / ANSI VT100                 Ctrl+B: Toggle Block
     ~    Ctrl+A / Ctrl+E: Home / End         Ctrl+C: Copy Block
     ~    Ctrl+T / Ctrl+G: Top / Bottom       Ctrl+X: Cut Block
     ~    Ctrl+U / Ctrl+V: Page Up / Down     Ctrl+V: Paste Block
     ~
     ~  Search & Replace:                  File & System:
     ~    Ctrl+F: Find Text                   Ctrl+S: Save File
     ~    Ctrl+N: Find Next                   Ctrl+O: Open File
     ~    Ctrl+R: Search and Replace          Ctrl+Q: Safe Quit
     ~    Ctrl+L: Goto Line Number            Ctrl+P: Plugin Palette
     ~    Ctrl+Y: Beautify Source Code        ESC   : Splash Screen
     ~
     ~                   Press any key to continue
     ~
     [STATUS BAR AT ROW 24]
     ```

4. Configuration Manager Workspace (`:c` from Splash):
   - Displays active parameters and allows direct hotkey toggling:
     ```text
     ~
     ~                      SE — Configuration Manager
     ~
     ~                   1. Screen Geometry  : 80x24
     ~                   2. Tab Width        : 4
     ~                   3. Max Line Capacity: 32K
     ~                   4. RAM Drive Mode   : Disabled
     ~
     ~             [S] Save to SE.CFG    [ESC]/[Enter] Return
     ~
     ~                          Enter option: _
     ~
     [STATUS BAR AT ROW 24]
     ```

5. File Open Workspace (`Ctrl+O` / `:o` from Splash):
   - Full-screen Tier 1 directory browser listing files on current drive/user.
   - Screen mode capacity:
     - 80x24 mode: 5 columns x 12 rows (60 files/page), column width 15 chars.
     - 120x40 mode: 7 columns x 28 rows (196 files/page), width 16 chars.
   - Paging navigation via `<PgUp>` and `<PgDn>` when file count exceeds page.
   - Visual Structure (80x24 Mode):
     ```text
     ~====================================================================
     ~                      OPEN FILE (DIRECTORY - DRIVE A:)
     ~====================================================================
     ~  FILE1   .TXT    FILE2   .ASM    README  .DOC    TEST    .C
     ~  PROG    .PAS    MANUAL  .TXT    DATA    .DAT    SE      .COM
     ~
     ~  [Page 1/2]  <PgUp>/<PgDn>=Page
     ~--------------------------------------------------------------------
     ~  [ESC]=Cancel  [d:][u:][pattern] to list (e.g. B:, C1:, *.TXT)
     ~  Enter filename to open: [ README.DOC           ]
     ~
     [STATUS BAR AT ROW 24]
     ```

6. File Insert Workspace (`Ctrl+O` with Active Block / `Ctrl+K R`):
   - Invoked when block selection is active or via `Ctrl+K R` shortcut.
   - Solidifies dynamic block bounds and opens directory browser in insert mode.
   - Streams selected file content into document at cursor without replacing
     existing document lines.
   - Visual Structure (80x24 Mode):
     ```text
     ~====================================================================
     ~                     INSERT FILE (DIRECTORY - DRIVE A:)
     ~====================================================================
     ~  HEADER  .INC    MACROS  .LIB    SNIPPET .ASM    TEST    .C
     ~  PROG    .PAS    MANUAL  .TXT    DATA    .DAT    SE      .COM
     ~
     ~  [Page 1/1]  <PgUp>/<PgDn>=Page
     ~--------------------------------------------------------------------
     ~  [ESC]=Cancel  [d:][u:][pattern] to list (e.g. B:, C1:, *.TXT)
     ~  Enter filename to insert: [ HEADER.INC          ]
     ~
     [STATUS BAR AT ROW 24]
     ```

7. Save File Workspace (`Ctrl+S` / `:s` from Splash):
   - Full-screen Tier 1 save workspace displaying directory contents, target
     filename input box, and line ending format indicator.
   - Line ending format toggle: Pressing `Ctrl+F` toggles between CP/M (`CRLF`)
     and Linux (`LF`) formats.
   - Pre-fills active filename if document already has an associated file.
   - Visual Structure (80x24 Mode):
     ```text
     ~====================================================================
     ~                      SAVE FILE (DIRECTORY - DRIVE A:)
     ~====================================================================
     ~  FILE1   .TXT    FILE2   .ASM    README  .DOC    TEST    .C
     ~  PROG    .PAS    MANUAL  .TXT    DATA    .DAT    SE      .COM
     ~
     ~  Format: [CP/M]   [^F]=Toggle Format
     ~--------------------------------------------------------------------
     ~  [ESC]=Cancel  [d:][u:][pattern] to list (e.g. B:, C1:, *.TXT)
     ~  Enter filename to save: [ MYPROG.ASM          ]
     ~
     [STATUS BAR AT ROW 24]
     ```

8. Block Save Workspace (`Ctrl+S` with Active Block / `Ctrl+K S`):
   - Invoked when block selection is active or via `Ctrl+K S` shortcut.
   - Solidifies dynamic block bounds and opens save dialog in block mode.
   - Writes only the highlighted block lines and characters to target file.
   - Retains block selection state upon completion for subsequent editing.
   - Visual Structure (80x24 Mode):
     ```text
     ~====================================================================
     ~                     SAVE BLOCK (DIRECTORY - DRIVE A:)
     ~====================================================================
     ~  FILE1   .TXT    FILE2   .ASM    README  .DOC    TEST    .C
     ~  PROG    .PAS    MANUAL  .TXT    DATA    .DAT    SE      .COM
     ~
     ~  Format: [CP/M]   [^F]=Toggle Format
     ~--------------------------------------------------------------------
     ~  [ESC]=Cancel  [d:][u:][pattern] to list (e.g. B:, C1:, *.TXT)
     ~  Enter filename to save: [ SNIPPET.TXT         ]
     ~
     [STATUS BAR AT ROW 24]
     ```

9. Document Close Lifecycle (`Ctrl+W` / `:w` from Splash):
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

   Archetype C: Single-Line Text Input (`show_input`)
     Used for text parameters (Find string, Replace string, Goto Line).
     Target input field enclosed in bracket pair `[  text  ]`.
     Terminal cursor placed directly inside bracket field.
     Supports standard editing keys: character entry, Backspace (deletes left),
     Delete / Ctrl+D (deletes under cursor), Left/Right arrows, and Home/End.
     WordStar diamond key mappings (e.g. `Ctrl+S` for left) are not supported.
     ```text
     +--------------------------------------------------+
     |                     Goto Line                    |
     +--------------------------------------------------+
     |        Enter target line number to jump to       |
     |                Goto line: [ 45       ]           |
     |                                                  |
     |          [Enter]=Confirm      [ESC]=Cancel       |
     +--------------------------------------------------+
     ```

   Archetype D: Selection Menu (`show_menu` / Plugin Palette)
     Used for choosing from dynamic list (Plugin Palette, Directory list).
     Numbered items with active selection indicator (`> `).
     Navigation with Up/Down arrows or direct digit key selection.
     ```text
     +--------------------------------------------------+
     |                  Plugin Palette                  |
     +--------------------------------------------------+
     |           Select a plugin to execute:            |
     |  > 1. ROT13    - Rotate letters by 13            |
     |    2. WORDCNT  - Document word, line, count      |
     |    3. BEAUTIFY - Align Z80 assembly labels       |
     |                                                  |
     |   [Up/Down]=Select   [Enter]=Run   [ESC]=Cancel  |
     +--------------------------------------------------+
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
   - Toggled via `Ctrl+B`.
   - Cursor movement extends selection range.

2. Visual Presentation:
   - Highlighting is rendered using ANSI Inverse Video (`\x1b[7m`).
   - Status Bar shows `[SEL]` while selection is in progress.
   - Status Bar shows `[BLK LOCK]` when a search match is pinned.

3. Clipboard Primitives:
   - `Ctrl+C`: Copy active block to internal clipboard buffer.
   - `Ctrl+X`: Cut active block to internal clipboard buffer and delete text.
   - `Ctrl+V`: Paste clipboard buffer at active cursor position.

10. Canonical Keybinding Matrix & Behavior
--------------------------------------------------------------------------------
| Key Sequence | ASCII | Symbolic Name | Functional Action in SE             |
| :---         | :---  | :---          | :---                                |
| `Ctrl+A`     | `0x01`| `KEY_CTRL_A`  | Jump to beginning of line (Home)    |
| `Ctrl+B`     | `0x02`| `KEY_CTRL_B`  | Toggle block selection mode         |
| `Ctrl+C`     | `0x03`| `KEY_CTRL_C`  | Copy block to clipboard             |
| `Ctrl+D`     | `0x04`| `KEY_CTRL_D`  | Delete character forward (DEL)      |
| `Ctrl+E`     | `0x05`| `KEY_CTRL_E`  | Jump to end of line (End)           |
| `Ctrl+F`     | `0x06`| `KEY_CTRL_F`  | Open Find Text modal dialog         |
| `Ctrl+G`     | `0x07`| `KEY_CTRL_G`  | Jump to Bottom of document (EOF)    |
| `Ctrl+K`     | `0x0B`| `KEY_CTRL_K`  | Display full-screen Help workspace  |
| `Ctrl+L`     | `0x0C`| `KEY_CTRL_L`  | Open Goto Line Number modal dialog  |
| `Ctrl+N`     | `0x0E`| `KEY_CTRL_N`  | Find Next search match              |
| `Ctrl+O`     | `0x0F`| `KEY_CTRL_O`  | Open File input modal               |
| `Ctrl+P`     | `0x10`| `KEY_CTRL_P`  | Open context-aware Plugin Palette   |
| `Ctrl+Q`     | `0x11`| `KEY_CTRL_Q`  | Safe exit (prompts if unsaved edits)|
| `Ctrl+R`     | `0x12`| `KEY_CTRL_R`  | Open Search & Replace modal dialog  |
| `Ctrl+S`     | `0x13`| `KEY_CTRL_S`  | Save File to disk                   |
| `Ctrl+T`     | `0x14`| `KEY_CTRL_T`  | Jump to Top of document (Row 0)     |
| `Ctrl+U`     | `0x15`| `KEY_CTRL_U`  | Page Up (viewport rows - 2)         |
| `Ctrl+V`     | `0x16`| `KEY_CTRL_V`  | Page Down / Paste block             |
| `Ctrl+X`     | `0x18`| `KEY_CTRL_X`  | Cut block to clipboard / Move block |
| `Ctrl+Y`     | `0x19`| `KEY_CTRL_Y`  | Run BEAUTIFY code formatter plugin  |
| `ESC`        | `0x1B`| `KEY_ESC`     | Return to Splash / Cancel modal     |
| `Enter`      | `0x0D`| `KEY_ENTER`   | Split line at cursor / Confirm modal|
| `Backspace`  | `0x08`| `KEY_BACKSPACE`| Delete char left / join line       |
| `Delete`     | `0x7F`| `KEY_DELETE`  | Delete char under cursor / join line|
| `Tab`        | `0x09`| `KEY_TAB`     | Insert spaces to next tab stop (4/8)|
| `Up Arrow`   | ANSI  | `KEY_UP`      | Move cursor Up one line             |
| `Down Arrow` | ANSI  | `KEY_DOWN`    | Move cursor Down one line           |
| `Left Arrow` | ANSI  | `KEY_LEFT`    | Move cursor Left one character      |
| `Right Arrow`| ANSI  | `KEY_RIGHT`   | Move cursor Right one character     |

> [!IMPORTANT]
> Architectural Policy on Navigation Keys & WordStar Diamond Deprecation:
> Canonical SE mappings designate `Ctrl+S` for Save File, `Ctrl+D` for Delete
> Forward, `Ctrl+E` for End of Line, and `Ctrl+X` for Cut/Move Block.
> Directional cursor navigation across all variants and surfaces is provided
> exclusively via standard ANSI VT100 arrow keys (`Up`, `Down`, `Left`,
> `Right`) and standard motion shortcuts (`Ctrl+A` Home, `Ctrl+E` End,
> `Ctrl+T` Top, `Ctrl+G` Bottom, `Ctrl+U` PgUp, `Ctrl+V` PgDn).
>
> WordStar diamond directional navigation (`^S`, `^D`, `^E`, `^X`) is strictly
> NOT supported anywhere in SE (including the Document Editor, Centered
> Workspaces, Directory Browsers, and Tier 2 Modal Dialogs). Implementations
> must never alias WordStar diamond keys to directional navigation, as doing
> so creates fatal command collisions with Save, Delete, End, and Cut.

1. Operational Descriptions for Deletion Keys:
   Canonical SE distinguishes between backward deletion, forward deletion, and
   block range deletion across the primary editor, active blocks, and modal
   dialogs:

   - `Backspace` (`KEY_BACKSPACE`, `0x08`, `Ctrl+H`):
     - Editor Workspace: Deletes character to the left of the cursor
       (`CUR_COL - 1`) and moves cursor left. When pressed at column 0
       (`CUR_COL == 0`), joins the current line to the previous line (landing
       the cursor at the junction column) provided the combined line length
       does not exceed 120 columns; blocked at Row 0 Column 0.
     - Block-Active Context: Cancels dynamic block (`BLOCK_ACTIVE = 0`)
       to safeguard highlighted text against accidental deletion.
     - Modal Input Dialogs (Archetype C): Deletes character preceding the
       input cursor inside the bracket field `[  ]`, shifting trailing text
       left and decrementing cursor index; blocked at index 0.

   - `Delete` (`KEY_DELETE`, `0x7F`, ANSI `\x1b[3~`) & `Ctrl+D` (`0x04`):
     - Editor Workspace: Deletes the character directly under the cursor
       without altering cursor column. When pressed at the end of a line
       (`CUR_COL >= len(line)`), pulls up and joins the next line to the
       current line provided the combined length does not exceed 120 columns;
       blocked at the end of the last line.
     - Block-Active Context: Solidifies selection and deletes the entire
       highlighted block range (`DO_DELETE_BLOCK`), resetting block mode and
       moving following text up to the block start.
     - Modal Input Dialogs (Archetype C): Deletes the character directly under
       the input cursor inside the bracket field `[  ]`, shifting trailing text
       left without moving the cursor index; blocked at end of input text.

2. Operational Descriptions for Directional Navigation:
   Directional navigation across all surfaces is performed exclusively with
   standard VT100 ANSI arrow keys and dedicated motion shortcuts:
   - `Up Arrow` (`KEY_UP`): Moves cursor up one row; realigns to sticky
     `TARGET_COL`. Blocked at top of document.
   - `Down Arrow` (`KEY_DOWN`): Moves cursor down one row; realigns to sticky
     `TARGET_COL`. Blocked at bottom of document.
   - `Left Arrow` (`KEY_LEFT`): Moves cursor left one column; wraps to previous
     line at column 0. In modal input fields, shifts cursor index left.
   - `Right Arrow` (`KEY_RIGHT`): Moves cursor right one column; wraps to next
     line at end of line. In modal input fields, shifts cursor index right.
   - Motion Shortcuts: `Ctrl+A` (Home / Start of input), `Ctrl+E` (End of line
     / End of input), `Ctrl+T` (Top of document), `Ctrl+G` (Bottom of
     document), `Ctrl+U` (Page Up), `Ctrl+V` (Page Down without active block).
   - WordStar Prohibition: WordStar diamond navigation keys (`Ctrl+S`,
     `Ctrl+D`, `Ctrl+E`, `Ctrl+X`) are strictly not supported for navigation
     in any editor workspace or modal input dialog.

11. The Ten UI/UX Anti-Patterns Checklist
--------------------------------------------------------------------------------
Port authors and maintainers must audit all visual routines against these
ten anti-patterns:

1. Status Bar Squatting:
   - Writing command prompts, text inputs, or alerts on Row 24 / Row 40.
   - Remedy: Move prompts and alerts into Tier 2 centered modal boxes.

2. Blind / Static Footers:
   - Emitting static command options that do not apply to current screen state.
   - Remedy: Ensure footers dynamically reflect active context.

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
   | `SCREEN` | `120X40` | `80X24`, `120X40` | Screen geometry mode |
   | `TAB` | `8` | `4`, `8` | Tab stop spacing |
   | `FORMAT` | `CPM` | `CPM`, `LINUX` | File line ending mode |
   | `LINES` | `16K` | `16K`, `32K` | Document line ceiling |
   | `RAMDRIVE` | `PRESERVE` | `PRESERVE`, `ON`, `HIB` | Far RAM bank usage |
   | `PLUGIN` | `AUTOLOAD` | `AUTO`, `DEMAND`, `OFF` | Plugin loading mode |

   - `SCREEN` (Default: `120X40`):
     Geometry mode in `config.inc` (`MODE_120X40` = 0). On classic 80-column
     CRT/terminals, `80X24` (`MODE_80X24` = 1) is selected.
   - `TAB` / `TABS` (Default: `8`):
     Tab stop column interval (`4` or `8`). In `se.asm`, default is 8
     (`CFG_TAB_WIDTH = 8`, mask = 7).
   - `FORMAT` (Default: `CPM`):
     Default line ending format for new documents (`CPM` = CRLF `0x0D, 0x0A`,
     `LINUX` = LF `0x0A`).
   - `LINES` / `MAXLINES` (Default: `16K`):
     Maximum document line pointer table capacity (`16K` = 16,384 lines,
     `32K` = 32,768 lines).
   - `RAMDRIVE` / `RAMDISK` (Default: `PRESERVE`):
     Far RAM banking discipline:
     - `PRESERVE` (`0`): Preserves RomWBW RAM disk banks 0x81..0x88.
     - `ON` (`1`): Uses all 12 Far RAM banks (384 KB) for editor buffer heap.
     - `HIBERNATE` (`2`): Automatically dumps RAM disk to `RAMDRV.IMG` on
       startup and restores on exit.
   - `PLUGIN` / `PLUGINS` (Default: `AUTOLOAD`):
     Plugin subsystem dispatch:
     - `AUTOLOAD` (`1`): Automatically loads `PLUGIN.PRL` at boot.
     - `ONDEMAND` (`2`): Loads `PLUGIN.PRL` on demand when a plugin is invoked.
     - `DISABLED` (`0`): Plugin manager completely disabled.

3. Discovery & Persistence Rules:
   - Loading Priority:
     1. Probes the current logged-in default drive first (`0:SE.CFG`).
     2. If not found on default drive, probes the program drive where `SE.COM`
        was executed.
     3. If no `SE.CFG` exists on either drive, internal hardcoded defaults
        are activated.
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
       selected via `SE.CFG` (`SCREEN=80x24`) to reproduce retro CRT fidelity.

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
