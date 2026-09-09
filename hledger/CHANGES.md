<!--
      _ _
  ___| (_)
 / __| | |
| (__| | |
 \___|_|_|

-->

User-visible changes in the hledger command line tool and library.


# 5817e58e

## Breaking changes

- In journal format, a single tab is also now accepted as the separator between account and amount, for improved compatibility with Ledger. This also means account names can no longer contain tab characters.

- In CSV rules, when a directive like `date-format` or `separator` is declared more than once, the last declaration now takes effect, as the manual describes, rather than the first. (Except for `skip`, where the first declaration still wins, also as the manual describes.) This makes it possible to override an included rules file's directives by writing new declarations after the `include` line. If any of your rules files relied on the old undocumented behaviour, declaring a directive before an `include` to override the included file, you should move that declaration below the `include`. [#2539]

- Config files can no longer specify the command to run via a bare first word in the general section. Since config files can now define command aliases (which can run shell commands), letting a config file also select the default command was too risky. The command to run must now always be given on the command line.

- The `--tldr` flag has been renamed to `--examples`.

- `stats`'s `-1` flag has been renamed to `--oneline`, consistent with `print --oneline` (and git's `log --oneline`).

- The `demo` command, which played asciinema recordings, has been removed.

- `any:` and `all:` queries now also work in posting-oriented reports
  (register, balance, aregister); previously they had an effect only in
  transaction-oriented commands like print, degrading to a plain AND
  elsewhere. A posting can now be selected because of its siblings: eg
  `hledger balance expenses any:cash` shows expenses which were paid
  with cash, which previously required a two-command pipeline.
  aregister with these queries now behaves differently, and more
  consistently, showing the same transactions as print would.

## Config files

- Command aliases: you can now define custom commands by adding `NAME = COMMAND...` to the `[alias]` section of your config file. COMMAND can be a builtin command, an addon command, another alias, or a shell command prefixed with `!`, and can be continued on multiple indented lines. (Shell commands will run only from your user config file or one specified explicitly with `--conf`.)

- In config files, a `#` inside single or double quotes is no longer misparsed as a comment start.

- Leading whitespace before a section header, and a trailing line containing whitespace with no final newline, are now accepted. 

- `--conf`/`--no-conf` flags inside a config file are now dropped, instead of being passed along and causing trouble later.

- Config file errors now follow hledger's standard FILE:LINE-and-excerpt format, and parse errors are displayed properly.

## Command line

- Colour handling is more robust:

  - ANSI colour is no longer used when `TERM=dumb`, eg in an Emacs shell, which was leaking escape codes into piped or redirected output. `--color=yes` can still override.
  - Colour output now works in terminals where the background lightness can't be detected, eg inside Emacs (a light background will be assumed).
  - In terminals without truecolor support, eg Emacs vterm or a stripped `COLORTERM` over ssh/tmux, we now downgrade to the nearest xterm 256-colour.

- Balance assertion failure messages show a better troubleshooting command:
  - regex metacharacters (eg the curly braces in `{2026-07-12, 2.5 €}`) will be escaped
  - `-E` is added, so zero-amount postings will also be shown
  - instead of `-I`, the more precise `--ignore-assertions` is used.

- `acc`, `comm`, `desc` are now official short spellings for the `accounts`, `commodities`, and `descriptions` commands.

- Abbreviating `print`'s `--locations` flag as `--loc` now works as expected.

