# PLAN: balance: and change: queries (formerly sum:)

Status: planned and implemented 2026-11-08 as `sum:` (PR #2847, unreleased);
revised 2026-11-08 to replace `sum:` with `change:` and `balance:`, not yet implemented (see the next section).
The sections after it describe the original `sum:` design and implementation, which the revision builds on.

## Revision: `change:` and `balance:` replace `sum:` (2026-11-08)

### Why

`sum:` tested "whatever amount the report displays": an account's change, or with `-H` its end
balance, and with the displayed sign. So its meaning depended on report options, and a query
could not say which of the two it meant. This surfaced in the assert directive design
(doc/PLAN-assert-directive.md), which needed a `balance`/`change` keyword to fix `sum:`'s meaning
and so could not be a plain query. Two terms with fixed meanings remove the problem everywhere.
`sum:` has not been released, so it is simply replaced.

### Design decisions (agreed)

- Two query terms, `change:` and `balance:`, with `amt:`'s value grammar
  (`N`, `<N`, `<=N`, `>N`, `>=N`; a leading `+`/`-` or N=0 means a signed comparison, otherwise
  magnitude; an optional commodity symbol selects one commodity's part, eg `balance:'<0 EUR'`;
  otherwise a multi-commodity amount matches if any single-commodity part does). `sum:` is removed.
- Like `sum:`, they test summed amounts, after `amt:`/`cur:` have selected postings; `amt:` keeps
  testing individual postings. Both terms may appear in one query; multiple terms are ANDed;
  `not:` negates; the `sum:` restriction stays (top-level AND or negated only).
- Query terms must not be command-specific, so each term's meaning is fixed by the kind of item
  being matched, not by the command or its display options:

  | item matched                                  | `change:` tests                        | `balance:` tests                                   |
  |-----------------------------------------------|----------------------------------------|----------------------------------------------------|
  | an account row (bal, bs, is, cf, budget...)   | its change over the report period      | its balance at the end of the report period        |
  | a posting or period row (reg)                 | its amount                             | the account(s)' balance after it (running total)   |
  | a transaction row (aregister)                 | its change to the account              | the account's balance after it                     |
  | an entry (print, descriptions, notes, codes)  | its net change: the sum of its postings, as `sum:` tested | the same as `change:` (an entry has no balance; fixed now, so it never changes later) |
  | items with no amount (accounts, tags, ...)    | matches everything (ignored)           | matches everything (ignored)                       |

- **Balance means the actual balance**: the sum of all postings from the start of the journal
  (within the query's other terms) to the end of the item's period, whether or not `-H` was used.
  Consequences:
  - In balance reports, a `balance:` term makes the report gather the postings before the report
    start, as `-H` does (`requiresHistorical`-style condition on the query). Without `-H` the
    displayed amounts are still changes, so the numbers shown are not the ones tested; the manual
    says "add -H to see the balances tested". (Rejected: letting `balance:` switch the report to
    historical mode. `depth:` is a precedent for a query term changing the report, but changing the
    accumulation mode is too much for a query term.)
  - An account matched by a `balance:` term is shown even if its change in the period is zero
    (else `bal assets balance:<0` would miss a dormant overdrawn account). `-E` semantics are
    otherwise unchanged: `change:0` rows are hidden without `-E`, as `sum:0` rows were.
  - In registers, the balance tested is the historical running total, even without `-H` (the
    displayed running total then starts from zero at the report start and differs; "-H shows it").
    It is the running total, not the running average, with `--average`.
- **Real signed amounts**, as `amt:` tests them: not the displayed sign. `--invert` and the sign
  normalisation of `bs`/`is`/`cf` subreports do not affect the test, so `is revenues change:<-1000`
  finds large revenues, exactly as `amt:<-1000` would. (`sum:` tested the displayed sign; that was
  command-dependent.) Amounts are tested after `-B`/`-V` conversion, since those convert the
  amounts being summed, but before any sign adjustment.
- **Rows are hidden after running totals are computed**, in registers: hidden rows still count in
  the running total and running balance, so the balances shown and tested are the account's true
  balances. (`sum:` hid rows before the totals, like `amt:`, which is a posting filter.) One rule
  for both terms. The manual notes the difference from `amt:`.
- Multi-period balance reports: `change:` tests the row's total change (the Total column);
  `balance:` tests the end balance (the last column with `-H`). Columns are still not filtered.
  Budget reports: as for `sum:`, rows are hidden when the actual amount (inclusive) fails; the
  actual change or actual end balance respectively.
- Account names beginning with `change:` or `balance:` now need `acct:`. Accepted, as for other
  prefixes.
- `sum:` is removed without a migration hint, since it was never in a release.

### Implementation changes

1. Query.hs: replace `Sum` with `Change` and `Balance` constructors (same fields); `queryprefixes`
   gets `change`, `balance`; parsing shared with `amt:`. `querySplitSum` becomes a split of both
   kinds of term (`querySplitRowTerms` or similar). `matchesSumAmount` becomes
   `matchesRowAmounts :: Query -> MixedAmount -> MixedAmount -> Bool` taking the row's change and
   balance; the entry matcher passes the entry sum for both. Posting/transaction matchers ignore
   the terms as they ignored `Sum`. Rename `_rsSumQuery` accordingly.
2. MultiBalanceReport.hs: `getPostings` fetches pre-start postings when the query has `balance:`
   terms (extend the `requiresHistorical` condition). The row filter gets each account's change
   (sum of its own period changes) and end balance (pre-start balance plus changes; check that
   `pdpre` holds the pre-start amounts in PerPeriod mode when they were fetched). Rows matched by
   `balance:` are kept when all-zero (`markAccountBoring`'s `allZeros`). Drop the displayed-sign
   logic. Budget report likewise.
3. PostingsReport.hs: compute items and running totals over all selected rows, plus the historical
   running balance when needed, then filter by change and balance; `--related` tests the displayed
   related posting's amount. AccountTransactionsReport.hs: same, filtering after the running
   balance; it already computes the historical balance.
4. EntriesReport: rename only. hledger-web `getViewData`: split both kinds of term; query help line.
5. Manual: replace `### sum: query` with one section `### balance: and change: queries` placed
   after `amt:` (alphabetical: balance, change, code); update the queries overview, `amt:`'s
   pointer, the transaction balancing note (`print not:change:0`), and the assert directive section
   (done in the other plan). hledger.pot entry for the web help line.
6. Tests: hledger/test/query-sum.test becomes query-balance-change.test with the terms renamed,
   plus: `balance:` in `bal` without `-H` (history fetched, dormant account shown), `bs` with
   `change:` using real signs, `reg balance:<0` with and without `-H` (same rows), hidden rows
   counting in running totals, `areg balance:`, both terms in one query, `print balance:` equal to
   `change:`. Unit tests renamed/extended.
7. History: the branch is unreleased, so rewrite it rather than add a "replace sum:" commit:
   `;doc: plan: ...` (this file, which was never committed), the feature commit renamed
   (`feat:query: change: and balance: match report rows by their summed amounts`, user-visible
   first), then the `amt:` commodity-symbol commit. Force-push after confirmation; update PR #2847's
   title and description (draft shown first) and post a comment explaining the revision.


## Original `sum:` implementation: changes made during it

- Split, not posting matching: `parseQuery` keeps `Sum` terms in the Query and validates
  (in `parseQueryList`, via `querySplitSum`) that they are only top-level AND conjuncts or negated.
  `reportOptsToSpec` moves them from `_rsQuery` to a new `ReportSpec` field, `_rsSumQuery`,
  so accounts/commodities/payees etc never see them and ignore sum: for free.
  hledger-web's `getViewData` does the same split for its `q` parameter.
  The posting and transaction matchers also ignore `Sum` (and negated `Sum`), for other callers
  such as auto posting rules. (A naive `matchesPosting (Not q)` would have made `not:sum:0`
  exclude every posting.)
- `print`'s entry sum can't be computed in Query.hs (Balancing.hs imports it), so it's applied
  in `entriesReportUnsorted`, with `transactionBalancingSum` from Balancing.hs. This also covers
  descriptions, notes and codes. It's tested before valuation and `--invert`.
- Balance reports: the plan said "hide rows; tree mode tests inclusive balances; totals from
  surviving rows". But totals come from the root account's inclusive balances, and parents'
  displayed balances would still include hidden children. So instead `applySumQuery` treats
  sum: like an account filter: each account's *own* amount (its list-mode row total) is tested,
  non-matching accounts' amounts are removed, inclusive balances recomputed, and empty
  non-matching accounts pruned. Parents, totals and `--percent` are then consistent
  automatically. To test inclusive balances, limit the depth (`bal -1 sum:>100`).
  Amounts are tested as displayed: after `--invert`, and negated for compound reports' normally
  negative subreports (`normalbalance_ == Just NormallyNegative`, which is set exactly where
  their display is negated). `--invert` now happens before boring-marking (sign-independent).
- Budget reports: own-amount testing would drop goals set on parent accounts with no postings
  of their own, so budget reports instead hide rows whose displayed actual (inclusive) amount
  doesn't match, leaving other rows and totals unchanged.
- Register running totals and the aregister running balance skip non-matching rows;
  the -H starting balance is unaffected.
- Zero rows are still hidden without `-E` (`bal sum:0` shows only multi-commodity rows).
- No hledger/test/errors example: query argument errors have no file position or excerpt.
- Follow-up commit (PR #2847): amt: also accepts a commodity symbol (shared parser,
  parseAmountQueryArg; Amt gained a Maybe CommoditySymbol). sum: now matches like amt:
  (matchesMixedAmount: any single-commodity part passing), replacing "multi-commodity always
  matches" and "absent commodity counts as zero". The amt: docs' "multi-commodity postings
  always match" was wrong and is corrected.

## Original `sum:` design

### Goal

Let users filter report rows by their aggregated amount, which `amt:` can't do
(it matches individual posting amounts, before aggregation). Eg:

```
hledger bal expenses sum:'>100'        # accounts whose change exceeded 100
hledger bal expenses -H sum:'>1000'    # accounts whose end balance exceeds 1000
hledger reg expenses -M sum:'>100'     # months whose expense total exceeded 100
hledger reg gifts -M sum:'>100'        # months with gift expense over 100
hledger bal sum:'>100 EUR'             # compare just the EUR part of each row
hledger print sum:'>100'               # entries with large unbalanced (virtual) postings
hledger print not:sum:0                # entries with a tolerated rounding imbalance
```

### Design decisions (agreed, as of the original design; see the revision above for what changed)

- One new query term, `sum:`, with the same value grammar as `amt:`
  (`N`, `<N`, `<=N`, `>N`, `>=N`; a leading `+`/`-` on N or N=0 means signed
  comparison, otherwise magnitude comparison), plus an optional commodity symbol
  in the value: `sum:'>100 EUR'`, `sum:'>$100'`.
  - With a symbol: compare that commodity's quantity in the row amount (absent
    commodity = 0).
  - Without: single-commodity rows are compared, zero/empty rows compare as 0,
    multi-commodity rows always match (same rule as `amt:`).
- Name: `sum:`, because every row is the sum of its postings (a change, an end
  balance, a period summary, an entry). Rejected `total:` (collides with the
  Total column/row, subreport and grand totals), `bal:`/`change:` (wrong for
  some modes/commands), `having:` (SQL-only meaning), `net:`, `row:`.
- It is a post-aggregation filter on *rows*, so it is a different stage from
  `amt:` (SQL WHERE vs HAVING). Rejected alternatives: a `having:QUERY` wrapper
  (more syntax, only `amt:`/`cur:` would ever be used inside it); a Ledger-style
  `--display EXPR` expression language (second grammar).
- The row amount tested is whatever the report shows as the row's summary:
  - balance reports: the account's balance; in multi-period reports the row
    Total column (sum of changes, or for `-H`/`--cumulative` the last period's
    balance, as `rowtotal` in `makePeriodicReportRow` already computes). In tree
    mode the inclusive balance (what is displayed), in list mode exclusive.
    Budget reports: the actual amount.
  - register: the posting amount, or with a report interval the period summary
    amount. (`reg sum:` without an interval is thus like `amt:`, but with the
    commodity-symbol form and multi-commodity rule.)
  - aregister: the transaction's change to the account.
  - transaction-oriented commands (print etc): the entry total = sum of all
    postings converted to cost, as transaction balancing does, but *including*
    unbalanced virtual postings. So a loaded entry's total is its unbalanced
    virtual postings plus any tolerated rounding imbalance. Independent of
    `-B`/`-V` (the entry total has a fixed meaning). Document that large real
    imbalances can't occur in a loaded journal, so `print sum:'>100'` only
    finds virtual ones; `print amt:'>100'` is the way to find big transactions.
  - commands with no rows/amounts (accounts, close, etc): matches everything;
    document as ignored. No command errors on `sum:`.
- Columns of a multi-period balance report are not filtered. Possible later
  extension; don't let one term silently pick an axis.
- Tree mode: a parent that fails the test is still shown if it has surviving
  descendants (same mechanism as boring parents today). A parent that passes
  while all its children fail is shown alone.
- Totals row and `--percent` are computed from the surviving rows, consistent
  with how `acct:` queries behave. (Alternative considered: percent before
  filtering; rejected as it would make `sum:>10` mean ">10%".)
- Boolean composition: `not:sum:...` and top-level AND are supported.
  A `sum:` term nested under `or` (or a `not` of an `or`) in `expr:` is an
  error for row-based reports, since it can't be separated from the posting
  query. (For transaction-oriented commands it would work naturally via
  `matchesTransaction`; simplest is to make it an error everywhere for
  consistency, or allow it there - implementer's call, document either way.)
- Multiple `sum:` terms are ANDed, which is the existing rule for all terms
  other than account, description and status (`combineQueriesByType`), so
  `sum:'>100' sum:'<500'` is a range, as with `amt:`. Nothing special needed.

### Implementation steps (original)

#### 1. Query type and parsing (hledger-lib/Hledger/Query.hs)

- Add constructor `Sum OrdPlus Quantity (Maybe CommoditySymbol)` next to
  `Amt` (line ~125). Add `"sum"` to `queryprefixes` (~263).
- Parser: reuse `parseAmountQueryTerm`'s operator/sign handling, then accept an
  optional commodity symbol before or after the number (`$100`, `100 EUR`,
  quoted symbols). Keep the existing restrictions (period decimal mark, no digit
  group marks). Return the same style of error message on failure.
- `queryIsSum`, exported. `matchesPosting (Sum ..) _ = True`
  (posting-oriented reports handle it at row level, like `Depth`).
  `matchesTransaction (Sum ord q mc) t` = compare the entry total (see above).
  Reuse the cost conversion used by `transactionCheckBalanced` in
  Hledger/Data/Balancing.hs; sum with `sumPostings` over all `tpostings`.
- Shared helper `matchesSumAmount :: OrdPlus -> Quantity -> Maybe CommoditySymbol -> MixedAmount -> Bool`
  implementing the commodity rules; used by the reports below and by
  `matchesTransaction`. Consider also making `matchesMixedAmount` use it.
- `simplifyQuery`/`filterQuery`: extracting total terms from a query should use
  `filterQueryOrNotQuery queryIsSum` so `not:sum:0` survives. Add a check
  that detects `Sum` under `Or` and raises the error above (a small
  `queryHasSumUnderOr`-style helper; find where `expr:` queries are validated
  for `inacct:`/`depth:`-like misuse, if anywhere, else do it in
  `reportOptsToSpec`/`updateReportSpec` in ReportOptions.hs ~line 1128 where
  the query is parsed).
- Unit tests in `tests_Query` for parsing (all operator/sign forms, symbol
  before/after, bad input) and for `matchesSumAmount`.

#### 2. Balance reports (hledger-lib/Hledger/Reports/MultiBalanceReport.hs)

- `getPostings` (~216-221): strip `Sum` terms from the posting query like
  `Depth` (`filterQuery (not . queryIsSum)`), else harmless but keep it clean.
- `markAccountBoring` (~330): add `failsSum` to `isBoring` alongside
  `tooDeep`/`allZeros`. It tests the row's total amount: compute from
  `pdperiods (adata acct)` with the same rule as `rowtotal` in
  `makePeriodicReportRow` (~499): sum for `PerPeriod`, else last period. Factor
  that into a shared helper so the two can't drift. Use the same `balance`
  selector (inclusive in tree mode) and `maybeStripPrices` as `allZeros`.
  The `isBoringParent` logic then gives the tree-mode behaviour for free.
- Check `-E` interplay: `-E sum:0` should show zero rows; `sum:'>0' -E`
  should not resurrect zero rows (failsSum must apply regardless of
  `keepEmptyAccount`).
- Totals row and `reportPercent` already run after this, so they reflect
  surviving rows.
- Budget report (BudgetReport.hs): confirm it goes through the same row
  selection, or apply the test to actual amounts there.
- Single-period `balance`, `bs`/`is`/`cf`, `accounts --locations`-style
  reports, hledger-ui accounts screen and hledger-web sidebar/balance all use
  this report; verify each gets the behaviour with no extra code.

#### 3. Register (hledger-lib/Hledger/Reports/PostingsReport.hs)

- Strip `Sum` from the posting query (~189). After summary postings are built
  (with interval) or plain postings are selected, drop items whose amount fails
  `matchesSumAmount`, *before* running totals are computed, so the running
  total is of displayed rows (as `amt:` behaves).
- `--related`: test the related posting's amount, as displayed.

#### 4. aregister (hledger-lib/Hledger/Reports/AccountTransactionsReport.hs)

- Strip `Sum` from `aregisterq` as `Amt`/`Cur`/`Depth` are (~120). Filter
  report items by the "change" column before the running balance is computed.
  hledger-ui's register screen uses this report; check the transaction count /
  balance shown there still make sense.

#### 5. Transaction-oriented commands

- `print`, `close`, `descriptions`, `notes`, `payees`, `codes`, `tags`, `rewrite`,
  `check` etc filter via `matchesTransaction` or `matchesPosting`; step 1 gives
  print the entry-total behaviour, the rest ignore it. Verify `print` goes via
  `matchesTransaction` (journalApplyFilter / filterJournalTransactions) and not
  per-posting matching.
- `--infer-imbalance`: generated imbalance postings make totals exactly zero;
  `print --infer-imbalance sum:0` then matches all (except unbalanced
  virtuals). Mention in docs.

#### 6. Docs

- hledger/hledger.m4.md Queries > Query types: add `### sum: query` between
  `status:` (5470) and `tag:` (5484) - check alphabetical order of neighbours
  (status, sum, tag, type). Cover: grammar, signed vs magnitude, commodity
  symbol, what "the sum" means per command (bal/-M/-H, reg/-M, areg, print entry
  total incl. unbalanced virtuals, others ignore), tree-mode parents, totals and
  percent from surviving rows, columns not filtered, `not:` ok, `or` error.
- `### amt: query` (5382): replace "Keep in mind that amt: matches posting
  amounts, not account balances" with a pointer to `sum:`.
- Queries overview list (~5332): add a `sum:'>100'` example line.
- Transaction balancing > Showing imbalances (~5879): mention `print not:sum:0`
  as another way to list entries with tolerated imbalances.
- hledger-web/templates/default-layout.hamlet ~296: add a `sum:` line to the
  query help; new `HMsg` string goes to hledger-lib/locale/hledger.pot only
  (not the .po catalogs).
- Any query-type list in hledger-ui help? (grep found none; double check.)
- doc/CODE.md if it lists query constructors. Don't touch CHANGES.md.

#### 7. Tests

- New hledger/test/query-sum.test (sequential numbering):
  - bal list mode: `>N`, `<N`, signed `>+N`/`<-N`, `sum:0`, `not:sum:0`.
  - bal tree mode: failing parent kept for passing child; passing parent with
    failing children; depth clipping.
  - bal -M: filters on row total; -H uses last balance; columns untouched;
    totals row recomputed; `--percent` from survivors.
  - commodity symbol: `sum:'>100 EUR'`, `'>$100'`, multi-commodity row
    without symbol matches; with symbol compares; absent commodity = 0.
  - `-E` interplay.
  - reg -M period rows; reg without interval; running total of survivors;
    `--related`.
  - areg.
  - print: unbalanced virtual postings (`(acct)  $500`), tolerated imbalance
    with a rounded unit cost (`not:sum:0` finds it; `--infer-imbalance sum:0`
    matches it), balanced entries match `sum:0`, `-V` doesn't change results.
  - `expr:` with `not`; `expr:` with `or` -> error.
  - multiple `sum:` terms ANDed.
  - bad value syntax -> error, same wording style as `amt:`.
- hledger/test/errors/: add an example for the new error kind (`sum:` under
  `or`), and README entry, if the parse error isn't already covered by an
  existing query-parse example.
- Unit tests as in step 1.

#### 8. Pre-commit

- Build with `stack build hledger --ghc-options=-Werror`, then `stack build`
  for hledger-ui/web once since they share the query parser.
- `just functest --hide`.
- Commit as `feat:query: sum: matches report rows by the sum of their postings` (user-visible
  first; details after). AI usage line per convention.
