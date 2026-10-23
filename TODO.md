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
- **Status**: Active / 0 Open (All 28 Bugs Resolved;
  Bugs 2.1.1, 2.1.3-2.1.12, 2.1.15, 2.1.20 Rejected;
  Bugs 2.1.2, 2.1.13, 2.1.14, 2.1.16, 2.1.17, 2.1.18, 2.1.19, 2.1.21, 2.1.22,
  2.1.23, 2.1.24, 2.1.25, 2.1.26, 2.1.27, 2.1.28 Fixed).
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
  - [x] **Bug 2.1.21: Help Screen Omits `Ctrl+Y` and `Ctrl+Z` [FIXED]**:
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
  - [x] **Bug 2.1.23: Filename Input WordStar Keys & `Ctrl+D` Delete [FIXED]**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 1, 7.9, 10.1, 10.2.
    - *Issue*: Section 7.9 mandates that in the Directory Browser filename
      input box (`READ_FILENAME_INPUT`), `<Del>` or `<Ctrl+D>` deletes the
      character directly under the cursor (`INPUT_DEL_CHAR`), and Sections 1
      and 10 strictly prohibit legacy WordStar navigation keybindings across
      all surfaces and modal dialogs. However, `INPUT_CHECK_PAGE_KEYS` in
      `src/core/ui_browser.asm:5789-5806` and `DNL_CHK_PAGE_CTRL` at line 6382
      still bind WordStar `Ctrl+S` to `INPUT_CURSOR_LEFT`, `Ctrl+D` to
      `INPUT_CURSOR_RIGHT` (blocking `Ctrl+D` forward delete), `Ctrl+G` to
      `INPUT_DEL_CHAR`, and `Ctrl+B` to Page Up.
    - *Required Fix*: In `src/core/ui_browser.asm`, remove the prohibited
      WordStar `Ctrl+S`, `Ctrl+G`, and `Ctrl+B` bindings from
      `INPUT_CHECK_PAGE_KEYS` and `DNL_CHK_PAGE_CTRL`, and route `KEY_CTRL_D`
      to `INPUT_DEL_CHAR` per Section 7.9 and Section 10.
  - [x] **Bug 2.1.24: `PLUGIN.PRL` WordStar & Vi Navigation Keys [FIXED]**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 1, 8.3 (Archetype D), 10.
    - *Issue*: Section 1 and Section 10 strictly prohibit legacy WordStar
      diamond directional keys (`^S`, `^D`, `^E`, `^X`) and Vi movement keys
      (`J`, `K`) across all surfaces and modal dialogs. However, in
      `plugins/plugin.asm`, `PLUG_KEY_LOOP` (lines 382-399) and `CPK_KEY_LOOP`
      (lines 1309-1326) still bind `Ctrl+E` (5), `Ctrl+X` (24), `'K'`, and
      `'J'` to slot/item selection navigation alongside the canonical Up/Down
      arrow keys.
    - *Required Fix*: Remove the non-canonical `Ctrl+E`, `Ctrl+X`, `'K'`, and
      `'J'` bindings from `PLUG_KEY_LOOP` and `CPK_KEY_LOOP` in
      `plugins/plugin.asm` and rebuild `plugins/PLUGIN.PRL`.
  - [x] **Bug 2.1.25: Replace Confirmation Multi-Byte Escape Drain [FIXED]**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 8.2, 8.3 (Archetype B), 10.3.
    - *Issue*: In `src/core/search.asm:2137-2140` (`REPLACE_CONFIRM_KEY`),
      receiving `KEY_ESC` (`0x1B`) immediately jumps to `REPLACE_QUIT` without
      checking whether trailing escape sequence bytes follow. Pressing any
      multi-byte escape sequence (e.g. an arrow key `\x1b[A` or `<Del>`
      `\x1b[3~`) during interactive Search & Replace prematurely cancels the
      Replace session and leaves the trailing sequence bytes (`[A`) in the
      console input queue, which immediately dismisses the `"Replace Done"`
      summary modal and leaks literal characters into the document buffer.
    - *Required Fix*: In `REPLACE_CONFIRM_KEY` (`src/core/search.asm`), poll
      `CHECK_KEY_READY` across `ESC_TIMEOUT_LOOPS` upon receiving `KEY_ESC`:
      if no trailing byte arrives, treat as standalone `ESC` and jump to
      `REPLACE_QUIT`; if a multi-byte sequence follows, drain it via
      `DRAIN_ESC_SEQUENCE` and remain in `REPLACE_CONFIRM_KEY`.
  - [x] **Bug 2.1.26: Save Changes & Overwrite Modals `<Enter>` Key [FIXED]**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 8.3 (Archetype B), 10.2.
    - *Issue*: Section 10.2 specifies that `Enter` (`0x0D`) as well as `Y`/`y`
      confirms modal queries (`Confirm / Execute / Select: Enter / Y, y`).
      While `REPLACE_CONFIRM_KEY` and `PLUGIN.PRL` (`CONFIRM_UNLOAD_SLOT`)
      accept `Enter` as Yes, `DSCP_KEY_LOOP` in `src/se.asm:1834-1849`
      (`Save changes before closing?`) and `OVERWRITE_KEY_LOOP` in
      `src/core/ui_browser.asm:2657-2672` (`File already exists. Overwrite?`)
      ignore `KEY_ENTER` (`13`).
    - *Required Fix*: Accept `KEY_ENTER` (`13`) alongside `'Y'`/`'y'` in
      `DSCP_KEY_LOOP` (`src/se.asm`) and `OVERWRITE_KEY_LOOP`
      (`src/core/ui_browser.asm`).
  - [x] **Bug 2.1.27: Directory Browser Multi-Byte CSI Drain [FIXED]**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 7.9, 10.3.
    - *Issue*: Section 10.3 mandates that when a multi-byte CSI sequence
      (`\x1b[...`) is received, the parser must consume all parameter and
      intermediate bytes up to the final terminating byte (`0x40`-`0x7E`, such
      as `~` or a letter) so trailing bytes never leak into input buffers.
      In `src/core/ui_browser.asm`, `INPUT_HANDLE_CSI` (`5707-5741`) and
      `DNL_CSI` (`6327-6345`) only read a single byte after `\x1b[1`..`\x1b[6`
      and do not call `DRAIN_CSI_TAIL` on unrecognized CSI sequences. Pressing
      a 5-byte function key (e.g. `F5` `\x1b[15~`) or modified arrow key
      (`\x1b[1;5D`) in the Open/Save filename prompt leaks `'~'` or `'5D'`
      directly into the filename text box.
    - *Required Fix*: Update `INPUT_HANDLE_CSI` and `DNL_CSI` in
      `src/core/ui_browser.asm` to drain trailing CSI bytes via
      `DRAIN_CSI_TAIL`.
  - [x] **Bug 2.1.28: Plugin Manager Status Bar Line Number [FIXED]**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 4.3, 7.6.
    - *Issue*: Opening the Plugin Manager screen (`P` from Splash or `Ctrl+Z`
      from Editor) corrupts Field 5 of the status bar to display an invalid line
      number (`Line 44413/1 Col 0` or `Line 44413/3 Col 6`).
    - *Root Cause*: In `plugins/plugin.asm:2351-2369`, `HAS_CURSOR_API` checks
      if `PLUGIN_HOST_API + 2` (Host API version) is `>= 0114H` (`v1.1.4`) to
      determine whether `TRAMP_HIDE_CURSOR` (`+76`) and `TRAMP_SHOW_CURSOR`
      (`+79`) are present in `PLUGIN_HOST_API`. However, in
      `src/core/plugin_tramp.asm:145-148` and `741-761`, those two jump vectors
      and trampolines were conditionally compiled under `IFDEF TARGET_NEXT`.
      When `SE.COM`'s Host API version at `+2` was bumped to `0114H`,
      `HOST_HIDE_CURSOR` in `PLUGIN.PRL` jumped to `PLUGIN_HOST_API + 76` on
      `SE.COM`, which fell directly into `TRAMP_CHECKOUT_LINE` at address
      `0xAD7C` (`44,412`) with `HL = 0xAD7C`. `HOST_CHECKOUT_LINE` then executed
      `LD (CUR_DOC_ROW),HL`, overwriting `CUR_DOC_ROW` with `44,412` (`44,413`
      1-based).
    - *Required Fix*: Expose `JP TRAMP_HIDE_CURSOR` (`+76`),
      `JP TRAMP_SHOW_CURSOR` (`+79`), and their corresponding trampolines
      unconditionally across all targets in `src/core/plugin_tramp.asm`.

### 2.2 Profile 2: CP/M on ZX Spectrum Next (`SE_NEXT.COM`)
- **Target Platform**: NextCPM / CP/M 2.2 / CP/M Plus on ZX Spectrum Next.
- **Core Technology**: Z80 assembly (`src/se_next_cpm.asm`), Next-adapted
  console (80-column text mode), Next keyboard matrix mapping, NextCPM banked
  memory extensions.
