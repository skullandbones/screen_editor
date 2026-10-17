# SE.COM User Guide

> [!WARNING]
> **AI Agents shall not use this document as an authoritive reference
> document.** For AI agents, developers, and automated validation harnesses,
> [`docs/UI_UX_DESIGN.md`](UI_UX_DESIGN.md) is the single authoritative
> specification for all SE UI/UX behavior, screen layouts, modal dialogs, and
> keybindings.

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

### 2.1 Splash Menu Shortcuts

* **`[E]` / `[Enter]`**: Enter the editor buffer (resumes current document or
  starts an untitled buffer).
* **`[N]`**: Start editing a clean blank document (`(Untitled)`).
* **`[O]` / `[^O]` (`Ctrl+O`)**: Open the interactive File Open directory
  browser.
* **`[S]` / `[^S]` (`Ctrl+S`)**: Open the interactive File Save screen.
* **`[W]` / `[^W]` (`Ctrl+W`)**: Close the current file and reset buffer.
* **`[L]` / `[^L]` (`Ctrl+L`)**: Prompt for a line number and jump directly to
  that line in the editor.
* **`[A]`**: Display version, implementation details, authorship, and licensing
  info.
* **`[M]`**: View Far RAM bank allocation and memory diagnostics.
* **`[P]`**: Open the Plugin Manager screen.
* **`[^P]` (`Ctrl+P`)**: Open the Context-Aware Plugin pop-up palette.
* **`[C]`**: Open the Configuration Manager (`SE.CFG`).
* **`[1]`**: Select classic `80x24` VT100 terminal mode (default).
* **`[2]`**: Select extended `120x40` widescreen terminal mode.
* **`[Q]` / `[^Q]` (`Ctrl+Q`)**: Exit cleanly to CP/M (prompts if unsaved
  changes exist).

---

## 3. Editing Essentials

### 3.1 Text Input & Modes

* **Typing**: Characters type directly at the cursor. Lines expand dynamically
  up to **1,000 characters**.
* **Insert vs Overwrite**: Press <kbd>Insert</kbd> to toggle between Insert mode
  and Overwrite mode. In Overwrite mode, existing characters are replaced under
  the cursor without shifting text, and Field 4 of the status bar displays
  `Overwrite       | `.
* **Backspace & Delete**:
  - <kbd>Backspace</kbd> (`0x08` / `^H`): Deletes character left of cursor. At
    column 0, joins the current line to the preceding line (if combined length
    is $\le 1,000$ characters).
  - <kbd>Del</kbd> (`0x7F` / `\x1b[3~`) or <kbd>Ctrl+D</kbd> (`0x04`): Deletes
    character under cursor. At the end of a line, joins the next line onto the
    current line.
* **Tab Key**: Pressing <kbd>Tab</kbd> (`Ctrl+I`) inserts spaces to advance to
  the next tab stop (default 8 columns, or 4 columns if configured).

### 3.2 Cursor Movement & Navigation

`SE.COM` uses standard ANSI VT100 cursor keys and dedicated control shortcuts:

| Action | Primary Key | Control / Alternate Shortcut |
| :--- | :--- | :--- |
| Move Cursor Up | <kbd>Up Arrow</kbd> | ANSI `\x1b[A` |
| Move Cursor Down | <kbd>Down Arrow</kbd> | ANSI `\x1b[B` |
| Move Cursor Left | <kbd>Left Arrow</kbd> | ANSI `\x1b[D` |
| Move Cursor Right | <kbd>Right Arrow</kbd> | ANSI `\x1b[C` |
| Start of Line | <kbd>Home</kbd> | <kbd>Ctrl+A</kbd> |
| End of Line | <kbd>End</kbd> | <kbd>Ctrl+E</kbd> |
| Page Up | <kbd>PgUp</kbd> | <kbd>Ctrl+U</kbd> |
| Page Down | <kbd>PgDn</kbd> | <kbd>Ctrl+V</kbd> |
| Top of File (Row 0) | <kbd>^Home</kbd> | <kbd>Ctrl+T</kbd> |
| Bottom of File (EOF) | <kbd>^End</kbd> | <kbd>Ctrl+G</kbd> |
| Goto Line Number | <kbd>Ctrl+L</kbd> | `[L]` / `[^L]` on Splash |
| Editor Help Screen | <kbd>Ctrl+K</kbd> | Full-screen `EDITOR MODE KEYS` |
| Return to Splash | <kbd>ESC</kbd> | Returns to Splash Screen |

