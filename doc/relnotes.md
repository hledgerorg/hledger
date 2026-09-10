<!--
          _             _            
 _ __ ___| |_ __   ___ | |_ ___  ___ 
| '__/ _ \ | '_ \ / _ \| __/ _ \/ __|
| | |  __/ | | | | (_) | ||  __/\__ \
|_|  \___|_|_| |_|\___/ \__\___||___/
                                     
-->

# Release notes

<!-- Beware: multiple paragraphs within HTML comments breaks mdbook, comment each line for now -->

<!-- In the release headings, dates appear first to keep them out of the -->
<!-- permalink urls, though it's not ideal for readability. The text part -->
<!-- ("hledger") is needed for stable urls. -->

<!-- The subheadings for the hledger package are written as "hledger cli" -->
<!-- to avoid clashing with the release headings and being assigned -->
<!-- unstable urls. -->

<!-- Releases before 1.0 are grouped under a parent heading to avoid -->
<!-- dominating the site's sidebar. -->

<!-- The older releases show changelog-level detail and should probably be -->
<!-- thinned out. -->

<!-- TEMPLATE:


# # YYYY-MM-DD hledger-1.XX

**HIGHLIGHTS**

### hledger 1.XX

hledger/CHANGES.md

### hledger-ui 1.XX

hledger-ui/CHANGES.md

### hledger-web 1.XX

hledger-web/CHANGES.md

### project changes 1.XX

CHANGES.md

### credits 1.XX

git shortlog -sn LASTRELEASETAG..

-->

<style>
h2, h2:last-child > h3 { margin-top:4em; }
</style>

Major releases and user-visible changes.








## 2026-09-10 hledger-1.52.4

**hledger-web packaging fixes for stackage; misc dependency and doc updates**

### hledger 1.52.4


Improvements

- Allow megaparsec 9.8.1+ (but not 9.8.0, because of [megaparsec#572](https://github.com/mrkkrp/megaparsec/issues/572)).

Docs

- csv: the manual now correctly documents that most top-level rules are evaluated first-wins, not last-wins as previously stated. 
  (Accepting the status quo, unlike hledger 2.x where they are changed to last-wins.) [#2539]

[#2539]: https://github.com/simonmichael/hledger/issues/2539


### hledger-ui 1.52.4


Improvements

- Allow megaparsec 9.8.1+ (but not 9.8.0, because of [megaparsec#572](https://github.com/mrkkrp/megaparsec/issues/572)).


### hledger-web 1.52.4


Fixes

- Raise aeson's lower bound to `>=2.2.5.1`, avoiding versions vulnerable to denial-of-service.
  (<https://haskell.github.io/security-advisories/advisory/HSEC-2026-0007.html>)

Improvements

- The yesod-static and hjsmin dependencies have been dropped;
  hledger-web now serves its static files itself, using wai-app-static
  and file-embed. (yesod-static doesn't currently build with crypton
  1.1+, which has kept it, and hledger-web, out of stackage nightly.)
  Static file urls no longer include an `?etag=...` cache buster;
  instead the files are served with an ETag header, and conditional
  requests are answered with 304 Not Modified.
  (Cherry picked from an AI-assisted change in hledger 2.x.)

- Allow megaparsec 9.8.1+ (but not 9.8.0, because of [megaparsec#572](https://github.com/mrkkrp/megaparsec/issues/572)).

- Allow yesod-core 1.7.0.0.


### project changes 1.52.4


Doc updates

- Github release install instructions have been fixed and simplified. [#2707]

[#2707]: https://github.com/simonmichael/hledger/issues/2707


### credits 1.52.4


Simon Michael.



## 2026-08-27 hledger-1.52.3
### hledger 1.52.3

- Uses hledger-lib 1.52.3.


### hledger-ui 1.52.3

- Uses hledger 1.52.3.


### hledger-web 1.52.3


Fixes

- Another XSS (cross-site scripting) vulnerability has been fixed, in
  the add transaction form's error message. Any web page visited while
  hledger-web was running could use it to run javascript in
  hledger-web's origin, and from there read the whole journal, or
  alter it. All hledger-web users should upgrade. See also:
  GHSA-vq7r-8w52-jv84.  (Arthur Cinader, Simon Michael, [#2700])

- A newline submitted in a transaction's description, code or account
  name is no longer written into the journal file. This removes the
  possibility of the user inserting an include directive, which could
  expose system files readable by the hledger-web server. See also:
  GHSA-vq7r-8w52-jv84.  [#2704]

  Note: as with #2698 in 1.52.2, these fixes were backported from
  AI-assisted fixes in hledger 2, under the security exception in
  https://hledger.org/AI.html; they have been reviewed and tested.

- hledger-web's official binaries, and builds from the hledger source
  tree, now use aeson 2.3, avoiding a denial of service bug.
  (<https://haskell.github.io/security-advisories/advisory/HSEC-2026-0007.html>)

[#2700]: https://github.com/simonmichael/hledger/issues/2700
[#2704]: https://github.com/simonmichael/hledger/issues/2704


### credits 1.52.3

Simon Michael,
Arthur Cinader.




## 2026-08-24 hledger-1.52.2
### hledger 1.52.2

- Uses hledger-lib 1.52.2.


### hledger-ui 1.52.2

- Uses hledger 1.52.2.


### hledger-web 1.52.2


Fixes

- An XSS (cross-site scripting) vulnerability has been fixed in the add
  transaction form's autocomplete. Journal data from an untrusted source
  could execute javascript when shown as a completion suggestion. All
  hledger-web users are encouraged to upgrade. Full technical details:
  GHSA-538p-cvc4-4qjm.
  (Arthur Cinader, Simon Michael, #2698)
  
  Note: this bug was detected, and the original patch was generated, by
  Arthur Cinader with AI assistance, for hledger 2.x.  Because the
  vulnerability is in theory quite severe, and the fix is small and
  obvious, and I don't want to add risk by redoing it from memory, and
  no-one else volunteered promptly to do that work - and after
  discussion in the chat and mail list (see today's thread), and careful
  human review and testing - I manually backported the same fix to
  hledger 1. And, updated the project's https://hledger.org/AI.html
  policy to allow this for needed security-related fixes like this one
  (which I expect to be very rare).


### credits 1.52.2

Simon Michael,
Arthur Cinader.




## 2026-04-28 hledger-1.52.1
### hledger 1.52.1


Breaking changes

- The `Gain` (`G`) account type is no longer auto-detected from account names like
  `revenue:gains` or `income:capital gains`; it must now be declared explicitly with `; type: G`.
  Also, the `UnrealisedGain` (`U`) account type, a subtype of Equity, has been added
  (spellings `U`, `UnrealisedGain`, and `UnrealizedGain` are all accepted).
  These improve compatibility between hledger 1 and 2.

Docs

- The "Cost basis / lot syntax" section has been renamed to "Cost basis",
  and updated to mention hledger 2.


### hledger-ui 1.52.1


Improvements

- Uses hledger 1.52.1.

- Allow vty-crossplatform 0.5.


### hledger-web 1.52.1


Improvements

- Uses hledger 1.52.1.


### credits 1.52.1


Simon Michael.




## 2026-03-20 hledger-1.52


### hledger 1.52


Features

- `aregister` and `register` now support `--drop` for trimming leading account name components,
  like the `balance` command.
  (Caleb Maclennan)

- `print` now preserves and reproduces Ledger-style lot syntax (cost basis annotations) in text and json output,
  and (converted to Beancount syntax) in beancount output.

- Tags can now be declared on commodities, and you can query for postings by their commodity's tags.

- A new `Gain` (`G`) account type has been added, as a subtype of Revenue.
  Certain account names, like `income:gains`, `revenue:capital-gains`, `income:losses`,
  are auto-detected as Gain type.
  This provides a language-independent way of matching capital gain/loss accounts specifically.
  (It is used more in hledger 2.)
  (g. nicholas d'andrea) [#2522]

Fixes

- The `add` and `import` commands once again read all `-f` files, not just the first. 
  This fixes a regression in 1.51.2 which broke autocompletion in `add`,
  and multi-file reading in `import`, when multiple `-f` options were given.
  [#2553]

- In balance reports, accounts revealed by `--empty --declared` now respect account display order, instead of being shown last.
  (Juliano Solanho) [#2564]

- `balance --budget`'s csv/tsv output now properly suppresses digit group marks (eg thousands separators),
  preserving valid CSV structure.
  [#2555]

- The `run` command now properly returns a non-zero exit code if there's an error while commands are being provided on standard input.
  (Previously it always returned exit code 0 in this mode.)
  [#2557]

- Options requiring a value (like `--round` or `-f`) now give a clear error if the value is missing
  (rather than trying to consume a following flag).
  [#2556]

- Postings generated by `--infer-equity` no longer inherit the source posting's tags, comment, or real/virtual type.
  (The posting's date and status are still inherited.)
  [#2535]

Improvements

- When converting to value, price lookups are now optimised with pre-built indexes. 
  This replaces O(n log n) re-sorting on every valuation date with O(log n) indexed lookups,
  significantly improving performance for `--value=end,COMM` with daily reports
  over long periods and large price databases.
  (Oleg Bulatov) [#2511]

- `date:` queries can now include a report interval, eg `date:weekly` or `date:'weekly from last month'`,
  like the `-p/--period` option.

- Smart dates now understand `last|this|next WEEKDAY` and `last|this|next MONTHNAME`.

- When `add` or `import` are autocreating a requested journal file that did not exist,
  they will also create any required parent directories.

- The less pager is now invoked more robustly; we catch and report more kinds of failure clearly,
  and/or fall back to unpaged output with a warning.
  [#2544]

- The `--quit-at-eof` flag is no longer added when running the less pager (and our less flags are better documented).

- Improvements to the `setup` command:
  - improve top info's layout
  - show the OS version, architecture, and compiler version
  - show if hledger is wrongly built without OS thread support
  - show the value of $LESS more accurately
  - test that it runs with the configured options
  - print a warning before making a http request
  - show more compact output if the http request fails

Docs

- Account tags: new separate section
- COMMON TASKS: Setting LEDGER_FILE: updates
- Cost basis / lot syntax: new section and edits
- Costs: rewrite
- csv: if: field matchers: clarify
- Inferring equity conversion postings: note account tags limitation
- journal: code: mention valid characters, recommend tags [#2563]
- Regular expressions: note no lazy quantifiers
- Tag names: clarify --verbose-tags

Examples

- csv: Fidelity, Open Collective updates
- csv: Interactive Brokers example CSV rules files [#2508] (Ilja Kocken)
- csv/cctax: notes and sample files related to exporting to cryptocurrency tax calculators
- debconf: DebConf ledger files 2017-2025, adapted for hledger
- investing/export-lots-workflow: doc and examples for exporting to Beancount, Ledger or rustledger for lots/gains calculation

Scripts/addons

- bashrc: drop clashy month aliases; fix LEDGER_FILE typo; cleanup.
- fix compilation errors in bin/ scripts (Dmitry Astapov) [#2497]
- `hledger-smooth`: accept ACCTPAT, matching case-insensitively as infix (like `aregister`).
- `hledger-fancyassertions`: use `showMixedAmount` for properly formatted output. (Joshua Chapman)
- `ledgereval`: evaluate Ledger value expressions at the command line

[#2508]: https://github.com/simonmichael/hledger/issues/2508
[#2511]: https://github.com/simonmichael/hledger/issues/2511
[#2522]: https://github.com/simonmichael/hledger/issues/2522
[#2535]: https://github.com/simonmichael/hledger/issues/2535
[#2544]: https://github.com/simonmichael/hledger/issues/2544
[#2553]: https://github.com/simonmichael/hledger/issues/2553
[#2555]: https://github.com/simonmichael/hledger/issues/2555
[#2556]: https://github.com/simonmichael/hledger/issues/2556
[#2557]: https://github.com/simonmichael/hledger/issues/2557
[#2563]: https://github.com/simonmichael/hledger/issues/2563
[#2564]: https://github.com/simonmichael/hledger/issues/2564


### hledger-ui 1.52


Fixes

- List screens with no items now correctly appear empty on all platforms.
  (An unguarded division by zero was disrupting the display on non-ARM machines.)
  (Tuong Nguyen Manh, Simon Michael) [#2476], [#2550]

- The less pager (used for displaying help, eg) is now invoked more robustly; we catch and report more kinds of failure clearly.
  [#2544]

Improvements

- New capital `J`/`K` keybindings move down/up 10 rows at a time.
  (Rahul Shankar V, Simon Michael) [#1911], [#2551]

- The `default` theme has been renamed to `light`.
  (Rahul Shankar V, Simon Michael) [#2168], [#2551]

- The selection colour has been changed to cyan, for better visibility in typical terminals.
  (Rahul Shankar V, Simon Michael) [#2175], [#2551]

[#1911]: https://github.com/simonmichael/hledger/issues/1911
[#2168]: https://github.com/simonmichael/hledger/issues/2168
[#2175]: https://github.com/simonmichael/hledger/issues/2175
[#2476]: https://github.com/simonmichael/hledger/issues/2476
[#2544]: https://github.com/simonmichael/hledger/issues/2544
[#2550]: https://github.com/simonmichael/hledger/issues/2550
[#2551]: https://github.com/simonmichael/hledger/issues/2551


### hledger-web 1.52


Fixes

- The less pager (used for displaying help, eg) is now invoked more robustly; we catch and report more kinds of failure clearly.
  [#2544]

Docs

- openapi.yaml (the OpenAPI spec for hledger-web's JSON API) has been updated.
  (n0vdd)

[#2544]: https://github.com/simonmichael/hledger/issues/2544


### project changes 1.52


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

[#2410]: https://github.com/simonmichael/hledger/issues/2410
[#2497]: https://github.com/simonmichael/hledger/issues/2497
[#2527]: https://github.com/simonmichael/hledger/issues/2527
[#2528]: https://github.com/simonmichael/hledger/issues/2528


### credits 1.52


Simon Michael,
Caleb Maclennan,
Dmitry Astapov,
Marko Kocić,
RahulShankarV52,
Tuong Nguyen Manh,
Ilja Kocken,
Jens Petersen,
Joshua Chapman,
Juliano Solanho,
Oleg Bulatov,
g. nicholas d'andrea,
n0vdd.




## 2026-01-08 hledger-1.51.2
### hledger 1.51.2


Fixes

- The `add` and `import` commands now once again auto-create the journal file
  if it does not exist yet, fixing a regression in 1.50.3.
  Also they now create it lazily, only when they have data to write,
  not unconditionally at the start.
  [#2514]

- The `roi` command has some more sanity checks, and some error messages
  have been clarified.
  (Dmitry Astapov,  [#2505])

Improvements

- The `-f` option now reports an error if you give it a glob pattern
  (a path containing `[`, `{`, `*`, or `?`) that matches nothing.
  This makes it consistent with `LEDGER_FILE`.

- Journal format's `include` directive no longer unnecessarily reads
  the attributes of all files in a directory. This works better with
  build tools like tup which detect filesystem operations.

- Journal format's `include` directive has been optimised,
  repairing a slight slowdown introduced in 1.50.3.
  It no longer calls `canonicalizePath` unnecessarily.
  This might be noticeable with many includes on a slow filesystem.

- Allow base 4.22 / ghc 9.14.

API

- Hledger.Cli.Utils:
  withPossibleJournal

[#2505]: https://github.com/simonmichael/hledger/issues/2505
[#2514]: https://github.com/simonmichael/hledger/issues/2514


### hledger-ui 1.51.2


- hledger add invoked via the `a` key now shows output properly,
  fixing a regression in 1.50. [#2512]

- Allow vty-crossplatform 0.5. (Jens Petersen)

- Allow base 4.22 / ghc 9.14.

[#2512]: https://github.com/simonmichael/hledger/issues/2512


### hledger-web 1.51.2


- The register view now prevents line wrapping in dates when the window is narrow. [#2520]

- Allow base 4.22 / ghc 9.14.

[#2520]: https://github.com/simonmichael/hledger/issues/2520


### credits 1.51.2

Simon Michael,
Dmitry Astapov,
Jens Petersen.




## 2025-12-08 hledger-1.51.1
### hledger 1.51.1


Fixes

- Relative includes from a symbolically-linked journal file now work again.
  This was fallout from 1.50.4's fixes.
  [#2503]

- When journal's include directive has an IO error, like trying to
  include an existing but unreadable file, or failing to find a home
  directory when expanding ~, it now shows the problematic include
  directive (previously the line number was off by one).

- `aregister`: respect the order of -f options when showing same-day transactions from multiple files.
  If transactions on the same date are coming from two files specified
  with -f options, we expect them to be displayed in parse order, ie
  respecting the order of the -f options. This wasn't always the case,
  now it is.

- `aregister`: show "ACCTPAT matches no account" error on just one line.

- Fix build failures with the scripts in bin/.
  (Dmitry Astapov, [#2497])

[#2503]: https://github.com/simonmichael/hledger/issues/2503
[#2497]: https://github.com/simonmichael/hledger/issues/2497


### hledger-ui 1.51.1


- Uses hledger 1.51.1.


### hledger-web 1.51.1


- Uses hledger 1.51.1.


### credits 1.51.1


Simon Michael,
Dmitry Astapov,



## 2025-12-08 hledger-1.50.5


### hledger 1.50.5

Fixes

- Relative includes from a symlinked file work again, fixing some fallout from 1.50.4's fixes.
  [#2503]

[#2503]: https://github.com/simonmichael/hledger/issues/2503


### hledger-ui 1.50.5


- Uses hledger 1.50.5.


### hledger-web 1.50.5


- Uses hledger 1.50.5.


### credits 1.50.5


Simon Michael.



## 2025-12-05 hledger-1.51

**Small improvements, doc updates**

### hledger 1.51

Fixes

- HTML output no longer contains invalid nested tables (Joschua Kesper). This may cause some visual changes, hopefully all for the better.
- `stats`: `-o` now redirects all output, including the performance stats.

Features

- `commodities`, `payees` and `tags` commands now have a `--find` mode for finding the best match (like the `accounts` command).
- `stats`: A new `-1` flag prints a single line of output in machine-friendly tab-separated format, including the program version, journal file name, and performance stats.

Improvements

- In journal format, an empty `{}` pair is now allowed (and ignored) in amounts, slightly improving Ledger/Beancount compatibility.
- `accounts` in `--tree` mode, when showing a subset of accounts, now shows parent accounts for context, like the `balance` command.
  (Sam Almahri, [#2427])
- `accounts --types` no longer shows value-less type tags; untyped accounts are shown without a `type` tag.
- When pivoting on account type with `--pivot=type`, account types will be normalised to their short spelling (`A` instead of `Assets`, etc).
- `accounts`: the `--positions` flag has been renamed to `--locations`.
- `print`: the `--location` flag has been renamed to `--locations`.
- `setup`: tidier output for missing LEDGER_FILE or default file; wording improvements

Docs

- Account names: rewrite, emphasise the two space delimiter
- accounts: improve/sync options order
- add: balance assertions/assignments: clarify, fix [#2494]
- aregister: clarify arguments
- argument files: corrections
- check: drop obsolete note about transaction balancing
- close: customisation: clarify [#2492]
- commodity directive: add info about the -c command line option (Ooker)
- COMMON TASKS: demote subheadings
- csv: "CSV fields and hledger fields"; "Regular expressions in CSV rules"; link the `if`-specific `skip` and `end` rules more clearly
- depth: rewrite, note combining issue
- Editor configuration -> Editors
- print: clarify amount styling; note more parseability breakers
- Setting LEDGER_FILE: rewrite, new windows procedures
- Special characters: rewrite (Simon Michael, Caleb Maclennan, [#2468])
- Tags: rewrite [hledger_site#141]
- Value reporting: more advice, examples for COMM, warn about -V/emphasise -X

Examples

- Organise/rename examples/csv/ as the [CSV rules library](https://github.com/simonmichael/hledger/tree/master/examples/csv)

Scripts/addons

- `hledger-check-buynothing`: check Buy Nothing Day compliance
- `hledgerj1`: example of a wrapper for reading a custom data format
- `sortandmergepostings`: Overhaul for more robust determinism (Caleb Maclennan)
  - Avoids non-deterministic flip-flopping when the alphabetical account sort has multiple commodities
  - Sorts postings commodities so commodities are in the same order across transactions
  - Sorts postings with matching commodity by posting amount

API

-  Hledger.Cli.Utils:
   - stop exporting pivotByOpts, anonymiseByOpts
   - renamed withJournalDo -> withJournal. The old name is still available but deprecated.


### hledger-ui 1.51

Improvements

- Allow brick 2.10, vty 6.5.

- Uses hledger 1.51.


### hledger-web 1.51

Improvements

- Uses hledger 1.51.


### project changes 1.51

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


### credits 1.51

Simon Michael,
Caleb Maclennan,
Joschua Kesper,
Ooker,
Sam Almahri.


[#2427]: https://github.com/simonmichael/hledger/issues/2427
[#2468]: https://github.com/simonmichael/hledger/issues/2468
[#2492]: https://github.com/simonmichael/hledger/issues/2492
[#2494]: https://github.com/simonmichael/hledger/issues/2494



## 2025-12-04 hledger-1.50.4
### hledger 1.50.4

Fixes

- An `include` directive with no argument now gives consistent error messages.

- journal format's `include` directive no longer excludes paths containing dotted directories/files.
  1.50-1.50.3 contained an overzealous workaround that sometimes wrongly excluded paths containing a dot dir or dot file.
  Now the pre-1.50 behaviour is restored
  (`*` and `**` generally avoid dot files and dot directories, except `**` will search non-top-level dot directories).
  [#2498]

- Symbolic links found by `include` directives are once again shown as-is, not dereferenced.
  (1.50-1.50.3 showed them dereferenced, eg in `hledger files` output.)

  There is some related new behaviour: each time an include directive is parsed,
  all the parent file paths and the new include file path(s) are re-canonicalised.
  Previous hledger versions did not do this; it's expected to be unnoticeable,
  but if you notice any slowdown caused by having many include directives and a slow filesystem,
  please report it.

[#2498]: https://github.com/simonmichael/hledger/issues/2498


### hledger-ui 1.50.4


- Uses hledger 1.50.4.


### hledger-web 1.50.4


- Uses hledger 1.50.4.


### credits 1.50.4

Simon Michael.

[#2498]: https://github.com/simonmichael/hledger/issues/2498



## 2025-11-18 hledger-1.50.3
### hledger 1.50.3

Fixes

- hledger versions 1.50-1.50.2 ran much slower than normal (depending on the speed of your hard drive).
  This 1.50.3 release fixes that; so please upgrade, and avoid those older 1.50 releases.
  [#2493]

- A regression in 1.50, where very large dates could produce wrong reports, has been fixed.
  (Affecting dates outside the range -25252734927764696-04-22..25252734927768413-06-12
  on 64 bit machines, or -5877752-05-08..5881469-05-27 on 32 bit machines.)
  [#2479]

- If the `LEDGER_FILE` environment variable is set to a nonexistent file, we now report an error
  rather than silently falling back on a default file path, which was confusing.
  Also, we no longer support the legacy `LEDGER` environment variable as a fallback.
  [#2485]

- `setup` now shows tidier output when a LEDGER_FILE or default file is not found,

- `add` now checks balance assertions more robustly, with awareness of how everything is ordered in the journal.
  Also, it now allows adding balance assignments.
  [#2478]

- `check accounts` no longer garbles non-ascii account names in its output.
  [#2469]

- We now escape special characters properly when passing arguments to addons
  (with just one level of quoting/escaping, not two).
  And related docs have been improved.
  (Caleb Maclennan, Simon Michael, [#2468])

- Internal report code which could produce certain date-related errors has been made robust again.
  (Stephen Morgan)

- The old "threaded" build flag, which cabal could turn off, has been dropped.
  This will hopefully prevent wrong builds like Debian's #1120833.
  [#2495]

- Docs updated: add, areg, argument files, check, close, csv, depth, print, print, Special characters, Value reporting


### hledger-ui 1.50.3

- `--watch` mode now also detects changes from apps which overwrite the file, such as VS Code.
  (Caleb Maclennan)

- When hledger-ui is started with --pivot, re-enabling balance assertions
  with the I key now does a full journal reload, to check assertions more accurately.
  [#2451]

- The old "threaded" build flag, which cabal could turn off, has been dropped.
  [#2495]

- Allow brick 2.10, vty 6.5.

- Uses hledger 1.50.3.


### hledger-web 1.50.3

- The old "threaded" build flag, which cabal could turn off, has been dropped.
  [#2495]

- Uses hledger 1.50.3


### credits 1.50.3

Simon Michael,
Caleb Maclennan,
Stephen Morgan.


[#2451]: https://github.com/simonmichael/hledger/issues/2451
[#2468]: https://github.com/simonmichael/hledger/issues/2468
[#2469]: https://github.com/simonmichael/hledger/issues/2469
[#2478]: https://github.com/simonmichael/hledger/issues/2478
[#2479]: https://github.com/simonmichael/hledger/issues/2479
[#2485]: https://github.com/simonmichael/hledger/issues/2485
[#2493]: https://github.com/simonmichael/hledger/issues/2493
[#2495]: https://github.com/simonmichael/hledger/issues/2495
[#2495]: https://github.com/simonmichael/hledger/issues/2495
[#2495]: https://github.com/simonmichael/hledger/issues/2495



## 2025-09-26 hledger-1.50.2
### hledger 1.50.2


Fixes

- The CSV `encoding` rule is now respected when using the rules file as input file. This was a regression in 1.50.
  Also, the text decoding error message has been clarified; it now mentions a possible CSV encoding.
  [#2465]

- The doc for `--depth` has been clarified, and now mentions the use of quotes.
  (Lý Minh Nhật, Simon Michael, [hledger_site#140])

- A typo was fixed in the --depth example in `register`'s doc.
  ([hledger_site#140], reported by Lý Minh Nhật)

- Our package bounds now avoid hashtables 1.3.x, which fails to build with some gcc versions
  (see https://github.com/gregorycollins/hashtables/issues/97)).
  (hseg, [#2463])

[#2463]: https://github.com/simonmichael/hledger/issues/2463
[#2465]: https://github.com/simonmichael/hledger/issues/2465


### hledger-ui 1.50.2


- Uses hledger 1.50.2


### hledger-web 1.50.2


- Uses hledger 1.50.2


### credits 1.50.2

Simon Michael (@simonmichael),
hseg (@hseg).



## 2025-09-16 hledger-1.50.1

### hledger 1.50.1


Fixes

- Balance commands now show an empty report instead of an error when
  no transactions are matched, fixing a regression in 1.50.
  (Stephen Morgan, [#2452])

- The `print` command's help no longer shows an unused --show-costs flag.
  And the command-specific flags are now mostly ordered alphabetically.

- Whitespace in the `setup` command's "undeclared commodities" output has been fixed.

Doc updates

- Text encoding
- bin/README: paypal\*, simplefin\* usage examples, doc link

### hledger-ui 1.50.1


Fixes

- The transaction screen and error screen now update on data changes like other screens,
  eg when using the `E` or `g` keys or `--watch`.
  [#2014], [#2288]

- When the journal is reloaded by the `g` key or `--watch`, the
  `--pivot` (and `--obfuscate`) options are now preserved,
  and spurious errors are avoided.
  [#2451]

- The `Z` key (and the `-E` command line flag) toggle zero-balance accounts again.
  (Stephen Morgan, [#2454])

Improvements

- Debug output has improved, eg it's easier to see changes to the screen stack.


### hledger-web 1.50.1

- Uses hledger 1.50.1


### credits 1.50.1

Simon Michael (@simonmichael),
Stephen Morgan (@Xitian9).

[#2014]: https://github.com/simonmichael/hledger/issues/2014
[#2288]: https://github.com/simonmichael/hledger/issues/2288
[#2451]: https://github.com/simonmichael/hledger/issues/2451
[#2452]: https://github.com/simonmichael/hledger/issues/2452
[#2454]: https://github.com/simonmichael/hledger/issues/2454


## 2025-09-03 hledger-1.50

**Better transaction balancing, include improvements, auto posting account interpolation, csv data commands, import archiving, timeclock improvements, fixes**


### hledger 1.50


Breaking changes

- Transaction balancing is now done in a more robust way, using local precisions only (like Ledger) [#2402].
  Until now, a transaction was required to balance using its commodities's global display precisions.
  Small imbalances were tolerated by configuring display precisions for the whole journal (with `commodity` directives).

  Now, a transaction is required to balance using the precisions in its journal entry only.
  This means each entry can use the precision it needs, and balancing precision and display precision are independent.
  (So eg, increasing the display precision with `-c` no longer breaks the journal.)

  In practice this requires journal entries to be more accurate, and you will probably need to fix some old entries.
  There are three main ways to fix an entry:
  - reduce the amounts' precision (use fewer decimal digits, so a lower balancing precision is inferred)
  - make the amounts more accurate (use better decimal digits, so the amounts sum to zero more closely)
  - or (easiest) add an amountless "expenses:rounding" posting (this is not a cheat, it's a more accurate record of what your bank/broker is doing).

  You can also keep the old transaction-balancing behaviour with `--txn-balancing=old`, for now.
  But updating your entries is recommended. 

  The old behaviour could allow small remainders to accumulate over time, 
  in accounts that often have an inexact posting amount or cost amount and are never reconciled -
  typically equity, revenues, and expenses.
  You can check for this in your old journals with a command like

      hledger bal cur:\\$ -c '$1.000000000000' | grep -E '\...0*[1-9]'

  (show $ account balances, with many decimals, which have a non-zero decimal in the 3rd place or beyond)
  
- Timeclock format has had various changes:
  - Timeclock syntax and parsing is now more robust (when not using --old-timeclock):
    - Semicolon always starts a comment (and timeclock account names may not include semicolons).
    - Trailing spaces are ignored.
    - Clock-ins now require an account name.
    - Clock-outs now can have a comment and tags.
    - Timeclock entries are processed in parse order.
  - Some order-related bugs in 1.43 have been fixed.
  - Concurrent/overlapping sessions are now fully supported, even if they have the same account name.
  - The timeclock doc has been rewritten.
  - The --old-timeclock hidden flag has been renamed, documented, and now also affects included files.
  [#2141], [#2365], [#2400], [#2417]

- The `import` command now shows info messages (such as the dry run "; would import .." message)
  on stderr, not stdout.
  Also the "no new transactions" output is more compact, showing file names not file paths;
  and it no longer prints an extra newline.

- Some edge cases in balance report behaviour were changed for internal consistency:
  - --declared now treats parent accounts consistently.
  - --flat --empty now ensures that implied accounts with no postings are not displayed,
      but accounts with zero balance and actual postings are.
  (Stephen Morgan, [#2360], [#2395])

- hledger now requires at least GHC 9.6 (and base 4.18), to ease maintenance.

Fixes

- Paging long output no longer gives an error when `LESS` is undefined and
  `less` does not have mouse support (as on some FreeBSD systems).

- The `all:` query now requires at least one posting to match.
  (Previously, matching no postings at all was also considered a success.)

- When using journal format's `include` directive, several kinds of
  error (read failure, cyclic include..) could show an off-by-one line
  number or excerpt, confusingly. This has been fixed.
  Also, attempting to include a rules file now gives a better error message.

- In CSV `if` rules, match group references like `\1` no longer get confused
  by differing case.
  (Jay Neubrand, [#2419])

- `add`, `commodities`, and `diff` now support the --conf and -n/--no-conf flags,
  like other commands.
  [#2446]

- On Windows machines, the `add` command now properly shows green prompts instead of ANSI codes.
  [#2410]

- Balance reports now properly show the historical balance even when the report period is empty.
  [#2403]

- Balance reports' csv output, and the `balance --budget` report, now respect the --summary-only flag.
  (Stephen Morgan, [#2411], [#2443])

- The `demo` command no longer mentions `-- ASCIINEMAOPTS` in help.
  Also it shows a better error message when asciinema is not installed.

- `hledger help -m TOPIC` or `hledger help -i TOPIC` now show the help for TOPIC, as intended.
  [#2399]

- Since hledger 1.32.1, the `import` command, when importing multiple files at once,
  would write an empty .latest file for data files with no new transactions
  (causing all transactions in those data files to appear new on next import).
  This is now fixed.
  [#2444]

Features

- CSV rules files can now run a shell command to clean the data:

      # read the latest foo*.csv file, and replace "USD" with "$"
      source foo*.csv | sed -e 's/USD/$/g'

  or to generate the data:

      # fetch JSON from simplefin.org, then transform it to CSV
      source | simplefinjson | simplefincsv

  Whenever hledger runs one of these commands, it will echo the command on stderr.

- The `import` command can now automatically archive imported CSV data files,
  saving a dated copy in a `data/` directory. This can be useful for troubleshooting,
  or for regenerating entries later with improved rules.
  To enable it, add `archive` to the rules file.

  This and the previous feature can simplify file management and reduce the need for support scripts.

Improvements

- In command line help, flag group headings have been simplified.
  And the help for -f/--file, `add`, and `import` is now clearer.

- When given both an unknown command and an unknown flag, hledger now gives
  a clearer error message (about the command, not the flag).
  [#2388]

- A long standing awkwardness with addon commands has been solved:
  you can now use addon options freely in a hledger command line;
  you don't need to write a `--` argument first.
  [#458]
 
- In smart dates and period expressions, quarter syntax like `2025q1` or `Q2` is now fully supported.

- In end-value reports where the end date is unspecified, market prices
  in the future can no longer influence the report end date and valuation date.
  (Market prices on or before today, still can.)
  [#2445]

- A `tag:` query with the `accounts` command now only matches account tags, not posting tags.
  Eg, `hledger accounts tag:t` now lists only account a from this journal:

      account a  ; t:

      2025-01-01
          a          1
          b         -1  ; t:

- Journal format's `include` directive now has more robust and convenient glob patterns:
  - `**` can match both directories and filenames
  - `**` now automatically ignores anything under dotted directories, like .git/, foo/.secret/, etc.
    (If you do want it to search dotted directories, 
    you can use the --old-glob flag for now to restore the old behaviour. See also Glob#49.)
  - Glob patterns with wildcards now automatically exclude the current file.
    Eg `include **.journal` will include all other .journal files in this directory and below.

- `include`'s error messages and debug messages have been improved.
  Eg, the including file paths are also shown.

- Journal format's auto posting rules can now use `%account` to insert the account name
  from the matched posting.
  (Stephen Morgan, [#1975], [#2412])

- The `aregister` command no longer abbreviates account names
  when producing `csv`, `html`, or `fods` output.
  (savanto, [#1995], [#2416])

- The `commodities`, `payees` and `tags` commands now have --used/--declared/--undeclared/--unused flags, like `accounts`.
  And there has been a general cleanup of options and help across these four commands.

- The `setup` command's output has been improved.
  Lack of a pager is now reported as info, not warning (there's no default pager on Windows).
  Shell completions are ignored for now.

Docs

- add: clarify that add is for journal format only
- addon commands: edits, drop `--` argument from all examples [#458]
- areg: clarification
- bin: README updates
- COMMANDS: mention general options
- completions: README updates
- config files: no longer experimental
- csv: date-format: mention lack of support for local time formats [#1874]
- csv: source, archive: rewrite, add examples
- Depth: fix typo
- github release docs: simplify install commands
- import: use windows-compatible quotes in watchexec example
- include directive: update docs; clarify effect, glob limitations
- note fish LEDGER_FILE setup
- options: mention that flag+value can't combine with other flags [#2059]
- print: improve --location help
- smart dates: fix typo

Examples

- CSV rules for Eternl cryptocurrency wallet
- VAT example

Scripts/addons

- renamed paypaljson2csv to paypaljson
- simplefinjson, simplefincsv: new helpers for downloading/converting data from simplefin.org bank aggregator


### hledger-ui 1.50


Breaking changes

- hledger now requires at least GHC 9.6 (and base 4.18), to ease maintenance.

Improvements

- Use hledger 1.50


### hledger-web 1.50


Breaking changes

- hledger now requires at least GHC 9.6 (and base 4.18), to ease maintenance.

Fixes

- The register chart is no longer hidden when the window is narrow.

- Dragging on the register chart now selects date ranges more accurately.
  Eg, now you can select a range including transactions at the rightmost edge of the chart.

Improvements

- Use hledger 1.50


### project changes 1.50


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
- Tutorial: hledger basics -> to Tutorial: hledger add
- Home: new, shorter home page content
- Home: show a quote/testimonial, updating on the hour
- Investments: fix link (#2436)
- Invoicing: fix kairos link
- Ledger: edits

Infrastructure/Misc

- hledger now requires at least GHC 9.6 (and base 4.18), to ease maintenance.
- bump default build, tools to lts 24.8 / ghc 9.10.2
- docker: sync Docker GHC version with Stack configuration, update dependencies, and replace deprecated Dockerfile syntax. (Lukas Fleischer)
- github workflows improvements
- tool updates: checkembeddedfiles, devtag, nightly-push, nightlytag, relver, test
- update github issue templates


### credits 1.50


Simon Michael (@simonmichael),
Stephen Morgan (@Xitian9),
Jay Neubrand (@jneubrand),
Lukas Fleischer (@lfos),
savanto (@savanto).

[#458]:  https://github.com/simonmichael/hledger/issues/458
[#1874]: https://github.com/simonmichael/hledger/issues/1874
[#1975]: https://github.com/simonmichael/hledger/issues/1975
[#1995]: https://github.com/simonmichael/hledger/issues/1995
[#2059]: https://github.com/simonmichael/hledger/issues/2059
[#2141]: https://github.com/simonmichael/hledger/issues/2141
[#2360]: https://github.com/simonmichael/hledger/issues/2360
[#2365]: https://github.com/simonmichael/hledger/issues/2365
[#2388]: https://github.com/simonmichael/hledger/issues/2388
[#2395]: https://github.com/simonmichael/hledger/issues/2395
[#2399]: https://github.com/simonmichael/hledger/issues/2399
[#2400]: https://github.com/simonmichael/hledger/issues/2400
[#2402]: https://github.com/simonmichael/hledger/issues/2402
[#2403]: https://github.com/simonmichael/hledger/issues/2403
[#2410]: https://github.com/simonmichael/hledger/issues/2410
[#2411]: https://github.com/simonmichael/hledger/issues/2411
[#2412]: https://github.com/simonmichael/hledger/issues/2412
[#2416]: https://github.com/simonmichael/hledger/issues/2416
[#2417]: https://github.com/simonmichael/hledger/issues/2417
[#2419]: https://github.com/simonmichael/hledger/issues/2419
[#2443]: https://github.com/simonmichael/hledger/issues/2443
[#2444]: https://github.com/simonmichael/hledger/issues/2444
[#2445]: https://github.com/simonmichael/hledger/issues/2445
[#2446]: https://github.com/simonmichael/hledger/issues/2446


## 2025-06-13 hledger-1.43.2

### hledger 1.43.2


- hledger no longer shows an error message or exits with error status
  when its output is truncated in a piped command. (This broke in 1.43.) [#2405]

- The `add` command's doc now describes how it interacts with balance assertions
  and balance assignments. [#2406]

- `aregister` now consistently rounds amounts to display precision again.
  (This broke in 1.32.) [#2407]

- Changelog, release notes: mention improved decoding errors [#73];
  add missing issue numbers


### hledger-ui 1.43.2


- Use hledger-1.43.2


### hledger-web 1.43.2


- Use hledger-1.43.2

- Add missing issue numbers in the changelog


### credits 1.43.2


Simon Michael.

[#73]:   https://github.com/simonmichael/hledger/issues/73
[#2405]: https://github.com/simonmichael/hledger/issues/2405
[#2406]: https://github.com/simonmichael/hledger/issues/2406
[#2407]: https://github.com/simonmichael/hledger/issues/2407



## 2025-06-04 hledger-1.43.1
### hledger 1.43.1


Fixes

- `cur:` in posting-based reports like `balance` and `register` once again
  filters multicommodity amounts as it should. [#2396]
- More error messages were made consistent, hiding call stack etc. [#2367]

Docs

- Query types: clarify that amt: filters postings [#2396]
- More text encoding corrections/cleanups [#2394]


### hledger-ui 1.43.1


- More error messages were made consistent, hiding call stack etc. [#2367]

- Allow brick 2.9


### hledger-web 1.43.1


Fixes

- Fixed a compilation error when not in the hledger source tree. [#2397]


### project changes 1.43.1


- tools:
  - Shake changelogs: fix missing blank lines around old heading
  - ghcruns-download: make tmp dir
- docs:
  RELEASING


### credits 1.43.1


Simon Michael.

[#2367]: https://github.com/simonmichael/hledger/issues/2367
[#2394]: https://github.com/simonmichael/hledger/issues/2394
[#2396]: https://github.com/simonmichael/hledger/issues/2396
[#2397]: https://github.com/simonmichael/hledger/issues/2397




## 2025-06-01 hledger-1.43

### hledger 1.43

**new `setup` command, better boolean queries, `add` assertions, timeclock concurrent sessions, CSV if rules debug output**

Breaking changes

- Timeclock format now supports multiple simultaneous clocked-in sessions.
  A clockout entry can reference the account name of the clockin it is ending,
  otherwise it will end the most recent clockin.

  This is a potentially breaking change, because we previously ignored
  the description on clockout entries.  For now, you can restore the
  old behaviour by adding the `--timeclock-old` flag.  This may be
  removed later, so if you needed it, please let us know!
  (Michael Rees, [#2141])

Fixes

- Some boolean queries involving `amt:` or `cur:` did not match correctly; now they do.
  (Simon Michael, Stephen Morgan, [#2371], [#2373], [#2387])

- The `roi` command has fixed a bug with PnL attributed to the wrong period.
  (Dmitry Astapov, [#2391])

- For a long time, hledger docs stated that hledger's input and output had to be UTF-8 encoded.
  In fact this was wrong; hledger has always used the system locale's encoding for both.
  Docs like [Install: Text encoding](install.md#text-encoding)
  and       [hledger: Text encoding](hledger.md#text-encoding)
  have been updated.
  [#2394]

- CLI error messages now have consistent format independent of the GHC
  version hledger was compiled with. [#2367]

Features

- A new `setup` command checks your hledger installation and shows information
  useful for troubleshooting. It will do more in future.
  For now, `setup` should be reliable and accurate;
  please test it on all your machines and share the results with us.
  Experimental.

  When you run this command, hledger attempts one HTTP request, with a 10s timeout,
  to hledger.org, to detect the current release version.

- New `any:"BOOLEANQUERY"` and `all:"BOOLEANQUERY"` queries can be
  used with transaction-matching commands like `print` and `import`.

  Unlike `expr:"BOOLEANQUERY"`, where the parts of the boolean query
  are allowed to match different postings in the transaction,
  with `any:` and `all:` the entire boolean query must match a single posting.
  `any:` matches the transaction if any posting is matched,
  `all:` matches the transaction if all postings are matched.

- The `add` command now allows balance assertions to be added, after an amount.
  Also, whenever you enter an amount, it now checks the journal's balance assertions
  and will not allow adding an amount that would cause assertion failure
  (unless you use the `-I/--ignore-assertions` flag).
  (Michael Rees, [#2355], [#2356])

- The hledger-print-location script, which shows transactions' file positions, 
  is now built in to `print` as the `--location` flag.
  (Sam Salmahri, [#2368])

Improvements

- Core data types are now more strict, which in some cases reduces memory and time usage by up to 15%.
  (Stephen Morgan, [#2381], [#2385], [#2387])

- Config files (and maybe timedot files) no longer require a final newline.

- In journal format, `include` directives can now have same-line comments.

- CSV `if` rules now produce more `--debug=2` output, useful for troubleshooting.

- CSV debug output now displays records as the `if` matchers see them.
  (Comma separated and with quotes and outer whitespace removed.)

- A number of error messages have been updated to show a consistent format.
  (reading a nonexistent data file,
  reading an unsafe dotted file name on Windows,
  demo not found,
  demo asciinema error,
  diff bad arguments,
  print --match with no match,
  register --match with no match,
  roi with no investment transactions).
  [#2367]

- When unicode/non-ascii text can't be decoded by the system locale's text encoding,
  we now show a consistent informative error message explaining it. [#73]

- Support GHC 9.12.

Docs

- Account types: rewrite
- Assertions and multiple files: edits
- Balance assertions and multiple files
- balance: edits
- Beancount output: edits
- check: edits
- Config file: drop the s
- CSV: clarify that CSV means delimiter-separated values, link to wikipedia DSV page
- CSV:description field: fix link [hledger_site#133]
- Fix broken hledger-iadd link
- Fix various broken "Commodity display style" links (JB Rainsberger, Simon Michael, [hledger_site/#132])
- How CSV rules are evaluated: clarify
- Journal: cheatsheet edits
- print: simplify [#2368]
- Queries: discuss transaction vs posting queries; cleanups
- Queries: fix the explanation of boolean queries and space-separated terms

Examples

- examples/csv/nps.csv.sh updated (Pranesh Prakash)
- examples/forecast-budget* -> examples/goal-budget*
- examples/i18n/\*.journal: top level account declarations in several languages.
- examples/quickstart.journal: the quickstart journal from the home page

Scripts/addons

- bin/balance-as-budget-multi.hs (Dmitry Astapov)
- bin/bashrc: command alias updates
- bin/hledger-sankeymatic

API

- Hledger.Cli.Conf: make getConf total, add getConf'
- Hledger.Cli.Version: add more version helpers, rename HledgerBinaryInfo


### hledger-ui 1.43


Fixes

- Require fsnotify >=0.4.2.0, which fixes some events being ignored on mac,
  possibly making hledger-ui --watch more reliable in this regard.

Improvements

- CLI error messages now have consistent clean format independent of GHC version. [#2367]

- Support GHC 9.12.

Docs

- Update --watch docs.
- Drop obsolete mention of Windows non-support.


### hledger-web 1.43


Features

- Serve openapi.json, documenting the hledger-web HTTP API so that tools
  like open-webui and LLMs can query hledger-web for context.
  (Ben Sima)

Improvements

- The search help popup has been updated, and now shows the hledger-web version.

- The default "serve and browse" mode now has an explicit `--serve-browse` mode flag, for consistency.

- The old `--server` flag is now deprecated and hidden. Use `--serve` instead.

- CLI error messages now have consistent clean format independent of GHC version. [#2367]

- Fix capitalisation in Sandstorm app metadata.

- Support GHC 9.12.

- Drop base-compat dependency (Thomas Miedema)

Docs

- Fix outdated PERMISSIONS doc.


### project changes 1.43


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


### credits 1.43

Simon Michael (@simonmichael),
Michael Rees (@reesmichael1),
Thomas Miedema (@thomie),
Dmitry Astapov (@adept),
Pranesh Prakash (@the-solipsist),
Stephen Morgan (@Xitian9),
Sam Almahri (@samahri),
Ben Sima (@bsima),
Doug Goldstein (@cardoe).

[#73]: https://github.com/simonmichael/hledger/issues/73
[#2002]: https://github.com/simonmichael/hledger/issues/2002
[#2141]: https://github.com/simonmichael/hledger/issues/2141
[#2355]: https://github.com/simonmichael/hledger/issues/2355
[#2356]: https://github.com/simonmichael/hledger/issues/2356
[#2359]: https://github.com/simonmichael/hledger/issues/2359
[#2367]: https://github.com/simonmichael/hledger/issues/2367
[#2368]: https://github.com/simonmichael/hledger/issues/2368
[#2371]: https://github.com/simonmichael/hledger/issues/2371
[#2373]: https://github.com/simonmichael/hledger/issues/2373
[#2381]: https://github.com/simonmichael/hledger/issues/2381
[#2385]: https://github.com/simonmichael/hledger/issues/2385
[#2387]: https://github.com/simonmichael/hledger/issues/2387
[#2391]: https://github.com/simonmichael/hledger/issues/2391
[#2394]: https://github.com/simonmichael/hledger/issues/2394
[hledger_site#132]: https://github.com/simonmichael/hledger_site/issues/132
[hledger_site#133]: https://github.com/simonmichael/hledger_site/issues/133


## 2025-05-16 hledger-1.42.2
### hledger 1.42.2

Fixes

- The test command can pass options to tasty again (this broke in 1.42).
  Also, any arguments before -- are now passed to tasty as test-selecting -p options.
  [#2386]

- Require extra >= 1.7.11, fixing the stack8.10.yaml build. (Thomas Miedema)

Docs

- CSV encoding: fix inaccurate list of encoding names. [#2354]
- Fix broken links to "Commodity display style". (Simon Michael, J.B. Rainsberger [hledger_site#132])
- Misc. edits/fixes: beancount output, commands list, balance command, hledger-iadd link, csv tutorial link


### hledger-ui 1.42.2

Fixes

- Require fsnotify-0.4.2.0+/hfsevents-0.1.8+, which fixes some events
  being ignored on mac (see https://github.com/luite/hfsevents/pull/19),
  which should help `hledger-ui --watch` a little.

- Require extra >= 1.7.11, fixing the stack8.10.yaml build. (Thomas Miedema)

Docs

- Update --watch notes
- Drop obsolete Windows non-support note


### hledger-web 1.42.2

Fixes

- Don't hang when saving a large file (this broke in 1.42). [#2389]

- Require extra >= 1.7.11, fixing the stack8.10.yaml build. (Thomas Miedema)


### project changes 1.42.2

Docs

- relnotes: fix links to hackage changelogs


### credits 1.42.2

Simon Michael (@simonmichael),
Thomas Miedema (@thomie).

[#2354]: https://github.com/simonmichael/hledger/issues/2354
[#2386]: https://github.com/simonmichael/hledger/issues/2386
[#2389]: https://github.com/simonmichael/hledger/issues/2389
[hledger_site#132]: https://github.com/simonmichael/hledger_site/issues/132



## 2025-03-12  hledger-1.42.1
### hledger 1.42.1

Fixes

- Fix a regression in the parsing of single ampersands (&) in csv rules.
  (Thomas Miedema, [#2352])

- The run and repl commands no longer cache data wrongly when using the --forecast option.
  (Dmitry Astapov, [#2345])

- The run and repl commands no longer miss a caching opportunity when using --forecast with a period argument.
  (Stephen Morgan)

- run, repl: doc fixes (Pranesh Prakash, Simon Michael)


### hledger-ui 1.42.1

- Allow vty 6.4.


### hledger-web 1.42.1


### project changes 1.42.1


Infrastructure/Misc

- Tools updates

- Fix cabalfilestest: test all cabal files before any hackage upload.


### credits 1.42.1

Simon Michael (@simonmichael),
Dmitry Astapov (@adept),
Pranesh Prakash (@the-solipsist),
Stephen Morgan (@Xitian9),
Thomas Miedema (@thomie).

[#2345]: https://github.com/simonmichael/hledger/issues/2345
[#2352]: https://github.com/simonmichael/hledger/issues/2352



## 2025-03-07 hledger-1.42


### hledger 1.42

**run & repl commands, non-UTF8 CSV, same-line if matchers, more pivot targets, fixes.**

Fixes

- hledger's default options for the `less` pager no longer include --use-color,
  which caused older less versions (eg 551) to break. [#2335]

- In balance --budget reports, costs no longer prevent display of percentages. [#2327]

- In the balance command's HTML output, -H/--historical now suppresses the total heading.

- print --help now shows the correct default for --round. [#2318]

- close --infer-costs no longer implies the -x/--explicit flag. [#1826]

- add: Account names provided on the command line are no longer ignored. [#2305]

- bs/bse/cf/is no longer show the unsupported --budget option in their help. [#2302]

- The print command now ignores --depth entirely. Previously, a depth
  limit caused it to show only transactions referencing accounts as
  deep or deeper than that.

- Week periods beginning in the previous year are now shown correctly.
  Eg the week beginning 2024-12-30 (which is week 1 of 2025 because the
  thursday falls in 2025) was previously shown as 2024-W01, and is now shown as 2025-W01.
  [#2304]

Features

- `run` and `repl` are new commands which run multiple commands
  without re-parsing data files, so they run faster.
  `run` runs a sequence of commands from files or command line arguments,
  and `repl` provides an interactive prompt with readline-style history.
  (Dmitry Astapov, Simon Michael, [#2323], [#2328])

- `commands` is a new explicit command for showing the commands list; it's useful in the REPL.
  With --builtin, it shows only the builtin commands.

- hledger can now read CSV/SSV/TSV data in encodings other than UTF8,
  using the new `encoding` CSV rule. (Joschua Kesper,  [#2319])

- `if` matchers in CSV rules can now be combined on the same line,
  separated by `&&` (AND) or `&& !` (AND NOT).  This makes `if` tables more expressive.
  Examples:

      if %description amazon && %date 2025-02-22
          account2 expenses:books

      if,account2
      %description amazon && %date 2025-02-22, expenses:books

  The next-line `&` operator also may now be written as `&&`, for consistency.
  (Thomas Miedema, [#2333])

Improvements

- Terminal width is now detected more robustly, using the POSIX API.
  This means that register commands will more reliably use the proper terminal width,
  eg when $TERM or $COLUMNS do not have a correct value, and on Windows.
  hledger no longer uses $COLUMNS.
  (gesh, [#2332], [#2340])

- Error messages (first line) in the terminal are now shown in red (and bold),
  and warning messages are shown in yellow,
  when ANSI codes are supported and permitted.

- --pivot can now also pivot on amount quantity (`amt`),
  amount cost (`cost`), and/or commodity symbol (`comm` or `cur`).

- The close command's --migrate flag has been renamed to `--clopen`.
  The start: tag has been renamed to `clopen:`,
  and its default value now excludes the new file's extension.
  And close --assign's tag has been renamed to `assign:`.

- The print command now supports the --invert flag. [#2314]

- The roi command is now faster:
  it no longer checks every day with P directive,
  and the "one period per report interval" case has been optimised.
  (Dmitry Astapov)

- Two more file extensions are now recognised as possible hledger addon
  commands: `.osh` and `.ysh`.

Docs

- aregister: Drop an inconsistent newline from options help.
- balance: improve --layout option help.
- close: doc rewrites
- shell completions: mention zsh; cleanups
- cost/lot notations: clarify
- cost, value reporting: edits
- Directive effects: fix account types link [#126]
- commodity styles: fix typo [hledger_site#123]
- commodity directive: clarify
- close: mention the balance assertions
- pager: mention --pager=no
- Aliases and account types: better troubleshooting command
- Beancount output: mention limitations: P and balance assignments
- Balance report output: drop outdated note about --tree and HTML [#1846]

Scripts/addons

- hledger-balance-as-budget properly applies commodity styles now. (Dmitry Astapov)

- hledger-git now runs pass-through git commands in the right repo.

- hledger-git now checks for a git repo more robustly. (Lars Kellogg-Stedman)

- hledger-jj is another easy CLI for keeping hledger files in version control,
  using newer tech (jujutsu and oil shell's ysh).

- hledger-script-example.hs has had some cleanup.


### hledger-ui 1.42


Fixes

- Startup arguments provided at the CLI are no longer passed to `add` when pressing the `a` key. [#2313]

Improvements

- Allow vty 6.3.
- Allow brick 2.8.


### hledger-web 1.42


Fixes

- Fix a test suite build issue: build it with -threaded.


### project changes 1.42


Docs

- new/updated: ACHIEVEMENTS, CREDITS, FINANCE, MOCKUPS, REGRESSIONS, RELEASING, Scripts
- examples/csv: pooltool-rewards.csv.rule cleanup
- examples: some sample hledger run scripts
- examples: test files for CSV encoding [#2319]

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


### credits 1.42


Simon Michael (@simonmichael),
Dmitry Astapov (@adept),
gesh (@hseg),
Thomas Miedema (@thomie),
Joschua Kesper (@jokesper),
Lars Kellogg-Stedman (@larks).


[#126]:  https://github.com/simonmichael/hledger/issues/126
[#1826]: https://github.com/simonmichael/hledger/issues/1826
[#1846]: https://github.com/simonmichael/hledger/issues/1846
[#2302]: https://github.com/simonmichael/hledger/issues/2302
[#2304]: https://github.com/simonmichael/hledger/issues/2304
[#2305]: https://github.com/simonmichael/hledger/issues/2305
[#2309]: https://github.com/simonmichael/hledger/issues/2309
[#2313]: https://github.com/simonmichael/hledger/issues/2313
[#2314]: https://github.com/simonmichael/hledger/issues/2314
[#2318]: https://github.com/simonmichael/hledger/issues/2318
[#2319]: https://github.com/simonmichael/hledger/issues/2319
[#2323]: https://github.com/simonmichael/hledger/issues/2323
[#2327]: https://github.com/simonmichael/hledger/issues/2327
[#2328]: https://github.com/simonmichael/hledger/issues/2328
[#2332]: https://github.com/simonmichael/hledger/issues/2332
[#2333]: https://github.com/simonmichael/hledger/issues/2333
[#2335]: https://github.com/simonmichael/hledger/issues/2335
[#2340]: https://github.com/simonmichael/hledger/issues/2340



## 2024-12-09 hledger-1.41

**Valuation fix, improved HTML and FODS output, multiple depths, terminal pagination, robust export to Beancount, ...**

### hledger 1.41


Breaking changes

- Accounts named "equity:conversion", "equity:trading", or "equity:trade(s)", which are detected as type `V`/`Conversion`, will now revert to type `E`/`Equity` instead if any other account has been declared as type `V`/`Conversion`.

- When built with ghc 9.10.1, hledger shows two extra newlines after any error message.

Fixes

- A somewhat severe, though hopefully rare, valuation bug has been fixed. In certain circumstances, values could be calculated inaccurately, because of display-rounding occurring inappropriately during calculations. [#2254]

  Specifically: when there was no direct P price for the target commodity, so that hledger had to convert via a chain of prices, and if all of those price amounts had too few decimal places, then the result could be inaccurate. An example:

      P 2000-01-01 A   10.5 B
      P 2000-01-01 B  100.5 C

      2000-01-01
          (a)    100 A
      
      $ hledger-1.40 print -X C
      2000-01-01
          (a)        105520 C   ; wrong

      $ hledger-1.41 print -X C
      2000-01-01
          (a)        105525 C   ; right
 
- `bs`/`bse`/`cf`/`is`'s HTML output no longer includes excess heading cells, and `bs`/`bse`'s HTML output no longer shows an inappropriate Total heading with `-T`. (`balancesheet` does not support `-T`.)
  (Henning Thielemann)

- Balance commands' HTML, CSV and FODS output now show tree mode properly indented (using no-break spaces).
  (Henning Thielemann)

- In the HTML output of `bs`/`bse`/`cf`/`is` reports, Net amounts in the Net row are now formatted like the others.
  (Bas van Dijk)

- In `bs`/`bse`/`cf`/`is` HTML output, some unnecessary TH cells have been fixed.
  [#2225] (Henning Thielemann)

- The `print` command now ignores a depth limit entirely.
  Previously, a depth limit caused it to show only transactions referencing accounts as deep or deeper than that.

- In the `roi` command, a division by zero error (when all assets were sold) has been fixed.
  [#2281] (Dmitry Astapov)

- In a multi-line comment generated by CSV rules, tags on all lines now work (ie, can be matched). Posting dates in comments generated from CSV also now [work](https://hledger.org/hledger.html#comment-field).
  [#2241]

- hledger's bash shell completions are now up to date with the latest CLI.
  [#986]

- When showing output with a pager, if `$PAGER` is set to something not found in PATH, we now ignore it instead of raising an error.

- `hledger --color=yes | less -R` now shows bold headings as you'd expect.

Features

- The `print`, `register` and `aregister` commands now support HTML and FODS output, and the `bs`/`bse`/`cf`/`is` commands now support FODS output. This means all of the "STANDARD REPORTS" commands, and the `balance` command, now support text, HTML, CSV, TSV, or FODS output.
  (Henning Thielemann)

- When generating HTML output with the register or balance commands, the `--base-url` option will add hyperlinks to hledger-web, allowing you to view the detailed transactions if you have hledger-web running.
  (Henning Thielemann)

- Reports can now specify different display depths for certain accounts, rather than showing all accounts with the same depth limit. Multiple `--depth=ACCTREGEX=DEPTH` options (or `depth:ACCTREGEX=DEPTH` arguments can be used. For example, this will clip all accounts matching "assets" to depth 3, all accounts matching "expenses" to depth 2, and all other accounts to depth 1: `--depth assets=3 --depth expenses=2 --depth 1`
  (Stephen Morgan, #2292)

- In unix-like environments, hledger now uses a pager (`$PAGER`, `less`, or `more`) for all large terminal output, not just for help. You can override this with the new `--pager` option. The pager is expected to handle hledger's ANSI colour output (unless you disable that). If `less` is used, it will be configured automatically, or you can override this by setting options in a `HLEDGER_LESS` environment variable.

- The `print` command's `beancount` output is now much more Beancount-compatible [#2295]. Other than using `--alias` to provide the top-level account names Beancount requires, you should rarely have to do anything special to produce a journal that `bean-check` accepts. hledger will automatically adjust problematic names, encode unsupported characters, and so on. See [hledger: Beancount output](https://hledger.org/dev/hledger.html#beancount-output) for the full details.

  This supersedes the `ledger2beancount` tool, and makes using Beancount tools, especially Fava, practical for hledger users. In many cases this should just work:
  ```
  hledger [ALIASES] print -o tmp.beancount; fava tmp.beancount
  ```

Improvements

- `if` blocks in CSV rules now allow `& !` (AND NOT) on the same line.

- When reading `.latest` files, whitespace is now ignored, and any date parse failure is reported with the file and line number.

- In journal format, P directives now require a space after the first symbol, preventing surprises like `P 2024-10-31 a0 1` parsed as `P 2024-10-31 a 01`.
  [#2280]

- `aregister` has a new `--heading=YN` option, for disabling the report heading. (Henning Thielemann)

- `aregister` now supports the `--invert` and `--cumulative` flags, like the `register` command. (Henning Thielemann)

- The balance commands' HTML and FODS output now shows table borders consistently.
  (Henning Thielemann)

- In the balance commands' HTML output, row headings now span multiple rows when appropriate, rather than being repeated.
  (Henning Thielemann)

- Balance commands now support `--transpose` when generating HTML output.
  (Henning Thielemann)

- The `balance` command's `--layout=tidy` now affects HTML and FODS output at least to some extent (not just CSV output). And it always disables the totals row. (Henning Thielemann)

- The `balance` command's FODS output now picks a report title based on the report mode: "Balance Report", "Multi-period Balance Report", or "Budget Report". (Henning Thielemann)

- `balance` and `aregister`'s HTML output will now use a hledger.css file if present, like `bs`/`bse`/`cf`/`is`.

- `bs`/`bse`/`cf`/`is` now support the `--count` (postings count) report type, like `balance`.

- The balance commands' options help has had some cleanup.

- The error messages from `check accounts` and `check recentassertions` are now clearer.

- The `check commodities` command now also checks commodities used in P directives. [#2280]

- The `commodities` command now also list commodities mentioned in P directives. [#2280]

- All of hledger's internal hidden (but searchable) tags can now be made visible by `print --verbose-tags`,  which is useful for troubleshooting `--infer-equity`,
  `--infer-costs`, and the detection of redundant costs and conversion postings. Also,

  - Some hidden tags have been renamed for clarity:
    `_modified` is now `_modified-transaction`,
    `_cost-matched` is now `_cost-posting`,
    `_conversion-matched` is now `_conversion-posting`.
  - The `generated-posting:` tag added by `--infer-equity` is now valueless.
  - The `modified-transaction:` tag added by `--auto` now appears on its own line.

- Using the `-NUM` shortcut (for `--depth NUM`) in a config file now works.

- Setting the `--color` option in a config file now works (except it does not affect `--debug` output, currently).

- The `--color` option's suggested values are now `yes`/`y`, `no`/`n`, or `auto`/`a`. `always` and `never` are no longer documented, though still supported.

- More compact and informative `--debug=2` output during valuation. Market prices are now shown using one line each, the known prices are listed, and the status of `--infer-market-prices` is shown.
  [#2287]

- More informative `--debug=7` output from CSV rules.

- The hledger packages have a new `debug` build flag. Builds made with ghc 9.10+ and this flag will show some kind of stack trace if the program exits with an error. (These will improve in future ghc versions.)

- Disabled the unused `ghcdebug` build flag and ghc-debug support, for now.

- Allow megaparsec 9.7.

- ghc 9.10 / base 4.20 are now supported.

Docs

- Windows: added tips for setting `LEDGER_FILE` (Amadeusz Wieczorek, hledger_site#119)
- csv: if blocks: explain matchers and field names better [#2289]
- import: rewrite; rename "date skipping" to "overlap detection"
- import: added tips for first import
- assertions: mention their behaviour with posting status
- journal: rewrite the Tags section
- pager: note that `help -p TOPIC` uses less; link to less FAQ
- query types: updates, add headings, mention tag:'s infix matching
- Regular expressions: note possible RTL/bidi limitation (?)
- Special characters: rewrite, more precision, mention some Windows differences
- Output formats: expand, document beancount and FODS output
- Text output: expand/consolidate terminal topics
- FODS output: describe the advantages over CSV (Henning Thielemann)
- Debug output: note that the --debug option doesn't work in config files.
- bal: improve --layout doc
- bal: also mention hledger.css and text encoding in balance doc
- html: note safari text encoding issue
- timedot: mention the common journal+timedot file setup [#2238]
- Install, manual: new shell completions doc. [#986]
- Config files: rewrite [#2231]
- examples/csv: an example of YNAB 4 data, and RTL text, with a workaround
- examples: hledger2beancount.conf

Scripts/addons

- bin/*: remove obsolete _FLAGS markers from --help
- examples/csv/csv-hledger-1.py: a python-based CSV converter script

API

- Hledger.Utils.IO's ansi color helpers now respect the --color option.
- Hledger.Utils.IO.rgb' now takes Float arguments instead of Word8.
- Hledger.Cli.Commands.Balance: export budgetReportAs* functions, for use in scripts.
  (Dmitry Astapov)


### hledger-ui 1.41


Breaking changes

- When built with ghc 9.10.1, error messages are displayed with two extra trailing newlines.

Fixes

- V (value) and C (cost) toggle keys once again reset each other as they should
  (broken since 1.21).
  (Gal Lakovnik Gorenec, [#2284])

- Bash shell completions are now up to date. [#986]

Features

Improvements

- Allow clipping depth to be configured per account (until adjusted in app, at least).
  (Stephen Morgan, [#2292])

- Added helix as a supported editor for the `e` key. (amano.kenji)

- Added --pager and --color options as in hledger, affecting command line help. Also --color=no forces use of the "terminal" theme.

- Added a new `debug` build flag. Builds made with ghc 9.10+ and this flag will show some kind of partial stack trace if the program exits with an error. These will improve in future ghc versions.

- Disabled the unused `ghcdebug` build flag and ghc-debug support, for now.

- Allow megaparsec 9.7.

- Allow brick 2.5, 2.6.

- Avoid brick 2.3.2, which doesn't build on windows.

- ghc 9.10 / base 4.20 are now supported.

Docs

- Mention that period navigation uses standard periods [#2293]
- Install, manual: new shell completions doc. [#986]


### hledger-web 1.41


Breaking changes

- When built with ghc 9.10.1, error messages are displayed with two extra trailing newlines.

Fixes

- hledger-web register no longer shows blank From/To accounts (broken since 1.33).
  (Henning Thielemann, [#2227]

- Autocompletions now work in newly created account fields. [#2215]

- Bash shell completions are now up to date. [#986]

Features

Improvements

- Added --pager and --color options as in hledger, affecting command line help.

- Added a new `debug` build flag. Builds made with ghc 9.10+ and this flag will show some kind of partial stack trace if the program exits with an error. These will improve in future ghc versions.

- Disabled the unused `ghcdebug` build flag and ghc-debug support, for now.

- allow megaparsec 9.7

- ghc 9.10 / base 4.20 are now supported.

Docs

- Install, manual: new shell completions doc. [#986]


### project changes 1.41


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


### credits 1.41


Simon Michael (@simonmichael),
Henning Thielemann (@thielema),
Dmitry Astapov (@adept),
Stephen Morgan (@Xitian9),
Bas van Dijk (@basvandijk),
Gal Lakovnik Gorenec,
amano.kenji,
gesh (@hseg).

[#986]:  https://github.com/simonmichael/hledger/issues/986
[#1846]: https://github.com/simonmichael/hledger/issues/1846
[#2215]: https://github.com/simonmichael/hledger/issues/2215
[#2222]: https://github.com/simonmichael/hledger/issues/2222
[#2223]: https://github.com/simonmichael/hledger/issues/2223
[#2225]: https://github.com/simonmichael/hledger/issues/2225
[#2227]: https://github.com/simonmichael/hledger/issues/2227
[#2231]: https://github.com/simonmichael/hledger/issues/2231
[#2238]: https://github.com/simonmichael/hledger/issues/2238
[#2241]: https://github.com/simonmichael/hledger/issues/2241
[#2254]: https://github.com/simonmichael/hledger/issues/2254
[#2280]: https://github.com/simonmichael/hledger/issues/2280
[#2281]: https://github.com/simonmichael/hledger/issues/2281
[#2284]: https://github.com/simonmichael/hledger/issues/2284
[#2287]: https://github.com/simonmichael/hledger/issues/2287
[#2289]: https://github.com/simonmichael/hledger/issues/2289
[#2292]: https://github.com/simonmichael/hledger/issues/2292
[#2293]: https://github.com/simonmichael/hledger/issues/2293
[#2295]: https://github.com/simonmichael/hledger/issues/2295



## 2024-09-09 hledger-1.40

**Config file support, sortable register, FODS output, prettier tables.**


### hledger 1.40


Fixes

- Account tags (and type declarations) declared in multiple files are now combined correctly. [#2202]
- Several kinds of report interval now choose a better start date:
  - `every Nth day of month from DATE` with periodic transactions [#2218]
  - `every M/D from DATE`
  - `every Nth WEEKDAY from DATE`
- The balance commands' html output no longer repeats the "Total" and "Net" headings when the totals row has multiple lines. And the layout has been improved and made more consistent with the text output.
- The `--tldr` flag now also works with the `tealdeer` tldr client.

Features

- You can now save command line options in a [config file](https://hledger.org/hledger.html#config-file), to be added to your hledger commands either on demand or automatically. (This supersedes the older arguments files feature.) This has been a popular feature request. It has pros and cons, and is experimental; your testing and feedback is welcome. It changes the nature of hledger somewhat, which I have marked by giving this release a more memorable version number (1.40).
- The balance commands can now output in FODS format, a spreadsheet file format accepted by LibreOffice Calc. If you use LibreOffice this is better than CSV because it works across locales (decimal point vs. decimal comma, character encoding stored in XML header), and it supports fixed header rows and columns, cell types (string vs. number vs. date), separation of number and currency, styles (bold), and borders. You can still extract CSV from FODS/ODS with the ods2csv utility from Hackage. (Henning Thielemann)
- The `register` report can now be sorted by date, description, account, amount, absolute amount, or a combination of these. (Michael Rees, [#2211])

Improvements

- Command line processing has been overhauled and should be more robust in certain cases, with tweaked error messages and debug output. Command-specific flags can now optionally appear before the command name. (Though writing them afterward is usually more readable. Addon-specific flags must still come last, after `--`.)
- The `--rules-file` option has been renamed to `--rules`. The old spelling is still supported as a hidden option.
- Weekly reports' week headings are now more compact, especially in single-year balance reports. ([#2204], Victor Mihalache)
- The `balance` command with no report interval, and also `balance --budget`, now support html output. (Henning Thielemann)
- In balance commands' html and csv output, "Total:" and "Net:" headings are now capitalised consistently.
- `bs`/`cf`/`is` reports now show the report interval in their title.
- The balance commands' text output with the `--pretty` flag now shows an outer table border and inter-column borders.
- The `check recentassertions` error message is now more readable.
- Timedot format now allows comment lines to be indented.
- When running the `tldr-node-client` client, auto-update of the tldr database is now suppressed.
- When running a tldr client fails, the warning now mentions the required `--render` flag. [#2201]
- The error message for unsupported regular expressions like `(?:foo)` has been improved.
- `--debug` has moved to "General help flags", making it available in more situations.
- Some verbose debug output from command line processing has been demoted to level 2.
- Parsing timedot files now gives debug output at level 9.
- Allow doclayout 0.5.

Docs

- The hledger/hledger-ui/hledger-web manuals now list all command options as shown by `--help`.
- Added an example config file, `hledger.conf.sample`.
- The `diff` and `prices` commands' help layout has been improved.
- `add`'s doc described the effect of `D` wrongly, now fixed.
- Date adjustments: rewrites and corrections
- Period headings: added
- Input: clarify that multiple -f options are allowed
- Scripts and add-ons: edits, list add-ons again
- Timeclock: edits, fix `ti`/`to` scripts
- Fixed "hledger and Ledger" links [hledger_site#112]
- examples/csv: Monzo CSV rules added
- examples/csv: Tiller CSV rules added
- examples/csv: Nordea CSV rules added (Arto Jonsson)

Scripts/addons

- `bin/bashrc` updates; add years, eachyear scripts
- `bin/hledger-simplebal`: ignore config files
- `bin/hledger-script-example`: explain shebang commands better
- `bin/hledger-register-max`: update/fix


### hledger-ui 1.40


Improvements

- The menu screen now supports the shift arrow and shift T keys, and its header shows any narrowed time period in effect, like other screens.
- Support brick 2.4.

Docs

- The description of the shift-T key (set period to today) has been fixed.
- The shift arrow keys and period narrowing have been clarified


### hledger-web 1.40


Improvements

- We now guess a more robust base url when `--base-url` is not specified. Now relative links to js/css resources will use the same hostname etc. that the main page was requested from, making them work better when accessed via multiple IP addresses/hostnames without an explicit `--base-url` setting. (A followup to [#2099], [#2100] and [#2127].)
- We now require a http[s] scheme in `--base-url`'s value. Previously it accepted just a hostname, and generated bad links.


### project changes 1.40


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
- Shake cmdhelp: renamed to cmddocs, and it now also updates the options listed in the manuals, and shows progress output.  It should be run (at some point) after changing commands' docs or options.
- Shake txtmanuals: silence all but wide table warnings
- just file cleanups; update to support just 1.28+
- just twih: date fixes
- just ghci: -fobject-code was a mistake, keep everything interpreted
- just functest: try again to reduce rebuilding/slowdowns when testing
- just installrel: update for .tar.gz
- ci scripts: cleanup, fix a macos-ism


### credits 1.40

Simon Michael (@simonmichael),
Henning Thielemann (@thielema),
Michael Rees (@reesmichael1),
Arto Jonsson (@artoj),
Victor Mihalache (@victormihalache).


[#2099]: https://github.com/simonmichael/hledger/issues/2099
[#2100]: https://github.com/simonmichael/hledger/issues/2100
[#2127]: https://github.com/simonmichael/hledger/issues/2127
[#2201]: https://github.com/simonmichael/hledger/issues/2201
[#2202]: https://github.com/simonmichael/hledger/issues/2202
[#2204]: https://github.com/simonmichael/hledger/issues/2204
[#2211]: https://github.com/simonmichael/hledger/issues/2211
[#2218]: https://github.com/simonmichael/hledger/issues/2218




## 2024-06-01 hledger-1.34
### hledger 1.34

**--tldr (short command examples), reorganised commands list, ghc-debug support**


Breaking changes

- `check ordereddates` no longer supports `--date2`. Also (not a breaking change): `--date2` and secondary dates are now officially [deprecated](https://hledger.org/1.34/hledger.html#secondary-dates) in hledger, though kept for compatibility.

Features

- You can now get a quick list of example command lines for hledger or its most useful subcommands by adding the `--tldr` flag (or just `--tl`).  For best appearance you should install the [`tldr`][tldr] client, though it's not required.

  These short "tldr pages" are a great counterbalance to verbose PTA docs. You can also use `tldr` without hledger to view the latest versions, or translations: `tldr hledger[-COMMAND]`. Or you can [browse tldr pages online](https://tldr.inbrowser.app/search?query=hledger+). Consider contributing translations! More tips at <https://github.com/simonmichael/hledger/tree/master/doc/tldr>.

[tldr]: https://tldr.sh

Improvements

- The `hledger` commands list has been reorganised, with commands listed roughly in the order you'll need them.

- The general flags descriptions in `--help` have been updated and grouped.

- Correctness checks now run in a documented order.  `commodities` are now checked before `accounts`, and `tags` before `recentassertions`. When both `ordereddates` and `assertions` checks are enabled, `ordereddates` now runs first, giving more useful error messages.

- `-I`/`--ignore-assertions` is now overridden by `-s`/`--strict` (or `check assertions`), enabling more flexible workflows. Eg you can `alias hl="hledger -I"` to delay balance assertions checking until you add `-s` to commands.

- `--color` and `--pretty` now also accept `y` or `n` as argument.

- When built with the `ghcdebug` flag and started with `--debug=-1`, hledger can be controlled by [ghc-debug] clients like ghc-debug-brick or a ghc-debug query script, for analysing memory/profile info.

[ghc-debug]: https://gitlab.haskell.org/ghc/ghc-debug

Fixes

- `hledger COMMAND --man` and `hledger help TOPIC --man` now properly scroll the man page to the TOPIC or COMMAND heading. The exact/prefix matching behaviour has been clarified in `help --help`.

- In journal files, `include` directives with trailing whitespace are now parsed correctly.

- The help command's help flags are now consistent with other commands (and it has `--debug` as a hidden flag).

- Build errors with GHC 8.10 have been fixed. [#2198]

Docs

- The tables of contents on hledger.org pages now just list top-level headings, (and the hledger manual structure has been adjusted for this). This makes the hledger manual on hledger.org more scannable and less scary.
- add: drop lengthy transcript, add simpler example commands (from tldr)
- Amount formatting: move down, it's not the best first topic
- balance: mention the `--summary-only` flag
- check: expand check descriptions
- examples: CSV rules: vanguard, fidelity, paypal updates
- Generating data: rewrite
- JSON output: link to OpenAPI spec
- manuals: synopsis, options cleanup/consistency
- Options: correction, NO_COLOR does not override --color
- PART 4: COMMANDS: reorganise into groups, like the CLI commands list.
- Period expressions: mention last day of month adjusting [#2005]
- Secondary dates: expand, and declare them deprecated.
- Time periods cleanup, simplify markup
- Unicode characters: mention UTF-8 on windows

Scripts/addons

- Added `hledger-pricehist`, an alias for the `pricehist` market price fetcher so that it can appear in hledger's commands list.

[#2005]: https://github.com/simonmichael/hledger/issues/2005
[#2198]: https://github.com/simonmichael/hledger/issues/2198


### hledger-ui 1.34


Features

- You can now get a quick list of example command lines by running with `--tldr` (or just `--tl`). For best appearance, install the [`tldr`][tldr] client, though it's not required.

Improvements

- The general flags in `--help` have been updated and grouped, consistent with hledger.

- When built with the `ghcdebug` flag and started with `--debug=-1`, hledger-ui can be controlled by [ghc-debug] clients like ghc-debug-brick or a ghc-debug query script, for analysing memory/profile info.

[tldr]: https://tldr.sh
[ghc-debug]: https://gitlab.haskell.org/ghc/ghc-debug


### hledger-web 1.34


Features

- You can now get a quick list of example command lines by running with `--tldr` (or just `--tl`). For best appearance, install the [`tldr`][tldr] client, though it's not required.

Improvements

- The general flags in `--help` have been updated and grouped, consistent with hledger.

- When built with the `ghcdebug` flag and started with `--debug=-1`, hledger-web can be controlled by [ghc-debug] clients like ghc-debug-brick or a ghc-debug query script, for analysing memory/profile info.

Docs

- A basic [OpenAPI specification][openapi.yaml] is provided for hledger-web's JSON-over-HTTP API. This is also applicable to `hledger print`'s JSON output format.

[ghc-debug]: https://gitlab.haskell.org/ghc/ghc-debug
[openapi.yaml]: https://github.com/simonmichael/hledger/blob/master/hledger-web/config/openapi.yaml
[tldr]: https://tldr.sh


### project changes 1.34


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
- Github release binaries for mac and linux are now in .tar.gz format (no longer tarred and zipped). 
- There is a new `oldest` workflow for testing the oldest GHC we support (currently 8.10.7).
- The `binaries-mac-x64` workflow has been bumped from GHC 9.4 to 9.8.
- The master branch's `ci` workflow has been updated to Ubuntu 24.04 and uses the preinstalled GHC & stack, saving some work.
- `md-issue-refs` helps generate markdown issue links.
- `relnotes.hs` helps generate release notes from changelogs.
- The project `Makefile` has now been fully replaced by `Justfile`.


### credits 1.34


Simon Michael (@simonmichael)



## 2024-05-02 hledger-1.33.1

### hledger 1.33.1

- process >=1.6.19.0 seems not strictly needed and is no longer required,
  improving installability.
  [#2149]

- `print` and `close` now show a trailing decimal mark on cost amounts also,
  when needed to disambiguate a digit group mark.

- The balance commands' HTML output now includes digit group marks when
  appropriate (fixes a regression in 1.25).
  [#2196]

- The add command no longer shows ANSI escape codes in terminals that
  don't support them.

- Doc updates:
  - import: Skipping -> Date skipping, discuss commodity styles more
  - csv: Amount decimal places: expand, note import behaviour

### hledger-ui 1.33.1

- Require vty-windows-0.2.0.2+ to avoid display problems in recent
  MS Terminal on Windows.

- process >=1.6.19.0 seems not strictly needed and is no longer required,
  improving installability.
  [#2149]

### hledger-web 1.33.1

- Support base64 >=1.0

### credits 1.33.1

- Simon Michael (@simonnmichael)

[#2149]: https://github.com/simonmichael/hledger/issues/2149
[#2196]: https://github.com/simonmichael/hledger/issues/2196


## 2024-04-18 hledger-1.33

**`close` enhancements, hledger-ui 'dark' theme, GHC 9.8 support, Apple ARM binaries**


### hledger 1.33


Breaking changes

- `expr:` boolean queries, introduced in hledger 1.30 (2023),
  no longer allow `date:` to be used within an `OR` expression,
  avoiding unclear semantics which confuse our reports.
  If you'd like to improve this, see #2178. [#2177] [#2178]

- Some error messages (date parse errors, balance assertion failures) have changed,
  which might affect error-parsing add-ons like flycheck-hledger.



Fixes

- `add`, `import`, `web`:
  On MS Windows, don't allow writing to files whose name ends with a period,
  since it can cause data loss; raise an error instead.
  I made this change in hledger 1.15 (2019), but it never worked; now it does.
  [#1056]

- `balance --budget`:
  The budget report in tree mode was omitting parent accounts with no actual or goal amounts
  and a single child, instead of showing them as a prefix of the child's name.
  Now it always shows them, on a line of their own (a bit like `--no-elide`).
  It's not a perfect fix, but the budget report code is twisty.
  [#2071]

- `check tags`:
  The special `date` and `date2` tags,
  and the `modified` and `_modified` tags generated by `--auto`,
  are now also implicitly declared.
  [#2148], [#2119]

- Regular expression match group references in CSV `if` rules,
  added in hledger 1.32, did not work right when multiple if conditions matched a CSV record.
  This is now fixed; match group references are now scoped to their local `if` block.
  [#2158] (Jonathan Dowland)

- `roi` now correctly interacts with `--value`.
  [#2190] (Dmitry Astapov)

- hledger now requires process-1.6.19.0+ to avoid any vulnerabilities on Windows from
  [HSEC-2024-0003](https://haskell.github.io/security-advisories/advisory/HSEC-2024-0003.html).



Features

- `close` has had some enhancements for usability ([#2151]):

  - It now excludes equity accounts by default; and always excludes the balancing account.

  - It has new `--assert` and `--assign` modes, for generating transactions which
    make balance assertions or balance assignments.
    There is also a `--assertion-type` option for changing the assertion/assignment type.

  - It adds a tag to generated transactions, named `start`, `assert` or `retain`
    depending on the mode.

  - The `start` tag's value will be a guess of the new file's name,
    inferred by incrementing a year number in the current file name.
    Eg, `hledger close --migrate` on `2024.journal` will add the tag
    `start:2025.journal` to both transactions.
    Tags like this can be helpful when reading multiple files,
    for excluding closing and opening balances transactions
    (eg with `not:tag:start=2025`).

  - You can set different tag values by writing the mode option with an argument.
    Eg: `hledger close --migrate=NEWFILENAME`.

  - `close` now supports `--round` for controlling display of decimal places, like `print`.

  - `examples/multi-year/` is examples/tutorial for managing multiple files with the `close` command.



Improvements

- `stats` has had some improvements:

  - It now also shows some information about memory usage, when hledger is built or is running
    with the GHC Run Time System available. (Try `hledger stats +RTS -T`.)

  - The default output is now more private, hiding file paths and commodity symbols.
    Those can be added by the new `-v/--verbose` flag.

  - Output is now more compact and more likely to fit in 80-character lines.

  - When generating multiple outputs with a report interval, reports are now
    separated by an empty line.

- Several more kinds of Unicode space are allowed for separating digit groups in numbers.
  We now support (my guess of the ones that might show up in real world CSV files):
  space,
  no-break space,
  en space,
  em space,
  punctuation space,
  thin space,
  narrow no-break space,
  medium mathematical space.

- Glob patterns in `$LEDGER_FILE` are now respected.
  Eg, setting it to `*.journal` or `2???.journal` now works as expected.

- When hledger is reading a symbolically-linked journal file,
  relative paths in include directives are now evaluated
  relative to the directory of the real linked file,
  not the directory containing the symbolic link.

- Date parse errors are now simpler and clearer.
  They no longer try to repeat (a reconstruction of) the problem date,
  since the actual problem date is already visible in the highlighted file excerpt.

- Balance assertion error messages are clearer,
  and show the difference between expected and actual balance again.
  With --debug=2 they also show costs.

- `tsv:` and `ssv:` file name prefixes are now supported in addition to `csv:`.
  They force the file to be read as a .tsv (tab separated values) or .ssv (semicolon-separated values) file.
  [#2164] (Michael Rees)

- In CSV rules files, commented lines are now allowed within "if tables". (Dmitry Astapov)

- `balance --budget`'s CSV and TSV output now shows zeroes instead of nothing when there's no amount.

- `bs`,`bse`,`cf`,`is`:
  Report sections which are empty now show zero as their subtotal. (aragaer)

- `print` and `close` add a trailing decimal mark when needed to disambiguate a single digit group mark.
  They now also do this for balance assertion and balance assignment amounts.
  [#2176]

- hledger can now be built with GHC 9.8.

- hledger now requires safe >=0.3.20.



Docs

- add version annotations for features added in 1.32 (hamzashezad)
- add Text encoding section, mention UTF-8 BOM support [#2189]
- journal: note that `payee` and `tag` directives can't have tags in comments, unlike `account`.
- journal: clarify how auto postings work.
- journal: list built-in special tag names
- journal: description/payee/note: clarify
- journal: amounts/commodities/numbers: cleanups
- journal: move intro before cheatsheet
- journal: transactions: explain transaction balancing [#2135]
- journal: transactions: mention debits, credits and sign
- journal: commodity directive: clarify & fix scope of effects [#2135]
- journal: D directive: clarify scope [#2191]
- journal: split Decimal marks, Digit group marks
- journal: move complex commodity styles, lot notation topics later
- journal: drop redundant/wrong Querying with cost or value section
- journal: cheatsheet: cleanups
- journal: assertions and ordering/commodities/subaccounts: cleanups
- csv: matchers: clarify, mention !/& limitation [#2088]
- csv: if tables: explain comments and order of application (Dmitry Astapov)
- add: document the effect of D default commodity directive [#815]
- balance: cleanups
- balance: budget report: moved "Budgets and subaccounts" to the Cookbook.
- bs,bse,cf,is: update sample output
- bse: note requirements for checking the accounting equation
- close: rewrite, give a better technique for excluding opening/closing balance txns [#2151]
- import: rename "deduplication" to "skipping", and rewrite
- examples: expand READMEs, clarify status for examples
- examples: invoicing: cleanups, renames
- examples: invoicing: pandoc-make-invoice: don't write to $LEDGER_FILE; remove the REMOVE THIS LINE line
- examples: csv: daedalus-transactions: update for current daedalus [#2171]



Scripts/addons

- hledger-bar, hledger-simplebal: shellcheck fixes, cleanups (Colin Dean)

- hledger-bar: Fix an error when NO_COLOR is not defined [#2159].
  Also, it's now more compliant with the no-color.org spec:

    Command-line software which adds ANSI color to its output by default
    should check for a NO_COLOR environment variable that, when present
    and not an empty string (regardless of its value), prevents the
    addition of ANSI color.

  so one can now temporarily override $NO_COLOR=1 in the environment by
  setting it empty: NO_COLOR= hledger ...

- hledger-txnsbycat: added



API

- move readFileStrictly to hledger-lib:Hledger.Utils.IO



[#815]:  https://github.com/simonmichael/hledger/issues/815
[#1056]: https://github.com/simonmichael/hledger/issues/1056
[#2071]: https://github.com/simonmichael/hledger/issues/2071
[#2088]: https://github.com/simonmichael/hledger/issues/2088
[#2119]: https://github.com/simonmichael/hledger/issues/2119
[#2135]: https://github.com/simonmichael/hledger/issues/2135
[#2135]: https://github.com/simonmichael/hledger/issues/2135
[#2148]: https://github.com/simonmichael/hledger/issues/2148
[#2151]: https://github.com/simonmichael/hledger/issues/2151
[#2151]: https://github.com/simonmichael/hledger/issues/2151
[#2158]: https://github.com/simonmichael/hledger/issues/2158
[#2159]: https://github.com/simonmichael/hledger/issues/2159
[#2164]: https://github.com/simonmichael/hledger/issues/2164
[#2171]: https://github.com/simonmichael/hledger/issues/2171
[#2176]: https://github.com/simonmichael/hledger/issues/2176
[#2177]: https://github.com/simonmichael/hledger/issues/2177
[#2178]: https://github.com/simonmichael/hledger/issues/2178
[#2189]: https://github.com/simonmichael/hledger/issues/2189
[#2190]: https://github.com/simonmichael/hledger/issues/2190
[#2191]: https://github.com/simonmichael/hledger/issues/2191


### hledger-ui 1.33


Fixes

- Require process 1.6.19.0+ to avoid any vulnerabilities on Windows from
  [HSEC-2024-0003](https://haskell.github.io/security-advisories/advisory/HSEC-2024-0003.html).

Features

- Add a `dark` theme. (Jonathan Dowland)

Improvements

- Allow building with GHC 9.8.

- Require safe >=0.3.20.


### hledger-web 1.33


Fixes

- Exclude base64 >=1.0 to avoid compilation failure. [#2166]

- Preserve line breaks when showing an error message. [#2163] (Martijn van der Ven)

Improvements

- Zero amounts are now shown with their commodity symbol.
  This was mainly to make the sidebar more informative,
  but also affects and hopefully helps amounts displayed elsewhere.
  [#2140]

- Amounts in the sidebar now also have the `amount` HTML class.

- Allow building with GHC 9.8.

- Require safe >=0.3.20.

Docs

- Mention the `-E/--empty` flag for hiding zeros,
  the non-display of costs,
  and non-zeros that look like zero because of hidden costs.

[#2140]: https://github.com/simonmichael/hledger/issues/2140
[#2163]: https://github.com/simonmichael/hledger/issues/2163
[#2166]: https://github.com/simonmichael/hledger/issues/2166


### project changes 1.33


Misc

- Apple ARM binaries are now included in github releases.

Docs

- REGRESSIONS: we now split the bounty between finder and fixer
- move Developer docs, MOCKUPS, investment-accounting-features to main repo
- merge LINKS into dev docs page; cleanup
- drop unused BACKLOG, TODO pages


### credits 1.33


Simon Michael,
Jonathan Dowland,
Ilja Kocken,
Colin Dean,
Dmitry Astapov,
Vekhir,
ShrykeWindgrace,
Martijn van der Ven,
Michael Rees,
aragaer,
hamzashezad.




## 2024-01-28 hledger-1.32.3

### hledger 1.32.3

Fixes

- A performance slowdown since 1.29, especially noticeable with many
  accounts and transactions, has been fixed. [#2153]

- Balance assertions involving mixed-cost balances are checked correctly again
  (a regression in 1.30). [#2072], [#2137], [#2150]

- import --catchup works again (a regression in 1.32). [#2156]

- --anon is now a deprecated hidden flag that raises an error,
  but is still usable as --obfuscate (also hidden). [#2133]

- Balance assertion error messages are clearer, and show the diff again.

### hledger-ui 1.32.3

- Use hledger-1.32.3

- Allow vty 6.2, brick 2.3

### hledger-web 1.32.3

- Use hledger-1.32.3

### project changes 1.32.3

- bin/hledger-bar: Fix an error when NO_COLOR is not defined;
  allow color when NO_COLOR is defined but empty, per no-color spec;
  and fix shellcheck warnings.
  [#2159] (Colin Dean, Simon Michael)

- bin/hledger-simplebal: Fix shellcheck warnings. (Colin Dean)

### credits 1.32.3

Simon Michael,
Colin Dean.

[#2159]: https://github.com/simonmichael/hledger/issues/2159
[#2156]: https://github.com/simonmichael/hledger/issues/2156
[#2153]: https://github.com/simonmichael/hledger/issues/2153
[#2150]: https://github.com/simonmichael/hledger/issues/2150
[#2133]: https://github.com/simonmichael/hledger/issues/2133

## 2023-12-31 hledger-1.32.2

### hledger 1.32.2

Fixes

- In CSV field assignments,  %FIELD interpolation and `\n` can be used together again. [#2134]

- In timedot data, numbers beginning with a decimal point are accepted again. [#2130]

- In a `balance --budget` report, `--layout=tall` no longer hides commodity symbols.

- Value reports seeing a pathological price chain with 1000 or more
  steps now write their warning to the console, not a debug log file.

Improvements

- Allow megaparsec 9.6

Docs

- Updated: 
  Queries,
  Periodic transactions,
  Auto postings,
  Assertions and costs,
  Budget report

### hledger-ui 1.32.2

Features

- hledger-ui is now available on Windows (ShrykeWindgrace)

Improvements

- Use Notepad as default editor on Windows (ShrykeWindgrace)

- Allow brick 2.2 (Vekhir)

- Allow megaparsec 9.6

### hledger-web 1.32.2

Fixes

- The `--base-url` option works again. [#2127], [#2100]

- Startup messages are more accurate and informative, eg with `--socket`. [#2127]

- The non-working `--file-url` option has been dropped for now. [#2139]

Improvements

- Allow megaparsec 9.6

- hledger-web's tests now respect and can test command line options.

- hledger-web's tests now run the app at 127.0.0.1 and port 5000,
  rather than "any of our IPv4 or IPv6 addresses" and 3000.


[#2139]: https://github.com/simonmichael/hledger/issues/2139
[#2134]: https://github.com/simonmichael/hledger/issues/2134
[#2130]: https://github.com/simonmichael/hledger/issues/2130
[#2127]: https://github.com/simonmichael/hledger/issues/2127
[#2100]: https://github.com/simonmichael/hledger/issues/2100

## 2023-12-07 hledger-1.32.1

### hledger 1.32.1

- Fixed: `import` with multiple files now updates .latest files correctly. ([#2125])

- Fixed: `print --round=hard` now properly pads/rounds amounts with inferred costs. ([#2123])

- CSV matcher syntax: mention that ! and & can't be used in the same line yet. ([#2088])

- Drop the "a difference of ..." line from balance assertion failure output.
  I feel it made the message harder to read and isn't really necessary.

- Declaring the empty payee name with `payee ""` now works,
  to let `hledger check payees` accept payee-less transactions.
  ([#2119])

- Built-in tags with special meaning like `type:` and `t:` are now implicitly declared,
  so using type: in account declarations or generating t: with timedot letters 
  won't cause `hledger check tags` to fail.
  ([#2119])

### hledger-ui 1.32.1

- Use hledger-1.32.1

### hledger-web 1.32.1

- Use hledger-1.32.1

[#2125]: https://github.com/simonmichael/hledger/issues/2125
[#2123]: https://github.com/simonmichael/hledger/issues/2123
[#2119]: https://github.com/simonmichael/hledger/issues/2119


## 2023-12-01 hledger-1.32

**More precision control, beancount output, TSV output, --summary-only,
strict/idempotent import, CSV rule enhancements, timedot letters, fixes.**

### hledger 1.32

Breaking changes

- Display styles and display precision are now managed more carefully
  during calculations and output, fixing a number of issues ([#2111],
  "Precisiongeddon").  In brief:

  - Cost and value reports, such as `print -V`, now (1) consistently
    apply commodity display styles, and (2) do not add or discard
    decimal digits unnecessarily.  ([#2105])
  
  - When "infinite decimals" arise during calculations (eg in value
    reports, or in `prices` or `roi` output), these are now shown
    limited to 8 decimal digits rather than 255.
  
  - Non-print-like reports no longer add trailing decimal marks to
    disambiguate digit group marks (this was an unintended regression
    in 1.31). ([#2115])
    
  - We now document number formatting adjustments made in certain
    reports and output formats (hledger manual > REPORTING CONCEPTS >
    Amount formatting, parseability).


Features

- Timedot format supports a new letters syntax for easier tagged time logging.
  ([#2116])

- `print` has a new `beancount` output format for exporting to Beancount.
  This prints journal output more likely (though not guaranteed) to
  be readable by Beancount.

- In CSV rules, matchers using regular expressions can now interpolate
  their matched texts into the values they assign to fields (field
  assignment values can reference match groups).
  ([#2009]) (Jonathan Dowland)
  
- In CSV rules, matchers can be negated by prepending `!`.
  ([#2088]) (bobobo1618)

- Multi-column balance reports (from `bal`, `bs`, `is` etc.) can use
  the new `--summary-only` flag (`--summary` also works) to display
  just the Total and Average columns (if enabled by `--row-total` and
  `-A/--average`) and hide the rest.
  ([#1012]) (Stephen Morgan)

- All commands that suport csv output now also support `tsv`
  (tab-separated values) output. The data is identical, but the fields
  are separated by tab characters and there is no quoting or
  escaping. Tab, carriage return, and newline characters in data are
  converted to spaces (this should rarely if ever happen in practice).
  ([#869]) (Peter Sagerson).


Improvements

- Journal format no longer fails to parse Ledger-style lot costs with spaces
  after the `{`, improving Ledger compatibility.

- `import` now does not update any .latest files until it has run
  without error (no failing strict checks, no failure while writing
  the journal file). This makes it more idempotent, so you can run it
  again after fixing problems.

- `print` now shows zeros with a commodity symbol and decimal digits
  when possible, preserving more information.

- `print` has a new option for controlling amount rounding ([#2085]):
  
  - `--round=none` - show amounts with original precisions (default;
    like 1.31; avoids implying less or more precision than was
    recorded)

  - `--round=soft` - add/remove decimal zeros in non-cost amounts
    (like 1.30 but also affects balance assertion amounts)

  - `--round=hard` - round non-cost amounts (can hide significant digits)

  - `--round=all`  - round all amounts and costs

  For the record:
  `print` shows four kinds of amount: posting amounts,
  balance assertion amounts, and costs for each of those.
  Past hledger versions styled and rounded these inconsistently.
  Since 1.31 they are all styled, and since 1.32 they are rounded as follows:
  
  | hledger-1.32 print | amt  | cost | bal  | balcost |
  |--------------------|------|------|------|---------|
  | (default)          | none | none | none | none    |
  | --round=soft       | soft | none | soft | none    |
  | --round=hard       | hard | none | hard | none    |
  | --round=all        | hard | hard | hard | hard    |

- The `prices` command has had a number of fixes and improvements ([#2111]):

  - It now more accurately lists the prices that hledger would use
    when calculating value reports (similar to what you'd see with
    `hledger bal -V --debug=2`).
    
  - The --infer-reverse-prices flag was confusing, since we always
    infer and use reverse prices; it has been renamed to `--show-reverse`.
    
  - `--show-reverse` and `--infer-market-prices` flags now combine properly.
    
  - `--show-reverse` now ignores zero prices rather than giving an error.
    
  - Price amounts are now shown styled.
  
  - Price amounts are now shown with all their decimal digits; or with
    8 decimal digits if they appear to be infinite decimals (which can
    arise with reverse prices).
    
  - Filtering prices with `cur:` or `amt:` now works properly.
    

Fixes

- `print` now styles balance assertion costs consistently, like other
  amounts.

- `import` now works with `-s/--strict`.
  And more generally, when reading multiple input files, eg with
  multiple `-f` options, strict checks are done only for the overall
  combined journal (not for each individual file).
  ([#2113])

- `tag:` queries now work when reading CSV files. ([#2114])

- Using a `.json` or `.sql` file extension with `-o`/`--outputfile`
  now properly selects those output formats.

- Auto postings no longer break redundant equity/cost detection and
  transaction balancing. ([#2110])
  
- Amounts set by balance assignment now affect commodity styles again.
  ([#2091], a regression in 1.30)

- Timedot quantities with units are parsed more accurately.
  Eg a quantity like "15m" was evaluated as 0.249999999 not 0.25,
  and since hledger 1.21, it was printed that way also.
  Now we round such quantities to two places during parsing to get
  exact quarter-hour amounts. ([#2096])

- The `demo` command no longer triggers a JSON decode error in asciinema
  2.3.0. It now also shows a better error message if asciinema fails
  ([#2094]).

- Failing balance assertions with a cost now show correct markers in
  the error message. ([#2083])


Docs

- New:
  
  - Amount formatting, parseability
  - Started new code docs for developers, based in the Hledger module's haddock

- Updated:
  
  - aregister
  - commodity directive
  - Commodity display style
  - if table
  - Decimal marks, digit group marks
  - Regular expressions
  - Timedot

  
### hledger-ui 1.32

Fixes

- The V key now preserves the valuation mode specified at the command
  line, if any. ([#2084])

- The hledger-ui package no longer wastefully builds its modules
  twice.


### hledger-web 1.32

Features

- The hledger-web app on the Sandstorm cloud platform has been updated to
  a recent version (Jacob Weisz, [#2102]), and now uses Sandstorm's access
  control. (Jakub Zárybnický, [#821])

Improvements

- The --capabilities and --capabilities-header options have been replaced
  with an easier `--allow=view|add|edit|sandstorm` option.
  `add` is the default access level, while `sandstorm` is for use on Sandstorm.
  UI and docs now speak of "permissions" rather than "capabilities".
  ([#834])

- The Sandstorm app's permissions and roles have been renamed for clarity. ([#834])

- Permissions are now checked earlier, before the web app is started,
  producing clearer command line errors when appropriate.

- Account's `adeclarationinfo` field is now included in JSON output. ([#2097]) (S. Zeid)

Fixes

- The app can now serve on address 0.0.0.0 (exposing it on all interfaces),
  which previously didn't work.
  ([#2099]) (Philipp Klocke)

- The broken "File format help" link in the edit form has been fixed. ([#2103])


### project changes 1.32

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


### credits 1.32

Simon Michael,
Jonathan Dowland,
S. Zeid,
Charlie Ambrose,
Jacob Weisz,
Peter Sagerson,
Philipp Klocke,
Stephen Morgan,
bobobo1618.

[#2116]: https://github.com/simonmichael/hledger/issues/2116
[#2115]: https://github.com/simonmichael/hledger/issues/2115
[#2114]: https://github.com/simonmichael/hledger/issues/2114
[#2113]: https://github.com/simonmichael/hledger/issues/2113
[#2111]: https://github.com/simonmichael/hledger/issues/2111
[#2110]: https://github.com/simonmichael/hledger/issues/2110
[#2105]: https://github.com/simonmichael/hledger/issues/2105
[#2103]: https://github.com/simonmichael/hledger/issues/2103
[#2102]: https://github.com/simonmichael/hledger/issues/2102
[#2099]: https://github.com/simonmichael/hledger/issues/2099
[#2097]: https://github.com/simonmichael/hledger/issues/2097
[#2096]: https://github.com/simonmichael/hledger/issues/2096
[#2094]: https://github.com/simonmichael/hledger/issues/2094
[#2091]: https://github.com/simonmichael/hledger/issues/2091
[#2088]: https://github.com/simonmichael/hledger/issues/2088
[#2085]: https://github.com/simonmichael/hledger/issues/2085
[#2084]: https://github.com/simonmichael/hledger/issues/2084
[#2083]: https://github.com/simonmichael/hledger/issues/2083
[#2079]: https://github.com/simonmichael/hledger/issues/2079
[#2068]: https://github.com/simonmichael/hledger/issues/2068
[#2065]: https://github.com/simonmichael/hledger/issues/2065
[#2050]: https://github.com/simonmichael/hledger/issues/2050
[#2045]: https://github.com/simonmichael/hledger/issues/2045
[#2041]: https://github.com/simonmichael/hledger/issues/2041
[#2040]: https://github.com/simonmichael/hledger/issues/2040
[#2039]: https://github.com/simonmichael/hledger/issues/2039
[#2034]: https://github.com/simonmichael/hledger/issues/2034
[#2032]: https://github.com/simonmichael/hledger/issues/2032
[#2025]: https://github.com/simonmichael/hledger/issues/2025
[#2024]: https://github.com/simonmichael/hledger/issues/2024
[#2023]: https://github.com/simonmichael/hledger/issues/2023
[#2020]: https://github.com/simonmichael/hledger/issues/2020
[#2018]: https://github.com/simonmichael/hledger/issues/2018
[#2015]: https://github.com/simonmichael/hledger/issues/2015
[#2012]: https://github.com/simonmichael/hledger/issues/2012
[#2011]: https://github.com/simonmichael/hledger/issues/2011
[#2009]: https://github.com/simonmichael/hledger/issues/2009
[#2007]: https://github.com/simonmichael/hledger/issues/2007
[#1997]: https://github.com/simonmichael/hledger/issues/1997
[#1996]: https://github.com/simonmichael/hledger/issues/1996
[#1982]: https://github.com/simonmichael/hledger/issues/1982
[#1978]: https://github.com/simonmichael/hledger/issues/1978
[#1977]: https://github.com/simonmichael/hledger/issues/1977
[#1970]: https://github.com/simonmichael/hledger/issues/1970
[#1967]: https://github.com/simonmichael/hledger/issues/1967
[#1966]: https://github.com/simonmichael/hledger/issues/1966
[#1965]: https://github.com/simonmichael/hledger/issues/1965
[#1962]: https://github.com/simonmichael/hledger/issues/1962
[#1961]: https://github.com/simonmichael/hledger/issues/1961
[#1959]: https://github.com/simonmichael/hledger/issues/1959
[#1953]: https://github.com/simonmichael/hledger/issues/1953
[#1950]: https://github.com/simonmichael/hledger/issues/1950
[#1942]: https://github.com/simonmichael/hledger/issues/1942
[#1936]: https://github.com/simonmichael/hledger/issues/1936
[#1933]: https://github.com/simonmichael/hledger/issues/1933
[#1932]: https://github.com/simonmichael/hledger/issues/1932
[#1927]: https://github.com/simonmichael/hledger/issues/1927
[#1921]: https://github.com/simonmichael/hledger/issues/1921
[#1919]: https://github.com/simonmichael/hledger/issues/1919
[#1915]: https://github.com/simonmichael/hledger/issues/1915
[#1909]: https://github.com/simonmichael/hledger/issues/1909
[#1907]: https://github.com/simonmichael/hledger/issues/1907
[#1905]: https://github.com/simonmichael/hledger/issues/1905
[#1889]: https://github.com/simonmichael/hledger/issues/1889
[#1879]: https://github.com/simonmichael/hledger/issues/1879
[#1870]: https://github.com/simonmichael/hledger/issues/1870
[#1839]: https://github.com/simonmichael/hledger/issues/1839
[#1770]: https://github.com/simonmichael/hledger/issues/1770
[#1763]: https://github.com/simonmichael/hledger/issues/1763
[#1754]: https://github.com/simonmichael/hledger/issues/1754
[#1562]: https://github.com/simonmichael/hledger/issues/1562
[#1436]: https://github.com/simonmichael/hledger/issues/1436
[#1229]: https://github.com/simonmichael/hledger/issues/1229
[#1220]: https://github.com/simonmichael/hledger/issues/1220
[#1012]: https://github.com/simonmichael/hledger/issues/1012
[#869]: https://github.com/simonmichael/hledger/issues/869
[#834]: https://github.com/simonmichael/hledger/issues/834
[#821]: https://github.com/simonmichael/hledger/issues/821

## 2023-09-03 hledger-1.31

**More tolerant equity/cost matching; print amounts in original style; multi-pivot.**

### hledger 1.31

Features

- Multi-pivot: the --pivot option now accepts multiple arguments,
  colon-delimited, to construct account names from multiple fields.
  ([#2050], Eric Mertens)

Improvements

- The `print` command now more closely replicates the original journal
   amount styles, which is helpful when round-tripping / cleaning up
   journal files:

  - Amounts in conversion transactions could be displayed rounded to a
    lower precision; this no longer happens.
    ([#2079])

  - Amounts could be displayed with extra zeros after the decimal mark;
    this no longer happens.

  - Amounts could display with a different precision if the journal
    included a timedot file; this no longer happens.

  - Costs in balance assertions were not displayed with standard
    styles like other amounts; now they are.

  - Zero amounts were always shown as just "0"; now they are shown
    with their original commodity symbol and style.  (And if an
    inferred amount has multiple zeros in different commodities, a
    posting is displayed for each of these.)
  
- `print` no longer displays numbers with a single digit group mark
  and no decimal mark, which are ambiguous and hard to re-parse.  Now
  if a number has digit group marks the decimal mark will always be
  shown also.  Eg `1,000` (where the comma is a thousands separator)
  is now shown as `1,000.`.

- The check command's 
  `balancedwithautoconversion` and `balancednoautoconversion` checks
  have been renamed to `autobalanced` and `balanced`.

- `hledger check recentassertions` now reports failures at the first
  posting that's more than 7 days later than the latest balance
  assertion (rather than at the balance assertion).  This is the thing
  actually triggering the error, and it is more likely to be visible
  or at least closer when you are working at the end of a journal
  file.

  Also, the suggested sample balance assertion now uses the same
  commodity symbol as in the failing posting (the first, if there are
  more than one); and, no longer includes a cleared mark.

- The import command now shows the file path being imported to.

- With --pivot, `desc` is now the preferred spelling for pivoting on
  description.

- The demo command now ignores an invalid journal file, like the other
  HELP commands.

- Debug output for equity conversion postings has been improved,
  making troubleshooting easier.

- Allow aeson 2.2, megaparsec 9.5.

Fixes

- In journal files, valid multicommodity transactions where the
  matching non-equity postings can't be auto-detected are no longer
  considered an error (as they were in hledger 1.29 and 1.30).  Now,
  such transactions are accepted, and --infer-cost has no effect on
  them. This is similar to the behaviour of --cost, --infer-equity,
  and --infer-market-prices.  ([#2045])

- In journal files, equity conversion postings are now detected more
  tolerantly, using the same precision as the conversion posting's
  amount ([#2041]). Eg, the following transaction is now accepted:

      2023-01-01
          Assets               -84.01 USD @ 2.495 GEL
		    ; ^ 209.60495 GEL, recognised as a match for the 209.60 below
          Equity:Conversion     84.01 USD
          Equity:Conversion   -209.60 GEL
          Assets               209.60 GEL

- The roi command now reports TWR per period and overall TWR for
  multi-period reports.
  ([#2068], Dmitry Astapov)

- The commands list no longer shows bar when hledger-bar is not installed ([#2065]),
  and had a few other cleanups.

### hledger-ui 1.31

Improvements

- Allow megaparsec 9.5

### hledger-web 1.31

Improvements

- Allow aeson 2.2, megaparsec 9.5

### project changes 1.31

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

### credits 1.31

Simon Michael,
Dmitry Astapov,
Eric Mertens,
Jay Neubrand,
Jonathan Dowland.


## 2023-06-02 hledger-1.30.1

### hledger 1.30.1

Fixes

- Add missing files to Hackage release, making it buildable.

Docs

- Replace note about repeated options.

## 2023-06-01 hledger-1.30

**Boolean queries, easier CSV file management, built-in demos, hledger-ui cash accounts screen, fixes.**

### hledger 1.30

Breaking changes

- The CSV reader now properly skips all empty lines, as specified by docs.
  Previously, inner empty lines were not being skipped automatically.
  You might need to adjust the `skip` count in some CSV rules files.
  ([#2024])

- Timedot format now generates a single multi-posting transaction per
  date line, and supports comments and tags on all lines.
  ([#1754])

- Timeclock format now supports comments and tags.
  Descriptions can no longer contain semicolons.
  ([#1220])

Features

- CSV rules files can now be read directly, as in
  `hledger -f foo.csv.rules CMD`. By default this will read data
  from foo.csv in the same directory.
  
- CSV rules files can use a new `source FILE` rule to specify the data file,
  with some convenience features:

  - If the data file does not exist, it is treated as empty, not an
    error.

  - If FILE is a relative path, it is relative to the rules file's
    directory. If it is just a file name with no path, it is relative
    to `~/Downloads/`.

  - If FILE is a glob pattern, the most recently modified matched file
    is used.

  This helps remove some of the busywork of managing CSV downloads.
  Most of your financial institutions's default CSV filenames are
  different and can be recognised by a glob pattern.  So you can put a
  rule like `source Checking1*.csv` in foo-checking.csv.rules,
  periodically download CSV from Foo's website accepting your browser's
  defaults, and then run `hledger import checking.csv.rules` to import
  any new transactions. The next time, if you have done no cleanup, your
  browser will probably save it as something like Checking1-2.csv, and
  hledger will still see that because of the * wild card. You can choose
  whether to delete CSVs after import, or keep them for a while as
  temporary backups, or archive them somewhere.
  (Experimental)

- The balance command has a new --count report type
  which reports posting counts instead of amounts.

- Full boolean queries, allowing arbitrary use of AND, OR, NOT
  (case insensitive) and parentheses for grouping, are now supported.
  For backward compatibility, these require an `expr:` prefix.
  Existing queries work as before, and you can mix and match the
  old and new styles if you like.
  (Chris Lemaire)
 
- demo: This new command plays brief asciinema screencasts explaining
  various features and use cases. We will add more of these over time.
  (Experimental)

Improvements

- Add-on commands can now have `.js`, `.lua`, or `.php` file extensions.

- Generated and modified transactions and postings have the same hidden
  tags (beginning with underscore) as before, but no longer have visible
  tags added by default. Use `--verbose-tags` if you want them added.

- We now try harder to ensure `less` (and its `more` mode) show our
  ANSI formatting properly in help output.
  If you use some other $PAGER, you may have to configure it yourself
  to show ANSI (or disable ANSI entirely, eg by setting NO_COLOR=1).
  This is now documented in hledger manual > Paging.
  ([#2015])

- The print command's `--match` mode has been refined.
  Previously, similarity completely outweighed recency, so a
  slightly-more-similar transaction would always be selected no matter
  how old it was. Now similarity and recency are more balanced,
  and it should produce the desired transaction more often.
  There is also new debug output (at debug level 1) for troubleshooting.

- Miscellaneous commands list updates.
  Help has been added for all published add-on commands (like hledger-lots).

- The help command's documentation now mentions an issue caused by
  a too-old `info` program, as on mac.
  ([#1770])

Fixes

- Unbalanced virtual postings with no amount always infer a zero amount.
  This is fixing and clarifying the status quo; they always did this,
  but print always showed them with no amount, even with -x, and
  the behaviour was undocumented.

- On windows systems with multiple drive letters, the commands list
  could fail to show all installed add-ons.
  ([#2040])

- Balancing a transaction with a balance assignment now properly respects costs.
  ([#2039])

- The commands list no longer lists non-installed addons.
  ([#2034])

- Since hledger 1.25, "every Nth day of month" period rules with N > 28 could
  be calculated wrongly by a couple of days when given certain forecast start dates.
  Eg `~ every 31st day of month` with `--forecast='2023-03-30..'`.
  This is now fixed.
  ([#2032])

- Postings are now processed in correct date order when inferring balance assignments.
  ([#2025])

- Posting comment lines no longer disrupt the underline position in error messages.
  ([#1927])

- Debug output is now formatted to fit the terminal width.

Docs

- Miscellaneous manual cleanups.

- Rewrite introductory sections,
  Date adjustment,
  Directives,
  Forecasting,
  etc.

- Add Paging section.

- Remove archaic mentions of `setenv`.

API

- Renamed: Hledger.Cli.Commands: findCommand -> findBuiltinCommand

### hledger-ui 1.30

Features

- A "Cash accounts" screen has been added, showing
  accounts of the `Cash` type.

Improvements

- The top-level menu screen is now the default screen.
  Power users can use the `--cash`/`--bs`/`--is`/`--all`
  flags to start up in another screen.

- "All accounts" screen has been moved to the bottom of the list.

- Screens' help footers have been improved.

Docs

- The transaction screen's inability to update is now noted.

- Miscellaneous manual cleanups.

### hledger-web 1.30

Fixes

- A command line depth limit now works properly.
  ([#1763])

Docs

- Miscellaneous manual cleanups.

### project changes 1.30

Scripts/addons

- hledger-bar: new script for making simple bar charts in the terminal

- hledger-install: also list cabal, stack, pip tool versions

Examples

- examples/csv: added a more up-to-date CSV makefile

- examples/i18: Added sample top level account and type declarations in several languages

Docs

- A shorter, more example-heavy home page on the website.

- Simplified website and FAQ structure.

### credits 1.30

Simon Michael,
Chris Lemaire,
Yehoshua Pesach Wallach.



## 2023-04-07 hledger-1.29.2

### hledger 1.29.2

Breaking changes

- 1.29's cleanup of the `close` command has been continued.
  Here are all the changes to `close` since hledger 1.28:

  - The default behaviour is now to print only one transaction: a closing transaction.

  - To print both closing and opening transactions as before,
    use the new `--migrate` flag.

  - The accounts closed by default are now just the ALE accounts
    (accounts declared or inferred as type `Asset`, `Liability`, or `Equity`).
    If you don't have account types configured, or
	  to close some other set of accounts, provide query arguments that match them.
    To close all accounts as before, use a `.` argument to match them all.

  - To print a retain earnings transaction for RX accounts (accounts
    of type `Revenue` or `Expense`), use the new `--retain` flag.

  - The `equity` command alias, removed in 1.29, has been restored.

  - The `--open-acct` option, removed in 1.29, has been restored.

  - The `--closing` and `--opening` flags have been renamed to `--close` and `--open`.
    (`--close` had been removed in 1.29 and is now restored.)

  - The docs have been rewritten. Also the 1.29 release notes now mention
    the breaking change.

  - The command is marked experimental again.

  ([#2020])

Fixes

- `type:` queries now "see through" account aliases and pivots,
  as they did in hledger <1.27, and as `acct:` queries do.
  ([#2018])

- The corruption in 1.29's info manual is fixed. ([#2023])

- The 1.29 release notes for periodic reports'/periodic transactions' start dates
  have been improved. Also the hledger manual's "Date adjustment" section
  has been corrected and clarified.

### hledger-ui 1.29.2

Improvements

- A pager is used to show --help output when needed, as in `hledger`.

Fixes

- The corruption in 1.29's info manual is fixed. ([#2023])

### hledger-web 1.29.2

Improvements

- A pager is used to show --help output when needed, as in `hledger`.

Fixes

- The corruption in 1.29's info manual is fixed. ([#2023])

### project changes 1.29.2

Scripts/addons

- hledger-install: re-enable hledger-interest, hledger-iadd; add hledger-lots

### credits 1.29.2

Simon Michael


## 2023-03-16 hledger-1.29.1

### hledger 1.29.1

Improvements

- Hledger.Cli.Script now also exports

       Control.Applicative
       Control.Concurrent
       Data.Char
       Data.Functor
       System.IO
       System.IO.Error

   and new string helpers

       strip1Char
       stripBy
       strip1By

- Allow building with GHC 9.6.1 ([#2011])

Fixes

- The stats report no longer displays "Exact" in front of dates. ([#2012])

Docs

- remove duplicate in `hledger close` docs (Yehoshua Pesach Wallach)

### hledger-ui 1.29.1

- Allow building with GHC 9.6.1 ([#2011])

### hledger-web 1.29.1

- Allow building with GHC 9.6.1 ([#2011])


## 2023-03-11 hledger-1.29

**Tag checking, 
flexible multi-period start dates, 
flexible cost/conversion posting combining,
new commands list,
hledger manual reorg,
easier close command,
10% more Ledger file compatible**

### hledger 1.29

Breaking changes

- Weekly reports are no longer automatically adjusted to start on a
  monday; in some cases you might need to adjust their start date to
  preserve simple week headings (see below).

Features

- In journal format there is now a `tag` directive for declaring tag names,
  and the check command now has a `tags` check to enforce use of declared tag names.

- Periodic transactions and multi-period reports can now start on any date.
  To enable this while still maintaining pretty good backward compatibility,
  hledger now keeps explicitly specified start dates as they are,
  but still automatically adjusts inferred start dates to interval boundaries.
  This means, eg:
  
  - A periodic rule like `~ monthly from 2023-01-15` now works as
    you'd expect instead of raising an error. This also improves
    our ability to read Ledger files.

  - Period options like `-p 'monthly from 2023/1/15'` or `-M -b 2023/1/15`
    now start the report on exactly 1/15 instead of being adjusted to 1/1.
  
  - `-p 'weekly in 2023-01'`, which previously was adjusted to start on a monday,
    now starts exactly on 2023-01-01. This can cause more verbose report headings.
	To ensure simple week headings, now weekly reports must start on a monday,
    eg `-p 'weekly from 2022-12-26 to 2023-02'`. ([#1982])

- You can now freely combine @/@@ notation and conversion postings
  in a single transaction. This can help readability, and also allows
  more flexibility when recording cost.  hledger will check that the
  two notations are in agreement, and ignore the redundancy if they are.
  (Conversion postings are postings to accounts with type `V`/`Conversion`
  or name `equity:conversion`/`equity:trade`/`equity:trading`,
  or subaccounts of these. See also COST.)

Improvements

- hledger's commands list has been reorganised for clarity.
  More add-on commands are now recognised and categorised,
  and unrecognised add-on commands are listed in a more compact
  multi-column layout.
  (Simon Michael, Michael Grünewald)

- hledger's commands list and command line help now use ANSI (bold
  headings) when supported.
  
- hledger's commands list and command line help now use a pager
  (respecting $PAGER) for long output except on MS Windows.

- hledger's `--version` output no longer shows `+` for dev builds made
  in dirty repos (it was buggy).

- The add command's Description completions now also include payee names
  (declared with `payee` or recorded in transactions with `|`),
  not just full descriptions.

- aregister now supports HTML output.
  ([#1996]) (Jonathan Dowland)

- aregister now shows a " (matching query)" hint in report title 
  when extra query args (other than date: or depth:) are used,
  to reduce confusion.

- close now has three modes, `--retain`/`--migrate`/`--open`,
  clarifying its uses and providing more useful defaults.

- register-match is now the `--match` mode of the register command.
  (This command was used by ledger-autosync at one point; if you still
  need it, hopefully `register --match` works similarly.)

- print-unique has been dropped, because it doesn't
  support print's options, it disorders same-day transactions, I don't
  know of any users or use cases, and it could easily be recreated as
  an addon script.

- print's JSON output now also includes source positions for `--forecast` transactions.
  (Chris Lemaire)

- Journal format now allows the empty commodity symbol to be written
  as `""`, so it's now possible to declare market prices for it:
  `P 2022-01-01 "" $100`.  This can be useful for timedot data.

- Inferring costs from equity now happens after transaction balancing,
  not before.  As a result, `--infer-costs` now works in transactions
  where an amount is left blank.

- `account` declarations now reject parenthesised account names,
  reducing confusion.
  (Chris Lemaire)

- Our journal reader now accepts more Ledger syntax, improving Ledger
  file compatibility ([#1962]).  We now test our ability to at least
  read the sample journals from Ledger's baseline functional tests,
  and our success rate has improved from 80% to 90% since 1.28.
  
  - `since` is accepted as synonym of `from` in period expressions
  - `apply year` and `year` are accepted as synonyms of `Y`
  - `(lot notes)` in amounts and `((valuation expressions))` after amounts are now ignored
  - directives 
    `A`, `assert`, `bucket`, `capture`, `check`, `define`,
    `expr`, `eval`, `python`, `value`,
    `apply fixed`, `apply tag`,
    `end apply fixed`, `end apply tag`, `end apply year`
	are now ignored
  - subdirectives of `payee`, `tag`, and `commodity` (other than `format`) are now ignored
  - `pop` directive is no longer supported

- When reading CSV, we now check that assigned account names are valid (parseable).
  ([#1978])

Fixes

- aregister now handles an extra account query correctly. ([#2007])

- balance's `--help` now mentions `--layout=tidy`

- Balance commands with `--layout=bare` now generate proper table
  layout in HTML output.

- register's `-w`/`--width` option no longer gives ugly parse error messages.

- stats's `--help` no longer wrongly claims to support -O/--output-format.

- Balance assignments with a cost now generate a correct balance assertion. ([#1965])

- The CSV reader now properly skips header lines before attempting to parse records. ([#1967])

Scripts/addons

- Scripts can now use Hledger.Cli.Script, a convenient new prelude which
  helps reduce import boilerplate. It currently re-exports:

	  Control.Monad
	  Data.Either
	  Data.List
	  Data.Maybe
	  Data.Ord
	  Data.Time
	  Text.Printf hiding (formatString)
	  Data.Text (Text, pack, unpack)
	  Safe hiding (at)
	  System.Directory
	  System.Environment
	  System.Exit
	  System.FilePath
	  System.Process
	  Hledger
	  Hledger.Cli
	  Hledger.Cli.Main (argsToCliOpts)

  (Not much of Data.Text/Data.Text.IO because those need to be qualified.)

Docs

- chunk the hledger manual into parts, rename and rearrange sections for better structure/flow
- add a cheatsheet demonstrating all the main journal features that I recommend
- move a number of my not-so-recommended journal features into a less visible "Other syntax" section
- add: payees/descriptions completion
- areg: more advice on account-matching
- bal: --budget: clarify use of print --forecast
- bal: budget: compare with forecasting; add some tips
- balance cleanups/reorder
- check: adjacentconversionpostings was dropped
- cli: balance: fix link to Budgeting page
- cli: fix all links to Journal > Tags / Commands > tags
- codes: improve example suggested by Rob Nielsen
- csv, timeclock, timedot: clarify comment lines ([#1953])
- csv: add new coinbase example
- csv: clarify amount-in/amount-out docs ([#1970])
- csv: clarify skip/valid csv semantics ([#1967])
- csv: clarify valid CSV requirements and issues (fix [#1966])
- csv: cleanup, reorder, CSV rules tips -> Working with CSV
- csv: fix wrong if tables doc; rewrite several sections ([#1977])
- csv: flatten, clean up CSV sections
- csv: improve Amount field / Setting amounts
- csv: note -in and -out are used together for one posting ([#1970])
- csv: rules factoring tips
- csv: try to clarify how CSV fields and hledger fields work
- document --infer-market-prices with signed costs ([#1870])
- fix duplicate market prices heading breaking info navigation
- import: note a pitfall with multifile import
- improve Directives summaries
- introduction/input/output improvements
- journal: cheatsheet: clarify date tag
- journal: rewrite Account names, mention brackets/parentheses ([#1915])
- mention pivoting on a tag with multiple values ([#1950])
- more cost notation docs; describe Ledger and Beancount cost notation
- more mention of posting order effect on inferring cost ([#1959])
- period expressions doc updates
- Removed redundant paragraph in documentation. (J. B. Rainsberger)
- rename directive sections, fix many links
- reorganise commands list, like the CLI
- reorganise bin/README & the Scripts page, add entries for recent scripts
- replace "transaction prices" terminology with "costs"
- tags: discuss multi-values/overriding ([#1950])
- update market price inference docs per sol
- Updated section on pivoting. Used synonyms for "member" in cases where there could be confusion with the tag named "member." (Robert Nielsen)
- use more standard and consistent boilerplate in hledger, ui, web man pages
- virtual postings: improve wording per Robert Nielsen

### hledger-ui 1.29

- In the help dialog, mention that LEFT shows other screens.

- In the manual, mention shift-up/down config needed for Terminal.app.

### hledger-web 1.29

- The add form's typeahead now shows non-ascii text correctly.
  ([#1961]) (Arsen Arsenović)

- In the manual, improve --base-url's description. ([#1562])

### project changes 1.29

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

- pr template: mention COMMITS page and prefix convention ([#1997])
- make ghc 9.4 and current stackage nightly the default for dev builds
- require megaparsec 9.3+ in dev builds, for its useful dbg tool
- make site-watch: fix runaway recursion, be more verbose
- new make rules: man-watch
- new tools: ciwatch, push, pushdocs, gtree
- misc process updates

### credits 1.29

Simon Michael, Chris Lemaire, Caleb Maclennan, Jonathan Dowland, J. B. Rainsberger, Michael Grünewald, Robert Nielsen, Yann Büchau.


## 2022-12-01 hledger-1.28

**new hledger-ui screens, better debug output;
accounts, print, csv-reading improvements;
new hledger-move, watchaccounts scripts**
<!-- ([announcement](https://groups.google.com/g/hledger/LINK)) -->

### hledger 1.28

Features

- The `accounts` command has new flags: `--undeclared` (show accounts used but not declared),
  `--unused` (show accounts declared but not used),  and `--find` (find the first account
  matched by the first command argument, a convenience for scripts). 
  Also `-u` and `-d` short flags have been added for `--used` and `--declared`.

- A new CSV rule `intra-day-reversed` helps generate transactions in correct order
  with CSVs where records are reversed within each day.

- CSV rules can now correctly convert CSV date-times with a implicit or explicit timezone
  to dates in your local timezone. Previously, CSV date-times with a different time zone
  from yours could convert to off-by-one dates, because the CSV's timezone was ignored.
  Now,

  1. When a CSV has date-times with an implicit timezone different from yours,
     you can use the `timezone` rule to declare it.

  2. CSV date-times with a known timezone (either declared by `timezone`
     or parsed with `%Z`) will be localised to the system timezone
     (or to the timezone set with the `TZ` environment variable).

  ([#1936])
  
Improvements

- print --match now respects -o and -O.

- print --match now returns a non-zero exit code when there is no acceptable match.

- Support megaparsec 9.3. (Felix Yan)

- Support GHC 9.4.

Fixes

- In CSV rules, when assigning a parenthesised account name to   `accountN`, 
  extra whitespace is now ignored, allowing unbalanced postings to be detected correctly.

Scripts/addons

- bin/hledger-move helps record transfers involving subaccounts and costs,
  eg when withdrawing some or all of an investment balance containing many lots and costs.

- bin/hledger-git no longer uses the non-existent git record command.
  ([#1942]) (Patrick Fiaux)

- bin/watchaccounts is a small shell script for watching the account tree as you make changes.

### hledger-ui 1.28

Features

- New "Balance sheet accounts" and "Income statement accounts" screens have been added,
  along with a new top-level "Menu" screen for navigating between these and the
  "All accounts" screen.

- hledger-ui now starts in the "Balance sheet accounts" screen by default
  (unless no asset/liability/equity accounts can be detected,
  or command line account query arguments are provided).
  This provides a more useful default view than the giant "All accounts" list.
  Or, you can force a particular starting screen with the new --menu/--all/--bs/--is flags
  (eg, `hledger-ui --all` to replicate the old behaviour).

Improvements

- The ENTER key is equivalent to RIGHT for navigation.

- hledger-ui debug output is now always logged to ./hledger-ui.log rather than the console,
  --debug with no argument is equivalent to --debug=1,
  and debug output is much more informative.

- Support GHC 9.4.

- Support megaparsec 9.3 (Felix Yan)

- Support (and require) brick 1.5, fsnotify 0.4.x.

Fixes

- Mouse-clicking in empty space below the last list item no longer navigates
  back. It was too obtrusive, eg when you just want to focus the window. 
  You can still navigate back with the mouse by clicking the left edge of the window.

- A possible bug with detecting change of date while in --watch mode has been fixed.

API

- hledger-ui's internal types have been changed to allow fewer invalid states\
  and make it easier  to develop and debug.
  ([#1889], [#1919]).

- Debug logging helpers have been added and cleaned up in Hledger.Ui.UIUtils:
  dbgui
  dbguiIO
  dbguiEv
  dbguiScreensEv
  mapScreens
  screenId
  screenRegisterDescriptions

### hledger-web 1.28

Improvements

- --debug with no argument is now equivalent to --debug=1.

- Allow megaparsec 9.3 (Felix Yan)

- Support GHC 9.4

### project changes 1.28

Docs

- Miscellaneous improvements.

Examples

- Indian National Pension Service CSV rules (Pranesh Prakash)

Infrastructure

- make site-watch: switch from entr to watchexec.

- make hoogle-setup, hoogle-serve: run a local hoogle on hledger code.

- make man-watch-PROG: watch a hledger program's man page as source files change.

### credits 1.28

Simon Michael, Felix Yan, Patrick Fiaux.

## 2022-09-18 hledger-1.27.1

### hledger 1.27.1

Fixes

- Balance commands using `-T -O html` no longer fail with an error
  when there is no data to report.
  ([#1933])

### hledger-ui 1.27.1

- Uses hledger-1.27.1

### hledger-web 1.27.1

Fixes

- The add form no longer gives an error when there is just a single file and no file field showing.
  ([#1932])

- Uses hledger-1.27.1


## 2022-09-01 hledger-1.27

**Infer costs from equity postings, new error checks, improved error messages, fixes.**
<!-- ([announcement](https://groups.google.com/g/hledger/LINK)) -->

### hledger 1.27

Features

- `hledger check recentassertions` (and flycheck-hledger in Emacs if
  you enable this check) requires that all balance-asserted accounts
  have a balance assertion within 7 days before their latest posting.

  This helps remind you to not only record transactions, but also to
  regularly check account balances against the real world, to catch
  errors sooner and avoid a time-consuming hunt.

- The --infer-costs general flag has been added, as the inverse
  operation to --infer-equity.  --infer-costs detects commodity
  conversion transactions which have been written with equity
  conversion postings (the traditional accounting notation) and adds
  PTA cost notation (@@) to them (allowing cost reporting).
  See https://hledger.org/hledger.html#equity-conversion-postings .
  (Stephen Morgan)

Improvements

- Many error messages have been improved. Most error messages now use
  a consistent, more informative format. 
  ([#1436])

- The accounts command has a new --directives flag which makes it
  show valid account directives which you can paste into a journal.

- The accounts command has a new --positions flag which shows where
  accounts were declared, useful for troubleshooting.
  ([#1909])

- Bump lower bounds for Diff and githash. (Andrew Lelechenko)

- GHC 8.6 and 8.8 are no longer supported. Building hledger now
  requires GHC 8.10 or greater.

Fixes

- Account display order is now calculated correctly even when accounts
  are declared in multiple files.
  ([#1909])

- At --debug 5 and up, account declarations info is logged.
  ([#1909])

- hledger aregister and hledger-ui now show transactions correctly
  when there is a type: query.
  ([#1905])

- bal: Allow cumulative gain and valuechange reports.
  Previously, --cumulative with --gain or --valuechange would produce an
  empty report. This fixes this issue to produce a reasonable report.
  (Stephen Morgan)

- bal: budget goal amounts now respect -c styles (fixes [#1907])

- bal: budget goals now respect -H ([#1879])

- bal: budget goals were ignoring rule-specified start date

- cf/bs/is: Fixed non-display of child accounts when there is an
  intervening account of another type.
  ([#1921]) (Stephen Morgan)

- roi: make sure empty cashflows are skipped when determining first cashflow (Charlotte Van Petegem)
  Empty cashflows are added when the begin date of the report is before the first
  transaction.

Scripts/addons

- https://hledger.org/scripts.html - an overview of scripts and addons in bin/.

- paypaljson, paypaljson2csv - download txns from paypal API

- hledger-check-postable.hs - check that no postings are made to accounts with a postable:(n|no) tag

- hledger-addon-example.hs - script template

### hledger-ui 1.27

Improvements

- At --debug=2 and up, log debug output to ./debug.log.

- Use/require brick 1.0+. ([#1889])

- Use hledger 1.27

### hledger-web 1.27

Improvements

- Improve the add form's layout and space usage.

- Pre-fill the add form's date field.

- Highlight today in the add form's date picker.

- Focus the add form's description field by default.

- Allow an empty description in the add form.

- Use hledger 1.27

Fixes

- Respect the add form's file selector again.
  (Simon Michael, Kerstin, [#1229])

### project changes 1.27

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
  github actions.  The CI tests for master now also include
  hledger-lib's doctests.

- All packages now disallow name shadowing in their code.

- make scc gives a modern report of code line counts.

- make ghci-unit-test loads hledger-lib unit tests in GHCI.

### credits 1.27

Simon Michael,
Stephen Morgan,
Alex Hirzel,
Pranesh Prakash,
David D Lowe,
Charlotte Van Petegem,
Max Thomas,
Andrew Lelechenko.


## 2022-07-11 hledger-1.26.1

### hledger 1.26.1

- require safe 0.3.19+ to avoid deprecation warning

### hledger-ui 1.26.1

- support doclayout 0.4, brick 0.72+

- require safe 0.3.19+ to avoid deprecation warning

## 2022-06-04 hledger-1.26

**Miscellaneous improvements.**
<!-- ([announcement](https://groups.google.com/g/hledger/LINK)) -->

### hledger 1.26

Improvements

- `register` and `aregister` have been made faster, by 

  - considering only the first 1000 items for choosing column
    widths. You can restore the old behaviour (guaranteed alignment
    across all items) with the new `--align-all` flag.
    ([#1839]](https://github.com/simonmichael/hledger/issues/1839), Stephen Morgan)

  - discarding cost data more aggressively, giving big speedups for
    large journals with many costs.
  	([#1828](https://github.com/simonmichael/hledger/issues/1828), Stephen Morgan)

- Most error messages from the journal reader and the `check` command now use
  a consistent layout, with an "Error:" prefix, line and column numbers,
  and an excerpt highlighting the problem. Work in progress.
  ([#1436](https://github.com/simonmichael/hledger/issues/1436)) (Simon Michael, Stephen Morgan)

- `hledger check ordereddates` now always checks all transactions
  (previously it could be restricted by query arguments).

- The `--pivot` option now supports a `status` argument, to pivot on transaction status.

- Update bash completions (Jakob Schöttl)

Fixes

- Value reports with `--date2` and a report interval (like `hledger bal -VM --date2`)
  were failing with a "expected all spans to have an end date" error since 1.22;
  this is now fixed.
  ([#1851](https://github.com/simonmichael/hledger/issues/1851), Stephen Morgan)

- In CSV rules, interpolation of a non-existent field like `%999` or `%nosuchfield`
  is now ignored (previously it inserted that literal text).
  Note this means such an error will not be reported; 
  Simon chose this as the more convenient behaviour when converting CSV.
  Experimental.
  ([#1803](https://github.com/simonmichael/hledger/issues/1803), [#1814](https://github.com/simonmichael/hledger/issues/1814)) (Stephen Morgan)

- `--infer-market-price` was inferring a negative price when selling.
  ([#1813](https://github.com/simonmichael/hledger/issues/1813), Stephen Morgan)

- Allow an escaped forward slash in regular expression account aliases.
  ([#982](https://github.com/simonmichael/hledger/issues/982), Stephen Morgan)

- The `tags` command now also lists tags from unused account declarations.
  It also has improved command-line help layout.
  ([#1857](https://github.com/simonmichael/hledger/issues/1857))

- `hledger accounts` now shows its debug output at a more appropriate level (4).

### hledger-ui 1.26

- Uses hledger 1.26.

### hledger-web 1.26

Fixes

- Don't add link URLs when printing.

Improvements

- Now builds with GHC 9.2.

- Uses hledger 1.26.

### project changes 1.26

Scripts/addons

- renamed hledger-number.sh to hledger-simplebal

- added hledger-git, hledger-pijul

- fin (and bin) scripts show available scripts and their help

- renamed aliases.sh to bashrc

- Get hledger-print-location working. (Stephen Morgan)

Docs

- README cleanup, inspired by feedback from README reviewer Lars Wirzenius.

- Clearer sponsoring info and more complete sponsor lists on website and README.

- The new <https://github.com/simonmichael/hledger_finance> repo
  keeps track of our public finances (on Open Collective, Liberapay etc.)

Examples

- invoice: calculate dates accurately on last days of month

Process

- Stackage nightly and GHC 9.2 are now the default for dev builds.

- CI workflows: 

  - Workflows and binaries have more consistent naming, mentioning platform and architecture.
  - The main test workflow is now `linux-x64-test`, replacing `push` and `pull`.
    It runs for both pushes and pull requests, and generates binaries on every run.
  - Pushes/merges to master, including Simon's, are required to have passed
    `linux-x64-test` on another github branch first.
  - Mac and Windows binaries are now stripped also (if applicable).

- `make buildtimes`, `make buildtimes-cabal` show GHC codegen times.

### credits 1.26

Simon Michael,
Stephen Morgan,
Jakob Schöttl,
Patrik Keller.


## 2022-03-04 hledger 1.25

**Account type and tag querying,
infer equity postings from @ notation,
easily-consumed "tidy" CSV output**
<!-- ([announcement](https://groups.google.com/g/hledger/LINK)) -->

### hledger 1.25

Breaking changes

- Journal format's `account NAME  TYPECODE` syntax, deprecated in 1.13, has been dropped.
  Please use `account NAME  ; type:TYPECODE` instead.
  (Stephen Morgan)

- The rule for auto-detecting "cash" (liquid asset) accounts in the `cashflow` report
  has changed: it's now "all accounts under a top-level `asset` account, with
  `cash`, `bank`, `checking` or `saving` in their name" (case insensitive, variations allowed).
  So if you see a change in your `cashflow` reports, you might need to add
  `account` directives with `type:C` tags, declaring your top-most cash accounts.

Features

- The new `type:TYPECODES` query matches accounts by their accounting type.
  Account types are declared with a `type:` tag in account directives,
  or inferred from common english account names, or inherited from parent accounts,
  as described at [Declaring accounts > Account types].
  This generalises the account type detection of `balancesheet`, `incomestatement` etc.,
  so you can now select accounts by type without needing fragile account name regexps.
  Also, the `accounts` command has a new `--types` flag to show account types.
  Eg:

      hledger bal type:AL  # balance report showing assets and liabilities
      hledger reg type:x   # register of all expenses
      hledger acc --types  # list accounts and their types

  ([#1820](https://github.com/simonmichael/hledger/issues/1820), 
  [#1822](https://github.com/simonmichael/hledger/issues/1822)) 
  (Simon Michael, Stephen Morgan)

- The `tag:` query can now also match account tags, as defined in account directives.
  Subaccounts inherit tags from their parents.
  Accounts, postings and transactions can be filtered by account tag.
  ([#1817](https://github.com/simonmichael/hledger/issues/1817))

- The new `--infer-equity` flag replaces the `@`/`@@` price notation in commodity
  conversion transactions with more correct equity postings (when not using `-B/--cost`).
  This makes these transactions fully balanced, and preserves the accounting equation.
  For example:

      2000-01-01
        a             1 AAA @@ 2 BBB
        b            -2 BBB

      $ hledger print --infer-equity
      2000-01-01
        a                               1 AAA
        equity:conversion:AAA-BBB:AAA  -1 AAA
        equity:conversion:AAA-BBB:BBB   2 BBB
        b                              -2 BBB

  
  `equity:conversion` is the account used by default. To use a different account,
  declare it with an account directive and the new `V` (`Conversion`) account type.
  Eg:
  
      account Equity:Trading    ; type:V

  ([#1554](https://github.com/simonmichael/hledger/issues/1554)) (Stephen Morgan, Simon Michael)

- Balance commands (`bal`, `bs` etc.) can now generate easy-to-process "tidy" CSV data 
  with `-O csv --layout tidy`.
  In tidy data, every variable is a column and each row represents a single data point 
  (cf <https://vita.had.co.nz/papers/tidy-data.html>).
  ([#1768](https://github.com/simonmichael/hledger/issues/1768), 
  [#1773](https://github.com/simonmichael/hledger/issues/1773), 
  [#1775](https://github.com/simonmichael/hledger/issues/1775)) 
  (Stephen Morgan)

Improvements

- Strict mode (`-s/--strict`) now also checks periodic transactions (`--forecast`) 
  and auto postings (`--auto`). 
  ([#1810](https://github.com/simonmichael/hledger/issues/1810)) (Stephen Morgan)

- `hledger check commodities` now always accepts zero amounts which have no commodity symbol. 
  ([#1767](https://github.com/simonmichael/hledger/issues/1767)) (Stephen Morgan)

- Relative [smart dates](hledger.md#smart-dates) may now specify an arbitrary number of some period into the future or past).
  Some examples:
  - `in 5 days`
  - `in -6 months`
  - `5 weeks ahead`
  - `2 quarters ago`
  
  (Stephen Morgan)

- CSV output now always disables digit group marks (eg, thousands separators),
  making it more machine readable by default. 
  ([#1771](https://github.com/simonmichael/hledger/issues/1771)) (Stephen Morgan)

- Unicode may now be used in field names/references in CSV rules files.
  ([#1809](https://github.com/simonmichael/hledger/issues/1809)) (Stephen Morgan)

- Error messages improved:
  - Balance assignments
  - aregister
  - Command line parsing (less "user error")

Fixes

- `--layout=bare` no longer shows a commodity symbol for zero amounts. 
  ([#1789](https://github.com/simonmichael/hledger/issues/1789)) (Stephen Morgan)

- `balance --budget` no longer elides boring parents of unbudgeted accounts 
  if they have a budget. 
  ([#1800](https://github.com/simonmichael/hledger/issues/1800)) (Stephen Morgan)

- `roi` now reports TWR correctly

  - when there are several PnL changes occurring on a single day
  - and also when investment is fully sold/withdrawn/discounted at the end of a particular reporting period.

  ([#1791](https://github.com/simonmichael/hledger/issues/1791)) (Dmitry Astapov)

Documentation

- There is a new CONVERSION & COST section, replacing COSTING. 
  ([#1554](https://github.com/simonmichael/hledger/issues/1554))

- Some problematic interactions of account aliases with other features have been noted. 
  ([#1788](https://github.com/simonmichael/hledger/issues/1788))

- Updated: [Declaring accounts > Account types](https://hledger.org/hledger.html#account-types)

### hledger-ui 1.25

- Uses hledger 1.25.

### hledger-web 1.25

- Uses hledger 1.25.

### project changes 1.25

Scripts/addons

- hledger-install.sh now also installs Pavan Rikhi's hledger-stockquotes tool.

- The bin/hledger-number addon was added.

- The bin/hledger-check-fancyassertions addon now shows docs in --help.

- A new invoice-making script was added: examples/invoicing/invoice-script/invoice

Process/tools

- The RELEASING doc and release process has been updated, 
  and a new helper script added: tools/releaseprep.
  `make hackageupload` now only works from a branch named
  VERSION-branch or VERSION-release. Ie, making releases from master
  is no longer allowed, a release branch is always required,

- CI: The commitlint check is more robust, and now runs only in
  the push to master and pull request workflows, and not eg when 
  building release binaries. linux-x64 binaries are now built
  with ghc 9.0, not 8.10. Workflow, branch, and binary names
  have been improved.

- `make ghci-ui`/`make ghcid-ui` now use older ghc 8.10 to avoid 
  ghc 9.0-triggered failures.

- hls support: The hie.yaml added to help hls work on mac m1 
  has been moved out of the way, since it probably makes things worse
  on other architectures.

### credits 1.25

Simon Michael,
Stephen Morgan,
Dmitry Astapov,
Patrik Keller.


## 2021-12-10 hledger-1.24.1

### hledger 1.24.1

Fixes

- `balance --declared` is now filtered correctly by a `not:ACCT` query.
  ([#1783](https://github.com/simonmichael/hledger/issues/1783))

- More reliable --version output, with commit date and without patch level.

### hledger-ui 1.24.1

Fixes

- An extra "root" account is no longer shown (a regression in 1.24).
  ([#1782](https://github.com/simonmichael/hledger/issues/1782))

- Declared accounts are now filtered correctly by a not:ACCT query.
  ([#1783](https://github.com/simonmichael/hledger/issues/1783))

- More reliable --version output, with commit date and without patch level.

### hledger-web 1.24.1

Fixes

- More reliable --version output, with commit date and without patch level.


## 2021-12-01 hledger-1.24

**New report layout options with less eliding,
hledger-ui mouse support,
misc fixes and improvements.**
<!-- ([announcement](https://groups.google.com/g/hledger/LINK)) -->

### hledger 1.24

Features

- balance commands provide more control over how multicommodity amounts
  are displayed. (And they no longer elide too-wide amounts by default.)
  The --commodity-column flag has been deprecated and replaced by a new
  --layout option, with three values:
  
  - wide (the default, shows amounts on one line unelided, like older hledger versions)
  - tall (a new display mode, shows one amount per line)
  - bare (like the old --commodity-columm, shows one commodity per line with symbols in their own column)
  
  (Stephen Morgan)

- The balance commands have a new `--declared` flag, causing them to
  include leaf (ie, non-parent) accounts declared by account directives,
  even if they contain no transactions yet. Together with `-E`, this shows
  a balance for both used and declared accounts.
  The idea is to be able to see a useful "complete" balance report, even
  when you don't have transactions in all of your declared accounts yet.
  ([#1765](https://github.com/simonmichael/hledger/issues/1765))

- journal files now support a `decimal-mark` directive as a more
  principled way (than `commodity` directives) to specify the decimal character
  in use in that file, to ensure accurate number parsing.
  ([#1670](https://github.com/simonmichael/hledger/issues/1670), Lawrence Wu)

Improvements

- The stats command now shows rough but useful performance stats: run
  time and processing speed in transactions per second.

- balance: support the --related flag, like register, showing the
  other postings from the transactions. ([#1469](https://github.com/simonmichael/hledger/issues/1469), Stephen Morgan)

- roi now uses posting dates when available, and honors the --date2
  flag. This will not change the results computed for the typical
  use-case, it just makes "roi" more thorough/consistent.
  (Dmitry Astapov)

- aregister now shows transactions' secondary date if the --date2 flag is used.
  ([#1731](https://github.com/simonmichael/hledger/issues/1731))

- timedot: a D default commodity (and style) declared in a parent
  journal file will now be applied to timedot amounts. This means they
  can be priced and valued/converted.

- cli: The --pretty and --forecast options can now be written after the
  command name, like other general options.
  (Stephen Morgan)

- register -V -H with no interval now values at report end date, like balance.
  ([#1718](https://github.com/simonmichael/hledger/issues/1718), Stephen Morgan)

- Allow megaparsec 9.2.

- Drop the base-compat-batteries dependency. (Stephen Morgan)

Fixes

- prices: Do not include zero amounts when calculating amounts for balance assignments. 
  This is not usually a problem, but can get in the way of auto-inferring prices.
  ([#1736](https://github.com/simonmichael/hledger/issues/1736), Stephen Morgan)

- csv: Successfully parse an empty csv file. 
  ([#1183](https://github.com/simonmichael/hledger/issues/1183), Stephen Morgan)

- balance: Balance reports with --depth=0 properly report aggregated
  values, not zero everywhere. 
  ([#1761](https://github.com/simonmichael/hledger/issues/1761), Stephen Morgan)

- prices: Do not try to generate prices when there would be a zero
  denominator. Also correctly generate reverse prices for zero
  amounts. (Stephen Morgan)

- csv: Allow both amount-in and amount-out fields to contain a zero.
  ([#1733](https://github.com/simonmichael/hledger/issues/1733), Stephen Morgan)

- balance: Balance reports should consider date: queries when
  calculating report span with --date2. 
  ([#1745](https://github.com/simonmichael/hledger/issues/1745), Stephen Morgan)

- print: auto: The print command should always display inferred
  amounts for --auto generated postings. 
  ([#1276](https://github.com/simonmichael/hledger/issues/1276), Stephen Morgan)
  
### hledger-ui 1.24

Features

- hledger-ui can now be controlled with mouse or touchpad.
  Click to enter things, click left margin or bottom blank area to return to
  previous screen, and use mouse wheel / swipe to scroll.

- In addition to accounts with postings, hledger-ui now also shows
  declared accounts, even if they are empty (just leaf accounts, not
  parents). The idea is to show a useful list of accounts out of the
  box, when all you have is a starter file with account declarations.

Improvements

- The `Z` key for toggling display of zeroes is now the easier lower-case `z`.

- The `--watch` feature now has a convenient short flag, `-w`.

- Drop the base-compat-batteries dependency. (Stephen Morgan)

- Allow megaparsec 9.2

Fixes

- When an invalid regular expression is entered at the `/` (filter) prompt,
  we now display an error instead of silently ignoring it.
  ([#1394](https://github.com/simonmichael/hledger/issues/1394), Stephen Morgan)

- Entering the register screen now always positions the selection mid-screen.
  Previously it would be at bottom of screen on the first entry.

- Report layout in the terminal is now robust with more kinds of wide
  characters, such as emoji.
  ([#895](https://github.com/simonmichael/hledger/issues/895), Stephen Morgan)
  
### hledger-web 1.24

Improvements

- Allow megaparsec 9.2

### project changes 1.24

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
  ([#1365](https://github.com/simonmichael/hledger/issues/1365), toonn)

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

### credits 1.24

Simon Michael,
Stephen Morgan,
toonn,
Pranesh Prakash,
Dmitry Astapov,
ShrykeWindgrace,
Joaquin Azcarate,
Lawrence Wu.


## 2021-09-21 hledger-1.23

**Capital gains report,
separate symbol/number display,
command line commodity styling,
budget selection,
weekday/weekend recurrence,
10% speedup,
fixes.**
<!-- ([announcement](https://groups.google.com/g/hledger/LINK)) -->

### project changes 1.23

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
  ([#1503](https://github.com/simonmichael/hledger/issues/1503), 
  [#1615](https://github.com/simonmichael/hledger/issues/1615))

- tools/commitlint is a new tool for hledger developers which checks and
  describes new commit conventions which simplify maintenance of
  change docs and releasing. It can be run locally while developing,
  manually or as a pre-commit hook
  (`ln -sf ../../bin/commitling .git/hooks/commit-msg`), 
  and is also run by our CI workflows to check pull requests.
  <https://hledger.org/CONTRIBUTING.html#commit-messages>,
  [tools/commitlint](https://github.com/simonmichael/hledger/blob/master/tools/commitlint)
  (#1602)

### hledger 1.23

Features

- The balance command has a new `--gain` report type, showing
  unrealised capital gains/losses. Essentially, this is the difference
  between the amounts' costs and their total present value. More
  precisely, between the value of the amounts' costs and the value of
  the amounts on the valuation date(s). (Ie, you can report gain in a
  different currency.)
  ([#1623](https://github.com/simonmichael/hledger/issues/1623),
  [#1432](https://github.com/simonmichael/hledger/issues/1432),
  Stephen Morgan, Charlotte Van Petegem)

- The new `-c/--commodity-style` option makes it easy to override
  commodity display styles at runtime, eg to adjust the number of
  decimal places or change the position of the symbol.
  ([#1593](https://github.com/simonmichael/hledger/issues/1593), Arjen Langebaerd)

- The balance commands have a new `--commodity-column` flag that
  displays commodity symbols in a dedicated column, showing one line
  per commodity and all amounts as bare numbers.
  ([#1559](https://github.com/simonmichael/hledger/issues/1559),
  [#1626](https://github.com/simonmichael/hledger/issues/1626),
  [#1654](https://github.com/simonmichael/hledger/issues/1654),
  Lawrence Wu, Simon Michael, Stephen Morgan)

- The `balance --budget` option can now take an argument,
  a case insensitive description substring which selects a subset of
  the journal's periodic transactions for setting budget goals. 
  This makes it possible to keep multiple named budgets in one journal, 
  and select the one you want with --budget's argument. 
  ([#1612](https://github.com/simonmichael/hledger/issues/1612))

- Period expressions now support `every weekday`, `every weekendday` and
  `every mon,wed,...` (multiple days of the week).
  This is intended for periodic transaction rules used with
  `--forecast` (or `bal --budget`).
  ([#1632](https://github.com/simonmichael/hledger/issues/1632), Lawrence Wu)

- The new `--today=DATE` option allows overriding today's date. This
  can be useful in tests and examples using relative dates, to make
  them reproducible.
  ([#1674](https://github.com/simonmichael/hledger/issues/1674), Stephen Morgan)

- In CSV rules, multi-line comments are now supported. Newlines in CSV
  data are preserved, or newlines can be added by writing `\n` when
  assigning to `comment`, `comment1` etc. 
  (Malte Brandy)

Improvements

- Incremental performance improvements; hledger 1.23 is the fastest
  hledger yet, about 10% faster than 1.22. 
  (Stephen Morgan)

- `register` no longer slows down when there are many report intervals.
  ([#1683](https://github.com/simonmichael/hledger/issues/1683), Stephen Morgan)

- Numbers in SQL output now always use decimal period (`.`),
  independent of commodity display styles. 
  (Stephen Morgan)

- `--sort` now gives a more intuitive sort oder when there are
   multiple commodities. Negative numbers in one commodity are always
   less than positive numbers in another commodity.
   ([#1563](https://github.com/simonmichael/hledger/issues/1563), Stephen Morgan)

- `--infer-market-price` has been renamed to `--infer-market-prices`.
  (The old spelling still works, since we accept flag prefixes.)

- Our pretty-printed JSON now orders object attributes alphabetically,
  across all GHC and haskell lib versions.

- register with a report interval starting on custom dates
  (eg: `hledger reg -p "every 15th day of month") now makes the 
  date column wide enough to show the start and end dates.
  It also wastes less whitespace after the column.
  ([#1655](https://github.com/simonmichael/hledger/issues/1655), Stephen Morgan)

- In JSON output, object attributes are now ordered alphabetically,
  consistently for all GHC and haskell lib versions. 
  ([#1618](https://github.com/simonmichael/hledger/issues/1618), Stephen Morgan)

- JSON output now indents with 2 spaces rather than 4. 
  (Stephen Morgan)

- The balance commands' `-S/--sort-amount` flag now behaves more
  predictably and intuitively with multiple commodities.
  Multi-commodity amounts are sorted by comparing their amounts in
  each commodity, with alphabetically-first commodity symbols being
  most significant, and assuming zero when a commodity is missing.
  ([#1563](https://github.com/simonmichael/hledger/issues/1563), 
  [#1564](https://github.com/simonmichael/hledger/issues/1564), Stephen Morgan)
  
- The close command now uses the later of today or journal's last day
  as default closing date, providing more intuitive behaviour when
  closing a journal with future transactions. Docs have been improved.
  ([#1604](https://github.com/simonmichael/hledger/issues/1604))

- Rules for selecting the forecast period (within with --forecast
  generates transactions) have been tweaked slightly, and
  some disagreement between docs and implementation has been fixed.
  Now, the forecast period begins on:
  - the start date supplied to the `--forecast` argument, if any
  - otherwise, the later of
    - the report start date if specified with -b/-p/date:
    - the day after the latest normal (non-periodic) transaction in the journal, if any
  - otherwise today.

  It ends on:
  - the end date supplied to the `--forecast` argument, if any
  - otherwise the report end date if specified with -e/-p/date:
  - otherwise 180 days (6 months) from today.

  This is more intuitive in some cases. (Eg:
  `hledger reg --forecast -b 2020-01-01` on a journal containing 
  only periodic transaction rules now shows forecast transactions 
  starting from 2020-01-01, rather than from today.)
  ([#1648](https://github.com/simonmichael/hledger/issues/1648), 
  [#1665](https://github.com/simonmichael/hledger/issues/1665),
  [#1667](https://github.com/simonmichael/hledger/issues/1667), 
  Stephen Morgan, Simon Michael)

- Require base >=4.11, prevent red squares on Hackage's build matrix.
  (We officially support GHC 8.6+, which means base 4.12, 
  but Hackage shows all packages building successfully with 
  base 4.11/GHC 8.4+ somehow, so it's still allowed..)

Fixes

- A rare bug causing incorrect balances to be reported by the
  cf/bs/bse/is commands, since hledger 1.19, has been fixed.
  (cf/bs/bse/is with --tree --no-elide --begin DATE and certain
  account directives could show wrong balances).
  ([#1698](https://github.com/simonmichael/hledger/issues/1698), Stephen Morgan)

- aregister now aligns multicommodity amounts properly (broken since 1.21).
  ([#1656](https://github.com/simonmichael/hledger/issues/1656), Stephen Morgan)

- `balance -E` (and hledger-ui Z) now correctly show zero parent accounts,
  fixing a bug introduced in hledger 1.19.
  ([#1688](https://github.com/simonmichael/hledger/issues/1688), Stephen Morgan)

- The `roi` command no longer gives an ugly error in a certain case
  with PnL applied on the first day of investment. (Dmitry Astapov)

- `--forecast` now generates transactions up to the day before the
  specified report end date (instead of two days before).
  ([#1633](https://github.com/simonmichael/hledger/issues/1633), Stephen Morgan)

- Certain errors in CSV conversion, such as a failing balance assertion,
  were always being reported as line 2.

### hledger-ui 1.23

Improvements

- Depend on hledger 1.23.

- Require base >=4.11, prevent red squares on Hackage's build matrix.

### hledger-web 1.23

Improvements

- Drop the obsolete hidden `--binary-filename` flag.

- Depend on hledger 1.23.

- Require base >=4.11, preventing red squares on Hackage's build matrix.

Fixes

- Toggle showing zero items properly even when called with --empty. 
  ([#1237](https://github.com/simonmichael/hledger/issues/1237), Stephen Morgan)

- Do not hide empty accounts if they have non-empty subaccounts. 
  ([#1237](https://github.com/simonmichael/hledger/issues/1237), Stephen Morgan)

- Allow unbalanced postings (parenthesised account name) in the add transaction form. 
  ([#1058](https://github.com/simonmichael/hledger/issues/1058), Stephen Morgan)

- An XSS (cross-site scripting) vulnerability has been fixed.
  Previously (since hledger-web 0.24), javascript code could be added 
  to any autocompleteable field and could be executed automatically 
  by subsequent visitors viewing the journal.
  Thanks to Gaspard Baye and Hamidullah Muslih for reporting this vulnerability.
  ([#1525](https://github.com/simonmichael/hledger/issues/1525), Arsen Arsenović)

### credits 1.23

Simon Michael,
Stephen Morgan,
Lawrence Wu,
Jakob Schöttl,
Dmitry Astapov,
Malte Brandy,
Arsen Arsenović,
Arjen Langebaerd,
Alan Young,
Daniel Gröber.


## 2021-08-07 hledger-1.22.2

### hledger 1.22.2

Breaking changes

- aregister no longer hides future transactions by default.
  This is a consequence of the fix for 
  [#1638](https://github.com/simonmichael/hledger/issues/1638). 
  It makes aregister consistent, so we think it's a reasonable change.
  So if you have future-dated transactions in your journal which you
  don't want reported, you now must exclude them with `-e tomorrow` or
  `date:-tomorrow` in the command, as with other reports.
  (Stephen Morgan)

Improvements

- Timedot format's doc has been rewritten.

Fixes

- Make balance assignments in forecasted transactions work again
  (broken in 1.22.1).
  Forecast transactions are now generated early and processed
  in the same way as other transactions.
  ([#1638](https://github.com/simonmichael/hledger/issues/1638), Stephen Morgan)

- aregister preserves the order of same-day transactions again
  (broken in 1.22.1).
  ([#1642](https://github.com/simonmichael/hledger/issues/1642), Stephen Morgan)

### hledger-ui 1.22.2

- Use hledger 1.22.2.

### hledger-web 1.22.2

- Use hledger 1.22.2.

### credits 1.22.2

Simon Michael, 
Stephen Morgan.

## 2021-08-02 hledger-1.22.1

### hledger 1.22.1

Improvements

- Bash shell completions (for hledger, hledger-ui, hledger-web) are
  now included in the hledger package's release tarballs, making them
  more likely to be installed by system packages. (Jakob Schöttl)

- roi docs now discuss how to quote multi-word queries.
  ([#1609](https://github.com/simonmichael/hledger/issues/1609),
  Dmitry Astapov)

- Allow megaparsec 9.1

Fixes

- `cur:` and `amt:` queries now match the original amounts before
  valuation and cost conversion, as they did before hledger 1.22. We
  believe this is the more useful behaviour in practice. 
  ([#1625](https://github.com/simonmichael/hledger/issues/1625), Stephen Morgan)

- Queries now work better with `register --related`, no longer showing
  duplicate postings when more than one posting in a transaction is
  matched. 
  ([#1629](https://github.com/simonmichael/hledger/issues/1629), Stephen Morgan)

- Valuation now works with `register --related`. 
  ([#1630](https://github.com/simonmichael/hledger/issues/1630), Stephen Morgan)

- Auto posting rules now also see inferred amounts,
  not just explicit amounts. 
  ([#1412](https://github.com/simonmichael/hledger/issues/1412), Stephen Morgan)

- The aregister command now properly ignores a `depth:` argument. 
  It might now also behave more correctly with valuation or `--txn-dates`.
  ([#1634](https://github.com/simonmichael/hledger/issues/1634), Stephen Morgan)

- Our info manuals now have more robust directory metadata (no
  subdirectory path), making them more likely to be linked in your
  top-level Info directory by system packages.
  ([#1594](https://github.com/simonmichael/hledger/issues/1594))
  (Simon Michael, Damien Cassou)

- The error message for a non-existent input file no longer shows
  excess double quotes.
  ([#1601](https://github.com/simonmichael/hledger/issues/1601),
  Stephen Morgan)

- Journal format docs: The commodity directive's scope is now
  correctly described (lasts until end of current file).

### hledger-ui 1.22.1

Improvements

- Document watch mode and its limitations. 
  ([#1617](https://github.com/simonmichael/hledger/issues/1617), 
  [#911](https://github.com/simonmichael/hledger/issues/911), 
  [#836](https://github.com/simonmichael/hledger/issues/836))

- Allow megaparsec 9.1.

Fixes

- Up/down keys work on the transaction screen again (broken since 1.22). 
  ([#1607](https://github.com/simonmichael/hledger/issues/1607), Stephen Morgan)

- Fix a possible off-by-one bug with valuation date when using `V` key on
  the transaction screen. (If it ever needs to use the journal's last day
  as valuation date, use that day, not the day after.)

### hledger-web 1.22.1

Improvements

- deps: Allow megaparsec 9.1.

Fixes

- The register chart works again when there are multiple commodities and 
  transaction prices (broken since 1.22). 
  ([#1597](https://github.com/simonmichael/hledger/issues/1597), Stephen Morgan)

### credits 1.22.1

Simon Michael,
Stephen Morgan,
Jakob Schöttl,
Dmitry Astapov.

## 2021-07-03 hledger-1.22

**Optimisations, bugfixes.**
([announcement](https://groups.google.com/g/hledger/c/t8-XbZBFtF0/m/tWCA8IQXAQAJ))

### project changes 1.22

Software:

- We now provide static executables for GNU/Linux on x64 (amd64) and arm32v7
  architectures. These are more portable and more likely to work on your linux
  system than the dynamic Ubuntu executables we have been providing.
  These will also be useful for Nextcloud.com users. (#1571) (Garret McGraw)

- GHC 9.0 support has been added. 
  We have dropped official support for GHC 8.0/8.2/8.4; building
  hledger now requires GHC 8.6 or newer. 

Docs:

- The info manuals now have the proper metadata so you or your
  packager can install them with `install-info` and they will appear
  in info's Directory. We also provide a `dir` file making it easy
  for developers to see the latest dev manuals in their info Directory.
  ([#1585](https://github.com/simonmichael/hledger/issues/1585)) (Damien Cassou, Simon Michael)

Chat:

- The hledger IRC channels (
  [#hledger:libera.chat](https://kiwiirc.com/nextclient/irc.libera.chat:+6697/#hledger),
  [#hledger-bots:libera.chat](https://kiwiirc.com/nextclient/irc.libera.chat:+6697/#hledger-bots)
  ) moved to Libera.chat.
    
- The hledger Matrix room (
  [#hledger:matrix.org](https://matrix.to/#/#hledger:matrix.org)
  ), is now on at least equal "official" footing with the IRC channel.
  
- I upgraded the matrix room to a newer version of the Matrix
  protocol. This effectively splits it into an old (read only) room
  and a new room. If you are joined to the old room, you might not
  have noticed; in your matrix client, please follow the link to the
  new room, ie #hledger:matrix.org.

- I briefly bridged the IRC and matrix rooms, because having two chats
  (four if we consider #plaintextaccounting) is a pain. I hope to try
  the experiment again at some point.

### hledger 1.22

Features

- check: A new `balancednoautoconversion` check requires transactions
  to balance without the use of inferred transaction prices. (Explicit
  transaction prices are allowed.) This check is included in `--strict`
  mode. The old `autobalanced` check has been renamed to
  `balancedwithautoconversion`. (Stephen Morgan)

Improvements

- Many internal optimisations have been applied (cf hledger-lib
  changelog). Overall, you can expect most reports to be about 20%
  faster. The register report is more than 2x faster and uses 4x less
  memory. (Stephen Morgan)

      ~/src/hledger$ quickbench -w hledger-1.21,hledger
      Running 5 tests 1 times with 2 executables at 2021-06-29 13:13:26 HST:
    
      Best times:
      +----------------------------------------------------++--------------+---------+
      |                                                    || hledger-1.21 | hledger |
      +====================================================++==============+=========+
      | -f examples/10000x1000x10.journal print            ||         1.18 |    0.90 |
      | -f examples/10000x1000x10.journal register         ||        12.82 |    5.95 |
      | -f examples/10000x1000x10.journal balance          ||         1.38 |    0.86 |
      | -f examples/1000x1000x10.journal balance --weekly  ||         0.96 |    0.78 |
      | -f examples/10000x1000x10.journal balance --weekly ||        13.07 |   10.79 |
      +----------------------------------------------------++--------------+---------+

- ANSI color is now disabled automatically (on stdout) when the
  `-o/--output-file` option is used (with a value other than `-`).
  ([#1533](https://github.com/simonmichael/hledger/issues/1533))

- ANSI color is now also available in debug output, determined in the
  usual way by `--color`, `NO_COLOR`, and whether the output (stderr)
  is interactive.
  
- The --version flag shows more details of the build, when known: git
  tag, number of commits since the tag, commit hash, platform and
  architecture. (Stephen Morgan)

- balance: Capitalisation of "account" and "total" (and lack of a
  colon in the latter) in CSV output is now consistent for single- and
  multi-period reports.

- balance reports' CSV output now includes full account names. ([#1566](https://github.com/simonmichael/hledger/issues/1566))
  (Stephen Morgan)

- csv: We now accept spaces when parsing amounts from CSV. (Eric
  Mertens)

- json: Avoid adding unnecessary decimal places in JSON output. (Don't
  increase them all to 10 decimal places.) (Stephen Morgan)
  
- json: Simplify amount precision (asprecision) in JSON output.
  It is now just the number of decimal places, rather than an object.
  (Stephen Morgan)

- GHC 9.0 is now officially supported. GHC 8.0, 8.2, 8.4 are no longer
  supported; we now require GHC 8.6 or greater.

- Added a now-required lower bound on containers. ([#1514](https://github.com/simonmichael/hledger/issues/1514))

Fixes

- Auto posting rules now match postings more precisely, respecting
  `cur:` and `amt:` queries. ([#1582](https://github.com/simonmichael/hledger/issues/1582)) (Stephen Morgan)

- balance reports: Fix empty cells when amounts are too wide to fit
  (broken since 1.20) ([#1526](https://github.com/simonmichael/hledger/issues/1526)). (Stephen Morgan)

- csv: Fix the escaping of double quotes in CSV output (broken in
  1.21). (Stephen Morgan, [#1508])

- register: Fix the running total when there is a report interval
  (broken since 1.19) ([#1568](https://github.com/simonmichael/hledger/issues/1568)). (Stephen Morgan)

- stats: No longer gets confused by posting dates. ([#772](https://github.com/simonmichael/hledger/issues/772)) (Stephen Morgan)

- timeclock: `hledger print` shows timeclock amounts with just 2
  decimal places again (broken in 1.21). ([#1527](https://github.com/simonmichael/hledger/issues/1527))

- When all transaction amounts have the same sign, the error message
  no longer adds an inferred price. ([#1551](https://github.com/simonmichael/hledger/issues/1551)) (Stephen Morgan)

- Cleaned up some references to old man pages. (Felix Yan)

### hledger-ui 1.22

Improvements

- Don't reset the `B`/`V` (cost, value) state when reloading with `g`
  or `--watch`. (Stephen Morgan)

- The accounts screen is a little smarter at allocating space to
  columns. (Stephen Morgan)

- Add support for the kakoune editor, and improve the invocations of
  some other editors. (crocket)

- The `--version` flag shows more detail (git tag/patchlevel/commit
  hash, platform/architecture). (Stephen Morgan)

- GHC 9.0 is now officially supported. GHC 8.0, 8.2, 8.4 are no longer
  supported; we now require GHC 8.6 or greater.

- Added a now-required lower bound on containers. ([#1514](https://github.com/simonmichael/hledger/issues/1514))

Fixes

- Queries in the register screen work again (broken in 1.21). ([#1523](https://github.com/simonmichael/hledger/issues/1523))
  (Stephen Morgan)

- Don't write to `./debug.log` when toggling value with `V`, or when
  reloading with `g` or `--watch` in the Transaction screen. ([#1556](https://github.com/simonmichael/hledger/issues/1556))
  (Simon Michael, Stephen Morgan)

### hledger-web 1.22

Improvements

- The --version flag shows more detail (git tag/patchlevel/commit
  hash, platform/architecture). (Stephen Morgan)

- Allow yesod-form 1.7 (Felix Yan)

- Add now-required lower bound on containers. ([#1514](https://github.com/simonmichael/hledger/issues/1514))

- GHC 9.0 is now officially supported. GHC 8.0, 8.2, 8.4 are no longer
  supported; we now require GHC 8.6 or greater.

Fixes

- In the add form, fix a bug where extra posting rows were not added
  when needed in certain web browsers. (charukiewicz)

### credits 1.22

This release was brought to you by
Simon Michael,
Stephen Morgan,
Felix Yan,
crocket,
Eric Mertens,
Damien Cassou,
charukiewicz,
and Garret McGraw.
## 2021-03-10 hledger-1.21

**More speed; more cli-accessible docs; value change report; improvements to balance reports, valuation and more**
([announcement](https://groups.google.com/g/hledger/c/xgO2ixBJcZc/m/FOxVeYGABAAJ))

### project-wide changes 1.21

- roi has a new cookbook doc, and example files have been updated.
  (Dmitry Astapov)

- Example CSV rules for the Daedalus wallet have been added.

- The default stackage resolver/GHC version has been bumped to
  lts-17.4/ghc-8.10.4.

- tools/generatejournal now includes more commodities and prices in
  generated journals. (Stephen Morgan)

- Our functional tests now also run on BSD. ([#1434], Felix Van der Jeugt)

- Addon scripts in bin/ have been updated for latest hledger API (Stephen Morgan).

- Addon scripts are now compiled as part of our CI tests, and always
  with the same version of hledger source they were shipped with. We
  now require script users to check out the hledger source tree and
  run the scripts (or, `bin/compile.sh`) from there. This keeps users
  and tests in sync, making things more reliable for everyone. ([#1453])

- Last but not least, hledger's bash completions (provided in ./shell-completions/)
  have been [thoroughly updated](https://github.com/simonmichael/hledger/blob/master/CHANGES.md#121-2021-03-10)
  ([#1404], [#1410], Vladimir Zhelezov).

### hledger cli 1.21

#### general

- hledger is now generally about 10% more memory- and time-efficient,
  and significantly more so in certain cases, eg journals with many
  total transaction prices. (Stephen Morgan)

- The `--help/-h` and `--version` flags are no longer position-sensitive;
  if there is a command argument, they now always refer to the command
  (where applicable).

- The new `--info` flag opens the hledger info manual, if "info" is in $PATH.
  `hledger COMMAND --info` will open COMMAND's info node.

- The `--man` flag opens the hledger man page, if "man" is in $PATH.
  `hledger COMMAND --man` will scroll the page to CMD's section, if "less"
  is in $PATH. (We force the use of "less" in this case, overriding any
  $PAGER or $MAN_PAGER setting.)

- Some command aliases, considered deprecated, have been removed:
  `txns`, `equity`, and the single-letter command aliases `a`, `b`,
  `p`, and `r`. This was discussed at
  https://github.com/simonmichael/hledger/pull/1423 and on the hledger
  mail list. It might annoy some folks; please read the issue and do
  follow up there if needed.
  
- Notable documentation updates:
  the separate file format manuals have been merged into the hledger manual,
  the topic hierarchy has been simplified,
  the `balance` command docs and "commands" section have been rewritten.

#### valuation

- Costing and valuation are now independent, and can be combined.
  `--value=cost` and `--value=cost,COMM` are still supported
  (equivalent to `--cost` and `--cost --value=then,COMM` respectively), 
  but deprecated. (Stephen Morgan)

- `-V` is now always equivalent to `--value=end`. (Stephen Morgan)

- `--value=end` now includes market price directives as well as
  transactions when choosing a valuation date for single-period
  reports. ([#1405], Stephen Morgan)

- `--value=end` now picks a consistent valuation date for single- and
  and multi-period reports. ([#1424], Stephen Morgan)

- `--value=then` is now supported with all reports, not just register. (Stephen Morgan)

- The too-vague `--infer-value` flag has been renamed to `--infer-market-price`.
  Tip: typing `--infer-market` or even `--infer` is sufficient.
  The old spelling still works, but is now deprecated.

#### commands

- add: Infix matches are now scored higher. If the search pattern
  occurs in full within the other description, that match gets a +0.5
  score boost.

- add: `--debug` now shows transaction matching results, useful when
  troubleshooting.

- balance: To accomodate new report types, the
  `--change|--cumulative|--historical|--budget` flags have been split
  into two groups: report type (`--sum|--budget|...`) and accumulation
  type (`--change|--cumulative|--historical`). `--sum` and `--change`
  are the defaults, and your balance commands should still work as
  before. (Stephen Morgan et al, [#1353])

- balance: The `--valuechange` report type has been added, showing the
  changes in period-end values. (Stephen Morgan, [#1353])

- balance: With `--budget`, the first and last subperiods are enlarged
  to whole intervals for calculating the budget goals also. (Stephen
  Morgan)

- balance: In multi-period balance reports, specifying a report period
  now also forces leading/trailing empty columns to be displayed,
  without having to add `-E`. This is consistent with `balancesheet`
  etc. ([#1396], Stephen Morgan)

- balancesheet, cashflow: declaring just a Cash account no longer
  hides other Asset accounts.

- check: Various improvements:

  - check name arguments may be given as case-insensitive prefixes
  - `accounts` and `commodities` may also be specified as arguments
  - `ordereddates` now checks each file separately ([#1493])
  - `ordereddates` no longer supports the `--unique` flag or query arguments
  - `payees` is a new check requiring payee declarations
  - `uniqueleafnames` now gives a fancy error message like the others
  - the old `checkdates`/`checkdupes` commands have been dropped

- help: The `help` command now shows only the hledger (CLI) manual,
  its `--info/--man/--pager` flags have been renamed to `-i/-m/-p`,
  and `--cat` has been dropped.

- help: With a TOPIC argument (any heading or heading prefix, case
  insensitive), it will open the manual positioned at this topic if
  possible. (Similar to the new `--man` and `--info` flags described above.)
  <!-- `hledger help print` will show `print`'s doc with the best available viewer (usually info). -->
  <!-- `hledger help print -m` is equivalent to `hledger print --man`.) -->

- payees: Add `--used`/`--declared` flags, like the `accounts` command.

- print: Now always shows amounts with all decimal places,
  unconstrained by commodity display style. This ensures more
  parseable and sensible-looking output in more cases, and behaves
  more like Ledger's print. (There may be a cosmetic issue with
  trailing zeroes.) ([#931], [#1465])

- print: With `--match`, infix matches are now scored higher, as with
  the add command.

- print: `--match` now provides debug output useful for troubleshooting.

  If you forget to give `--match` an argument, it can confusingly
  consume a following flag. Eg if you write:

      hledger print --match -x somebank   # should be: hledger print --match=somebank -x

  it gets quietly parsed as:

      hledger print --match="-x"

  Now you can at least use --debug to figure it out:

      hledger print --match -x somebank --debug
      finding best match for description: "-x"
      similar transactions:
      ...

- roi: Now supports the valuation options ([#1417], [#1483]), and uses
  commodity display styles. Also the manual has been simplified, with
  some content moved to the Cookbook. (Dmitry Astapov):

#### journal format

- The `commodity` directive now properly sets the display style of the
  no-symbol commodity. ([#1461])

#### csv format

- More kinds of malformed signed numbers are now ignored, in
  particular just a sign without a number, which simplifies sign
  flipping with amount-in/amount-out.

### hledger-ui 1.21

- Register screen: also show transactions below the depth limit, as in
  1.19, keeping the register balance in agreement with the balance
  shown on the accounts screen. This regressed in 1.20. ([#1468])

- Transaction screen: all decimal places are now shown. On the
  accounts screen and register screen we round amounts according to
  commodity display styles, but when you drill down to a transaction
  you probably want to see the unrounded amounts. (Like print, #cf
  [#931].)

- New flags `--man` and `--info` open the man page or info manual.
  (See hledger)

### hledger-web 1.21

- Register: a date range can be selected by dragging over a region on
  the chart. (Arnout Engelen, [#1471])

- Add form: the description field's autocompletions now also offer
  declared and used payee names.

- New flags `--man` and `--info` open the man page or info manual.
  (See hledger)

### credits 1.21

This release was brought to you by
Simon Michael,
Vladimir Zhelezov,
Stephen Morgan,
Dmitry Astapov,
Arnout Engelen,
Damien Cassou,
aragaer,
Doug Goldstein,
Caleb Maclennan,
and
Felix Van der Jeugt.

[#931]:  https://github.com/simonmichael/hledger/issues/931
[#1353]: https://github.com/simonmichael/hledger/issues/1353
[#1396]: https://github.com/simonmichael/hledger/issues/1396
[#1404]: https://github.com/simonmichael/hledger/issues/1404
[#1405]: https://github.com/simonmichael/hledger/issues/1405
[#1410]: https://github.com/simonmichael/hledger/issues/1410
[#1417]: https://github.com/simonmichael/hledger/issues/1417
[#1424]: https://github.com/simonmichael/hledger/issues/1424
[#1434]: https://github.com/simonmichael/hledger/issues/1434
[#1453]: https://github.com/simonmichael/hledger/issues/1453
[#1461]: https://github.com/simonmichael/hledger/issues/1461
[#1465]: https://github.com/simonmichael/hledger/issues/1465
[#1468]: https://github.com/simonmichael/hledger/issues/1468
[#1471]: https://github.com/simonmichael/hledger/issues/1471
[#1483]: https://github.com/simonmichael/hledger/issues/1483
[#1493]: https://github.com/simonmichael/hledger/issues/1493

## 2021-01-29 hledger-1.20.4

- aregister: ignore a depth limit, as in 1.19 (#1468).
  In 1.20-1.20.3, aregister had stopped showing transactions in subaccounts 
  below a depth limit. Now it properly shows all subaccount transactions, 
  ensuring that the register's final total matches a balance report with 
  similar arguments.

## 2021-01-29 hledger-ui-1.20.4

- ui: register: show all txns in/under an account at the depth limit (#1468).
  In 1.20-1.20.3, the register screen had stopped showing transactions 
  in accounts below a depth limit. Now it properly shows all subaccount transactions,
  even when there is a depth limit, ensuring that the register's final total 
  matches the balance shown on the account screen.

## 2021-01-29 hledger-web-1.20.4

- Use hledger 1.20.4.

## 2021-01-14 hledger 1.20.3, hledger-ui 1.20.3, hledger-web 1.20.3

- When searching for price chains during valuation/currency conversion:

  - It no longer hangs when there are price loops. (And in case of
    future bugs, it will give up rather than search forever.) (#1439)
  - It now really finds the shortest path. (#1443)
  - Useful progress info is displayed with `--debug=1` or `--debug=2`.

- balance, incomestatement: End-valued multi-period balance change
  reports (eg: `bal -MV`) have been reverted to show value-of-change,
  as in previous hledger versions, rather than change-of-value, for
  now. (#1353, #1428) (Stephen Morgan)

- balance: End-valued balance change reports now choose the same final
  valuation date and show consistent results whether single-period or
  multi-period. (#1424) (Stephen Morgan)

- balance: the `--drop` option now works with `csv` and `html` output.
  (#1456) (Ilya Konovalov)

- check: the `commodities` check, and `-s`/`--strict` mode, now ignore
  the "AUTO" internal pseudo-commodity. (#1419) (Ilya Konovalov)

- register: Then-valued multi-period register reports
  (eg: `register -M --value=then`) now calculate the correct values.
  (#1449) (Stephen Morgan)

- roi: now shows a better error message when required prices are
  missing. (#1446) (Dmitry Astapov)

- The no-symbol commodity's input number format can now be set by a
  `commodity` directive, like other commodities. (#1461)

## 2020-12-28 hledger 1.20.2 

- help: Fix loss of capitalisation in part of the hledger-ui manual. 

- help: Fix the node structure in info manuals.

- Drop unused parsec dependency.

## 2020-12-28 hledger-ui 1.20.2 

- Fix loss of capitalisation in part of the manual. 

- Fix the info manual's node structure.

## 2020-12-28 hledger-web 1.20.2 

- Fix the info manual's node structure.

## 2020-12-15 hledger 1.20.1 

- bal, bs, cf, is: In amount-sorted balance reports, equal-balance accounts 
  are now reliably sorted by name. (Simon Michael, Stephen Morgan)

- help: Fix the topic hierarchy in Info manuals.

## 2020-12-15 hledger-ui 1.20.1 

- Fix the F key (toggle future/forecast transactions), which in 1.20 
  would only work twice. (#1411)

- Fix loss of forecasted transactions when the journal was reloaded
  while they were hidden. (#1204)

## 2020-12-06 hledger-web-1.20.1

- don't hang when reloading the journal, eg after adding a transaction
  or editing the file. (#1409)

## 2020-12-05 hledger-1.20

**Strict mode; check command; rendering, speed, and valuation fixes**

### project-wide changes 1.20

- examples: clean up & add more budgeting examples; stripe csv

- a hie.yaml file has been added, so hledger source loads
  easily in IDEs supporting haskell-language-server

- The functional tests in tests/ have been moved into the respective
  packages, eg hledger/test/ and hledger-ui/test/.

- Shake cabalfiles: now gives an error when it fails

- make bench: add some large tabular reports; 
  run just the slowest commands by default;
  run after make (func)test

### hledger cli 1.20

#### general

- strict mode: with -s/--strict, hledger requires that
  all accounts and commodities are declared with directives.

- Reverted a stripAnsi change in 1.19.1 that caused a 3x slowdown of amount rendering
  in terminal reports. (#1350)

- Amount and table rendering has been improved, so that stripAnsi is no longer needed.
  This speeds up amount rendering in the terminal, speeding up some reports by 10% or more since 1.19.
  (Stephen Morgan)

- Amount eliding no longer displays corrupted ANSI codes (#1352, Stephen Morgan)

- Eliding of multicommodity amounts now makes better use of available space,
  avoiding unnecessary eliding (showing as many amounts as possible within
  32 characters). (Stephen Morgan)

- Command line help for --no-elide now mentions that it also disables eliding of
  multicommodity amounts.

- Query terms containing quotes (eg to match account names containing quotes)
  now work properly. (#1368, Stephen Morgan)

- cli, journal: Date range parsing is more robust, fixing failing/incorrect cases such as: (Stephen Morgan)

  - a hyphenated range with just years (`2017-2018`)
  - a hyphenated date with no day in a hyphenated range (`2017-07-2018`)
  - a dotted date with no day in a dotted range (`2017.07..2018.02`)
 
- Debug output is prettier (eg, in colour), using pretty-simple instead of pretty-show.

- csv, timedot, timeclock files now respect command line --alias options,
  like journal files.  (#859)

- Market price lookup for value reports is now more robust, fixing several bugs
  (and debug output is more informative).
  There has been a slight change in functionality: when chaining prices,
  we now prefer chains of all "forward" prices, even if longer, with chains
  involving reverse prices being the last resort.
  (#1402)

#### commands

- add: number style (eg thousands separators) no longer disturbs the value
  that is offered as default. (#1378)

- bal: --invert now affects -S/--sort-amount, reversing the order. (#1283, #1379) (Stephen Morgan)

- bal: --budget reports no longer insert an extra space inside the brackets. (Stephen Morgan)

- bal: --budget reports now support CSV output (#1155)

- bal, is, bs --change: 
  Valued multiperiod balance change reports now show changes of value, 
  rather than the value of changes. (#1353, Stephen Morgan)

- bal: clearer debug output, following debug levels policy

- check: A new command which consolidating the various check-* commands.
  It runs the default, strict, or specified checks and produces
  no output and a zero exit code if all is well.

- check-dates: this command is deprecated and will be removed
  in next release; use "hledger check ordereddates" instead.

- check-dupes: this command is deprecated and will be removed
  in next release; use "hledger check uniqueleafnames" instead.

- import: The journal's commodity styles (declared or inferred) are now applied
  to imported amounts, overriding their original number format.

- roi: TWR now handles same-day pnl changes and cashflows,
  calculation failure messages have been improved, and
  the documentation includes more detail and examples.
  (#1398) (Dmitry Astapov)

#### journal format

- The journal's commodity styles are now applied to forecasted transactions. (#1371)

- journal, csv: commodity style is now inferred from the first amount, as documented,
  not the last. This was "working wrongly" since hledger 1.12..

- A zero market price no longer causes "Ratio has zero denominator" error
  in valued reports. (#1373)

#### csv format

- The new `decimal-mark` rule allows reliable number parsing
  when CSV numbers contain digit group marks (eg thousands separators).

- The CSV reader's verbose "assignment" debug output is now at level 9.

### hledger-ui 1.20

- When entering a query with `/`, malformed queries/regular expressions
  no longer cause the program to exit. (Stephen Morgan)

- Eliding of multicommodity amounts now makes better use of available space. (Stephen Morgan)

- `E` now parses the `HLEDGER_UI_EDITOR` or `EDITOR` environment variable
  correctly on Windows (ignoring the file extension), so if you have that set
  it should be better at opening your editor at the correct line.

- `E` now supports positioning when `HLEDGER_UI_EDITOR` or `EDITOR` 
  is VS Code ("`code`") (#1359)

- hledger-ui now has a (human-powered) test suite.

### hledger-web 1.20

- hledger-web's test suite is re-enabled, now included in the main executable.
  hledger-web --test [-- HSPECARGS] runs it.

- Fix --forecast, broken in hledger-web since 1.18 (#1390)

- Fix unescaped slashes in hledger-web description on hackage  (TANIGUCHI Kohei)

- The hledger-web version string is now provided at /version, as JSON (#1152)

- The session file (hledger-web_client_session_key.aes) is now written in 
  $XDG_DATA_DIR rather than the current directory.
  Eg on non-Windows systems this is ~/.cache/ by default (cf
  https://hackage.haskell.org/package/directory/docs/System-Directory.html#t:XdgDirectory).
  (#1344) (Félix Sipma)

### credits 1.20

This release was brought to you by
Simon Michael,
Stephen Morgan,
Dmitry Astapov,
TANIGUCHI Kohei,
legrostdg.


## 2020/09/07 hledger 1.19.1

### hledger cli 1.19.1

- Fix alignment of coloured numbers (#1345, #1349, Stephen Morgan)

- Fix a regression in account type autodetection for accounts with
  capitalised names. (#1341)

- Allow megaparsec 9

### hledger-ui 1.19.1

- Allow megaparsec 9

### hledger-web 1.19.1

- Allow megaparsec 9

- Drop redundant semigroups dependency (Felix Yan)

## 2020/09/01 hledger-1.19

**New aregister and codes commands,
more powerful CSV conditional rules, 
new sql output format,
consistently default to flat mode,
better colour control,
cashflow report customisable like the others,
more number/date/regexp parsing/validation,
more speed.**

### hledger cli 1.19

#### new

- [aregister]: a new command showing a transaction-oriented register
  for a single account. This is like hledger-ui, hledger-web, or your
  bank statement, and unlike the register command which shows
  individual postings possibly spanning multiple accounts. You might
  prefer aregister when reconciling real-world asset/liability
  accounts, and register when reviewing detailed revenues/expenses.
  (#1294)

- [codes]: a new command for listing transaction codes

- print: a new `sql` [output format] has been added (Dmitry Astapov)

- A `--color/--colour` command line option, support for the `NO_COLOR`
  environment variable, and smarter autodetection of colour terminals
  have been added. (#1296)

- In queries, you can now use q or Q to specify a year quarter, like
  `2020q1` or `Q4`. (#1247, Henning Thieleman, Stephen Morgan)

- When specifying report intervals, you can use `fortnightly` as a
  synonym for `biweekly`. (Stephen Morgan)

#### improved

- Reports involving multiple commodities now show at most two
  commodities per amount by default, making multicolumn reports less
  wide and more readable. Use the --no-elide flag to prevent this.

- Flat (AKA list) mode is now the consistent default used by all
  balance reports and other commands showing accounts. (Stephen
  Morgan)

- All commands supporting tree/list mode now accept -t and -l as short
  forms of the --tree and --flat flags. (#1286)

- account,bal,bs,cf,is: --drop now also works in tree mode (Stephen Morgan)

- bal,bs,cf,is: tabular balance reports now elide (compress) boring
  parent accounts, like the non-tabular reports. (Stephen Morgan)

- bal,bs,cf,is: monthly column headings are no longer be displayed as
  just the month abbreviations, if multiple years are being displayed.

- bal --budget: with --cumulative or --historical, column headings now
  correctly show the period end dates rather than date spans.

- bs,cf,is: --no-total now hides subtotals as well as the grand total
  (Stephen Morgan)

- bs,cf,is: -%/--percent no longer implies --no-total. (Stephen
  Morgan)

- roi: errors are now shown without a call stack

- tags: the new --parsed flag causes all tags or values to be shown,
  including duplicates, in the order they were parsed. Blank/empty
  values are omitted by default and can be shown with -E/--empty.

- Debug output is now organised better by debug level.
  The levels are:

  0. normal command output only (no warnings)
  1. useful warnings & most common troubleshooting info (valuation, eg)
  2. common troubleshooting info, more detail
  3. report options selection
  4. report generation
  5. report generation, more detail
  6. input file reading
  7. input file reading, more detail
  8. command line parsing
  9. any other rarely needed or more in-depth info

#### correctness/robustness

- Added a missing lower bound for aeson, making cabal installs more
  reliable. (#1268)

- When parsing dates, we now require the year to have at least four
  digits. So eg Feb 1 in the year 10 would need to be written
  `0010-02-01`, not `10/02/01`. would need to be written `0200/1/1`.
  This change was made for consistency and to avoid ambiguities; let
  us know if it causes you trouble.

- Command line options taking a numeric argument are now validated
  more carefully to avoid any issues with unexpected negatives or Int
  overflow. (Stephen Morgan)

- Numbers with more than 255 decimal places, which we do not support,
  now give an error instead of silently misparsing. (#1326)

- Digit groups in numbers are now limited to at most 255 digits each.
  (#1326)

- Account aliases (on command line or in journal) containing a bad
  regular expression now give a more detailed error message.

- In the argument of `amt:` queries, whitespace around the operator,
  sign, or number no longer causes a parse error. (#1312)

- A tab character could get parsed as part of a commodity symbol, with
  confusing results. This no longer happens. (#1301, Dmitry Astapov)

- add: fixed an error in the command line help (arguments are inputs,
  not a query)

#### journal format

- account directives can specify a new account type, `Cash`, for
  accounts which should be displayed in the `cashflow` report. `Cash`
  accounts are also `Asset` accounts.
  
- Documentation of [account types] has been improved.

#### csv format

- Conditional rule patterns can now be
  [grouped](csv.md#combining-matchers) with the `&` (AND) operator,
  allowing more powerful matching. (Michael Sanders)

- "[If tables](csv.md#if-table)", a compact bulk format for
  conditional rules, have been added. (Dmitry Astapov)

- csv conversion with a lot of conditional rules is now faster (Dmitry Astapov)

- Invalid csv rules files now give clearer parse error messages.
  (Dmitry Astapov)

- Inferring the appropriate default field separator based on file
  extension (, for .csv, ; for .ssv, \t for .tsv) now works as
  documented.

### hledger-ui 1.19

- A --color/--colour command line option, support for the NO_COLOR
  environment variable, and smarter autodetection of colour terminals
  have been added. (#1296)

- -t and -l have been added as short forms of --tree and --flat
  command line flags.

- Flat (AKA list) mode is now the default for the accounts screen.

- t now toggles tree/list mode, while T sets the "today" period
  (#1286)

- register screen: multicommodity amounts containing more than two
  commodities are now elided, unless the --no-elide flag is used.

- register screen: a transaction dated outside the report period now
  is not shown even if it has postings dated inside the report period.

- ESC now restores exactly the app's state at startup, which includes
  clearing any report period limit. (#1286)

- DEL/BS no longer changes the tree/list mode.

- q now exits the help dialog, if active; press q again to exit the
  app. (#1286)

- The help dialog's layout is improved.

### hledger-web 1.19

- Added a missing lower bound for aeson, making cabal installs more
  reliable. (#1268)

- Queries containing a malformed regular expression (eg the single
  character `?`) now show a tidy error message instead "internal
  server error". (Stephen Morgan, Simon Michael) (#1245)

- In account registers, a transaction dated outside the report period
  now is not shown even if it has postings dated inside the report
  period.

### credits 1.19

This release was brought to you by
Simon Michael,
Stephen Morgan,
Dmitry Astapov,
Michael Sanders,
Henning Thielemann,
Martin Michlmayr,
Colin Woodbury.

[aregister]: hledger.html#aregister
[codes]: hledger.html#codes
[output format]: hledger.html#output-format
[account types]: journal.html#account-types

## 2020/06/21 hledger 1.18.1

### hledger cli 1.18.1

- value reports now work as in 1.17 again; inferring market prices from
  transactions is now an option, requiring the --infer-value flag.
  (#1239, #1253)

- print: amounts in csv output now have commodity symbol, digit group
  separators and prices removed (Dmitry Astapov)

- begin more systematic level usage in --debug output

- journal: document recursive wildcards

### hledger-ui 1.18.1

- Fix F key having no effect (#1255) (Dmitry Astapov)


## 2020/06/07 hledger 1.18

**Fixed JSON output;
market prices inferred from transactions;
more Ledger file compatibility;
more flexible journal entries from CSV;
misc. fixes and improvements.**

### project-wide changes 1.18

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
  - scheduled and on-demand testing (push to master, push to ci-* branches, pull request, weekly)
  - now tested: all GHC versions, doctests, haddock building
  - new shortcut url: https://ci.hledger.org

### hledger cli 1.18

- The --forecast flag now takes an optional argument
  (--forecast=PERIODICEXPR), allowing periodic transactions to
  start/end on any date and to overlap recorded transactions.
  (#835, #1236) (Dmitry Astapov)

- An upper case file extension no longer confuses file format
  detection. (#1225)

- In the commands list, redundant source scripts are now hidden
  properly when a corresponding .com/.exe file exists. (#1225)

- We now show `..` instead of `-` to indicate date ranges, eg in
  report titles, to stand out more from hyphenated dates. (Stephen Morgan)
  
- Period expressions (eg in -p, date:, and periodic rules) now accept
  `to`, `until`, `-`, or `..` as synonyms. (Stephen Morgan)

- When parsing amounts, whitespace between sign and number is now allowed.

- A clearer error message is shown on encountering a malformed regular
  expression.

#### commands

- commands allowing different output formats now list their supported
  formats accurately in --help (#689)

- commands allowing JSON output now actually produce JSON (#689)

- bal, bs: show .. (not ,,) in report titles, like other reports

#### journal format

- We now also infer market prices from transactions, like Ledger.
  See https://hledger.org/hledger.html#market-prices (#1239). 
  
  Upgrade note: this means value reports (-V, -X etc.) can give
  different output compared to hledger 1.17. If needed, you can
  prevent this by adding a P directive declaring the old price, on or
  after the date of the transaction causing the issue.

- The include directive now accepts a file format prefix, like the
  -f/--file option. This works with glob patterns too, applying the
  prefix to each path. This can be useful when included files don't
  have the standard file extension, eg:

      include timedot:2020*.md

- We now accept (and ignore) Ledger-style lot dates
  (`[DATE]`) and four lot price forms (`{PRICE}`, `{{PRICE}}`,
  `{=PRICE}`, `{{=PRICE}}`), anywhere after the posting amount but
  before any balance assertion.

- We now accept Ledger-style parenthesised "virtual posting
  costs" (`(@)`, `(@@)`). In hledger these are equivalent to the
  unparenthesised form.

- The unbalanced transaction error message is clearer, especially when
  postings all have the same sign, and is split into multiple lines
  for readability.

#### csv format

- You can now generate up to 99 postings in a transaction. (Vladimir Sorokin)

- You can now generate postings with an explicit 0 amount. (#1112)

- For each posting, when both numbered and unnumbered amount
  assignments are active (eg: both `amount` and `amount1`), we ignore
  the unnumbered ones. This makes it easier to override old `amount`
  rules.
  
- Fix a 1.17.1 regression involving amount-in/amount-out. (#1226)

- Assigning too many non-zero or zero values to a posting amount now
  gives a clearer error. (#1226)

### hledger-ui 1.18

- builds with hledger 1.18

### hledger-web 1.18

- The filter query is now preserved when clicking a different account
  in the sidebar. (Henning Thielemann)

- Hyperlinks are now more robust when there are multiple journal
  files, eg links from register to journal now work properly.
  (#1041) (Henning Thielemann)

#### add form

- Fixed a 2016 regression causing too many rows to be added by
  keypresses in the last amount field or CTRL-plus (#422, #1059).

- Always start with four rows when opened.

- Drop unneeded C-minus/C-plus keys & related help text.

### credits 1.18

This release was brought to you by
Simon Michael,
Stephen Morgan,
Dmitry Astapov,
Henning Thielemann,
Andriy Mykhaylyk,
Pavan Rikhi,
Vladimir Sorokin.


## 2020/03/01 hledger 1.17

**CSV single-field matching; easier SSV/TSV conversion; 
fixed/enhanced close command; undo in add command; more JSON output; 
org headline support in timedot format; GHC 8.10 support.**

### project-wide changes 1.17

- hledger-install tweaks

- Simpler, clearer structure in the manuals and hledger.org sidebar.

- A new [Quick Start](https://hledger.org/start.html) page

- A new [Common Tasks](https://hledger.org/hledger.html#common-tasks) section in the hledger manual

- A new [Invoicing](https://hledger.org/invoicing.html) how-to

- A basic example of rule parsing for the output of csb2format. (Evilham)
  csb2format deals with the CSB43/AEB43 format, which all banks operating in
  Spain must support.


### hledger cli 1.17

- hledger's default date format is now ISO-8601 (YYYY-MM-DD).
  (Brian Wignall, Jakob Schöttl, Simon Michael)

- Drop the file format auto-detection feature.

  For a long time hledger has auto-detected the file format when it's
  not known, eg when reading from a file with unusual extension (like
  .dat or .txt), or from standard input (-f-), or when using the
  include directive (which currently ignores file extensions). This
  was done by trying all readers until one succeeded. Recent changes
  to timedot format have made this unreliable. So now, hledger will no
  longer guess; when there's no file extension or reader prefix
  available, it always assumes journal format. To specify one of the
  other formats, you must use its standard file extension
  (`.timeclock`, `.timedot`, `.csv`, `.ssv`, `.tsv`), or a reader
  prefix (`-f csv:foo.txt`, `-f timedot:-`).
  Experimental, feedback welcome.

- More robust quoting of arguments for addons (#457). (Jacek Generowicz) 
  Command lines like `hledger ui 'amt:>200'` failed, because the
  process of dispatching from `hledger` to `hledger-ui` lost the
  quotes around `amt:>20` and the `>` character was interpreted as a
  shell redirection operator.

- --output-format now rejects invalid formats

- Numbers in JSON output now provide a floating point Number
  representation as well as our native Decimal object representation,
  since the latter can sometimes contain 255-digit integers. The
  floating point numbers can have up to 10 decimal digits (and an
  unbounded number of integer digits.)
  Experimental, suggestions needed. (#1195)

- Fix finding latest date in queryEndDate Or queries and simplify
  date comparison code. (Stephen Morgan)

- Fix extra $ symbol (Mateus Furquim)


#### commands

- add: you can use `<` to undo and redo previous inputs (Gaith Hallak)

- bs, cf, is, bal, print, reg: support json output

- bs, cf, is: fix excess subreport columns in csv output

- bs, cf, is, bal: fix an issue with border intersections in
  --pretty-tables output. (Eric Mertens)

- close: fix a rounding bug that could generate unbalanced transactions. (#1164)

- close: hide cost prices by default, show them with --show-costs.
  close no longer preserves costs (transaction prices) unless you ask
  it to, since that can generate huge entries when there are many
  foreign currency/investment transactions. (#1165)

- close: equity amounts are omitted by default, for simpler entries;
  -x/--explicit shows them (usually causing more postings). (#1165)

- close: --interleaved generates equity postings alongside each closed
  account, making troubleshooting easier.

- close: "equity:opening/closing balances" is now the default
  closing and opening account.

- close: --close-desc/--open-desc customise the closing/opening
  transaction descriptions. (#1165)

- close: some --open*/--close* flags have been simplified for memorability:
  ```plain
  --closing -> --close
  --opening -> --open
  --close-to -> --close-acct
  --open-from -> --open-acct
  ```
  The old flags are accepted as hidden aliases, and deprecated. (#1165)

- print, register: a new valuation type, --value=then, shows the
  market value at each posting's date.

- print: -V/-X/--value now imply -x/--explicit, as -B/--cost does.
  This avoids a bug where print -V of a transaction with an implicit
  commodity conversion would convert only some of its postings to value.

#### journal format

- The include directive no longer tries all readers.  It now picks
  just one, based on the included file's extension, defaulting to
  journal.  (It doesn't yet handle a reader prefix.)

- The default commodity (`D`) directive now limits display precision
  too, and is fully equivalent to `commodity` directives for setting a
  commodity's display style. (#1187)

#### csv format

- Conditional blocks can now match single fields. \o/

- The experimental --separator command line option has been dropped,
  replaced by a new `separator` directive in CSV rule files. (Aleksandar Dimitrov)

- The `.tsv` and `.ssv` file extensions are now recognised,
  and will set the default `separator` to TAB and semicolon respectively.
  (#1179)

- Manually assigning the "expenses:unknown" account name now works. (#1192)

- CSV rule keywords are now case insensitive. (Aleksandar Dimitrov)

#### timeclock format

- Misc. fixes making parsing more robust. (Jakob Schöttl)

#### timedot format

- Org mode headlines (lines beginning with one or more `*` followed by
  a space) can be used as date lines or timelog items (the stars are
  ignored). Also all org headlines before the first date line are
  ignored. This means org users can manage their timelog as an org
  outline (eg using org-mode/orgstruct-mode in Emacs), for
  organisation, faster navigation, controlling visibility etc.
  Experimental.
- You can now write a description after a date, which will be used in
  all of that day's transactions.
  Experimental.

### hledger-ui 1.17

- Don't enable --auto by default.

- Don't enable --forecast by default; drop the --future flag. (#1193)

  Previously, periodic transactions occurring today were always shown,
  in both "present" and "future" modes. To fix this, generation of
  periodic transactions and display of future transactions (all kinds)
  have been combined as "forecast mode", which can be enabled with
  --forecast and/or toggled with the F key. The --future flag is now a
  hidden alias for --forecast, and deprecated.

### hledger-web 1.17

- Fonts have been improved on certain platforms. (David Zhang)

- IPv6 is supported (Amarandus) (#1145)

- The --host option can now take a local hostname (Amarandus) (#1145)

- New --socket option to run hledger-web over an AF_UNIX socket file. (Carl Richard Theodor Schneider)
  This allows running multiple instances of hledger-web on the same
  system without having to manually choose a port for each instance,
  which is helpful for running individual instances for multiple
  users. In this scenario, the socket path is predictable, as it can
  be derived from the username.

- The edit and upload forms now normalise line endings, avoiding parse
  errors (#1194). Summary of current behaviour:

  - hledger add and import commands will append with (at least some)
    unix line endings, possibly causing the file to have mixed line
    endings

  - hledger-web edit and upload forms will write the file with
    the current system's native line endings, ie changing all
    line endings if the file previously used foreign line endings.

- Numbers in JSON output now provide a floating point Number
  representation as well as our native Decimal object representation,
  since the latter can sometimes contain 255-digit integers. The
  floating point numbers can have up to 10 decimal digits (and an
  unbounded number of integer digits.)
  Experimental, suggestions needed. (#1195)

### credits 1.17

This release was brought to you by
Simon Michael,
Aleksandar Dimitrov,
Brian Wignall,
Stephen Morgan,
Jacek Generowicz,
Gaith Hallak,
Eric Mertens,
Jakob Schöttl,
Carl Richard Theodor Schneider,
David Zhang,
Amarandus,
Evilham,
Mateus Furquim and
Rui Chen.


## 2019/12/01 hledger 1.16

**GHC 8.8 support, much more powerful CSV conversion rules,
percentage balance reports, misc improvements.**
([mail](https://groups.google.com/d/topic/hledger/wiMafb11uBQ/discussion))

### project-wide changes 1.16

- add support for GHC 8.8, base-compat 0.11 (#1090)

- drop support for GHC 7.10

- add descriptions to most issue tracker labels

- matrix.hledger.org now redirects to a more readable/useful url

### hledger cli 1.16

- The `--anon` flag now also anonymises transaction codes and account
  names declared with account directives. (Mykola Orliuk) (#901)

- The benchmark suite has been disabled.

#### commands

- balance/bs/cf/is: balance commands now support the `-%`/`--percent` flag
  to show amounts as percentages of the column's total. (Michael Kainer)

  If there are multiple commodities involved in a report hledger bails
  with an error message. This can be avoided by using `-B`/`--cost`. Also note
  that if one uses -% with the balance command the chances are high that
  all numbers are 0. This is due to the fact that by default balance sums
  up to zero. If one wants to use -% in a meaningful way with balance one
  has to add a query.

  In order to keep the implementation as simple as possible `--tree` has no
  influence over how the percentages are calculated, i.e., the percentages
  always represent the fraction of the columns total. If one wants to know
  the percentages relative to a parent account, one has to use a query to
  narrow down the accounts.

- balance: `--budget` no longer errors when there is neither budget nor
  transactions in the report period (Dmitry Astapov)

- balance: `--budget` has improved debug output (shows budget txns)
  (Dmitry Astapov)

- check-dates: now sets the exit status code (Amitai Burstein)

- close: no longer strips zeroes after the decimal mark, and preserves
  parseable output (#1137)

- close: the `--close-to`, `--open-from` options allow closing/opening
  account names to be chosen

- import: create the journal if missing, like the add command
  Streamlines import/migration instructions.

- import: `--catchup` marks all transactions imported, without importing

- import: more informative output: mention the input files, also show
  a message when nothing was imported

- prices: show price amounts with proper display style; always show
  full precision

- roi: don't give an error with empty input data (Dmitry Astapov)

- tests: unit tests are now run by tasty, and show coloured output by default (#1090).
  Test running options have changed, see the command help. 
  Some unit tests have been collapsed, so the reported test count has
  dropped a little.

#### journal format

- Fixed: wrong dates generated by certain periodic transaction rules,
  eg "~ every 12 months from 2019/04". (Dmitry Astapov) (#1085)

#### csv format

CSV conversion is now more powerful (#1095, Dmitry Astapov, Simon Michael):

- A variable number of postings can be generated, from zero to nine. (#627, #1095)

- In conditional blocks, `skip` can be used to skip one or more
  records after a pattern match, or the new `end` rule can be used to
  skip all remaining records. (#1076)

- The new `balance-type` CSV rule controls which kind of balance
  assertions are generated (=, ==, =*, ==*)

- Postings with balance assignments can be generated. (#1000)

- Both the amount-in/amount-out fields having a non-empty value is now
  accepted, as long as one of them is zero. (#570)

- Line feeds/carriage returns in (quoted) CSV values are now converted
  to spaces during conversion. (#416, #841)

- Field assignments can now unset a field (eg a posting can be
  suppressed by assigning no value to its account).

- CSV records with varying lengths are now allowed; short records will
  be padded with empty fields as needed. This allows us to handle eg
  exported Google spreadsheets, where trailing empty fields are omitted.

- Journals generated from CSV are now finalised and checked like
  ordinary journals (#1000). So invalid transactions generated from
  CSV will be rejected, amount styles will be standardised etc.

- Fixed: we no longer add an extra (third) space between description and comment.

- Fixed: whitespace on the line after an if block no longer causes misparsing. (#1120)

- Fixed: an empty field assignment no longer consumes the next line. (#1001)

- Fixed: interpolation of field names containing punctuation now works.

- Docs have been rewritten and clarified.

Migration notes:

- When `print`ing from CSV, there is now one less space between
  transaction descriptions and comments, which may generate noisy
  diffs if you are comparing old and new reports. `diff -w`
  (`--ignore-all-space`) will filter these out.

- CSV rules now give you more freedom to generate any journal
  entries you want, including malformed or unbalanced ones. 
  The csv reader now checks the journal after conversion,
  so it will report any problems with the generated entries.

- Balance assertions generated from CSV are not checked, currently.
  This is appropriate when you are downloading partial CSV data to
  be merged into your main journal. If you do need to check balance
  assertions right away, you can pipe through hledger again:

      $ hledger -f a.csv print | hledger -f- print

### hledger-ui 1.16

- the B and V keys toggle cost or value display (like the `-B` and `-V`
  command line flags)

- uses hledger 1.16.1

### hledger-web 1.16

- The `--cors` option allows simple cross-origin requests to hledger-web
  (Alejandro García Montoro)

- Weeks in the add form's date picker now start on Mondays (#1109)
  (Timofey Zakrevskiy)

- No longer depends on json (#1190) or mtl-compat.

- The test suite has been disabled for now.

### credits 1.16

Release contributors:
Simon Michael,
Dmitry Astapov,
Mykola Orliuk,
Brian Wignall,
Alejandro García Montoro,
Timofey ZAKREVSKIY,
Amitai Burstein,
Michael Kainer.


## 2019/09/01 hledger 1.15

**new website, faster and more flexible valuation, more accurate close command,
tags `--values`, new descriptions/payees/notes/diff commands, misc. fixes.**
([mail](https://groups.google.com/d/topic/hledger/ZIuHR_Gv7o8/discussion))

### project-wide changes 1.15

- new unified website: hledger.org now has its own git repo, has
  absorbed the github wiki, and is generated with Sphinx.

- hledger-api is now mothballed. Its functionality is included in hledger-web.

- hledger-install.sh: bump to lts-14.4, hledger 1.15, drop
  hledger-api, now also works on FreeBSD 12.

- Wine has been added to the list of install options.

- Dmitry Astapov's hledger docker image is now based on the "haskell" image.

- Andreas Pauley's hledger-makeitso has been renamed to hledger-flow.

- bin/ addon scripts: hledger-swap-dates added; hledger-check,
  hledger-smooth updated. (#1072)

- shell-completion scripts: updated

- github: FUNDING.yml / sponsor button configured

- tools: generatejournal updates: vary amount, make reports with fewer
  zeroes, start from a fixed year to keep tests stable, also generate
  P records. (#999)

- tools: make, shake, CI: misc. updates

- doc: add a README for the functional tests, linked from contrib guide

### hledger cli 1.15

- There is a new valuation option `--value=TYPE[,COMM]`, with
  backwards-compatible `-B`/`--cost`, `-V`/`--market`, `-X`/`--exchange=COMM`
  variants. These provide control over valuation date (#329), and
  inference of indirect market prices (similar to Ledger's `-X`) (#131).
  Experimental.
  
- Market valuation (`-V`/`-X`/`--value`) is now much faster (#999):

      +-------------------------------------------++--------------+--------------+
      |                                           || hledger-1.14 | hledger-1.15 |
      +===========================================++==============+==============+
      | -f examples/10000x1000x10.journal bal -Y  ||         2.43 |         2.44 |
      | -f examples/10000x1000x10.journal bal -YV ||        44.91 |         6.48 |
      | -f examples/10000x1000x10.journal reg -Y  ||         4.60 |         4.15 |
      | -f examples/10000x1000x10.journal reg -YV ||        61.09 |         7.21 |
      +-------------------------------------------++--------------+--------------+

- How date options like `-M` and `-p` interact has been updated and clarified.
  (Jakob Schöttl) (#1008, #1009, #1011)

- Restore `--aux-date` and `--effective` as `--date2` aliases (#1034).
  These Ledger-ish spellings were dropped over the years, to improve
  `--help`'s layout. Now we support them again, as semi-hidden flags
  (`--help` doesn't list them, but they are mentioned in `--date2`'s help).

#### commands

- add, web: on Windows, trying to add transactions to a file path
  containing trailing periods (eg `hledger add -f  Documents.\.hledger.journal`) 
  now gives an error, since this could cause data loss otherwise (#1056).
  This affects the add command and hledger-web's add form.

- bal: `--budget`: don't always convert to cost.

- bal: `--budget`: don't show a percentage when budgeted and actual
  amounts are in different commodities.

- bal/bs/bse: `-H`/`--historical` or `--cumulative` now disables `-T`/`--row-total` (#329).
  Multiperiod balance reports which show end balances (eg, `bal -MH` or `bs -M`)
  no longer show a Totals column, since summing end balances generally
  doesn't make sense.

- bs: show end date(s) in title, not transactions date span (#1078)
  Compound balance reports showing ending balances (eg balancesheet),
  now show the ending date (single column) or range of ending
  dates (multi column) in their title. ,, (double comma) is used
  rather than - (hyphen) to suggest a sequence of discrete dates
  rather than a continuous span.

- close: preserve transaction prices (costs) accurately (#1035).
  The generated closing/opening transactions were collapsing/misreporting
  the costs in balances involving multiple costs.
  Now, each separately-priced amount gets its own posting.
  (And only the last of these (for each commodity) gets a balance assertion.)
  Also the equity posting's amount is now always shown explicitly, 
  which in multicommodity situations means that multiple equity postings are shown. 
  The upshot is that a `balance -B` report will be unchanged after
  the closing & opening transactions generated by the close command.

- descriptions, payees, notes commands added (Caleb Maclennan)

- diff: Gabriel Ebner's hledger-diff is now a built in command,
  and https://github.com/gebner/hledger-diff is deprecated.

- help: don't require a journal file

- print: now also canonicalises the display style of balance assertion amounts (#1042)

- reg: show negative amounts in red, like balance and Ledger

- reg: fix `--average`, broken since 1.12 (#1003)

- stats: show count of market prices (P directives), and the commodities covered

- tags: add `--values` flag to list tag values.

- tags: now runs much faster when there many tags

#### journal format

- Transactions and postings generated/modified by periodic transaction
  rules and/or transaction modifier rules are now marked with
  `generated-transaction`, `generated-posting`, and `modified` tags,
  for easier troubleshooting and filtering.

#### csv format

- When interpolating CSV values, outer whitespace is now stripped.
  This removes a potential snag in amount field assignments (#1051),
  and hopefully is harmless and acceptable otherwise.

- We no longer add inter-field spaces in CSV error messages,
  which was misleading and not valid RFC-4180 CSV format.

- CSV parse errors are human-readable again (broken since 1.11) (#1038)

- CSV rules now allow the amount to be left unassigned if there is an
  assignment to "balance", which generates a balance assignment. (#1000)

### hledger-ui 1.15

- uses hledger 1.15

### hledger-web 1.15

- `--serve-api` disables the usual server-side web UI (leaving only the API routes)

- register page: account names are hyperlinked

- ?sidebar= now hides the sidebar, same as ?sidebar=0

- fix "_create_locale could not be located" error on windows 7 (#1039)

- uses hledger 1.15

### credits 1.15

Release contributors:
Simon Michael,
Caleb Maclennan,
Jakob Schöttl,
Henning Thielemann,
Dmitry Astapov,
Ben Creasy,
zieone,
Boyd Kelly,
Gabriel Ebner,
Hans-Peter Deifel,
Andreas Pauley.


## 2019/03/01 hledger 1.14

**inclusive balance assertions, commodities command, `--invert` option,
JSON get/add support in hledger-web**
([mail](https://groups.google.com/d/topic/hledger/f4Mir3PLooI/discussion))

### project-wide changes 1.14

- hledger.org website: now uses https, home page updates,
  download page improved package list with status badges.
  Also the github wiki pages are now rendered as part of hledger.org,
  like the main site pages (with pandoc markdown and tables of contents).
  Building the site now requires that a copy of the wiki is checked out
  under wiki/.

- bash completion support: removed duplicate options, added new
  options, stopped listing `-h` as a command, added some completion for
  external addon commands.

- release automation improvements

- makefile cleanups; make site-liverender helps with local site preview

### hledger cli 1.14

- journal: subaccount-including balance assertions have been
  added, with syntax =* and ==* (experimental) (#290)

- new commodities command lists commodity symbols

- new `--invert` option flips sign of amounts in reports

### hledger-ui 1.14

- use hledger 1.14

### hledger-web 1.14

- serve the same JSON-providing routes as in hledger-api:
  ```
  /accountnames
  /transactions
  /prices
  /commodities
  /accounts
  /accounttransactions/ACCT
  ```
  And allow adding a new transaction by PUT'ing JSON (similar to the
  output of /transactions) to /add. This requires the `add` capability
  (which is enabled by default). Here's how to test with curl:
  ```
  $ curl -s http://127.0.0.1:5000/add -X PUT -H 'Content-Type: application/json' --data-binary @in.json; echo
  ```
  (#316)

- fix unbalanced transaction prevention in the add form

- fix transaction-showing tooltips (#927)

- manual updates: document `--capabilities`/`--capabilities-header` and
  editing/uploading/downloading.

- use hledger 1.14

### hledger-api 1.14

- use hledger 1.14

### hledger-lib 1.14

- added:  
  transaction, [v]post*, balassert* constructors, for tests etc.  

- renamed:  
  porigin -> poriginal  

- refactored:  
  transaction balancing & balance assertion checking (#438)

### credits 1.14

Release contributors:
Simon Michael,
Jakob Schöttl,
Jakub Zárybnický.

## 2019/02/01 hledger 1.13

**Unified command CLI help/manuals, bash completions, docker support,
improved budget report, `--transpose`, new account types syntax, 
usability & bug fixes.**
([mail](https://groups.google.com/d/topic/hledger/ffkwwkcHmmU/discussion))

### project-wide changes 1.13

- packaging: A docker image providing the main hledger tools is now
  linked on the download page. This is another way to get up-to-date
  hledger tools without building them yourself (and, a way to run
  hledger-ui on windows ?) (Dmitry Astapov, Simon Michael)

- doc: fixed pandoc typography conversion in web manuals. Eg `--` was
  being rendered as en-dash. ([#954](https://github.com/simonmichael/hledger/issues/954)).

Developers:

- developer docs have moved from the wiki into CONTRIBUTING.md ([#920](https://github.com/simonmichael/hledger/issues/920))

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

### hledger cli 1.13

- cli: reorganised commands list. Addons now have a + prefix.

- cli: the command line help and manual section for all hledger's
  commands are now consistent, and generated from the same source.

- cli: comprehensive bash completion support is now provided (in
  shell-completion/). See how-to in the Cookbook. (Jakob Schöttl)

- balance `--budget`: budget amounts now aggregate hierarchically, like
  account balances. Unbudgeted accounts can be shown with `-E`/`--empty`
  (along with zero-balance accounts), and the `--show-budgeted` flag has
  been dropped.  (Dmitry Astapov)

- balance: new `--transpose` flag switches the rows and columns of
  tabular balance reports (in txt and csv output formats). (Dmitry
  Astapov)

- close: generated balance assertions now have exact amounts with all
  decimal digits, ignoring display precision. Also, balance assertion
  amounts will no longer contain prices.
  ([#941](https://github.com/simonmichael/hledger/issues/941),
  [#824](https://github.com/simonmichael/hledger/issues/824),
  [#958](https://github.com/simonmichael/hledger/issues/958))

- files: now shows up in the commands list

- import: be silent when there's nothing to import

- roi: percentages smaller than 0.01% are displayed as zero (Dmitry
  Astapov)

- stats, ui: correct file order is preserved when using `--auto`
  ([#949](https://github.com/simonmichael/hledger/issues/949))

- journal: account directive: the account name can now be followed by
  a comment on the same line

- journal: account directive: account types for the bs/bse/cf/is
  commands can now be set with a `type:` tag, whose value is `Asset`,
  `Liability`, `Equity`, `Revenue`, `Expense`, `A`, `L`, `E`, `R` or
  `X` (case-insensitive).  The previous syntax (`account assets A`) is
  now deprecated.

- journal: account directive: account sort codes like `account 1000`
  (introduced in 1.9, deprecated in 1.11) are no longer supported.

- journal: transaction modifiers (auto postings) can affect periodic
  transactions (`--auto` can add postings to transactions generated with
  `--forecast`). (Dmitry Astapov)

- journal: balance assertion errors now show exact amounts with all
  decimal digits.  Previously it was possible, in case of a commodity
  directive limiting the display precision, to have a balance
  assertion error with asserted and actual amounts looking the
  same. ([#941](https://github.com/simonmichael/hledger/issues/941))

- journal: fixed a periodic transaction parsing failure
  ([#942](https://github.com/simonmichael/hledger/issues/942)) (Dmitry
  Astapov)

### hledger-ui 1.13

- on posix systems, control-z suspends the program

- control-l now works everywhere and redraws more reliably

- the top status info is clearer

- use hledger 1.13

### hledger-web 1.13

- use hledger 1.13

### hledger-api 1.13

- use hledger 1.13

### hledger-lib 1.13

- in Journal's jtxns field, forecasted txns are appended rather than prepended

- API changes:

  added:
  +setFullPrecision
  +setMinimalPrecision
  +expectParseStateOn
  +embedFileRelative
  +hereFileRelative

  changed:
  - amultiplier -> aismultiplier
  - Amount fields reordered for clearer debug output
  - tpreceding_comment_lines -> tprecedingcomment, reordered
  - Hledger.Data.TransactionModifier.transactionModifierToFunction -> modifyTransactions
  - Hledger.Read.Common.applyTransactionModifiers -> Hledger.Data.Journal.journalModifyTransactions

  - HelpTemplate -> CommandDoc

### credits 1.13

Release contributors:
Simon Michael,
Jakob Schöttl,
Dmitry Astapov.


## 2018/12/02 hledger 1.12

**Account type declarations,
complete balance assertions,
GHC 8.6 support,
hledger-ui usability updates,
misc fixes**
([mail](https://groups.google.com/d/topic/hledger/H7NYdvo0FeQ/discussion))

### hledger cli 1.12

* install script: ensure a new-enough version of stack; more informative output  

* build with GHC 8.6/base-4.12 (Peter Simons)  

* add required upper bound for statistics (Samuel May)  

* `--anon` anonymises more thoroughly (including linked original postings) (Moritz Kiefer)  

* unbalanced transaction errors now include location info (Mykola Orliuk)  

* accounts command: `--drop` also affects the default flat output, without needing an explicit `--flat` flag  

* accounts command: the `--codes` flag has been dropped  

* accounts command: filtering by non-account-name queries now works  

* add command: fix transaction rendering regression during data entry and in journal file  

* balance command: fix wrongful eliding of zero-balance parent accounts in tree mode (Dmitry Astapov)  

* journal format, bs/bse/cf/is commands: account directives can declare account types ([#877](https://github.com/simonmichael/hledger/issues/877))  
  Previously you had to use one of the standard english account names
  (assets, liabilities..) for top-level accounts, if you wanted them to
  appear in the right place in the balancesheet, balancesheetequity,
  cashflow or incomestatement reports.

  Now you can use your preferred account names, and use account directives
  to declare which accounting class (Asset, Liability, Equity, Revenue or
  eXpense) an account (and its subaccounts) belongs to, by writing one of
  the letters A, L, E, R, X after the account name, after two or more
  spaces. This syntax may change (see issue).  Experimental.

  Currently we allow unlimited account type declarations anywhere in the
  account tree. So you could declare a liability account somewhere under
  assets, and maybe a revenue account under that, and another asset account
  even further down. In such cases you start to see oddities like accounts
  appearing in multiple places in a tree-mode report. I have left it this
  way for now in case it helps with, eg, modelling contra accounts, or
  combining multiple files each with their own account type
  declarations. (In that scenario, if we only allowed type declarations on
  top-level accounts, or only allowed a single account of each type,
  complications seem likely.)

* journal format: periodic transaction rules now require a double space separator.  
  In periodic transaction rules which specify a transaction description or
  same-line transaction comment, this must be separated from the period
  expression by two or more spaces, to prevent ambiguous parsing. Eg
  this will parse correctly as "monthly" thanks to the double space:

      ~ monthly  In 2020 we'll end this monthly transaction.

* journal format: exact/complete balance assertions (Samuel May).  
  A stronger kind of balance assertion, written with a double equals sign,
  asserts an account's complete account balance, not just the balance in
  one commodity. (But only if it is a single-commodity balance, for now.)
  Eg:

      1/1
        (a)  A 1
        (a)  B 1
        (a)  0   =  A 1   ; commodity A balance assertion, succeeds
        (a)  0   == A 1   ; complete balance assertion, fails

* journal format: account directives now allow whitespace or a comment after the account name  

* journal format: using ~ for home directory in include directives now works ([#896](https://github.com/simonmichael/hledger/issues/896)) (Mykola Orliuk)  

* journal format: prevent misleading parse error messages with cyclic include directives ([#853](https://github.com/simonmichael/hledger/issues/853)) (Alex Chen)  

* journal format: transaction modifier multipliers handle total-priced amounts correctly ([#928](https://github.com/simonmichael/hledger/issues/928)).  
  Multipliers (*N) in transaction modifier rules did not multiply
  total-priced amounts properly.  Now the total prices are also multiplied,
  keeping the transaction balanced.

* journal format: do amount inference/balance assignments/assertions before transaction modifiers ([#893](https://github.com/simonmichael/hledger/issues/893), [#908](https://github.com/simonmichael/hledger/issues/908)) (Jesse Rosenthal)  
  Previously, transaction modifier (auto postings) rules were applied
  before missing amounts were inferred. This meant amount multipliers could
  generate too many missing-amount postings, making the transaction
  unbalanceable ([#893](https://github.com/simonmichael/hledger/issues/893)).

  Now, missing amount inference (and balance assignments, and balance
  assertions, which are interdependent) are done earlier, before
  transaction modifier rules are applied ([#900](https://github.com/simonmichael/hledger/issues/900), [#903](https://github.com/simonmichael/hledger/issues/903)).

  Also, we now disallow the combination of balance assignments and
  transaction modifier rules which both affect the same account, which
  could otherwise cause confusing balance assertion failures ([#912](https://github.com/simonmichael/hledger/issues/912)).
  (Because assignments now generate amounts to satisfy balance assertions
  before transaction modifier rules are applied ([#908](https://github.com/simonmichael/hledger/issues/908)).)

* journal format: periodic transaction rules are now aware of Y default year directives. ([#892](https://github.com/simonmichael/hledger/issues/892))  
  Ie when a default year Y is in effect, they resolve partial or relative
  dates using Y/1/1 as the reference date, rather than today's date.

### hledger-ui 1.12

* fix "Any" build error with GHC < 8.4  

* error screen: always show error position properly ([#904](https://github.com/simonmichael/hledger/issues/904)) (Mykola Orliuk)  

* accounts screen: show correct balances when there's only periodic transactions  

* drop the `--status-toggles` flag  

* periodic transactions and transaction modifiers are always enabled.  
  Rule-based transactions and postings are always generated
  (`--forecast` and `--auto` are always on).
  Experimental.

* escape key resets to flat mode.  
  Flat mode is the default at startup. Probably it should reset to tree
  mode if `--tree` was used at startup.

* tree mode tweaks: add `--tree`/`-T`/`-F` flags, make flat mode the default,    
  toggle tree mode with T, ensure a visible effect on register screen

* hide future txns by default, add `--future` flag, toggle with F.  
  You may have transactions dated later than today, perhaps piped from
  print `--forecast` or recorded in the journal, which you don't want to
  see except when forecasting.

  By default, we now hide future transactions, showing "today's balance".
  This can be toggled with the F key, which is easier than setting a
  date query. `--present` and `--future` flags have been added to set the
  initial mode.

  (Experimental. Interactions with date queries have not been explored.)

* quick help tweaks; try to show most useful info first  

* reorganise help dialog, fit content into 80x25 again  

* styling tweaks; cyan/blue -> white/yellow  

* less noisy styling in horizontal borders ([#838](https://github.com/simonmichael/hledger/issues/838))  

* register screen: positive amounts: green -> black  
  The green/red scheme helped distinguish the changes column from the
  black/red balance column, but the default green is hard to read on
  the pale background in some terminals. Also the changes column is
  non-bold now.

* use hledger 1.12  

### hledger-web 1.12

* fix duplicate package.yaml keys warned about by hpack  

* use hledger 1.12  

### hledger-api 1.12

* use hledger 1.12  

### hledger-lib 1.12

* switch to megaparsec 7 (Alex Chen)  
  We now track the stack of include files in Journal ourselves, since
  megaparsec dropped this feature.

* add 'ExceptT' layer to our parser monad again (Alex Chen)  
  This was removed under the assumption that it would be possible to
  write our parser without this capability. However, after a hairy
  backtracking bug, we would now prefer to have the option to prevent
  backtracking.

* more support for location-aware parse errors when re-parsing (Alex Chen)  

* make 'includedirectivep' an 'ErroringJournalParser' (Alex Chen)  

* drop Ord instance breaking GHC 8.6 build (Peter Simons)  

* flip the arguments of (divide|multiply)[Mixed]Amount  

* showTransaction: fix a case showing multiple missing amounts  
  showTransaction could sometimes hide the last posting's amount even if
  one of the other posting amounts was already implcit, producing invalid
  transaction output.

* plog, plogAt: add missing newline  

* split up journalFinalise, reorder journal finalisation steps ([#893](https://github.com/simonmichael/hledger/issues/893)) (Jesse Rosenthal)  
  The `journalFinalise` function has been split up, allowing more granular
  control.

* journalSetTime --> journalSetLastReadTime  

* journalSetFilePath has been removed, use journalAddFile instead  

### credits 1.12

Release contributors:
Simon Michael,
Alex Chen,
Jesse Rosenthal,
Samuel May,
Mykola Orliuk,
Peter Simons,
Moritz Kiefer,
Dmitry Astapov,
Felix Yan,
Aiken Cairncross,
Nikhil Jha.


## 2018/9/30 hledger 1.11

**Customisable account display order,
support for other delimiter-separated formats (eg semicolon-separated),
new files and roi commands,
fixes**
([mail](https://groups.google.com/d/topic/hledger/V62txFLaD_U/discussion))

### hledger cli 1.11

* The default display order of accounts is now influenced by
  the order of account directives. Accounts declared by account
  directives are displayed first (top-most), in declaration order,
  followed by undeclared accounts in alphabetical order. Numeric
  account codes are no longer used, and are ignored and considered
  deprecated.

  So if your accounts are displaying in a weird order after upgrading,
  and you want them alphabetical like before, just sort your account
  directives alphabetically.

* Account sorting (by name, by declaration, by amount) is now more
  robust and supported consistently by all commands (accounts,
  balance, bs..) in all modes (tree & flat, tabular & non-tabular).

* close: new `--opening`/`--closing` flags to print only the opening or
  closing transaction

* files: a new command to list included files

* prices: query arguments are now supported. Prices can be filtered by
  date, and postings providing transaction prices can also be filtered.

* rewrite: help clarifies relation to print `--auto` ([#745](https://github.com/simonmichael/hledger/issues/745))

* roi: a new command to compute return on investment, based on hledger-irr

* test: has more verbose output, more informative failure messages,
  and no longer tries to read the journal

* csv: We use a more robust CSV lib (cassava) and now support
  non-comma separators, eg `--separator ';'` (experimental, this flag
  will probably become a CSV rule) ([#829](https://github.com/simonmichael/hledger/issues/829))

* csv: interpolated field names in values are now properly case insensitive, so
  this works:

  fields  ...,Transaction_Date,...
  date %Transaction_Date

* journal: D (default commodity) directives no longer break multiplier
  amounts in transaction modifiers (AKA automated postings) ([#860](https://github.com/simonmichael/hledger/issues/860))

* journal: "Automated Postings" have been renamed to "Transaction Modifiers".

* journal: transaction comments in transaction modifier rules are now parsed correctly. ([#745](https://github.com/simonmichael/hledger/issues/745))

* journal: when include files form a cycle, we give an error instead
  of hanging.

* upper-case day/month names in period expressions no longer give an error ([#847](https://github.com/simonmichael/hledger/issues/847), [#852](https://github.com/simonmichael/hledger/issues/852))


### hledger-ui 1.11

* uses hledger-lib 1.11


### hledger-web 1.11

* uses hledger-lib 1.11


### hledger-api 1.11

* uses hledger-lib 1.11


### hledger-lib 1.11

* compilation now works when locale is unset ([#849](https://github.com/simonmichael/hledger/issues/849))

* all unit tests have been converted from HUnit+test-framework to easytest

* doctests now run quicker by default, by skipping reloading between tests. 
  This can be disabled by passing `--slow` to the doctests test suite
  executable.

* doctests test suite executable now supports `--verbose`, which shows
  progress output as tests are run if doctest 0.16.0+ is installed
  (and hopefully is harmless otherwise).

* doctests now support file pattern arguments, provide more informative output.
  Limiting to just the file(s) you're interested can make doctest start
  much quicker. With one big caveat: you can limit the starting files,
  but it always imports and tests all other local files those import.

* a bunch of custom Show instances have been replaced with defaults,
  for easier troubleshooting.  These were sometimes obscuring
  important details, eg in test failure output. Our new policy is:
  stick with default derived Show instances as far as possible, but
  when necessary adjust them to valid haskell syntax so pretty-show
  can pretty-print them (eg when they contain Day values, cf
  https://github.com/haskell/time/issues/101).  By convention, when
  fields are shown in less than full detail, and/or in double-quoted
  pseudo syntax, we show a double period (..) in the output.

* Amount has a new Show instance.  Amount's show instance hid
  important details by default, and showing more details required
  increasing the debug level, which was inconvenient.  Now it has a
  single show instance which shows more information, is fairly
  compact, and is pretty-printable.

  ghci> usd 1
  OLD:
  Amount {acommodity="$", aquantity=1.00, ..}
  NEW:
  Amount {acommodity = "$", aquantity = 1.00, aprice = NoPrice, astyle = AmountStyle "L False 2 Just '.' Nothing..", amultiplier = False}

  MixedAmount's show instance is unchanged, but showMixedAmountDebug
  is affected by this change:

  ghci> putStrLn $ showMixedAmountDebug $ Mixed [usd 1]
  OLD:
  Mixed [Amount {acommodity="$", aquantity=1.00, aprice=, astyle=AmountStyle {ascommodityside = L, ascommodityspaced = False, asprecision = 2, asdecimalpoint = Just '.', asdigitgroups = Nothing}}]
  NEW:
  Mixed [Amount {acommodity="$", aquantity=1.00, aprice=, astyle=AmountStyle "L False 2 Just '.' Nothing.."}]

* Same-line & next-line comments of transactions, postings, etc.
  are now parsed a bit more precisely (followingcommentp). 
  Previously, parsing no comment gave the same result as an empty
  comment (a single newline); now it gives an empty string.  
  Also, and perhaps as a consequence of the above, when there's no
  same-line comment but there is a next-line comment, we'll insert an
  empty first line, since otherwise next-line comments would get moved
  up to the same line when rendered.

* Hledger.Utils.Test exports HasCallStack

* queryDateSpan, queryDateSpan' now intersect date AND'ed date spans
  instead of unioning them, and docs are clearer.

* pushAccount -> pushDeclaredAccount

* jaccounts -> jdeclaredaccounts

* AutoTransaction.hs -> PeriodicTransaction.hs & TransactionModifier.hs

* Hledger.Utils.Debug helpers have been renamed/cleaned up

### credits 1.11

Release contributors:
Simon Michael,
Joseph Weston,
Dmitry Astapov,
Gaith Hallak,
Jakub Zárybnický,
Luca Molteni,
SpicyCat.



## 2018/6/30 hledger 1.10

**hledger-web edit/upload/download and permissions,
more expressive periodic transactions,
more informative parse errors,
misc fixes**
([mail](https://groups.google.com/forum/#!msg/hledger/SWFV2n6xMQA/Ss78nil8AQAJ))

### project-wide changes 1.10

* build cleanly with all supported GHC versions again (7.10 to 8.4)

* support latest deps

* back in Stackage LTS (12.0)


### hledger-lib 1.10

* extensive refactoring and cleanup of parsers and related types and utilities

* readJournalFile(s) cleanup, these now use InputOpts

* doctests now run a bit faster ([#802](https://github.com/simonmichael/hledger/issues/802))


### hledger cli 1.10

* journal: many parse error messages have become more informative, and
  some now show the source line and error location.

* journal: `;tag:` is no longer parsed as a tag named ";tag" ([#655](https://github.com/simonmichael/hledger/issues/655))

* journal: transaction price amounts having their own price amounts is
  now a parse error

* journal: amounts with space as digit group separator and trailing whitespace 
  now parse correctly ([#780](https://github.com/simonmichael/hledger/issues/780))

* journal: in amounts containing digits and a single space, the space
  is now interpreted as a digit group separator, not a decimal separator ([#749](https://github.com/simonmichael/hledger/issues/749))

* journal: in commodity/format/D directives, the amount must now include a decimal separator.

  When more precise control is needed over number parsing, our
  recommended solution is commodity directives. Commodity directives
  that don't specify the decimal separator leave things ambiguous,
  increasing the chance of misparsing numbers. In some cases it could
  cause amounts with a decimal point to be parsed as if with a digit
  group separator, so 1.234 became 1234.

  It seems the simple and really only way to do this reliably is to require
  an explicit decimal point character. Most folks probably do this already.
  Unfortunately, it makes another potential incompatiblity with ledger and
  beancount journals. But the error message will be clear and easy to
  work around.

* journal: directives currently have diverse and somewhat tricky
  semantics, especially with multiple files.  The manual now describes
  their behaviour precisely.

* journal: `alias` and `apply account` directives now affect `account` directives ([#825](https://github.com/simonmichael/hledger/issues/825))

* journal: periodic transactions can now have all the usual transaction fields
  (status mark, code, description, comment), for generating more expressive
  forecast transactions.

* journal: forecast transactions now have the generating period
  expression attached as a tag named "recur".

* journal: periodic transactions now start on the first instance of the 
  recurring date, rather than the day after the last regular transaction ([#750](https://github.com/simonmichael/hledger/issues/750))

* journal: periodic transaction rules now allow period expressions relative to today's date

* csv: amount-in/amount-out errors are more detailed

* balance: `--drop` is now ignored when not in flat mode, 
  rather than producing a corrupted report ([#754](https://github.com/simonmichael/hledger/issues/754))

* budget: `--drop` now preserves the `<unbudgeted>` top-level account in `--budget` reports

* register: in CSV output, the code field is now included ([#746](https://github.com/simonmichael/hledger/issues/746))

* smart dates now allow  the YYYYMM format, and are better documented

* uses hledger-lib 1.10


### hledger-ui 1.10

* the effect of `--value`, `--forecast`, and `--anon` flags is now preserved on reload ([#753](https://github.com/simonmichael/hledger/issues/753))

* edit-at-transaction-position is now also supported when $EDITOR is neovim

* support/require fsnotify 0.3.0.1+

* uses hledger-lib 1.10


### hledger-web 1.10

* view, add, edit permissions can be set at CLI or by Sandstorm HTTP header

* the edit form has been revived, for whole-journal editing

* the journal can now be uploaded and downloaded

* the e key toggles empty accounts in the sidebar

* multiple `-f` options, and `--auto`, work again

* uses hledger-lib 1.10


### hledger-api 1.10

* uses hledger-lib 1.10


### credits 1.10

Release contributors:
Simon Michael,
Alex Chen,
Everett Hildenbrandt,
Jakub Zárybnický,
Nolan Darilek,
Dmitry Astapov,
Jacob Weisz,
Peter Simons,
Stephen Morgan,
Pavlo Kerestey,
Trevor Riles,
Léo Gaspard,
Mykola Orliuk,
Wad,
Nana Amfo.



## 2018/3/31 hledger 1.9

**Report cleanups,
normal-positive reports,
HTML output,
account sort codes,
budget improvements.**
([mail](https://groups.google.com/forum/#!topic/hledger/DifO6UbeKnU))

Release contributors:
Simon Michael,
Eli Flanagan,
Peter Simons,
Christoph Nicolai,
agander,
M Parker,
Moritz Kiefer,
Mykola Orliuk.
* support ghc 8.4, latest deps


### hledger-lib 1.9

* when the system text encoding is UTF-8, ignore any UTF-8 BOM prefix
found when reading files.

* CompoundBalanceReport amounts are now normally positive. (experimental)

### hledger cli 1.9

* journal: account directives can define a numeric account code to
customize sorting.  bal/bs/cf/is will sort accounts by account code,
if any, then account name.

* journal: support scientific number notation ([#704](https://github.com/simonmichael/hledger/issues/704), [#706](https://github.com/simonmichael/hledger/issues/706))

* csv: reading a CSV file containing no records is no longer an error

* cli: when the system text encoding is UTF-8, ignore any UTF-8 BOM
prefix found when reading files.  (Paypal's new CSV has this BOM
prefix, causing a confusing parse error.)

* cli: tabular reports no longer have a trailing blank line added.
(This allows omitting the ">=0" delimiters in our functional tests,
making them easier to read and maintain.)

* acc: the accounts command now has `--declared` and `--used` flags

* bal: the `--invert` flag flips all signs

* bal: `--drop` now works with CSV output

* bal/bs/bse/cf/is: show overall report span in title

* bal/bs/bse/cf/is: show short month names as headings in monthly reports

* bal/bs/bse/cf/is: these commands can now generate HTML output

* bal/bs/is/cf: drop short name and indent fields from multicolumn CSV

* bs/bse/cf/is: these, the "financial statement" commands, now show
normal income, liability and equity balances as positive numbers.
Negative numbers now indicate a contra-balance (eg an overdrawn
checking account), a net loss, or a negative net worth.  This makes
these reports more like conventional financial statements, and easier
to read and share with others. (Other commands, like balance, have not
changed.)  (experimental)

* bs/cf/is: always show a tabular report, even with no report
interval.  Previously you would get a simple borderless report like
the original balance command.  Less code, fewer bugs.

* bs/bse/cf/is: in CSV output, don't repeat the headings row for each subreport

* budget: warn that CSV output with bal `--budget` is unimplemented

* budget: bal `--budget` shows budget goals even with no or zero actual amounts. 
Makes budget reports more intuitive, at the cost of a temporary hack
which may misorder columns in some cases (if actual and budget
activity occur in a different range of columns).

* budget: `--budget` uses only periodic txns with the selected interval.  
Budgets with different interval, eg a daily and weekly budget, are independent.

* budget: show mostly fixed-width columns for readability

* budget: fix bug where a budget report could include budget goals
ending on the day before the report start date (splitSpan issue)

* close: the equity command has been renamed to close.  It now ignores
any begin date (it always closes historical end balances).  It also
ignores `--date2`.

### hledger-ui 1.9

* `-E`/`--empty` toggles zeroes at startup (with opposite default to cli)

### hledger-web 1.9

* `-E`/`--empty` toggles zeroes at startup (with opposite default to cli)

### hledger-api 1.9



## 2017/12/31 hledger 1.5

([mail](https://groups.google.com/forum/#!topic/hledger/CyNifndzZxk))

Release contributors:
Simon Michael,
Dmitry Astapov,
Mykola Orliuk,
Eli Flanagan,
Elijah Caine,
Sam Jeeves,
Matthias Kauer,
Hans-Peter Deifel,
Mick Dekkers,
Nadrieril,
Alvaro Fernando García.

### project-wide changes 1.5

* remove upper bounds on all but hledger* and base (experimental)
  It's rare that my deps break their api or that newer versions must
  be avoided, and very common that they release new versions which I
  must tediously and promptly test and release hackage revisions for
  or risk falling out of stackage. Trying it this way for a bit.


### hledger-lib 1.5

* `-V`/`--value` uses today's market prices by default, not those of last transaction date. [#683](https://github.com/simonmichael/hledger/issues/683), [#648](https://github.com/simonmichael/hledger/issues/648))

* csv: allow balance assignment (balance assertion only, no amount) in csv records (Nadrieril)

* journal: allow space as digit group separator character, [#330](https://github.com/simonmichael/hledger/issues/330) (Mykola Orliuk)

* journal: balance assertion errors now show line of failed assertion posting, [#481](https://github.com/simonmichael/hledger/issues/481) (Sam Jeeves)

* journal: better errors for directives, [#402](https://github.com/simonmichael/hledger/issues/402) (Mykola Orliuk)

* journal: better errors for included files, [#660](https://github.com/simonmichael/hledger/issues/660) (Mykola Orliuk)

* journal: commodity directives in parent files are inherited by included files, [#487](https://github.com/simonmichael/hledger/issues/487) (Mykola Orliuk)

* journal: commodity directives limits precision even after `-B`, [#509](https://github.com/simonmichael/hledger/issues/509) (Mykola Orliuk)

* journal: decimal point/digit group separator chars are now inferred from an applicable commodity directive or default commodity directive. [#399](https://github.com/simonmichael/hledger/issues/399), [#487](https://github.com/simonmichael/hledger/issues/487) (Mykola Orliuk)

* journal: numbers are parsed more strictly (Mykola Orliuk)

* journal: support Ledger-style automated postings, enabled with `--auto` flag (Dmitry Astapov)

* journal: support Ledger-style periodic transactions, enabled with `--forecast` flag (Dmitry Astapov)

* period expressions: fix "nth day of {week,month}", which could generate wrong intervals (Dmitry Astapov)

* period expressions: month names are now case-insensitive (Dmitry Astapov)

* period expressions: stricter checking for invalid expressions (Mykola Orliuk)

* period expressions: support "every 11th Nov" (Dmitry Astapov)

* period expressions: support "every 2nd Thursday of month" (Dmitry Astapov)

* period expressions: support "every Tuesday", short for `every <n>th day of week` (Dmitry Astapov)

### hledger cli 1.5

* `--auto` adds Ledger-style automated postings to transactions (Dmitry Astapov, Mykola Orliuk)

* `--forecast` generates Ledger-style periodic transactions in the future (Dmitry Astapov, Mykola Orliuk)

* `-V`/`--value` uses today's market prices by default, not those of last transaction date. [#683](https://github.com/simonmichael/hledger/issues/683), [#648](https://github.com/simonmichael/hledger/issues/648)

* add: suggest implied (parent) and declared (by account directives) account names also

* bal: `--budget` shows performance compared to budget goals defined
  with periodic transactions.  Accounts with budget goals are
  displayed folded (depth-clipped) at a depth matching the budget
  specification.  Unbudgeted accounts are hidden, or with
  `--show-unbudgeted`, shown at their usual depth. (Dmitry Astapov)

* import: the output of `--dry-run` is now valid journal format

* print: `-B` shows converted amounts again, as in 1.1, even without
  `-x`. [#551](https://github.com/simonmichael/hledger/issues/551) (Mykola Orliuk, Simon Michael)

* tag: the first argument now filters tag names, additional arguments
  filter transactions ([#261](https://github.com/simonmichael/hledger/issues/261))

### hledger-ui 1.5

* fix help -> view manual (on posix platforms) [#623](https://github.com/simonmichael/hledger/issues/623)

* support `-V`/`--value`, `--forecast`, `--auto`

### hledger-web 1.5

* add form account fields now suggest implied and declared account names also

* add form date field now uses a datepicker (Eli Flanagan)

* don't write a session file at startup, don't require a writable working directory

* support `-V`/`--value`, --forecast, `--auto`

### hledger-api 1.5


## 2017/9/30 hledger 1.4

**easy install script,
simpler help commands,
experimental addon commands now built in,
new balancesheetequity/tags commands,
new import command for easy CSV merging,
print can detect new transactions,
balance reports can sort by amount,
cli conveniences**
([mail](https://groups.google.com/forum/#!topic/hledger/tdtkhchqg9k))

Release contributors:
Simon Michael,
Nicholas Niro,
Hans-Peter Deifel,
Jakub Zárybnický,
Felix Yan,
Mark Hansen,
Christian G. Warden,
Nissar Chababy,
Peter Simons.


* update stack configs for the last three GHC versions, add "make
test-stackage" for finding stackage build problems, switch to GHC
8.2.1 as default for developer builds

* streamline docs page

* improve changelog/release notes process

* improve makefile help and speed

* Added a new installer script for the hledger tools, which aims to
dodge common pitfalls and just work. Based on the stack install
script, this bash script is cross platform, uses cabal or stack,
installs stack and GHC if needed, and installs the latest release of
all major hledger packages. See http://hledger.org/download for details.

### hledger-lib 1.4

* add readJournalFile[s]WithOpts, with simpler arguments and support
for detecting new transactions since the last read.

* query: add payee: and note: query terms, improve description/payee/note docs (Jakub Zárybnický, Simon Michael, [#598](https://github.com/simonmichael/hledger/issues/598), [#608](https://github.com/simonmichael/hledger/issues/608))

* journal, cli: make trailing whitespace significant in regex account aliases
Trailing whitespace in the replacement part of a regular expression
account alias is now significant. Eg, converting a parent account to
just an account name prefix: `--alias '/:acct:/=:acct '`

* timedot: allow a quantity of seconds, minutes, days, weeks, months
  or years to be logged as Ns, Nm, Nd, Nw, Nmo, Ny

* csv: switch the order of generated postings, so account1 is first.
This simplifies things and facilitates future improvements.

* csv: show the "creating/using rules file" message only with `--debug`

* csv: fix multiple includes in one rules file

* csv: add "newest-first" rule for more robust same-day ordering

* deps: allow ansi-terminal 0.7

* deps: add missing parsec lower bound, possibly related to [#596](https://github.com/simonmichael/hledger/issues/596), [fpco/stackage#2835](https://github.com/fpco/stackage/issues/2835)

* deps: drop oldtime flag, require time 1.5+

* deps: remove ghc < 7.6 support, remove obsolete CPP conditionals

* deps: fix test suite with ghc 8.2

<!-- 1.3.1 (2017/8/25) -->

* Fix a bug with `-H` showing nothing for empty periods ([#583](https://github.com/simonmichael/hledger/issues/583), Nicholas Niro)
This patch fixes a bug that happened when using the `-H` option on
a period without any transaction. Previously, the behavior was no
output at all even though it should have shown the previous ending balances
of past transactions. (This is similar to previously using `-H` with `-E`,
but with the extra advantage of not showing empty accounts)

* allow megaparsec 6 ([#594](https://github.com/simonmichael/hledger/issues/594))

* allow megaparsec-6.1 (Hans-Peter Deifel)

* fix test suite with Cabal 2 ([#596](https://github.com/simonmichael/hledger/issues/596))

### hledger cli 1.4

* cli: a @FILE argument reads flags & args from FILE, one per line

* cli: reorganized commands list, added some new command aliases:
  accounts: a
  balance:  b
  print:    p, txns
  register: r

* cli: accept `-NUM` as a shortcut for `--depth=NUM` (eg: -2)

* cli: improve command-line help for `--date2` ([#604](https://github.com/simonmichael/hledger/issues/604))

* cli: make `--help` and `-h` the same, drop `--man` and `--info` for now ([#579](https://github.com/simonmichael/hledger/issues/579))

* help: offers multiple formats, accepts topic substrings.
  The separate info/man commands have been dropped. help now
  chooses an appropriate documentation format as follows: 
  - it uses info if available, 
  - otherwise man if available, 
  - otherwise $PAGER if defined, 
  - otherwise less if available, 
  - otherwise it prints on stdout
  - (and it always prints on stdout when piped). 
  You can override this with the `--info`/`--man`/`--pager`/`--cat` flags.
  ([#579](https://github.com/simonmichael/hledger/issues/579))

* bal/bs/cf/is: `--sort-amount`/`-S` sorts by largest amount instead of
  account name

* bs/cf/is: support `--output-file` and `--output-format=txt|csv`
  The CSV output should be reasonably ok for dragging into a
  spreadsheet and reformatting.

* bal/bs/cf/is: consistent double space between columns, consistent
  single final blank line.  Previously, amounts wider than the column
  headings would be separated by only a single space.

* bs/is: don't let an empty subreport disable the grand totals (fixes [#588](https://github.com/simonmichael/hledger/issues/588))

* cf: exclude asset accounts with ":fixed" in their name (Christian G. Warden, Simon Michael, [#584](https://github.com/simonmichael/hledger/issues/584))

* new balancesheetequity command: like balancesheet but also shows
  equity accounts (Nicholas Niro)

* new import command: adds new transactions seen in one or more input
  files to the main journal file

* print: `--new` shows only transactions added since last time
  (saves state in .latest.JOURNALFILE file)

* new tags command: lists tags in matched transactions

* most addons formerly shipped in bin/ are now builtin commands. These
  include: check-dates, check-dupes, equity, prices, print-unique,
  register-match, rewrite.

* refactor: new Commands module and subdirectory.
  Builtin commands are now gathered more tightly in a single module,
  Hledger.Cli.Commands, facilitating change.  The legacy "convert"
  command has been dropped.

* refactor: BalanceView -> CompoundBalanceCommand

* deps: drop support for directory < 1.2

* deps: allow ansi-terminal 0.7

* deps: drop oldtime flag, require time 1.5+

* deps: simplify shakespeare bounds

* deps: remove ghc < 7.6 support

<!-- 1.3.1 (2017/8/25) -->

* bs/is: don't let an empty subreport disable the grand totals ([#588](https://github.com/simonmichael/hledger/issues/588))

* allow megaparsec 6 ([#594](https://github.com/simonmichael/hledger/issues/594))

* allow megaparsec-6.1 (Hans-Peter Deifel)

* restore upper bounds on hledger packages

### hledger-ui 1.4

* a @FILE argument reads flags & args from FILE, one per line

* enable `--pivot` and `--anon` options, like hledger CLI ([#474](https://github.com/simonmichael/hledger/issues/474)) (Jakub Zárybnický)

* accept `-NUM` as a shortcut for `--depth NUM`

* deps: allow ansi-terminal 0.7

* deps: drop oldtime flag, require time 1.5+

<!-- # 1.3.1 (2017/8/25) -->

* allow megaparsec 6 ([#594](https://github.com/simonmichael/hledger/issues/594), Simon Michael, Hans-Peter Deifel)

* allow megaparsec-6.1 (Hans-Peter Deifel)

* allow vty 5.17 (Felix Yan)

* allow brick 0.24

* restore upper bounds on hledger packages

### hledger-web 1.4

* a @FILE argument reads flags & args from FILE, one per line

* enable `--pivot` and `--anon` options, like hledger CLI ([#474](https://github.com/simonmichael/hledger/issues/474)) (Jakub Zárybnický)

* web: Make "Add transaction" button tabbable ([#430](https://github.com/simonmichael/hledger/issues/430)) (Jakub Zárybnický)

* accept `-NUM` as a shortcut for `--depth NUM`

* deps: drop oldtime flag, require time 1.5+, remove ghc < 7.6 support

<!-- # 1.3.2 (2017/8/25) -->

* remove unnecessary bound to satisfy hackage server

<!-- # 1.3.1 (2017/8/25) -->

* allow megaparsec 6 ([#594](https://github.com/simonmichael/hledger/issues/594), Simon Michael, Hans-Peter Deifel)

* allow megaparsec-6.1 (Hans-Peter Deifel)

* restore upper bounds on hledger packages

### hledger-api 1.4

* api: add support for swagger2 2.1.5+ (fixes [#612](https://github.com/simonmichael/hledger/issues/612))

<!-- # 1.3.1 (2017/8/25) -->

* require servant-server 0.10+ to fix compilation warning

* restore upper bounds on hledger packages


## 2017/6/30 hledger 1.3

**terminology/UI improvements for the status field,
selection/scrolling/movement improvements in hledger-ui,
negative amounts shown in red,
bugfixes.**
([mail](https://groups.google.com/d/msg/hledger/X4iR1wpaq0E/_v5BLQIXAgAJ))

Release contributors:
Simon Michael,
Mykola Orliuk,
Christian G. Warden,
Dmitry Astapov,
Justin Le,
Joe Horsnell,
Nicolas Wavrant,
afarrow,
Carel Fellinger,
flip111,
David Reaver,
Felix Yan,
Nissar Chababy,
Jan Zerebecki.
<!-- #### Packaging -->

<!-- #### Finance -->

<!-- #### Documentation and website -->

<!-- #### Examples -->

#### Tools

make ghci-prof starts GHCI in profiling mode, enabling stack traces with traceStack

make ghci-web now also creates required symlinks

make site-reload opens an auto-reloading browser on the latest site html

make changelog-draft shows the commits since last tag as org nodes

### hledger-lib 1.3

#### journal format

The "uncleared" transaction/posting status (and associated UI flags
and keys) has been renamed to "unmarked" to remove ambiguity and
confusion. See the issue and linked mail list discussion for more
background.  ([#564](https://github.com/simonmichael/hledger/issues/564))

#### csv format

In CSV conversion rules, assigning to the "balance" field name
creates balance assertions ([#537](https://github.com/simonmichael/hledger/issues/537), Dmitry Astapov).

Doubled minus signs are handled more robustly (fixes [#524](https://github.com/simonmichael/hledger/issues/524), Nicolas
Wavrant, Simon Michael)

#### Misc

Multiple status: query terms are now OR'd together. ([#564](https://github.com/simonmichael/hledger/issues/564))

Deps: allow megaparsec 5.3.

### hledger cli 1.3

#### CLI

The "uncleared" transaction/posting status, and associated UI flags
and keys, have been renamed to "unmarked" to remove ambiguity and
confusion.  This means that we have dropped the `--uncleared` flag,
and our `-U` flag now matches only unmarked things and not pending
ones. See the issue and linked mail list discussion for more
background. ([#564](https://github.com/simonmichael/hledger/issues/564))

Also the `-P` short flag has been added for `--pending`, and the `-U`/`-P`/`-C`
flags can be combined. 

bs/is: fix "Ratio has zero denominator" error ([#535](https://github.com/simonmichael/hledger/issues/535))

bs/is/cf: fix `--flat` ([#552](https://github.com/simonmichael/hledger/issues/552)) (Justin Le, Simon Michael)

bal/bs/is/cf: show negative amounts in red (Simon Michael, Justin Le).
These commands now show negative amounts in red, when hledger detects
that ANSI codes are supported, (ie when TERM is not "dumb" and stdout
is not being redirected or piped).

print: show pending mark on postings (fixes [#563](https://github.com/simonmichael/hledger/issues/563)).
A pending mark on postings is now displayed, just like a cleared mark.
Also there will now be a space between the mark and account name.

print: amounts are now better aligned, eg when there are posting
status marks or virtual postings.

#### Addons

prices: add `--inverted-costs` flag, sort output, increase precision
(Mykola Orliuk)

rewrite: add support for rewriting multipler postings into different
commodities. For example, postings in hours can be used to generate
postings in USD. ([#557](https://github.com/simonmichael/hledger/issues/557)) (Christian G. Warden)

`make addons` compiles the experimental add-ons.

### hledger-ui 1.3

The register screen now shows transaction status marks.

The "uncleared" status, and associated UI flags and keys, have been
renamed to "unmarked" to remove ambiguity and confusion.  This means
that we have dropped the `--uncleared` flag, and our `-U` flag now
matches only unmarked things and not pending ones. See the issue and
linked mail list discussion for more background. ([#564](https://github.com/simonmichael/hledger/issues/564))

The P key toggles pending mode, consistent with U (unmarked) and C
(cleared). There is also a temporary `--status-toggles` flag for testing
other toggle styles; see `hledger-ui -h`. ([#564](https://github.com/simonmichael/hledger/issues/564))

There is now less "warping" of selection when lists change:

- When the selected account disappears, eg when toggling zero
  accounts, the selection moves to the alphabetically preceding item,
  instead of the first one.

- When the selected transaction disappears, eg when toggling status
  filters, the selection moves to the nearest transaction by date (and
  if several have the same date, by journal order), instead of the
  last one.

In the accounts and register screens, you can now scroll down further
so that the last item need not always be shown at the bottom of the
screen.  And we now try to show the selected item centered in the
following situations:

-   after moving to the end with Page down/End
-   after toggling filters/display modes (status, real, historical..)
-   on pressing the control-l key (this forces a screen redraw, also)
-   on entering the register screen from the accounts screen
    (except the first time, a known problem).

Items near the top won't be centered because we don't scroll above the
top of the list.

Emacs movement keys are now supported, as well as VI keys.
`CTRL-b/CTRL-f/CTRL-n/CTRL-p` and `hjkl` should work wherever unmodified arrow keys work.

In the transaction screen, amounts are now better aligned, eg when
there are posting status marks or virtual postings.

Deps: allow brick 0.19 ([#575](https://github.com/simonmichael/hledger/issues/575), Felix Yan, Simon Michael)

### hledger-web 1.3

Depends on hledger 1.3.

### hledger-api 1.3

Depends on hledger 1.3.



## 2017/3/31 hledger 1.2

**new commands list,
more powerful balancesheet/incomestatement/cashflow commands,
more parseable print output,
better `--pivot`, 
basic automated postings and periodic transactions support,
more and easier addons,
bugfixes**
<!-- ([mail](http://thread.gmane.org/gmane.comp.finance.ledger.hledger/1267)) -->
<!-- ([mail](https://groups.google.com/d/topic/hledger/WgdTy3-a6sc/discussion))  -->

Release contributors:
Simon Michael,
Mykola Orliuk,
Justin Le,
Peter Simons,
Stefano Rodighiero,
Moritz Kiefer,
Pia Mancini,
Bryan Richter,
Steven R. Baker,
Hans-Peter Deifel,
Joshua Chia,
Joshua Kehn,
Michael Walker.

### project-wide changes 1.2

#### Packaging

bump stack config to latest lts,
bump brick to 0.15.2 to allow hledger-iadd install in hledger dir,
update cabal files to latest hpack 0.17.0/stack 1.4 format ([#512](https://github.com/simonmichael/hledger/issues/512)),
use more accurate license tag in Cabal file (Peter Simons).

#### Finance

set up a hledger open collective (http://opencollective.com/hledger),
more devguide links to issues with bounties,
codefund link,
start tracking and publishing project finances (dogfooding!).

#### Documentation and website

docs page & manual cleanups, 
begin organising a cookbook,
update addons list,
move detailed addon docs out of hledger manual,
document addons installation,
explain print's CSV output,
note an issue with balance assertions & multiple `-f` options,
clarify tags,
add github stars widget to home and devguide,
improve market price docs,
ui & web screenshots layout fixes,
fix extra whitespace after synopsis in hledger-web text manuals,
update accounts directive/budget/rewrite/read-related mockups,
drop old org notes.

#### Examples

consolidate extra/ and data/ in examples/,
tarsnap csv rules & reporting example,
xpensetracker csv rules.

#### Tools

Travis CI now checks functional tests/build warnings/addons,
temporary workaround for Appveyor CI failures,
remove accidentally committed pandoc executables,
some pandoc filter fixes,
mailmap file to clean up git log authors,
bench.hs cleanup,
fix gitignore of generated manuals,
avoid excessive rebuilding with make [func]test,
run functional tests more verbosely,
add alex/happy update step to cabal-install.sh.

### hledger-lib 1.2

#### journal format

A pipe character can optionally be used to delimit payee names in
transaction descriptions, for more accurate querying and pivoting by
payee.  Eg, for a description like `payee name | additional notes`,
the two parts will be accessible as pseudo-fields/tags named `payee`
and `note`.
<!-- (When descriptions do not contain a pipe character, `payee` and `note` are synonyms for `description`.) -->

Some journal parse errors now show the range of lines involved, not just the first.

#### ledger format

The experimental `ledger:` reader based on the WIP ledger4 project has
been disabled, reducing build dependencies.

#### Misc

Fix a bug when tying the knot between postings and their parent transaction, reducing memory usage by about 10% ([#483](https://github.com/simonmichael/hledger/issues/483)) (Mykola Orliuk)

Fix a few spaceleaks ([#413](https://github.com/simonmichael/hledger/issues/413)) (Moritz Kiefer)

Add Ledger.Parse.Text to package.yaml, fixing a potential build failure.

Allow megaparsec 5.2 ([#503](https://github.com/simonmichael/hledger/issues/503))

Rename optserror -> usageError, consolidate with other error functions

### hledger cli 1.2

#### CLI

"hledger" and "hledger -h" now print a better organised commands list
and general usage message respectively ([#297](https://github.com/simonmichael/hledger/issues/297)).

The common reporting flags can now be used anywhere on the command line.

Fixed deduplication of addons in commands list.

Fixed ugly stack traces in command line parse error messages.

The `-V`/`--value` flag is now a global report flag, so it works with
balance, print, register, balancesheet, incomestatement, cashflow,
etc. (Justin Le)

The `--pivot` global reporting option replaces all account names with
the value of some other field or tag. It has been improved, eg:

- we don't add the field/tag name name as a prefix
- when pivoting on a tag, if the tag is missing we show a blank 
  (rather than showing mixed tag values and account names)
- a pipe character delimiter may be used in descriptions to get a more accurate
  and useful payee report (`hledger balance --pivot payee`)

options cleanups

#### Addons

Easier installation:
move add-ons and example scripts to bin/, 
convert to stack scripts,
add a build script to install all deps,
add some functional tests,
test add-ons with Travis CI,
add installation docs to download page.

Improved docs: 
all addons now contain their own documentation. Most of them (all but
hledger-budget) use a new reduced-boilerplate declaration format
and can show short (`-h`) and long (`--help`) command line help.
(Long help is declared with pre and postambles to the generated
options help, short help is that truncated at the start of the hledger
common flags.)

`hledger` now shows a cleaner list of addon commands, showing only the
compiled version of an addon when both source and compiled versions
are in $PATH. (Addons with .exe extension or no extension are
considered compiled.  Modification time is not checked, ie, an old
compiled addon will override a newer source version.  If there are
three or more versions of an addon, all are shown.  )

New addons added/included:

- autosync - example symlink to ledger-autosync
- budget - experimental budget reporting command supporting Ledger-like periodic transactions and automated transactions (Mykola Orliuk)
- chart - pie-chart-generating prototype, a repackaging of the old hledger-chart tool
- check - more powerful balance assertions (Michael Walker)
- check-dupes - find accounts sharing the same leaf name (Stefano Rodighiero)
- prices - show all market price records (Mykola Orliuk)
- register-match - a helper for ledger-autosync's deduplication, finds best match for a transaction description

The equity command now always generates a valid journal transaction,
handles prices better, and adds balance assertions (Mykola Orliuk).

The rewrite command is more robust and powerful (Mykola Orliuk):

- in addition to command-line rewrite options, it understands rewrite rules
  defined in the journal, similar to Ledger's automated transactions ([#99](https://github.com/simonmichael/hledger/issues/99)).
  Eg:
    ```journal
    = ^income
        (liabilities:tax)  *.33

    = expenses:gifts
        budget:gifts  *-1
        assets:budget  *1
    ```

- it can generate diff output, allowing easier review of the proposed
  changes, and safe modification of original journal files (preserving
  file-level comments and directives). Eg:
    ```
    hledger-rewrite --diff Agency --add-posting 'Expenses:Taxes  *0.17' | patch
    ```

- rewrites can affect multiple postings in a transaction, not just one.

- posting-specific dates are handled better

#### balance

A new `--pretty-tables` option uses unicode characters for rendering
table borders in multicolumn reports ([#522](https://github.com/simonmichael/hledger/issues/522)) (Moritz Kiefer)

#### balancesheet/cashflow/incomestatement

These commands are now more powerful, able to show multicolumn reports
and generally having the same features as the balance command. (Justin Le)

balancesheet has always ignored a begin date specified with a `-b` or
`-p` option; now it also ignores a begin date specified with a `date:`
query. (Related discussion at [#531](https://github.com/simonmichael/hledger/issues/531))

#### print

The output of print is now always a valid journal (fixes [#465](https://github.com/simonmichael/hledger/issues/465)) (Mykola Orliuk).

print now tries to preserves the format of implicit/explicit balancing
amounts and prices, by default. To print with all amounts explicit,
use the new `--explicit`/`-x` flag (fixes [#442](https://github.com/simonmichael/hledger/issues/442)). (Mykola Orliuk)
    
Don't lose the commodity of zero amounts/zero balance assertions (fixes [#475](https://github.com/simonmichael/hledger/issues/475)) (Mykola Orliuk)

#### Misc

Fix a regression in the readability of option parsing errors ([#478](https://github.com/simonmichael/hledger/issues/478)) (Hans-Peter Deifel)

Fix an example in Cli/Main.hs (Steven R. Baker)

Allow megaparsec 5.2 ([#503](https://github.com/simonmichael/hledger/issues/503))

### hledger-ui 1.2

Fix a pattern match failure when pressing E on the transaction screen (fixes [#508](https://github.com/simonmichael/hledger/issues/508))

Accounts with ? in name had empty registers (fixes [#498](https://github.com/simonmichael/hledger/issues/498)) (Bryan Richter)

Allow brick 0.16 (Joshua Chia) and brick 0.17/vty 0.15 (Peter Simons)

Allow megaparsec 5.2 (fixes [#503](https://github.com/simonmichael/hledger/issues/503))

Allow text-zipper 0.10

### hledger-web 1.2

Accounts with ? in name had empty registers (fixes [#498](https://github.com/simonmichael/hledger/issues/498)) (Bryan Richter)

Allow megaparsec 5.2 (fixes [#503](https://github.com/simonmichael/hledger/issues/503))

<!-- ### hledger-api 1.2 -->



## 2016/12/31 hledger 1.1

**more robust file format detection,
integration of WIP ledger4 parser,
balance assignments,
`hledger-ui --watch`,
`hledger-iadd` integration,
bugfixes**
<!-- ([mail](http://thread.gmane.org/gmane.comp.finance.ledger.hledger/1267)) -->
<!-- ([mail](https://groups.google.com/d/topic/hledger/WgdTy3-a6sc/discussion))  -->

Release contributors:
Simon Michael, Johannes Gerer, Mykola Orliuk, Shubham Lagwankar.

### project-wide changes 1.1

#### misc

-   don't show stack trace details in errors

-   more predictable [file format detection](/hledger.html#input-files)
    
    When we don't recognise a file's extension, instead of choosing a subset of
    readers to try based on content sniffing, now we just try them all.
    Also, this can be overridden by prepending the reader name and a
    colon to the file path (eg timedot:file.dat, csv:-).

-   avoid creating junk CSV rules files when trying alternate readers.
    We now create it only after successfully reading a file as CSV.

-   improvements to [-B](/journal.html#transaction-prices) and [-V](/hledger.html#market-value) docs: clearer descriptions, more linkage ([#403](http://bugs.hledger.org/403))

### hledger-lib 1.1

#### journal format

-   [balance assignments](/journal.html#balance-assignments) are now supported ([#438](http://bugs.hledger.org/438), [#129](http://bugs.hledger.org/129), [#157](http://bugs.hledger.org/157), [#288](http://bugs.hledger.org/288))

    This feature also brings a slight performance drop (~5%);
    optimisations welcome.

-   also recognise `*.hledger` files as hledger journal format

#### ledger format

-   use ledger-parse from the ledger4 project as an alternate reader for C++ Ledger journals
    
    The idea is that some day we might get better compatibility with Ledger files this way.
    Right now this reader is not very useful and will be used only if you explicitly select it with a `ledger:` prefix.
    It parses transaction dates, descriptions, accounts and amounts, and ignores everything else.
    Amount parsing is delegated to hledger's journal parser, and malformed amounts might be silently ignored.

    This adds at least some of the following as new dependencies for hledger-lib:
    parsers, parsec, attoparsec, trifecta.

#### misc

-   update base lower bound to enforce GHC 7.10+
    
    hledger-lib had a valid install plan with GHC 7.8, but currently requires GHC 7.10 to compile.
    Now we require base 4.8+ everywhere to ensure the right GHC version at the start.
    
-   Hledger.Read api cleanups

-   rename dbgIO to dbg0IO, consistent with dbg0, and document a bug in dbg*IO

-   make readJournalFiles [f] equivalent to readJournalFile f ([#437](http://bugs.hledger.org/437))

-   more general parser types enabling reuse outside of IO ([#439](http://bugs.hledger.org/439))

### hledger cli 1.1

#### balance

-   with `-V`, don't ignore market prices in the future ([#453](http://bugs.hledger.org/453), [#403](http://bugs.hledger.org/403))

-   with `-V` and multiple same-date market prices, use the last parsed not the highest price ([#403](http://bugs.hledger.org/403))

#### misc

-   fix non-existent "oldtime" dependency ([#431](http://bugs.hledger.org/431))

-   [hledger-equity.hs](https://github.com/simonmichael/hledger/blob/master/bin/hledger-equity.hs) now generates valid journal format when there are multiple commodities

### hledger-ui 1.1

-   with [`--watch`](/hledger-ui.html#options), the display updates automatically to show file or date changes

    `hledger-ui --watch` will reload data when the journal file (or any included file) changes.
    Also, when viewing a current standard period (ie this day/week/month/quarter/year),
    the period will move as needed to track the current system date.

-   the [`--change`](/hledger-ui.html#options) flag shows period changes at startup instead of historical ending balances

-   the A key runs the `hledger-iadd` tool, if installed

-   always reload when `g` is pressed

    Previously it would check the modification time and reload only if
    it looked newer than the last reload.

-   mark hledger-ui as "stable"

-   allow brick 0.15, vty 5.14, text-zipper 0.9

### hledger-web 1.1

-   add [`--host`](/hledger-web.html#options) option ([#429](http://bugs.hledger.org/429))
    
    This came up in the context of Docker, but it seems it wasn't
    possible for hledger-web to serve remote clients directly (without
    a proxy) because of 127.0.0.1 being hardcoded. That can now be
    changed with `--host=IPADDR`. Also, the default base url uses this
    address rather than a hard-coded "localhost".
    
-   rename `--server` to `--serve`

    The `--server` flag sounded too close in meaning to `--host` so
    I've renamed it to `--serve`. The old spelling is still accepted,
    but deprecated and will be removed in the next release.

### hledger-api 1.1

-   serves on 127.0.0.1 by default, [`--host`](/hledger-api.html#options) option added ([#432](http://bugs.hledger.org/432))
    
    Consistent with hledger-web: serves only local requests by default,
    use `--host=IPADDR` to change this.

-   fixed the version string in command-line help and swagger info



## 2016/10/26 hledger 1.0

**More hledger-ui features, 
better hledger-web layout,
new hledger-api server, 
new timedot format, 
`--pivot` & `--anon`, 
reorganized multi-format docs,
built-in help.**
<!-- ([mail](http://thread.gmane.org/gmane.comp.finance.ledger.hledger/1267)) -->
([mail](https://groups.google.com/d/topic/hledger/WgdTy3-a6sc/discussion)) 

Release contributors:
Simon Michael, Dominik Süß, Thomas R. Koll, Moritz Kiefer,
jungle-boogie, Sergei Trofimovich, Malte Brandy, Sam Doshi, 
Mitchell Rosen, Hans-Peter Deifel, Brian Scott, and Andrew Jones.


#### misc

-   added GHC 8 support, dropped GHC 7.6 and 7.8 support.

    GHC 7.8 support could be restored with small code changes and a maintainer.

-   a cabal.project file has been added (Moritz Kiefer)

-   use hpack for maintaining cabal files ([#371](http://bugs.hledger.org/371)).

    Instead of editing cabal files directly, we now edit the less
    verbose and less redundant package.yaml files and let stack (or
    hpack) update the cabal files. We commit both the .yaml and
    .cabal files.

-   clean up some old cabal flags

-   tools/simplebench has been spun off as the [quickbench](http://hackage.haskell.org/package/quickbench) package.

-   add Appveyor CI builds, provide more up-to-date Windows binaries

-   extra: add a bunch of CSV rules examples

#### docs

-   the website is simpler, clearer, and more mobile-friendly.

    Docs are now collected on a single page and organised by type: getting started, reference, more.

-   reference docs have been split into one manual for each executable and file format.

    This helps with maintenance and packaging and also should make it
    easier to see what's available and to read just what you need.

-   manuals are now provided in html, plain text, man and info formats

    generated from the same source by a new Shake-based docs build system. ([#292](http://bugs.hledger.org/292))

-   versioned manuals are provided on the website, covering recent releases and the latest dev version ([#385](http://bugs.hledger.org/385), [#387](http://bugs.hledger.org/387))

-   manuals are built in to the hledger executables, allowing easy offline reading on all platforms.

        PROG -h              shows PROG's command-line usage
        PROG --help          shows PROG's manual (fixed width)
        PROG --man           shows PROG's manual with man (formatted/paged)
        PROG --info          shows PROG's manual with info (hypertext)
        hledger help [TOPIC] shows any manual
        hledger man  [TOPIC] shows any manual with man
        hledger info [TOPIC] shows any manual with info

-   the general and reporting options are now listed in all executable manuals.

    We assume any of them which are unsupported are harmlessly ignored.

-   demo.hledger.org is using beancount's example journal.

    This is the somewhat realistic example journal from the beancount
    project, tweaked for hledger.

-   minor copyedits (jungle-boogie)

#### cli

-   parsing multiple input files is now robust.

    When multiple `-f` options are provided, we now parse each file
    individually rather than just concatenating them, so they can
    have different formats ([#320](http://bugs.hledger.org/320)).  Note this also means that
    directives (like `Y` or `alias`) no longer carry over from one
    file to the next.

-   `-I` has been added as the short flag for `--ignore-assertions`

    (this is different from Ledger's CLI, but useful for hledger-ui).

-   parsing an argument-less `--debug` option is more robust

### hledger-lib 1.0

#### timedot format

-   new "timedot" format for retroactive/approximate time logging.

    Timedot is a plain text format for logging dated, categorised
    quantities (eg time), supported by hledger.  It is convenient
    for approximate and retroactive time logging, eg when the
    real-time clock-in/out required with a timeclock file is too
    precise or too interruptive.  It can be formatted like a bar
    chart, making clear at a glance where time was spent.

#### timeclock format

-   renamed "timelog" format to "timeclock", matching the emacs package

-   sessions can no longer span file boundaries (unclocked-out

    sessions will be auto-closed at the end of the file).

-   transaction ids now count up rather than down ([#394](http://bugs.hledger.org/394))

-   timeclock files no longer support default year directives

-   removed old code for appending timeclock transactions to journal transactions.

    A holdover from the days when both were allowed in one file.

#### csv format

-   fix empty field assignment parsing, rule parse errors after megaparsec port ([#407](http://bugs.hledger.org/407)) (Hans-Peter Deifel)

#### journal format

-   journal files can now include timeclock or timedot files ([#320](http://bugs.hledger.org/320))

    (but not yet CSV files).

-   fixed an issue with ordering of same-date transactions included from other files

-   the "commodity" directive and "format" subdirective are now supported, allowing

    full control of commodity style ([#295](http://bugs.hledger.org/295)) The commodity directive's
    format subdirective can now be used to override the inferred
    style for a commodity, eg to increase or decrease the
    precision. This is at least a good workaround for [#295](http://bugs.hledger.org/295).

-   Ledger-style "apply account"/"end apply account" directives are now used to set a default parent account.

-   the Ledger-style "account" directive is now accepted (and ignored).

-   bracketed posting dates are more robust ([#304](http://bugs.hledger.org/304))

    Bracketed posting dates were fragile; they worked only if you
    wrote full 10-character dates. Also some semantics were a bit
    unclear. Now they should be robust, and have been documented
    more clearly. This is a legacy undocumented Ledger syntax, but
    it improves compatibility and might be preferable to the more
    verbose "date:" tags if you write posting dates often (as I do).
    Internally, bracketed posting dates are no longer considered to
    be tags.  Journal comment, tag, and posting date parsers have
    been reworked, all with doctests.

-   balance assertion failure messages are clearer

-   with `--debug=2`, more detail about balance assertions is shown.

#### misc

-   file parsers have been ported from Parsec to Megaparsec \o/ ([#289](http://bugs.hledger.org/289), [#366](http://bugs.hledger.org/366)) (Alexey Shmalko, Moritz Kiefer)

-   most hledger types have been converted from String to Text, reducing memory usage by 30%+ on large files

-   file parsers have been simplified for easier troubleshooting ([#275](http://bugs.hledger.org/275)).

    The journal/timeclock/timedot parsers, instead of constructing
    opaque journal update functions which are later applied to build
    the journal, now construct the journal directly by modifying the
    parser state. This is easier to understand and debug. It also
    rules out the possibility of journal updates being a space
    leak. (They weren't, in fact this change increased memory usage
    slightly, but that has been addressed in other ways).  The
    ParsedJournal type alias has been added to distinguish
    "being-parsed" journals and "finalised" journals.

-   file format detection is more robust.

    The Journal, Timelog and Timedot readers' detectors now check
    each line in the sample data, not just the first one. I think the
    sample data is only about 30 chars right now, but even so this
    fixed a format detection issue I was seeing. 
    Also, we now always try parsing stdin as journal format (not just sometimes).

-   all file formats now produce transaction ids, not just journal ([#394](http://bugs.hledger.org/394))

-   git clone of the hledger repo on windows now works ([#345](http://bugs.hledger.org/345))

-   added missing benchmark file ([#342](http://bugs.hledger.org/342))

-   our stack.yaml files are more compatible across stack versions ([#300](http://bugs.hledger.org/300))

-   use [newer file-embed](https://github.com/snoyberg/file-embed/issues/18) to fix ghci working directory dependence

-   report more accurate dates in account transaction report when postings have their own dates

    (affects hledger-ui and hledger-web registers).
    The newly-named "transaction register date" is the date to be
    displayed for that transaction in a transaction register, for
    some current account and filter query.  It is either the
    transaction date from the journal ("transaction general date"),
    or if postings to the current account and matched by the
    register's filter query have their own dates, the earliest of
    those posting dates.

-   simplify account transactions report's running total.

    The account transactions report used for hledger-ui and -web
    registers now gives either the "period total" or "historical
    total", depending strictly on the `--historical` flag. It doesn't
    try to indicate whether the historical total is the accurate
    historical balance (which depends on the user's report query).

-   reloading a file now preserves the effect of options, query arguments etc.

-   reloading a journal should now reload all included files as well.

-   the Hledger.Read.\* modules have been reorganised for better reuse.

    Hledger.Read.Utils has been renamed Hledger.Read.Common
    and holds low-level parsers & utilities; high-level read
    utilities are now in Hledger.Read.

-   clarify amount display style canonicalisation code and terminology a bit.

    Individual amounts still have styles; from these we derive
    the standard "commodity styles". In user docs, we might call
    these "commodity formats" since they can be controlled by the
    "format" subdirective in journal files.

-   Journal is now a monoid

-   expandPath now throws a proper IO error

-   more unit tests, start using doctest

### hledger cli 1.0

#### add

-   suggest only one commodity at a time as default amount ([#383](http://bugs.hledger.org/383))

    (since we currently can't input more than one at a time)

#### balance

-   added `--change` flag for consistency

-   `-H`/`--historical` now also affects single-column balance reports with a start date ([#392](http://bugs.hledger.org/392)).

    This has the same effect as just omitting the start date, but adds consistency.

-   in CSV output, render amounts in one-line format ([#336](http://bugs.hledger.org/336))

#### balancesheet

-   fix an infinite loop ([#393](http://bugs.hledger.org/393))

#### print

-   in CSV output, fix and rename the transaction id field

#### register

-   fix a sorting regression with `--date2` ([#326](http://bugs.hledger.org/326))

-   `--average`/`-A` is now affected by `--historical`/`-H`

-   added `--cumulative` flag for consistency

-   in CSV output, include the transaction id and rename the total field ([#391](http://bugs.hledger.org/391))

#### stats

-   fixed an issue with ordering of include files

#### misc

-   `--pivot` option added, groups postings by tag instead of account ([#323](http://bugs.hledger.org/323)) (Malte Brandy)

-   `--anon` option added, obfuscates account names and descriptions ([#265](http://bugs.hledger.org/265)) (Brian Scott)

    (Only affects the hledger tool, for now.)

-   try to clarify balance/register's various report modes,

    kinds of "balance" displayed, and related options and language.

-   with multiple `--change`/`--cumulative`/`--historical` flags, use the last one instead of complaining

-   don't add the "d" suffix when displaying day periods

-   stack-ify extra/hledger-rewrite.hs

### hledger-ui 1.0

#### accounts screen

-   at depth 0, show accounts on one "All" line and show all transactions in the register

-   0 now sets depth limit to 0 instead of clearing it

-   always use `--no-elide` for a more regular accounts tree

#### register screen

-   registers can now include/exclude subaccount transactions.

    The register screen now includes subaccounts' transactions if the
    accounts screen was in tree mode, or when showing an account
    which was at the depth limit. Ie, it always shows the
    transactions contributing to the balance displayed on the
    accounts screen. As on the accounts screen, F toggles between
    tree mode/subaccount txns included by default and flat
    mode/subaccount txns excluded by default. (At least, it does when
    it would make a difference.)

-   register transactions are filtered by realness and status ([#354](http://bugs.hledger.org/354)).

    Two fixes for the account transactions report when `--real`/`--cleared`/`real:`/`status:` 
    are in effect, affecting hledger-ui and hledger-web:
    
    1.  exclude transactions which affect the current account via an excluded posting type.
        Eg when `--real` is in effect, a transaction posting to the current account with only
        virtual postings will not appear in the report.
    
    2.  when showing historical balances, don't count excluded posting types in the
        starting balance. Eg with `--real`, the starting balance will be the sum of only the
        non-virtual prior postings.
        
        This is complicated and there might be some ways to confuse it still, causing
        wrongly included/excluded transactions or wrong historical balances/running totals
        (transactions with both real and virtual postings to the current account, perhaps ?)

-   show more accurate dates when postings have their own dates.

    If postings to the register account matched by the register's
    filter query have their own dates, we show the earliest of these
    as the transaction date.

#### misc

-   H toggles between showing "historical" or "period" balances ([#392](http://bugs.hledger.org/392)).

    By default hledger-ui now shows historical balances, which
    include transactions before the report start date (like hledger
    balance `--historical`). Use the H key to toggle to "period" mode,
    where balances start from 0 on the report start date.

-   shift arrow keys allow quick period browsing

    -   shift-down narrows to the next smaller standard period
        (year/quarter/month/week/day), shift-up does the reverse
    -   when narrowed to a standard period, shift-right/left moves to
        the next/previous period
    -   \`t\` sets the period to today.

-   a runs the add command

-   E runs $HLEDGER<sub>UI</sub><sub>EDITOR</sub> or $EDITOR or a default editor (vi) on the journal file.

    When using emacs or vi, if a transaction is selected the cursor will be positioned at its journal entry.

-   / key sets the filter query; BACKSPACE/DELETE clears it

-   Z toggles display of zero items (like `--empty`), and they are shown by default.

    `-E`/`--empty` is now the default for hledger-ui, so accounts with 0 balance
    and transactions posting 0 change are shown by default.  The Z key
    toggles this, entering "nonzero" mode which hides zero items.

-   R toggles inclusion of only real (non-virtual) postings

-   U toggles inclusion of only uncleared transactions/postings

-   I toggles balance assertions checking, useful for troubleshooting

-   vi-style movement keys are now supported (for help, you must now use ? not h) ([#357](http://bugs.hledger.org/357))

-   ESC cancels minibuffer/help or clears the filter query and jumps to top screen

-   ENTER has been reserved for later use

-   reloading now preserves any options and modes in effect

-   reloading on the error screen now updates the message rather than entering a new error screen

-   the help dialog is more detailed, includes the hledger-ui manual, and uses the full terminal width if needed

-   the header/footer content is more efficient; historical/period and tree/flat modes are now indicated in the footer

-   date: query args on the command line now affect the report period.

    A `date2: arg` or `--date2` flag might also affect it (untested).

-   hledger-ui now uses the quicker-building microlens

### hledger-web 1.0

#### ui

-   use full width on large screens, hide sidebar on small screens, more standard bootstrap styling ([#418](http://bugs.hledger.org/418), [#422](http://bugs.hledger.org/422)) (Dominik Süß)

-   show the sidebar by default ([#310](http://bugs.hledger.org/310))

-   fix the add link's tooltip

-   when the add form opens, focus the first field ([#338](http://bugs.hledger.org/338))

-   leave the add form's date field blank, avoiding a problem with tab clearing it ([#322](http://bugs.hledger.org/322))

-   use transaction id instead of date in transaction urls ([#308](http://bugs.hledger.org/308)) (Thomas R. Koll)

-   after following a link to a transaction, highlight it (Thomas R. Koll)

-   misc. HTML/CSS/file cleanups/fixes (Thomas R. Koll)

#### misc

-   startup is more robust ([#226](http://bugs.hledger.org/226)).

    Now we exit if something is already using the specified port,
    and we don't open a browser page before the app is ready.

-   termination is more robust, avoiding stray background threads.

    We terminate the server thread more carefully on exit, eg on control-C in GHCI.

-   more robust register dates and filtering in some situations (see hledger-ui notes)

-   reloading the journal preserves options, arguments in effect ([#314](http://bugs.hledger.org/314)).

    The initial query specified by command line arguments is now preserved
    when the journal is reloaded. This does not appear in the web UI, it's
    like an invisible extra filter.

-   show a proper not found page on 404

-   document the special \`inacct:\` query ([#390](http://bugs.hledger.org/390))

### hledger-api 1.0

#### misc

-   new hledger-api tool: a simple web API server with example clients ([#316](http://bugs.hledger.org/316))

-   start an Angular-based API example client ([#316](http://bugs.hledger.org/316)) (Thomas R. Koll)



## 2008-2015 Pre-1.0

### 2015/10/30 hledger 0.27

**New curses-style interface, market value reporting, wide characters, fast regex aliases, man pages**
([mail](http://thread.gmane.org/gmane.comp.finance.ledger.hledger/1267))
<!-- [mail](https://groups.google.com/forum/#!topic/hledger/3w7G0H9e7aE) -->

Release contributors:
Simon Michael,
Carlos Lopez-Camey.

**hledger 0.27:**

Account aliases:

- Regular expression account aliases are now fast enough that you can
  use lots of them without slowing things down. They now take
  O(aliases x accounts) time, instead of O(aliases x transactions);
  also, regular expressions are no longer recompiled unnecessarily.

Documentation:

- The hledger packages now have man pages, based on the current user
  manual, thanks to the mighty pandoc ([#282](http://bugs.hledger.org/282)).
 
Journal format:

- Dates must now begin with a digit (not /, eg).

- The comment directive longer requires an end comment, and will
  extend to the end of the file(s) without it.

Command-line interface:

- Output (balance reports, register reports, print output etc.)
  containing wide characters, eg chinese/japanese/korean characters,
  should now align correctly, when viewed in apps and fonts that show
  wide characters as double width ([#242](http://bugs.hledger.org/242)).
 
- The argument for `--depth` or `depth:` must now be positive.

add:

- Journal entries are now saved with all amounts explicit, to avoid
  losing price info ([#283](http://bugs.hledger.org/283)).

- Fixed a bug which sometimes (when the same letter pair was repeated)
  caused it not to pick the most similar past transaction for defaults.
    
balance:

- There is now a `-V`/`--value` flag to report current market value (as in Ledger).
  It converts all reported amounts using their "default market price".
  "Market price" is the new name for "historical prices", defined with the P directive.
  The default market price for a commodity is the most recent one found in the journal on or before the report end date.
    
    Unlike Ledger, hledger's `-V` uses only the market prices recorded
  with P directives; it does not use the transaction prices
  recorded as part of posting amounts.
  Using both `-B` and `-V` at the same time is possible.

- Fixed a bug in amount normalization which caused amount styles
  (commodity symbol placement, decimal point character, etc.) to be
  lost in certain cases ([#230](http://bugs.hledger.org/230), [#276](http://bugs.hledger.org/276)).

- The balance command's `--format` option can now adjust the rendering
  style of multi-commodity amounts, if you begin the format string
  with one of:
    
     %_  - renders amounts on multiple lines, bottom-aligned (the default)
     %^  - renders amounts on multiple lines, top-aligned
     %,  - renders amounts on one line, comma-separated
    
- The balance report's final total (and the line above it) now adapt
  themselves to a custom `--format`.

print:

- The `--match` option prints the journal entry that best matches a
  description (ie whose description field is most similar to the value
  given, and if there are several equally similar, the most recent).
  This was originally an add-on I used to guess account names for
  ledger-autosync. It's nice for quickly looking up a recent
  transaction from a guessed or partial description.

- print now always right-aligns the amounts in an entry, even when
  they are wider than 12 characters.  (If there is a price, it's
  considered part of the amount for right-alignment.)

register:

- Amount columns now resize automatically, using more space if it's
  needed and available.

**hledger-ui 0.27:**

- [hledger-ui](ui.md) is a new curses-style UI, intended to be a standard part
  of the hledger toolset for all users (except on native MS Windows,
  where the vty lib is not [yet](https://github.com/coreyoconnor/vty/pull/1) supported).

    The UI is quite simple, allowing just browsing of accounts and
  transactions, but it has a number of improvements over the old
  hledger-vty, which it replaces:

    - adapts to screen size
    - handles wide characters
    - shows multi-commodity amounts on one line
    - manages cursor and scroll position better
    - allows depth adjustment
    - allows `--flat` toggle
    - allows `--cleared` toggle
    - allows journal reloading
    - shows a more useful transaction register, like hledger-web
    - offers multiple color themes
    - includes some built-in help

    hledger-ui is built with brick, a new higher-level UI library based
  on vty, making it relatively easy to grow and maintain.

**hledger-web 0.27:**

- Fix keyboard shortcut for adding a transaction (Carlos Lopez-Camey)

- Clear the form when clicking 'Add a transaction' (just like the shortcut) (Carlos Lopez-Camey)

- Disallow -f- (reading from standard input) which currently doesn't work ([#202](http://bugs.hledger.org/202))

- Fix broken links when using `--base-url` ([#235](http://bugs.hledger.org/235))

- Fix the `--file-url` option ([#285](http://bugs.hledger.org/285))

- Show fewer "other accounts" in the account register: to reduce
  clutter in the "other accounts" field, if there are both real and
  virtual postings to other accounts, show only the accounts posted to
  by real postings.


### 2015/7/12 hledger 0.26

**Website & doc updates, account aliases, misc. bugfixes & cleanups, performance.**
<!-- [mail](http://thread.gmane.org/gmane.comp.finance.ledger.hledger/N) -->
<!-- [mail](https://groups.google.com/forum/#!topic/hledger/k2Y_NYZGGJw) -->

Release contributors:
Simon Michael,
Imuli,
Carlos Lopez-Camey,
Kyle Marek-Spartz,
Rick Lupton,
Simon Hengel.

**Changes to hledger.org & docs:**

- examples everywhere, screenshots, content & style updates
- manual: reorganise topics, add some undocumented things, clarify some things
- dev guide: more links, put how-tos first, copy diagram from old wiki, update the setup docs


**User-visible changes in hledger since 0.25.1:**

Account aliases:

- Account aliases are once again non-regular-expression-based, by default. (#252)
    
    The regex account aliases added in 0.24 tend to trip up people
    switching between hledger and Ledger. (Also they are currently
    slow).  We now use the old non-regular-expression aliases again,
    by default; these are unsurprising, useful, and pretty close in
    functionality to Ledger's aliases.

    The new regex aliases are still available, but they must now be
    enclosed in forward slashes. (Ledger effectively ignores these.)
    
Journal format:

- We now parse, and also print, journal entries with no postings, as
  proposed on the mail lists.  These are not well-formed General
  Journal entries/transactions, but on the other hand:
    Ledger and beancount parse them;
    if they are parsed, they should be printed;
    they provide a convenient way to record (and report) non-transaction events;
    and they permit more gradual introduction and learning of the concepts
    (so eg a beginner can keep a simple journal before learning about accounts and postings).

- Trailing whitespace after a `comment` directive is now ignored.

Command-line interface:

- The `-f`/file option may now be used multiple times. 
  This is equivalent to concatenating the input files before running hledger.
  The add command adds entries to the first file specified.

Queries:

- real: (no argument) is now a synonym for real:1

- tag: now matches tag names with a regular expression, like most other queries

- empty: is no longer supported, as it overlaps a bit confusingly with
  amt:0. The `--empty` flag is still available.

- You can now match on pending status (#250)
    
    A transaction/posting status of ! (pending) was effectively equivalent
    to * (cleared). Now it's a separate state, not matched by `--cleared`.
    The new Ledger-compatible `--pending` flag matches it, and so does
    `--uncleared`.

    The relevant search query terms are now status:*, status:! and
    status: (the old status:1 and status:0 spellings are deprecated).
    
    Since we interpret `--uncleared` and status: as "any state except cleared",
    it's not currently possible to match things which are neither cleared
    nor pending.

activity:

- activity no longer excludes 0-amount postings by default.

add:

- Don't show quotes around the journal file path in the "Creating..."
  message, for consistency with the subsequent "Adding..." message.

balancesheet:

- Accounts beginning with "debt" or now also recognised as liabilities.

print:

- We now limit the display precision of inferred prices. (#262)
    
    When a transaction posts to two commodities without specifying the
    conversion price, we generate a price which makes it balance (cf
    <http://hledger.org/journal.html#transaction-prices). The print command showed
    this with full precision (so that manual calculations with the
    displayed numbers would look right), but this sometimes meant we
    showed 255 digits (when there are multiple postings in the
    commodity being priced, and the averaged unit price is an
    irrational number). In this case we now set the price's display
    precision to the sum of the (max) display precisions of the
    commodities involved. An example:
    ```
    hledger -f- print
    <<<
    1/1
        c    C 10.00
        c    C 11.00
        d  D -320.00
    >>>
    2015/01/01
        c  C 10.00 @ D 15.2381
        c  C 11.00 @ D 15.2381
        d     D -320.00
    
    >>>=0
    ```
    There might still be cases where this will show more price decimal
    places than necessary. 

- We now show inferred unit prices with at least 2 decimal places.
    
    When inferring prices, if the commodities involved have low
    display precisions, we don't do a good job of rendering
    accurate-looking unit prices. Eg if the journal doesn't use any
    decimal places, any inferred unit prices are also displayed with
    no decimal places, which makes them look wrong to the user.  Now,
    we always give inferred unit prices a minimum display precision of
    2, which helps a bit.

register:

- Postings with no amounts could give a runtime error in some obscure case, now fixed.

stats: 

- stats now supports `-o`/`--outputfile`, like register/balance/print.
- An O(n^2) performance slowdown has been fixed, it's now much faster on large journals.
    ```
    +--------------------------------------++--------+--------+
    |                                      ||   0.25 |   0.26 |
    +======================================++========+========+
    | -f data/100x100x10.journal     stats ||   0.10 |   0.16 |
    | -f data/1000x1000x10.journal   stats ||   0.45 |   0.21 |
    | -f data/10000x1000x10.journal  stats ||  58.92 |   2.16 |
    +--------------------------------------++--------+--------+
    ```

Miscellaneous:

- The June 30 day span was not being rendered correctly; fixed. (#272)
- The deprecated shakespeare-text dependency has been removed more thoroughly.
- The bench script invoked by "cabal bench" or "stack bench" now runs
  some simple benchmarks.
  You can get more accurate benchmark times by running with `--criterion`.
  This will usually give much the same numbers and takes much longer.
  Or with `--simplebench`, it benchmarks whatever commands are
  configured in bench/default.bench. This mode uses the first
  "hledger" executable in $PATH.

**User-visible changes in hledger-web since 0.25.1:**

- make the j keybinding respect `--base-url` (fixes #271)
- respect command line options (fixes #225)
- include the unminified jquery source again (#161)
- fix build breakage from #165 (fixes #268)
- fix a js error breaking add form in browsers other than firefox (fixes #251)
- drop deprecated network-conduit dependency

##### 2015/4/29 hledger-web 0.25.1

- support/require base-compat >0.8 (#245)

##### 2015/4/29 hledger 0.25.1

- timelog: support the description field (#247)

##### 2015/4/29 hledger-lib 0.25.1

- support/require base-compat >0.8 (#245)

### 2015/4/7 hledger 0.25

**GHC 7.10 compatibility, terminal width awareness, useful averages and totals columns, and a more robust hledger-web add form.**
<!-- [mail](http://thread.gmane.org/gmane.comp.finance.ledger.hledger/N) -->
[mail](https://groups.google.com/forum/#!topic/hledger/k2Y_NYZGGJw)

Release contributors:
Simon Michael,
Julien Moutinho.

**User-visible changes in hledger since 0.24.1:**

- GHC 7.10 compatibility ([#239](http://bugs.hledger.org/239))

- On POSIX systems, the register command now uses the full terminal width by
    default. Specifically, the output width is set from:
    
    1. a `--width` option
    2. or a COLUMNS environment variable (NB: not the same as a bash shell var)
    3. or on POSIX (non-windows) systems, the current terminal width
    4. or the default, 80 characters.
    
    This feature requires the C curses dev libraries, making installation slightly harder.
    If that's a problem you can disable curses support with a cabal flag:
    `cabal install -f-curses ...`.

- register's `--width` option now accepts an optional
    description column width following the overall width (`--width
    WIDTH[,DESCWIDTH]`). This also sets the account column width, since
    the available space (WIDTH-41) is divided up between these two
    columns. Here's a diagram:
<br clear="all">
```    
    <--------------------------------- width (W) ---------------------------------->
    date (10)  description (D)       account (W-41-D)     amount (12)   balance (12)
    DDDDDDDDDD dddddddddddddddddddd  aaaaaaaaaaaaaaaaaaa  AAAAAAAAAAAA  AAAAAAAAAAAA
```    
    Examples:
```
    $ hledger reg                 # use terminal width on posix
    $ hledger reg -w 100          # width 100, equal description/account widths
    $ hledger reg -w 100,40       # width 100, wider description
    $ hledger reg -w $COLUMNS,100 # terminal width and set description width
```

- balance: new `-T`/`--row-total` and `-A`/`--average` options

    In multicolumn balance reports, `-T`/`--row-total` now shows a totals
    column and `-A`/`--average` shows an averages column.
    This helps eg to see monthly average expenses (hledger bal ^expenses -MA).

    NB our use of `-T` deviates from Ledger's UI, where `-T` sets a custom
    final total expression.

- balance: `-N` is now short for `--no-total`
- balance: fix partially-visible totals row with `--no-total`
    
    A periodic (not using `--cumulative` or `--historical`) balance report
    with `--no-total` now hides the totals row properly.

- journal, csv: comment lines can also start with *
    
    As in Ledger. This means you can embed emacs org/outline-mode nodes in
    your journal file and manipulate it like an outline.

**User-visible changes in hledger-web since 0.24.1:**

- GHC 7.10 compatibility ([#239](http://bugs.hledger.org/239))

- fix the add form when there are included files ([#234](http://bugs.hledger.org/234))

    NB to make this work, the add form now shows the full file path of
    the main and included journal files.

- improve add form validation ([#223](http://bugs.hledger.org/223), [#234](http://bugs.hledger.org/234))
    
    All add form errors are displayed as form errors, not internal
    server errors, and when there are errors the add form is redisplayed
    (form inputs are not preserved, currently).

- keep the add button right-aligned when pressing ctrl - on the add form

##### 2015/3/15 hledger 0.24.1

- timelog: show hours with 2 decimal places, not 1 ([#237](http://bugs.hledger.org/237))
- fix balance accumulation through assertions in several commodities ([#195](http://bugs.hledger.org/195))
- fix rendering of week 52 heading in weekly reports
- allow utf8-string-1 ([fpco/stackage/#426](https://github.com/fpco/stackage/issues/426))

##### 2015/3/15 hledger-lib 0.24.1

- fix JournalReader "ctx" compilation warning
- add some type signatures in Utils to help make ghci-web

##### 2015/1/10 hledger-web 0.24.1

- add missing modules to fix cabal tests ([#232](http://bugs.hledger.org/232))


### 2014/12/25 hledger 0.24

Release contributors:
Simon Michael,
Julien Moutinho,
Ryan Desfosses,
Gergely Risko,
Gwern Branwen.

**CSV export,
a non-floating point number representation,
more powerful account aliases,
speedups,
and
a streamlined web UI.**
<!-- [mail](http://thread.gmane.org/gmane.comp.finance.ledger.hledger/N) -->

**User-visible changes in hledger since 0.23.3:**

General:

- fix redundant compilation when cabal installing the hledger packages
- switch to Decimal for representing amounts ([#118](http://bugs.hledger.org/118))
- report interval headings (eg in balance, register reports) are shown
  compactly when possible
- general speedups.
```
+--------------------------------------------++----------------+--------------+--------+
|                                            || hledger-0.23.3 | hledger-0.24 | ledger |
+============================================++================+==============+========+
| -f data/100x100x10.journal     balance     ||           0.05 |         0.03 |   0.01 |
| -f data/1000x1000x10.journal   balance     ||           0.34 |         0.21 |   0.04 |
| -f data/10000x1000x10.journal  balance     ||           2.72 |         1.48 |   0.19 |
| -f data/10000x1000x10.journal  balance aa  ||           3.16 |         1.55 |   0.14 |
| -f data/100x100x10.journal     register    ||           0.09 |         0.05 |   0.04 |
| -f data/1000x1000x10.journal   register    ||           0.66 |         0.32 |   0.30 |
| -f data/10000x1000x10.journal  register    ||           6.27 |         2.77 |   2.80 |
| -f data/10000x1000x10.journal  register aa ||           3.30 |         1.62 |   0.21 |
| -f data/100x100x10.journal     print       ||           0.06 |         0.05 |   0.01 |
| -f data/1000x1000x10.journal   print       ||           0.42 |         0.25 |   0.04 |
| -f data/10000x1000x10.journal  print       ||           3.95 |         2.57 |   0.38 |
| -f data/10000x1000x10.journal  print aa    ||           3.23 |         1.56 |   0.14 |
| -f data/100x100x10.journal     stat        ||           0.04 |         0.03 |   0.01 |
| -f data/1000x1000x10.journal   stat        ||           0.35 |         0.24 |   0.03 |
| -f data/10000x1000x10.journal  stat        ||          14.84 |        13.29 |   0.20 |
| -f data/10000x1000x10.journal  stat aa     ||          12.08 |        10.16 |   0.17 |
+--------------------------------------------++----------------+--------------+--------+
```

Journal format:

- detect decimal point and digit groups more robustly ([#196](http://bugs.hledger.org/196))
- check that transaction dates are followed by whitespace or newline
- check that dates use a consistent separator character
- balance assertions now are specific to a single commodity, like
  Ledger ([#195](http://bugs.hledger.org/195))
- support multi-line comments using "comment", "end comment"
  directives, like Ledger

CSV format:

- fix: reading CSV data from stdin now works better
- the original order of same-day transactions is now usually preserved
  (if the records appear to be in reverse date order, we reverse them
  before finally sorting by transaction date)
- the rules file include directive is now relative to the current
  file's directory ([#198](http://bugs.hledger.org/198))
- CSV output is now built in to the balance, print, and register
  commands, controlled by `-O`/`--output-format` (and `-o`/`--output-file`,
  see below). This means that hledger data can be easily exported,
  eg for spreadsheet reporting or to migrate to a different tool.

CLI:

- the `--width` and `--debug` options now require their argument ([#149](http://bugs.hledger.org/149))
- when an option is repeated, the last value takes precedence ([#219](http://bugs.hledger.org/219)).
  This is helpful eg for customising your reporting command aliases on
  the fly.
- smart dates (used in `-p`/`-b`/`-e`/`date:`/`date2:`) now must use a
  consistent separator character, and must be parseable to the end
- output destination and format selection is now built in to the
  balance, print and register commands, controlled by `-o`/`--output-file`
  and `-O`/`--output-format` options. Notes:
  `-o -` means stdout.
  An output file name suffix matching a supported format will also
  set the output format, unless overridden by `--output-format`.
  Commands' supported output formats are listed in their
  command-line help. Two formats are currently available:
  txt (the default) and csv.
- balance assertions can be disabled with `--ignore-assertions`

Account aliases:

- all matching account aliases are now applied, not just one directive
  and one option
- account aliases now match by case insensitive regular expressions
  matching anywhere in the account name
- account aliases can replace multiple occurrences of the pattern
  within an account name
- an account alias replacement pattern can reference matched groups
  with \\N

Queries:

- date:/date2: with a malformed date now reports an error instead of
  being ignored
- amt: now supports >= or <=
- clarify status: docs and behaviour; "*" is no longer a synonym for
  "1" (fixes [#227](http://bugs.hledger.org/227))

balance:

- fix: in tree mode, `--drop` is ignored instead of showing empty account names
- a depth limit of 0 now shows summary items with account name "...",
  instead of an empty report ([#206](http://bugs.hledger.org/206))
- in multicolumn balance reports, `-E` now also shows posting-less
  accounts with a non-zero balance during the period (in addition to
  showing leading & trailing empty columns)
- in multicolumn reports, multi-commodity amounts are rendered on one
  line for better layout ([#186](http://bugs.hledger.org/186))
- multicolumn reports' title now includes the report span

register:

- runs faster with large output
- supports date2:, and date:/date2: combined with `--date2`, better (fixes
  [#201](http://bugs.hledger.org/201), [#221](http://bugs.hledger.org/221), [#222](http://bugs.hledger.org/222))
- a depth limit of 0 now shows summary items (see balance)
- `-A`/`--average` now implies `-E`/`--empty`
- postings with multi-commodity amounts are now top-aligned, like
  Ledger


**User-visible changes in hledger-web since 0.23.3:**

General:

- fix: add missing hs/js files to package
- the web UI has been streamlined, dropping the raw and entries views and
  the edit form
- the help dialog has been improved
- keyboard shortcuts are now available
- the sidebar can be toggled open or closed (press s)

Journal view:

- layout tweaks for less truncation of descriptions and account names

Register view:

- fix: don't show all zero amounts when searching by account within an
  account register view
- chart improvements: show zero balances with correct commodity; show
  accurate balance at all dates; show transaction events & tooltips;
  show zero/today lines & background colors

Add form:

- parses data more strictly and gives better errors (eg [#194](http://bugs.hledger.org/194))
- allows any number of postings, not just two
- after adding a transaction, goes back to the journal
- keyboard shortcut (a) allows quick access

Dependencies:

- allow warp 3\*, wai-handler-launch 3\*
- require yesod 1.4* (fixes [#212](http://bugs.hledger.org/212))
- js updated (jquery, bootstrap, flot), added (typeahead, cookie, hotkeys),
  removed (select2)


**API-ish changes in hledger-lib since 0.23.3:**

- fix combineJournalUpdates folding order
- fix a regexReplaceCI bug
- fix a splitAtElement bug with adjacent separators
- mostly replace slow regexpr with regex-tdfa (fixes [#189](http://bugs.hledger.org/189))
- use the modern Text.Parsec API
- allow transformers 0.4*
- regexReplace now supports backreferences
- Transactions now remember their parse location in the journal file
- export Regexp types, disambiguate CsvReader's similarly-named type
- export failIfInvalidMonth/Day (closes [#216](http://bugs.hledger.org/216))
- track the commodity of zero amounts when possible
  (useful eg for hledger-web's multi-commodity charts)
- show posting dates in debug output
- more debug helpers


##### 2014/9/12 hledger-web 0.23.3

- remove warp, wai-handler-launch upper bounds (fixes [#205](http://bugs.hledger.org/205))

##### 2014/9/12 hledger 0.23.3

- allow text 1.2+ (fixes [#207](http://bugs.hledger.org/207))

##### 2014/5/8 hledger 0.23.2

- register: also fix date sorting of postings ([#184](http://bugs.hledger.org/184))

##### 2014/5/7 hledger 0.23.1

- register: fix a refactoring-related regression that the tests
  missed: if transactions were not ordered by date in the journal,
  register could include postings before the report start date in the
  output. ([#184](http://bugs.hledger.org/184))
- add: don't apply a default commodity to amounts on entry ([#138](http://bugs.hledger.org/138))
- cli: options before the add-on command name are now also passed to it ([#182](http://bugs.hledger.org/182))
- csv: allow the first name in a fields list to be empty ([#178](http://bugs.hledger.org/178))
- csv: don't validate fields count in skipped lines ([#177](http://bugs.hledger.org/177))


### 2014/5/1 hledger 0.23

**command-line fixes and polish, a new accounts
command, and a number of changes to the balance command relating
to `--depth`, `--flat`, and multicolumn mode, which I find has made it much
more useful.**
[mail](http://thread.gmane.org/gmane.comp.finance.ledger.hledger/1028)

Changes since 0.22.2:

Journal format:

- A # (hash) in column 0 is now also supported for starting a top-level journal comment, like Ledger.
- The "too many missing amounts" error now reminds about the 2-space rule.
- Fix: . (period) is no longer parsed as a valid amount.
- Fix: default commodity directives no longer limit the maximum display precision ([#169](http://bugs.hledger.org/169)).
- Fix: + before an amount is no longer parsed as part of the commodity ([#181](http://bugs.hledger.org/181)).

CLI:

- Command-line help cleanups, layout improvements.
- Descriptions are shown for known add-ons in the command list.
- Command aliases have been simplified.
- Add-ons can now have any of these file extensions:
  none, hs, lhs, pl, py, rb, rkt, sh, bat, com, exe.
- Add-ons are displayed without their file extensions when possible.
- Add-ons with the same name as a built-in command or alias are ignored.
- Fix: add-on detection and invocation now works on windows.
- Fix: add-ons with digits in the name are now found.
- Fix: add-on arguments containing a single quote now work.
- Fix: when -- is used to hide add-on options from the main program,
  it is no longer passed through as an add-on argument.

accounts:

- An accounts command has been added, similar to Ledger's, for listing account names
  in flat or hierarchical mode.

add:

- Tab completion now works at all prompts, and will insert the default if the input area is empty.
- Account and amount defaults are more robust and useful.
- Transactions may also be completed by the enter key, when there are no more default postings.
- Input prompts are displayed in a different colour when supported.

balance:

- Balance reports in flat mode now always show exclusive (subaccount-excluding) balances.
- Balance reports in flat mode with `--depth` now aggregate deeper accounts at the depth limit instead of excluding them.
- Multicolumn reports in flat mode now support `--drop`.
- Multicolumn balance reports can now show the account hierarchy with `--tree`.
- Multicolumn report start/end dates are adjusted to encompass the displayed
  report periods, so the first and last periods are "full" and comparable to the others.
- Fix: zero-balance leaf accounts below a non-zero-balance parent are no longer always shown ([#170](http://bugs.hledger.org/170)).
- Fix: multicolumn reports now support `--date2` (cf [#174](http://bugs.hledger.org/174)).

balancesheet, cashflow, incomestatement:

- These commands now support `--flat` and `--drop`.

print:

- Tag queries (tag:) will now match a transaction if any of its postings match.

register:

- The `--display` option has been dropped. To see an accurate running total which
  includes the prior starting balance, use `--historical`/`-H` (like balance). 
- With a report interval, report start/end dates are adjusted to encompass the displayed
  periods, so the first and last periods are "full" and comparable to the others.
- Fix: `--date2` now works with report intervals (fixes [#174](http://bugs.hledger.org/174)).

Queries:

- The currency/commodity query prefix (sym:) has been renamed to cur:.
- Currency/commodity queries are applied more strongly in register and
  balance reports, filtering out unwanted currencies entirely. Eg
  hledger balance cur:'\$' now reports only the dollar amounts even if
  there are multi-currency transactions or postings.
- Amount queries like `amt:N`, `amt:<N` and `amt:>N`, where N is not 0, now do an unsigned
  comparison of the amount and N. That is, they compare the absolute magnitude.
  To do a signed comparison instead, write N with its sign (eg amt:+N, amt:<+N, amt:>-N).
- Fix: amount queries no longer give false positives on multi-commodity amounts.

Miscellaneous:

- Default report dates now derive from the secondary dates when `--date2` is in effect.
- Default report dates now notice any posting dates outside the transaction dates' span.
- Debug output improvements.
- New add-on example: extra/hledger-rewrite.hs, adds postings to matched entries.
- Compatible with GHC 7.2 ([#155](http://bugs.hledger.org/155)) - GHC 7.8, shakespeare 2


### 2014/5/1 hledger-web 0.23

Changes since 0.22.8:

- The `--static-root` flag has been renamed to `--file-url`.
- hledger-web now builds with Cabal's default `-O`, not `-O2`,
  so may be a little quicker/less memory-hungry to install.


##### 2014/4/29 hledger-web 0.22.8

- allow shakespeare 2.* ([#179](http://bugs.hledger.org/179))

##### 2014/4/17 hledger-web 0.22.7

- add Peter Simons' patch fixing Data.Conduit.Network HostIPv4 error ([#171](http://bugs.hledger.org/171))

##### 2014/4/16 hledger-web 0.22.6

- depend on hledger[-lib] 0.22.2

##### 2014/4/16 hledger 0.22.2

- display years before 1000 with four digits, not three
- avoid pretty-show to build with GHC < 7.4
- allow text 1.1, drop data-pprint to build with GHC 7.8.x

##### 2014/4/15 hledger-web 0.22.5

- allow http-client 0.3.*, fixing cabal install again with GHC <= 7.6 (not yet 7.8)
- use pretty-show only with GHC 7.4+, fixing GHC 7.2 (fixes [#155](http://bugs.hledger.org/155))
- allow warp 2.1, fixing cabal install

##### 2014/2/10 hledger-web 0.22.4

* web: include the right unminified version of jquery.url.js (1.1) to avoid js breakage

##### 2014/2/10 hledger-web 0.22.3

* web: fix version number reported by `--version`

##### 2014/2/10 hledger-web 0.22.2

New:

* web: new option `--static-root` to set the base url for static files

Improved:

* web: include unminified source of all javascript to help packagers (fixes [#161](http://bugs.hledger.org/161))
* web: work around clang-related build failures with OS X mavericks/XCode 5
* web: allow blaze-html 0.7 (closes [#159](http://bugs.hledger.org/159))


##### 2014/1/6 hledger 0.22.1

- require the latest pretty-show so hledger installation no longer
  needs an upgraded version of happy, and the docs build on hackage

- require regex-tdfa directly instead of regex-compat-tdfa,
  simplifying Debian packaging

### 2013/12/13 hledger 0.22

[mail](http://thread.gmane.org/gmane.comp.finance.ledger.general/5333)

New:

- balance: with a reporting interval (monthly, yearly etc.), the
  [balance command](hledger.md#balance) will now show a multi-column report, showing either
  the per-period changes in balance (by default),
  the period ending balances starting from zero (`--cumulative`),
  or the actual period ending balances (`--historical`).
  A more detailed specification of the balance command's behaviour
  has been added to [Hledger.Cli.Balance](http://hackage.haskell.org/package/hledger/docs/Hledger-Cli-Balance.html).

- csv: rules files can now include other rules files, useful for factoring out common rules

- queries: `sym:REGEXP` matches commodity symbols

- register: `--average`/`-A` shows a running average, like ledger

- in period expressions, `-` (hyphen) can be used as a more compact
  synonym for `from` and `to`.  Eg: `-p 2012/12/1-2013/2/1` or `date:aug-`.

- the add-on script examples in extra/ have been updated; get the
  hledger source and add .../hledger/extra/ to your PATH to make them
  available.  They include:

  - `hledger-accountnames.hs` - print account names
  - `hledger-balance-csv.hs`  - print a balance report as CSV
  - `hledger-equity.hs`       - print an entry matching all account balances (like ledger)
  - `hledger-print-unique.hs` - print only journal entries unique descriptions
  - `hledger-register-csv.hs` - print a register report as CSV

Improved:

- balancesheet: now shows just assets and liabilities, not equity

- print: comment positions (same line or next line) are now preserved

- queries: `amt` now uses the = operator by default, eg `amt:50` is
  equivalent to `amt:=50`

- command line processing has been overhauled and made more
  consistent, and now has tests and debug output.  More flags now work
  both before and after COMMAND: `-f`, `--rule-file`, `--alias`,
  `--help`, `--debug`, `--version`.  Command line help, command
  aliases, API docs and code have been improved.

- `--debug` now takes an optional numeric argument to set the debug level
  higher than 1, for more verbose debug output in a few cases.

Fixed:

- csv: CSV data containing non-ascii characters is now supported

- build with latest versions of dependencies (text, warp, http-conduit etc.)

Release contributors:

Marko Kocić, Max Bolingbroke, and a big welcome to first-time committer John Wiegley! :)

##### 2013/7/10 hledger-web 0.21.3

  - drop yesod-platform dependency, it is not worthwhile. The other
    yesod dependencies are currently without version ranges, so cabal
    install might require `--constraint` to restrict them in some cases.

##### 2013/6/23 hledger 0.21.3

  - csv: fix wrong application of multiple assignments in a conditional block

##### 2013/6/4 hledger 0.21.2

  - web: fix a build failure

##### 2013/6/3 hledger 0.21.1

  - web: show proper Y-values in register chart (fixes [#122](http://bugs.hledger.org/122))
  - web: avoid trailing commas in register chart values, in case of trouble with IE

### 2013/6/1 hledger 0.21

Bugs fixed:

  - parsing: don't fail when a csv amount has trailing whitespace (fixes [#113](http://bugs.hledger.org/113))
  - web: don't show prices in the accounts sidebar (fixes [#114](http://bugs.hledger.org/114))
  - web: show one line per commodity in charts. Needs more polish, but fixes [#109](http://bugs.hledger.org/109).
  - web: bump yesod-platform dependency to avoid a cabal install failure

Journal reading:

  - balance assertions are now checked after reading a journal

web command:

  - web: support/require yesod 1.2
  - web: show zero-balance accounts in the sidebar (fixes [#106](http://bugs.hledger.org/106))
  - web: use nicer select2 autocomplete widgets in the add form

Documentation and infrastructure:

  - add basic cabal test suites for hledger-lib and hledger

##### 2013/5/4 hledger 0.20.0.1

  * web: require at least version 1.1.7 of yesod-core to avoid a potential build error
  * Update the bug tracker and source repository links on hackage

### 2013/5/1 hledger 0.20

Bugs fixed:

  * balance: a 0.19 regression which showed wrong total balance with `--flat` has been fixed ([#94](http://bugs.hledger.org/94))
  * register: when `--date2` is used, the register is now sorted by the secondary date
  * web: some missing static & template files have been added to the package, fixing cabal-dev and hackage builds ([#97](http://bugs.hledger.org/97), [#98](http://bugs.hledger.org/98))
  * web: some hardcoded static urls have been fixed
  * Dependencies and code have been updated to support the latest
    libraries and GHC versions.  For now, hledger requires GHC 7.2+
    and hledger-web requires GHC 7.4+.

Journal reading:

  - DOS-style line-endings are now also supported in journal and rules files.
  - `!` is now accepted in the status field as well as `*`, like ledger
  - The *actual date* and *effective date* terminology has changed to *primary date* and *secondary date*.
    Use `--date2` to select the secondary date for reports. (`--aux-date` or `--effective` are also accepted
    for ledger and backwards compatibility).
  - Per-posting dates are supported, using hledger tags or ledger's posting date syntax
  - Comment and tag handling has been improved

CSV reading:

  - CSV conversion rules have a simpler, more flexible [syntax](csv.md).
    Existing rules files will need to be updated manually:
    - the filename is now `FILE.csv.rules` instead of `FILE.rules`
    - `FIELD-field N` is now `FIELD %N+1` (or set them all at once with a `fields` rule)
    - `base-currency` is now `currency`
    - `base-account` is now `account1`
    - account-assigning rules:
      add `if` before the list of regexps,
      add indented `account2 ` before the account name
  - parenthesised amounts are parsed as negative

Querying:

  - Use `code:` to match the transaction code (check number) field
  - Use `amt:` followed by `<`, `=` or `>` and a number N to match
    amounts by magnitude. Eg `amt:<0` or `amt:=100`. This works only
    with single-commodity amounts (multi-commodity amounts are
    always matched).
  - `tag:` can now match (exact, case sensitive) tag values. Eg `tag:TAG=REGEXP`.

add comand:

  - Transaction codes and comments (which may contain tags) can now be entered, following a date or amount respectively. ([#45](http://bugs.hledger.org/45))
  - The current entry may be restarted by entering `<` at any prompt. ([#47](http://bugs.hledger.org/47))
  - Entries are displayed and confirmed before they are written to the journal.
  - Default values may be specified for the first entry by providing them as command line arguments.
  - Miscellaneous UI cleanups

register command:

  - The `--related`/`-r` flag shows the other postings in each transaction, like ledger.
  - The `--width`/`-w` option increases or sets the output width.

web command:

  - The web command now also starts a browser, and auto-exits when unused, by default ("local ui mode").
    With `--server`, it keeps running and logs requests to the console ("server mode").
  - Bootstrap is now used for styling and layout
  - A favicon is served
  - The search field is wider
  - yesod devel is now supported; it uses `$LEDGER_FILE` or `~/.hledger.journal`
  - the `blaze_html_0_5` build flag has been reversed and renamed to `blaze_html_0_4`

Add-ons:

  - The hledger-interest and hledger-irr commands have been released/updated.
  - hledger-chart and hledger-vty remain unmaintained and deprecated.

Documentation and infrastructure:

  - The hledger docs and website have been reorganised and updated
  - Manuals for past releases are provided as well as the latest dev version
  - hledger has moved from darcs and darcs hub to git and github (!)
  - The bug tracker has moved from google code to github
  - Feature requests and project planning are now managed on trello
  - A build bot builds against multiple GHC versions on each commit

Release contributors:

- Sascha Welter commissioned register enhancements (`--related` and `--width`)
- David Patrick contributed a bounty for add enhancements
- Joachim Breitner added support for ! in status field
- Xinruo Sun provided hledger-web build fixes
- Peter Simons provided hledger-web build fixes, and a build bot
- Marko Kocić provided hledger-web fixes

<!-- Days since last release: 109\ -->
<!-- Commits since last release: 105 -->


##### 2012/11/24 hledger-web 0.19.3

  * web: fix "Prelude.read: no parse" errors with GHC >= 7.6
  * web & lib refactoring

### 2012/11/16 hledger-web 0.19

  * builds with yesod 1.1.3
  * obeys command-line query options at startup again
  * the autogenerated session file is now a dot file
    (.hledger-web_client_session.aes)

##### 2012/11/16 hledger 0.19.1

  * [87](http://bugs.hledger.org/87): fix an arithmetic and transaction balancing bug with multiple
    total-priced amounts ( @@ PRICE )
  * parsing: ignore ledger-style balance assertions ( = BAL ) and fixed
    lot price declarations ( {= PRICE} )


### 2012/10/21 hledger 0.19

**a much faster balance command, and support for the latest GHC and libs.**
[mail](http://thread.gmane.org/gmane.comp.finance.ledger.general/4190)

  * hledger, hledger-lib: support GHC 7.6 and latest cmdargs, haskeline, split
  * balance report no longer has an O(n^2) slowdown with large numbers of accounts,
    and is generally more speedy. Benchmark on a 2010 macbook:

    ```
    +-------------------------------------------++--------------+--------------+--------+
    |                                           || hledger-0.18 | hledger-0.19 | ledger |
    +===========================================++==============+==============+========+
    | -f data/100x100x10.journal     balance    ||         0.21 |         0.07 |   0.09 |
    | -f data/1000x1000x10.journal   balance    ||        10.13 |         0.47 |   0.62 |
    | -f data/1000x10000x10.journal  balance    ||        40.67 |         0.67 |   1.01 |
    | -f data/10000x1000x10.journal  balance    ||        15.01 |         3.22 |   2.36 |
    | -f data/10000x1000x10.journal  balance aa ||         4.77 |         4.40 |   2.33 |
    +-------------------------------------------++--------------+--------------+--------+
    ```

  * build version is set with CPP instead of cabal-file-th

#### 2012/7/7 hledger 0.18.2

  * web: fix compilation error with -fblaze_html_0_5 flag
  * bump base lower bound to 4.3 to enforce GHC 7 requirement

#### 2012/6/29 hledger 0.18.1

  * register, print: fix reverse ordering of same-day transactions
  * balance: respect all query terms, not just acct
  * combine command-line flags like `--depth` properly with non-flag query patterns
  * web: don't auto-create a missing journal file at startup
  * stats: list included journal files
  * support tilde (~) in journal and rules file paths
  * expose more utilities from CsvReader
  * remove ensureRulesFile debug trace

### 2012/5/29 hledger 0.18

[mail](http://thread.gmane.org/gmane.comp.finance.ledger.general/3736)

  * web: hledger-web is now based on yesod 1.0
  * web: fix js error breaking second use of add form ([#72](http://bugs.hledger.org/72))
  * web: make `yesod devel` work
  * the command-line now supports a more powerful [query language](hledger.md#queries), consistent with the web UI
  * hledger now fully supports [tags](journal.md#tags) (aka metadata) on both transactions and postings, and querying by tag or tag value
  * new [commands](hledger.md#incomestatement) `incomestatement`, `balancesheet`, and `cashflow` provide basic financial statements under certain conditions
  * format conversion is now done on demand, and the convert command has been dropped. So instead of
    `hledger convert FILE.csv` just do `hledger -f FILE.csv print` or any other command.
    You can also pipe any supported format into `hledger -f- CMD` and hledger will try to do the right thing.
  * support for GHC 6.12 has been dropped; this release has been tested with GHC 7.0.4, 7.2.2, and 7.4.1
  * unicode is now handled properly on all supported GHC versions
  * API and internal cleanups

##### 2012/3/3 hledger-web 0.17.1

  * set more upper bounds to fix cabal install issues with latest packages

### 2012/2/1 hledger 0.17

**fixes bugs and updates dependencies**
[mail](http://thread.gmane.org/gmane.comp.finance.ledger.general/3149)

  * support HP 2011.4.0.0
  * support and require cmdargs 0.9
  * allow non-threaded builds, supporting more debian architectures
  * parsing: give a clearer error when journal file path contains ~
  * parsing: `-B`/`--cost` now ignores P historical prices, like ledger
  * parsing: inferred amounts now use the cost commodity if known, like ledger ([#69](http://bugs.hledger.org/69))
  * balance: report differently-priced lots in an account as a single amount, like ledger
  * web: support and require yesod >= 0.9.4
  * web: use the main aeson package again
  * web: fix a regression with dollar signs in hamlet templates
  * web: add form allowed blank account names ([#81](http://bugs.hledger.org/81))
  * chart, vty: hledger-chart and hledger-vty demoted to non-maintained extras for now

##### 2011/10/26 hledger-web 0.16.5

  * web: fix a ghc 6.12 incompatibility in Settings.hs

##### 2011/10/24 hledger-web 0.16.4

  * web: yet another cabal install fix, fix AppConfig name clash

##### 2011/10/4 hledger-web 0.16.3

  * web: another cabal install fix, disable favicon.ico since it's not easily embeddable

##### 2011/10/4 hledger-web 0.16.2

  * web: more cabal install fixes (remove bad path, add routes and models) ([#63](http://bugs.hledger.org/63))

##### 2011/10/4 hledger 0.16.1

  * parsing: show correct line number for posting parse errors ([#67](http://bugs.hledger.org/67))
  * web: declare static files as extra-source-files to fix cabal install ([#63](http://bugs.hledger.org/63))
  * web: add a threaded flag for debian ([#68](http://bugs.hledger.org/68))
  * web: fewer build warnings by default

### 2011/10/1 hledger 0.16

**a stability/bugfix/polish release (which may become the pattern for
even-numbered releases in future.)**
[mail](http://thread.gmane.org/gmane.comp.finance.ledger.hledger/521)

  * cli: strip the -- when calling add-on commands, so their options work ([#64](http://bugs.hledger.org/64))
  * cli: hledger ADDON `--version` now shows add-on command's version
  * cli: only the add and web commands auto-create the journal file
  * cli: give a non-confusing error if LEDGER_FILE contains a literal tilde
  * add: clearer prompts, more validation, use . to end also
  * add: use unix line endings consistently, avoiding parse error on windows ([#51](http://bugs.hledger.org/51))
  * add: avoid excess whitespace between transactions ([#46](http://bugs.hledger.org/46))
  * balance: ledger compatibility fix: don't elide parent accounts with multiple displayed subaccounts
  * convert: always order converted transactions by date
  * convert: rename currency -> base-currency, in-field, out-field -> amount-in-field, amount-out-field
  * convert: give an error, not a zero when date or amount-in-field/amount-out-field parsing fails
  * register: show more useful range of intervals with `--empty` and a query pattern
  * print, web: always show both dates, ignoring `--effective` ([#42](http://bugs.hledger.org/42))
  * web: production builds (the default with cabal) have all web content embedded (dev builds use ./static/) ([#63](http://bugs.hledger.org/63))
  * web: update to yesod 0.9
  * web: obey at least some of the general reporting options, like `--cost`
  * web: adjust the default base url when a custom port is specified
  * web: prevent an infinite redirect when custom base url has a trailing slash
  * web: fix "not:'multi word'" patterns
  * web: hide old title and search form when adding/editing
  * web: adjust `--help` to indicate command-line arguments are not expected
  * web: don't bother running cli unit tests at startup

##### 2011/9/12 hledger 0.15.2, hledger-web 0.15.3

  * handle multiple filter patterns on the command-line again
  * don't pass an add-on command's name to it as an extra argument
  * don't give a confusing error with `-f` and no command
  * fix a regression balancing a transaction containing different prices
  * web: fix journal edit form
  * web: fix wrong transaction amount in account register with virtual postings
  * web: fix some invalid html

##### 2011/9/2 hledger 0.15.1, hledger-web 0.15.2

  * fix a parsec 2 incompatibility
  * web: add missing Hledger.Web.Options to cabal file
  * web: tighten up dependencies to reduce build problems

### 2011/9/1 hledger 0.15

[mail](http://thread.gmane.org/gmane.comp.finance.ledger.general/2748)

  * hledger's options are now modal, providing better help (using cmdargs)
  * hledger now lists and runs any hledger-* add-ons found in the user's path
  * case insensitivity of filter patterns has been fixed
  * parsing: `alias`/`end aliases` directives, for renaming accounts, are supported, like ledger's but a bit more powerful; also an `--alias` option for renaming on the fly
  * parsing: the `account` directive now preserves posting type (normal/virtual/balanced virtual)
  * parsing: the `pop` directive is supported as an alias for `end tag`, like ledger
  * parsing: `P` (historical price) directives can contain a (ignored) numeric time zone, like ledger
  * parsing: the leading `!` in directives is now optional and deprecated, like ledger
  * parsing: entries with a negative amount in the first posting now infer the correct balancing amount
  * parsing: bad date checking is more accurate
  * balance: collapsing of boring accounts to one line can be disabled with `--no-elide`
  * balance: fix a wrong precision regression from last release
  * convert: standard input can be converted
  * convert: an alternate rules file can be specified with `--rules`
  * convert: `account2-field` can be used when the CSV file specifies both accounts
  * convert: `description-field` can have a custom format and combine multiple CSV fields
  * convert: `in-field` and `out-field` support CSV files that use two amount columns
  * convert: don't fail when there's no default journal file
  * web: the web interface has been overhauled/cleaned up
  * web: account register views are now transaction-based, like gnucash etc., and show accurate historical balances when possible
  * web: simple balance charts are displayed (using flot)
  * web: more expressive and consistent search patterns, using a new matching engine
  * web: add form uses currently focussed account as default, redirects to itself, formats status messages better
  * web: sidebar now shows empty/boring accounts too
  * web: now uses warp and a newer yesod
  * api simplifications
  * importable Hledger, Hledger.Web, Hledger.Vty and Hledger.Chart modules
  * the basic reports are now provided by hledger-lib for easier reuse
  * new api use examples: `equity.hs`, `uniquify.hs`
  * some old base 3 support has been dropped
  * the old `-s` flag has been dropped

### 2011/4/22 hledger 0.14

[mail](http://thread.gmane.org/gmane.comp.finance.ledger.hledger/383)

  * remove the specific process dependency that caused too many cabal install problems
  * treat arguments as possibly-encoded platform strings, do not assume UTF-8
  * hledger now always reads and writes data as UTF-8, ignoring the system locale ([#34](http://bugs.hledger.org/34))
  * look at the LEDGER_FILE env var for the journal path, otherwise LEDGER, like ledger
  * handle a blank LEDGER_FILE or LEDGER value more gracefully (use the default file path)
  * the default journal file path is now ~/.hledger.journal, to avoid breaking mac filevault ([#41](http://bugs.hledger.org/41))
  * amounts with different prices are now aggregated, like ledger
  * zero amounts now have no sign or commodity, like ledger
  * parsing: assume current year when transaction dates have no year and there is no default year
  * parsing: more careful validation of eg leap years in transaction dates
  * parsing: better international number format support, allowing comma as decimal point and flexible digit groups ([#32](http://bugs.hledger.org/32))
  * parsing: support @@ syntax specifying total price
  * parsing: infer the conversion price in transactions involving two unpriced commodities
  * parsing: support per-posting cleared status
  * parsing: more reporting interval syntax: biweekly, bimonthly, every N days/weeks/months/quarters/years, every Nst/nd/rd/th day of month/week
  * add: avoid offering account names for completion in inappropriate contexts
  * add: remember default account even if user submits a different amount.
  * convert: account-field directive specifies a field containing the base account name
  * convert: effective-date-field directive specifies a field containing the effective date
  * convert: date-format directive specifies custom date formats
  * convert: allow amount fields containing "AMT @@ PRICE"
  * histogram: honour the specified start or end dates
  * print: don't show a trailing space when description is blank
  * web: allow filter patterns with spaces if quoted, like command line
  * web: make edit form more cross-browser compatible, fixing it in firefox ([#38](http://bugs.hledger.org/38))
  * web: move hidden add/edit/import forms below main content to help text-mode browsers a bit ([#33](http://bugs.hledger.org/33))

Release contributors: Simon Michael, Dmitry Astapov, Eric Kow, Max Bolingbroke, Omari Norman.
Stats:
137 days, 113 commits, 11 end-user features and 15 end-user bugfixes since last release.
189 unit & functional tests and 59% unit test coverage (hledger, hledger-lib packages).
5540 lines of code (all packages).

### 2010/12/6 hledger 0.13

**readline editing and tab completion
from Judah Jacobson, more ledger compatibility, a more robust and
installable web interface, bugfixes, and a much-deliberated package split.**
[mail](http://thread.gmane.org/gmane.comp.finance.ledger.hledger/296)

  * move web, vty, chart commands into separate hledger-web, hledger-vty,
    hledger-chart packages. This both simplifies (no more build flags) and
    complicates (more room for dependency hassles), but I hope overall it
    will be easier and more scalable.
  * all packages but chart are now marked "beta", ie "not finished but
    suitable for everyday use"
  * parsing: ledger compatibility: support D default commodity directive
  * parsing: ledger compatibility: ignore metadata tags on transactions and postings
  * parsing: ledger compatibility: ignore cleared flags at the start of postings
  * parsing: ledger compatibility: ignore C commodity conversion directives
  * parsing: price precisions no longer affect commodities' display precisions
  * add: readline-style editing
  * add: tab-completion for account names
  * add: add the default commodity, if any, to commodity-less amounts ([#26](http://bugs.hledger.org/26))
  * add: misc. commodity/precision/defaults-related bugfixes
  * chart: give a meaningful error message for empty journals
  * chart: update for current Chart lib (0.14)
  * web: support files now live in ./.hledger/web/ and will be auto-created at startup
  * web: page layout is more robust with wide content
  * web: allow editing of included files
  * web: handle multiple filter patterns correctly
  * web: allow single- or double-quoted filter patterns containing spaces
  * web: update for current yesod lib (0.6.*)
  * transaction balancing is now based on display precision ([#23](http://bugs.hledger.org/23))
  * briefer, more informative usage error messages

##### 2010/9/6 hledger 0.12.1

[mail](http://thread.gmane.org/gmane.comp.finance.ledger.hledger/272)

  * web: fix account filtering breakage
  * installing: tighten up utf8-string dependency

### 2010/9/5 hledger 0.12

  * web: new, better web ui; accounts are now a permanent sidebar; add form uses auto-completing combo fields
  * installing: fix a build error with parsec 3 ([#22](http://bugs.hledger.org/22))
  * installing: require exactly matching hledger-lib version for more robust builds
  * installing: explicit data-object dependency to ensure hledger and hledger-lib use the same time version
  * installing: explicit hamlet dependency for more robust building
  * installing: build threaded and with warnings
  * installing: drop -fweb610 flag
  * installing: add gtk2hs-buildtools dependency needed to build with -fchart
  * installing: require cabal 1.6 or greater
  * add `-D`/`--daily` flag
  * register: with `--depth`, clip account names or aggregate postings rather than excluding them
  * fix !include with deeply nested directories ([#21](http://bugs.hledger.org/21))
  * fix obscured date parse errors with parsec 3
  * handle unicode better in errors
  * fix a ghc 6.12.3 error when running interpreted

Stats: 50 days and 90 commits since last release, now at 5741
lines of code with 136 tests and 41% unit test coverage.

##### 2010/07/17 hledger 0.11.1

  * fix `--version` output

### 2010/07/17 hledger 0.11

[mail](http://thread.gmane.org/gmane.comp.finance.ledger.hledger/253)

  * split `--help`, adding `--help-options` and `--help-all`/`-H`, and make
    it the default command
  * use "journal" instead of "ledger file"; default suffix is
    .journal, default file is \~/.journal
  * auto-create missing journal files rather than giving an error
  * new format-detecting file reader (mixed journal transactions
    and timelog entries are no longer supported)
  * work around for first real-world rounding issue (test zero to 8
    decimal places instead of 10)
  * when reporting a balancing error, convert the error amount to
    cost
  * parsing: support double-quoted commodity symbols, containing
    anything but a newline or double quote
  * parsing: allow minus sign before commodity symbol as well as
    after (also fixes a convert bug)
  * parsing: fix wrong parse error locations within postings
  * parsing: don't let trailing whitespace in a timelog description
    mess up account names
  * add: allow blank descriptions
  * balance: `--flat` provides a simple non-hierarchical format
  * balance: `--drop` removes leading account name components from a
    `--flat` report
  * print, register, balance: fix layout issues with
    mixed-commodity amounts
  * print: display non-simple commodity names with double-quotes
  * stats: layout tweaks, add payee/description count
  * stats: don't break on an empty file
  * stats: `-p`/`--period` support; a reporting interval generates
    multiple reports
  * test: drop verbose test runner and testpack dependency
  * web: a new web ui based on yesod, requires ghc 6.12; old ghc
    6.10-compatible version remains as -fweb610
  * web: allow wiki-like journal editing
  * web: warn and keep running if reloading the journal gives an
    error
  * web: `--port` and `--base-url` options set the webserver's tcp port
    and base url
  * web: slightly better browser opening on microsoft windows,
    should find a standard firefox install now
  * web: in a web-enabled build on microsoft windows, run the web
    ui by default

Stats: 55 days and 136 commits since last release. Now at 5552
lines of code with 132 tests and 54% unit test coverage.

### 2010/05/23 hledger 0.10

**installation and bug fixes and api improvements**
[mail](http://thread.gmane.org/gmane.comp.finance.ledger.hledger/242)

  * fix too-loose testpack dependency, missing safe dependency
  * fix ghc 6.12 compatibility with -fweb
  * fix handling of non-ascii arguments with ghc 6.12
  * fix "0.8" in `--version` output
  * fix an occasional stack overflow error due to infinite
    recursion in Posting/Transaction equality tests
  * the -fwebhappstack build flag is gone for now, to avoid a cabal
    problem
  * parsing: if there is no description, don't require a space
    after the transaction date
  * parsing: balance balanced-virtual postings separately, allow
    them to have an implicit amount
  * parsing: timelog entries now generate balanced transactions,
    using virtual postings
  * parsing: simpler high-level parse error message
  * parsing: clearer bad date errors
  * add: fix wrongful program exit on bad dates
  * print: negative account patterns now exclude transactions
    containing any posting to a matched account
  * vty: rename the ui command to vty for consistency
  * vty: fix restricted account scope when backing up to top level
  * web: fix non-ascii handling with ghc 6.12
  * web: fix a bug possibly affecting reload-on-change
  * consolidate module namespace under Hledger, api cleanups

Stats: 44 days, 81 commits since last release. Now at 4904 lines of
code including tests, 144 tests, 53% coverage.

### 2010/04/10 hledger 0.9

**many bugfixes and small improvements, GHC 6.12 support, and a separate library package
to make building (h)ledger-compatible tools easier.**
[mail](http://thread.gmane.org/gmane.comp.finance.ledger.hledger/239)

  * ghc 6.12 support
  * split off hledger-lib package, containing core types & utils
  * parsing: ignore D, C, N, tag, end tag directives; we should now
    accept any ledger 2.6 file
  * parsing: allow numbers in commodities if double-quoted, like
    ledger
  * parsing: allow transactions with empty descriptions
  * parsing: show a better error for illegal month/day numbers in
    dates
  * parsing: don't ignore trailing junk in a smart date, eg in web
    add form
  * parsing: don't ignore unparsed text following an amount
  * parsing: @ was being treated as a currency symbol
  * add: fix precision handling in default amounts ([#19](http://bugs.hledger.org/19))
  * add: elide last amount in added transactions
  * convert: keep original description by default, allow
    backreferences in replace pattern
  * convert: basic csv file checking, warn instead of dying when it
    looks wrong
  * convert: allow blank/comment lines at end of rules file
  * print: always show zero amounts as 0, hiding any
    commodity/decimal places/price, like ledger
  * register: fix bad layout with years < 1000
  * register: fix a Prelude.head error with reporting interval,
    `--empty`, and `--depth`
  * register: fix a regression, register should not show posting
    comments
  * register: with `--empty`, intervals should continue to ends of
    the specified period
  * stats: better output when last transaction is in the future
  * stats: show commodity symbols, account tree depth, reorder
    slightly
  * web: -fweb now builds with simpleserver; to get happstack, use
    -fwebhappstack instead
  * web: pre-fill the add form with today's date
  * web: help links, better search form wording
  * web: show a proper error for a bad date in add form ([#17](http://bugs.hledger.org/17))
  * web: fix for unicode search form values
  * web: fix stack overflow caused by regexpr, and handle requests
    faster ([#14](http://bugs.hledger.org/14))
  * web: look for more-generic browser executables
  * web: more robust browser starting ([#6](http://bugs.hledger.org/6))
  * error message cleanups
  * more tests, refactoring, docs

Stats: 58 days, 2 contributors, 102 commits since last release. Now
at 3983 lines of non-test code, 139 tests, 53% coverage.

### 2010/02/11 hledger 0.8

**Bug fixes, refactoring and Hi-Res Graphical Charts.**
[mail](http://thread.gmane.org/gmane.comp.finance.ledger.hledger/210)

  * parsing: in date=date2, use first date's year as a default for
    the second
  * add: ctrl-d doesn't work on windows, suggest ctrl-c instead
  * add: `--no-new-accounts` option disallows new accounts (Roman
    Cheplyaka)
  * add: re-use the previous transaction's date as default (Roman
    Cheplyaka)
  * add: a command-line argument now filters by account during
    history matching (Roman Cheplyaka)
  * chart: new command, generates balances pie chart (requires
    -fchart flag, gtk2hs) (Roman Cheplyaka, Simon Michael)
  * register: make reporting intervals honour a display expression
    ([#18](http://bugs.hledger.org/18))
  * web: fix help link
  * web: use today as default when adding with a blank date
  * web: re-enable account/period fields, they seem to be fixed,
    along with file re-reading ([#16](http://bugs.hledger.org/16))
  * web: get static files from the cabal data dir, or the current
    dir when using make ([#13](http://bugs.hledger.org/13))
  * web: preserve encoding during add, assuming it's utf-8 ([#15](http://bugs.hledger.org/15))
  * fix some non-utf8-aware file handling ([#15](http://bugs.hledger.org/15))
  * filter ledger again for each command, not just once at program
    start
  * refactoring, clearer data types

Stats: 62 days, 2 contributors, 76 commits since last release. Now
at 3464 lines of non-test code, 97 tests, 53% test coverage.

### 2009/12/11 hledger 0.7

[mail](http://thread.gmane.org/gmane.comp.finance.ledger.hledger/193)

  * price history support (first cut): P directives now work,
    though differently from ledger. Each posting amount takes its
    fixed unit price from the price history (or
    @) when available. This is simple and useful for things like
    foreign currency expenses (but not investment tracking). Like
    ledger, balance and register don't show amount prices any more, and
    don't separate differently-priced amounts. Unlike ledger, print
    shows all amount prices, and supports `-B`.
  * `--effective` option, will use transactions' effective dates if
    any
  * convert: new rules file format, find/create rules file
    automatically, more robust parsing, more useful `--debug` output
  * print: always sort by date, fix long account name truncation,
    align amounts, show end of line comments, show all amounts for
    clarity (don't elide the final balancing amount)
  * ui: use vty 4, fixes non-ascii and gnome terminal problems
    (issues [#3](http://bugs.hledger.org/3), [#4](http://bugs.hledger.org/4))
  * web: allow data entry, react to data file changes, better
    layout, help links, remove histogram command and filter fields for
    now, fix bad localhost redirect, filter form did not work in eg
    firefox (issue [#7](http://bugs.hledger.org/7)), reset link did not work in all browsers
  * parsing: require whitespace between date and status code, allow
    (and ignore) a time in price records, better error messages,
    non-zero exit code on parse failure
  * display non-ascii error messages properly (issue [#5](http://bugs.hledger.org/5))
  * fix an arithmetic bug that occasionally rejected valid
    transactions
  * fix a regex bug in showtree
  * don't break if HOME is undefined
  * `--debug` now implies `--verbose`
  * add functional tests like ledger's, use test-framework for
    speedy running, release shelltestrunner as a separate package
  * many hlint cleanups (Marko Kocić)
  * many site and documentation updates

Stats: 60 days, 1 contributor, 50 commits since last release. Now
at 3377 lines of non-test code, 97 tests, 53% test coverage.

##### 2009/06/22 hledger 0.6.1

  * avoid use of exitSuccess which was breaking ghc 6.8/base 3
    compatibility (issue [#2](http://bugs.hledger.org/2))

### 2009/06/13 hledger 0.6

**Some pre-built binaries are now available. cabal install works on gnu/linux, mac and windows. Hurrah!**
[mail](http://thread.gmane.org/gmane.comp.finance.ledger.general/1215)

  * now cabal-installable on unix, mac, and windows, with Haskell
    Platform
  * provide experimental platform binaries
  * parsing: fix a silly failure to open ledger file paths
    containing \~
  * parsing: show better errors for unbalanced transaction and
    missing default year
  * parsing: allow parentheses and brackets inside account names,
    as ledger does
  * parsing: fail on empty account name components, don't just
    ignore
  * add: description passed as arguments now affects first
    transaction only
  * add: better handling of virtual postings and default amounts
  * print, register: show virtual accounts bracketed/parenthesised
  * web: improved web ui supporting full patterns & period
    expressions
  * new "stats" command reports some ledger statistics
  * many dev/doc/deployment infrastructure improvements
  * move website into darcs repo, update home page
  * move issue tracker to google code

Release stats:

  * Contributors: Simon Michael
  * Days since last release: 21
  * Commits: 94
  * Lines of non-test code: 2865
  * Tests: 82
  * Test coverage: 53% expressions
  * Known errors: 3 (inconsistent eliding, vty-related failures)
  * Performance: similar
    (http://hledger.org/profs/200906131120.bench)

##### 2009/05/23 hledger 0.5.1

  * two fixes: really disable vty flag by default, and include
    ConvertCommand in cabal file

### 2009/05/23 hledger 0.5

[mail](http://thread.gmane.org/gmane.comp.finance.ledger.general/1181)

  * the vty flag is disabled by default again, to ease installation
    on windows
  * use ledger 3 terminology: a ledger contains transactions which
    contain postings
  * new "add" command prompts for transactions interactively and
    adds them to the ledger
  * new "convert" command transforms bank CSV exports to ledger
    format, with rule-based cleanup
  * new "histogram" command shows transaction counts per day or
    other reporting interval
  * most commands now work properly with UTF8-encoded text (Sergey
    Astanin)
  * invoking as "hours" is now less different: it just uses your
    timelog, not your ledger
  * `--quarterly`/`-Q` option summarises by quarter
  * `--uncleared`/`-U` option looks only at uncleared transactions
  * be more accurate about checking balanced amounts, don't rely on
    display precision
  * enforce balancing for bracketed virtual postings
  * fix bug in eliding of posting amounts
  * don't show trailing spaces on amountless postings
  * parse null input as an empty ledger
  * don't treat comments as part of transaction descriptions
  * require some postings in ledger transactions
  * require a non-empty description in ledger transactions
  * don't fail when matching an empty pattern, as in "not:"
  * make the web server handle the null path
  * code, api and documentation updates
  * add a contributor agreement/list

Release stats:

  * Contributors: Simon Michael, Sergey Astanin
  * Days since last release: 51
  * Commits: 101
  * Lines of non-test code: 2795
  * Tests: 76
  * Known errors: 0

### 2009/04/03 hledger 0.4

**There is also a new website at hledger.org, with screenshots (textual!),
a demo (will it survive!?), and docs (not too many!) ...
I wrote it because I did not want to hack on c++ and because haskell seemed a good fit ...
new happstack-based web interface.**
[mail](http://thread.gmane.org/gmane.comp.finance.ledger.general/1097)

  * new "web" command serves reports in a web browser (install with
    -f happs to build this)
  * make the vty-based curses ui a cabal build option, which will
    be ignored on MS windows
  * drop the `--options-anywhere` flag, that is now the default
  * patterns now use `not:` and `desc:` prefixes instead of `^` and ``^^``
  * patterns are now case-insensitive, like ledger
  * `!include` directives are now relative to the including file (Tim
    Docker)
  * "Y2009" default year directives are now supported, allowing m/d
    dates in ledger
  * individual transactions now have a cleared status
  * unbalanced entries now cause a proper warning
  * balance report now passes all ledger compatibility tests
  * balance report now shows subtotals by default, like ledger 3
  * balance report shows the final zero total when `-E` is used
  * balance report hides the final total when `--no-total` is used
  * `--depth` affects print and register reports (aggregating with a
    reporting interval, filtering otherwise)
  * register report sorts transactions by date
  * register report shows zero-amount transactions when `-E` is used
  * provide more convenient timelog querying when invoked as
    "hours"
  * multi-day timelog sessions are split at midnight
  * unterminated timelog sessions are now counted. Accurate time
    reports at last!
  * the test command gives better `--verbose` output
  * `--version` gives more detailed version numbers including
    patchlevel for dev builds
  * new make targets include: ghci, haddocktest, doctest, unittest,
    view-api-docs
  * a doctest-style framework for functional/shell tests has been
    added

Release stats:

  * Contributors: Simon Michael, Tim Docker; thanks to the HAppS,
    happstack and testpack developers
  * Days since release: 76
  * Commits: 144
  * Lines of non-test code: 2367
  * Tests: 56
  * Known errors: 0

### 2009/01/17 hledger 0.3

[mail](http://thread.gmane.org/gmane.comp.finance.ledger.hledger/67)

  * count timelog sessions on the day they end, like ledger, for
    now
  * when options are repeated, use the last instead of the first
  * builds with ghc 6.10 as well as 6.8
  * a simple ui for interactive report browsing: hledger ui
  * accept smart dates everywhere (YYYYMMDD, Y/M/D, Y, M/D, D, jan,
    today, last week etc.)
  * `--period`/`-p` flag accepting period expressions like "in 2008",
    "weekly from last month"..
  * `-W`/`-M`/`-Y` convenience flags to summarise register weekly,
    monthly, yearly
  * `--depth` and `-E` flags also affect summarised register reports
    (including depth=0)
  * `--display`/`-d` flag supporting date predicates (like "d<[DATE]",
    "d\>=[DATE]")
  * `!include` directive to include additional ledger files
  * `!account` directive to set a default parent account
  * Added support for reading historical prices from files
  * timelog and ledger entries can be intermixed in one file
  * modifier and periodic entries can appear anywhere (but are
    still ignored)
  * help and readme improvements
  * runs much faster than 0.2

Release stats:

  * Contributors: Simon Michael, Nick Ingolia, Tim Docker; thanks
    to Corey O'Connor & the vty team
  * Lines of non-test code: 2123
  * Tests: 58
  * Known errors: 1

### 2008/11/23 hledger 0.2

[mail](http://thread.gmane.org/gmane.comp.finance.ledger.general/826)

  * fix balance report totals when filtering by account
  * fix balance report selection of accounts when filtering by
    account
  * fix a bug with account name eliding in balance report
  * if we happen to be showing a not-yet-auto-balanced entry, hide
    the AUTO marker
  * fix print command filtering by account
  * omit transactions with zero amount from register report
  * Fix bug in parsing of timelogs
  * rename `--showsubs` to `--subtotal`, like ledger
  * drop `--usage` flag
  * don't require quickcheck
  * priced amounts (eg "10h @ $50") and `--basis`/`--cost`/`-B` flag to
    show them with cost basis
  * easy `--depth` option, equivalent to ledger's `-d 'l<=N'`
  * smarter y/m/d date parsing for `-b` and `-e` (any number of digits,
    month and day default to 1, separator can be / - or .)
  * `-n` flag for balance command
  * `--empty`/`-E` flag
  * build a library, as well as the exe
  * new home page url (http://joyful.com/hledger)
  * publish html and pdf versions of README
  * detect display preferences for each commodity like ledger
  * support amounts with multiple currencies/commodities
  * support `--real`/`-R` flag
  * support `-C`/`--cleared` flag to filter by entry status (not
    transaction status)
  * support virtual and balanced virtual transactions
  * parse comment lines beginning with a space, as from M-; in
    emacs ledger-mode
  * allow any non-whitespace in account names, perhaps avoiding
    misleading missing amounts errors
  * clearer error message when we can't balance an entry
  * when we fail because of more than one missing amount in an
    entry, show the full entry
  * document the built-in test runner in `--help`
  * add a `--verbose`/`-v` flag, use it to show more test-running
    detail

Release stats:

  * Contributors: Simon Michael, Tim Docker
  * Lines of non-test code: 1350
  * Tests: 43
  * Known errors: 0

### 2008/10/15 hledger 0.1

[mail](http://thread.gmane.org/gmane.comp.finance.ledger.general/775)
**I'm pleased to announce the first release of hledger, a command-line
accounting tool similar to John Wiegley's c++ ledger. hledger generates
simple ledger-compatible transaction & account balance reports from a
plain text ledger file. It's simple to use, at least for techies.
This has been my "learning Haskell" project, but I think it's also
useful. It is much less featureful than ledger, and not quite as fast,
but it has the virtue of being fun for haskellers to hack on. I am
documenting the code, the app is simple, and I'm not too far up the
haskell learning curve, so I think other people learning haskell might
enjoy a look. It is currently ~1100 lines of haskell excluding tests.
My thanks to John Wiegley for help with compatibility and for his very
useful ledger tool. I use it (and now, both of them) daily to track time
and money. This is of course a hot topic around our planet. I hope you
find it useful or intriguing.**

Release stats:

  * Contributors: Simon Michael









