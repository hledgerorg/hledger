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
- Sunday is kept to the minimum: tag, publish, announce.
- #2648's bounty is settled; mention it in that changelog entry.

## Schedule

Tasks that change translatable text come first, so the message freeze and the request to
translators can go out on Wednesday, giving translators Thursday to Saturday.
Then the riskiest and most time-consuming work.

| Day | Tasks |
|---|---|
| **Wed Oct 28** | #2821/#2807 review/discussion/merge. Single-period bs SVG net mark fix. Cache-busting. Message freeze; collect translator addresses; send the translation request. |
| **Thu Oct 29** | Start `just oldest`. Doc updates: Post-release translation process, Upgrading page, Ledger and Beancount pages. Charts page and screenshots. |
| **Fri Oct 30** | `just generaloptionshelp`, `just manuals`, `just anchortest`. `just relbranch 1.99.6`. Changelogs (`just changelogs`, edit, `just changelogs-finalise` - allow most of a day.) Draft announcements. |
| **Sat Oct 31** | Translation deadline 20:00 UTC. Merge translations as they arrive (on main, cherry-pick to the release branch). `just relnotes` + summary; `doc/ANNOUNCE`; `doc/ghrelnotes`; Install page updates; manuals snapshot (`make -C site snapshot-1.99.6`, site.js / Makefile / caddy). Cherry-pick docs back to main. Last: `just ghbin` (30-40 min), after the translation deadline. |
| **Sun Nov 1** | Check the binaries' `--version`. `just reltags`; push ⚠; `just ghrel`, publish ⚠; site render; announce ⚠. |

## Tasks

In order.

- [x] **#2821 review/merge/redo** (web refactor). First, since it may touch web text, and so CI can shake it out.
  Discussed and done for now (Oct 28);  #2821 (cosmetic) is set aside in favour of #2807;
  if there's time, revisit for inclusion in this release.
- [x] **Single-period bs SVG net mark**: the net is a one-point polyline, so invisible;
  it now shows in hledger-web's balance sheet page too. Fix, with a test.
  Done (Oct 28, b8c247a07): marked across the bars; any other lone line point is drawn as a dash.
- [x] **hledger-web static file cache-busting**: this release changes hledger.js a lot, and on Oct 27
  Safari kept a stale copy, silently disabling the report keys.
  Done (Oct 28): static files are served with `Cache-Control: no-cache` (and their ETag), so browsers
  check them before each use, at the cost of a cheap 304 per file per page view.
  `?etag=HASH` URLs with long caching were considered and set aside: wai-app-static 3.2.1 ignores the
  query, so it would need TH hashing in `staticFileRoute`, a per-request max-age and a dev-mode exception,
  and it would mainly speed up remote instances, which are uncommon. Revisit if they become common.
