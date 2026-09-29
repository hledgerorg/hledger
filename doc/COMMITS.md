# COMMITS

In the hledger project we try to follow certain conventions for commit messages,
because good messages lead to good commits => good change docs =>
easier code review => quicker merging => faster delivery of quality software.
`tools/commitlint` checks them (locally and in CI), and we'll help you polish them in code review.

Here's the format: <!-- keep synced with tools/commitlint -->

    [;]type[!]: [topic:] Summary

    [Longer description when useful]

More precisely:

- Commit messages must begin with one or more prefixes (colon-terminated words):
  a type, and optionally a [topic](ISSUES.md#topics) (or several, separated by commas).
- The type says who the change is for, and where it will be announced:
  - `feat`, `imp`, `fix` (new feature, improvement, bugfix):
    user-visible changes. These go in release notes and changelogs.
  - `pkg`, `lib` (packaging, library):
    changes affecting packagers, builders or library users. These go in changelogs.
  - `dev`, `doc`, `test`, `ci`, `tools`, (misc. development, docs, tests, CI, tools):
    developer changes. These mostly stay in the commit log.
- Breaking/incompatible changes add a `!` after the type: `feat!:`, `imp!:`, `fix!:`.
- A leading `;` marks a commit that doesn't need the expensive CI tests
  (docs, tools, tests, etc.). When the latest pushed commit has it, CI skips those steps.
  Our CI does a lot of work, so this reduces energy waste and carbon emissions.
- Mention any relevant issue numbers, usually parenthesised at the end: `(#NNNN)`.
- Write the message as changelog/release-note-ready documentation, telling its intended audience
  (users, installers, packagers and/or developers) what they need to know.

Some examples:

- `feat: accounts: --types shows account types (#1820)`
- `imp!: journal: Remove deprecated account type code syntax from account directives.`
- `fix: types: Ensure auto postings can match against and be matched by type: queries.`
- `;pkg: stack: bump to lts-24`
- `;tools: commitlint: allow a git "fixup! " prefix`
- `;doc: releasing: tweaks`

## How to check commits

Before committing, pushing, or merging, run `tools/commitlint` to check recent commit messages.
(See the script for more ways to select commits.) You can configure your local working copy
to do this automatically, by running `just installcommithook`.

commitlint also runs on Github as part of CI, where its result is advisory.

## See also

- <https://groups.google.com/g/hledger/c/t14xwHQMJqU/m/9frARXIdAAAJ>
- <https://conventionalcommits.org>
- <https://git.savannah.gnu.org/cgit/emacs.git/plain/CONTRIBUTE> -> Commit messages
