# SE.COM User Guide

**`SE.COM`** is a high-performance full-screen text editor written in 100% Z80
assembly language for CP/M 2.2 and CP/M 3.0 systems running the **RomWBW**
firmware platform (specifically **RomWBW v3.6.0 or later** on RC2014, SC126,
SC130, SC131, Zeta 2, and compatibles).

> [!IMPORTANT]
> **Firmware Requirement**: `SE.COM` is strictly designed to run on **RomWBW
> v3.6.0 and later**. Earlier versions and generic CP/M BIOSes lack the
> standardized HBIOS `RST 08H` Far RAM memory management and RAM drive
> introspection services required by the editor. See
> [HARDWARE_COMPATIBILITY.md](HARDWARE_COMPATIBILITY.md) for details.

---

## 1. Quick Start & Invocation

### 1.1 Command-Line Syntax

Launch `SE.COM` from the CP/M command line prompt (`C>`):

```text
C>SE                            # Open the startup Splash Screen
C>SE MYFILE.TXT                 # Open MYFILE.TXT directly in editor
C>SE MYFILE.TXT:150             # Open MYFILE.TXT and jump directly to line 150
C>SE B:PROGRAM.ASM              # Open file on Drive B:
C>SE 1C:SOURCE.C                # Open SOURCE.C on Drive C: in User Area 1
C>SE C1:SOURCE.C                # Alternate User Area syntax (Drive C, User 1)
```

> **Tip for Developers**: The `:line` suffix allows compiler lint tools or
> command batches to jump directly to an error line.

---

## 2. Startup Splash Screen

When started without arguments or when closing an active file, `SE.COM`
displays the centered startup landing screen:

```text
~                      SE - Screen Editor
~                  version 0.9.9 (2026-10-07)
~
~        type   [E]  or  [Enter] to edit
~        type   [N]              to create a new file
~        type   [O]              to open a file
~        type   [S]              to save current file
~        type   [W]              to close file to splash
~        type   [C]              for configuration
~        type   [P]              for plugins
~        type   [^P]             for context plugin menu
~        type   [M]              for memory info
~        type   [A]              for about
~        type   [1]              for 120x40 screen mode
~        type   [2]              for 80x24 screen mode
~        type   [Q]              to exit to CP/M
~
~        Active Screen : [120x40 (Widescreen)]
~        RAM Drive (A:): [Preserved (Active)]
~        Plugin System : [Autoload (Ready)]
~        Max Lines     : [16,384 lines]
~
| (Untitled)     | 120x40 | CP/M  | Free: 48 KB     | Line    1/1    Col 0   |
```

### 2.1 Splash Menu Shortcuts

* **`[E]` / `[Enter]`**: Enter the editor buffer (resumes current document or
  starts an untitled buffer).
* **`[N]`**: Start editing a clean blank document (`(Untitled)`).
* **`[O]`**: Open the interactive File Open directory browser.
* **`[S]`**: Open the interactive File Save screen.
* **`[W]`**: Close the current file and reset buffer.
* **`[C]`**: Open the Configuration Manager (`SE.CFG`).
* **`[P]`**: Open the Plugin Manager screen.
* **`[^P]` (`Ctrl+P`)**: Open the Context-Aware Plugin pop-up palette.
* **`[M]`**: View Far RAM bank allocation and memory diagnostics.
* **`[A]`**: Display version, authorship, and licensing info.
* **`[1]`**: Select modern 120x40 widescreen terminal mode.
* **`[2]`**: Select classic 80x24 VT100 terminal mode.
* **`[Q]` / `Ctrl+Q`**: Exit cleanly to CP/M.

---

## 3. Editing Essentials

### 3.1 Text Input & Modes

* **Typing**: Characters type directly at the cursor. Lines expand dynamically
  up to 120 characters.
* **Insert vs Overwrite**: Press <kbd>Insert</kbd> to toggle between Insert mode
  and Overwrite mode. In Overwrite mode, existing characters are replaced under
  the cursor without shifting text, and Field 4 of the status bar displays
  `Overwrite mode  | `.
* **Backspace & Delete**:
  - <kbd>Backspace</kbd> (`0x08` / `^H`): Deletes character left of cursor. At
    column 0, joins current line to preceding line.
  - <kbd>Del</kbd> (`0x7F` / `\x1b[3~`): Deletes character under cursor.
* **Tab Key**: Pressing <kbd>Tab</kbd> inserts spaces to advance to the next
  tab stop (default 8 columns, or 4 columns if configured).

### 3.2 Cursor Movement & Navigation

`SE.COM` supports both standard ANSI arrow keys and classic WordStar diamond
control shortcuts:

