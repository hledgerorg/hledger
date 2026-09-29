#!/usr/bin/env python3
"""Regenerate expected stdout in shelltestrunner v3 .test files.

For each test in each given .test file:

1. Parse the test (input, command, expected stdout, exit marker).
2. Run the command (with cwd set to the file's directory, mimicking
   `shelltest --execdir`) and capture actual stdout + exit code.
3. If the actual exit code matches the test's expected exit code AND the
   actual stdout differs from the expected stdout *only in whitespace*,
   replace the expected stdout with actual.

The whitespace-only check (`--whitespace-only`, the default) is a safety
net: it lets you bulk-regenerate after a layout/alignment change without
clobbering tests where the actual content has drifted in some other way.
Pass `--all` to replace expected with actual whenever the run succeeded
with the expected exit code (use after content changes you've audited).

Skipped (left untouched):
- Tests with stderr expectations (`>2 …` or `>>>2 …`).
- Tests with no exit marker (malformed or v2-format).
- Tests whose actual exit code doesn't match expected.
- Tests whose actual stdout differs in non-whitespace ways (in
  whitespace-only mode).

Usage:
  tools/regen-shelltests.py [--all] FILE.test [FILE.test ...]

Workflow (typical hledger usage):
  1. just functest --hide                # see how many fail
  2. shelltest --execdir --exclude=/_ hledger/test/ … 2>&1 \\
       | grep "Failed\\]" | sed 's/^:\\(.*\\):[0-9]*: \\[Failed\\]$/\\1/' \\
       | sort -u > /tmp/failing.txt
  3. cat /tmp/failing.txt | xargs tools/regen-shelltests.py
  4. just functest --hide                # confirm
  5. git diff and review.
"""
import argparse
import os
import re
import subprocess
import sys
from pathlib import Path


def find_hledger():
    """Locate the project's just-built hledger binary."""
    return subprocess.check_output(
        ["stack", "exec", "--", "which", "hledger"], text=True
    ).strip()


def squash_ws(s):
    return re.sub(r'\s+', '', s)


