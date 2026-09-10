<!--
 _ _ _
| (_) |__
| | | '_ \
| | | |_) |
|_|_|_.__/

Item order: security fixes first, then breaking changes, then the rest.
Section headings: "Security" first if any, then "Breaking changes"
if any; then topic headings,
or a suitable generic heading (eg Fixes, Improvements), as needed.

-->

API/developer-ish changes in hledger-lib.
For user-visible changes, see the hledger package changelog.


# e5e4e608

Breaking changes

- `Journal`'s derived JSON instance no longer includes its transient
  `jparse*` parser-state fields (`jincludefilestack` is renamed to
  `jparseincludefilestack`, for consistency with the others, and then
  dropped along with them). This affects only hledger-lib users who
  serialise a `Journal` themselves; hledger and hledger-web don't expose
  Journal JSON.

- `matchesPayeeWIP` is renamed to `matchesPayee`, now matching declared
  payees strictly (see the hledger changelog); the unused and
  inconsistent `matchesDescription` is dropped.

- `Hledger.Utils.Text`'s quote helpers are renamed `textStripQuotes`,
  `textIsSingleQuoted` and `textIsDoubleQuoted`, for consistency with
  that module's other names. The `String` versions (`stripQuotes`,
  `isSingleQuoted`, `isDoubleQuoted`) are now exported from
  `Hledger.Utils.String`.

Fixes

- `divideAmount`/`divideMixedAmount` no longer raise an error when
  dividing by zero; they now return the amount unchanged.

Improvements

- `Hledger.Data.Errors.decorateExcerpt` is now exported, and there's a
  new `wordsmay`, a total variant of `words'`.

- `words'` and friends now tokenise quoted arguments more like the
  shell (see the hledger changelog), with new doctests demonstrating
  it. New `wordsEither` is like `wordsmay` but returns the parse error.

- `warnIO` now emits through a swappable handler, settable with the new
  `setWarningHandler`, so a TUI can collect warnings and display them
  itself rather than letting them corrupt the terminal.

- A `Journal` now also records the non-journal files its data came from
  (a CSV rules file, the files it includes, and any file read by a
  `source` rule), so callers watching for changes can watch those too.

- `Write.Spreadsheet`'s `Cell` has a new `cellParts` field, holding a
  multi-commodity amount's individual amounts for writers (eg HTML)
  that want to style each one separately; other writers can ignore it
  and use `cellContent` as before. `Data.Amount` has a new
  `showMixedAmountOneLinePartsB`, like `showMixedAmountOneLineB` but
  returning the amounts individually rather than joined.

- `Hledger.Data.Journal` has a new `journalBaseCurrency` helper,
  returning a journal's apparent base currency (used by the `stats`
  command).

- The aeson lower bound has been relaxed from 2.3 to 2.2.5.1, the
  oldest version not vulnerable to HSEC-2026-0007.


# 1.52.4 2026-09-10

Improvements

