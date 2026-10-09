#!/usr/bin/env python3
"""
Test runner for native Python SE editor port.
Executes all unit and integration test suites under ports/python/tests/.
Strictly conforms to Rule 9 logging standards and <= 80 characters line length.
"""

import os
import subprocess
import sys
import time


def run_test_module(
    step_num: int, label: str, module_path: str, repo_root: str
):
    """Run a Python test module and report results according to Rule 9."""
    print(f"[*] Step {step_num}: Running {label}...", flush=True)

    py_root = os.path.join(repo_root, "ports", "python")
    plugins_root = os.path.join(py_root, "plugins")

    env = os.environ.copy()
    py_path = env.get("PYTHONPATH", "")
    env["PYTHONPATH"] = f"{py_root}:{plugins_root}:{py_path}"

    target = os.path.join(repo_root, module_path)

    proc = subprocess.run(
        [sys.executable, target],
        capture_output=True,
        text=True,
        env=env,
    )

    if proc.returncode != 0:
        err_tail = (proc.stdout + proc.stderr)[-300:]
        print(
            f"[-] Step {step_num}: {label} failed with code "
            f"{proc.returncode}. Buffer: {repr(err_tail)}",
            flush=True,
        )
        sys.exit(proc.returncode)

    print(f"[+] Step {step_num}: {label} PASSED.", flush=True)


def main():
    start_time = time.time()
    script_dir = os.path.dirname(os.path.abspath(__file__))
    repo_root = os.path.dirname(script_dir)

    print("==================================================", flush=True)
    print("SE Python Native Port Test Suite", flush=True)
    print("==================================================", flush=True)

    test_suites = [
        (
            "terminal and escape sequence tests",
            "ports/python/tests/test_terminal.py",
        ),
        (
            "SE.CFG configuration tests",
            "ports/python/tests/test_config.py",
        ),
        (
            "document buffer and paging tests",
            "ports/python/tests/test_buffer.py",
        ),
        (
            "plugin subsystem tests",
            "ports/python/tests/test_plugin.py",
        ),
        (
            "headless PTY integration tests",
            "ports/python/tests/test_headless.py",
        ),
    ]

    for step_idx, (label, mod_path) in enumerate(test_suites, 1):
        run_test_module(step_idx, label, mod_path, repo_root)

    elapsed = time.time() - start_time
    print(
        f"[+] All Python Port tests PASSED in {elapsed:.2f}s!",
        flush=True,
    )


if __name__ == "__main__":
    main()