- [x] **Request new translations**
  - Message freeze: `just i18n-pot`, `just i18n-merge`, `just i18n-check`; commit and push the template and catalogs,
    so translators work from main. Avoid changing translatable text until the release.
    Merged Oct 28: each catalog has 220 untranslated entries (~870 words, nearly all hledger-web; 173 have notes).
    Translator list: hledger-lib/locale/README.md, Translators.
  - Collect translator addresses: authors of past catalog work (`git log` on hledger-lib/locale/*.po;
    eg Daniil Iaitskov for ru, Chunhui Ouyang for zh), participants in the i18n PRs/issues (#2735, #2736, #2806),
    and a call for a native Spanish reviewer (es.po is machine-made) and a German translator if none is known,
    on matrix and the forum.
  - Compose and send the mail: per-language gap counts from `just i18n-check`, the deadline (Sat Oct 31, 20:00 UTC),
    a link to TRANSLATING.md, how to send the result back (PR, or the .po file by mail),
    and that partial translations are welcome.
- [x] **Design/document an easy process for users to update and submit translations after release**,
  on all platforms, without building hledger. TRANSLATING.md already covers translating against an installed
  release (user catalogs in the config directory); what's missing is an easy way to get the current template
  and to send the result back. Options to weigh: a "submit" section in TRANSLATING.md (attach the .po to a
  github issue, or mail it); a github issue template for translations; hosted Weblate (free for libre projects;
  web-based, so works everywhere, but another service to maintain). Link it from the release notes and
  announcement.
  Done (Oct 28): `hledger --write-lang=LANG` writes the built-in catalog, or a filled-in template, to the
  config directory, matching the installed version; TRANSLATING.md is rewritten around it, with mail as the
  main way to send a file back, and says how to review machine-translated entries.
  Deferred: a github submission workflow (issue template; .po attachments may be refused), and Weblate
  (another service, and its continuous .po commits would need fitting to the pot-only policy).
  Still to do: the release notes / announcement line inviting translations. Draft (update the names from the
  README's Translators table once the translations are in):

  > **Translations.** hledger, hledger-ui and hledger-web can show their own text in ten languages besides
  > English: German (Arthur Cinader, Henning Thielemann), Russian (Daniil Iaitskov), Simplified Chinese
  > (Chunhui Ouyang) and Italian (Diego Depaoli, a draft completed by machine); and Spanish, French,
  > Brazilian Portuguese, Japanese, Irish and Hawaiian, machine-made drafts not yet checked by a native
  > speaker. Text new in this release that translators didn't reach in time is machine-translated too, and
  > marked for review.
  > Choose one with `--lang`, eg `hledger bs --lang ja`; hledger-web follows your browser's language unless
  > started with `--lang en`.
  > If you speak one of these languages, a few minutes' review helps: start with the entries marked
  > "Key term". To start a new language, run `hledger --write-lang=LANG`. See https://hledger.org/TRANSLATING.html.
  > Thanks to [this release's translators].
- [ ] **Review/update affected docs** (site repo)
  - [ ] **Upgrading to hledger 2** (site/src/upgrading.md): the breaking changes, for 1.x users:
    `test` -> `--test`, `activity` output, amounts that may now read as expressions,
    alias vs apply account order, repeated commodity declarations, holdings tree layout.
  - [ ] **Ledger page** (site/src/ledger.md): differences affected by this release, eg alias / apply account
    order now as in Ledger (#2733), amount expressions.
  - [ ] **Beancount page** (site/src/beancount.md): differences affected by this release, eg amount expressions.
  - [x] **Charts page** (site/src/charts.md): bring up to date with the CLI, html, `run` and hledger-web charts;
    add screenshots (a terminal `--chart`, an SVG chart, a hledger-web report page), reusable in the announcement.
    Done (Oct 29, site ac96c4e17): the terminal chart stays a text block; images/charts-hledger.svg regenerated;
    images/charts-hledger-web.png is now the monthly income statement page (light scheme).
- [ ] **Merge translations** (until Sat Oct 31 20:00 UTC), for each catalog received:
  - put it in hledger-lib/locale/ (or merge the PR); merge it with the latest template if it is behind
    (`msgmerge --update --no-fuzzy-matching`), so translators needn't track late text changes;
    `just i18n-check` (placeholders, stale entries)
    Files made before Oct 29 have the help text "match with a boolean query (and, or, not, ()", since fixed to
    "... ())": after the merge, copy any translation of it from the obsolete `#~` entry, adding the `)`.
  - try it in the CLI (`--lang`), hledger-ui and hledger-web (see the translations skill)
  - commit on main with the translator as author (`git commit --author`); cherry-pick to the release branch
  - add each translator to the language's list in hledger-lib/locale/README.md (Translators) and its catalog
    header (`# Translators: ...`), and credit them in the changelog / release notes
  - add additional languages. Done (Oct 29): Irish, Japanese, Hawaiian, French and Brazilian Portuguese, machine-made, and Italian (Diego Depaoli's draft, completed by machine), built in and labelled
    unreviewed in their README sections; still to do: ask for native reviewers. They follow the template,
    so `just i18n-merge` keeps them current like the others, and the gap filling covers them.
- [ ] **Late text changes**: the freeze is soft. Prefer fixes that don't change text; any that do land by
  Sat morning, with `just i18n-pot` and `just i18n-merge` (during the freeze the catalogs on main
  follow the template, so translators' files stay current). No follow-up request unless there are several and time allows.
- [x] **Mark the human catalogs' machine-made entries**, as promised to Henning once he finished.
  Done (Oct 29): de 18, ru 12, zh-Hans 10 entries marked `# machine-translated, please review`, with a header
  note. They are the entries whose current text first appeared in a maintainer commit (found by tracing each
  msgstr through the file's history, as blame is muddied by msgmerge reflows): the chart strings, run's page
  links, "Report details", the zero-balances message, and in de the "Transaktionspreis" cost entries.
  Not marked: Dmitry Astapov's ru wording review (812f719b2), and trims or fixes of human text
  (the shortened help lines, the boolean-query parenthesis).
  At Henning's request, de's 121 untranslated entries were then machine-filled and marked the same way,
  so he can review them before the deadline.
- [ ] **Fill the gaps** (after the deadline, before `just ghbin`): `just i18n-pot`, `just i18n-merge`
  (which now unwraps the catalogs, one line per string: a one-off layout diff, kept separate in its own commit), then
  machine-translate every entry still untranslated in every catalog, each marked with the translator comment
  `# machine-translated, please review` (msgmerge keeps it; not fuzzy, which hledger would ignore);
  `just i18n-check` shows 0 untranslated; try them as above; commit on main and cherry-pick.

## Release process

- [ ] `just oldest` CI passes
- [ ] Options help, manuals, anchor check
- [ ] Release branch
- [ ] Changelogs, with a Breaking changes section and the #2648 bounty mention
- [ ] Release notes and summary (confirm the summary with the maintainer)
- [ ] ANNOUNCE and ANNOUNCE.mastodon (confirm with the maintainer)
- [ ] ghrelnotes, Install page updates
- [ ] Manuals snapshot on the site
- [ ] Binaries (after the translation deadline), tags, push, github release
- [ ] Site render, announcements
