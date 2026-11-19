# PLAN: version control awareness

Status: designed and implemented 2026-11-19; the open decisions were settled as recommended. See "Implementation notes" at the end.

hledger detects whether the journal's files are in a version control repository (jj or git),
`setup` reports on it, and the commands which change files can record their changes there with `--commit`.

## Goals

- Make it easy to keep a journal's history, and to undo a mistaken import or add, without scripting.
- Give commits meaningful messages, which only hledger knows (eg how many transactions were imported, from where).
- Never surprise: nothing is committed without `--commit` (given on the command line or in a config file).
- Commit only what the command changed, never unrelated work in the repo.

Non-goals (for now): reading past revisions, ui/web status indicators, creating repositories,
other version control systems, per-transaction history.

## Detection

- Start from a directory: the main journal file's directory (for `init`, the target directory).
- Walk up from there towards the root. In each directory, if `.jj` exists, the repo is jj, rooted there;
  else if `.git` exists (a directory, or a file as in worktrees and submodules), the repo is git, rooted there.
  The nearest repo wins; in one directory, jj wins (so a colocated jj/git repo is used through jj, which keeps git in sync).
- Detection only looks at the filesystem. Using a repo also needs its tool (`jj` or `git`) in PATH, checked with `findExecutable`.
- Files outside the detected repo's root (eg included from elsewhere) are never committed; `--commit` warns about them.

## setup

In setup's journal section, after the default journal file is found and read:

- `the journal is in a version control repo ?` Y: `jj repo at DIR` or `git repo at DIR`, and if its tool is not in PATH,
  say so (N). N (informational, not a problem): with a hint like `jj git init` or `git init`, and a pointer to the manual.
- When there is a repo and its tool is available:
  - `all journal files are tracked ?` Y, or N with a count of the files not tracked (the files listed by `hledger files`, inside the repo).
    This catches a new year file or rules file which was never added.
  - `journal files have unrecorded changes ?` informational: N, or Y with a count of changed files.
- Status is per file, from the tool (git: `git status --porcelain=v1 -z -- PATHS`; jj: `jj diff --name-only` and `jj file list` with fileset arguments).
  setup must stay robust: any tool error is shown as a failed check, never a crash.

## --commit

A new flag, `--commit`, on the commands which change files:

| command        | files changed                                                    | commit message (first line)                          |
|----------------|------------------------------------------------------------------|------------------------------------------------------|
| `add`          | the journal file appended to                                     | `hledger add: N transactions` (one: `hledger add: DATE DESCRIPTION`) |
| `import`       | main journal; `.latest.*` files; archive files written; source files removed by archiving | `hledger import: N new transactions from FILES` (`--catchup`: `hledger import: caught up FILES`) |
| `get`          | prices files written; anything under the data directory (written by getdata) | `hledger get: prices for COMM1, COMM2..; data`     |
| `init`         | the files created                                                | `hledger init: LAYOUT layout`                        |
| `hledger-web`  | add form: the file appended to; edit and upload: the file written | `hledger-web add: DATE DESCRIPTION`, `hledger-web edit: FILE`, `hledger-web upload: FILE` |

Behaviour:

- Before changing anything: if `--commit` is given and there is no repo, or its tool is not in PATH, it is an error
  (`--commit: no jj or git repository found at or above DIR`), and nothing is written.
- After the command has written its files: commit exactly those paths (pathspecs), with the message above.
  - git: `git add -A -- PATHS` (after dropping paths which git ignores, found with `git check-ignore`), then
    `git commit -m MSG -- PATHS`. The `-- PATHS` form commits only these paths, leaving anything else the user has staged alone.
  - jj: `jj commit -m MSG FILESETS`, which moves just those paths' changes into a new commit and leaves the rest in the working copy.
    Paths are given as exact filesets (eg `root-file:"PATH"`, quoted and escaped; check the current jj fileset syntax), so names with special characters are safe.
  - If those paths have no changes (eg import found nothing new), commit nothing and say nothing.
- After a successful commit, print one line on stderr: `committed to jj: MSG` (or git).
- Directories as pathspecs (get's data directory, import's archive directory) are fine; the tools respect their ignore files,
  so users who keep downloads out of version control just ignore them.
- Commit failure (eg a failing git hook, no user.name configured): the files stay written; report an error which says so
  and includes the tool's output; exit code 1.
- `--dry-run` (import, get, init): also print `would commit to jj: MSG` with the paths, and run no tool.
- Uncommitted changes the user made earlier, in the same files (eg a hand-edited journal before an import): see the open decisions.
- add commits once, when the session ends (normally, or on interrupt or error, via `finally`), not after each transaction.
- hledger-web: `--commit` is a server option; each add, edit or upload is committed when it is saved.
  The edit form's numbered backup files (`FILE.N`) are not needed when committing; skip them with `--commit`.
- Tool processes run without a shell (argument lists), in the repo root, with `LC_ALL=C` where output is parsed.
  The tool's stderr is shown only on failure.