def regen_file(path, hledger_bin, env, replace_all):
    workdir = path.parent  # mimic shelltest --execdir
    text = path.read_text()
    if not text.endswith('\n'):
        text += '\n'
    src = text.split('\n')
    if src[-1] == '':
        src.pop()
    out = []
    i = 0
    n_total = 0
    n_changed = 0
    n_skipped = 0

    # Implicit shared input: shelltest treats lines from file start up to the
    # first `$ command` (excluding any `<` block, but including comments and
    # blank lines) as the stdin used when no later `<` overrides it.
    pre_dollar = []
    for ln in src:
        if (ln.startswith('$') or ln.startswith('$$$')
                or ln == '<' or ln.startswith('< ') or ln.startswith('<<<')):
            break
        pre_dollar.append(ln)
    current_input = pre_dollar if pre_dollar else None

    while i < len(src):
        ln = src[i]

        # Begin new input block (v3 `<` form)
        if ln == '<' or (ln.startswith('< ') and not ln.startswith('<<<')):
            input_start = i
            new_input = []
            if ln.startswith('< '):
                new_input.append(ln[2:])
            i += 1
            while i < len(src):
                ln2 = src[i]
                if (ln2.startswith('$') or ln2.startswith('$$$')
                        or ln2 == '<' or ln2.startswith('< ')):
                    break
                new_input.append(ln2)
                i += 1
            current_input = new_input
            out.extend(src[input_start:i])
            continue

        # v2 `<<<` input: not handled; pass through
        if ln.startswith('<<<'):
            out.append(ln)
            i += 1
            continue

        # Command
        if ln.startswith('$ ') or ln == '$' or ln.startswith('$$$'):
            cmd_idx = i
            cmd_str = (ln[3:] if ln.startswith('$$$') else ln[1:]).lstrip()
            i += 1
            stdout_lines = []
            has_stderr = False
            exit_line = None

            while i < len(src):
                ln2 = src[i]
                if re.match(r'^>=', ln2) or ln2.startswith('>>>='):
                    exit_line = ln2
                    i += 1
                    break
                if re.match(r'^>2(?=[\s/]|$)', ln2) or ln2.startswith('>>>2'):
                    has_stderr = True
                    break
                # Next test begins without an intervening exit marker
                if (ln2 == '<' or ln2.startswith('< ') or ln2.startswith('<<<')
                        or ln2.startswith('$') or ln2.startswith('$$$')):
                    break
                stdout_lines.append(ln2)
                i += 1

            n_total += 1

            if has_stderr or exit_line is None:
                # Pass through verbatim. Consume any trailing >2/>=/>>>=
                # lines that belong to this block.
                end_i = i
                while end_i < len(src):
                    ln3 = src[end_i]
                    if (re.match(r'^>2(?=[\s/]|$)', ln3) or ln3.startswith('>>>2')
                            or re.match(r'^>=', ln3) or ln3.startswith('>>>=')):
                        end_i += 1
                        continue
                    break
                i = end_i
                out.extend(src[cmd_idx:i])
                n_skipped += 1
                continue

            m = re.match(r'^>=\s*(-?\d*)', exit_line)
            expected_exit = int(m.group(1)) if (m and m.group(1)) else 0

            # Rewrite a leading `hledger` to the absolute path of the project's
            # built binary, so we always exercise the freshly-built code.
            cmd_full = re.sub(r'^hledger\b', hledger_bin, cmd_str)
            stdin_str = '\n'.join(current_input or [])
            if stdin_str and not stdin_str.endswith('\n'):
                stdin_str += '\n'

            try:
                result = subprocess.run(
                    cmd_full, shell=True, input=stdin_str,
                    capture_output=True, text=True, timeout=30,
                    env=env, cwd=str(workdir),
                )
            except subprocess.TimeoutExpired:
                print(f"  TIMEOUT in {path}: {cmd_str!r}", file=sys.stderr)
                out.extend(src[cmd_idx:i])
                n_skipped += 1
                continue

            if result.returncode != expected_exit:
                print(f"  EXIT {result.returncode}!={expected_exit} in {path}: {cmd_str!r}",
                      file=sys.stderr)
                out.extend(src[cmd_idx:i])
                n_skipped += 1
                continue

            actual_lines = result.stdout.split('\n')
            if actual_lines and actual_lines[-1] == '':
                actual_lines.pop()

            # Whitespace-only safety net: only overwrite when the diff is
            # purely whitespace. Anything else (added/removed/changed
            # non-whitespace content) is left for human review.
            whitespace_only = (
                len(actual_lines) == len(stdout_lines)
                and all(squash_ws(a) == squash_ws(e)
                        for a, e in zip(actual_lines, stdout_lines))
            )

            out.append(src[cmd_idx])  # the `$ command` line
            if replace_all or whitespace_only:
                out.extend(actual_lines)
                if actual_lines != stdout_lines:
                    n_changed += 1
            else:
                out.extend(stdout_lines)
                n_skipped += 1
            out.append(exit_line)
            continue

        # Anything else: pass through
        out.append(ln)
        i += 1

    new_text = '\n'.join(out) + '\n'
    if new_text != text:
        path.write_text(new_text)
    return n_total, n_changed, n_skipped


def main():
    parser = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument('files', nargs='+', metavar='FILE.test',
                        help='shelltestrunner .test files to regenerate')
    parser.add_argument('--all', action='store_true',
                        help='replace expected with actual whenever the run '
                             'succeeded with the expected exit code, even if '
                             'the diff is more than whitespace (default: only '
                             'replace whitespace-only diffs)')
    args = parser.parse_args()

    hledger_bin = find_hledger()
    hledger_dir = os.path.dirname(hledger_bin)
    env = {**os.environ,
           'PATH': hledger_dir + os.pathsep + os.environ.get('PATH', '')}

    grand_total = grand_changed = grand_skipped = 0
    for a in args.files:
        path = Path(a)
        if not path.exists():
            print(f"missing: {a}", file=sys.stderr)
            continue
        total, changed, skipped = regen_file(path, hledger_bin, env, args.all)
        grand_total += total
        grand_changed += changed
        grand_skipped += skipped
        print(f"{path}: {total} tests, {changed} updated, {skipped} skipped")
    print(f"TOTAL: {grand_total} tests, {grand_changed} updated, {grand_skipped} skipped")


if __name__ == '__main__':
    main()
