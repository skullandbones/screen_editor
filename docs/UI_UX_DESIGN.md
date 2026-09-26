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
     RomWBW / CP/M hardware (Z80 / Z180).
   - **Zero Unplanned Scrolling**: No screen, dialog, or prompt may ever
     exceed 80 columns or emit unchecked line feeds that push headers off
     the screen. Every character position is budgeted.
2. **Dedicated Surfaces for Dedicated Tasks**:
   - Do not cram complex interactive flows into tiny status rows. If an
     action requires choosing from multiple items, navigation, or file
     browsing, it belongs in a dedicated Tier 1 Full-Screen workspace or
     a Tier 2 Boxed Modal Dialog.
3. **Contextual Awareness & Transparency**:
   - The system must always communicate:
     1. Where the user is.
     2. What item is currently selected.
     3. Exactly which keys are valid and actionable for that item right now.
   - If an action cannot be performed on the current selection (e.g., config
     on an unconfigurable plugin), that key must either not be shown or
     provide a clear transient status message explaining why.

---

## 2. Screen Surface Taxonomy (The 3 Tiers)

Every visual element in SE.COM belongs to one of three strictly defined tiers.
Never blur the boundaries between these tiers.

### Tier 1: Full-Screen Workspaces
* **Examples**: Splash Screen, Editor Workspace, Open File UI, Save File UI,
  Plugin Manager, Configuration Screen, Memory Info Screen.
* **Layout Structure**:
  - Header: Centered screen title and global system status indicators.
  - Body: Horizontally padded margins (e.g. leading '~' or bordered table).
  - Paging/Cursor: Explicit selection indicator (e.g. `>[0]` or inverted bar).
  - Footer: **Dynamic, context-dependent command summary line** reflecting
    the currently selected item or mode.
  - Status Line: Row 24 reserved for transient notifications.

### Tier 2: Centered Boxed Modal Dialogs
* **Examples**: Save Changes Prompt, Overwrite Warning, Ctrl+P Plugin
  Palette, Embedded About / Help Dialogs.
* **Layout Structure**:
  - Border Box: Distinct ASCII frame (`+---+`, `|   |`).
  - Centering: Dynamically centered horizontally and vertically based on
    `HOST_COLS` and `HOST_ROWS`.
  - **Visual Hierarchy (Mandatory Ordering)**:
    1. **Context & Warning First**: State the consequences of the decision
       before asking the user to decide (e.g. *"Any unsaved edits will be
       lost if discarded"*).
    2. **Question / Decision Prompt Second**: Present the clear question
       (e.g. *"Save changes?"*).
    3. **Action Hotkeys Third**: Present valid choices with hotkeys clearly
       identified (e.g. `Yes / No / ESC:Cancel`).
    4. **Cursor Placement**: Position the blinking hardware cursor
       immediately adjacent to the prompt input character.

### Tier 3: Transient Status Bar (Row 24)
* **Examples**: `[Saved]`, `[Done]`, `[All Slots Full]`, `[No Config]`,
  `[Beautify Done]`, `[Error: File Not Found]`.
* **Rules**:
  - Single-line passive feedback only.
  - Cleared automatically on the next keystroke or screen redraw.
  - **HARD RULE**: NEVER implement interactive multi-character input loops
    (such as filename prompts or parameter entries) on Row 24. Complex inputs
    belong in Tier 1 or Tier 2.

---

## 3. Keybinding Orthogonality & Conventions

Every screen and dialog must adhere to uniform keybinding semantics:

* **Dismiss / Cancel / Exit**:
  - Always support both `ESC` and `Q` (or `Ctrl+Q` / `Ctrl+C`).
  - Dismissing must return safely to the parent screen without mutating
    unconfirmed state.
* **Confirm / Execute / Primary Action**:
  - `Enter` runs or confirms the primary action of the selected item.
  - Single-key hotkeys (e.g. `Y`/`N`) must execute immediately without
    requiring a trailing `Enter`.
* **Navigation**:
  - Directional navigation must dual-bind Arrow keys (`Up`/`Down`,
    `Left`/`Right`) with standard Vi keys (`k`/`j`, `h`/`l`) and/or
    WordStar diamond keys (`Ctrl+E`/`Ctrl+X`, `Ctrl+S`/`Ctrl+D`).
* **Hotkey Formatting**:
  - Hotkey choices must clearly distinguish the active trigger letter:
    either bracketed (`[Y]es / [N]o`) or underlined ANSI escapes.

---

## 4. Dynamic Context-Aware Footers

On any screen featuring selectable items (such as the Plugin Manager or File
Selector):
1. **Dynamic Re-generation**: The footer line must be re-evaluated and
   redrawn whenever the selection cursor changes.
2. **True State Representation**:
   - When an empty slot is selected: show load, navigation, and exit keys.
   - When a loaded plain plugin is selected: show `Enter:run`, `L:load`,
     `U:unload`, navigation, and exit.
   - When an About-capable plugin is selected: explicitly include `A:about`.
   - When a Config-capable plugin is selected: explicitly include `C:config`.
   - When both are supported: include both `A:about` and `C:config`.
3. **Strict Column Budget**:
   - Combined footer length (prefix + dynamic keys) must never exceed
     78 characters, ensuring it fits cleanly on an 80-column terminal with
     margin padding without wrapping.

---

## 5. Existing Codebase Anti-Pattern Catalog

When reading, debugging, or modifying SE.COM assembly files, agents must
actively look for these 6 non-conformances and refactor them:

1. **Status Bar Squatting**:
   - *Symptom*: Drawing an interactive text input loop directly onto Row 24.
   - *Remedy*: Replace with full-screen selector (`DO_OPEN_FILE_UI`) or
     a Tier 2 centered boxed modal.
2. **Blind / Static Footer**:
   - *Symptom*: Displaying fixed help keys that don't match the selected item.
   - *Remedy*: Implement dynamic footer formatter based on item capabilities
     (e.g., `FORMAT_PLUGIN_FOOTER`).
3. **Terminal Column Spill**:
   - *Symptom*: Emitting strings > 78 chars inside padded rows, causing
     unplanned line wrapping and screen disruption.
   - *Remedy*: Shorten strings or split across lines; enforce $\le 80$ columns.
4. **Inverted Visual Hierarchy**:
   - *Symptom*: Asking a decision question before explaining consequences.
   - *Remedy*: Place consequence/warning context before the question prompt.
5. **Missing Dual-Exit**:
   - *Symptom*: Supporting `ESC` but ignoring `Q` (or vice-versa) on menus.
   - *Remedy*: Wire both `ESC` and `Q`/`q` to the exit handler.
6. **Buffer Pointer Clobber**:
   - *Symptom*: Overwriting `DE` or scratch pointer registers during formatting.
   - *Remedy*: Use `BC` for arithmetic offsets; preserve pointer registers
     with `PUSH`/`POP`.

---

## 6. Verification & Quality Gate

Before submitting any UI/UX changes:
1. **Line Length Check**:
   ```bash
   python3 check_line_length.py
   ```
2. **Buffer Capacity Audit**:
   Ensure `SCRATCH_BUF` and local string buffers have adequate space for
   the maximum possible formatted string + null terminator.
3. **Automated Emulator Testing**:
   Add or update interactive test suites (such as
   `tests/test_plugin_interactive.py`) to assert that context-dependent
   text appears and updates correctly across all navigation states.