Making it the default: users can put `--commit` in their config file, in the sections of the commands they want it for,
or in `[general]` (commands which don't support `--commit` drop it, as with other unsupported general options).

## Implementation

- New module `Hledger.Cli.Vcs` (hledger/Hledger/Cli/Vcs.hs), used by the CLI commands and hledger-web:

  ```haskell
  data Vcs = Jj | Git
  data Repo = Repo { repoVcs :: Vcs, repoRoot :: FilePath }

  detectRepo     :: FilePath -> IO (Maybe Repo)            -- walk up from a directory
  repoToolFound  :: Repo -> IO Bool
  repoFileStatus :: Repo -> [FilePath] -> IO (Either String [(FilePath, FileStatus)])  -- for setup
  repoCommit     :: Repo -> String -> [FilePath] -> IO (Either String CommitResult)    -- Committed | NothingToCommit
  ```

  plus a small helper for the commands: given CliOpts and the start directory, check `--commit` preconditions up front
  (returning the Repo or an error), and later commit the paths and report the outcome. Keep the per-tool command lines in one place.
- A `commitflag` in CliOptions (`flagNone ["commit"] ... "record the changed files in the jj or git repository"`), added to the five commands' modes.
- Each command collects the paths it actually writes or removes. Where that is deep in a library function
  (import's archiving and .latest files), prefer returning or computing the paths over passing pathspecs broader than needed;
  if that is impractical, use the data directory's `archive/` subdirectory and the source data files as pathspecs, and note it here.
- No partial functions; tool errors are values (Either), never exceptions escaping to the user unformatted.

## Docs

- hledger.m4.md: a short "Version control" section (detection, `--commit`, making it the default, what is committed), linked from the commands' docs.
- Add.md, Import.md, Get.md, Init.md: the flag. Setup.md: the new checks. hledger-web manual: the server option.
- Mention bin/hledger-git and bin/hledger-jj as complementary (status/log/record of all journal files).
- Do not run `./Shake cmddocs`; the maintainer regenerates the .txt files.

## Tests

- Unit tests: detection precedence (jj over git in one directory, nearest repo wins, `.git` as a file), fileset quoting, message formatting.
- Functional tests (hledger/test/vcs.test), each in a temporary directory:
  - git: `git init -q`, author/committer set via `GIT_AUTHOR_NAME` etc environment variables; then `init --commit`, `add --commit`
    (with piped input), `import --commit` (a small CSV and rules), `get --commit --prices` (with a stub getprices like get.test's);
    check `git log --format=%s` and that `git status --porcelain` shows only expected leftovers.
  - Unrelated changes (a staged file, an edited other file) are not included in the commit.
  - No repo: `--commit` errors and nothing is written.
  - jj: the same core cases, run only when `jj` is in PATH (otherwise the test prints the expected output itself, so it passes).
  - setup: hard to test (it requires the installed hledger); test the Vcs functions it uses instead, or test setup manually.
- hledger-web: a yesod-test for add with `--commit` in a temporary git repo, if practical.

## Phases (a commit each)

1. Vcs module, detection, unit tests.
2. setup checks.
3. `init --commit` (the simplest: a known list of new files).
4. `add --commit`, `import --commit`, `get --commit`.
5. hledger-web `--commit`.

## Open decisions

1. Earlier unrecorded changes in the same files (eg the user hand-edited main.journal, then runs `import --commit`).
   File-level commits can't separate them.
   Recommendation: include them, and say so (`also recording earlier changes in main.journal`), so `--commit` never blocks a normal workflow.
   Alternative: refuse before writing anything, so each commit contains only hledger's own change.
2. `init --commit` where there is no repo yet.
   Recommendation: an error with a hint (`git init` / `jj git init`), consistent with "commit to the active repo".
   Alternative: create one (jj if installed, else git), which is friendlier to newcomers but makes init choose a tool.
3. get's data phase: commit the whole data directory (catching whatever getdata wrote), or only the prices files.
   Recommendation: both, relying on ignore files for users who don't want downloads recorded.

## Implementation notes (2026-11-19)

Built as designed (module `Hledger.Cli.Vcs`, setup checks, `--commit` on init, add, import, get and hledger-web), with these differences:

- jj: before committing, `jj file track` the paths, since jj may be configured not to track new files automatically
  (`snapshot.auto-track`); it doesn't track ignored files. jj paths are given as `root:"PATH"` filesets.
- git: paths which are ignored, or which neither exist nor are tracked, are left out before `git add -A -- PATHS`
  (git refuses them); then `git diff --cached --quiet` decides whether there is anything to commit.
- get makes a commit per phase (`hledger get: new data`, then `hledger get: new prices for X, Y`), so each message is accurate.
  `import --get --commit` makes get's commits, then import's.
- import commits the main journal, the `.latest.*` files, and the whole data directory (simpler than finding the archived and removed files).
- add prints a newline before its commit message, ending the last prompt's line.
- hledger-web checks for a repository at startup (exiting with an error if there is none), and commits after each add, edit or upload;
  a commit problem is shown as the page's message (or for the JSON API, logged on stderr). It doesn't detect earlier unrecorded changes,
  and the edit/upload backup files (`FILE.N`) are still written.
- setup's first check is worded `the journal is version controlled ?` (to fit the column).
- Tests: hledger/test/vcs.test, with helpers in hledger/test/vcs.sh which isolate git and jj from user configuration.
  setup's checks and hledger-web's commits were tested manually, not in the test suites.
- Not done: translating the new messages; regenerating the commands' .txt docs and the manuals (left to the maintainer).
