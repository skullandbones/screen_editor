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
* **512KB Extended Memory Buffer**: Breaks the classic 64KB CP/M memory ceiling
  by utilizing RomWBW HBIOS bank switching (`RST 08H`) to allocate and edit
  large files (such as multi-thousand line Z80 assembly source files) in upper
  RAM banks.
* **Canonical Full-Screen UI/UX & Terminal Interface**: Mathematically centered
  workspaces, boxed modal dialogs, universal status bar, direct in-place block
  manipulation, and VT100/ANSI keybindings across all SE variants. See
  [docs/UI_UX_DESIGN.md](docs/UI_UX_DESIGN.md) for the authoritative UI/UX
  specification.
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

# 2. Build ZX Spectrum Next targets:
make se-next-cpm       # NextCPM 80-column binary (SE_NEXT.COM)
make se-next-native    # Native NextZXOS binaries (SE.NEX, .se)

# 3. Build plugins only (ROT13, WORDCNT, BEAUTIFY, FATFS, etc.):
make plugins

# 4. Create CP/M disk image and inject SE.COM and plugins:
make image

# 5. Check binary footprints and ABI conformance:
make check-tpa
make check-plugins
make check-lines

# 6. Run test suites:
make test          # Fast sanity integration test
make test-conformity  # Full regression suite

# 7. Clean build artifacts:
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

### 1. Command-Line Launch & Goto Line

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
* `C>SE 1C:SOURCE.C` — Opens `SOURCE.C` on Drive C: in User Area 1.
* `C>SE C1:SOURCE.C:42` — Opens `SOURCE.C` in User Area 1 on Line 42.

### 2. UI/UX Design, Workspaces, Modals & Keybindings

All interactive user interface surfaces, screen geometries (`80x24` baseline
default, `120x40` extended console, and `NATIVE` host mode), Tier 1 full-screen
workspaces (Splash, Help, Configuration Manager, Directory Browser, About,
Memory Info, Plugin Manager), Tier 2 modal dialogs, status bar layout, block
manipulation, and keybindings across all SE variants are governed by a single
authoritative specification:

* **[`docs/UI_UX_DESIGN.md`](docs/UI_UX_DESIGN.md)** — Canonical Look and Feel,
  functional behavior, keybinding matrix, and configuration specification.


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

## Deploying & Running on ZX Spectrum Next

The editor supports two operating environments on the ZX Spectrum Next:
1. **NextCPM**: Full CP/M 2.2 with 80-column ANSI console (`SE_NEXT.COM`).
2. **Native NextZXOS**: Standalone executable (`SE.NEX`) and dot command
   (`.se` / `SE`).

### 1. Host Emulator Dependencies (ZEsarUX)

The bundled ZEsarUX emulator (`$TOOLS_DIR/zesarux/zesarux`) requires the
SDL 1.2 compatibility runtime and audio libraries on the host Linux system.

Install the prerequisites on your host distribution:

* **Ubuntu / Debian / Linux Mint**:
  ```bash
  sudo apt update
  sudo apt install -y libsdl1.2debian libsndfile1 libpulse0
  ```

* **Fedora / RHEL**:
  ```bash
  sudo dnf install -y sdl12-compat libsndfile pulseaudio-libs
  ```

* **Arch Linux / Manjaro**:
  ```bash
  sudo pacman -S --needed sdl12-compat libsndfile libpulse
  ```

### 2. Running Next CP/M in ZEsarUX (Interactive Emulation)

From the project repository directory:

```bash
# Launch ZEsarUX in TBBlue Next mode with DivMMC and the MMC card image:
$TOOLS_DIR/zesarux/zesarux --machine TBBlue --enable-mmc --enable-divmmc \
    --mmc-file disks/tbblue.mmc
```

*(Note: append `--vo curses` to run inside a text terminal window).*

Once the emulator boots:
1. At the Sinclair BASIC prompt, type `.cpm` and press <kbd>Enter</kbd>.
2. The 80-column ANSI terminal initializes at the CP/M `A>` prompt.
3. Launch the editor (`SE_NEXT.COM` is pre-installed on `disks/tbblue.mmc`):
   ```text
   A>SE_NEXT
   ```
4. Use the splash screen and editor controls as specified in
   [docs/UI_UX_DESIGN.md](docs/UI_UX_DESIGN.md).

### 3. Automated Demo Harness

To run automated headless verification and demos via ZEsarUX:

```bash
# Demo NextCPM variant:
PATH="../../tools/zesarux:$PATH" python3 tools/demo_next.py --target cpm

# Demo all Next variants (SE.NEX, .se, and SE_NEXT.COM):
PATH="../../tools/zesarux:$PATH" python3 tools/demo_next.py --target all
```

### 4. Running on Real ZX Spectrum Next Hardware

1. Copy `SE_NEXT.COM` (optionally renamed to `SE.COM`) to your SD card.
2. Boot your ZX Spectrum Next into NextZXOS.
3. Run `.cpm` to start NextCPM.
4. Execute `SE_NEXT` at the `A>` prompt.

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
│   ├── UI_UX_DESIGN.md     # Authoritative UI/UX & keybinding specification
│   └── KEYBINDINGS.md      # Complete editor and splash key reference
└── tests/                  # Automated integration and regression suites
    ├── README.md           # Test suite documentation
    ├── test_sanity.py      # Fast integration sanity test
    └── test_editor_headless.py # Full PTY emulator conformity suite
```
