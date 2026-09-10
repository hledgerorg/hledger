<!--
       _
 _   _(_)
| | | | |
| |_| | |
 \__,_|_|

Breaking changes

Fixes

Features

Improvements

Docs

API

-->

User-visible changes in hledger-ui.
See also the hledger changelog.


# 1.52.4 2026-09-10

Improvements

- Allow megaparsec 9.8.1+ (but not 9.8.0, because of [megaparsec#572](https://github.com/mrkkrp/megaparsec/issues/572)).


# 1.52.3 2026-08-27



# 1.52.2 2026-08-24



# 1.52.1 2026-04-28

Improvements

- Uses hledger 1.52.1.

- Allow vty-crossplatform 0.5.


# 1.52 2026-03-20

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


# 1.51.2 2026-01-08

- hledger add invoked via the `a` key now shows output properly,
  fixing a regression in 1.50. [#2512]

- Allow vty-crossplatform 0.5. (Jens Petersen)

- Allow base 4.22 / ghc 9.14.

[#2512]: https://github.com/simonmichael/hledger/issues/2512


# 1.51.1 2025-12-08

- Uses hledger 1.51.1.


# 1.51 2025-12-05

Improvements

- Allow brick 2.10, vty 6.5.

- Uses hledger 1.51.


# 1.50.5 2025-12-08

- Uses hledger 1.50.5.


# 1.50.4 2025-12-04

- Uses hledger 1.50.4.


# 1.50.3 2025-11-18

- `--watch` mode now also detects changes from apps which overwrite the file, such as VS Code.
  (Caleb Maclennan)

- When hledger-ui is started with --pivot, re-enabling balance assertions
  with the I key now does a full journal reload, to check assertions more accurately.
  [#2451]

- The old "threaded" build flag, which cabal could turn off, has been dropped.
  [#2495]

- Allow brick 2.10, vty 6.5.

- Uses hledger 1.50.3.


# 1.50.2 2025-09-26

- Uses hledger 1.50.2


# 1.50.1 2025-09-16

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

API

- Hledger.UI.ErrorScreen:
  uiReloadJournal -> uiReload,
  uiReloadJournalIfChanged -> uiReloadIfFileChanged
- Hledger.UI.UIState:
  enableForecastPreservingPeriod -> enableForecast

[#2014]: https://github.com/simonmichael/hledger/issues/2014
[#2288]: https://github.com/simonmichael/hledger/issues/2288
[#2451]: https://github.com/simonmichael/hledger/issues/2451
[#2454]: https://github.com/simonmichael/hledger/issues/2454


# 1.50 2025-09-03

Breaking changes

- hledger now requires at least GHC 9.6 (and base 4.18), to ease maintenance.

Improvements

- Use hledger 1.50


# 1.43.2 2025-06-13

- Use hledger-1.43.2


# 1.43.1 2025-06-04

- More error messages were made consistent, hiding call stack etc. [#2367]

- Allow brick 2.9


# 1.43 2025-06-01

Fixes

- Require fsnotify >=0.4.2.0, which fixes some events being ignored on mac,
  possibly making hledger-ui --watch more reliable in this regard.

Improvements

- CLI error messages now have consistent clean format independent of GHC version. [#2367]

- Support GHC 9.12.

Docs

- Update --watch docs.
- Drop obsolete mention of Windows non-support.


# 1.42.2 2025-05-16

Fixes

- Require fsnotify-0.4.2.0+/hfsevents-0.1.8+, which fixes some events
  being ignored on mac (see https://github.com/luite/hfsevents/pull/19),
  which should help `hledger-ui --watch` a little.

- Require extra >= 1.7.11, fixing the stack8.10.yaml build. (Thomas Miedema)

Docs

- Update --watch notes
- Drop obsolete Windows non-support note


# 1.42.1 2025-03-12

- allow vty 6.4


# 1.42 2025-03-07

Fixes

- Startup arguments provided at the CLI are no longer passed to `add` when pressing the `a` key. [#2313]

Improvements

- Allow vty 6.3.
- Allow brick 2.8.


# 1.41 2024-12-09

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

- Added --pager and --color options as in hledger, affecting command line help.
  Also --color=no forces use of the "terminal" theme.

- Added a new `debug` build flag. Builds made with ghc 9.10+ and this flag
  will show some kind of partial stack trace if the program exits with an error.
  These will improve in future ghc versions.

- Disabled the unused `ghcdebug` build flag and ghc-debug support, for now.

- Allow megaparsec 9.7.

- Allow brick 2.5, 2.6.

- Avoid brick 2.3.2, which doesn't build on windows.

- ghc 9.10 / base 4.20 are now supported.

Docs

- Mention that period navigation uses standard periods [#2293]
- Install, manual: new shell completions doc. [#986]



# 1.40 2024-09-09

Improvements

- The menu screen now supports the shift arrow and shift T keys,
  and its header shows any narrowed time period in effect, like other screens.

- Support brick 2.4.

Docs

- The description of the shift-T key (set period to today) has been fixed.
- The shift arrow keys and period narrowing have been clarified


# 1.34 2024-06-01

Features

- You can now get a quick list of example command lines by running with `--tldr` (or just `--tl`).
  For best appearance, install the [`tldr`][tldr] client, though it's not required.

Improvements

- The general flags in `--help` have been updated and grouped,
  consistent with hledger.

- When built with the `ghcdebug` flag and started with `--debug=-1`,
  hledger-ui can be controlled by [ghc-debug] clients like
  ghc-debug-brick or a ghc-debug query script, for analysing
  memory/profile info.

[tldr]: https://tldr.sh
[ghc-debug]: https://gitlab.haskell.org/ghc/ghc-debug


# 1.33.1 2024-05-02

- Require vty-windows-0.2.0.2+ to avoid display problems in recent
  MS Terminal on Windows.

- We no longer require process >=1.6.19.0, as it hurt installability
  and seems not strictly needed.
  [#2149]

[#2149]: https://github.com/simonmichael/hledger/issues/2149


# 1.33 2024-04-18

Fixes

- Require process 1.6.19.0+ to avoid any vulnerabilities on Windows from
  [HSEC-2024-0003](https://haskell.github.io/security-advisories/advisory/HSEC-2024-0003.html).

Features

- Add a `dark` theme. (Jonathan Dowland)

Improvements

- Allow building with GHC 9.8.

- Require safe >=0.3.20.

# 1.32.3 2024-01-28

- Use hledger-1.32.3

- Allow vty 6.2, brick 2.3

# 1.32.2 2023-12-31

Features

- hledger-ui is now available on Windows (ShrykeWindgrace)

Improvements

- Use Notepad as default editor on Windows (ShrykeWindgrace)

- Allow brick 2.2 (Vekhir)

- Allow megaparsec 9.6

# 1.32.1 2023-12-07
- Use hledger-1.32.1

# 1.32 2023-12-01

Fixes

- The V key now preserves the valuation mode specified at the command
  line, if any. (#2084)

- The hledger-ui package no longer wastefully builds its modules
  twice.

- Add upper bounds for vty & brick.

# 1.31 2023-09-03

Improvements

- Allow megaparsec 9.5

# 1.30 2023-06-01

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

# 1.29.2 2023-04-07

Improvements

- A pager is used to show --help output when needed, as in `hledger`.

Fixes

- The corruption in 1.29's info manual is fixed. (#2023)

# 1.29.1 2023-03-16

- Allow building with GHC 9.6.1 (#2011)

# 1.29 2023-03-11

- In the help dialog, mention that LEFT shows other screens.

- In the manual, mention shift-up/down config needed for Terminal.app.

# 1.28 2022-12-01

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
  back. It was too obtrusive, eg when you just want to focus the window. You can still navigate back with the mouse by clicking the left edge of the window.

- A possible bug with detecting change of date while in --watch mode has been fixed.

API

- hledger-ui's internal types have been changed to allow fewer invalid states and make it easier  to develop and debug.
  (#1889, #1919).

- Debug logging helpers have been added and cleaned up in Hledger.Ui.UIUtils:
  dbgui
  dbguiIO
  dbguiEv
  dbguiScreensEv
  mapScreens
  screenId
  screenRegisterDescriptions

# 1.27.1 2022-09-18

- Uses hledger-1.27.1

# 1.27 2022-09-01

Improvements

- At --debug=2 and up, log debug output to ./debug.log.

- Use/require brick 1.0+. (#1889)

- Use hledger 1.27

# 1.26.1 2022-07-11

- support doclayout 0.4, brick 0.72+

- require safe 0.3.19+ to avoid deprecation warning

# 1.26 2022-06-04

- Uses hledger 1.26.

# 1.25 2022-03-04

- Uses hledger 1.25.

# 1.24.1 2021-12-10

Fixes

- An extra "root" account is no longer shown (a regression in 1.24).
  (#1782)

- Declared accounts are now filtered correctly by a not:ACCT query.
  (#1783)

- More reliable --version output, with commit date and without patch level.

# 1.24 2021-12-01

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
  (#1394, Stephen Morgan)

- Entering the register screen now always positions the selection mid-screen.
  Previously it would be at bottom of screen on the first entry.

- Report layout in the terminal is now robust with more kinds of wide
  characters, such as emoji.
  (#895, Stephen Morgan)
  
  
  


# 1.23 2021-09-21

Improvements

- Require base >=4.11, prevent red squares on Hackage's build matrix.

Fixes

- Do not display a screen full of .. when there are no transactions. (#822)

API changes

- Lenses are now available for UIState etc., saving a lot of boilerplate. (Stephen Morgan)

- Renamed:
  ```
  version -> packageversion
  versiondescription -> versionStringFor
  UIOpts fields
  ```

# 1.22.2 2021-08-07

- Use hledger 1.22.2.

# 1.22.1 2021-08-02

Improvements

- Document watch mode and its limitations. (#1617, #911, #836)

- Allow megaparsec 9.1.

Fixes

- Up/down keys work on the transaction screen again (broken since 1.22). 
  (#1607, Stephen Morgan)

- Fix a possible off-by-one bug with valuation date when using `V` key on
  the transaction screen. (If it ever needs to use the journal's last day
  as valuation date, use that day, not the day after.)

# 1.22 2021-07-03

Improvements

- Don't reset the `B`/`V` (cost, value) state when reloading with `g`
  or `--watch`. (Stephen Morgan)

- The accounts screen is a little smarter at allocating space to
  columns. (Stephen Morgan)

- Add support for the kakoune editor, and improve the invocations of
  some other editors. (crocket)

- The `--version` flag shows more detail (git tag/patchlevel/commit
  hash, platform/architecture). (Stephen Morgan)

- GHC 9.0 is now officially supported, and GHC 8.0, 8.2, 8.4 are not;
  building hledger now requires GHC 8.6 or greater.

- Added a now-required lower bound on containers. (#1514)

Fixes

- Queries in the register screen work again (broken in 1.21). (#1523)
  (Stephen Morgan)

- Don't write to `./debug.log` when toggling value with `V`, or when
  reloading with `g` or `--watch` in the Transaction screen. (#1556)
  (Simon Michael, Stephen Morgan)

# 1.21 2021-03-10

- Register screen: also show transactions below the depth limit, as in
  1.19, keeping the register balance in agreement with the balance
  shown on the accounts screen. This regressed in 1.20. (#1468)

- Transaction screen: all decimal places are now shown. On the
  accounts screen and register screen we round amounts according to
  commodity display styles, but when you drill down to a transaction
  you probably want to see the unrounded amounts. (Like print, #cf
  931.)

- New flags `--man` and `--info` open the man page or info manual.
  (See hledger changelog)

# 1.20.4 2021-01-29

- ui: register: show all txns in/under an account at the depth limit (#1468).
  In 1.20-1.20.3, the register screen had stopped showing transactions 
  in accounts below a depth limit. Now it properly shows all subaccount transactions,
  even when there is a depth limit, ensuring that the register's final total 
  matches the balance shown on the account screen.

# 1.20.3 2021-01-14

- Use hledger 1.20.3.

# 1.20.2 2020-12-28

- Fix loss of capitalisation in part of the manual. 

- Fix the info manual's node structure.

- Use hledger 1.20.2.

# 1.20.1 2020-12-15

- Fix the F key (toggle future/forecast transactions), which in 1.20 
  would only work twice. (#1411)

- Fix loss of forecasted transactions when the journal was reloaded
  while they were hidden. (#1204)

# 1.20 2020-12-05

- When entering a query with `/`, malformed queries/regular expressions
  no longer cause the program to exit. (Stephen Morgan)

- Eliding of multicommodity amounts now makes better use of available space. (Stephen Morgan)

- `E` now parses the `HLEDGER_UI_EDITOR` or `EDITOR` environment variable
  correctly on Windows (ignoring the file extension), so if you have that set
  it should be better at opening your editor at the correct line.

- `E` now supports positioning when `HLEDGER_UI_EDITOR` or `EDITOR` 
  is VS Code ("`code`") (#1359)

- hledger-ui now has a (human-powered) test suite.


# 1.19.1 2020-09-07

- Allow megaparsec 9

# 1.19 2020-09-01

- The --color/--colour=WHEN command line option, support for the
  NO_COLOR environment variable, and smarter autodetection of colour
  terminals have been added (#1296)

- -t and -l command line flags have been added as short forms of
  --tree and --flat (#1286)

- Flat (AKA list) mode is now the default

- t now toggles tree mode, while T sets the "today" period (#1286)

- register: multicommodity amounts containing more than two
  commodities are now elided

- register: a transaction dated outside the report period now is not
  shown even if it has postings dated inside the report period.

- ESC now restores exactly the app's state at startup, which includes
  clearing any report period limit (#1286)

- DEL/BS no longer changes the tree/list mode

- q now exits help before exiting the app (#1286)

- The help dialog's layout is improved

# 1.18.1 2020-06-21

- Fix regression in 'F' (#1255) (Dmitry Astapov)

# 1.18 2020-06-07

- builds with hledger 1.18

# 1.17.1.1 2020-03-19

- update bounds after some belated hledger-* version bumps

# 1.17.1 2020-03-19

- fix a regression, empty register of depth-limited account (fix #1208)

- require newer Decimal, math-functions libs to ensure consistent
  rounding behaviour, even when built with old GHCs/snapshots. 
  hledger uses banker's rounding (rounds to nearest even number, eg
  0.5 displayed with zero decimal places is "0").

# 1.17 2020-03-01

- don't enable --auto by default

- don't enable --forecast by default; drop the --future flag (#1193)

  Previously, periodic transactions occurring today were always shown,
  in both "present" and "future" modes.

  Now, generation of periodic transactions and display of future
  transactions (all kinds) are combined as "forecast mode", which can
  be enabled with --forecast and/or the F key.  The --future flag is
  now a hidden alias for --forecast, and deprecated.

# 1.16.2 2020-01-14

- add support for megaparsec 8 (#1175)

# 1.16.1 2019-12-03

- use hledger 1.16.1, fixing GHC 8.0/8.2 build

# 1.16 2019-12-01

- add support for GHC 8.8, base-compat 0.11 (#1090)

- drop support for GHC 7.10

- the B and V keys toggle cost or value display (like the -B and -V
  command line flags)

# 1.15 2019-09-01

- allow brick >=0.47

- use hledger 1.15

# 1.14.2 2019-03-20

- support brick 0.47+ as well, to get into stackage nightly.

# 1.14.1 2019-03-20

- require brick <0.47 to fix build (#995)

- use hledger 1.14.2

# 1.14 2019-03-01

- use hledger 1.14

# 1.13.1 (2019/02/02)

- fix build issues with older brick/stack resolvers; require brick 0.23+

# 1.13 (2019/02/01)

- on posix systems, control-z suspends the program

- control-l now works everywhere and redraws more reliably

- the top status info is clearer

- use hledger 1.13

# 1.12.1 (2018/12/10)

-   avoid build issue with brick 0.44+ (#935)

# 1.12 (2018/12/02)

-   fix "Any" build error with GHC < 8.4

-   error screen: always show error position properly (#904) (Mykola Orliuk)

-   accounts screen: show correct balances when there's only periodic transactions

-   drop the --status-toggles flag

-   periodic transactions and transaction modifiers are always enabled.
    Rule-based transactions and postings are always generated
    (--forecast and --auto are always on).
    Experimental.

-   escape key resets to flat mode.
    Flat mode is the default at startup. Probably it should reset to tree
    mode if --tree was used at startup.

-   tree mode tweaks: add --tree/-T/-F flags, make flat mode the default,\
    toggle tree mode with T, ensure a visible effect on register screen

-   hide future txns by default, add --future flag, toggle with F.
    You may have transactions dated later than today, perhaps piped from
    print --forecast or recorded in the journal, which you don't want to
    see except when forecasting.

    By default, we now hide future transactions, showing "today's balance".
    This can be toggled with the F key, which is easier than setting a
    date query. --present and --future flags have been added to set the
    initial mode.

    (Experimental. Interactions with date queries have not been explored.)

-   quick help tweaks; try to show most useful info first

-   reorganise help dialog, fit content into 80x25 again

-   styling tweaks; cyan/blue -> white/yellow

-   less noisy styling in horizontal borders (#838)

-   register screen: positive amounts: green -> black
    The green/red scheme helped distinguish the changes column from the
    black/red balance column, but the default green is hard to read on
    the pale background in some terminals. Also the changes column is
    non-bold now.

-   use hledger 1.12

# 1.11.1 (2018/10/06)

-   use hledger 1.11.1

# 1.11 (2018/9/30)

-   use hledger 1.11

# 1.10.1 (2018/7/3)

-   restore support for fsnotify 0.2.1.2, as well as 0.3.x (#833)

-   fix a vty version bound & possibly build failures with old vty (#494)

# 1.10 (2018/6/30)

-   the effect of --value, --forecast, and --anon flags is now preserved on reload (#753)

-   edit-at-transaction-position is now also supported when $EDITOR is neovim

-   support/require fsnotify 0.3.0.1+

-   use hledger-lib 1.10

# 1.9.1 (2018/4/30)

-   use hledger-lib 1.9.1

# 1.9 (2018/3/31)

-   support ghc 8.4, latest deps

-   when the system text encoding is UTF-8, ignore any UTF-8 BOM prefix
    found when reading files

-   -E/--empty toggles zeroes at startup (with opposite default to cli)

# 1.5 (2017/12/31)

-   fix help -> view manual (on posix platforms) #623

-   support -V/--value, --forecast, --auto

-   remove upper bounds on all but hledger* and base (experimental)

# 1.4 (2017/9/30)

-   a @FILE argument reads flags & args from FILE, one per line

-   enable --pivot and --anon options, like hledger CLI (#474) (Jakub Zárybnický)

-   accept -NUM as a shortcut for --depth NUM

-   deps: allow ansi-terminal 0.7

-   deps: drop oldtime flag, require time 1.5+

# 1.3.1 (2017/8/25)

-   allow megaparsec 6 (#594, Simon Michael, Hans-Peter Deifel)

-   allow megaparsec-6.1 (Hans-Peter Deifel)

-   allow vty 5.17 (Felix Yan)

-   allow brick 0.24

-   restore upper bounds on hledger packages

# 1.3 (2017/6/30)

The register screen now shows transaction status marks.

The "uncleared" status, and associated UI flags and keys, have been
renamed to "unmarked" to remove ambiguity and confusion. This means
that we have dropped the `--uncleared` flag, and our `-U` flag now
matches only unmarked things and not pending ones. See the issue and
linked mail list discussion for more background. (#564)

The P key toggles pending mode, consistent with U (unmarked) and C
(cleared). There is also a temporary --status-toggles flag for testing
other toggle styles; see `hledger-ui -h`. (#564)

There is now less "warping" of selection when lists change:

-   When the selected account disappears, eg when toggling zero
    accounts, the selection moves to the alphabetically preceding item,
    instead of the first one.

-   When the selected transaction disappears, eg when toggling status
    filters, the selection moves to the nearest transaction by date (and
    if several have the same date, by journal order), instead of the
    last one.

In the accounts and register screens, you can now scroll down further
so that the last item need not always be shown at the bottom of the
screen. And we now try to show the selected item centered in the
following situations:

-   after moving to the end with Page down/End
-   after toggling filters (status, real, historical..)
-   on pressing the control-l key (should force a screen redraw, also)
-   on entering the register screen from the accounts screen (there's a
    known problem with this: it doesn't work the first time).

(Items near the top can't be centered, as we don't scroll higher than
the top of the list.)

Emacs movement keys are now supported, as well as VI keys.
hjkl and CTRL-bfnp should work wherever unmodified arrow keys work.

In the transaction screen, amounts are now better aligned, eg when
there are posting status marks or virtual postings.

Deps: allow brick 0.19 (#575, Felix Yan, Simon Michael)

# 1.2 (2017/3/31)

Fix a pattern match failure when pressing E on the transaction screen (fixes #508)

Accounts with ? in name had empty registers (fixes #498) (Bryan Richter)

Allow brick 0.16 (Joshua Chia) and brick 0.17/vty 0.15 (Peter Simons)

Allow megaparsec 5.2 (fixes #503)

Allow text-zipper 0.10

# 1.1.1 (2017/1/20)

-   allow brick 0.16 (Joshua Chia)

-   drop obsolete --no-elide flag

# 1.1 (2016/12/31)

-   with --watch, the display updates automatically to show file or date changes

    hledger-ui --watch will reload data when the journal file (or any included file) changes.
    Also, when viewing a current standard period (ie this day/week/month/quarter/year),
    the period will move as needed to track the current system date.

-   the --change flag shows period changes at startup instead of historical ending balances

-   the A key runs the hledger-iadd tool, if installed

-   always reload when g is pressed

    Previously it would check the modification time and reload only if
    it looked newer than the last reload.

-   mark hledger-ui as "stable"

-   allow brick 0.15, vty 5.14, text-zipper 0.9

# 1.0.4 (2016/11/2)

-   allow brick 0.13

# 1.0.3 (2016/10/31)

-   use brick 0.12

# 1.0.2 (2016/10/27)

-   use latest brick 0.11

# 1.0.1 (2016/10/27)

-   allow megaparsec 5.0 or 5.1

# 1.0 (2016/10/26)

## accounts screen

-   at depth 0, show accounts on one "All" line and show all transactions in the register

-   0 now sets depth limit to 0 instead of clearing it

-   always use --no-elide for a more regular accounts tree

## register screen

-   registers can now include/exclude subaccount transactions.

    The register screen now includes subaccounts' transactions if the
    accounts screen was in tree mode, or when showing an account
    which was at the depth limit. Ie, it always shows the
    transactions contributing to the balance displayed on the
    accounts screen. As on the accounts screen, F toggles between
    tree mode/subaccount txns included by default and flat
    mode/subaccount txns excluded by default. (At least, it does when
    it would make a difference.)

-   register transactions are filtered by realness and status (#354).

    Two fixes for the account transactions report when --real/--cleared/real:/status:
    are in effect, affecting hledger-ui and hledger-web:

    1.  exclude transactions which affect the current account via an excluded posting type.
        Eg when --real is in effect, a transaction posting to the current account with only
        virtual postings will not appear in the report.

    2.  when showing historical balances, don't count excluded posting types in the
        starting balance. Eg with --real, the starting balance will be the sum of only the
        non-virtual prior postings.

        This is complicated and there might be some ways to confuse it still, causing
        wrongly included/excluded transactions or wrong historical balances/running totals
        (transactions with both real and virtual postings to the current account, perhaps ?)

-   show more accurate dates when postings have their own dates.

    If postings to the register account matched by the register's
    filter query have their own dates, we show the earliest of these
    as the transaction date.

## misc

-   H toggles between showing "historical" or "period" balances (#392).

    By default hledger-ui now shows historical balances, which
    include transactions before the report start date (like hledger
    balance --historical). Use the H key to toggle to "period" mode,
    where balances start from 0 on the report start date.

-   shift arrow keys allow quick period browsing

    -   shift-down narrows to the next smaller standard period
        (year/quarter/month/week/day), shift-up does the reverse
    -   when narrowed to a standard period, shift-right/left moves to
        the next/previous period
    -   \`t\` sets the period to today.

-   a runs the add command

-   E runs $HLEDGER_UI_EDITOR or $EDITOR or a default editor (vi) on the journal file.

    When using emacs or vi, if a transaction is selected the cursor will be positioned at its journal entry.

-   / key sets the filter query; BACKSPACE/DELETE clears it

-   Z toggles display of zero items (like --empty), and they are shown by default.

    -E/--empty is now the default for hledger-ui, so accounts with 0 balance
    and transactions posting 0 change are shown by default. The Z key
    toggles this, entering "nonzero" mode which hides zero items.

-   R toggles inclusion of only real (non-virtual) postings

-   U toggles inclusion of only uncleared transactions/postings

-   I toggles balance assertions checking, useful for troubleshooting

-   vi-style movement keys are now supported (for help, you must now use ? not h) (#357)

-   ESC cancels minibuffer/help or clears the filter query and jumps to top screen

-   ENTER has been reserved for later use

-   reloading now preserves any options and modes in effect

-   reloading on the error screen now updates the message rather than entering a new error screen

-   the help dialog is more detailed, includes the hledger-ui manual, and uses the full terminal width if needed

-   the header/footer content is more efficient; historical/period and tree/flat modes are now indicated in the footer

-   date: query args on the command line now affect the report period.

    A date2: arg or --date2 flag might also affect it (untested).

-   hledger-ui now uses the quicker-building microlens

0.27.3 (2016/1/12)

-   allow brick 0.4

0.27.2 (2016/1/11)

-   allow brick 0.3.x

0.27.1 (2015/12/3)

-   allow lens 4.13
-   make reloading work on the transaction screen

0.27 (2015/10/30)

-   hledger-ui is a new curses-style UI, intended to be a standard part
    of the hledger toolset for all users (except on native MS Windows,
    where the vty lib is not yet supported).

    The UI is quite simple, allowing just browsing of accounts and
    transactions, but it has a number of improvements over the old
    hledger-vty, which it replaces:

    -   adapts to screen size
    -   handles wide characters
    -   shows multi-commodity amounts on one line
    -   manages cursor and scroll position better
    -   allows depth adjustment
    -   allows --flat toggle
    -   allows --cleared toggle
    -   allows journal reloading
    -   shows a more useful transaction register, like hledger-web
    -   offers multiple color themes
    -   includes some built-in help

    hledger-ui is built with brick, a new higher-level UI library based
    on vty, making it relatively easy to grow and maintain.
