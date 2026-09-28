# SE.COM — UI/UX Design System & Philosophy

This document defines the canonical UI/UX design standards, screen surface
taxonomy, keybinding conventions, and anti-pattern checklists for SE.COM
(Screen Editor) and its modular plugins.

All AI agents and developers modifying or creating user interfaces in this
codebase must adhere strictly to these principles.

---

## 1. Core Philosophy & Design Principles

1. **Terminal-First & Geometry-Bound**:
   - The target environment is a standard 80x24 VT100 / ANSI terminal on
     RomWBW / CP/M hardware (Z80 / Z180), scalable to 120x40.
   - **Zero Unplanned Scrolling**: No screen, dialog, or prompt may ever
     exceed terminal bounds or emit unchecked line feeds that push headers off
     the screen. Every character position is budgeted.
2. **Universal Status Bar Presence**:
   - **All screens shall show the status bar.** Regardless of whether the
     active interface is the splash screen, editor workspace, plugin manager,
     configuration screen, or directory browser, the status bar remains
     anchored on the bottom row (`HOST_ROWS`: Row 24 for 80x24 geometry,
     Row 40 for 120x40 geometry) to guarantee constant system state context.
   - **On non-document screens, the status bar indicates the last status of
     the editing screen.**
   - **The status bar no longer shows status events.** Pop-ups are now used
     for all status events.
3. **Strict Column 0 Tilde Discipline**:
   - Tildes (`~`) in column 0 denote background / non-document screen space
     on unallocated body and margin rows.
   - **Tildes in col 0 are used on all screens except for file open and save
     related screens.**
   - Header rows, the status bar, and Tier 2 boxed modal pop-ups do not use
     column 0 tildes.
4. **Dedicated Surfaces & Centered Pop-ups**:
   - Complex interactive tasks belong in dedicated Full-Screen Workspaces
     (Tier 1) or Centered Boxed Modal Pop-ups (Tier 2).
   - **All pop-ups shall be shown in the centre of the screen both
     horizontally and vertically.**
5. **Clean Single-Level Pop-up Visibility**:
   - **When a child pop-up is to be shown, the parent pop-up shall be taken
     off the screen (hidden) and the parent pop-up is redrawn when the child
     pop-up no longer exists (child pop-up no longer shown).**
6. **Mandatory Bracket Notation for Parameters & Hotkeys**:
   - Variable parameters (user inputs, run-time settings), slot indexes,
     list selectors, and action hotkeys shall be expressed inside `[ ]` pairs
     (e.g. `[Y]es / [N]o`, `[ESC]=Cancel`).
   - **The `Y:Yes, N:No` forms are no longer allowed.**
7. **Cancellation & Dismissal Discipline**:
   - **If a pop-up needs user input such as yes or no, then only ESC can
     cancel the pop-up (no use of Ctrl-C or q key).**
   - **A pop-up with no user input, such as a status pop-up, shall be
     dismissable by any key.**

---

## 2. Screen Surface Taxonomy (The 3 Tiers)

Every visual element in SE.COM belongs to one of three strictly defined tiers.
Never blur the boundaries between these tiers.

### Tier 1: Full-Screen Workspaces
* **Examples**: Splash Screen, Editor Workspace, Open File UI, Save File UI,
  Plugin Manager, Configuration Screen, Memory Info Screen.
* **Layout Structure by Workspace Type**:
  - **Editor Workspace**:
    - Document Body: `HOST_ROWS - 1` text rows (Rows 1 to 23 on 80x24
      geometry; Rows 1 to 39 on 120x40 geometry). Unallocated rows below EOF
      use column 0 tildes (`~`).
    - Status Bar: **All screens shall show the status bar** on the bottom row
      (`HOST_ROWS`: Row 24 on 80x24; Row 40 on 120x40).
    - Note: The editor workspace contains no separate header or footer row.
  - **Centered Information & Splash Screens** (Splash, About, Memory Info):
    - Body: Vertically and horizontally centered content block with top and
      bottom margin rows padded with column 0 tildes (`~`).
    - Status Bar: Anchored on the bottom row (`HOST_ROWS`: Row 24 on 80x24;
      Row 40 on 120x40), indicating the last status of the editing screen.
    - Note: Contains no fixed Row 1 header or bottom footer row.
  - **Navigation & Management Workspaces** (Plugin Manager, Config, Browsers):
    - Header (Row 1): Centered screen title and global status indicators.
    - Body: Content display with column 0 tildes (`~`) on margin rows
      (except file open and save screens, which omit column 0 tildes).
    - Paging/Cursor: Selection indicator (e.g. `>[0]` or inverted cursor bar).
    - Footer (`HOST_ROWS - 1`: Row 23 on 80x24; Row 39 on 120x40): Dynamic,
      context-dependent command summary line.
    - Status Bar: Anchored on the bottom row (`HOST_ROWS`: Row 24 on 80x24;
      Row 40 on 120x40), indicating the last status of the editing screen.