### 3.3 Horizontal Viewport Scrolling

Both `80x24` and `120x40` screen geometries support lines up to 1,000
characters. When the cursor moves past the right edge of the active viewport,
the viewport pans horizontally in **40-column increments**, and Field 4 of the
status bar displays the active horizontal pan offset (e.g. `[Pan +40]`,
`[Pan +80]`).

---

## 4. Visual Block Selection & Manipulation

`SE.COM` features a visual block highlight engine with direct in-place block
manipulation (no intermediary clipboard is used) and a dedicated modal menu.

### 4.1 Block Selection Workflow

1. **Start Selection**: Position cursor at the start of desired text and press
   <kbd>Ctrl+B</kbd>. Selection mode activates in reverse video, and the status
   bar displays `Sel: 0 chars`.
2. **Expand Selection**: Move the cursor with arrow keys or navigation keys. The
   highlight expands dynamically across characters and lines. Status displays:
   - Single-line: `Sel: <N> char(s)`
   - Multi-line: `Sel: <N> line(s)`
3. **Lock / Solidify Block**:
   - Press <kbd>Enter</kbd> while dynamic selection is active.
   - The selection is now locked/solidified (`Block: <N> char(s)` or
     `Block: <N> line(s)`).
   - Once solidified, you can move the cursor freely through the file to choose
     a target destination without altering the block boundaries.
4. **Direct Block Shortcuts**:
   - <kbd>Ctrl+C</kbd>: Copy marked block directly to the cursor position.
   - <kbd>Ctrl+X</kbd>: Move marked block directly to the cursor position.
   - <kbd>Ctrl+D</kbd> / <kbd>Del</kbd>: Delete the marked block range.
   - <kbd>Ctrl+S</kbd>: Save the marked block to a disk file.
   - <kbd>Ctrl+O</kbd>: Insert an external disk file at the cursor position.
   - <kbd>Ctrl+Y</kbd>: Run the `BEAUTIFY` formatter restricted to the block.
5. **Cancel / Clear Selection**:
   - Press <kbd>Ctrl+B</kbd> or <kbd>ESC</kbd> at any time to clear the block
     selection and return to normal editing.

### 4.2 Block Operations Modal (`Ctrl+K`)

When a block is active or solidified, pressing <kbd>Ctrl+K</kbd> summons the
centered 50x7 **Block Operations** modal dialog instead of the standard Help
screen:

```text
+------------------------------------------------+
|                Block Operations                |
+------------------------------------------------+
|              Selection: 2 lines                |
|  [Enter]=Lock/Set    [^C]=Copy    [^X]=Move    |
|  [^D]=Del  [^S]=Save  [^B]=Clear  [ESC]=Close  |
+------------------------------------------------+
```

Modal Commands:
* **`[Enter]=Lock/Set`**: Solidifies a dynamic selection and dismisses the
  modal so you can position the cursor at the target location.
* **`[^C]=Copy`** (or **`C`**): Copies the marked block directly to the current
  cursor position.
* **`[^X]=Move`** (or **`X`**): Moves the marked block directly to the current
  cursor position.
* **`[^D]=Del`** (or **`D`** / <kbd>Del</kbd>): Deletes the marked block from
  the document.
* **`[^S]=Save`** (or **`S`**): Opens the Save Block dialog to write the marked
  block to a disk file.
* **`[^B]=Clear`** (or **`B`**): Cancels block selection and returns to regular
  editing.
* **`[ESC]=Close`**: Safe non-destructive close. Dismisses the modal while
  leaving the active block selection intact.

---

## 5. File Operations & Directory Management

### 5.1 Open File Screen (`Ctrl+O` or `[O]` from Splash)

Summons the full-screen sorted directory browser:
* **Directory Navigation**: Use arrow keys or <kbd>PgUp</kbd> / <kbd>PgDn</kbd>
  to navigate through directory listings.
* **In-Line Filename Editing**: Type a filename directly into the bracketed edit
  box using <kbd>Left</kbd>/<kbd>Right</kbd> arrow keys, <kbd>Backspace</kbd>,
  and <kbd>Del</kbd> (<kbd>Ctrl+D</kbd>).
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
  presents a centered 50x7 confirmation pop-up:
  `[Y]es      [N]o      [ESC]=Cancel`.

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

