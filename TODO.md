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
- **Status**: Active / 1 Open (Bug 2.1.21 Open;
  Bugs 2.1.1, 2.1.3-2.1.12, 2.1.15, 2.1.20 Rejected;
  Bugs 2.1.2, 2.1.13, 2.1.14, 2.1.16, 2.1.17, 2.1.18, 2.1.19, 2.1.22 Fixed).
- **Active Defects & Issue Tracking (UI_UX_DESIGN.md Conformance)**:
  - [x] **Bug 2.1.1: Status Bar Field Squatting & Layout [REJECTED / WONTFIX]**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 4.3, 6.6, 9.2.
    - *Disposition*: **REJECTED / WONTFIX** per canonical specification.
    - *Rationale*: Analysis of `SE.COM` (`src/core/ui_render.asm:998-1244`)
      establishes that Field 4 is canonically defined as a dynamic 15-character
      contextual slot (+ " | " separator) operating under a strict priority
      hierarchy (Free Memory on splash/plugin, Block Selection metrics, Pan
      offset, Overwrite mode, or default Help Key Hint). Anti-Pattern #1
      (Status Bar Squatting) governs interactive input loops on row 24, not
      contextual status indicators. Appending mode tags to Field 5 would
      violate Field 5's fixed 22-character jitter-free coordinate budget and
      cause line wrapping (> 78 cols). Furthermore, Field 3 `CP/M  |` is the
      canonical format string in Section 4.3, and Field 2 uses 1 leading space
      (` 80x24 | `) matching `120x40 | ` width.
  - [x] **Bug 2.1.2: Startup Screen Geometry Inversion [FIXED]**:
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
  - [x] **Bug 2.1.4: Tier 1 Help Screen Layout [REJECTED / WONTFIX]**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 5.2, 7.1, 7.3.
    - *Disposition*: **REJECTED / WONTFIX** per canonical specification.
    - *Rationale*: Analysis of `SE.COM` (`plugins/help.asm` / `HELP.OVL`)
      confirms that the 22-line Help screen is the authoritative reference
      template across all SE variants. The proposed 17-line layout was an
      obsolete early wireframe containing duplicated keys (`Ctrl+V`),
      fictitious commands (`Ctrl+Y`), and redundant title prefixes
      (`SE.COM — `). In 80x24 mode, the 22-line block fits within the 23
      available text rows (0 top margin rows, 1 bottom margin row of `~` at
      Row 23, and status bar at Row 24). In 120x40 mode, it is symmetrically
      centered with 8 top and 9 bottom margin rows and 20 columns of horizontal
      padding. Banner rules `=` and `-` adhere to Tier 1 framing standards.
      Field 4 canonically displays free memory during overlay execution per
      Section 4.3.
  - [x] **Bug 2.1.5: Splash Screen Centering & Menu [REJECTED / WONTFIX]**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 7.1, 7.2.
    - *Disposition*: **REJECTED / WONTFIX** per architectural decision.
    - *Rationale*: The demand to replace `SE.COM`'s 21-line splash menu with an
      obsolete 14-line (`:e to edit`, `:o to open`) presentation was based on an
      early conceptual wireframe. `docs/UI_UX_DESIGN.md` Section 7.2 explicitly
      codifies canonical `SE.COM`'s 21-line centered menu (`type [E] or [Enter]
      to edit...`) as the authoritative splash screen template across ALL SE
      variants, and expressly prohibits queries such as `Enter option: _`.
      `SE.COM` already implements this canonical 21-line template.
  - [x] **Bug 2.1.6: Goto Line Modal Footer Buttons [REJECTED / WONTFIX]**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 8.1, 8.3 (Archetype C).
    - *Disposition*: **REJECTED / WONTFIX** per canonical specification.
    - *Rationale*: Analysis of `SE.COM` (`src/core/editor.asm:1466-1518` and
      `src/core/plugin_mgr.asm:4170-4180`) confirms that `[Enter]=Goto Line
      [ESC]=Cancel` is the canonical footer phrasing. The draft wireframe in
      Section 8.3 previously rendered an inaccurate 8-row box with generic
      `[Enter]=Confirm`. Archetype C modals consistently use specific action
      verbs (`[Enter]=Find` for Find Text, `[Enter]=Replace` for Replace, and
      `[Enter]=Goto Line` for Goto Line). Section 8.3 has been codified to
      match `SE.COM`'s canonical 50x7 layout and explicit footer.
  - [x] **Bug 2.1.7: Clipboard Paste & Buffer Primitives [REJECTED / WONTFIX]**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 9, 10.
    - *Disposition*: **REJECTED / WONTFIX** per architectural decision.
    - *Rationale*: Dropped support for detached intermediary clipboard buffers
      and `Ctrl+V` clipboard paste across all SE variants. All implementations
      strictly enforce Direct In-Place Block Manipulation (`Ctrl+B` toggle,
      `Enter` solidify, `Ctrl+C` copy directly to cursor, `Ctrl+X` move
      directly to cursor, `Ctrl+D` / `DEL` delete block, `Ctrl+K` block menu
      popup, `Ctrl+S` save block, `Ctrl+O` insert file). Intermediary clipboard
      buffers are strictly prohibited across all variants to conserve memory,
      respect CP/M TPA headroom, and eliminate state desynchronization.
      Directional page navigation is handled exclusively via dedicated `PgUp`
      and `PgDn` keys; `Ctrl+U` and `Ctrl+V` are removed as paging shortcuts.
  - [x] **Bug 2.1.8: Line Join Length Barrier [REJECTED / WONTFIX]**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 6.8, 10.1.
    - *Disposition*: **REJECTED / WONTFIX** per architectural decision.
    - *Rationale*: The 120-column limit in `docs/UI_UX_DESIGN.md` was an error
      in the design specification that conflated terminal screen width (120x40
      console mode) with document line buffer capacity. `SE.COM` correctly
      enforces `MAX_INPUT_LINE_CHARS` (1,000 characters) across `src/core/`
      (`JOIN_TWO_LINES` in `editor.asm`, `do_backspace` / `do_delete` in
      `editor.c`), fully supported by horizontal panning (`[Pan +40]`).
      `docs/UI_UX_DESIGN.md` has been corrected to reference the canonical
      1,000-character barrier.
  - [x] **Bug 2.1.9: Column Clamping on Expanded Tab [REJECTED / WONTFIX]**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 6.2, 6.4.
    - *Disposition*: **REJECTED / WONTFIX** per architectural decision.
    - *Rationale*: The Tab Exclusion Mandate is 100% satisfied in `SE.COM`;
      the cursor never rests within a tab because `CUR_COL` is an integer byte
      offset into document memory. When `TARGET_COL` falls across an expanded
      tab (`vis_acc < TARGET_COL < vis_acc + spaces`), `SE.COM` intentionally
      uses "snap-forward" behavior (`ADJUST_COL_TO_TARGET`), aligning with the
      character boundary directly after the tab (e.g. column 8 rather than
      column 0). This preserves alignment with indented text during vertical
      navigation. `docs/UI_UX_DESIGN.md` has been updated to explicitly codify
      snap-forward alignment.
  - [x] **Bug 2.1.10: Modal In-Field Cursor Movement [REJECTED / WONTFIX]**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 8.3, 10.1, 10.2.
    - *Disposition*: **REJECTED / WONTFIX** per architectural decision.
    - *Rationale*: In-field cursor movement behaviors are identical across all
      SE variants. Full in-field cursor movement (Left/Right arrows, Delete
      under cursor, Backspace, Home, and End) is supported across all variants
      in the Tier 1 directory filename input screens (Section 7.9). In
      contrast, Archetype C single-line modals (Find, Replace, Goto Line) are
      intentionally designed as lightweight append/backspace linear input
      fields across all variants to conserve memory, preserve CP/M TPA
      headroom, and keep modal interactions robust. The requirement for
      intra-field cursor tracking and mid-string insertion inside Archetype C
      modals is rejected. The separate defect where unexpected keystrokes (such
      as cursor arrow keys) cancel the modal dialog has been split out and
      tracked as Bug 2.1.17.
  - [x] **Bug 2.1.11: Config Manager Menu Layout [REJECTED / WONTFIX]**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 7.4.
    - *Disposition*: **REJECTED / WONTFIX** per architectural decision.
    - *Rationale*: The 4-option wireframe in `docs/UI_UX_DESIGN.md` Section 7.4
      was an early conceptual sketch that omitted the Plugin Manager and
      Config Status. In `SE.COM`, Option 5 (`5. Plugin Manager`) is required
      to configure whether the Far RAM plugin subsystem is autoloaded or
      disabled, and `Config Status` provides essential feedback on whether
      `SE.CFG` was loaded from current or program drive. Furthermore, the
      Configuration Manager is an instant-reaction hotkey event loop
      (`1-5` toggle, `S` save, `ESC`/`Enter`/`Q` return); an `Enter option: _`
      prompt line with an interactive terminal cursor is inappropriate and
      misleading for a single-keypress dispatch loop. `docs/UI_UX_DESIGN.md`
      has been updated to reflect the canonical 5-option hotkey layout.
  - [x] **Bug 2.1.12: Splash Hotkeys & Screen Debris [REJECTED / WONTFIX]**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 2.1, 7.2, 14.1.
    - *Disposition*: **REJECTED / WONTFIX** per architectural decision.
    - *Rationale*: The claim that switching modes leaves screen debris due to
      omitting `\x1b[2J\x1b[H` was factually false; `RENDER_SPLASH` in
      `src/se.asm:2595` already executes `CALL TERM_CLEAR_SCREEN` emitting
      `\x1b[2J\x1b[H` before repainting the splash workspace and status bar.
      Furthermore, in `SE.COM`, `[1]` = 120x40 and `[2]` = 80x24 was
      synchronized between `STR_SPLASH_CMDS` and `SPLASH_LOOP` for RomWBW
      hardware. The requirement to harmonize splash screen hotkeys across all
      variants (`1` = 80x24 default, `2` = 120x40 if supported) has been
      split out and tracked as a discrete enhancement in Bug 2.1.18.
  - [x] **Bug 2.1.13: Escape Sequence Trailing Byte Leakage [FIXED]**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 10.3.
    - *Issue*: In `src/core/editor.asm:217-383` (`HANDLE_CSI`, `HANDLE_CSI_1`,
      `HANDLE_CSI_2`, and `HANDLE_CSI_LOOP`), when an unhandled or extended
      multi-byte escape sequence is encountered (such as function keys F5–F12:
      `\x1b[15~`–`\x1b[24~`, bracketed paste sequences `\x1b[200~`, or mouse
      tracking events), the sub-handlers execute `RET` upon encountering
      unrecognized digits or non-matching characters without consuming the
      remainder of the sequence. Trailing sequence characters (specifically the
      terminating `'~'` or trailing parameter digits) remain pending in the
      BIOS console input buffer and are subsequently read by `MAIN_LOOP` as
      regular typed keystrokes, erroneously inserting literal `'~'` or digits
      directly into the document text buffer.
    - *Required Fix*: In `src/core/editor.asm`, update `HANDLE_CSI` sub-handlers
      (`HANDLE_CSI_1`, `HANDLE_CSI_2`, `HANDLE_CSI_LOOP`) and `HANDLE_SS3` so
      that unrecognized or unhandled multi-byte sequences drain remaining bytes
      until a terminating character (e.g. `'~'`, `'A'..'Z'`, `'a'..'z'`) or
      timeout, preventing trailing escape sequence bytes from leaking into the
      editor document buffer.
  - [x] **Bug 2.1.14: Predominant Language on About Screen [FIXED]**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 7.12, 14.6.
    - *Issue*: In `src/core/plugin_mgr.asm:4384`, `STR_ABOUT_VERSION` displays
      `version 1.1.0 (2026-10-09)`, omitting the predominant programming
      language. Per `docs/UI_UX_DESIGN.md` Section 7.12 and 14.6, all SE
      variants must display the predominant programming language appended to
      the version number and build date on the About screen (`[A]` from
      splash): `version 1.1.0 (2026-10-09) (Z80 Assembly)`. (The splash screen
      itself serves as the clean canonical template across all variants
      without displaying programming language or version numbers).
    - *Required Fix*: In `src/core/plugin_mgr.asm:4384`, update
      `STR_ABOUT_VERSION` to append ` (Z80 Assembly)`:
      `STR_ABOUT_VERSION: DB "version 1.1.0 (2026-10-09) (Z80 Assembly)", "$"`.
      Ensure `SHOW_ABOUT_SCREEN` in `src/se.asm`, `src/se_next.asm`, and
      `src/se_next_cpm.asm` centers the line cleanly within the content block.
  - [x] **Bug 2.1.15: FORMAT Parameter in SE.CFG [REJECTED / WONTFIX]**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 7.7, 13.2.
    - *Disposition*: **REJECTED / WONTFIX** per architectural decision.
    - *Rationale*: Text file line ending format (`CPM` vs `Linux`) is strictly
      a per-document property and not an installation setting in `SE.CFG`.
      Across all SE variants, newly created documents default to the host
      platform's native text file format (CRLF on CP/M and Next, LF on Linux),
      opened files preserve their existing detected end-of-line markers, and
      format can be toggled per-file in the Save File screen via `Ctrl+F`
      before writing to disk. `SE.CFG` strictly mirrors the 5 canonical options
      of the Configuration Manager (`SCREEN`, `RAMDRIVE`, `LINES`, `TAB`,
      `PLUGIN`), which has no format option. `docs/UI_UX_DESIGN.md` has been
      updated to remove `FORMAT` from `SE.CFG` and detail per-document line
      ending handling in Section 7.7.
  - [x] **Bug 2.1.16: Forward Deletion Line Join Target Column [FIXED]**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 6.8.
    - *Issue*: In `src/core/editor.asm:1874-1883` (`DO_DEL_FWD_JOIN_NEXT`),
      when the current line and next line are joined on Delete at EOL,
      `JOIN_TWO_LINES` merges the lines, but `DO_DEL_FWD_JOIN_NEXT` fails to
      update `TARGET_COL = CALC_VISUAL_COL(CUR_COL)`.
    - *Required Fix*: In `DO_DEL_JOIN_OK`, call `CALC_VISUAL_COL` and update
      `(TARGET_COL),HL`.
  - [x] **Bug 2.1.17: Modal Cancellation by Unexpected Keys [FIXED]**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 8.2, 8.3, 11.
    - *Issue*: In `src/core/editor.asm:1420-1440` (`DO_GOTO_LINE_UI`),
      `src/core/search.asm:214-233` (`DO_FIND_UI`), and
      `src/core/search.asm:1940-1960` (`DO_REPLACE_UI`):
      - Receiving unexpected keys or escape sequences (such as cursor arrow
        keys, PgUp/PgDn, or function keys) routes into `GOT_ESC_SEQ` handlers.
      - These handlers invoke `CALL GOT_ESC_BYTE`, executing cursor navigation
        commands on the underlying document beneath the modal and abruptly
        dismissing the dialog.
      - Modals must only be dismissed by explicit `Enter` (confirm) or
        standalone `ESC` (cancel); unexpected keys and multi-byte escape
        sequences must be cleanly drained and discarded without executing
        background actions or aborting the active dialog.
    - *Required Fix*: In `DO_GOTO_LINE_UI`, `DO_FIND_UI`, and `DO_REPLACE_UI`,
      drain and discard unexpected escape sequences and unassigned keys,
      preserving the active modal dialog and retaining input buffer state.
  - [x] **Bug 2.1.18: Splash Screen Geometry Hotkeys [FIXED]**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 2.1, 7.2.
    - *Issue*: Splash screen geometry hotkeys are standardized across all SE
      variants so that `1` selects 80x24 (universal baseline and default)
      and `2` selects 120x40 (if supported). In `SE.COM`, `STR_SPLASH_CMDS` in
      `src/core/plugin_mgr.asm:4290-4291` currently displays `type [1] set
      120x40` and `type [2] set 80x24`, and `SPLASH_LOOP` in
      `src/se.asm:578-584` dispatches `'1'` to `DO_SET_120X40` and `'2'` to
      `DO_SET_80X24`.
    - *Required Fix*: In `src/core/plugin_mgr.asm:4290-4291`, update
      `STR_SPLASH_CMDS` to display `type [1] set 80x24` and `type [2] set
      120x40`. In `src/se.asm:578-584`, update `SPLASH_LOOP` to dispatch
      `'1'` to `DO_SET_80X24` and `'2'` to `DO_SET_120X40`.
  - [x] **Bug 2.1.19: Search & Replace Line Length Barrier [FIXED]**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 6.6.
    - *Issue*: In `src/core/search.asm:2386-2400` (`DO_REPLACE_CURRENT`), after
      computing replacement line length `L' = C - B + E`, the code executes
      `CP MAX_LINE_STRIDE-7` (121) using an 8-bit comparison. If the resulting
      line exceeds 120 characters, it halts replacement, calls
      `SHOW_POPUP_LINE_TOO_LONG`, and displays `Line > 120 chars - skipped.`
      from `STR_POPUP_TOO_LONG_MSG1`. Per Section 6.6, all SE variants support
      line lengths up to `MAX_INPUT_LINE_CHARS` (1,000 characters), supported by
      horizontal panning (`[Pan +40]`). Limiting Search & Replace to 120
      characters truncates replacements on long lines and creates an artificial
      barrier contradicting the 1,000-character standard.
    - *Required Fix*: Update `DO_REPLACE_CURRENT` in `src/core/search.asm` to
      evaluate line capacity using a 16-bit comparison against
      `MAX_INPUT_LINE_CHARS` (1,000 characters) and update line strings.
  - [x] **Bug 2.1.20: Deprecated Paging Keys (Ctrl+U / Ctrl+V) [REJECTED]**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 7.3, 10.
    - *Disposition*: **REJECTED / WONTFIX** per canonical specification.
    - *Rationale*: Section 7.3 explicitly codifies `Ctrl+U / PgUp` (Page Up)
      and `Ctrl+V / PgDn` (Page Down) in the canonical 22-line Help Screen
      template across all SE variants. On standard serial terminals, VT100
      consoles, and retro keyboards lacking dedicated PgUp and PgDn keys,
      `Ctrl+U` and `Ctrl+V` are standard paging control keys. Removing them
      from `SE.COM` would break terminal accessibility and contradict Section
      7.3. Section 10 has been updated to include `Ctrl+U` and `Ctrl+V` as
      paging aliases while reaffirming the prohibition of clipboard paste.
  - [ ] **Bug 2.1.21: Help Screen Omits `Ctrl+Y` and `Ctrl+Z`**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 7.3, 10;
      `docs/KEYBINDINGS.md`.
    - *Issue*: The editor handles `Ctrl+Y` (Beautify block / whole file,
      `CHECK_CTRL_Y`) and `Ctrl+Z` (Plugin Manager screen, `CHECK_CTRL_Z`),
      but `STR_HELP_BODY` in `plugins/help.asm` (`HELP.OVL`) does not list
      either key, so they are undiscoverable from the Help screen.
    - *Required Fix*: Add `Ctrl+Y` and `Ctrl+Z` to the Help screen within the
      canonical 22-line Tier 1 layout (80x24 fit), update Section 7.3, and
      apply the same change to `HELPNEXT.OVL` (Bug 2.2.17).
  - [x] **Bug 2.1.22: Splash Screen `Ctrl+O` / `Ctrl+S` Support [FIXED]**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 7.2, 10.
    - *Issue*: On the Splash Screen, Close (`[W]  or  [^W]`), Goto Line
      (`[L]  or  [^L]`), and Exit (`[Q]  or  [^Q]`) support and display
      both plain letter keys and their editor-mode `Ctrl` equivalents.
      However, for Open File and Save File, `SPLASH_LOOP` in
      `src/se.asm:540-545` does not handle `Ctrl+S` (`KEY_CTRL_S`) to
      enter the Save File screen, and `STR_SPLASH_CMDS` in
      `src/core/plugin_mgr.asm:4277-4278` only displays `[O]` and `[S]`
      without `or  [^O]` and `or  [^S]`.
    - *Required Fix*: In `src/se.asm` (`SPLASH_LOOP`), dispatch
      `KEY_CTRL_S` (`^S`) to `DO_SPLASH_SAVE` alongside `'s'`/`'S'`
      (matching `KEY_CTRL_O` -> `HANDLE_SPLASH_OPEN`). In
      `src/core/plugin_mgr.asm` (`STR_SPLASH_CMDS`), update the Open and
      Save menu lines to display `[O]  or  [^O]` and `[S]  or  [^S]`.

### 2.2 Profile 2: CP/M on ZX Spectrum Next (`SE_NEXT.COM`)
- **Target Platform**: NextCPM / CP/M 2.2 / CP/M Plus on ZX Spectrum Next.
- **Core Technology**: Z80 assembly (`src/se_next_cpm.asm`), Next-adapted
  console (80-column text mode), Next keyboard matrix mapping, NextCPM banked
  memory extensions.
- **Build Target**: `make se-next-cpm` (produces `SE_NEXT.COM`).
- **Status**: Active / 7 Open (Bugs 2.2.16–2.2.22 Open; 10 Bugs 2.2.2, 2.2.7,
  2.2.8, 2.2.9, 2.2.10, 2.2.11, 2.2.12, 2.2.13, 2.2.14, 2.2.15 Resolved;
  Bugs 2.2.1, 2.2.3, 2.2.4, 2.2.5, 2.2.6 Rejected).
- **Active Defects & Issue Tracking (UI_UX_DESIGN.md Conformance)**:
  - [x] **Bug 2.2.1: Status Bar Field Squatting & Layout [REJECTED]**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 4.3, 4.4, 13.2.
    - *Disposition*: **REJECTED / WONTFIX** per canonical specification.
    - *Rationale*: Identical to Bug 2.1.1 and Bug 2.3.2. Status bar Field 4 is
      canonically defined as a dynamic 15-character contextual slot (+ " | ")
      operating under a strict priority hierarchy (Free Memory, Block Selection
      metrics, Pan offset, Overwrite mode, or default Help Key Hint). Mode
      indicators belong strictly in Field 4; appending variable-length tags to
      Field 5 violates Field 5's fixed-width jitter-free coordinate budget and
      exceeds terminal column limits (Anti-Pattern #3). Furthermore, `CP/M  |`
      (with slash) is the canonical format string in Section 4.3 and 13.2.
  - [x] **Bug 2.2.2: Startup Screen Geometry Inversion (Defaults to 120x40)**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 2.1.
    - *Issue*: Next CP/M profile defaults to 120x40 instead of standard 80x24.
    - *Resolution*: Initialized to `80x24` mode in `START` (`se_next_cpm.asm`).
  - [x] **Bug 2.2.3: WordStar Navigation Disconnect [REJECTED / WONTFIX]**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 10.
    - *Disposition*: **REJECTED / WONTFIX** per architectural decision.
    - *Rationale*: Dropped support for WordStar diamond navigation in
      `SE_NEXT.COM` to preserve established SE.COM keymappings.
  - [x] **Bug 2.2.4: Tier 1 Help Screen Layout [REJECTED / WONTFIX]**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 5.2, 7.1, 7.3.
    - *Disposition*: **REJECTED / WONTFIX** per canonical specification.
    - *Rationale*: Identical to Bug 2.1.4. The 22-line Help screen template in
      `plugins/help.asm` is the authoritative reference design codified in
      Section 7.3. The 17-line layout was an obsolete conceptual mockup.
  - [x] **Bug 2.2.5: Splash Screen Centering & Menu [REJECTED / WONTFIX]**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 7.1, 7.2.
    - *Disposition*: **REJECTED / WONTFIX** per architectural decision.
    - *Rationale*: The demand to replace `SE_NEXT.COM`'s splash menu with an
      obsolete 14-line (`:e to edit`, `:o to open file`) layout was based on an
      early conceptual wireframe. `docs/UI_UX_DESIGN.md` Section 7.2 explicitly
      codifies canonical `SE.COM`'s 21-line centered menu (`type [E] or [Enter]
      to edit...`) as the authoritative splash screen template across ALL SE
      variants, and expressly prohibits colon commands and queries such as
      `Enter option: _`. Rejected for parity with Bug 2.1.5.
  - [x] **Bug 2.2.6: Tier 2 Modal Framing (52x8 Box) [REJECTED / WONTFIX]**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 8.1, 8.3 (Archetype C).
    - *Disposition*: **REJECTED / WONTFIX** per architectural decision.
    - *Rationale*: The claim that Archetype C input modals must use a 52-column
      width and 52x8 framing is factually incorrect and contrary to
      `docs/UI_UX_DESIGN.md` Section 8.3. The specification explicitly
      standardizes all Archetype C input modals (Goto Line, Find Text, Overwrite
      File) to 50 columns by 7 rows (`50 cols x 7 rows`). `src/core/editor.asm`
      already implements the canonical 50x7 dimensions, and the explicit
      action footer `[Enter]=Goto Line [ESC]=Cancel` is codified in Section 8.3
      (Bug 2.1.6 Rejected).
  - [x] **Bug 2.2.7: Dedicated Next Delete Key Normalized to Backspace**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 10.1.
    - *Issue*: In `src/hal/next_cpm/hal_nextcpm_keyboard.asm:56-60`,
      `HAL_KEYBOARD_TRANSLATE` intercepts `NEXT_KEY_DELETE` (`0x7F`) and
      replaces it with `KEY_BACKSPACE` (`0x08`). This turns the dedicated Next
      Delete key into a backward deletion key. It completely prevents forward
      deletion under cursor in the document editor and Archetype C modals, and
      erroneously causes Delete to cancel dynamic block selection rather than
      executing `DO_DELETE_BLOCK`.
    - *Required Fix*: In `src/hal/next_cpm/hal_nextcpm_keyboard.asm`, preserve
      `0x7F` (`KEY_DELETE`) so that the editor engine distinguishes forward
      deletion and block range deletion from destructive backward deletion.
    - *Resolution*: Preserved `0x7F` (`NEXT_KEY_DELETE` / `KEY_DEL`) in
      `HAL_KEYBOARD_TRANSLATE` (`src/hal/next_cpm/hal_nextcpm_keyboard.asm`)
      and hooked translation in `GET_KEY`
      (`src/hal/next_cpm/hal_nextcpm_console.asm`), distinguishing forward
      deletion and block deletion from Backspace.
      Validated via `tests/test_bug_2_2_7.py`.
  - [x] **Bug 2.2.8: Memory Screen Queries RomWBW HBIOS Under NextCPM**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 3, 11.2.
    - *Issue*: In `src/se_next_cpm.asm:3480`, `SHOW_MEM_INFO_SCREEN` invokes
      `QUERY_MEM_SCREEN_INFO`, which queries RomWBW HBIOS function vectors
      (`HBIOS_SYS_GET`). Under NextCPM, HBIOS is absent; the screen displays
      `HBIOS: None | OS: CP/M 2.2 | RAM: 64 KB Base` and renders an empty
      16-row HBIOS bank table (`80h..8Fh`), ignoring the 1024 KB / 2048 KB
      Next SRAM and 8KB MMU Far RAM allocations (NextRegs `0x50`–`0x57`).
    - *Required Fix*: Implement a NextCPM-specific memory map reporter in
      `src/se_next_cpm.asm` that queries Next hardware memory capacity via
      NextReg `0x01` / `0x14` and reports active Next MMU Far RAM bank slots
      rather than invoking HBIOS discovery.
    - *Resolution*: Replaced RomWBW HBIOS memory queries with native Next
      hardware queries via NextReg 0x01/0x14 and mapped 16 32KB Next MMU
      Far RAM banks in `src/se_next_cpm.asm`. Preserved RomWBW CP/M binary
      invariance. Validated via `tests/test_bug_2_2_8.py`.
  - [x] **Bug 2.2.9: Escape Sequence Trailing Byte Leakage in Editor**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 10.3.
    - *Issue*: In `src/core/editor.asm:217-383` (`HANDLE_CSI`, `HANDLE_CSI_1`,
      `HANDLE_CSI_2`, `HANDLE_CSI_LOOP`), when an unhandled or extended
      multi-byte escape sequence is received (e.g. function keys F5–F12,
      bracketed paste, or mouse tracking events), the handlers execute `RET`
      upon encountering unrecognized characters without consuming the remainder
      of the sequence. Trailing sequence bytes (such as terminating `'~'`)
      remain pending in the console input buffer and leak into document text.
    - *Required Fix*: In `src/core/editor.asm`, update `HANDLE_CSI` sub-handlers
      to atomically drain unrecognized multi-byte sequences until a terminating
      character (`'~'`, `'A'..'Z'`, `'a'..'z'`) or timeout occurs.
    - *Resolution*: Implemented `DRAIN_REMAINING_CSI` in `src/core/editor.asm`
      under `TARGET_NEXT` to drain trailing sequence bytes until terminal byte
      boundary (`0x40`..`0x7E`) or timeout, routing unhandled CSI branches to
      it. Optimized NextCPM BSS overlay to preserve +2,048 B TPA headroom and
      RomWBW CP/M binary invariance. Validated via `tests/test_bug_2_2_9.py`.
  - [x] **Bug 2.2.10: Predominant Language Indication on About Screen**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 7.12, 14.6.
    - *Issue*: In `src/core/plugin_mgr.asm:4384`, `STR_ABOUT_VERSION` displays
      `version 1.1.0 (2026-10-09)`, omitting the predominant programming
      language. Per Section 7.12 and 14.6, `SE_NEXT.COM` must display
      `version 1.1.0 (2026-10-09) (Z80 Assembly)` on the About screen.
    - *Required Fix*: Update `STR_ABOUT_VERSION` in `src/core/plugin_mgr.asm`
      to append ` (Z80 Assembly)`, ensuring clean centering in
      `SHOW_ABOUT_SCREEN` across all 80x24 screens.
    - *Resolution*: Appended ` (Z80 Assembly)` to `STR_ABOUT_VERSION` under
      `TARGET_NEXT` in `src/core/plugin_mgr.asm`, displaying
      `version 1.1.0 (2026-10-09) (Z80 Assembly)` dynamically centered on
      the About screen while preserving RomWBW CP/M binary invariance.
      Validated via `tests/test_bug_2_2_10.py`.
  - [x] **Bug 2.2.11: Forward Deletion Line Join Sticky Target Column Update**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 6.8.
    - *Issue*: In `src/core/editor.asm:1874-1883` (`DO_DEL_FWD_JOIN_NEXT`),
      when the current line and next line are joined on Delete at EOL,
      `JOIN_TWO_LINES` merges the lines, but `DO_DEL_FWD_JOIN_NEXT` fails to
      update `TARGET_COL = CALC_VISUAL_COL(CUR_COL)`.
    - *Required Fix*: In `DO_DEL_JOIN_OK`, call `CALC_VISUAL_COL` and update
      `(TARGET_COL),HL`.
    - *Resolution*: Updated `DO_DEL_JOIN_OK` in `src/core/editor.asm` under
      `TARGET_NEXT` to invoke `CHECKOUT_ACTIVE_LINE` and `CALC_VISUAL_COL`
      and update `(TARGET_COL),HL`, ensuring subsequent vertical navigation
      adheres to the join column while preserving RomWBW CP/M binary
      invariance. Validated via `tests/test_bug_2_2_11.py`.
  - [x] **Bug 2.2.12: Modal Dialog Cancellation by Unexpected Keystrokes**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 8.2, 8.3, 11.
    - *Issue*: In `src/core/editor.asm:1420-1440` (`DO_GOTO_LINE_UI`),
      `src/core/search.asm:214-233` (`DO_FIND_UI`), and
      `src/core/search.asm:1940-1960` (`DO_REPLACE_UI`), receiving unexpected
      escape sequences (e.g. arrow keys, PgUp/PgDn) routes into `GOT_ESC_SEQ`,
      executing background document cursor movements and abruptly aborting the
      active dialog. Modals must only dismiss on `Enter` or `ESC`.
    - *Required Fix*: In modal input loops, drain and discard unexpected escape
      sequences and non-input keys, preserving active dialog state.
    - *Resolution*: Implemented `DRAIN_ESCAPE_SEQUENCE` in `src/core/editor.asm`
      under `TARGET_NEXT` to drain and discard multi-byte escape sequences
      (CSI, SS3) without moving document cursor or closing active dialogs.
      Routed `GOTO_GOT_ESC_SEQ`, `FIND_GOT_ESC_SEQ`, and `REP_GOT_ESC_SEQ` to
      it, gated `Ctrl+U`/`Ctrl+V` in Goto Line, and preserved input state.
      Validated via `tests/test_bug_2_2_12.py`.
  - [x] **Bug 2.2.13: Splash Screen Geometry Hotkeys & Unsupported 120x40**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 2.1, 7.2.
    - *Issue*: In `src/se_next_cpm.asm:582-589` and `src/core/plugin_mgr.asm`,
      hotkey `1` selects 120x40 and `2` selects 80x24 (inverted per Section
      2.1). Furthermore, ZX Spectrum Next hardware text mode is fixed 80
      columns; 120x40 wide console mode is unsupported on Next hardware.
      Triggering `1` causes horizontal column spill and corrupted wrapping.
    - *Required Fix*: In `src/se_next_cpm.asm`, assign `1` to 80x24 classic
      terminal mode and omit or disable 120x40 mode per Section 2.1 mandate.
    - *Resolution*: Mapped hotkey '1' to 80x24 classic terminal mode, disabled
      hotkey '2', and enforced 80x24 on 120x40 requests in
      `src/se_next_cpm.asm`.
      Updated `STR_SPLASH_CMDS` in `src/core/plugin_mgr.asm` under
      `TARGET_NEXT` to display `type [1] set 80x24`.
      Validated via `tests/test_bug_2_2_13.py`.
  - [x] **Bug 2.2.14: `Ctrl+K` (`Extend + K`) Performs Cursor Up Instead of
    Opening Help Key Overlay (`HELP.OVL`) [FIXED]**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 7.3, 10, 10.4.
    - *Issue*: In `SE_NEXT.COM` editor mode, pressing `Ctrl+K` (`EXTEND + K`
      on the ZX Spectrum Next keyboard, ASCII `0x0B` / `KEY_CTRL_K`) performs
      a Cursor Up operation instead of opening the Help Key overlay file
      (`HELP.OVL` / Block Menu when a block is active).
    - *Root Cause*: In `src/hal/next_cpm/hal_nextcpm_keyboard.asm:93-94`,
      `HAL_KEYBOARD_TRANSLATE` checks `CP 00BH` (Sinclair VT Up Arrow control
      code) and unconditionally jumps to `HKT_SET_UP` (emitting `\x1b[A`
      Cursor Up) without polling the ULA hardware keyboard matrix (Row 6,
      port `0xBFFE`, bit 2 for key `'K'` or Row 4, port `0xEFFE`, bit 3 for
      key `'7'`) to disambiguate `EXTEND + K` (`Ctrl+K` = `0x0B`) from the
      Up Arrow key.
    - *Required Fix*: In `src/hal/next_cpm/hal_nextcpm_keyboard.asm`,
      disambiguate `0x0B` via the ULA keyboard matrix (checking whether key
      `'K'` on Row 6 port `0xBFFE` bit 2 is pressed, or whether key `'7'` on
      Row 4 port `0xEFFE` bit 3 is pressed) so that `EXTEND + K` (`Ctrl+K`)
      returns `0x0B` (`KEY_CTRL_K`) to open `HELP.OVL` (or the Block Menu),
      while the physical Up Arrow key continues to emit `\x1b[A`.
    - *Resolution*: Added `HKT_CHECK_CTRL_K` in
      `src/hal/next_cpm/hal_nextcpm_keyboard.asm` to poll ULA matrix Row 6
      (`port 0xBFFE`, bit 2 = `'K'`) and Row 4 (`port 0xEFFE`, bit 3 = `'7'`),
      returning `0x0B` (`KEY_CTRL_K`) for `Extend + K` / `Ctrl+K` and queuing
      `\x1b[A` only when physical `'7'` (Up Arrow) is held. Validated via
      `tests/test_nextcpm_entry.py`.
  - [x] **Bug 2.2.15: Visible Cursor on Splash, Memory, Configure, and Modal
    Pop-up Screens [FIXED]**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 7.2, 7.4, 7.11, 8.
    - *Issue*: In `SE_NEXT.COM`, on the Splash screen (`RENDER_SPLASH`), the
      cursor is shown highlighted at the top-left screen position (`1, 1`).
      The cursor should not be visible on the Splash screen, Memory Info
      screen (`SHOW_MEM_INFO_SCREEN`), or Configure screen
      (`SHOW_CONFIG_SCREEN`). Additionally, when `M` (or a plugin action
      requiring the Plugin Manager) triggers the missing Plugin Manager
      pop-up (`SHOW_POPUP_NEED_PLUGIN_MGR`), the cursor remains visible at the
      bottom-right corner of the pop-up box where the border finishes drawing,
      whereas the cursor should be hidden.
    - *Root Cause*: `TERM_HIDE_CURSOR` in
      `src/hal/next_cpm/hal_nextcpm_console.asm` emits `STR_HIDE_CURSOR`
      (`\x1b[?25l`, DEC private mode cursor hide). Per the NextZXOS CP/M
      terminal documentation (shipped on the NextZXOS SD card image), the
      NextCPM console emulates a Zenith Z-19 plus the Locomotive Spectrum +3
      extensions and a subset of ANSI; `ESC [ ? 25 l/h` is not supported.
      Cursor visibility is controlled by `ESC f` (disable cursor blob) and
      `ESC e` (enable cursor blob). Consequently, `CALL TERM_HOME` followed
      by `CALL TERM_HIDE_CURSOR` at the end of `RENDER_SPLASH`,
      `SHOW_MEM_INFO_SCREEN`, `SHOW_CONFIG_SCREEN`, and `SHOW_ABOUT_SCREEN`
      leaves the cursor visible at `(1, 1)`, and `CALL TERM_HIDE_CURSOR`
      before drawing Tier 2 modal pop-ups leaves the cursor visible at the
      bottom-right corner of the pop-up border.
    - *Resolution*: `TERM_HIDE_CURSOR` / `TERM_SHOW_CURSOR` in
      `src/hal/next_cpm/hal_nextcpm_console.asm` now emit NextCPM-local
      strings `STR_NEXTCPM_HIDE_CURSOR` (`ESC f`) and
      `STR_NEXTCPM_SHOW_CURSOR` (`ESC e`). Shared `STR_HIDE_CURSOR` /
      `STR_SHOW_CURSOR` are untouched, so `SE.COM` stays byte-identical and
      `SE.NEX` / `.se` keep their native ANSI parser path. Validated via
      `tests/test_bug_2_2_15.py`.
    - *Follow-up*: Hardcoded `\x1b[?25l` in `HELP.OVL` and `PLUGIN.PRL` is
      tracked separately as Bug 2.2.16.
  - [ ] **Bug 2.2.16: Cursor Visible While `HELP.OVL` / `PLUGIN.PRL`
    Overlays Are Displayed**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 7.3, 8; Bug 2.2.15.
    - *Issue*: In `SE_NEXT.COM`, the terminal cursor may remain visible
      while the Help screen (`HELP.OVL`, opened via `Ctrl+K` / `EXTEND + K`)
      or Plugin Manager / plugin screens (`PLUGIN.PRL`) are displayed,
      whereas the cursor should be hidden on these non-input screens.
    - *Root Cause*: `plugins/help.asm` (lines 145, 197) and
      `plugins/plugin.asm` (lines 596, 1016, 1074, 1092, 1098, 1236, 1802,
      1863, 1935) emit their own local `STR_HIDE_CURSOR` /
      `STR_SHOW_CURSOR` strings (`\x1b[?25l` / `\x1b[?25h`) through the
      host `PRINT_STR` vector rather than calling the host HAL
      `TERM_HIDE_CURSOR` / `TERM_SHOW_CURSOR` routines. The NextCPM console
      (Zenith Z-19 + Spectrum +3 extensions) does not support
      `ESC [ ? 25 l/h`; it requires `ESC f` / `ESC e` (see Bug 2.2.15).
      The plugin host API (`PLUGIN_HOST_API` in
      `src/core/plugin_tramp.asm`) currently exposes no hide/show cursor
      entry points, so overlays cannot request the target-correct sequence.
    - *Required Fix*: Append `TERM_HIDE_CURSOR` and `TERM_SHOW_CURSOR`
      trampolines to `PLUGIN_HOST_API` (new vectors after `+73`, bumping the
      host API version), and update `plugins/help.asm` and
      `plugins/plugin.asm` to call those vectors instead of printing
      hardcoded DEC sequences. Overlays must fall back to the existing
      `\x1b[?25l/h` strings when loaded by an older host (version check),
      and `SE.COM` must continue to emit `\x1b[?25l/h` on RomWBW.
  - [ ] **Bug 2.2.17: Help Screen Shows PC/Terminal Keys Instead of ZX
    Spectrum Next Keys (Create `HELPNEXT.OVL`)**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 7.3, 10.4;
      `docs/KEYBINDINGS.md` Section 7.
    - *Issue*: `SE_NEXT.COM` loads the shared `HELP.OVL`
      (`plugins/help.asm`), which has no Next-specific content and
      describes PC / serial-terminal keys. On the Next keyboard this is
      confusing:
      - `Ctrl+<key>` is used throughout, but `EXTEND` (or `Caps Shift +
        Symbol Shift`) acting as `Ctrl` is never explained.
      - `PgUp`, `PgDn`, `Home`, `End`, `^Home`, `^End`, `Insert`, `Tab`,
        `Backspace`, `Delete` and `ESC` are listed, but the Next has no
        such keys.
      - Keys that `SE_NEXT.COM` deliberately redefines away from the
        standard Next CP/M mappings are not shown: `TRUE VIDEO` = `Tab`
        (standard: `Ctrl+S`), `INV VIDEO` = Page Up (standard: `Ctrl+I`
        / Tab), `GRAPH` = Page Down (standard: `Ctrl+G`).
      - The Next `DELETE` key (`Caps Shift + 0`) and `EXTEND + D` (forward
        delete) are not shown.
      - `Ctrl+Y` (Beautify) and `Ctrl+Z` (Plugin Manager) are missing
        (see also Bug 2.1.21).
    - *Required Fix*: Create a Next-specific overlay `HELPNEXT.OVL`
      (e.g. `plugins/helpnext.asm`, or `plugins/help.asm` assembled with a
      Next define) rather than adding Next text to the shared `HELP.OVL`,
      to avoid confusing either audience:
      - Use Next key names (`EXTEND + K`, `INV VIDEO`, `GRAPH`,
        `TRUE VIDEO`, `DELETE`, `EDIT`, `BREAK`, arrow keys) and include a
        one-line note that `EXTEND` = `Ctrl`.
      - Clearly mark keys whose `SE_NEXT.COM` behaviour differs from the
        standard Next CP/M mapping.
      - Fit the canonical 22-line Tier 1 layout on the 80x24 Next display.
      - Under `SE_NEXT.COM`, load `HELPNEXT OVL` instead of `HELP    OVL`
        (`src/core/ui_browser.asm:166`) and update the "help missing"
        pop-up text accordingly; `SE.COM` must remain byte-identical.
      - Add a build target and deploy `HELPNEXT.OVL` with `SE_NEXT.COM`
        (see Bug 2.2.20).
  - [ ] **Bug 2.2.18: Insert/Overwrite Mode Cannot Be Toggled From the Next
    Keyboard**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 4.3, 10, 10.4.
    - *Issue*: Insert/Overwrite is toggled only by terminal Insert-key
      sequences (`ESC [ 2 ~`, `ESC [ L`, `ESC [ @`, handled by
      `TOGGLE_INSERT_MODE` in `src/core/editor.asm`). No key on the ZX
      Spectrum Next keyboard produces any of these sequences under NextCPM,
      so Overwrite mode is unreachable in `SE_NEXT.COM`.
    - *Required Fix*: Assign a Next key in
      `src/hal/next_cpm/hal_nextcpm_keyboard.asm` that toggles
      Insert/Overwrite (e.g. remap the `EDIT` key, `Caps Shift + 1`, via
      ULA matrix disambiguation, queuing `ESC [ 2 ~`), keeping existing
      `EXTEND` mappings intact. Document the key in `HELPNEXT.OVL`
      (Bug 2.2.17), `docs/UI_UX_DESIGN.md` Section 10.4 and
      `docs/KEYBINDINGS.md` Section 7.
  - [ ] **Bug 2.2.19: Next Key Mapping Documentation Disagrees With Standard
    Next CP/M Mappings (`EDIT` / `BREAK`)**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 10.4;
      `docs/KEYBINDINGS.md` Section 7; NextZXOS CP/M terminal docs.
    - *Issue*: The NextZXOS CP/M terminal documentation (on the NextZXOS SD
      image, `disks/tbblue.mmc`) defines the standard Next CP/M key codes:
      `BREAK` = `ESC`, `EDIT` = `Ctrl+W`, `TRUE VIDEO` = `Ctrl+S`,
      `INV VIDEO` = `Ctrl+I` (Tab), `GRAPH` = `Ctrl+G`, `DELETE` =
      `Ctrl+H`, `Ctrl+DELETE` = `DEL` (0x7F), cursor keys = `Ctrl+A/F/E/X`.
      `SE_NEXT.COM` intentionally redefines `TRUE VIDEO`, `INV VIDEO`,
      `GRAPH` and the cursor keys via ULA matrix disambiguation in
      `HAL_KEYBOARD_TRANSLATE`, but does not remap `EDIT` or `BREAK`.
      However, `docs/KEYBINDINGS.md` Section 7 and `docs/UI_UX_DESIGN.md`
      Section 10.4 state `EDIT` = `ESC` and `BREAK` = `Ctrl+C`. If the
      standard mapping applies, pressing `EDIT` in the editor sends
      `Ctrl+W` (Close file to splash) and `BREAK` is the only `ESC` key.
    - *Required Fix*: Verify `EDIT` / `BREAK` behaviour on real Next
      hardware. Then either remap them in `HAL_KEYBOARD_TRANSLATE` (note
      Bug 2.2.18 may claim `EDIT`) or correct the documentation. Update the
      Section 10.4 / Section 7 tables to show three columns: standard SE
      key, standard Next CP/M key code, and `SE_NEXT.COM` behaviour, so
      every key that `SE_NEXT.COM` redefines is explicit.
  - [ ] **Bug 2.2.20: `HELP` Overlay and `PLUGIN.PRL` Not Deployed to the
    Next Disk Image**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 7.3; `Makefile`
      `next-image` target.
    - *Issue*: `make next-image` runs `tools/populate_next_disk.py`, which
      injects only `dot_se.bin`, `SE.NEX` and `SE_NEXT.COM` into
      `tbblue.mmc`. Unlike the RomWBW `image` target, the help overlay and
      `PLUGIN.PRL` are not copied, so `Ctrl+K` (`EXTEND + K`) in
      `SE_NEXT.COM` may display the "help missing" pop-up and plugin
      features are unavailable on the Next image.
    - *Required Fix*: Extend `tools/populate_next_disk.py` (and the
      `next-image` dependencies) to build and inject `HELPNEXT.OVL`
      (Bug 2.2.17) and `PLUGIN.PRL` alongside `SE_NEXT.COM`, and add a
      check to `tests/test_next_targets.py`.
  - [ ] **Bug 2.2.21: Splash Screen `Ctrl+S` (`^S`) Not Dispatched in
    `SPLASH_LOOP`**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 7.2, 10, 15.1; Bug 2.1.22.
    - *Issue*: `STR_SPLASH_CMDS` in `src/core/plugin_mgr.asm:4270` displays
      `type   [S]  or  [^S]    to save file` on the Splash Screen, and
      Section 7.2 / 15.1 mandate that `S`, `s`, or `Ctrl+S` (`KEY_CTRL_S`)
      invokes `DO_SPLASH_SAVE`. However, `SPLASH_LOOP` in
      `src/se_next_cpm.asm:545-550` only checks `'s'` and `'S'` and lacks
      `CP KEY_CTRL_S` / `JP Z,DO_SPLASH_SAVE`, so pressing `Ctrl+S`
      (`EXTEND + S`) on the Splash Screen is silently ignored.
    - *Required Fix*: In `src/se_next_cpm.asm:545-550` (`SPLASH_LOOP`), add
      `CP KEY_CTRL_S` and `JP Z,DO_SPLASH_SAVE` alongside `'s'` and `'S'`
      (matching `src/se.asm:545-546`).
  - [ ] **Bug 2.2.22: Splash Screen Blank Gap Row Replacing Omitted
    `[2] set 120x40`**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 7.2, 14.1, 15.1.5.
    - *Issue*: Under `IFDEF TARGET_NEXT` in `src/core/plugin_mgr.asm:4278-4281`,
      `STR_SPLASH_CMDS` omits `type   [2]              set 120x40` by replacing
      it with `DB 13,10`. During `RENDER_SPLASH` (`src/se_next_cpm.asm:2631`),
      `PRINT_SPLASH_PREFIX` outputs `~` plus 19 spaces before `DB 13,10`,
      creating an empty gap row inside the command list between
      `type   [1]              set 80x24` and
      `type   [Q]  or  [^Q]    to exit`. Per Section 7.2 and Section 15.1.5,
      Option `[2]` must be omitted cleanly without leaving an empty row gap
      inside the command block.
    - *Required Fix*: Remove the `DB 13,10` placeholder under
      `IFDEF TARGET_NEXT` in `src/core/plugin_mgr.asm:4280` and define
      `SPLASH_MENU_LINES EQU 20` under `IFDEF TARGET_NEXT` in
      `src/include/ui.inc` so the 20-line Splash Screen block centers cleanly
      on 80x24 without a gap row between `[1]` and `[Q]`.

### 2.3 Profile 3: Native ZX Spectrum Next (`SE.NEX` & `.se` Dot Command)
- **Target Platform**: NextZXOS / ESXDOS standalone browser executable and
  `/dot` command on SD card.
- **Core Technology**: Z80 assembly (`src/se_next.asm`), native Next hardware
  tile/text layer (80x25 / 80x32), NextRegs MMU 8KB SRAM banking (1MB/2MB),
  NextZXOS filesystem API (`RST 08h`).
- **Build Target**: `make se-next-native` (produces `SE.NEX` and `.se`).
- **Status**: Active / 2 Open (Bugs 2.3.13, 2.3.14 Open; Bugs 2.3.1, 2.3.3,
  2.3.4, 2.3.5, 2.3.9, 2.3.10, 2.3.11, 2.3.12 Resolved; Bugs 2.3.2, 2.3.6,
  2.3.7, 2.3.8 Rejected).
- **Active Defects & Issue Tracking (UI_UX_DESIGN.md Conformance)**:
  - [x] **Bug 2.3.1: Dedicated Arrow Keys Mapped to WordStar Diamond Commands**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 1, 10.
    - *Issue*: In `src/hal/next_native/hal_next_keyboard.asm:22-26, 309-313`,
      the Sinclair matrix keyboard decoder maps dedicated cursor keys to legacy
      WordStar diamond control codes:
      - Left Arrow (Caps+5) emits `0x13` (`KEY_WORDSTAR_LEFT` = `Ctrl+S`),
        triggering Save File in the editor!
      - Right Arrow (Caps+8) emits `0x04` (`KEY_WORDSTAR_RIGHT` = `Ctrl+D`),
        triggering character deletion!
      - Up Arrow (Caps+7) emits `0x05` (`KEY_WORDSTAR_UP` = `Ctrl+E`),
        jumping to End of line!
      - Down Arrow (Caps+6) emits `0x18` (`KEY_WORDSTAR_DOWN` = `Ctrl+X`),
        triggering Move Block!
      - Delete (Caps+0) emits `0x07` (`KEY_WORDSTAR_DEL` = `Ctrl+G`),
        jumping to EOF (bottom of document)!
      This directly violates the canonical navigation key mandate in Section 1
      and Section 10, creating catastrophic command collisions.
    - *Required Fix*: Update `KEY_TABLE_CAPS` in `hal_next_keyboard.asm` to emit
      standard ANSI VT100 arrow escape sequences (`\x1b[A`, `\x1b[B`, `\x1b[C`,
      `\x1b[D`) or direct editor movement codes (`KEY_UP`, `KEY_DOWN`,
      `KEY_LEFT`, `KEY_RIGHT`), and map Delete (Caps+0) to `0x7F`
      (`KEY_DELETE`).
    - *Resolution*: Replaced legacy WordStar equates with ANSI VT100 escape
      sequence generator for dedicated arrow keys (`\x1b[A`, `\x1b[B`,
      `\x1b[C`, `\x1b[D`) and mapped Delete (Caps+0) to `0x7F` in
      `src/hal/next_native/hal_next_keyboard.asm`. Preserved RomWBW CP/M
      binary invariance. Validated via `tests/test_bug_2_3_1.py`.
  - [x] **Bug 2.3.2: Status Bar Field Squatting & Layout [REJECTED / WONTFIX]**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 4.3, 6.6, 9.2.
    - *Disposition*: **REJECTED / WONTFIX** per canonical specification.
    - *Rationale*: Identical to Bug 2.1.1. Status bar Field 4 is canonically
      defined as a dynamic 15-character contextual slot (+ " | " separator)
      operating under a strict priority hierarchy (Free Memory, Block Selection
      metrics, Pan offset, Overwrite mode, or default Help Key Hint). Mode
      indicators belong in Field 4, while Field 5 is strictly reserved for
      fixed-width cursor coordinates (`Line <cur>/<tot> Col <col> |`).
  - [x] **Bug 2.3.3: Extended Memory Map Screen Queries RomWBW HBIOS**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 3, 11.2.
    - *Issue*: In `src/se_next.asm:3523` (`SHOW_MEM_INFO_SCREEN`), the native
      Next application invokes `QUERY_MEM_SCREEN_INFO`, which executes RomWBW
      HBIOS queries (`HBIOS_SYS_GET`). Under native NextZXOS / ESXDOS, HBIOS is
      non-existent. The screen displays `HBIOS: None | OS: CP/M 2.2 | RAM: 64 KB
      Base` and prints an empty 16-row HBIOS bank table (`80h..8Fh`), ignoring
      the 1024 KB / 2048 KB Next SRAM and 8KB MMU Far RAM allocations.
    - *Required Fix*: Implement a native Next memory map renderer in
      `src/se_next.asm` that queries Next hardware registers (NextReg `0x01`
      Machine ID, `0x14` Global RAM paging) and visualizes the 8KB MMU page
      allocations (pages 32..43) instead of invoking HBIOS discovery.
    - *Resolution*: Replaced RomWBW HBIOS memory queries with native Next
      hardware queries via NextReg 0x01/0x14 and mapped 16 32KB Next MMU
      Far RAM banks in `src/se_next.asm`. Preserved RomWBW CP/M binary
      invariance. Validated via `tests/test_bug_2_3_3.py`.
  - [x] **Bug 2.3.4: Splash Screen Geometry Hotkeys & Unsupported 120x40**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 2.1, 7.2.
    - *Issue*: In `src/se_next.asm:625-631` and `src/core/plugin_mgr.asm`,
      hotkey `1` selects 120x40 and `2` selects 80x24. ZX Spectrum Next
      hardware text mode is fixed 80 columns; 120x40 is unsupported. Selecting
      `1` causes visual corruption and terminal column spill across the screen.
    - *Required Fix*: In `src/se_next.asm`, assign `1` to 80x24 classic
      terminal mode and omit or disable 120x40 mode per Section 2.1 mandate.
    - *Resolution*: Mapped hotkey '1' to 80x24 classic terminal mode, disabled
      hotkey '2', and enforced 80x24 on 120x40 requests in `src/se_next.asm`.
      Preserved RomWBW CP/M binary invariance. Validated via
      `tests/test_bug_2_3_4.py`.
  - [x] **Bug 2.3.5: Predominant Language Indication on About Screen**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 7.12, 14.6.
    - *Issue*: In `src/core/plugin_mgr.asm:4384`, `STR_ABOUT_VERSION` displays
      `version 1.1.0 (2026-10-09)`, omitting the predominant programming
      language. Per Section 7.12 and 14.6, `SE.NEX` and `.se` must display
      `version 1.1.0 (2026-10-09) (Z80 Assembly)` on the About screen.
    - *Required Fix*: Update `STR_ABOUT_VERSION` in `src/core/plugin_mgr.asm`
      to append ` (Z80 Assembly)`, ensuring clean centering in
      `SHOW_ABOUT_SCREEN` across all 80x24 screens.
    - *Resolution*: Displayed `version 1.1.0 (2026-10-09) (Z80 Assembly)` on
      native Next `SE.NEX` and `.se` via `TARGET_NEXT` in
      `src/core/plugin_mgr.asm`, centered dynamically on the About screen
      while preserving RomWBW CP/M binary invariance. Validated via
      `tests/test_bug_2_3_5.py`.
  - [x] **Bug 2.3.6: Tier 1 Help Screen Rules [REJECTED / WONTFIX]**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 5.2, 7.1, 7.3.
    - *Disposition*: **REJECTED / WONTFIX** per canonical specification.
    - *Rationale*: Identical to Bug 2.1.4. `plugins/help.asm` (`HELP.OVL`) is
      the canonical 22-line Help screen template codified in Section 7.3.
  - [x] **Bug 2.3.7: Splash Screen Centering & Menu [REJECTED / WONTFIX]**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 7.1, 7.2.
    - *Disposition*: **REJECTED / WONTFIX** per architectural decision.
    - *Rationale*: The demand to replace `SE.NEX`'s 21-line splash menu with an
      obsolete 14-line (`:e to edit`, `:o to open file`) layout was based on an
      early conceptual wireframe. `docs/UI_UX_DESIGN.md` Section 7.2 explicitly
      codifies canonical `SE.COM`'s 21-line centered menu (`type [E] or [Enter]
      to edit...`) as the authoritative splash screen template across ALL SE
      variants, and expressly prohibits colon commands and queries such as
      `Enter option: _`. Rejected for parity with Bug 2.1.5 and Bug 2.2.5.
  - [x] **Bug 2.3.8: Tier 2 Modal Framing (52 Cols) [REJECTED / WONTFIX]**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 8.1, 8.3 (Archetype C).
    - *Disposition*: **REJECTED / WONTFIX** per architectural decision.
    - *Rationale*: The claim that 50-column modal dialogs are non-canonical and
      should be 52 columns is factually incorrect and contrary to
      `docs/UI_UX_DESIGN.md` Section 8.3. The specification explicitly
      standardizes all Archetype C input modals to 50 columns by 7 rows
      (`50 cols x 7 rows`). `src/core/editor.asm` already implements the
      canonical 50x7 dimensions, and the explicit action footer
      `[Enter]=Goto Line [ESC]=Cancel` is codified in Section 8.3
      (Bug 2.1.6 Rejected).
  - [x] **Bug 2.3.9: Escape Sequence Trailing Byte Leakage in Native Next**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 10.3.
    - *Issue*: In `src/core/editor.asm:217-383` (`HANDLE_CSI` sub-handlers),
      when an unhandled or extended multi-byte escape sequence is received
      (e.g. function keys F5–F12, bracketed paste, or mouse tracking events),
      the handlers execute `RET` upon encountering unrecognized characters
      without consuming the remainder of the sequence. Trailing sequence bytes
      leak into the document buffer.
    - *Required Fix*: In `src/core/editor.asm`, update `HANDLE_CSI` sub-handlers
      to atomically drain unrecognized multi-byte sequences until a terminating
      character (`'~'`, `'A'..'Z'`, `'a'..'z'`) or timeout occurs.
    - *Resolution*: Routed unhandled CSI branches (`CSI_DONE`, `HANDLE_CSI_*`)
      to `DRAIN_REMAINING_CSI` in `src/core/editor.asm` under `TARGET_NEXT` to
      atomically consume trailing sequence bytes until terminal boundary
      (`0x40`..`0x7E`) or timeout, preventing stray bytes from leaking into
      document text on native Next `SE.NEX` and `.se`. Preserved RomWBW CP/M
      binary invariance. Validated via `tests/test_bug_2_3_9.py`.
  - [x] **Bug 2.3.10: Forward Deletion Line Join Sticky Target Column Update**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 6.8.
    - *Issue*: In `src/core/editor.asm:1874-1883` (`DO_DEL_FWD_JOIN_NEXT`),
      when the current line and next line are joined on Delete at EOL,
      `JOIN_TWO_LINES` merges the lines, but `DO_DEL_FWD_JOIN_NEXT` fails to
      update `TARGET_COL = CALC_VISUAL_COL(CUR_COL)`.
    - *Required Fix*: In `DO_DEL_JOIN_OK`, call `CALC_VISUAL_COL` and update
      `(TARGET_COL),HL`.
    - *Resolution*: Updated `DO_DEL_JOIN_OK` in `src/core/editor.asm` under
      `TARGET_NEXT` to invoke `CHECKOUT_ACTIVE_LINE` and `CALC_VISUAL_COL`
      and update `(TARGET_COL),HL`, ensuring subsequent vertical navigation
      adheres to the join column across native Next targets `SE.NEX` and `.se`
      while preserving RomWBW CP/M binary invariance. Validated via
      `tests/test_bug_2_3_10.py`.
  - [x] **Bug 2.3.11: Modal Dialog Cancellation by Unexpected Keystrokes**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 8.2, 8.3, 11.
    - *Issue*: In `src/core/editor.asm:1420-1440` (`DO_GOTO_LINE_UI`),
      `src/core/search.asm:214-233` (`DO_FIND_UI`), and
      `src/core/search.asm:1940-1960` (`DO_REPLACE_UI`), receiving unexpected
      escape sequences (e.g. arrow keys, PgUp/PgDn) routes into `GOT_ESC_SEQ`,
      executing background document cursor movements and abruptly aborting the
      active dialog. Modals must only dismiss on `Enter` or `ESC`.
    - *Required Fix*: In modal input loops, drain and discard unexpected escape
      sequences and non-input keys, preserving active dialog state.
    - *Resolution*: Implemented `DRAIN_ESCAPE_SEQUENCE` under `TARGET_NEXT` in
      `src/core/editor.asm` to absorb multi-byte escape sequences without
      moving document cursor or dismissing active modals. Routed
      `GOTO_GOT_ESC_SEQ`, `FIND_GOT_ESC_SEQ`, and `REP_GOT_ESC_SEQ` to it in
      native Next targets `SE.NEX` and `.se`. Preserved RomWBW CP/M binary
      invariance. Validated via `tests/test_bug_2_3_11.py`.
  - [x] **Bug 2.3.12: File Browser Displays CP/M User Areas Under NextZXOS**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 7.5, 7.6, 7.7.
    - *Issue*: In `src/core/ui_browser.asm`, the directory browser prompt line
      displays `[ESC]=Cancel  [d:][u:][pattern] to list (e.g. B:, C1:, *.TXT)`.
      Under native NextZXOS / ESXDOS FAT storage, user areas (`u:`) are
      non-existent; files are organized in hierarchical directories and paths
      (e.g. `/`, `/dot`). Prompting the user for `[u:]` under NextZXOS causes
      user confusion and visual non-conformance.
    - *Required Fix*: In `src/core/ui_browser.asm`, adapt the directory browser
      prompt line under `TARGET_NEXT_NATIVE` to display native path syntax
      rather than CP/M drive/user area notation.
    - *Resolution*: Updated `STR_ESC_CANCEL_TXT` and `STR_ESC_CANCEL` in
      `src/core/plugin_mgr.asm` under `TARGET_NEXT_NATIVE` to display native
      path syntax `[ESC]=Cancel  Enter [path][pattern] to list (e.g. /dot/,
      *.TXT)` on `SE.NEX` and `.se`, while preserving CP/M user area notation
      on `SE_NEXT.COM` and byte-for-byte binary invariance on `SE.COM`.
      Validated via `tests/test_bug_2_3_12.py`.
  - [ ] **Bug 2.3.13: Splash Screen `Ctrl+S` (`^S`) Not Dispatched in
    `SPLASH_LOOP`**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 7.2, 10, 15.1; Bug 2.1.22.
    - *Issue*: `STR_SPLASH_CMDS` in `src/core/plugin_mgr.asm:4270` displays
      `type   [S]  or  [^S]    to save file` on the Splash Screen, and
      Section 7.2 / 15.1 mandate that `S`, `s`, or `Ctrl+S` (`KEY_CTRL_S`)
      invokes `DO_SPLASH_SAVE`. However, `SPLASH_LOOP` in
      `src/se_next.asm:588-593` only checks `'s'` and `'S'` and lacks
      `CP KEY_CTRL_S` / `JP Z,DO_SPLASH_SAVE`, so pressing `Ctrl+S`
      (`EXTEND + S`) on the Splash Screen in `SE.NEX` and `.se` is silently
      ignored.
    - *Required Fix*: In `src/se_next.asm:588-593` (`SPLASH_LOOP`), add
      `CP KEY_CTRL_S` and `JP Z,DO_SPLASH_SAVE` alongside `'s'` and `'S'`
      (matching `src/se.asm:545-546`).
  - [ ] **Bug 2.3.14: Splash Screen Blank Gap Row Replacing Omitted
    `[2] set 120x40`**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 7.2, 14.1, 15.1.5.
    - *Issue*: Under `IFDEF TARGET_NEXT` in `src/core/plugin_mgr.asm:4278-4281`,
      `STR_SPLASH_CMDS` replaces the omitted `[2] set 120x40` line with
      `DB 13,10`. In `RENDER_SPLASH` (`src/se_next.asm:2663`),
      `PRINT_SPLASH_PREFIX` outputs `~` plus 19 spaces before `DB 13,10`,
      creating a blank gap row inside the command list between
      `type   [1]              set 80x24` and
      `type   [Q]  or  [^Q]    to exit`.
    - *Required Fix*: Remove the `DB 13,10` placeholder under
      `IFDEF TARGET_NEXT` in `src/core/plugin_mgr.asm:4280` and define
      `SPLASH_MENU_LINES EQU 20` under `IFDEF TARGET_NEXT` in
      `src/include/ui.inc` so the 20-line Splash Screen block centers cleanly
      on 80x24 without a gap row between `[1]` and `[Q]`.

### 2.4 Profile 4: Linux Native C Profile (`se-linux`)
- **Target Platform**: Linux PC / Workstation (`x86_64`) and Raspberry Pi 4/5
  (`aarch64`).
- **Core Technology**: Portable C core modules (`src/core/*.c`), POSIX
  Hardware Abstraction Layer (`src/hal/linux/`), `termios` raw mode ANSI
  terminal I/O, dynamic heap buffer management.
- **Build Target**: `make se-linux` (verified via `make test-linux`).
- **Status**: Active / 2 Open (Bugs 2.4.51, 2.4.52 Open; Bugs 2.4.1–2.4.50
  Resolved).
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
  - [x] **Bug 2.4.20: Deprecated WordStar Diamond Navigation & Key Aliases**:
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
    - *Resolution*: Disassociated WordStar diamond keys from cursor movement
      across all core and UI modules. Re-bound `KEY_CTRL_D` to `do_delete()` and
      `KEY_CTRL_E` to `cursor_end()` in `src/core/editor.c`. Removed
      `KEY_CTRL_E` and `KEY_CTRL_X` grid aliases from `src/core/ui_browser.c`.
      Removed `KEY_CTRL_D` and `KEY_CTRL_S` button aliases from
      `src/core/ui_modal.c`. Updated `s_help_lines` in `src/core/ui_render.c` to
      render `Arrows / ANSI VT100`. Validated via
      `test_arrow_and_wordstar_navigation` in `tests/test_linux_native.py`.
  - [x] **Bug 2.4.21: Off-by-Zero Column Anchor on Backspace Line Join**:
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
    - *Resolution*: Preserved `join_col` before concatenation in
      `src/core/editor.c`. Invalidated active line before deleting document row
      to avoid redundant commits. Explicitly assigned `target_row =
      g_cur_doc_row - 1`, anchored cursor to junction boundary (`g_cur_col =
      join_col`), updated sticky target column, and triggered status bar
      rendering. Validated via `test_bug_2_4_21_backspace_line_join` in
      `tests/test_linux_native.py`.
  - [x] **Bug 2.4.22: Delete & Ctrl+D Fail to Delete Active Block Selection**:
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
    - *Resolution*: Updated `do_delete()` in `src/core/editor.c` to inspect
      `g_block_mode`. When active, it solidifies selection if dynamically
      selecting, invokes `do_delete_block()`, and recalculates sticky visual
      column target. Validated via `test_bug_2_4_22_delete_active_block` in
      `tests/test_linux_native.py`.
  - [x] **Bug 2.4.23: Backspace Fails to Cancel Dynamic Block Selection**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 6.8, 10.1.
    - *Issue*: In `src/core/editor.c:192-238` (`do_backspace`), pressing
      Backspace while dynamic block selection is underway
      (`g_block_mode == BLOCK_MODE_SELECTING`) deletes the character preceding
      the cursor and mutates document contents. Section 6.8 strictly mandates
      that pressing Backspace during dynamic block selection must cancel
      selection (`g_block_mode = BLOCK_MODE_OFF`) to safeguard highlighted
      text against unintended modification, keeping the cursor stationary
      without deleting text.
    - *Resolution*: Updated `do_backspace()` in `src/core/editor.c` to inspect
      `g_block_mode`. When `BLOCK_MODE_SELECTING`, it cancels the block via
      `cancel_block()`, triggers status bar re-rendering, and returns
      immediately without mutating text or moving cursor. Validated via
      `test_bug_2_4_23_backspace_cancels_block` in `tests/test_linux_native.py`.
  - [x] **Bug 2.4.24: Enter Key in Dynamic Block Mode Splits Active Line**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 6.5, 9.1, 10.
    - *Issue*: In `src/core/editor.c:276-307` (`do_enter`), pressing Enter
      unconditionally splits the active line at `g_cur_col` and creates a new
      line. When dynamic block selection is active (`g_block_mode ==
      BLOCK_MODE_SELECTING`), pressing Enter must solidify the selection
      (`solidify_block()`, locking `g_block_mode = BLOCK_MODE_SOLIDIFIED`)
      without splitting the line or mutating document text.
    - *Resolution*: Updated `do_enter()` in `src/core/editor.c` to inspect
      `g_block_mode`. When `BLOCK_MODE_SELECTING`, it solidifies the selection
      via `solidify_block()`, triggers status bar re-rendering, and returns
      without splitting the line. Validated via
      `test_bug_2_4_24_enter_solidifies_block` in `tests/test_linux_native.py`.
  - [x] **Bug 2.4.25: Missing In-Field Editing Keys in Archetype C Modals**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 8.3, 10.1, 10.2.
    - *Issue*: In `src/core/ui_modal.c:258-318` (`modal_prompt_text`), the
      parametric input field pins the cursor to the end of the input string
      (`cur_len`). It does not track an internal cursor index, completely
      ignoring directional navigation (`KEY_LEFT`, `KEY_RIGHT`, `KEY_HOME`,
      `KEY_END`, `KEY_CTRL_A`, `KEY_CTRL_E`). Furthermore, `KEY_DEL` is mapped
      to backspace (deleting the last character), and `KEY_CTRL_D` is unhandled,
      violating the mandate for forward character deletion under the cursor.
    - *Resolution*: Implemented internal cursor index (`cursor_pos`) in
      `modal_prompt_text()` in `src/core/ui_modal.c`. Added full support for
      Left/Right navigation, Home (`Ctrl+A`), End (`Ctrl+E`), character
      insertion at `cursor_pos`, Backspace deleting left of cursor, and Delete /
      `Ctrl+D` deleting under cursor. Validated via
      `test_bug_2_4_25_modal_prompt_text_editing` in
      `tests/test_linux_native.py`.
  - [x] **Bug 2.4.26: Status Bar Layout Regression & Format Truncation Error**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 4.1, 4.3, 4.4, 11.1
      (Anti-Pattern #1).
    - *Issue*: In `src/core/ui_render.c:170-245` (`render_status_bar`), buffer
      capacities were reduced (`raw_name[32]`, `sbuf[16]`, `core[128]`), causing
      GCC compilation to fail with `-Werror=format-truncation` during `make
      se-linux`. Furthermore, Field 4 is squatted by `Sel: ...`, `Block: ...`,
      `[Pan +40]`, and `[Overwrite]`, clobbering persistent `^K: Editor keys |`
      and violating the canonical status bar invariant that mode flags and
      indicators belong exclusively in Field 5.
    - *Resolution*: Isolated CP/M status bar optimizations under
      `#ifdef __CPM__` and restored canonical Linux SE status bar with 80-byte
      `raw_name` and 256-byte `core`/`full_bar` buffers, eliminating format
      truncation errors. Restored persistent `^K: Editor keys |` in Field 4,
      routed mode indicators into Field 5, and restored Tier 2 save
      notifications under `#ifndef __CPM__` in `src/core/file_io.c`.
  - [x] **Bug 2.4.27: Missing File Not Found Modal Alert on Open and Insert**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 8.3 (Archetype A).
    - *Issue*: In `src/core/editor.c:560`, `src/core/ui_render.c:355`, and
      `src/core/file_io.c:93`, attempting to open or insert a non-existent file
      silently returns `-1`. The editor fails to render the canonical 50x7
      File Not Found modal alert
      (`+------------------------------------------------+`,
      `'FILENAME' was not found.`, `Specified file not found on disk.`,
      `Press any key to continue`), and either initializes an empty buffer or
      silently drops the action without notifying the user.
    - *Resolution*: Implemented canonical 50x7 File Not Found modal alert
      (`modal_alert_file_not_found`) adhering to Archetype A in
      `src/core/ui_modal.c` and declared in `src/include/ui_modal.h`. Added
      pre-flight existence checks in `file_read_op()` (`src/core/file_io.c`) and
      in `ui_browser_workspace()` (`src/core/ui_browser.c`) for Open and Insert
      operations, returning the user directly to the active browser workspace
      with input buffer preserved upon dismissal. Validated via
      `test_bug_2_4_27_file_not_found_alert` in `tests/test_linux_native.py`.
  - [x] **Bug 2.4.28: Missing Overwrite File Confirmation Dialog on Save**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 8.3 (Archetype B).
    - *Issue*: In `src/core/file_io.c:189` (`file_write_op`) and
      `src/core/ui_browser.c` (`ui_browser_workspace` in `BROWSER_MODE_SAVE`
      and `BROWSER_MODE_SAVE_BLOCK`), saving to an existing destination file
      executes `fopen(filename, "wb")` unconditionally. Section 8.3 mandates
      that saving to an existing file must present the canonical 50x7
      Overwrite File Confirmation Dialog (`Existing file contents will be lost`,
      `File already exists. Overwrite?`, `[Y]es   [N]o   [ESC]=Cancel`) with the
      terminal cursor positioned on the prompt line after `Overwrite? ` at
      Column 40.
    - *Resolution*: Implemented canonical Archetype B Overwrite File modal
      dialog (`modal_confirm_overwrite`) in `src/core/ui_modal.c` with terminal
      cursor positioned after `Overwrite? ` at Column 40 (`left + 40`). Added
      destination file existence checks in `ui_browser_workspace` for both typed
      and grid-selected entries in `BROWSER_MODE_SAVE` and
      `BROWSER_MODE_SAVE_BLOCK`, proceeding only on `Y`/`y` or Enter on Yes, and
      returning to browser with input intact on `N`/`n` or ESC. Validated via
      `test_bug_2_4_28_overwrite_confirmation` in `tests/test_linux_native.py`.
  - [x] **Bug 2.4.29: Missing Block-Active File Insert and Block Save Modes**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 7.6, 7.8, 9.1, 10.
    - *Issue*: In `src/core/editor.c:535-565`, pressing `Ctrl+O` while a block
      is active replaces the entire document buffer via `file_load()`, rather
      than opening the Insert File workspace and streaming file contents into
      the buffer at the cursor (`file_insert()`). Likewise, pressing `Ctrl+S`
      while a block is active saves the full document buffer via `file_save()`,
      rather than opening the Save Block workspace and writing only the
      highlighted block range (`file_save_block()`).
    - *Resolution*: Updated `KEY_CTRL_O` and `KEY_CTRL_S` handlers in
      `src/core/editor.c` to inspect `g_block_mode != BLOCK_MODE_OFF`. When a
      block is active:
      - Solidifies dynamic selection if selecting.
      - On `Ctrl+S`, routes to `ui_browser_save_block_dialog()` and saves only
        normalized block range (`g_norm_start_row`..`g_norm_end_row`) via
        `file_save_block()`, preserving selection state.
      - On `Ctrl+O`, routes to `ui_browser_insert_dialog()` and streams lines
        into document at cursor via `file_insert()`, clearing selection.
      - Updated `do_paste_block()` in `src/core/block.c` to clear active block
        selection upon pasting per Section 9.1.
      Validated via `test_bug_2_4_29_block_save_and_insert` in
      `tests/test_linux_native.py`.
  - [x] **Bug 2.4.30: Missing Tier 2 Block Operations Pop-up Menu on Ctrl+K**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 7.3, 7.6, 7.8, 8.3, 10.
    - *Issue*: In `src/core/editor.c:576`, pressing `KEY_CTRL_K` unconditionally
      displays the full-screen Help workspace (`show_help_screen()`). When a
      block selection is active (`g_block_mode != BLOCK_MODE_OFF`), Section 10
      and canonical CP/M rules mandate that `Ctrl+K` display the centered
      Tier 2 Block Operations pop-up modal (`do_block_menu_popup()`), providing
      quick block actions: `[C]opy`, `[M]ove`, `[D]elete`, `[S]ave Block`,
      `[R]ead/Insert File`, `[ESC] Cancel`. Although `do_block_menu_popup()` is
      declared in `include/block.h`, it is uncalled and unimplemented.
    - *Required Fix*: Implement `do_block_menu_popup()` in `src/core/block.c`
      displaying the canonical 50x7 dialog with hotkeys for Copy, Move, Delete,
      Save Block, Insert File, and ESC Cancel. Update `KEY_CTRL_K` dispatch in
      `src/core/editor.c` to invoke `do_block_menu_popup()` when
      `g_block_mode != BLOCK_MODE_OFF`.
    - *Resolution*: Implemented canonical 50x7 Tier 2 Block Operations modal
      in `src/core/block.c` with metric calculation, dynamic vs solidified
      shortcuts, hotkey dispatch (Enter, Copy, Move, Delete, Save, Insert,
      Clear, ESC), and verified screen restoration.
      Validated via `test_bug_2_4_30_block_menu_popup` in
      `tests/test_linux_native.py`.
  - [x] **Bug 2.4.31: Missing In-Field Cursor Navigation in Find Text Modal**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 8.3 (Archetype C), 10.1, 10.2.
    - *Issue*: In `src/core/search.c:215-289` (`do_ctrl_f_find`), the 50x7 Find
      Text modal dialog lacks cursor navigation. The cursor is pinned to
      `left + 14 + cur_len`. It does not support Left/Right arrow keys
      (`KEY_LEFT`, `KEY_RIGHT`), Home/End (`KEY_HOME`, `KEY_END`, `KEY_CTRL_A`,
      `KEY_CTRL_E`), or forward character deletion under the cursor
      (`KEY_CTRL_D`), and maps `KEY_DEL` to Backspace (deleting the last
      character in the buffer).
    - *Required Fix*: Track internal cursor position (`cursor_pos`) in
      `do_ctrl_f_find()`. Support Left/Right arrow cursor movement, Home
      (`Ctrl+A`) / End (`Ctrl+E`), character insertion at `cursor_pos`,
      Backspace deleting left of cursor (`cursor_pos - 1`), and Delete /
      `Ctrl+D` forward-deleting character at `cursor_pos`.
    - *Resolution*: Implemented `cursor_pos` navigation in `do_ctrl_f_find()`
      and `draw_find_field()` (`src/core/search.c`) supporting Left/Right
      arrows, Home (`Ctrl+A`), End (`Ctrl+E`), Backspace left-deletion, Delete /
      `Ctrl+D` forward character deletion, and in-field character insertion.
      Validated via `test_bug_2_4_31_find_modal_cursor_navigation` in
      `tests/test_linux_native.py`.
  - [x] **Bug 2.4.32: Multi-Byte Escape Sequence Trailing Byte Leakage**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 10.3.
    - *Issue*: In `src/hal/linux/hal_linux_keyboard.c:142-145`, when an
      unrecognized escape prefix is encountered, the HAL calls
      `unget_raw_byte(b1)` and returns `KEY_ESC`. For multi-byte sequences that
      fail parsing midway (such as incomplete CSI or SS3 sequences), subsequent
      bytes in the sequence remain in `s_raw_buf` and are returned as regular
      typed ASCII characters. Section 10.3 strictly mandates that any sequence
      beginning with `ESC` followed by `[` or `O` must drain and discard all
      sequence bytes atomically without leaking characters back into console
      input.
    - *Required Fix*: In `hal_linux_keyboard.c`, implement atomic escape
      sequence draining on unrecognized or malformed sequences following
      `ESC [` or `ESC O`, ensuring zero trailing bytes leak into standard input.
    - *Resolution*: Implemented `drain_csi_sequence()` in
      `src/hal/linux/hal_linux_keyboard.c` consuming intermediate and final
      bytes (0x40..0x7E) atomically upon encountering unrecognized or
      unhandled CSI / SS3 escape sequences, returning 0 without leaking
      trailing bytes or triggering spurious hotkeys.
      Validated via `test_bug_2_4_32_escape_sequence_leakage` in
      `tests/test_linux_native.py`.
  - [x] **Bug 2.4.33: Typing Characters and Tab Fail to Clear Active Block**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 9.1, 9.2, 10.1;
      `src/se.asm:1361-1399`.
    - *Issue*: In `src/core/editor.c:591-600`, typing printable characters or
      pressing Tab while dynamic block selection is active (`g_block_mode ==
      BLOCK_MODE_SELECTING`) inserts characters into the line and extends
      selection bounds. Per Section 9.1 and 10.1, typing in dynamic mode must
      cancel selection (`cancel_block()`) to protect against accidental edits
      without inserting text; in solidified mode (`g_block_mode ==
      BLOCK_MODE_SOLIDIFIED`), clear selection before inserting characters.
    - *Required Fix*: In `editor_handle_key()`, on printable characters and
      `KEY_TAB`, if `g_block_mode == BLOCK_MODE_SELECTING`, invoke
      `cancel_block()`, update status render, and return without inserting
      characters. If `g_block_mode == BLOCK_MODE_SOLIDIFIED`, cancel block and
      proceed with normal character insertion.
    - *Resolution*: Updated printable character and tab handling in
      `editor_handle_key()` (`src/core/editor.c`) to cancel dynamic block
      selection without inserting characters, and clear solidified block
      selection before proceeding with normal character insertion.
      Validated via `test_bug_2_4_33_block_typing_cancellation` in
      `tests/test_linux_native.py`.
  - [x] **Bug 2.4.34: Missing Predominant Language Indication on Splash**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 7.2, 14.6.
    - *Issue*: Section 7.2 and Section 14.6 mandate that row 2 of the 14-line
      splash content block display `Version <version> (<Language>)`, explicitly
      specifying `(C)` for Linux native C builds (`Version v1.1.0 (C)`). Row 1
      must display `SE — Screen Editor`. In `src/core/ui_render.c:409-411`,
      row 1 displays `SE.COM — Screen Editor` and row 2 displays
      `"                    Version v1.1.0                    "`, omitting the
      mandatory language indicator.
    - *Required Fix*: Update `s_splash_lines` in `src/core/ui_render.c` to
      render `SE — Screen Editor` on row 1 and `Version v1.1.0 (C)` on row 2.
    - *Resolution*: Updated `s_splash_lines` in `src/core/ui_render.c` to render
      canonical title `SE — Screen Editor` on row 1 and release version with
      predominant language indicator `Version v1.1.0 (C)` on row 2.
      Validated via `test_bug_2_4_34_splash_language_indication` in
      `tests/test_linux_native.py`.
  - [x] **Bug 2.4.35: Splash Screen Hotkey Inversion & Missing Native Mode**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 2.1, 7.2, 14.1.
    - *Issue*: Section 2.1 and Section 7.2 designate Option 1 (`80x24`) as
      standard classic terminal mode triggered by hotkey `1`, Option 2
      (`120x40`) as wide console mode triggered by hotkey `2`, and Option 3
      (`Native host terminal`) triggered by hotkey `3` on platforms supporting
      dynamic dimension querying. In `src/core/ui_render.c:424-425, 507-517`:
      - Splash menu lines display `type [1] set 120x40` and
        `type [2] set 80x24`.
      - Key handler maps `1` to `MODE_120X40` and `2` to `MODE_80X24`
        (inverted).
      - Option 3 (`Native` dynamic host dimensions via `ioctl(TIOCGWINSZ)`) is
        completely missing from menu and key handler.
    - *Required Fix*: In `s_splash_lines` and splash event loop in
      `ui_render.c`, map `1` to Option 1 (`80x24`), `2` to Option 2 (`120x40`),
      and add `3` for Option 3 (`Native host terminal`). Support dynamic host
      terminal dimensions when native mode is active in `hal_linux_console.c`.
    - *Resolution*: Updated `s_splash_lines` and hotkey dispatch in
      `src/core/ui_render.c` mapping `1` to 80x24 (`MODE_80X24`), `2` to 120x40
      (`MODE_120X40`), and `3` to Native (`MODE_NATIVE`). Implemented
      `hal_console_get_native_size` and dynamic terminal querying via
      `ioctl(TIOCGWINSZ)` in `src/hal/linux/hal_linux_console.c`. Updated
      status bar geometry formatting to dynamically render native dimensions.
      Validated via `test_bug_2_4_35_splash_hotkeys_and_native_mode` in
      `tests/test_linux_native.py`.
  - [x] **Bug 2.4.36: Missing Screen Clearance on Screen Geometry Switching**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 2.1, 7.2, 14.1.
    - *Issue*: Sections 2.1, 7.2, and 14.1 mandate that prior to switching
      screen geometries, the editor must explicitly clear the entire terminal
      screen (emitting ANSI clear sequence `\x1b[2J\x1b[H` / `TERM_INIT`)
      before applying new dimensions and re-rendering. In
      `src/core/ui_render.c:507-517`, switching modes updates
      `g_config.screen_mode`, `g_active_cols`, and `g_active_rows` and sets
      `need_render = 1` without clearing the screen. Switching from 120x40 or
      Native to 80x24 leaves stale character debris, tildes, and ghost status
      bar remnants on rows 25..40 and columns 81..120.
    - *Required Fix*: In `show_splash_screen()`, invoke `clear_screen()` /
      `hal_console_clear()` before updating dimensions and re-rendering on
      geometry switch keys.
    - *Resolution*: Invoked `clear_screen()` prior to mutating active dimensions
      and triggering screen repaint on keys `1`, `2`, and `3` in
      `show_splash_screen()` (`src/core/ui_render.c`), completely wiping dirty
      screen remnants and viewport artifacts.
      Validated via `test_bug_2_4_36_geometry_switch_clear` in
      `tests/test_linux_native.py`.
  - [x] **Bug 2.4.37: Non-Interactive Configuration Manager Workspace**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 7.4, 13.1, 13.2.
    - *Issue*: In `src/core/ui_render.c:572-593` (`show_config_screen`), the
      Tier 1 Configuration Manager workspace renders a static 11-line text
      block with hardcoded values (`80x24`, Tab 8, 32K, RAM Drive Disabled) and
      unconditionally exits on the first keystroke received. It lacks an
      interactive event loop to toggle settings (`1` Geometry, `2` Tab Width,
      `3` Max Lines, `4` RAM Drive) or persist settings to `SE.CFG` on `S`/`s`
      via `config_save()`.
    - *Required Fix*: Implement an interactive event loop in
      `show_config_screen()` (`src/core/ui_render.c`) that dynamically formats
      current parameters from `g_config`, toggles values on `1`, `2`, `3`, `4`,
      saves to `SE.CFG` on `S`/`s`, and returns on `ESC`/`Enter`.
    - *Resolution*: Implemented dynamic interactive event loop in
      `show_config_screen()` (`src/core/ui_render.c`), formatting active
      parameters from `g_config`, toggling options on keys `1`, `2`, `3`, `4`,
      persisting configuration to `SE.CFG` via `config_save()` on `S`/`s`, and
      returning to caller on `ESC`/`Enter`.
      Validated via `test_bug_2_4_37_config_screen_interactive` in
      `tests/test_linux_native.py`.
  - [x] **Bug 2.4.38: Default Tab Width Inversion in Config Defaults**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 6.2, 7.4.
    - *Issue*: Section 6.2 defines default tab stop intervals as
      `CFG_TAB_WIDTH = 4` columns (configurable to 8). In `src/core/config.c:41`
      (`config_init_defaults`) and `src/core/editor.c:54`, default tab width is
      hardcoded to `8` columns instead of `4`.
    - *Required Fix*: Change `g_config.tab_width` default in
      `src/core/config.c:41` to `4`, and update fallback in
      `src/core/editor.c:54` to `4`.
    - *Resolution*: Updated `g_config.tab_width` default to `4` in
      `src/core/config.c` and updated fallback tab widths to `4` in
      `src/core/editor.c` and `src/core/ui_render.c`. Adjusted config header and
      updated regression test suite, adding `test_bug_2_4_38_default_tab_width`
      in `tests/test_linux_native.py`.
  - [x] **Bug 2.4.39: Help Screen Displays Obsolete WordStar Diamond Keys**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 6.3, 6.4, 7.3.
    - *Issue*: In `src/core/ui_render.c:528`, the Help workspace displays
      `Arrows / WordStar (^S,^D,^E,^X)`. Sections 6.3, 6.4, and 7.3 explicitly
      mandate that legacy WordStar diamond navigation keys (`Ctrl+S`, `Ctrl+D`,
      `Ctrl+E`, `Ctrl+X`) are unsupported for directional movement to avoid
      collisions with Save File, Delete, End of Line, and Cut Block. The
      canonical Help Screen layout in Section 7.3 explicitly specifies
      `Arrows / ANSI VT100`.
    - *Required Fix*: Update `s_help_lines` in `src/core/ui_render.c` to
      display `Arrows / ANSI VT100` and remove misleading WordStar references.
    - *Resolution*: Replaced obsolete Help screen mockup with canonical 22-line
      template from Section 7.3 and `plugins/help.asm`, displaying ANSI cursor
      navigation (`Arrow Keys`), direct block commands, and standard editor
      shortcuts while eliminating legacy WordStar diamond references. Validated
      via `test_bug_2_4_39_help_screen_canonical_layout` in
      `tests/test_linux_native.py`.
  - [x] **Bug 2.4.40: Missing Archetype D Selection Modal on Ctrl+P**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 7.2, 8.3 (Archetype D), 10.
    - *Issue*: In `src/core/editor.c:568` and `src/core/ui_render.c:501`,
      pressing `Ctrl+P` directly opens the slot table of `plugin_manager_ui()`.
      Per Section 7.2, Section 8.3, and Section 10, `Ctrl+P` is bound to the
      context-aware Plugin Palette (`DO_CONTEXT_PLUGIN_POPUP`), which must
      present the canonical 50x8 Archetype D modal (`Select a plugin to
      execute:`, numbered entries, `> ` active pointer, Up/Down navigation,
      Enter to run, ESC to cancel).
    - *Required Fix*: Implement `show_plugin_palette()` adhering to Archetype D
      in `src/core/plugin_mgr.c`, and route `KEY_CTRL_P` in `editor.c` and
      `ui_render.c` to this modal.
    - *Resolution*: Implemented canonical Archetype D Plugin Palette modal
      dialog (`show_plugin_palette`) in `src/core/plugin_mgr.c` featuring
      50-col framing, active pointer (`> `), Up/Down navigation, direct digit
      selection, Enter execution, and ESC cancellation. Bound `KEY_CTRL_P`
      to this modal in `src/core/editor.c` and `src/core/ui_render.c`.
      Validated via `test_bug_2_4_40_plugin_palette_modal` in
      `tests/test_linux_native.py`.
  - [x] **Bug 2.4.41: Tab Traversal Halts Early vs Snap-Forward Alignment**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 6.2, 6.4.
    - *Issue*: In `src/core/editor.c:485-497` (`adjust_col_to_target`), when
      traversing an active line to match sticky target column `target_vis_col`,
      if the target falls within an expanded tab (`vis_acc + spaces >
      target_vis_col`), the loop executes `break;`. This snaps the cursor
      backward to the start of the tab (`vis_acc`). Section 6.2 and 6.4 strictly
      mandate snap-forward alignment: the cursor must advance across the tab
      (`vis_acc += spaces`, `char_idx++`) to snap forward to the discrete
      character boundary directly following the tab, keeping the cursor
      adjacent to indented code rather than retreating to the margin.
    - *Required Fix*: Update `adjust_col_to_target()` in `src/core/editor.c` to
      remove early loop breaks on tab boundaries, advancing across the tab to
      snap forward to the discrete character position following the tab.
    - *Resolution*: Removed premature loop break on tab boundaries in
      `adjust_col_to_target()` in `src/core/editor.c`, ensuring traversal
      advances across the tab (`vis_acc += spaces`, `char_idx++`) to snap
      forward to the discrete character boundary following the tab per
      Section 6.2 and 6.4. Updated regression test expectations and added
      `test_bug_2_4_41_tab_snap_forward` in `tests/test_linux_native.py`.
  - [x] **Bug 2.4.42: Config Manager Layout Divergence & Prohibited Prompt**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 7.4.
    - *Issue*: In `src/core/ui_render.c:601-706` (`show_config_screen`):
      1. Displays only 4 options in non-canonical order (`1. Screen Geometry`,
         `2. Tab Width`, `3. Max Line Capacity`, `4. RAM Drive Mode`), omitting
         Option 5 (`Plugin Manager`). Canonical order is (1) Screen Geometry,
         (2) RAM Drive Mode, (3) Max Doc Lines, (4) Tab Width, (5) Plugin
         Manager.
      2. Renders an interactive prompt line `Enter option: _` on row 9, which
         Section 7.4 strictly prohibits ("The workspace operates as a
         non-buffered, instant-response hotkey menu. An `Enter option: _`
         prompt line is strictly prohibited").
      3. Footer displays `[S] Save to SE.CFG    [ESC]/[Enter] Return` instead
         of canonical `[1-5]=Toggle Option  [S]=Save Config  [ESC]=Exit`.
      4. Omits the `Config Status:` origin header (`Config Status: Loaded
         from SE.CFG` or `Defaults`).
      5. Fails to support `Q` / `q` for exiting to the Splash screen.
      6. Fails to hide the terminal hardware cursor (`TERM_HIDE_CURSOR`).
      7. Uses UTF-8 em-dash `—` in title instead of ASCII hyphen `-`.
    - *Required Fix*: Refactor `show_config_screen()` to match canonical Section
      7.4 layout: 5 options in canonical order, `Config Status:` header,
      canonical footer, instant single-keystroke dispatch on 1-5, S/s save,
      ESC/Q/Enter exit, hidden cursor, and elimination of `Enter option: _`.
    - *Resolution*: Refactored `show_config_screen()` in `src/core/ui_render.c`
      to conform to canonical Section 7.4 layout: rendered 5 options in
      canonical order, added `Config Status:` header tracking `g_config_loaded`,
      removed prohibited `Enter option: _` prompt, updated footer to canonical
      `[1-5]=Toggle Option  [S]=Save Config  [ESC]=Exit`, supported `Q`/`q`
      exit to Splash screen, hid terminal hardware cursor, and replaced UTF-8
      em-dash with ASCII hyphen `-`. Validated via
      `test_bug_2_4_42_config_screen_canonical_layout` in
      `tests/test_linux_native.py`.
  - [x] **Bug 2.4.43: Splash Screen Layout Non-Conformity & Clean Header**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 2.6, 7.2, 14.6.
    - *Issue*: In `src/core/ui_render.c:422-442` (`s_splash_lines`):
      1. Violates the Clean Header Mandate by rendering `Version v1.1.0 (C)` on
         Row 2 directly beneath the application title. Section 7.2 strictly
         mandates that the splash screen does not display the release version or
         programming language (consolidated exclusively onto the About screen).
      2. Uses UTF-8 em-dash `SE — Screen Editor` on Row 1 instead of standard
         ASCII hyphen `SE - Screen Editor` (violating Section 2.6).
      3. Omits the 4 canonical diagnostic status lines at the bottom of the
         splash content block: `Active Screen : [80x24 (Classic Terminal)]`,
         `RAM Drive (A:): [Preserved (Active)]`, `Plugin System :
         [Operational]`, and `Max Lines     : [32,768 lines]`.
      4. Uses a 19-line by 54-column bounding box instead of the standardized
         21-line by 50-column geometry.
    - *Required Fix*: Update `s_splash_lines` and `show_splash_screen()` in
      `src/core/ui_render.c` to conform to the 21x50 canonical layout: ASCII
      hyphen header, removal of version/language line, inclusion of the 4
      diagnostic status lines, and standard geometry option presentation.
    - *Resolution*: Updated `show_splash_screen()` in `src/core/ui_render.c` to
      conform to canonical 21-line by 50-column layout: enforced Clean Header
      Mandate with `SE - Screen Editor` on Row 1 using ASCII hyphen `-`, removed
      premature version/language line, centered standard command hotkeys, and
      dynamically formatted the 4 canonical diagnostic status lines (Active
      Screen, RAM Drive (A:), Plugin System, Max Lines). Validated via
      `test_bug_2_4_43_splash_canonical_layout` in `tests/test_linux_native.py`.
  - [x] **Bug 2.4.44: Non-Conforming About Screen Layout & Missing Credits**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 2.6, 7.11, 14.6.
    - *Issue*: In `src/core/ui_render.c:583-599` (`show_about_screen`), the
      About screen displays a non-conforming 6-line, 46-column text block:
      1. Uses UTF-8 em-dash and generic host operating system label `SE.COM —
         Screen Editor (Linux)` instead of canonical title `SE - Screen Editor`.
      2. Row 2 displays `Version v1.1.0`, omitting the mandatory build date and
         predominant programming language `version 1.1.0 (2026-10-09) (C)`.
      3. Omits author attribution (`by Dean Jenkins`), AI toolchain credits
         (`Google Antigravity 2.19.1 & Gemini FLASH 3.8 high`), and license
         notice (`Open source software under the MIT License`).
      4. Prompt reads `Press any key to return...` instead of canonical
         `Press any key to continue`.
      5. Geometry is 6 lines x 46 columns instead of 9 lines x 54 columns.
    - *Required Fix*: Rewrite `show_about_screen()` in `src/core/ui_render.c` to
      render the standardized 9-line by 54-column template adhering to Section
      7.11 and 14.6.
    - *Resolution*: Rewrote `show_about_screen()` in `src/core/ui_render.c` to
      render the standardized 9-line by 54-column template: canonical title
      `SE - Screen Editor` using ASCII hyphen `-`, release version with build
      date and predominant language `version 1.1.0 (2026-10-09) (C)`, author
      attribution (`by Dean Jenkins`), AI toolchain credits (`Google
      Antigravity 2.19.1 & Gemini FLASH 3.8 high`), MIT license notice, and
      canonical prompt `Press any key to continue`. Validated via
      `test_bug_2_4_44_about_screen_canonical_layout` in
      `tests/test_linux_native.py`.
  - [x] **Bug 2.4.45: Line Ending Decoupling Failure & Global Config Mutation**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 7.7, 13.2.
    - *Issue*: Section 13.2 explicitly removes `FORMAT` from `SE.CFG`,
      mandating that line endings are managed strictly per-document: newly
      created files default to host-native format (LF on Linux, CRLF on CP/M),
      opened files preserve their detected line endings, and the Save File
      screen (`Ctrl+F`) toggles format for that specific document.
      In Linux SE:
      1. `src/core/config.c:46` sets `g_config.save_format = FMT_CPM`, and
         `src/core/config.c:205` serializes `FORMAT=CPM`/`FORMAT=LINUX` into
         `SE.CFG`.
      2. `src/core/buffer.c:63` initializes new empty documents with
         `g_file_format = g_config.save_format`, causing new documents on Linux
         to default to CP/M CRLF endings rather than native Linux LF endings.
      3. In `src/core/editor.c:568, 580, 588, 591`, `src/core/ui_render.c:485`,
         and `src/core/ui_modal.c:378`, document saves invoke `file_save(...,
         g_config.save_format)` passing the global config format rather than
         the document's `g_file_format`.
      4. In `src/core/ui_browser.c:647-649`, pressing `Ctrl+F` toggles
         `g_config.save_format` (global configuration) rather than toggling
         solely the document's per-file `g_file_format`.
      5. `src/core/config.c:40` defaults `g_config.screen_mode` to
         `MODE_120X40` instead of `MODE_80X24` (`SCREEN=80X24` per Section
         13.2).
    - *Required Fix*: Remove `FORMAT` from `SE.CFG` serialization and parsing in
      `src/core/config.c`. Default new documents on Linux to `FMT_LINUX` (`LF`).
      Ensure all save operations use the active document's `g_file_format`.
      Ensure `Ctrl+F` in `ui_browser.c` toggles `g_file_format` without mutating
      global configuration. Default `g_config.screen_mode` to `MODE_80X24`.
    - *Resolution*: Removed `FORMAT` parsing and serialization from `SE.CFG`
      in `src/core/config.c`. Defaulted new documents on Linux to `FMT_LINUX`
      (`LF`) in `src/core/buffer.c`, `src/core/file_io.c`, and
      `src/core/config.c`. Updated all save operations in `src/core/editor.c`,
      `src/core/block.c`, `src/core/ui_render.c`, and `src/core/ui_modal.c` to
      pass active document `g_file_format`. Isolated `Ctrl+F` format toggling
      in `src/core/ui_browser.c` to `g_file_format` without mutating `g_config`.
      Defaulted `g_config.screen_mode` to `MODE_80X24`. Validated via
      `test_bug_2_4_45_line_ending_decoupling` in `tests/test_linux_native.py`.
  - [x] **Bug 2.4.46: Premature Modal Dismissal on Unexpected Keys**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 8.3.
    - *Issue*: In `src/core/ui_modal.c:321-326` (`modal_prompt_text`), pressing
      `Up`, `Down`, `PgUp`, `PgDn`, `Ctrl+U`, or `Ctrl+V` exits the modal dialog
      and returns `k`. Section 8.3 explicitly mandates the Unexpected Keystroke
      Protection Mandate: "Modals MUST NOT be cancelled or dismissed by
      unexpected keys or escape sequences (such as cursor arrow keys, PgUp/PgDn,
      function keys, or stray control keys). Any unexpected sequences received
      while an input modal is active must be discarded without altering the
      modal's input buffer, without moving the underlying document cursor, and
      without cancelling the dialog."
    - *Required Fix*: Remove lines 321-326 in `modal_prompt_text()`
      (`src/core/ui_modal.c`) so that unexpected keys are safely discarded
      without dismissing the input dialog or altering state.
    - *Resolution*: Removed premature modal dismissal on unexpected navigation
      keys (`Up`, `Down`, `PgUp`, `PgDn`, `Ctrl+U`, `Ctrl+V`) from
      `modal_prompt_text()` in `src/core/ui_modal.c`, enforcing the Section 8.3
      Unexpected Keystroke Protection Mandate and ensuring input modals remain
      active with buffer preserved until explicit `Enter` or `ESC`. Validated
      via `test_bug_2_4_46_unexpected_keys_in_modals` in
      `tests/test_linux_native.py`.
  - [x] **Bug 2.4.47: Retention of Intermediary Clipboard Primitives**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 7.3, 9.3, 10.
    - *Issue*: Section 9.3 establishes the "Direct In-Place Block Manipulation
      Mandate", strictly prohibiting intermediary clipboard buffers
      (`s_clipboard_buf`) and asynchronous paste steps across all SE variants.
      Block operations must execute directly between the marked block and
      cursor: `Ctrl+C` (Copy Block to Cursor), `Ctrl+X` (Move Block to
      Cursor), and `Ctrl+D` (Delete Block). Furthermore, legacy `Ctrl+U` and
      `Ctrl+V` motion aliases are removed in favor of dedicated `PgUp` and
      `PgDn` keys, and `Ctrl+V` paste is eliminated.
      In Linux SE:
      1. In `src/core/editor.c:541-547`, `KEY_CTRL_U` is bound to `page_up()`,
         and `KEY_CTRL_V` is bound to `do_paste_block()` / `page_down()`.
      2. In `src/core/block.c:232, 246, 336-373`, `s_clipboard_buf`,
         `do_cut_block()`, and `do_paste_block()` are retained as intermediary
         clipboard mechanisms.
      3. In `src/core/ui_render.c:560`, `s_help_lines` advertises
         `Ctrl+U / Ctrl+V: Page Up / Down`, `Ctrl+V: Paste Block`,
         `Ctrl+X: Cut Block`, and `Ctrl+C: Copy Block` instead of canonical
         direct block shortcuts and dedicated `PgUp`/`PgDn` paging keys.
    - *Required Fix*: Eliminate intermediary clipboard routines (`do_cut_block`,
      `do_paste_block`, `s_clipboard_buf`) in `src/core/block.c` in favor of
      direct in-place block manipulation. Remove `KEY_CTRL_U` and `KEY_CTRL_V`
      aliases from `src/core/editor.c`. Update `s_help_lines` in
      `src/core/ui_render.c` to advertise canonical direct block shortcuts and
      dedicated `PgUp`/`PgDn` paging keys.
    - *Resolution*: Eliminated intermediary clipboard buffer
      (`s_clipboard_buf`), clipboard length tracker, `do_cut_block()`,
      `do_paste_block()`, and clipboard getters from `src/core/block.c` and
      `src/include/block.h`. Refactored `do_copy_block()` to operate directly
      in-place without static clipboard storage. Removed legacy `KEY_CTRL_U`
      and `KEY_CTRL_V` motion and paste aliases from `src/core/editor.c`.
      Updated `s_help_lines` in `src/core/ui_render.c` to display dedicated
      `PgUp` and `PgDn` keys. Validated via
      `test_bug_2_4_47_direct_inplace_block_manipulation` in
      `tests/test_linux_native.py`.
  - [x] **Bug 2.4.48: UTF-8 Multi-Byte Encodings in Screen Headers**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 2.6.
    - *Issue*: Section 2.6 establishes the VT100 & ASCII Terminal Encoding
      Mandate (UTF-8 Prohibition): all text and control output must strictly
      adhere to 7-bit ASCII (`0x20`–`0x7E`), and titles must use the ASCII
      hyphen-minus `-` (`0x2D`), e.g. `SE - Screen Editor`. Multi-byte UTF-8
      sequences (such as Unicode em-dash `—` `0xE2 0x80 0x94`) are strictly
      prohibited as they corrupt standard serial and retro VT100/VT102
      terminals.
      In `src/core/ui_render.c`:
      - Line 423: `"                  SE — Screen Editor                  "`
      - Line 554: `"               SE.COM — EDITOR MODE KEYS                "`
      - Line 586: `"        SE.COM — Screen Editor (Linux)        "`
      - Line 641: `"            SE — Configuration Manager            "`
      All use the 3-byte UTF-8 sequence `\xE2\x80\x94`.
    - *Required Fix*: Replace all occurrences of Unicode em-dash `—` in UI
      string literals with ASCII hyphen-minus `-` (`0x2D`) in
      `src/core/ui_render.c`.
    - *Resolution*: Replaced all occurrences of Unicode em-dash `—` across
      all workspace headers, Help screen, Splash screen, About screen, and
      Configuration Manager with canonical ASCII hyphen-minus `-` (`0x2D`),
      and eliminated non-ASCII section symbols from core modules to guarantee
      strict 7-bit ASCII conformance. Validated via
      `test_bug_2_4_48_utf8_prohibition` in `tests/test_linux_native.py`.
  - [x] **Bug 2.4.49: Off-by-One Barrier on Line Joins at Maximum Capacity**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 6.8, 10.1.
    - *Issue*: In `src/core/editor.c:216` (`do_backspace`) and
      `src/core/editor.c:275` (`do_delete`), the combined length barrier check
      for joining two lines is implemented as:
      `if (prev_len + g_active_line_len < MAX_INPUT_LINE_CHARS)`
      `if (g_active_line_len + next_len < MAX_INPUT_LINE_CHARS)`
      And in `src/core/block.c:317`:
      `if (g_active_line_len + copy_cnt < MAX_INPUT_LINE_CHARS)`
      Section 6.8 explicitly specifies:
      `If prev_len + cur_len <= MAX_INPUT_LINE_CHARS (1,000 chars):`
      `If cur_len + next_len <= MAX_INPUT_LINE_CHARS (1,000 chars):`
      Using `<` instead of `<=` inhibits joining when the combined line length
      is exactly 1,000 characters, prematurely rejecting valid joins that fit
      within `MAX_INPUT_LINE_CHARS`.
    - *Required Fix*: Change `< MAX_INPUT_LINE_CHARS` to `<=
      MAX_INPUT_LINE_CHARS` in `src/core/editor.c:216, 275` and
      `src/core/block.c:317`.
    - *Resolution*: Updated line join and tail join boundary checks from `<`
      to `<=` in `src/core/editor.c` (`do_backspace` and `do_delete`),
      `src/core/block.c` (`do_delete_block`), and `src/core/file_io.c`
      (`file_read_op`), enabling successful joins and loading up to exactly
      `MAX_INPUT_LINE_CHARS` (1,000 characters per Section 6.8). Validated via
      `test_bug_2_4_49_line_join_boundary` in `tests/test_linux_native.py`.
  - [x] **Bug 2.4.50: Single-Page Pagination Check in `test_bug_2_4_17`**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 7.5 (Single-Page Invariant).
    - *Issue*: `test_bug_2_4_17_tier1_file_workspaces_and_directory_scan` in
      `tests/test_linux_native.py:1256` asserted
      `"<PgUp>/<PgDn>=Page" in open_out` when scanning the repository directory
      (`< 60` entries, `total_pages == 1`), causing `make test-linux` to fail
      after `src/core/ui_browser.c:412` was updated to enforce the Single-Page
      Invariant (`if (total_pages > 1)`).
    - *Required Fix*: Update `test_bug_2_4_17` in `tests/test_linux_native.py`
      to assert that `<PgUp>/<PgDn>=Page` is suppressed when `total_pages == 1`.
    - *Resolution*: Updated `test_bug_2_4_17` in `tests/test_linux_native.py`
      to verify that `<PgUp>/<PgDn>=Page` is suppressed on single-page
      directories per Section 7.5.
  - [ ] **Bug 2.4.51: Splash Screen Layout, Menu Text, Alignment & Status Bar
    Non-Conformities**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 4.3, 7.2, 11.2, 14.1, 15.1.
    - *Issue*: In `src/core/ui_render.c:244-354` (`render_status_bar`) and
      `src/core/ui_render.c:395-563` (`show_splash_screen`), the `se-linux`
      Splash Screen exhibits multiple non-conformities with Section 7.2 and
      Section 15.1:
      1. *Missing `[^O]` and `[^S]` Labels*: `splash_lines[4]` and
         `splash_lines[5]` (lines 410–411) display
         `"   type   [O]              to open file"` and
         `"   type   [S]              to save file"`, omitting `or  [^O]` and
         `or  [^S]` mandated by Section 7.2 and Section 15.1.3.
      2. *Missing `[3] set native` Menu Option*: Although key `'3'` is handled
         in the event loop (lines 543–556) to activate `MODE_NATIVE`,
         `splash_lines` (lines 419–421) omits
         `type   [3]              set native` from the displayed menu
         (violating Section 7.2, 14.1, and 15.1.5).
      3. *Horizontal Column Alignment Discrepancy*:
         `render_tier1_workspace_screen(splash_lines, 21, 50)` sets
         `left_col = 16` (`14` spaces after `~` on `80x24`). With 3 leading
         spaces in `splash_lines[2..15]` and `splash_lines[17..20]`, both
         command lines (`type ...`) and diagnostic lines (`Active Screen ...`)
         start at 1-based Column 19 (`17` spaces after `~`), whereas canonical
         `SE.COM` (Section 15.1.2–15.1.3) places command lines at Column 23
         (`21` spaces after `~`) and diagnostic lines at Column 21 (`19` spaces
         after `~`, outdented 2 spaces left of `type`).
      4. *Prohibited Colon-Prefix Intercept & Undocumented Help Keys*:
         Lines 463–469 intercept `':'` and block waiting for a second keystroke
         (violating the Section 7.2 Instant Single-Keystroke Protocol), and
         line 527 dispatches undocumented `?`/`h`/`H`/`Ctrl+K` keys from the
         Splash Screen.
      5. *Inapplicable CP/M `RAM Drive (A:)` & `Max Lines` Diagnostics*:
         Lines 435–444 and 452–454 display CP/M `RAM Drive (A:)` and bounded
         `Max Lines` on Linux where hardware RAM drives and 16-bit bank limits
         do not apply (Section 15.1.5).
      6. *Status Bar Field 4 Static `^K: Editor keys` & `CPM  ` Format Label*:
         Under `#ifndef __CPM__`, `render_status_bar()` (line 277)
         unconditionally renders `" ^K: Editor keys |"` in Field 4 on the
         Splash Screen (violating Anti-Pattern #2 and Section 15.1.5, which
         require Field 4 on Splash/About to be blank `               | ` or
         show `Free: <N> KB`), and line 274 formats Field 3 as `"CPM  "`
         instead of canonical `"CP/M "`.
    - *Required Fix*: Update `show_splash_screen()` and `render_status_bar()`
      in `src/core/ui_render.c` to display `or  [^O]` and `or  [^S]`, include
      `type   [3]              set native` under `#ifndef __CPM__`, align
      horizontal padding with Section 15.1.2, remove the `':'` prefix
      intercept, adapt Linux diagnostic lines per Section 15.1.5, and blank
      Field 4 (or show `Free: <N> KB`) when `g_is_splash_screen` is active.
  - [ ] **Bug 2.4.52: About Screen Version, AI Attribution, Blank Row &
    Centering Non-Conformities**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 7.12, 14.6, 15.2.
    - *Issue*: In `src/core/ui_render.c:611-640` (`show_about_screen`) and
      `src/se_linux.c:29`:
      1. *Outdated Version & Date*: `s_about_lines[1]` displays
         `"version 1.1.0 (2026-10-09) (C)"` (and `se_linux.c:29` prints
         `v1.1.0`) instead of canonical `"version 1.1.3 (2026-10-17) (C)"`
         mandated by Sections 7.12, 14.6, and 15.2.4.
      2. *Outdated AI Attribution*: `s_about_lines[4]` displays
         `"Google Antigravity 2.19.1 & Gemini FLASH 3.8 high"` instead of
         canonical `"Google Antigravity 2.23.0 & Gemini 4 Argon Medium"`
         (Sections 7.12 & 15.2.3).
      3. *Missing Blank Row Between AI Attribution and MIT License*:
         `s_about_lines[5]` places `"Open source software under the MIT
         License"` immediately below the AI attribution line with no
         intervening blank `~` line, and places a trailing `""` at
         `s_about_lines[8]`. Per Section 7.12 and Section 15.2.2–15.2.3,
         Content Row 6 (Screen Row 13 in `80x24`) must be a blank `~` line,
         Content Row 7 is the MIT License, Content Row 8 is a blank `~` line,
         and Content Row 9 is `"Press any key to continue"`.
      4. *Off-by-One Per-Line Horizontal Centering*:
         `render_tier1_workspace_screen(s_about_lines, 9, 54)` (`left_col = 14`,
         12 spaces after `~`) combined with hardcoded leading spaces places
         `"by Dean Jenkins"` after 31 spaces (instead of canonical 32) and
         `"Press any key to continue"` after 26 spaces (instead of canonical
         27).
      5. *Status Bar & Cursor State*: `show_about_screen()` does not set
         `g_is_splash_screen = 1` and unconditionally calls
         `hal_console_show_cursor()` on exit before returning to the Splash
         Screen.
    - *Required Fix*: Update `s_about_lines` and `show_about_screen()` in
      `src/core/ui_render.c` (and version string in `src/se_linux.c`) to
      `"version 1.1.3 (2026-10-17) (C)"` and
      `"Google Antigravity 2.23.0 & Gemini 4 Argon Medium"`, insert the blank
      line at index 5 (removing the trailing blank line at index 8), center
      each line using `(g_active_cols - 1 - strlen(line)) / 2` spaces after
      `~`, and keep `g_is_splash_screen = 1` with cursor hidden on return to
      Splash.

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
  raw `termios` / `libc` terminal engine, line-slot `Vec<Vec<u8>>` document
  buffer, WordStar / SE keybindings, `SE.CFG` parser, dynamic plugin discovery.
- **Build Target**: `make se-rs` / `make se-rust` (produces `se-rs`, verified
  via `make test-rust`).
- **Status**: Active / 2 Open (Bugs 2.6.5, 2.6.6 Open; Bugs 2.6.1–2.6.4
  Resolved).
- **Active Defects & Issue Tracking**:
  - [x] **Bug 2.6.1: Line Feed (`\n`, `0x0A`) Not Accepted as Enter in Modals**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 7.5, Section 8.3.
    - *Issue*: Sending `4\n` (`0x0A`) in the `Goto Line` modal or File Browser
      failed to submit the input field because `hal_keyboard_get_key()` did not
      translate `KEY_LF` (`0x0A`) to `KEY_ENTER` (`0x0D`).
    - *Root Cause*: Raw `termios` disables `ICRNL`, so PTY callers sending `\n`
      deliver `KEY_LF` (`0x0A`), which `hal_keyboard_get_key()` in
      `ports/rust/src/hal_linux.rs` returned raw instead of normalizing to
      `KEY_ENTER` (`0x0D`).
    - *Resolution*: Normalized `KEY_LF` (`0x0A`) to `KEY_ENTER` (`0x0D`) in
      `hal_keyboard_get_key()` in `ports/rust/src/hal_linux.rs`. Validated via
      `test_bug_2_4_8_modal_dispatchers` in `tests/test_linux_native.py --rust`.
  - [x] **Bug 2.6.2: Attribute Reset Ordering Before Tilde on Empty Rows**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 5.1, Section 6.5.
    - *Issue*: Empty rows beyond EOF emitted `\x1b[2;1H\x1b[0m~\x1b[K` instead
      of `\x1b[0m\x1b[2;1H~\x1b[K`, breaking callers expecting `\x1b[2;1H~`
      at column 1 (`test_bug_2_4_14_viewport_col1_alignment`).
    - *Root Cause*: `render_line()` in `ports/rust/src/ui_render.rs` called
      `hal_console_set_attr(ATTR_NORMAL)` after `hal_console_locate(row, 1)`
      when rendering rows beyond EOF.
    - *Resolution*: Moved `hal_console_set_attr(ATTR_NORMAL)` before
      `hal_console_locate(screen_row, 1)` for rows beyond EOF in
      `ports/rust/src/ui_render.rs`. Validated via
      `test_bug_2_4_14_viewport_col1_alignment`.
  - [x] **Bug 2.6.3: Spurious 4-Space Padding Before File Browser Rules**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 7.5.
    - *Issue*: `ui_browser_workspace()` in `ports/rust/src/ui_browser.rs`
      rendered `~    ====...` on an `80x24` terminal instead of `~====...`
      (`test_bug_2_4_17_tier1_file_workspaces_and_directory_scan`).
    - *Root Cause*: `left_pad` was computed from `GRID_WIDTH` (`70`) instead
      of `80` (adding 4 spaces on an 80-column display), whereas
      `src/core/ui_browser.c` starts the rule immediately after `~` on an
      80-column display.
    - *Resolution*: Computed `left_pad` as `((active_cols - 80) / 2)` when
      `active_cols > 80` and `0` on 80-column displays in
      `ports/rust/src/ui_browser.rs`.
  - [x] **Bug 2.6.4: Missing Dynamic 120x40 Geometry Adaptation on Wide PTY**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 14.1.
    - *Issue*: Launching `se-rs` on a `120x40` PTY without `SE.CFG`
      (`test_bug_2_4_19_panning_edge_trigger_and_geometry`) retained `80x24`
      instead of adapting to `120x40`.
    - *Root Cause*: `hal_console_get_size()` in `ports/rust/src/hal_linux.rs`
      returned `(ROWS_24, COLS_80)` unconditionally whenever
      `cfg.screen_mode == MODE_80X24` instead of querying `TIOCGWINSZ` at
      startup and on `SIGWINCH`.
    - *Resolution*: Added `editor_apply_winch()` in `ports/rust/src/editor.rs`
      and invoked it in `editor_init()` and on `SIGWINCH` in
      `ports/rust/src/main.rs` to adapt to `120x40` when `TIOCGWINSZ` reports
      `cols >= 120 && rows >= 40`. Validated via
      `test_bug_2_4_19_panning_edge_trigger_and_geometry`.
  - [ ] **Bug 2.6.5: Non-Canonical Splash Screen Menu, Missing Commands (`[N]`,
    `[W]`, `[L]`, `[M]`) & Alignment**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 7.2, 14.1, 15.1.
    - *Issue*: In `ports/rust/src/ui_render.rs:387-564` (`show_splash_screen`)
      and `ports/rust/src/editor.rs:597-603`:
      1. *Spurious License Line on Splash Screen*: `splash_lines[2]` (line 439)
         renders `"SE is freely distributable under the MIT License"` and an
         extra blank row below the title, which is non-canonical on the Splash
         Screen (belongs on the About Screen).
      2. *Missing `[N]`, `[W]`, and `[L]` Commands & Handlers*: `splash_lines`
         and the `show_splash_screen()` event loop completely omit
         `type   [N]              to new file`,
         `type   [W]  or  [^W]    to close file`, and
         `type   [L]  or  [^L]    to goto line`.
      3. *Wrong Memory Info Hotkey (`[U]` Instead of `[M]`)*: Line 444 displays
         `"  type   [U]              for memory usage"` and line 512 dispatches
         `'u'`/`'U'` instead of canonical
         `type   [M]              for memory info` on `'m'`/`'M'`.
      4. *Merged `[P]` / `[^P]` Line, Extra `[H]` Line, and Non-Canonical
         Wording/Order*: Line 446 merges `[P]` and `[^P]` into
         `"  type   [P]  or  [^P]    for plugins"` instead of two separate
         lines (`[P] for plugins` and `[^P] for context plugin menu`),
         lines 442–445 use `"to open a file"`, `"to save a file"`, and
         `"for configuration"` instead of `"to open file"`, `"to save file"`,
         and `"to configure"`, line 450 adds a non-canonical
         `"  type   [H]  or  [?]     for help"` row, and `[A] for about` is
         placed out of order below `[1]`/`[2]`/`[3]`.
      5. *Horizontal Padding Discrepancy*:
         `render_centered_text_block(&splash_lines, 50)` sets
         `left_pad = (79 - 50) / 2 = 14` spaces after `~`. Both command lines
         (`"  type ..."`) and diagnostic lines (`"  Active Screen ..."`) start
         after `16` spaces (`Column 18`) instead of canonical `21` spaces
         (`Column 23`) for commands and `19` spaces (`Column 21`) for
         diagnostics (Section 15.1.2).
      6. *Non-Canonical Diagnostic Labels & Colon Intercept*: Lines 414–427 use
         non-canonical `RAM Drive (A:)` strings (`"Overwrite (Scratch)"`,
         `"Hibernate (Backed)"`, `"Disabled (TPA Only)"`) and omit
         `"On Demand"` for `Plugin System`; lines 468–474 block on `':'` prefix
         input; and `editor_handle_key()` in `ports/rust/src/editor.rs:597-603`
         has a fallback that exits splash mode on any key (including `Space`).
    - *Required Fix*: Update `show_splash_screen()` in
      `ports/rust/src/ui_render.rs` and `ports/rust/src/editor.rs` to render
      the canonical menu items and order (`E`, `N`, `O`/`^O`, `S`/`^S`,
      `W`/`^W`, `L`/`^L`, `A`, `M`, `P`, `^P`, `C`, `1`, `2`, `3`, `Q`),
      implement dispatch handlers for `N`, `W`/`^W`, `L`/`^L`, and `M`, align
      horizontal padding with Section 15.1.2, remove the `':'` intercept and
      spurious license/help lines, and adapt diagnostic rows per
      Section 15.1.4–15.1.5.
  - [ ] **Bug 2.6.6: About Screen Version, AI Attribution, Spurious
    `"created the code"` Row & Centering**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 7.12, 14.6, 15.2.
    - *Issue*: In `ports/rust/src/ui_render.rs:615-638` (`ABOUT_LINES` and
      `show_about_screen`) and `ports/rust/src/config.rs` (`SE_VERSION_STR`):
      1. *Outdated Version & Date*: `ABOUT_LINES[1]` displays
         `"version 1.1.0 (2026-10-09) (Rust)"` (and `SE_VERSION_STR` is
         `"v1.1.0"`) instead of canonical
         `"version 1.1.3 (2026-10-17) (Rust)"` (Sections 7.12, 14.6, 15.2.4).
      2. *Outdated AI Attribution*: `ABOUT_LINES[4]` displays
         `"Google Antigravity 2.19.1 & Gemini FLASH 3.8 high"` instead of
         canonical `"Google Antigravity 2.23.0 & Gemini 4 Argon Medium"`
         (Sections 7.12 & 15.2.3).
      3. *Spurious `"created the code"` Line on Content Row 6*:
         `ABOUT_LINES[5]` (Screen Row 13 in `80x24`) renders
         `"                  created the code                    "` instead of
         a blank `~` line separating the AI attribution from
         `Open source software under the MIT License` (Section 7.12 &
         Section 15.2.2–15.2.3).
      4. *Fixed-Width Block Padding Instead of Per-Line Centering*:
         `ABOUT_LINES` uses 54-char strings with trailing spaces rendered at
         `left_pad = 12`, placing `"by Dean Jenkins"` after 31 spaces (instead
         of 32) and `"Press any key to continue"` after 26 spaces (instead of
         27) and emitting trailing spaces before `\x1b[K`.
      5. *Cursor Shown on Return to Splash*: `show_about_screen()` calls
         `hal_console_set_cursor_vis(1)` on line 634 even when returning to the
         Splash Screen (`prev_splash == 1`).
    - *Required Fix*: Update `ABOUT_LINES` and `show_about_screen()` in
      `ports/rust/src/ui_render.rs` (and `SE_VERSION_STR` in
      `ports/rust/src/config.rs`) to display
      `"version 1.1.3 (2026-10-17) (Rust)"` and
      `"Google Antigravity 2.23.0 & Gemini 4 Argon Medium"`, replace
      `ABOUT_LINES[5]` (`"created the code"`) with an empty string `""`, center
      each line individually using `(active_cols - 1 - line.len()) / 2` spaces
      after `~`, and only restore cursor visibility when `prev_splash == 0`.

### 2.7 Profile 7: Linux Native Python Profile (`ports/python/`)
- **Target Platform**: Linux PC / Workstation (`x86_64`) and Raspberry Pi 4/5
  (`aarch64`) running Python 3.10+.
- **Core Technology**: Python 3 standard library package (`ports/python/se`),
  `termios` / `tty` raw terminal driver, object-based line buffer paging,
  `SE.CFG` reader/writer, modular Python plugins.
- **Build Target**: `make se-py` (verified via `make test-py`).
- **Status**: Active / 4 Open (Bugs 2.7.1–2.7.44, 2.7.46–2.7.63,
  2.7.65–2.7.71, 2.7.73–2.7.87, 2.7.92–2.7.94 Resolved; Bugs 2.7.45, 2.7.64,
  2.7.72 Rejected; 4 Open: 2.7.88–2.7.91).
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
  - [x] **Bug 2.7.42: Status Bar Field Squatting & Missing Block Indicators**:
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
    - *Resolution*: Preserved `^K: Editor keys |` unconditionally in Field 4
      and routed `[SEL]` (`block_active == 1`) and `[BLK LOCK]`
      (`block_active == 2`) indicators into Field 5 alongside horizontal pan
      flags with dynamic compact spacing in `render_status_bar` (`ui.py`).
      Validated via Step 33 in `test_editor.py`
      (`test_bug_2_7_42_status_bar_field4_invariance_and_block_indicators`).
  - [x] **Bug 2.7.43: Missing Tier 2 Block Operations Modal Dialog on Ctrl+K**:
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
    - *Resolution*: Implemented `show_block_operations_dialog()` in `modal.py`
      rendering the canonical 50x7 Tier 2 Block Operations modal dialog with
      live metrics (`Selection:` vs `Marked Block:`, char/line counts) and
      command options. Added `action_block_popup()` in `editor.py` and routed
      `KEY_CTRL_K` when `block_active > 0` directly to the modal dialog,
      supporting Lock, Clear, Copy, Move, Del, Save, and Dismiss actions.
      Validated via Step 34 in `test_editor.py`
      (`test_bug_2_7_43_block_operations_modal_dialog`).
  - [x] **Bug 2.7.44: Ctrl+K Prefix Command Polling Blocks Interactive Chords**:
    - *Symptom*: Pressing `Ctrl+K` followed by a secondary command key (`R` for
      File Insert, `S` for Block Save, `Q`/`X` for Exit) fails to execute the
      command and immediately falls back to displaying the Help workspace.
    - *Root Cause*: In `ports/python/se/editor.py:183-194`, secondary key
      polling queries `self.terminal.is_key_ready()` with the default
      `timeout=0.0`. In interactive terminal sessions, human keystrokes cannot
      arrive within 0.0 seconds of `Ctrl+K`, causing `is_key_ready()` to return
      `False` immediately and dispatching `self.action_help()`.
    - *Spec Reference*: `docs/UI_UX_DESIGN.md` Section 7.6, 7.8, and 10.
    - *Resolution*: Updated `KEY_CTRL_K` prefix chord polling in `editor.py` to
      query `self.terminal.is_key_ready(timeout=1.0)`, providing a 1.0-second
      interactive window for secondary key arrival (`R`, `S`, `Q`, `X`) and
      allowing `KEY_ESC` to cancel the chord gracefully without triggering Help.
      Validated via Step 35 in `test_editor.py`
      (`test_bug_2_7_44_ctrl_k_prefix_command_interactive_chords`).
  - [x] **Bug 2.7.45: WordStar Diamond Key Mapping [REJECTED / WONTFIX]**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 8.3, 10, 11.8.
    - *Disposition*: **REJECTED / WONTFIX** per architectural decision.
    - *Rationale*: WordStar diamond key mappings (`^S`, `^D`, `^E`, `^X`) are
      explicitly not supported across all editor workspaces, dialogs, and modal
      surfaces. Modal text input prompts adhere strictly to standard VT100/ANSI
      editing primitives, eliminating WordStar navigation by design.
  - [x] **Bug 2.7.46: WordStar Diamond Key Aliasing in Modal Inputs (Ctrl+S)**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 1, 8.3, 10, 11.8.
    - *Issue*: In `ports/python/se/modal.py:194` (`show_input`) and
      `modal.py:270` (`show_find_dialog`), `KEY_CTRL_S` is aliased alongside
      `KEY_LEFT` to cursor retreat (`elif k in (KEY_LEFT, KEY_CTRL_S):`).
      This violates the architectural prohibition against WordStar diamond
      aliasing in modal input loops (Anti-Pattern #8), where navigation must
      strictly be standard ANSI arrow keys.
    - *Resolution*: Removed `KEY_CTRL_S` from cursor navigation branches in
      `show_input` and `show_find_dialog` in `ports/python/se/modal.py`,
      restricting directional navigation to `KEY_LEFT` and standard editing
      keys. Validated via Step 36 in `test_editor.py`
      (`test_bug_2_7_46_wordstar_diamond_modal_exclusion`).
  - [x] **Bug 2.7.47: Line Capacity Limit Clamped to 120 Chars (vs 1,000)**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 6.6.
    - *Issue*: In `ports/python/se/buffer.py:9`, `MAX_LINE_LENGTH` is hardcoded
      to 120. `insert_char` rejects character insertion beyond 120 characters,
      `calc_visual_col` clamps visual columns to 120, and `update_pan` disables
      horizontal panning when `view_cols >= MAX_LINE_LENGTH` (e.g. 120x40),
      preventing lines from extending up to the canonical 1,000-char limit.
    - *Resolution*: Updated maximum line capacity constants to 1,000 characters
      (`MAX_LINE_CHARS = 1000`, `MAX_INPUT_LINE_CHARS = 1000`) and preserved
      `LINE_JOIN_LIMIT = 120` in `buffer.py`. Enabled horizontal panning
      in 120-column geometries. Validated via Step 2 and Step 14 in
      `test_buffer.py` (`test_bug_2_7_47_line_capacity_limit_and_panning`).
  - [x] **Bug 2.7.48: Missing File Not Found Modal Alert in Directory Browser**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 8.3 (Archetype A).
    - *Issue*: In `ports/python/se/editor.py:485`, attempting to open or insert
      a non-existent file causes `action_directory_browser` to return target
      and exit back to editor, where `action_open_file` and
      `action_insert_file` display a generic notification alert over the
      editor, discarding directory browser state and user input buffer.
    - *Resolution*: Added canonical 50x7 `show_file_not_found` modal alert
      in `ports/python/se/modal.py` and invoked it inside
      `action_directory_browser` on non-existent targets in open/insert modes,
      returning directly to the directory browser with input text and cursor
      preserved. Validated via Step 37 in `test_editor.py`
      (`test_bug_2_7_48_file_not_found_modal_alert`).
  - [x] **Bug 2.7.49: Overwrite File Modal Phrasing & Geometry Non-Conformity**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 8.3 (Archetype B).
    - *Issue*: In `ports/python/se/editor.py:572-576` (`action_save_file`) and
      `editor.py:609-613` (`action_block_save`), destination overwrite prompts
      use title `"Overwrite Warning"`, desc `"File already exists on disk."`,
      query `"Overwrite <filename>?"`, and 52x8 modal dimensions with an extra
      blank line.
    - *Resolution*: Implemented canonical 50x7 `show_overwrite_dialog` in
      `ports/python/se/modal.py` (title `"Overwrite File"`, desc `"Existing`
      `file contents will be lost"`, query `"File already exists. Overwrite?"`)
      and integrated into `action_save_file` and `action_block_save` in
      `editor.py`. Validated via Step 38 in `test_editor.py`
      (`test_bug_2_7_49_overwrite_modal_geometry_and_phrasing`).
  - [x] **Bug 2.7.50: Active Block Text Not Pre-filled in Find (Ctrl+F)**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 8.3 (Archetype C).
    - *Issue*: In `ports/python/se/editor.py:268-271`, `action_find()`
      unconditionally passes `initial_text=self.search_query` to
      `show_find_dialog`. If a block selection is active (`block_active > 0`),
      the highlighted text selection is not extracted or pre-filled into the
      Find input buffer.
    - *Resolution*: Implemented `get_selected_text()` on `DocumentBuffer` and
      updated `action_find()` in `ports/python/se/editor.py` to extract active
      selection text when `block_active > 0` and pre-fill it into
      `show_find_dialog`. Validated via Step 39 in `test_editor.py`
      (`test_bug_2_7_50_active_block_prefills_find_dialog`).
  - [x] **Bug 2.7.51: Find Text Modal Dialog Geometry & Layout Discrepancies**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 8.3 (Archetype C).
    - *Issue*: In `ports/python/se/modal.py:219-245`, `show_find_dialog` builds
      an 8-row x 52-column modal box with an extraneous empty row between the
      input line and action options, rather than the canonical 50-col x 7-row
      layout.
    - *Resolution*: Updated `show_find_dialog` in `ports/python/se/modal.py`
      to canonical 50-col x 7-row compact geometry without empty row padding.
      Validated via Step 18 and Step 40 in `test_editor.py`
      (`test_bug_2_7_51_find_dialog_canonical_50x7_geometry`).
  - [x] **Bug 2.7.52: Uncanonical Prompt Syntax in action_new_file()**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 8.3 (Archetype B), 11.8.
    - *Issue*: In `ports/python/se/editor.py:658-662`, `action_new_file()`
      prompts with `desc="Discard current modifications for new document?"`
      and `query="Discard edits? [y/n]:"`, violating the prohibition against
      legacy slash delimiters and non-standard query phrasing
      (Anti-Pattern #8).
    - *Resolution*: Updated `action_new_file()` in `ports/python/se/editor.py`
      to use canonical Archetype B confirmation modal dialog: title `"Unsaved`
      `Modifications"`, desc `"Any unsaved edits will be lost if discarded."`,
      query `"Save changes?"`, and options
      `"[Y]es      [N]o      [ESC]=Cancel"`.
      Validated via Step 41 in `test_editor.py`
      (`test_bug_2_7_52_canonical_new_file_prompt`).
  - [x] **Bug 2.7.53: Splash Screen Over-Capacity Height & Colon Commands**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 5.2, 7.1, 7.2.
    - *Issue*: In `ports/python/se/editor.py:766-790`, `action_splash_screen`
      defines 23 content lines. On standard 80x24 displays (`AvailRows = 23`),
      `compute_centering` yields `TopRow = 1`, filling all 23 available screen
      rows with text and completely eliminating column 0 tilde margin rows.
      Additionally, splash screen dispatch lacks colon-prefixed command syntax
      (`:e`, `:o`, `:s`, `:c`, `:p`, `:?`, `:q`) defined in Section 7.2.
    - *Resolution*: Restructured splash screen content to canonical 14 lines x
      50 columns in `ports/python/se/editor.py`, restoring column 0 tildes on
      rows 1..4 and 19..23 on 80x24 displays (`top_row = 5`). Implemented colon
      prefix command intercept (`:e`, `:o`, `:s`, `:c`, `:p`, `:?`, `:q`) and
      silent rejection of non-entry keys (Space bar, arrow keys, unassigned).
      Validated via Step 42 in `test_editor.py`
      (`test_bug_2_7_53_splash_screen_dimensions_and_colon_commands`).
  - [x] **Bug 2.7.54: Inversion of Splash Screen Geometry Hotkeys (1 vs 2)**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 2.1, 7.2, 14.1.
    - *Symptom*: Pressing hotkey `1` on the Tier 1 Splash screen sets 120x40
      mode, and pressing hotkey `2` sets 80x24 mode.
    - *Root Cause*: In `ports/python/se/editor.py:818-827`, hotkey `1` assigns
      `SCREEN=120x40` and hotkey `2` assigns `SCREEN=80x24`. In
      `docs/UI_UX_DESIGN.md` Section 7.2, `1` is defined as Option 1 (80x24
      classic terminal mode, `DO_SET_80X24`), and `2` is defined as
      Option 2 (120x40 modern terminal mode, `DO_SET_120X40`). The hotkeys
      are inverted.
    - *Resolution*: In `ports/python/se/editor.py`, corrected splash hotkeys so
      `1` selects 80x24 (`DO_SET_80X24`) and `2` selects 120x40
      (`DO_SET_120X40`) conforming with Section 7.2. Validated via Step 43 in
      `test_editor.py` (`test_bug_2_7_54_splash_geometry_hotkeys_inversion`).
  - [x] **Bug 2.7.55: Missing Option 3 (Native Mode) on Splash Screen**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 2.1, 7.2, 14.1.
    - *Symptom*: The user has no hotkey or option on the Splash screen to
      select or revert to Native dynamic host terminal dimensions.
    - *Root Cause*: `ports/python/se/editor.py:818-834` only intercepts keys
      `1` and `2`, silently rejecting key `3` under non-entry key filtering.
      Section 7.2 explicitly mandates Option 3 (`DO_SET_NATIVE`, hotkey `3`)
      when native screen size is supported (e.g. Linux native Python port) to
      revert geometry to auto-detected host terminal size.
    - *Resolution*: In `ports/python/se/editor.py`, bound hotkey `3` in
      `action_splash_screen` to `DO_SET_NATIVE`, setting `SCREEN=NATIVE`,
      querying dynamic host terminal size via `update_geometry()`, and
      re-rendering. Validated via Step 44 in `test_editor.py`
      (`test_bug_2_7_55_splash_option3_native_mode`).
  - [x] **Bug 2.7.56: Missing Screen Clearance Prior to Geometry Switching**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 2.1, 7.2, 14.1.
    - *Symptom*: Switching screen geometry leaves stale column tildes, clipped
      characters, margin remnants, and ghost status bar lines on the screen.
    - *Root Cause*: In `ports/python/se/editor.py:818-827` (splash screen) and
      `editor.py:896-902` (config screen), terminal dimensions are updated
      without clearing the terminal screen. Section 2.1, 7.2, and 14.1 mandate
      that the screen must be explicitly cleared (emitting `\x1b[2J\x1b[H` /
      `TERM_INIT`) prior to switching dimensions.
    - *Resolution*: In `ports/python/se/editor.py`, invoked
      `self.terminal.term_init()` prior to switching dimensions in both
      `action_splash_screen` (hotkeys 1, 2, 3) and `action_config_screen`
      (option 1), clearing the screen to prevent visual debris. Validated via
      Step 45 in `test_editor.py`
      (`test_bug_2_7_56_screen_clear_on_geometry_switch`).
  - [x] **Bug 2.7.57: Config Subsystem Lacks NATIVE Screen Geometry Support**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 2.1, 7.4, 14.1.
    - *Symptom*: Setting `SCREEN=NATIVE` in `SE.CFG` or via `config.set()`
      evaluates to fixed `(120, 40)` instead of native host terminal size.
    - *Root Cause*: In `ports/python/se/config.py:35-50`, `screen_geometry`
      only checks if `SCREEN == "80X24"` and falls back to `(120, 40)` for all
      other values, lacking support for Option 3 (`NATIVE`).
    - *Resolution*: In `ports/python/se/config.py`, added `NATIVE` screen
      geometry handling to `Config.screen_geometry`, querying dynamic
      terminal dimensions via `os.get_terminal_size()` with safe fallback, and
      added `is_native_screen` property. Validated via Step 5 in
      `test_config.py` (`test_native_screen_geometry`).
  - [x] **Bug 2.7.58: Configuration Manager Lacks Native Screen Mode Toggle**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 2.1, 7.4, 14.1.
    - *Symptom*: Configuration Manager option 1 only toggles between 80x24 and
      120x40, preventing selection of Native dynamic terminal mode.
    - *Root Cause*: In `ports/python/se/editor.py:896-902`, option 1 performs
      a binary toggle between `80x24` and `120x40`, omitting Native mode.
    - *Resolution*: In `ports/python/se/editor.py`, updated
      `action_config_screen` option 1 to cycle through `80x24`, `120x40`, and
      `Native` modes (with clearance via `term_init()`). Displays `(Native)`
      indicator on geometry line when native mode is active. Validated via
      Step 46 in `test_editor.py`
      (`test_bug_2_7_58_config_screen_native_mode_toggle`).
  - [x] **Bug 2.7.59: Startup Raw Mode Overrides Configured Geometry**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 14.1.
    - *Symptom*: Setting `SCREEN=80x24` or `SCREEN=120x40` in `SE.CFG` is
      overridden on startup, forcing editor dimensions to the host window
      size.
    - *Root Cause*: In `ports/python/se/terminal.py:124`, `enter_raw_mode()`
      unconditionally calls `self.update_geometry()`, which queries
      `os.get_terminal_size()` and clobbers `self.cols` and `self.rows`,
      ignoring the fixed geometry configured in `SE.CFG`.
    - *Resolution*: In `ports/python/se/terminal.py` and `editor.py`, added
      `fixed_geometry` support to `Terminal`, initialized from
      `Config.is_native_screen` on startup, and updated upon splash/config
      geometry changes. `update_geometry()` and `enter_raw_mode()` preserve
      configured fixed dimensions (`80x24` or `120x40`) when `fixed_geometry`
      is active. Validated via Step 47 in `test_editor.py`
      (`test_bug_2_7_59_startup_geometry_emulation_preserved`).
  - [x] **Bug 2.7.60: Intermediary Clipboard & Missing In-Place Block Ops**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 9.3, Section 10.
    - *Issue*: Section 9.3 mandates Direct In-Place Block Manipulation across
      all SE implementations and strictly prohibits intermediary clipboard
      buffers. All block manipulations operate directly between the marked
      block and active cursor in document memory. `Ctrl+C` must copy marked
      block directly to cursor (`DO_COPY_BLOCK`), `Ctrl+X` must move marked
      block directly to cursor (`DO_MOVE_BLOCK`), and legacy `Ctrl+V` pasting
      aliases are removed.
    - *Root Cause*: In `ports/python/se/buffer.py:91`, `DocumentBuffer`
      maintains `self.clipboard: str = ""`. `copy_block()` and `cut_block()`
      copy to this detached buffer, `paste_block()` pastes from it, and
      `ports/python/se/editor.py:168-175` binds `Ctrl+C`, `Ctrl+X`, and
      `Ctrl+V` to clipboard primitives.
    - *Resolution*: Implemented `is_cursor_in_block()`,
      `copy_block_to_cursor()`, and `move_block_to_cursor()` on
      `DocumentBuffer` in `buffer.py`. Updated `editor.py` to route
      `KEY_CTRL_C` to `copy_block_to_cursor()` and `KEY_CTRL_X` to
      `move_block_to_cursor()`, mapped `KEY_CTRL_V` to `page_down()`, and
      updated `action_block_popup()` to invoke in-place manipulation. Validated
      via Step 15 in `test_buffer.py` and Step 2 and Step 48 in `test_editor.py`
      (`test_bug_2_7_60_direct_in_place_block_ops`).
  - [x] **Bug 2.7.61: Non-Canonical Splash Template & Prohibited Prompt**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 2.7, 7.2.
    - *Issue*: Section 7.2 mandates the 21-line canonical `SE.COM` splash
      screen template (`type [E] or [Enter] to edit`, etc.) with instant
      single-keystroke dispatch across all SE variants, and strictly prohibits
      interactive prompts (such as `Enter option: _` or `Enter choice: _`).
      Unassigned keys (including `ESC` and Space) must be silently rejected.
    - *Root Cause*: In `ports/python/se/editor.py:757-772`,
      `action_splash_screen()` renders an obsolete 14-line layout using colon
      command syntax (`:e to edit`, etc.) and displays prohibited prompt
      `"Enter choice: "` on line 771. Furthermore, line 789 improperly allows
      `KEY_ESC` to enter the editor workspace.
    - *Resolution*: Updated `action_splash_screen()` in `editor.py` to render
      the canonical 21-line `SE.COM` template without prompt strings, removed
      colon command parsing in favor of instant single-keystroke dispatch, and
      silently ignored unassigned keystrokes (including `KEY_ESC`). Validated
      via Step 14, Step 42, and Step 49 in `test_editor.py`
      (`test_bug_2_7_61_canonical_21_line_splash_template`).
  - [x] **Bug 2.7.62: Missing Predominant Language on About Screen**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 7.12, 14.6; `TODO.md`
      Bug 2.1.14.
    - *Issue*: Section 7.12 and 14.6 mandate that all SE variants display the
      programming language predominantly used to create that specific port
      appended to the version number and build date line on the Tier 1 About
      screen: `version 1.1.0 (2026-10-09) (Python)`.
    - *Root Cause*: In `ports/python/se/editor.py:699`, `action_about()`
      displays `version 1.1.0 (2026-10-09)` without ` (Python)`.
    - *Resolution*: Updated the version string in `action_about()` in
      `editor.py` to `version 1.1.0 (2026-10-09) (Python)`. Validated via
      Step 16 and Step 50 in `test_editor.py`
      (`test_bug_2_7_62_about_screen_predominant_language`).
  - [x] **Bug 2.7.63: Config Manager Inverted Layout & Prohibited Prompt**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 2.6, 7.4.
    - *Issue*: Section 7.4 mandates a canonical 5-option hotkey layout:
      1. Screen Geometry, 2. RAM Drive Mode, 3. Max Doc Lines, 4. Tab Width,
      and 5. Plugin Manager, with prompt line `[1-5]=Toggle Option
      [S]=Save Config  [ESC]=Exit`. An `Enter option: _` prompt line is
      strictly prohibited, and titles must use ASCII hyphen `-`.
    - *Root Cause*: In `ports/python/se/editor.py:895-906`,
      `action_config_screen()` defines only 4 options with inverted numbering
      (2 is Tab Width, 3 is Max Line Capacity, 4 is RAM Drive Mode; option 5
      Plugin Manager is missing), uses Unicode em-dash in title
      (`SE — Configuration Manager`), displays prohibited `"Enter option: "`,
      and shows non-standard navigation options.
    - *Resolution*: Reorganized `action_config_screen()` in `editor.py` to
      match the canonical 5-option layout, removed `Enter option:`, added
      option 5 Plugin Manager toggle, conformed title to ASCII hyphen
      (`SE - Configuration Manager`), and added canonical status/footer.
      Validated via Step 7 and Step 51 in `test_editor.py`
      (`test_bug_2_7_63_canonical_5_option_config_screen`).
  - [x] **Bug 2.7.64: Field 4 Status Bar Placement [REJECTED / WONTFIX]**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 4.3, 4.4.
    - *Disposition*: **REJECTED / WONTFIX** per architectural decision.
    - *Rationale*: The claim that `docs/UI_UX_DESIGN.md` assigns block mode cues
      (`[SEL]`, `[BLK LOCK]`) to Field 4 is factually false. Section 4.3
      explicitly defines Field 4 as persistent help key hint
      (`^K: Editor keys |`) and places mode indicators (`[SEL]`, `[BLK LOCK]`)
      and horizontal panning (`[Pan +{pan_col}]`) in Field 5 alongside cursor
      coordinates. `ports/python/se/ui.py` already conforms 100% to Section 4.3;
      routing mode indicators into Field 4 would clobber Field 4 and violate
      Anti-Pattern #1 (Status Bar Squatting / Context Clobber).
  - [x] **Bug 2.7.65: Sticky Column Clamping Retreats on Expanded Tabs**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 6.2, 6.4.
    - *Issue*: Section 6.2 and 6.4 mandate snap-forward vertical alignment
      clamping (`ADJUST_COL_TO_TARGET`): if sticky `TARGET_COL` falls across
      an expanded tab (`vis_acc < TARGET_COL < vis_acc + spaces`), the cursor
      must snap forward to the character boundary directly following the tab
      (`vis_acc + spaces`) to stay adjacent to indented code rather than
      retreating to the margin.
    - *Root Cause*: In `ports/python/se/buffer.py:59-65`
      (`adjust_col_to_target`), the loop executes
      `if vis_acc + spaces > target_col: break`, halting alignment before the
      tab and retreating the cursor to the margin.
    - *Resolution*: Updated `adjust_col_to_target()` in `buffer.py` to advance
      `vis_acc += spaces` and `char_idx += 1` through the tab when
      `vis_acc < target_col` per Section 6.4, snapping forward to the character
      directly following the tab. Validated via Step 10 and Step 16 in
      `test_buffer.py` (`test_bug_2_7_65_snap_forward_tab_alignment`).
  - [x] **Bug 2.7.66: Premature Line Join Inhibition at 120 Columns**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 6.5, 6.6, 10.
    - *Issue*: Section 6.5, 6.6, and Section 10 specify that Backspace
      (at col 0) and Delete (at end of line) line joins are permitted up to
      `MAX_INPUT_LINE_CHARS` (1,000 characters).
    - *Root Cause*: In `ports/python/se/buffer.py:12, 220, 247`,
      `LINE_JOIN_LIMIT = 120`. Joins are prematurely blocked when combined
      length exceeds 120 columns even though line buffer capacity supports up
      to 1,000 characters (`MAX_LINE_CHARS = 1000`).
    - *Resolution*: Updated `LINE_JOIN_LIMIT = MAX_INPUT_LINE_CHARS` (1,000)
      in `buffer.py`, allowing line joins via Backspace and Delete up to the
      mandated 1,000-character line capacity limit. Validated via Step 14
      and Step 17 in `test_buffer.py`
      (`test_bug_2_7_66_line_join_limit_1000_chars`).
  - [x] **Bug 2.7.67: Inverted Default File Format & SE.CFG Persistence**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 7.7, 13.2; `TODO.md`
      Bug 2.1.15.
    - *Issue*: Section 7.7 specifies that new documents created on Linux/POSIX
      hosts (`se-linux`, `se-py`, `se-rs`) must default to host native text
      format (`LF`, `format_cpm = False`). Furthermore, Section 7.7 and
      Section 13.2 mandate that file line ending format is governed
      per-document and is NOT an `SE.CFG` setting.
    - *Root Cause*: In `ports/python/se/buffer.py:90`, `DocumentBuffer.__init__`
      defaults `self.format_cpm: bool = True` (`CRLF`). In
      `ports/python/se/editor.py:582`, `action_save_file()` persists
      `self.config.set("FORMAT", ...)` to `SE.CFG`.
    - *Resolution*: Defaulted `format_cpm = False` (Linux native LF) in
      `DocumentBuffer.__init__` in `buffer.py`. Removed
      `self.config.set("FORMAT", ...)` in `editor.py` so line ending format is
      not persisted to `SE.CFG`. Validated via Step 52 in `test_editor.py`
      (`test_bug_2_7_67_default_lf_and_decouple_config_save`).
  - [x] **Bug 2.7.68: Trailing Byte Leakage on Unrecognized Escape Sequences**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 10; `TODO.md` Bug 2.1.13,
      Bug 2.4.32.
    - *Issue*: Section 10 Anti-Leakage Invariant dictates that if an incomplete
      or unrecognized escape sequence is received (e.g. unhandled function keys
      F5–F12 emitting `\x1b[15~`..`\x1b[24~`, mouse reporting, bracketed
      paste), the input decoder must drain and discard all sequence bytes
      atomically until the sequence terminator (`~`, alpha) or timeout.
      Trailing characters must NEVER leak into console stream as keystrokes.
    - *Root Cause*: In `ports/python/se/terminal.py:280-294`, when an
      unrecognized CSI sequence like `\x1b[15~` arrives, `c2` is `'1'` and
      `c3` is `'5'`. Because `c3 != '~'`, `get_key()` immediately returns
      `KEY_ESC`, leaving trailing `~` in stdin, which leaks as a normal typed
      character on the next keystroke and corrupts the document buffer.
    - *Resolution*: Implemented `_drain_csi()` in `terminal.py` draining all
      intermediate parameter bytes and sequence terminators (0x40..0x7E) upon
      unrecognized or extended CSI escape sequences, preventing trailing byte
      leakage into console input. Validated via Step 10 in `test_terminal.py`
      (`test_bug_2_7_68_drain_unrecognized_escape_sequences`).
  - [x] **Bug 2.7.69: Full-Screen Workspace Redraw on Typing Keystrokes**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 7.5, 7.7, 7.10, 8.3;
      `TODO.md` Bug 2.8.1.
    - *Issue*: Section 7.10 strictly prohibits full-screen re-rendering
      (`render_directory_workspace`) upon receiving individual text input
      keystrokes in Tier 1 directory workspaces. Typing characters,
      backspaces, and cursor navigation must echo in-place or update only the
      bracketed prompt row; full-screen redraws are strictly reserved for entry
      and page changes.
    - *Root Cause*: In `ports/python/se/editor.py:458-529`
      (`action_directory_browser`), every single keystroke triggers
      `self.renderer.render_directory_workspace(...)`, redrawing the entire
      screen, file grid, and status bar on every character entered.
    - *Resolution*: Implemented `render_directory_prompt()` in `ui.py` and
      updated `action_directory_browser()` in `editor.py` to redraw only the
      prompt row during typing, character deletions, and cursor navigation,
      restricting full workspace redraws to initial entry, pagination,
      and pattern updates. Validated via Step 53 in `test_editor.py`
      (`test_bug_2_7_69_directory_browser_in_place_prompt_echoing`).
  - [x] **Bug 2.7.70: Obsolete Help Screen Key Mappings & Unicode Em-Dash**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 2.6, 7.3, 10; `TODO.md`
      Bug 2.4.39.
    - *Issue*: Section 7.3 specifies the canonical Help Screen layout:
      `PgUp / PgDn : Page Up / Down`, `Ctrl+C: Copy Block to Cursor`,
      `Ctrl+X: Move Block to Cursor`, `Ctrl+D: Delete Block`. Section 2.6
      prohibits Unicode em-dash `—` (must use ASCII hyphen `-`).
    - *Root Cause*: In `ports/python/se/editor.py:368-384`, `action_help()`
      displays obsolete references: `Ctrl+U / Ctrl+V: Page Up / Down`,
      `Ctrl+V: Paste Block`, `Ctrl+C: Copy Block` (without target),
      `Ctrl+X: Cut Block`, and uses Unicode em-dash in header:
      `"SE.COM — EDITOR MODE KEYS"`.
    - *Resolution*: Updated `action_help()` in `editor.py` to canonical Help
      Screen key mappings (`PgUp / PgDn : Page Up / Down`,
      `Ctrl+C: Copy Block to Cursor`, `Ctrl+X: Move Block to Cursor`,
      `Ctrl+D: Delete Block`), removed obsolete paste/cut mappings, and
      conformed title to ASCII hyphen (`SE - EDITOR MODE KEYS`). Validated
      via Step 19 and Step 54 in `test_editor.py`
      (`test_bug_2_7_70_canonical_help_screen_keys`).
  - [x] **Bug 2.7.71: Startup Screen Geometry Inversion in Config Defaults**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 2.1, 13.2; `TODO.md`
      Bug 2.1.2.
    - *Issue*: Section 2.1 and Section 13.2 mandate `80x24` as the universal
      baseline standard and default screen geometry across all SE
      implementations (`SCREEN=80X24`).
    - *Root Cause*: In `ports/python/se/config.py:16`,
      `DEFAULT_SCREEN = "120X40"`, causing editor instances without `SE.CFG`
      to default to 120x40 wide console mode rather than canonical 80x24.
    - *Resolution*: Updated `DEFAULT_SCREEN = "80X24"` in `config.py`,
      conforming default startup console geometry to canonical 80x24 across
      unconfigured instances. Validated via Step 1, Step 4, and Step 6 in
      `test_config.py` and Step 28 and Step 55 in `test_editor.py`
      (`test_bug_2_7_71_startup_screen_geometry_defaults`).
  - [x] **Bug 2.7.72: Default Tab Width Inversion in Config Defaults**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 6.2, 7.4, 13.2; `TODO.md`
      Bug 2.4.38; `src/se.asm:4620`.
    - *Status*: REJECTED / INVALID (WONTFIX).
    - *Reason for Rejection*:
      1. Default tab stop spacing across all SE variants (`SE.COM`, `se-linux`,
         `se-py`, `SEC.COM`) is canonically 8 columns, configurable to 4. In
         `SE.COM` (`src/se.asm`), `CFG_TAB_WIDTH: DB 8` has always defined 8
         as the default. Furthermore, Section 7.4 (Configuration Manager) and
         Section 13.2 (`TAB / TABS Default: 8`) define 8 columns.
      2. The statement in Section 6.2 mentioning "default 4 columns" was an
         erroneous specification defect that contradicted `SE.COM`, Section 7.4,
         and Section 13.2. Section 6.2 has been corrected to codify 8 columns as
         the universal default across all SE variants.
      3. `ports/python/se/config.py` correctly defines `DEFAULT_TAB_WIDTH = 8`
         and fallback `8`. In addition, `ports/python/se/buffer.py` default
         parameter has been updated to 8 for full architectural parity.
  - [x] **Bug 2.7.73: Status Bar Field 1 Overflow on Filenames >13 Characters**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 4.3; `src/core/ui_render.c`.
    - *Issue*: Section 4.3 defines Field 1 of the Universal Status Bar as a
      fixed 18-character section (`| %-14.14s |`).
    - *Root Cause*: In `ports/python/se/ui.py:53`, `name_field` was formatted
      using `f"| {raw_name:<14} |"` without a maximum precision specifier.
      When opening files with names exceeding 13 characters, Field 1 expanded
      beyond 18 columns and pushed Field 5 (`Col N`, `[Pan +40]`, `[SEL]`,
      `[BLK LOCK]`) past column 80, where `status_text = core[:cols]` clipped
      the right side of the status bar.
    - *Resolution*: Updated `name_field` in `render_status_bar()` in `ui.py` to
      `f"| {raw_name:<14.14} |"`, strictly bounding Field 1 to 18 characters
      and preserving Field 5 indicators across 80-column viewports. Validated
      via Step 56 in `test_editor.py`
      (`test_bug_2_7_73_status_bar_long_filename_truncation`).
  - [x] **Bug 2.7.74: 1.0-Second Blocking Lag on Ctrl+K Help Screen Dispatch**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 7.3, 10.
    - *Issue*: Pressing `Ctrl+K` with no active block freezes the editor UI for
      1,000ms before rendering the Help screen, and swallows any dismissal key
      pressed within that 1-second window. Furthermore, the Help screen lacked
      the canonical `Arrow Keys` navigation label.
    - *Root Cause*: In `ports/python/se/editor.py:185`, `dispatch_key()` polled
      `self.terminal.is_key_ready(timeout=1.0)` waiting 1.0 second for legacy
      WordStar `^K` two-key chords before invoking `action_help()`.
    - *Resolution*: Reduced the `Ctrl+K` lookahead poll timeout in
      `dispatch_key()` in `editor.py` from `1.0`s to `0.1`s (100ms) and
      included `Arrow Keys` in `action_help()`. Validated via Step 35 and
      Step 57 in `test_editor.py`
      (`test_bug_2_7_74_ctrl_k_immediate_help_dispatch`).
  - [x] **Bug 2.7.75: Archetype D Plugin Palette Frame Width & Slot Order**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 8.4 (Archetype D).
    - *Issue*: The Plugin Palette (`Ctrl+P`) rendered a 46-column modal box
      (`+--------------------------------------------+`) instead of the
      canonical 50-column Archetype D frame
      (`+------------------------------------------------+`), and listed
      built-in plugins alphabetically (`BEAUTIFY`, `ROT13`, `WORDCNT`) instead
      of the canonical slot sequence (`1. ROT13`, `2. WORDCNT`,
      `3. BEAUTIFY`).
    - *Root Cause*: `show_menu()` in `ports/python/se/modal.py` set
      `width = 46` instead of `50`, and `discover_plugins()` in
      `ports/python/se/plugin.py` used `sorted(os.listdir(...))` for built-in
      plugins.
    - *Resolution*: Updated `show_menu()` in `modal.py` to use a 50-column
      minimum frame width (`width = 50`) and updated `discover_plugins()` in
      `plugin.py` to load built-in plugins in canonical order (`rot13.py`,
      `wordcnt.py`, `beautify.py`). Validated via Step 58 in `test_editor.py`
      (`test_bug_2_7_75_plugin_palette_canonical_width_and_order`).
  - [x] **Bug 2.7.76: Config Manager Option 5 Toggle Cycle & Save Flow**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 7.4, 13.2.
    - *Issue*: Pressing `5` in the Configuration Manager toggled Plugin Manager
      directly from `Autoload` to `Disabled` (omitting `Demand`), and pressing
      `S` opened a blocking modal pop-up instead of immediately saving to
      `SE.CFG` and refreshing the `Config Status: Loaded from SE.CFG` header.
    - *Root Cause*: `action_config_screen()` in `ports/python/se/editor.py`
      only handled two states (`AUTOLOAD` and `DISABLED`) for `PLUGIN` and
      invoked `self.modal.show_notification()` after
      `self.config.save_config()`.
    - *Resolution*: Updated `action_config_screen()` in `editor.py` to cycle
      Option 5 through all three canonical states (`Autoload` -> `Demand` ->
      `Disabled` -> `Autoload`) and save `SE.CFG` immediately on `S`/`s`
      without a blocking modal. Validated via Step 51 and Step 59 in
      `test_editor.py` (`test_bug_2_7_76_config_plugin_toggle_cycle_and_save`).
  - [x] **Bug 2.7.77: Splash Screen 120x40 Active Screen Diagnostic Label**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 7.2.
    - *Issue*: Switching to `120x40` geometry on the Splash screen rendered
      `Active Screen : [120x40 (Wide Console)]` instead of the canonical
      `Active Screen : [120x40 (Modern Default)]` diagnostic string.
    - *Root Cause*: `action_splash_screen()` in `ports/python/se/editor.py:783`
      formatted `geom_tag` with `(Wide Console)`.
    - *Resolution*: Updated `action_splash_screen()` in `editor.py` to format
      120x40 mode as `120x40 (Modern Default)`. Validated via Step 60 in
      `test_editor.py`
      (`test_bug_2_7_77_splash_active_screen_diagnostic_labels`).
   - [x] **Bug 2.7.78: Insert Key Not Decoded; Overwrite Mode Missing**:
     - *Reference*: `docs/KEYBINDINGS.md`, `docs/UI_UX_DESIGN.md` Section 4.3.
     - *Issue*: `Insert` (`ESC [ 2 ~`, `ESC [ 2 ; 5 ~`, `ESC [ L`, `ESC [ @`)
       was ignored, so Overwrite mode could not be entered and Field 4 never
       showed ` Overwrite mode  |`.
     - *Root Cause*: `terminal.py` had no `KEY_INSERT`, and
       `DocumentBuffer` had no overwrite state.
     - *Resolution*: Added `KEY_INSERT` decoding in `terminal.py`,
       `overwrite_mode` and in-place replacement in `buffer.insert_char()`,
       and the Field 4 label in `render_status_bar()`. Validated via Step 60
       of `tests/test_editor_headless.py --python`.
   - [x] **Bug 2.7.79: Shift+Arrow and Ctrl+Home/End Not Decoded**:
     - *Reference*: `docs/KEYBINDINGS.md`.
     - *Issue*: `ESC [ 1 ; 2 A/B/C/D` did not start or extend a selection and
       `ESC [ 1 ; 5 H/F` did not jump to the top or bottom of the document.
     - *Root Cause*: `terminal.py` only decoded unmodified CSI arrows and
       Home/End.
     - *Resolution*: Decoded modifier 2 arrows as `SHIFT_*` keys and modifier
       5 Home/End as `JUMP_TOP`/`JUMP_BOTTOM`; handled in `dispatch_key()`.
       Validated via Steps 24 and 39 of the headless `--python` run.
   - [x] **Bug 2.7.80: Block Copy Rejected at Block Start**:
     - *Reference*: `docs/UI_UX_DESIGN.md` Section 9 (Block Operations).
     - *Issue*: `Ctrl+C` with the cursor exactly at the block start column
       was ignored instead of inserting a copy before the block.
     - *Root Cause*: `copy_block_to_cursor()` treated the block start as
       inside the half-open range.
     - *Resolution*: Allowed the copy when the cursor equals `(r1, c1)` and
       shifted the block bounds. Validated via Step 38.
   - [x] **Bug 2.7.81: Redundant Redraw on No-Op Ctrl+C / Ctrl+X**:
     - *Issue*: `Ctrl+C` or `Ctrl+X` with no active block, or with the cursor
       inside the block, repainted the whole screen.
     - *Resolution*: `dispatch_key()` now sets `_skip_render` for these
       no-ops. Validated via Steps 36 and 40.
   - [x] **Bug 2.7.82: Find / Find Next Start Position and Wrap**:
     - *Reference*: `docs/UI_UX_DESIGN.md` Section 11.
     - *Issue*: The first `Ctrl+F` search skipped a match under the cursor
       and did not wrap; `Ctrl+N` after the last match did not report
       `Search completed.`.
     - *Resolution*: `action_find()` searches from the cursor and wraps;
       `action_find_next()` searches from the next column and reports
       `Search completed.` once a match has been found. Validated via
       Steps 48-50 and Step 45.
   - [x] **Bug 2.7.83: Failed Find Kept Query, Block and Moved Cursor**:
     - *Reference*: `src/core/search.asm` (`CHECK_START_FROM_BLOCK`).
     - *Issue*: After `Pattern not found.`, the next Find prompt was
       pre-filled with the failed query, a stale locked block survived, and
       the cursor stayed at the old block start.
     - *Resolution*: A never-matched Find clears the query, cancels the
       block and restores the cursor; a locked block the cursor has left is
       cancelled before the prompt opens. Validated via Steps 45 and 46.
   - [x] **Bug 2.7.84: Open / Close Unsaved-Changes Handling**:
     - *Reference*: `docs/UI_UX_DESIGN.md` Section 7.2.
     - *Issue*: `Ctrl+O` and Splash `o` discarded edits without prompting,
       and ESC from the Splash `w` / `o` prompts did not return to the
       editor.
     - *Resolution*: `action_open_file()` prompts when modified; Splash `o`
       and `w` route cancel correctly. Validated via Steps 26, 53 and 54.
   - [x] **Bug 2.7.85: `file:line` and Drive-Prefixed Filenames**:
     - *Issue*: `se C:2.TXT`, `2.TXT:15` and mixed-case names were not
       resolved on a case-sensitive host.
     - *Resolution*: `parse_filename_and_line()` strips CP/M drive prefixes
       and `Editor._resolve_existing_file()` matches case-insensitively.
       Validated via Steps 3, 30 and 55.
   - [x] **Bug 2.7.86: 80-Column Continuation Highlight and Geometry Clamp**:
     - *Reference*: `docs/UI_UX_DESIGN.md` Section 5.
     - *Issue*: Lines wider than the viewport lacked the inverse-video
       right-edge marker, and switching 120x40 to 80x24 left the cursor
       below the new status bar.
     - *Resolution*: `render_editor()` highlights the last visible column
       (suppressed during block mode) and Splash `1` clamps `cursor_row` to
       `top_row + 22`. Validated via Steps 59 and 62.
   - [x] **Bug 2.7.87: Cursor Visibility on Tier 1 Workspaces**:
     - *Issue*: The cursor stayed visible on Splash, About and directory
       screens and was not restored on entering the editor.
     - *Resolution*: Added `hide_cursor()` / `show_cursor()` discipline to
       the workspace renderers. Validated via Step 64.
   - [ ] **Bug 2.7.88: Default Tab Width Is 8 (Native C Profile Uses 4)**:
     - *Reference*: Bug 2.4.38, Bug 2.4.41.
     - *Issue*: `tests/test_linux_native.py --python` fails
       `test_bug_2_4_38_default_tab_width` and `..._41_tab_snap_forward`:
       a Tab on an empty line reaches visual `Col 8`, not `Col 4`.
     - *Root Cause*: `Config.DEFAULT_TAB_WIDTH = 8` in
       `ports/python/se/config.py`.
     - *Action*: Decide whether the Python profile should follow the
       canonical default of 4; if so change the default and update
       `test_editor.py` expectations.
   - [ ] **Bug 2.7.89: Help Screen Lacks Dedicated PgUp / PgDn Lines**:
     - *Reference*: Bug 2.4.47 (`test_bug_2_4_47_...`).
     - *Issue*: `action_help()` lists `PgUp / PgDn : Page Up / Down` on one
       line; the canonical Help screen documents `PgDn` separately.
     - *Action*: Align the Help text with `docs/UI_UX_DESIGN.md` Section 7.3.
   - [ ] **Bug 2.7.90: Tier 1 Header Shows Host Path, Not Drive Label**:
     - *Reference*: Bug 2.4.17, 2.4.27, 2.4.28, 2.4.29.
     - *Issue*: Open/Save/Insert/Block-Save workspaces render
       `(DIRECTORY - <host path>/)`; the native suite expects
       `(DIRECTORY)` and the CP/M suite `(DIRECTORY - DRIVE C:)`.
     - *Action*: Clarify the canonical Linux header in
       `docs/UI_UX_DESIGN.md` and align `ports/python/se/ui.py`.
   - [ ] **Bug 2.7.91: CRLF Status Label and Save-Flow Differences vs Native**:
     - *Reference*: Bug 2.4.45; `tests/test_linux_native.py --python`.
     - *Issue*: The native suite expects `CPM   |` for CRLF files and a
       single-key `Ctrl+S` save, whereas Python SE shows `CP/M  |` and opens
       the Save workspace. Eight native tests fail on these differences
       (see the `--python` summary).
     - *Action*: Decide whether the native tests or the Python profile is
       canonical, then update one side.
   - [x] **Bug 2.7.92: Screen Transition and Modal Pop-up Display Debris**:
     - *Reference*: `docs/UI_UX_DESIGN.md` Section 5.2, 8.1, 8.4.
     - *Issue*: Changing screens or displaying sequential modal pop-ups leaves
       debris characters from the previous screen or taller pop-up on the
       terminal display instead of refreshing the whole display.
     - *Root Cause*:
       1. In `ports/python/se/ui.py:270-288` (`render_centered_workspace`),
          each row wrote `"~"` at column 1, jumped directly to `left_col` via
          `locate(screen_r, left_col)` to write `line_str`, and only called
          `clear_eol()` afterward, leaving columns `2 .. left_col - 1`
          un-cleared when transitioning from wider screens or editor text.
       2. In `ports/python/se/editor.py`, sequential pop-ups and workspace-to-
          modal transitions (`action_find`, `action_replace`,
          `action_insert_file`, `action_save_file`, `action_block_save`)
          drew child notifications (`52x7`) directly over taller input modals
          (`52x8`) or over the Tier 1 Directory Browser without redrawing the
          underlying editor screen first.
     - *Resolution*: Called `clear_eol()` immediately after writing the
       column 0 tilde in `render_centered_workspace()` in `ui.py`, and added
       `_refresh_editor_screen()` in `editor.py` before chained modal pop-ups
       and post-browser notifications. Validated via Step 61 in
       `test_editor.py`
       (`test_bug_2_7_92_screen_transition_and_popup_debris_cleanup`).
  - [x] **Bug 2.7.93: Splash Screen Missing `[^O]`/`[^S]`/`[3]` Labels,
    Flush-Left Title/Menu Alignment & Hardcoded Diagnostics**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 4.3, 7.2, 11.2, 14.1, 15.1.
    - *Issue*: In `ports/python/se/editor.py:913-1040` (`action_splash_screen`)
      and `ports/python/se/ui.py:37-122, 247-300` (`render_status_bar`,
      `render_centered_workspace`):
      1. *Missing `or  [^O]` and `or  [^S]` Menu Text*: Lines 942–943 display
         `"type   [O]              to open file"` and
         `"type   [S]              to save file"`, omitting `or  [^O]` and
         `or  [^S]` required by Section 7.2 and Section 15.1.3.
      2. *Missing `type   [3]              set native` Menu Line*: Although
         hotkey `'3'` is handled in `action_splash_screen()` (lines 1028–1033)
         to set `SCREEN=NATIVE`, the displayed `lines` list (lines 951–952)
         omits `type   [3]              set native` (Section 7.2, 14.1, 15.1.5).
      3. *Flush-Left Title, Menu, and Diagnostic Alignment*: All strings in
         `lines` (lines 937–959) lack relative leading indentation and are
         rendered by `render_centered_workspace()` at a single
         `left_col = (80 - 47) // 2 + 1 = 17` (`15` spaces after `~` in
         `80x24`). Consequently, the title `"SE - Screen Editor"` is flush-left
         at Column 17 instead of centered at Column 32 (`30` spaces after `~`),
         command lines start at Column 17 (`15` spaces after `~`) instead of
         Column 23 (`21` spaces after `~`), and diagnostic lines start at
         Column 17 (`15` spaces after `~`) instead of Column 21 (`19` spaces
         after `~`, outdented 2 spaces left of `type`) per
         Section 15.1.2–15.1.3.
      4. *Hardcoded Static `RAM Drive (A:)` & `Plugin System` Status Lines*:
         Lines 956–957 hardcode `"RAM Drive (A:): [Preserved (Active)]"` and
         `"Plugin System : [Operational]"` instead of reflecting `self.config`
         (`On Demand` / `Disabled`) or adapting inapplicable CP/M
         `RAM Drive (A:)` / `Max Lines` on Linux per Section 15.1.5.
      5. *Status Bar Field 4 Static `^K: Editor keys` on Splash/About*:
         `render_status_bar()` (`ports/python/se/ui.py:60-64`) renders
         `" ^K: Editor keys |"` in Field 4 on the Splash and About screens
         instead of a blank 15-character field (`               | `) or
         `Free: <N> KB` (Section 4.3, 11.2, 15.1.5, 15.2.4).
    - *Required Fix*: Update `action_splash_screen()` in
      `ports/python/se/editor.py` and `ports/python/se/ui.py` to include
      `or  [^O]`, `or  [^S]`, and `type   [3]              set native`, apply
      canonical relative indentation (`11` spaces before title, `2` spaces
      before `type`, `0` spaces before diagnostics within a 41-col/50-col block
      so `~` padding matches Section 15.1.2), dynamically format
      `Plugin System` from `self.config` (and adapt `RAM Drive`/`Max Lines` per
      Section 15.1.5), and blank Field 4 (or show `Free: <N> KB`) on non-editor
      screens.
    - *Resolution*:
      1. Updated `action_splash_screen()` in `ports/python/se/editor.py` to
         include `or  [^O]`, `or  [^S]`, and
         `"  type   [3]              set native"`, apply canonical relative
         indentation (`11` leading spaces on `"           SE - Screen Editor"`,
         `2` leading spaces on `"  type   ..."` rows, and `0` leading spaces on
         diagnostic rows), and dynamically format `Plugin System`
         (`[Operational]`, `[On Demand]`, `[Disabled]`) and `RAM Drive`
         (`[Preserved (Active)]`, `[Overwritten (Max RAM)]`,
         `[Hibernated (Temp Image)]`, `[None Detected]`) from `self.config`.
      2. Updated `render_centered_workspace()`, `render_directory_workspace()`,
         and `render_status_bar()` in `ports/python/se/ui.py` to center the
         Splash Screen block at width `40` (`left_col = 21` in `80x24`, `41` in
         `120x40`) and render a blank 15-character Field 4
         (`"                 |"`) on non-editor screens.
      3. Verified via Step 62 in `ports/python/tests/test_editor.py`
         (`test_bug_2_7_93_splash_screen_labels_alignment_and_diagnostics`).
  - [x] **Bug 2.7.94: About Screen Outdated Version/AI Attribution &
    Flush-Left Line Alignment**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 7.12, 14.6, 15.2.
    - *Issue*: In `ports/python/se/editor.py:863-881` (`action_about`),
      `ports/python/se/__init__.py:5`, and `ports/python/se/ui.py:247-300`
      (`render_centered_workspace`):
      1. *Outdated Version & Date*: Line 867 displays
         `"version 1.1.0 (2026-10-09) (Python)"` (and `__version__ = "1.1.0"`
         in `__init__.py`) instead of canonical
         `"version 1.1.3 (2026-10-17) (Python)"` (Sections 7.12, 14.6, 15.2.4).
      2. *Outdated AI Attribution*: Line 870 displays
         `"Google Antigravity 2.19.1 & Gemini FLASH 3.8 high"` instead of
         canonical `"Google Antigravity 2.23.0 & Gemini 4 Argon Medium"`
         (Sections 7.12 & 15.2.3).
      3. *Flush-Left Line Alignment Instead of Per-Line Horizontal Centering*:
         `action_about()` passes unpadded strings to
         `render_centered_workspace()`, which computes a single `left_col` from
         the longest line (`49` chars -> `left_col = 16`, `14` spaces after `~`
         in `80x24`) and renders every line flush-left at Column 16. Per
         Section 7.12 and Section 15.2.2–15.2.3, each of the 9 lines on the
         About Screen must be individually centered horizontally
         (`LeftPad = (ACTIVE_COLS - 1 - len(str)) // 2` spaces after Column 1
         `~`).
    - *Required Fix*: Update `action_about()` in `ports/python/se/editor.py`
      (and `__version__` in `ports/python/se/__init__.py`) to
      `"version 1.1.3 (2026-10-17) (Python)"` and
      `"Google Antigravity 2.23.0 & Gemini 4 Argon Medium"`, and center each
      line individually per Section 15.2.2
      (`LeftPad = (cols - 1 - len(line)) // 2` spaces after `~`).
    - *Resolution*:
      1. Updated `__version__ = "1.1.3"` in `ports/python/se/__init__.py` and
         updated `action_about()` in `ports/python/se/editor.py` to display
         `"version 1.1.3 (2026-10-17) (Python)"` and
         `"Google Antigravity 2.23.0 & Gemini 4 Argon Medium"`.
      2. Updated `render_centered_workspace()` in `ports/python/se/ui.py` to
         center each non-empty About Screen line individually at column
         `2 + (cols - 1 - len(line_str)) // 2` (`LeftPad` spaces after Column 1
         `~`) while leaving empty separator lines as bare `~`.
      3. Verified via Step 63 in `ports/python/tests/test_editor.py`
         (`test_bug_2_7_94_about_screen_version_attribution_and_centering`) and
         Step 65 in `tests/test_editor_headless.py --python`.

### 2.8 Profile 8: CP/M C Semantic Equivalent Profile (`SEC.COM`)
- **Target Platform**: Standard CP/M 2.2 / 3.0 (RomWBW v3.6.0+, RC2014, SC131,
  standard 64KB TPA).
- **Core Technology**: Portable C core modules (`src/core/*.c`), CP/M Hardware
  Abstraction Layer (`src/hal/cpm/`), z88dk cross-compiler toolchain (`+cpm`).
- **Build Target**: `make sec-cpm` (or `make SEC.COM`).
- **Status**: Active / 0 Defects Open (Bugs 2.8.1–2.8.6, 2.8.8–2.8.12
  Resolved; Bug 2.8.7 Rejected).
- **Active Defects & Issue Tracking (UI_UX_DESIGN.md & SE.COM Parity)**:
  - [x] **Bug 2.8.1: Full-Screen Redraw on Keystrokes in Directory Browser**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 7.5, 7.7, 7.10, 8.3;
      `TODO.md` Section 7.1.
    - *Symptom*: When running `tests/test_editor_headless.py --sec`, Step 17
      enters `OUTPUT.TXT\r` in the Save Screen. Step 18 immediately fails on
      `Ctrl+Q` clean exit back to CP/M with `Buffer captured: b''` because
      `SEC.COM` fails to return to the `C>` prompt.
    - *Root Cause Analysis*:
      1. In `src/core/ui_browser.c:325-448` (`ui_browser_workspace`), every
         character received during filename input (such as typing
         `"OUTPUT.TXT\r"`) loops back to the top of `while (1)` and executes
         a full-screen re-render of all 24 rows, including repainting the
         file grid, borders, and Row 24 status bar via `render_status_bar()`.
      2. Repainting 24 rows 11 times across a 4–10 MHz Z80 CP/M serial console
         causes extreme display latency and floods the terminal stream with
         redundant status bars containing `Line    1/1`.
      3. The headless test runner in Step 17 looks for `Line    1/1` to detect
         save completion. Because the browser emits `Line    1/1` on the very
         first character typed (`'O'`), the test runner prematurely declares
         save completion, drains the PTY, and sends `\x11` (`Ctrl+Q`) for
         Step 18 while `SEC.COM` is still processing queued redraws for the
         remaining characters of `"UTPUT.TXT\r"`.
      4. `ui_browser_workspace()` does not handle `Ctrl+Q` as an input key, so
         `\x11` is dropped, the save is never committed to disk, and `SEC.COM`
         remains stuck in the browser rather than exiting cleanly to CP/M.
      5. Automatic local stack buffers in `ui_browser_workspace()` exceeded TPA
         stack headroom (+451 B), causing stack collision into `_g_config`.
    - *Resolution*:
      1. Introduced `render_browser_prompt()` in `src/core/ui_browser.c` to
         perform localized in-place prompt updates on text input, deletions,
         and navigation without repainting the directory grid or status bar.
      2. Gated full-screen re-renders behind `need_full_render` for macro
         events (initial display, pagination, drive/filter changes, and format
         toggles).
      3. Relocated CP/M browser buffers to static BSS and right-sized
         `MAX_BROWSER_FILES` to 64 entries, expanding TPA stack headroom from
         +451 B to +1,519 B below BDOS (`0xD800`).
      4. Fixed `workspace_root` resolution in `test_editor_headless.py` and
         consolidated Step 17 save prompt capture buffer.
      5. Verified 100% pass across Steps 17–24 in headless test suite.
  - [x] **Bug 2.8.2: TPA Memory Overflow Overwriting BDOS and CCP (BAD LOAD)**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 14.4, 14.5; `TODO.md`
      Section 7.1; `check_tpa.py SEC.COM`.
    - *Issue*: When running `SEC.COM` on RomWBW RC2014 CP/M, CCP reports
      `BAD LOAD` and immediately aborts execution. `check_tpa.py SEC.COM`
      reports -3,336 bytes of negative headroom below BDOS (`0xD800`), with
      code and data spanning 54,854 bytes (0x0100..0xD746) and BSS reaching
      `0xE508` (58,376 bytes consumed / 106.06% of TPA capacity).
    - *Root Cause*: Code growth from Linux profile feature additions in
      `src/core/`, unpruned rodata string literals (~5.5 KB), multiple
      `snprintf` calls with large format buffers, and CRT stdio redirection
      exceed the 55,040-byte TPA limit, directly overwriting CCP (`0xD000`) and
      BDOS (`0xD800`).
    - *Remedy*: Apply `#ifdef __CPM__` / `#ifndef __CPM__` conditional
      directives across shared C modules to isolate Linux-specific routines,
      eliminate redundant `snprintf` formatters on CP/M, trim string literals,
      configure z88dk pragmas to trim unused CRT/stdio features, and restore
      positive TPA headroom below `0xD800`.
    - *Resolution*:
      1. Replaced POSIX stdio file operations with native BDOS sector I/O calls
         (Calls 15, 16, 19, 20, 21, 22, 26, 34).
      2. Set `-pragma-define:CLIB_OPEN_MAX=0` in `Makefile` to eliminate CRT
         file descriptors, FILE structs, and stdio buffer allocations.
      3. Unified 128-byte sector DMA buffers and FCBs across `file_io.c`,
         `config.c`, and `ui_browser.c` into a single shared `g_cpm_dma_buf`
         and `g_cpm_fcb`.
      4. Right-sized CP/M browser capacity to 32 entries and implemented
         insertion sort to eliminate CRT `qsort`.
      5. Replaced `snprintf` formatters with `strncpy` in `search.c` and
         `beautify.c`.
      6. Verified positive headroom (+890 bytes below BDOS `0xD800`) via
         automated test `tests/test_sec_tpa_headroom.py`.
  - [x] **Bug 2.8.3: UTF-8 Character Emission Violating 7-Bit ASCII Mandate**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 2.6, 7.2, 7.3, 7.4, 7.12,
      11.10.
    - *Issue*: Multi-byte UTF-8 em-dash characters (`—` / `\xe2\x80\x94`) are
      emitted across title banners in the Splash, Help, About, and Configuration
      screens, producing visual glitches and character corruption (e.g. `â€”`)
      on standard CP/M VT100 / ANSI serial terminals.
    - *Root Cause*: Static string tables in `src/core/ui_render.c`
      (`s_splash_lines[0]`, `s_help_lines[0]`, `s_about_lines[0]`, and
      `cfg_lines[0]`) contain UTF-8 em-dashes instead of 7-bit standard ASCII.
    - *Remedy*: Replace all multi-byte UTF-8 em-dash characters in
      `src/core/ui_render.c` and shared UI routines with standard 7-bit ASCII
      hyphens (`-`) in strict conformance with Section 2.6.
    - *Resolution*: Replaced all 4 multi-byte UTF-8 em-dash characters in
      `src/core/ui_render.c` with standard 7-bit ASCII hyphens (`-`). Added
      automated test suite `tests/test_sec_utf8_ascii.py` verifying zero UTF-8
      em-dash sequences across all C source files and compiled `SEC.COM`.
  - [x] **Bug 2.8.4: Non-Conforming Splash Options & Missing System Metadata**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 2.1, 7.2.
    - *Issue*: The splash screen in `SEC.COM` displays unsupported Option 3
      (`type [3] set native`), includes redundant `Version v1.1.0 (C)` on Row 2,
      and completely omits the four canonical dynamic system metadata rows
      (`Active Screen`, `RAM Drive`, `Plugin System`, `Max Lines`).
    - *Root Cause*: `show_splash_screen()` in `src/core/ui_render.c` uses a
      static 19-line string array that does not conditionally omit Option 3 on
      CP/M, violates the clean header mandate by including version info on
      Row 2, and lacks formatting logic for the four dynamic system fields.
    - *Remedy*: Conditionally hide Option 3 on CP/M targets (`#ifndef __CPM__`),
      remove version/language from Row 2, and dynamically render the four
      canonical system status fields from `g_config` matching canonical
      `SE.COM`.
    - *Resolution*: Conditionally omitted Option 3 on CP/M via
      `#ifndef __CPM__`, enforced clean header mandate by removing version
      info from Row 2, and added dynamic rendering of Active Screen, RAM Drive,
      Plugin System, and Max Lines fields from `g_config`. Verified with
      `tests/test_sec_splash_metadata.py`.
  - [x] **Bug 2.8.5: Non-Conforming Config Workspace & Prohibited Prompt**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 7.4, 11.1, 13.2.
    - *Issue*: Configuration Manager in `SEC.COM` renders a prohibited
      `Enter option: _` input prompt line (violating anti-pattern 1), uses
      non-canonical 4-option numbering, displays non-standard footer
      `[S] Save to SE.CFG [ESC]/[Enter] Return`, and serializes illegal
      `FORMAT=...` parameter into `SE.CFG`.
    - *Root Cause*: `show_config_screen()` in `src/core/ui_render.c` uses an
      ad-hoc 4-option layout with an embedded `Enter option: _` text line, and
      `config_save_file()` in `src/core/config.c` serializes `FORMAT=%s`.
    - *Remedy*: Harmonize `show_config_screen()` to the canonical 5-option
      hotkey layout (1 Geometry, 2 RAM Drive, 3 Max Lines, 4 Tab Width,
      5 Plugins), remove `Enter option: _`, format canonical footer
      `[1-5]=Toggle Option  [S]=Save Config  [ESC]=Exit`, and remove `FORMAT`
      parameter serialization from `config_save_file()`.
    - *Resolution*: Harmonized `show_config_screen()` in `src/core/ui_render.c`
      to canonical 5-option hotkey layout with proper parameter toggling,
      eliminated `Enter option: _` input prompt, rendered canonical footer, and
      removed `FORMAT=` serialization from `src/core/config.c`. Verified with
      `tests/test_sec_config_layout.py`.
  - [x] **Bug 2.8.6: Non-Conforming About Screen Displaying (Linux) on CP/M**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 7.12, 14.6.
    - *Issue*: About screen in `SEC.COM` displays `SE.COM — Screen Editor
      (Linux)` when executed on CP/M hardware or RomWBW emulator, uses an
      abbreviated 6-line layout, and omits author and license credits.
    - *Root Cause*: `s_about_lines` in `src/core/ui_render.c` hardcodes
      `(Linux)` into the title string and uses an ad-hoc 6-line format instead
      of the canonical 9-line specification.
    - *Remedy*: Refactor `show_about_screen()` in `src/core/ui_render.c` to
      adopt the canonical 9-line centered layout from Section 7.12, format
      `version 1.1.0 (2026-10-09) (C)` in Row 2, and include author and
      Antigravity/Gemini open-source credits.
    - *Resolution*: Refactored `show_about_screen()` in `src/core/ui_render.c`
      to canonical 9-line centered layout (54 cols width), eliminated the
      `(Linux)` tag, added canonical `version 1.1.0 (2026-10-09) (C)`, and
      included full author and open-source credits. Verified with
      `tests/test_sec_about_screen.py`.
  - [x] **Bug 2.8.7: Status Bar Field 4 Context Clobber [REJECTED]**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 4.3, 4.4, 6.6, 11.1.
    - *Disposition*: **REJECTED / WONTFIX** per canonical specification.
    - *Rationale*: Identical to Bug 2.1.1, 2.2.1, and 2.3.2. Section 4.3
      codifies Field 4 as the dynamic 15-character contextual slot governed
      by a strict priority hierarchy (Free Memory, Block Selection metrics,
      Pan offset, Overwrite mode, Help Key Hint). Relocating mode indicators
      (`[SEL]`, `[BLK LOCK]`, `[Pan +40]`) to Field 5 directly violates Section
      4.3's Jitter-Free Mandate ("Field 5 MUST NOT contain variable-length
      tags, mode indicators, or pan offsets... All mode and contextual
      indicators belong strictly in Field 4").
  - [x] **Bug 2.8.8: Help Screen Key Discrepancy & Duplicate Ctrl+V Alias**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 7.3, 10.
    - *Issue*: Help screen (`Ctrl+K`) displays `Ctrl+U / Ctrl+V: Page Up / Down`
      alongside `Ctrl+V: Paste Block` (duplicating `Ctrl+V` on the same line),
      and lists `Ctrl+X: Cut Block` / `Ctrl+C: Copy Block` instead of canonical
      `Move Block to Cursor` / `Copy Block to Cursor`.
    - *Root Cause*: `s_help_lines` in `src/core/ui_render.c` retains deprecated
      WordStar/legacy paging aliases and non-canonical block action verbs.
    - *Remedy*: Update `s_help_lines` in `src/core/ui_render.c` to display
      `PgUp / PgDn : Page Up / Down` and `Ctrl+D: Delete Block`, and standardize
      block descriptions to `Copy Block to Cursor` and `Move Block to Cursor`
      matching Section 7.3.
    - *Resolution*: Harmonized `s_help_lines` in `src/core/ui_render.c` to the
      canonical 22-line layout matching `plugins/help.asm` and Section 7.3,
      eliminating duplicate `Ctrl+V: Paste Block` and non-canonical `Cut Block`,
      and displaying `Delete / Ctrl+D` and `Copy/Move solidified block`.
      Verified with `tests/test_sec_help_screen.py`.
  - [x] **Bug 2.8.9: Goto Line Modal Height & Redraw Inefficiency**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 8.3 (Archetype C), 7.10.
    - *Issue*: Goto Line modal dialog renders with 8 rows instead of canonical
      7 rows, lacks canonical `Goto line: [ ... ]` query framing, and repaints
      the entire inverse-video field on every single keystroke.
    - *Root Cause*: `modal_prompt_text()` in `src/core/ui_modal.c` sets
      `height = 8` and redraws the full bracketed field in its event loop
      rather than performing in-place character echoing.
    - *Remedy*: Standardize `modal_prompt_text()` (or create dedicated
      `modal_goto_line()`) to canonical 7-row framing (`50 cols x 7 rows`)
      adhering to Archetype C, and implement in-place prompt character echoing
      per Section 7.10.
    - *Resolution*: Implemented `modal_goto_line()` in `src/core/ui_modal.c`
      with canonical 50x7 dimensions, `Goto line: [     ]` query framing, and
      explicit `[Enter]=Goto Line     [ESC]=Cancel` action footer. Replaced full
      frame redraws with in-place character echoing and visual backspacing.
      Standardized `modal_prompt_text()` to 7 rows. Verified with
      `tests/test_sec_goto_line.py`.
  - [x] **Bug 2.8.10: Unsaved Document Close Loss on Untitled Buffer (Ctrl+W)**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 7.11.
    - *Issue*: Closing an untitled modified document via `Ctrl+W` prompts "Save
      changes?", but selecting `[Y]es` fails silently and discards edits because
      `file_save(NULL, ...)` cannot save without a filename.
    - *Root Cause*: `modal_confirm_save_changes()` in `src/core/ui_modal.c:378`
      calls `file_save(NULL, ...)` directly without redirecting to the Save
      File dialog when `g_current_filename` is empty.
    - *Remedy*: In `modal_confirm_save_changes()`, if
      `g_current_filename[0] == '\0'`, redirect `[Y]es` to
      `ui_browser_save_dialog()` so the user can enter a destination filename
      before closing to the splash screen.
    - *Resolution*: Updated `modal_confirm_save_changes()` in
      `src/core/ui_modal.c` to check `if (!g_current_filename[0])`. When
      untitled, selecting `[Y]es` redirects to `ui_browser_save_dialog()`. If
      the user cancels the file browser dialog, it returns `MODAL_RES_CANCEL`
      to prevent discarding unsaved changes. Verified with
      `tests/test_sec_untitled_close.py`.
  - [x] **Bug 2.8.11: Splash Screen Missing `[^O]`/`[^S]` Labels, Horizontal
    Padding Offset & Hardcoded `RAM Drive (A:)`**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 7.2, 15.1; `TODO.md`
      Section 7.1.
    - *Issue*: In `src/core/ui_render.c:395-563` (`show_splash_screen`, shared
      with `SEC.COM` under `__CPM__`):
      1. *Missing `or  [^O]` and `or  [^S]` Menu Text*: `splash_lines[4]` and
         `splash_lines[5]` (lines 410–411) display
         `"   type   [O]              to open file"` and
         `"   type   [S]              to save file"`, omitting `or  [^O]` and
         `or  [^S]` required by Section 7.2 and Section 15.1.3.
      2. *Horizontal Column Alignment Discrepancy*:
         `render_tier1_workspace_screen(splash_lines, 21, 50)` sets
         `left_col = 16` (`14` spaces after `~` in `80x24`). With 3 leading
         spaces in `splash_lines[2..15]` and `splash_lines[17..20]`, both
         command rows (`type ...`) and diagnostic rows (`Active Screen ...`)
         start at Column 19 (`17` spaces after `~`), whereas canonical `SE.COM`
         (Section 15.1.2–15.1.3) places command rows at Column 23 (`21` spaces
         after `~`) and diagnostic rows at Column 21 (`19` spaces after `~`).
      3. *Hardcoded `RAM Drive (A:)` Label*: Lines 435–444 hardcode
         `RAM Drive (A:)` instead of reporting the detected RAM drive or
         `RAM Drive     : [None Detected]` when no RAM drive is present
         (Section 15.1.4–15.1.5).
      4. *Prohibited Colon-Prefix Intercept*: Lines 463–469 intercept `':'`
         and block waiting for a second keystroke, violating Section 7.2's
         Instant Single-Keystroke Protocol.
    - *Required Fix*: Update `show_splash_screen()` in `src/core/ui_render.c`
      to display `or  [^O]` and `or  [^S]`, match `SE.COM`'s exact horizontal
      column offsets (`21` spaces after `~` for commands, `19` spaces after `~`
      for diagnostics in `80x24`), report `RAM Drive     : [None Detected]`
      when applicable on `SEC.COM`, and remove the `':'` prefix intercept.
    - *Resolution*: Updated `show_splash_screen()` in `src/core/ui_render.c`
      to include `or  [^O]` and `or  [^S]`, pass `content_width = 40` to
      `render_tier1_workspace_screen` (`left_col = 21` in `80x24` / `41` in
      `120x40`) with `11` leading spaces on the title, `2` on command rows,
      and `0` on diagnostic rows, remove the blocking `if (k == ':')`
      intercept, and detect the RomWBW `MD0` RAM drive letter via
      `hbios_detect_ramdrive()` (`g_ramdrive_char`) in
      `src/hal/cpm/hal_cpm_memory.c` (falling back to
      `RAM Drive     : [None Detected]`). Verified with
      `tests/test_sec_splash_metadata.py`.
  - [x] **Bug 2.8.12: About Screen Outdated Version/AI Attribution, Missing
    Blank Row & Off-by-One Centering**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 7.12, 14.6, 15.2; `TODO.md`
      Section 7.1.
    - *Issue*: In `src/core/ui_render.c:611-640` (`show_about_screen`) and
      `src/sec_cpm.c:66`:
      1. *Outdated Version & Date*: `s_about_lines[1]` displays
         `"version 1.1.0 (2026-10-09) (C)"` (and `src/sec_cpm.c:66` prints
         `v1.1.0`) instead of canonical `"version 1.1.3 (2026-10-17) (C)"`
         (Sections 7.12, 14.6, 15.2.4).
      2. *Outdated AI Attribution*: `s_about_lines[4]` displays
         `"Google Antigravity 2.19.1 & Gemini FLASH 3.8 high"` instead of
         canonical `"Google Antigravity 2.23.0 & Gemini 4 Argon Medium"`
         (Sections 7.12 & 15.2.3).
      3. *Missing Blank Row Between AI Attribution and MIT License*:
         `s_about_lines[5]` places `"Open source software under the MIT
         License"` directly after `s_about_lines[4]` with no blank `~` line on
         Content Row 6 (Screen Row 13 in `80x24`), and places an extra trailing
         `""` at `s_about_lines[8]` (Section 15.2.2–15.2.3).
      4. *Off-by-One Horizontal Centering*: `"by Dean Jenkins"` is rendered
         with 31 leading spaces after `~` (instead of 32) and
         `"Press any key to continue"` with 26 leading spaces after `~`
         (instead of 27).
    - *Required Fix*: Update `s_about_lines` and `show_about_screen()` in
      `src/core/ui_render.c` (and version string in `src/sec_cpm.c`) to
      `"version 1.1.3 (2026-10-17) (C)"` and
      `"Google Antigravity 2.23.0 & Gemini 4 Argon Medium"`, insert the blank
      line at index 5 (removing the trailing blank line at index 8), and center
      each line per Section 15.2.2.
    - *Resolution*: Updated `s_about_lines` and `show_about_screen()` in
      `src/core/ui_render.c` (and version string in `src/sec_cpm.c`) to display
      `"version 1.1.3 (2026-10-17) (C)"` and
      `"Google Antigravity 2.23.0 & Gemini 4 Argon Medium"`, inserted the blank
      row at index 5 (`s_about_lines[5] = ""`), passed `content_width = 48` to
      `render_tier1_workspace_screen` (`left_col = 17` in `80x24` / `37` in
      `120x40`) with exact per-line leading spaces (`15`, `9`, `17`, `0`, `3`,
      `12`) matching Section 15.2.2, and skipped redundant cursor locates on
      blank `~` rows. Verified with `tests/test_sec_about_screen.py`.

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
- [x] Define sub-system API header standards (`include/*.inc`) with clear
  register calling conventions (inputs, outputs, clobbered registers).
- [x] Establish strict data encapsulation so platform-agnostic core logic
  never accesses platform-specific hardware registers or BDOS calls directly.
- [x] Maintain deterministic memory layout across modules to preserve TPA
  headroom margins on CP/M while allowing flexible banking on other targets.

### 6.3 Sub-system API Header Specifications (`include/`)
- [x] `include/config.inc`: Global editor constants, keycodes, geometry,
  line limits, and configuration defaults.
- [x] `include/hal.inc`: Hardware Abstraction Layer API defining console,
  keyboard, memory banking, and storage function signatures.
- [x] `include/buffer.inc`: Document buffer engine API (line cache indexing,
  line split/join, active line unpacking, virtual slot mapping).
- [x] `include/editor.inc`: Core editor command dispatch API, cursor
  movement, character insertion, deletion, and word-wrap primitives.
- [x] `include/block.inc`: Block selection, copy/cut/paste, and clipboard
  buffer management API.
- [x] `include/search.inc`: Text search, replace, and case-sensitivity API.
- [x] `include/ui.inc`: Modal dialog engine, Tier 1 status alerts, Tier 2
  query pop-ups, status bar rendering, and frame styling API.
- [x] `include/file_io.inc`: High-level file open, save, backup, and
  directory enumeration API.
- [x] `include/plugin.inc`: Far RAM plugin manager, slot allocation table,
  and Upper Memory Host API vector definitions (`PLUGIN_HOST_API`).
- [x] `include/beautify.inc`: Z80 assembly formatter & alignment engine API.

### 6.4 Platform Abstraction Layer (HAL / PAL) Architecture
- [x] Decouple all BDOS calls, VT100 ANSI sequences, and RomWBW HBIOS bank
  switching from core editor logic into platform-specific HAL modules.
- [x] Implement Standard CP/M Platform Layer (`hal/cpm/`):
  - `hal/cpm/hal_cpm_console.asm`: VT100 / ANSI terminal escape sequences,
    cursor positioning, attribute styling, and BDOS console character I/O.
  - `hal/cpm/hal_cpm_memory.asm`: RomWBW HBIOS 512K bank switching and CP/M 3
    banked memory drivers for Far RAM paging.
  - `hal/cpm/hal_cpm_storage.asm`: BDOS FCB operations, CP/M drive & user
    area switching, and swap file (`$$$SE$$$.SWP`) random record I/O.
- [x] Implement CP/M on ZX Spectrum Next Platform Layer (`hal/next_cpm/`):
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
- [x] Implement Native ZX Spectrum Next Platform Layer (`hal/next_native/`):
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
- [x] `src/core/buffer.asm`: Extract line cache (`LINE_STORAGE`), line split
  and join operations, and virtual slot index tables from `se.asm`.
- [x] `src/core/memory.asm`: Extract virtual memory paging coordinator,
  cache eviction logic, and swap page tracking.
- [x] `src/core/editor.asm`: Extract interactive key dispatch table, cursor
  navigation, text editing primitives, and auto-indent.
- [x] `src/core/block.asm`: Extract block highlight calculations, clipboard
  buffering, block cut/copy/paste, and block indentation.
- [x] `src/core/search.asm`: Extract search string matching, forward find,
  and search-and-replace loop.
- [x] `src/core/ui_render.asm`: Extract screen repaint engine, status bar
  rendering (`STR_STATUS_PREFIX`), and column 0 tilde margin discipline.
- [x] `src/core/ui_modal.asm`: Extract Tier 1 notification pop-ups, Tier 2
  query pop-ups, centered frame drawing, and button selectors.
- [x] `src/core/ui_browser.asm`: Extract file selection and directory
  browser modal screens.
- [x] `src/core/config.asm`: Extract `SE.CFG` reader, parser, serializer, and
  default settings table.
- [x] `src/core/plugin_mgr.asm`: Extract PRL/OVL relocation loader, Far RAM
  slot manager, and Host API trampoline table.
- [x] `src/core/beautify.asm`: Extract Z80 code beautifier and column
  alignment subsystem (`DO_CTRL_Y_BEAUTIFY`).

### 6.6 Target Coordinators & Build Pipeline
- [x] `src/se.asm`: Refactor top-level Standard CP/M coordinator to include
  headers (`include/*.inc`), CP/M HAL (`hal/cpm/*.asm`), and core
  modules (`core/*.asm`).
- [x] Verify binary invariance: Ensure modular CP/M build matches original
  monolithic `SE.COM` functionality and preserves TPA headroom (+2,048 B).
- [x] `src/se_next_cpm.asm`: Create top-level CP/M on Next coordinator
  combining NextCPM HAL (`hal/next_cpm/*.asm`) with core modules.
  Produces `SE_NEXT.COM` for deployment under NextCPM.
- [x] `src/se_next.asm`: Create top-level Native ZX Spectrum Next coordinator
  combining Next Native HAL (`hal/next_native/*.asm`) with core modules.
- [x] Create Next build targets in `Makefile` to produce:
  - `SE_NEXT.COM`: CP/M executable tailored for NextCPM environment.
  - `SE.NEX`: Standalone ZX Spectrum Next executable runnable from NextZXOS
    browser (setting CPU speed to 14/28 MHz and configuring MMU).
  - `.se` / `SE`: NextZXOS dot command installed into `/dot` on SD card
    allowing direct CLI invocation (e.g. `.se readme.txt`).
- [x] Establish automated testing for Next targets using CSpect or ZEsarUX
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
- [x] Construct a native SE editor implementation in Rust for Linux (`se-rs`).
- [x] Implement idiomatic Rust architecture mirroring SE UI/UX specification:
  - [x] Terminal engine using raw `termios` (`libc`) and non-blocking ESC
    timing.
  - [x] Tier 1 full-screen workspaces, Tier 2 centered modal pop-up dialogs,
    and Tier 3 persistent status bar strictly matching `docs/UI_UX_DESIGN.md`.
  - [x] High-performance line-slot text buffer engine
    (`ports/rust/src/buffer.rs`).
  - [x] WordStar / SE keybindings (`Ctrl+K`, `Ctrl+Q`, `Ctrl+F`, `Ctrl+R`).
  - [x] Compatible `SE.CFG` configuration parsing and serialization.
- [x] Target platforms:
  - PC: `x86_64-unknown-linux-gnu`.
  - Raspberry Pi: `aarch64-unknown-linux-gnu` (RPi 4 / RPi 5).
- [x] Add Cargo package configuration under `ports/rust/` and `--rust` flag to
  `tests/test_linux_native.py` and `tests/compare_cpm_linux.py`.

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
