<!--
              _
__      _____| |__
\ \ /\ / / _ \ '_ \
 \ V  V /  __/ |_) |
  \_/\_/ \___|_.__/

Section headings: "Breaking changes" first if any; then topic headings,
or a suitable generic heading (eg Fixes, Improvements), as needed.

-->

User-visible changes in hledger-web.
See also the hledger changelog.


# 5817e58e

Fixes

- An XSS (cross-site scripting) vulnerability has been fixed in the
  add form's autocomplete. Journal data from an untrusted source could
  execute javascript when shown as a completion suggestion. All
  hledger-web users should upgrade.
  (Arthur Cinader, Simon Michael, [#2698], advisory GHSA-538p-cvc4-4qjm)

- Another XSS vulnerability has been fixed in the add transaction
  form's error message. Any web page visited while hledger-web was
  running could use it to run javascript in hledger-web's origin, and
  from there read the whole journal, or alter it. All hledger-web
  users should upgrade.  (Arthur Cinader, Simon Michael, [#2700],
  advisory GHSA-vq7r-8w52-jv84)

- A newline submitted in a transaction's description, code or account
  name is no longer written into the journal file. This removes the
  possibility of the user inserting an include directive, which could
  expose system files readable by the hledger-web server.  ([#2704],
  advisory GHSA-vq7r-8w52-jv84)

- The upload form now shows the name of the chosen file. It never did
  before, because of an escaping bug that disabled its handler.
  (Arthur Cinader)

- /favicon.ico and /robots.txt no longer return 404 unless hledger-web
  happens to be run from its source directory; they are now built into
  the executable, like the other static files. robots.txt now also asks
  crawlers not to index the site. (Arthur Cinader)

- hledger-web now has its own favicon: a gold coin struck with an equals
  sign, in the palette of the hledger coin logo. It replaces the Yesod
  scaffold's blue "y". (Arthur Cinader)

Improvements

- Keep the account sidebar's scroll position when switching accounts
  [#2679] (Arthur Cinader).  The sidebar and the main content now
  scroll independently (on wider screens), so you don't lose your
  place when clicking an account - the account stays exactly where it
  was. And, the sidebar's scroll position is remembered across
  navigations.

- --port 0 lets the OS choose a free port [#2559] (Arthur Cinader).
  The chosen port is reported in the startup message and used in the
  default base url, so scripts can discover it. Supported with --serve
  and --serve-api.

- Add the -? and --webman flags; rename --tldr to --examples (see hledger changelog).

- The web UI's javascript has been modernised, replacing five vendored
  libraries with standard browser features (Arthur Cinader):
  autocomplete suggestions now use a native `<datalist>`; the button
  beside the date field opens the browser's own date picker (typed
  smart dates like "today" still work); and keyboard shortcuts,
  sidebar state and transaction-link highlighting are handled by small
  standard code. Two dead third-party script tags (html5shiv, chrome
  frame) are gone, so nothing is loaded from a third party now. jquery
  and the flot library remain, for the register chart. Also,
  browser-drawn widgets like the suggestion list and date picker now
  stay light when the OS is in dark mode.

- The add and help dialogs now use the native `<dialog>` element
  instead of bootstrap modals, so bootstrap.js is no longer loaded
  (Arthur Cinader). They keep the familiar look - rounded corners,
  shadow, dimmed backdrop - and open near the top of the window as
  before.

- hledger-web now sends the `X-Frame-Options: SAMEORIGIN` and
  `X-Content-Type-Options: nosniff` security headers on every
  response, so other sites can't frame its pages for clickjacking, and
  browsers won't second-guess content types. Static files and error
  pages get them too. (Arthur Cinader)

- The yesod-static and hjsmin dependencies have been dropped;
  hledger-web now serves its static files itself, using wai-app-static
  and file-embed. (yesod-static doesn't currently build with crypton
  1.1+, which has kept it, and hledger-web, out of stackage nightly.)
  Static file urls no longer include an `?etag=...` cache buster;
  instead the files are served with an ETag header, and conditional
  requests are answered with 304 Not Modified.

- The aeson lower bound has been relaxed from 2.3 to 2.2.5.1, the
  oldest version not vulnerable to the HSEC-2026-0007 denial of
  service, easing installation while the ecosystem catches up with
  newer aeson.

- hledger-web now sends a Content-Security-Policy with every page
  [#2703] (Arthur Cinader). The browser loads scripts, styles, images
  and fonts only from hledger-web's own origin, and runs only the
  inline scripts that carry the page's nonce. A script that reached a
  page some other way, eg through journal data, is blocked and
  reported in the browser's console. The policy also refuses framing
  by another site, as X-Frame-Options does for the other responses.

- The register chart is drawn from data carried on the page rather
  than from a script generated into it. This fixes the chart silently
  disappearing when a commodity symbol contained a backslash and a
  double quote, and moves the legend from inside the chart, where it
  covered the start of the balance line, to the title line above it.

- The unused Google Analytics hook has been removed.

[#2559]: https://github.com/plaintextaccounting/hledger/issues/2559
[#2679]: https://github.com/plaintextaccounting/hledger/issues/2679
[#2698]: https://github.com/plaintextaccounting/hledger/issues/2698
[#2700]: https://github.com/plaintextaccounting/hledger/issues/2700
[#2703]: https://github.com/plaintextaccounting/hledger/issues/2703
[#2704]: https://github.com/plaintextaccounting/hledger/issues/2704


# 1.52.2 2026-08-24

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


# 1.99.3 2026-06-24

Breaking changes

- When listening on a non-local-only IP address, hledger-web now
  allows only read-only access by default. So if you set a public
  address with --host, you may also need --allow=add.

Fixes

- hledger-web now uses aeson 2.3, avoiding a denial-of-service bug in
  that library.  Previous hledger-web versions, with /add enabled, are
  vulnerable to HTTP requests that could trigger memory/CPU exhaustion.
  Now it uses a fixed version of aeson (and disables /add by default,
  except on local-only addresses).
  (<https://haskell.github.io/security-advisories/advisory/HSEC-2026-0007.html>)

Features

- `cur:COMM` queries now match COMM or any of its commodity aliases (see hledger changelog).
  To match only a specific symbol without considering aliases, use `sym:SYM`.
  Aliases are recomputed on each journal reload, so a mid-session
  change to alias definitions takes effect next time.

Improvements

- allow megaparsec >9.8
- allow yesod-core 1.7*

Docs

API


# 1.99.2 2026-04-28

Improvements

- Allow yesod-static 1.6.1.1 and later again.

- Uses hledger 1.99.2.


# 1.52.1 2026-04-28

Improvements

- Uses hledger 1.52.1.


# 1.99.1 2026-03-28

(2.0 preview 1)

Breaking changes

- Posting's `ptype` field has been renamed to `preal` (and `PostingType` to `PostingRealness`),
  to avoid confusion with the new `ptype` tag. This changes JSON output.

Improvements

- Uses hledger 1.99.1

- Require yesod-static <1.6.1.1 to avoid a build breakage with cabal
  (https://github.com/psibi/crypton-conduit/issues/3).


# 1.52 2026-03-20

Fixes

- The less pager (used for displaying help, eg) is now invoked more robustly; we catch and report more kinds of failure clearly.
  [#2544]

Docs

- openapi.yaml (the OpenAPI spec for hledger-web's JSON API) has been updated.
  (n0vdd)

[#2544]: https://github.com/plaintextaccounting/hledger/issues/2544


# 1.51.2 2026-01-08

- The register view now prevents line wrapping in dates when the window is narrow. [#2520]

- Allow base 4.22 / ghc 9.14.

[#2520]: https://github.com/plaintextaccounting/hledger/issues/2520


# 1.51.1 2025-12-08

- Uses hledger 1.51.1.


# 1.51 2025-12-05

Improvements

- Uses hledger 1.51.


# 1.50.5 2025-12-08

- Uses hledger 1.50.5.


# 1.50.4 2025-12-04

- Uses hledger 1.50.4.


# 1.50.3 2025-11-18

- The old "threaded" build flag, which cabal could turn off, has been dropped.
  [#2495]

- Uses hledger 1.50.3


# 1.50.2 2025-09-26

- Uses hledger 1.50.2


# 1.50.1 2025-09-16

- Uses hledger 1.50.1


# 1.50 2025-09-03

Breaking changes

- hledger now requires at least GHC 9.6 (and base 4.18), to ease maintenance.

Fixes

- The register chart is no longer hidden when the window is narrow.

- Dragging on the register chart now selects date ranges more accurately.
  Eg, now you can select a range including transactions at the rightmost edge of the chart.

Improvements

- Use hledger 1.50


# 1.43.2 2025-06-13

- Use hledger-1.43.2

- Add missing issue numbers in the changelog


# 1.43.1 2025-06-04

Fixes

- Fixed a compilation error when not in the hledger source tree. [#2397]


# 1.43 2025-06-01

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


# 1.42.2 2025-05-16

Fixes

- Don't hang when saving a large file (this broke in 1.42). [#2319]

- Require extra >= 1.7.11, fixing the stack8.10.yaml build. (Thomas Miedema)


# 1.42.1 2025-03-12

- Build with hledger 1.42.1.


# 1.42 2025-03-07

Fixes

- Fix a test suite build issue: build it with -threaded.


# 1.41 2024-12-09

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

- Added a new `debug` build flag. Builds made with ghc 9.10+ and this flag
  will show some kind of partial stack trace if the program exits with an error.
  These will improve in future ghc versions.

- Disabled the unused `ghcdebug` build flag and ghc-debug support, for now.

- allow megaparsec 9.7

- ghc 9.10 / base 4.20 are now supported.

Docs

- Install, manual: new shell completions doc. [#986]



# 1.40 2024-09-09

Improvements

- We now guess a more robust base url when `--base-url` is not specified.
  Now relative links to js/css resources will use the same hostname etc.
  that the main page was requested from, making them work better
  when accessed via multiple IP addresses/hostnames
  without an explicit `--base-url` setting.
  A followup to [#2099], [#2100] and [#2127]. 

- We now require a http[s] scheme in `--base-url`'s value.
  Previously it accepted just a hostname, and generated bad links.


# 1.34 2024-06-01

Features

- You can now get a quick list of example command lines by running with `--tldr` (or just `--tl`).
  For best appearance, install the [`tldr`][tldr] client, though it's not required.

Improvements

- The general flags in `--help` have been updated and grouped,
  consistent with hledger.

- When built with the `ghcdebug` flag and started with `--debug=-1`,
  hledger-web can be controlled by [ghc-debug] clients like
  ghc-debug-brick or a ghc-debug query script, for analysing
  memory/profile info.

Docs

- A basic [OpenAPI specification][openapi.yaml] is provided for hledger-web's JSON-over-HTTP API.
  This is also applicable to `hledger print`'s JSON output format.

[ghc-debug]: https://gitlab.haskell.org/ghc/ghc-debug
[openapi.yaml]: https://github.com/plaintextaccounting/hledger/blob/master/hledger-web/config/openapi.yaml
[tldr]: https://tldr.sh


# 1.33.1 2024-05-02

- Support base64 >=1.0


# 1.33 2024-04-18

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

[#2140]: https://github.com/plaintextaccounting/hledger/issues/2140
[#2163]: https://github.com/plaintextaccounting/hledger/issues/2163
[#2166]: https://github.com/plaintextaccounting/hledger/issues/2166

# 1.32.3 2024-01-28

- Use hledger-1.32.3

# 1.32.2 2023-12-31

Fixes

- The --base-url option works again. [#2127], [#2100]

- Startup messages are more accurate and informative, eg with --socket. [#2127]

- The non-working --file-url option has been dropped for now. [#2139]

Improvements

- Allow megaparsec 9.6

- hledger-web's tests now respect and can test command line options.

- hledger-web's tests now run the app at 127.0.0.1 and port 5000,
  rather than "any of our IPv4 or IPv6 addresses" and 3000,

# 1.32.1 2023-12-07
- Use hledger-1.32.1

# 1.32 2023-12-01

Features

- The hledger-web app on the Sandstorm cloud platform has been updated to
  a recent version (Jacob Weisz, #2102), and now uses Sandstorm's access
  control. (Jakub Zárybnický, #821)

Improvements

- The --capabilities and --capabilities-header options have been replaced
  with an easier `--allow=view|add|edit|sandstorm` option.
  `add` is the default access level, while `sandstorm` is for use on Sandstorm.
  UI and docs now speak of "permissions" rather than "capabilities".
  (#834)

- The Sandstorm app's permissions and roles have been renamed for clarity. (#834)

- Permissions are now checked earlier, before the web app is started,
  producing clearer command line errors when appropriate.

- Account's `adeclarationinfo` field is now included in JSON output. (#2097) (S. Zeid)

Fixes

- The app can now serve on address 0.0.0.0 (exposing it on all interfaces),
  which previously didn't work.
  (#2099) (Philipp Klocke)

- The broken "File format help" link in the edit form has been fixed. (#2103)

# 1.31 2023-09-03

Improvements

- Allow aeson 2.2, megaparsec 9.5

# 1.30 2023-06-01

Fixes

- A command line depth limit now works properly.
  (#1763)

Docs

- Miscellaneous manual cleanups.

# 1.29.2 2023-04-07

Improvements

- A pager is used to show --help output when needed, as in `hledger`.

Fixes

- The corruption in 1.29's info manual is fixed. (#2023)

# 1.29.1 2023-03-16

- Allow building with GHC 9.6.1 (#2011)

# 1.29 2023-03-11

- The add form's typeahead now shows non-ascii text correctly.
  (#1961) (Arsen Arsenović)

- In the manual, improve --base-url's description. (#1562)

# 1.28 2022-12-01

Improvements

- --debug with no argument is now equivalent to --debug=1.

- Allow megaparsec 9.3 (Felix Yan)

- Support GHC 9.4

# 1.27.1 2022-09-18

Fixes

- The add form no longer gives an error when there is just a single file and no file field showing. (#1932)

# 1.27 2022-09-01

Improvements

- Improve the add form's layout and space usage.

- Pre-fill the add form's date field.

- Highlight today in the add form's date picker.

- Focus the add form's description field by default.

- Allow an empty description in the add form.

- Use hledger 1.27

Fixes

- Respect the add form's file selector again.
  (Simon Michael, Kerstin, #1229)

# 1.26.1 2022-07-11

- Uses hledger 1.26.1.

# 1.26 2022-06-04

Fixes

- Don't add link URLs when printing.

Improvements

- Now builds with GHC 9.2.

- Uses hledger 1.26.

# 1.25 2022-03-04

- Uses hledger 1.25.

# 1.24.1 2021-12-10

Fixes

- More reliable --version output, with commit date and without patch level.

# 1.24 2021-12-01

Improvements

- Allow megaparsec 9.2


# 1.23 2021-09-21

Improvements

- Drop the obsolete hidden `--binary-filename` flag.

- Require base >=4.11, preventing red squares on Hackage's build matrix.

Fixes

- Toggle showing zero items properly even when called with --empty. 
  ([#1237](https://github.com/plaintextaccounting/hledger/issues/1237), Stephen Morgan)

- Do not hide empty accounts if they have non-empty subaccounts. 
  ([#1237](https://github.com/plaintextaccounting/hledger/issues/1237), Stephen Morgan)

- Allow unbalanced postings (parenthesised account name) in the add transaction form. 
  ([#1058](https://github.com/plaintextaccounting/hledger/issues/1058), Stephen Morgan)

- An XSS (cross-site scripting) vulnerability has been fixed.
  Previously (since hledger-web 0.24), javascript code could be added 
  to any autocompleteable field and could be executed automatically 
  by subsequent visitors viewing the journal.
  Thanks to Gaspard Baye and Hamidullah Muslih for reporting this vulnerability.
  ([#1525](https://github.com/plaintextaccounting/hledger/issues/1525), Arsen Arsenović)

API changes

- Renamed:
  ```
  version -> packageversion
  versiondescription -> versionStringFor
  ```

# 1.22.2 2021-08-07

- Use hledger 1.22.2.

# 1.22.1 2021-08-02

Improvements

- deps: Allow megaparsec 9.1.

Fixes

- The register chart works again when there are multiple commodities and 
  transaction prices (broken since 1.22). (#1597, Stephen Morgan)

# 1.22 2021-07-03

Improvements

- The --version flag shows more detail (git tag/patchlevel/commit
  hash, platform/architecture). (Stephen Morgan)

- Allow yesod-form 1.7 (Felix Yan)

- Add now-required lower bound on containers. (#1514)

- GHC 9.0 is now officially supported, and GHC 8.0, 8.2, 8.4 are not;
  building hledger now requires GHC 8.6 or greater.

Fixes

- In the add form, fix a bug where extra posting rows were not added
  when needed in certain web browsers. (charukiewicz)

# 1.21 2021-03-10

- Register: a date range can be selected by dragging over a region on
  the chart. (Arnout Engelen, #1471)

- Add form: the description field's autocompletions now also offer
  declared and used payee names.

- New flags `--man` and `--info` open the man page or info manual.
  (See hledger changelog)

# 1.20.4 2021-01-29

- Use hledger 1.20.4.

# 1.20.3 2021-01-14

- Use hledger 1.20.3.

# 1.20.2 2020-12-28

- Fix the info manual's node structure.

- Use hledger 1.20.2.

# 1.20.1 2020-12-06

- don't hang when reloading the journal, eg after adding a transaction
  or editing the file. (#1409)

# 1.20 2020-12-05

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

# 1.19.1 2020-09-07

- Allow megaparsec 9

- Drop redundant semigroups dependency (Felix Yan)

# 1.19 2020-09-01

- Queries containing a malformed regular expression (eg the single
  character `?`) now show a tidy error message instead "internal
  server error" (Stephen Morgan, Simon Michael) (#1245)

- In account registers, a transaction dated outside the report period
  now is not shown even if it has postings dated inside the report
  period.

- Added a missing lower bound for aeson, making cabal installs more
  reliable. (#1268)

# 1.18.1 2020-06-21

- fix some doc typos (Martin Michlmayr)

# 1.18 2020-06-07

- The filter query is now preserved when clicking a different account
  in the sidebar. (Henning Thielemann)

- Hyperlinks are now more robust when there are multiple journal
  files, eg links from register to journal now work properly.
  (#1041) (Henning Thielemann)

## add form

- Fixed a 2016 regression causing too many rows to be added by
  keypresses in the last amount field or CTRL-plus (#422, #1059).

- Always start with four rows when opened.

- Drop unneeded C-minus/C-plus keys & related help text.


# 1.17.1 2020-03-19

- require newer Decimal, math-functions libs to ensure consistent
  rounding behaviour, even when built with old GHCs/snapshots. 
  hledger uses banker's rounding (rounds to nearest even number, eg
  0.5 displayed with zero decimal places is "0").

# 1.17 2020-03-01

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
  since the later can sometimes contain 255-digit integers. The
  floating point numbers can have up to 10 decimal digits (and an
  unbounded number of integer digits.)
  Experimental, suggestions needed. (#1195)


# 1.16.2 2020-01-14

- add support for megaparsec 8 (#1175)

- fix add form completions (#1156)

# 1.16.1 2019-12-03

- Drop unnecessary json (#1190), mtl-compat dependencies

- use hledger 1.16.1, fixing GHC 8.0/8.2 build

# 1.16 2019-12-01

- add support for GHC 8.8, base-compat 0.11 (#1090).
  For now, hledger-web needs an unreleased version of json.

- drop support for GHC 7.10

- Weeks in the add form's date picker now start on Mondays (#1109)
  (Timofey Zakrevskiy)

- The --cors option allows simple cross-origin requests to hledger-web
  (Alejandro García Montoro)

- The test suite has been disabled for now.

# 1.15 2019-09-01

- --serve-api disables the usual server-side web UI (leaving only the API routes)

- register page: account names are hyperlinked

- ?sidebar= now hides the sidebar, same as ?sidebar=0

- fix "_create_locale could not be located" error on windows 7 (#1039)

- use hledger 1.15

# 1.14.1 2019-03-20

- /accounts JSON: return all accounts, not just top-level ones (#985)
  Accounts are returned as a flat list, in tree order, with asubs fields empty.

- use hledger 1.14.2

# 1.14 2019-03-01

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

- manual updates: document --capabilities/--capabilities-header and
  editing/uploading/downloading.

- use hledger 1.14

# 1.13 (2019/02/01)

- use hledger 1.13

# 1.12 (2018/12/02)

-   fix duplicate package.yaml keys warned about by hpack

-   use hledger 1.12

# 1.11.1 (2018/10/06)

-   use hledger 1.11.1

# 1.11 (2018/9/30)

-   use hledger 1.11

# 1.10 (2018/6/30)

-   multiple -f options, and --auto, work again

-   view, add, edit permissions can be set at CLI or by Sandstorm HTTP header

-   the edit form has been revived, for whole-journal editing

-   the journal can now be uploaded and downloaded

-   the e key toggles empty accounts in the sidebar

-   use hledger-lib 1.10

# 1.9.2 (2018/4/30)

-   use hledger-lib 1.9.1

# 1.9.1 (2018/4/13)

-   fix compilation with yesod < 1.6

# 1.9 (2018/3/31)

-   support ghc 8.4, latest deps

-   when the system text encoding is UTF-8, ignore any UTF-8 BOM prefix
    found when reading files

-   -E/--empty toggles zeroes at startup (with opposite default to cli)

# 1.5 (2017/12/31)

-   add form account fields now suggest implied and declared account names also

-   add form date field now uses a datepicker (Eli Flanagan)

-   don't write a session file at startup, don't require a writable working directory

-   support -V/--value, --forecast, --auto

-   remove upper bounds on all but hledger* and base (experimental)

# 1.4 (2017/9/30)

-   a @FILE argument reads flags & args from FILE, one per line

-   enable --pivot and --anon options, like hledger CLI (#474) (Jakub Zárybnický)

-   web: Make "Add transaction" button tabbable (#430) (Jakub Zárybnický)

-   accept -NUM as a shortcut for --depth NUM

-   deps: drop oldtime flag, require time 1.5+, remove ghc < 7.6 support

# 1.3.2 (2017/8/25)

-   remove unnecessary bound to satisfy hackage server

# 1.3.1 (2017/8/25)

-   allow megaparsec 6 (#594, Simon Michael, Hans-Peter Deifel)

-   allow megaparsec-6.1 (Hans-Peter Deifel)

-   restore upper bounds on hledger packages

# 1.3 (2017/6/30)

Depends on hledger\[-lib\] 1.3, see related changelogs.

# 1.2 (2017/3/31)

Accounts with ? in name had empty registers (fixes #498) (Bryan Richter)

Allow megaparsec 5.2 (fixes #503)

# 1.1 (2016/12/31)

-   add --host option (#429)

    This came up in the context of Docker, but it seems it wasn't
    possible for hledger-web to serve remote clients directly (without
    a proxy) because of 127.0.0.1 being hardcoded. That can now be
    changed with --host=IPADDR. Also, the default base url uses this
    address rather than a hard-coded "localhost".

-   rename --server to --serve

    The --server flag sounded too close in meaning to --host so
    I've renamed it to --serve. The old spelling is still accepted,
    but deprecated and will be removed in the next release.

# 1.0.1 (2016/10/27)

-   allow megaparsec 5.0 or 5.1

# 1.0 (2016/10/26)

## ui

-   use full width on large screens, hide sidebar on small screens, more standard bootstrap styling (#418, #422) (Dominik Süß)

-   show the sidebar by default (#310)

-   fix the add link's tooltip

-   when the add form opens, focus the first field (#338)

-   leave the add form's date field blank, avoiding a problem with tab clearing it (#322)

-   use transaction id instead of date in transaction urls (#308) (Thomas R. Koll)

-   after following a link to a transaction, highlight it (Thomas R. Koll)

-   misc. HTML/CSS/file cleanups/fixes (Thomas R. Koll)

## misc

-   startup is more robust (#226).

    Now we exit if something is already using the specified port,
    and we don't open a browser page before the app is ready.

-   termination is more robust, avoiding stray background threads.

    We terminate the server thread more carefully on exit, eg on control-C in GHCI.

-   more robust register dates and filtering in some situations (see hledger-ui notes)

-   reloading the journal preserves options, arguments in effect (#314).

    The initial query specified by command line arguments is now preserved
    when the journal is reloaded. This does not appear in the web UI, it's
    like an invisible extra filter.

-   show a proper not found page on 404

-   document the special \`inacct:\` query (#390)

0.27 (2015/10/30)

-   Fix keyboard shortcut for adding a transaction (Carlos Lopez-Camey)

-   Clear the form when clicking 'Add a transaction' (just like the shortcut) (Carlos Lopez-Camey)

-   Disallow -f- (reading from standard input) which currently doesn't work (#202)

-   Fix broken links when using --base-url (#235)

-   Fix the --file-url option (#285)

-   Show fewer "other accounts" in the account register: to reduce
    clutter in the "other accounts" field, if there are both real and
    virtual postings to other accounts, show only the accounts posted to
    by real postings.

0.26 (2015/7/12)

-   make the j keybinding respect --base-url (fixes #271)
-   respect command line options (fixes #225)
-   include the unminified jquery source again (#161)
-   fix build breakage from #165 (fixes #268)
-   fix a js error breaking add form in browsers other than firefox (#251, Carlos Lopez-Camey <c.lopez@kmels.net>)
-   drop deprecated network-conduit dependency

0.25 (2015/4/7)

-   GHC 7.10 compatibility (#239)

-   fix the add form when there are included files (#234)

    NB to make this work, the add form now shows the full file path of
    the main and included journal files.

-   improve add form validation (#223, #234)

    All add form errors are displayed as form errors, not internal
    server errors, and when there are errors the add form is redisplayed
    (form inputs are not preserved, currently).

-   keep the add button right-aligned when pressing ctrl - on the add form

0.24.1 (2015/1/10)

-   add missing modules to fix cabal tests (#232)

0.24 (2014/12/25)

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
- parses data more strictly and gives better errors (eg #194)
- allows any number of postings, not just two
- after adding a transaction, goes back to the journal
- keyboard shortcut (a) allows quick access

Dependencies:
- allow warp 3*, wai-handler-launch 3*
- require yesod 1.4* (fixes #212)
- js updated (jquery, bootstrap, flot), added (typeahead, cookie, hotkeys),
removed (select2)

0.23.3 (2014/9/12)

-   remove warp, wai-handler-launch upper bounds (fixes #205)

0.23.2 (2014/5/8)

-   depend on latest hledger

0.23.1 (2014/5/7)

-   depend on latest hledger

0.23 (2014/5/1)

-   The --static-root flag has been renamed to --file-url.
-   hledger-web now builds with Cabal's default -O, not -O2,
    so may be a little quicker/less memory-hungry to install.

0.22.8 (2014/4/29)

-   allow shakespeare 2.* (#179)

0.22.7 (2014/4/17)

-   add Peter Simons' patch fixing Data.Conduit.Network HostIPv4 error (#171)

0.22.6 (2014/4/16)

-   depend on hledger\[-lib\] 0.22.2

0.22.5 (2014/4/15)

-   allow http-client 0.3.*, fixing cabal install again with GHC <= 7.6 (not yet 7.8)
-   use pretty-show only with GHC 7.4+, fixing GHC 7.2 (fixes #155)
-   allow warp 2.1, fixing cabal install

0.22.4 (2014/2/10)

-   Fix: include the right unminified version of jquery.url.js (1.1) to avoid js breakage

0.22.3 (2014/2/10)

-   Fix: version number reported by --version

0.22.2 (2014/2/10)

-   new option --static-root to set the base url for static files
-   allow blaze-html 0.7 (#159)
-   Fix: include unminified source of all javascript to help packagers (#161)
-   Fix: work around clang-related build failures with OS X mavericks/XCode 5

0.22.1 (2014/1/6) and older

See http://hledger.org/release-notes or doc/RELNOTES.md.
