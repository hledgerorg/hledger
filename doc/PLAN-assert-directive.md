# PLAN: assert directive

Status: designed and implemented 2026-11-08 on branch `assert-directive` (PR #2848);
revised and reimplemented 2026-11-09 to use the `change:`/`balance:` queries instead of `balance`/`change` keywords
(see "Revision 2" next, and its implementation notes), then given a fixed spacing rule (see "Revision 3").
Exceptions (`except`) are designed but not implemented (see "Possible later work: exceptions").
The later sections describe the first design and its implementation.
Replaces the bin/hledger-check-fancyassertions.hs add-on script.
Builds on the `change:`/`balance:` queries (PR #2847, formerly `sum:`; see doc/PLAN-balance-change-queries.md),
so implement it on a branch stacked on `sum-query`.

## Revision 3 (2026-11-09): one space before the period expression, two before the query

```
assert (none|some)[ PERIODEXPR][  QUERY]
```

Revision 2 found the period expression by looking for a double space anywhere in the line, so a rule
with no period expression could be written with one space or two, and adding or removing a period
expression could change how the rest of the line was read. Now the spacing alone decides:
one space after the quantifier begins a period expression, and two or more spaces begin the query.

- Adding or removing a period expression never changes the spacing of the query.
- A missing double space is always a syntax error ("could not parse this as a period expression",
  or "remainder of period expression cannot be parsed ... double space?"), so the heuristic which
  tried a query's first words as a period expression is gone, and accounts named like period words
  need no `acct:`.
- A double space inside a quoted query term (`desc:'a  b'`) no longer turns on period parsing.
- The query is optional, also after a period expression: `assert some monthly` means every month has
  postings. The suggested `reg`/`bal` command then has no query arguments.
- It matches periodic transactions, where the description follows the period expression after two
  or more spaces. All documented examples already used this form.

## Possible later work: exceptions with `except` (designed 2026-11-09, not implemented)

```
assert (none|some)[ PERIODEXPR[ except PERIOD...]][  QUERY]
```

Eg `assert none daily except 2026-03-04..2026-03-07 2026-05  type:A balance:<0`.
Rules will often need exceptions, and `not:date:` in the query is wrong for balance rules:
it removes postings, making a hole in every later balance (as in `bal -H`).
`except` removes checks, never data: postings in a skipped period still count in later balances.

- Syntax: one or more single-word periods (dates, partial dates, `..` ranges), separated by single spaces.
  It needs a period expression with an interval. It is parsed by the assert directive only,
  not in period expressions generally (`-p` etc.); perhaps later in periodic transaction rules.
- A check is skipped when an excepted date is among the dates it examines:
  - a rule with `balance:` and no `change:` examines the period's last day (the balance is tested
    at the period's end, as `bal -H` shows it);
  - any other rule (with `change:`, both terms, or neither) examines the whole period.

  So `monthly except 2026-02` always skips February; `monthly except 2026-02-15` skips February
  except in a balance-only rule, where it has no effect; `monthly except 2026-02-28` always skips February.
- For a `none` rule with neither term, `not:date:` in the query is more exact, and harmless.
- Rejected: skipping any period which overlaps an exception, whatever the query (simpler, but it would
  skip a month-end balance check for an excepted mid-month date); and making `balance:` ignore date terms.

## Revision 2 (2026-11-09): plain queries, no `balance`/`change` keywords

### Why

The first design needed a `balance` or `change` keyword because `sum:` meant "the displayed
amount", so the directive had to say which amount. With `sum:` replaced by `change:` and
`balance:` (doc/PLAN-balance-change-queries.md), each with a fixed meaning, the query itself says
what is tested, and the directive becomes a quantifier, an optional period expression, and an
ordinary hledger query, run exactly as the balance report would run it.

### Syntax

```
assert (none|some) [PERIODEXPR]  QUERY
```

```journal
assert none daily  type:A balance:<0                        ; no asset account is ever negative (in any commodity)
assert none monthly  liabilities:card balance:<-$5000       ; the card never owes more than $5000 at a month end
assert none  expenses:petty amt:>+500                       ; no single petty cash expense is larger than 500 (in any currency)
assert none  assets:oldbank date:2025-                      ; nothing posted to a closed account
assert none monthly  expenses:dining depth:2 change:>+$500  ; no month has more than $500 of dining expenses
assert some monthly  income:salary                          ; there's a salary transaction every month
assert some  desc:'opening balances'                        ; the journal has an opening balances entry
assert some  assets:checking date:thismonth                 ; this month's bank import has been done
assert some  assets:savings balance:>=+10000                ; savings hold at least $10000 (now, ie at the end of the journal)
```

- `none`/`some` as before. `sum:` is no longer accepted anywhere (removed from hledger).
- The period expression, if any, is the text between the quantifier and the first double space
  (as in periodic transactions). No double space means no period expression: the whole rest of the
  line is the query. `assert none  QUERY` and `assert none QUERY` are the same.
  Safety check: with no double space, if the query's leading word(s) parse as a period expression
  (`daily`, `monthly from 2025`, `2025`, ...), it is an error: "perhaps you need to terminate the
  period expression with a double space? (or write acct:2025 for an account query)". Otherwise
  `assert none daily type:A` would silently match accounts named "daily".
- **The interval rule is dropped.** `balance:` now means the balance at the end of the period
  checked, so a rule with no period expression tests the final balances, exactly what
  `hledger bal QUERY` shows; nothing is implied. Requiring an interval would also forbid useful
  present-state rules like the savings example above. The remaining trap (writing
  `assert none  type:A balance:<0` when `daily` was meant) is handled in the manual, next to the
  first example: "without a period expression, only the final balances are checked".
- Relative dates relative to today, `date:` terms setting the report period, the double-space
  hint, the query parse errors (including the AND-only restriction on `change:`/`balance:`): as before.

### Semantics

Each checkpoint is the balance report `hledger bal -E -b START -e END QUERY` (or `hledger bal -E QUERY`
with no period expression), run on the whole journal (file tree); the rule must hold at every
checkpoint. The periods come from the period expression as before (intersected with `date:`
terms, open ends filled from the journal span, adjusted to interval boundaries unless a start date
was given); a period expression with no interval is a single period.

- Rows: as `bal -E` shows them: the accounts (clipped to `depth:`) with a posting matching the
  other terms within the period, plus, when the query has `balance:` terms, accounts with such
  postings before the period (dormant accounts have a row with zero change). Each row has a
  change (its postings in the period) and a balance (all its postings up to the period end).
- A row matches if `matchesRowAmounts` passes for its change and balance (true when the query has
  neither term). `none` fails if any row matches, `some` fails if none does.
- So `assert some monthly  income:salary` means a salary posting in every month;
  `assert none daily  type:A balance:<0` means no asset account is negative at the end of any day;
  `assert none  type:A balance:<0` means none is negative at the end of the journal.
- Everything else is unchanged: file-tree scope, the `assertions` check and `-I`/`-s`, running at
  the end of finalisation, costs and valuation ignored, the finest grain daily, check arguments.

### Error messages

Same layout. The evidence is chosen from the query's terms: no `change:`/`balance:` terms:
the matching postings and a `reg` command, as now; only `change:` terms: "These changes matched:"
with each account's change; only `balance:` terms: "These balances matched:" with each end
balance; both: "These accounts matched:" with two amount columns, change then balance.
The suggested command is `hledger bal -E -b START -e END QUERY` (`-H` is no longer needed: a
`balance:` term makes `bal` include the earlier postings), or `hledger reg ...` for the postings
case, or without period flags for a whole-journal check.

### Implementation

1. Types: `adPeriod :: Maybe (Interval, DateSpan)`; drop `AssertKind`.
2. Parser: after the quantifier, take the text up to the first double space (or newline/`;`);
   if there was a double space, reparse it with `periodexprp` as before; else apply the safety
   check above and treat all of it as the query. Drop the interval check; the `sum:` check goes
   away with `sum:`. Unit tests updated.
3. Checker: per period, rows need both amounts: keep the running balance map over date-sorted
   postings (as now) and build the period's change map; the row set is the keys of the change map,
   plus the keys of the balance map when the query has `balance:` terms. `matchesRowAmounts`
   replaces `matchesSumAmount`. The early-exit paths stay: with no amount terms a period's rows
   exist iff it has a posting (no `balance:` terms, so dormant accounts don't count), so the
   "any posting" shortcut is unchanged. Evidence per the error messages section.
4. Manual: rewrite the "`assert` directive" section for the new grammar (lead example
   `assert none daily  type:A balance:<0`; the final-balances note; no "a sum: comparison must say
   when" paragraph); directives summary row text unchanged; SPEC-journal.md grammar; Check.md
   examples; errors example; functional tests rewritten (every current test has a direct
   counterpart; add: no-period `balance:` final balances, `some ... balance:>=` present-state rule,
   dormant account row with `balance:`, both terms in one rule, the leading-period-word error).
5. History: rebase onto the rewritten `sum-query`; the grammar change touches every commit, so
   squash to three: the plan (with this revision), one feature commit with the final grammar
   (absorbing the perf and failure-message commits), and the check-arguments commit. Force-push
   after confirmation (the branch was already rebased locally onto the plan commit 5d5d70c4f).
   Update PR #2848's title/description and post a revision comment, drafts shown first.


### Implementation notes (2026-11-09)

- Parser: a period expression is present iff the rest of the line, before any `;` comment and trailing
  spaces, contains a double space; it is reparsed with `periodexprp` as before. A period expression
  which fails to parse at all gets "could not parse this as a period expression ... if this is the
  start of the query, use single spaces within the query" (which also covers a query written with
  double spaces); one that parses partially gets the old "remainder ... double space" hint. With no
  double space, the first one to three words are tried as a period expression and an error asks for
  the double space (or `acct:`). The interval/`sum:` checks are gone; the query is still parsed and
  checked with `querySplitRowTerms`.
- Checker: each checkpoint has the period's changes by account and the running balances (postings
  before the first period count in the balances only); a row matches via `matchesRowAmounts`. Rows
  are the active accounts, plus with `balance:` terms the inactive ones, handled incrementally as the
  set of accounts whose balance matches the `balance:` terms, updated once per period for the accounts
  posted to, so a `daily` check stays proportional to the postings, not periods × accounts.
  Each running balance also counts its single-commodity amounts matching each `balance:` term
  ("matching-amount counts", switchable with `assertCountingEnabled`), so a posting re-tests only its own
  commodities, and the cost does not grow with the number of commodities a balance holds. Without row terms a period's rows
  exist iff it has postings, as before. Evidence rows carry (account, change, balance).
- Error wording: the noun follows the query's terms: "changes" (`change:` only), "balances"
  (`balance:` only), "accounts" with two amount columns and a "(change, balance)" hint (both),
  "postings" (neither). Checkpoints are "on DATE" (one-day periods), "for the period P", or
  "(checked over the whole journal)" / "(checked over the period P)" for the whole-journal check
  with `date:` terms. The suggested command is `hledger bal -E -b START -e END QUERY` (or `reg`),
  without `-H`, since a `balance:` term makes `bal` include the earlier postings.
- Tests: hledger/test/journal/directive-assert.test (38 tests, including: `balance:` with no period
  = final balances; a present-state `some ... balance:>=` rule; a dormant account as a row; both terms
  in one rule; the period-word hint), hledger/test/errors/assert.*, 12 parser unit tests.
- History: see the first design's notes for the earlier commits; the branch was rebuilt as three
  commits (plan, feature, check arguments) from the final tree.

## First design (2026-11-08)

### Goals

Consolidate the useful functionality from hledger-check-fancyassertions,
without the ambiguous grammar (see #1738, #2719), in the check command.

Let users declare standing rules about their books, in the journal, checked like
balance assertions:

```journal
assert none balance daily  type:A sum:<0                        ; no asset account is ever negative (in any commodity)
assert none balance monthly  liabilities:card sum:<-$5000       ; the card never owes more than $5000 at a month end
assert none  expenses:petty amt:>+500                           ; no single petty cash expense is larger than 500 (in any currency)
assert none  assets:oldbank date:2025-                          ; nothing posted to a closed account
assert none change monthly  expenses:dining depth:2 sum:>+$500  ; no month has more than 500 of dining expenses in $
assert some change monthly  income:salary                       ; there's a salary transaction every month
assert some  desc:'opening balances'                            ; the journal has an opening balances entry
assert some  assets:checking date:thismonth                     ; this month's bank import has been done
```

The script did this with its own expression language on the command line
(`hledger-check-fancyassertions -M 'budget:books  >= £0'`). Moving it into
hledger proper gives: rules kept with the data under version control; hledger's
query language instead of a bespoke one (regex account matching, `status:`,
`cur:`, `tag:`, `depth:`, `date:`, ...); hledger's error format with file
positions and excerpts; and no separate script to install.

### Design decisions (agreed)

#### Syntax

```
assert (none|some) [(balance|change) PERIODEXPR]  QUERY
```

- `assert` reuses the Ledger directive name, which hledger currently parses and
  ignores (`assertdirectivep` in JournalReader.hs). Ledger-style `assert`
  lines with value expressions will now be parse errors; acceptable on the 2.x
  track. The Ledger `check` directive stays ignored.
- `none` or `some` is **mandatory**: the query must match no rows, or at least
  one row. (The first word is always one of these, which keeps parsing simple.)
- `balance` or `change` followed by a period expression comes **as a unit**: no
  keyword without a period expression, no period expression without a keyword.
  There are no optional synonyms; each thing has one spelling.
  The period expression uses the normal grammar (`periodexprp`): an interval
  (`daily`, `weekly`, `monthly`, `quarterly`, `yearly`, `every 2 weeks`, ...),
  a span (`from 2024`, `in 2025`, ...), or both. A period expression without an
  interval is a single period, so `change in 2025` tests the total change over
  2025.
- **When the query has a `sum:` term, the period part is required**, and
  `balance` must have an interval (`change` may have just a span). A balance is
  a value at a time, so the directive must say which times; nothing is implied.
  A `balance` with only a span would mean one check at the end while reading as
  "since ...", so it is an error too. Without `sum:` the period part is
  optional: a posting either exists in the journal or it doesn't.
- **Two or more spaces** separate the period expression from the query, as in
  periodic transactions (`~ PERIODEXPR  DESCRIPTION`). Without a keyword, a
  single space is fine: `assert none  QUERY` and `assert none QUERY` are the same.
- `QUERY` is an ordinary hledger query, parsed with `parseQuery`, including
  `sum:` terms (subject to the usual `sum:` restriction: top-level AND or
  negated only, enforced by `querySplitSum`). Account name terms are the usual
  infix-matching regexes. Eg `assets:` matches `assets`'s subaccounts, but
  not `assets` itself; `type:A` matches all asset accounts by type.
- Relative dates in the period expression and in `date:` terms are relative to
  today (not the `Y` directive year rule used by periodic transactions).

#### Semantics

An assert directive runs the equivalent of `bal -E QUERY` at one or more
checkpoints and requires the result to be empty (`none`) or non-empty (`some`).
Precisely:

- **Rows** are the accounts (clipped to the query's `depth:`, as `bal` does)
  with at least one posting matching the non-`sum:` query terms within the
  scope. Zero-balance rows exist, as with `-E`. Each row's amount is the sum of
  those postings' amounts, ignoring costs and valuation, like balance
  assertions and like `bal` without `-B`/`-V`. So `sum:` tests each account's
  own (exclusive) balance. To test inclusive balances, use `depth:N` (or `depth:REGEX=N`)
  to fold subaccounts into their parent's balance.
- **Comparing accounts**: `depth:0` folds every matched account into a single
  row (named `...`, as `clipOrEllipsifyAccountName` does), which lets us compare
  two accounts of opposite normal sign by testing their combined sum. Eg
  "savings always cover the debts" (the old script's `liabilities  <= assets:savings`)
  can be expressed with `assert none balance daily  acct:'^(assets:savings|liabilities)' depth:0 sum:<0`.
  This covers assets against liabilities, income against expenses, a budget
  against its spending. Two same-signed accounts (checking versus savings) can't
  be compared this way; that is accepted (see Rejected alternatives).
- A row **matches** if the query has no `sum:` terms, or its amount passes them
  (`matchesSumAmount`, the same test `bal` applies). `none` fails if any row
  matches; `some` fails if no row matches.
- **Scope and checkpoints**:
  - No period expression (only allowed without `sum:`): one check over the
    whole journal. `none` means the journal contains no matching posting,
    `some` means it contains at least one. Timeless, so no checkpoint is needed.
  - With a period expression, the assertion must hold in **every** period:
  - `balance PERIODEXPR`: the period expression is split into periods
    (`splitSpan`), intersected with the journal's span. For each period, the
    scope is all postings dated on or before the period's end, regardless of
    the span's start (these are historical balances, as in `bal -H`; the span
    only chooses when to check).
    So `balance monthly` tests end-of-month balances and `balance monthly from
    2024` tests them only from 2024 on. Periods containing no postings are
    still checkpoints.
  - `change PERIODEXPR`: for each period, the scope is the postings within
    that period only. A period with no matching postings has no rows, so
    `none` passes and `some` fails there.
- The finest granularity is `daily`. There is no "after every transaction"
  mode (the script's default): same-day transactions have no meaningful order
  beyond file order, and a daily check catches everything a day-ordered journal
  can express. The commonest assertion is therefore spelled
  `assert none balance daily  type:A sum:<0`: two extra words, but no
  implicit rule to learn.
- **Scope: file tree**, like balance assertions. A directive sees every entry in
  its file tree (the main file and all its includes, before and after the
  directive), but not entries of other file trees read with separate `-f`
  options. This falls out of running the check in journal finalisation, which
  happens per file tree. `jasserts` is still concatenated in the Journal merge
  (like `jperiodictxns`) so that included files' directives are collected.
- Checked by default as part of the `assertions` check: disabled by
  `-I`/`--ignore-assertions`, forced back on by `--strict` or
  `hledger check assertions`, exactly like inline balance assertions. Runs at
  the end of journal finalisation, after lot processing, so lot errors and
  inline assertion failures are reported first. Skipped entirely when the
  journal has no assert directives.
- hledger-ui and hledger-web need no changes; failures surface as load errors.

#### Error messages

Standard verbose format: the directive's position and excerpt, what failed and
where, and the evidence. One layout for `none`, one for `some`:

```
hledger: Error: /path/to/file.journal:12:
   | assert none balance monthly  type:A sum:<0

This assert directive failed for the period 2026-03 (checked at 2026-03-31).
These balances matched:
  assets:bank:checking   $-120.00
  assets:cash              $-3.50
  ...and 7 more. To see them all: hledger bal -E -H -e 2026-04-01 'type:A' 'sum:<0'
```

List at most 10 matching rows; beyond that, elide with a count as above. Always
end with the equivalent report command (`bal -E` plus `-H -e END` for
`balance`, `-p PERIOD` for `change`, nothing extra for the whole journal, then
the query terms shell-quoted), so the failure can be inspected.

```
hledger: Error: /path/to/file.journal:13:
   | assert some change monthly  income:salary

This assert directive failed for the period 2026-04: no postings matched.
```

Without a period expression, say "checked over the whole journal" instead of
naming a period. Use the excerpt helpers in hledger-lib/Hledger/Data/Errors.hs.
Report the first failing checkpoint of the first failing directive (in file
order), consistent with other checks reporting only the first failure.

Parse-time errors (at the directive, with excerpt):
- first word not `none`/`some`: say which words are allowed;
- `balance`/`change` not followed by a parseable period expression terminated
  by a double space: reuse the periodic transaction wording ("perhaps you need
  to terminate the period expression with a double space?");
- query parse errors, including the `sum:` combination error from
  `querySplitSum`, shown at the directive's position;
- a `sum:` term with no period part, or with `balance` lacking an interval:
  "a sum: comparison needs to say when to check: add `balance daily`,
  `balance monthly`, `change monthly`, ...".

#### Rejected alternatives (for the record)

- A bespoke expression language like the script's (`ACCT  >= AMT`, `*ACCT`,
  `&&`, `||`, `==>`, `<==>`), or one mirroring balance assertion operators with
  a `*` suffix (`>=*`). A near-duplicate of balance assertions with its own
  quirks; the query language already exists and is more powerful. What is lost:
  comparing two same-signed accounts (opposite-signed pairs work via `depth:0`,
  see Semantics), and logical conditions spanning several accounts. Implication
  examples all reduce to "never both", which is `none` with two terms when the
  terms apply to one row, and otherwise rare. The script's account-vs-account
  comparison was also ill-defined for mixed-commodity balances.
- A positive "every selected row passes its sum: terms" form (`assert type:A
  sum:>=0`). It is a special case of `none` with the predicate negated, and it
  would be a second kind of assertion to explain. `none ... sum:<0` is also
  stricter for multi-commodity rows (fails on any negative part, where
  `sum:>=0` passes if any part is non-negative).
- Optional keywords (`balance` as an optional default, an implicit quantifier).
  One spelling per concept is easier to learn than variability.
- An `all`/`only` quantifier ("every posting in scope matches"). Needs a
  scope/predicate split a single query can't express; spell it `none ... not:X`.
- "After every transaction" as the default or an available granularity (see
  Semantics).
- Implicit timing for `sum:` queries with no period part. Two drafts of this
  plan tried it. "One check, on the final balances" is uniform, but a guessed
  `assert none  type:A sum:<0` passes silently over a past dip. "Daily
  checkpoints, `none` = never, `some` = ever" fixes that but creates the mirror
  trap: `assert some  assets:savings sum:>=+10000`, meant as "I have 10k",
  passes forever once the balance has ever reached 10k. Both also add a hidden
  rule to learn. Requiring the period part when `sum:` is present costs two
  words and makes every assertion mean exactly what it says.
- The script's `-C`/`-P`/`-U`/`-R` flags (use `status:`, `real:` in the query),
  `--sunday` (use `every 7 days from SOMESUNDAY`), `-b`/`-e` (use the period
  expression's span).
- A `--assert EXPR` command-line flag for ad hoc checks. Initially not planned
  (a wrapper file including the journal works); later added as a `check` argument instead
  (see Implementation notes).
- Posting-level `sum:` semantics different from `bal`'s (eg signed by default).
  `sum:` must mean the same thing everywhere. Document that `sum:>=100`
  compares magnitude and `sum:>=+100` is signed; zero is always signed.

### Implementation steps

#### 1. Types (hledger-lib/Hledger/Data/Types.hs)

```haskell
data AssertQuantifier = AssertNone | AssertSome
data AssertKind = AssertBalance | AssertChange
data AssertDirective = AssertDirective {
   adQuantifier :: AssertQuantifier
  ,adKind       :: AssertKind        -- AssertBalance when there is no period expression
  ,adInterval   :: Interval          -- NoInterval when there is no period expression
  ,adSpan       :: DateSpan          -- nulldatespan when there is no period expression
  ,adQueryText  :: Text              -- the query as written; re-parsed at check time
  ,adSourceText :: Text              -- the whole directive line, for excerpts
  ,adSourcePos  :: SourcePos
  }
```

Store the query as text, not a `Query`, because `Hledger.Query` imports
`Hledger.Data.Types`. This follows the `TransactionModifier`/`tmquerytxt`
precedent: validate by parsing at read time, parse again at check time.
Add `jasserts :: [AssertDirective]` to `Journal`, in parse order; initialise in
`nulljournal`, concatenate in the Journal merge (Hledger/Data/Journal.hs, next to
`jperiodictxns`), and show it in the debug `Show Journal` output.

#### 2. Parsing (hledger-lib/Hledger/Read/JournalReader.hs)

Replace the ignoring `assertdirectivep` with a real parser, dispatched from
`directivep` and recorded like `periodictransactionp` is:

1. `string "assert"`, spaces, then the quantifier word.
2. Optionally `balance` or `change`, spaces, then a period expression up to the
   first double space, parsed with `periodexprp today`, using the
   excerpt/reparse technique and double-space hint from `periodictransactionp`.
   A period expression without an interval is one period.
3. The rest of the line (up to `;` comment or newline), stripped, is the query
   text. Parse it once with `parseQuery today` to validate (and to run
   `querySplitSum`'s checks); on failure, raise a parse error at the directive
   with the query parser's message. If it has a `sum:` term, require the period
   part, with an interval for `balance`. Discard the parsed Query; store the text.
4. Record the directive (`addAssertDirective`), and the source position/line
   for error excerpts.

Add `assert` to the directive table in the manual (Directives section) and
remove it from the "Ledger directives ignored" comment/list.

#### 3. Checking (new module hledger-lib/Hledger/Data/JournalChecks/Assert.hs)

`journalCheckAsserts :: Day -> Journal -> Either String ()`

Direct accumulation over postings (preferred over driving the balance report
code from journal finalisation, which would add a Read -> Reports dependency
and still need per-cell posting counts). For each directive, in file order:

1. `parseQuery today` the query text; `querySplitSum` it into the `sum:` query
   and the rest; `queryDepth` of the rest gives the `DepthSpec` for clipping.
2. Candidate postings: `journalPostings j` filtered with `matchesPostingExtra
   (journalAccountType j)` and the non-sum query, amounts cost-stripped
   (`postingStripCosts`), account names clipped with
   `clipOrEllipsifyAccountName`.
3. Checkpoints: with no period expression (no `sum:` term, so only existence
   matters), a single scope of all candidate postings. Otherwise `splitSpan` of
   the period expression intersected with the journal's span (`journalDateSpan`
   including future transactions), giving one scope per period: postings dated
   `<= end` for `balance`, within the period for `change`; the assertion must
   hold in every period. For `balance`, accumulate incrementally over
   date-sorted postings rather than re-summing per period.
4. Rows per scope: `Map AccountName MixedAmount` built from the scope's
   postings (every account seen gets a row, even if its sum is zero). A row
   matches if `queryIsNull sumq || matchesSumAmount sumq amt`.
5. `none`: fail at the first checkpoint with a matching row, listing up to 10
   matching rows (aligned, amounts via `showMixedAmount` with the journal's
   styles) and eliding the rest with a count. `some`: fail at the first
   checkpoint with no matching row. Both end with the equivalent `bal` command.

Hook it into `journalFinalise` (hledger-lib/Hledger/Read/Common.hs), after the
last finalisation stage and just before the deferred inline assertion error is
raised (or after it: lot errors first, then inline assertion failures, then
assert directives). Run only when `checkassertions` is true and `jasserts` is
non-empty. It sees the finalised journal, so lot subaccounts exist by then;
confirm in tests that `assets:` matches what `bal assets:` shows.

Things to verify against `bal -E QUERY` in tests, since fidelity to the report
is the documented contract: depth clipping, zero rows, lot subaccounts,
commodity aliases (`maConvertAliases` is applied to running balances in
Balancing.hs; check whether `bal` sees converted amounts and match it), `cur:`
and the commodity-symbol form of `sum:`, `date:` and `amt:` terms, `not:sum:`.

#### 4. The check command (hledger/Hledger/Cli/Commands/Check.hs, Check.md)

No code change: the `Assertions` check is already assumed to have run during
reading, and `hledger check assertions` already forces it on. Update Check.md:

- `assertions` bullet: "all balance assertions and assert directives in the
  journal are passing", linking to both manual sections.
- Remove the `hledger-check-fancyassertions` line from "Custom checks".

#### 5. Manual (hledger/hledger.m4.md)

- New section "Assert directives" after "Balance assertions" (keep anchors).
  Explain with reports, not with rows: an assert directive names a query and
  says whether it must match nothing or something; the query is run like
  `hledger bal -E QUERY`, once over the whole journal, or at each period end
  with `balance`, or on each period's postings with `change`, and with a
  period it must hold in every period; a `sum:` comparison must say when it is
  checked. Lead with examples; the first should be
  `none balance daily  type:A sum:<0`, "no asset account is ever negative".
  Then the grammar, and a short details note covering what is simply `bal`'s
  behaviour: zero rows, exclusive balances, depth clipping.
  Notes: finest grain is daily; costs and valuation ignored; `sum:`
  magnitude vs signed (`sum:>=+100`); multi-commodity rows and `cur:`; `depth:`
  is absolute; `-I`, `--strict`, `hledger check assertions`; scope is the file
  tree (several `-f` files are checked separately).
- A short "Balance assertions versus assert directives" paragraph with the
  mapping table: `= AMT` ~ `sum:` per matching account; `=*` ~ `depth:N`;
  `==` ~ `cur:` or a commodity symbol in `sum:`; comparing two accounts ~
  `depth:0` on both (opposite-signed only). Keep the vocabulary apart:
  "balance assertions" (facts at one point, from the real world) and "assert
  directives" (rules at all times, from the user's policy).
- Directives summary table: add `assert` under a new group heading **Checks
  data:** with scope "file tree":
  "Declares a [standing rule](#assert-directives), a query that must match no
  rows or some rows, checked like balance assertions." Add the `[`assert`]`
  link. In "Combining file trees", extend "balance assertions" to "balance
  assertions and assert directives". Ledger compatibility notes: `assert` is no
  longer ignored.
- Add-ons table (around line 7988): remove `check-fancyassertions`.

#### 6. Tests

- hledger/test/journal/directive-assert.test (new): parse forms (`none`/`some`,
  with and without keyword and period, single vs double space, comments);
  every example above against small journals, passing and failing (match a key
  phrase of the message); `none` without period vs `balance daily` (a dip that
  recovers); `change monthly` with an empty month for `none` and `some`; zero
  balance rows; `depth:`, `depth:REGEX=N` and the `depth:0` account comparison
  idiom; `cur:` and `sum:'<0 EUR'`;
  `not:sum:`; `date:` and `amt:` terms; directives across two files; `-I`
  disables, `-s` and `check assertions` re-enable; lot subaccounts; parse
  errors (bad quantifier, missing double space, bad query, `sum:` inside `or`);
  the period-required rule: `sum:` with no period part, `sum:` with `balance
  from DATE` (span only) are errors, `change in YEAR` (span only) works;
  `balance daily ... sum:<0` fails on a past dip that has since recovered.
- hledger/test/errors/assert.j + assert.test: one `none` failure example (the
  `some` layout is the same shape minus the row list; add a second example only
  if the layouts diverge). Add it to the errors README list.
- Unit tests for the directive parser in JournalReader.hs's test group.

#### 7. Removing the script

- Delete bin/hledger-check-fancyassertions.hs (and the untracked .hi/.o).
- Other scripts' header comment `-- See hledger-check-fancyassertions.hs.`
  points at its usage notes: move those notes to one remaining script (eg
  hledger-check-tagfiles.hs) and update the pointers.
- Remove its line from: hledger/Hledger/Cli/Commands.hs add-on list (~line 339),
  hledger/shell-completion/parse-commands.sh, bin/README.md (section and the
  comment near line 645), bin/scripts.test, and any `_scripts*.test`.
- Leave CHANGES.md, relnotes.md and CREDITS.md alone (history).

#### 8. Pre-commit checklist

The usual: warning-free build with `--ghc-options=-Werror`, GHC 9.6
compatibility, no partial functions, docs and error examples updated, this plan
updated with any deviations (as doc/PLAN-balance-change-queries.md records its own).

### Out of scope (possible later work)

- Valuation (`-V`) or cost (`-B`) in assertion amounts.
- An inclusive-balance convenience shorter than `^assets:checking depth:2`.

- A warn-only variant (Ledger's `check` directive).
- Filtering multi-period report columns by `sum:`, which would let the
  report-based implementation replace the direct accumulation.
- Letting the directive take a literal report command line (`assert empty  bal
  -E -H -D type:A sum:<0`). Reuses flag knowledge, but `sum:` filters
  multi-period rows by total, not per column, so the semantics would not match
  the report, and parsing option syntax inside a directive is a lot of
  machinery for a cosmetic gain.

### Implementation notes and deviations

Implemented 2026-11-08 as planned, with these differences and details:

- Types: the period part is one field, `adPeriod :: Maybe (AssertKind, Interval, DateSpan)`,
  instead of separate `adKind`/`adInterval`/`adSpan` fields, so invalid combinations can't be represented.
  `Show AssertDirective` is derived standalone in Journal.hs (where `Show DateSpan` is available).
  `jasserts` is not added to the JSON output or to `--anon`.
- Parsing: today's date comes from `InputOpts` (`_ioDay`), as journal finalisation uses.
  The directive is recorded as an exported item, so `print --export` reproduces it.
  An empty query is allowed (it matches every posting).
  `balance`/`change` is recognised only as a whole word followed by spaces;
  a query whose first term is one of those words can be written with `acct:`.
- Checking: in Hledger.Data.JournalChecks.Assert, as planned. Postings are prepared as `bal` prepares them:
  matched by the non-sum:, non-depth: query, amounts limited by `amt:`/`cur:` terms (`filterPostingAmount`),
  costs stripped, account names clipped by `depth:`. Periods are calculated as `bal` does
  (open ends filled from the journal span, adjusted to interval boundaries unless a start date was given).
  The set of matching rows is updated incrementally, from the rows changed at each checkpoint.
  The journal's date-sorted postings and its date span are calculated once, shared by all directives.
  Checking stops at the first failing checkpoint; only then are its rows calculated in full, for the error message.
  Without `sum:` terms every row matches, so a scope is checked just for having any posting, stopping at the first
  (eg `assert some` with no period costs almost nothing).
  Measured on examples/100ktxns-1kaccts.journal (1.2s to check without directives): a directive costs about
  0.02s when its query selects few postings, up to about 0.15s when it selects all 200k postings
  (the cost of summing them, as `bal` would); `balance daily` over that journal's 100k days adds about 0.08s;
  peak live memory is unchanged.
  2026-11-10: with one account holding 200 commodities, `balance daily` over 100k transactions took 1.7s
  (each posting re-tested the whole balance, twice); matching-amount counts brought it to 0.12s.
  As a share of read time, measured on synthetic journals, a rule adds about 5-15%, up to about 30%
  for a broad `balance daily` rule; most of a narrow rule's cost is regex-matching every posting's account name.
  `date:` terms are handled as in `bal`: removed from the posting query, and used as the report period
  (intersected with the period expression's span), so with `balance` they limit the checkpoints
  but earlier postings still count in the historical balances (decided 2026-11-08, for fidelity with `bal -H`;
  this gives two ways to write a span, which was accepted). `date2:` terms are ignored, as in `bal` without `--date2`.
  Without a period expression, a failure with `date:` terms names their period instead of "the whole journal".
  Commodity aliases need no special handling: amounts are converted early in finalisation, so `bal` and the check see the same amounts.
  With `--forecast`, forecast transactions are included, as they are in `bal --forecast`.
- Error messages: the layout matches other check errors (position, excerpt, blank line, explanation).
  Wording: `balance` checkpoints say "failed on DATE, at the end of the period PERIOD." (just "failed on DATE." for a one-day period);
  `change` says "failed for the period PERIOD"; no period says "failed (checked over the whole journal)".
  The last line is "To see the report: hledger bal ..." (or "To see them all: ..." when rows were elided).
  For `change` the command uses `-b`/`-e` rather than `-p`, so the exclusive end date is unambiguous.
  Without `sum:` terms (decided after a user report, 2026-11-08), the error lists the matching postings
  (date, abbreviated description, account, amount; up to 10) and suggests `hledger reg QUERY` (with `-e END` or `-b`/`-e`),
  since summed rows hid which postings broke a rule like `assert none  charity amt:>90`;
  `some` failures then say "no postings matched".
  With `sum:` terms, the rows are called "balances" (for `balance`) or "changes" (for `change`) rather than "rows":
  "These balances matched:", "no changes matched", etc.
  Query terms are single-quoted only when they contain shell-sensitive characters.
- Manual: the new section is "`assert` directive" (anchor `#assert-directive`), placed with the other directive sections
  (between `alias` and `comment`), with a pointer from the end of the Balance assertions intro, rather than right after Balance assertions.
  "Balance assertions and assert directives" is its subsection. The sum: query section also mentions assert directives.
- Check.md: also fixed `hledger check lots` to `hledger check assertions` in the assertions bullet.
- Tests: hledger/test/journal/directive-assert.test (29 tests, with directive-assert/ files for the file tree tests),
  hledger/test/errors/assert.{j,test} (flycheck column left blank in the errors README, not verified),
  and parser unit tests. print/export.test and ledger-compat/hledger-other.test used Ledger-style `assert` lines
  as examples of ignored directives; they now use `check`, or omit it.
- Script removal: the usage notes moved to hledger-check-tagfiles.hs. hledger/embeddedfiles/help.cast (an old recording)
  and the generated Check.txt still mention the script.
- Assert rules as check arguments (added 2026-11-08, after the first implementation commit):
  `hledger check 'assert none balance daily  type:A sum:<0'`, each rule one quoted argument,
  written exactly like the directive and parsed by the same parser (`parseAssertDirective`, source name "check argument").
  Chosen over a general `--assert` option: it fits check's model (arguments are the checks to run),
  keeps check free of command-specific flags, and avoids a config-file `--assert` blocking every command.
  Live checking in hledger-ui/web is what was given up. Unlike directives, these rules check all files combined,
  and run even with `-I` (an explicit request). They run after any named checks.
  A plain `assert` argument still selects the `assertions` check (by name prefix);
  an unquoted rule gets a hint (`none`/`some` as a check name).
  Failure messages still say "This assert directive failed".