| Action | Primary Key | WordStar Shortcut |
| :--- | :--- | :--- |
| Move Cursor Up | <kbd>Up Arrow</kbd> | <kbd>Ctrl+E</kbd> |
| Move Cursor Down | <kbd>Down Arrow</kbd> | <kbd>Ctrl+X</kbd> |
| Move Cursor Left | <kbd>Left Arrow</kbd> | <kbd>Ctrl+S</kbd> |
| Move Cursor Right | <kbd>Right Arrow</kbd> | <kbd>Ctrl+D</kbd> |
| Start of Line | <kbd>Home</kbd> | <kbd>Ctrl+A</kbd> |
| End of Line | <kbd>End</kbd> | <kbd>Ctrl+F</kbd> |
| Page Up | <kbd>PgUp</kbd> | <kbd>Ctrl+R</kbd> |
| Page Down | <kbd>PgDn</kbd> | <kbd>Ctrl+C</kbd> |
| Jump to Line | <kbd>Ctrl+L</kbd> | <kbd>Ctrl+L</kbd> |

### 3.3 Horizontal Viewport Scrolling (80x24 Mode)

In 80x24 retro geometry, moving past column 79 automatically scrolls the
viewport horizontally. A continuation indicator (`$`) appears in column 79,
and the status bar shows horizontal pan offset (e.g. `[Pan +20]`).

---

## 4. Visual Block Selection & Manipulation

`SE.COM` features a visual block highlight engine with dedicated modal
controls.

### 4.1 Block Selection Workflow

1. **Start Selection**: Position cursor at start of desired text and press
   <kbd>Ctrl+B</kbd>. Selection mode activates in reverse video, and the status
   bar displays `Sel: 0 chars`.
2. **Expand Selection**: Move the cursor with arrow keys. The highlight expands
   dynamically across characters and lines. Status displays:
   - Single-line: `Sel: <N> char(s)`
   - Multi-line: `Sel: <N> line(s)`
3. **Lock / Solidify Block**:
   - Press <kbd>Enter</kbd> while dynamic selection is active.
   - The selection is now locked/solidified (`Block: <N> char(s)` or
     `Block: <N> line(s)`).
   - Once solidified, you can move the cursor freely through the file without
     altering the block boundaries.
4. **Cancel / Clear Selection**:
   - Press <kbd>Ctrl+B</kbd> at any time. <kbd>Ctrl+B</kbd> acts as a toggle:
     when active, it clears the selection immediately.

### 4.2 Block Operations Modal (`Ctrl+K`)

When a block is active or solidified, press <kbd>Ctrl+K</kbd> to summon the
centered 50x7 Block Operations Modal dialog:

```text
+----------------- Block Mode -------------------+
|                                                |
|  Marked Block: 2 lines (78 bytes)              |
|                                                |
| [Enter]=Lock   [^C]=Copy   [^X]=Cut   [^D]=Del |
| [^S]=Save      [^B]=Clear  [ESC]=Close         |
+------------------------------------------------+
```

Modal Commands:
* **`[Enter]=Lock`**: Solidifies a dynamic selection and dismisses the modal.
* **`[^C]=Copy`**: Duplicates the marked block to the current cursor position.
* **`[^X]=Cut`**: Moves the marked block to the current cursor position.
* **`[^D]=Del`**: Deletes the marked block from the document.
* **`[^S]=Save`**: Opens Save Block dialog to write block to a disk file.
* **`[^B]=Clear`**: Cancels block selection and returns to regular editing.
* **`[ESC]=Close`**: Safe non-destructive NOP. Dismisses the modal while leaving
  the active block selection 100% intact.

---

## 5. File Operations & Directory Management

### 5.1 Open File Screen (`Ctrl+O` or `[O]` from Splash)

Summons the full-screen sorted directory browser:
* **Directory Navigation**: Use arrow keys or <kbd>PgUp</kbd> / <kbd>PgDn</kbd>
  to page through directory listings.
* **In-Line Filename Editing**: Type a filename directly into the bracketed edit
  box. Supports WordStar navigation, backspace, and cursor movement.
* **Directory Wildcard Filtering**: Type a filter pattern (e.g. `*.TXT`,
  `*.ASM`, `1C:*.C`) and press <kbd>Enter</kbd> to filter the directory view.
* **User Areas**: Switch user areas directly in the edit box (e.g. `1:` or
  `C1:`).

### 5.2 Save File Screen (`Ctrl+S` or `[S]` from Splash)

* **Save Prompt**: Prompts for target filename (pre-filled with active file).
* **Format Toggling**: Press <kbd>Ctrl+F</kbd> on the save screen to toggle
  between classic CP/M `[CP/M]` (`CRLF`) and Unix/Linux `[Linux]` (`LF`) line
  endings.
* **Overwrite Guard**: If the target filename already exists on disk, `SE.COM`
  presents a centered Tier 2 confirmation pop-up:
  `[Y]es   [N]o   [ESC]=Cancel`.

### 5.3 Progress Indicators

Large file load, save, insert, and block-save operations display a centered
progress modal with a live line ticker updating every 100 lines. Saving is
non-interruptible to protect disk integrity.

