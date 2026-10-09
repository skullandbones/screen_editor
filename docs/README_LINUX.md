# SE Screen Editor: Linux Native Profile (se-linux)

`se-linux` is the native Linux port of **SE (Screen Editor)**, built using
portable C core modules (`src/core/`) and a POSIX Hardware Abstraction Layer
(`src/hal/linux/`). It provides a high-fidelity retro full-screen editing
experience with modern Linux convenience and performance across both x86_64
workstations and AArch64 systems (such as Raspberry Pi 4 and 5).

---

## Key Features

* **Multi-Platform C Architecture**: Drop-in C equivalent modules mirroring
  the modular Z80 assembly engine with clean abstraction boundaries.
* **Native POSIX HAL**: High-performance ANSI terminal I/O using termios raw
  mode, non-blocking keyboard input decoding, and POSIX file system access.
* **Architecture Targets**: First-class support for Linux PC / Workstation
  (`x86_64`) and Raspberry Pi 4 / 5 (`aarch64`).
* **WordStar & ANSI Navigation**: Authentic WordStar-style control chords
  (`Ctrl+S`, `Ctrl+Q`, `Ctrl+F`, `Ctrl+R`, `Ctrl+K`) alongside standard ANSI
  terminal arrow keys, PageUp/PageDown, and Home/End.
* **Tiered UI Hierarchy**:
  - **Tier 1 (Full-Screen Workspaces)**: Splash landing screen and editor.
  - **Tier 2 (Centered Modals)**: Boxed dialogs for file browsing, search and
    replace, configuration, memory diagnostics, and plugin management.
  - **Tier 3 (Persistent Status Bar)**: Bottom-row status feedback reporting
    active file, screen geometry, line/column coordinates, and alert messages.
* **Dual Line-Ending Support**: Seamlessly detects, loads, and saves both
  Unix (`LF`) and CP/M (`CRLF`) line terminators.
* **Extended Virtual Buffer**: Dynamic heap-backed line-slot paging engine
  providing smooth editing of multi-thousand-line source files.
* **Integrated Code Beautifier**: Built-in Z80 assembly auto-reformatter and
  column alignment engine (`Ctrl+Y`).

---

## System Requirements & Prerequisites

Building and running `se-linux` requires a standard Linux development
environment:

* **Operating System**: Linux kernel 3.2 or newer (Ubuntu 20.04+, Debian 11+,
  Fedora 36+, Arch Linux, Raspberry Pi OS, or compatible distributions).
* **C Compiler**: GCC (`gcc` 9.0+) or Clang (`clang` 10.0+) with C99/C11
  support.
* **Build System**: GNU Make (`make` 3.81+).
* **C Library**: Standard POSIX C library (`glibc` or `musl`) providing
  `<termios.h>`, `<sys/ioctl.h>`, and `<dirent.h>`.
* **Terminal**: Any VT100 / ANSI compatible terminal emulator (GNOME Terminal,
  Alacritty, Kitty, Windows Terminal, xterm, Minicom, or Linux virtual console).
* **Python (Optional)**: Python 3.8+ for executing automated test suites
  (`tests/test_linux_native.py`).

---

## Building se-linux

### 1. Standard Native Build

Compile the native Linux executable directly from the repository root:

```bash
make se-linux
```

This compiles all C core modules and POSIX HAL drivers with `-O2` optimization
and `-Wall -Wextra -Werror` compiler hygiene, producing the standalone
`se-linux` binary in the project root.

### 2. Cross-Compilation for Raspberry Pi (AArch64)

To build for Raspberry Pi 4 or 5 from an x86_64 host machine, specify an
AArch64 cross-compiler:

```bash
make se-linux CC=aarch64-linux-gnu-gcc
```

### 3. Debug Build

To compile with debugging symbols and disabled optimizations for use with GDB:

```bash
make se-linux CFLAGS="-Wall -Wextra -g -O0 -Isrc/include"
```

### 4. Cleaning Build Artifacts

To remove compiled binaries and object files:

```bash
make clean
```

---

## Installation Instructions

You can run `se-linux` directly in-place from the source directory, or install
it into your system binary search path.

### Option 1: System-Wide Installation (Recommended for All Users)

Install the compiled binary into `/usr/local/bin`:

