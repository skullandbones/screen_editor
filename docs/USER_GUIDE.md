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
~                  version 1.0.1 (2026-10-07)
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

## 6. Working with CP/M Drive User Areas

In classic CP/M 2.2 and CP/M 3.0 systems, storage drives do not have
hierarchical directories or subdirectories. Instead, files are organized into
up to 16 logical partitions called **User Areas** (numbered `0` through `15`).
Each user area maintains an isolated directory of files on the same physical
drive, allowing projects, system utilities, and data files to be cleanly
separated.

`SE.COM` provides comprehensive support for navigating, loading, editing,
saving, and transferring files across CP/M user areas.

### 6.1 Supported Drive and User Area Prefix Formats

When entering filenames on the CP/M command line, in the Open File browser, in
the Save File dialog, or during Block operations, `SE.COM` recognizes flexible,
bidirectional prefix notations:

| Prefix Format | Example | Drive | User | Description |
| :--- | :--- | :---: | :---: | :--- |
| **Digit-First** | `1C:SOURCE.C` | `C:` | `1` | Digit before drive letter |
| **Two-Digit First** | `15A:BIG.TXT` | `A:` | `15` | Two digits before drive |
| **Letter-First** | `C1:SOURCE.C` | `C:` | `1` | Drive letter before digit |
| **Letter + 2-Digit**| `A15:BIG.TXT` | `A:` | `15` | Drive before two digits |
| **User-Only** | `2:TEST.ASM` | Active | `2` | Operates on active drive |
| **Drive-Only** | `B:TEST.ASM` | `B:` | Active | Operates on active user |

> [!NOTE]
> CP/M user numbers range from `0` to `15`. Numbers greater than 15 are
> rejected as invalid by `SE.COM`'s prefix parser.

### 6.2 Command-Line Invocation with User Areas

You can launch `SE.COM` directly into any drive and user area from the CP/M
prompt:

```text
C>SE 1C:SOURCE.C            # Open SOURCE.C in User Area 1 on Drive C:
C>SE C1:SOURCE.C:42         # Open SOURCE.C in User Area 1 and jump to Line 42
C>SE 3:README.TXT           # Open README.TXT in User Area 3 on current drive
C>SE 15A:KERNEL.ASM         # Open KERNEL.ASM in User Area 15 on Drive A:
```

### 6.3 Browsing & Filtering User Areas (Open File Screen)

From the Open File directory browser (<kbd>Ctrl+O</kbd> in editor, or
**`[O]`** on splash):

1. **Switch User Areas**:
   - Type the desired prefix into the filename edit box (for example, `1C:`,
     `C1:`, or `2:`) and press <kbd>Enter</kbd>.
   - The directory listing refreshes immediately to display all files in the
     specified drive and user area.
2. **Wildcard Filtering in User Areas**:
   - Combine user prefixes with standard CP/M wildcards (e.g. `1C:*.C`,
     `3A:*.ASM`, or `2:*.TXT`) and press <kbd>Enter</kbd>.
   - Only files matching the wildcard within that user area are displayed.
3. **Opening Files**:
   - Select the desired file using arrow keys and press <kbd>Enter</kbd>, or
     type the full filename with prefix (e.g. `1C:SOURCE.C`) and press
     <kbd>Enter</kbd>.

### 6.4 Saving Files Across User Areas (Save File Screen)

In the Save File screen (<kbd>Ctrl+S</kbd> in editor, or **`[S]`** on splash):

* Prepending a drive/user prefix to the filename writes the file directly into
  that target user area.
* For example, typing `2C:PROJECT.C` saves the document into User Area 2 on
  Drive C:, regardless of which user area the file was originally opened from.
* If a file with the same name already exists in the destination user area,
  `SE.COM` prompts with the standard overwrite confirmation modal before
  replacing it.

### 6.5 Transferring Text Blocks Across User Areas

The visual block manager (<kbd>Ctrl+K</kbd>) fully supports user area prefixes
for inter-project code sharing:

* **Block Save**: Marking a block and choosing Save (<kbd>Ctrl+S</kbd> from the
  Block Menu) allows specifying a destination user area (e.g. `1C:SNIPPET.LIB`).
* **Block Insert**: Choosing Insert File (<kbd>Ctrl+I</kbd>) allows specifying a
  source user area (e.g. `1C:HEADER.H`) to splice text directly into the active
  editor buffer at the current cursor position.

