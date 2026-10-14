# SE.COM Keyboard Reference & Keybindings

**`SE.COM`** provides a dual-model keyboard interface optimized for vintage
serial terminals (VT100/VT102/ANSI) and terminal emulators (Minicom, PuTTY,
TeraTerm, Windows Terminal).

---

## 1. Splash Screen Commands

When launched without arguments, `SE.COM` presents a startup landing screen:

- **`e` / `E` / <kbd>Enter</kbd>**: Resume or enter active text editor buffer.
- **`n` / `N`**: Start editing a new blank file (`(Untitled)`).
- **`o` / `O`**: Open interactive full-screen file browser.
- **`s` / `S`**: Open interactive save screen with CRLF/LF format toggle.
- **`w` / `W` / <kbd>Ctrl+W</kbd>**: Close active file and return to splash.
- **`l` / `L` / <kbd>Ctrl+L</kbd>**: Prompt for line number on status bar.
- **`a` / `A`**: Display version, author, and license info.
- **`m` / `M`**: Display 512KB Far RAM bank allocation table.
- **`c` / `C`**: Open interactive `SE.CFG` setup screen.
- **`1`**: Set modern widescreen display (120 cols x 40 rows, default).
- **`2`**: Set classic VT100 terminal mode (80 cols x 24 rows).
- **`q` / `Q` / <kbd>Ctrl+Q</kbd>**: Exit cleanly to CP/M command line.

---

## 2. Editor Navigation & Cursor Movement

`SE.COM` supports both classic WordStar control keys and standard ANSI arrows:

- **<kbd>Up</kbd> / <kbd>Ctrl+E</kbd>**: Move cursor up one row.
- **<kbd>Down</kbd> / <kbd>Ctrl+X</kbd>**: Move cursor down one row.
- **<kbd>Left</kbd> / <kbd>Ctrl+S</kbd>**: Move cursor left one character.
- **<kbd>Right</kbd> / <kbd>Ctrl+D</kbd>**: Move cursor right one character.
- **<kbd>Home</kbd> / <kbd>Ctrl+A</kbd>**: Move cursor to column 0 of line.
- **<kbd>End</kbd> / <kbd>Ctrl+F</kbd>**: Jump cursor to end of text on line.
- **<kbd>PgUp</kbd> / <kbd>Ctrl+R</kbd>**: Scroll viewport up one screen page.
- **<kbd>PgDn</kbd> / <kbd>Ctrl+C</kbd>**: Scroll viewport down one screen page.
- **<kbd>Ctrl+L</kbd>**: Prompt for line number and center viewport.

---

## 3. Visual Block Selection & Editing

`SE.COM` implements an intuitive visual block highlighting mechanism:

- **<kbd>Ctrl+B</kbd>**: Toggle block selection (starts dynamic highlight if
  inactive; cancels/clears selection if active).
- **<kbd>Enter</kbd>**: Lock/solidify block in editor, allowing free travel.
- **<kbd>Ctrl+K</kbd>**: Open centered 50x7 Block Operations Modal dialog.
  - In modal: **<kbd>Enter</kbd>** locks block, **<kbd>ESC</kbd>** safely
    closes modal without clearing selection, **<kbd>^B</kbd>** clears block.
- **<kbd>Ctrl+C</kbd>**: Copy selected/solidified text to cursor.
- **<kbd>Ctrl+X</kbd>**: Cut / move selected/solidified text to cursor.
- **<kbd>Ctrl+D</kbd> / <kbd>Del</kbd>**: Delete block selection (or character).
- **<kbd>Ctrl+S</kbd>**: Save active block to disk file.

---

## 4. Search and Replace

- **<kbd>Ctrl+F</kbd>**: Search forward with automatic document wrap.
- **<kbd>Ctrl+N</kbd>**: Repeat last search forward without prompt.
- **<kbd>Ctrl+P</kbd>**: Repeat last search backward with wrap.
- **<kbd>Ctrl+R</kbd>**: Interactive Search & Replace with confirmation.
- **<kbd>Tab</kbd> / <kbd>Ctrl+I</kbd>**: Toggle Exact/Insens case at prompt.

---

## 5. File Operations & System Commands

- **<kbd>Ctrl+O</kbd>**: Open multi-column directory browser.
- **<kbd>Ctrl+S</kbd>**: Open save dialog (toggle CRLF/LF format).
- **<kbd>Ctrl+W</kbd>**: Close active file and return to splash screen.
- **<kbd>Ctrl+Q</kbd>**: Exit to CP/M (prompts to save dirty buffer).
- **<kbd>Insert</kbd>**: Toggle between Insert and Overwrite modes.

---

## 6. Command-Line Launch Syntax

`SE.COM` can be launched from the CP/M command line with an optional file path
and line number:

```text
C>SE <filename>[:<line>]
```

Examples:
- `C>SE MAIN.C` — Opens `MAIN.C` at line 1.
- `C>SE MAIN.C:42` — Opens `MAIN.C` centered on line 42 (compiler lint jump).
- `C>SE B:TEST.ASM:100` — Opens file on Drive B: at line 100.
- `C>SE 1C:SOURCE.C` — Opens `SOURCE.C` on Drive C: in User Area 1.
- `C>SE C1:SOURCE.C:42` — Opens `SOURCE.C` in User Area 1 on line 42.

---

## 7. Using the Non-Standard ZX Spectrum Next Keyboard

