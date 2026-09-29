---
name: regen-shelltests
description: Regenerate expected output in failing shelltestrunner v3 fixtures (`hledger/test/**/*.test`) after a hledger output-format change (alignment, column shifts, rendering tweaks). Use when many `.test` fixtures are stale because of a deliberate, audited rendering change.
---

# Regenerating shelltestrunner fixtures

When a change to hledger's output rendering (alignment, padding, column positions) breaks many fixtures in `hledger/test/`, use [tools/regen-shelltests.py](../../tools/regen-shelltests.py) to bulk-update them.

The script's default mode is **whitespace-only**: it overwrites a test's expected stdout with the actual output only when the difference is purely whitespace (column shifts). Anything else — added/removed lines, changed numbers, different commodities — is left for human review. This makes it safe to run on a batch of failing tests without losing in-flight content edits.

## When to use this skill

The user is dealing with many failing functional tests after a deliberate rendering change, and wants the column shifts auto-applied while preserving any other content for hand-review.

Do NOT use this skill if the user wants to regenerate all output blindly without auditing — that's a sign the underlying change isn't well understood, and a hand-review of a few representative failures is the right next step.

## Workflow

1. **Build hledger first** — the script invokes `stack exec -- which hledger` to find the binary and prepends its dir to PATH so test wrapper scripts (e.g. `csvtest.sh`) pick up the just-built one.

   ```sh
   stack build hledger
   ```

2. **Identify failing test files** (not individual tests — the script processes whole files):

   ```sh
   stack exec -- shelltest --execdir --exclude=/_ hledger/test/ \
     -x hledger/test/perf.test \
     -x ledger-compat/ledger-baseline -x ledger-compat/ledger-regress -x ledger-compat/ledger-extra \
     -j8 2>&1 \
     | grep "Failed\]" \
     | sed 's/^:\(.*\):[0-9]*: \[Failed\]$/\1/' \
     | sort -u > /tmp/failing-files.txt
   ```

3. **Run the regen on just those files**:

   ```sh
   cat /tmp/failing-files.txt | xargs tools/regen-shelltests.py
   ```

   Output looks like:

   ```
   hledger/test/csv.test: 63 tests, 3 updated, 7 skipped
   ...
   TOTAL: 102 tests, 9 updated, 17 skipped
   ```

   "Updated" = expected stdout overwritten because the diff was whitespace-only.
   "Skipped" = left as-is for one of these reasons (the script logs each):
   - Test has a stderr expectation (`>2 …` or `>>>2 …`).
   - No exit marker (malformed or v2-format).
   - Exit code mismatched (real failure, not just formatting).
   - Diff was more than whitespace.

4. **Re-run the tests** to confirm the regen reduced failures:

   ```sh
   just functest --hide
   ```

5. **Hand-fix the remainder.** Common remaining cases:
   - **Stderr-regex tests** with embedded posting renders (`errors/`, `journal/parse-errors.test`, etc.) — adjust the spaces/carets in the regex by hand.
   - **Tests without exit markers** — add `>=` or `>= 0` if the format is malformed.
   - **Real content changes** — investigate; these are not just-formatting issues.

6. **`git diff` and review** before committing. The whitespace-only safeguard is good but not infallible.

## Flags

- `--all` — bypass the whitespace-only check and overwrite whenever the run produced the expected exit code. Use only after you've audited a few failures and confirmed the actual output is correct in a non-whitespace way.

## Limitations

- Doesn't handle stderr regenerate. Stderr regex blocks (`>2 /…/` and `>>>2 /…/`) are skipped because regex regen is fiddly (escaping, multi-line patterns, regex-tdfa size limits).
- Doesn't handle v2-format input blocks (`<<<` / `>>>` / `>>>=`). Files using those are passed through verbatim.
- Doesn't update doctests in Haskell sources (run `just doctest` separately, then hand-update).
- Regenerates in place. Always work on a clean tree so `git diff` is meaningful for review.

## Anti-patterns

- **Regen with `--all` on a fresh transcript without inspection.** This is the same as accepting whatever hledger emits today as correct, including bugs. Always run with the default (whitespace-only) first; only escalate to `--all` for tests where you've manually verified the new output.
- **Regen across the whole `hledger/test/` directory.** The whitespace-only mode protects against this somewhat, but it's still safer to feed only the failing files — that way you'll notice if a passing test mysteriously changes.
- **Skipping the rebuild.** If `stack build hledger` is stale, the regen reflects yesterday's binary, not your latest code. Always build first.
