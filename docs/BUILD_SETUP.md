# SE.COM Build Environment & Developer Setup Guide

This guide describes how to configure the host build environment, compile
**`SE.COM`** and its modular plugins, execute automated verification suites,
and adhere to repository development standards.

> **Setting Up From Scratch?** If you are configuring a clean host machine from
> zero, see the step-by-step [`REPLICATION_GUIDE.md`](REPLICATION_GUIDE.md) for
> package installation commands, git repository cloning, and toolchain builds.

---

## 1. System Requirements & Toolchain Prerequisites

Development and testing of `SE.COM` require a Linux host system (Ubuntu,
Debian, Fedora, or equivalent) with the following tools:

### 1.1 Toolchain Components

1. **Z80 Assembler (`z88dk-z80asm`)**:
   - The primary macro assembler used to build `SE.COM` and assembly plugins.
   - Bundled or located in `tools/z88dk/bin/z88dk-z80asm`.
2. **CP/M Disk Utilities (`cpmtools`)**:
   - `cpmcp` and `cpmrm` configured with RomWBW disk definitions.
   - Bundled in `tools/romwbw_src/Tools/Linux/` with disk definitions at
     `tools/romwbw_src/Tools/cpmtools/diskdefs`.
3. **Hardware Emulator (`rc2014`)**:
   - Native Linux Z80 RC2014 emulator supporting banked memory and RomWBW
     HBIOS firmware calls (`RST 08H`).
   - Located in `tools/rc2014_emu/rc2014`.
4. **RomWBW Firmware & Golden Disk Images**:
   - ROM image: `tools/romwbw_src/Binary/RC2014_std.rom`.
   - Master disk image: `tools/romwbw_src/Binary/hd1k_combo.img`.
5. **Python 3 Runtime (3.8+)**:
   - Python 3 standard library with `pty`, `select`, `subprocess`, and `time`.
   - Required for test automation, TPA checks, and line length audits.
   - **Important Constraint**: Running one-liner scripts via `python -c` or
     `python3 -c` is strictly prohibited by project guidelines. Always create
     and invoke Python script files.

### 1.2 Verified Tool & Component Versions

The environment has been verified with the following tool versions:

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

## 2. Directory Structure & Environment Configuration

The standard workspace layout maps tools relative to repository root:

```text
experiment/
├── tools/
│   ├── z88dk/bin/z88dk-z80asm      # Z80 Macro Assembler
│   ├── rc2014_emu/rc2014           # RC2014 Hardware Emulator
│   └── romwbw_src/                 # Firmware, cpmtools, and golden images
└── src/
    └── se.com_dev/
        └── agy1_dev/               # Development worktree
            ├── Makefile            # Main project build rules
            ├── src/se.asm          # Primary SE.COM assembly source
            ├── plugins/            # Modular plugin sources & build script
            ├── tests/              # Test suites & test harnesses
            └── docs/               # Technical specifications & guides
```

### 2.1 Makefile Environment Variables

The `Makefile` automatically discovers tool paths relative to `WORKSPACE_ROOT`.
You may also set these variables explicitly in your shell:

```bash
export TOOLS_DIR=/path/to/experiment/tools
export DISKDEFS=$TOOLS_DIR/romwbw_src/Tools/cpmtools/diskdefs
```

---

## 3. Compilation & Build Targets

All primary build tasks are managed through `make`:

### 3.1 Assembling SE.COM

To assemble `SE.COM` from `src/se.asm`:

```bash
make -B SE.COM
```

Flags passed to `z88dk-z80asm`:
* `-b`: Generate raw CP/M binary (.COM file).
* `-m`: Generate symbol map file (`SE.map`).
* `-s`: Generate symbol table (`SE.sym`).
* `-o=SE.COM`: Output binary name.

### 3.2 Building Modular Plugins

To compile all 10 plugin overlays and Far RAM modules:

```bash
make plugins
```

