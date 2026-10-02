# SE.COM — Development To-Do & Roadmap

This file tracks pending enhancement tasks, architectural optimizations, and
upcoming milestones for SE.COM.

---

## 1. AGENTS.md Enhancements

### 1.1 Prohibit "python -c" in AGENTS.md
- [ ] Enhancement: Be explicit that "python -c" shall not be used and instead
  construct and run python scripts.

---

## 2. BUGS

### 2.1 Memory Screen Misreports Loaded Plugin Banks as Free / Unallocated
- [ ] The memory screen erroneously shows "Free / Unallocated" when a plugin
  has been loaded. Update bank role and usage detection in the memory info
  screen ('m') to indicate that the memory bank is being used for plugins.

### 2.2 System Hangs When Loading Large Files with 32K Available RAM
- [ ] When only 32K of RAM is available (reported on the status line), loading
  of large files hangs the system.

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
- [ ] **[PRIORITY]** Centralize repeated terminal escape sequences
  (`\x1b[7m`, `\x1b[0m`, `\x1b[K`, cursor addressing) into shared helper
  routines.

---

## 4. UI/UX Design System Audits & Enhancements (`docs/UI_UX_DESIGN.md`)

### 4.1 Audit Column 0 Tilde Discipline on File & Block Screens
- [ ] Verify column 0 tildes (`~`) are rendered on all unallocated margin
  rows across Open File, Save File, and Block selection screens.
- *Justification* (`docs/UI_UX_DESIGN.md` Section 1.3):
  > *"Tildes in column 0 are used on all screens without exception
  > (including file open, save, and block screens)."*

### 4.2 Audit Center Justification in Remaining Query Pop-ups
- [ ] Audit all Tier 2 query pop-ups to ensure text lines (description, query,
  and options) are centre justified with space-separated options.
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
- [ ] Periodically check SE.COM complies with the `docs/UI_UX_DESIGN.md` file
  and append a resolution task list into Section 2 (BUGS).

---

## 6. Preparations for Releasing SE.COM v1.0.0

### 6.1 Create Documentation Suite
- [ ] Create documents including architecture, setup build environment, and
  user guide.

### 6.2 Review and Enhance Subroutine Comments in `SE.ASM`
- [ ] Review and enhance the comments in `SE.ASM` to provide information on
  subroutine call usage and purpose of the subroutine.
