<!--
                 _           _
 _ __  _ __ ___ (_) ___  ___| |_
| '_ \| '__/ _ \| |/ _ \/ __| __|
| |_) | | | (_) | |  __/ (__| |_
| .__/|_|  \___// |\___|\___|\__|
|_|           |__/

## Docs

## Website

## Tools/infrastructure

## AI usage

-->

General changes in the hledger project.
For package-specific changes, see the hledger package changelogs.


# 1.99.4 2026-09-10

- The hledger repo has moved to the hledgerorg github
  organisation: <https://github.com/hledgerorg/hledger>. Old
  links redirect. [#2681]

## Docs

- ai.journal: updates
- RELEASING: revise release script with lessons from the 1.52.2 release
- AI: allow maintainer-discretion exceptions for hledger 1.x security fixes
- ai.journal: switch to simpler t/kt/Mt output-token units; import June/July usage; other edits
- AI: various edits and clarifications (extra usage notes, policy reference links)
- ANNOUNCE: edits
- CHANGELOGS: retired; superseded by RELEASING and changelogs/SKILL.md
- CONTRIBUTING: added a developer quick start; fixed test and benchmark links [#2528]
- CREDITS, .mailmap: various edits (headings, alignment, stats table; consolidated Alex Chen's commits; tidied committer names)
- DECISIONS: updates
- DEVFAQ, DEVWORKFLOWS, TESTS and other dev docs: updated for current tools, scripts and test suites; removed dead links; DEVFAQ now defers to install.md for build instructions [#2528]
- examples/lots: merge and refresh the roi-vs-holdings comparison notes; cross-reference lots.journal and irr.journal
- FUNDING: updated links
- ghrelnotes: note the updated Windows binary; fix the eget command
- hledger.conf.sample: edits
- html: document builtin styling in the manual; sample hledger.css now demonstrates customising it
- PULLREQUESTS, pull request template: many edits; link to the AI policy; first-time contributors' PRs may no longer use AI tools
- REGRESSIONS: discontinue the regression bounties; other edits
- release notes: fixed and simplified the binary install instructions - the mac/linux install command was discarding its download [#2707], and the windows command now installs to a directory that can be on PATH; also noted what the install command needs, and updated the eget repo path
- relnotes/changelog: AI usage section edits; fix a link
- RELEASING: edits; consolidated to a single release script, grouped into phases
- RULES: new doc gathering repo policies, old and new, in one place
- SPEC-holdings: record decisions (future-dated postings stay included by default; XIRR's final cashflow is the displayed Value at the report date)
- SPEC-lots: add a roadmap section for future work (per-account lot-tracking opt-out, tax boundary declarations, AVERAGE vs transfers, non-local-method coherence checks)
- STYLE: new hledger-web doc recording the rules a change to the web UI's appearance should follow (no build step, nothing from a third party, no style attributes, how tabular and monetary data should read), for people and coding agents alike

- examples: added lots/average.journal
- README: dropped the gitscope.dev badges; that service is gone

## Tools/infrastructure

- Changelog tooling improved: `just changelogs` now pre-cleans changelogs items (routine commits dropped, AI usage lines stripped, breaking changes lifted to the top, possible duplicates flagged); a stale resume point (eg after a rebase) is detected and reported with its fix; and a new `just changelogs-check` verifies resume points, issue links and leftover draft markers. Changelog section headings are simplified: Security, then Breaking changes, then topic or generic headings as needed.
- CI: binaries-mac-arm64-hx, an experimental workflow using the hx build tool (an alternative to stack/cabal, for easier reproducible builds); cache the official cabal binary; build with -O1
- CI: bump most third-party actions to their latest major version; binaries-mac-arm64 bumped to macos-26-arm64; binaries-mac-x64 lists dependency versions like the others
- CI: the addon functional tests now run again (they had been accidentally excluded since 2017)
- CI: the hledger-web browser tests now run on pull requests, as a non-blocking check
- .gitignore, .ignore: stop tracking site/ under git entirely, but keep site/src/*.md (and the old manuals) visible to ripgrep/VS Code search via a new .ignore file
- hledger-web: added an on-demand Playwright browser test suite covering the web UI's client-side behaviour, runnable with `just browsertest`
- hledger-web: the favicon's vector sources and the standard-library script that regenerates the .ico from them are now committed, so the mark can be edited rather than redrawn
- Justfile: various `just ai-*` AI-usage-reporting recipe tweaks; `just holdings-*` recipes for trying the holdings command against hledger/beancount/rledger example data; `just installrel`, `just contribs*` fixes; gitignore .hx; experimental hx build tool config
- Release automation improved: `just ghrel` now assembles the github release on github (no local round trip for binaries) and creates it as a draft, with `just ghrel-publish` making it public after review; `just installpage` automates Install page version bumps; `just generaloptionshelp` automates updating the general options help in the manuals; and the relbranch, reltags-push and ghbin-download recipes are more robust
- Shake: changelogs: capitalise multi-line items' first lines and give them a trailing period, so they read as complete sentences; single-line items are left as written
- skills: add binary-badges skill, checking/refreshing the version badges in site/src/install.md; fix its red badge colour to match repology's hex
- skills: add release skill for assisting hledger releases
- skills: the changelogs skill was missing its YAML frontmatter, so it had no useful name or description to be matched against
- stack/cabal: ensure haskeline 0.8.4.1 is used, fixing the Windows build again [#2410]
- tools/aicommits: new script (plus `just ai-commits*` recipes) to report AI usage parsed from commit messages' "AI usage:" trailers
- tools/skills: add a credits skill documenting the CREDITS.md refresh process


[#2410]: https://github.com/hledgerorg/hledger/issues/2410
[#2528]: https://github.com/hledgerorg/hledger/issues/2528
[#2681]: https://github.com/hledgerorg/hledger/issues/2681
[#2707]: https://github.com/hledgerorg/hledger/issues/2707

- Shake changelogs: resume points rewritten by rebase/amend are now
  auto-relocated (matching author date/author/subject), instead of
  re-listing already-drafted commits; changelogs-catchup is rarely
  needed now.


# 1.52.4 2026-09-10

Doc updates

- Github release install instructions have been fixed and simplified. [#2707]

[#2707]: https://github.com/hledgerorg/hledger/issues/2707

Software

- New layout type `barewide`. [#2691]

[#2691]: https://github.com/hledgerorg/hledger/pull/2691


# 1.52.3 2026-08-27



# 1.52.2 2026-08-24



# 1.99.3 2026-06-24

## AI usage

hledger 2.x releases use careful AI-assisted development.
(If you want to use software built without any help from AI tools, choose hledger 1.x instead.)
All changes were steered, reviewed, and tested by Simon or a contributor.
See <https://hledger.org/AI.html> for our current AI policy and rationale.

For 1.99.3, mostly opus 4.7 was used. My reporting methods have
changed since last time; here's my current rough estimate of tokens
used per month:

```
            output tokens  release
 Jan       ||       771 || 
 Feb       ||    53,229 || 
 Mar       ||   112,112 || 1.99.1
 Apr       ||   686,507 || 1.99.2
 May       || 2,680,593 || 
 Jun       ||   737,780 || 1.99.3

   Total   || 4,270,992 || 
 Average   ||   711,832 || 
```

## Docs

- Install: add Building outside the source tree
- AI policy/FAQ/journal: updates, links; start journalling estimated project AI usage
- SPEC-lots: align with the user manual's restructure of Lot reporting
- PLAN-commodity-preferred-symbols, PLAN-ugain
- ACHIEVEMENTS: better star-history link, top 10 apps
- PULLREQUESTS: cross-link to COMMITS and AI
- REGRESSIONS: [#2642]
- RELEASING, ANNOUNCE, relnotes updates

## Tools/infrastructure

- tools/relnotes: demote any markdown headings in changelogs, to fit in release notes
- tools: Shake changelogs: parse inter-release headings more carefully
- tools: just hackagerevise
- cabal.project: consolidate workarounds (haskeline Windows bug [#2410], yesod-static bounds bug); general cleanup
- stack: bump dev/release builds and scripts to nightly-2026-06-01 [#2410]
- stack: ignore all bounds, for now, to allow building with aeson 2.3
- ci: fix old references to `master` in workflows
- ci: linux binaries: more workarounds for dependency/bounds bugs
- pr template: update, mention the AI policy
- `just ai*` usage report scripts: vertical output by default; easy conversion from opus tokens to t/kt/Mt
- `tools/regen-shelltests.py` script, `regen-shelltests` claude code skill
- `just devver`: fix
- gitignore updates


[#2410]: https://github.com/hledgerorg/hledger/issues/2410
[#2636]: https://github.com/hledgerorg/hledger/issues/2636
[#2642]: https://github.com/hledgerorg/hledger/issues/2642


# 1.99.2 2026-04-28

Doc updates

- AI: ongoing edits, new monitoring scripts and notes, FOSS credit, link cleanups
- ACHIEVEMENTS, ANNOUNCE, DECISIONS, DEVFAQ, README, RELEASING: edits
- SPEC-lots: edits and cleanups
- SPEC-special-postings: converted to markdown tables
- relnotes/ghrelnotes: AI doc url fixes, edits
- references to the master branch updated to main

Infrastructure/tools

- stack configs: bumped to nightly-2026-04-17
- workflows: fix stack.yaml path in binaries-windows
- justfile: ccusage scripts
- justfile: functest uses more threads
- general --help options doc updated

# 1.52.1 2026-04-28

# 1.99.1 2026-03-28

(2.0 preview 1)

Doc updates

- site: upgrade to latest mdbook
- site: move pages' tables of contents to sidebar
- AI: new project AI policy doc, with links and discussion notes
- IMPACT: new project "external impacts" doc
- README(hledger2 branch): describe the 2.x branch and plans
- REGRESSIONS
- SPEC-lots: specification for lot-related functionality, lot subaccount parsing technique, balance assertions
- SPEC-finalising: retroactive specification for journal finalising
- SPEC-print: document some print behaviours as a specification
- SPEC-special-postings: document patterns of postings recognised by hledger
- PLAN-lots: planning and design notes from implementing SPEC-lots

Infrastructure/tools

- Shake: fix build error with GHC 9.12.2 by using newer shake
- `just devtag-push` renamed to `just devver`
- stack configs: 9.14 made default, 9.12 made non-default, both cleaned up and bumped


# 1.52 2026-03-20

Doc updates

- ACHIEVEMENTS, ANNOUNCE, README, REGRESSIONS, RELEASING
- Github issue template improvements

Infrastructure/tools

- fix URLs in github test binaries release doc
- github issue templates updated
- Justfile scripts
  - specify and require (newish) bash as default shell [#2527]
  - depend less on ghc in PATH
  - add compile.sh to build Haskell scripts
  - just ghrel-bin-upload -> ghrel-upload, fix
  - just google-search-console
  - just perfhelp (Simon Michael, Marko Kocić)
  - just perftest
  - just test: run doctests last to reduce double compilation (Marko Kocić) [#2528]
  - just tools
  - replace gsed with sed (Marko Kocić)
- github workflows
  - binaries-windows: update for new GHC
  - binaries-linux: caching, cleanup improvements
  - nightly -> testbin
  - ensure linux binary uses fixed haskeline [#2410]
  - testbin: update, use testlatest tag / testbin branch

[#2410]: https://github.com/hledgerorg/hledger/issues/2410
[#2497]: https://github.com/hledgerorg/hledger/issues/2497
[#2527]: https://github.com/hledgerorg/hledger/issues/2527
[#2528]: https://github.com/hledgerorg/hledger/issues/2528


# 1.51.2 2026-01-08

# 1.51.1 2025-12-08

# 1.50.5 2025-12-08

# 1.51 2025-12-05

Docs updated

- ACHIEVEMENTS
- ANNOUNCE.short
- AUTHORS
- bin/README
- CHANGES.md: move to doc/ for consistent paths
- Contributing: mention translation (Lý Minh Nhật)
- DECISIONS
- dev
- DOCS: document & diagram latest doc update procedures
- ISSUES
- REGRESSIONS
- RELEASING
- relnotes: more reliable changelog links
- ROADMAP
- tldr/README

Infrastructure/Misc

- bump stack snapshots
- Dockerfile fixed (probably)
- drop the hledger-install script
- just changelogs* update
- just docupdatediag
- just ghci-ui: :main (and :rmain) now works again
- just ghnightly* -> nightly*
- just oldest
- just perftest: run performance tests, logged to perf.log
- just releasediag update
- just rels-major
- just site-restart
- just: devtag-push: simplify
- just: ghrel-bin-upload
- just: manuals, manuals-site
- just: reltags: cleanup
- just: ver, majorver
- Justfile: less safari dependence
- Justfile reorg, cleanups
- release script updates
- Shake: drop mandates target, update manual dates automatically
- Shake manuals: more contributor instructions in the header comment [hledger_site#140]
- stack92: add valid hashtables version
- stack94: add valid hashtables version
- stack96: add valid hashtables version 
- stack98: include valid hashtables version
- stack98: restore needed encoding 0.10 extra dep
- stop git ignoring site/src/, allowing web docs to be easily opened in vscode
- tools/relnotes.hs update
- use a nightly branch instead of a nightly tag on github, it's simpler
- workflows: use shelltestrunner 1.11
- workflows:binaries-mac-x64: switch to macos-15-intel


# 1.50.4 2025-12-04

# 1.50.3 2025-11-18

# 1.50.2 2025-09-26

# 1.50.1 2025-09-16

# 1.50 2025-09-03

Doc updates

- FINANCE
- ISSUES
- REGRESSIONS
- RELEASING
- SCHEDULE & `just schedule` script

Website

- fix the "edit this page" link
- redirects: handle more old pages; fix some old redirects to #FMT-format; stop redirecting /timeclock, /timedot, /timedot.html
- set up a github issue template clarifying this repo's scope
- shortcut urls: release.hledger.org, nightly.hledger.org, regressions.hledger.org; readyprs.hledger.org excludes PRs with needs-* labels
- sidebar: reorganise
- sidebar: leave all links visible to avoid popping
- sidebar: avoid duplicate links, they're no longer allowed
- sidebar: link to the current release's manuals, not the dev version's
- Beancount: edits, new conversion tips
- Docs: consolidate all user docs onto a single Docs page
- Editors: more vs code extensions, more emacs calc notes
- Export: updates
- FAQ: updates
- Hledger By Example: start a new progressive "book", with 18 pages
- Home: new, shorter home page content
- Home: show a quote/testimonial, updating on the hour
- Investments: fix link (#2436)
- Invoicing: fix kairos link
- Ledger: edits
- Tutorial: hledger basics -> to Tutorial: hledger add

Infrastructure/Misc

- hledger now requires at least GHC 9.6 (and base 4.18), to ease maintenance.
- bump default build, tools to lts 24.8 / ghc 9.10.2
- docker: sync Docker GHC version with Stack configuration, update dependencies, and replace deprecated Dockerfile syntax. (Lukas Fleischer)
- github workflows improvements
- tool updates: checkembeddedfiles, devtag, nightly-push, nightlytag, relver, test
- update github issue templates


# 1.43.2 2025-06-13


# 1.43.1 2025-06-04

- tools:
  - Shake changelogs: fix missing blank lines around old heading
  - ghcruns-download: make tmp dir
- docs:
  RELEASING


# 1.43 2025-06-01

Docs

- Updated:
  FILES,
  FINANCE,
  ISSUES,
  PULLREQUESTS,
  REGRESSIONS,
  RELEASING,
  ghrelnotes,
  relnotes

Infrastructure/Misc

- issue labels updates, `severity*` -> `annoyance*`, `impact*` -> `affects*`
- new shortcut urls: assignedprs.hledger.org, unassignedprs.hledger.org
- clean up LICENSE files, main module licensing headers, add AUTHORS.md, try to fix github license detection
- cabal files now specify GPLv3+ exactly. [#2359]
- building the hledger packages now requires at least Cabal 2.2+ or stack built with Cabal 2.2+ (was 1.12+).
- avoid a ghci warning if :rmain is defined in user's config.
- simplify stack yaml file names
- workflows updates:
  - binaries\*: simplify, cleanup
  - binaries-linux-x64: install ghcup only if not cached; fix cache
  - windows: use preinstalled stack
  - docker: draft of a docker image build/publish workflow (Doug Goldstein, [#2002])
  - nightly: adds latest binaries to the "nightly" release
- tools updated:
  binaries,
  devtag-push,
  ghnightly,
  ghnightly-bin,
  ghnightlynotes-push,
  ghrel,
  ghrelease-upload,
  ghrelnotes-push,
  ghrun,
  ghrun-id,
  ghrun-open,
  ghruns,
  ghruns-download,
  ghruns-open,
  hackageupload,
  nightly,
  nightlybin,
  nightlytag


# 1.42.2 2025-05-16

Docs

- relnotes: fix links to hackage changelogs


# 1.42.1 2025-03-12

Infrastructure/Misc

- Tools updates

- Fix cabalfilestest: test all cabal files before any hackage upload.


# 1.42 2025-03-07

Infrastructure/Misc

- Unix bindists in github releases now include the man pages and info manuals. [#2309]

- Unix bindists in github releases are now normal .tar.gz files, without the extra zip compression. [#2299]

- Release notes and install instructions in github releases are now collapsed by default again.
  This makes the sequence of dates and releases clearer.
  Github automatically expands the assets of the latest release, so those will be visible by default.
  For a full text search of all release notes, use the https://hledger.org/relnotes.html page.

- hledger-install: if installing third party packages fails, it now tries again with bounds relaxed.
  This makes hledger-iadd and hledger-interest more likely to install successfully,
  even if their bounds have not yet been updated for a new hledger release.

- just functest now fails if there are warnings.
  (It does not force recompilation of already compiled modules,
  but even so this should help catch more warnings before pushing them to CI.)

- new/changed recipes/tools:
  bench*.sh,
  changelogs-catchup,
  changelogs-finalise,
  changelogs-reset,
  devtag,
  ghrelnotes,
  ghrelnotes-publish,
  log-headtail, 
  log-push,
  log-save, 
  modulediag,
  modulediags,
  modulediags-view,
  packagediags,
  packagediags-view,
  releasediag,
  relnotes
  relprep -> relbranch,
  reltags,
  reltags-push,
  showrelnotes,
  site-manuals-snapshot,
  site-watch,
  time,
  tldr-diff

- gitignore cleanups.


# 1.41 2024-12-09

Docs

- REGRESSIONS: new table format; updates.
- CODE: notes on the use of haddock [#2222]
- Simplify github bug report template
- Add man pages and info manuals to the release bindists on github

Scripts/addons

- Fixed build errors in all bin/ scripts. (Dmitry Astapov)
- hledger-install: fix installation of hledger-ui

Infrastructure/Misc

- GHC 9.10 is now the default for dev builds and most github workflows.
- Add consistent greppable summaries to all workflows; various other improvements
- Add bash shell completion script to the release bindists ([#2223], gesh/hseg, Simon Michael)
- tools/gtree: -u shows untracked files, -I adds ignored files.
- just doctest: pass through doctest arg(s).


# 1.40 2024-09-09

Docs

- In the hledger 1.29 release notes, Date adjustments has had some corrections.
- Github release notes template cleanups; fix mac, linux install commands.
- README: fixed contributors link.
- RELEASING: updates

Scripts/addons

- hledger-install: cleanups, bump versions, perhaps fix hledger-interest install
- hledger-install: clarify some stack/cabal setup messages

Infrastructure/Misc

- Shake.hs: fix partial warnings
- Shake cmdhelp: renamed to cmddocs, and it now also updates the options
  listed in the manuals, and shows progress output.  It should be run (at
  some point) after changing commands' docs or options.
- Shake txtmanuals: silence all but wide table warnings
- just file cleanups; update to support just 1.28+
- just twih: date fixes
- just ghci: -fobject-code was a mistake, keep everything interpreted
- just functest: try again to reduce rebuilding/slowdowns when testing
- just installrel: update for .tar.gz
- ci scripts: cleanup, fix a macos-ism


# 1.34 2024-06-01

Docs

- move release notes from the hledger_site repo to the main hledger repo
- github release notes: show the release notes, hide the install instructions by default
- github release notes: improve windows install commands
- github release notes: start mentioning github usernames, enabling the Contributors avatar list
- dev docs: new Developer FAQ, Contributor Quick Start updates

Scripts/addons

- `hledger-install.sh` now uses stackage nightly, and a failure on non-Windows platforms has been fixed.

Infrastructure/misc

- A new `release` workflow creates github releases, uploads release binaries and generates release notes.
- There is a new `oldest` workflow for testing the oldest GHC we support (currently 8.10.7).
- The `binaries-mac-x64` workflow has been bumped from GHC 9.4 to 9.8.
- The main branch's `ci` workflow has been updated to Ubuntu 24.04
  and uses the preinstalled GHC & stack, saving some work.
- `md-issue-refs` helps generate markdown issue links.
- `relnotes.hs` helps generate release notes from changelogs.
- The project `Makefile` has now been fully replaced by `Justfile`.


# 1.33 2024-04-18

Misc

- Apple ARM binaries are now included in github releases.

Docs

- REGRESSIONS: we now split the bounty between finder and fixer
- move Developer docs, MOCKUPS, investment-accounting-features to main repo
- merge LINKS into dev docs page; cleanup
- drop unused BACKLOG, TODO pages


# 1.32.3 2024-01-28

Scripts/addons

- bin/hledger-bar: Fix an error when NO_COLOR is not defined;
  allow color when NO_COLOR is defined but empty, per no-color spec;
  and fix shellcheck warnings.
  [#2159] (Colin Dean, Simon Michael)

- bin/hledger-simplebal: Fix shellcheck warnings. (Colin Dean)

[#2159]: https://github.com/hledgerorg/hledger/issues/2159

# 1.32.2 2023-12-31

Docs

- Added: 

- Updated: ISSUES.md, REGRESSIONS.md

- WORKFLOWS.md is renamed to DEVWORKFLOWS.md to avoid a name clash.

Examples

- New CSV rules examples for Wise, ING, Venmo, PayPal, FHB, N26, Triodos (Ilja Kocken) 

Scripts/addons

Infrastructure

- Project scripts in `Makefile` and `bake` have been converted to a `Justfile`.
  After many years using `make` and shell for scripting, I find `just`
  better enough, and the goal of clean consolidated efficient project
  automation so valuable, that we will use it in the hledger project
  even though it usually is not installed by default.

- The `.mailmap` file has been updated to clean up committer info in git output.

- `tools/generatejournal` can now be run as a script.

- The "new issue" and "new PR" templates have had some cleanup.

- There are some new issue tracker labels intended for use with a new 
  ISSUES.md > Prioritising scheme, and a few issues using them.

# 1.32 2023-12-01

Scripts/addons

- hledger-install.sh: replaced hledger-stockquotes with pricehist

- added gsheet-csv.hs: fetch a google sheet as CSV

- added hledger-report1: an example custom compound report, with haskell and bash versions

- justfile: updated import, time report scripts


Examples

- New:

  - Fidelity CSV rules

- Updated:

  - roi-unrealised.ledger (Charlie Ambrose)

Docs

- New:

  - Started a weekly This Week In Hledger news post, inspired by Matrix.
  - There's now a News page, for This Week In Hledger etc.
  - hledgermatic, an up-to-date, simple journal-first workflow
  - How to record journal entries: added
  - Reporting version control stats: added
  - Moved regression bounty info from the issue tracker to Developer docs > REGRESSIONS.

- Updated:

  - Checking for errors
  - Common workflows
  - Ledger
  - Simon's old setup
  - Videos
  - All docs now use the `cli` class instead of `shell` for command-line examples,
    avoiding inaccurate highlighting.


Infrastructure

- hledger.org website:

  - Fixed the webhook that was not updating the site on git push.
  
  - Fixed a problem with cloudflare authentication that was preventing
    automatic TLS certificate renewal on hledger.org.
  
  - Updated and committed hledger.org's caddy config and short urls (redirects)
  
  - Enabled https for code.hledger.org and site.hledger.org short urls.

  - Updated the stars.hledger.org redirect
    (we have reached the top 30 github-starred Haskell projects 🌟 🎉).
  
  - Set up a self-hosted Sandstorm server, and a public hledger-web
    instance (sandbox.hledger.org) in it that is fully writable (until
    spammers find it). Use it as a pastebin for examples, eg.

- Github CI (continuous integration) workflows have been optimised somewhat:

  - Scheduled weekly builds have been disabled, as they were propagating
    to forks and running wastefully there in some cases.

  - Some repeated rebuilding of the hledger-lib and hledger packages
    that seems unnecessary has been stopped.

  - hledger-ui no longer builds its modules twice.

  - Haddock testing now done only at release time.
  
  - renamed main CI workflow and branch to "ci"

- Tools:

  - .ghci: added an :rmain alias, which is like :main but reloads first -
  saves typing, and is useful eg when changing --debug level.

  - make haddock-watch is now fast


Finance

- Updated project finance scripts, regenerated the journal with consistent precisions.
  
- Updated reports with the last few months of data from Open Collective.


# 1.31 2023-09-03

Scripts/addons

- ft, tt shell scripts for collecting financial and time reports

- A justfile implementation of ft and tt

Examples

- self-tracking

- RPG ledger (Eric Mertens)

Docs

Infrastructure

- tools, CI: checkembeddedfiles, checkversions

- Shake: avoid making empty commits

- make functest-PAT: runs a subset of functional tests

- Provide a ghc-tags.yaml file to make use of ghc-tags with Hledger easy.

  ghc-tags is a standalone tool to replace the formerly-built-in
  ":ctags" feature (and I presume ":etags") in GHCi. These walked over
  the source and produced a TAGS file (in vim-compatible ctags or
  Emacs-compatible etags format) that allows the relevant editors to
  quickly navigate around function definitions.

  ghc-tags trips over some of the CPP used in Hledger. The solution
  is to provide ghc-tags with explicit CPP defines via a YAML file.
  However, if a YAML file is provided, one also must specify the source
  paths, as the tool XORs config file | paths-on-command-line.

  See <https://github.com/arybczak/ghc-tags/issues/6> for more
  information.
  (Jonathan Dowland)

# 1.30 2023-06-01

Scripts/addons

- hledger-bar: new script for making simple bar charts in the terminal

- hledger-install: also list cabal, stack, pip tool versions

Examples

- examples/csv: added a more up-to-date CSV makefile

- examples/i18: Added sample top level account and type declarations in several languages

Docs

- A shorter, more example-heavy home page on the website.

- Simplified website and FAQ structure.

# 1.29.2 2023-04-07

Scripts/addons

- hledger-install: re-enable hledger-interest, hledger-iadd; add hledger-lots

# 1.29.1 2023-03-16

Scripts/addons

- hledger-install: slight output cleanups

Docs

Infrastructure

- RELEASING: new release process diagram
- update hie.yaml so HLS uses GHC 9.4

# 1.29 2023-03-11

Scripts/addons

- hledger-script-example.hs: rename/cleanup
- sortandmergepostings: new, sorts postings and merges duplicates (Caleb Maclennan, Murukesh Mohanan)
- hledger-register-max: new, prints the posting with largest historical balance
- hledger-git: record shows better error output, no longer force-adds ignored files
- hledger-git: status is fixed, also shows diffs
- hledger-git: add short command aliases r, s, l
- hledger-git: -h is fixed
- hledger-git: pass unrecognised commands to git
- hledger-install: also install hledger-edit, hledger-plot
- hledger-install: add support for installing python packages
- hledger-install: show quieter stack/cabal output
- hledger-install: align install status list
- hledger-install: don't list hledger-install.sh in PATH
- hledger-install: drop hledger-iadd for now  https://github.com/hpdeifel/hledger-iadd/issues/71

Docs

- move most dev docs to doc/
- Scripting hledger: move plugin types table here
- Scripts: add hledger-plot, hledger-edit, hledger-fifo (Yann Büchau, Simon Michael)
- update lots mockups, move to Mockups page
- split Contributor Guide into Contributor Quick Start, LINKS, ISSUES
- add REPOS, FILES, DECISIONS
- CREDITS: updates, link to github contributors list

Infrastructure

- pr template: mention COMMITS page and prefix convention (#1997)
- make ghc 9.4 and current stackage nightly the default for dev builds
- require megaparsec 9.3+ in dev builds, for its useful dbg tool
- make site-watch: fix runaway recursion, be more verbose
- new make rules: man-watch
- new tools: ciwatch, push, pushdocs, gtree
- misc process updates

# 1.28 2022-12-01

Docs

- Miscellaneous improvements.

Examples

- Indian National Pension Service CSV rules (Pranesh Prakash)

Infrastructure

- make site-watch: switch from entr to watchexec.

- make hoogle-setup, hoogle-serve: run a local hoogle on hledger code.

- make man-watch-PROG: watch a hledger program's man page as source files change.

# 1.27 2022-09-01

Docs

- https://hledger.org/ERRORS.html - an overview of hledger's error messages.

- Rewrite/consolidate cost and conversion docs.

- New template for github releases, with improved install instructions for binaries.

- Add modern windows binary install instructions. (Lazar Lazarov, Simon Michael)

- Fix tables of contents in developer documentation. (Alex Hirzel)

- Update ACHIEVEMENTS. (Alex Hirzel)

- Corrected the extension for the CREDITS file.  (Pranesh Prakash)

- Fix broken link in bin/README.md. (David D Lowe)

Examples

- Add example for capital one credit cards CSV. (max thomas)

Process

- Revive github projects, set up http://projects.hledger.org shortcut url

- Many cleanups and improvements to the CI test and binary-generating
  github actions.  The CI tests for main now also include
  hledger-lib's doctests.

- All packages now disallow name shadowing in their code.

- make scc gives a modern report of code line counts.

- make ghci-unit-test loads hledger-lib unit tests in GHCI.

# 1.26 2022-06-04

Scripts/addons

- renamed hledger-number.sh to hledger-simplebal

- added hledger-git, hledger-pijul

- fin (and bin) scripts show available scripts and their help

- renamed aliases.sh to bashrc

- Get hledger-print-location working. (Stephen Morgan)

Docs

- README cleanup, inspired by feedback from README reviewer Lars Wirzenius.

- Clearer sponsoring info and more complete sponsor lists on website and README.

- The new <https://github.com/hledgerorg/hledger_finance> repo
  keeps track of our public finances (on Open Collective, Liberapay etc.)

Examples

- invoice: calculate dates accurately on last days of month

Process

- Stackage nightly and GHC 9.2 are now the default for dev builds.

- CI workflows: 

  - Workflows and binaries have more consistent naming, mentioning platform and architecture.
  - The main test workflow is now `linux-x64-test`, replacing `push` and `pull`.
    It runs for both pushes and pull requests, and generates binaries on every run.
  - Pushes/merges to main, including Simon's, are required to have passed
    `linux-x64-test` on another github branch first.
  - Mac and Windows binaries are now stripped also (if applicable).

- `make buildtimes`, `make buildtimes-cabal` show GHC codegen times.

# 1.25 2022-03-04

Scripts/addons

- hledger-install.sh now also installs Pavan Rikhi's hledger-stockquotes tool.

- The bin/hledger-number addon was added.

- The bin/hledger-check-fancyassertions addon now shows docs in --help.

- A new invoice-making script was added: examples/invoicing/invoice-script/invoice

Process/tools

- The RELEASING doc and release process has been updated, 
  and a new helper script added: tools/releaseprep.
  `make hackageupload` now only works from a branch named
  VERSION-branch or VERSION-release. Ie, making releases from main
  is no longer allowed, a release branch is always required,

- CI: The commitlint check is more robust, and now runs only in
  the push to main and pull request workflows, and not eg when 
  building release binaries. linux-x64 binaries are now built
  with ghc 9.0, not 8.10. Workflow, branch, and binary names
  have been improved.

- `make ghci-ui`/`make ghcid-ui` now use older ghc 8.10 to avoid 
  ghc 9.0-triggered failures.

- hls support: The hie.yaml added to help hls work on mac m1 
  has been moved out of the way, since it probably makes things worse
  on other architectures.

# 1.24.1 2021-12-10

Docs

- More platform notes for setting LEDGER_FILE.

- Clarify which commands support which output formats and data layouts.

- Note that hyphenated field names are allowed in CSV rules.

- Fix some table layouts in non-HTML docs.

# 1.24 2021-12-01

Software

- bin/hledger-check-fancyassertions.hs: fix ugly assertion parse errors. 
  (ShrykeWindgrace)

- bin/hledger-check-tagfiles.hs: Update description, clarify wording.
  (Pranesh Prakash)

Docs

- Account types: prioritise the short one-letter names, hide the deprecated
  legacy syntax.

- Directives: a more compact and accurate overview.

- examples/templates/basic: A new starter file set, and a place to collect them.

- Expose more developer docs as separate web pages:
  CHANGELOGS, COMMITS, RELEASING, etc.

- Fix a link to developer workflows. (Joaquin "Florius" Azcarate)

Process

- PR template: Fix our github PR template to use proper comment syntax,
  and link to more relevant docs.
  (toonn)

- cabal.project: Drop obsolete compatibility comment. 
  (#1365, toonn)

- Bump default stackage snapshot to one avoiding buggy happy version.

- bin/changelog: a new helper making changelog edits more pleasant.

- make throughput{,-dev,-EXE}: reports transactions per second for a range of
  file sizes with the hledger in PATH, hledger dev build, or named hledger 
  executable.

- make install-as-FOO: build executables and save as bin/hledger*-FOO

- perf: bench-ledger.sh for comparative benchmarking with Ledger.

- CI: commitlint: be more forgiving when we can't figure out recent commits
  (don't check any).

- CI: commitlint: recognise any commit starting with ‘Merge’ as a merge commit
  (and ignore it). (Stephen Morgan)


# 1.23 2021-09-21

Software:

- The bin/hledger-check-fancyassertions.hs addon script,
  allowing more complex balance assertions, works again.
  (#1464, Stephen Morgan)

- Many code cleanups suggested by hlint (Stephen Morgan)

Docs:

- Added a public BACKLOG.org to the hledger repo and website.

- Website updates:

  - Reorganised site content.
  - Improved page tables of contents.
  - Content fixes.
  - New docs:
    Currency conversion.
    hledger and Beancount/GnuCash/Ledger/Quicken.

- New examples: systemd and nginx configs for hledger-web (Alan Young)

Tools/process:

- `make site-watch` works again

- `make list-commits` and `make showauthors` show those things.

- `Shake cabalfiles` now uses (and requires) hpack in $PATH, to avoid building.
  It should be the version that's in the current stack release, to avoid commit conflicts.

- shake: changelogs: A leading semicolon now means 
  "skip most CI steps", not "omit from changelog".

- ci: most steps are skipped if commit message begins with ;.

- hledger developers now use GHC 9.0/stackage nightly by default. (#1503)

- Our doctests are disabled with GHC 9 for now to work around an
  upstream bug. 
  ([#1503](https://github.com/hledgerorg/hledger/issues/1503), 
  [#1615](https://github.com/hledgerorg/hledger/issues/1615))

- bin/commitlint is a new tool for hledger developers which checks and
  describes new commit conventions which simplify maintenance of
  change docs and releasing. It can be run locally while developing,
  manually or as a pre-commit hook
  (`ln -sf ../../bin/commitling .git/hooks/commit-msg`), 
  and is also run by our CI workflows to check pull requests.
  <https://hledger.org/CONTRIBUTING.html#commit-messages>,
  <https://github.com/hledgerorg/hledger/blob/main/bin/commitlint>
  (#1602)

# 1.22 2021-07-03

Software:

- We now provide static executables for GNU/Linux on x64 (amd64) and arm32v7
  architectures. These are more portable and more likely to work on your linux
  system than the dynamic Ubuntu executables we have been providing.
  These will also be useful for Nextcloud.com users. (#1571) (Garret McGraw)

- GHC 9.0 is now officially supported, and GHC 8.0, 8.2, 8.4 are not;
  building hledger now requires GHC 8.6 or greater.

Docs:

- The info manuals now have the proper metadata so you or your
  packager can install them with `install-info` and they will appear
  in info's Directory. We also provide a `dir` file making it easy
  for developers to see the latest dev manuals in their info Directory.
  (#1585) (Damien Cassou, Simon Michael)

Chat:

- The hledger IRC channels (#hledger:libera.chat,
  #hledger-bots:libera.chat) moved to Libera.chat.
    
- The hledger Matrix room (#hledger:matrix.org), is now on at least
  equal "official" footing with the IRC channel. 
  
- I upgraded the matrix room to a newer version of the Matrix
  protocol. This effectively splits it into an old (read only) room
  and a new room. If you are joined to the old room, you might not
  have noticed; in your matrix client, please follow the link to the
  new room, ie #hledger:matrix.org.

- I briefly bridged the IRC and matrix rooms, because having two chats
  (four if we consider #plaintextaccounting) is a pain. I hope to try
  the experiment again at some point.

# 1.21 2021-03-10

- roi has a new cookbook doc, and example files have been updated.
  (Dmitry Astapov)

- Example CSV rules for the Daedalus wallet have been added.

- The default stackage resolver/GHC version has been bumped to
  lts-17.4/ghc-8.10.4.

- tools/generatejournal now includes more commodities and prices in
  generated journals. (Stephen Morgan)

- Our functional tests now also run on BSD. (#1434, Felix Van der Jeugt)

- Addon scripts in bin/ have been updated for latest hledger API (Stephen Morgan).

- Addon scripts are now compiled as part of our CI tests, and always
  with the same version of hledger source they were shipped with. We
  now require script users to check out the hledger source tree and
  run the scripts (or, `bin/compile.sh`) from there. This keeps users
  and tests in sync, making things more reliable for everyone. (#1453)

- Last but not least, hledger's bash completions (provided in ./shell-completions/)
  have been thoroughly updated (#1404, #1410, Vladimir Zhelezov).

  "This was supposed to be just a fix for #1404 but upon visiting the source
   several issues became apparent and that is why the commit grew a bit more than
   expected. A complete list of changes below:
  
  - Fix #1404.
    No more orphaned temporary directories. Commands, options, etc. that used to be
    stored in there are included at build-time as here documents in the source.
  
  - Fix artifacts in /tmp after build.
    Upon fixing the above I became aware that the build itself was leaving behind a
    heap of artifacts in /tmp that were not taken care of with a make clean.
    Fixed by using temporary files and directories in the build directory. Makefile
    and build scripts adjusted.
  
  - Produce command aliases.
    Regular expressions in build scripts changed to produce all command aliases
    except single letter ones (see below)
  
  - Do not propose single letters completions.
    It is simply not useful and adds a lot of noise. It makes completion slower as
    well because you need to hit yes on the prompt:
    Display all 200 possibilities? (y or n)
    output-options.sh now excludes those.
  
  - Query filters simplified.
    Keep only the prefix of the filter with the colon in query-filters.txt. This
    change has two reasons:
  
  - Single letter completions are not useful (see above).
    It allows for completion suggestions specific to each
    Bonus reason: it's a completion engine, not a user manual.
    Fix completion impacts on global environment
    The completion script was making a couple of changes to the global environment
    which had an impact for the rest of the shell session.
  
  - set -o pipefail: the change is hidden from the user and could lead to subtle
    errors throughout the shell session.
    COMP_WORDBREAKS=" ": this affects subsequent completions for us and other
    programs too. I exclude the colon : from its value and use
    compopt -o filenames to handle escaping of special characters for us. I would
    like to find a solution without messing with COMP_WORDBREAKS but it is not
    straight forward.

  - Fix hiding of legit subcommands.
    Completion was hiding all possibilities if a subcommand happens to be the prefix
    of another. On typing balance, one should be proposed balancesheet and
    balancesheetequity as well.
  
  - Return early.
    Try to complete depending on the current context and return immediately if
    successful. Keep completion list relevant and as short as possible.
  
  - Context aware completion
  
    Add handlers for option parameter completion, see _hledger_compreply_optarg()
    Add handlers for query filters:, see _hledger_compreply_query()
    Use --file and --rules-file arguments when proposing completions for the
    above, see _hledger()
    Propose only top level accounts at first. Again, keep it short and focused.
    Custom compgen wrapper
    compgen is fairly complicated. There is no way to feed it a word list with
    literals. It will mangle your input in so many ways that we cannot trust it. To
    work around this several wrappers are used: _hledger_compgen() works with
    _hledger_quote_by_ref() to process and escape newline separated input which is
    then fed to compgen and finally in COMPREPLY through _hledger_compreply()
    and _hledger_compreply_append(). It sounds messy and I guess it is, I would like
    to find a more straight forward way to do it. I think it is still a way better
    and safer interface with readline than trying to grep our way through.
  
  - Replace declare with local.
    Again, this script is sourced by the shell -- keep variable scopes as narrow as
    possible. Oops, they are actually synonymous when used in a function but
    local declares our intentions explicitly.
  
  - Use compopt -o nosort.
    Often I resort to using it to keep different groups of completions together.
    Whether this is more ergonomic or not is subjective. But our input lists are
    already sorted at build-time so why not. Sort manually query-filters.txt when
    editing it.
  
  - Remove irrelevant comments.
    And add some new ones :)
  
  I think that is all. Give it a spin, try to abuse it, in and outside of quotes,
  with some funky accounts, payees, tags, whatever, and tell me where it breaks or
  behaves unexpectedly."

# 1.20.4 2021-01-29

# 1.20.3 2021-01-14

- The run/compile instructions for add-on scripts in bin/ have been
  updated. The scripts now use `stack runghc` and are tested (manually
  with `make functest` for now) with the corresponding hledger source,
  not the hledger on stackage.

# 1.20 2020-12-05

- examples: clean up & add more budgeting examples

- examples: stripe csv

- The functional tests in tests/ have been moved into the respective
  packages, eg hledger/test/ and hledger-ui/test/.

- Shake cabalfiles: now gives an error when it fails

- make bench: add some large tabular reports; 
  run just the slowest commands by default;
  run after make (func)test

- a hie.yaml file has been added, so hledger source loads
  easily in IDEs supporting haskell-language-server

# 2020-09-07

- Update shell completions (Jakob Schöttl)

# 1.19 2020-09-01

- example scripts:

  - stack scripts now use stack's script command consistently
  - stack scripts no longer have explicit --package lists, stack
    infers them from the imports
  - hledger-print-location: new script

- CI: 

  - always recompile all modules for robustness
  - generate optimised binaries, which can be downloaded
  - build a single different GHC version with each workflow, reducing
    total building and carbon footprint a bit
  - stop building with GHC 8.0

- the default stack file now uses lts 16.12 (ghc 8.8.4)

# 1.18.1 2020-06-21

- provide CI binaries for windows, mac & gnu/linux

# 1.18 2020-06-07

- new example scripts:

  - hledger-combine-balances.hs, hledger-balance-as-budget.hs  (Dmitry Astapov)
  - hledger-check-tag-files.hs, hledger-check-tag-files2.hs

- more CSV rule examples: coinbase, waveapp

- new CI (continuous integration) system using Github Actions.
  Thanks to Travis and Appveyor for their service to date.
  Improvements:

  - one CI service instead of several
  - more closely integrated with code repo
  - tests run on the three main platforms (linux, mac, windows)
  - harmless commits are ignored automatically ([ci skip] no longer needed for doc commits)
  - scheduled and on-demand testing (push to main, push to ci-* branches, pull request, weekly)
  - now tested: all GHC versions, doctests, haddock building
  - new shortcut url: http://ci.hledger.org

# 1.17 2020-03-01

- hledger-install: re-enable installation of hledger-iadd & hledger-interest.

- hledger-install: bump minimum stack version to 1.9.1
  1.7.1 fails with deps using newer cabal file syntax I believe.

- hledger-install: always do stack update, to help ensure we get the latest packages.
  https://github.com/commercialhaskell/stack/issues/5112

- examples: Add a basic example of rule parsing for the output of csb2format. (Evilham)
  csb2format deals with the CSB43/AEB43 format, which all banks operating in
  Spain must support.
  Having these example rules enables easens bootstraping for users with a
  Spanish bank account.

- doc: simpler, clearer structure in the manuals and hledger.org sidebar

- doc: a new [Quick Start](https://hledger.org/start.html) page

- doc: a new [Common Tasks](https://hledger.org/hledger.html#common-tasks) section in the hledger manual

- doc: a new invoicing how-to: https://hledger.org/invoicing.html

- doc: Fix dead pointer in contributing (Aleksandar Dimitrov)

- doc: Fix build badges for Travis and AppVeyor (Rui Chen)

# 1.16 2019-12-01

- add support for GHC 8.8, base-compat 0.11 (#1090)

- drop support for GHC 7.10

- add descriptions to most issue tracker labels

- matrix.hledger.org now redirects to a more readable/useful url

# 1.15 2019-09-01

- install: bump to lts-14.4, hledger 1.15, drop hledger-api

- bump versions to 1.15

- api: drop from Shake scripts

- new unified website: hledger.org now has its own git repo, has
  absorbed the github wiki, and is generated with Sphinx.

- hledger-api's functionality is now included in hledger-web,
  and the hledger-api package is mothballed.

- hledger-install.sh: updated, now also works on FreeBSD 12 (zieone)

- bin/ addon scripts: hledger-swap-dates added; hledger-check,
  hledger-smooth updated. (#1072)

- shell-completion/ scripts: updated (Jakob Schöttl)

- github: FUNDING.yml / sponsor button configured

- site: Wine option added to download page

- tools: generatejournal updates: vary amount, make reports with fewer
  zeroes, start from a fixed year to keep tests stable, also generate
  P records. (#999)

- tools: make, shake, CI: misc. updates

- doc: add a README for the functional tests, linked from contrib guide

- hledger-makeitso has been renamed to hledger-flow (Andreas Pauley)

- The hledger docker image is now based on the "haskell" image (Dmitry Astapov)


# 1.14 2019-03-01

- hledger.org website: now uses https, home page updates,
  download page improved package list with status badges.
  Also the github wiki pages are now rendered as part of hledger.org,
  like the main site pages (with pandoc markdown and tables of contents).
  Building the site now requires that a copy of the wiki is checked out
  under wiki/.

- bash completion support: removed duplicate options, added new
  options, stopped listing -h as a command, added some completion for
  external addon commands.

- release automation improvements

- makefile cleanups; make site-liverender helps with local site preview

# 1.13 (2019/01/02)

- packaging: A docker image providing the main hledger tools is now
  linked on the download page. This is another way to get up-to-date
  hledger tools without building them yourself (and, a way to run
  hledger-ui on windows ?) (Dmitry Astapov, Simon Michael)

- hledger-install.sh: fix installation of stack when .local/bin is not
  in PATH (Dmitry Astapov)

- doc: fixed pandoc typography conversion in web manuals. Eg `--` was
  being rendered as en-dash. (#954).

Developers:

- developer docs have moved from the wiki into CONTRIBUTING.md (#920)

- new streamlined changelog update process. Shake targets:
  
      ./Shake changelogs
      ./Shake CHANGES.md
      ./Shake CHANGES.md-dry
      ./Shake PKG/CHANGES.md
      ./Shake PKG/CHANGES.md-dry

  update the project-wide and/or package changelogs, inserting new
  commits (touching the respective directory, since the tag version or
  commit hash which is the first word in the changelog's previous top
  heading) at the top, formatted as changelog entries.

- ./Shake PKG - builds a package plus its embedded docs.
  ./Shake build - builds all the packages and their embedded docs.
  ("stack build PKG" does not notice changes in embedded doc files.)

- make ghci-shake - loads Shake.hs in ghci

- make tags - includes doc source files, hpack/cabal files, Shake.hs

- make site-livereload - opens a reloading browser view on the website html
  (requires `livereloadx`)

- added a Dockerfile and helper scripts (Dmitry Astapov)
  
- doc files and hpack/cabal files are included in TAGS again

# 1.12 (2018/12/02)
