# SE: CP/M Full-Screen Text Editor for RomWBW / RC2014

**SE** (`SE.COM`) is an ANSI C, full-screen text editor specifically designed for CP/M 2.2 / 3.0 systems running the **RomWBW** firmware (e.g. RC2014, SC126, Zeta 2, SBC) communicating over **Minicom** or any standard VT100/ANSI terminal emulator.

---

## Key Features

* **Vim-Style Splash Screen & Diagnostics**: Clean startup landing screen
  with keyboard navigation, memory diagnostics, and direct editor entry.
* **512KB Extended Memory Buffer**: Breaks the classic 64KB CP/M memory ceiling
  by utilizing RomWBW HBIOS bank switching (`RST 08H`) to allocate and edit
  large files (such as multi-thousand line Z80 assembly source files) in upper
  RAM banks.
* **ANSI / VT100 Terminal Interface**: Full-screen editing with cursor
  navigation, scrolling, inverse video status bar, and dialog popups tailored
  for Minicom.
* **Z80 ASM Tab Handling**: Configurable tab stops (default 8 columns or 4
  columns) with visual alignment for assembly labels, opcodes, operands, and
  comments.
* **Modern ANSI C Codebase**: Built using standard C89/C99 with isolated Z80
  assembly primitives for bare-metal HBIOS inter-bank transfers.

---

## Toolchain & Build Environment Setup

The build system utilizes **`z88dk`** (the modern ANSI C cross-compiler targeting Z80 CP/M).

### 1. Ubuntu / Debian (x86_64 Host)

#### Option A: Binary Release Archive (Recommended & Fastest)
1. Install prerequisites:
   ```bash
   sudo apt update
   sudo apt install -y build-essential curl libxml2 libboost-all-dev git
   ```
2. Download and unpack the latest z88dk release:
   ```bash
   mkdir -p ~/tools/z88dk
   cd ~/tools/z88dk
   curl -L https://github.com/z88dk/z88dk/releases/download/v2.3/z88dk-linux-x86_64-2.3.tgz -o z88dk.tgz
   tar -xzf z88dk.tgz
   ```
3. Set your environment variables in `~/.bashrc`:
   ```bash
   export Z88DK_PATH="$HOME/tools/z88dk"
   export PATH="$Z88DK_PATH/bin:$PATH"
   export ZCCCFG="$Z88DK_PATH/lib/config"
   ```
4. Reload shell:
   ```bash
   source ~/.bashrc
   ```

---

### 2. Raspberry Pi 5 (Raspberry Pi OS / Debian Trixie aarch64 Host)

On a Raspberry Pi 5 running **Debian Trixie (testing / 64-bit arm64)** or Raspberry Pi OS based on Trixie:

#### Option A: Quick Build from Source with System SDCC
1. Install required packages from Debian Trixie repositories:
   ```bash
   sudo apt update
   sudo apt install -y build-essential git bison flex libxml2-dev libboost-all-dev sdcc
   ```
2. Clone and build z88dk:
   ```bash
   git clone --recursive https://github.com/z88dk/z88dk.git ~/z88dk
   cd ~/z88dk
   ./build.sh
   ```
3. Add to `~/.bashrc`:
   ```bash
   export PATH="$HOME/z88dk/bin:$PATH"
   export ZCCCFG="$HOME/z88dk/lib/config"
   ```

#### Option B: Nightly Binary Tarball (ARM64)
Alternatively, fetch the pre-built nightly for Linux aarch64 from the z88dk daily repository:
```bash
mkdir -p ~/tools/z88dk && cd ~/tools/z88dk
curl -L http://nightly.z88dk.org/z88dk-linux-arm64-latest.tgz -o z88dk.tgz
tar -xzf z88dk.tgz
export ZCCCFG="$HOME/tools/z88dk/lib/config"
export PATH="$HOME/tools/z88dk/bin:$PATH"
```

---

## Building `SE.COM`

Once `zcc` is in your `PATH`, compile the editor from the repository root:

```bash
cd src/screen_editor
make
```

This will produce the binary:
```
SE.COM
```

To clean build artifacts:
```bash
make clean
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
                  ~                version 0.2.0                
                  ~              by Dean Jenkins                
                  ~                                             
                  ~       SE is open source and freely usable   
                  ~                                             
                  ~       type   :e  or  <Enter>   to edit      
                  ~       type   :t                for mem test 
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
* Press **`1`** to set modern **120 columns x 40 rows** mode (Default).
* Press **`2`** to set classic **80 columns x 24 rows** terminal mode.
* Press **`t`** or **`T`** to run the live **512KB Extended Memory Diagnostic**.
* Press **`q`**, **`Q`**, or <kbd>Ctrl+Q</kbd> to return cleanly to CP/M.

### 2. Screen Size Configurations
`SE.COM` supports both modern widescreen and retro terminal geometries:
* **Modern Mode (120x40 - Default)**: Uses 120 columns by 40 rows, ideal for
  modern terminal emulators (e.g. Minicom, GNOME Terminal, Windows Terminal,
  xterm) giving 39 lines of visible text buffer and footer on row 40.
* **Classic Mode (80x24)**: Uses 80 columns by 24 rows, ideal for classic VT100
  hardware terminals or 80x24 serial windows.

### 3. 512KB Extended Memory Diagnostic
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
├── Makefile                # Cross-compilation & test targets
├── README.md               # Toolchain setup and documentation
├── CODING_GUIDELINES.md    # ANSI C and Z80 assembly coding standards
├── requirements.txt        # Python dependencies for tests & tools
├── include/
│   ├── editor.h            # Main editor state and configuration
│   ├── terminal.h          # VT100 / ANSI escape routines & key input
│   ├── buffer.h            # 512K Far memory buffer and line indexing
│   └── hbios.h             # RomWBW HBIOS API (RST 08H) bindings
├── src/
│   ├── main.c              # Application entry & main event loop
│   ├── terminal.c          # Screen renderer and ANSI key decoder
│   ├── buffer.c            # Gap buffer and line management
│   ├── fileio.c            # CP/M BDOS file load/save
│   ├── se.asm              # Standalone assembly editor implementation
│   └── hbios_far.asm       # Z80 assembly for RomWBW inter-bank transfers
└── tests/
    ├── README.md           # Test suite documentation
    ├── test_editor_headless.py # Automated PTY integration test runner
    ├── send_xmodem.py      # Serial XMODEM file sender for real hardware
    └── sample_large.asm    # Large assembly file for tab/paging tests
```
