# Replicating the SE.COM Antigravity Build Environment from Scratch

This guide provides step-by-step instructions to replicate the complete
**`SE.COM`** development, compilation, emulation, and testing environment on a
fresh Linux host (Debian, Ubuntu, Linux Mint, or compatible distribution).

Following these steps allows any developer or AI agent to construct the exact
toolchains, firmware images, emulator, and multi-worktree environment used by
the Antigravity agent system.

---

## 1. Host System Package Prerequisites

Update your package index and install the native build tools, compiler
prerequisites, Python 3 environment, and CP/M disk utilities:

```bash
sudo apt-get update
sudo apt-get install -y \
    build-essential \
    git \
    curl \
    unzip \
    pkg-config \
    bison \
    flex \
    libxml2-dev \
    zlib1g-dev \
    cpmtools \
    python3 \
    python3-venv \
    python3-pip
```

---

## 2. Verified Tool & Component Versions

The complete development stack is verified against these tool versions:

| Component | Version / Commit | Purpose / Origin |
| :--- | :--- | :--- |
| **Antigravity** | `2.19.1` | Agentic AI coding environment |
| **`z88dk-z80asm`** | `v2.4+` (`b9b1d45`) | Z80 Macro Assembler (z88dk/z88dk) |
| **`rc2014` Emulator** | Master (`b145b90`) | RC2014 hardware emulator |
| **RomWBW** | `v3.6.0` (2026-03-28) | RC2014 ROM and master disk images |
| **`cpmtools`** | RomWBW bundle | `cpmcp` / `cpmrm` disk utilities |
| **`diskdefs`** | `wbw_hd1k_0` format | RomWBW 512B/sector disk geometry |
| **Python** | `3.12.3` | Test harness & automation runner |
| **`pyserial`** | `3.5` | Serial terminal emulation library |
| **`xmodem`** | `0.5.0` | Hardware binary transfer protocol |
| **GCC** | `13.3.0` | C compiler for emulator & plugins |
| **GNU Make** | `4.3` | Build orchestration engine |

---

## 3. Directory Layout & Repository Setup

The project uses a structured workspace where toolchains reside in `tools/` and
isolated development branches reside in `src/se.com_dev/`:

```bash
# 1. Create main project root
mkdir -p ~/experiment
cd ~/experiment

# 2. Create tools directory
mkdir -p tools
```

### 2.1 Cloning the Screen Editor Repository

Clone the master repository into `src/screen_editor`:

```bash
mkdir -p src
git clone <git-repo-url> src/screen_editor
cd src/screen_editor
```

### 2.2 Configuring Git Hooks & Agent Worktrees

The Antigravity system uses git worktrees to keep feature development isolated
from the `master` branch while sharing git objects:

```bash
# Configure conventional commit message validation hook
git config core.hooksPath .githooks

# Create development worktree for feature branch agy1_dev_branch
git worktree add ../se.com_dev/agy1_dev -b agy1_dev_branch

# Configure commit hook inside the worktree
cd ../se.com_dev/agy1_dev
git config core.hooksPath .githooks
```

---

## 4. Bootstrapping Toolchains in `tools/`

Return to `~/experiment` to set up the four core external tool components:

```bash
cd ~/experiment/tools
```

### 4.1 Z88DK (Z80 Macro Assembler: `z88dk-z80asm`)

`SE.COM` relies on `z88dk-z80asm` for assembly, symbol map generation, and
binary generation.

```bash
# Clone the official z88dk repository
git clone --recursive https://github.com/z88dk/z88dk.git z88dk
cd z88dk

# Compile z88dk toolchain binaries (builds z88dk-z80asm in bin/)
./build.sh

cd ~/experiment/tools
```

Create the environment helper script `tools/source_z88dk`:

```bash
cat << 'EOF' > ~/experiment/tools/source_z88dk
EXP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PATH="$EXP_ROOT/tools/z88dk/bin:$PATH"
export ZCCCFG="$EXP_ROOT/tools/z88dk/lib/config"
EOF
```

### 4.2 RC2014 Hardware Emulator (`rc2014`)

The automated regression test suite executes against Alan Cox's multi-system
RC2014 emulator with RomWBW HBIOS bank-switching support:

```bash
# Clone the RC2014 emulator repository
git clone https://github.com/etchedpixels/RC2014.git rc2014_emu
cd rc2014_emu

# Compile the rc2014 executable
make rc2014

cd ~/experiment/tools
```

### 4.3 RomWBW Firmware & Master Disk Image (`romwbw_src`)

Obtain the official RomWBW release package (**v3.6.0 or later**, strictly
required for `SE.COM` runtime and banking support) containing standard RC2014
ROM binaries, master disk images, and disk definitions:

```bash
mkdir -p romwbw_src
cd romwbw_src

# Download RomWBW distribution package (v3.6.0 or later)
curl -L -o romwbw.zip \
  https://github.com/wwarthen/RomWBW/releases/latest/download/RomWBW.zip

# Unpack distribution
unzip -q romwbw.zip

# Ensure essential files are in place:
# - Binary/RC2014_std.rom
# - Binary/hd1k_combo.img
# - Tools/cpmtools/diskdefs
# - Tools/Linux/cpmcp, cpmrm
chmod +x Tools/Linux/cpm* 2>/dev/null || true

cd ~/experiment/tools
```

### 4.4 CP/M Disk Definitions Setup

Ensure the RomWBW disk definition for `wbw_hd1k_0` is accessible:

```bash
mkdir -p cpmtools
cp romwbw_src/Tools/cpmtools/diskdefs cpmtools/diskdefs
export DISKDEFS="$HOME/experiment/tools/cpmtools/diskdefs"
```

---

## 5. Python Virtual Environment Setup

Set up a Python 3 virtual environment for serial interaction and test harness
support:

```bash
cd ~/experiment/src/se.com_dev/agy1_dev

python3 -m venv .venv
source .venv/bin/activate
pip install pyserial xmodem
```

---

## 6. Verification Checklist: Testing the Fresh Environment

Execute these sanity checks in sequence to verify that every component is
correctly installed and functional:

### Step 1: Verify Assembler
```bash
source ~/experiment/tools/source_z88dk
z88dk-z80asm -h
```
*Expected*: Displays `z88dk-z80asm` version and usage flags.

### Step 2: Assemble SE.COM
```bash
cd ~/experiment/src/se.com_dev/agy1_dev
make -B SE.COM
```
*Expected*: Assembles `src/se.asm` into `SE.COM` (47,872 bytes).

### Step 3: Check Memory Headroom (TPA)
```bash
make check-tpa
```
*Expected*: Outputs `VERDICT: [ PASS ] Headroom: +2,048 bytes`.

### Step 4: Check 80-Column Line Length
```bash
make check-lines
```
*Expected*: Outputs `[+] Line length check PASSED`.

### Step 5: Build Plugins
```bash
make plugins
```
*Expected*: Assembles all 10 plugin overlays and Far RAM binaries.

### Step 6: Initialize Test Disk Image
```bash
make image
```
*Expected*: Creates `disks/hd1k_combo.img` and copies `SE.COM` and plugins.

### Step 7: Run an Isolated Emulator Test
```bash
python3 tests/isolate_step.py 65
```
*Expected*: Boots the RC2014 emulator, runs the About Screen test, and
reports `[+] STEP 65 PASSED`.

### Step 8: Run Block Modal Tests
```bash
python3 tests/test_block_modal.py
```
*Expected*: Tests 1-10 pass cleanly (`[+] All Block Modal tests PASSED`).

### Step 9: Run Full Regression Suite
```bash
python3 tests/test_editor_headless.py
```
*Expected*: All 74 automated emulator tests pass cleanly.

---

## 7. Physical Hardware Deployment (Optional)

If running on real hardware (RC2014, SC126, SC130, SC131):

1. **Connect Serial Console**:
   - Speed / Framing: `115200 bps 8N1`
   - Flow Control: Full-duplex RTR/CTS hardware flow control via RTS/CTS pins
   - Emulation: `VT100` / `ANSI` (e.g. Minicom:
     `minicom -D /dev/ttyUSB0 -b 115200`).
2. **Transfer Binary**:
   - In CP/M: `A>XMODEM R SE.COM`
   - In Minicom: Send file via XMODEM protocol.
3. **Launch**:
   - `A>SE`