### Tier 2: Centered Boxed Modal Pop-ups
* **Examples**: Status Event Notifications (Save Confirmation, File Not Found,
  Done Notification), Save Changes Prompt, Overwrite Warning, Ctrl+P Plugin
  Palette, Unload Plugin Confirm, Embedded About / Help Dialogs.
* **Mandate for Status Events**:
  - Pop-ups are now used for all status events (the status bar no longer
    shows status events).
* **Layout Structure**:
  - Border Box: Distinct ASCII frame (`+---+`, `|   |`).
  - **Centering (Mandatory)**: All pop-ups shall be shown in the centre of
    the screen both horizontally and vertically, calculated dynamically from
    `HOST_COLS` and `HOST_ROWS` in 1-based ANSI coordinates:
    - `TopRow = ((HOST_ROWS - PopupHeight) / 2) + 1`
    - `LeftCol = ((HOST_COLS - PopupWidth) / 2) + 1`
  - **Child Pop-up Display Lifecycle**:
    - When a child pop-up is spawned from an existing parent pop-up, the
      parent pop-up must be hidden (taken off the screen).
    - The child pop-up is rendered centered on a clear base.
    - When the child pop-up is dismissed or closed (no longer exists), the
      parent pop-up is redrawn in full.
    - Multiple overlapping/stacked pop-up layers are strictly prohibited.
  - **Pop-up Classification & Dismissal Semantics**:
    - **Status Event Pop-ups (No User Input)**:
      - Used for informational notices (e.g. Save Confirmation, File Not Found,
        Done Notification).
      - Visual Hierarchy: Event message context followed by dismissal prompt
        (e.g. `[Any Key]=Dismiss`).
      - Dismissal Rule: **A pop-up with no user input such as a status
        pop-up shall be dismissable by any key.**
    - **Decision & Interactive Pop-ups (Needs User Input)**:
      - Used for decisions and inputs (e.g. Save Changes Prompt, Overwrite
        Warning, interactive text input loops).
      - Visual Hierarchy (Mandatory Ordering):
        1. **Context & Warning First**: State consequences before questions
           (e.g. *"Any unsaved edits will be lost if discarded"*).
        2. **Question / Decision Prompt Second**: Present clear question
           (e.g. *"Save changes?"*).
        3. **Action Hotkeys Third**: Present valid choices with hotkeys
           wrapped in `[ ]` pairs (e.g. `[Y]es / [N]o / [ESC]=Cancel`).
           The `Y:Yes, N:No` forms are no longer allowed.
        4. **Cursor Placement**: Blinking cursor positioned adjacent to input.
      - Cancellation Rule: **If a pop-up needs user input such as yes or no,
        then only ESC can cancel the pop-up.** No use of `Ctrl-C` or `q` key.

### Tier 3: Persistent Status Bar (Bottom Row / `HOST_ROWS`)
* **Mandate**: All screens shall show the status bar.
* **Status Events Prohibition**:
  - **The status bar no longer shows status events.** Pop-ups are now used
    for all status events.
* **Content**:
  - Document & Session Info: Active filename, modified flag (`*`), geometry
    (`80x24` / `120x40`), line ending format (`CP/M` / `Linux`), free memory.
  - Non-Document Screens: On non-document screens (Splash Screen, Plugin
    Manager, Configuration Screen, File browsers), the status bar indicates
    the last status of the editing screen.
* **Rules**:
  - Single-line display only.
  - Displays persistent document and session state only.
  - **HARD RULE**: NEVER implement interactive multi-character input loops
    directly on the status row. All user inputs must use dedicated Full-Screen
    interfaces (Tier 1) or Centered Boxed Modal Pop-ups (Tier 2).