The visual block manager (<kbd>Ctrl+B</kbd> / <kbd>Ctrl+K</kbd>) fully supports
user area prefixes for inter-project code sharing:

* **Block Save**: Marking a block and pressing <kbd>Ctrl+S</kbd> (either
  directly in the editor or from the Block Operations modal) allows specifying
  a destination user area (e.g. `1C:SNIPPET.LIB`).
* **Block Insert**: While a block is active, pressing <kbd>Ctrl+O</kbd> opens
  the Insert File browser, allowing you to specify a source user area (e.g.
  `1C:HEADER.H`) to splice text directly into the active editor buffer at the
  current cursor position.

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

* **Find Text (<kbd>Ctrl+F</kbd>)**: Opens the centered 50x7 Find Text modal
  dialog.
  - Type a search pattern and press <kbd>Enter</kbd> (`[Enter]=Find`).
  - Press <kbd>Tab</kbd> (`Ctrl+I`) to toggle case sensitivity in place
    between `[Case Sensitive  ]` and `[Case Insensitive]`.
  - Search automatically wraps from the end of the file to the beginning.
* **Find Next (<kbd>Ctrl+N</kbd>)**: Repeats the last search forward without
  re-opening the dialog (or opens Find Text if no search pattern is set).
* **Search & Replace (<kbd>Ctrl+R</kbd>)**: Opens the Find Text modal followed
  by the 50x7 Replace Text modal dialog.
  - Prompts for the search pattern and the replacement string.
  - On each match, displays the 50x7 Replace Confirmation modal:
    `[Y]es  [N]o  [A]ll  [R]everse   [ESC]=Cancel`.

---

## 8. Configuration & System Diagnostics

### 8.1 Configuration Screen (`[C]` from Splash)

The Configuration Manager uses instant single-keystroke hotkeys (`[1-5]=Toggle
Option  [S]=Save Config  [ESC]=Exit`):

* **[1] Screen Geometry**: Toggle between `80x24 (Classic Terminal)` (default)
  and `120x40 (Modern Default)`.
* **[2] RAM Drive**:
  - `Preserve`: Keeps RAM disk `A:` intact and limits editor Far RAM.
  - `Hibernate`: Backs up RAM disk to temporary swap file during editing.
  - `Overwrite`: Overwrites RAM disk for maximum Far RAM capacity.
* **[3] Max Document Lines**: Toggle between `16,384 lines` and `32,768 lines`.
* **[4] Tab Width**: Toggle between `8 columns` (default) and `4 columns`.
* **[5] Plugin System**: Cycle between `Autoload`, `On-Demand`, and `Disabled`.
* **`[S]`**: Save configuration permanently to `SE.CFG`.

### 8.2 Memory Map Screen (`[M]` from Splash)

Displays detailed hardware diagnostics, RomWBW HBIOS bank allocations, system
roles (System, Line Table, Document Paging, Plugins), and available TPA memory.

---

## 9. ZX Spectrum Next Operations & Targets

The `SE` editor provides three distinct deployment packages for the ZX Spectrum
Next, covering both CP/M emulation and native NextZXOS operating environments.

### 9.1 NextCPM Deployment (`SE_NEXT.COM`)

NextCPM provides a full CP/M 2.2 operating environment on the ZX Spectrum Next,
running directly from the NextZXOS SD card.

* **Installation**:
  1. Copy `SE_NEXT.COM` to your NextCPM disk image or virtual drive folder
     (e.g., drive `A:` or `C:`).
  2. Boot NextCPM from the NextZXOS browser or command line (`.cpm`).
* **Invocation**:
  ```text
  A>SE_NEXT                       # Open startup Splash Screen in 80x24 mode
  A>SE_NEXT README.TXT            # Open README.TXT directly
  A>SE_NEXT MAIN.C:42             # Open MAIN.C jumping to line 42
  ```
* **Display & Keyboard**:
  - Automatically utilizes the NextCPM 80-column ANSI terminal driver.
  - Translates Sinclair cursor keys (<kbd>Caps+5</kbd>, <kbd>6</kbd>,
    <kbd>7</kbd>, <kbd>8</kbd>) directly into standard ANSI VT100 directional
    arrow keys, and <kbd>Caps+0</kbd> into <kbd>Delete</kbd> (`0x7F`),
    preserving all standard `Ctrl` shortcuts (`Ctrl+S` Save, `Ctrl+D` Delete,
    `Ctrl+E` End, `Ctrl+X` Move Block).


