---
name: release
description: Drive an hledger release (major, bugfix, or preview) using doc/RELEASING.md's "Release script" as the step list. Use in the hledger repo when the user says "let's do the X.Y.Z release" or similar.
---

# hledger release process

This skill describes *how* to drive a release, not the release steps themselves - those live in
`doc/RELEASING.md` (and possibly a maintainer's working copy `doc/.RELEASING.md`, ahead of it during
an in-progress release) under "Release script" (the canonical step sequence, grouped into phases) and
"Release artifacts reference" (supporting details, gotchas, "How to.." recipes; the script wins on any
conflict). Always read the current version of that file at the start of a
release rather than relying on memory of a past one - it gets updated after each release with lessons
learned, and step order/branch placement has changed between releases.

## How to drive it

- **One step at a time, with confirmation.** Run one numbered step, report what happened, then wait -
  even for a full release - unless the user has explicitly said to proceed autonomously through a
  stretch of steps. The maintainer leads; you execute.
- **Never push/upload/publish/announce without being asked.** These are one-way doors. Don't run them
  speculatively even mid-release - get an explicit go-ahead for that specific step, even if earlier,
  similar-looking steps were already approved.
- **Distinguish reversible from irreversible before acting.** E.g. re-uploading release binaries with
  `--clobber` is safe to just do; uploading to Hackage is not (no unpublish). If unsure which a command
  is, say so and ask rather than guessing.
- **Confirm the current branch before each step** (`git branch --show-current`) against that step's
  `main:`/`rel:`/`site:` label. 
  The branch can change between your checks (e.g. the maintainer switching branches outside your tool
  calls), so re-check rather than trusting an earlier check.
- **Major vs minor/bugfix vs preview:** steps tagged `(major release)` only apply to `A.B` releases;
  `(minor release)` only to `A.B.C` bugfix releases; untagged steps apply to both. Preview releases
  (`A.B.99...`) skip anything tagged `(non-preview release)`.
- **If a GHC version the release branch needs isn't installed locally**, avoid installing it if possible -
  save a copy of main's `stack.yaml` (e.g. as `stackmain.yaml`, then use `-w stackmain.yaml` with all stack commands, or temporarily replace the release branch's `stack.yaml` for tools like Shake
  that don't take `-w`). Always restore the real `stack.yaml` afterward and check `git status`
  before committing.
- **If the release includes a fix for a previously-embargoed security issue**, treat that as an extra
  thread alongside the normal steps: keep the advisory private until the release is out and installable;
  publish it once the fix has had a little time to propagate (don't wait on CVE grant - that's a separate,
  slower, async process); cross-link the advisory and the release notes/tag; and if an issue/PR had to be
  redacted during the incident, restore it and link it to the advisory once published (a published GHSA
  is already public and indexed regardless of what links to it, so redacting only helps for as long as the
  PR/issue holds materially more detail than the advisory itself).

## Where things live

- `doc/RELEASING.md` - canonical process docs (goals, release-type table, script, checklist, glossary)
- `doc/.RELEASING.md` - maintainer's working copy, if present; may be temporarily ahead of RELEASING.md
  during a release (edited live to avoid interfering with branch switching) - diff it against
  RELEASING.md and prefer it if both exist
- `Justfile`, `Shake.hs`, `tools/` - the actual commands / `just` recipes the script steps refer to
