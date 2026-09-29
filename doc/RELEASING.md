# RELEASING

Notes for hledger release managers and maintainers.

## Goals

**2026**
- [ ] AI policy
- [ ] lot tracking
- [ ] hledger 2.0

**2025**
- [x] Make releasing easier
- [x] Improve automation
- [x] Improve process docs
- [x] Track releasing and release engineering time explicitly, per release

**2024**
- [x] Make releasing easier

**2023**
- [x] Make releasing eas<s>y</s>ier

**2022**
- [x] Update/consolidate release process docs,
- [x] Establish routine <s>monthly</s> release cadence,
- [ ] Make releasing easy

## hledger release types

hledger major releases happen each quarter, normally at the start of the third month (see [past releases](relnotes.md)).
Bugfix releases follow those when needed, usually soon after.
Preview/nightly releases may happen any time.

|                     | Major&nbsp;release<br>A.B                                | Bugfix&nbsp;release<br>A.B.C | Preview/Nightly&nbsp;release<br>A.B.99   |
|---------------------|----------------------------------------------------------|------------------------------|------------------------------------------|
| **Contains:**       | New features, breaking changes                           | Only bug fixes               | Early snapshot of the next major release |
| **When:**           | Start of third month in quarter: Mar, Jun, Sep, Dec      | When needed                  | Occasionally, as needed                  |
|                     |                                                          |                              |                                          |
| **Deliverables:**   |                                                          |                              |                                          |
| Changelogs          | ✓                                                        | ✓                            | ✓                                        |
| Github release      | ✓                                                        | ✓                            | ✓                                        |
| Binaries            | ✓                                                        | ✓                            | ✓                                        |
| Hackage release     | ✓                                                        | ✓                            |                                          |
| Install page        | ✓                                                        | ✓                            |                                          |
| Regression&nbsp;bounties | ✓                                                   | ✓                            |                                          |
| Release notes       | ✓                                                        | ✓                            |                                          |
| Manuals snapshot    | ✓                                                        |                              |                                          |
| Announcements       | ✓                                                        |                              |                                          |

[Regression bounty]: https://hledger.org/regressionbounty

## hledger release artifacts / value chain

Higher things depend on lower things.
Release readiness and the release process go from the bottom of this diagram to the top.

[![release diagram](RELEASING.png)](RELEASING.png)
<!-- source: RELEASING.canvas (Obsidian) -->

## Release script
Last updated: 2026-09\
This is the canonical step sequence for making a release, annotated with lessons from past releases.
For extra how-to's not covered here, see the "How to.." and "Tips" sections below.\
Key: main: = in hledger repo main branch, rel: = in hledger repo release branch, site: = in site repo,
(CONDITION) ... = when CONDITION is true, `CMD` = suggested relevant command.\
Steps marked ⚠ push/upload/publish/announce to somewhere shared and are hard or impossible to undo -
always get explicit go-ahead for that specific step, even mid-release, even if earlier steps were approved.
Steps without ⚠ are safe to just do once they're clearly next.\
The actual commands referred to above live in `Justfile`, `Shake.hs`, `tools/`.
During a release, this file may be copied to `doc/.RELEASING.md` (untracked) and edited live there,
to avoid interfering with branch switching; RELEASING.md should be updated from it after the release.

0. **before any step: confirm the current branch** (`git branch --show-current`) matches that step's `main:`/`rel:`/`site:` label.
   The branch can change between your checks (e.g. the maintainer switching branches outside your tool calls),
   so re-check rather than trusting an earlier check.

### Phase 1: prepare main

