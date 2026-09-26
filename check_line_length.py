#!/usr/bin/env python3
"""
check_line_length.py - Enforce 80-character line length limit.

Validates that text files and git diffs adhere strictly to the project's
maximum line length constraint (<= 80 characters).

Usage:
  python3 check_line_length.py             # Check git diff & modified files
  python3 check_line_length.py --diff      # Check added lines in git diff
  python3 check_line_length.py --staged    # Check added lines in staged diff
  python3 check_line_length.py --all       # Audit all tracked repository files
  python3 check_line_length.py <files...>  # Check specific files
"""

import argparse
import os
import subprocess
import sys

DEFAULT_MAX_LEN = 80

BINARY_OR_IGNORED_EXTENSIONS = {
    ".img", ".rom", ".com", ".prl", ".ovl", ".bin", ".o", ".obj",
    ".map", ".sym", ".lst", ".lis", ".def", ".png", ".jpg", ".ico",
    ".json"
}

IGNORED_DIRECTORIES = {
    ".git", ".venv", "venv", ".build", "__pycache__", "build", "scratch",
    "tools", ".githooks"
}


def is_ignored_file(filepath: str) -> bool:
    norm = filepath.replace("\\", "/")
    parts = norm.split("/")
    for part in parts:
        if part in IGNORED_DIRECTORIES:
            return True
    _, ext = os.path.splitext(norm)
    if ext.lower() in BINARY_OR_IGNORED_EXTENSIONS:
        return True
    return False


def is_binary_content(raw_bytes: bytes) -> bool:
    return b"\x00" in raw_bytes[:1024]


def parse_diff_violations(diff_text: str, max_len: int = DEFAULT_MAX_LEN):
    violations = []
    current_file = None
    line_num = 0

    for raw_line in diff_text.splitlines():
        if raw_line.startswith("+++ b/"):
            current_file = raw_line[6:]
            line_num = 0
            continue
        if raw_line.startswith("@@"):
            # Format: @@ -start,count +start,count @@
            parts = raw_line.split()
            if len(parts) >= 3 and parts[2].startswith("+"):
                try:
                    num_str = parts[2][1:].split(",")[0]
                    line_num = int(num_str) - 1
                except ValueError:
                    line_num = 0
            continue

        if raw_line.startswith("+") and not raw_line.startswith("+++"):
            line_num += 1
            if current_file and is_ignored_file(current_file):
                continue
            content = raw_line[1:]
            if len(content) > max_len:
                violations.append((
                    current_file or "diff",
                    line_num,
                    len(content),
                    content
                ))
        elif not raw_line.startswith("-"):
            line_num += 1

    return violations


def check_file(filepath: str, max_len: int = DEFAULT_MAX_LEN):
    if is_ignored_file(filepath) or not os.path.isfile(filepath):
        return []

    try:
        with open(filepath, "rb") as f:
            raw_data = f.read()
    except Exception as e:
        print(f"[-] Warning: Unable to read {filepath}: {e}", file=sys.stderr)
        return []

    if is_binary_content(raw_data):
        return []

    try:
        text = raw_data.decode("utf-8")
    except UnicodeDecodeError:
        text = raw_data.decode("latin1", errors="replace")

    violations = []
    for idx, line in enumerate(text.splitlines(), start=1):
        clean_line = line.rstrip("\r\n")
        if len(clean_line) > max_len:
            violations.append((filepath, idx, len(clean_line), clean_line))

    return violations


def get_tracked_files():
    try:
        out = subprocess.check_output(
            ["git", "ls-files"], text=True, stderr=subprocess.DEVNULL
        )
        return [f.strip() for f in out.splitlines() if f.strip()]
    except Exception:
        return []


def get_git_diff(cached: bool = False, commit_ref: str = None):
    cmd = ["git", "diff", "--no-color", "-U0"]
    if cached:
        cmd.append("--cached")
    elif commit_ref:
        cmd.append(commit_ref)
    try:
        return subprocess.check_output(
            cmd, text=True, stderr=subprocess.DEVNULL
        )
    except Exception:
        return ""


def main():
    parser = argparse.ArgumentParser(
        description="Verify <= 80 character line lengths in git and files."
    )
    parser.add_argument(
        "files", nargs="*", help="Specific files to audit"
    )
    parser.add_argument(
        "--diff", action="store_true",
        help="Check unstaged git diff added lines"
    )
    parser.add_argument(
        "--staged", "--cached", dest="staged", action="store_true",
        help="Check staged git diff added lines"
    )
    parser.add_argument(
        "--commit", type=str, default=None,
        help="Check diff of a specific commit or range (e.g. HEAD~1..HEAD)"
    )
    parser.add_argument(
        "--all", action="store_true",
        help="Audit all tracked files in the git repository"
    )
    parser.add_argument(
        "--max-len", type=int, default=DEFAULT_MAX_LEN,
        help=f"Maximum permitted line length (default: {DEFAULT_MAX_LEN})"
    )

    args = parser.parse_args()
    max_len = args.max_len
    all_violations = []

    if args.files:
        # Check explicit files
        for f in args.files:
            all_violations.extend(check_file(f, max_len=max_len))
    elif args.all:
        # Check all tracked files
        tracked = get_tracked_files()
        if not tracked:
            print("[-] No tracked git files found.", file=sys.stderr)
            return 1
        for f in tracked:
            all_violations.extend(check_file(f, max_len=max_len))
    elif args.staged:
        diff_text = get_git_diff(cached=True)
        all_violations.extend(parse_diff_violations(diff_text, max_len))
    elif args.diff:
        diff_text = get_git_diff(cached=False)
        all_violations.extend(parse_diff_violations(diff_text, max_len))
    elif args.commit:
        diff_text = get_git_diff(commit_ref=args.commit)
        all_violations.extend(parse_diff_violations(diff_text, max_len))
    else:
        # Default mode: check unstaged + staged diffs
        unstaged_diff = get_git_diff(cached=False)
        staged_diff = get_git_diff(cached=True)
        diff_violations = parse_diff_violations(unstaged_diff, max_len)
        diff_violations.extend(parse_diff_violations(staged_diff, max_len))

        # If working tree is clean, inspect latest commit
        if not unstaged_diff.strip() and not staged_diff.strip():
            head_diff = get_git_diff(commit_ref="HEAD~1..HEAD")
            if head_diff.strip():
                diff_violations.extend(
                    parse_diff_violations(head_diff, max_len)
                )

        all_violations.extend(diff_violations)

    if all_violations:
        print(f"[-] Line length check FAILED: {len(all_violations)} "
              f"violation(s) found (max allowed: {max_len} chars):",
              file=sys.stderr)
        for fpath, lnum, length, line in all_violations:
            print(f"  {fpath}:{lnum} ({length} chars):", file=sys.stderr)
            print(f"    {line}", file=sys.stderr)
        return 1

    print(f"[+] Line length check PASSED: all inspected lines <= {max_len} "
          f"characters.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