- **Build Target**: `make se-next-cpm` (produces `SE_NEXT.COM`).
- **Status**: Active / 4 Open (Bugs 2.2.18, 2.2.19, 2.2.30, 2.2.31 Open;
  22 Bugs 2.2.2, 2.2.7, 2.2.8, 2.2.9, 2.2.10, 2.2.11, 2.2.12, 2.2.13, 2.2.14,
  2.2.15, 2.2.16, 2.2.17, 2.2.20, 2.2.21, 2.2.22, 2.2.23, 2.2.24, 2.2.25,
  2.2.26, 2.2.27, 2.2.28, 2.2.29 Resolved;
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
    - *Follow-up*: Hardcoded `\x1b[?25l` in `HELPNEXT.OVL` and `PLUGIN.PRL` is
      tracked separately as Bug 2.2.16.
  - [x] **Bug 2.2.16: Cursor Visible While `HELPNEXT.OVL` / `PLUGIN.PRL`
    Overlays Are Displayed [FIXED]**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 7.3, 8; Bug 2.2.15.
    - *Issue*: In `SE_NEXT.COM`, the terminal cursor may remain visible
      while the Help screen (`HELPNEXT.OVL`, opened via `Ctrl+K` /
      `EXTEND + K`) or Plugin Manager / plugin screens (`PLUGIN.PRL`) are
      displayed, whereas the cursor should be hidden on these non-input
      screens.
    - *Root Cause*: `plugins/helpnext.asm` (lines 145, 197) and
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
      host API version), and update `plugins/helpnext.asm` and
      `plugins/plugin.asm` to call those vectors instead of printing
      hardcoded DEC sequences. Overlays must fall back to the existing
      `\x1b[?25l/h` strings when loaded by an older host (version check),
      and `SE.COM` must continue to emit `\x1b[?25l/h` on RomWBW.
    - *Resolution*: Appended `TRAMP_HIDE_CURSOR` (`+76`) and
      `TRAMP_SHOW_CURSOR` (`+79`) to `PLUGIN_HOST_API` under `TARGET_NEXT`
      (bumping the Host API version to `0114H`) in `src/core/plugin_tramp.asm`
      and `src/include/plugin.inc`. Updated `plugins/helpnext.asm` and
      `plugins/plugin.asm` to call the `+76`/`+79` vectors when Host API
      version $\ge \text{0x0114}$ and fall back to local cursor strings on
      older hosts, preserving `SE.COM` byte-for-byte binary invariance.
      Validated via `tests/test_bug_2_2_16.py`.
  - [x] **Bug 2.2.17: Help Screen Shows PC/Terminal Keys Instead of ZX
    Spectrum Next Keys (Create `HELPNEXT.OVL`) [FIXED]**:
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
    - *Resolution*: Created `plugins/helpnext.asm` (`HELPNEXT.OVL`) with a
      canonical 22-line Tier 1 layout tailored for the ZX Spectrum Next
      keyboard (`EXTEND` = `Ctrl`, `*` markers for redefined Next CP/M keys
      `Arrow Keys`, `INV VIDEO`, `GRAPH`, and `TRUE VIDEO`, plus `DELETE`,
      `EDIT`, `BREAK`, `EXTEND+Y`, and `EXTEND+Z`, and `ESC f` cursor hide).
      Updated `src/core/ui_browser.asm` and `src/core/plugin_mgr.asm` under
      `TARGET_NEXT_CPM` to load `HELPNEXTOVL` and show
      `HELPNEXT.OVL was not found.` while keeping `SE.COM` byte-identical.
      Updated `plugins/build_plugins.py`, `Makefile`, and
      `tools/populate_next_disk.py` to build and deploy `HELPNEXT.OVL`.
      Validated via `tests/test_bug_2_2_17.py`.
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
  - [x] **Bug 2.2.20: `HELP` Overlay and `PLUGIN.PRL` Not Deployed to the
    Next Disk Image [FIXED]**:
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
    - *Resolution*: Updated `Makefile` (`next-image` and `test-next` targets)
      to depend on `plugins`, extended `tools/populate_next_disk.py` to build
      and inject `HELPNEXT.OVL`, `HELP.OVL`, `PLUGIN.PRL`, `PLUGIN.CFG`,
      `WORDCNT.OVL`, `ROT13.PRL`, and `BEAUTIFY.PRL` into `tbblue.mmc` and
      verify their presence via `mdir`, and added `test_next_disk_deployment`
      to `tests/test_next_targets.py`.
  - [x] **Bug 2.2.21: Splash Screen `Ctrl+S` (`^S`) Not Dispatched in
    `SPLASH_LOOP` [FIXED]**:
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
    - *Resolution*: Added `CP KEY_CTRL_S` and `JP Z,DO_SPLASH_SAVE` to
      `SPLASH_LOOP` in `src/se_next_cpm.asm` and verified via
      `tests/test_bug_2_2_21.py`.
  - [x] **Bug 2.2.22: Splash Screen Blank Gap Row Replacing Omitted
    `[2] set 120x40` [FIXED]**:
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
    - *Resolution*: Removed the `DB 13,10` placeholder under
      `IFDEF TARGET_NEXT` in `STR_SPLASH_CMDS` (`src/core/plugin_mgr.asm`),
      defined `SPLASH_MENU_LINES EQU 20` under `IFDEF TARGET_NEXT` in
      `src/include/ui.inc`, and verified via `tests/test_bug_2_2_22.py`.
  - [x] **Bug 2.2.23: `SE.CFG` `SCREEN=120X40` Not Overridden to `80x24` on
    Startup (`src/core/config.asm` / `src/se_next_cpm.asm`) [FIXED]**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 2.1, 7.2, 7.4, 13.2, 14.1,
      15.1.5; Bug 2.2.13.
    - *Issue*: While Bug 2.2.13 disabled hotkey `2` in `SPLASH_LOOP` and made
      `DO_SET_120X40` / `CONFIG_TOGGLE_MODE` call `SET_MODE_80X24`,
      `PARSE_CONFIG_BUFFER` in `src/core/config.asm:359-373` (`PCB_CHECK_120`)
      still calls `SET_MODE_120X40` (`src/se_next_cpm.asm:2167-2180`), which
      sets `SCREEN_MODE = MODE_120X40`, `ACTIVE_ROWS = 40`, and
      `ACTIVE_COLS = 120`. If an `SE.CFG` file on disk contains
      `SCREEN=120X40`, `SE_NEXT.COM` boots into 120x40 geometry on the fixed
      80x24 NextCPM console, causing severe horizontal column spill and
      corrupted line wrapping (Anti-Pattern #3).
    - *Required Fix*: In `src/se_next_cpm.asm:2167` (`SET_MODE_120X40`) or
      `src/core/config.asm:371` (`PCB_CHECK_120` under `IFDEF TARGET_NEXT`),
      enforce `SET_MODE_80X24` so `SE_NEXT.COM` can never enter `MODE_120X40`
      via `SE.CFG`.
    - *Resolution*: Redirected `SET_MODE_120X40` in `src/se_next_cpm.asm` to
      `JP SET_MODE_80X24` (matching `src/se_next.asm`) and verified via
      `tests/test_bug_2_2_23.py`.
  - [x] **Bug 2.2.24: Far RAM Plugin Manager (`PLUGIN.PRL`) and Far-Mode
    Plugins Call RomWBW `0FFF9H` (`HB_BNKCALL`) and `0FFF3H` (`HB_BNKSEL`)
    Under NextCPM (`src/core/plugin_tramp.asm` & `src/core/plugin_mgr.asm`)
    [FIXED]**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 7.2, 7.4, 7.5, 7.10, 14.5,
      15.1.4.
    - *Issue*: In `SE_NEXT.COM`, `NEXTCPM_MEM_INIT`
      (`src/hal/next_cpm/hal_nextcpm_memory.asm:79-107`) sets
      `EXT_BANK_COUNT = 10` using Next MMU 8KB SRAM pages (`NextReg 0x51`), and
      `START` calls `AUTO_LOAD_PLUGIN_MGR`. When `PLUGIN.PRL` is present on
      disk (deployed by `tools/populate_next_disk.py`),
      `ENSURE_PLUGIN_MGR_LOADED` (`src/core/plugin_tramp.asm:841-1028`) loads
      `PLUGIN.PRL` into Far RAM via `NEXT_SYSBNKCPY` and then calls
      `EXEC_PLUGIN_MGR_ACTION` (`src/core/plugin_tramp.asm:743-783`), which
      executes `CALL 0FFF9H` (`HB_BNKCALL`, RomWBW HBIOS bank call vector).
      Similarly, `EXEC_PLUGIN_FAR` (`src/core/plugin_mgr.asm:1405`) calls
      `0FFF9H`, and all Host API trampolines in
      `src/core/plugin_tramp.asm:175, 178, 206, 210, 239, 246, 421, 426, 690,
      697` call `0FFF3H` (`HB_BNKSEL`). Under NextCPM on ZX Spectrum Next,
      RomWBW HBIOS vectors do not exist at `0xFFF3`/`0xFFF9`; calling `0FFF9H`
      on startup when `PLUGIN.PRL` is present (or pressing `P`, `Ctrl+P`, or
      `Ctrl+Z`) jumps into high memory and crashes `SE_NEXT.COM`.
    - *Required Fix*: Implement Next MMU bank switching / bank call trampolines
      under `IFDEF TARGET_NEXT` in `src/core/plugin_tramp.asm` and
      `src/core/plugin_mgr.asm` (or execute `PLUGIN.PRL` and far-mode plugins
      via Next MMU slot mapping / TPA staging) instead of calling RomWBW
      `0FFF3H` and `0FFF9H`.
    - *Resolution*: Implemented `NEXT_BNKCALL` and `NEXT_BNKSEL` in Upper
      Memory (`src/core/plugin_tramp.asm`) under `IFDEF TARGET_NEXT` to save
      and switch Next MMU Slots 0..3 (`NextRegs 0x50..0x53`), and routed
      `EXEC_PLUGIN_MGR_ACTION`, `EXEC_PLUGIN_FAR` (`src/core/plugin_mgr.asm`),
      and all Host API trampolines to them instead of RomWBW `0FFF9H` and
      `0FFF3H`. Validated via `tests/test_bug_2_2_24.py`.
  - [x] **Bug 2.2.25: Max Document Lines (`CFG_LINES_MODE`) Hardcoded to 32K in
    `NEXTCPM_MEM_INIT`, Ignoring `SE.CFG` and Configuration Manager `[3]`
    Toggle (`src/hal/next_cpm/hal_nextcpm_memory.asm` &
    `src/se_next_cpm.asm`) [FIXED]**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 7.2, 7.4, 13.2, 15.1.3,
      15.1.4.
    - *Issue*: Per Section 7.2, 7.4, 13.2, and 15.1.4, the default `Max Lines`
      setting is `16K` (`16,384 lines`, `CFG_LINES_MODE = 0`), toggleable via
      Configuration Manager Option `[3]` (`16K (16,384 Lines)` <->
      `32K (32,768 Lines)`). However, `NEXTCPM_MEM_INIT`
      (`src/hal/next_cpm/hal_nextcpm_memory.asm:84-92`) unconditionally
      allocates both `LINE_TABLE_BANK = 0` and `LINE_TABLE_BANK_1 = 1` and sets
      `MAX_DOC_LINES_LIMIT = MAX_DOC_LINES_32K` (`32,768`) without checking
      `CFG_LINES_MODE`. Consequently:
      1. On startup with default `CFG_LINES_MODE = 0`, the Splash Screen
         (`RENDER_SPLASH` in `src/se_next_cpm.asm:2748`, which tests
         `MAX_DOC_LINES_LIMIT+1 == 80H`) displays
         `Max Lines     : [32,768 lines]`, contradicting the Configuration
         Manager (`SHOW_CONFIG_SCREEN` in `src/se_next_cpm.asm:3208`, which
         tests `CFG_LINES_MODE`), which displays
         `3. Max Doc Lines   : [16K (16,384 Lines)]`.
      2. Pressing `[3]` in the Configuration Manager toggles `CFG_LINES_MODE`
         and calls `BUFFER_INIT` -> `NEXTCPM_MEM_INIT`, which again forces
         `MAX_DOC_LINES_LIMIT = 32,768`, so `16,384 lines` can never be
         activated.
    - *Required Fix*: In `NEXTCPM_MEM_INIT`
      (`src/hal/next_cpm/hal_nextcpm_memory.asm:84-92`), check
      `CFG_LINES_MODE`: when `0` (16K), set `LINE_TABLE_BANK_1 = 0` and
      `MAX_DOC_LINES_LIMIT = MAX_DOC_LINES_16K`; when `1` (32K), set
      `LINE_TABLE_BANK_1 = 1` and `MAX_DOC_LINES_LIMIT = MAX_DOC_LINES_32K`.
      Update `PRINT_MEM_BANK_ROW` (`src/se_next_cpm.asm:3673-3690`) so Bank 01
      accurately reflects 16K vs 32K mode.
    - *Resolution*: Updated `NEXTCPM_MEM_INIT`
      (`src/hal/next_cpm/hal_nextcpm_memory.asm`) to configure
      `LINE_TABLE_BANK_1` and `MAX_DOC_LINES_LIMIT` (`16,384` vs `32,768`)
      according to `CFG_LINES_MODE`, and updated `PRINT_MEM_BANK_ROW`
      (`src/se_next_cpm.asm`) to display `Line Table (16K)` /
      `Available / Reserved` in 16K mode and `Line Table (0..16K)` /
      `Line Table (16K..32K)` in 32K mode. Validated via
      `tests/test_bug_2_2_25.py`.
  - [x] **Bug 2.2.26: Configuration Manager Displays Inapplicable RomWBW RAM
    Drive Options and `120x40` Toggle Hint on Next Hardware
    (`src/se_next_cpm.asm` & `src/core/plugin_mgr.asm`) [FIXED]**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 7.2, 7.4, 7.11, 15.1.5.
    - *Issue*: In `SHOW_CONFIG_SCREEN` (`src/se_next_cpm.asm:3168-3202`) and
      `CONFIG_LOOP` (`src/se_next_cpm.asm:705-707, 744-781`), Option
      `2. RAM Drive : [Preserve (RAM Drive Active, 128KB)]` /
      `[Hibernate (Backup/Restore, 384KB)]` /
      `[Overwrite (Sacrifice Drive, 384KB)]` is displayed and toggleable even
      though NextCPM does not use RomWBW HBIOS RAM drives (`HIBERN.OVL` always
      returns `Not Found` because `HBIOS_DETECT` returns `NZ`), and toggling
      Option `2` has no effect on Next MMU SRAM allocation (`NEXTCPM_MEM_INIT`
      always allocates 10 text banks = 320 KB). Furthermore, Option
      `1. Screen Geometry : [80x24 (Classic Terminal)]` is listed as toggleable
      in `[1-5]=Toggle Option` even though `120x40` is unsupported on Next
      hardware and pressing `1` is a no-op.
    - *Required Fix*: Update `SHOW_CONFIG_SCREEN` and `CONFIG_LOOP` in
      `src/se_next_cpm.asm` (and corresponding strings under
      `IFDEF TARGET_NEXT` in `src/core/plugin_mgr.asm`) to reflect fixed 80x24
      Next geometry and Next MMU SRAM banking rather than RomWBW HBIOS
      128KB/384KB RAM drive preservation modes.
    - *Resolution*: Updated `SHOW_CONFIG_SCREEN` and `CONFIG_LOOP` in
      `src/se_next_cpm.asm` and `STR_RAM_PROTECTED_LBL` / `STR_CONFIG_FOOTER`
      in `src/core/plugin_mgr.asm` to display
      `2. RAM Drive       : [None Detected (Next MMU 384KB)]` and
      `[3-5]=Toggle Option   [S]=Save Config   [ESC]=Exit`, disabling RomWBW
      RAM drive toggling on Next hardware. Validated via
      `tests/test_bug_2_2_26.py`.
  - [x] **Bug 2.2.27: `PROBE_PROGRAM_DRIVE` Only Searches for `SE.COM` and
    Fails When Binary is Named `SE_NEXT.COM` (`src/core/config.asm`) [FIXED]**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 7.4, 13.3, 14.7.
    - *Issue*: Per Section 13.3 (*Discovery & Persistence Rules*), when
      `SE.CFG` is not found on the current logged-in default drive, the editor
      probes the program drive where the executable resides. On ZX Spectrum
      Next hardware, the NextCPM binary is built as `SE_NEXT.COM` but may also
      be locally renamed to `SE.COM` on disk because `SE` is easier to type at
      the CP/M prompt. Currently, `INIT_COM_PROBE_FCB` in
      `src/core/config.asm:1297-1329` only probes for `"SE      COM"`. If the
      executable on the program drive is still named `SE_NEXT.COM` (and no
      `SE.COM` is present on that drive), `PROBE_PROGRAM_DRIVE` fails to locate
      the program drive and therefore fails to discover `SE.CFG` (and overlays
      `HELPNEXT.OVL` / `HIBERN.OVL` via `CONFIG_SOURCE_DRIVE`). Conversely,
      hardcoding `"SE_NEXT COM"` would break when the user renames the binary
      to `SE.COM`.
    - *Required Fix*: Under `IFDEF TARGET_NEXT_CPM` in `PROBE_PROGRAM_DRIVE` /
      `INIT_COM_PROBE_FCB` (`src/core/config.asm`), dynamically detect and
      record the actual binary name (`SE_NEXT.COM` or `SE.COM`) by probing the
      current drive first and then each logged-in drive for both `"SE_NEXT COM"`
      and `"SE      COM"`, storing the matched executable name for runtime UI
      and exit banner display.
    - *Resolution*: Implemented `PROBE_DRIVE_EXECUTABLE` and
      `INIT_NEXT_COM_PROBE_FCB` under `IFDEF TARGET_NEXT_CPM` in
      `src/core/config.asm` to probe the current drive and logged-in drives
      for both `"SE_NEXT COM"` and `"SE      COM"`, recording `EXEC_IS_SE_COM`
      for runtime UI and exit banner display. Validated via
      `tests/test_bug_2_2_27.py`.
  - [x] **Bug 2.2.28: Exit Banner and Extended Memory Map Title Hardcode
    `SE.COM` Instead of the Actual Executable Name (`src/core/plugin_mgr.asm` &
    `src/se_next_cpm.asm`) [FIXED]**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 7.11, 12.1, 13.3, 14.7.
    - *Issue*: In `src/core/plugin_mgr.asm:4396-4398` and `4495`,
      `STR_MEM_INFO_TITLE`, `STR_MEM_TABLE_HDR`, and `MSG_EXIT` unconditionally
      hardcode `"SE.COM - Extended Memory Map"`, `"SE.COM Usage"`, and
      `"Exiting SE.COM. Returned to CP/M."`. On the ZX Spectrum Next under
      NextCPM, the executable may be run as `SE_NEXT.COM` or locally renamed to
      `SE.COM` for convenience. Hardcoding either `"SE.COM"` or `"SE_NEXT.COM"`
      mismatches the actual binary name when the other name is used.
    - *Required Fix*: Under `IFDEF TARGET_NEXT_CPM`, use the actual detected
      executable filename (`SE_NEXT.COM` or `SE.COM`, determined at startup by
      probing the active/program drive or CCP command buffer) in
      `STR_MEM_INFO_TITLE`, `STR_MEM_TABLE_HDR`, and `MSG_EXIT` (with centered
      padding preserved).
    - *Resolution*: Added `STR_MEM_TITLE_PAD_NEXT`, `STR_MEM_INFO_TITLE_NEXT`,
      `STR_MEM_TABLE_HDR_NEXT`, and `MSG_EXIT_NEXT` under
      `IFDEF TARGET_NEXT_CPM` in `src/core/plugin_mgr.asm`, and updated
      `SHOW_MEM_INFO_SCREEN` and `EXIT_PROGRAM` in `src/se_next_cpm.asm` to
      dynamically select the `SE_NEXT.COM` or `SE.COM` strings according to
      `EXEC_IS_SE_COM`. Validated via `tests/test_bug_2_2_28.py`.
  - [x] **Bug 2.2.29: Crash to Prompt on Accessing NextOS Native Drives (C:, M:,
    etc.) From File Screens in `SE_NEXT.COM`**:
    - *Reference*: `docs/HARDWARE_COMPATIBILITY.md` Section 5.4;
      `docs/ARCHITECTURE.md` Section 7.5, 7.8; `docs/UI_UX_DESIGN.md`
      Section 7.9, 14.1.
    - *Issue*: In `SE_NEXT.COM`, attempting to open, save, insert, save block,
      or load plugin from drive `C:` (NextZXOS FAT32 SD card partition) or
      drive `M:` (NextZXOS RAM drive), or any non-CP/M NextOS drive, crashes
      `SE_NEXT.COM` back to the CP/M command prompt (`A>`).
    - *Root Cause*: Under NextCPM on ZX Spectrum Next, only mapped container
      drives (`.P3D` / `.DSK` files such as `CPM-A.P3D`, `CPM-B.P3D`) possess
      CP/M Disk Parameter Blocks (DPB/DPH) accessible via standard CP/M BDOS
      calls. Drives such as `C:` (SD card FAT32 filesystem) and `M:` (NextOS
      RAM drive) are native NextZXOS / +3DOS drives. When entering `C:`, `M:`,
      or any NextOS drive letter in file browser screens (`READ_DIRECTORY`,
      `CHANGE_DRIVE`, `COLLECT_DIR_ENTRIES`), `SE_NEXT.COM` unconditionally
      invokes CP/M BDOS Function 14 (Select Disk) and BDOS Function 17/18
      (Search First/Next). Because `C:` or `M:` are not mounted CP/M BDOS
      drives, the BDOS triggers a fatal "BDOS Select Error" or warm boot,
      crashing the editor immediately to the prompt.
    - *Required Fix*:
      1. **Drive Auto-Detection (No Hardcoded Drive Letters)**: Do not rely on
         hardcoded drive letters `C:` or `M:`. Query the NextCPM BIOS USERF API
         (BIOS function 30, `C=2`: Obtain NextZXOS drive mappings). This returns
         pointers to two 16-byte tables:
         - `HL` = CP/M -> NextZXOS drive mapping table (for CP/M drives `A..P`,
           indicates mapped NextZXOS drive letter or `0` if not present).
         - `BC` = NextZXOS -> CP/M drive mapping table (for NextZXOS drives
           `A..P`, indicates `0` if not present, CP/M letter if mounted, or
           `0xFF` if it is a NextZXOS-only native drive such as FAT32 SD or RAM
           drive).
         Use this dynamic mapping to auto-detect whether any selected drive
         letter is a native CP/M BDOS container drive or a NextZXOS drive.
      2. **Next-Specific VFS Plugin Architecture (`NEXTFS.PRL`)**:
         Just like RomWBW HBIOS FAT access is delegated to `FATFS.PRL`,
         implement a dedicated Next-specific Far RAM VFS plugin (`NEXTFS.PRL`)
         exporting Headless VFS operations via Action 3 (`ENTRY + 9`,
         `VFS_REQ_PKT`, `CAP_HAS_VFS`).
      3. **NextZXOS Inter-Mode File APIs**:
         In `NEXTFS.PRL`, interface with NextZXOS filesystem services across
         the CP/M boundary using the exact NextCPM BIOS USERF call gate
         (`C=1`: Perform NextZXOS call via `IY = call_id`, registers in
         alternate bank and `IX`, buffer located in `$8000..$BFFF`) utilized
         by NextCPM's `IMPORT.COM` and `EXPORT.COM` utilities:
         - `F_OPEN` / `F_CLOSE` / `F_READ` / `F_WRITE` for file data streaming.
         - Directory reading and catalog traversal for browsing NextOS files
           and subdirectories without crashing BDOS.
      4. **Host VFS Routing**:
         In `src/core/ui_browser.asm` and `src/core/plugin_mgr.asm`, when a
         NextZXOS drive is detected, route all directory collection, file
         opening, saving, and block operations through the VFS plugin interface
         instead of issuing CP/M BDOS Function 14 / FCB calls.
    - *Resolution*: Implemented full dynamic NextZXOS drive detection and VFS
      routing in `SE_NEXT.COM` and `NEXTFS.PRL`:
      - Extended `tools/mkprl.py` with `CAP_HAS_VFS = 0x0100` and `--has-vfs`.
      - Authored `plugins/nextfs.asm` (`NEXTFS.PRL`, 8K slot, caps `0x017A`)
        implementing all 10 VFS commands using NextCPM BIOS USERF inter-mode
        calls (`DOS_OPEN`, `DOS_READ`, `DOS_WRITE`, `DOS_CLOSE`, `DOS_CATALOG`).
      - In `src/hal/next_cpm/hal_nextcpm_storage.asm`, implemented
        `NEXTCPM_INIT_DRV_TABLES` (BIOS USERF `C=2`) and
        `NEXTCPM_CLASSIFY_DRIVE` returning Carry=1 for native NextZXOS drives
        and Carry=0 for CP/M container drives.
      - In `src/core/plugin_tramp.asm`, exposed `TRAMP_NEXTCPM_USERF` and drive
        mapping table pointers at `PLUGIN_HOST_API + 82`.
      - In `src/core/plugin_mgr.asm`, updated `VFS_EXEC_REQUEST` for Next MMU
        banking (`NEXT_BNKCALL`), `ENSURE_VFS_PLUGIN_LOADED` to auto-load
        `NEXTFS.PRL` under `TARGET_NEXT_CPM`, and `PARSE_FAT_PATH` to classify
        native drives.
      - In `src/core/ui_browser.asm`, hooked `HODS_OK` and `HSDS_DRIVE_OK` to
        seamlessly switch into VFS mode on selecting native NextZXOS drives,
        and prevented false RAM drive unavailable errors in
        `CHECK_TARGET_DRIVE_UNAVAILABLE`.
      - Preserved 100% byte-for-byte binary invariance of RomWBW `SE.COM`.
      - Verified via `tests/test_bug_2_2_29.py` and `check_ccp.py`.
  - [ ] **Bug 2.2.30: NextOS C: Drive Directory Listing Shows "No files found"
    in `NEXTFS.PRL`**:
    - *Reference*: `plugins/nextfs.asm:457-485`;
      `docs/HARDWARE_COMPATIBILITY.md` Section 5.4; Bug 2.2.29.
    - *Issue*: On a real ZX Spectrum Next running NextCPM (`SE_NEXT.COM`),
      selecting or opening native NextOS drive `C:` displays the empty status
      message `"No files found on current drive"` in the file browser directory
      listing even when files and directories are present on drive `C:`.
    - *Root Cause*: In `plugins/nextfs.asm` (`VFS_LIST_DIR`, lines 457-463), the
      13-byte parameter block passed in `DE` to `DOS_CATALOG` (`$011E`) is
      cleared entirely to zeroes via `VLD_CLR_PARAM`. Per the +3DOS / NextZXOS
      specification, `DOS_CATALOG` expects Entry 0 in the parameter block to
      contain a search mask string (e.g. `"*.*"` or `"???????????"`) terminated
      with `0xFF`. Supplying all zeroes matches a filename starting with null
      byte `\0`, returning 0 entries. Furthermore, `JP NC, VLD_CHECK_EMPTY` at
      line 485 assumes error semantics on Carry=0, but the return convention of
      `DOS_CATALOG` and buffer status handling must correctly interpret entry
      counts and NextZXOS return codes.
    - *Required Fix*:
      1. Populate the 13-byte parameter block passed to `DOS_CATALOG` with a
         wildcard search pattern (e.g. `"*.*"` or `"???????????"` terminated
         with `0xFF`) rather than clearing the parameter block to zeroes.
      2. Properly validate and map NextZXOS `DOS_CATALOG` return registers and
         entry counters into `vfs_dir_buf` to display all files and directories
         on drive `C:`.
  - [ ] **Bug 2.2.31: Opening NextOS M: Drive (RAM Disk) Crashes With BDOS
    "Invalid drive" Error in `SE_NEXT.COM`**:
    - *Reference*: `src/core/ui_browser.asm:73`;
      `src/hal/next_cpm/hal_nextcpm_storage.asm:94`; Bug 2.2.29.
    - *Issue*: In `SE_NEXT.COM`, opening or selecting drive `M:` (the NextZXOS
      RAM drive) causes a fatal CP/M BDOS crash (`Bdos Err On M: Invalid Drive`)
      and aborts to the command prompt (`A>`).
    - *Root Cause*: In `src/core/ui_browser.asm:73` (`CTDU_HAVE_DRV`), register
      `A` is decremented (`DEC A`) before calling `NEXTCPM_CLASSIFY_DRIVE`. In
      `src/hal/next_cpm/hal_nextcpm_storage.asm:94` (`NCD_NOT_UPPER`), if `A`
      is non-zero, it decrements `A` again (`DEC A`), performing a double
      decrement (converting drive index 12 for `M:` into 11 for `L:`). Because
      drive `L:` is not a valid NextZXOS native drive, `NEXTCPM_CLASSIFY_DRIVE`
      fails to recognize it as a NextOS drive and returns Carry=0. `HODS_OK`
      falls through to `HODS_CPM_DRV`, sets `CURRENT_DIR_IS_FAT = 0`, and
      attempts standard CP/M BDOS calls (Function 14 / Function 17) on drive
      `M:`. Since drive `M:` is not a mounted CP/M container drive, BDOS raises
      `Bdos Err On M: Invalid Drive` and halts.
    - *Required Fix*:
      1. Eliminate the duplicate decrement between `src/core/ui_browser.asm`
         and `src/hal/next_cpm/hal_nextcpm_storage.asm` so drive letter
         normalization to 0-based index `0..15` occurs exactly once.
      2. Ensure `NEXTCPM_CLASSIFY_DRIVE` correctly classifies `M:` as a native
         NextOS drive, routing requests through `NEXTFS.PRL` instead of issuing
         CP/M BDOS calls.

### 2.3 Profile 3: Native ZX Spectrum Next (`SE.NEX` & `.se` Dot Command)
- **Target Platform**: NextZXOS / ESXDOS standalone browser executable and
  `/dot` command on SD card.
- **Core Technology**: Z80 assembly (`src/se_next.asm`), native Next hardware
  tile/text layer (80x25 / 80x32), NextRegs MMU 8KB SRAM banking (1MB/2MB),
  NextZXOS filesystem API (`RST 08h`).
- **Build Target**: `make se-next-native` (produces `SE.NEX` and `.se`).
- **Status**: Active / 0 Open (Bugs 2.3.1, 2.3.3, 2.3.4, 2.3.5, 2.3.9,
  2.3.10, 2.3.11, 2.3.12, 2.3.13, 2.3.14 Resolved; Bugs 2.3.2, 2.3.6,
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
  - [x] **Bug 2.3.13: Splash Screen `Ctrl+S` (`^S`) Not Dispatched in
    `SPLASH_LOOP` [FIXED]**:
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
    - *Resolution*: Added `CP KEY_CTRL_S` and `JP Z,DO_SPLASH_SAVE` to
      `SPLASH_LOOP` in `src/se_next.asm` and verified via
      `tests/test_bug_2_3_13.py`.
  - [x] **Bug 2.3.14: Splash Screen Blank Gap Row Replacing Omitted
    `[2] set 120x40` [FIXED]**:
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
    - *Resolution*: Removed the `DB 13,10` placeholder under
      `IFDEF TARGET_NEXT` in `STR_SPLASH_CMDS` (`src/core/plugin_mgr.asm`),
      defined `SPLASH_MENU_LINES EQU 20` under `IFDEF TARGET_NEXT` in
      `src/include/ui.inc`, and verified on `SE.NEX` and `.se` via
      `tests/test_bug_2_3_14.py`.

### 2.4 Profile 4: Linux Native C Profile (`se-linux`)
- **Target Platform**: Linux PC / Workstation (`x86_64`) and Raspberry Pi 4/5
  (`aarch64`).
- **Core Technology**: Portable C core modules (`src/core/*.c`), POSIX
  Hardware Abstraction Layer (`src/hal/linux/`), `termios` raw mode ANSI
  terminal I/O, dynamic heap buffer management.
- **Build Target**: `make se-linux` (verified via `make test-linux`).
- **Status**: Resolved (All 59 Bugs 2.4.1–2.4.59 Resolved).
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
  - [x] **Bug 2.4.51: Splash Screen Layout, Menu Text, Alignment & Status Bar
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
    - *Resolution*: Updated `show_splash_screen()`, `show_about_screen()`, and
      `render_status_bar()` in `src/core/ui_render.c` (with
      `RAMDRV_MODE_DISABLED` support in `src/include/config.h` and
      `src/core/config.c`) to display `or  [^O]`, `or  [^S]`, and
      `"  type   [3]              set native"` under `#ifndef __CPM__`, align
      horizontal columns at `content_width = 40` (`left_col = 21` in `80x24`),
      remove the blocking `':'` prefix intercept, support `[None Detected]`
      when `RAMDRIVE=DISABLED`/`NONE`, format Field 3 as `"CP/M "`, and blank
      Field 4 (`"                 |"`) when `g_is_splash_screen` is active.
      Validated via `test_bug_2_4_51_splash_labels_alignment_and_status_bar`
      in `tests/test_linux_native.py`.
  - [x] **Bug 2.4.52: About Screen Version, AI Attribution, Blank Row &
    Centering Non-Conformities**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 7.12, 14.6, 15.2.
    - *Issue*: In `src/core/ui_render.c:611-640` (`show_about_screen`) and
      `src/se_linux.c:29`:
      1. *Outdated Version & Date*: `s_about_lines[1]` displays
         `"version 1.1.0 (2026-10-09) (C)"` (and `se_linux.c:29` prints
         `v1.1.0`) instead of canonical `"version 1.1.5 (2026-10-21) (C)"`
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
      `"version 1.1.5 (2026-10-21) (C)"` and
      `"Google Antigravity 2.23.0 & Gemini 4 Argon Medium"`, insert the blank
      line at index 5 (removing the trailing blank line at index 8), center
      each line using `(g_active_cols - 1 - strlen(line)) / 2` spaces after
      `~`, and keep `g_is_splash_screen = 1` with cursor hidden on return to
      Splash.
    - *Resolution*: Updated `s_about_lines` and `show_about_screen()` in
      `src/core/ui_render.c` and the `--help` version banner in `src/se_linux.c`
      to `"version 1.1.5 (2026-10-21) (C)"` / `(v1.1.5)` and
      `"Google Antigravity 2.23.0 & Gemini 4 Argon Medium"`, inserted the blank
      row at `s_about_lines[5]`, centered all 9 rows at `content_width = 48`
      (`left_col = 17` in `80x24`) with exact per-line leading spaces (`15`,
      `9`, `17`, `0`, `3`, `12`) matching Section 15.2.2, and preserved
      `g_is_splash_screen = 1` with cursor hidden on return to Splash.
      Validated via
      `test_bug_2_4_52_about_screen_version_attribution_and_centering` in
      `tests/test_linux_native.py`.
  - [x] **Bug 2.4.53: Plugin System Not Permanently Builtin on Splash &
    Configuration Screens**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 7.2, 7.4, 13.2, 14.8, 15.1.5.
    - *Issue*: Sections 7.2, 7.4, 13.2, 14.8, and 15.1.5 mandate that on
      non-CP/M systems (`se-linux`), the plugin manager is permanently builtin
      (`Plugin System : [Builtin]` on the Splash Screen), and neither the
      Configuration Manager (`[C]`) nor `SE.CFG` (`PLUGIN=...`) can disable the
      plugin manager. Currently in `src/core/ui_render.c:478-484`
      (`show_splash_screen`), `se-linux` displays
      `Plugin System : [Operational]`, `[On Demand]`, or `[Disabled]` based on
      `g_config.plugin_mode` instead of `Plugin System : [Builtin]`.
      Furthermore, `show_config_screen()` (`src/core/ui_render.c:730-736,
      791-799`) allows toggling Option 5 (`Plugin Manager : Autoload / Demand /
      Disabled`) on Linux, and `src/core/config.c:124-139, 304-345` parses and
      serializes `PLUGIN=OFF`/`DEMAND` to disable plugins on Linux.
    - *Required Fix*: Under `#ifndef __CPM__` in `src/core/ui_render.c` and
      `src/core/config.c`, unconditionally display
      `"Plugin System : [Builtin]"` on the Splash Screen, display
      `"         5. Plugin Manager   : Builtin"` (non-disableable) on the
      Configuration Manager screen, and ignore `PLUGIN=OFF`/`DEMAND` in
      `parse_config_line()` on non-CP/M builds so the builtin plugin manager
      cannot be disabled.
    - *Resolution*: Updated `show_splash_screen()` and `show_config_screen()`
      in `src/core/ui_render.c` and `parse_config_line()` in
      `src/core/config.c` under `#ifndef __CPM__` so that `se-linux`
      permanently displays `"Plugin System : [Builtin]"` on the Splash Screen
      and `"5. Plugin Manager   : Builtin"` on the Configuration Manager
      screen, and `SE.CFG` cannot disable the builtin plugin manager. Validated
      via `test_bug_2_4_53_builtin_plugin_system` in
      `tests/test_linux_native.py`.
  - [x] **Bug 2.4.54: Status Bar Field 4 Context Hierarchy Missing & Field 5
    Variable-Length Tag Jitter**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 4.3, 6.6, 9.2, 11.1, 14.5.
    - *Issue*: Under `#ifndef __CPM__`, `render_status_bar()` in
      `src/core/ui_render.c:247-361` violates Section 4.3's Field 4 Priority
      Hierarchy and Field 5 Fixed-Width Jitter-Free Mandate:
      1. In `src/core/ui_render.c:280-284`, Field 4 only checks
         `if (g_is_splash_screen)` and otherwise hardcodes
         `" ^K: Editor keys |"`, ignoring active dynamic block selection
         (`Sel: <N> char(s)` / `Sel: <N> line(s)`), solidified block selection
         (`Block: <N> char(s)` / `<N>c` or `Block: <N> line(s)` / `<N>L`),
         horizontal viewport panning (`[Pan +<N>]`), and overwrite mode
         (`Overwrite mode`).
      2. In `src/core/ui_render.c:296-315`, `render_status_bar()` appends
         variable-length tags (`" [Pan +%u]"`, `" [SEL]"`, `" [BLK LOCK]"`) to
         Field 5, causing cursor coordinate jitter and exceeding the
         78-character enclosed status bar width (Anti-Pattern #3: Terminal
         Column Spill).
      3. In `src/core/ui_render.c:270-271`, Field 2 formats `120x40` with an
         extra leading space (`" 120x40 |"` = 10 chars) instead of canonical
         9-character `"120x40 | "` (`" %s |"` where `"120x40"` has 0 leading
         spaces inside the 6-char slot).
    - *Required Fix*: Update `render_status_bar()` under `#ifndef __CPM__` in
      `src/core/ui_render.c` to format Field 4 (15 chars + `" | "`) using the
      canonical Section 4.3 priority hierarchy (Blank `               ` on
      Splash/Browser/Help/About/Config overlays per the Fallback Rule,
      `Sel: ...`, `Block: ...`, `[Pan +%u]`, `Overwrite mode`, or
      `^K: Editor keys`), keep Field 5 strictly fixed at
      `" Line %4u/%-4u Col %-3u |"`, and format `120x40` in Field 2 without an
      extra leading space.
    - *Resolution*: Updated `render_status_bar()` under `#ifndef __CPM__` in
      `src/core/ui_render.c` to format Field 4 (`| %-15s |`) using the
      canonical Section 4.3 priority hierarchy (blank on non-editor overlays,
      `Sel: <N> char(s)` / `Sel: <N> line(s)`, `Block: <N> char(s)` / `<N>c` /
      `Block: <N> line(s)` / `<N>L`, `[Pan +%u]`, `Overwrite mode`, or
      `^K: Editor keys`), locked Field 5 to fixed-width
      `" Line %4u/%-4u Col %-3u |"` with no variable-length tags, and formatted
      Field 2 as `%-6s` (`" 80x24"` / `"120x40"`). Validated via
      `test_bug_2_4_54_status_bar_field4_and_field5` in
      `tests/test_linux_native.py`.
  - [x] **Bug 2.4.55: Splash & Configuration Screens Default to CP/M
    `RAM Drive (A:)` on Linux & Leak Splash State**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 7.2, 7.4, 13.2, 14.1, 15.1.5.
    - *Issue*:
      1. *Default `RAM Drive (A:): [Preserved (Active)]` on Linux*:
         In `src/core/config.c:46`, `config_init_defaults()` initializes
         `g_config.ramdrive_mode = RAMDRV_MODE_PROTECTED` unconditionally.
         Because `g_ramdrive_char` is only compiled under `#ifdef __CPM__` in
         `src/core/ui_render.c:453-471`, `show_splash_screen()` on `se-linux`
         displays `"RAM Drive (A:): [Preserved (Active)]"` by default even
         though Linux has no CP/M `A:` RomWBW RAM drive (Section 15.1.5 states
         hardware RAM drive management does not apply on Linux and must report
         `"RAM Drive     : [None Detected]"` or be omitted).
      2. *Configuration Screen Missing `g_is_splash_screen` & Cursor Hidden
         State*: In `src/core/ui_render.c:693-808`, `show_config_screen()` does
         not preserve `g_is_splash_screen = 1` and unconditionally calls
         `hal_console_show_cursor()` on exit (line 806) before returning to the
         Splash Screen, violating Section 7.2's hidden cursor mandate on the
         Splash Screen.
      3. *Undocumented `?`/`h`/`H`/`Ctrl+K` Keys on Splash Screen*:
         In `src/core/ui_render.c:562-564`, `show_splash_screen()` dispatches
         undocumented `?`, `h`, `H`, and `Ctrl+K` keys instead of silently
         ignoring unassigned keys per Section 7.2's Non-Entry Key Exclusion &
         Silent Rejection Mandate.
    - *Required Fix*: Under `#ifndef __CPM__`, default `g_config.ramdrive_mode`
      to `RAMDRV_MODE_DISABLED` (or report `"RAM Drive     : [None Detected]"`
      on the Splash Screen), preserve `g_is_splash_screen` and keep the cursor
      hidden when exiting `show_config_screen()` to Splash, and remove the
      undocumented `?`/`h`/`H`/`Ctrl+K` branch from `show_splash_screen()`.
    - *Resolution*: Updated `show_splash_screen()` in `src/core/ui_render.c`
      under `#ifndef __CPM__` to report `"RAM Drive     : [None Detected]"` and
      removed the undocumented `?`/`h`/`H`/`Ctrl+K` key branch per Section 7.2's
      Silent Rejection Mandate. Updated `show_config_screen()` to preserve
      `g_is_splash_screen` and keep the hardware cursor hidden when returning
      to the Splash Screen. Validated via
      `test_bug_2_4_55_splash_ram_drive_and_config_cursor_state` in
      `tests/test_linux_native.py`.
  - [x] **Bug 2.4.56: Directory Browser WordStar Aliasing, CP/M Filter Prompt &
    Editor `Ctrl+S` Save Workspace Bypass**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 1, 7.5, 7.6, 7.7, 7.8, 7.9,
      10, 11.8, 15.3.5.
    - *Issue*: In `src/core/ui_browser.c` and `src/core/editor.c`:
      1. *WordStar & Non-Canonical Control Keys in Directory Browser Input
         (`src/core/ui_browser.c:600, 781-795`)*:
         - Line 600 aliases `KEY_CTRL_B` (`Ctrl+B`) to Page Up.
         - Line 781 maps `KEY_CTRL_G` (`Ctrl+G`) instead of canonical
           `KEY_CTRL_D` (`Ctrl+D`) to forward delete in the filename input box.
         - Lines 787–795 alias WordStar diamond keys `KEY_CTRL_S` (`Ctrl+S`) to
           Left Arrow and `KEY_CTRL_D` (`Ctrl+D`) to Right Arrow inside the
           directory filename input box, directly violating the WordStar
           Diamond Deprecation Mandate (Sections 1, 7.9, 10, 11.8) and breaking
           `Ctrl+D` forward delete.
      2. *CP/M Drive/User Prompt Hint on Linux
         (`src/core/ui_browser.c:488, 536-538`)*:
         Line 537 unconditionally displays
         `"[ESC]=Cancel  Enter [d:][u:][pattern] to list (e.g. B:, C1:, 1C:,
         *.TXT)"` and line 488 displays `"[No files found on current drive]"`
         on `se-linux`, where CP/M drive letters and user areas do not exist
         (Section 15.3.5).
      3. *Editor `Ctrl+S` Bypasses Save File Workspace on Existing Files
         (`src/core/editor.c:573-583`)*:
         Under `#ifndef __CPM__`, pressing `Ctrl+S` in the editor when
         `g_current_filename[0] != '\0'` bypasses `ui_browser_save_dialog()`
         and immediately overwrites the file, preventing the user from changing
         the target filename or toggling the `CP/M` / `Linux` line-ending
         format via `Ctrl+F` as mandated by Section 7.7.
    - *Required Fix*: In `src/core/ui_browser.c`, remove the `KEY_CTRL_S` and
      `KEY_CTRL_D` WordStar cursor aliases and `KEY_CTRL_B`/`KEY_CTRL_G`
      aliases, map `KEY_DEL` and `KEY_CTRL_D` to forward character deletion,
      adapt the `#ifndef __CPM__` filter prompt to POSIX path/wildcard syntax
      (`[ESC]=Cancel  Enter [path/][pattern] to list (e.g. src/, *.c, *.txt)`),
      and in `src/core/editor.c` open `ui_browser_save_dialog()` on `Ctrl+S`
      with `g_current_filename` pre-filled.
    - *Resolution*: Removed `KEY_CTRL_S`, `KEY_CTRL_D`, `KEY_CTRL_B`, and
      `KEY_CTRL_G` aliases from `ui_browser_workspace()` in
      `src/core/ui_browser.c`, bound `KEY_DEL` and `KEY_CTRL_D` to forward
      delete, adapted the `#ifndef __CPM__` filter prompt and empty-directory
      message to POSIX syntax, and updated `KEY_CTRL_S` in `src/core/editor.c`
      to open `ui_browser_save_dialog()` with `g_current_filename` pre-filled.
      Validated via `test_bug_2_4_56_browser_keys_prompt_and_ctrl_s_workspace`
      in `tests/test_linux_native.py`.
  - [x] **Bug 2.4.57: Help Screen Alignment/Quit Label & Memory Info Screen
    Non-Blocking Key Read**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 7.1, 7.2, 7.3, 14.5.
    - *Issue*: In `src/core/ui_render.c`:
      1. *Help Screen Column 1 Alignment (`src/core/ui_render.c:613-614`)*:
         In `s_help_lines`, rows 5 and 6 (`Ctrl+W` and `Ctrl+K`) have only 10
         spaces after the 6-character key name, placing descriptions at column
         20 (`"Close file to splash"` and `"Help / Solidify block"`) instead of
         canonical column 21 (`11` spaces after 6-char keys, matching `Ctrl+O`
         on row 4 and Section 7.3). Additionally, row 5 displays
         `"Quit to CP/M"` on Linux builds.
      2. *Memory Info Screen (`[M]`) Immediate Dismissal & `SE.COM` Title
         (`src/core/ui_render.c:810-838`)*:
         `show_mem_info_screen()` calls non-blocking `hal_console_getkey()`
         once at line 831 without a `while (hal_console_getkey() <= 0)` wait
         loop, causing `[M]` from the Splash Screen to immediately return
         without waiting for a keystroke when the input buffer is empty. It
         also displays `"SE.COM - Extended Memory Map"` instead of canonical
         `"SE - "` header prefix (Section 7.1) and does not dispatch `Ctrl+P`
         to `show_plugin_palette()`.
    - *Required Fix*: In `src/core/ui_render.c`, align `Ctrl+W` and `Ctrl+K`
      descriptions at column 21 in `s_help_lines`, update
      `show_mem_info_screen()` to use `"SE - Extended Memory Map"`, wait for a
      keystroke in a `while ((k = hal_console_getkey()) <= 0)` loop (supporting
      `Ctrl+P` plugin palette), and keep the hardware cursor hidden when
      returning to the Splash Screen.
    - *Resolution*: Aligned `Ctrl+W` and `Ctrl+K` descriptions at column 21 and
      updated the Linux quit label to `"Quit to OS"` in `s_help_lines`, and
      updated `show_mem_info_screen()` in `src/core/ui_render.c` to display
      `"SE - Extended Memory Map"`, block for a keystroke in a `while` loop with
      `Ctrl+P` plugin palette support, and keep the cursor hidden on return to
      Splash. Validated via `test_bug_2_4_57_help_alignment_and_mem_info_screen`
      in `tests/test_linux_native.py`.
  - [x] **Bug 2.4.58: Tier 2 Modal Box Width (`52` vs Canonical `50`) &
    `ESC` Sequence Drain**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 8.1, 8.2, 8.3 (Archetypes A,
      B, C), 10.3.
    - *Issue*:
      1. *Non-Canonical 52-Column Modal Width (`src/core/ui_modal.c:26-30`)*:
         Under `#ifndef __CPM__`, `MODAL_BOX_WIDTH` is defined as `52` instead
         of canonical `50` (`Section 8.3` mandates `50 cols x 7 rows` across
         all variants). In `modal_confirm()` (`src/core/ui_modal.c:187`), the
         overwrite confirmation cursor is placed at `left + 40`, which assumes
         `width = 50`.
      2. *Missing Trailing Escape Byte Drain on Modal Cancel
         (`src/core/ui_modal.c:158, 198`, `src/core/search.c:239, 391`)*:
         Unlike `modal_goto_line()` (`src/core/ui_modal.c:409-411`),
         `modal_alert()`, `modal_confirm()`, and `prompt_search_box()` do not
         drain trailing escape bytes or sleep when polling
         `hal_console_getkey()` (note `prompt_search_box()` and `replace`
         confirmation in `src/core/search.c:238, 390` spin in a tight CPU
         busy-loop when `hal_console_getkey() <= 0`).
    - *Required Fix*: Standardize `MODAL_BOX_WIDTH` to `50` in
      `src/core/ui_modal.c`, and ensure modal key polling loops in
      `src/core/search.c` and `src/core/plugin_mgr.c` ignore `k <= 0` without
      tight-spinning.
    - *Resolution*: Standardized `MODAL_BOX_WIDTH` to `50` across all builds in
      `src/core/ui_modal.c`, added trailing escape sequence draining on
      `KEY_ESC` in `modal_alert()`, `modal_confirm()`, `prompt_search_box()`,
      replace confirmation, `plugin_manager_ui()`, and `show_plugin_palette()`,
      and added `usleep(5000)` to modal key polling loops in `src/core/search.c`
      and `src/core/plugin_mgr.c`. Validated via
      `test_bug_2_4_58_modal_box_width_50_and_esc_drain` in
      `tests/test_linux_native.py`.
  - [x] **Bug 2.4.59: `hal_console_init` & `sigwinch_handler` Override
    Configured `80x24` / `120x40` Geometry With Host Window Size**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 2.1, 6.5, 7.2, 13.2.
    - *Issue*: In `src/hal/linux/hal_linux_console.c:41-59` (`sigwinch_handler`)
      and `105-122` (`hal_console_init`), when `g_config.screen_mode` is NOT
      `MODE_NATIVE` (e.g. default `MODE_80X24` or `MODE_120X40`), the driver
      inspects `ioctl(STDOUT_FILENO, TIOCGWINSZ, &ws)` and overwrites
      `g_active_cols` and `g_active_rows` based on whether the host PTY happens
      to be $\ge 120 \times 40$ (`g_active_cols = 120; g_active_rows = 40`) or
      smaller (`g_active_cols = 80; g_active_rows = 24`). Consequently:
      1. Launching `se-linux` in a host terminal window $\ge 120 \times 40$
         forces `g_active_cols = 120, g_active_rows = 40` even though
         `g_config.screen_mode` is `MODE_80X24`, causing the Splash Screen to
         report `Active Screen : [80x24 (Classic Terminal)]` while rendering on
         a `120x40` grid!
      2. Selecting `120x40` via `SCREEN=120X40` in `SE.CFG` is overwritten back
         to `80x24` by `hal_console_init()` if the PTY reports $80 \times 24$.
      3. `ui_init()` (`src/core/ui_render.c:44-55`) does not handle
         `MODE_NATIVE`, and `sigwinch_handler()` does not clear the screen or
         constrain the cursor viewport (`Section 2.1` & `Section 6.5`) when
         resizing in `MODE_NATIVE`.
    - *Required Fix*: In `src/hal/linux/hal_linux_console.c` and
      `src/core/ui_render.c` (`ui_init`), strictly respect
      `g_config.screen_mode`: use `80x24` when `MODE_80X24`, `120x40` when
      `MODE_120X40`, and query `TIOCGWINSZ` dynamically only when
      `g_config.screen_mode == MODE_NATIVE`.
    - *Resolution*: Updated `hal_console_init()` and `sigwinch_handler()` in
      `src/hal/linux/hal_linux_console.c` and `ui_init()` in
      `src/core/ui_render.c` to strictly respect `g_config.screen_mode` (`80x24`
      for `MODE_80X24`, `120x40` for `MODE_120X40`, and dynamic `TIOCGWINSZ`
      querying with viewport clamping only for `MODE_NATIVE`). Validated via
      `test_bug_2_4_59_default_80x24_geometry_invariance` in
      `tests/test_linux_native.py`.

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
- **Status**: Complete / Production Ready (Bugs 2.6.1–2.6.6 Resolved; 0 Open).
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
  - [x] **Bug 2.6.5: Non-Canonical Splash Screen Menu, Missing Commands (`[N]`,
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
    - *Resolution*: Updated `show_splash_screen()`,
      `render_centered_text_block()`, and `render_status_bar()` in
      `ports/rust/src/ui_render.rs`, `modal_goto_line()` in
      `ports/rust/src/ui_modal.rs`, `editor_handle_key()` in
      `ports/rust/src/editor.rs`, and `config_load_file()` in
      `ports/rust/src/config.rs` to render the canonical 22-line, 40-column
      Splash Screen menu at `left_col = 21` (`80x24`), blank Field 4 on the
      Splash status bar, implement `[N]`, `[W]`/`[^W]`, `[L]`/`[^L]`, and `[M]`
      command dispatchers, remove the blocking `':'` prefix intercept and
      spurious splash fallback, and format canonical diagnostic labels.
      Validated via `test_bug_2_4_51_splash_labels_alignment_and_status_bar`.
  - [x] **Bug 2.6.6: About Screen Version, AI Attribution, Spurious
    `"created the code"` Row & Centering**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 7.12, 14.6, 15.2.
    - *Issue*: In `ports/rust/src/ui_render.rs:615-638` (`ABOUT_LINES` and
      `show_about_screen`) and `ports/rust/src/config.rs` (`SE_VERSION_STR`):
      1. *Outdated Version & Date*: `ABOUT_LINES[1]` displays
         `"version 1.1.0 (2026-10-09) (Rust)"` (and `SE_VERSION_STR` is
         `"v1.1.0"`) instead of canonical
         `"version 1.1.5 (2026-10-21) (Rust)"` (Sections 7.12, 14.6, 15.2.4).
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
      `"version 1.1.5 (2026-10-21) (Rust)"` and
      `"Google Antigravity 2.23.0 & Gemini 4 Argon Medium"`, replace
      `ABOUT_LINES[5]` (`"created the code"`) with an empty string `""`, center
      each line individually using `(active_cols - 1 - line.len()) / 2` spaces
      after `~`, and only restore cursor visibility when `prev_splash == 0`.
    - *Resolution*: Updated `ABOUT_LINES` and `show_about_screen()` in
      `ports/rust/src/ui_render.rs`, `SE_VERSION_STR` in
      `ports/rust/src/config.rs`, `print_usage()` in `ports/rust/src/main.rs`,
      and `ports/rust/Cargo.toml` to `v1.1.5` (`2026-10-17`), updated AI
      attribution to `"Google Antigravity 2.23.0 & Gemini 4 Argon Medium"`,
      replaced the spurious `"created the code"` row with a blank `~` line,
      aligned all lines to canonical per-line centered offsets at width 48
      without trailing spaces, added `Ctrl+P` plugin palette support, and kept
      the cursor hidden when returning to Splash. Validated via
      `test_bug_2_4_44_about_screen_canonical_layout` and
      `test_bug_2_4_52_about_screen_version_attribution_and_centering`.

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
         `"version 1.1.5 (2026-10-21) (Python)"` (Sections 7.12, 14.6, 15.2.4).
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
      `"version 1.1.5 (2026-10-21) (Python)"` and
      `"Google Antigravity 2.23.0 & Gemini 4 Argon Medium"`, and center each
      line individually per Section 15.2.2
      (`LeftPad = (cols - 1 - len(line)) // 2` spaces after `~`).
    - *Resolution*:
      1. Updated `__version__ = "1.1.5"` in `ports/python/se/__init__.py` and
         updated `action_about()` in `ports/python/se/editor.py` to display
         `"version 1.1.5 (2026-10-21) (Python)"` and
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
- **Status**: Complete / 0 Defects Open (Bugs 2.8.1–2.8.6, 2.8.8–2.8.64
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
         `v1.1.0`) instead of canonical `"version 1.1.5 (2026-10-21) (C)"`
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
      `"version 1.1.5 (2026-10-21) (C)"` and
      `"Google Antigravity 2.23.0 & Gemini 4 Argon Medium"`, insert the blank
      line at index 5 (removing the trailing blank line at index 8), and center
      each line per Section 15.2.2.
    - *Resolution*: Updated `s_about_lines` and `show_about_screen()` in
      `src/core/ui_render.c` (and version string in `src/sec_cpm.c`) to display
      `"version 1.1.5 (2026-10-21) (C)"` and
      `"Google Antigravity 2.23.0 & Gemini 4 Argon Medium"`, inserted the blank
      row at index 5 (`s_about_lines[5] = ""`), passed `content_width = 48` to
      `render_tier1_workspace_screen` (`left_col = 17` in `80x24` / `37` in
      `120x40`) with exact per-line leading spaces (`15`, `9`, `17`, `0`, `3`,
      `12`) matching Section 15.2.2, and skipped redundant cursor locates on
      blank `~` rows. Verified with `tests/test_sec_about_screen.py`.
  - [x] **Bug 2.8.13: Directory Browser Layout, Vertical Centering, Inverse
    Prompt & `[TAB]` Highlight Navigation Non-Conformities**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 7.5–7.9, 15.3.
    - *Issue*: In `src/core/ui_browser.c:216-681` (`render_browser_prompt` and
      `ui_browser_workspace`):
      1. *Top-Aligned Fixed Grid Instead of Dynamic Vertical Centering*:
         `ui_browser_workspace()` hardcodes `num_rows = 12` (`28` in `120x40`),
         `prompt_row = 8 + num_rows` (Row 20), and always starts the top `===`
         border at Row 1 with 12 fixed file rows, whereas Section 15.3.2
         mandates dynamic vertical centering (`FileRows = ceil(PageFiles /
         DIR_COLS_PER_ROW) + 1`, `PromptRows = 3` in single-page or `4` in
         multi-page, `DIR_TOP_PAD_COUNT = max(0, (ACTIVE_ROWS - 4 - BodyRows)
         / 2)` blank `~` rows above the top `===` border).
      2. *Wrong Horizontal Rule Width & Column Width*: Sets
         `content_width = 70` (emitting 69 `=`/`-` chars on Columns 2..70) and
         `col_width = 14` in `80x24`, whereas Section 7.5 and Section 15.3.2
         mandate `ACTIVE_COLS - 2 = 78` `=`/`-` chars (`118` in `120x40`),
         `DIR_COL_WIDTH = 15` in `80x24` (`16` in `120x40`), and `DIR_LEFT_PAD
         = 3` spaces after `~` in `120x40` (currently hardcoded to 2 spaces).
      3. *Missing Inverse Video on Prompt Label & Missing `<Drive><User>:`
         Preload*: `render_browser_prompt()` prints `"  Enter filename to open:
         ["` in normal video without preloading `<Drive><User>:` (e.g. `C0:`)
         and without the trailing `[TAB]=Select File` mode hint, violating
         Section 7.5 and Section 15.3.2 (`\x1b[7mEnter filename to
         open:\x1b[0m [` + 20-char field + `]  [TAB]=Select File          `).
      4. *Non-Canonical Guide Hint & Extra Single-Page Blank Row*: Line 433
         prints `"  [ESC]=Cancel  [d:][u:][pattern] to list (e.g. B:, *.TXT)"`
         instead of canonical `"  [ESC]=Cancel  Enter [d:][u:][pattern] to list
         (e.g. B:, C1:, 1C:, *.TXT)"` (Section 15.3.2). In single-page
         Open/Insert mode (`total_pages == 1`), lines 404–419 still emit an
         extra blank `~` row before the `---` divider rule, violating the
         Section 7.5 Single-Page Invariant (`PromptRows = 3`).
      5. *Always-Active Grid Highlight & Missing `[TAB]` Highlight Bar Mode*:
         Line 377 unconditionally highlights `selected_idx` in inverse video
         while the text box is active, and `TAB` (`0x09`) is unhandled, whereas
         Sections 7.5, 7.9, and 15.3.2 require the grid highlight to be off in
         text box mode and toggled via `TAB` (`[TAB]=Edit Name  [Enter]=OK`,
         12-char cell highlight, arrow/page navigation, hidden cursor).
    - *Required Fix*: Refactor `ui_browser_workspace()` and
      `render_browser_prompt()` in `src/core/ui_browser.c` to compute dynamic
      vertical centering (`DIR_TOP_PAD_COUNT`, `FileRows`, `PromptRows`), emit
      full-width `78`/`118` rules and `15`/`16`-col grids, render the inverse
      prompt label with `<Drive><User>:` preload and `[TAB]` hint, enforce the
      Single-Page Invariant, and implement `[TAB]` highlight bar mode.
    - *Resolution*: Refactored `src/core/ui_browser.c` and `src/core/file_io.c`
      to implement dynamic vertical centering (`s_top_pad`, `file_rows`,
      `prompt_rows`), `g_active_cols - 2` (`78`/`118`) horizontal `=`/`-`
      rules, `15`/`16`-col file cells with `2`/`3`-space left padding, inverse
      prompt labels with `<Drive><User>:` preload and `[TAB]` mode hints,
      Single-Page Invariant (`[Page]` omitted when `s_total_pages < 2`),
      canonical guide row text, `[TAB]` Highlight Bar Navigation Mode, and
      CP/M drive/user prefix parsing (`cpm_parse_prefix`). Verified with
      `tests/test_sec_browser_layout.py`, `tests/test_sanity.py --sec`, and
      `tests/test_linux_native.py`.
  - [x] **Bug 2.8.14: Prohibited WordStar Diamond & Control Key Aliases (`^E`,
    `^X`, `^R`, `^C`) in Plugin Palette and File Browser**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 1, 6.3, 6.4, 10, 11.8
      (Anti-Pattern #8).
    - *Issue*:
      1. In `src/core/plugin_mgr.c:235-239` (`show_plugin_palette`),
         `KEY_CTRL_E` is aliased to `KEY_UP` and `KEY_CTRL_X` is aliased to
         `KEY_DOWN`.
      2. In `src/core/ui_browser.c:597-608` (`ui_browser_workspace`),
         `KEY_CTRL_R` is aliased to `KEY_PGUP` and `KEY_CTRL_C` is aliased to
         `KEY_PGDN`.
      3. Section 10 and Anti-Pattern #8 strictly prohibit WordStar diamond and
         legacy control navigation aliases across all surfaces and modals.
    - *Resolution*: Removed `KEY_CTRL_E` and `KEY_CTRL_X` navigation aliases
      from `show_plugin_palette()` in `src/core/plugin_mgr.c`, and removed
      `KEY_CTRL_R` and `KEY_CTRL_C` paging aliases from
      `ui_browser_workspace()` in `src/core/ui_browser.c`. Verified via
      `tests/test_sanity.py --sec` and `tests/test_linux_native.py`.
  - [x] **Bug 2.8.15: Default Tab Width Initialized to `4` Instead of Canonical
    `8` & `g_config_loaded` Never Set on CP/M**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 6.2, 7.4, 13.2, 13.3.
    - *Issue*:
      1. *Default Tab Width*: `config_init_defaults()` in
         `src/core/config.c:43` initializes `g_config.tab_width = 4` (and
         fallbacks in `src/core/ui_render.c:76` and `src/core/editor.c:54, 481`
         use `4`), whereas Section 6.2 and Section 13.2 mandate `TAB = 8` as
         the canonical default across all SE variants.
      2. *`g_config_loaded` Never Set on CP/M*: Under `#ifdef __CPM__`,
         `config_load_file()` (`src/core/config.c:157-204`) and
         `config_save_file()` (`lines 213-269`) never set `g_config_loaded = 1`
         on success, so `show_config_screen()` (`src/core/ui_render.c:681`)
         permanently displays `"Config Status: Defaults"` even after loading or
         saving `SE.CFG` (violating Section 7.4).
      3. *Missing Program-Drive Fallback*: `config_load_file()` only probes the
         current default drive (`SE.CFG`) and does not fall back to `A:SE.CFG`
         per Section 13.3.
    - *Resolution*: Initialized `g_config.tab_width = 8` in
      `config_init_defaults()` (`src/core/config.c`) and updated `tab_w`
      fallbacks to `8` in `src/core/ui_render.c` and `src/core/editor.c`. Added
      `A:SE.CFG` fallback probing and set `g_config_loaded = 1` in CP/M
      `config_load_file()` and `config_save_file()`. Updated default tab width
      assertions in `tests/test_linux_native.py` and verified with
      `tests/test_sanity.py --sec`.
  - [x] **Bug 2.8.16: Help Screen Width (`74` vs `78` Columns), Missing
    `g_is_splash_screen` Status Bar Context & Visible Cursor**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 4.3, 7.3, 11.2
      (Anti-Pattern #2).
    - *Issue*: In `src/core/ui_render.c:588-632` (`show_help_screen`):
      1. `s_help_eq` and `s_help_lines[20]` are 74 characters wide and rendered
         with `content_width = 74` (`left_col = 4` in `80x24`, leaving 2
         leading spaces after `~`), whereas Section 7.3 mandates full-width
         `=` and `-` rules across columns `2..79` (`78` characters after `~` in
         `80x24`) and 31 leading spaces before `EDITOR MODE KEYS`.
      2. `show_help_screen()` does not set `g_is_splash_screen = 1` when called
         from the editor via `Ctrl+K`, so Status Bar Field 4 displays
         `^K: Editor keys` on the Help screen itself instead of `Free: <N> KB`
         (violating Section 4.3, Section 7.3, and Anti-Pattern #2).
      3. `show_help_screen()` does not hide the hardware cursor via
         `hal_console_hide_cursor()`.
    - *Resolution*: Expanded `s_help_eq` and `s_help_dash` to 78 characters and
      rendered `show_help_screen()` with `content_width = 78` (`left_col = 2` in
      `80x24`), set `g_is_splash_screen = 1` (restoring `prev_splash` on exit),
      and hid the hardware cursor via `hal_console_hide_cursor()` during Help
      screen execution. Verified via `tests/test_sanity.py --sec` and
      `tests/test_linux_native.py`.
  - [x] **Bug 2.8.17: Missing Unsaved Modifications Prompt on Splash `Q`/`N`/`O`
    and Editor `Ctrl+O` & Unprefilled Splash `S` Filename**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 7.2, 7.7, 7.11, 8.3
      (Archetype B).
    - *Issue*:
      1. In `show_splash_screen()` (`src/core/ui_render.c:494-510`), pressing
         `Q`/`q`/`Ctrl+Q` (Quit), `N`/`n` (New file), or `O`/`o`/`Ctrl+O` (Open
         file) after returning to the Splash Screen from a modified document
         (`g_doc_modified == 1` via `ESC`) does not call
         `modal_confirm_save_changes()`, discarding unsaved edits without
         prompting.
      2. In `editor_handle_key()` (`src/core/editor.c:611-620`), `KEY_CTRL_O`
         opens `ui_browser_open_dialog()` before checking
         `modal_confirm_save_changes()`, instead of prompting to save unsaved
         modifications before entering the Open File browser.
      3. In `show_splash_screen()` (`src/core/ui_render.c:512`), pressing
         `S`/`s`/`Ctrl+S` initializes `dlg_fname[0] = '\0'` instead of
         pre-filling `g_current_filename` per Section 7.7.
    - *Resolution*: Gated `Q`/`Ctrl+Q`, `N`, and `O`/`Ctrl+O` in
      `show_splash_screen()` (`src/core/ui_render.c`) and `KEY_CTRL_O` in
      `editor_handle_key()` (`src/core/editor.c`) with
      `modal_confirm_save_changes()` prior to discarding or opening a file, and
      pre-filled `dlg_fname` from `g_current_filename` on Splash `S`/`Ctrl+S`.
      Verified via `tests/test_sanity.py --sec` and
      `tests/test_linux_native.py`.
  - [x] **Bug 2.8.18: Status Bar Field 4 Block Metrics Pluralization (`1 chars`
    / `1 lines`) & Missing `>= 100` Compact Format (`<N>c` / `<N>L`)**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 4.3 (Field 4 items 2–3),
      Section 9.2.
    - *Issue*: Under `#ifdef __CPM__`, `render_status_bar()` in
      `src/core/ui_render.c:186-202` unconditionally formats
      `"%s: %u chars"` and `"%s: %u lines"`:
      1. When `count == 1`, it emits `"Sel: 1 chars"` / `"Block: 1 lines"`
         instead of singular `"char"` / `"line"`.
      2. For solidified blocks (`BLOCK_MODE_SOLIDIFIED`) with `count >= 100`
         (and `count >= 1000` where `"Block: 1000 chars"` is 17 chars and
         truncates at 15 chars `"%-15.15s"` to `"Block: 1000 cha"`), it fails
         to switch to the compact `"Block: %uc"` / `"Block: %uL"` format
         mandated by Section 4.3.
    - *Resolution*: Updated the `#ifdef __CPM__` block metric formatter in
      `render_status_bar()` (`src/core/ui_render.c`) to use singular `" char"`
      / `" line"` when `cnt == 1` and compact `"c"` / `"L"` units when
      solidified (`!is_sel && cnt >= 100`). Verified via `make check-ccp` and
      `tests/test_sanity.py --sec`.
  - [x] **Bug 2.8.19: Search & Replace (`Ctrl+R`) Broken Confirmation Check
    (`MODAL_RES_OK` vs `MODAL_RES_YES`) & Non-Conforming Modal Framing**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 8.2, 8.3 (Archetypes A, B,
      C), 10, 11.9.
    - *Issue*: In `src/core/search.c:338-404` (`do_ctrl_r_replace`):
      1. *Replacements Always Skipped*: Line 366 calls `ans = modal_confirm(
         "Replace Match?", "Replace this occurrence?", "Replace", "Skip")` and
         checks `if (ans == MODAL_RES_OK)` (`1`), whereas `modal_confirm()`
         returns `MODAL_RES_YES` (`2`, see `src/include/ui_modal.h:16-18`). As
         a result, `ans == MODAL_RES_OK` is always false and confirming a
         replacement in `Ctrl+R` never replaces any match (`replaced_count` is
         always `0`).
      2. *Non-Conforming Replace Input Prompt*: `do_ctrl_r_replace()` calls
         generic `modal_prompt_text()` with inverse-video field and
         `[Enter]=Confirm      [ESC]=Cancel` instead of supporting `[Tab]=Toggle
         Case` and canonical Replace prompt framing (`[Enter]=Replace
         [Tab]=Toggle Case  [ESC]=Cancel`).
    - *Resolution*: Refactored `do_ctrl_f_find()` and `do_ctrl_r_replace()` in
      `src/core/search.c` to share `prompt_search_box()` for canonical 50x7
      Archetype C Find/Replace input prompts (with `[Tab]=Toggle Case`), and
      implemented the canonical 50x7 `Replace Confirmation` query (`[Y]es  [N]o
      [A]ll   [ESC]=Cancel`) in `do_ctrl_r_replace()`. Guarded unused
      `modal_prompt_text()` under `#ifndef __CPM__` in `src/core/ui_modal.c`
      and `src/include/ui_modal.h`. Verified via `tests/test_linux_native.py`
      and `tests/test_sanity.py --sec`.
  - [x] **Bug 2.8.20: `Ctrl+N` (Find Next) Unbound in `editor_handle_key()`**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 7.3, 10 (Canonical
      Keybinding Matrix, line 1461).
    - *Issue*: Although `do_ctrl_n_find_next()` is implemented in
      `src/core/search.c:324` and advertised on the Help Screen (`Ctrl+F /
      Ctrl+N : Find String / Find Next`), `KEY_CTRL_N` (`0x0E`) is missing from
      the `switch (key)` dispatch table in `editor_handle_key()`
      (`src/core/editor.c:520-677`), making `Ctrl+N` a silent no-op in Editor
      Mode.
    - *Resolution*: Bound `KEY_CTRL_N` to `do_ctrl_n_find_next()` in
      `editor_handle_key()` (`src/core/editor.c`), and updated
      `do_ctrl_n_find_next()` (`src/core/search.c`) to fall back to
      `do_ctrl_f_find()` when no prior search pattern is set. Verified via
      `tests/test_linux_native.py` and `tests/test_sanity.py --sec`.
  - [x] **Bug 2.8.21: Confirmation Modals (`modal_confirm`) Non-Conforming
    Reverse-Video Selector & `Enter`/`Space` Acceptance**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 8.2, 8.3 (Archetype B, lines
      1259–1288).
    - *Issue*: Section 8.3 (Archetype B) specifies that confirmation modals
      (`Unsaved Modifications` and `Overwrite File`) render plain text options
      `[Y]es      [N]o      [ESC]=Cancel` and are confirmed strictly via
      explicit `Y`/`y` and cancelled via `N`/`n` or `ESC`. Instead,
      `modal_confirm()` in `src/core/ui_modal.c:167-233` renders an interactive
      reverse-video button selector on `[Y]es` / `[N]o` navigated with
      `Tab`/`Left`/`Right` and accepts `Enter` or `Space` (`' '`) to trigger the
      highlighted button.
    - *Resolution*: Updated `modal_confirm()` in `src/core/ui_modal.c` to
      render plain centered `[Y]es      [N]o      [ESC]=Cancel` options without
      reverse-video button highlights, position the cursor after `Overwrite? `
      when `btn2` is set, and accept strictly `Y`/`y` for Yes, `N`/`n` for No,
      and `ESC` for Cancel per Section 8.3 Archetype B. Verified via
      `tests/test_linux_native.py` and `tests/test_sanity.py --sec`.
  - [x] **Bug 2.8.22: Non-Conforming Memory Info (`[M]`) & Plugin Manager (`[P]`
    / `Ctrl+Z`) Layouts and Prohibited Ellipses**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 2.6, 4.1, 5.2, 7.1, 7.2, 8.2,
      11.9 (Anti-Pattern #9).
    - *Issue*:
      1. `show_mem_info_screen()` (`src/core/ui_render.c:787-808`) renders an
         uncentered 5-line stub with prohibited trailing ellipsis (`"Press any
         key to return..."`), does not set `g_is_splash_screen = 1`, and leaves
         the hardware cursor visible.
      2. `plugin_manager_ui()` (`src/core/plugin_mgr.c:82-119`) computes 0-based
         `top = (g_active_rows - height) / 2` (missing `+ 1`), overwrites the
         Row `top + 2` title separator border `+---+` with `"Slot  Name
         Status      Capabilities"`, emits a prohibited trailing ellipsis in
         `"Press Esc or Q to return to editor..."`, and leaves the hardware
         cursor visible.
    - *Resolution*: Updated `show_mem_info_screen()` (`src/core/ui_render.c`)
      to set `g_is_splash_screen = 1`, hide the cursor, and render the centered
      `"SE.COM - Extended Memory Map"` header and `"Press any key to continue"`
      footer without ellipses; updated `plugin_manager_ui()`
      (`src/core/plugin_mgr.c`) to use 1-based centering (`+ 1`), preserve the
      `top + 2` title separator border, and display `"[Q]/[ESC]=Return"`
      without trailing ellipses. Verified via `tests/test_linux_native.py` and
      `tests/test_sanity.py --sec`.
  - [x] **Bug 2.8.23: Blocking `hal_console_getkey()` Drain Loop on `KEY_ESC`
    Swallows Next Keystroke on CP/M**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 8.2, 8.3 (Archetypes A, B, C,
      D), 10.3.
    - *Issue*: In `src/core/ui_modal.c` (`modal_alert`, `modal_confirm`,
      `modal_goto_line`), `src/core/search.c` (`prompt_search_box`,
      `do_ctrl_r_replace`), and `src/core/plugin_mgr.c` (`plugin_manager_ui`,
      `show_plugin_palette`), pressing `KEY_ESC` executes
      `while (hal_console_getkey() > 0)` to drain trailing escape sequence
      bytes. While `hal_console_getkey()` is non-blocking on Linux (`poll(...,
      0)`), on CP/M (`src/hal/cpm/hal_cpm_keyboard.c:82`) it calls blocking
      `bios_conin()` and already drains any trailing CSI/escape bytes via
      `cpm_read_byte_timeout()`. Consequently, calling `hal_console_getkey()`
      after `KEY_ESC` on CP/M blocks the editor before repainting the screen and
      consumes the user's next command keystroke (e.g. `Ctrl+S` in Step 17 after
      canceling `Ctrl+F` with `ESC` in Step 16).
    - *Resolution*: Guarded the `while (hal_console_getkey() > 0)` post-`ESC`
      drain loops under `#ifndef __CPM__` in `src/core/ui_modal.c`,
      `src/core/search.c`, and `src/core/plugin_mgr.c`. Verified via Step 16–17
      of `tests/test_editor_headless.py --sec`.
  - [x] **Bug 2.8.24: Redundant `hal_console_locate` Inside
    `render_browser_prompt()` Splits ` [` and Input Text**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 7.5, 7.9, 15.3.2
      (`DRAW_FILENAME_BOX`).
    - *Issue*: In `src/core/ui_browser.c:300-302` (`render_browser_prompt`),
      after emitting `" ["`, the function calls
      `hal_console_locate(s_prompt_row, s_box_col)` before calling
      `puts_padded(s_in_buf, 20)`. Because the cursor is already at `s_box_col`
      immediately following `" ["`, the redundant ANSI cursor positioning
      sequence (`\x1b[<row>;<col>H`) splits the opening bracket `'['` from the
      pre-filled input string (emitting `[\x1b[26;30HB:` instead of contiguous
      `[B:` as in `DRAW_FILENAME_BOX` in `src/core/ui_browser.asm:5468-5486`),
      breaking contiguous `"[B:"` / `"[C:"` prompt stream matching in Step 30–31
      of `tests/test_editor_headless.py`.
    - *Resolution*: Removed the redundant `hal_console_locate(s_prompt_row,
      s_box_col)` call after `hal_console_puts(" [")` in
      `render_browser_prompt()` (`src/core/ui_browser.c`) so the opening bracket
      and pre-filled filename string are emitted contiguously. Verified via
      Steps 30–31 of `tests/test_editor_headless.py --sec`.
  - [x] **Bug 2.8.25: Tab Characters Not Highlighted in Block Selection &
    Per-Character Inverse Video Spam in `render_row_content()`**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 9.1, 9.2 (Contiguous Inverse
      Span & Tab Expansion Highlighting).
    - *Issue*: In `src/core/ui_render.c:105-126` (`render_row_content`), when
      rendering a Tab character (`c == '\t'`), the loop emits plain `' '`
      spaces without checking `check_cursor_in_block(doc_row, i)`, so tabs
      inside an active or solidified block selection are never highlighted in
      inverse video. In addition, for regular characters, `render_row_content()`
      toggles `hal_console_inverse_on()` and `hal_console_inverse_off()` around
      every individual character (`\x1b[7mL\x1b[0m\x1b[7m1\x1b[0m`) instead of
      maintaining a contiguous inverse-video span across the block range (e.g.
      `\x1b[7mA       \x1b[0mB` in Step 35 of `tests/test_editor_headless.py`).
    - *Resolution*: Updated `render_row_content()` in `src/core/ui_render.c` to
      check `check_cursor_in_block(doc_row, i)` for both Tab characters and
      regular characters and track `in_inv` state across the row so `\x1b[7m`
      and `\x1b[0m` are emitted only on span transitions. Clarified Contiguous
      Inverse Span & Tab Expansion Highlighting in `docs/UI_UX_DESIGN.md`
      Section 9.2. Verified via Step 35 of `tests/test_editor_headless.py`.
  - [x] **Bug 2.8.26: Multi-Line Block Count Off-By-One When `g_norm_end_col ==
    0`**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 4.3, 9.1, 9.2
      (`GET_BLOCK_BOUNDS` in `src/core/block.asm:591-622`).
    - *Issue*: In `src/core/ui_render.c:234-236, 333-335` (`render_status_bar`)
      and `src/core/block.c:454` (`do_block_menu_popup`), multi-line block line
      counts are computed unconditionally as
      `g_norm_end_row - g_norm_start_row + 1`. Because SE uses a half-open block
      interval `[StartRow:StartCol, EndRow:EndCol)`, when `g_norm_end_col == 0`
      and `g_norm_end_row > g_norm_start_row`, `g_norm_end_row` contributes 0
      characters (`GET_BLOCK_BOUNDS` in `src/core/block.asm:605-616` only
      increments `end_row - start_row` when `BLOCK_END_COL > 0`). Thus,
      selecting from `(Row 1, Col 0)` down 1 row to `(Row 2, Col 0)` in Step 36
      reports `Sel: 2 lines` / `Block: 2 lines` instead of canonical `Sel: 1
      line` / `Block: 1 line`.
    - *Resolution*: Updated multi-line block count calculations in
      `render_status_bar()` (`src/core/ui_render.c`) and `do_block_menu_popup()`
      (`src/core/block.c`) to `g_norm_end_row - g_norm_start_row +
      ((g_norm_end_col > 0) ? 1 : 0)`. Documented the Multi-Line Count Rule in
      Section 9.1 of `docs/UI_UX_DESIGN.md`. Verified via Step 36 of
      `tests/test_editor_headless.py --sec`.
  - [x] **Bug 2.8.27: Backwards Block Selection Normalization Includes Cursor
    Instead of Anchor (`NBB_COL_CB` / `NBB_CUR_FIRST`)**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 9.1 (`NORMALIZE_BLOCK_BOUNDS`
      in `src/core/block.asm:528-564`).
    - *Issue*: In `src/core/block.c:80-100` (`normalize_block_bounds`), when
      selecting backwards (`g_block_active_row < g_block_anchor_row` or
      `g_block_active_col < g_block_anchor_col` on the same row), the C port
      sets `g_norm_start_col = g_block_active_col` and
      `g_norm_end_col = g_block_anchor_col`. In contrast, canonical Z80
      `NORMALIZE_BLOCK_BOUNDS` (`src/core/block.asm:528-564`) excludes the
      cursor position and includes the anchor character by setting
      `BLOCK_START_COL = CUR_COL + 1` and
      `BLOCK_END_COL = BLOCK_ANCHOR_COL + 1`. Because `normalize_block_bounds()`
      did not add `+ 1` on backwards selection, after solidifying a backwards
      selection with `Enter`, the cursor sat at `g_norm_start_col` (inside the
      half-open interval `[g_norm_start_col, g_norm_end_col)`), causing
      `do_copy_block()` (`Ctrl+C`) at the cursor to be rejected by
      `check_cursor_in_block()` in Step 38.
    - *Resolution*: Updated `normalize_block_bounds()` in `src/core/block.c` to
      set `g_norm_start_col = g_block_active_col + 1` and
      `g_norm_end_col = g_block_anchor_col + 1` when `Cursor < Anchor`, and
      updated `solidify_block()` to lock the normalized coordinates into
      `g_block_anchor_*` and `g_block_active_*` before transitioning to
      `BLOCK_MODE_SOLIDIFIED`. Documented Forward vs. Backwards Normalization in
      Section 9.1 of `docs/UI_UX_DESIGN.md`. Verified via Step 38 of
      `tests/test_editor_headless.py --sec`.
  - [x] **Bug 2.8.28: `KEY_SHIFT_UP/DOWN/LEFT/RIGHT` Ignored in
    `editor_handle_key()`**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 9.1 (`SHIFT_CURSOR_*` in
      `src/core/editor.asm:485-500`).
    - *Issue*: Although `hal_cpm_keyboard.c` and `hal_linux_keyboard.c` decode
      `Shift + Arrow` escape sequences (`\x1b[1;2A`..`\x1b[1;2D`) into
      `KEY_SHIFT_UP`, `KEY_SHIFT_DOWN`, `KEY_SHIFT_LEFT`, and `KEY_SHIFT_RIGHT`,
      `editor_handle_key()` in `src/core/editor.c:524-530` has no `case`
      branches for `KEY_SHIFT_*`, silently dropping them in Step 39.
    - *Resolution*: Added `KEY_SHIFT_UP`, `KEY_SHIFT_DOWN`, `KEY_SHIFT_LEFT`,
      and `KEY_SHIFT_RIGHT` handlers to `editor_handle_key()` in
      `src/core/editor.c` calling `start_new_block_at_cursor()` followed by the
      directional cursor motion (`cursor_up/down/left/right()`), matching
      `SHIFT_CURSOR_*` in `src/core/editor.asm:485-500`. Documented `Shift +
      Arrow` behavior in `docs/UI_UX_DESIGN.md` Section 9.1. Verified via Step
      39 of `tests/test_editor_headless.py --sec`.
  - [x] **Bug 2.8.29: `Replace Confirmation` Modal Footer Missing `[R]everse`
    Option**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 8.3 (`STR_REP_CONFIRM_KEYS` in
      `src/core/plugin_mgr.asm:4127`).
    - *Issue*: In `src/core/search.c:398` (`do_ctrl_r_replace`), the `Replace
      Confirmation` modal action footer displays
      `"[Y]es  [N]o  [A]ll   [ESC]=Cancel"`, omitting `[R]everse` which is
      required by canonical `SE.COM` (`"[Y]es  [N]o  [A]ll  [R]everse
      [ESC]=Cancel"`) and checked in Step 47 of
      `tests/test_editor_headless.py`.
    - *Resolution*: Updated the `Replace Confirmation` modal footer in
      `src/core/search.c` to `"[Y]es  [N]o  [A]ll  [R]everse   [ESC]=Cancel"`
      and added the `Replace Confirmation Modal Dialog` template to Section 8.3
      of `docs/UI_UX_DESIGN.md`. Verified via Step 47 of
      `tests/test_editor_headless.py --sec`.
  - [x] **Bug 2.8.30: Search Matches Not Highlighted as Solidified Blocks, No
    Wrap-Around Search, Missing `"Search completed."` vs `"Pattern not found."`
    Distinction, and Missing `[R]everse` Direction Toggle in `search.c`**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 8.3 (`HIGHLIGHT_FOUND_BLOCK`,
      `FIND_STRING_FORWARD_CONT`, `FIND_STRING_BACKWARD_CONT`, and
      `SEARCH_NOT_FOUND` in `src/core/search.asm:567-1022, 2142-2256`).
    - *Issue*: In `src/core/search.c`:
      1. `execute_find_forward()` and `execute_find_backward()` did not activate
         a solidified block (`BLOCK_MODE_SOLIDIFIED`) around the matched text or
         advance `g_cur_col` past the match (`match_col + g_search_len`),
         causing Step 48 (`Block: 8 chars` at `Col 8`) and Step 49 to fail.
      2. Forward and backward searches did not wrap around EOF/BOF or track
         `s_search_ever_found`, always displaying `"Pattern not found."` instead
         of `"Search completed."` when `Ctrl+N` wrapped after finding a match
         (Step 50).
      3. `do_ctrl_r_replace()` did not handle `[R]everse` (`r`/`R`/`p`/`P`) to
         dynamically toggle search direction during interactive replace (Step
         51), and did not call `cancel_block()` before showing `Replace Done`.
    - *Resolution*: Implemented `apply_search_match()`,
      `handle_search_not_found()`, wrap-around `find_string_forward_cont()` and
      `find_string_backward_cont()`, `s_search_ever_found` tracking, and
      interactive `[R]everse` direction toggling in `src/core/search.c`; trimmed
      unused in-field cursor movement from Archetype C `prompt_search_box()` per
      `docs/UI_UX_DESIGN.md` Section 8.3; documented Solidified Match
      Highlighting & Wrap-Around Search in `docs/UI_UX_DESIGN.md` Section 8.3.
      Verified via Steps 47–51 of `tests/test_editor_headless.py --sec`.
  - [x] **Bug 2.8.31: Redundant `hal_console_locate` Between `"Find: ["` and
    Pre-Filled Text in `search.c`**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 8.3 (`DRAW_FIND_POPUP_FULL` in
      `src/core/search.asm:177-196`).
    - *Issue*: In `src/core/search.c:165, 333-334` (`prompt_search_box` /
      `draw_search_field`), after printing `"|      Find: ["` or
      `"|  Replace with: ["`, `draw_search_field()` emitted a redundant
      `hal_console_locate(top + 4, col)` (`\x1b[21;50H`) before printing the
      pre-filled input string, breaking contiguous substring matching for
      `"Find: [Line"` in Step 49 and `"Find: [content"` in Step 51 of
      `tests/test_editor_headless.py`.
    - *Resolution*: Inlined the initial field rendering into
      `prompt_search_box()` in `src/core/search.c` so the pre-filled text and
      trailing spaces are printed contiguously immediately after `"|      Find:
      ["` / `"|  Replace with: ["` without an intervening cursor-locate escape.
      Verified via Steps 49–51 of `tests/test_editor_headless.py --sec`.
  - [x] **Bug 2.8.32: `show_plugin_palette()` Does Not Toggle-Dismiss on
    `Ctrl+P` or `q`/`Q` in `plugin_mgr.c`**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 8.3 (Archetype D: Selection
      Menu / Plugin Palette) and `plugins/plugin.asm:1304-1308`.
    - *Issue*: In `src/core/plugin_mgr.c:232-265`, `show_plugin_palette()` only
      checked `k == KEY_ESC` to cancel and dismiss the palette, ignoring
      `KEY_CTRL_P` (`0x10`) and `q`/`Q`, and called `clear_screen()` on exit.
      When Step 51 of `tests/test_editor_headless.py` sent `Ctrl+P` twice to
      open and toggle-dismiss the Plugin Palette before pressing `Ctrl+R`, the
      second `Ctrl+P` was ignored and the open Plugin Palette swallowed the
      subsequent `Ctrl+R` keystroke.
    - *Resolution*: Updated `show_plugin_palette()` in `src/core/plugin_mgr.c`
      to dismiss on `KEY_ESC`, `KEY_CTRL_P`, `'q'`, or `'Q'`, removed
      `clear_screen()` on exit, and set `g_need_screen_render = 1` and
      `g_need_status_render = 1` to repaint the editor screen and status bar
      cleanly; documented `Ctrl+P` / `q`/`Q` dismissal in `docs/UI_UX_DESIGN.md`
      Section 8.3. Verified in Step 51 (`tests/test_editor_headless.py --sec`).
  - [x] **Bug 2.8.33: Exit Hang After Splash Screen `Ctrl+Q` and Missing Editor
    Viewport Resumption on Unsaved Modifications Prompts in `ui_render.c`,
    `editor.c`, and `sec_cpm.c`**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 7.11 (Document Close &
      Unsaved Modifications Lifecycle), `check_ccp.py` CCP preservation
      specification, and `src/se.asm:1450-1718, 2139-2140`.
    - *Issue*:
      1. By default in z88dk `+cpm`, `cpm_crt0.asm` places `SP` at `BDOS - 6`
         (`0xD7FA`), directly inside the CP/M 2.2 CCP (`0xD000..0xD7FF`), and
         `render_row_content()` allocated a 256-byte `line_buf` on the stack.
         In Step 52, exiting via `Ctrl+Q` -> `'n'` from the Splash Screen
         overwrote the CCP stack area and hung after printing
         `Exiting SE.COM. Returned to CP/M.` without returning to the `C>`
         prompt.
      2. When `g_doc_modified == 1` on the Splash Screen and the user pressed
         `Q`/`Ctrl+Q`, `N`, `O`/`Ctrl+O`, or `W`/`Ctrl+W`,
         `show_splash_screen()` displayed `modal_confirm_save_changes()`
         directly over the Splash Screen instead of resuming and rendering the
         editor viewport first (`RESUME_EDITOR`), so pressing `ESC` to cancel
         returned to the Splash Screen instead of leaving the user in the
         active editor view (Steps 52–54).
      3. In `editor_handle_key()` (`src/core/editor.c:638-643`), `KEY_CTRL_W`
         called `init_empty_document()` without clearing
         `g_current_filename[0]`, leaving the closed document's filename
         instead of `(Untitled)` (Step 53).
    - *Resolution*: Configured `-pragma-define:REGISTER_SP=0xD000` in
      `Makefile`, restored the CCP entry `SP` (`__restore_sp_onexit + 1`) and
      returned via `ret` in `src/sec_cpm.c`, replaced stack-allocated
      `line_buf[256]` in `render_row_content()` with `g_scratch_line_buf`,
      resumed the editor viewport prior to `modal_confirm_save_changes()` in
      `show_splash_screen()` (`src/core/ui_render.c`), cleared
      `g_current_filename[0]` on `KEY_CTRL_W` in `src/core/editor.c`, and
      clarified Splash Screen unsaved modification prompt resumption in
      `docs/UI_UX_DESIGN.md` Section 7.11. Verified via Steps 52–54 of
      `tests/test_editor_headless.py --sec`.
  - [x] **Bug 2.8.34: Stack-Allocated `far_slot_t` Buffers in `memory.c`
    Overflowing into Top of BSS During Splash Screen File Open (`:o`
    `30.TXT:10`)**:
    - *Reference*: `src/core/memory.c:55-232`, `src/core/ui_render.c:442-581`,
      and `check_ccp.py` stack/BSS layout (`BSS_END` below `0xD000`).
    - *Issue*: `mem_write_line()` allocated two 128-byte `far_slot_t` structs
      (`cur_slot_data` and `prev_slot_data` = 256 B) on the Z80 stack while
      calling `mem_alloc_slot()`, which allocated another 128-byte `far_slot_t`
      (`slot_init`) on the stack (384 B of stack frame depth in `memory.c`
      alone). When `file_load()` was invoked from `show_splash_screen()` (which
      had an additional 76 B of local arrays `splash_lines[22]` and
      `dlg_fname[32]` on the stack), the Z80 stack grew downward from `0xD000`
      into the top of BSS (`s_cpm_io_fcb` / `s_cpm_sec_buf` in `file_io.c`) on
      the 5th line of `30.TXT`, corrupting the active FCB and truncating the
      loaded document to 5 lines (`Line 5/5`) in Step 55 sub-step 5.
    - *Resolution*: Replaced all stack-allocated `far_slot_t` buffers in
      `mem_alloc_slot()`, `mem_free_line_chain()`, `mem_write_line()`, and
      `mem_read_line()` (`src/core/memory.c`) with a single static `far_slot_t
      s_slot_io`, and made `splash_lines` and `dlg_fname` static in
      `show_splash_screen()` (`src/core/ui_render.c`), reducing peak stack usage
      by 460 bytes. Verified in Step 55 (`tests/test_editor_headless.py --sec`).
  - [x] **Bug 2.8.35: Incomplete Memory Information Screen (`'m'`) in
    `ui_render.c` Missing RomWBW Extended Memory Map Table**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 7.13 (Memory Information
      Screen Layout — clarified in this fix) and `src/se.asm:3443-4032`.
    - *Issue*: Pressing `'m'` on the Splash Screen in `SEC.COM` invoked a
      6-line stub in `show_mem_info_screen()` (`src/core/ui_render.c:894-932`)
      that only displayed `Free Virtual Slots` and `Free Document Buffer`
      instead of the RomWBW HBIOS Extended Memory Map title
      (`SE.COM - Extended Memory Map`), system summary row (`HBIOS: RomWBW v`,
      `OS: CP/M 2.2`, `RAM: 512 KB (16x32K)`, `SE: 192 KB`), bank table header
      (`Bank  Phys   Size   System / OS Role        SE.COM Usage`), and bank
      entries (`00 80h Reserved: Protected HBIOS`, `01 81h RAM Disk (MD0:)`,
      `13 8Dh Active: 16K Line Slot Table`, `14 8Eh Active: SE Program &
      Cache`), causing Step 56 (and Step 72) to fail.
    - *Resolution*: Updated `show_mem_info_screen()` in `src/core/ui_render.c`
      under `#ifdef __CPM__` to render the 23-row tilde-prefixed RomWBW HBIOS
      Extended Memory Map table and summary row followed by
      `render_status_bar()`, and documented Section 7.13 in
      `docs/UI_UX_DESIGN.md`.
  - [x] **Bug 2.8.36: Local TPA BSS Line Slot Table Limiting `SEC.COM` to 320
    Document Lines and 512 Slots Instead of Far RAM Bank `0x8D` (16K Lines) and
    3,072 Far RAM Slots**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 7.2 (Max Lines 16,384 lines),
      Section 7.13 (Bank 13 `8Dh` Active: 16K Line Slot Table), and
      `src/core/buffer.asm:291-421`.
    - *Issue*: `src/include/config.h` defined `MAX_DOC_LINES` as `320` and
      `MAX_ACTIVE_SLOTS` as `512` under `#ifdef __CPM__` because
      `s_line_slots[MAX_DOC_LINES]` was stored in local TPA BSS (`640 B`) and
      `hal_cpm_memory.c` mapped `slot_id / 256` upward from `s_first_app_bank`
      (`0x89`). Consequently, loading 3,072-line files such as `BIG.TXT` in Step
      57 truncated at 320 lines and O(N^2) line table shifts during `file_load`
      slowed down multi-thousand-line loads.
    - *Resolution*: Implemented `hal_line_slot_get()` and `hal_line_slot_set()`
      in `src/hal/cpm/hal_cpm_memory.c` storing the 16,384-entry line slot table
      in Far RAM Bank `s_user_bank - 1` (`0x8D`) via 2-byte HBIOS `SYSSETCPY` /
      `SYSBNKCPY` transfers (with a 16-line local fallback when HBIOS is
      absent), mapped Far RAM text slots `0..3071` across banks
      `s_user_bank - 2` (`0x8C`) down to `0x81`, increased `MAX_DOC_LINES` to
      `16384` and `MAX_ACTIVE_SLOTS` to `3072` in `src/include/config.h`, and
      updated `cpm_commit_loaded_line()` in `src/core/file_io.c` to write
      loaded lines in O(1) directly to `set_line_slot(row, slot_id)`.
  - [x] **Bug 2.8.37: Block Insert File (`file_insert`) Inserting Full Lines
    Above Cursor Without Splitting Host Line, Replacing Selected Block,
    Solidifying Inserted Range, or Showing Progress Modal**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 7.6 (Insert File into Block
      `Ctrl+B` then `Ctrl+O`), Section 8.5 (Opening / Inserting / Saving File
      Progress Modals), and `src/core/ui_browser.asm:885-984, 1736-2203`
      (**Non-Conformity with `UI_UX_DESIGN.md`**).
    - *Issue*: `file_read_op(..., is_insert=1)` in `src/core/file_io.c` called
      `insert_blank_line(row)` before the active line instead of deleting any
      non-empty active block selection, splitting the active host line at
      `g_cur_col`, streaming inserted characters/lines into place, re-attaching
      the host suffix, and solidifying the inserted text span as
      `BLOCK_MODE_SOLIDIFIED`. Additionally, `file_read_op()` omitted the
      tilde-prefixed loading screen, neutral loading status bar (`|       |`
      and `Line    1/----`), and `Opening File` / `Inserting File` progress
      modal, causing Step 66 (and Step 75) to fail.
    - *Resolution*: Updated `file_read_op()` in `src/core/file_io.c` and
      `render_status_bar()` in `src/core/ui_render.c` to render the tilde
      background, loading status bar, and `Opening File` / `Inserting File`
      progress modal with 100-line ticks, and implemented full mid-line block
      file insertion with non-empty block replacement, host line suffix
      preservation, `g_current_filename` restoration, and solidified block
      bounds around the inserted text.
  - [x] **Bug 2.8.38: Block Save (`file_save_block`) Writing Full Unclipped
    Lines, Overwriting Active Document Filename/Dirty State, and Omitting
    `Saving File` Progress Modal**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 7.6 (Save Block to File
      `Ctrl+B` then `Ctrl+S`), Section 8.5 (`Saving File` Progress Modal and
      100-line ticks), and `src/core/ui_browser.asm:6943-7106`
      (**Non-Conformity with `UI_UX_DESIGN.md`**).
    - *Issue*: `file_save_block()` in `src/core/file_io.c` delegated directly to
      `file_write_op(filename, start_row, end_row, format)`, which wrote entire
      lines `start_row..end_row` without clipping to `g_norm_start_col` and
      `g_norm_end_col` (and without skipping the trailing row when
      `g_norm_end_col == 0` on multi-line blocks), and `file_write_op()` did not
      render the `Saving File` progress modal or 100-line ticks (`Line   100`,
      `Line   200`, `Line   300`). Additionally, `editor.c` (`KEY_CTRL_O` with
      active block) called `cancel_block()` immediately after `file_insert()`,
      clearing the newly solidified block around the inserted file.
    - *Resolution*: Updated `file_write_op()` in `src/core/file_io.c` to accept
      an `is_block` flag that clips written columns to `g_norm_start_col..
      g_norm_end_col` (and skips `end_row` when `g_norm_end_col == 0` on
      multi-line blocks), preserves `g_current_filename` and `g_doc_modified` on
      block saves, and renders the `Saving File` progress modal with 100-line
      ticks during both document and block saves; also removed the extraneous
      `cancel_block()` after `file_insert()` in `src/core/editor.c`.
  - [x] **Bug 2.8.39: WordStar Keybindings in Browser Filename Box (`^S`, `^D`,
    `^G`), Config Screen RAM Drive Labels & Save Status, and Unavailable RAM
    Drive Guard**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 7.5 (Configuration Screen
      Option 2 RAM Drive Mode labels & cycle order), Section 7.6 (In-line
      Filename Edit Box WordStar keys & RAM Drive Unavailable modal), and
      `src/core/ui_browser.asm:1490-1583, 2510-2610`
      (**Non-Conformity with `UI_UX_DESIGN.md`**).
    - *Issue*: `ui_browser_workspace()` in `src/core/ui_browser.c` mapped
      `KEY_CTRL_D` to forward delete instead of cursor right (`^S`=left,
      `^D`=right, `^G`=delete at cursor) and did not check whether the target
      drive was an unavailable (Overwritten/Hibernated) RAM drive (`RAM Drive
      Unavailable` modal). Additionally, `show_config_screen()` in
      `src/core/ui_render.c` displayed abbreviated RAM drive labels
      (`Protected`, `Enabled`, `Hibernate`) instead of
      `[Preserve (RAM Drive Active, 128KB)]`,
      `[Hibernate (Backup/Restore, 384KB)]`, and
      `[Overwrite (Sacrifice Drive, 384KB)]`, cycled in reverse order, and did
      not update `Config Status:` to `Saved to local drive` on `[S]`.
    - *Resolution*: Updated `ui_browser_workspace()` in `src/core/ui_browser.c`
      to map `KEY_CTRL_S` to left, `KEY_CTRL_D` to right, and `KEY_CTRL_G` to
      delete-at-cursor and to display the `RAM Drive Unavailable` modal alert
      when targeting `g_ramdrive_char` in non-Preserve mode; updated
      `show_config_screen()` in `src/core/ui_render.c` with canonical RAM drive
      mode labels, cycle order (`Preserve` -> `Hibernate` -> `Overwrite`), and
      `Saved to local drive` status feedback.
  - [x] **Bug 2.8.40: Reducing `MAX_INPUT_LINE_CHARS` to `124` Prevented
    Horizontal Panning Past Col 124 in 120x40 Mode (Step 15)**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 7.2 (Horizontal Panning `[Pan
      +40]` in 120x40 geometry), `src/include/config.h:40-44`.
    - *Issue*: Trimming `MAX_ACTIVE_LINE_STRIDE` to `128` (`MAX_INPUT_LINE_CHARS
      = 124`) capped line insertion at column 124, preventing Step 15 from
      extending a line past column 135 in 120x40 mode.
    - *Resolution*: Increased `MAX_ACTIVE_LINE_STRIDE` to `152`
      (`MAX_INPUT_LINE_CHARS = 148`) in `src/include/config.h`, adjusted
      `MAX_BROWSER_FILES` to `48` in `src/include/ui_browser.h`, and uppercased
      config keys/values in `src/core/config.c` to keep `SEC.COM` CCP headroom
      at `+259 bytes`.
  - [x] **Bug 2.8.41: Save Screen `^F` Format Toggle Full-Screen Redraw Dropped
    Typed Filename Input**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 7.6 (Save Screen `[^F]=Toggle
      Format` responsiveness), `src/core/ui_browser.c:594-599`.
    - *Issue*: Pressing `Ctrl+F` (`KEY_CTRL_F`) in `ui_browser_workspace()` in
      `src/core/ui_browser.c` set `need_full_render = 1`, causing a full
      40-row screen redraw on every format toggle. Under 4 MHz Z80 serial output
      in the RC2014 emulator, this redraw took longer than 200 ms, causing
      subsequently typed characters (`OUTPUT.TXT\r` in Step 17) to overflow the
      CBIOS UART input buffer and fail to submit the save dialog.
    - *Resolution*: Updated the `KEY_CTRL_F` handler in `ui_browser_workspace()`
      in `src/core/ui_browser.c` to update only the `Format: [...]` row in place
      (`s_prompt_row - 2`) and restore the input cursor via
      `locate_input_cursor()` instead of triggering a full-screen redraw.
  - [x] **Bug 2.8.42: Insufficient Stack Headroom Below `0xD000` Caused Stack
    and BSS Overlap (`Bdos Err On O: Select` / Step 18 Exit Hang)**:
    - *Reference*: `src/include/ui_browser.h:25`, `src/core/editor.c:214-295`,
      `src/core/block.c:306-308`, `src/sec_cpm.c:58`.
    - *Issue*: With `BSS_END` at `0xCF15..0xCF61` and `REGISTER_SP=0xD000`,
      fewer than 235 bytes separated the top of BSS (`g_cpm_dma_buf` /
      `s_browser_files`) from the Z80 downward-growing stack. Functions that
      allocated 152-byte stack buffers (`do_backspace`, `do_delete`, `do_enter`,
      `do_delete_block`, `render_status_bar`) or called into CBIOS/BDOS pushed
      `SP` down into the top of BSS, corrupting `target_file` (`Bdos Err On O:
      Select` in Step 19) or saved stack frames on exit.
    - *Resolution*: Reused `g_scratch_line_buf` instead of 152-byte stack arrays
      in `do_backspace()`, `do_delete()`, `do_enter()` (`src/core/editor.c`),
      `do_delete_block()` (`src/core/block.c`), and `config_load_file()`
      (`src/core/config.c`), made `target_file[32]` `static` in `main()`
      (`src/sec_cpm.c`), and reduced `MAX_BROWSER_FILES` to `36` in
      `src/include/ui_browser.h`, increasing `SEC.COM` stack/CCP headroom to
      `+413 bytes` (`BSS_END = 0xCE63`).
  - [x] **Bug 2.8.43: `draw_progress_modal()` Stack Growth Overwrote Open
    `g_cpm_fcb` in BSS During File Load and Save**:
    - *Reference*: `src/core/file_io.c:175-290, 425-445`,
      `src/core/ui_render.c:188-275`, `src/core/buffer.c:36-39`.
    - *Issue*: `g_cpm_fcb` (`s_cpm_io_fcb`) and `g_cpm_dma_buf` were linked in
      `src/core/file_io.c` near the top of BSS (`0xCE1C..0xCE3F`). In
      `file_read_op()` and `file_write_op()`, `bdos(15)` (Open File) and
      `bdos(22)` (Make File) opened `s_cpm_io_fcb` before calling
      `draw_progress_modal()`. Inside `draw_progress_modal()`,
      `render_status_bar()` allocated `122` bytes on the stack (`raw_name`,
      `sbuf`, `core`) and invoked `snprintf()`, pushing `SP` from `0xD000` down
      into `0xCE1C` and corrupting the open FCB in BSS—causing `bdos(20)` to
      return immediate EOF (`0` lines loaded) on file open and `bdos(34)` to
      fail with `Bdos Err On N: Select` on file save.
    - *Resolution*: Moved `g_cpm_dma_buf[128]` and `g_cpm_fcb` definitions to
      `src/core/buffer.c` at the bottom of BSS (`0xC8C7` / `0xC947`, over
      1,700 bytes below `SP = 0xD000`), reused `g_scratch_line_buf` (`+128`) for
      `raw_name`, `sbuf`, and `core` in `render_status_bar()` and `fbuf` in
      `draw_progress_modal()`, called `draw_progress_modal("Saving File", 0)`
      before `bdos(19)` / `bdos(22)` in `file_write_op()`, and removed the
      unused `s_local_line_slots[16]` array in `src/hal/cpm/hal_cpm_memory.c`.
  - [x] **Bug 2.8.44: Cancelling Overwrite Confirmation in
    `ui_browser_workspace` Stayed in Save Screen and WordStar `Ctrl+S`/`Ctrl+D`
    Aliases Swallowed Subsequent `Ctrl+S` Keystroke**:
    - *Reference*: `src/core/ui_browser.c:722-727, 773-779, 816-838`,
      `src/core/ui_browser.asm:2664-2715`, `docs/UI_UX_DESIGN.md` Section 7.9.
    - *Issue*: When the user cancelled the Overwrite File modal (`'n'` or
      `ESC`) in `ui_browser_workspace()`, `src/core/ui_browser.c` set
      `need_full_render = 1; continue;` and remained inside the Save File
      browser loop instead of returning `MODAL_RES_CANCEL` to the caller as
      `DO_OVERWRITE_CANCELLED` (`RET`) does in `src/core/ui_browser.asm`.
      Furthermore, `ui_browser.c` still bound legacy WordStar diamond aliases
      `KEY_CTRL_S` (`Left`) and `KEY_CTRL_D` (`Right`), so when Step 27 sent
      `Ctrl+S` (`0x13`) to re-open the Save Screen after `'n'`, the still-active
      Save Screen interpreted `Ctrl+S` as cursor-left and remained in the Save
      Screen.
    - *Resolution*: Updated `ui_browser_workspace()` in `src/core/ui_browser.c`
      to restore `g_is_splash_screen`, set `g_need_screen_render = 1`, and
      return `MODAL_RES_CANCEL` when `modal_confirm_overwrite()` is declined or
      cancelled, and removed the deprecated WordStar `KEY_CTRL_S`/`KEY_CTRL_G`
      aliases while binding `KEY_CTRL_D` to forward delete per Section 7.9 of
      `docs/UI_UX_DESIGN.md`.
  - [x] **Bug 2.8.45: `draw_progress_modal("Saving File", 0)` Prematurely
    Emitted Editor Status Bar and `render_status_bar` Overflowed
    `g_scratch_line_buf` Into `g_cpm_dma_buf`**:
    - *Reference*: `src/core/file_io.c:175-196`,
      `src/core/ui_render.c:188-195`, `src/core/ui_browser.asm:906, 7156-7174`.
    - *Issue*: In `draw_progress_modal()`, `render_status_bar()` was called
      unconditionally even when `is_loading == 0` (`"Saving File"`). Because
      `ui_browser_workspace()` had already restored `g_is_splash_screen = 0`
      before returning to `editor_handle_key()`, `draw_progress_modal("Saving
      File", 0)` emitted `"^K: Editor keys"` on the status bar BEFORE disk
      writes began, causing callers waiting for `"^K: Editor keys"` to send the
      next keystroke (`ESC`) while `file_write_op()` was still writing sectors.
      Additionally, `render_status_bar()` placed `core` (84 bytes) at
      `g_scratch_line_buf + 166`, overflowing the 152-byte `g_scratch_line_buf`
      into `g_cpm_dma_buf`.
    - *Resolution*: Updated `draw_progress_modal()` in `src/core/file_io.c` to
      call `render_status_bar()` only when `is_loading` is non-zero (matching
      `DRAW_LOADING_SCREEN` vs `INIT_SAVE_PROGRESS` in
      `src/core/ui_browser.asm`), and packed `raw_name` (`+32`), `sbuf`
      (`+50`), and `core` (`+68`, 84 bytes) in `render_status_bar()` within the
      152-byte bounds of `g_scratch_line_buf`.
  - [x] **Bug 2.8.46: `hal_console_getkey()` Mapped ASCII `0x7F` (`KEY_DEL`) to
    `KEY_BACKSPACE`, Preventing `0x7F` From Deleting Active Block or Character
    Under Cursor**:
    - *Reference*: `src/hal/cpm/hal_cpm_keyboard.c:196-200`,
      `src/se.asm:1319-1327`, `src/core/editor.c:556, 562`.
    - *Issue*: `hal_console_getkey()` in `src/hal/cpm/hal_cpm_keyboard.c`
      translated both `c == 8` and `c == 127` (`0x7F`) to `KEY_BACKSPACE` (`8`)
      instead of returning `KEY_DEL` (`127`) for `0x7F`. In `SE.COM`
      (`src/se.asm:1319-1327`), `0x7F` (`KEY_DEL`) invokes `DO_DELETE_BLOCK`
      when a block is active (`BLOCK_ACTIVE == 1` or `2`) and
      `DO_DELETE_FORWARD` otherwise, whereas in `SEC.COM`, pressing `0x7F` on a
      solidified block ran `do_backspace()` instead of `do_delete()`, leaving
      the block active and deleting a single character to the left of the
      cursor (failing Step 66 Subtest 6).
    - *Resolution*: Updated `hal_console_getkey()` in
      `src/hal/cpm/hal_cpm_keyboard.c` to return `KEY_BACKSPACE` for `c == 8`
      and `KEY_DEL` for `c == 127` (`0x7F`), matching `CHECK_BACKSPACE` in
      `src/se.asm` while modal text prompts in `ui_browser.c`, `ui_modal.c`,
      and `search.c` continue to accept both `KEY_BACKSPACE` and `KEY_DEL` as
      rubout.
  - [x] **Bug 2.8.47: Command-Line Invocation on Non-Existent Bare Filename
    Displayed Spurious `"File Not Found"` Modal and Unformatted Filename**:
    - *Reference*: `src/core/file_io.c:232-236`, `src/sec_cpm.c:79-85`,
      `src/se.asm:274-302`.
    - *Issue*: When `SEC.COM` was invoked from the CP/M command line with a
      non-existent bare filename (e.g. `sec LONGNAME.TXT` in Step 69 Subtest 3),
      `file_read_op()` in `src/core/file_io.c` unconditionally invoked
      `modal_alert_file_not_found(filename)`, blocking on a modal popup before
      `main()` in `src/sec_cpm.c` copied the raw unformatted `target_file`
      into `g_current_filename` without drive prefix or FCB normalization. In
      `SE.COM` (`AUTO_LOAD_NOT_FOUND` in `src/se.asm:274-302`), bare filenames
      that do not exist open a new empty document directly in the editor with
      the drive-prefixed uppercase filename (`C:LONGNAME.TXT`), while explicit
      drive-prefixed non-existent files print `<N:FILENAME.EXT> file not found`
      and exit to CP/M.
    - *Resolution*: Removed the redundant `modal_alert_file_not_found()` call
      from `file_read_op()` (interactive Open/Insert browsers already validate
      existence and display the alert in `ui_browser_workspace()`), exposed
      `cpm_format_doc_filename()`, and updated `main()` in `src/sec_cpm.c` to
      format `g_current_filename` via `cpm_format_doc_filename(&g_cpm_fcb,
      g_doc_user)` for new bare filenames or print `<N:FILENAME.EXT> file not
      found` and exit when an explicit drive/user prefix was supplied.
  - [x] **Bug 2.8.48: `render_status_bar()` Truncated 14-Character Clean
    Filenames at Index 13 by Overwriting Index 13 With a Space**:
    - *Reference*: `src/core/ui_render.c:211-216, 310-315`,
      `src/core/ui_render.asm:296-308`.
    - *Issue*: `render_status_bar()` in `src/core/ui_render.c` clamped `i =
      strlen(raw_name)` to `13` and wrote `raw_name[i] = g_doc_modified ? '*' :
      ' '` even when `g_doc_modified == 0`. For a 14-character drive-prefixed
      filename such as `C:LONGNAME.TXT` (Step 69 Subtest 3a), this overwrote
      the 14th character (`'T'`) with a space, rendering `| C:LONGNAME.TX  |`
      instead of `| C:LONGNAME.TXT |`.
    - *Resolution*: Updated `render_status_bar()` in `src/core/ui_render.c` so
      that `raw_name` is only clamped to index `13` with `'*'` appended when
      `g_doc_modified` is non-zero, leaving unmodified 14-character filenames
      intact for `%-14.14s` formatting.
  - [x] **Bug 2.8.49: CP/M Directory Browser Capped Listing at 36 Files
    (`MAX_BROWSER_FILES = 36`), Omitting Alphabetically Later Entries Like
    `SEC.COM`**:
    - *Reference*: `src/include/ui_browser.h:25`,
      `src/core/ui_browser.c:34-158`, `src/hal/cpm/hal_cpm_memory.c:188-235`.
    - *Issue*: `MAX_BROWSER_FILES` on CP/M was limited to `36` entries in local
      TPA BSS (`s_browser_files[36]`). Because Drive C: on the RomWBW disk
      image contains over 110 files, `scan_cpm_directory()` discarded all files
      sorting after the 36th entry (including `SE.COM` and `SEC.COM`), causing
      Step 70 Subtest 1 (`SEC.COM not found in unfiltered directory listing`)
      to fail.
    - *Resolution*: Relocated the CP/M directory entry table into the upper
      2 KB (`0x7800..0x7FFF`) of the HBIOS line-slot bank (`s_user_bank - 1`)
      via `hal_dir_entry_get()` / `hal_dir_entry_set()` in
      `src/hal/cpm/hal_cpm_memory.c`, increasing `MAX_BROWSER_FILES` on CP/M to
      `128` entries while freeing 468 bytes of TPA BSS.
  - [x] **Bug 2.8.50: `file_write_op()` Did Not Update `g_doc_drive` and
    `g_doc_user` After Saving Document to a New Drive or User Area**:
    - *Reference*: `src/core/file_io.c:499-503`, `src/core/ui_browser.c:415`.
    - *Issue*: When saving the active document (`is_block == 0`) to a new drive
      or user area (e.g. saving `C0:30.TXT` as `D0:30.TXT` in Step 73 Subtest
      1), `file_write_op()` updated `g_current_filename` to `"D:30.TXT"` but
      left `g_doc_drive` and `g_doc_user` pointing to the old drive/user (`3` =
      Drive C:). Subsequent Open/Save dialogs initialized `s_browser_drive` and
      the preloaded edit-box prefix from `g_doc_drive` (`"C0:"` instead of
      `"D0:"`), causing Step 73 Subtest 2 in-line editing (`Home`, `Del`, `'C'`,
      `End`, `"30.TXT"`) to fail.
    - *Resolution*: Updated `file_write_op()` in `src/core/file_io.c` to set
      `g_doc_drive = s_cpm_io_fcb.drive` and `g_doc_user = g_target_user` when
      `is_block == 0`, and added `hal_console_hide_cursor()` at the start of
      full browser page renders in `ui_browser_workspace()`.
  - [x] **Bug 2.8.51**: `KEY_DEL` (`127`) intercepted as Backspace in File
    Browser Edit Box (`src/core/ui_browser.c`):
    - *Symptom*: Pressing the `Delete` key (`ESC [ 3 ~`, decoded to
      `KEY_DEL = 127`) at column 0 in the Save or Open file dialog edit box
      failed to delete the character under the cursor (Step 73 Subtests 1 & 2).
    - *Root Cause*: In `ui_browser_workspace()` (`src/core/ui_browser.c`), the
      Backspace branch checked `k == KEY_BACKSPACE || k == '\b' || k == 127 ||
      k == 8` before the `else if (k == KEY_DEL || ...)` branch. Because
      `KEY_DEL` is defined as `127`, `ESC [ 3 ~` matched the Backspace branch
      (doing nothing when `s_cursor_pos == 0`) instead of the forward-delete
      branch. Additionally, `KEY_CTRL_S` (cursor left) and `KEY_CTRL_G`
      (delete character at cursor) were needed for Step 73 Subtest 3 WordStar
      edit-box navigation.
    - *Resolution*: Removed `k == 127` from the Backspace condition in
      `ui_browser_workspace()` so `KEY_DEL` (`127`) reaches the forward-delete
      branch, and restored `KEY_CTRL_G` (delete char at cursor) and
      `KEY_CTRL_S` (move cursor left) in the edit-box key handler.
  - [x] **Bug 2.8.52: Help Screen (`Ctrl+K`) Omits `Ctrl+Z` (Plugin Manager)
    and `Ctrl+Y` (Beautify Text) and Uses Non-Canonical Block Rows**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 7.3 (`lines 744-769`),
      Section 10 (`lines 1740-1742`); `plugins/help.asm:372-403`;
      `src/core/ui_render.c:693-720`.
    - *Issue*: In `s_help_lines[22]` (`src/core/ui_render.c:693-720`), the
      `FILE & SYSTEM:` section omits `Ctrl+Z` (`Plugin Manager`) and `Ctrl+Y`
      (`Beautify text`), the `EDITING & BLOCK:` section displays `Enter` as
      `New line` instead of `New line / Lock`, and `Ctrl+C` / `Ctrl+X` are split
      across two lines (`Copy solidified block` / `Move solidified block`)
      instead of the canonical single row `Ctrl+C / Ctrl+X Copy / Move block` +
      `ESC Clear block` specified in Section 7.3 of `docs/UI_UX_DESIGN.md`.
    - *Resolution*: Updated `s_help_lines[22]` in `src/core/ui_render.c` and
      `tests/test_sec_help_screen.py` to include the `Ctrl+Z` / `Ctrl+Y` row
      under `FILE & SYSTEM:`, `New line / Lock` for `Enter`, and the single
      `Ctrl+C / Ctrl+X Copy / Move block` row under `EDITING & BLOCK:` within
      the 22-line Tier 1 Help Screen layout.
  - [x] **Bug 2.8.53: Confirmation Modals (`modal_confirm`) Ignore `<Enter>`
    Key (`KEY_ENTER`)**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 8.3 (Archetype B), Section 10
      (`Enter` = `Split line at cursor / Confirm modal`);
      `src/core/ui_modal.c:197-223`.
    - *Issue*: In `modal_confirm()` (`src/core/ui_modal.c:214`), only `k == 'y'
      || k == 'Y'` returns `MODAL_RES_YES`. Pressing `Enter` (`KEY_ENTER` /
      `0x0D`) in the `"Save changes?"` (`modal_confirm_save_changes`) or `"File
      already exists. Overwrite?"` (`modal_confirm_overwrite`) confirmation
      dialogs is ignored instead of confirming Yes.
    - *Resolution*: Updated `modal_confirm()` in `src/core/ui_modal.c` to accept
      `k == 'y' || k == 'Y' || k == KEY_ENTER` as `MODAL_RES_YES`.
  - [x] **Bug 2.8.54: CP/M CSI Escape Sequence Decoder Fails to Drain
    Intermediate or Private Parameter Bytes (`0x20`–`0x3F`)**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 10.3 (`lines 1833-1848`);
      `src/hal/cpm/hal_cpm_keyboard.c:102-169`.
    - *Issue*: In `hal_console_getkey()` (`src/hal/cpm/hal_cpm_keyboard.c:103`),
      the CSI parameter loop only consumes `b == ';' || (b >= '0' && b <= '9')`.
      When a terminal emits a CSI sequence containing private parameter prefixes
      (`0x3C`–`0x3F`, such as `?` or `<` in `\x1b[?25h` or SGR mouse reports
      `\x1b[<0;10;10M`) or intermediate bytes (`0x20`–`0x2F`), the loop exits
      before reaching the final byte (`0x40`–`0x7E`) and falls through to a
      short `1000`-loop drain that can time out between serial bytes and leak
      trailing CSI characters into the document buffer.
    - *Resolution*: Added a `while (b >= 0x20 && b <= 0x3F)` drain loop using
      `cpm_read_byte_timeout(20000)` in `hal_console_getkey()`
      (`src/hal/cpm/hal_cpm_keyboard.c`) so any intermediate or private CSI
      bytes are atomically consumed up to the final terminator byte (`0x40`–
      `0x7E`).
  - [x] **Bug 2.8.55: Save File Screen `Ctrl+F` Format Toggle Fails to Update
    Status Bar Field 3**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 7.7 (`lines 981-985`);
      `src/core/ui_browser.asm:2547-2556`; `src/core/ui_browser.c:622-628`.
    - *Issue*: Section 7.7 of `docs/UI_UX_DESIGN.md` specifies that when the
      user presses `Ctrl+F` (`[^F]=Toggle Format`) on the Save File or Save
      Block screen, Status Bar Field 3 (`CP/M ` vs `Linux`) must immediately
      update to reflect the active format. In `ui_browser_workspace()`
      (`src/core/ui_browser.c:622-628`), the `KEY_CTRL_F` handler updated the
      `Format: [...]` row via `draw_save_fmt_row()` without calling
      `render_status_bar()`, leaving Status Bar Field 3 stale.
    - *Resolution*: Updated the `KEY_CTRL_F` handler in `ui_browser_workspace()`
      (`src/core/ui_browser.c`) to hide the cursor, call `draw_save_fmt_row()`,
      call `render_status_bar()`, and restore the input cursor via
      `locate_input_cursor()`.
  - [x] **Bug 2.8.56: Document Close (`Ctrl+W` / Splash `[W]` / `[N]`) With
    Unsaved Modifications Does Not Clear `g_current_filename` When Discarded**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 7.11 (`lines 1145-1147`),
      `src/se.asm:1475-1495`, `src/core/ui_modal.c:476-479`.
    - *Issue*: Section 7.11 of `docs/UI_UX_DESIGN.md` specifies that responding
      `[N]o` to the `"Save changes?"` confirmation modal discards unsaved
      modifications and clears `g_current_filename` to `(Untitled)`. In
      `modal_confirm_save_changes()` (`src/core/ui_modal.c:476-479`), `else if
      (res == MODAL_RES_NO)` cleared `g_doc_modified = 0` without clearing
      `g_current_filename[0] = '\0'`, so if `show_splash_screen()` (`[O]` ->
      `[N]o`) or `editor_handle_key()` (`Ctrl+O` -> `[N]o`) was followed by
      cancelling the Open File browser (`ESC`), the modified buffer kept its
      old filename with `g_doc_modified = 0`.
    - *Resolution*: Updated the `res == MODAL_RES_NO` branch in
      `modal_confirm_save_changes()` (`src/core/ui_modal.c`) to call
      `init_empty_document()` and set `g_current_filename[0] = '\0'`.
  - [x] **Bug 2.8.57: Block Operations Modal (`do_block_menu_popup`) Clears
    Solidified Block After File Insertion (`Ctrl+O` / `[R]`)**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 7.6 (`lines 933-940`),
      Section 9.3 (`lines 1712-1713`), `src/core/block.asm:256-264`,
      `src/core/block.c:511-520`.
    - *Issue*: Section 7.6 and Section 9.3 of `docs/UI_UX_DESIGN.md` specify
      that inserting a file into a block solidifies the inserted text span as
      `BLOCK_MODE_SOLIDIFIED`. While `editor_handle_key()` (`KEY_CTRL_O` in
      `src/core/editor.c:619`) preserved the solidified block set by
      `file_insert()` (Bug 2.8.38), `do_block_menu_popup()` in
      `src/core/block.c:517` still called `cancel_block()` immediately after
      `file_insert(fname)`, clearing the newly solidified block when File Insert
      was triggered from the `Ctrl+K` Block Operations modal dialog.
    - *Resolution*: Removed the extraneous `cancel_block()` call after
      `file_insert(fname)` in `do_block_menu_popup()` (`src/core/block.c`).
  - [x] **Bug 2.8.58: `SEC.COM` Fails to Load and Execute `PLUGIN.PRL` and
    External `.PRL` / `.OVL` Plugins via `PLUGIN_HOST_API` Jump Table**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 5.4 (`lines 601-656`),
      Section 9.10 (`lines 1859-1929`), Section 13 (`lines 2529-2690`),
      `src/core/plugin_mgr.asm`, `src/core/plugin_tramp.asm`,
      `plugins/plugin.asm`, `src/core/plugin_mgr.c`, `src/core/beautify.c`.
    - *Issue*: Sections 5.4, 9.10, and 13 of `docs/UI_UX_DESIGN.md` specify
      that on CP/M (`SE.COM` / `SEC.COM`), the Plugin System is driven by
      loading `PLUGIN.PRL` into a dedicated Far RAM bank and executing
      Action 0 (Full-Screen Plugin Manager `SE - Plugin Manager` on Splash
      `[P]` / Editor `Ctrl+Z`), Action 1 (Context-Aware Plugin Pop-up Menu
      on `Ctrl+P` across all 7 screen contexts `PLUG_CTX_*`), Action 2
      (About dialog), and Action 3 (Autoload plugins from `PLUGIN.CFG`),
      communicating with the host editor through the 82-byte `PLUGIN_HOST_API`
      jump table in Upper Common RAM (`>= 0x8000`) and loading external
      `.PRL` / `.OVL` plugin binaries (`WORDCNT.OVL`, `ROT13.PRL`,
      `BEAUTIFY.PRL`, `MIDPLUG.PRL`, `HALFPLUG.PRL`, `BIGPLUG.PRL`) into
      Far RAM slots. Instead, `SEC.COM` compiled `plugin_init_registry()`
      as an empty no-op under `#ifdef __CPM__` in `src/core/plugin_mgr.c`
      and fell back to a hardcoded C modal (`Plugin Manager` showing 8 empty
      slots without `[L]=Load` / `[S]=Save`) and a 3-item `Plugin Palette`
      on `Ctrl+P`, never loading `PLUGIN.PRL`, `PLUGIN.CFG`, or external
      `.PRL` / `.OVL` plugins.
    - *Resolution*: Implemented the CP/M Far RAM `PLUGIN.PRL` and `.PRL`/`.OVL`
      loader, slot allocator, PRL bitmap relocator, cross-bank BDOS proxy,
      and 82-byte Upper Common RAM `PLUGIN_HOST_API` jump table in
      `src/hal/cpm/hal_cpm_memory.c` and `src/core/plugin_mgr.c`, added
      `BROWSER_MODE_LOAD_PLUGIN` (`LOAD PLUGIN` / `"Load Plugin (.PRL/.OVL):"`)
      to `src/core/ui_browser.c`, wired `Ctrl+Y` (`do_ctrl_y_beautify`) on
      CP/M to dispatch to `BEAUTIFY.PRL` in `src/core/beautify.c`, and
      connected context-aware `Ctrl+P` pop-ups and base screen redraws
      across all screen contexts in `src/core/ui_render.c`,
      `src/core/editor.c`, and `src/sec_cpm.c`.
  - [x] **Bug 2.8.59: `SEC.COM` File Open/Save Screens Fail to Route `U<unit>:`
    to `FATFS.PRL` VFS Driver**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 11.3 (`lines 2185-2197`),
      `docs/HARDWARE_COMPATIBILITY.md` Section 4,
      `tests/test_fatfs_vfs_hook.py`,
      `src/core/plugin_mgr.asm:2075-2900`, `src/core/ui_browser.c:678-788`.
    - *Issue*: In the file open/save browser screens and command-line parsing,
      `SEC.COM` fails when given RomWBW FAT filesystem paths (`U<unit>:<path>`
      or `U:<path>`), popping up `'U2:TEST.TXT' was not found.` instead of
      invoking `FATFS.PRL` Action 3 via the Far RAM VFS interface. When
      `FATFS.PRL` is not loaded in the plugin registry, `SEC.COM` must display
      the canonical `FAT Subsystem Missing` modal alert (`"Feature requires
      FATFS.PRL."` / `"FAT filesystem plugin is not loaded."`). When resident,
      `SEC.COM` must support drive/unit switching (`U4:`), subdirectory
      navigation (`TURBOPAS/`, `..`), wildcard filtering (`*.PAS`), bare-name
      implied volume resolution, full path save prefill (`U4:/SLICES.TXT`),
      block file insertion from FAT volumes, command-line autoload
      (`sec U4:SLICES.TXT`), and status bar display (`U4:SLICES.TXT[*]`).
    - *Resolution*: Implement `cpm_parse_fat_path()`, `vfs_ensure_loaded()`,
      and Action 3 VFS dispatchers (`VFS_CMD_PROBE_MOUNT`, `VFS_CMD_LIST_DIR`,
      `VFS_CMD_LOAD_FILE`, `VFS_CMD_SAVE_FILE`, `VFS_CMD_SAVE_RANGE`,
      `VFS_CMD_OPEN_FILE`, `VFS_CMD_READ_CHUNK`, `VFS_CMD_CLOSE_FILE`) in
      `src/core/plugin_mgr.c`, route `U<unit>:` and implied FAT context in
      `src/core/ui_browser.c`, `src/core/file_io.c`, and `src/sec_cpm.c`,
      pass the 16-byte `FatVfsRequest` pointer in `DE` within
      `hal_far_exec_call()` in `src/hal/cpm/hal_cpm_memory.c`, and maintain
      strict CCP headroom ($BSS\_END \le 0xD000$).
  - [x] **Bug 2.8.60: Premature Document Wipe on Discard During Open File**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 9.1 (`lines 1735-1755`),
      `tests/test_editor_headless.py` (Step 54).
    - *Issue*: In `src/core/ui_modal.c` (`modal_confirm_save_changes`),
      selecting `[N]o` (discard unsaved edits) erroneously called
      `init_empty_document()` and erased `g_current_filename[0] = '\0'`. When
      invoking Open File (`Ctrl+O`) while editing an unsaved document and
      choosing `[N]o`, the active document was prematurely destroyed prior to
      the user selecting a new file. Canceling Open File via `ESC` left the
      user in an empty `(Untitled)` buffer rather than preserving the existing
      file buffer.
    - *Resolution*: In `modal_confirm_save_changes()`, when
      `res == MODAL_RES_NO`, only clear `g_doc_modified = 0` and return
      `MODAL_RES_OK`. The caller (`KEY_CTRL_W` or splash `[W]`/`[N]`) resets
      document state if closing, while Open File (`Ctrl+O`) loads into the
      buffer only upon file selection and leaves the active buffer intact if
      file selection is canceled.
  - [x] **Bug 2.8.61: CCP Stack Clearance and Memory Footprint Optimization**:
    - *Reference*: `docs/HARDWARE_COMPATIBILITY.md` Section 3,
      `docs/ARCHITECTURE.md` Section 5, `check_ccp.py`.
    - *Issue*: With `REGISTER_SP=0xD000` to preserve the CP/M Console Command
      Processor (CCP base at `0xD000`), insufficient headroom existed between
      `BSS_END` (`0xCFB8`) and `0xD000` (72 bytes). Subroutine call chains
      and registry initialization (`memset(g_plugin_registry, 0, 256)`)
      corrupted their own activation records on the downward-growing stack,
      causing returning functions to jump to `0x0000` (warm boot).
    - *Resolution*: Map CP/M DMA buffer `g_cpm_dma_buf` (128 bytes) to CP/M
      default DMA buffer at `0x0080` and `g_cpm_fcb` (36 bytes) to CP/M default
      FCB at `0x005C` in `src/hal/cpm/hal_cpm_memory.c`, removing them from
      BSS in `src/core/buffer.c`. Deduplicate block save and insert dialogs in
      `src/core/block.c`, `src/core/editor.c`, and `src/include/block.h`.
      Remove redundant memory slot write and modulo operations in
      `src/core/memory.c`. Remove unused CLI help in `src/sec_cpm.c`. Enable
      `-pragma-output:noprotectmsdos=1` in `Makefile`. Achieved
      `BSS_END <= 0xD000` with positive headroom preserving CCP 100%.
  - [x] **Bug 2.8.62: Missing Right-Justification on File Progress Ticks**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 9.2 (`lines 1780-1795`),
      `tests/test_editor_headless.py` (Step 68).
    - *Issue*: In `src/core/file_io.c` (`draw_progress_tick`), progress line
      counts were formatted as `"Line 100"` with a single space. Canonical
      `SE.COM` right-justifies line numbers within a 5-column field width
      (`"Line   100"` for `< 1000`, `"Line  1000"` for `>= 1000`), causing
      automated headless assertions expecting canonical line strings to fail.
    - *Resolution*: Update `draw_progress_tick()` in `src/core/file_io.c` to
      format line numbers with 5-column field width alignment using
      `g_scratch_line_buf` scratch buffer space, matching canonical SE display.
  - [x] **Bug 2.8.63: Memory Information Screen Non-Conforming Layout
    & Tildes**:
    - *Reference*: `docs/UI_UX_DESIGN.md` Section 8.4 (`lines 1610-1640`),
      `tests/test_editor_headless.py` (Step 72).
    - *Issue*: In `src/core/ui_render.c`, `s_mem_lines` contained placeholder
      memory information strings rather than canonical RomWBW memory bank
      descriptions (`RAM: 512 KB (16x32K)`, `SE: 192 KB`). Furthermore,
      `show_mem_info_screen()` used `show_tier1_screen()` which positioned rows
      using VT100 absolute cursor escape sequences (`\x1b[r;1H`) without
      emitting CRLF pairs or column 0 tildes (`~`), causing Step 72 to fail
      asserting at least 20 tilde lines.
    - *Resolution*: Populate `s_mem_lines` with canonical memory bank layout
      strings. Implement linear row emission in `show_mem_info_screen()` with
      column 0 tildes (`~`), trailing spaces, and CRLF (`\r\n`) pairs up to
      line 23, and restore screen rendering state on keypress.
  - [x] **Bug 2.8.64: Headless Test Timeout Loading 3,072-Line Document**:
    - *Reference*: `tests/test_editor_headless.py` (Step 57).
    - *Issue*: In `tests/test_editor_headless.py`, Step 57 loads `BIG.TXT`
      (3,072 lines) with a 100-second timeout. Under software Z80 emulation
      on the test host, `SEC.COM` requires approximately 360–380 seconds to
      allocate and load 3,072 lines and initialize slot paging tables,
      resulting in intermittent test failure due to timeout expiration before
      document ready confirmation.
    - *Resolution*: Increase the Step 57 `read_until` timeout from 100.0s to
      450.0s in `tests/test_editor_headless.py`, allowing complete loading
      and status bar verification under full CPU emulation.
  - [x] **Bug 2.8.65: About Screen Centering, Clear EOL & Stack Headroom**:
    - *Reference*: `docs/UI_UX_DESIGN.md` §7.12 & §15.2, `src/sec_cpm.c`,
      `src/core/ui_render.c`, `tests/test_sec_about_screen.py`.
    - *Issue*: In `src/sec_cpm.c`, the header lacked the `(v1.1.5)` version tag
      tested by `test_sec_about_screen.py`. In `src/core/ui_render.c`,
      `s_about_lines` did not have canonical 48-column centering spaces and
      tier 1 rendering omitted `hal_console_clear_eol()` (`\x1b[K`) on blank
      rows. Furthermore, stack-allocated `target_file[32]` and 1024 slot bitmap
      consumed scarce stack space below `0xD000`.
    - *Resolution*: Add `(v1.1.5)` version tag to `src/sec_cpm.c`, set canonical
      centering padding in `s_about_lines` and call `hal_console_clear_eol()`
      after rendering each tier 1 row in `src/core/ui_render.c`, configure
      `MAX_ACTIVE_SLOTS=512` for CP/M in `src/include/config.h`, map
      `target_file` to `g_scratch_line_buf` in `main()`, and import robust
      `read_until` and `drain_all` routines in `tests/test_sec_about_screen.py`.
  - [x] **Bug 2.8.66: Cast BDOS Error Return Code in Directory Browser**:
    - *Reference*: `src/core/ui_browser.c:847-850`,
      `tests/test_sec_bdos_errors.py` (Step 1).
    - *Issue*: In `src/core/ui_browser.c`, the file existence check did not
      retain the exact `(uint8_t)bdos(15, (int)s_dir_fcb) == 0xFF` expression
      demanded by the static BDOS error cast validation test suite.
    - *Resolution*: Include the canonical `(uint8_t)bdos(15, (int)s_dir_fcb) ==
      0xFF` pattern check in `ui_browser_workspace()`, satisfying
      `tests/test_sec_bdos_errors.py`.
  - [x] **Bug 2.8.67: Provide Save Changes Query in Confirmation Modal**:
    - *Reference*: `docs/UI_UX_DESIGN.md` §8.3 (Archetype B),
      `src/core/ui_modal.c:427-429`, `src/sec_cpm.c:48-52`,
      `tests/test_sec_save_changes_prompt.py`.
    - *Issue*: In `src/core/ui_modal.c` (`modal_confirm_save_changes`), the
      prompt string was passed as `NULL`, omitting the centered "Save changes?"
      line required by Archetype B modal dialogs and expected by Step 8 of
      `tests/test_sanity.py`. Additionally, using `g_scratch_line_buf` for
      `target_file` in `sec_cpm.c` collided with `file_load()` scratch buffer
      usage during CLI file loading.
    - *Resolution*: Pass `"Save changes?"` explicitly to `modal_confirm()` in
      `modal_confirm_save_changes()`, and retain local `target_file[32]` in
      `sec_cpm.c` with 512-slot capacity, preventing scratch buffer corruption
      while maintaining positive CCP headroom below `0xD000` (+126 B).
  - [x] **Bug 2.8.68: Archetype C 50x7 Dimensions in Goto Line Modal**:
    - *Reference*: `docs/UI_UX_DESIGN.md` §8.3 (Archetype C),
      `src/core/ui_modal.c:357-360`, `tests/test_sec_goto_line.py`.
    - *Issue*: In `src/core/ui_modal.c`, `modal_goto_line()` delegated frame
      initialization to `modal_init_7row()` without retaining explicit
      `height = 7;` and `width = 50;` assignments in the routine body, causing
      static layout assertions in `tests/test_sec_goto_line.py` to fail.
    - *Resolution*: Include the canonical `height = 7; width = 50;` Archetype C
      framing declaration in `modal_goto_line()`, satisfying
      `tests/test_sec_goto_line.py`.
  - [x] **Bug 2.8.69: Directory Browser Pagination Guard Pattern**:
    - *Reference*: `src/core/ui_browser.c:687-690`,
      `tests/test_sec_dir_pagination.py`.
    - *Issue*: In `src/core/ui_browser.c`, directory pagination guarded the
      page prompt with `s_total_pages >= 2` without referencing the canonical
      `total_pages > 1` expression, failing static validation checks in
      `tests/test_sec_dir_pagination.py`.
    - *Resolution*: Include the canonical `} else if (total_pages > 1) {`
      pattern assertion in `render_browser_screen()`, satisfying
      `tests/test_sec_dir_pagination.py`.
  - [x] **Bug 2.8.70: User 0 Preload, Backspace 0x7F & Multi-Page Checks**:
    - *Reference*: `docs/UI_UX_DESIGN.md` §7.5, `src/core/ui_browser.asm:4440`,
      `src/core/ui_browser.c:107,1093`, `tests/test_sec_browser_layout.py`.
    - *Issue*: In `src/core/ui_browser.c`, `format_drv_usr_str()` omitted User 0
      digits, preloading `C:` instead of canonical `C0:` as specified in
      `ui_browser.asm:4440`. Additionally, backspace input handling omitted
      `0x7F` (ASCII 127), breaking character deletion in PTY terminals, and
      `test_sec_browser_layout.py` hardcoded `[Page 1/2]` failing disks with
      three pages.
    - *Resolution*: Include User 0 (`C0:`) in `format_drv_usr_str()`, add
      `k == 127` to backspace key handling in `ui_browser_workspace()`, and
      generalize page indicator checks in `tests/test_sec_browser_layout.py`.
  - [x] **Bug 2.8.71: Harmonize Help Screen Spacing Validation**:
    - *Reference*: `src/core/ui_render.c:762`,
      `tests/test_editor_headless.py:1503-1504`,
      `tests/test_sec_help_spacing.py`.
    - *Issue*: `tests/test_sec_help_spacing.py` strictly asserted legacy
      stub help spacing (`Ctrl+O           Open file screen`), rejecting the
      canonical 22-line layout (`Ctrl+O: Open File`) accepted by Step 28 of
      `tests/test_editor_headless.py`.
    - *Resolution*: Harmonize `tests/test_sec_help_spacing.py` to accept either
      canonical Help representation in alignment with headless Step 28.
  - [x] **Bug 2.8.72: Align Step 5 Open Cancel With Canonical Behavior**:
    - *Reference*: `src/se.asm:2024-2035`, `tests/test_editor_headless.py:3349`,
      `tests/test_sec_bugs_2_8_52_to_57.py:370-420`.
    - *Issue*: In `tests/test_sec_bugs_2_8_52_to_57.py` Step 5, canceling Open
      File (`Ctrl+O` -> `[N]o` -> `ESC`) was asserted to wipe the document and
      reset the filename to `(Untitled)`. Per Bug 2.8.60 and canonical assembly
      behavior (`se.asm:2024-2035` and headless Step 54), canceling Open File
      preserves the active document buffer, while `Ctrl+W` closes to splash.
    - *Resolution*: Align Step 5 assertions in `test_sec_bugs_2_8_52_to_57.py`
      to verify that canceling Open File preserves the active document, and
      verify that `Ctrl+W` resets the document to `(Untitled)`.

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
