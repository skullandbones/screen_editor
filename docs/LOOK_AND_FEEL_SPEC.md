# SE.COM — Look and Feel Specification for Ported Variants
================================================================================
Canonical UI/UX Specification for Cross-Platform Implementations of SE
================================================================================

1. Scope, Purpose & Invariance Mandate
--------------------------------------------------------------------------------
This specification establishes the authoritative visual layout, terminal
interaction protocols, surface hierarchy, and keybinding behaviors of the
classic CP/M Screen Editor (`SE.COM`).

All native and multi-platform ports—including the Linux C executable
(`se-linux`), the Python 3 implementation (`se-py`), future Rust (`se-rs`),
CP/M-86 (`SE.CMD`), and ZX Spectrum Next (`SE_NEXT.COM`, `SE.NEX`, `.se`)
variants—must conform 100% to this specification.

The overarching design objective is Zero Cognitive Friction:
A user transitioning between 8-bit CP/M hardware and a modern 64-bit Linux
workstation or Raspberry Pi must encounter an identical visual aesthetic,
identical screen geometry, identical modal lifecycles, and identical WordStar
keybindings.

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

6. Horizontal Panning Engine ([Pan +40]) & Line Barrier
--------------------------------------------------------------------------------
1. Physical Line Length Barrier:
   - Maximum physical line length is strictly 120 characters (`MAX_LINE = 120`).
   - When the cursor reaches column 120, character insertion is blocked.
   - No line may ever exceed 120 characters under any circumstance.

2. Horizontal Pan Quantum (+40 Columns):
   - Viewing columns beyond the 80-column screen boundary is accomplished via
     horizontal viewport panning in increments of 40 columns.
   - When cursor column exceeds 79, `pan_col` shifts to 40 (`[Pan +40]`).
   - If cursor column exceeds 119, `pan_col` shifts to 80 (`[Pan +80]`).
   - When cursor retreats below column 40, `pan_col` returns to 0.

3. Viewport Mapping Formula:
   - `ScreenColumn = (BufferCursorCol - PanCol) + 1`
   - Visible text slice for screen row: `line[PanCol : PanCol + ViewportWidth]`

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

