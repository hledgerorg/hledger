# Plan: hledger 1.99.6 release (2.0 preview 6)

Target: Sun Nov 1, 2026. Planned Wed Oct 28.
A preview release, following doc/RELEASING.md's release script.

## Scope

Deliverables for a preview release: changelogs, release notes, github release with binaries,
updates to the Install page, manuals snapshot on the site, announcements. No hackage upload.

State on Oct 28:

- 469 commits since 1.99.5, mostly hledger-web (report controls, keys, holdings page, charts)
  and charts (balance/compound/register/holdings `--chart`, SVG, html, `run` pages);
  also arithmetic expressions in posting amounts (#2648), CSV `%{...}` functions, `--infer-imbalance`.
- 7 breaking changes (`!` commits): posting amount expressions; holdings tree account sections;
  `test` command became a `--test` flag; `activity` (two changes); repeated commodity declarations add up;
  alias directives apply before the apply account prefix (#2733).
- Translations: each catalog (de, es, ru, zh-Hans) has about 220 strings to do
  (167 untranslated, 53 missing, 35 stale), mostly new web and chart text.
- CI green on main, nothing unpushed. Open PRs: #2821 (web refactor), #2807 (draft, web refactor).

## Decisions

- Ship the best translations available on release day, including es.po (machine-made, unreviewed).
  We probably won't get complete translations before a release, in general.
- Machine-made catalogs need not be labelled as such; their quality probably
  falls into the same range as human translations'.
- Translations are due by Sat Oct 31, 20:00 UTC (10:00 HST); later ones go into the next release.
- Sunday's work is minimised: ideally tag, publish, announce.

## Schedule

Tasks that change translatable text come first, so the message freeze and the request to
translators can go out on Wednesday, giving translators Thursday to Saturday.
Then the riskiest and most time-consuming work.

| Day | Tasks |
|---|---|
| **Wed Oct 28** | #2821/#2807 review/discussion/merge. Single-period bs SVG net mark fix. Cache-busting. Message freeze; collect translator addresses; send the translation request. |
| **Thu Oct 29** | Start `just oldest`. Doc updates: Post-release translation process, Upgrading page, Ledger and Beancount pages. Charts page and screenshots. |
| **Fri Oct 30** | `just generaloptionshelp`, `just manuals`, `just anchortest`. Changelogs, on main (`just changelogs`, edit - allow most of a day). Draft announcements. |
| **Sat Oct 31** | Translation deadline 20:00 UTC. Merge translations as they arrive, and fill the gaps, on main. Re-run `just changelogs` for late commits; `just changelogs-finalise`; `just relnotes` + summary; `doc/ANNOUNCE`; all on main. Then `just relbranch 1.99.6` (the release branch is cut late, so main's release work needs no cherry-picking). On the branch: `doc/ghrelnotes`; Install page updates; manuals snapshot (`make -C site snapshot-1.99.6`, site.js / Makefile / caddy). Last: `just ghbin` (30-40 min), after the translation deadline. |
| **Sun Nov 1** | Check the binaries' `--version`. `just reltags`; push ⚠; `just ghrel`, publish ⚠; site render; announce ⚠. |

## Pre-release tasks

In order.

- [x] **#2821 review/merge/redo** (web refactor): set aside in favour of #2807 (Oct 28); revisit after the release.
- [x] **Single-period bs SVG net mark** fixed, with a test (Oct 28, b8c247a07).
- [x] **hledger-web static file cache-busting**: static files are served with `Cache-Control: no-cache` (Oct 28).
  `?etag=HASH` URLs set aside unless remote instances become common.
- [x] **Request new translations**: message freeze, template and catalogs merged, translators mailed (Oct 28).
- [x] **Easy post-release translation process**: `hledger --write-lang=LANG` plus a rewritten TRANSLATING.md,
  with mail as the way to send a file back (Oct 28). Deferred: a github submission workflow, Weblate.
- [x] **Docs updated** (site repo): Upgrading, Ledger, Beancount and Charts pages (Oct 29-30).
- [x] **Merge translations**: none arrived by the deadline (Sat Oct 31 20:00 UTC). Six more languages were
  added machine-made on Oct 29 (it from Diego Depaoli's draft; fr, ga, haw, ja, pt-BR), labelled unreviewed.
- [x] **Late text changes**: holdings' CLI headings made translatable (Oct 31); template and catalogs updated.
- [x] **Mark the human catalogs' machine-made entries** (Oct 29); de's gaps filled at Henning's request.
- [x] **Fill the gaps** (Oct 31): es, ru and zh-Hans's 219 untranslated entries each, and the new holdings
  entries in all catalogs, machine-translated and marked `# machine-translated, please review`;
  `just i18n-check` shows 0 untranslated everywhere. The "Key term" mark shortened and trimmed to 24 terms.

## Release process

- [x] `just oldest` CI passes
- [x] Options help, manuals, anchor check (Oct 31; also shortened --chart's help)
- [x] Changelogs, with a Breaking changes section and the #2648 bounty mention (polished Oct 30-31; final reread Sunday)
- [x] Release notes summary drafted: doc/SUMMARY.md (uncommitted; paste into relnotes.md after `just relnotes`)
- [x] ANNOUNCE and ANNOUNCE.short drafted (uncommitted; review and commit)
- [x] Trial `just ghbin` build on Saturday, to find errors and warm the CI caches
- [x] Release branch (`just relbranch 1.99.6`), `just changelogs-finalise`, `just relnotes` + summary (redone after adding Ukrainian)
- [x] ghrelnotes (nothing to change), Install page updates
- [x] finalise announcements
- [x] Manuals snapshot on the site (1.99.5 snapshot dropped)
- [x] Binaries from the final commit (check `--version`), tags, push, github release
- [x] Push main (branch doc commits cherry-picked)
- [x] Push/render site (stale out2/1.99.5 on the server had to be removed first)
- [x] announce