### 6.6 Status Bar Indication

The status bar indicates the active file's drive and user area:

* **User Area 0 (Default)**: Omitted for conciseness (e.g. `| C:MAIN.C     |`).
* **User Areas 1 to 15**: Explicitly displayed between the drive letter and
  colon (e.g. `| C1:MAIN.C      |` or `| A15:KERNEL.ASM |`).

### 6.7 Automatic Session & User Area Restoration

When you launch `SE.COM`, the editor queries and records your starting CP/M
logged-in drive and user area via BDOS Function 32 (`Get/Set User Number`).

Regardless of how many drives or user areas you navigate while editing,
exiting `SE.COM` via <kbd>Ctrl+Q</kbd> automatically restores your original
logged-in drive and user area before returning to the CP/M command line prompt,
preventing unintentional disorientation in your CP/M shell session.

---

## 7. Search and Replace

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

## 8. Configuration & System Diagnostics

### 8.1 Configuration Screen (`[C]` from Splash)

* **[1] Screen Geometry**: Toggle between `120x40 (Widescreen)` and `80x24`.
* **[2] RAM Drive**:
  - `Preserve`: Keeps RAM disk `A:` intact and limits editor Far RAM.
  - `Hibernate`: Backs up RAM disk to temporary swap file during editing.
  - `Overwrite`: Overwrites RAM disk for maximum Far RAM capacity.
* **[3] Max Document Lines**: Toggle between `16,384 lines` and `32,768 lines`.
* **[4] Tab Width**: Toggle between `8 columns` and `4 columns`.
* **[5] Plugin System**: Toggle plugin autoloading on or off.
* **`[S]`**: Save configuration permanently to `SE.CFG`.

### 8.2 Memory Map Screen (`[M]` from Splash)

Displays detailed hardware diagnostics, RomWBW HBIOS bank allocations, system
roles (System, Line Table, Document Paging, Plugins), and available TPA memory.

---

## 9. Modular Plugin System

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

## 10. Troubleshooting & Common Questions

### 10.1 Splash Screen Shows "Max Lines: [256 lines (RAM)]"

* **Cause**: By default, `SE.COM` runs in `Preserve` mode to protect RomWBW RAM
  disk `A:`. When all upper RAM banks are reserved for `Drive A:`, `SE.COM`
  detects no free Far RAM banks and falls back to conventional 64KB RAM mode.
* **Solution**:
  1. From the splash screen, press **`c`** to enter Configuration.
  2. Press **`2`** to set **RAM Drive** to `Hibernate` (swaps RAM disk to disk
     during editing) or `Overwrite` (reclaims all upper banks).
  3. Press **`s`** to save to `SE.CFG`.
  4. Return to the splash screen; line capacity will now show `[16,384 lines]`.

### 10.2 How to Maximise the Number of Editor Lines (Up to 32,768 Lines)

* **Step 1**: Press **`c`** for Configuration, then press **`3`** to set
  **Max Document Lines** to `32,768 lines`.
* **Step 2**: Ensure at least 3 Far RAM banks are available (set RAM Drive to
  `Hibernate` or `Overwrite`, and unload unused resident plugins via `[P]`).
* **Step 3**: Press **`s`** to save to `SE.CFG`.
* **Step 4**: Press **`m`** on splash to inspect bank allocations in the
  **Memory Map**.

### 10.3 Garbled Pop-ups or Screen Wrapping at 80 Columns

* **Cause**: Terminal emulator is set to standard 80x24, while `SE.COM` defaults
  to 120x40 widescreen mode.
* **Solution**: Press **`2`** on the splash screen to select `80x24 (Classic
  Mode)`, then press **`c`** and **`s`** to save.

### 10.4 Serial Communications & Flow Control (115200 bps)

* **Speed & Framing**: Set terminal emulator to **115200 bps 8N1**.
* **Hardware Flow Control**: Enable hardware flow control using full-duplex
  RTR/CTS operation via the physical RTS/CTS pins (where each device's RTS pin
  signals Ready To Receive into the peer's CTS pin). Software flow control
  (XON/XOFF) must be disabled to avoid buffer overflow and dropped characters.

For deep-dive diagnostics, flow control setup, and swap file management,
consult the complete [Troubleshooting Guide](TROUBLESHOOTING.md).