### 9.2 NextZXOS Standalone Application (`SE.NEX`)

`SE.NEX` is a self-contained executable with a 512-byte `.NEX` header that can
be launched directly from the NextZXOS file browser.

* **Installation**:
  1. Copy `SE.NEX` to any folder on your Next SD card (e.g. `/apps/editor/`).
* **Launching**:
  - Open the NextZXOS file browser (press `Enter` from the Next Basic prompt).
  - Navigate to `/apps/editor/` and highlight `SE.NEX`.
  - Press `Enter` to run.
* **Hardware Configuration**:
  - Automatically engages 28 MHz turbo execution (NextReg `0x07`).
  - Pre-loads into 16KB SRAM Banks 0, 2, and 5 with entry point at `0x4000`.
  - Direct ANSI terminal rendering over the NextZXOS `RST 10H` stream.

### 9.3 NextZXOS Command-Line Dot Command (`.se` / `SE`)

NextZXOS dot commands are executable utilities located in the `/dot/` directory
that can be invoked directly from the Sinclair Basic command prompt.

* **Installation**:
  1. Copy the `.se` (or `SE`) binary into the `/dot/` directory of your SD card:
     ```text
     copy "c:/se_dist/.se" to "/dot/.se"
     ```
* **Invocation**:
  - From the Sinclair Basic command prompt or an exec script:
    ```text
    .se                           # Open editor splash screen
    .se autoexec.bas              # Edit autoexec.bas from current directory
    .se c:/src/kernel.asm         # Edit file with absolute SD path
    .se c:/src/kernel.asm:120     # Jump directly to line 120
    ```
* **Command-Line Argument Parsing**:
  - NextZXOS passes command line tail arguments directly to dot commands.
  - The editor automatically extracts file paths, resolves drive prefixes,
    and parses optional `:line` jump targets.
  - Exiting the editor returns cleanly to the Sinclair Basic prompt.

---

## 10. Modular Plugin System

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

## 11. Troubleshooting & Common Questions

### 11.1 Splash Screen Shows "Max Lines: [256 lines (RAM)]"

* **Cause**: By default, `SE.COM` runs in `Preserve` mode to protect RomWBW RAM
  disk `A:`. When all upper RAM banks are reserved for `Drive A:`, `SE.COM`
  detects no free Far RAM banks and falls back to conventional 64KB RAM mode.
* **Solution**:
  1. From the splash screen, press **`c`** to enter Configuration.
  2. Press **`2`** to set **RAM Drive** to `Hibernate` (swaps RAM disk to disk
     during editing) or `Overwrite` (reclaims all upper banks).
  3. Press **`s`** to save to `SE.CFG`.
  4. Return to the splash screen; line capacity will now show `[16,384 lines]`.

### 11.2 How to Maximise the Number of Editor Lines (Up to 32,768 Lines)

* **Step 1**: Press **`c`** for Configuration, then press **`3`** to set
  **Max Document Lines** to `32,768 lines`.
* **Step 2**: Ensure at least 3 Far RAM banks are available (set RAM Drive to
  `Hibernate` or `Overwrite`, and unload unused resident plugins via `[P]`).
* **Step 3**: Press **`s`** to save to `SE.CFG`.
* **Step 4**: Press **`m`** on splash to inspect bank allocations in the
  **Memory Map**.

### 11.3 Garbled Pop-ups or Screen Wrapping at 80 Columns

* **Cause**: Terminal emulator is set to standard 80x24, while `SE.COM` was
  switched to or configured for `120x40` widescreen mode in `SE.CFG`.
* **Solution**: Press **`1`** on the splash screen to select `80x24 (Classic
  Terminal)`, then press **`c`** and **`s`** to save to `SE.CFG`.

### 11.4 Serial Communications & Flow Control (115200 bps)

* **Speed & Framing**: Set terminal emulator to **115200 bps 8N1**.
* **Hardware Flow Control**: Enable hardware flow control using full-duplex
  RTR/CTS operation via the physical RTS/CTS pins (where each device's RTS pin
  signals Ready To Receive into the peer's CTS pin). Software flow control
  (XON/XOFF) must be disabled to avoid buffer overflow and dropped characters.

For deep-dive diagnostics, flow control setup, and swap file management,
consult the complete [Troubleshooting Guide](TROUBLESHOOTING.md).