---

## 3. Keybinding Orthogonality & Conventions

Every screen and dialog must adhere to uniform keybinding semantics:

* **Dismiss / Cancel Pop-ups & User Input**:
  - **Pop-ups Needing User Input**: If a pop-up needs user input such as yes
    or no, then only `ESC` can cancel the pop-up. `Ctrl-C` and `q`/`Q` must
    never be used to cancel or dismiss input pop-ups or prompts. Pressing
    `ESC` cancels the operation safely without mutating unconfirmed state.
  - **Pop-ups With No User Input**: A pop-up with no user input, such as a
    status pop-up, shall be dismissable by any key.
* **Screen & Menu Exit**:
  - Menus and management screens may be exited using `ESC` or designated exit
    commands (e.g. `Q` on the splash screen to exit to CP/M).
* **Confirm / Execute / Primary Action**:
  - `Enter` runs or confirms the primary action of the selected item or input.
  - Single-key hotkeys (e.g. `[Y]es` / `[N]o`) execute immediately without
    requiring a trailing `Enter`.
* **Navigation**:
  - Directional navigation must dual-bind Arrow keys (`Up`/`Down`,
    `Left`/`Right`) with standard Vi keys (`k`/`j`, `h`/`l`) and/or
    WordStar diamond keys (`Ctrl+E`/`Ctrl+X`, `Ctrl+S`/`Ctrl+D`).

---

## 4. Parameter & Bracket Notation (`[ ]`) Standards

Brackets (`[ ]`) convey structured parameters and triggers across SE.COM:

1. **Mandatory Use of `[ ]` Pairs**:
   - Variable parameters such as user inputs and run-time information
     dependent on user settings shall be expressed inside `[ ]` pairs.
   - Slot indexes, list selectors, and action hotkeys must be expressed
     inside `[ ]` pairs:
     - User Input Fields: `Enter filename: [            ]`, `Goto line: [     ]`
     - Dynamic Settings: `Format: [CP/M]`, `Match: [Case Sensitive  ]`
     - Runtime Resource Info: `Far RAM: [Dynamic On-Demand]`, `Slot: [Free]`
     - Slot Indexes & List Selectors: `[0] BEAUTIFY.PRL`, `[Page 1/2]`
     - Action Hotkeys & Triggers: `[Y]es / [N]o`, `[ESC]=Cancel`
2. **Prohibited Hotkey Syntax & Label Misplacement**:
   - **The `Y:Yes, N:No` forms are no longer allowed.** All hotkey triggers
     must use bracket notation (e.g. `[Y]es / [N]o`).
   - Never place static prompt labels inside brackets (e.g. use
     `Filename: [          ]`, never `[Filename]:`).

---

## 5. Column 0 Tilde (`~`) Discipline

1. **Denoting Non-Document Space**:
   - On full-screen workspaces, a leading tilde (`~`) in column 0 identifies
     unallocated editor buffer rows or background menu padding.
2. **Scoping Rules**:
   - **All screens shall use tildes in column 0**, including:
     - Splash Screen menu padding rows.
     - Editor Workspace (all empty rows below the end of document).
     - Plugin Manager workspace padding rows.
     - Configuration Screen padding rows.
     - About, Memory, and Help screen padding rows.
   - **Exceptions**:
     - File open and save related screens (Open File UI, Save File UI,
       Block Insert UI, Block Save UI) do NOT use tildes in column 0.
     - Column 0 tildes apply strictly to unallocated body and margin rows of
       Tier 1 screens; they do NOT apply to Row 1 header rows, the bottom
       status bar (`HOST_ROWS`), or Tier 2 centered boxed modal pop-ups.

---

## 6. Pop-up Lifecycle & Child Pop-up Management

To avoid visual clutter and maintain crisp boundaries on terminal displays:

1. **Centering**:
   - Every pop-up must be mathematically centered horizontally and vertically
     on the screen using 1-based ANSI terminal coordinates:
     - `TopRow = ((HOST_ROWS - PopupHeight) / 2) + 1`
     - `LeftCol = ((HOST_COLS - PopupWidth) / 2) + 1`