- Allow megaparsec 9.8.1+ (but not 9.8.0, because of [megaparsec#572](https://github.com/mrkkrp/megaparsec/issues/572)).


# 1.52.3 2026-08-27



# 1.52.2 2026-08-24



# 1.99.3 2026-06-24

Breaking changes

Fixes

- `amountIntegerWidth` was one too wide with a negative amount that
  truncates to 0 with `Precision 0` (eg -0.3).

Improvements

- Rename `defaultMaxPrecision` to `defaultMaxDisplayPrecision`.
  This constant is a display fallback for amounts representing
  infinite decimals; the new name makes that intent explicit.

- Rename `splitPostingTagName` to `feesplitPostingTagName`.
  The tag was historically called `_split-posting` because fee-splits
  were the only kind. Now that `_lotsplit-posting` exists for per-lot
  splits, the names are renamed for symmetry. The tag value
  `_split-posting` becomes `_feesplit-posting`.

- `Hledger.Write.Ods`: enable digit grouping in output if `AmountStyle` declares any digit groups.
  (Henning Thielemann)

- `Hledger.Write.Ods.CommodityStyle`: use a custom data type instead of a pair.
  (Henning Thielemann)

- `Hledger.Utils.Regex`: new `regexEscape`.

- `Hledger.Data.Amount`: consolidate `showPriceDirective` here.

- `Hledger.Data.Journal`: new `journalBaseCurrencyCode` guesses a base currency.

- `Hledger.Utils.IO`: new `withFileOrStdout`.

- `Hledger.Utils.String`: new `shellQuoteIfNeeded` (double-quote escaping on mingw32, single quotes elsewhere).

- `Hledger.Data.Currency`: some cryptocurrency symbols added for auto-detection
  (roughly the top 100 by market cap).

- The `Query` ADT now has `Cur` for alias-aware cur: queries and`Sym`
  for exact sym: queries. Helpers that operate on these constructors
  are renamed accordingly: queryIsSym -> queryIsCurOrSym,
  queryIsAmtOrSym -> queryIsAmtOrCurOrSym, queryExpandSym{For,}Aliases
  -> queryExpandCur{For,}Aliases, reportSpecExpandSymQueries ->
  reportSpecExpandCurQueries.

- allow megaparsec >9.8



# 1.99.2 2026-04-28

Improvements

- New `Hledger.Data.Errors.makePostingErrorExcerptByIndex` for posting-aware error excerpts
  in cases where the original posting's account name has been rewritten.

- `escapeName` now also escapes `]`, `{`, `}`, and `.`.

# 1.52.1 2026-04-28


# 1.99.1 2026-03-28

(2.0 preview 1)

Breaking changes

- `PostingType`/`RegularPosting`/`ptype` have been renamed to `PostingRealness`/`RealPosting`/`preal`,
  to avoid confusion with the new `ptype` tag.

- `isAccountSubtypeOf` has been moved from `Hledger.Data.Types` to `Hledger.Data.AccountType`.

- Standard transaction balancing ignores postings to accounts of Gain type, which typically occur in lot disposal transactions.
  Those postings are now excluded from normal transaction balancing;
  they are checked by a new disposal balancing check, which makes sure the transaction sums to zero at cost basis.

Features

- New `Hledger.Data.Lots` module with the full lot-tracking pipeline:
  posting classification, lot calculation (FIFO/LIFO/HIFO/AVERAGE and *ALL variants),
  disposal balancing, gain posting inference, and lot subaccount name parsing.
  Key functions: `journalClassifyLotPostings`, `journalCalculateLots`,
  `journalInferAndCheckDisposalBalancing`, `journalInferBasisFromAccountNames`.

- New `Hledger.Write.Ledger` module provides `showTransactionLedger` for Ledger-style lot syntax output.

- `Commodity` type gains a `csourcepos` field, captured during parsing.
  This allows lots-tag validation errors to show file:line and a megaparsec-style excerpt.

Improvements

- `MixedAmount` and `MixedAmountKey` are better documented.

- Amount arithmetic helpers now explicitly discard cost basis.

- `sumSimilarAmountsUsingFirstCost` is renamed to `sumSimilarAmounts`.

- `lotcostp` parser now accepts both Ledger-style `{COST} [DATE] (NOTE)` and
  hledger consolidated `{DATE, "LABEL", COST}` lot annotations.

- New `commentPrependTag` helper and a prepend parameter for `postingAddHiddenAndMaybeVisibleTag`.

- New `amountSetQuantity` helper that resets precision to `NaturalPrecision`,
  for lot-generated amounts with no user-written precision to preserve.

- `postingsAsLines`/`postingAsLines` are parameterised with `AmountFormat`,
  allowing the rendering chain to be reused with different amount formats.
  `AmountFormat` gains a `displayLedgerLotSyntax` field.


# 1.52 2026-03-20

Breaking changes

- A cost basis field (`acostbasis`) has been added to Amount (to store Ledger/Beancount-style cost basis annotations).

Fixes

- invertAmount: with zero amounts, do nothing instead of failing.
  Previously `invertAmount` would raise a "Ratio has zero denominator"
  exception if the amount's quantity was zero. Now it's a no-op in that case.
  [#2476]

[#2476]: https://github.com/hledgerorg/hledger/issues/2476


# 1.51.2 2026-01-08

- Allow base 4.22 / ghc 9.14.

# 1.51.1 2025-12-08

# 1.50.5 2025-12-08

# 1.51 2025-12-05

Breaking changes

- Hledger.Data.Balancing: balanceTransaction -> balanceSingleTransaction
- Hledger.Utils.IO:
  - inputToHandle -> textToHandle; set utf8 not utf8_bom
  - readHandlePortably, readHandlePortably' -> hGetContentsPortably

Improvements

- Hledger.Utils.String:
  quoteForCommandLine now quotes some additional problem characters, and no longer quotes "7".
  [#2468]


# 1.50.4 2025-12-04

# 1.50.3 2025-11-18

# 1.50.2 2025-09-26

# 1.50.1 2025-09-16

# 1.50 2025-09-03

Breaking changes

- hledger now requires at least GHC 9.6 (and base 4.18), to ease maintenance.

Fixes

- Fix liftA2 build error with ghc <9.6 (broken since 1.43.1).

Improvements

- Account now stores balances, one per date period. This enables it do
  the hard work in MultiBalanceReport.
  Some new types are created to enable convenient operation of accounts:
  - `BalanceData` is a type which stores an exclusive balance, inclusive
    balance, and number of postings. This was previously directly stored
    in Account, but is now factored into a separate data type.
  - `PeriodData` is a container which stores date-indexed data, as well as
    pre-period data. In post cases, this represents the report spans,
    along with the historical data.
  - Account becomes polymorphic, allowing customisation of the type of
    data it stores. This will usually be `BalanceData`, but in
    `BudgetReport` it can use `These BalanceData BalanceData` to store
    both actuals and budgets in the same structure. The data structure
    changes to contain a `PeriodData`, allowing multiperiod accounts.
  (Stephen Morgan)
- Hledger.Read: make LatestDatesForFile showable
- Hledger.Read.Common: accountnamep and modifiedaccountnamep now take a flag to allow semicolons or not
- Hledger.Utils.IO: getFlag, warnIO, rename exitOnError -> handleExit, improve doc
- Hledger.Query: matchesCommodity handles all query types, not just cur:, and doesn't match by default
- Hledger.Data.Amount: move commodityStylesFromAmounts here, drop canonicalStyleFrom

# 1.43.2 2025-06-13

- Hledger.Utils.IO: rename exitOnError -> handleExit, improve doc


# 1.43.1 2025-06-04

- Hledger.Query: queryIsAmtOrSym


# 1.43 2025-06-01

- Support GHC 9.12.

- Fix doctest suite with ghc-8.10.7 (Thomas Miedema)

- Drop base-compat dependency (Thomas Miedema)

- Added NFData instances for Journal and subcomponents. (Stephen Morgan)

- Hledger.Data.Dates:
  - renamed parsedateM -> parsedate.
    M makes me think of monad and is awkward to type for this common helper.
    Maybe is expected for a parser.
  - parsedate now also accepts YYYYMMDD format, for convenience in ghci and for parseHledgerVersion.
    This is more permissive, now parsing many integers successfully; hopefully that won't be a problem.
    I noted but did not document two user-facing uses, which now also accept YYYYMMDD dates:
    --value's argument, and import's .latest files.

- Hledger.Data.Journal: journalCommoditiesUsed

- Hledger.Read: more ways to read the default journal:
  defaultJournalWith, defaultJournalSafely, defaultJournalSafelyWith

- Hledger.Utils.Debug:
  - Provide simpler, more consistent dbg* names.
  - A few cases of hledger/hledger-ui debug output which were always
    traced to stderr or always logged to a file, now consistently follow
    the policy on whether to trace or log.

- Hledger.Utils.IO:
  - exitOnError, a helper to clean up unicode errors and GHC error output generally.
  - make parseYN(A) total
  - export findPager, getHomeSafe


# 1.42.2 2025-05-16

- Require extra >= 1.7.11, fixing the stack8.10.yaml build. (Thomas Miedema)


# 1.42.1 2025-03-12


# 1.42 2025-03-07

Improvements

- readJournal, when not given a file name, now always assumes it is "-" rather than "(string)".
  [#2328]
- Reader's rReadFn has changed type (for the new CSV text encoding feature);
  it now takes a `Handle` rather than a `Text`, allowing more flexibility.
- Make test/unittest.hs more buildable; remove PackageImports that was causing
  trouble for ghci.
  (Thomas Miedema, [#2337])
- Added: postingNegate
- Renamed: negatePostingAmount -> postingNegateMainAmount
- Refactor Hledger.Write.Html etc, reducing Lucid references.
  Clarify the HTML lib situation a bit, and clean up some imports.
  [#2244]
- Added: dropRawOpt, cliOptsDropArgs
- Hledger.Data.Amount: showAmountCost(B) now drops leading whitespace.


# 1.41 2024-12-09

Breaking changes

- New/refactored modules (Hledger.Write.*) and types (Spreadsheet) to help
  abstract rendering in various output formats, eg HTML, FODS and beancount.
  Spreadsheet is an abstraction for tabular reports, in addition to the
  tabular package we already use; there may be some overlap.
  (Henning Thielemann)

- Rename displayDepth/prrDepth to displayIndent/prrIndent, and make them
  correspond to the number of indentation steps.
  (These are about indentation for rendering, not account depth.) [#2246]

Improvements

- Add Hledger.Data.Currency, currencySymbolToCode, currencyCodeToSymbol
- AmountFormat: add displayQuotes flag to control enclosing quotes
- InputOpts: add `posting_account_tags_` flag to control account tags on postings
- Support ghc 9.10 and base 4.20.
  Note, when built with ghc 9.10.1, hledger error messages are displayed with two extra trailing newlines.

Other API/doc changes

- Hledger.Utils.IO: cleanup; rgb' now takes Float arguments instead of Word8
- rename jinferredcommodities to jinferredcommoditystyles
- rename jcommodities to jdeclaredcommodities
- move/rename nullsourcepos
- document isBlockActive, matcherMatches
- posting*AsLines: fix some docs



# 1.40 2024-09-09

Breaking changes

- Some constructors of the Interval type have been renamed for clarity.
- Hledger.Read.CsvUtils has moved to Hledger.Write.Csv. (Henning Thielemann)
- Tabular report rendering code has been added/reworked to allow new output formats and more reuse. (Henning Thielemann)

Improvements

- Added `journalDbg` debug output helper.

- Allow doclayout 0.5.

# 1.34 2024-06-01

Improvements

- InputOpts has a new `_defer` flag for internal use instead of overusing `strict_`
- journalCheckBalanceAssertions has moved to JournalChecks


# 1.33.1 2024-05-02

- Updates for hledger 1.33.1


# 1.33 2024-04-18

Breaking changes

Fixes

- Require process 1.6.19.0+ to avoid any vulnerabilities on Windows from
  [HSEC-2024-0003](https://haskell.github.io/security-advisories/advisory/HSEC-2024-0003.html).
  This has also required disabling this package's doctest test suite for the moment.

- A potential Glob/filemanip package conflict in Hledger.Utils.IO now prevented,
  avoiding build failures.


Improvements

- hledger can now be built with GHC 9.8.
- hledger now requires safe >=0.3.20.
- fix spanUnion with open-ended dates; add spanExtend [#2177]
- move readFileStrictly from hledger to Hledger.Utils.IO
- rename/improve amountSetFullPrecisionUpTo; add mixedAmountSetFullPrecisionUpTo
- rename Amount's aprice -> acost
- rename AmountPrice, UnitPrice, TotalPrice -> AmountCost, UnitCost, TotalCost
- showAmountWithoutPrice             -> showAmountWithoutCost
- mixedAmountStripPrices             -> mixedAmountStripCosts
- showMixedAmountWithoutPrice        -> showMixedAmountWithoutCost
- showMixedAmountOneLineWithoutPrice -> showMixedAmountOneLineWithoutCost
- rename amountStripPrices           -> amountStripCost, etc
- rename AmountDisplayOpts -> AmountFormat; add a new flag for symbol display
- rename noColour          -> defaultFmt
- rename noCost            -> noCostFmt
- rename oneLine           -> oneLineFmt
- rename csvDisplay        -> machineFmt
- distinguish oneLineFmt and oneLineNoCostFmt; add fullZeroFmt
- matchedPostingsBeforeAndDuring: improve debug output

[#2177]: https://github.com/hledgerorg/hledger/issues/2177


# 1.32.3 2024-01-28

- Some API renames ended up in this release, including

  - amountStripPrices    -> amountStripCost
  - showAmountPrice      -> showAmountCostB
  - showAmountPriceDebug -> showAmountCostDebug

# 1.32.2 2023-12-31

Breaking changes

- In Hledger.Data.Amount, noPrice is renamed to noCost.

- AmountDisplayOpts has a new displayCommodity flag, controlling commodity symbol display.

Fixes

- Hledger.Utils.Debug.traceOrLog was logging when it should trace and vice versa.

Improvements

- Allow megaparsec 9.6

# 1.32.1 2023-12-07

- readFileStrictly is now provided by Hledger.Utils.IO

# 1.32 2023-12-01

Misc. changes

- styleAmounts is used in more places

- journalApplyCommodityStyles renamed to journalStyleAmounts

- "hard" and "all" rounding strategies have been added

- debug output improvements, eg for precision handling

- Table is now Showable, for debugging


# 1.31 2023-09-03

Breaking changes

- There is a new consolidated API for styling amounts, and a
  convenient HasAmounts typeclass.  AmountStyle's fields have been
  renamed/reordered more mnemonically, and setting the precision is
  now optional.  (This simplifies the amount-stylingn code, but
  complicates the semantics a little. When reading, an unset precision
  generally behaves like NaturalPrecision.)

- (Possible breaking change):
  showMixedAmountLinesB, showAmountB, showAmountPrice now preserve
  commodityful zeroes when rendering. This is intended to affect print output,
  but it seems possible it might also affect balance and register reports,
  though our tests show no change in those.

- Renamed: journalAddInferredEquityPostings -> journalInferEquityFromCosts

Misc. changes

- Reports now do a final amount styling pass before rendering.

- groupByDateSpan code cleanup (Jay Neubrand)

- Allow aeson 2.2, megaparsec 9.5

# 1.30 2023-06-01

Breaking changes

- dropped: Hledger.Data.RawOptions.inRawOpts

Misc. changes

- added more terminal size, ANSI style/color helpers in Hledger.Utils.IO
  (and therefore Hledger and Hledger.Cli.Script):

      getTerminalHeightWidth
      getTerminalHeight
      getTerminalWidth
      bold'
      faint'
      black'
      red'
      green'
      yellow'
      blue'
      magenta'
      cyan'
      white'
      brightBlack'
      brightRed'
      brightGreen'
      brightYellow'
      brightBlue'
      brightMagenta'
      brightCyan'
      brightWhite'
      rgb'
      multicol
      expandGlob
      sortByModTime

# 1.29.2 2023-04-07

# 1.29.1 2023-03-16

- Hledger.Utils.String:

       added:
       strip1Char
       stripBy
       strip1By

- Allow building with GHC 9.6.1; add base-compat (#2011)

# 1.29 2023-03-11
- added terminal colour detection helpers:
  terminalIsLight
  terminalLightness
  terminalFgColor
  terminalBgColor

- Hledger.Data.RawOptions: add unsetboolopt

- add journalMarkRedundantCosts to help with balancing

- journalInferCosts -> journalInferCostsFromEquity

- `BalancingOpts{infer_transaction_prices_ -> infer_balancing_costs_}`

- Hledger.Data.Balancing: inferBalancingPrices -> transactionInferBalancingCosts

- Hledger.Data.Balancing: inferBalancingAmount -> transactionInferBalancingAmount

- Hledger.Data.Journal: transactionAddPricesFromEquity -> transactionInferCostsFromEquity

- Hledger.Data.Journal: journalAddPricesFromEquity -> journalInferCosts

- Hledger.Data.Dates: intervalStartBefore -> intervalBoundaryBefore

- Hledger.Read.Common: cleaned up some amount parsers; describe Ledger lot notation
  ```
  amountpwithmultiplier -> amountp'
  amountpnolotpricesp   -> amountnobasisp
  amountwithoutpricep   -> simpleamountp
  priceamountp          -> costp
  ```

- depend on text-ansi


# 1.28 2022-12-01

- Hledger.Utils.Debug's debug logging helpers have been unified.
  The "trace or log" functions log to stderr by default, or to a file
  if ",logging" is appended to the program name (using withProgName). 
  The debug log file is PROGNAME.log (changed from debug.log).

- Moved from Hledger.Utils.Debug to Hledger.Utils.Parse:
  traceParse
  traceParseAt
  dbgparse

- Moved from Hledger.Utils.Debug to Hledger.Utils.Print:
  pshow
  pshow'
  pprint
  pprint'
  colorOption
  useColorOnStdout
  useColorOnStderr
  outputFileOption
  hasOutputFile

- Rename Hledger.Utils.Print -> Hledger.Utils.IO, consolidate utils there.

- Hledger.Utils cleaned up.

- Hledger.Data.Amount: showMixedAmountOneLine now also shows costs.
  Note that different costs are kept separate in amount arithmetic.

- Hledger.Read.Common: rename/add amount parsing helpers.

  added:
   parseamount
   parseamount'
   parsemixedamount
   parsemixedamount'

  removed:
   amountp'
   mamountp'

- Hledger.Utils.Parse:
  export customErrorBundlePretty, 
  for pretty-printing hledger parse errors.

- Support megaparsec 9.3. (Felix Yan)

- Support GHC 9.4.

- Update cabal files to match hpack 0.35/stack 2.9


# 1.27 2022-09-01

Breaking changes

- Support for GHC 8.6 and 8.8 has been dropped.
  hledger now requires GHC 8.10 or newer.

- Hledger.Data.Amount: `amount` has been dropped; use `nullamt` instead.

- journal*AccountQuery functions have been dropped; use a type: query instead.
  cbcsubreportquery no longer takes Journal as an argument.
  (#1921)

Misc. changes

- Hledger.Utils.Debug now re-exports Debug.Breakpoint from the
  breakpoint library, so that breakpoint's helpers can be used easily
  during development.

- Hledger.Utils.Debug:
  dlog has been replaced by more reliable functions for debug-logging
  to a file (useful for debugging TUI apps like hledger-ui):

  dlogTrace
  dlogTraceAt
  dlogAt
  dlog0
  dlog1
  dlog2
  dlog3
  dlog4
  dlog5
  dlog6
  dlog7
  dlog8
  dlog9

- Hledger.Utils.Debug: pprint' and pshow' have been added,
  forcing monochrome output.

- Hledger.Utils.String: add quoteForCommandLine

- Hledger.Data.Errors: export makeBalanceAssertionErrorExcerpt

- Hledger.Utils.Parse: export HledgerParseErrors

- Debug logging from journalFilePath and the include directive will
  now show "(unknown)" instead of an empty string.

# 1.26.1 2022-07-11

- require safe 0.3.19+ to avoid deprecation warning

# 1.26 2022-06-04

Breaking changes

- readJournal, readJournalFile, readJournalFiles now return
  `ExceptT String IO a` instead of `IO (Either String a)`.
  Internally, this increases composability and avoids some ugly case handling.
  It means that these must now be evaluated with `runExceptT`.
  That can be imported from `Control.Monad.Except` in the `mtl` package,
  but `Hledger.Read` also re-exports it for convenience.

  New variants readJournal', readJournalFiles', readJournalFile' are
  also provided; these are like the old functions but more convenient,
  assuming default input options and needing one less argument.
  (Stephen Morgan)

- parseAndFinaliseJournal' (a variant of parseAndFinaliseJournal) has been removed. 
  In the unlikely event you needed it in your code, you can replace:
  ```haskell
  parseAndFinaliseJournal' parser iopts fp t
  ```
  with:
  ```haskell
  initialiseAndParseJournal parser iopts fp t
  >>= liftEither . journalApplyAliases (aliasesFromOpts iopts)
  >>= journalFinalise iopts fp t
  ```

- Some parsers have been generalised from JournalParser to TextParser.
  (Stephen Morgan)

Misc. changes

- Allow doclayout 0.4.

- Our doctests now run with GHC 9.2+ only, to avoid doctest issues.

- Hledger.Data.JournalChecks: some Journal checks have been moved and renamed:
  journalCheckAccounts,
  journalCheckCommodities,
  journalCheckPayees
  
- Hledger.Data.Errors: new error formatting helpers
  makeTransactionErrorExcerpt,
  makePostingErrorExcerpt,
  transactionFindPostingIndex

- HledgerParseErrors is a new type alias for our parse errors.
  CustomErr has been renamed to HledgerParseErrorData.

- Hledger.Query: added
  matchesQuery,
  queryIsCode,
  queryIsTransactionRelated

- Improve ergonomics of SmartDate constructors. 
  (Stephen Morgan)

- Hledger.Utils: Add a helper function numDigitsInt to get the number
  of digits in an integer, which has a surprising number of ways to
  get it wrong.
  ([#1813](https://github.com/hledgerorg/hledger/issues/1813) (Stephen Morgan)

# 1.25 2022-03-04

- hledger-lib now builds with GHC 9.2 and latest deps. 
  ([#1774](https://github.com/hledgerorg/hledger/issues/1774)

- Journal has a new jaccounttypes map.
  The journalAccountType lookup function makes it easy to check an account's type.
  The journalTags and journalInheritedTags functions look up an account's tags.
  Functions like journalFilterPostings and journalFilterTransactions,
  and new matching functions matchesAccountExtra, matchesPostingExtra
  and matchesTransactionExtra, use these to allow more powerful matching
  that is aware of account types and tags.

- Journal has a new jdeclaredaccounttags field
  for easy lookup of account tags.
  Query.matchesTaggedAccount is a tag-aware version of matchesAccount.

- Some account name functions have moved from Hledger.Data.Posting
  to Hledger.Data.AccountName:
  accountNamePostingType, accountNameWithPostingType, accountNameWithoutPostingType,
  joinAccountNames, concatAccountNames, accountNameApplyAliases, accountNameApplyAliasesMemo.

- Renamed: CommodityLayout to Layout.

# 1.24.1 2021-12-10

Improvements

- Added: filterQueryOrNotQuery.

# 1.24 2021-12-01

Improvements

- The Semigroup instance of PeriodicReportRow and PeriodicReport now
  preserves the first prrName, rather than the second.
  (Stephen Morgan)

- PeriodicReport and PeriodicReportRow now have Bifunctor instances.
  (Stephen Morgan)

- Move posting rendering functions into Hledger.Data.Posting.
  This produces slightly different output for showPosting, in particular
  it no longer displays the transaction date. However, this has been
  marked as ‘for debugging only’ for a while.
  (Stephen Morgan)

- Drop postingDateOrDate2, transactionDateOrDate2; rename
  whichDateFromOpts to whichDate. (#1731)

- Added new helper functions journalValueAndFilterPostings(With) to make
  valuation and filtration less error prone.
  (Stephen Morgan)

- Avoid deprecation warnings with safe 0.3.18+. 
  (Stephen Morgan)

- Drop base-compat-batteries dependency. 
  (Stephen Morgan)

- Allow megaparsec 9.2.

# 1.23 2021-09-21

- Require base >=4.11, prevent red squares on Hackage's build matrix.

Much code cleanup and reorganisation, such as:

- Introduce lenses for many types. (Stephen Morgan)

- The now-obsolete normaliseMixedAmount and
  normaliseMixedAmountSquashPricesForDisplay functions have been
  dropped. (Stephen Morgan)

- GenericSourcePos has been dropped, replaced by either SourcePos or
  (SourcePos, SourcePos), simplifying module structure. (Stephen Morgan)

- Functions related to balancing (both transaction balancing and journal balancing)
  have been moved to Hledger.Data.Balancing, reducing module size and reducing the risk
  of import cycles.
  (Stephen Morgan)

- `ReportOptions{infer_value_}` has been renamed to `infer_prices_`,
  for more consistency with the corresponding CLI flag.
  And `BalancingOpts{infer_prices_}` is now `infer_transaction_prices_`.

- JournalParser and ErroringJournalParser have moved to
  Hledger.Data.Journal. (Stephen Morgan)

- MixedAmounts now have a more predictable Ord instance / sort order.
  They are compared in each commodity in turn, with
  alphabetically-first commodity symbols being most significant.
  Missing commodities are assumed to be zero. 
  As a consequence, all the ways of representing zero with a MixedAmount ([],
  [A 0], [A 0, B 0, ...]) are now Eq-ual (==), whereas before they were
  not. We have not been able to find anything broken by this change.
  ([#1563](https://github.com/hledgerorg/hledger/issues/1563), 
  [#1564](https://github.com/hledgerorg/hledger/issues/1564), 
  Stephen Morgan)

- HUnit's testCase and testGroup are now used directly instead of
  having test and tests aliases. (Stephen Morgan)

- The codebase now passes many hlint checks

- Dropped modules:
  Hledger.Utils.Color,
  Hledger.Data.Commodity,
  Hledger.Utils.UTF8IOCompat,
  Hledger.Utils.Tree module.
  (Stephen Morgan)

- Drop the deprecated old-time lib.
  A small number type signatures have changed:
  journalSetLastReadTime, maybeFileModificationTime and Journal
  now use POSIXTime instead of ClockTime.
  Hledger.Cli.Utils.utcTimeToClockTime has been removed, 
  as it is now equivalent to utcTimeToPOSIXSeconds from Data.Time.Clock.POSIX.
  To get the current system time, you should now use getPOSIXTime 
  from Data.Time.Clock.POSIX instead of getClockTime.
  ([#1650](https://github.com/hledgerorg/hledger/issues/1650), Stephen Morgan)

- modifyTransactions now takes a Map of commodity styles, and will style amounts according to that argument. journalAddForecast and journalTransform now return an Either String Journal. (Stephen Morgan)
  This improves efficiency, as we no longer have to restyle all amounts in
  the journal after generating auto postings or periodic transactions.
  Changing the return type of journalAddForecast and journalTransform
  reduces partiality.
  To get the previous behaviour for modifyTransaction, use modifyTransaction mempty.

- Refactor journalFinalise to clarify flow. (Stephen Morgan)
  The only semantic difference is that we now apply
  journalApplyCommodityStyles before running journalCheckAccountsDeclared
  and journalCheckCommoditiesDeclared.

- Introduce lenses for ReportOpts and ReportSpec. (Stephen Morgan)

- Rename the fields of ReportSpec. (Stephen Morgan)

  This is done to be more consistent with future field naming conventions,
  and to make automatic generation of lenses simpler. See discussion in
  [#1545](https://github.com/hledgerorg/hledger/issues/1545).

      rsOpts      -> _rsReportOpts
      rsToday     -> _rsDay
      rsQuery     -> _rsQuery
      rsQueryOpts -> _rsQueryOpts

- Remove aismultiplier from Amount. (Stephen Morgan)

  In Amount, aismultiplier is a boolean flag that will always be False,
  except for in TMPostingRules, where it indicates whether the posting
  rule is a multiplier. It is therefore unnecessary in the vast majority
  of cases. This posting pulls this flag out of Amount and puts it into
  TMPostingRule, so it is only kept around when necessary.

  This changes the parsing of journals somewhat. Previously you could
  include an * before an amount anywhere in a Journal, and it would
  happily parse and set the aismultiplier flag true. This will now fail
  with a parse error: * is now only acceptable before an amount within an
  auto posting rule.

  Any usage of the library in which the aismultiplier field is read or set
  should be removed. If you truly need its functionality, you should
  switch to using TMPostingRule.

  This changes the JSON output of Amount, as it will no longer include
  aismultiplier.

- For accountTransactionsReport, generate the overall reportq from the ReportSpec, rather than being supplied as a separate option. (Stephen Morgan)

  This is the same approach used by the other reports, e.g. EntryReport,
  PostingReport, MultiBalanceReport. This reduces code duplication, as
  previously the reportq had to be separately tweaked in each of 5
  different places.

  If you call accountTransactionreport, there is no need to separately
  derive the report query.

- Remove unused TransactionReport. Move the useful utility functions to AccountTransactionsReport. (Stephen Morgan)

  If you use transactionsReport, you should either use entryReport if you
  don't require a running total, or using accountTransactionsReport with
  thisacctq as Any or None (depending on what you want included in the
  running total).

- Some balance report types have been renamed for clarity and to sync with docs:

      ReportType -> BalanceCalculation
       ChangeReport -> CalcChange
       BudgetReport -> CalcBudget
       ValueChangeReport -> CalcValueChange

      BalanceType -> BalanceAccumulation
       PeriodChange -> PerPeriod
       CumulativeChange -> Cumulative
       HistoricalBalance -> Historical

      ReportOpts:
       reporttype_ -> balancecalc_
       balancetype_ -> balanceaccum_

      CompoundBalanceCommandSpec:
       cbctype -> cbcaccum

      Hledger.Reports.ReportOptions:
       balanceTypeOverride -> balanceAccumulationOverride

# 1.22.2 2021-08-07

- forecast_ has moved from ReportOpts to InputOpts. (Stephen Morgan)

- Generate forecast transactions at journal finalisation, rather than as a postprocessing step.
  This allows us to have a uniform procedure for balancing transactions,
  whether they are normal transactions or forecast transactions, including
  dealing with balance assignments, balance assertions, and auto postings.
  ([#1638](https://github.com/hledgerorg/hledger/issues/1638), Stephen Morgan)

# 1.22.1 2021-08-02

- Allow megaparsec 9.1

- journalEndDate's behaviour has been clarified, journalLastDay has
  been added.

- transactionCheckBalanced is now exported. (#1596)

# 1.22 2021-07-03

- GHC 9.0 is now officially supported, and GHC 8.0, 8.2, 8.4 are not;
  building hledger now requires GHC 8.6 or greater.

- Added now-required lower bound on containers. (#1514)

- Added useColor, colorOption helpers usable in pure code, eg for debug output.

- Added a Show instance for AmountDisplayOpts and WideBuilder, for debug logging.

Many internal refactorings/improvements/optimisations by Stephen Morgan,
including:

- Don't infer a txn price with same-sign amounts. (#1551)

- Clean up valuation functions, and make clear which to use where. (#1560)

- Replace journalSelectingAmountFromOpts with journalApplyValuationFromOpts.
  This also has the effect of allowing valuation in more reports, for
  example the transactionReport.

- Refactor to eliminate use of printf.

- Remove unused String, Text utility functions.

- Replace concat(Top|Bottom)Padded with textConcat(Top|Bottom)Padded.

- Export Text.Tabular from Text.Tabular.AsciiWide, clean up import lists.

- When matching an account query against a posting, don't try to match
  against the same posting twice, in cases when poriginal is Nothing.

- Create mixedAmountApplyValuationAfterSumFromOptsWith for doing any
  valuation needed after summing amounts.

- Create journalApplyValuationFromOpts. This does costing and
  valuation on a journal, and is meant to replace most direct calls of
  costing and valuation. The exception is for reports which require
  amounts to be summed before valuation is applied, for example a
  historical balance report with --value=end.

- Remove unused (amount|mixedAmount|posting|transaction)ApplyCostValuation functions.

- Remove unnecessary normalisedMixedAmount.

- Remove `showAmounts*B` functions, replacing them entirely with
  `showMixedAmount*B` functions.

- Pull "show-costs" option used by the Close command up into ReporOpts.

- Add more efficient toEncoding for custom ToJSON declarations.

- Fix ledgerDateSpan, so that it considers both transaction and
  posting dates. (#772)

- Move reportPeriodName to Hledger.Reports.ReportOptions, use it for
  HTML and CSV output for compound balance reports.

- Simplify the JSON representation of AmountPrecision. It now uses the
  same JSON representation as Maybe Word8. This means that the JSON
  serialisation is now broadly compatible with that used before the
  commit f6fa76bba7530af3be825445a1097ae42498b1cd, differing only in
  how it handles numbers outside Word8 and that it can now produce
  null for NaturalPrecision.

- A number of AccountName and Journal functions which are supposed to
  produce unique sorted results now use Sets internally to be slightly
  more efficient. There is also a new function journalCommodities.

- More efficiently check whether Amounts are or appear to be zero.
  Comparing two Quantity (either with == or compare) does a lot of
  normalisation (calling roundMax) which is unnecessary if we're
  comparing to zero. Do things more directly to save work.
  For `reg -f examples/10000x10000x10.journal`, this results in

  - A 12% reduction in heap allocations, from 70GB to 62GB
  - A 14% reduction in (profiled) time, from 79s to 70s

  Results for bal -f examples/10000x10000x10.journal are of the same
  order of magnitude.

- In sorting account names, perform lookups on HashSets and HashMaps,
  rather than lists. This is probably not an enormous performance sink
  in real situations, but it takes a huge amount of time and memory in
  our benchmarks (specifically 10000x10000x10.journal). For 
  `bal -f examples/10000x10000x10.journal`, this results in

  - A 23% reduction in heap allocation, from 27GiB to 21GiB
  - A 33% reduction in (profiled) time running, from 26.5s to 17.9s

- Minor refactor, using foldMap instead of asum . map . toList.

- Do not call showAmount twice for every posting. For print -f
  examples/10000x10000x10.journal, this results in a 7.7% reduction in
  heap allocations, from 7.6GB to 7.1GB.

- Some efficiency improvements in register reports.
  Use renderRow interface for Register report.

  For `reg -f examples/10000x10000x10.journal`, this results in:

  - Heap allocations decreasing by 55%, from 68.6GB to 31.2GB
  - Resident memory decreasing by 75%, from 254GB to 65GB
  - Total (profiled) time decreasing by 55%, from 37s to 20s

- Split showMixedAmountB into showMixedAmountB and showAmountsB, the
  former being a simple wrapper around the latter. This removes the
  need for the showNormalised option, as showMixedAmountB will always
  showNormalised and showAmountsB will never do so.

- Change internal representation of MixedAmount to use a strict Map
  instead of a list of Amounts. No longer export Mixed constructor, to
  keep API clean. (If you really need it, you can import it directly
  from Hledger.Data.Types). We also ensure the JSON representation of
  MixedAmount doesn't change: it is stored as a normalised list of
  Amounts.
  
  This commit improves performance. Here are some indicative results:

      hledger reg -f examples/10000x1000x10.journal
      - Maximum residency decreases from 65MB to 60MB (8% decrease)
      - Total memory in use decreases from 178MiB to 157MiB (12% decrease)

      hledger reg -f examples/10000x10000x10.journal
      - Maximum residency decreases from 69MB to 60MB (13% decrease)
      - Total memory in use decreases from 198MiB to 153MiB (23% decrease)

      hledger bal -f examples/10000x1000x10.journal
      - Total heap usage decreases from 6.4GB to 6.0GB (6% decrease)
      - Total memory in use decreases from 178MiB to 153MiB (14% decrease)

      hledger bal -f examples/10000x10000x10.journal
      - Total heap usage decreases from 7.3GB to 6.9GB (5% decrease)
      - Total memory in use decreases from 196MiB to 185MiB (5% decrease)

      hledger bal -M -f examples/10000x1000x10.journal
      - Total heap usage decreases from 16.8GB to 10.6GB (47% decrease)
      - Total time decreases from 14.3s to 12.0s (16% decrease)

      hledger bal -M -f examples/10000x10000x10.journal
      - Total heap usage decreases from 108GB to 48GB (56% decrease)
      - Total time decreases from 62s to 41s (33% decrease)

  If you never directly use the constructor Mixed or pattern match against
  it then you don't need to make any changes. If you do, then do the
  following:

  - If you really care about the individual Amounts and never normalise
    your MixedAmount (for example, just storing `Mixed amts` and then
    extracting `amts` as a pattern match, then use should switch to using
    [Amount]. This should just involve removing the `Mixed` constructor.
  - If you ever call `mixed`, `normaliseMixedAmount`, or do any sort of
    amount arithmetic (+), (-), then you should replace the constructor
    `Mixed` with the function `mixed`. To extract the list of Amounts, use
    the function `amounts`.
  - Any remaining calls to `normaliseMixedAmount` can be removed, as that
    is now the identity function.

- Create a new API for MixedAmount arithmetic. This should supplant
  the old interface, which relied on the Num typeclass. MixedAmount
  did not have a very good Num instance. The only functions which were
  defined were fromInteger, (+), and negate. Furthermore, it was not
  law-abiding, as 0 + a /= a in general. Replacements for used
  functions are:

      0 -> nullmixedamt / mempty
      (+) -> maPlus / (<>)
      (-) -> maMinus
      negate -> maNegate
      sum -> maSum
      sumStrict -> maSum

  Also creates some new constructors for MixedAmount:

      mixedAmount :: Amount -> MixedAmount
      maAddAmount :: MixedAmount -> Amount -> MixedAmount
      maAddAmounts :: MixedAmount -> [Amount] -> MixedAmount

  Add Semigroup and Monoid instances for MixedAmount.
  Ideally we would remove the Num instance entirely.

  The only change needed have nullmixedamt/mempty substitute for 0
  without problems was to not squash prices in
  mixedAmount(Looks|Is)Zero. This is correct behaviour in any case.


# 1.21 2021-03-10

- Building Hledger.Data.Journal no longer fails if the monad-extras
  package is installed.

- Many parts of the hledger-lib and hledger APIs have become more
  Text-ified, expecting or returning Text instead of String, reducing
  hledger's time and resident memory requirements by roughly 10%.
  Some functions now use WideBuilder (a text "builder" which keeps track
  of width), to concatenate text more efficiently. There are some
  helpers for converting to and from WideBuilder (wbUnpack, wbToText..)
  showAmountB/showMixedAmountB are new amount-displaying functions
  taking an AmountDisplayOpts. These will probably replace the old
  show(Mixed)Amount* functions. (#1427, Stephen Morgan)

- AtThen valuation is now implemented for all report types.
  amountApplyValuation now takes the posting date as an argument.
  (transaction/posting)ApplyValuation's valuation type and
  transaction/posting arguments have been reordered like
  amountApplyValuation's. (Stephen Morgan)

- Amount, AmountPrice, AmountStyle, DigitGroupStyle fields are now
  strict. (Stephen Morgan)

- Amount prices are now stored with their sign, so negative prices can
  be represented. (They seem to have always worked, but now the
  internal representation is more accurate.) (Stephen Morgan)
 
- normaliseMixedAmount now combines Amounts with TotalPrices in the
  same commodity. (Stephen Morgan)

- normaliseMixedAmount now uses a strict Map for combining amounts
  internally, closing a big space leak. (Stephen Morgan)

- (multiply|divide)(Mixed)?Amount now also multiply or divide the
  TotalPrice if it is present, and the old
  (multiply|divide)(Mixed)?AmountAndPrice functions are removed. (Stephen Morgan)

- (amount|mixedAmount)(Looks|Is)Zero functions now check whether both
  the quantity and the cost are zero. This is usually what you want,
  but if you do only want to check whether the quantity is zero, you
  can run mixedAmountStripPrices (or similar) before this. (Stephen Morgan)

- commodityStylesFromAmounts now consumes the list immediately,
  reducing the maximum heap size per thread from ~850K to ~430K in a
  real-world register report. (Stephen Morgan)

- *ApplyValuation functions take two less arguments, and
  *ApplyCostValuation functions have been added, performing both
  costing and valuation. (Stephen Morgan)

- traceAtWith now has a level argument and works properly.

- API changes include:
  ```
  Hledger.Data.Amount:
   setAmountPrecision -> amountSetPrecision
   setFullPrecision -> amountSetFullPrecision
   setMixedAmountPrecision -> mixedAmountSetPrecision
   showMixed -> showMixedAmountB
   showMixedLines -> showMixedAmountLinesB
  -mixedAmountSetFullPrecision

  Hledger.Data.Journal:
   mapJournalTransactions -> journalMapTransactions
   mapJournalPostings -> journalMapPostings
  -mapTransactionPostings
  +journalPayeesUsed
  +journalPayeesDeclaredOrUsed

  Hledger.Data.Transaction:
  +transactionFile
  +transactionMapPostings

  Hledger.Data.Valuation:
  -valuationTypeIsCost
  -valuationTypeIsDefaultValue
  -ValuationType's AtDefault constructor

  Hledger.Query:
  +matchesDescription
  +matchesPayeeWIP

  Hledger.Utils.Text:
  +textConcatBottomPadded
  +wbToText
  +wbUnpack

  Text.Tabular.AsciiWide:
   alignCell -> textCell
  ```
# 1.20.4 2021-01-29

- See hledger.

# 1.20.3 2021-01-14

- See hledger.

# 1.20.2 2020-12-28

- Fix the info manuals' node structure.

- Drop unused parsec dependency.

# 1.20.1 2020-12-15

- renamed: updateReportSpecFromOpts -> updateReportSpec[With]

# 1.20 2020-12-05

- added: journalApplyAliases, transactionApplyAliases, postingApplyAliases

- a new more robust price lookup implementation, fgl library dropped (#1402)

- Reverted a stripAnsi change in 1.19.1 that caused a 3x slowdown of amount rendering 
  in terminal reports. (#1350)

- Amount and table rendering has been improved, so that stripAnsi is no longer needed.
  This speeds up amount rendering in the terminal, speeding up some reports by 10% or more since 1.19.
  (Stephen Morgan)

- global commodity display styles can now be set in InputOpts or Journal,
  overriding all others (declared or inferred). This is used by the import
  command and probably command-line options in future.

- Journal keeps a new piece of parsing state, a decimal mark character,
  which can optionally be set to force the number format expected by all
  amount parsers.

- Remove Empty Query constructor, which does nothing and has done so for a very long time. (Stephen Morgan)

- In ReportOpts, store query terms term-by-term in a list in querystring_. (Stephen Morgan)
  This helps deal with tricky quoting issues, as we no longer have to make
  sure everything is quoted properly before merging it into a string.

- Implement concat(Top|Bottom)Padded in terms of renderRow, allowing them to be width aware. (Stephen Morgan)

- Expand Tabular.AsciiWide to allow multiline, custom-width,
  vertically/horizontally-aligned cells, and optional table borders.
  (Stephen Morgan)

- Introduce showMixed*Unnormalised, eliminate most direct calls of strWidth. (Stephen Morgan)

- showMixedAmountElided now makes better use of space, showing as many
  Amounts possible as long as they and the elision string fit within
  32 characters. (Stephen Morgan)

- Add Functor instance for CompoundPeriodicReport. (Stephen Morgan)

- Generalise CBCSubreportSpec to allow more subreport control. (Stephen Morgan)

- Export some MultiBalanceReport helper functions. (Stephen Morgan)

- Make Default instances clearer, remove Default instance for Bool. (Stephen Morgan)

- Many ReportOpts-related changes, such as the addition of ReportSpec, aimed
  at preventing runtime errors (from parsing: regexps, dates, format strings;
  from not having today's date set; etc.)
  ReportSpec holds a ReportOpts, the day of the report, and the Query generated from these.

- StringFormat now takes an optional overline width, which is
  currently only used by defaultBalanceLineFormat. (Stephen Morgan)

- quoteIfNeeded should not escape the backslashes in unicode code points. (Stephen Morgan)

- Export OrdPlus and constructors. (Stephen Morgan)

- Debug output now uses pretty-simple instead pretty-show.
  This hopefully gives overall nicer debug output (eg in colour), 
  including for values which don't have Read-able Show output.
  This means that we can start removing custom Show instances 
  that were a workaround for pretty-show. Eg account names
  in debug output no longer show their colons as underscores.

  Here's some old pretty-show output:

   CsvRules
     { rdirectives = [ ( "skip" , "1" ) ]
     , rcsvfieldindexes = [ ( "date" , 1 ) , ( "amount" , 2 ) ]
     , rassignments = [ ( "amount" , "%2" ) , ( "date" , "%1" ) ]
     , rconditionalblocks = []
     }

  And the new pretty-simple output:

   CsvRules
     { rdirectives=
       [ ( "skip", "1" ) ]
     , rcsvfieldindexes=
       [ ( "date", 1 ), ( "amount", 2 ) ]
     , rassignments=
       [ ( "amount", "%2" ), ( "date", "%1" ) ]
     , rconditionalblocks= []
     }

  We require pretty-simple 4.0.0.0 to get this compact output.
  It's a little less compact than pretty-show, but not too bad.
  Non-compact pretty-simple output would be:

   CsvRules
       { rdirectives=
           [
               ( "skip"
               , "1B"
               )
           ]
       , rcsvfieldindexes=
           [
               ( "date"
               , 1
               )
           ,
               ( "amount"
               , 2
               )
           ]
       , rassignments=
           [
               ( "amount"
               , "%2"
               )
           ,
               ( "date"
               , "%1"
               )
           ]
       , rconditionalblocks=[]
       }


# 1.19.1 2020-09-07

- Allow megaparsec 9

- stripAnsi: correctly strip ansi sequences with no
  numbers/semicolons. (Stephen Morgan)

- Added case-insensitive accountNameToAccountRegexCI,
  accountNameToAccountOnlyRegexCI, made the default account type
  queries case insensitive again. (#1341)

# 1.19 2020-09-01

- Added a missing lower bound for aeson, making cabal installs more
  reliable. (#1268)

- The Regex type alias has been replaced by the Regexp ADT, which
  contains both the compiled regular expression (so is guaranteed to
  be usable at runtime) and the original string (so can be serialised,
  printed, compared, etc.) A Regexp also knows whether is it case
  sensitive or case insensitive. The Hledger.Utils.Regex API has
  changed. (#1312, #1330).

- Typeable and Data instances are no longer derived for hledger's
  data types; they were redundant/no longer needed.

- NFData instances are no longer derived for hledger's data types.
  This speeds up a full build by roughly 7%. But it means we can't
  deep-evaluate hledger values, or time hledger code with Criterion.
  https://github.com/hledgerorg/hledger/pull/1330#issuecomment-684075129
  has some ideas on this.

- Query no longer has a custom Show instance

- Hledger.Utils.String: quoteIfNeeded now actually escapes quotes in
  strings. escapeQuotes was dropped. (Stephen Morgan)

- Hledger.Utils.Tree: dropped some old utilities

- Some fromIntegral calls have been replaced with safer code, removing
  some potential for integer wrapping bugs (#1325, #1326)

- Parsing numbers with more than 255 decimal places now gives an error
  instead of silently misparsing (#1326)

- Digit groups are now limited to at most 255 digits each. (#1326)

- Exponents are parsed as Integer rather than Int.
  This means exponents greater than 9223372036854775807 or less than
  -9223372036854775808 are now parsed correctly, in theory. (In
  practice, very large exponents will cause hledger to eat all your
  memory, so avoid them for now.) (#1326)

- AmountStyle's asprecision is now a sum type with Word8, instead of
  an Int with magic values.

- DigitGroupStyle uses Word8 instead of Int.

- Partial helper function parsedate has been dropped, use fromGregorian instead.

- Partial helper function mkdatespan has been dropped.

- Helper function transaction now takes a Day instead of a date string. (Stephen Morgan)

- Old CPP directives made redundant by version bounds have been
  removed. (Stephen Morgan)

- Smart dates are now represented by the SmartDate type, and are
  always well formed. (Stephen Morgan)

- accountTransactionsReport (used for hledger aregister and
  hledger-ui/hledger-web registers) now filters transactions more
  thoroughly, so eg transactions dated outside the report period will
  not be shown. Previously the transaction would be shown if it had
  any posting dated inside the report period. Possibly some other
  filter criteria now get applied that didn't before. I think on
  balance this will give slightly preferable results.

- The old BalanceReport code has been dropped at last, replaced by
  MultiBalanceReport so that all balance reports now use the same
  code. (Stephen Morgan, #1256).

  - The large multiBalanceReport function has been split up and refactored
    extensively.
  - Tabular data formerly represented as [[MixedAmount]] is now HashMap
    AccountName (Map DateSpan Account). Reports with many columns are now faster.
  - Calculating starting balances no longer calls the whole balanceReport,
    just the first few functions.
  - displayedAccounts is completely rewritten. Perhaps one subtle thing to
    note is that in tree mode it no longer excludes nodes with zero inclusive
    balance unless they also have zero exclusive balance.
  - Simon's note: "I'll mark the passing of the old multiBalanceReport, into
    which I poured many an hour :). It is in a way the heart (brain ?) of
    hledger - the key feature of ledgerlikes (balance report) and a key
    improvement introduced by hledger (tabular multiperiod balance reports)
    ...
    Thanks @Xitian9, great work."

# 1.18.1 2020-06-21

- fix some doc typos (Martin Michlmayr)

# 1.18 2020-06-07

- added: getHledgerCliOpts', takes an explicit argument list

- added: toJsonText

- changed: isNegativeMixedAmount now gives an answer for
  multi-commodity amounts which are all negative

- changed: multiBalanceReport now gets the query from ReportOpts (Dmitry Astapov)

- renamed:
  isZeroAmount                -> amountLooksZero
  isReallyZeroAmount          -> amountIsZero
  isZeroMixedAmount           -> mixedAmountLooksZero
  isReallyZeroMixedAmount     -> mixedAmountIsZero
  isReallyZeroMixedAmountCost dropped

- renamed: finaliseJournal -> journalFinalise

- renamed: fixedlotpricep -> lotpricep, now also parses non-fixed lot prices

- dropped: transactionPostingBalances

- dropped: outputflags no longer exported by Hledger.Cli.CliOptions

- fixed: documentation for journalExpenseAccountQuery (Pavan Rikhi)

# 1.17.1 2020-03-19

- require newer Decimal, math-functions libs to ensure consistent
  rounding behaviour, even when built with old GHCs/snapshots. 
  hledger uses banker's rounding (rounds to nearest even number, eg
  0.5 displayed with zero decimal places is "0").

- added: debug helpers traceAt, traceAtWith

- Journal is now a Semigroup, not a Monoid (since <> is right-biased). (Stephen Morgan)

# 1.17.0.1 2020-03-01

- fix org heading comments and doctest setup comment that were
  breaking haddock (and in some cases, installation)

# 1.17 2020-03-01

- Reader-finding utilities have moved from Hledger.Read to
  Hledger.Read.JournalReader so the include directive can use them.

- Reader changes:
  - rExperimental flag removed
  - old rParser renamed to rReadFn
  - new rParser field provides the actual parser.
    This seems to require making Reader a higher-kinded type, unfortunately.

- Hledger.Tabular.AsciiWide now renders smoother outer borders in
  pretty (unicode) mode.
  Also, a fix for table edges always using single-width intersections
  and support for double horizontal lines with single vertical lines. (Eric Mertens)

- Hledger.Utils.Parse: restofline can go to eof also

- Hledger.Read cleanup

- Hledger.Read.CsvReader cleanup
  Exports added: CsvRecord, CsvValue, csvFileFor.
  Exports removed: expandIncludes, parseAndValidateCsvRules, transactionFromCsvRecord

- more cleanup of amount canonicalisation helpers (#1187)
  Stop exporting journalAmounts, overJournalAmounts, traverseJournalAmounts.
  Rename journalAmounts helper to journalStyleInfluencingAmounts.

- export mapMixedAmount

- Don't store leaf name in PeriodReport. (Stephen Morgan)
  Calculate at the point of consumption instead.

- Generalise PeriodicReport to be polymorphic in the account labels. (Stephen Morgan)

- Use records instead of tuples in PeriodicReport. (Stephen Morgan)

- Use PeriodicReport in place of MultiBalanceReport. (Stephen Morgan)

- Calculate MultiReportBalance columns more efficiently. (Stephen Morgan)
  Only calculate posting date once for each posting, and calculate their
  columns instead of checking each DateSpan separately.

- Moved JSON instances from hledger-web to hledger-lib (Hledger.Data.Json),
  and added ToJSON instances for all (?) remaining data types, up to Ledger.

- Dropped nullassertion's "assertion" alias, fixing a warning.
  Perhaps we'll stick with the null* naming convention. 


# 1.16.2 2020-01-14

- add support for megaparsec 8 (#1175)

# 1.16.1 2019-12-03

- Drop unnecessary mtl-compat dependency

- Fix building with GHC 8.0, 8.2

# 1.16 2019-12-01

- drop support for GHC 7.10, due to MonadFail hassles in JournalReader.hs

- add support for GHC 8.8, base-compat 0.11 (#1090)

  We are now using the new fail from the MonadFail class, which we
  always import as qualified Fail.fail, from base-compat-batteries
  Control.Monad.Fail.Compat to work with old GHC versions. If old fail
  is needed (shouldn't be) it should be imported qualified as
  Prelude.Fail, using imports such as:

      import Prelude hiding (fail)
      import Prelude qualified (fail)
      import Control.Monad.State.Strict hiding (fail)
      import "base-compat-batteries" Prelude.Compat hiding (fail)
      import "base-compat-batteries" qualified Control.Monad.Fail.Compat as Fail

- hledger and hledger-lib unit tests have been ported to tasty.

- The doctest suite has been disabled for now since it doesn't run
  well with cabal (#1139)
  
# 1.15.2 2019-09-05

Changes:

- postingApplyValuation, mixedAmountApplyValuation, amountApplyValuation
  take an argument, the report end date if one was specified.

# 1.15.1 2019-09-02

- fix failing doctests

# 1.15 2019-09-01

Removals include:

- journalPrices
- BalanceHistoryReport
- postingValueAtDate

Additions include:

- MarketPrice (more pure form of PriceDirective without the amount style information)
- PriceOracle (efficient lookup of exchange rates)
- ValuationType (ways to convert amount value)
- aliasnamep (export)
- setNaturalPrecisionUpTo
- dbgNWith, ptraceAtWith
- postingTransformAmount, postingToCost, postingValue
- amountToCost, mixedAmountToCost
- valueTypeFromOpts
- mapJournalTransactions, mapJournalPostings, mapTransactionPostings
- journalStartDate, journalEndDate
- journalPriceOracle
- marketPriceReverse
- priceDirectiveToMarketPrice
- mixedAmountApplyValuation
- mixedAmountValueAtDate

Changes include:

- Price -> AmountPrice,  AKA "transaction price"
- old MarketPrice -> PriceDirective
- TransactionsReport/AccountTransactionsReport split into separate files
- journalTransactionsReport -> transactionsReport
- accountTransactionsReportItems: rewrite using catMaybes and mapAccumL (Henning Thielemann)
- optionally save the current date in ReportOpts
- Hledger.Cli tests now have correct prefix; add Cli.Utils tests
- MultiBalanceReport now returns zero for row totals when in cumulative or historical mode (#329)


# 1.14.1 2019-03-20

- require easytest <0.3 to fix build issue

# 1.14 2019-03-01

- added:  
  transaction, [v]post*, balassert* constructors, for tests etc.  

- renamed:  
  porigin -> poriginal  

- refactored:  
  transaction balancing & balance assertion checking (#438)

# 1.13.1 (2019/02/02)

- stop depending on here to avoid haskell-src-meta/stackage blockage.

# 1.13 (2019/02/01)

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


# 1.12 (2018/12/02)

-   switch to megaparsec 7 (Alex Chen)
    We now track the stack of include files in Journal ourselves, since
    megaparsec dropped this feature.

-   add 'ExceptT' layer to our parser monad again (Alex Chen)
    We previously had a parser type, 'type ErroringJournalParser = ExceptT
    String ...' for throwing parse errors without allowing further
    backtracking. This parser type was removed under the assumption that it
    would be possible to write our parser without this capability. However,
    after a hairy backtracking bug, we would now prefer to have the option to
    prevent backtracking.

    -   Define a 'FinalParseError' type specifically for the 'ExceptT' layer
    -   Any parse error can be raised as a "final" parse error
    -   Tracks the stack of include files for parser errors, anticipating the
        removal of the tracking of stacks of include files in megaparsec 7
        -   Although a stack of include files is also tracked in the 'StateT
            Journal' layer of the parser, it seems easier to guarantee correct
            error messages in the 'ExceptT FinalParserError' layer
        -   This does not make the 'StateT Journal' stack redundant because the
            'ExceptT FinalParseError' stack cannot be used to detect cycles of
            include files

-   more support for location-aware parse errors when re-parsing (Alex Chen)

-   make 'includedirectivep' an 'ErroringJournalParser' (Alex Chen)

-   drop Ord instance breaking GHC 8.6 build (Peter Simons)

-   flip the arguments of (divide\|multiply)\[Mixed\]Amount

-   showTransaction: fix a case showing multiple missing amounts
    showTransaction could sometimes hide the last posting's amount even if
    one of the other posting amounts was already implicit, producing invalid
    transaction output.

-   plog, plogAt: add missing newline

-   split up journalFinalise, reorder journal finalisation steps (#893) (Jesse Rosenthal)
    The `journalFinalise` function has been split up, allowing more granular
    control.

-   journalSetTime --> journalSetLastReadTime

-   journalSetFilePath has been removed, use journalAddFile instead

# 1.11.1 (2018/10/06)

-   add, lib: fix wrong transaction rendering in balance assertion errors
    and when using the add command

# 1.11 (2018/9/30)

-   compilation now works when locale is unset (#849)

-   all unit tests have been converted from HUnit+test-framework to easytest

-   doctests now run quicker by default, by skipping reloading between tests.
    This can be disabled by passing --slow to the doctests test suite
    executable.

-   doctests test suite executable now supports --verbose, which shows
    progress output as tests are run if doctest 0.16.0+ is installed
    (and hopefully is harmless otherwise).

-   doctests now support file pattern arguments, provide more informative output.
    Limiting to just the file(s) you're interested can make doctest start
    much quicker. With one big caveat: you can limit the starting files,
    but it always imports and tests all other local files those import.

-   a bunch of custom Show instances have been replaced with defaults,
    for easier troubleshooting. These were sometimes obscuring
    important details, eg in test failure output. Our new policy is:
    stick with default derived Show instances as far as possible, but
    when necessary adjust them to valid haskell syntax so pretty-show
    can pretty-print them (eg when they contain Day values, cf
    https://github.com/haskell/time/issues/101). By convention, when
    fields are shown in less than full detail, and/or in double-quoted
    pseudo syntax, we show a double period (..) in the output.

-   Amount has a new Show instance. Amount's show instance hid
    important details by default, and showing more details required
    increasing the debug level, which was inconvenient. Now it has a
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

-   Same-line & next-line comments of transactions, postings, etc.
    are now parsed a bit more precisely (followingcommentp).
    Previously, parsing no comment gave the same result as an empty
    comment (a single newline); now it gives an empty string.\
    Also, and perhaps as a consequence of the above, when there's no
    same-line comment but there is a next-line comment, we'll insert an
    empty first line, since otherwise next-line comments would get moved
    up to the same line when rendered.

-   Hledger.Utils.Test exports HasCallStack

-   queryDateSpan, queryDateSpan' now intersect date AND'ed date spans
    instead of unioning them, and docs are clearer.

-   pushAccount -> pushDeclaredAccount

-   jaccounts -> jdeclaredaccounts

-   AutoTransaction.hs -> PeriodicTransaction.hs & TransactionModifier.hs

-   Hledger.Utils.Debug helpers have been renamed/cleaned up

# 1.10 (2018/6/30)

-   build cleanly with all supported GHC versions again (7.10 to 8.4)

-   support/use latest base-compat (#794)

-   support/require megaparsec 6.4+

-   extensive refactoring and cleanup of parsers and related types and utilities

-   readJournalFile(s) cleanup, these now use InputOpts

-   doctests now run a bit faster (#802)

# 1.9.1 (2018/4/30)

-   new generic PeriodicReport, and some report-related type aliases

-   new BudgetReport

-   make (readJournal\|tryReader)s?WithOpts the default api, dropping "WithOpts"

-   automated postings and command line account aliases happen earlier
    in journal processing (see hledger changelog)

# 1.9 (2018/3/31)

-   support ghc 8.4, latest deps

-   when the system text encoding is UTF-8, ignore any UTF-8 BOM prefix
    found when reading files.

-   CompoundBalanceReport amounts are now normally positive.
    The bs/bse/cf/is commands now show normal income, liability and equity
    balances as positive. Negative numbers now indicate a contra-balance
    (eg an overdrawn checking account), a net loss, a negative net worth,
    etc. This makes these reports more like conventional financial
    statements, and easier to read and share with others. (experimental)

-   splitSpan now returns no spans for an empty datespan

-   don't count periodic/modifier txns in Journal debug output

-   lib/ui/web/api: move embedded manual files to extra-source-files

-   Use skipMany/skipSome for parsing spacenonewline (Moritz Kiefer)
    This avoids allocating the list of space characters only to then
    discard it.

-   rename, clarify purpose of balanceReportFromMultiBalanceReport

-   fix some hlint warnings

-   add some easytest tests

# 1.5 (2017/12/31)

-   -V/--value uses today's market prices by default, not those of last transaction date. #683, #648)

-   csv: allow balance assignment (balance assertion only, no amount) in csv records (Nadrieril)

-   journal: allow space as digit group separator character, #330 (Mykola Orliuk)

-   journal: balance assertion errors now show line of failed assertion posting, #481 (Sam Jeeves)

-   journal: better errors for directives, #402 (Mykola Orliuk)

-   journal: better errors for included files, #660 (Mykola Orliuk)

-   journal: commodity directives in parent files are inherited by included files, #487 (Mykola Orliuk)

-   journal: commodity directives limits precision even after -B, #509 (Mykola Orliuk)

-   journal: decimal point/digit group separator chars are now inferred from an applicable commodity directive or default commodity directive. #399, #487 (Mykola Orliuk)

-   journal: numbers are parsed more strictly (Mykola Orliuk)

-   journal: support Ledger-style automated postings, enabled with --auto flag (Dmitry Astapov)

-   journal: support Ledger-style periodic transactions, enabled with --forecast flag (Dmitry Astapov)

-   period expressions: fix "nth day of {week,month}", which could generate wrong intervals (Dmitry Astapov)

-   period expressions: month names are now case-insensitive (Dmitry Astapov)

-   period expressions: stricter checking for invalid expressions (Mykola Orliuk)

-   period expressions: support "every 11th Nov" (Dmitry Astapov)

-   period expressions: support "every 2nd Thursday of month" (Dmitry Astapov)

-   period expressions: support "every Tuesday", short for "every <n>th day of week" (Dmitry Astapov)

-   remove upper bounds on all but hledger* and base (experimental)
    It's rare that my deps break their api or that newer versions must
    be avoided, and very common that they release new versions which I
    must tediously and promptly test and release hackage revisions for
    or risk falling out of stackage. Trying it this way for a bit.

# 1.4 (2017/9/30)

-   add readJournalFile\[s\]WithOpts, with simpler arguments and support
    for detecting new transactions since the last read.

-   query: add payee: and note: query terms, improve description/payee/note docs (Jakub Zárybnický, Simon Michael, #598, #608)

-   journal, cli: make trailing whitespace significant in regex account aliases
    Trailing whitespace in the replacement part of a regular expression
    account alias is now significant. Eg, converting a parent account to
    just an account name prefix: --alias '/:acct:/=:acct'

-   timedot: allow a quantity of seconds, minutes, days, weeks, months
    or years to be logged as Ns, Nm, Nd, Nw, Nmo, Ny

-   csv: switch the order of generated postings, so account1 is first.
    This simplifies things and facilitates future improvements.

-   csv: show the "creating/using rules file" message only with --debug

-   csv: fix multiple includes in one rules file

-   csv: add "newest-first" rule for more robust same-day ordering

-   deps: allow ansi-terminal 0.7

-   deps: add missing parsec lower bound, possibly related to #596, fpco/stackage#2835

-   deps: drop oldtime flag, require time 1.5+

-   deps: remove ghc < 7.6 support, remove obsolete CPP conditionals

-   deps: fix test suite with ghc 8.2

# 1.3.1 (2017/8/25)

-   Fix a bug with -H showing nothing for empty periods (#583, Nicholas Niro)
    This patch fixes a bug that happened when using the -H option on
    a period without any transaction. Previously, the behavior was no
    output at all even though it should have shown the previous ending balances
    of past transactions. (This is similar to previously using -H with -E,
    but with the extra advantage of not showing empty accounts)

-   allow megaparsec 6 (#594)

-   allow megaparsec-6.1 (Hans-Peter Deifel)

-   fix test suite with Cabal 2 (#596)

# 1.3 (2017/6/30)

journal: The "uncleared" transaction/posting status, and associated UI flags
and keys, have been renamed to "unmarked" to remove ambiguity and
confusion. This means that we have dropped the `--uncleared` flag,
and our `-U` flag now matches only unmarked things and not pending
ones. See the issue and linked mail list discussion for more
background. (#564)

csv: assigning to the "balance" field name creates balance
assertions (#537, Dmitry Astapov).

csv: Doubled minus signs are handled more robustly (fixes #524, Nicolas Wavrant, Simon Michael)

Multiple "status:" query terms are now OR'd together. (#564)

deps: allow megaparsec 5.3.

# 1.2 (2017/3/31)

## journal format

A pipe character can optionally be used to delimit payee names in
transaction descriptions, for more accurate querying and pivoting by
payee. Eg, for a description like `payee name | additional notes`,
the two parts will be accessible as pseudo-fields/tags named `payee`
and `note`.

Some journal parse errors now show the range of lines involved, not just the first.

## ledger format

The experimental `ledger:` reader based on the WIP ledger4 project has
been disabled, reducing build dependencies.

## Misc

Fix a bug when tying the knot between postings and their parent transaction, reducing memory usage by about 10% (#483) (Mykola Orliuk)

Fix a few spaceleaks (#413) (Moritz Kiefer)

Add Ledger.Parse.Text to package.yaml, fixing a potential build failure.

Allow megaparsec 5.2 (#503)

Rename optserror -> usageError, consolidate with other error functions

# 1.1 (2016/12/31)

## journal format

-   balance assignments are now supported (#438, #129, #157, #288)

    This feature also brings a slight performance drop (\~5%);
    optimisations welcome.

-   also recognise `*.hledger` files as hledger journal format

## ledger format

-   use ledger-parse from the ledger4 project as an alternate reader for C++ Ledger journals

    The idea is that some day we might get better compatibility with Ledger files this way.
    Right now this reader is not very useful and will be used only if you explicitly select it with a `ledger:` prefix.
    It parses transaction dates, descriptions, accounts and amounts, and ignores everything else.
    Amount parsing is delegated to hledger's journal parser, and malformed amounts might be silently ignored.

    This adds at least some of the following as new dependencies for hledger-lib:
    parsers, parsec, attoparsec, trifecta.

## misc

-   update base lower bound to enforce GHC 7.10+

    hledger-lib had a valid install plan with GHC 7.8, but currently requires GHC 7.10 to compile.
    Now we require base 4.8+ everywhere to ensure the right GHC version at the start.

-   Hledger.Read api cleanups

-   rename dbgIO to dbg0IO, consistent with dbg0, and document a bug in dbg*IO

-   make readJournalFiles \[f\] equivalent to readJournalFile f (#437)

-   more general parser types enabling reuse outside of IO (#439)

# 1.0.1 (2016/10/27)

-   allow megaparsec 5.0 or 5.1

# 1.0 (2016/10/26)

## timedot format

-   new "timedot" format for retroactive/approximate time logging.

    Timedot is a plain text format for logging dated, categorised
    quantities (eg time), supported by hledger. It is convenient
    for approximate and retroactive time logging, eg when the
    real-time clock-in/out required with a timeclock file is too
    precise or too interruptive. It can be formatted like a bar
    chart, making clear at a glance where time was spent.

## timeclock format

-   renamed "timelog" format to "timeclock", matching the emacs package

-   sessions can no longer span file boundaries (unclocked-out

    sessions will be auto-closed at the end of the file).

-   transaction ids now count up rather than down (#394)

-   timeclock files no longer support default year directives

-   removed old code for appending timeclock transactions to journal transactions.

    A holdover from the days when both were allowed in one file.

## csv format

-   fix empty field assignment parsing, rule parse errors after megaparsec port (#407) (Hans-Peter Deifel)

## journal format

-   journal files can now include timeclock or timedot files (#320)

    (but not yet CSV files).

-   fixed an issue with ordering of same-date transactions included from other files

-   the "commodity" directive and "format" subdirective are now supported, allowing

    full control of commodity style (#295) The commodity directive's
    format subdirective can now be used to override the inferred
    style for a commodity, eg to increase or decrease the
    precision. This is at least a good workaround for #295.

-   Ledger-style "apply account"/"end apply account" directives are now used to set a default parent account.

-   the Ledger-style "account" directive is now accepted (and ignored).

-   bracketed posting dates are more robust (#304)

    Bracketed posting dates were fragile; they worked only if you
    wrote full 10-character dates. Also some semantics were a bit
    unclear. Now they should be robust, and have been documented
    more clearly. This is a legacy undocumented Ledger syntax, but
    it improves compatibility and might be preferable to the more
    verbose "date:" tags if you write posting dates often (as I do).
    Internally, bracketed posting dates are no longer considered to
    be tags. Journal comment, tag, and posting date parsers have
    been reworked, all with doctests.

-   balance assertion failure messages are clearer

-   with --debug=2, more detail about balance assertions is shown.

## misc

-   file parsers have been ported from Parsec to Megaparsec \o/ (#289, #366) (Alexey Shmalko, Moritz Kiefer)

-   most hledger types have been converted from String to Text, reducing memory usage by 30%+ on large files

-   file parsers have been simplified for easier troubleshooting (#275).

    The journal/timeclock/timedot parsers, instead of constructing
    opaque journal update functions which are later applied to build
    the journal, now construct the journal directly by modifying the
    parser state. This is easier to understand and debug. It also
    rules out the possibility of journal updates being a space
    leak. (They weren't, in fact this change increased memory usage
    slightly, but that has been addressed in other ways). The
    ParsedJournal type alias has been added to distinguish
    "being-parsed" journals and "finalised" journals.

-   file format detection is more robust.

    The Journal, Timelog and Timedot readers' detectors now check
    each line in the sample data, not just the first one. I think the
    sample data is only about 30 chars right now, but even so this
    fixed a format detection issue I was seeing.
    Also, we now always try parsing stdin as journal format (not just sometimes).

-   all file formats now produce transaction ids, not just journal (#394)

-   git clone of the hledger repo on windows now works (#345)

-   added missing benchmark file (#342)

-   our stack.yaml files are more compatible across stack versions (#300)

-   use newer file-embed to fix ghci working directory dependence (<https://github.com/snoyberg/file-embed/issues/18>)

-   report more accurate dates in account transaction report when postings have their own dates

    (affects hledger-ui and hledger-web registers).
    The newly-named "transaction register date" is the date to be
    displayed for that transaction in a transaction register, for
    some current account and filter query. It is either the
    transaction date from the journal ("transaction general date"),
    or if postings to the current account and matched by the
    register's filter query have their own dates, the earliest of
    those posting dates.

-   simplify account transactions report's running total.

    The account transactions report used for hledger-ui and -web
    registers now gives either the "period total" or "historical
    total", depending strictly on the --historical flag. It doesn't
    try to indicate whether the historical total is the accurate
    historical balance (which depends on the user's report query).

-   reloading a file now preserves the effect of options, query arguments etc.

-   reloading a journal should now reload all included files as well.

-   the Hledger.Read.* modules have been reorganised for better reuse.

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

0.27 (2015/10/30)

-   The main hledger types now derive NFData, which makes it easier to
    time things with criterion.

-   Utils has been split up more.

-   Utils.Regex: regular expression compilation has been memoized, and
    memoizing versions of regexReplace\[CI\] have been added, since
    compiling regular expressions every time seems to be quite
    expensive (#244).

-   Utils.String: strWidth is now aware of multi-line strings (#242).

-   Read: parsers now use a consistent p suffix.

-   New dependencies: deepseq, uglymemo.

-   All the hledger packages' cabal files are now generated from
    simpler, less redundant yaml files by hpack, in principle. In
    practice, manual fixups are still needed until hpack gets better,
    but it's still a win.

0.26 (2015/7/12)

-   allow year parser to handle arbitrarily large years
-   Journal's Show instance reported one too many accounts
-   some cleanup of debug trace helpers
-   tighten up some date and account name parsers (don't accept leading spaces; hadddocks)
-   drop regexpr dependency

0.25.1 (2015/4/29)

-   support/require base-compat >0.8 (#245)

0.25 (2015/4/7)

-   GHC 7.10 compatibility (#239)

0.24.1 (2015/3/15)

-   fix JournalReader "ctx" compilation warning
-   add some type signatures in Utils to help make ghci-web

0.24 (2014/12/25)

-   fix combineJournalUpdates folding order
-   fix a regexReplaceCI bug
-   fix a splitAtElement bug with adjacent separators
-   mostly replace slow regexpr with regex-tdfa (fixes #189)
-   use the modern Text.Parsec API
-   allow transformers 0.4*
-   regexReplace now supports backreferences
-   Transactions now remember their parse location in the journal file
-   export Regexp types, disambiguate CsvReader's similarly-named type
-   export failIfInvalidMonth/Day (fixes #216)
-   track the commodity of zero amounts when possible
    (useful eg for hledger-web's multi-commodity charts)
-   show posting dates in debug output
-   more debug helpers

0.23.3 (2014/9/12)

-   allow transformers 0.4*

0.23.2 (2014/5/8)

-   postingsReport: also fix date sorting of displayed postings (#184)

0.23.1 (2014/5/7)

-   postingsReport: with disordered journal entries, postings before the
    report start date could get wrongly included. (#184)

0.23 (2014/5/1)

-   orDatesFrom -> spanDefaultsFrom

0.22.2 (2014/4/16)

-   display years before 1000 with four digits, not three
-   avoid pretty-show to build with GHC < 7.4
-   allow text 1.1, drop data-pprint to build with GHC 7.8.x

0.22.1 (2014/1/6) and older: see http://hledger.org/release-notes or doc/CHANGES.md.
