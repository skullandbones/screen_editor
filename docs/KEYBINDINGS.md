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

- **<kbd>Ctrl+B</kbd>**: Anchor selection at cursor; dynamic highlight.
- **<kbd>Ctrl+K</kbd>**: Freeze highlight in place, allowing free travel.
- **<kbd>Ctrl+C</kbd>**: Copy selected/solidified text to cursor.
- **<kbd>Ctrl+X</kbd>**: Cut / move selected/solidified text to cursor.
- **<kbd>Ctrl+D</kbd> / <kbd>Del</kbd>**: Delete block selection (or character).
- **<kbd>ESC</kbd>**: Clear active or solidified block highlight.

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