This target invokes:
1. `python3 plugins/build_plugins.py` to assemble 4K, 8K, 16K, and 32K modules:
   * `ROT13.PRL`, `WORDCNT.OVL`, `HELP.OVL`, `HIBERN.OVL` (4K / TPA slot)
   * `BEAUTIFY.PRL`, `PLUGIN.PRL`, `MIDPLUG.PRL` (8K Far RAM)
   * `HALFPLUG.PRL` (16K Far RAM)
   * `BIGPLUG.PRL` (32K Far RAM)
2. `make -C plugins/fat all` to compile `FATFS.PRL` (FAT32 SD driver).

### 3.3 Disk Image Initialization & Binary Injection

To create an isolated working disk image and populate it with binaries:

```bash
make image
```

* Clones `tools/romwbw_src/Binary/hd1k_combo.img` into `disks/hd1k_combo.img`.
* Uses `cpmcp` with format `wbw_hd1k_0` to inject `SE.COM`, plugins, and
  configuration files into User 0 and User 3.

---

## 4. Quality Assurance & Static Checks

Before running functional tests, run the repository verification checks:

### 4.1 TPA Memory Footprint Check (`make check-tpa`)

Validates that `SE.COM` fits safely below the BDOS entry point (`0xD800`):

```bash
make check-tpa
```

* Confirms Code + Data range (`0x0100..0xBC00`).
* Confirms BSS allocations (`0xBC00..0xD000`).
* Asserts positive headroom margin ($\ge +2,048$ bytes).
* Verifies all plugin binaries fit their designated TPA and Far RAM slots.

### 4.2 80-Column Line Length Enforcement (`make check-lines`)

Enforces the strict $\le 80$ characters per line limit across all source code,
test scripts, and markdown documentation:

```bash
make check-lines
```

Underlying script options:
* `python3 check_line_length.py`: Audits git diff and modified files.
* `python3 check_line_length.py --diff`: Audits unstaged git diff lines.
* `python3 check_line_length.py --staged`: Audits staged git diff lines.
* `python3 check_line_length.py <file>`: Audits a specific file.

---

## 5. Test Automation Suites

The test suite runs headlessly against the `rc2014` emulator over pseudo-TTYS
(`pty`), simulating realistic user keystrokes and verifying terminal output.

### 5.1 Full Headless Regression Suite

Runs all 74 conformity regression steps covering editing, scrolling, search,
modal dialogs, configuration, user areas, and plugins:

```bash
python3 tests/test_editor_headless.py
```

### 5.2 Isolated Step Test Harness (`tests/isolate_step.py`)

When debugging a specific step, use `isolate_step.py` to boot a clean emulator
instance and execute only that step in seconds:

```bash
python3 tests/isolate_step.py 65        # Run Step 65 (About Screen)
python3 tests/isolate_step.py 66        # Run Step 66 (Block Insert File)
python3 tests/isolate_step.py 68        # Run Step 68 (Save Progress Indicator)
python3 tests/isolate_step.py 70        # Run Step 70 (Directory Filter)
python3 tests/isolate_step.py all       # Run all registered isolated steps
```

### 5.3 Block Modal Test Suite (`tests/test_block_modal.py`)

Validates the complete visual block lifecycle and modal dialogs (Tests 1-10):

```bash
python3 tests/test_block_modal.py
```

Verifies:
* Dynamic character and multi-line selection.
* `Enter` in editor confirming/solidifying block.
* `Ctrl-B` toggle behavior (start selection or clear active block).
* Centered 50x7 Block Operations Modal (`Ctrl-K`).
* Safe `ESC` dismissal preserving active block selection.
* Modal operations: Solidify (`Enter`), Clear (`^B`), Delete (`^D`).

---

## 6. Git Workflow & Commit Guidelines

The repository enforces strict commit standards via `.githooks/commit-msg`:

1. **Branch Policy**: Direct commits to `master` are prohibited. All development
   must occur on feature branches (e.g. `agy1_dev_branch`) and be merged into
   `master`.
2. **Subject Header**:
   - Maximum 72 characters.
   - Conventional format: `<type>(<scope>): <summary>`.
3. **Body Structure**:
   - Line 2 must be blank.
   - Must contain a non-empty `Why:` section explaining rationale.
   - Must contain a non-empty `How:` section listing concrete changes.
   - All body lines must be $\le 80$ characters.
   - Bullet lists must be compact (single-spaced).
