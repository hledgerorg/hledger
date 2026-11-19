# PLAN: init command

Status: designed and implemented 2026-11-19 (see "Implementation notes" at the end for deviations).

A new builtin command which writes starter files for a new hledger setup,
or adds missing ones to an existing setup.
The files come from the example layouts in examples/file-layouts/,
which are embedded in the hledger executable and remain the only copy.

```
hledger init [FILE.journal | DIR] [--dry-run]
```

## Behaviour

### What is written where

| Argument                          | Layout  | Written to                                    |
|-----------------------------------|---------|-----------------------------------------------|
| none                              | default | the current directory                         |
| a directory path                  | default | that directory, created with parents if needed |
| a journal file path               | simple  | simple's main.journal content, at exactly that path (parents created) |

Deciding which kind of argument it is, in this order:

1. It names an existing directory, or ends with a path separator: a directory.
2. Its extension is one of the journal reader's extensions
   (`journal`, `j`, `hledger`, `ledger`; take them from the journal reader's `rExtensions`, don't repeat the list): a journal file.
3. It has any other extension (`foo.csv`, `foo.timeclock`, `foo.txt`): a usage error,
   saying that a file argument must have a journal file extension and a directory argument must not look like a file.
4. Otherwise: a directory.

More than one argument is a usage error.

### Existing files

- A file that already exists is never overwritten or changed. It is skipped, with a warning on stderr (`warnIO`).
  "Exists" includes a symbolic link or anything else already at that path.
- Skipping is not a failure: the exit code is 0, so init can be re-run to add missing files.
- If a directory is needed where a non-directory exists, that is an error (exit 1), reported before anything is written.
- So init does all its checks first, then writes. An IO error while writing is reported normally and exits 1;
  files already written are left in place.

### Files written

- Content is written byte for byte (ByteString), with no line ending conversion, so it matches the repo files on every platform.
- data/getdata and prices/getprices are written as regular files with the owner-executable bit set
  (`System.Directory.setPermissions`, no unix-only API). In the repo they are symlinks to bin/; the embedded content is the target's.
- Paths with a component ending in a dot are refused on Windows, as `ensureJournalFileExists` does (`isWindowsUnsafeDotPath`, export it from Hledger.Read).

### Output

On stdout, one line per file in manifest order, with paths shown relative to the current directory when they are inside it:

```
created  main.journal
created  accounts.journal
skipped  commodities.journal (exists)
...
```

then, if a main journal was created or already exists there, short next steps:

```
To use these files, add this to your shell startup file:
  export LEDGER_FILE=/full/path/to/main.journal
Then try:
  hledger check      check the journal
  hledger add        add transactions
  hledger setup      check your installation
```

The `LEDGER_FILE` hint is omitted when `$LEDGER_FILE` already resolves to that file.
(On Windows, show the equivalent hint used by `setup`, if it has one; otherwise the same text.)

With `--dry-run` the same list is printed with `would create` / `would skip`, nothing is written,
and the next steps are not shown.

All new user-visible strings go through the i18n mechanism like other commands' output; update hledger.pot only.

### Options

- `--dry-run`: as above.
- init never reads a journal or a config-specified file: add `"init"` to `journalIgnoringCommandNames`
  (hledger/Hledger/Cli/CliOptions.hs), which covers both Cli.hs and Run.hs dispatch. `-f` and `$LEDGER_FILE` do not affect where files are written.
- No other command-specific flags in v1. Use `generalflagsgroup3` like setup.

## Layout content changes (examples/file-layouts)

Do these first, as their own commit(s) (`;examples:file-layouts: ...`).

1. Update all dates to 2026:
   - simple/main.journal and default/main.journal: 2021-01-0N becomes 2026-01-0N.
   - default/data/bankofireland-checking.csv and year-dirs' copy: 07/12/2012 becomes 07/01/2026 (kept in the past).
2. Keep the files literal; init does no templating. The sample entries stay as they are.
3. `examples/file-layouts/check` must still pass.

## Implementation

### Embedding

- Add a directory symlink `hledger/embeddedfiles/file-layouts -> ../../examples/file-layouts`,
  following the existing embeddedfiles pattern (which so far uses per-file symlinks).
  Verify that `stack sdist hledger` includes the files' contents, and that the Windows CI build finds them.
  If a directory symlink fails either check, fall back to per-file symlinks under `hledger/embeddedfiles/file-layouts/`.
- List every embedded file in `extra-source-files` in hledger/package.yaml (explicit paths, no globs), so `tools/checkembeddedfiles` passes.
- New module `Hledger.Cli.Layouts` (hledger/Hledger/Cli/Layouts.hs) with an explicit manifest, not `embedDir`
  (embedDir loses executable bits, follows directory symlinks, and does not notice added files):

  ```haskell
  data LayoutFile = LayoutFile
    { lfPath       :: FilePath     -- relative to the layout's root, with / separators
    , lfExecutable :: Bool
    , lfContent    :: ByteString
    }

  simpleLayout, defaultLayout :: [LayoutFile]
  ```

  each entry using `$(embedFileRelativeBytes "embeddedfiles/file-layouts/...")`.
  `simpleLayout` has one file. `defaultLayout` has, in this order: main.journal, accounts.journal, commodities.journal,
  payees.journal, data/getdata, data/bankofireland-checking.csv, data/archive/README.md, prices/getprices,
  rules/bankofireland-checking.csv.rules.
  Convert `/` to the platform separator when writing.
