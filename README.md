# SE: CP/M Full-Screen Text Editor for RomWBW / RC2014

**SE** (`SE.COM`) is a high-performance, full-screen text editor written in 100%
Z80 assembly, specifically designed and supported to run on CP/M 2.2 / 3.0
systems running **RomWBW v3.6.0 or later** (e.g. RC2014, SC126, Zeta 2, SBC)
communicating over **Minicom** or any standard VT100/ANSI terminal emulator.

---

## Key Features

* **RomWBW v3.6.0+ Firmware Requirement**: Engineered strictly for RomWBW
  v3.6.0 and later. Interfaces directly with standardized HBIOS `RST 08H`
  vectors for Far RAM bank discovery, fast memory copying, and RAM drive
  protection. See
  [docs/HARDWARE_COMPATIBILITY.md](docs/HARDWARE_COMPATIBILITY.md).
* **Vim-Style Splash Screen**: Clean startup landing screen with keyboard
  navigation, memory info, and direct editor entry.
* **512KB Extended Memory Buffer**: Breaks the classic 64KB CP/M memory ceiling
  by utilizing RomWBW HBIOS bank switching (`RST 08H`) to allocate and edit
  large files (such as multi-thousand line Z80 assembly source files) in upper
  RAM banks.
* **Interactive File Open & Save Screens**: Sorted multi-column directory
  browser with automatic pagination, filename pre-filling, and overwrite
  confirmation warnings.
* **Format Detection & Toggling**: Seamlessly loads and saves both classic CP/M
  (`CRLF`) and Linux/Unix (`LF`) text files with live toggle in the save screen.
* **ANSI / VT100 Terminal Interface**: Full-screen editing with cursor
  navigation, scrolling, inverse video status bar, and dialog popups tailored
  for Minicom.
* **Z80 ASM Tab Handling**: Configurable tab stops (default 8 columns or 4
  columns) with visual alignment for assembly labels, opcodes, operands, and
  comments.
* **Multi-Line Block Highlighting**: Live visual block selection (toggle with
  `Ctrl+B`) supporting dynamic expansion/contraction across lines in reverse
  video, with status bar line-count reporting.
* **Pure Z80 Assembly Implementation**: Self-contained assembly codebase
  (`src/se.asm`) assembled into `SE.COM` via `z88dk-z80asm`.

---

## Toolchain & Build Environment

`SE.COM` and its companion plugin subsystem are built using the following
tools:
* **`z88dk-z80asm`**: Z80 macro assembler used to assemble `SE.COM` and
  assembly plugins (4K, 8K, 16K, 32K classes).
* **`z88dk` (`zcc`)**: ANSI C cross-compiler used to build the FAT filesystem
  plugin (`plugins/fat/FATFS.PRL`).
* **RomWBW Tools & `cpmtools`**: Host Linux tools (`cpmcp`, `cpmrm`, and
  `diskdefs`) used to create and manipulate CP/M disk images (`hd1k_combo.img`).

### Tools Directory Structure

The build system expects the tools to be arranged in a standard layout:

```text
<tools_directory>/
├── z88dk/
│   ├── bin/ (z88dk-z80asm, zcc)
│   └── lib/config/
├── romwbw_src/
│   ├── Binary/ (hd1k_combo.img, RC2014_std.rom)
│   └── Tools/
│       ├── Linux/ (cpmcp, cpmrm, uz80as)
│       └── cpmtools/diskdefs
└── rc2014_emu/
    └── rc2014 (hardware emulator for tests)
```

---

## Specifying the Tools Location (`TOOLS_DIR` / `TOOL_DIR`)

When cloning the repository outside the default workspace, specify the
location of your tools directory using `TOOLS_DIR` (or `TOOL_DIR`). Both
absolute and relative paths are fully supported.

### Option 1: Pass on the `make` Command Line (Recommended)

You can pass `TOOLS_DIR` directly on any make target:

```bash
# Build SE.COM and all plugins using an absolute path:
make TOOLS_DIR=/tools

# Build using a relative path:
make TOOLS_DIR=../../tools

# Either TOOLS_DIR or TOOL_DIR may be used:
make TOOL_DIR=/opt/retro_tools
```

### Option 2: Set in Environment

Export `TOOLS_DIR` in your terminal session to avoid specifying it on every
command:

```bash
export TOOLS_DIR=/tools

# Standard make targets now automatically use /tools:
make
make image
make check-plugins
```

### Option 3: Monorepo Workspace Default

If neither `TOOLS_DIR` nor `TOOL_DIR` is set, `make` defaults to:
`$(WORKSPACE_ROOT)/tools` (default: `../../tools`).

---

## Building `SE.COM` & Plugins

### Standard Make Targets

From the repository root:

