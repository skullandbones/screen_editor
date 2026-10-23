#!/usr/bin/env python3
"""Run all 16 SEC component validation test suites."""

import os
import subprocess
import sys
import time

TEST_FILES = [
    "tests/test_sec_about_screen.py",
    "tests/test_sec_bdos_errors.py",
    "tests/test_sec_browser_layout.py",
    "tests/test_sec_browser_status.py",
    "tests/test_sec_bugs_2_8_52_to_57.py",
    "tests/test_sec_cli_arg.py",
    "tests/test_sec_config_layout.py",
    "tests/test_sec_dir_pagination.py",
    "tests/test_sec_goto_line.py",
    "tests/test_sec_help_screen.py",
    "tests/test_sec_help_spacing.py",
    "tests/test_sec_save_changes_prompt.py",
    "tests/test_sec_splash_metadata.py",
    "tests/test_sec_tpa_headroom.py",
    "tests/test_sec_untitled_close.py",
    "tests/test_sec_utf8_ascii.py",
]


def main():
    repo_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    results = {}
    total_start = time.time()

    for rel_path in TEST_FILES:
        full_path = os.path.join(repo_root, rel_path)
        print(f"[*] Running {rel_path}...", flush=True)
        t0 = time.time()
        res = subprocess.run([sys.executable, full_path], cwd=repo_root)
        dt = time.time() - t0
        status = "PASS" if res.returncode == 0 else "FAIL"
        results[rel_path] = (status, dt)
        print(f"[{status}] {rel_path} in {dt:.2f}s\n", flush=True)

    print("=" * 60, flush=True)
    print("SEC Component Tests Summary:", flush=True)
    print("=" * 60, flush=True)
    all_passed = True
    for t, (status, dt) in results.items():
        print(f"  {status:4s} | {dt:6.2f}s | {t}", flush=True)
        if status != "PASS":
            all_passed = False
    print("-" * 60, flush=True)
    total_dt = time.time() - total_start
    print(f"Total time: {total_dt:.2f}s", flush=True)
    return 0 if all_passed else 1


if __name__ == "__main__":
    sys.exit(main())