- year-dirs is not embedded in v1.

### Command

- New module `Hledger.Cli.Commands.Init` with `initmode` and `init'` (or similar; avoid shadowing Prelude's `init`),
  docs in `Commands/Init.md`, generated `Init.txt` via `./Shake cmddocs -c` (never hand-edit the .txt).
- Register it everywhere setup is registered:
  - `builtinCommands` and the module exports/imports in hledger/Hledger/Cli/Commands.hs
  - `commandsListSections`: in MAINTENANCE, directly after setup: ` init                     create starter journal files`
  - hledger/Hledger/Cli/Commands/commands.m4, after Setup
  - hledger/hledger.m4.md: the command list (after setup) and the command/option compatibility table near line 8283
  - hledger/package.yaml: `Init.txt` in extra-source-files, the two new modules in the module lists
- Structure: a pure planning function from (argument, layout, facts about existing paths) to a list of actions
  (`Create path file | Skip path`) or an error, plus a small IO layer that gathers the facts, prints, and writes.
  This keeps dry-run and real runs identical up to the final write, and makes the argument rules unit-testable.
- No partial functions, no `error` outside the usual `usageError`/`error'` reporting of user errors.

### Pointers to init (deferred)

- `requireJournalFileExists` (hledger-lib/Hledger/Read.hs): change the hint to
  `Please create it first, eg with "hledger init", "hledger add" or a text editor.` and update tests that show this message
  (including hledger/test/errors/ if it has an example).
- Setup.md / setup's journal section: when no journal file is found, suggest `hledger init`.
- examples/file-layouts/README.md: mention that `hledger init` writes the simple and default layouts.
- Get.md: mention that `hledger init` installs starter getdata/getprices scripts.

## Tests

New `hledger/test/init.test` (shelltest v3 format, sequential test numbers), each test working in a `mktemp -d` directory like get.test does,
with `--no-conf`:

1. `init DIR` then `diff -r DIR examples/file-layouts/default` shows no differences (this catches a manifest out of sync with the tree),
   and getdata/getprices are executable.
2. `hledger -f DIR/main.journal check -s` succeeds on the result.
3. No argument: writes the default layout into the current directory.
4. Re-run in the same directory: every file skipped with a warning, exit 0, files unchanged.
5. One file pre-existing with different content: it is skipped and unchanged, the rest are created.
6. `init some/new/dir/my.journal`: writes simple's main.journal content there; `diff` against examples/file-layouts/simple/main.journal.
7. `init foo.csv`: usage error. Two arguments: usage error.
8. `--dry-run`: lists `would create` lines, writes nothing.
9. A regular file where a directory is needed (`touch D/data; init D`): error, exit 1, nothing written.

Unit tests for the argument classification and planning function.

## Decided

- Sample content stays literal, no templating; dates updated to 2026.
- In the commands list, init goes directly after setup.
- A non-journal file extension is an error.
- Bare `hledger init` writes into the current directory, like `git init`; `--dry-run` is the opt-in preview.
  (Alternative considered: bare `init` only previews and suggests `hledger init .`.)
- The sample entries stay as they are for now: they show something working and are easy to customise.
- Hints pointing to init from elsewhere (see "Pointers to init") are deferred, to reduce churn.

## Later

- `--layout simple|default|year-dirs`, and a way to list layouts.
  year-dirs needs the year templated in paths and content, relative directory symlinks (a problem on Windows),
  and its empty `2026/rules` directory (which git does not track).
- `--git` / `--jj`: initialise a repository, write an ignore file, make a first commit.

## Implementation notes (2026-11-19)

Deviations from the plan above:

- One module, hledger/Hledger/Cli/Commands/Init.hs, holds the manifest as well as the command (no separate Layouts.hs).
- Output: created files are listed on stdout (`created PATH`); skipped files are only reported as warnings on stderr
  (`Warning: skipped PATH, it already exists`), not also listed on stdout. `--dry-run` lists both on stdout (`would create`, `would skip`).
  Paths are shown as written (relative to the argument), not made relative to the current directory.
- Next steps are aligned commands with comments (`hledger -f PATH check`, `bs`, `add`, `hledger setup`), with `-f` omitted
  when LEDGER_FILE already selects the main journal; then the LEDGER_FILE hint, linking to the manual's "Setting LEDGER_FILE".
- No i18n: like setup, get and files, init's output is not translated yet, so hledger.pot is unchanged.
- init accepts the hidden general flags, including `-n`/`--no-conf` (setup does not).
  Config files are still read for init, as for most commands.
- The symlinks go the other way from the plan, so that builds never depend on symlinks
  (Windows checkouts have them as small text files by default) and nothing is duplicated:
  - The simple and default layouts' real files are in `hledger/embeddedfiles/file-layouts/{simple,default}/`.
  - `examples/file-layouts/simple` and `default` are directory symlinks to those; examples/file-layouts/README.md says so.
  - getdata and getprices are real files only in the default layout; `bin/getdata`, `bin/getprices`
    and year-dirs' `data/getdata`, `prices/getprices` are symlinks to them (year-dirs' were full copies before).
    Links to them in Get.md and bin/README.md now point to the new location.
  - year-dirs stays in examples/ (not embedded yet).
  - `stack sdist` includes the real file contents, with executable bits.
- The existing per-file symlinks in hledger/embeddedfiles (tldr pages, manuals) are probably embedded as their
  target path text in Windows builds. Not checked.