```bash
sudo install -m 755 se-linux /usr/local/bin/se-linux
```

To verify system installation:

```bash
which se-linux
se-linux --help
```

### Option 2: User-Local Installation (No Root Privileges Required)

Install into your personal `~/.local/bin` directory:

```bash
install -d ~/.local/bin
install -m 755 se-linux ~/.local/bin/se-linux
```

Ensure `~/.local/bin` is in your `PATH` environment variable (typically set in
`~/.bashrc` or `~/.profile`):

```bash
export PATH="$HOME/.local/bin:$PATH"
```

### Option 3: Uninstalling

To remove `se-linux` from your system:

```bash
# For system-wide install:
sudo rm -f /usr/local/bin/se-linux

# For user-local install:
rm -f ~/.local/bin/se-linux
```

---

## Starting Instructions & Command-Line Usage

### Synopsis

```text
se-linux [options] [filename]
```

### 1. Launching into Splash Screen

Starting `se-linux` without arguments launches the Vim-style splash landing
screen:

```bash
./se-linux
```

From the splash screen, press `E` or `Enter` to start editing a blank document,
`O` to browse and open a file, or `Q` to exit.

### 2. Opening an Existing File

To open a file directly in the editor:

```bash
./se-linux document.txt
```

If the specified file exists, it will be loaded into the buffer with line
endings automatically detected.

### 3. Creating a New File

To create and start editing a new file under a specified name:

```bash
./se-linux new_source.c
```

The editor initializes an empty document with the target filename pre-assigned.
Saving with `Ctrl+S` writes directly to this file.

### 4. Command-Line Help

To print usage syntax and version information:

```bash
./se-linux --help
```

---

## Keybindings & Interactive Controls

### Splash Screen Controls

| Key | Description |
| :--- | :--- |
| `E` / `Enter` | Enter full-screen editor mode |
| `N` | Start a new empty document |
| `O` | Open interactive file browser modal |
| `S` | Open save file modal |
| `W` / `Ctrl+W` | Close current document and return to splash |
| `A` | Show About dialog |
| `M` | Display memory usage diagnostics |
| `P` | Open plugin manager dialog |
| `C` | Open editor configuration settings |
| `1` | Switch terminal geometry to 120x40 (Modern default) |
| `2` | Switch terminal geometry to 80x24 (Classic terminal) |
| `Q` / `Ctrl+Q` | Exit SE back to shell |

### Editor Navigation & Cursor Movement

| Key | Description |
| :--- | :--- |
| `Up` / `Down` | Move cursor up or down one line |
| `Left` / `Right` | Move cursor left or right one column |
| `Home` | Jump to column 0 of current line |
| `End` | Jump to end of current line |
| `Page Up` | Scroll viewport up one screen page |
| `Page Down` | Scroll viewport down one screen page |
| `Insert` | Toggle between Insert and Overwrite modes |
| `Backspace` | Delete character before cursor |
| `Delete` | Delete character under cursor |

### WordStar & Editor Command Chords

| Shortcut | Action | Description |
| :--- | :--- | :--- |
| `Ctrl+S` | Save Document | Save current buffer to disk |
| `Ctrl+Q` | Clean Exit | Exit editor (prompts if unsaved changes) |
| `Ctrl+O` | Open File | Open directory browser modal |
| `Ctrl+W` | Close File | Close active file and return to splash |
| `Ctrl+F` | Find Text | Search forward for text string |
| `Ctrl+N` | Find Next | Repeat forward search for previous string |
| `Ctrl+P` | Find Previous | Repeat search backward with wrap-around |
| `Ctrl+R` | Replace Text | Search and replace with confirmation |
| `Ctrl+L` | Go to Line | Jump directly to specified line number |
| `Ctrl+B` | Block Select | Toggle visual block selection mode |
| `Ctrl+K` | Solidify / Help | Solidify block selection, or show Help |
| `Ctrl+C` | Copy Block | Copy solidified block to cursor position |
| `Ctrl+X` | Move Block | Cut and paste solidified block to cursor |
| `Ctrl+D` | Delete Block | Delete highlighted block or current char |
| `Ctrl+Y` | Beautify Code | Auto-format Z80 assembly source lines |
| `Ctrl+Z` | Plugin Manager | Open modular plugin configuration modal |
| `Esc` | Cancel / Dismiss| Cancel modal dialog or dismiss block selection |