```bash
# 1. Build SE.COM and all plugins (default target):
make
# or
make all

# 2. Build plugins only (ROT13, WORDCNT, BEAUTIFY, FATFS, etc.):
make plugins

# 3. Create CP/M disk image and inject SE.COM and plugins:
make image

# 4. Check binary footprints and ABI conformance:
make check-tpa
make check-plugins
make check-lines

# 5. Run test suites:
make test          # Fast sanity integration test
make test-conformity  # Full regression suite

# 6. Clean build artifacts:
make clean
```

### Running Python Build Scripts Standalone

When invoking Python build utilities directly outside of `make`, provide
`TOOLS_DIR` or `TOOL_DIR` via the environment:

```bash
TOOLS_DIR=/tools python3 plugins/build_plugins.py
```

---

## Python Environment & Automated Tools

The test harness and hardware serial utilities use an isolated Python
virtual environment:

```bash
# Create and activate virtual environment
python3 -m venv .venv
source .venv/bin/activate

# Install dependencies (pyserial, xmodem)
pip install -r requirements.txt
```

---

## Using `SE.COM` (Screen Editor)

### 1. Splash Screen
Launching `SE` without arguments displays the Vim-style splash screen:

```text
~
~                               SE - Screen Editor              
~
~                         type   [E]  or  [Enter]  to edit       
~                         type   [N]              to new file   
~                         type   [O]              to open file  
~                         type   [S]              to save file  
~                         type   [W]  or  [^W]    to close file 
~                         type   [L]  or  [^L]    to goto line  
~                         type   [A]              for about     
~                         type   [M]              for memory info
~                         type   [P]              for plugins   
~                         type   [^P]             for context plugin menu
~                         type   [C]              to configure  
~                         type   [1]              set 120x40    
~                         type   [2]              set 80x24     
~                         type   [Q]  or  [^Q]    to exit       
~
~                     Active Screen : [120x40 (Modern Default)]          
~
 | (Untitled)    | 120x40 | CP/M  | Free: 416 KB    | Line    1/1   Col 0   | 
```

* Press **`e`**, **`E`**, or <kbd>Enter</kbd> to enter/resume full-screen
  editing mode.
* Press **`n`** or **`N`** to start editing a new blank file (`(Untitled)`).
* Press **`w`**, **`W`**, or <kbd>Ctrl+W</kbd> to close current file to splash.
* Press **`o`** or **`O`** to open the interactive **Open File** directory
  browser.
* Press **`s`** or **`S`** to open the interactive **Save File** screen.
* Press **`a`** or **`A`** to view the **About** screen (version, author,
  tools, license).
* Press **`m`** or **`M`** to view the interactive **Memory Info** table.
* Press **`c`** or **`C`** to open the interactive **Configuration** screen.
* Press **`1`** to set modern **120 columns x 40 rows** mode (Default).
* Press **`2`** to set classic **80 columns x 24 rows** terminal mode.
* Press **`q`**, **`Q`**, or <kbd>Ctrl+Q</kbd> to return cleanly to CP/M.

### 2. Command-Line Launch & Goto Line

`SE.COM` can be launched directly from the CP/M command line with an optional
target filename and line number:
```text
C>SE <filename>[:<line>]
```
Examples:
* `C>SE 30.TXT` — Opens `30.TXT` directly in the editor at Line 1.
* `C>SE 30.TXT:15` — Opens `30.TXT` with viewport centered on Line 15.
* `C>SE B:MYFILE.ASM:42` — Opens file on Drive B: centered on Line 42
  (matching compiler error output).

### 3. Editor Mode Keybindings & Hybrid Block Highlighting

* <kbd>Ctrl+F</kbd>: Find text (forward search with document wrap; highlights
  match as solidified block; pre-fills from active block).
* <kbd>Ctrl+N</kbd>: Find Next (repeats search forward without re-prompting;
  reports "Search completed." on wrap loop completion).
* <kbd>Ctrl+P</kbd>: Find Previous (repeats search backward with document wrap;
  reports "Search completed." on wrap loop completion).
* <kbd>Ctrl+R</kbd>: Search and Replace (prompts for find & replace strings;
  pre-fills from active block; interactive confirmation: `y`=yes, `n`=no,
  `a`=all, `q`=quit, `r`/`p`=reverse direction).
* <kbd>Ctrl+I</kbd> / <kbd>Tab</kbd>: Toggle case sensitivity in Find/Replace
  prompt between `[Exact]` (session default) and `[Insens]`.
* <kbd>Ctrl+L</kbd>: Goto line number (prompts on status line; centers viewport
  on target line).
* <kbd>Ctrl+B</kbd>: Start / toggle block selection mode (anchors at cursor row
  and character column).
* <kbd>Ctrl+K</kbd>: Solidify (lock/freeze) active block selection, or show
  Editor Keys Reference Screen if no block active.
* <kbd>Ctrl+C</kbd>: Copy solidified block to current cursor position (or
  solidify dynamic block).
* <kbd>Ctrl+X</kbd>: Move solidified block to current cursor position (or
  solidify dynamic block).
