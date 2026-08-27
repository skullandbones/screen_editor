# SE.COM Test Suite

This directory contains host-agnostic automated tests and test fixtures for the **SE.COM** screen editor.

---

## Test Files

1. **`test_editor_headless.py`**:
   - Automated integration test runner.
   - Spins up the RC2014 RomWBW emulation environment via pseudo-terminal (`openpty`), boots CP/M, launches `SE.COM`, verifies VT100 screen initialization and status line rendering, and tests clean exit on `Ctrl+Q`.

2. **`sample_large.asm`**:
   - Sample Z80 assembly source file used to verify tab alignment, line editing, and 512KB far memory paging.

---

## Running the Tests

From the `src/screen_editor` directory:
```bash
python3 tests/test_editor_headless.py
```
