# SE: CP/M Full-Screen Text Editor for RomWBW / RC2014

**SE** (`SE.COM`) is a high-performance, full-screen text editor written in 100% Z80 assembly, specifically designed for CP/M 2.2 / 3.0 systems running the **RomWBW** firmware (e.g. RC2014, SC126, Zeta 2, SBC) communicating over **Minicom** or any standard VT100/ANSI terminal emulator.

---

## Key Features

* **Vim-Style Splash Screen & Diagnostics**: Clean startup landing screen
  with keyboard navigation, memory diagnostics, and direct editor entry.
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
* **Pure Z80 Assembly Implementation**: Self-contained, zero-dependency
  assembly codebase (`src/se.asm`) assembled directly into `SE.COM` via `uz80as`.

---

## Toolchain & Build Environment

`SE.COM` is assembled using **`uz80as`** (the micro Z80 assembler included with RomWBW tools or available as a standalone utility). No C cross-compiler or external runtime libraries are required.

The `uz80as` binary for Linux host systems is located in the repository under:
```
tools/romwbw_src/Tools/Linux/uz80as
```

---

## Building `SE.COM`

You can build `SE.COM` either using `make` or manually invoking `uz80as` directly.

### Option 1: Using `make` (from `src/screen_editor/`)

Navigate to `src/screen_editor` and run `make`:

```bash
cd src/screen_editor

# Assemble SE.COM:
make

# Assemble SE.COM and inject it into the RomWBW disk image (hd1k_combo.img):
make image

# Run automated headless integration tests:
make test

# Clean build artifacts:
make clean
```

### Option 2: Manual Assembly using `uz80as` directly (without `make`)

You can assemble `SE.COM` directly from the command line without invoking `make`.

* **From inside `src/screen_editor/`**:
  ```bash
  cd src/screen_editor
  ../../tools/romwbw_src/Tools/Linux/uz80as -q src/se.asm SE.COM
  ```

* **From the workspace root**:
  ```bash
  tools/romwbw_src/Tools/Linux/uz80as -q src/screen_editor/src/se.asm src/screen_editor/SE.COM
  ```

#### Command Options & Disassembly Listings
* **`-q` (Quiet)**: Suppresses generating the `.lst` listing file for faster assembly.
* **Generating a Listing File**: Omit `-q` or provide a 3rd argument to produce an assembly listing with symbol addresses and opcodes:
  ```bash
  ../../tools/romwbw_src/Tools/Linux/uz80as src/se.asm SE.COM SE.lst
  ```

### Option 3: Using `make` (from workspace root)

From the project root directory, the top-level Makefile provides convenient targets:

```bash
make editor   # Assembles SE.COM
make image    # Assembles SE.COM and injects it into hd1k_combo.img
make run      # Assembles, injects, and boots the RC2014 hardware emulator
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
                  ~             SE - Screen Editor              
                  ~                version 0.8.1                
                  ~              by Dean Jenkins                
                  ~                                             
                  ~       SE is open source and freely usable   
                  ~                                             
                  ~       type   :e  or  <Enter>   to edit      
                  ~       type   :o                to open file 
                  ~       type   :s                to save file 
                  ~       type   :t                for mem test 
                  ~       type   :f                for file test
                  ~       type   :1                set 120x40   
                  ~       type   :2                set 80x24    
                  ~       type   :q  or  ^Q        to exit      
                  ~                                             
                  ~   Active Screen: [120x40 (Modern Default)]  
                  ~      Z80 CP/M with 512K Extended Storage    
                  ~      Auto-detects CP/M [CRLF] & Linux [LF]  
                  ~                                             
```

* Press **`e`**, **`E`**, or <kbd>Enter</kbd> to enter full-screen editing mode.
* Press **`o`** or **`O`** to open the interactive **Open File** directory browser.
* Press **`s`** or **`S`** to open the interactive **Save File** screen.
* Press **`t`** or **`T`** to run the live **512KB Extended Memory Diagnostic**.
* Press **`f`** or **`F`** to run the **Multi-Sector File I/O Diagnostic**.
* Press **`1`** to set modern **120 columns x 40 rows** mode (Default).
* Press **`2`** to set classic **80 columns x 24 rows** terminal mode.
* Press **`q`**, **`Q`**, or <kbd>Ctrl+Q</kbd> to return cleanly to CP/M.

### 2. Command-Line Launch & Goto Line
`SE.COM` can be launched directly from the CP/M command line with an optional target filename and line number:
```text
C>SE <filename>[:<line>]
```
Examples:
* `C>SE 30.TXT` — Opens `30.TXT` directly in the editor at Line 1.
* `C>SE 30.TXT:15` — Opens `30.TXT` with the viewport centered on Line 15.
* `C>SE B:MYFILE.ASM:42` — Opens file on Drive B: centered on Line 42 (matching compiler error output).