- Arguments are now passed to addon commands as an argv list rather
  than a shell command line, so empty arguments, apostrophes and other
  special characters now reach the addon intact. (Kevin F. Konrad,
  [#2696]) Where a shell command line is still used (addons run from
  `run`/`repl`, and `!` shell aliases), quoting of apostrophes and
  empty arguments has been fixed. (Arthur Cinader)

- `--` handling with addon commands is improved (Kevin F. Konrad,
  [#2696]): hledger's own options written after `--` are no longer
  stripped from addon arguments; only the first `--` is consumed, so
  later ones reach the addon; and a `--` written in a config file
  section or command alias now works like one on the command line,
  making the documented `-- -n` escape hatch reachable from those too.
  Also, flags requiring a value are now checked only against the
  running command's flags, so a flag belonging to some other command is
  no longer wrongly rejected with "needs a value".

## Help & docs

- `help` has been reorganised and is now an entry point for all hledger docs.

  - `help` with no arguments (or `hledger` with no command) shows a quick reference card.
  - `help commands` shows the full commands list.
  - `help examples [CMD]` shows command examples (like `--examples`).
  - `help usage [CMD]` shows command options and docs (like `-h`).
  - `help manual [TOPIC]` or `help TOPIC` shows the full manual, in several formats, now including the HTML versions at hledger.org.
  - `help install`/`docs`/`support`/`home`/`sponsor`/`relnotes` open the corresponding hledger.org page in a web browser.

- `help`'s matching of manual topics is more powerful.
  `help manual TOPIC` (or `help TOPIC`) now matches by exact match or unique prefix, with all viewers.
  It now also searches the hledger-ui and hledger-web manuals.
  A topic matching several headings, or nothing, now warns or lists the candidates instead of failing or being ignored.

- `help manual` has a new `-l` flag which lists manual topics rather than showing them.
  And `help manual` with no further arguments lists all topics, indented to show some of their hierarchy.

- When `TERM=dumb`, or in Emacs shells that don't support TUIs, `help manual` now defaults to showing plain text instead of failing to run a manual viewer. And it shows only the introduction, not the whole manual.

- `help` now has `h` as its official alias.

- Opening a web page in the browser (`help home`, `--webman` and friends)
  now works on Windows, where it tried a fixed Firefox path; it now asks
  the Win32 API, through the open-browser library. On Linux, `xdg-open`
  is tried first, and a launcher that is not installed no longer stops
  the others from being tried. (Arthur Cinader)

- The commands list can now be limited to particular categories of
  command with `help commands --builtins`, `--addons` or `--aliases`;
  the flags can be combined. (`--builtin` has been renamed to
  `--builtins`, but still works as a unique prefix.)

## Data entry

- Numbers can now also use `_` or `'` as digit group marks. (Kevin F. Konrad, [#273], [#1489])

- `add` no longer offers default amounts with ambiguous digit group marks (eg instead of `-1.000` it will ofer `-1.000,`, avoiding misparsing. [#2656]

## Data import

- In CSV data, characters which journal format can't represent are now
  replaced, with a warning: a semicolon in a description is replaced
  with `.,` (it would otherwise start a comment when read back,
  truncating the description), and a right parenthesis in a
  transaction code is replaced with `]` (it would otherwise end the
  code early). [#2413]

- CSV rules files' `include` directives are handled more robustly
  [#2537]: include cycles, and unreadable included files, are now
  reported with a proper error message showing the include directive's
  location; errors in included files are reported at the right file
  and line (previously they were reported against the top-level file);
  included files now handle BOMs and CRLF line endings like the
  top-level file; and whitespace around the included file path is
  ignored.

- A CSV rules file's data-generating command (`source | cmd`) failing
  no longer aborts the whole run; instead it warns and continues, as
  if no data was found. So when `import` processes several rules
  files, one flaky external source won't block the rest. Data-cleaning
  commands (`source PATTERN | cmd`) still fail hard, since they
  operate on a file that was actually found.

- `import --dry-run` no longer wrongly archives data files when the
  flag is given in abbreviated form (eg `--dr`). Also, the reader's
  import-specific behaviour (preferring the oldest file matched by a
  source glob, honouring the archive rule) now applies only to the
  import command's own reading of its data files.

- `import` with `archive` enabled, if there are multiple downloaded copies of the source file,  now properly deletes processed files and always makes progress. (Previously it could stall, reprocessing the oldest file each time.)

- `--debug=2` now shows clearer output when reading a CSV rules file.

## Lot tracking

Lot tracking has been reworked extensively since 1.99.3. In summary:

- How lot tracking is enabled has changed: a `lots:` tag enables it only on commodities now, not accounts. An account's `lots:` tag now just sets that account's disposal method (FIFO, LIFO, etc - a value is now required), or opts the account out of tracking with `lots: NONE` (eg for tax-sheltered accounts).

- Many more real-world entries are now recognised and handled correctly: transfers involving multiple source or destination accounts, transfers written with `{}` cost annotations, transfer fees that are unpriced or split across several postings, in-kind (priceless) disposals, and entries whose amounts are implied or set by balance assignments.

- Several bugs that could silently produce wrong numbers are fixed: a transfer's sent and received quantities must now match (previously lots could be silently dropped, or a shortfall silently treated as a no-gain fee); fees are now deducted before a transfer selects its lots, so FIFO/LIFO etc choose from the right lots; amounts stay correct when lot detail is collapsed for display (previously balances could be wrong or fees double-counted); and a transfer into an `AVERAGE` pool now re-averages the pool's cost, as an acquisition does.

- Lot names are shown consistently and are always usable: a lot now displays the same name (same cost precision) when acquired, disposed, or transferred; inferred cost bases display enough digits to be exact; and any lot name shown in reports or errors can be used to reference that lot. Also, `print --lots` output can now always be read back by hledger.

- Error messages are clearer and more accurate: they show the entry as it was written, not hledger's processed version; "no lots available" errors list the lots actually available; quantity-mismatch errors suggest the likely cause; an unbalanced entry is reported as such instead of producing a confusing inferred cost; and incompatible mixes of global (`*ALL` etc) and per-account disposal methods are now rejected.

- Balance assertions on lot subaccounts can't be checked correctly (assertions are checked before lots are calculated), and are now handled consistently: close --lots no longer generates them, and when lot detail is hidden (in print output or hledger-ui) existing ones are ignored instead of failing spuriously. The manual and the assertion failure message now explain this limitation.

- `close` no longer generates a spurious zero posting for some emptied accounts, and `close --lots` output is more readable (lot subaccount balances no longer show redundant costs).

- A new `holdings` report shows your lot-tracked investment holdings, per account and commodity or per lot, with units, cost basis, current price and market value, portfolio weight, unrealised and realised gains, and XIRR annualised return.

- `holdings` now values each lot in its own cost commodity, so Value, Weight, unrealised gain and XIRR no longer change or disappear when lots with different cost commodities are grouped into rows (by `--depth`, `--pivot`, tree mode etc). A row aggregating lots with different value commodities shows multiple amounts, like the Cost column; `-X COMM` gives a single-currency view as before.

## REPL & run

The `repl` and `run` commands have been improved since 1.99.3. In summary:

- Most general flags given to `repl`/`run` at startup (such as `-I`, `--strict`, `-b`/`-e`, `--depth`, `--cost`, `--color`) are now applied to every command in the session or script (overrideable by flags within the session).

- `run` scripts are more robust: successfully running an addon command no longer ends the script.

- File handling is more flexible: an `-f` at startup sets the default journal file(s) for all commands, and is passed to addon commands; and a nonexistent default journal file is tolerated, as at the command line (so `add`/`import` can create it).

- The REPL now auto-reloads before each command, detecting changes in input files, the config file, or installed addon commands. This can be disabled with the `--no-watch` flag.

- The REPL is friendlier: it shows a small startup banner, and the journal's base file name in the prompt; the help and quit commands are `h` and `q`; and `echo` interprets common backslash escapes like `\n` and `\t`.

- Getting help in the REPL works better: `help` and `CMD -h` now show the same full, paged output as at the command line, and `help` (also `setup`) no longer fails when there's a problem in the journal.

## Reports

- `print` has a new `--oneline` flag showing just each entry's first line, for a compact overview.

- Multi-period balance reports using `--tree` and `--transpose` together now show only the leaf accounts, for less confusing output. [#1941] (JoeJoeflyn)

- `balance` has a new `--full-names` flag, which in tree mode shows full account names instead of the usual indented leaf names. (Henning Thielemann, [#2429], [#2661]) 

- `balance`'s `--no-elide` flag now also has an effect in list mode: it adds the parents of the posted-to accounts, shown with their own exclusive balances (usually zero, so add `-E` to see them). Eg `bal --no-elide -E` shows a complete table of every posted-to account and its parents. (Henning Thielemann, [#2429], [#2661])

- In `balance`'s single-period csv/tsv/html/fods output, `--drop` no longer causes the total row's "Total:" heading to be truncated. [#2688]

- Omitting `roi`'s `--pnl` option now works as documented, selecting no postings; previously it selected all postings. (Dmitry Astapov, [#2670])

- Repeating the `--transpose` flag now toggles it, allowing a previous `--transpose` to be cancelled.

- `setup` no longer reports unused commodity aliases as undeclared commodities; it's now consistent with `check commodities`.

- `balance --budget` reports no longer lose their goals when the query
  includes terms describing transactions or postings, such as
  `status:`, `desc:` or `--cleared` [#2545]. Budget goal transactions
  are generated, with synthetic status, code and description, so such
  terms matched no goals at all and the goal and performance
  percentage columns silently vanished. Now only the terms that
  meaningfully select goals (account, account type, depth, date,
  commodity) are applied to them; eg `bal --budget --cleared` compares
  cleared spending against the full goals.

- `-X`/`--value` with a commodity to which no conversion price can be
  found now prints a warning, instead of silently having no effect. An
  equivalent commodity symbol is suggested if one is known (eg `$` for
  `USD`).

- Report titles in HTML output are improved: `balance` now shows the
  same default heading as its text output (for multi-period and budget
  reports), `register`, `aregister` and `holdings` now show a title
  too, and in all of these `--title=TEXT` replaces it and `--title=`
  suppresses it. Also, the title is now a `<h3 class="report-title">`
  element placed before the table, making it easier to style.

- In `print`'s csv/tsv/html/fods/sql output, the debit column now
  appears before the credit column, following convention.

- In `aregister`'s csv/tsv/html output, the "change" column has been
  renamed to "amount", matching `print`'s output and making it easier
  to re-import with csv rules.

- HTML output now has newlines between elements, making it easier for
  humans to read and troubleshoot; rendering in browsers is unchanged.
  [#2326]

- HTML output now prevents wrapping within dates and individual commodity amounts, by default. Each amount is wrapped in a `span` with an "amount" class, date cells are marked with a "date" class. `aregister` gets the same builtin table styles as the other reports. A `hledger.css` file now overrides the builtin styles (previously the builtin styles took precedence), and an example `hledger.css` file  provided in the repo.

## Other

- `rewrite`'s `--diff` output can now be applied by `patch` or `git
  apply` [#2548]. Previously its hunks contained no context lines, so
  they were rejected. Now each source file is diffed as a whole, with
  the standard three lines of context. And changed transactions which
  have no journal entry to patch (ones read from CSV or timeclock
  data, or generated by a periodic rule) are now left out of the diff
  and reported on stderr, instead of producing bogus or destructive
  hunks.

- `stats` now shows the base currency's symbol as used in the journal,
  with the guessed ISO 4217 code alongside when that differs (eg `$
  (USD)`). Previously it showed only the code, which looked like a
  journal commodity but wasn't usable in queries or `-X`.

- The aeson version bound has been relaxed to `>=1 && <2.4`, easing
  installation while the ecosystem catches up. (hledger's own stack
  and cabal configs still select aeson 2.3, avoiding HSEC-2026-0007.)

## Docs

- aregister: noted that transactions with multiple currencies may occupy more than one line
- balance, help: minor updates
- balance: html and fods output are not multi-period-only; they have been supported since 1.40
- Boolean queries: simplified and clarified
- check: move the basis check note to the end
- commodity/Directives: clarify commodity and `D` directive scopes [#2665]
- decimal marks: clarify commodity/decimal-mark directive scope leakage [#2664]; simplify Trailing decimal marks
- Directives: fixed a link to the Ledger page
- First lots example: improved
- fixed some stray junk characters in the manual
- help flags: clarified `-i`/`-m`/`-w` vs `--info`/`--man`/`--webman`; reduced line wrapping in 80-column terminals; misc edits
- Lot reporting: various edits, including a holdings example and cross-reference
- lots: documented the consequences of changing the cost basis method, and two ways to make a change apply only going forward
- lots: documented how to record a transfer that received more than was sent
- PART 5's sections promoted to markdown-level-1 headings, consistent with the manual's other PARTs
- Period expressions: fixed outdated date adjustment info [#2714]
- quickref: consistent checks ordering
- rewrite: noted that --diff re-renders the transactions it changes, and that --layout can be set to minimise the diff
- roi vs holdings: added comparison examples and interop advice (see also Examples)
- Two-space delimiter: rewritten

## Examples

- `examples/home-page-example.journal` is the example journal from the hledger.org home page
- `examples/lots/lots.journal` is renamed (from lot-entries.journal), updated so `hledger holdings` shows a full report, and contains notes comparing roi and holdings XIRR
- `examples/lots/irr.journal` is another example comparing roi and holdings XIRR
- `examples/csv/banking/` has new rules for SimpleFIN (json and csv exports) and for Unify Federal Credit Union

## Scripts/addons

- `bin/check-fancyassertions` now checks assertions in date order, avoiding spurious failures with journals recorded out of chronological order. [#1742]
- `bin/hledger-bar` now allows its flags to appear anywhere among the arguments, and sets scale with a new `-s` option.
- `bin/getprices` now has a small delay between requests, reducing failures with some providers.


[#273]: https://github.com/plaintextaccounting/hledger/issues/273
[#1489]: https://github.com/plaintextaccounting/hledger/issues/1489
[#1742]: https://github.com/plaintextaccounting/hledger/issues/1742
[#1941]: https://github.com/plaintextaccounting/hledger/issues/1941
[#2326]: https://github.com/plaintextaccounting/hledger/issues/2326
[#2413]: https://github.com/plaintextaccounting/hledger/issues/2413
[#2429]: https://github.com/plaintextaccounting/hledger/issues/2429
[#2537]: https://github.com/plaintextaccounting/hledger/issues/2537
[#2539]: https://github.com/plaintextaccounting/hledger/issues/2539
[#2545]: https://github.com/plaintextaccounting/hledger/issues/2545
[#2548]: https://github.com/plaintextaccounting/hledger/issues/2548
[#2656]: https://github.com/plaintextaccounting/hledger/issues/2656
[#2661]: https://github.com/plaintextaccounting/hledger/issues/2661
[#2664]: https://github.com/plaintextaccounting/hledger/issues/2664
[#2665]: https://github.com/plaintextaccounting/hledger/issues/2665
[#2670]: https://github.com/plaintextaccounting/hledger/issues/2670
[#2688]: https://github.com/plaintextaccounting/hledger/issues/2688
[#2696]: https://github.com/plaintextaccounting/hledger/issues/2696
[#2714]: https://github.com/plaintextaccounting/hledger/issues/2714

# 1.52.2 2026-08-24



# 1.99.3 2026-06-24

## Breaking changes

- CLI: `--verbose-tags` is no longer a general flag, it is now a
  command-specific flag for `print` and `rewrite`.

- Commodities & prices: `commodities --used` now only shows
  commodities used in transactions; use `--priced` to see commodities
  used in P directives.

- Data import: The CSV `source` and `archive` rules now read from/write to a
  journal-adjacent `data/` directory by default.

- Journal: Inferred missing amounts no longer affect display precisions or
  entry balancing precisions.

- Journal: account names whose final part is enclosed in curly braces
  (like `assets:{foo}`) are expected to have a valid lot subaccount
  name within the braces, and will raise an error if not. This is now
  documented.  Also this error checking (and the hiding by default) of
  explicit lot subaccounts can now be disabled with `-I`/`--ignore-lots`.

- print: `print` now aligns posting amounts by decimal mark, by default.
  `--layout=hledger1` restores the old layout.

## Command line

- We now show a clear error when no value is provided for a
  value-requiring option.  (Eg, `hledger import -f --dry-run` no
  longer tries to use `--dry-run` as `-f`'s value.)

- Bad option values are now reliably reported as an error.
  Previously, some invalid option values triggered an error only if
  the option was actually used by the command being run.

- On Windows, file paths containing spaces are now quoted properly
  when invoking external helpers (info, man, tldr, pager, `$EDITOR`,
  `hledger-iadd`). This affected hledger-ui's `A` and `E` keys, and
  hledger's help/pager invocations.
  [#2646]

## Commodities & prices

- Commodity aliases:
  In journal files, commodity directives can now define one or more
  aliases for the commodity.  Eg here USD has three aliases:

      commodity USD 1.00    ; alias: $ US$ "us dollars"

  A 1:1 market price is inferred for these, so you can use `-X` to
  freely convert between them.  This is useful eg if your journal and
  your downloaded market price data use different symbols for a currency.

  `cur:COMM` queries now match COMM or any of its commodity aliases.
  To match only a specific symbol without considering aliases, use `sym:SYM`.

- `commodities`: `--used` now only shows commodities used in transactions;
  a new `--priced` flag shows commodities used in P directives.
  Separating these makes `--used` more useful with a date query.

- `commodities` now supports `date:` queries (and/or `-b`/`-e`/`-p`
  report period options), affecting the `--used` and `--priced` reports.

- `prices` has a new `--summary` mode.

- `prices` has a new `--locations` flag, showing the file and line number
  of each price's directive or transaction from which it was inferred.

## Data entry

- `add` and `import` now test for faulty filesystems before writing.
  Some filesystems, eg an Android shared filesystem in Termux, overwrite when you tell them to append.
  hledger now tests for this before writing to the journal, to reduce risk of data loss.
  [#2577]

- `add` now offers useful default amounts after entering a balance assignment.
  Previously, amounts entered via `= BALANCEAMOUNT` were not affecting
  subsequent postings' default amounts, making it difficult to
  complete data entry. Now, appropriate balancing amounts are offered.

- `add` no longer restarts at posting 1 if the final transaction checks fail.
  So if the entered transaction fails to balance or satisfy balance assertions,
  it now just reprompts for another posting, instead of discarding the postings
  entered. (This is most visible when entering balance assignments.)

- `add`'s default amounts are now displayed with the journal's commodity
  display styles, helping to avoid misparsing of decimal marks. [#2645]

## Data import

- `get` is a new command for fetching transaction data and market prices.
  It runs two helper scripts which you can customise:
  
  - `data/getdata` to gather transaction data (eg CSV) files in `data/`
  - `prices/getprices` to download market prices, to be saved in `prices/`

  Or with `--transactions` or `--prices`, only the selected phase is run.
  The data and prices directories are autocreated if needed, next to the main journal file.
  Sample scripts can be found in <https://github.com/plaintextaccounting/hledger/tree/main/bin>.
  The sample `getprices` requires `pricehist`.

- `import` with no file arguments now reads from all `.rules` files in
  the `rules/` directory next to the main journal file, by default.
  Files whose name begins with `.` or `_` are skipped (this is useful
  for included files which should not be read directly.)

- `import -g`/`--get` runs the `get` command before importing.  So
  with appropriate helper scripts, a complete import workflow can be:
  `hledger import -g [--dry-run]`

- `import` now archives only when new transactions were actually
  imported.  This avoids creating duplicate archives, eg with a
  data-generating `source` rule like `source | paypalcsv ...`.

- The CSV `source` and `archive` rules now read from/write to the
  journal's `data/` directory by default:

  - `source` looks for bare filenames/relative paths first in `data/`,
    then in `~/Downloads`.
    (Except paths beginning with `./` or `../` - these are relative
    to the rules file, as before.)
  - `archive` saves to `data/archive/`, autocreating that if needed.
    (A breaking change; previously it saved in a data dir next to the rules file.)

- On Windows, `source` file paths with a drive letter like `C:\foo`
  are now properly recognised as absolute paths (not relative).

- A `#` character in a `source` rule now always starts a same-line
  comment, even if it appears after `|`.

## Error messages

- Balance assertion errors: in the suggested troubleshooting command,
  commodity symbols containing regex metacharacters (like $) are now
  properly quoted for the shell.

- In error messages which compare two amounts (balance assertions,
  recorded gain, `check basis`), when the rounded amounts look
  identical, we now show more decimal places to make the difference
  visible. [#2636]

- Certain errors when reading a CSV or rules file 
  (eg a missing date rule, or encoding/skip/timezone errors)
  now show the path of the problem rules file.

- `import`'s "no data files" error message is improved.

- With an unrecognised command argument, the error message now shows
  the bad argument, and the config file path if it came from a config
  file.  [#2489]

## Journal

- Inferred missing amounts no longer affect display precisions or the
  entries' local balancing precisions. So a high-precision inferred
  amount won't affect the number of decimals displayed in reports, or
  the precision required to balance the entry. So,

  - An unseen high-precision balancing amount, eg inferred from a
    precise `@` price, no longer makes it harder to balance the entry.
  - Some reports that used to add unnecessary decimal zeros no longer do so.
  - Reports more consistently show amounts smaller than their
    commodity's display precision as `0`.

## Lots & gains

- In command line help, `--lots` has moved from "General input flags"
  to "General output flags".

- hledger can now detect gain postings heuristically, without
  requiring that their account is declared as `type:G`. Five styles
  for writing disposal transactions are documented in the manual's
  "Recording disposals" section.

- The `G`/`Gain` and `U`/`UnrealisedGain` account types are now
  inferred from conventional English names, like the other types.  Eg
  `revenues:gain`, `income:capital-gains`, `equity:unrealised-gain`,
  `equity:unrealized gains` are recognised as type G, G, U, U.

- Gain amounts are now inferred or checked at the gain commodity's
  local precision within the entry. This makes it easier to read
  inferred gain amounts and to write explicit gain amounts.
  As a special case, if the local precision is zero but the gain is a
  non-integer, 2 decimal places are assumed.
  Inferred gain amounts preserve their full precision internally, so
  they can be viewed more precisely with a command like `print -c
  '$1.000000' --round=soft`.

- Lot transfer destinations are now checked more carefully: any
  specified lot details on the destination annotation (date, label,
  cost) must match the source lot, or an error is raised. (Previously,
  this would silently disrupt lot identities.)

- The `AVERAGE`/`AVERAGEALL` cost basis methods now properly
  recalculate the pool-wide average cost after each acquisition.
  And when they are used, lot subaccount names now omit the cost
  (`{2026-01-15}` rather than `{2026-01-15, $50}`), so account names
  remain stable as new lots are acquired.
  [#2581]

- `check basis` no longer fails because of non-terminating decimals in
  the unit cost (eg `$50/7 = $7.142857...`).
  [#2636]

- Harmless commodity style differences in explicit lot subaccount
  names are now ignored (eg `$60` vs `$ 60`).
 
- Explicit lot subaccounts are detected more robustly, tolerating
  colons or curly braces within the label or commodity symbol.

- Explicit lot subaccounts now require a comma after the date.

- The `--ignore-lots`/`-I` flags disable explicit lot subaccounts
  detection and error checking. [#2649]

- When disposing a single lot with a balance assertion, we no longer
  generate an unnecessary new assertion posting.

- If a Ledger-style `(LOTNOTE)` annotation contains double quotes,
  these are now stripped so they don't clash with hledger's cost basis
  syntax and break round-trip parsing.

- When generating labels for unlabelled lots acquired on the same day,
  we now pick the smallest numeric label not already used on that
  date, avoiding collisions with user-provided labels.

- When there's only one unlabelled acquisition on a date, we no longer
  generate an unnecessary label.

## print & print-like commands

- `--verbose-tags` is now a command-specific flag for `print` and
  `rewrite` (not a general flag).

- `print`'s `-x` and `--lots` flags are decoupled again (`-x` no
  longer implies `--lots`).

- `print` has a new `-a`/`--all` convenience flag that shows all
  details useful for troubleshooting: it turns on `--explicit`,
  `--lots`, and `--verbose-tags`.

- `print` now properly shows inferred per-lot dispose/transfer
  postings only when in `--lots` mode.

- `print --output-format=beancount` now also encodes non-ASCII letters
  in tag names (metadata keys), ensuring Beancount can read them.
  [#2576]

- `print` now aligns posting amounts at their decimal marks by
  default.  The target column is 53; this is increased when needed to
  preserve 2+ spaces between accounts and amounts.
  
  Also, the `=`, `==`, `=*`, `==*` operators of balance assertions and
  assignments are aligned in a column one space past the transaction's
  rightmost posting amount. And the assertion/assignment amounts are
  themselves decimal-aligned, with the leftmost one starting one space
  past the widest operator.

  A new `--layout` option (also supported by `add`, `close`, `import`,
  `rewrite`) customises this:

  - `--layout=COL` (a positive integer) sets a different target column.
  - `--layout=hledger1` revert's to hledger 1's layout (each
    transaction's amounts right-aligned within an expandable 12-char
    region).

## Reports

- A new `--title=TITLE` option sets or customises a title heading for
  most reports, when producing `txt`, `html` or `fods` output (or
  `csv` or `tsv` output, in some cases).  `balancesheet`,
  `balancesheetequity`, `cashflow`, `incomestatement` have their usual
  title as the default; other reports have no title by default.

- The `--subreport-titles=TITLE1|TITLE2|...` option customises section
  titles for compound reports like `balancesheet` and
  `incomestatement`. Titles should be `|`-separated. Eg: `hledger bs
  --subreport-titles='Aktiva|Passiva'`. Or use `--subreport-titles=''`
  to suppress subreport titles.

- The `--period-titles=compact|dates` option customises column
  headings for periodic reports.  `compact` (the default) preserves
  current behaviour (abbreviated english month/week names within a
  single year, explicit dates otherwise).  `dates` always shows
  explicit ISO dates. [#2578]

- `balance`: in single-period reports, account names are now kept
  aligned when amounts are wide.  (Adam Sardo, [#1148])

- `balance`: single-period HTML/FODS reports now respect the preferred
  commodity display style, like other reports.
  (Simon Michael, Henning Thielemann, [#2584], [#2588])

- In `--pivot`'s value, `account` is now accepted as a synonym for `acct`.
  And `description` is documented as a synonym for `desc`.

- `roi` uses a new more robust TWR algorithm.
  The previous TWR implementation assumed that an exact valuation of
  the investment could be obtained immediately before or after any
  cashflow, which is not generally possible. `roi` now uses the BAI
  (Bank Administration Institute) Linked IRR method, valuing the
  investment only on dates where an exact valuation is available.
  This greatly improves the robustness of TWR computations.
  (Dmitry Astapov, [#2420])

## Timedot

- A line whose first word looks like a date (three groups of digits
  separated by `-`, `/`, or `.`) is now always parsed as a timedot
  date line, and shows a clear error if the date is invalid (instead
  of silently treating it as a comment or a zero-amount entry).
  
- Lines with an org heading prefix (eg `** `) are parsed more consistently.

## Other

- hledger now requires version 2.3+ of the aeson library, avoiding a
  bug where certain data could trigger memory/CPU exhaustion.
  (<https://haskell.github.io/security-advisories/advisory/HSEC-2026-0007.html>)

- `setup` no longer shows a `'"ver' is not recognized ...` error message on Windows.

- `setup` now shows "all account types exist" as neutral, not a warning.

- `setup` now warns if the filesystem does not support appending. [#2577]

- `stats` now shows a base currency inferred for the journal.

- allow megaparsec >9.8

## Docs

- add: balance assignments [#2603]
- balance: `--gain` shows total (realised + unrealised) gain [#2049]
- check basis: explain strict-comparison rationale, list escape hatches [#2636]
- Cost basis methods: edits
- Cost basis vs transacted cost: edits
- csv: CSV vs hledger fields, if, if table: rewrites [#2647]
- Directives, Directive effects: consolidate, cleanup, update
- get: document new command
- Lot reporting: many updates
- print layout: rename, expand
- Recording disposals: new section walking through each disposal style
- Report titles: new section
- roi: describe new TWR algorithm (Dmitry Astapov)
- Tags: clarify/restore some missing tags info [#1640], [#1950]
- timedot: rewrite

## Examples

- `examples/csv/github-sponsorships.rules`
- `examples/lots/lot-entries.journal`: fix gain posting

## Scripts/addons

- Rename, update bin/hledger-example* scripts
- Add sample `getdata` and `getprices` scripts for the `get` command.

## API

- `Hledger.Write.Ods`: enable digit grouping in output if `AmountStyle` declares any digit groups. (Henning Thielemann) [#2584]
- `Hledger.Data.Amount`: consolidate `showPriceDirective` here.


[#1148]: https://github.com/plaintextaccounting/hledger/issues/1148
[#1640]: https://github.com/plaintextaccounting/hledger/issues/1640
[#1950]: https://github.com/plaintextaccounting/hledger/issues/1950
[#2049]: https://github.com/plaintextaccounting/hledger/issues/2049
[#2410]: https://github.com/plaintextaccounting/hledger/issues/2410
[#2420]: https://github.com/plaintextaccounting/hledger/issues/2420
[#2489]: https://github.com/plaintextaccounting/hledger/issues/2489
[#2576]: https://github.com/plaintextaccounting/hledger/issues/2576
[#2577]: https://github.com/plaintextaccounting/hledger/issues/2577
[#2578]: https://github.com/plaintextaccounting/hledger/issues/2578
[#2581]: https://github.com/plaintextaccounting/hledger/issues/2581
[#2584]: https://github.com/plaintextaccounting/hledger/issues/2584
[#2588]: https://github.com/plaintextaccounting/hledger/issues/2588
[#2603]: https://github.com/plaintextaccounting/hledger/issues/2603
[#2636]: https://github.com/plaintextaccounting/hledger/issues/2636
[#2645]: https://github.com/plaintextaccounting/hledger/issues/2645
[#2646]: https://github.com/plaintextaccounting/hledger/issues/2646
[#2649]: https://github.com/plaintextaccounting/hledger/issues/2649


# 1.99.2 2026-04-28

Breaking changes

- Lot processing and checking is now performed by default when reading a journal with lot entries.
  The `--lots` flag is now a display toggle; without it, lot subaccounts are hidden from reports.

- The `G` (`Gain`) account type is no longer auto-detected from account names
  (to avoid breaking hledger 1 journals using those names).
  And a `U` (`UnrealisedGain`) account type has been added (a subtype of `Equity`).

- Disposal transactions now produce a balanced pair of gain postings:
  a transfer between the first `U` account and the first `G` account.
  (If none are declared, the names `equity:unrealised-gain` and `revenues:gain` will be used.)
  The special exception for gain postings during transaction balancing,
  and the separate disposal balancing step, have been dropped.
      
- Amountless explicit gain postings are no longer allowed; if you write gain
  postings in the journal, you must write their amounts also.

Features, Improvements

- The new `--ignore-lots` flag disables lot processing. This can be useful
  to avoid errors when working with incomplete journals.

- The `-I` flag is now a shorthand for `--ignore-assertions --ignore-lots`.

- Capital gain is now computed more robustly, from disposal postings only
  (not from the entry's cost basis residual).

- Cost amounts in lot subaccount names like `assets:x1:{2026-01-15, $1,500}`
  are now styled with the canonical commodity styles.
  Likewise for inferred gain posting amounts.

- Lot transfer transactions with a priced fee posting will be automatically
  split into a transfer portion and a disposal portion (for the fee), if possible.
  
- A new optional `hledger check basis` check verifies that each acquire posting's
  cost basis matches its transacted cost (`{B} = @T`).
  This prevents typos in cost basis which could silently cause wrong capital gain to be calculated.

- `print`'s  `-x`/`--explicit` flag now implies `--lots`, so you can just
  type `hledger print -x` to see lot details. (To see all possible details,
  add `--verbose-tags`.)

- `print --verbose-tags` now shows some new lot posting `ptype` tag values:

  - `rgain` and `ugain` on generated realised- and unrealised-gain postings
  - `lot-parent-assertion` on generated postings preserving balance assertions across lot splitting
  - `split-posting` on the disposal portion of auto-split lot transfers.

- When inferring a transacted price to balance a two-commodity transaction,
  if one of the postings is lotful, hledger will attach the price to that one,
  rather than always picking the first posting.
  [#2571]

- Transaction-balancing error messages have been improved, and now show the summed amounts
  to help with troubleshooting.

- In CSV rules, a `%(FIELD)` interpolation syntax with parentheses is now accepted.
  This is useful when the field name needs to be delimited from adjacent text.
  Eg: `account1 assets:%(type)checking`.

- When using the `less` pager, hledger no longer duplicates options in the `LESS` environment variable.

- `add` now date-weights similar transactions by absolute distance from today,
  not from the journal's latest date. This prevents a future date typo from skewing defaults.

- `setup` now also checks for the `G` (`Gain`) and `U` (`UnrealisedGain`) account types.
  Also output related to the `less` pager, lot-related data, and strict checking has been improved.

Fixes

- The `G` (`Gain`) account type's spelling has been fixed (it's `Gain`, not `Gains`). [#2570]

- `add` no longer breaks when the journal contains postings to a type `G` account.
  [#2572]

- `register` and `aregister` now omit postings whose amount couldn't be inferred
  instead of showing blank entries and report layout problems. (Shouldn't occur in practice.)
  [#2571]

- Equity conversion postings generated by `--infer-equity` no longer break
  transaction balancing in lot disposals.

- `{{TOTALCOST}}` annotations may now contain a date and label too.

- `{{TOTALCOST}}` annotations now preserve decimal digits (capped at 8 digits)
  when converted to `{UNITCOST}`.

Scripts/addons

- `hledger-fancyassertions`: add `-s/--strict` flag. (Joshua Chapman)

Docs

- Cost basis, Lot reporting: many updates.

[#2570]: https://github.com/plaintextaccounting/hledger/issues/2570
[#2571]: https://github.com/plaintextaccounting/hledger/issues/2571
[#2572]: https://github.com/plaintextaccounting/hledger/issues/2572


# 1.52.1 2026-04-28

Breaking changes

- The `Gain` (`G`) account type is no longer auto-detected from account names like
  `revenue:gains` or `income:capital gains`; it must now be declared explicitly with `; type: G`.
  Also, the `UnrealisedGain` (`U`) account type, a subtype of Equity, has been added
  (spellings `U`, `UnrealisedGain`, and `UnrealizedGain` are all accepted).
  These improve compatibility between hledger 1 and 2.

Docs

- The "Cost basis / lot syntax" section has been renamed to "Cost basis",
  and updated to mention hledger 2.


# 1.99.1 2026-03-28

(2.0 preview 1)

Breaking changes

- This 2.0 preview is the first hledger release to explore AI-assisted development,
  so please do check out the evolving AI policy/FAQ: <https://hledger.org/AI.html>.
  There's also a new "AI usage" section below.

- hledger now recognises certain transactions as lot disposals;
  and in these, postings to accounts with the Gain type (declared or auto-detected)
  are excluded from normal transaction balancing.
  This means it's possible for existing journal entries to be rejected.
  Eg, this entry (though nonsensical and unlikely) is ok in hledger 1.x but an error in 2.x:
  ```
  2026-02-01 sell stock
      assets:stocks      -1 AAA {$50} @ $60
      assets:cash       $50
      revenue:gains     $10
  ```
  hledger 2.x recognises the `assets:stocks` posting as a lot disposal,
  and `revenue:gains` as a Gain account,
  so it excludes the $10 from transaction balancing,
  and then fails to balance the $-60 and $50.
  To fix it you could: rename the `revenue:gains` to something else,
  or explicitly declare it as type `R` (Revenue) instead of `G` (Gain),
  or omit the $10 amount (allowing hledger to infer it).

  Here's a more realistic entry for 2.x, to explain the two balancing steps:
  ```
  2026-02-01 sell stock
      assets:stocks      -1 AAA {$50} @ $60
      assets:cash       $60
      revenue:gains    $-10
  ```
  By default, 2.x will check just the $-60 and $60 (transaction balancing).
  And in lots mode, it will also check the $-50, $60, and $-10 (disposal balancing).

- Posting's `ptype` field has been renamed to `preal` (and `PostingType` to `PostingRealness`),
  to avoid confusion with the new `ptype` tag. This changes JSON output.

Features

- hledger now understands, and prints, a Beancount-like cost basis syntax:
  `{DATE, "LABEL", COST}`, with the parts in that order, all optional.
  Ledger-compatible `{COST} [DATE] (NOTE)` syntax is also accepted,
  and can be printed using `print`'s new `ledger` output format.

- Lot-related postings are detected,
  from a `{COSTBASIS}` annotation, or a `:{LOTNAME}` subaccount,
  or a `lots` tag on their account or commodity, or in a few other ways.
  Their type (acquire, dispose, transfer-from, transfer-to, gain) is saved
  in a hidden `_ptype` posting tag; or with `--verbose-tags`, in a visible `ptype` tag.
  (For examples, see `hledger print --verbose-tags -f examples/lots/lot-entries.journal`)

- Transacted cost (`@`) is inferred from cost basis (`{}`) if needed,
  and vice versa. So writing either one is often sufficient.

- Internally, every lot has its own subaccount.
  These can be left implicit, or recorded explicitly.

  A new `--lots` flag enables "lots mode", which calculates and checks lot movements,
  and makes lot subaccounts visible in reports.

- Lot identities and balances are tracked across transactions and accounts
  (and between year files, with `close --clopen --lots`).
  Wrong or ambiguous lot movements are reported.

- The reduction method (booking method) for transfers and disposals
  can be configured per account or per commodity, using the `lots` tag.
  Per-account FIFO, LIFO, HIFO, AVERAGE
  and globally-scoped FIFOALL, LIFOALL, HIFOALL, AVERAGEALL methods are supported.

- Disposals automatically calculate or check capital gain/loss,
  which can be left implicit or recorded explicitly.
  Transaction balancing behaviour has been updated to allow this (see "Breaking changes").

- The `check` command has a new `lots` check,
  which is another way to validate lot movements.
  Eg to run the usual strict checks and also the lot checks: `hledger check -s lots`.
  Also `check accounts` now ignores lot subaccounts.

Fixes

- `print` now preserves empty `{}` cost basis annotations.

Improvements

- `commodities` now supports `tag:` queries, eg `hledger commodities tag:lots`.

- `print`'s beancount output has been improved:
  - it converts single-letter commodity symbols
  - it converts the no-symbol commodity (to "CC")
  - it converts a top-level "revenue" or "revenues" account to "Income"
  - it converts balance assignments to explicit amounts
  - it converts market prices
  - it sets booking methods based on accounts' `lots` tag value
  - it generates a (commented) tolerance option
  - it handles account and commodity tags better
  - it shows cost basis before transacted cost, as Beancount requires.

Docs

- Cost basis / Lot syntax: updated
- Lot reporting: added
- Lot postings with balance assertions: added
- Reporting concepts > Detecting special postings: added

Examples

- lot-entries.journal: sample journal entries involving lots
- hledger.conf: how to hide explicit lots

AI usage

This 2.0 preview is the first hledger release to explore AI-assisted development.
There is an AI policy document/FAQ: <https://hledger.org/AI.html>

In this release, I used claude models to help me design, plan, implement, test, debug and document the lot tracking and capital gains features.
Mostly opus 4.6, plus some experimentation with the cheaper models and the more expensive modes.
Each commit is relatively small and clear and was reviewed and tested by me.

Approx. estimated claude token use (in+out), and cost, for the lots work in this release:

- 2026-01: 133Mt,   $85
- 2026-02: 598Mt,  $551
- 2026-03: 299Mt,  $256
- Total:    ~1Gt, ~$900

Approx. human dev time: ~150h, market value ~$10k-30k


# 1.52 2026-03-20

Features

- `aregister` and `register` now support `--drop` for trimming leading account name components,
  like the `balance` command.
  (Caleb Maclennan)

- `print` now preserves and reproduces Ledger-style lot syntax (cost basis annotations) in text and json output,
  and (converted to Beancount syntax) in beancount output.

- Tags can now be declared on commodities, and you can query for postings by their commodity's tags.

- A new `Gain` (`G`) account type has been added, as a subtype of Revenue.
  Account names matched by `^(income|revenue)s?:(capital[- ]?)?(gains?|loss(es)?)(:|$)`
  are auto-detected as Gain type.
  (Some examples: revenue:gains, income:capital-gains, income:losses.)
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

[#2508]: https://github.com/plaintextaccounting/hledger/issues/2508
[#2511]: https://github.com/plaintextaccounting/hledger/issues/2511
[#2522]: https://github.com/plaintextaccounting/hledger/issues/2522
[#2535]: https://github.com/plaintextaccounting/hledger/issues/2535
[#2544]: https://github.com/plaintextaccounting/hledger/issues/2544
[#2553]: https://github.com/plaintextaccounting/hledger/issues/2553
[#2555]: https://github.com/plaintextaccounting/hledger/issues/2555
[#2556]: https://github.com/plaintextaccounting/hledger/issues/2556
[#2557]: https://github.com/plaintextaccounting/hledger/issues/2557
[#2563]: https://github.com/plaintextaccounting/hledger/issues/2563
[#2564]: https://github.com/plaintextaccounting/hledger/issues/2564


# 1.51.2 2026-01-08

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

[#2505]: https://github.com/plaintextaccounting/hledger/issues/2505
[#2514]: https://github.com/plaintextaccounting/hledger/issues/2514


# 1.51.1 2025-12-08

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

[#2503]: https://github.com/plaintextaccounting/hledger/issues/2503
[#2497]: https://github.com/plaintextaccounting/hledger/issues/2497


# 1.51 2025-12-05

Breaking changes

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

- Organise/rename examples/csv/ as the [CSV rules library](https://github.com/plaintextaccounting/hledger/tree/master/examples/csv)

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


# 1.50.5 2025-12-08

Fixes

- Relative includes from a symlinked file work again, fixing some fallout from 1.50.4's fixes.
  [#2503]

[#2503]: https://github.com/plaintextaccounting/hledger/issues/2503


# 1.50.4 2025-12-04

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

[#2498]: https://github.com/plaintextaccounting/hledger/issues/2498


# 1.50.3 2025-11-18

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


# 1.50.2 2025-09-26

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

[#2463]: https://github.com/plaintextaccounting/hledger/issues/2463
[#2465]: https://github.com/plaintextaccounting/hledger/issues/2465


# 1.50.1 2025-09-16

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

API

- Hledger.Cli.Utils:
  add withJournal alias for withJournalDo,
  pivotByOpts -> maybePivot,
  anonymiseByOpts -> maybeWarnAboutAnon,
  stop exporting pivotByOpts, anonymiseByOpts

- Hledger.UI.ErrorScreen:
  uiReloadJournal -> uiReload,
  uiReloadJournalIfChanged -> uiReloadIfFileChanged

[#2452]: https://github.com/plaintextaccounting/hledger/issues/2452

# 1.50 2025-09-03

## Breaking changes

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

## Fixes

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

## Features

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

## Improvements

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

## Docs

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

## Examples

- CSV rules for Eternl cryptocurrency wallet
- VAT example

## Scripts/addons

- renamed paypaljson2csv to paypaljson
- simplefinjson, simplefincsv: new helpers for downloading/converting data from simplefin.org bank aggregator


# 1.43.2 2025-06-13

- hledger no longer shows an error message or exits with error status
  when its output is truncated in a piped command. (This broke in 1.43.) [#2405]

- The `add` command's doc now describes how it interacts with balance assertions
  and balance assignments. [#2406]

- `aregister` now consistently rounds amounts to display precision again.
  (This broke in 1.32.) [#2407]

- Changelog, release notes: mention improved decoding errors [#73];
  add missing issue numbers


# 1.43.1 2025-06-04

Fixes

- `cur:` in posting-based reports like `balance` and `register` once again
  filters multicommodity amounts as it should. [#2396]
- More error messages were made consistent, hiding call stack etc. [#2367]

Docs

- Query types: clarify that amt: filters postings [#2396]
- More text encoding corrections/cleanups [#2394]


# 1.43 2025-06-01

## Breaking changes

- Timeclock format now supports multiple simultaneous clocked-in sessions.
  A clockout entry can reference the account name of the clockin it is ending,
  otherwise it will end the most recent clockin.

  This is a potentially breaking change, because we previously ignored
  the description on clockout entries.  For now, you can restore the
  old behaviour by adding the `--timeclock-old` flag.  This may be
  removed later, so if you needed it, please let us know!
  (Michael Rees, [#2141])

## Fixes

- For a long time, hledger docs stated that hledger's input and output had to be UTF-8 encoded.
  In fact this was wrong; hledger has always used the system locale's encoding for both.
  Docs like [Install: Text encoding](install.md#text-encoding)
  and       [hledger: Text encoding](hledger.md#text-encoding)
  have been updated.
  [#2394]

- Some boolean queries involving `amt:` or `cur:` did not match correctly; now they do.
  (Simon Michael, Stephen Morgan, [#2371], [#2373], [#2387])

- The `roi` command has fixed a bug with PnL attributed to the wrong period.
  (Dmitry Astapov, [#2391])

- CLI error messages now have consistent format independent of the GHC
  version hledger was compiled with. [#2367]

## Features

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
  (Sam Almahri, [#2368])

## Improvements

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

## Docs

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

## Examples

- examples/csv/nps.csv.sh updated (Pranesh Prakash)
- examples/forecast-budget* -> examples/goal-budget*
- examples/i18n/\*.journal: top level account declarations in several languages.
- examples/quickstart.journal: the quickstart journal from the home page

## Scripts/addons

- bin/balance-as-budget-multi.hs (Dmitry Astapov)
- bin/bashrc: command alias updates
- bin/hledger-sankeymatic

## API

- Hledger.Cli.Conf: make getConf total, add getConf'
- Hledger.Cli.Version: add more version helpers, rename HledgerBinaryInfo


# 1.42.2 2025-05-16

Fixes

- The test command can pass options to tasty again (this broke in 1.42).
  Also, any arguments before -- are now passed to tasty as test-selecting -p options.
  [#2386]

- Require extra >= 1.7.11, fixing the stack8.10.yaml build. (Thomas Miedema)

Docs

- CSV encoding: fix inaccurate list of encoding names. [#2354]
- Fix broken links to "Commodity display style". (Simon Michael, J.B. Rainsberger [hledger_site#132])
- Misc. edits/fixes: beancount output, commands list, balance command, hledger-iadd link, csv tutorial link


# 1.42.1 2025-03-12

Fixes

- Fix a regression in the parsing of single ampersands (&) in csv rules.
  (Thomas Miedema, [#2352])

- The run and repl commands no longer cache data wrongly when using the --forecast option.
  (Dmitry Astapov, [#2345])

- The run and repl commands no longer miss a caching opportunity when using --forecast with a period argument.
  (Stephen Morgan)

Docs

- run, repl: doc fixes (Pranesh Prakash, Simon Michael)


# 1.42 2025-03-07

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
- new/updated: ACHIEVEMENTS, CREDITS, FINANCE, MOCKUPS, REGRESSIONS, RELEASING, Scripts
- examples/csv: pooltool-rewards.csv.rule cleanup
- examples: some sample hledger run scripts
- examples: test files for CSV encoding [#2319]

Scripts/addons

- hledger-balance-as-budget properly applies commodity styles now. (Dmitry Astapov)

- hledger-git now runs pass-through git commands in the right repo.

- hledger-git now checks for a git repo more robustly. (Lars Kellogg-Stedman)

- hledger-jj is another easy CLI for keeping hledger files in version control,
  using newer tech (jujutsu and oil shell's ysh).

- hledger-script-example.hs has had some cleanup.


# 1.41 2024-12-09

Breaking changes

- Accounts named "equity:conversion", "equity:trading", or "equity:trade(s)",
  which are detected as type `V`/`Conversion`, will now revert to type `E`/`Equity` instead
  if any other account has been declared as type `V`/`Conversion`.

- When built with ghc 9.10.1, hledger shows two extra newlines after any error message.

Fixes

- A somewhat severe, though hopefully rare, valuation bug has been fixed.
  In certain circumstances, values could be calculated inaccurately,
  because of display-rounding occurring inappropriately during calculations. [#2254]

  Specifically:
  when there was no direct P price for the target commodity,
  so that hledger had to convert via a chain of prices,
  and if all of those price amounts had too few decimal places,
  then the result could be inaccurate.
  An example:

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
 
- `bs`/`bse`/`cf`/`is`'s HTML output no longer includes excess heading cells,
  and `bs`/`bse`'s HTML output no longer shows an inappropriate Total heading with `-T`.
  (`balancesheet` does not support `-T`.)
  (Henning Thielemann)

- Balance commands' HTML, CSV and FODS output now show tree mode properly indented
  (using no-break spaces).
  (Henning Thielemann)

- In the HTML output of `bs`/`bse`/`cf`/`is` reports, Net amounts in the Net row are now formatted like the others.
  (Bas van Dijk)

- In `bs`/`bse`/`cf`/`is` HTML output, some unnecessary TH cells have been fixed.
  [#2225] (Henning Thielemann)

- The `print` command now ignores a depth limit entirely.
  Previously, a depth limit caused it to show only transactions referencing accounts as deep or deeper than that.

- In the `roi` command, a division by zero error (when all assets were sold) has been fixed.
  [#2281] (Dmitry Astapov) 

- In a multi-line comment generated by CSV rules, tags on all lines now work (ie, can be matched).
  Posting dates in comments generated from CSV also now [work](https://hledger.org/hledger.html#comment-field).
  [#2241]

- hledger's bash shell completions are now up to date with the latest CLI.
  [#986]

- When showing output with a pager, if `$PAGER` is set to something not found in PATH,
  we now ignore it instead of raising an error.

- `hledger --color=yes | less -R` now shows bold headings as you'd expect.

Features

- The `print`, `register` and `aregister` commands now support HTML and FODS output,
  and the `bs`/`bse`/`cf`/`is` commands now support FODS output.
  This means all of the "STANDARD REPORTS" commands, and the `balance` command, now support text, HTML, CSV, TSV, or FODS output.
  (Henning Thielemann)

- When generating HTML output with the register or balance commands,
  the `--base-url` option will add hyperlinks to hledger-web,
  allowing you to view the detailed transactions if you have hledger-web running.
  (Henning Thielemann)

- Reports can now specify different display depths for certain accounts,
  rather than showing all accounts with the same depth limit.
  Multiple `--depth=ACCTREGEX=DEPTH` options (or `depth:ACCTREGEX=DEPTH` arguments can be used.
  For example, this will clip all accounts matching "assets" to depth 3,
  all accounts matching "expenses" to depth 2, and all other accounts to depth 1:
  `--depth assets=3 --depth expenses=2 --depth 1`
  (Stephen Morgan, #2292)

- In unix-like environments, hledger now uses a pager (`$PAGER`, `less`, or `more`)
  for all large terminal output, not just for help.
  You can override this with the new `--pager` option.
  The pager is expected to handle hledger's ANSI colour output (unless you disable that).
  If `less` is used, it will be configured automatically,
  or you can override this by setting options in a `HLEDGER_LESS` environment variable.

- The `print` command's `beancount` output is now much more Beancount-compatible [#2295].
  Other than using `--alias` to provide the top-level account names Beancount requires,
  you should rarely have to do anything special to produce a journal that `bean-check` accepts.
  hledger will automatically adjust problematic names, encode unsupported characters, and so on.
  See [hledger: Beancount output](https://hledger.org/dev/hledger.html#beancount-output) for the full details.

  This supersedes the `ledger2beancount` tool, and makes using Beancount tools,
  especially Fava, practical for hledger users. In many cases this should just work:
  ```
  hledger [ALIASES] print -o tmp.beancount; fava tmp.beancount
  ```

Improvements

- `if` blocks in CSV rules now allow `& !` (AND NOT) on the same line.

- When reading `.latest` files, whitespace is now ignored, and any date parse failure
  is reported with the file and line number.

- In journal format, P directives now require a space after the first symbol,
  preventing surprises like `P 2024-10-31 a0 1` parsed as `P 2024-10-31 a 01`.
  [#2280]

- `aregister` has a new `--heading=YN` option, for disabling the report heading. (Henning Thielemann)

- `aregister` now supports the `--invert` and `--cumulative` flags, like the `register` command. (Henning Thielemann)

- The balance commands' HTML and FODS output now shows table borders consistently.
  (Henning Thielemann)

- In the balance commands' HTML output, row headings now span multiple rows when appropriate, rather than being repeated.
  (Henning Thielemann)

- Balance commands now support `--transpose` when generating HTML output.
  (Henning Thielemann)

- The `balance` command's `--layout=tidy` now affects HTML and FODS output at least to some extent (not just CSV output).
  And it always disables the totals row. (Henning Thielemann)

- The `balance` command's FODS output now picks a report title based on the report mode:
  "Balance Report", "Multi-period Balance Report", or "Budget Report". (Henning Thielemann)

- `balance` and `aregister`'s HTML output will now use a hledger.css file if present, like `bs`/`bse`/`cf`/`is`.

- `bs`/`bse`/`cf`/`is` now support the `--count` (postings count) report type, like `balance`.

- The balance commands' options help has had some cleanup.

- The error messages from `check accounts` and `check recentassertions` are now clearer.

- The `check commodities` command now also checks commodities used in P directives. [#2280]

- The `commodities` command now also list commodities mentioned in P directives. [#2280]

- All of hledger's internal hidden (but searchable) tags can now be made visible 
  by `print --verbose-tags`,  which is useful for troubleshooting `--infer-equity`,
  `--infer-costs`, and the detection of redundant costs and conversion postings.
  Also,

  - Some hidden tags have been renamed for clarity:
    `_modified` is now `_modified-transaction`,
    `_cost-matched` is now `_cost-posting`,
    `_conversion-matched` is now `_conversion-posting`.
  - The `generated-posting:` tag added by `--infer-equity` is now valueless.
  - The `modified-transaction:` tag added by `--auto` now appears on its own line.

- Using the `-NUM` shortcut (for `--depth NUM`) in a config file now works.

- Setting the `--color` option in a config file now works
  (except it does not affect `--debug` output, currently).

- The `--color` option's suggested values are now `yes`/`y`, `no`/`n`, or `auto`/`a`.
  `always` and `never` are no longer documented, though still supported.

- More compact and informative `--debug=2` output during valuation.
  Market prices are now shown using one line each, the known prices
  are listed, and the status of `--infer-market-prices` is shown.
  [#2287]

- More informative `--debug=7` output from CSV rules.

- The hledger packages have a new `debug` build flag. Builds made with ghc 9.10+ and this flag
  will show some kind of stack trace if the program exits with an error.
  (These will improve in future ghc versions.)

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


# 1.40 2024-09-09

Fixes

- Account tags (and type declarations) declared in multiple files are now combined correctly. [#2202]

- Several kinds of report interval now choose a better start date:
  - `every Nth day of month from DATE` with periodic transactions [#2218]
  - `every M/D from DATE`
  - `every Nth WEEKDAY from DATE`

- The balance commands' HTML output no longer repeats the "Total" and
  "Net" headings when the totals row has multiple lines.
  And the layout has been improved and made more consistent with the
  text output.

- The `--tldr` flag now also works with the `tealdeer` tldr client.
  
- `hledger check tags` no longer warns about the internal `_price-matched` tag
  being undeclared (and that tag has been renamed to `_cost-matched`).
  [#2247]

- `hledger check accounts` no longer warns about the special `equity:conversion` account
  being undeclared (the default account used by `--infer-equity`).

Features

- You can now save command line options in a [config file](https://hledger.org/hledger.html#config-file),
  to be added to your hledger commands either on demand or automatically.
  (This supersedes the older arguments files feature.)

  This much-requested new feature has pros and cons, and is experimental;
  your testing and feedback is welcome.
  It changes the nature of hledger somewhat, which I have marked by
  giving this release a more memorable version number (1.40).

- The balance commands can now output in FODS format, an XML spreadsheet
  file format readable by LibreOffice. (Henning Thielemann)

- The `register` report can now be sorted by date, account, amount,
  absolute amount, description, or a combination of these. (Michael Rees, [#2211])

Improvements

- All the balance-like commands now support FODS output, not just `balance`.
  (Henning Thielemann)

- Config files can now also provide the command name.
  If the first thing in a config file's general section is a non-flag argument,
  that will be used as the command name argument,
  taking precedence over any command line arguments.
  This makes config files strictly more powerful than the older argument files.

- Improved debug output for command line and config file processing.

- The print command's beancount output is now better at producing Beancount-ready data,
  converting hledger account names and commodity names to Beancount-compatible ones.

- Command line processing has been overhauled and should be more robust
  in certain cases, with tweaked error messages and debug output.
  Command-specific flags can now optionally appear before the command name.
  (Though writing them afterward is usually more readable.
   Addon-specific flags must still come last, after `--`.)

- The `--rules-file` option has been renamed to `--rules`.
  The old spelling is still supported as a hidden option.

- Weekly reports' week headings are now more compact, especially in
  single-year balance reports. ([#2204], Victor Mihalache)

- The `balance` command with no report interval, and also `balance --budget`,
  now support html output. (Henning Thielemann)

- In balance commands' html and csv output, "Total:" and "Net:" headings
  are now capitalised consistently.

- `bs`/`cf`/`is` reports now show the report interval in their title.

- The balance commands' text output with the `--pretty` flag now shows
  an outer table border and inter-column borders.

- The `check recentassertions` error message is now more readable.

- Timedot format now allows comment lines to be indented.

- When running the `tldr-node-client` client, auto-update of the tldr
  database is now suppressed.

- When running a tldr client fails, the warning now mentions the required
  `--render` flag. [#2201]

- The error message for unsupported regular expressions like `(?:foo)` has
  been improved.

- `--debug` has moved to "General help flags", making it available in
  more situations.

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



# 1.34 2024-06-01

Breaking changes

- `check ordereddates` no longer supports `--date2`.
  Also (not a breaking change): `--date2` and secondary dates are now officially
  [deprecated](https://hledger.org/1.34/hledger.html#secondary-dates) in hledger,
  though kept for compatibility.

Features

- You can now get a quick list of example command lines for hledger or
  its most useful subcommands by adding the `--tldr` flag (or just
  `--tl`).  For best appearance you should install the [`tldr`][tldr] client,
  though it's not required.

  These short "tldr pages" are a great counterbalance to verbose PTA docs.
  You can also use `tldr` without hledger to view the latest versions, or translations:\
  `tldr hledger[-COMMAND]`.
  Or you can [browse tldr pages online](https://tldr.inbrowser.app/search?query=hledger+).
  Consider contributing translations!
  More tips at <https://github.com/plaintextaccounting/hledger/tree/master/doc/tldr>.

[tldr]: https://tldr.sh

Improvements

- The `hledger` commands list has been reorganised,
  with commands listed roughly in the order you'll need them.

- The general flags descriptions in `--help` have been updated and grouped.

- Correctness checks now run in a documented order.  `commodities` are
  now checked before `accounts`, and `tags` before `recentassertions`.
  When both `ordereddates` and `assertions` checks are enabled,
  `ordereddates` now runs first, giving more useful error messages.

- `-I`/`--ignore-assertions` is now overridden by `-s`/`--strict`
  (or `check assertions`), enabling more flexible workflows.
  Eg you can `alias hl="hledger -I"` to delay balance assertions
  checking until you add `-s` to commands.

- `--color` and `--pretty` now also accept `y` or `n` as argument.

- When built with the `ghcdebug` flag and started with `--debug=-1`,
  hledger can be controlled by [ghc-debug] clients like
  ghc-debug-brick or a ghc-debug query script, for analysing
  memory/profile info.

[ghc-debug]: https://gitlab.haskell.org/ghc/ghc-debug

Fixes

- `hledger COMMAND --man` and `hledger help TOPIC --man` now properly scroll
  the man page to the TOPIC or COMMAND heading.
  The exact/prefix matching behaviour has been clarified in `help --help`.

- In journal files, `include` directives with trailing whitespace are now parsed correctly.

- The help command's help flags are now consistent with other commands
  (and it has `--debug` as a hidden flag).

- Build errors with GHC 8.10 have been fixed. [#2198]

Docs

- The tables of contents on hledger.org pages now just list top-level headings,
  (and the hledger manual structure has been adjusted for this).
  This makes the hledger manual on hledger.org more scannable and less scary.
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

- Added `hledger-pricehist`, an alias for the `pricehist` market price
  fetcher so that it can appear in hledger's commands list.

[#2005]: https://github.com/plaintextaccounting/hledger/issues/2005
[#2198]: https://github.com/plaintextaccounting/hledger/issues/2198


# 1.33.1 2024-05-02

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

[#2149]: https://github.com/plaintextaccounting/hledger/issues/2149
[#2196]: https://github.com/plaintextaccounting/hledger/issues/2196


# 1.33 2024-04-18


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
- examples: shared-finances/



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



[#815]:  https://github.com/plaintextaccounting/hledger/issues/815
[#1056]: https://github.com/plaintextaccounting/hledger/issues/1056
[#2071]: https://github.com/plaintextaccounting/hledger/issues/2071
[#2088]: https://github.com/plaintextaccounting/hledger/issues/2088
[#2119]: https://github.com/plaintextaccounting/hledger/issues/2119
[#2135]: https://github.com/plaintextaccounting/hledger/issues/2135
[#2135]: https://github.com/plaintextaccounting/hledger/issues/2135
[#2148]: https://github.com/plaintextaccounting/hledger/issues/2148
[#2151]: https://github.com/plaintextaccounting/hledger/issues/2151
[#2151]: https://github.com/plaintextaccounting/hledger/issues/2151
[#2158]: https://github.com/plaintextaccounting/hledger/issues/2158
[#2159]: https://github.com/plaintextaccounting/hledger/issues/2159
[#2164]: https://github.com/plaintextaccounting/hledger/issues/2164
[#2171]: https://github.com/plaintextaccounting/hledger/issues/2171
[#2176]: https://github.com/plaintextaccounting/hledger/issues/2176
[#2177]: https://github.com/plaintextaccounting/hledger/issues/2177
[#2178]: https://github.com/plaintextaccounting/hledger/issues/2178
[#2189]: https://github.com/plaintextaccounting/hledger/issues/2189
[#2190]: https://github.com/plaintextaccounting/hledger/issues/2190
[#2191]: https://github.com/plaintextaccounting/hledger/issues/2191


# 1.32.3 2024-01-28

Fixes

- A performance slowdown since 1.29, especially noticeable with many
  accounts and transactions, has been fixed. [#2153]

- Balance assertions involving mixed-cost balances are checked correctly again
  (a regression in 1.30). [#2072], [#2137], [#2150]

- import --catchup works again (a regression in 1.32). [#2156]

- --anon is now a deprecated hidden flag that raises an error,
  but is still usable as --obfuscate (also hidden). [#2133]

- Balance assertion error messages are clearer, and show the diff again.



[#2156]: https://github.com/simonmichael/issue/2156



# 1.32.2 2023-12-31

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

# 1.32.1 2023-12-07

- Fixed: `import` with multiple files now updates .latest files correctly. (#2125)

- Fixed: `print --round=hard` now properly pads/rounds amounts with inferred costs. (#2123)

- CSV matcher syntax: mention that ! and & can't be used in the same line yet. (#2088)

- Drop the "a difference of ..." line from balance assertion failure output.
  I feel it made the message harder to read and isn't really necessary.

- Declaring the empty payee name with `payee ""` now works,
  to let `hledger check payees` accept payee-less transactions.
  (#2119)

- Built-in tags with special meaning like `type:` and `t:` are now implicitly declared,
  so using type: in account declarations or generating t: with timedot letters 
  won't cause `hledger check tags` to fail.
  (#2119)

# 1.32 2023-12-01

Breaking changes

- Display styles and display precision are now managed more carefully
  during calculations and output, fixing a number of issues (#2111,
  "Precisiongeddon").  In brief:

  - Cost and value reports, such as `print -V`, now (1) consistently
    apply commodity display styles, and (2) do not add or discard
    decimal digits unnecessarily.  (#2105)
  
  - When "infinite decimals" arise during calculations (eg in value
    reports, or in `prices` or `roi` output), these are now shown
    limited to 8 decimal digits rather than 255.
  
  - Non-print-like reports no longer add trailing decimal marks to
    disambiguate digit group marks (this was an unintended regression
    in 1.31). (#2115)
    
  - We now document number formatting adjustments made in certain
    reports and output formats (hledger manual > REPORTING CONCEPTS >
    Amount formatting, parseability).


Features

- Timedot format supports a new letters syntax for easier tagged time logging.
  (#2116)

- `print` has a new `beancount` output format for exporting to Beancount.
  This prints journal output more likely (though not guaranteed) to
  be readable by Beancount.

- In CSV rules, matchers using regular expressions can now interpolate
  their matched texts into the values they assign to fields (field
  assignment values can reference match groups).
  (#2009) (Jonathan Dowland)
  
- In CSV rules, matchers can be negated by prepending `!`.
  (#2088) (bobobo1618)

- Multi-column balance reports (from `bal`, `bs`, `is` etc.) can use
  the new `--summary-only` flag (`--summary` also works) to display
  just the Total and Average columns (if enabled by `--row-total` and
  `-A/--average`) and hide the rest.
  (#1012) (Stephen Morgan)

- All commands that suport csv output now also support `tsv`
  (tab-separated values) output. The data is identical, but the fields
  are separated by tab characters and there is no quoting or
  escaping. Tab, carriage return, and newline characters in data are
  converted to spaces (this should rarely if ever happen in practice).
  (#869) (Peter Sagerson).


Improvements

- Journal format no longer fails to parse Ledger-style lot costs with spaces
  after the `{`, improving Ledger compatibility.

- `import` now does not update any .latest files until it has run
  without error (no failing strict checks, no failure while writing
  the journal file). This makes it more idempotent, so you can run it
  again after fixing problems.

- `print` now shows zeros with a commodity symbol and decimal digits
  when possible, preserving more information.

- `print` has a new option for controlling amount rounding (#2085):
  
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

- The `prices` command has had a number of fixes and improvements (#2111):

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
  (#2113)

- `tag:` queries now work when reading CSV files. (#2114)

- Using a `.json` or `.sql` file extension with `-o`/`--outputfile`
  now properly selects those output formats.

- Auto postings no longer break redundant equity/cost detection and
  transaction balancing. (#2110)
  
- Amounts set by balance assignment now affect commodity styles again.
  (#2091, a regression in 1.30)

- Timedot quantities with units are parsed more accurately.
  Eg a quantity like "15m" was evaluated as 0.249999999 not 0.25,
  and since hledger 1.21, it was printed that way also.
  Now we round such quantities to two places during parsing to get
  exact quarter-hour amounts. (#2096)

- The `demo` command no longer triggers a JSON decode error in asciinema
  2.3.0. It now also shows a better error message if asciinema fails
  (#2094).

- Failing balance assertions with a cost now show correct markers in
  the error message. (#2083)


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

  
# 1.31 2023-09-03

Features

- Multi-pivot: the --pivot option now accepts multiple arguments,
  colon-delimited, to construct account names from multiple fields.
  (#2050, Eric Mertens)

Improvements

- The `print` command now more closely replicates the original journal
   amount styles, which is helpful when round-tripping / cleaning up
   journal files:

  - Amounts in conversion transactions could be displayed rounded to a
    lower precision; this no longer happens.
    (#2079)

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
  and --infer-market-prices.  (#2045)

- In journal files, equity conversion postings are now detected more
  tolerantly, using the same precision as the conversion posting's
  amount (#2041). Eg, the following transaction is now accepted:

      2023-01-01
          Assets               -8401USD  @  2.495 GEL
		    ; ^ 209.60495 GEL, recognised as a match for the 209.60 below
          Equity:Conversion     84.01 USD
          Equity:Conversion   -209.60 GEL
          Assets               209.60 GEL

- The roi command now reports TWR per period and overall TWR for
  multi-period reports.
  (#2068, Dmitry Astapov)

- The commands list no longer shows bar when hledger-bar is not installed (#2065),
  and had a few other cleanups.

# 1.30.1 2023-06-02

Fixes

- Add missing files to Hackage release, making it buildable.

Docs

- Replace note about repeated options.

# 1.30 2023-06-01

Breaking changes

- The CSV reader now properly skips all empty lines, as specified by docs.
  Previously, inner empty lines were not being skipped automatically.
  You might need to adjust the `skip` count in some CSV rules files.
  (#2024)

- Timedot format now generates a single multi-posting transaction per
  date line, and supports comments and tags on all lines.
  (#1754)

- Timeclock format now supports comments and tags.
  Descriptions can no longer contain semicolons.
  (#1220)

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
  (#2015)

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
  (#1770)

Fixes

- Unbalanced virtual postings with no amount always infer a zero amount.
  This is fixing and clarifying the status quo; they always did this,
  but print always showed them with no amount, even with -x, and
  the behaviour was undocumented.

- On windows systems with multiple drive letters, the commands list
  could fail to show all installed add-ons.
  (#2040)

- Balancing a transaction with a balance assignment now properly respects costs.
  (#2039)

- The commands list no longer lists non-installed addons.
  (#2034)

- Since hledger 1.25, "every Nth day of month" period rules with N > 28 could
  be calculated wrongly by a couple of days when given certain forecast start dates.
  Eg `~ every 31st day of month` with `--forecast='2023-03-30..'`.
  This is now fixed.
  (#2032)

- Postings are now processed in correct date order when inferring balance assignments.
  (#2025)

- Posting comment lines no longer disrupt the underline position in error messages.
  (#1927)

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

# 1.29.2 2023-04-07

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

  (#2020)

Fixes

- `type:` queries now "see through" account aliases and pivots,
  as they did in hledger <1.27, and as `acct:` queries do.
  (#2018)

- The corruption in 1.29's info manual is fixed. (#2023)

- The 1.29 release notes for periodic reports'/periodic transactions' start dates
  have been improved. Also the hledger manual's "Date adjustment" section
  has been corrected and clarified.


# 1.29.1 2023-03-16

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

- Allow building with GHC 9.6.1 (#2011)

Fixes

- The stats report no longer displays "Exact" in front of dates. (#2012)

Docs

- remove duplicate in `hledger close` docs (Yehoshua Pesach Wallach)

# 1.29 2023-03-11

Breaking changes

- Periodic reports will now start exactly at the start date you have specified,
  rather than being adjusted to a natural period boundary; see below.

- The `close` command's CLI and default behaviour was changed; see below
  (and fixes in hledger 1.29.2+).

Features

- Periodic transactions and periodic reports can now start on any date.
  Eg, `hledger reg -M -b 1/15` now starts exactly on jan 15th, and a periodic rule
  like `~ monthly from 2023-01-15` now works as you'd expect instead of raising an error.
  This also improves our ability to read Ledger files.
  Inferred start/end dates, eg obtained from the journal instead of the command line,
  are still automatically adjusted to period boundaries, as before.

  Upgrade notes: in report commands which specify a start date, you might need to
  adjust that date to see the same periods as before. Eg:
  
  - `-p 'weekly from 202304'` (equivalent to `-p 'weekly from 20230401'`)
    now gives periods like `2023-04-01..2023-04-07`.
    Change it to start on a monday (eg `-p 'weekly from 20230403`) to restore
    simple week periods like `2023-04-03W14`.

  - `-M -b 2023/1/15` now gives periods like `2023-01-15..2023-02-14  2023-02-15..2023-03-14`.
    Change it to start on a first of month (eg `-M -b 2023/1`) to restore
    simple month periods like `Jan  Feb  Mar`.

  (#1982)

- You can now freely combine @/@@ notation and conversion postings
  in a single transaction. This can help readability, and also allows
  more flexibility when recording cost.  hledger will check that the
  two notations are in agreement, and ignore the redundancy if they are.
  (Conversion postings are postings to accounts with type `V`/`Conversion`
  or name `equity:conversion`/`equity:trade`/`equity:trading`,
  or subaccounts of these. See also COST.)

- In journal format there is now a `tag` directive for declaring tag names,
  and the check command now has a `tags` check to enforce use of declared tag names.

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
  (#1996) (Jonathan Dowland)

- aregister now shows a " (matching query)" hint in report title 
  when extra query args (other than date: or depth:) are used,
  to reduce confusion.

- The `close` command's CLI and default behaviour were changed,
  attempting to make it easier to understand and use.  Some of its
  legacy flags and aliases were also dropped, without sufficient
  warning. For the full details, including subsequent cleanups,
  see hledger 1.29.2's change notes.

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
  file compatibility (#1962).  We now test our ability to at least
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
  (#1978)

Fixes

- aregister now handles an extra account query correctly. (#2007)

- balance's `--help` now mentions `--layout=tidy`

- Balance commands with `--layout=bare` now generate proper table
  layout in HTML output.

- register's `-w`/`--width` option no longer gives ugly parse error messages.

- stats's `--help` no longer wrongly claims to support -O/--output-format.

- Balance assignments with a cost now generate a correct balance assertion. (#1965)

- The CSV reader now properly skips header lines before attempting to parse records. (#1967)

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
- csv, timeclock, timedot: clarify comment lines (#1953)
- csv: add new coinbase example
- csv: clarify amount-in/amount-out docs (#1970)
- csv: clarify skip/valid csv semantics (#1967)
- csv: clarify valid CSV requirements and issues (fix #1966)
- csv: cleanup, reorder, CSV rules tips -> Working with CSV
- csv: fix wrong if tables doc; rewrite several sections (#1977)
- csv: flatten, clean up CSV sections
- csv: improve Amount field / Setting amounts
- csv: note -in and -out are used together for one posting (#1970)
- csv: rules factoring tips
- csv: try to clarify how CSV fields and hledger fields work
- document --infer-market-prices with signed costs (#1870)
- fix duplicate market prices heading breaking info navigation
- import: note a pitfall with multifile import
- improve Directives summaries
- introduction/input/output improvements
- journal: cheatsheet: clarify date tag
- journal: rewrite Account names, mention brackets/parentheses (#1915)
- mention pivoting on a tag with multiple values (#1950)
- more cost notation docs; describe Ledger and Beancount cost notation
- more mention of posting order effect on inferring cost (#1959)
- period expressions doc updates
- Removed redundant paragraph in documentation. (J. B. Rainsberger)
- rename directive sections, fix many links
- reorganise commands list, like the CLI
- reorganise bin/README & the Scripts page, add entries for recent scripts
- replace "transaction prices" terminology with "costs"
- tags: discuss multi-values/overriding (#1950)
- update market price inference docs per sol
- Updated section on pivoting. Used synonyms for "member" in cases where there could be confusion with the tag named "member." (Robert Nielsen)
- use more standard and consistent boilerplate in hledger, ui, web man pages
- virtual postings: improve wording per Robert Nielsen


# 1.28 2022-12-01

Features

- The `accounts` command has new flags: `--undeclared` (show accounts used but not declared), `--unused` (show accounts declared but not used),  and `--find` (find the first account matched by the first command argument, a convenience for scripts). Also `-u` and `-d` short flags have been added for `--used` and `--declared`.

- A new CSV rule `intra-day-reversed` helps generate transactions in correct order with CSVs where records are reversed within each day.

- CSV rules can now correctly convert CSV date-times with a implicit or explicit timezone to dates in your local timezone. Previously, CSV date-times with a different time zone from yours could convert to off-by-one
  dates, because the CSV's timezone was ignored.
  Now,

  1. When a CSV has date-times with an implicit timezone different from yours, you can use the `timezone` rule to declare it.

  2. CSV date-times with a known timezone (either declared by `timezone` or parsed with `%Z`) will be localised to the system timezone
     (or to the timezone set with the `TZ` environment variable).

  (#1936)
  
Improvements

- print --match now respects -o and -O.

- print --match now returns a non-zero exit code when there is no acceptable match.

- Support megaparsec 9.3. (Felix Yan)

- Support GHC 9.4.

Fixes

- In CSV rules, when assigning a parenthesised account name to   `accountN`, extra whitespace is now ignored, allowing unbalanced postings to be detected correctly.

Scripts/addons

- bin/hledger-move helps record transfers involving subaccounts and costs,
  eg when withdrawing some or all of an investment balance containing many lots and costs.

- bin/hledger-git no longer uses the non-existent git record command.
  (#1942) (Patrick Fiaux)

- bin/watchaccounts is a small shell script for watching the account tree as you make changes.

# 1.27.1 2022-09-18

Fixes

- Balance commands using `-T -O html` no longer fail with an error
  when there is no data to report.
  (#1933)

# 1.27 2022-09-01

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
  (#1436)

- The accounts command has a new --directives flag which makes it
  show valid account directives which you can paste into a journal.

- The accounts command has a new --positions flag which shows where
  accounts were declared, useful for troubleshooting.
  (#1909)

- Bump lower bounds for Diff and githash. (Andrew Lelechenko)

- GHC 8.6 and 8.8 are no longer supported. Building hledger now
  requires GHC 8.10 or greater.

Fixes

- Account display order is now calculated correctly even when accounts
  are declared in multiple files.
  (#1909)

- At --debug 5 and up, account declarations info is logged.
  (#1909)

- hledger aregister and hledger-ui now show transactions correctly
  when there is a type: query.
  (#1905)

- bal: Allow cumulative gain and valuechange reports.
  Previously, --cumulative with --gain or --valuechange would produce an
  empty report. This fixes this issue to produce a reasonable report.
  (Stephen Morgan)

- bal: budget goal amounts now respect -c styles (fixes #1907)

- bal: budget goals now respect -H (#1879)

- bal: budget goals were ignoring rule-specified start date

- cf/bs/is: Fixed non-display of child accounts when there is an
  intervening account of another type.
  (#1921) (Stephen Morgan)

- roi: make sure empty cashflows are skipped when determining first cashflow (Charlotte Van Petegem)
  Empty cashflows are added when the begin date of the report is before the first
  transaction.

Scripts/addons

- https://hledger.org/scripts.html - an overview of scripts and addons in bin/.

- paypaljson, paypaljson2csv - download txns from paypal API

- hledger-check-postable.hs - check that no postings are made to accounts with a postable:(n|no) tag

- hledger-addon-example.hs - script template


# 1.26.1 2022-07-11

- require safe 0.3.19+ to avoid deprecation warning

# 1.26 2022-06-04

Improvements

- `register` and `aregister` have been made faster, by 

  - considering only the first 1000 items for choosing column
    widths. You can restore the old behaviour (guaranteed alignment
    across all items) with the new `--align-all` flag.
    ([#1839](https://github.com/plaintextaccounting/hledger/issues/1839), Stephen Morgan)

  - discarding cost data more aggressively, giving big speedups for
    large journals with many costs.
  	([#1828](https://github.com/plaintextaccounting/hledger/issues/1828), Stephen Morgan)

- Most error messages from the journal reader and the `check` command now use
  a consistent layout, with an "Error:" prefix, line and column numbers,
  and an excerpt highlighting the problem. Work in progress.
  ([#1436](https://github.com/plaintextaccounting/hledger/issues/1436)) (Simon Michael, Stephen Morgan)

- `hledger check ordereddates` now always checks all transactions
  (previously it could be restricted by query arguments).

- The `--pivot` option now supports a `status` argument, to pivot on transaction status.

- Update bash completions (Jakob Schöttl)

Fixes

- Value reports with `--date2` and a report interval (like `hledger bal -VM --date2`)
  were failing with a "expected all spans to have an end date" error since 1.22;
  this is now fixed.
  ([#1851](https://github.com/plaintextaccounting/hledger/issues/1851), Stephen Morgan)

- In CSV rules, interpolation of a non-existent field like `%999` or `%nosuchfield`
  is now ignored (previously it inserted that literal text).
  Note this means such an error will not be reported; 
  Simon chose this as the more convenient behaviour when converting CSV.
  Experimental.
  ([#1803](https://github.com/plaintextaccounting/hledger/issues/1803), [#1814](https://github.com/plaintextaccounting/hledger/issues/1814)) (Stephen Morgan)

- `--infer-market-price` was inferring a negative price when selling.
  ([#1813](https://github.com/plaintextaccounting/hledger/issues/1813), Stephen Morgan)

- Allow an escaped forward slash in regular expression account aliases.
  ([#982](https://github.com/plaintextaccounting/hledger/issues/982), Stephen Morgan)

- The `tags` command now also lists tags from unused account declarations.
  It also has improved command-line help layout.
  ([#1857](https://github.com/plaintextaccounting/hledger/issues/1857))

- `hledger accounts` now shows its debug output at a more appropriate level (4).

# 1.25 2022-03-04

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

  ([#1820](https://github.com/plaintextaccounting/hledger/issues/1820), 
  [#1822](https://github.com/plaintextaccounting/hledger/issues/1822)) 
  (Simon Michael, Stephen Morgan)

- The `tag:` query can now also match account tags, as defined in account directives.
  Subaccounts inherit tags from their parents.
  Accounts, postings and transactions can be filtered by account tag.
  ([#1817](https://github.com/plaintextaccounting/hledger/issues/1817))

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

  ([#1554](https://github.com/plaintextaccounting/hledger/issues/1554)) (Stephen Morgan, Simon Michael)

- Balance commands (`bal`, `bs` etc.) can now generate easy-to-process "tidy" CSV data 
  with `-O csv --layout tidy`.
  In tidy data, every variable is a column and each row represents a single data point 
  (cf <https://vita.had.co.nz/papers/tidy-data.html>).
  ([#1768](https://github.com/plaintextaccounting/hledger/issues/1768), 
  [#1773](https://github.com/plaintextaccounting/hledger/issues/1773), 
  [#1775](https://github.com/plaintextaccounting/hledger/issues/1775)) 
  (Stephen Morgan)

Improvements

- Strict mode (`-s/--strict`) now also checks periodic transactions (`--forecast`) 
  and auto postings (`--auto`). 
  ([#1810](https://github.com/plaintextaccounting/hledger/issues/1810)) (Stephen Morgan)

- `hledger check commodities` now always accepts zero amounts which have no commodity symbol. 
  ([#1767](https://github.com/plaintextaccounting/hledger/issues/1767)) (Stephen Morgan)

- Relative [smart dates](hledger.html#smart-dates) may now specify an arbitrary number of some period into the future or past).
  Some examples:
  - `in 5 days`
  - `in -6 months`
  - `5 weeks ahead`
  - `2 quarters ago`
  
  (Stephen Morgan)

- CSV output now always disables digit group marks (eg, thousands separators),
  making it more machine readable by default. 
  ([#1771](https://github.com/plaintextaccounting/hledger/issues/1771)) (Stephen Morgan)

- Unicode may now be used in field names/references in CSV rules files.
  ([#1809](https://github.com/plaintextaccounting/hledger/issues/1809)) (Stephen Morgan)

- Error messages improved:
  - Balance assignments
  - aregister
  - Command line parsing (less "user error")

Fixes

- `--layout=bare` no longer shows a commodity symbol for zero amounts. 
  ([#1789](https://github.com/plaintextaccounting/hledger/issues/1789)) (Stephen Morgan)

- `balance --budget` no longer elides boring parents of unbudgeted accounts 
  if they have a budget. 
  ([#1800](https://github.com/plaintextaccounting/hledger/issues/1800)) (Stephen Morgan)

- `roi` now reports TWR correctly

  - when there are several PnL changes occurring on a single day
  - and also when investment is fully sold/withdrawn/discounted at the end of a particular reporting period.

  ([#1791](https://github.com/plaintextaccounting/hledger/issues/1791)) (Dmitry Astapov)

Documentation

- There is a new CONVERSION & COST section, replacing COSTING. 
  ([#1554](https://github.com/plaintextaccounting/hledger/issues/1554))

- Some problematic interactions of account aliases with other features have been noted. 
  ([#1788](https://github.com/plaintextaccounting/hledger/issues/1788))

- Updated: [Declaring accounts > Account types](https://hledger.org/hledger.html#account-types)

# 1.24.1 2021-12-10

Fixes

- `balance --declared` is now filtered correctly by a `not:ACCT` query.
  (#1783)

- More reliable --version output, with commit date and without patch level.

API changes:

- new type synonyms ProgramName, PackageVersion, VersionString
- versionStringForProgname -> versionString with extra argument
- versionStringFor -> versionStringWith with extra argument

# 1.24 2021-12-01

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
  (#1765)

- journal files now support a `decimal-mark` directive as a more
  principled way (than `commodity` directives) to specify the decimal character
  in use in that file, to ensure accurate number parsing.
  (#1670, Lawrence Wu)

Improvements

- The stats command now shows rough but useful performance stats: run
  time and processing speed in transactions per second.

- balance: support the --related flag, like register, showing the
  other postings from the transactions. (#1469, Stephen Morgan)

- roi now uses posting dates when available, and honors the --date2
  flag. This will not change the results computed for the typical
  use-case, it just makes "roi" more thorough/consistent.
  (Dmitry Astapov)

- aregister now shows transactions' secondary date if the --date2 flag is used.
  (#1731)

- timedot: a D default commodity (and style) declared in a parent
  journal file will now be applied to timedot amounts. This means they
  can be priced and valued/converted.

- cli: The --pretty and --forecast options can now be written after the
  command name, like other general options.
  (Stephen Morgan)

- register -V -H with no interval now values at report end date, like balance.
  (#1718, Stephen Morgan)

- Allow megaparsec 9.2.

- Drop the base-compat-batteries dependency. (Stephen Morgan)

Fixes

- prices: Do not include zero amounts when calculating amounts for balance assignments. (#1736) (Stephen Morgan)
  This is not usually a problem, but can get in the way of auto-inferring prices.

- csv: Successfully parse an empty csv file. (#1183) (Stephen Morgan)

- balance: Balance reports with --depth=0 properly report aggregated
  values, not zero everywhere. (#1761) (Stephen Morgan)

- prices: Do not try to generate prices when there would be a zero
  denominator. Also correctly generate reverse prices for zero
  amounts. (Stephen Morgan)

- csv: Allow both amount-in and amount-out fields to contain a zero.
  (#1733, Stephen Morgan)

- balance: Balance reports should consider date: queries when
  calculating report span with --date2. (#1745, Stephen Morgan)

- print: auto: The print command should always display inferred
  amounts for --auto generated postings. (#1276, Stephen Morgan)
  
  
  
  
  
  
  
  
  
  
  
  
  
  
  
  
  
  
  
  
  
  
  
  
  
  
  
  
  
  
  
  
  
  


# 1.23 2021-09-21

Features

- The balance command has a new `--gain` report type, showing
  unrealised capital gains/losses. Essentially, this is the difference
  between the amounts' costs and their total present value. More
  precisely, between the value of the amounts' costs and the value of
  the amounts on the valuation date(s). (Ie, you can report gain in a
  different currency.)
  ([#1623](https://github.com/plaintextaccounting/hledger/issues/1623),
  [#1432](https://github.com/plaintextaccounting/hledger/issues/1432),
  Stephen Morgan, Charlotte Van Petegem)

- The new `-c/--commodity-style` option makes it easy to override
  commodity display styles at runtime, eg to adjust the number of
  decimal places or change the position of the symbol.
  ([#1593](https://github.com/plaintextaccounting/hledger/issues/1593), Arjen Langebaerd)

- The balance commands have a new `--commodity-column` flag that
  displays commodity symbols in a dedicated column, showing one line
  per commodity and all amounts as bare numbers.
  ([#1559](https://github.com/plaintextaccounting/hledger/issues/1559),
  [#1626](https://github.com/plaintextaccounting/hledger/issues/1626),
  [#1654](https://github.com/plaintextaccounting/hledger/issues/1654),
  Lawrence Wu, Simon Michael, Stephen Morgan)

- The `balance --budget` option can now take an argument,
  a case insensitive description substring which selects a subset of
  the journal's periodic transactions for setting budget goals. 
  This makes it possible to keep multiple named budgets in one journal, 
  and select the one you want with --budget's argument. 
  ([#1612](https://github.com/plaintextaccounting/hledger/issues/1612))

- Period expressions now support `every weekday`, `every weekendday` and
  `every mon,wed,...` (multiple days of the week).
  This is intended for periodic transaction rules used with
  `--forecast` (or `bal --budget`).
  ([#1632](https://github.com/plaintextaccounting/hledger/issues/1632), Lawrence Wu)

- The new `--today=DATE` option allows overriding today's date. This
  can be useful in tests and examples using relative dates, to make
  them reproducible.
  ([#1674](https://github.com/plaintextaccounting/hledger/issues/1674), Stephen Morgan)

- In CSV rules, multi-line comments are now supported. Newlines in CSV
  data are preserved, or newlines can be added by writing `\n` when
  assigning to `comment`, `comment1` etc. 
  (Malte Brandy)

Improvements

- Incremental performance improvements; hledger 1.23 is the fastest
  hledger yet, about 10% faster than 1.22. 
  (Stephen Morgan)

- `register` no longer slows down when there are many report intervals.
  ([#1683](https://github.com/plaintextaccounting/hledger/issues/1683), Stephen Morgan)

- Numbers in SQL output now always use decimal period (`.`),
  independent of commodity display styles. 
  (Stephen Morgan)

- `--sort` now gives a more intuitive sort oder when there are
   multiple commodities. Negative numbers in one commodity are always
   less than positive numbers in another commodity.
   ([#1563](https://github.com/plaintextaccounting/hledger/issues/1563), Stephen Morgan)

- `--infer-market-price` has been renamed to `--infer-market-prices`.
  (The old spelling still works, since we accept flag prefixes.)

- Our pretty-printed JSON now orders object attributes alphabetically,
  across all GHC and haskell lib versions.

- register with a report interval starting on custom dates
  (eg: `hledger reg -p "every 15th day of month") now makes the 
  date column wide enough to show the start and end dates.
  It also wastes less whitespace after the column.
  ([#1655](https://github.com/plaintextaccounting/hledger/issues/1655), Stephen Morgan)

- The --forecast option will now reject a report interval in its
  argument, instead of silently ignoring it.

- In JSON output, object attributes are now ordered alphabetically,
  consistently for all GHC and haskell lib versions. 
  ([#1618](https://github.com/plaintextaccounting/hledger/issues/1618), Stephen Morgan)

- JSON output now indents with 2 spaces rather than 4. 
  (Stephen Morgan)

- The balance commands' `-S/--sort-amount` flag now behaves more
  predictably and intuitively with multiple commodities.
  Multi-commodity amounts are sorted by comparing their amounts in
  each commodity, with alphabetically-first commodity symbols being
  most significant, and assuming zero with alphabetically-first commodity symbols being
  most significant, and assuming zero when a commodity is missing.
  ([#1563](https://github.com/plaintextaccounting/hledger/issues/1563), 
  [#1564](https://github.com/plaintextaccounting/hledger/issues/1564), Stephen Morgan)
  
- The close command now uses the later of today or journal's last day
  as default closing date, providing more intuitive behaviour when
  closing a journal with future transactions. Docs have been improved.
  ([#1604](https://github.com/plaintextaccounting/hledger/issues/1604))

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
  ([#1648](https://github.com/plaintextaccounting/hledger/issues/1648), 
  [#1665](https://github.com/plaintextaccounting/hledger/issues/1665),
  [#1667](https://github.com/plaintextaccounting/hledger/issues/1667), 
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
  ([#1698](https://github.com/plaintextaccounting/hledger/issues/1698), Stephen Morgan)

- aregister now aligns multicommodity amounts properly (broken since 1.21).
  ([#1656](https://github.com/plaintextaccounting/hledger/issues/1656), Stephen Morgan)

- `balance -E` (and hledger-ui Z) now correctly show zero parent accounts,
  fixing a bug introduced in hledger 1.19.
  ([#1688](https://github.com/plaintextaccounting/hledger/issues/1688), Stephen Morgan)

- The `roi` command no longer gives an ugly error in a certain case
  with PnL applied on the first day of investment. (Dmitry Astapov)

- `--forecast` now generates transactions up to the day before the
  specified report end date (instead of two days before).
  ([#1633](https://github.com/plaintextaccounting/hledger/issues/1633), Stephen Morgan)

- Certain errors in CSV conversion, such as a failing balance assertion,
  were always being reported as line 2.

# 1.22.2 2021-08-07

Breaking changes

- aregister no longer hides future transactions by default.
  This is a consequence of the fix for 
  [#1638](https://github.com/plaintextaccounting/hledger/issues/1638). 
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
  ([#1638](https://github.com/plaintextaccounting/hledger/issues/1638), Stephen Morgan)

- aregister preserves the order of same-day transactions again
  (broken in 1.22.1).
  ([#1642](https://github.com/plaintextaccounting/hledger/issues/1642), Stephen Morgan)

# 1.22.1 2021-08-02

Improvements

- Bash shell completions (for hledger, hledger-ui, hledger-web) are
  now included in the hledger package's release tarballs, making them
  more likely to be installed by system packages. (Jakob Schöttl)

- roi docs now discuss how to quote multi-word queries. (#1609, Dmitry
  Astapov)

- Allow megaparsec 9.1

Fixes

- `cur:` and `amt:` queries now match the original amounts before
  valuation and cost conversion, as they did before hledger 1.22. We
  believe this is the more useful behaviour in practice. (#1625)
  (Stephen Morgan)

- Queries now work better with `register --related`, no longer showing
  duplicate postings when more than one posting in a transaction is
  matched. (#1629) (Stephen Morgan)

- Valuation now works with `register --related`. (#1630) (Stephen
  Morgan)

- Auto posting rules now also see inferred amounts,
  not just explicit amounts. (#1412) (Stephen Morgan)

- Our info manuals now have more robust directory metadata (no
  subdirectory path), making them more likely to be linked in your
  top-level Info directory by system packages. (#1594) (Simon Michael,
  Damien Cassou)

- The error message for a non-existent input file no longer shows
  excess double quotes. (#1601, Stephen Morgan)

- Journal format docs: The commodity directive's scope is now
  correctly described (lasts until end of current file).

- The aregister command now properly ignores a `depth:` argument. 
  It might now also behave more correctly with valuation or `--txn-dates`.
  (#1634, Stephen Morgan)

# 1.22 2021-07-03

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
  (#1533)

- ANSI color is now also available in debug output, determined in the
  usual way by `--color`, `NO_COLOR`, and whether the output (stderr)
  is interactive.
  
- The --version flag shows more details of the build, when known: git
  tag, number of commits since the tag, commit hash, platform and
  architecture. (Stephen Morgan)

- balance: Capitalisation of "account" and "total" (and lack of a
  colon in the latter) in CSV output is now consistent for single- and
  multi-period reports.

- balance reports' CSV output now includes full account names. (#1566)
  (Stephen Morgan)

- csv: We now accept spaces when parsing amounts from CSV. (Eric
  Mertens)

- json: Avoid adding unnecessary decimal places in JSON output. (Don't
  increase them all to 10 decimal places.) (Stephen Morgan)
  
- json: Simplify amount precision (asprecision) in JSON output.
  It is now just the number of decimal places, rather than an object.
  (Stephen Morgan)

- GHC 9.0 is now officially supported, and GHC 8.0, 8.2, 8.4 are not;
  building hledger now requires GHC 8.6 or greater.

- Added a now-required lower bound on containers. (#1514)

Fixes

- Auto posting rules now match postings more precisely, respecting
  `cur:` and `amt:` queries. (#1582) (Stephen Morgan)

- balance reports: Fix empty cells when amounts are too wide to fit
  (broken since 1.20) (#1526). (Stephen Morgan)

- csv: Fix the escaping of double quotes in CSV output (broken in
  1.21). (Stephen Morgan, #1508)

- register: Fix the running total when there is a report interval
  (broken since 1.19) (#1568). (Stephen Morgan)

- stats: No longer gets confused by posting dates. (#772) (Stephen Morgan)

- timeclock: `hledger print` shows timeclock amounts with just 2
  decimal places again (broken in 1.21). (#1527)

- When all transaction amounts have the same sign, the error message
  no longer adds an inferred price. (#1551) (Stephen Morgan)

- Cleaned up some references to old man pages. (Felix Yan)

# 1.21 2021-03-10

## general

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
  https://github.com/plaintextaccounting/hledger/pull/1423 and on the hledger
  mail list. It might annoy some folks; please read the issue and do
  follow up there if needed.
  
- Notable documentation updates:
  the separate file format manuals have been merged into the hledger manual,
  the topic hierarchy has been simplified,
  the `balance` command docs and "commands" section have been rewritten.

## valuation

- Costing and valuation are now independent, and can be combined.
  `--value=cost` and `--value=cost,COMM` are still supported
  (equivalent to `--cost` and `--cost --value=then,COMM` respectively), 
  but deprecated. (Stephen Morgan)

- `-V` is now always equivalent to `--value=end`. (Stephen Morgan)

- `--value=end` now includes market price directives as well as
  transactions when choosing a valuation date for single-period
  reports. (#1405, Stephen Morgan)

- `--value=end` now picks a consistent valuation date for single- and
  and multi-period reports. (#1424, Stephen Morgan)

- `--value=then` is now supported with all reports, not just register. (Stephen Morgan)

- The too-vague `--infer-value` flag has been renamed to `--infer-market-price`.
  Tip: typing `--infer-market` or even `--infer` is sufficient.
  The old spelling still works, but is now deprecated.

## commands

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
  before. (Stephen Morgan et al, #1353)

- balance: The `--valuechange` report type has been added, showing the
  changes in period-end values. (Stephen Morgan, #1353)

- balance: With `--budget`, the first and last subperiods are enlarged
  to whole intervals for calculating the budget goals also. (Stephen
  Morgan)

- balance: In multi-period balance reports, specifying a report period
  now also forces leading/trailing empty columns to be displayed,
  without having to add `-E`. This is consistent with `balancesheet`
  etc. (#1396, Stephen Morgan)

- balancesheet, cashflow: declaring just a Cash account no longer
  hides other Asset accounts.

- check: Various improvements:

  - check name arguments may be given as case-insensitive prefixes
  - `accounts` and `commodities` may also be specified as arguments
  - `ordereddates` now checks each file separately (#1493)
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
  trailing zeroes.) (#931, #1465)

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

- roi: Now supports the valuation options (#1417), and uses commodity display styles.
  Also the manual has been simplified, with some content moved to the Cookbook.
  (Dmitry Astapov):

## journal format

- The `commodity` directive now properly sets the display style of the
  no-symbol commodity. (#1461)

## csv format

- More kinds of malformed signed numbers are now ignored, in
  particular just a sign without a number, which simplifies sign
  flipping with amount-in/amount-out.

## API

- API changes include:
  ```
  Hledger.Cli.Utils:
  +journalSimilarTransaction
  
  Hledger.Cli.Commands.Add:
   transactionsSimilarTo -> Hledger.Data.Journal.journalTransactionsSimilarTo
    and now takes a number-of-results argument
  ```


# 1.20.4 2021-01-29

- aregister: ignore a depth limit, as in 1.19 (#1468).
  In 1.20-1.20.3, aregister had stopped showing transactions in subaccounts 
  below a depth limit. Now it properly shows all subaccount transactions, 
  ensuring that the register's final total matches a balance report with 
  similar arguments.

# 1.20.3 2021-01-14

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

# 1.20.2 2020-12-28

- help: Fix loss of capitalisation in part of the hledger-ui manual. 

- Fix the info manuals' node structure.

- Drop unused parsec dependency.

# 1.20.1 2020-12-15

- bal, bs, cf, is: In amount-sorted balance reports, equal-balance accounts 
  are now reliably sorted by name. (Simon Michael, Stephen Morgan)

- help: Fix the topic hierarchy in Info manuals.

# 1.20 2020-12-05

## general

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

## commands

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

## journal format

- The journal's commodity styles are now applied to forecasted transactions. (#1371)

- journal, csv: commodity style is now inferred from the first amount, as documented,
  not the last. This was "working wrongly" since hledger 1.12..

- A zero market price no longer causes "Ratio has zero denominator" error
  in valued reports. (#1373)

## csv format

- The new `decimal-mark` rule allows reliable number parsing
  when CSV numbers contain digit group marks (eg thousands separators).

- The CSV reader's verbose "assignment" debug output is now at level 9.


# 1.19.1 2020-09-07

- Fix alignment of coloured numbers (#1345, #1349, Stephen Morgan)

- Fix a regression in account type autodetection for accounts with
  capitalised names. (#1341)

- Allow megaparsec 9

# 1.19 2020-09-01

## general

- When parsing dates, the year is now required to have at least four
  digits. So eg we no longer accept `200/1/1` as a valid date, it
  would need to be written `0200/1/1`. This was done for.. reasons,
  and is experimental; let us know if it causes you trouble.

- The --color/--colour=WHEN command line option, support for the
  NO_COLOR environment variable, and smarter autodetection of colour
  terminals have been added (#1296)

- Command line options taking a numeric argument are now validated
  more carefully, preventing issues with unexpected negatives or Int
  overflow. (Stephen Morgan)

- In queries, you can now specify a quarter like `2020q1` or `q4`
  (the q is case-insensitive). (#1247, Henning Thieleman, Stephen Morgan)

- In report intervals, `fortnightly` has been added as a synonym for
  `biweekly`. (Stephen Morgan)

- -t and -l command line flags have been added as short forms of
  --tree and --flat (#1286)

- All reports displaying accounts now choose flat mode by default
  (Stephen Morgan)

- Reports now show at most 2 commodities of multicommodity amounts,
  unless the --no-elide flag is used. This helps keep them readable by
  default, since multicolumn, multicommodity balance reports otherwise
  tend to become very wide, especially in tree mode.

- Numbers with more than 255 decimal places, which we do not support,
  now give an error instead of silently misparsing. (#1326)

- Digit groups are now limited to at most 255 digits each. (#1326)

- Account aliases (on command line or in journal) containing a bad
  regular expression now give a more detailed error message.

- A tab character could get parsed as part of a commodity symbol, with
  confusing results. This no longer happens. (#1301, Dmitry Astapov)

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

- Added a missing lower bound for aeson, making cabal installs more
  reliable. (#1268)

- lib: parseAmountQueryTerm: allow whitespace around arg parts (#1312)
  Whitespace around the operator, sign, or number is now tolerated.

## commands

- account,bal,bs,cf,is: --drop now also works in tree mode (Stephen Morgan)

- add: fix an error in the command line help (arguments are inputs,
  not a query)

- aregister: a new command showing a transaction-oriented account
  register, like hledger-ui, hledger-web, or your bank statement. 
  Each line represents a whole transaction in one account, unlike
  the register command which shows individual postings possibly from
  multiple accounts. You might prefer aregister when reconciling
  real-world asset/liability accounts, and register when reviewing
  detailed revenues/expenses. (#1294)

- bal,bs,cf,is: boring parents are now elided by default in tabular
  balance reports too, like single-column reports. (Stephen Morgan)

- bal,bs,cf,is: monthly column headings are no longer elided to just
  the short month name, if multiple years are being displayed.

- bal --budget's column headings are now end dates rather than
  periods when appropriate (ie with --cumulative or --historical).

- bs,cf,is: -%/--no-total no longer forces --no-total (Stephen Morgan)

- bs,cf,is: --no-total now hides subtotals as well as the grand total
  (Stephen Morgan)

- codes: a new command for listing transaction codes

- print: a new `sql` output format has been added (Dmitry Astapov)

- roi: errors are now shown without a call stack

- tags: add --parsed flag, hide empties without --empty. With the
  --parsed flag, all tags or values are shown in the order they are
  parsed from the input data, including duplicates. With -E/--empty,
  any blank/empty values will also be shown, otherwise they are
  omitted.

## journal format

- account directives can specify a new `Cash` account type. This is a
  subtype of `Asset`, denoting accounts which should be displayed
  in `cashflow` reports. 
  
- The built-in regular expressions for choosing default account types
  have been tweaked, and documentation for account types has been
  improved.

## csv format

- Inferring the appropriate default field separator based on file
  extension (, for .csv, ; for .ssv, \t for .tsv) now works as
  documented.

- Conditional rule patterns can now be grouped with the `&` (AND) operator,
  allowing more powerful matching. (Michael Sanders)

- Invalid csv rules files now give clearer parse error messages.
  (Dmitry Astapov)

- "If tables", a compact bulk format for conditional rules, have been
  added. (Dmitry Astapov)

- csv conversion with a lot of conditional rules is now faster (Dmitry Astapov)


# 1.18.1 2020-06-21

- journal: document recursive wildcards

- by default, value reports work as in 1.17; to infer market prices from
  transactions, add the new --infer-value flag. (#1239, #1253)

- organise debug output better

- print: amounts in csv output now have commodity symbol, digit group
  separators and prices removed (Dmitry Astapov)


# 1.18 2020-06-07

## General

- The --forecast flag now takes an optional argument
  (--forecast=PERIODICEXPR), allowing periodic transactions to
  start/end on any date and to overlap recorded transactions.
  (#835, #1236) (Dmitry Astapov)

- An upper case file extension no longer confuses file format
  detection. (#1225)

- In the commands list, redundant source scripts are now hidden
  properly when a corresponding .com/.exe file exists. (#1225)

- We now show `..` instead of `-` to indicate date ranges, eg in
  report titles, to stand out more from hyphenated dates. 
  (Stephen Morgan)
  
- Period expressions (eg in -p, date:, and periodic rules) now accept
  `to`, `until`, `-`, or `..` as synonyms. (Stephen Morgan)

- When parsing amounts, whitespace between sign and number is now allowed.

- A clearer error message is shown on encountering a malformed regular
  expression.

## commands

- commands allowing different output formats now list their supported
  formats accurately in --help (#689)

- commands allowing JSON output now actually produce JSON (#689)

- bal, bs: show .. (not ,,) in report titles, like other reports

## journal format

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

## csv format

- You can now generate up to 99 postings in a transaction. (Vladimir Sorokin)

- You can now generate postings with an explicit 0 amount. (#1112)

- For each posting, when both numbered and unnumbered amount
  assignments are active (eg: both `amount` and `amount1`), we ignore
  the unnumbered ones. This makes it easier to override old `amount`
  rules.
  
- Fix a 1.17.1 regression involving amount-in/amount-out. (#1226)

- Assigning too many non-zero or zero values to a posting amount now
  gives a clearer error. (#1226)


# 1.17.1.1 2020-03-19

- update bounds after some belated hledger-* version bumps

# 1.17.1 2020-03-19

- csv: amount1 no longer forces a second posting or second posting amount.
  The "special handling for pre 1.17 rules" should now be less
  noticeable. amount1/amount2 no longer force a second posting or
  explicit amounts on both postings. (Only amount/amount-in/amount-out
  do that.) Error messages and handling of corner cases may be more
  robust, also.

- journal: a commodity directive without decimal mark now gives a more
  verbose error message with examples

- journal: inclusive balance assignments now work (#1207)

- require newer Decimal, math-functions libs to ensure consistent
  rounding behaviour, even when built with old GHCs/snapshots. 
  hledger uses banker's rounding (rounds to nearest even number, eg
  0.5 displayed with zero decimal places is "0").

# 1.17 2020-03-01

## General

- hledger's default date format is now YYYY-MM-DD (ISO-8601 dates).
  (Brian Wignall, Jakob Schöttl, Simon Michael)

- Drop the file format auto-detection feature.

  For a long time hledger has auto-detected the file format when it's
  not known, eg when reading from a file with unusual extension (like
  .dat or .txt), or from standard input (-f-), or when using the
  include directive (which currently ignores file extensions).  This
  was done by trying all readers until one succeeded.  This worked
  well in practice. But recent changes to timedot format have made
  this kind of auto-detection unreliable. (timedot and journal formats
  overlap).

  For predictability and to minimise confusion, hledger will no longer
  guess; when there's no file extension or reader prefix available, it
  always assumes journal format.

  To specify one of the other formats, you must use its standard file
  extension (`.timeclock`, `.timedot`, `.csv`, `.ssv`, `.tsv`), or a
  reader prefix (`-f csv:foo.txt`, `-f timedot:-`).

  Experimental, feedback welcome.

- Fix extra $ symbol (Mateus Furquim)

- --output-format now rejects invalid formats

- Numbers in JSON output now provide a floating point Number
  representation as well as our native Decimal object representation,
  since the later can sometimes contain 255-digit integers. The
  floating point numbers can have up to 10 decimal digits (and an
  unbounded number of integer digits.)
  Experimental, suggestions needed. (#1195)

- Fix finding latest date in queryEndDate Or queries and simplify
  date comparison code. (Stephen Morgan)

- Fix issue 457. (Jacek Generowicz)
  Issue #457 pointed out that commands such as

      hledger ui 'amt:>200'

  failed. This was because the process of dispatching from `hledger ui`
  to `hledger-ui` (note addition of `-`) lost the quotes around
  `amt:>20` and the `>` character was interpreted as a shell redirection
  operator, rather than as part of the argument.

  The machinery for quoting or escaping arguments which contain
  characters which require quoting or escaping (thus far whitespace and
  quotes) already existed. This solution simply adds shell stdio
  redirection characters to this set.

## commands

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

  --closing -> --close
  --opening -> --open
  --close-to -> --close-acct
  --open-from -> --open-acct

  The old flags are accepted as hidden aliases, and deprecated. (#1165)

- print, register: a new valuation type, --value=then, shows the
  market value at each posting's date.

- print: -V/-X/--value now imply -x/--explicit, as -B/--cost does.
  This avoids a bug where print -V of a transaction with an implicit
  commodity conversion would convert only some of its postings to value.

## journal format

- The include directive no longer tries all readers.  It now picks
  just one, based on the included file's extension, defaulting to
  journal.  (It doesn't yet handle a reader prefix.)

- The default commodity (D) directive now limits display precision too. (#1187)
  D directives are now fully equivalent to commodity directives for
  setting a commodity's display style. (Previously it couldn't limit
  the number of decimal places.)  When both kinds of directive exist,
  commodity directives take precedence.  When there are multiple D
  directives in the journal, only the last one affects display style.

## csv format

- Conditional blocks can now match single fields. \o/

- The experimental --separator command line option has been dropped,
  replaced a new `separator` directive in CSV rule files. (Aleksandar Dimitrov)
  Also the `.tsv` and `.ssv` file extensions are now recognised,
  and set the default `separator` to TAB and semicolon respectively.
  (#1179)

- Allow manual assignment of the "expenses:unknown" account name. (#1192)

- CSV rule keywords are now case insensitive. (Aleksandar Dimitrov)

## timeclock format

- Misc. fixes making parsing more robust. (Jakob Schöttl)

## timedot format

- More support for org mode: org headlines can now be used for date
  lines and timelog items (the stars are ignored). Also, any org
  headlines before the first date line are ignored.

- You can now write a description after a date, which will be used in
  all of that day's transactions.


# 1.16.2 2020-01-14

- add support for megaparsec 8 (#1175)
 
- close: mention --close-to/--open-from in docs
 
# 1.16.1 2019-12-03

- Drop unnecessary mtl-compat dependency

- Fix building with GHC 8.0, 8.2

# 1.16 2019-12-01

## General

- add support for GHC 8.8, base-compat 0.11 (#1090)

- drop support for GHC 7.10

- The benchmark suite has been disabled.

- The --anon flag now also anonymises transaction codes and account
  names declared with account directives. (Mykola Orliuk) (#901)

## commands

- balance/bs/cf/is: balance commands now support the -%/--percent flag
  to show amounts as percentages of the column's total. (Michael Kainer)

  If there are multiple commodities involved in a report hledger bails
  with an error message. This can be avoided by using -B/--cost. Also note
  that if one uses -% with the balance command the chances are high that
  all numbers are 0. This is due to the fact that by default balance sums
  up to zero. If one wants to use -% in a meaningful way with balance one
  has to add a query.

  In order to keep the implementation as simple as possible --tree has no
  influence over how the percentages are calculated, i.e., the percentages
  always represent the fraction of the columns total. If one wants to know
  the percentages relative to a parent account, one has to use a query to
  narrow down the accounts.

- balance: --budget no longer errors when there is neither budget nor
  transactions in the report period (Dmitry Astapov)

- balance: --budget has improved debug output (shows budget txns)
  (Dmitry Astapov)

- check-dates: now sets the exit status code (Amitai Burstein)

- close: no longer strips zeroes after the decimal mark, and preserves
  parseable output (#1137)

- close: the --close-to, --open-from options allow closing/opening
  account names to be chosen

- import: create the journal if missing, like the add command
  Streamlines import/migration instructions.

- import: --catchup marks all transactions imported, without importing

- import: more informative output: mention the input files, also show
  a message when nothing was imported

- prices: show price amounts with proper display style; always show
  full precision

- roi: don't give an error with empty input data (Dmitry Astapov)

- tests: unit tests are now run by tasty, and show coloured output by default (#1090).
  Test running options have changed, see the command help. 
  Some unit tests have been collapsed, so the reported test count has
  dropped a little.

## journal format

- Fixed: wrong dates generated by certain periodic transaction rules,
  eg "~ every 12 months from 2019/04". (Dmitry Astapov) (#1085)

## csv format

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
  diffs if you are comparing old and new reports. diff -w
  (--ignore-all-space) will filter these out.

- CSV rules now give you more freedom to generate any journal
  entries you want, including malformed or unbalanced ones. 
  The csv reader now checks the journal after conversion,
  so it will report any problems with the generated entries.

- Balance assertions generated from CSV are not checked, currently.
  This is appropriate when you are downloading partial CSV data to
  be merged into your main journal. If you do need to check balance
  assertions right away, you can pipe through hledger again:

      $ hledger -f a.csv print | hledger -f- print



# 1.15.2 2019-09-05

- -V and -X now respect a report end date (set with -e or -p or date:)
  when choosing the valuation date (which determines the market prices
  used). This is how -V works in hledger 1.14 and Ledger, and it means
  that -V isn't exactly equivalent to either --value=end or
  --value=now. Possibly some other corner cases in valuation have been
  fixed as well. "Effect of --value on reports" in the hledger manual
  has been updated and is more accurate.

# 1.15.1 2019-09-02

- add commodities, descriptions, diff, notes, payees commands to manual

# 1.15 2019-09-01

## General

- There is a new valuation option `--value=TYPE[,COMM]`, with
  backwards-compatible `-B/--cost`, `-V/--market`, `-X/--exchange=COMM`
  variants. These provide control over valuation date (#329), and
  inference of indirect market prices (similar to Ledger's -X) (#131).
  Experimental.
  
- Market valuation (-V/-X/--value) is now much faster (#999):

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

## commands

- add, web: on Windows, trying to add transactions to a file path
  containing trailing periods (eg `hledger add -f  Documents.\.hledger.journal`) 
  now gives an error, since this could cause data loss otherwise (#1056).
  This affects the add command and hledger-web's add form.

- bal: --budget: don't always convert to cost.

- bal: --budget: don't show a percentage when budgeted and actual
  amounts are in different commodities.

- bal/bs/bse: `-H/--historical` or `--cumulative` now disables `-T/--row-total` (#329).
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
  The upshot is that a balance -B report will be unchanged after
  the closing & opening transactions generated by the close command.

- descriptions, payees, notes commands added (Caleb Maclennan)

- diff: Gabriel Ebner's hledger-diff is now a built in command,
  and https://github.com/gebner/hledger-diff is deprecated.

- help: don't require a journal file

- print: now also canonicalises the display style of balance assertion amounts (#1042)

- reg: show negative amounts in red, like balance and Ledger

- reg: fix `--average`, broken since 1.12 (#1003)

- stats: show count of market prices (P directives), and the commodities covered

- tags: add --values flag to list tag values.

- tags: now runs much faster when there many tags

## journal format

- Transactions and postings generated/modified by periodic transaction
  rules and/or transaction modifier rules are now marked with tags
  (`generated-transaction`, `generated-posting`, `modified`) for
  easier troubleshooting and filtering.

## csv format

- When interpolating CSV values, outer whitespace is now stripped.
  This removes a potential snag in amount field assignments (#1051),
  and hopefully is harmless and acceptable otherwise.

- We no longer add inter-field spaces in CSV error messages.
  Some CSV errors would show the problem record, eg:

      2000-01-01,a,"1"
  
  with extra spaces added, eg:

      the CSV record is: "2000-01-01", "a", "1"

  which was inaccurate and not valid RFC-4180 CSV format.

- CSV parse errors are human-readable again (broken since 1.11) (#1038)

- CSV rules now allow the amount to be unassigned, if there is an
  assignment to "balance" (generating a balance assignment in this
  case). (#1000)


# 1.14.2 2019-03-20

- require easytest <0.3 to fix build issue

- fix some CSV parse errors which weren't in human readable format

# 1.14.1 2019-03-01

- fix missing Commodities.txt build error

# 1.14 2019-03-01

- journal: subaccount-including balance assertions have been
  added, with syntax =* and ==* (experimental) (#290)

- new commodities command lists commodity symbols

- new --invert option flips sign of amounts in reports

# 1.13.2 2019-02-04

- print, register: restore the accidentally dropped -o, -O flags (#967)

# 1.13.1 2019-02-02

- stop depending on here to avoid haskell-src-meta/stackage blockage.

# 1.13 2019-02-01

- cli: reorganised commands list. Addons now have a + prefix.

- cli: the command line help and manual section for all hledger's
  commands are now consistent, and generated from the same source.

- cli: comprehensive bash completion support is now provided (in
  shell-completion/). See how-to in the Cookbook. (Jakob Schöttl)

- balance --budget: budget amounts now aggregate hierarchically, like
  account balances. Unbudgeted accounts can be shown with -E/--empty
  (along with zero-balance accounts), and the --show-budgeted flag has
  been dropped.  (Dmitry Astapov)

- balance: new --transpose flag switches the rows and columns of
  tabular balance reports (in txt and csv output formats). (Dmitry
  Astapov)

- close: generated balance assertions now have exact amounts with all
  decimal digits, ignoring display precision. Also, balance assertion
  amounts will no longer contain prices. (#941, #824, #958)

- files: now shows up in the commands list

- import: be silent when there's nothing to import

- roi: percentages smaller than 0.01% are displayed as zero (Dmitry
  Astapov)

- stats, ui: correct file order is preserved when using --auto (#949)

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
  transactions (--auto can add postings to transactions generated with
  --forecast). (Dmitry Astapov)

- journal: balance assertion errors now show exact amounts with all
  decimal digits.  Previously it was possible, in case of a commodity
  directive limiting the display precision, to have a balance
  assertion error with asserted and actual amounts looking the
  same. (#941)

- journal: fixed a periodic transaction parsing failure (#942) (Dmitry
  Astapov)

# 1.12.1 2018-12-03

-   roi: use math-functions lib instead of statistics,
    be more stackage nightly compatible

# 1.12 2018-12-02

-   install script: ensure a new-enough version of stack; more informative output

-   build with GHC 8.6/base-4.12 (Peter Simons)

-   add required upper bound for statistics (Samuel May)

-   --anon anonymises more thoroughly (including linked original postings) (Moritz Kiefer)

-   unbalanced transaction errors now include location info (Mykola Orliuk)

-   accounts command: --drop also affects the default flat output, without needing an explicit --flat flag

-   accounts command: the --codes flag has been dropped

-   accounts command: filtering by non-account-name queries now works

-   add command: fix transaction rendering regression during data entry and in journal file

-   balance command: fix wrongful eliding of zero-balance parent accounts in tree mode (Dmitry Astapov)

-   journal format, bs/bse/cf/is commands: account directives can declare account types (#877)
    Previously you had to use one of the standard english account names
    (assets, liabilities..) for top-level accounts, if you wanted them to
    appear in the right place in the balancesheet, balancesheetequity,
    cashflow or incomestatement reports.

    Now you can use your preferred account names, and use account directives
    to declare which accounting class (Asset, Liability, Equity, Revenue or
    eXpense) an account (and its subaccounts) belongs to, by writing one of
    the letters A, L, E, R, X after the account name, after two or more
    spaces. This syntax may change (see issue). Experimental.

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

-   journal format: periodic transaction rules now require a double space separator.
    In periodic transaction rules which specify a transaction description or
    same-line transaction comment, this must be separated from the period
    expression by two or more spaces, to prevent ambiguous parsing. Eg
    this will parse correctly as "monthly" thanks to the double space:

        ~ monthly  In 2020 we'll end this monthly transaction.

-   journal format: exact/complete balance assertions (Samuel May).
    A stronger kind of balance assertion, written with a double equals sign,
    asserts an account's complete account balance, not just the balance in
    one commodity. (But only if it is a single-commodity balance, for now.)
    Eg:

        1/1
          (a)  A 1
          (a)  B 1
          (a)  0   =  A 1   ; commodity A balance assertion, succeeds
          (a)  0   == A 1   ; complete balance assertion, fails

-   journal format: account directives now allow whitespace or a comment after the account name

-   journal format: using \~ for home directory in include directives now works (#896) (Mykola Orliuk)

-   journal format: prevent misleading parse error messages with cyclic include directives (#853) (Alex Chen)

-   journal format: transaction modifier multipliers handle total-priced amounts correctly (#928).
    Multipliers (*N) in transaction modifier rules did not multiply
    total-priced amounts properly. Now the total prices are also multiplied,
    keeping the transaction balanced.

-   journal format: do amount inference/balance assignments/assertions before transaction modifiers (#893, #908) (Jesse Rosenthal)
    Previously, transaction modifier (auto postings) rules were applied
    before missing amounts were inferred. This meant amount multipliers could
    generate too many missing-amount postings, making the transaction
    unbalanceable (#893).

    Now, missing amount inference (and balance assignments, and balance
    assertions, which are interdependent) are done earlier, before
    transaction modifier rules are applied (#900, #903).

    Also, we now disallow the combination of balance assignments and
    transaction modifier rules which both affect the same account, which
    could otherwise cause confusing balance assertion failures (#912).
    (Because assignments now generate amounts to satisfy balance assertions
    before transaction modifier rules are applied (#908).)

-   journal format: periodic transaction rules are now aware of Y default year directives. (#892)
    Ie when a default year Y is in effect, they resolve partial or relative
    dates using Y/1/1 as the reference date, rather than today's date.

# 1.11.1 2018-10-06

-   fix wrong transaction rendering in balance assertion errors and when
    using the add command

# 1.11 2018-09-30

-   The default display order of accounts is now influenced by
    the order of account directives. Accounts declared by account
    directives are displayed first (top-most), in declaration order,
    followed by undeclared accounts in alphabetical order. Numeric
    account codes are no longer used, and are ignored and considered
    deprecated.

    So if your accounts are displaying in a weird order after upgrading,
    and you want them alphabetical like before, just sort your account
    directives alphabetically.

-   Account sorting (by name, by declaration, by amount) is now more
    robust and supported consistently by all commands (accounts,
    balance, bs..) in all modes (tree & flat, tabular & non-tabular).

-   close: new --opening/--closing flags to print only the opening or
    closing transaction

-   files: a new command to list included files

-   prices: query arguments are now supported. Prices can be filtered by
    date, and postings providing transaction prices can also be filtered.

-   rewrite: help clarifies relation to print --auto (#745)

-   roi: a new command to compute return on investment, based on hledger-irr

-   test: has more verbose output, more informative failure messages,
    and no longer tries to read the journal

-   csv: We use a more robust CSV lib (cassava) and now support
    non-comma separators, eg --separator ';' (experimental, this flag
    will probably become a CSV rule) (#829)

-   csv: interpolated field names in values are now properly case insensitive, so
    this works:

        fields  ...,Transaction_Date,...
        date %Transaction_Date

-   journal: D (default commodity) directives no longer break multiplier
    amounts in transaction modifiers (AKA automated postings) (#860)

-   journal: "Automated Postings" have been renamed to "Transaction Modifiers".

-   journal: transaction comments in transaction modifier rules are now parsed correctly. (#745)

-   journal: when include files form a cycle, we give an error instead
    of hanging.

-   upper-case day/month names in period expressions no longer give an error (#847, #852)

# 1.10 2018-06-30

-   journal: many parse error messages have become more informative, and
    some now show the source line and error location.

-   journal: ;tag: is no longer parsed as a tag named ";tag" (#655)

-   journal: transaction price amounts having their own price amounts is
    now a parse error

-   journal: amounts with space as digit group separator and trailing whitespace
    now parse correctly (#780)

-   journal: in amounts containing digits and a single space, the space
    is now interpreted as a digit group separator, not a decimal separator (#749)

-   journal: in commodity/format/D directives, the amount must now include a decimal separator.

    When more precise control is needed over number parsing, our
    recommended solution is commodity directives. Commodity directives
    that don't specify the decimal separator leave things ambiguous,
    increasing the chance of misparsing numbers. In some cases it could
    cause amounts with a decimal point to be parsed as if with a digit
    group separator, so 1.234 became 1234.

    It seems the simple and really only way to do this reliably is to require
    an explicit decimal point character. Most folks probably do this already.
    Unfortunately, it makes another potential incompatibility with ledger and
    beancount journals. But the error message will be clear and easy to
    work around.

-   journal: directives currently have diverse and somewhat tricky
    semantics, especially with multiple files. The manual now describes
    their behaviour precisely.

-   journal: `alias` and `apply account` directives now affect `account` directives (#825)

-   journal: periodic transactions can now have all the usual transaction fields
    (status mark, code, description, comment), for generating more expressive
    forecast transactions.

-   journal: forecast transactions now have the generating period
    expression attached as a tag named "recur".

-   journal: periodic transactions now start on the first instance of the
    recurring date, rather than the day after the last regular transaction (#750)

-   journal: periodic transaction rules now allow period expressions relative to today's date

-   csv: amount-in/amount-out errors are more detailed

-   balance: --drop is now ignored when not in flat mode,
    rather than producing a corrupted report (#754)

-   budget: --drop now preserves the <unbudgeted> top-level account in --budget reports

-   register: in CSV output, the code field is now included (#746)

-   smart dates now allow the YYYYMM format, and are better documented

-   use hledger-lib 1.10

# 1.9.1 2018-04-30

-   use hledger-lib 1.9.1

-   budget (balance --budget): monthly columns are displayed in the
    proper order. This fixes a regression in 1.9.

-   budget: budgets can be built from periodic transactions with
    different intervals again. In 1.9, budgets were restricted to a
    single interval, but this was a mistake. This restores the 1.5
    behaviour.

-   budget: budget reports are more intuitive and much less likely to
    produce no output.

-   budget: when no report interval is specified, a budget report for
    the whole journal period is shown.

-   budget: periodic transactions and the requested report period can
    each have their own start/end dates, and the resulting report will
    span the union of those periods, showing zeroes where data is
    missing.

-   budget: total row and total/average columns are now calculated correctly

-   budget: actual, percentage, and goal amounts are now aligned in
    columns for better readability (usually, unless numbers get huge).

-   budget: combining --budget and --sort-amount is not yet supported
    and now gives an error.

-   csv: handle "-%amount" in a rule when the CSV amount is parenthesised (#736)

-   journal: automated postings are now generated early, before journal finalisation,
    so they are present for amount inference, transaction balancing, and balance assertions
    (#729)

-   journal: automated postings are now inserted right after the posting that triggered them
    (#729)

-   cli: command-line account aliases are now applied early, before journal finalisation,
    so they are equivalent to alias directives in the journal (#730)

-   journal: inferred amounts now have the appropriate standard amount style applied
    (setting the precision correctly, eg). (#737)

-   journal: when checking for balanced transactions, amount styles declared with
    commodity directives are also used (previously only inferred amount styles were).

# 1.9 2018-03-31

-   support ghc 8.4, latest deps

-   journal: account directives can define a numeric account code to
    customize sorting. bal/bs/cf/is will sort accounts by account code,
    if any, then account name.

-   journal: support scientific number notation (#704, #706)

-   csv: reading a CSV file containing no records is no longer an error

-   cli: when the system text encoding is UTF-8, ignore any UTF-8 BOM
    prefix found when reading files. (Paypal's new CSV has this BOM
    prefix, causing a confusing parse error.)

-   cli: tabular reports no longer have a trailing blank line added.
    (This allows omitting the ">=0" delimiters in our functional tests,
    making them easier to read and maintain.)

-   acc: the accounts command now has --declared and --used flags

-   bal: the --invert flag flips all signs

-   bal: --drop now works with CSV output

-   bal/bs/bse/cf/is: show overall report span in title

-   bal/bs/bse/cf/is: show short month names as headings in monthly reports

-   bal/bs/bse/cf/is: these commands can now generate HTML output

-   bal/bs/is/cf: drop short name and indent fields from multicolumn CSV

-   bs/bse/cf/is: these, the "financial statement" commands, now show
    normal income, liability and equity balances as positive numbers.
    Negative numbers now indicate a contra-balance (eg an overdrawn
    checking account), a net loss, or a negative net worth. This makes
    these reports more like conventional financial statements, and easier
    to read and share with others. (Other commands, like balance, have not
    changed.) (experimental)

-   bs/cf/is: always show a tabular report, even with no report
    interval. Previously you would get a simple borderless report like
    the original balance command. Less code, fewer bugs.

-   bs/bse/cf/is: in CSV output, don't repeat the headings row for each subreport

-   budget: warn that CSV output with bal --budget is unimplemented

-   budget: bal --budget shows budget goals even with no or zero actual amounts.
    Makes budget reports more intuitive, at the cost of a temporary hack
    which may misorder columns in some cases (if actual and budget
    activity occur in a different range of columns).

-   budget: --budget uses only periodic txns with the selected interval.\
    Budgets with different interval, eg a daily and weekly budget, are independent.

-   budget: show mostly fixed-width columns for readability

-   budget: fix bug where a budget report could include budget goals
    ending on the day before the report start date (splitSpan issue)

-   close: the equity command has been renamed to close. It now ignores
    any begin date (it always closes historical end balances). It also
    ignores --date2.

# 1.5 2017-12-31

-   --auto adds Ledger-style automated postings to transactions (Dmitry Astapov, Mykola Orliuk)

-   --forecast generates Ledger-style periodic transactions in the future (Dmitry Astapov, Mykola Orliuk)

-   -V/--value uses today's market prices by default, not those of last transaction date. #683, #648

-   add: suggest implied (parent) and declared (by account directives) account names also

-   bal: --budget shows performance compared to budget goals defined
    with periodic transactions. Accounts with budget goals are
    displayed folded (depth-clipped) at a depth matching the budget
    specification. Unbudgeted accounts are hidden, or with
    --show-unbudgeted, shown at their usual depth. (Dmitry Astapov)

-   import: the output of --dry-run is now valid journal format

-   print: -B shows converted amounts again, as in 1.1, even without
    -x. #551 (Mykola Orliuk, Simon Michael)

-   tag: the first argument now filters tag names, additional arguments
    filter transactions (#261)

-   remove upper bounds on all but hledger* and base (experimental)

# 1.4 2017-09-30

-   cli: a @FILE argument reads flags & args from FILE, one per line

-   cli: reorganized commands list, added some new command aliases:

    -   accounts: a
    -   balance: b
    -   print: p, txns
    -   register: r

-   cli: accept -NUM as a shortcut for --depth=NUM (eg: -2)

-   cli: improve command-line help for --date2 (#604)

-   cli: make --help and -h the same, drop --man and --info for now (#579)

-   help: offers multiple formats, accepts topic substrings.
    The separate info/man commands have been dropped. help now
    chooses an appropriate documentation format as follows:

    -   it uses info if available,
    -   otherwise man if available,
    -   otherwise $PAGER if defined,
    -   otherwise less if available,
    -   otherwise it prints on stdout
    -   (and it always prints on stdout when piped).

    You can override this with the `--info`/`--man`/`--pager`/`--cat` flags.
    (#579)

-   bal/bs/cf/is: --sort-amount/-S sorts by largest amount instead of
    account name

-   bs/cf/is: support --output-file and --output-format=txt\|csv
    The CSV output should be reasonably ok for dragging into a
    spreadsheet and reformatting.

-   bal/bs/cf/is: consistent double space between columns, consistent
    single final blank line. Previously, amounts wider than the column
    headings would be separated by only a single space.

-   bs/is: don't let an empty subreport disable the grand totals (fixes #588)

-   cf: exclude asset accounts with ":fixed" in their name (Christian G. Warden, Simon Michael, #584)

-   new balancesheetequity command: like balancesheet but also shows
    equity accounts (Nicholas Niro)

-   new import command: adds new transactions seen in one or more input
    files to the main journal file

-   print: --new shows only transactions added since last time
    (saves state in .latest.JOURNALFILE file)

-   new tags command: lists tags in matched transactions

-   most addons formerly shipped in bin/ are now builtin commands. These
    include: check-dates, check-dupes, equity, prices, print-unique,
    register-match, rewrite.

-   refactor: new Commands module and subdirectory.
    Builtin commands are now gathered more tightly in a single module,
    Hledger.Cli.Commands, facilitating change. The legacy "convert"
    command has been dropped.

-   refactor: BalanceView -> CompoundBalanceCommand

-   deps: drop support for directory < 1.2

-   deps: allow ansi-terminal 0.7

-   deps: drop oldtime flag, require time 1.5+

-   deps: simplify shakespeare bounds

-   deps: remove ghc < 7.6 support

# 1.3.1 2017-08-25

-   bs/is: don't let an empty subreport disable the grand totals (#588)

-   allow megaparsec 6 (#594)

-   allow megaparsec-6.1 (Hans-Peter Deifel)

-   restore upper bounds on hledger packages

# 1.3 2017-06-30

The "uncleared" transaction/posting status, and associated UI flags
and keys, have been renamed to "unmarked" to remove ambiguity and
confusion. This means that we have dropped the `--uncleared` flag,
and our `-U` flag now matches only unmarked things and not pending
ones. See the issue and linked mail list discussion for more
background. (#564)

Also the -P short flag has been added for --pending, and the -U/-P/-C
flags can be combined.

bs/is: fix "Ratio has zero denominator" error (#535)

bs/is/cf: fix --flat (#552) (Justin Le, Simon Michael)

bal/bs/is/cf: show negative amounts in red (Simon Michael, Justin Le).
These commands now shows negative amounts in red, when hledger detects
that ANSI codes are supported, (ie when TERM is not "dumb" and stdout
is not being redirected or piped).

print: show pending mark on postings (fixes #563).
A pending mark on postings is now displayed, just like a cleared mark.
Also there will now be a space between the mark and account name.

print: amounts are now better aligned, eg when there are posting
status marks or virtual postings

# 1.2 2017-03-31

## CLI

"hledger" and "hledger -h" now print a better organised commands list
and general usage message respectively (#297).

The common reporting flags can now be used anywhere on the command line.

Fixed deduplication of addons in commands list.

Fixed ugly stack traces in command line parse error messages.

The -V/--value flag is now a global report flag, so it works with
balance, print, register, balancesheet, incomestatement, cashflow,
etc. (Justin Le)

The `--pivot` global reporting option replaces all account names with
the value of some other field or tag. It has been improved, eg:

-   we don't add the field/tag name name as a prefix
-   when pivoting on a tag, if the tag is missing we show a blank
    (rather than showing mixed tag values and account names)
-   a pipe character delimiter may be used in descriptions to get a more accurate
    and useful payee report (`hledger balance --pivot payee`)

options cleanups

## Addons

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
and can show short (-h) and long (--help) command line help.
(Long help is declared with pre and postambles to the generated
options help, short help is that truncated at the start of the hledger
common flags.)

`hledger` now shows a cleaner list of addon commands, showing only the
compiled version of an addon when both source and compiled versions
are in $PATH. (Addons with .exe extension or no extension are
considered compiled. Modification time is not checked, ie, an old
compiled addon will override a newer source version. If there are
three or more versions of an addon, all are shown. )

New addons added/included:

-   autosync - example symlink to ledger-autosync
-   budget - experimental budget reporting command supporting Ledger-like periodic transactions and automated transactions (Mykola Orliuk)
-   chart - pie-chart-generating prototype, a repackaging of the old hledger-chart tool
-   check - more powerful balance assertions (Michael Walker)
-   check-dupes - find accounts sharing the same leaf name (Stefano Rodighiero)
-   prices - show all market price records (Mykola Orliuk)
-   register-match - a helper for ledger-autosync's deduplication, finds best match for a transaction description

The equity command now always generates a valid journal transaction,
handles prices better, and adds balance assertions (Mykola Orliuk).

The rewrite command is more robust and powerful (Mykola Orliuk):

-   in addition to command-line rewrite options, it understands rewrite rules
    defined in the journal, similar to Ledger's automated transactions (#99).
    Eg:

        = ^income
            (liabilities:tax)  *.33

        = expenses:gifts
            budget:gifts  *-1
            assets:budget  *1

-   it can generate diff output, allowing easier review of the proposed
    changes, and safe modification of original journal files (preserving
    file-level comments and directives). Eg:

        hledger-rewrite --diff Agency --add-posting 'Expenses:Taxes  *0.17' | patch

-   rewrites can affect multiple postings in a transaction, not just one.

-   posting-specific dates are handled better

## balance

A new --pretty-tables option uses unicode characters for rendering
table borders in multicolumn reports (#522) (Moritz Kiefer)

## balancesheet/cashflow/incomestatement

These commands are now more powerful, able to show multicolumn reports
and generally having the same features as the balance command. (Justin Le)

balancesheet has always ignored a begin date specified with a `-b` or
`-p` option; now it also ignores a begin date specified with a `date:`
query. (Related discussion at #531)

## print

The output of print is now always a valid journal (fixes #465) (Mykola Orliuk).

print now tries to preserves the format of implicit/explicit balancing
amounts and prices, by default. To print with all amounts explicit,
use the new `--explicit/-x` flag (fixes #442). (Mykola Orliuk)

Don't lose the commodity of zero amounts/zero balance assertions (fixes #475) (Mykola Orliuk)

## Misc

Fix a regression in the readability of option parsing errors (#478) (Hans-Peter Deifel)

Fix an example in Cli/Main.hs (Steven R. Baker)

Allow megaparsec 5.2 (#503)

# 1.1 2016-12-31

## balance

-   with -V, don't ignore market prices in the future (#453, #403)

-   with -V and multiple same-date market prices, use the last parsed not the highest price (#403)

## misc

-   fix non-existent "oldtime" dependency (#431)

-   extra/hledger-equity.hs now generates valid journal format when there are multiple commodities

# 1.0.1 2016-10-27

-   allow megaparsec 5.0 or 5.1

-   fix benchmark build failure (#423)

# 1.0 2016-10-26

## add

-   suggest only one commodity at a time as default amount (#383)

    (since we currently can't input more than one at a time)

## balance

-   added --change flag for consistency

-   -H/--historical now also affects single-column balance reports with a start date (#392).

    This has the same effect as just omitting the start date, but adds consistency.

-   in CSV output, render amounts in one-line format (#336)

## balancesheet

-   fix an infinite loop (#393)

## print

-   in CSV output, fix and rename the transaction id field

## register

-   fix a sorting regression with --date2 (#326)

-   --average/-A is now affected by --historical/-H

-   added --cumulative flag for consistency

-   in CSV output, include the transaction id and rename the total field (#391)

## stats

-   fixed an issue with ordering of include files

## misc

-   --pivot option added, groups postings by tag instead of account (#323) (Malte Brandy)

-   --anon option added, obfuscates account names and descriptions (#265) (Brian Scott)

    (Only affects the hledger tool, for now.)

-   try to clarify balance/register's various report modes,

    kinds of "balance" displayed, and related options and language.

-   with multiple --change/--cumulative/--historical flags, use the last one instead of complaining

-   don't add the "d" suffix when displaying day periods

-   stack-ify extra/hledger-rewrite.hs

## misc

-   added GHC 8 support, dropped GHC 7.6 and 7.8 support.

    GHC 7.8 support could be restored with small code changes and a maintainer.

-   a cabal.project file has been added (Moritz Kiefer)

-   use hpack for maintaining cabal files (#371).

    Instead of editing cabal files directly, we now edit the less
    verbose and less redundant package.yaml files and let stack (or
    hpack) update the cabal files. We commit both the .yaml and
    .cabal files.

-   clean up some old cabal flags

-   tools/simplebench has been spun off as the quickbench package.

-   add Appveyor CI builds, provide up-to-date binaries for Windows

-   extra: add a bunch of CSV rules examples

## docs

-   the website is simpler, clearer, and more mobile-friendly.

    Docs are now collected on a single page and organised by type: getting started, reference, more.

-   reference docs have been split into one manual for each executable and file format.

    This helps with maintenance and packaging and also should make it
    easier to see what's available and to read just what you need.

-   manuals are now provided in html, plain text, man and info formats

    generated from the same source by a new Shake-based docs build system. (#292)

-   versioned manuals are provided on the website, covering recent releases and the latest dev version (#385, #387)

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

## cli

-   parsing multiple input files is now robust.

    When multiple -f options are provided, we now parse each file
    individually rather than just concatenating them, so they can
    have different formats (#320). Note this also means that
    directives (like \`Y\` or \`alias\`) no longer carry over from one
    file to the next.

-   -I has been added as the short flag for --ignore-assertions

    (this is different from Ledger's CLI, but useful for hledger-ui).

-   parsing an argument-less --debug option is more robust

# 0.27 2015-10-30

Account aliases:

-   Regular expression account aliases are now fast enough that you can
    use lots of them without slowing things down. They now take
    O(aliases x accounts) time, instead of O(aliases x transactions);
    also, regular expressions are no longer recompiled unnecessarily.

Documentation:

-   Each hledger package now includes one or more man pages, generated
    from markdown by the mighty pandoc. Currently there are six: one
    for each main executable and each input file format. Currently these
    somewhat duplicate the manual on the website; this will be resolved
    somehow. (#282).

-   The site is now built with hakyll-std, a generic hakyll script.

-   hledger once again has a HCAR entry.

Tools:

-   The hledger cabal files are now generated from package.yaml files by
    hpack, in principle, removing a lot of error-prone duplication and
    boilerplate. (In practice, both files are being updated manually
    for the moment, until hpack supports flags and conditional blocks.)

-   Time/allocation and heap profiling is working again, and easier:

    -   `make quickprof-CMD` generates a profile for CMD, which runs
        against one of the sample journals. (CMD must be one word,
        enclosing in double quotes isn't working here for some reason).

    -   `make quickheap-CMD` generates a heap profile for CMD, in
        hledgerprof.ps, and tries to open it in a viewer (currently the
        mac-friendly "open" executable, so you may need to adjust this in
        the makefile). As with quickprof, CMD must be one word and runs
        against one of the sample journals.

    -   `make hledgerprof` builds the hledgerprof executable used for
        time/allocation profiling. `make hledgercov` builds the hledgercov
        executable used for coverage reports.

-   Travis CI now tests the build on each github push and announces
    status changes by email and on #hledger.

Journal format:

-   Dates must now begin with a digit (not /, eg).

-   The comment directive longer requires an end comment, and will
    extend to the end of the file(s) without it.

Command-line interface:

-   Output (balance reports, register reports, print output etc.)
    containing wide characters, eg chinese/japanese/korean characters,
    should now align correctly, when viewed in apps and fonts that show
    wide characters as double width (#242).

-   The argument for --depth or depth: must now be positive.

add:

-   Journal entries are now written with all amounts explicit, to avoid
    losing price info (#283).

-   Fixed a bug which sometimes (when the same letter pair was repeated)
    caused it not to pick the most similar past transaction for defaults.

balance:

-   There is now a -V/--value flag to report current market value (as in Ledger).
    It converts all reported amounts using their "default market price".
    "Market price" is the new name for "historical prices", defined with the P directive.
    The default market price for a commodity is the most recent one found in the journal on or before the report end date.

    Unlike Ledger, hledger's -V uses only the market prices recorded
    with P directives; it does not use the "transaction prices"
    recorded as part of posting amounts (which are used by -B/--cost).
    Also, using both -B and -V at the same time is supported.

-   Fixed a bug in amount normalization which caused amount styles
    (commodity symbol placement, decimal point character, etc.) to be
    lost in certain cases (#230, #276).

-   The balance command's --format option can now adjust the rendering
    style of multi-commodity amounts, if you begin the format string
    with one of:

        %_  - renders amounts on multiple lines, bottom-aligned (the default)
        %^  - renders amounts on multiple lines, top-aligned
        %,  - renders amounts on one line, comma-separated

-   The balance report's final total (and the line above it) now adapt
    themselves to a custom --format.

print:

-   The --match option prints the journal entry that best matches a
    description (ie whose description field is most similar to the value
    given, and if there are several equally similar, the most recent).
    This was originally an add-on I used to guess account names for
    ledger-autosync. It's nice for quickly looking up a recent
    transaction from a guessed or partial description.

-   print now always right-aligns the amounts in an entry, even when
    they are wider than 12 characters. (If there is a price, it's
    considered part of the amount for right-alignment.)

register:

-   Amount columns now resize automatically, using more space if it's
    needed and available.

# 0.26 2015-07-12

Account aliases:

-   Account aliases are once again non-regular-expression-based, by default. (#252)

    The regex account aliases added in 0.24 trip up people switching between
    hledger and Ledger. (Also they are currently slow).

    This change makes the old non-regex aliases the default; they are
    unsurprising, useful, and pretty close in functionality to Ledger's.

    The new regex aliases are still available; they must be enclosed
    in forward slashes. (Ledger effectively ignores these.)

Journal format:

-   We now parse, and also print, journal entries with no postings, as
    proposed on the mail lists. These are not well-formed General
    Journal entries/transactions, but here is my rationale:

    -   Ledger and beancount parse them
    -   if they are parsed, they should be printed
    -   they provide a convenient way to record (and report) non-transaction events
    -   they permit more gradual introduction and learning of the concepts.
        So eg a beginner can keep a simple journal before learning about accounts and postings.

-   Trailing whitespace after a `comment` directive is now ignored.

Command-line interface:

-   The -f/file option may now be used multiple times.
    This is equivalent to concatenating the input files before running hledger.
    The add command adds entries to the first file specified.

Queries:

-   real: (no argument) is now a synonym for real:1

-   tag: now matches tag names with a regular expression, like most other queries

-   empty: is no longer supported, as it overlaps a bit confusingly with
    amt:0. The --empty flag is still available.

-   You can now match on pending status (#250)

    A transaction/posting status of ! (pending) was effectively equivalent
    to * (cleared). Now it's a separate state, not matched by --cleared.
    The new Ledger-compatible --pending flag matches it, and so does
    --uncleared.

    The relevant search query terms are now status:*, status:! and
    status: (the old status:1 and status:0 spellings are deprecated).

    Since we interpret --uncleared and status: as "any state except cleared",
    it's not currently possible to match things which are neither cleared
    nor pending.

activity:

-   activity no longer excludes 0-amount postings by default.

add:

-   Don't show quotes around the journal file path in the "Creating..."
    message, for consistency with the subsequent "Adding..." message.

balancesheet:

-   Accounts beginning with "debt" or now also recognised as liabilities.

print:

-   We now limit the display precision of inferred prices. (#262)

    When a transaction posts to two commodities without specifying the
    conversion price, we generate a price which makes it balance (cf
    https://hledger.org/hledger.html#prices). The print command showed
    this with full precision (so that manual calculations with the
    displayed numbers would look right), but this sometimes meant we
    showed 255 digits (when there are multiple postings in the
    commodity being priced, and the averaged unit price is an
    irrational number). In this case we now set the price's display
    precision to the sum of the (max) display precisions of the
    commodities involved. An example:

          hledgerdev -f- print
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

    There might still be cases where this will show more price decimal
    places than necessary.

-   We now show inferred unit prices with at least 2 decimal places.

    When inferring prices, if the commodities involved have low
    display precisions, we don't do a good job of rendering
    accurate-looking unit prices. Eg if the journal doesn't use any
    decimal places, any inferred unit prices are also displayed with
    no decimal places, which makes them look wrong to the user. Now,
    we always give inferred unit prices a minimum display precision of
    2, which helps a bit.

register:

-   Postings with no amounts could give a runtime error in some obscure case, now fixed.

stats:

-   stats now supports -o/--outputfile, like register/balance/print.
-   An O(n\^2) performance slowdown has been fixed, it's now much faster on large journals.

        +--------------------------------------++--------+--------+
        |                                      ||   0.25 |   0.26 |
        +======================================++========+========+
        | -f data/100x100x10.journal     stats ||   0.10 |   0.16 |
        | -f data/1000x1000x10.journal   stats ||   0.45 |   0.21 |
        | -f data/10000x1000x10.journal  stats ||  58.92 |   2.16 |
        +--------------------------------------++--------+--------+

Miscellaneous:

-   The June 30 day span was not being rendered correctly; fixed. (#272)

-   The bench script invoked by "cabal bench" or "stack bench" now runs
    some simple benchmarks.

    You can get more accurate benchmark times by running with --criterion.
    This will usually give much the same numbers and takes much longer.

    Or with --simplebench, it benchmarks whatever commands are
    configured in bench/default.bench. This mode uses the first
    "hledger" executable in $PATH.

-   The deprecated shakespeare-text dependency has been removed more thoroughly.

# 0.25.1 2015-04-29

-   timelog: support the description field (#247)

# 0.25 2015-04-07

-   GHC 7.10 compatibility (#239)

-   build with terminfo support on POSIX systems by default

    On non-windows systems, we now build with terminfo support by
    default, useful for detecting terminal width and other things.

    This requires the C curses dev libraries, which makes POSIX
    installation slightly harder; if it causes problems you can
    disable terminfo support with the new `curses` cabal flag, eg:
    cabal install -f-curses ... (or cabal might try this
    automatically, I'm not sure).

-   register: use the full terminal width, respect COLUMNS, allow column width adjustment

    On POSIX systems, register now uses the full terminal width by
    default. Specifically, the output width is set from:

    1.  a --width option
    2.  or a COLUMNS environment variable (NB: not the same as a bash shell var)
    3.  or on POSIX (non-windows) systems, the current terminal width
    4.  or the default, 80 characters.

    Also, register's --width option now accepts an optional
    description column width following the overall width (--width
    WIDTH\[,DESCWIDTH\]). This also sets the account column width, since
    the available space (WIDTH-41) is divided up between these two
    columns. Here's a diagram:

          <--------------------------------- width (W) ---------------------------------->
          date (10)  description (D)       account (W-41-D)     amount (12)   balance (12)
          DDDDDDDDDD dddddddddddddddddddd  aaaaaaaaaaaaaaaaaaa  AAAAAAAAAAAA  AAAAAAAAAAAA

    Examples:

          $ hledger reg                 # use terminal width on posix
          $ hledger reg -w 100          # width 100, equal description/account widths
          $ hledger reg -w 100,40       # width 100, wider description
          $ hledger reg -w $COLUMNS,100 # terminal width and set description width

-   balance: new -T/--row-total and -A/--average options

    In multicolumn balance reports, -T/--row-total now shows a row totals
    column and -A/--average shows a row averages column.
    This helps eg to see monthly average expenses (hledger bal \^expenses -MA).

    NB our use of -T deviates from Ledger's UI, where -T sets a custom
    final total expression.

-   balance: -N is now short for --no-total
-   balance: fix partially-visible totals row with --no-total

    A periodic (not using --cumulative or --historical) balance report
    with --no-total now hides the totals row properly.

-   journal, csv: comment lines can also start with *

    As in Ledger. This means you can embed emacs org/outline-mode nodes in
    your journal file and manipulate it like an outline.

# 0.24.1 2015-03-15

-   journal: fix balance accumulation across assertions (#195)

    A sequence of balance assertions asserting first one commodity, then
    another, then the first again, was not working.

-   timelog: show hours with two decimal places instead of one (#237)
-   in weekly reports, simplify week 52's heading like the others
-   disallow trailing garbage in a number of parsers

    Trailing garbage is no longer ignored when parsing the following:
    balance --format option, register --width option, hledger-rewrite
    options, hledger add's inputs, CSV amounts, posting amounts,
    posting dates in tags.

-   allow utf8-string-1 (fpco/stackage/#426)

# 0.24 2014-12-25

General:

-   fix redundant compilation when cabal installing the hledger packages
-   switch to Decimal for representing amounts (#118)
-   report interval headings (eg in balance, register reports) are shown
    compactly when possible
-   general speedups

Journal format:

-   detect decimal point and digit groups more robustly (#196)
-   check that transaction dates are followed by whitespace or newline
-   check that dates use a consistent separator character
-   balance assertions now are specific to a single commodity, like
    Ledger (#195)
-   support multi-line comments using "comment", "end comment"
    directives, like Ledger

CSV format:

-   reading CSV data from stdin now works better
-   the rules file include directive is now relative to the current
    file's directory (#198)
-   the original order of same-day transactions is now usually preserved
    (if the records appear to be in reverse date order, we reverse them
    before finally sorting by transaction date)
-   CSV output is now built in to the balance, print, and register
    commands, controlled by -O/--output-format (and -o/--output-file,
    see below)

CLI:

-   the --width and --debug options now require their argument (#149)
-   when an option is repeated, the last value takes precedence (#219).
    This is helpful eg for customising your reporting command aliases on
    the fly.
-   smart dates (used in -p/-b/-e/date:/date2:) now must use a
    consistent separator character, and must be parseable to the end
-   output destination and format selection is now built in to the
    balance, print and register commands, controlled by -o/--output-file
    and -O/--output-format options. Notes:
    -   -o - means stdout
    -   an output file name suffix matching a supported format will also
        set the output format, unless overridden by --output-format
    -   commands' supported output formats are listed in their
        command-line help. Two formats are currently available:
        txt (the default) and csv.
-   balance assertions can be disabled with --ignore-assertions

Account aliases:

-   all matching account aliases are now applied, not just one directive
    and one option
-   account aliases now match by case insensitive regular expressions
    matching anywhere in the account name
-   account aliases can replace multiple occurrences of the pattern
    within an account name
-   an account alias replacement pattern can reference matched groups
    with \N

Queries:

-   date:/date2: with a malformed date now reports an error instead of
    being ignored
-   amt: now supports >= or <=
-   clarify status: docs and behaviour; \"*\" is no longer a synonym for
    "1" (fixes #227)

balance:

-   fix: in tree mode, --drop is ignored instead of showing empty account names
-   a depth limit of 0 now shows summary items with account name "...",
    instead of an empty report (#206)
-   in multicolumn balance reports, -E now also shows posting-less
    accounts with a non-zero balance during the period (in addition to
    showing leading & trailing empty columns)
-   in multicolumn reports, multi-commodity amounts are rendered on one
    line for better layout (#186)
-   multicolumn reports' title now includes the report span

register:

-   runs faster with large output
-   supports date2:, and date:/date2: combined with --date2, better (fixes
    #201, #221, #222)
-   a depth limit of 0 now shows summary items (see balance)
-   -A/--average now implies -E/--empty
-   postings with multi-commodity amounts are now top-aligned, like
    Ledger

Extra commands:

-   hledger-equity: fix end date in title; print closing entry too
-   hledger-check-dates: added

# 0.23.3 2014-09-12

-   allow text 1.2+ (#207)

# 0.23.2 2014-05-08

-   register: also fix date sorting of postings (#184)

# 0.23.1 2014-05-07

-   register: fix a refactoring-related regression that the tests
    missed: if transactions were not ordered by date in the journal,
    register could include postings before the report start date in the
    output. (#184)
-   add: don't apply a default commodity to amounts on entry (#138)
-   cli: options before the add-on command name are now also passed to it (#182)
-   csv: allow the first name in a fields list to be empty (#178)
-   csv: don't validate fields count in skipped lines (#177)

# 0.23 2014-05-01

Journal format:

-   A # (hash) in column 0 is now also supported for starting a top-level journal comment, like Ledger.
-   The "too many missing amounts" error now reminds about the 2-space rule.
-   Fix: . (period) is no longer parsed as a valid amount.
-   Fix: default commodity directives no longer limit the maximum display precision (#169).
-   Fix: + before an amount is no longer parsed as part of the commodity (#181).

CLI:

-   Command-line help cleanups, layout improvements.
-   Descriptions are shown for known add-ons in the command list.
-   Command aliases have been simplified.
-   Add-ons can now have any of these file extensions:
    none, hs, lhs, pl, py, rb, rkt, sh, bat, com, exe.
-   Add-ons are displayed without their file extensions when possible.
-   Add-ons with the same name as a built-in command or alias are ignored.
-   Fix: add-on detection and invocation now works on windows.
-   Fix: add-ons with digits in the name are now found.
-   Fix: add-on arguments containing a single quote now work.
-   Fix: when -- is used to hide add-on options from the main program,
    it is no longer passed through as an add-on argument.

Queries:

-   The currency/commodity query prefix (sym:) has been renamed to cur:.
-   Currency/commodity queries are applied more strongly in register and
    balance reports, filtering out unwanted currencies entirely. Eg
    hledger balance cur:'$' now reports only the dollar amounts even if
    there are multi-currency transactions or postings.
-   Amount queries like amt:N, amt:<N and amt:>N, where N is not 0, now do an unsigned
    comparison of the amount and N. That is, they compare the absolute magnitude.
    To do a signed comparison instead, write N with its sign (eg amt:+N, amt:<+N, amt:>-N).
-   Fix: amount queries no longer give false positives on multi-commodity amounts.

accounts:

-   An accounts command has been added, similar to Ledger's, for listing account names
    in flat or hierarchical mode.

add:

-   Tab completion now works at all prompts, and will insert the default if the input area is empty.
-   Account and amount defaults are more robust and useful.
-   Transactions may also be completed by the enter key, when there are no more default postings.
-   Input prompts are displayed in a different colour when supported.

balance:

-   Balance reports in flat mode now always show exclusive (subaccount-excluding) balances.
-   Balance reports in flat mode with --depth now aggregate deeper accounts at the depth limit instead of excluding them.
-   Multicolumn reports in flat mode now support --drop.
-   Multicolumn balance reports can now show the account hierarchy with --tree.
-   Multicolumn report start/end dates are adjusted to encompass the displayed
    report periods, so the first and last periods are "full" and comparable to the others.
-   Fix: zero-balance leaf accounts below a non-zero-balance parent are no longer always shown (#170).
-   Fix: multicolumn reports now support --date2 (cf #174).

balancesheet, cashflow, incomestatement:

-   These commands now support --flat and --drop.

print:

-   Tag queries (tag:) will now match a transaction if any of its postings match.

register:

-   The --display option has been dropped. To see an accurate running total which
    includes the prior starting balance, use --historical/-H (like balance).
-   With a report interval, report start/end dates are adjusted to encompass the displayed
    periods, so the first and last periods are "full" and comparable to the others.
-   Fix: --date2 now works with report intervals (fixes #174).

Miscellaneous:

-   Default report dates now derive from the secondary dates when --date2 is in effect.
-   Default report dates now notice any posting dates outside the transaction dates' span.
-   Debug output improvements.
-   New add-on example: extra/hledger-rewrite.hs, adds postings to matched entries.
-   Compatible with GHC 7.2 (#155) - GHC 7.8, shakespeare 2

# 0.22.2 2014-04-16

-   display years before 1000 with four digits, not three
-   avoid pretty-show to build with GHC < 7.4
-   allow text 1.1, drop data-pprint to build with GHC 7.8.x

# 0.22.1 2014-01-06 and older

See <https://hledger.org/relnotes.html> (or doc/relnotes.md).