* <kbd>Ctrl+D</kbd> / <kbd>Delete</kbd>: Forward delete character under cursor
  (or delete selected/solidified block).
* <kbd>Insert</kbd>: Toggle between Insert mode (default) and Overwrite mode
  (status bar displays `Overwrite mode  | `).
* <kbd>ESC</kbd>: Dismiss active or solidified block highlight (or return to
  splash screen if no block active).
* <kbd>Arrow Keys</kbd> / <kbd>Home</kbd> / <kbd>End</kbd> / <kbd>PgUp</kbd> /
  <kbd>PgDn</kbd>: Move cursor and dynamically expand or contract block
  highlight (partial lines, single lines, or multi-lines).
* <kbd>Ctrl+O</kbd>: Open interactive file browser.
* <kbd>Ctrl+S</kbd>: Open save file screen.
* <kbd>Ctrl+W</kbd>: Close file and return to splash screen (prompts to save
  if modified).
* <kbd>Ctrl+Q</kbd>: Clean exit to CP/M (prompts to save if modified).

### 4. Screen Size Configurations

`SE.COM` supports both modern widescreen and retro terminal geometries:
* **Modern Mode (120x40 - Default)**: Uses 120 columns by 40 rows, ideal for
  modern terminal emulators (e.g. Minicom, GNOME Terminal, Windows Terminal,
  xterm) giving 39 lines of visible text buffer and footer on row 40.
* **Classic Mode (80x24)**: Uses 80 columns by 24 rows, ideal for classic VT100
  hardware terminals or 80x24 serial windows.


---

## Deploying & Running on RC2014

### 1. In the Local RC2014 Hardware Emulator

From the project workspace root:
```bash
# Build SE.COM, inject into modern hd1k image, and launch emulator
make run
```

### 2. On Real Hardware (RC2014 via Minicom & XM.COM)

#### Option A: Direct Minicom XMODEM Transfer

1. Connect to your RC2014 serial port at `115200 bps 8N1` with full-duplex
   RTR/CTS hardware flow control (via RTS/CTS pins):
   ```bash
   minicom -b 115200 -D /dev/ttyUSB0
   ```
2. Set Minicom terminal emulation:
   * Terminal type: `VT102` or `ANSI`
   * Backspace key: `BS` (0x08) or `DEL` (0x7F)
3. On the CP/M SBC, switch to your target drive (e.g. `J:`) and start receiver:
   ```text
   A>J:
   J>A:XM R SE.COM
   ```
4. In Minicom, press `Ctrl+A` then `S`, choose `xmodem`, and select `SE.COM`.
5. Launch on the SBC:
   ```text
   J>SE
   ```

#### Option B: Automated Python Script Transfer
1. On your CP/M SBC, start the receiver:
   ```text
   J>A:XM R SE.COM
   ```
2. From the host terminal (ensure Minicom is closed so port is free):
   ```bash
   .venv/bin/python tests/send_xmodem.py SE.COM /dev/ttyUSB0
   ```
3. Re-open Minicom and run `J>SE`.

---

## Project Structure

```
screen_editor/
├── Makefile                # Build targets (SE.COM, plugins, image, test)
├── README.md               # Toolchain setup, build guide & documentation
├── CODING_GUIDELINES.md    # Coding and formatting standards
├── requirements.txt        # Python dependencies for tests & tools
├── SE.COM                  # Assembled CP/M binary
├── src/
│   └── se.asm              # 100% Z80 assembly editor implementation
├── plugins/                # Modular CP/M 3 plugin subsystem (PRL / OVL)
│   ├── build_plugins.py    # Reference plugin packaging script
│   ├── PLUGIN_ABI.md       # Plugin architecture and ABI specification
│   └── fat/                # 32KB Far-RAM FAT filesystem plugin & tests
├── tools/                  # Host development and packaging utilities
│   ├── mkprl.py            # CP/M 3 PRL and OVL binary packager
│   └── z80_beautifier/     # Multi-dialect Z80 assembly reformatter
├── docs/                   # Architecture, UI/UX, and reference specs
│   ├── ARCHITECTURE.md     # Technical specification & memory layout
│   ├── BUILD_SETUP.md      # Toolchain setup and verification
│   ├── USER_GUIDE.md       # Complete user guide and manual
│   ├── TROUBLESHOOTING.md  # Diagnostic & troubleshooting guide
│   ├── HARDWARE_COMPATIBILITY.md # Hardware & RomWBW requirements
│   ├── UI_UX_DESIGN.md     # Visual hierarchy and screen design rules
│   └── KEYBINDINGS.md      # Complete editor and splash key reference
└── tests/                  # Automated integration and regression suites
    ├── README.md           # Test suite documentation
    ├── test_sanity.py      # Fast integration sanity test
    └── test_editor_headless.py # Full PTY emulator conformity suite
```