1. **main: finish fixes/features/docs/issues/prs**
1. **main: begin/fix release builds:** `just ghbin oldest`
1. **main: update general flags help:** `just generaloptionshelp` (updates doc/common.m4 from the build's --help output; review the diff)
1. **main: update command docs and manuals ?** `just manuals`; check the manuals' internal links: `just anchortest`
1. **(major release) main: update website manuals:** `just manuals-site`
1. **(major release) main: update website scripts/redirects:** update `site/Makefile`, `site/js/site.js`, `site/hledger.org.caddy`

### Phase 2: prepare the release branch

1. **main: create/update release branch:** `just relbranch VER` (also works for A.99.N preview releases, creating VER-branch)
   - if a GHC version the release branch needs isn't installed locally, avoid installing it if possible - save a copy
     of main's `stack.yaml` (e.g. as `stackmain.yaml`), then use `-w stackmain.yaml` with stack commands, or
     temporarily replace the release branch's `stack.yaml` for tools like Shake that don't take `-w`. Always restore
     the real `stack.yaml` (`git checkout -- stack.yaml`) afterward, and check `git status` for stragglers before
     committing/pushing.
1. **(minor release) rel: cherry-pick new changes from main**
1. **rel: update command docs and manuals:** `just manuals`
1. **rel: update changelogs:** `just changelogs`; edit by hand; `just changelogs-finalise`
1. **rel: update relnotes:** `just relnotes`; edit (add summary); commit
   - (major release) show the drafted summary to the maintainer and get it confirmed before committing.
   - it's normal for some packages to have zero changes in a bugfix release - `just relnotes` emits a one-line
     "Uses PKG X.Y.Z" for them; not a problem for downstream packagers.
1. **(major or preview release) rel: update announcements:** edit `doc/ANNOUNCE` - do this before making the
   release builds below, so that it is included in the release tags. (Preview releases are announced too;
   in general they are treated more like major than minor releases.)
   Show the drafted ANNOUNCE to the maintainer for editing/confirmation before committing it.
1. **rel: update install docs:** `just installpage`; edit `doc/ghrelnotes`, and finish
   `site/src/install.md` by hand ("Update the Install page" below) - do this on the release branch, not on main
   (main's copy of ghrelnotes describes the *next preview* line and is unrelated to the
   release branch's version).
1. **rel: make release builds:** `just ghbin` - do this last, once the release branch has all its commits, so the
   binaries are built from the commit that will be tagged. Takes 30-40 minutes; watch with `just ghbin-open`.
   If more commits land on the branch afterwards, re-run it.
1. **main: cherry-pick changelogs, relnotes, announcement, other relevant updates from relbranch** `jjui -r ::`
   - this happens on main and doesn't affect the release branch, so it can be done while the binaries build.

### Phase 3: tag and publish ⚠

Everything before this phase is revisable (nothing shared beyond scratch CI branches); this phase contains the one-way doors.

1. **rel: make release tags:** (once binaries are all built) `just reltags` - safe to re-run/move if the release branch
   gets more commits before tags are pushed.
1. **(non-preview release) rel: publish on hackage:** `just hackageupload` ⚠ (no unpublish - confirm before running the
   actual upload, distinct from the earlier reversible build/upload steps)
1. **push to github:** push site repo, push VER-branch, `just reltags-push`, push main ⚠
1. **publish on github:** `just ghrel` (runs the release workflow on github, creating/updating a *draft*
   github release with release notes and the binaries built from the tagged commit - the binaries stay on
   github's servers; safe to re-run); review it (`just ghrel-open`); then `just ghrel-publish` ⚠
   - the workflow selects each binaries-* workflow's run for the release tag's commit, and fails if there's
     no successful one (eg if the binaries were built from a different commit - rerun `just ghbin` on the tag).
   - on older release branches without the release.yml workflow, use `just ghrel-local` instead.
   - release branches cut before 2026-09 have the *old* release.yml (nominally triggered by the tag push, and
     picking each binaries-* workflow's **latest** successful run rather than the tag commit's), and lack the
     `ghrel`/`ghrel-publish` recipes. Rather than cherry-pick the new tooling onto such a branch, use the old
     workflow (as in the 1.52.4 release): make sure `just ghbin` ran from the final release commit and finished,
     and cancel any stale binaries runs, before pushing tags. In 1.52.4 the tag push did not actually trigger the
     workflow, and dispatching it needed the tag ref for a good tag_name: `gh workflow run release.yml --ref TAG`.
     Its notes come out empty (it passes refs/tags/TAG to ghrelnotes); fix with `just ghrel-notes`. Then review
     the draft and publish by hand: `gh release edit TAG --draft=false --latest`.
   - a good final check before publishing: download and unpack the archive for your own platform and run
     `./hledger --version` etc - it should show `VER-gHASH` matching the release tag's commit.
     (Use `--no-conf` if your personal config uses newer syntax than the release understands.)

### Phase 4: aftermath and announce

1. **(major release) main: activate website scripts/redirects:** `just site-restart`
1. **(major release) main: update dev version:** `just devver`
1. **main: update manuals:** `just manuals`
1. **main: update changelogs:** `just changelogs`; edit
1. **announce to matrix, irc, mail list, mastodon, forum, pta.o** ⚠
1. **(if this release fixes a previously-embargoed security issue)**
   - keep the GHSA draft private until the release is out and installable
   - publish the advisory once the fix has had a little time to propagate; don't gate on CVE grant, that's a separate
     async process that can take much longer
   - cross-link: relnotes/CHANGES entry → advisory, advisory → release tag/binaries
   - if an issue/PR had to be redacted when the bug was first (prematurely) disclosed, restore its original content
     once the advisory is published, and link it to the advisory. A published GHSA is already public and indexed
     (repo Security tab, github.com/advisories, OSV, scanners) regardless of what links to it, so redacting only
     helps for as long as the PR/issue contains materially more detail than the advisory does.


## Release artifacts reference

A detailed expansion of the release artifacts / value chain diagram above,
listing required artifacts, related commands, and gotchas.
This is reference material supporting the Release script above, not a step sequence -
if it conflicts with the script on step order or commands, the script wins.
Last updated: 2026-09

<!-- Trailing double spaces are used for line breaks -->

- **general**
  - when browser (Safari) refuses to show new content, use another

- **product**
  - blocking defects resolved
  - desired improvements landed and stabilised
  - building and passing tests with current ghcs, deps, and stackage snapshots
  - building and passing tests on all platforms / with all ghc versions  
        `just ghbin` (or push to github `binaries[-*]` branch)  
        `just oldest` (or push to github `oldest` branch)

- **product docs and metadata**
  - release branch
  - version strings (in **/.version, */.version.m4, */package.yaml)
  - cabal files x 4 (hledger*/hledger*.cabal)  
        `just relbranch VER`,  
        `just cabalfilestest`
  - options help texts up to date (in CliOptions.hs, UIOptions.hs, WebOptions.hs)  
        `stack build`  
        `./Shake cmddocs -c`
  - embedded manuals x 3
    - generaloptions macro (in doc/common.m4)  
          `just generaloptionshelp`
    - tool specific options in manuals (hledger*/hledger*.m4.md > # Options)
    - man page dates (*/.date.m4)
    - man  (hledger*/hledger*.1)
    - info (hledger*/hledger*.info)
    - text (hledger*/hledger*.txt)  
        `./Shake mandates`  
        `./Shake manuals -c`
  - embedded tldr pages synced with upstream (doc/tldr/*)  
        `just tldr-diff`
  - shell completions (hledger/shell-completion/hledger-completion.bash)  
        `just completions`, commit any changes
  - changelogs x 5 (*/CHANGES.md)  
        `just changelogs [-c]`  
        group the new/unreleased entries by topic, not by change type (Fixes/Features/Improvements) -
        choose topics appropriate to this release's actual changes, using the previous major release's
        topic headings as a starting point (not a fixed list); keep `## Breaking changes` and the
        trailing `## Docs`/`## Examples`/`## Scripts/addons`/`## API` sections as-is  
        add notable changes from site, finance repos to project changelog (major release only)  
        add issue links with `md-issue-refs`, uniquify  
        add author github nicks  
        `just changelogs-finalise`  

- **release docs and artifacts**
  - draft binaries building started  
      `just ghbin`
  - hledger.org html manuals x 3 (site/src/MAJORVER/\*.md) (major release only)  
        `just site-manuals-snapshot MAJORVER` to create/update  
        update `site/Makefile`, `site/js/site.js`, `site/hledger.org.caddy`
  - release notes @ hledger.org (doc/relnotes.md)  
      `just relnotes` *(XXX minor release: moves previous release's summary, adds whitespace)*  
      add summary (major release only)  
      add issue links with md-issue-refs  
      bump changelog links at the top  
      commit
  - github binary install docs (doc/ghrelnotes.md) up to date and pre-tested
  - Install page (site/src/install.md) up to date and pre-tested
  - draft announcement for chat, mail list, mastodon etc (doc/ANNOUNCE)
  - release tags  
      `just reltags`
  - release binaries built from tag  
      `just ghbin`,
      wait for all to succeed
  - Install page (site/src/install.md) --version examples match release binaries

- **published**
  - relevant release branch work cherry-picked to main branch  
      changelogs,
      relnotes,
      announcements
  - all packages uploaded correctly to hackage  
      `just hackageupload`
  - main branch pushed to github
  - new manuals published and rendering/redirecting correctly  
    - site repo pushed to github
    - main and site repos  auto-pulled to hledger.org, site rebuilt  
        `hledgerorgsh grep release.= /opt/hledger/site/out/js/site.js`  
    - <https://www.hledger.org/js/site.js> showing latest version  
        `curl -s https://hledger.org/js/site.js | grep release.=`  
        purge cache at <https://dash.cloudflare.com/f629035917dd3b99b1e37ae20c15ff09/hledger.org/caching/configuration> (major release only)
    - default manual urls redirecting to latest version (major release only)  
        `hledgerorgsh sh -c 'systemctl stop caddy; systemctl start caddy'`  
        `curl -sI https://hledger.org/hledger.html | grep location`
  - release branch pushed to github  
  - release tags pushed to github  
      `just reltags-push`
  - github draft release with release notes and binaries attached  
      `just ghrel` (in release branch)  
      <!-- (if downloads are throttled: `just ghbin-open`, download to tmp/, unzip the unix ones) -->  
  - github release published  
      decide if release should be immutable (artifacts attached, all correct ?) then adjust repo settings  
      review,
      `just ghrel-publish`
  - github nightly release updated *(XXX nightly release deleted, needs reviving)*  
      in main, update changes link in doc/ghnightlynotes.md
      `just nightlyrel-notes`  
  - install instructions tested and working
    - stack
    - cabal
    - source checkout
    - github release > How to install, each platform
  - announced
    - mail list(s) hledger@googlegroups.com for major (+ haskell-cafe@googlegroups.com for supermajor) 
    - matrix
    - irc
    - mastodon
    - pta forum

- **cleanup and support**
  - review/polish/sync changelogs & relnotes
  - new version, man dates, dev tag in main (major version only)  
    `j devtag-push`
  - RELEASING.md checklist/notes updated
  - monitor/support/handle issues:
    [issue tracker](https://github.com/hledgerorg/hledger/issues?q=is%3Aopen+is%3Aissue), matrix, irc, mail list, forum, reddit

Some more good things to do after a release:

  - hledger.org site/doc updates
  - hledger_finance repo updates
  - plaintextaccounting site updates (eg project stats)

## How to..

More procedure notes.

### Check release readiness

- Any blocking open issues ? <https://bugs.hledger.org>
- Any blocking open PRs ? <https://prs.hledger.org>
- Any blocking items on <https://hledger.org/ROADMAP.html> ?
- Any blocking items in personal notes & backlogs ?

### Check tools are up to date
- Check for consistent stackage snapshot(s) and extra deps used in
  stack.yaml, Shake.hs, hledger-install.sh, bin scripts, tools scripts
- Shake binary is up to date
  `./Shake.hs`
- `hpack --version` matches the one in `stack --version`

### Run local tests
- `just test`
- `just doctest`
- `just haddocktest`
- `just anchortest` (checks the manuals' internal links)

### Run CI tests
- push to a PR, wait for green
- or push to `ci` branch, wait for green at <https://ci.hledger.org>
- or `just push` (pushes to `ci`, then to `main`)

### Run release branch tests
- `just test`
- `stack exec -- hledger --version`, check version, hash, release date, no '+'
- `stack exec -- hledger help | tail`, check version, month matches release

### Update the Install page
- `just installpage [NEWVER]` updates the mechanical version references in `site/src/install.md`
  (the current release line, release binaries badge/link, git checkout examples),
  marks still-outdated packaged-version badges red,
  and lists any remaining old-version occurrences for review.
- then by hand:
  - only after release binaries are built (preferably after release is published):
    update --version outputs (version, hash, date, but not platform)
  - final output line from `hledger test` (run local build and in terminal for normal speed)
  - Total count from `make functest`
  - preview
  - commit: `install: NEW`

### Update hledger in stackage

- monitor packaging status in lts and nightly: <https://www.stackage.org/package/hledger>
- update <https://github.com/fpco/stackage/blob/main/build-constraints.yaml> as needed

### Update RELEASING.png
- edit RELEASING.canvas in obsidian
- CMD-p > Export as image, don't show logo
- commit

## Tips

- Release, or practice releasing, often to improve the process.

- Use and continually update RELEASING.md.
  Document procedures and gotchas to save time and enable automation in future.

- Also the diagram (RELEASING.canvas, made with Obsidian).

- But don't document prematurely or in too much detail.

- Make things a little better each time through: simpler, more reliable, better documented, more automated, easier, faster, cheaper, higher quality.

- Optionally save this file as RELEASING2.md and update notes there until after release, if it's interfering with git branch switching.

- Use and update scripts, in `Justfile`, `Shake.hs`, `tools/` etc.

- Do all releases from a release branch.

- Update dev changelogs frequently in main - ideally every few weeks, or after each big merge -
  so that each drafting/polishing session stays small and duplicates are rare.
  Run `just changelogs`, polish the drafts (see the changelogs skill), and check with `just changelogs-check`.
  Finalise changelogs in the release branch. Merge back to main after release.

- All release binaries should be built from the release-tagged commit.
  The binaries' --version output should match the release tag and release date.

- Try to do only full releases including all four main hledger packages; partial releases add complexity.

- Try to avoid pre-announcing a hard release date. 
  It will always take more time than you think,
  if you go late you might miss your intended date in many timezones,
  and there's no point adding unnecessary pressure.

- The biggest potential time sinks are:

  - reviewing/relearning the process/docs/infrastructure
  - updating/improving the process/docs/infrastructure
  - preparing changelogs
  - building binaries for all platforms
  - troubleshooting github workflow issues
  - followup work due to release mistakes, bugs in new features, or regressions

- Hard/risky/intensive tasks should happen without time pressure;
  during the final countdown, things should be easy.

## Release manager activities

These have complex interdependencies and sequencing constraints.
Chunk, separate, routinise, document and automate them as far as possible.

|                       |                                                                                                                                                            |
|-----------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------|
| **Software**          | selecting changes, packages, release dates; coordinating contributions; ensuring release readiness                                                         |
| **Branch Management** | coordinating main and release branch, local and remote repos, CI branches                                                                                  |
| **Version Bumping**   | choosing and applying new version numbers and related things like tags, github releases, urls, ghc and dep versions, stackage resolvers, everywhere needed |
| **Docs**              | command help, manuals, changelogs, release notes, github release notes, install page, install scripts, announcements, process docs                         |
| **Testing**           | local testing, CI testing, extra release-specific testing                                                                                                  |
| **Artifacts**         | generating binaries, zip files, github releases etc.                                                                                                       |
| **Publishing**        | uploading, pushing, making visible, finalising                                                                                                             |
| **Announcing**        | various announcement stages and channels                                                                                                                   |

## Glossary

Some standard terminology, useful when precision is needed, eg in release scripts.

### General

**release**\
A snapshot of the software and related artifacts like executable binaries, which is named, tagged, documented, announced, and usually picked up by packaging systems on various platforms.

**version control system, VCS**\
A tool used for storing and sharing and viewing the history and different lines of development of a software project, or other set of files. hledger uses Git.

**repository, repo**\
A set of files being stored and managed by a VCS. Often published on a **repository hosting service**, such as Github.

**working copy, clone**\
A local copy of a repository's files. Typically each developer has one or more of these, and can share changes easily with the official public repository.

**branch**\
Some VCS's, including Git, can store multiple branching lines of development within one repository. A working copy can be quickly switched to a different branch to show its content.

**main**\
The main branch in a repo, usually named `main` or `master`. Pull requests are usually relative to this.

**pull request, PR**\
A request to merge a development branch with main, and any related discussion. On Github, these are kept alongside issues in the issue tracker.

**continuous integration, CI**\
Automated actions that run when new code is pushed to a shared repo, such as running tests or producing binaries. On Github this is called Github Actions and action scripts are called **workflows**.

**release engineering**\
<https://en.wikipedia.org/wiki/Release_engineering>

### hledger-specific

**package**\
A releasable unit of Haskell software. hledger has several core packages usually released together: hledger-lib, hledger, hledger-ui, hledger-web.

**hledger version number**\
A 2-4 part dotted number naming a hledger release or hledger package version: `MA.JOR[.MINOR[.FIXUP]]` or `MA.JOR.99[.PREVIEW]` where 99 means "unreleased (MAJOR+1)". See examples below.

**hledger version string**\
A line of text describing a hledger binary, shown by `--version`. It contains program name, version number, commit hash and date, machine architecture etc. Eg: `hledger 1.24.1-g7799d526b-20211210, mac-x86_64`

**Full release**\
A release of all four core hledger packages (hledger-lib, hledger, hledger-ui, hledger-web). Major and preview releases are always full releases.

**Partial release**\
A release of just some of the hledger packages. Bugfix and fixup releases are sometimes partial.

**Single-version release**\
A release where all packages have the same version. Major and preview releases are always single-version.

**Mixed-version release**\
A release where the packages have different versions, because of a previous partial release. Bugfix and fixup releases are sometimes mixed-version.

**changelog**\
A CHANGES.md file listing the release history and the changes in each release. There is one for each hledger package and one for the hledger project as a whole.

**release notes**\
The Release Notes page on the hledger website: the combined release history of the core hledger packages, showing user visible changes only.

### Releases and builds

**Major release**\
Major releases include new features and incompatible API changes, and normally happen at the start of each quarter's third month (3/1, 6/1, 9/1, 12/1). Example version number: `1.25`

**Bugfix release**\
Bugfix releases include only bug fixes, without API changes. These happen when needed, to fix significant bugs in the previous major release. Example version number: `1.25.2` (**"second bugfix release for 1.25"**)

**Fixup release**\
Fixup releases fix packaging errors, with no changes to the hledger software. Example version number: `1.25.0.1` or `1.25.2.1` (**"first fixup release for 1.25 / 1.25.2"**).
These should rare; we basically never do these.

**Preview release**\
A preview of the upcoming major release for testers/early adopters, and a test of the release process, published on Github. Not a formal hledger release, eg not published on Hackage, usually not packaged, no bugfix releases, no regression bounties, not shown in release notes. These typically appear in the quarter's first and second month if needed. Example version number: `1.25.99.1` (**"preview 1 of 1.26"**)

**CI binaries**\
Temporary downloadable binaries produced by a run of the `linux`/`mac`/`windows` workflows in the hledger repo. This may happen periodically, eg weekly. Downloading requires a Github login.

**Dev build**\
A local developer build of unreleased code. This is typically in `main` or a development/PR branch. Example version number: `1.25.99` (**"unreleased 1.26-dev"**)

### Repos and branches

**hledger repo**\
The `hledger` git repository, containing the hledger software, reference manuals, and developer docs. <https://github.com/hledgerorg/hledger>

**site repo**\
The `hledger_website` git repository, containing most of the hledger website which appears at <https://hledger.org>. Usually checked out under the hledger repo as `site/`. <https://github.com/hledgerorg/hledger_website>

**finance repo**\
The `hledger_finance` git repository, containing the hledger project's financial ledger. Usually checked out under the hledger repo as `finance/`. <https://github.com/hledgerorg/hledger_finance>

**main**\
The branch named `main` in the hledger repo; the main line of hledger development. Pull requests are usually relative to this.

**release&nbsp;branch**\
Branches named `MA.JOR-branch` in the hledger repo, eg `1.25-branch`. Releases and release previews are always made from a release branch.