2. **Child Pop-up Isolation**:
   - When an active pop-up opens a child pop-up (e.g. Ctrl+P Plugin Palette
     opening an Unload Confirmation prompt or Plugin Info dialog):
     1. Hide the parent pop-up from the screen.
     2. Draw the child pop-up centered on the base screen.
     3. Keep the child modal active until dismissed (via any key for non-input
        status pop-ups, or confirmed / cancelled via `ESC` for interactive
        pop-ups).
     4. When the child pop-up closes, redraw the parent pop-up in full.
   - Never render a pop-up on top of another visible pop-up.

---

## 7. Existing Codebase Anti-Pattern Catalog

When reading, debugging, or modifying SE.COM assembly files and plugins,
agents must actively check for and refactor these non-conformances:

1. **Status Bar Omission & Status Event Misplacement**:
   - *Symptom*: Clearing or omitting the status bar on the bottom row
     (`HOST_ROWS`), or displaying status events on the status bar.
   - *Remedy*: Ensure all screens call `RENDER_STATUS_BAR` on the bottom row.
     On non-document screens, ensure the status bar displays the last status
     of the editing screen. Display all status events in Tier 2 centered
     boxed modal pop-ups.
2. **Off-Center Pop-ups**:
   - *Symptom*: Hardcoding pop-up coordinates or failing to center both
     horizontally and vertically.
   - *Remedy*: Compute centering dynamically from `HOST_ROWS` and `HOST_COLS`.
3. **Pop-up Stacking / Ghosting**:
   - *Symptom*: Drawing a child pop-up directly over an unhidden parent pop-up.
   - *Remedy*: Hide parent before showing child; redraw parent on child close.
4. **Legacy Hotkey Forms & Bracket Misplacement**:
   - *Symptom*: Using legacy `Y:Yes, N:No` forms or enclosing static prompt
     labels (e.g. `[Filename]:`) in brackets.
   - *Remedy*: Enforce bracketed hotkeys (`[Y]es / [N]o`) and reserve brackets
     for variable parameters, inputs, slot indexes, and hotkeys.
5. **Non-ESC Cancellation & Status Pop-up Lock**:
   - *Symptom*: Using `Ctrl-C` or `q`/`Q` to cancel interactive input dialogs,
     or failing to dismiss status pop-ups (no user input) on any key.
   - *Remedy*: Enforce `ESC` as the sole cancellation key for pop-ups needing
     user input. Ensure pop-ups with no user input (status pop-ups) are
     dismissable by any key.
6. **Tilde Inconsistency**:
   - *Symptom*: Omitting `~` in column 0 on non-file screens, or including `~`
     on file open/save screens, or drawing `~` on header/status rows.
   - *Remedy*: Use column 0 `~` on body rows of all screens except file
     open/save screens.
7. **Status Bar Squatting**:
   - *Symptom*: Drawing an interactive text input loop directly onto the
     status row.
   - *Remedy*: Replace with a Tier 2 centered boxed modal or full-screen UI.
8. **Terminal Column Spill**:
   - *Symptom*: Emitting strings > 78 chars inside padded rows, causing line
     wrapping.
   - *Remedy*: Shorten strings or split across lines; enforce <= 80 columns.

---

## 8. Verification & Quality Gate

Before submitting any UI/UX changes:
1. **Line Length Check**:
   ```bash
   python3 check_line_length.py
   ```
2. **Buffer Capacity Audit**:
   Ensure `SCRATCH_BUF` and local string buffers have adequate space for
   the maximum possible formatted string + null terminator.
3. **Automated Emulator Testing**:
   Assert that:
   - Status bar is visible on the bottom row (`HOST_ROWS`) across all screens.
   - On non-document screens, status bar indicates the last editing status.
   - Pop-ups are used for all status events (status bar shows no events).
   - Pop-ups are centered: `((HOST_ROWS - Height) / 2) + 1` and
     `((HOST_COLS - Width) / 2) + 1`.
   - Child pop-ups hide parent pop-ups and restore them upon exit.
   - User inputs, runtime settings, slot indexes, and hotkeys use `[ ]`.
   - The `Y:Yes, N:No` forms are not used.
   - Pop-ups needing user input (e.g. yes/no) are cancelled solely via `ESC`.
   - Pop-ups with no user input (e.g. status pop-ups) are dismissable by
     any key.
   - Column 0 tildes appear on body rows of all screens except file open/save.
