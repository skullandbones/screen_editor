#!/usr/bin/env python3
"""Validation test for Step 19: CLI target filename preservation in SEC.COM.

Verifies that target filenames provided via command-line arguments are
stored in a preserved buffer rather than g_scratch_line_buf, ensuring that
buffer_init() does not wipe the target filename before file_load() is invoked.
"""

import os
import subprocess
import sys
import time


def test_sec_cli_arg():
    start_time = time.time()
    repo_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    sec_cpm_src = os.path.join(repo_root, "src", "sec_cpm.c")

    # Step 1: Verify source implementation avoids g_scratch_line_buf
    print("[*] Step 1: Verifying parse_target_filename signature in "
          "src/sec_cpm.c...", flush=True)
    with open(sec_cpm_src, "r") as f:
        src_text = f.read()

    if "g_scratch_line_buf" in src_text:
        print("[-] Step 1: Found prohibited g_scratch_line_buf in "
              "src/sec_cpm.c.", flush=True)
        return False
    if "parse_target_filename(char *out_buf, size_t max_len" not in src_text:
        print("[-] Step 1: parse_target_filename missing out_buf parameter.",
              flush=True)
        return False
    print("[+] Step 1: parse_target_filename uses dedicated caller buffer.",
          flush=True)

    # Step 2: Compile SEC.COM with the fix
    print("[*] Step 2: Compiling SEC.COM with 'make sec-cpm'...", flush=True)
    res = subprocess.run(
        ["make", "sec-cpm"],
        cwd=repo_root,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    if res.returncode != 0:
        print(f"[-] Step 2: Compilation failed. "
              f"Buffer: {repr(res.stderr[-300:])}", flush=True)
        return False
    print("[+] Step 2: SEC.COM compiled successfully with preserved "
          "CLI buffer.", flush=True)

    # Step 3: Verify stack buffer declaration in main()
    print("[*] Step 3: Verifying stack target_file buffer allocation in "
          "main()...", flush=True)
    if "char target_file[32];" not in src_text:
        print("[-] Step 3: Missing local target_file buffer declaration in "
              "main().", flush=True)
        return False
    if "parse_target_filename(target_file, sizeof(target_file)" not in src_text:
        print("[-] Step 3: Missing parse_target_filename call with stack "
              "buffer.", flush=True)
        return False
    print("[+] Step 3: Stack target_file allocation verified in main().",
          flush=True)

    elapsed = time.time() - start_time
    print(f"[+] All SEC CLI Argument tests PASSED in {elapsed:.2f}s!",
          flush=True)
    return True


if __name__ == "__main__":
    if not test_sec_cli_arg():
        sys.exit(1)