When running `SE_NEXT.COM` under NextCPM or the native Next targets (`SE.NEX`
and `.se`) on the ZX Spectrum Next's 58-key keyboard (or a classic 48K layout),
standard terminal control keys map to the Next's compound hardware keys:

- **`EXTEND` (`Extend Mode`) or `Caps Shift + Symbol Shift` = `Ctrl`**:
  Hold **`EXTEND`** (or **`Caps Shift + Symbol Shift`**) with a letter key
  (`A`–`Z`) to generate any `Ctrl+<Key>` command (`Ctrl+A` through `Ctrl+Z`).
- **`EDIT` (`Caps Shift + 1`) = `ESC`**:
  Returns to the Splash Screen or cancels active block selections and modals.
- **`BREAK` (`Caps Shift + Space`) = `Ctrl+C`**:
  Copies a marked block to the cursor position.
- **`TRUE VIDEO` (`Caps Shift + 3`) or `EXTEND + I` = `Tab`**:
  Inserts tab spaces in the editor or toggles Exact/Insensitive case in
  Find/Replace modals (`SE_NEXT.COM` disambiguates `TRUE VIDEO` `0x13` from
  `EXTEND + S` via ULA port `0xFDFE` bit 1).
- **`DELETE` (`Caps Shift + 0`) = `Backspace` / `Delete`**:
  Deletes the character left of the cursor (`EXTEND + H` = `Backspace`,
  `EXTEND + D` = forward `Delete` or delete marked block).
- **Dedicated Arrow Keys (`Up`, `Down`, `Left`, `Right`)**:
  Move the cursor in all four directions (`SE_NEXT.COM` polls ULA matrix port
  `0x00FE` to disambiguate physical arrow keys from `Ctrl+F`, `Ctrl+A`,
  `Ctrl+E`, `Ctrl+K`, and `Ctrl+X`).

| Standard SE Key | ZX Spectrum Next SE Key            | Functional Action |
| :---            | :---                               | :---              |
| `Up Arrow`      | `Up` (`Caps Shift + 7`)            | Cursor Up 1 row   |
| `Down Arrow`    | `Down` (`Caps Shift + 6`)          | Cursor Down 1 row |
| `Left Arrow`    | `Left` (`Caps Shift + 5`)          | Cursor Left 1 col |
| `Right Arrow`   | `Right` (`Caps Shift + 8`)         | Cursor Right 1 col|
| `ESC`           | `EDIT` (`Caps Shift + 1`)          | Splash / Cancel   |
| `Enter`         | `Enter`                            | New line / Confirm|
| `Backspace`     | `DELETE` (`Caps Shift + 0`) / `^H` | Delete char left  |
| `Delete` (`^D`) | `EXTEND + D` (`CS + SS + D`)       | Delete char/block |
| `Tab` (`^I`)    | `TRUE VIDEO` (`CS+3`) / `EXTEND+I` | Insert tab spaces |
| `Ctrl+A` (`Home`)| `EXTEND + A` (`CS + SS + A`)      | Start of line     |
| `Ctrl+B`        | `EXTEND + B` (`CS + SS + B`)       | Toggle block mode |
| `Ctrl+C`        | `BREAK` (`CS + Space`) / `EXT + C` | Copy marked block |
| `Ctrl+D`        | `EXTEND + D` (`CS + SS + D`)       | Delete char/block |
| `Ctrl+E` (`End`)| `EXTEND + E` (`Sym Shift + E`)     | End of line (End) |
| `Ctrl+F`        | `EXTEND + F` (`CS + SS + F`)       | Find text modal   |
| `Ctrl+G`        | `EXTEND + G` (`CS + SS + G`)       | Bottom of file    |
| `Ctrl+H`        | `EXTEND + H` (`CS + SS + H`)       | Backspace left    |
| `Ctrl+I` (`Tab`)| `TRUE VIDEO` (`CS+3`) / `EXTEND+I` | Tab / Toggle case |
| `Ctrl+K`        | `EXTEND + K` (`CS + SS + K`)       | Help / Block menu |
| `Ctrl+L`        | `EXTEND + L` (`CS + SS + L`)       | Goto line number  |
| `Ctrl+N`        | `EXTEND + N` (`CS + SS + N`)       | Find next match   |
| `Ctrl+O`        | `EXTEND + O` (`CS + SS + O`)       | Open file browser |
| `Ctrl+P`        | `EXTEND + P` (`CS + SS + P`)       | Plugin palette    |
| `Ctrl+Q`        | `EXTEND + Q` (`Sym Shift + Q`)     | Safe exit to OS   |
| `Ctrl+R`        | `EXTEND + R` (`CS + SS + R`)       | Search & Replace  |
| `Ctrl+S`        | `EXTEND + S` (`CS + SS + S`)       | Save file to disk |
| `Ctrl+T`        | `EXTEND + T` (`CS + SS + T`)       | Top of file (Row0)|
| `Ctrl+U` (`PgUp`)| `EXTEND + U` (`CS + SS + U`)      | Page Up           |
| `Ctrl+V` (`PgDn`)| `EXTEND + V` (`CS + SS + V`)      | Page Down         |
| `Ctrl+W`        | `EXTEND + W` (`Sym Shift + W`)     | Close to splash   |
| `Ctrl+X`        | `EXTEND + X` (`Sym Shift + X`)     | Move marked block |
| `Ctrl+Y`        | `EXTEND + Y` (`CS + SS + Y`)       | Beautify code     |
| `Ctrl+Z`        | `EXTEND + Z` (`CS + SS + Z`)       | Plugin Manager    |