3. Help Screen Layout (`Ctrl+K`):
   - Content Width: 70 columns, Content Height: 17 lines.
   - Arranged in two clean tabular columns:
     ```text
     ~
     ~                       SE.COM — EDITOR MODE KEYS
     ~
     ~  Cursor Navigation:                 Block Operations:
     ~    Arrows / WordStar (^S,^D,^E,^X)     Ctrl+B: Toggle Block
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

8. Tier 2 Centered Boxed Modal Pop-ups
--------------------------------------------------------------------------------
Modal pop-ups appear centered over the active screen surface to request input
or display notifications.

1. Mathematical Centering Formulas (1-Based Coordinates):
   - `TopRow = max(1, ((HOST_ROWS - PopupHeight) // 2) + 1)`
   - `LeftCol = max(1, ((HOST_COLS - PopupWidth) // 2) + 1)`

2. Framing Structure:
   - Outer Box: Drawn with standard ASCII borders:
     `+--------------------------------------------------+`
     `|                                                  |`
     `+--------------------------------------------------+`
   - Title Separator: Title row separated by divider line (`+---+`).
   - Interior Text: All lines centered across interior width (`width - 2`).

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

10. WordStar Keybinding Matrix & Behavior
--------------------------------------------------------------------------------
| Key Sequence | ASCII | Symbolic Name | Functional Action in SE             |
| :---         | :---  | :---          | :---                                |
| `Ctrl+S`     | `0x13`| `KEY_CTRL_S`  | Move cursor Left one character      |
| `Ctrl+D`     | `0x04`| `KEY_CTRL_D`  | Move cursor Right one character     |
| `Ctrl+E`     | `0x05`| `KEY_CTRL_E`  | Move cursor Up one line             |
| `Ctrl+X`     | `0x18`| `KEY_CTRL_X`  | Move cursor Down one line           |
| `Ctrl+A`     | `0x01`| `KEY_CTRL_A`  | Jump to beginning of line (Home)    |
| `Ctrl+F`     | `0x06`| `KEY_CTRL_F`  | Open Find Text modal dialog         |
| `Ctrl+N`     | `0x0E`| `KEY_CTRL_N`  | Find Next search match              |
| `Ctrl+R`     | `0x12`| `KEY_CTRL_R`  | Open Search & Replace modal dialog  |
| `Ctrl+L`     | `0x0C`| `KEY_CTRL_L`  | Open Goto Line Number modal dialog  |
| `Ctrl+B`     | `0x02`| `KEY_CTRL_B`  | Toggle block selection mode         |
| `Ctrl+C`     | `0x03`| `KEY_CTRL_C`  | Copy block to clipboard             |
| `Ctrl+X`     | `0x18`| `KEY_CTRL_X`  | Cut block to clipboard (with block) |
| `Ctrl+T`     | `0x14`| `KEY_CTRL_T`  | Jump to Top of document (Row 0)     |
| `Ctrl+G`     | `0x07`| `KEY_CTRL_G`  | Jump to Bottom of document (EOF)    |
| `Ctrl+U`     | `0x15`| `KEY_CTRL_U`  | Page Up (viewport rows - 2)         |
| `Ctrl+V`     | `0x16`| `KEY_CTRL_V`  | Page Down / Paste block             |
| `Ctrl+O`     | `0x0F`| `KEY_CTRL_O`  | Open File input modal               |
| `Ctrl+K`     | `0x0B`| `KEY_CTRL_K`  | Display full-screen Help workspace  |
| `Ctrl+P`     | `0x10`| `KEY_CTRL_P`  | Open context-aware Plugin Palette   |
| `Ctrl+Y`     | `0x19`| `KEY_CTRL_Y`  | Run BEAUTIFY code formatter plugin  |
| `Ctrl+Q`     | `0x11`| `KEY_CTRL_Q`  | Safe exit (prompts if unsaved edits)|
| `ESC`        | `0x1B`| `KEY_ESC`     | Return to Tier 1 Splash screen      |
| `Enter`      | `0x0D`| `KEY_ENTER`   | Split current line at cursor        |
| `Backspace`  | `0x08`| `KEY_BACKSPACE`| Delete char left / join line       |
| `Delete`     | `0x7F`| `KEY_DELETE`  | Delete char under cursor / join line|
| `Tab`        | `0x09`| `KEY_TAB`     | Insert spaces to next tab stop (4/8)|

> [!NOTE]
> Architectural Decision (CP/M Profiles): WordStar diamond navigation
> (`^S`, `^D`, `^E`, `^X`) is explicitly dropped in CP/M implementations
> (`SE.COM` and `SE_NEXT.COM`) to prevent invasive disruption to canonical
> SE.COM keybindings (`Ctrl+S` Save File, `Ctrl+D` Delete Forward, `Ctrl+E` End
> of Line, `Ctrl+X` Cut/Move Block). Navigation on CP/M is provided via ANSI
> VT100 arrow keys and standard navigation shortcuts (`Ctrl+A`/`Ctrl+E`).

11. The Six UI/UX Anti-Patterns Checklist
--------------------------------------------------------------------------------
Port authors must audit all visual routines against these 6 anti-patterns:

1. Status Bar Squatting:
   - Writing command prompts or text input fields on Row 24 / Row 40.
   - Remedy: Move prompts into Tier 2 centered modal boxes (`show_input`).

2. Blind / Static Footers:
   - Emitting static command options that do not apply to current screen state.
   - Remedy: Ensure footers dynamically reflect active context.

3. Terminal Column Spill:
   - Emitting strings or line data exceeding terminal column bounds, inducing
     unwanted wraps or scrolling.
   - Remedy: Budget every string length; clip lines at `HOST_COLS`.

4. Inverted Hierarchy:
   - Asking a query before explaining the reason or danger.
   - Remedy: Display the descriptive warning first, then the query.

5. Missing Dual-Exit:
   - Trapping user in menus requiring specific keys while ignoring `ESC` or `Q`.
   - Remedy: Always provide `ESC` to cancel or return to previous surface.

6. Buffer Pointer Clobber:
   - Allowing temporary UI string formatting to corrupt document line caches.
   - Remedy: Use isolated scratch buffers for string formatting and modals.

12. Verification & Conformance Testing
--------------------------------------------------------------------------------
Every ported SE variant must include automated headless test harnesses
verifying look and feel compliance:

1. Headless PTY Verification:
   - Must boot the editor inside a real pseudo-terminal (`openpty`).
   - Must verify universal status bar presence on `HOST_ROWS`.
   - Must verify column 0 tilde filling on empty rows.
   - Must verify modal dialog centering, border framing, and child isolation.
   - Must verify clean shutdown and exit code 0.

2. Code Formatting & Line Width Enforcement:
   - All source code, documentation, and test scripts must strictly satisfy
     the visual line length limit: $\le 80$ characters per line.