---

## 6. Search and Replace

* **Find Text (<kbd>Ctrl+F</kbd>)**: Opens centered Find modal dialog.
  - Type search pattern and press <kbd>Enter</kbd>.
  - Press <kbd>Tab</kbd> to toggle case sensitivity (`Case Sensitive` vs
    `Case Insensitive`).
  - Search automatically wraps from end of file to beginning.
* **Find Next (<kbd>Ctrl+N</kbd>)**: Repeats last search forward without
  re-opening the dialog.
* **Search & Replace (<kbd>Ctrl+R</kbd>)**: Opens Replace modal dialog.
  - Prompts for search pattern and replacement string.
  - On each match, prompts: `[Y]es   [N]o   [A]ll   [ESC]=Cancel`.

---

## 7. Configuration & System Diagnostics

### 7.1 Configuration Screen (`[C]` from Splash)

* **[1] Screen Geometry**: Toggle between `120x40 (Widescreen)` and `80x24`.
* **[2] RAM Drive**:
  - `Preserve`: Keeps RAM disk `A:` intact and limits editor Far RAM.
  - `Hibernate`: Backs up RAM disk to temporary swap file during editing.
  - `Overwrite`: Overwrites RAM disk for maximum Far RAM capacity.
* **[3] Max Document Lines**: Toggle between `16,384 lines` and `32,768 lines`.
* **[4] Tab Width**: Toggle between `8 columns` and `4 columns`.
* **[5] Plugin System**: Toggle plugin autoloading on or off.
* **`[S]`**: Save configuration permanently to `SE.CFG`.

### 7.2 Memory Map Screen (`[M]` from Splash)

Displays detailed hardware diagnostics, RomWBW HBIOS bank allocations, system
roles (System, Line Table, Document Paging, Plugins), and available TPA memory.

---

## 8. Modular Plugin System

* **Context Plugin Pop-up (<kbd>Ctrl+P</kbd>)**: Displays a quick menu of
  active plugins relevant to the current screen context.
* **Plugin Manager Screen (`[P]` from Splash)**: Manage up to 8 plugin slots,
  inspect memory requirements (4K, 8K, 16K, 32K), view plugin About boxes, and
  toggle on-demand plugins.
* **Standard Plugins**:
  - `BEAUTIFY.PRL`: Z80 assembly source code formatter.
  - `ROT13.PRL`: Caesar cipher text transform.
  - `WORDCNT.OVL`: Document word, line, and character counter.
  - `FATFS.PRL`: Direct FAT32 SD-card filesystem reader/writer.

---

## 9. Troubleshooting & Common Questions

### 9.1 Splash Screen Shows "Max Lines: [256 lines (RAM)]"

* **Cause**: By default, `SE.COM` runs in `Preserve` mode to protect RomWBW RAM
  disk `A:`. When all upper RAM banks are reserved for `Drive A:`, `SE.COM`
  detects no free Far RAM banks and falls back to conventional 64KB RAM mode.
* **Solution**:
  1. From the splash screen, press **`c`** to enter Configuration.
  2. Press **`2`** to set **RAM Drive** to `Hibernate` (swaps RAM disk to disk
     during editing) or `Overwrite` (reclaims all upper banks).
  3. Press **`s`** to save to `SE.CFG`.
  4. Return to the splash screen; line capacity will now show `[16,384 lines]`.

### 9.2 How to Maximise the Number of Editor Lines (Up to 32,768 Lines)

* **Step 1**: Press **`c`** for Configuration, then press **`3`** to set
  **Max Document Lines** to `32,768 lines`.
* **Step 2**: Ensure at least 3 Far RAM banks are available (set RAM Drive to
  `Hibernate` or `Overwrite`, and unload unused resident plugins via `[P]`).
* **Step 3**: Press **`s`** to save to `SE.CFG`.
* **Step 4**: Press **`m`** on splash to inspect bank allocations in the
  **Memory Map**.

### 9.3 Garbled Pop-ups or Screen Wrapping at 80 Columns

* **Cause**: Terminal emulator is set to standard 80x24, while `SE.COM` defaults
  to 120x40 widescreen mode.
* **Solution**: Press **`2`** on the splash screen to select `80x24 (Classic
  Mode)`, then press **`c`** and **`s`** to save.

### 9.4 Serial Communications & Flow Control (115200 bps)

* **Speed & Framing**: Set terminal emulator to **115200 bps 8N1**.
* **Hardware Flow Control**: Enable hardware flow control using full-duplex
  RTR/CTS operation via the physical RTS/CTS pins (where each device's RTS pin
  signals Ready To Receive into the peer's CTS pin). Software flow control
  (XON/XOFF) must be disabled to avoid buffer overflow and dropped characters.

For deep-dive diagnostics, flow control setup, and swap file management,
consult the complete [Troubleshooting Guide](TROUBLESHOOTING.md).