---

## Automated Verification & Testing

The Linux native profile includes an automated end-to-end PTY test suite
located at `tests/test_linux_native.py`.

### Running Tests

Execute the automated test suite using make:

```bash
make test-linux
```

Or run the Python test harness directly:

```bash
python3 tests/test_linux_native.py
```

### Verified Test Scenarios

The automated test runner executes without hanging or blocking:

1. **Compilation Validation**: Asserts `make se-linux` produces a valid binary
   with zero compiler warnings or errors.
2. **CLI Help Interface**: Validates `--help` and `-h` return code 0 and output
   expected usage syntax.
3. **Interactive PTY Session**: Launches `se-linux` inside a virtual pseudo-
   terminal, verifies initial splash screen output, sends `Ctrl+Q`, and
   verifies clean terminal restoration and exit code 0.
4. **Document Load, Edit, & Save**: Loads a sample document into `se-linux`,
   modifies text via keyboard input, writes changes to disk via `Ctrl+S`,
   exits cleanly, and asserts the on-disk file content matches modifications.
5. **Unsaved Changes Prompt**: Edits a document without saving, triggers
   `Ctrl+Q`, asserts the modal confirmation prompt displays, answers `n`
   (discard changes), and verifies clean exit.
6. **Non-Blocking Process Supervision**: All sub-process invocations utilize
   strict timeout deadlines (`wait_pid_with_timeout`) with non-blocking polling
   to guarantee zero test hangs.

---

## Architecture & Directory Layout

The C Linux SE architecture separates core editor logic from platform I/O:

```text
src/
├── se_linux.c              # Linux native entry point & CLI coordinator
├── include/                # Subsystem API header specifications
│   ├── config.h            # Configuration settings & defaults
│   ├── buffer.h            # Line-slot buffer paging interface
│   ├── memory.h            # Memory allocator & slot management
│   ├── editor.h            # Editor loop, cursor, & key dispatch
│   ├── block.h             # Block highlight & clipboard operations
│   ├── search.h            # String search & replace engine
│   ├── ui.h                # Modal dialogs & frame renderer
│   ├── file_io.h           # Document load, save, & format detection
│   ├── plugin.h            # Modular plugin manager & host API
│   ├── beautify.h          # Z80 code beautifier & alignment
│   └── hal.h               # Hardware Abstraction Layer signatures
├── core/                   # Platform-agnostic C core implementations
│   ├── buffer.c            # Line storage cache & slot split/join
│   ├── memory.c            # Dynamic heap paging & slot allocation
│   ├── editor.c            # Key processing, cursor, & text editing
│   ├── block.c             # Multi-line selection & block operations
│   ├── search.c            # Case-sensitive / insensitive search
│   ├── ui_render.c         # Viewport repaint & persistent status bar
│   ├── ui_modal.c          # Boxed dialog frames & button selectors
│   ├── ui_browser.c        # Directory pagination & file picker
│   ├── config.c            # SE.CFG configuration parser & writer
│   ├── plugin_mgr.c        # Plugin relocation & host trampolines
│   ├── beautify.c          # Multi-dialect assembly code formatter
│   └── file_io.c           # File loading, saving, & CRLF/LF handling
└── hal/linux/              # POSIX Hardware Abstraction Layer
    ├── hal_linux_console.c # ANSI escape codes & termios raw terminal
    ├── hal_linux_keyboard.c# Non-blocking stdin & escape key decoder
    ├── hal_linux_memory.c  # Linux heap memory management
    └── hal_linux_storage.c # POSIX file I/O & directory enumeration
```

---

## Configuration (`SE.CFG`)

`se-linux` automatically loads editor settings from `SE.CFG` in the current
working directory if present. Configurable options include:

* **Tab Width**: Set default tab stop indentation (4 or 8 columns).
* **Screen Mode**: Select default terminal geometry (80x24 or 120x40).
* **Line Terminators**: Default save format (`LF` for Unix or `CRLF` for CP/M).
* **Beautifier Alignment**: Column stops for assembly labels, mnemonics,
  operands, and inline comments.