### 3. Editor Mode Keybindings & Hybrid Block Highlighting
* <kbd>Ctrl+F</kbd>: Find text (forward search with document wrap; highlights match as solidified block; pre-fills from active block; displays `Find [Exact] : ` on status bar).
* <kbd>Ctrl+N</kbd>: Find Next (repeats search forward without re-prompting; reports "Search completed." on wrap loop completion).
* <kbd>Ctrl+P</kbd>: Find Previous (repeats search backward with document wrap; reports "Search completed." on wrap loop completion).
* <kbd>Ctrl+R</kbd>: Search and Replace (prompts for find & replacement strings; pre-fills from active block; interactive confirmation `y`=yes, `n`=no, `a`=all, `q`=quit, `r`/`p`=reverse direction; guards 120-character line length limit).
* <kbd>Ctrl+I</kbd> / <kbd>Tab</kbd>: Toggle case sensitivity in Find/Replace prompt between `[Exact]` (session default) and `[Insens]`.
* <kbd>Ctrl+L</kbd>: Goto line number (prompts on status line; centers viewport on target line).
* <kbd>Ctrl+B</kbd>: Start / toggle block selection mode (anchors at cursor row & character column).
* <kbd>Ctrl+K</kbd>: Solidify (lock/freeze) active block selection, or show Editor Keys Reference Screen if no block active.
* <kbd>Ctrl+C</kbd>: Copy solidified block to current cursor position (or solidify dynamic block).
* <kbd>Ctrl+X</kbd>: Move solidified block to current cursor position (or solidify dynamic block).
* <kbd>Ctrl+D</kbd> / <kbd>Delete</kbd>: Forward delete character under cursor (or delete selected/solidified block).
* <kbd>ESC</kbd>: Dismiss active or solidified block highlight (or return to splash screen if no block active).
* <kbd>Arrow Keys</kbd> / <kbd>Home</kbd> / <kbd>End</kbd> / <kbd>PgUp</kbd> / <kbd>PgDn</kbd>: Move cursor and dynamically expand or contract block highlight (partial lines, single lines, or multi-lines).
* <kbd>Ctrl+O</kbd>: Open interactive file browser.
* <kbd>Ctrl+S</kbd>: Open save file screen.
* <kbd>Ctrl+Q</kbd>: Clean exit to CP/M.

### 4. Screen Size Configurations
`SE.COM` supports both modern widescreen and retro terminal geometries:
* **Modern Mode (120x40 - Default)**: Uses 120 columns by 40 rows, ideal for
  modern terminal emulators (e.g. Minicom, GNOME Terminal, Windows Terminal,
  xterm) giving 39 lines of visible text buffer and footer on row 40.
* **Classic Mode (80x24)**: Uses 80 columns by 24 rows, ideal for classic VT100
  hardware terminals or 80x24 serial windows.

### 4. 512KB Extended Memory Diagnostic
Pressing `t` on the splash screen queries the RomWBW HBIOS API (`RST 08H`), reports
hardware memory capacity, and runs an inter-bank DMA transfer (`SYSSETCPY` / `SYSBNKCPY`)
between CP/M User RAM and upper 32KB RAM banks:

```text
=== SE.COM 512KB Extended Memory Diagnostic ===

[+] RomWBW HBIOS API (RST 08H): DETECTED
[*] Installed RAM Banks: 16 x 32KB (512KB Total RAM)
[*] Active CP/M User Bank ID: 0x00
[*] Testing Inter-Bank Far Memory Transfer (Bank 0 <-> Bank 1)...
[+] 512KB Far Memory Banking Test: PASSED! (Pattern 0xAA55 Verified)

Press any key to return to Splash Screen...
```

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
1. Connect to your RC2014 serial port at `115200 8N1` with hardware flow control:
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
src/screen_editor/
├── Makefile                # Build targets (SE.COM, image, test, clean)
├── README.md               # Toolchain setup, build guide & documentation
├── CODING_GUIDELINES.md    # Z80 assembly coding standards
├── requirements.txt        # Python dependencies for tests & tools
├── SE.COM                  # Assembled CP/M binary
├── src/
│   └── se.asm              # 100% Z80 assembly editor implementation
└── tests/
    ├── README.md           # Test suite documentation
    ├── test_editor_headless.py # Automated PTY integration test runner
    ├── send_xmodem.py      # Serial XMODEM file sender for real hardware
    └── sample_large.asm    # Large assembly file for tab/paging tests
```
