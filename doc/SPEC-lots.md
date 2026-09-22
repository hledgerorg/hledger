# Lot tracking

Here is the current specification for lots functionality, most of which has been implemented in the lots branch.

See also 
- hledger manual: Cost basis
- hledger manual: Lot reporting
- <https://github.com/hledgerorg/hledger/blob/main/examples/lots/lots.journal>
- <https://joyful.com/hledger+lot+tracking>
- <https://github.com/hledgerorg/hledger/issues/1015>

## Background

Before lot tracking was added, hledger 1 users 
tracked lots manually using one subaccount per lot, 
used the `close` command and `hledger-move` script to help record complex lot movements,
and used the transaction balancing mechanism to calculate capital gain/loss.
Or, they computed gains with `balance --gain`, or the `roi` command.
These mechanisms still work but the tooling described here aims to largely subsume them.

## Lots

A lot is an amount of some commodity, acquired and held for investment purposes,
to be disposed of later, hopefully at a better price.

A lot's acquisition price and date are preserved, to 

1. help comply with tax rules, and 
2. calculate the capital gain or loss, both unrealised (before disposal), and realised (at disposal).

## Lots mode

By default, lot inference, tracking, and error checking are performed when loading a
journal, as part of journal finalising (see SPEC-finalising.md). Any journal with
lot-related content (lotful commodities, cost basis annotations, or
disposals) is validated up front. Journals with no lot activity pay near-zero cost
via an internal fast path.

Lot checking can be disabled with `--ignore-lots` (or its shortcut alias `-I`,
which also sets `--ignore-assertions`). This is a troubleshooting aid, for
loading incomplete or problematic journals (eg piping between hledger
commands, or fixing a complex journal incrementally); it silences lot errors
without introducing new ones. It splits the lot pipeline in two:

- The pre-balancing "enrichment" stages still run, so lot entries balance
  the same as with lots enabled: `journalInferBasisFromAccountNames` (in
  lenient mode: an invalid or conflicting lot subaccount name leaves the
  posting unchanged, an ordinary subaccount, instead of erroring),
  `journalInferPostingsTransactedCost`, `journalTagGainPostings` (in
  lenient mode: the amountless-gain-posting error is skipped), and
  `journalStripBalancerCopiedBases`. The transaction balancer also stays
  lot-aware (`lotful_commodities_`/`account_lots_tags_` are populated as
  usual, so lot fee auto-splitting still works), with one relaxation: the
  lot quantity mismatch veto on balancing cost inference is skipped
  (`lenient_lots_` in BalancingOpts), so a transfer whose lot quantities
  don't add up (eg an unrecorded fee) loads with an inferred conversion
  cost instead of erroring. Thus `--ignore-lots` loads a superset of the
  journals that load with lots enabled.

- The post-balancing checking and calculation stages are skipped entirely:
  `journalClassifyLotPostings`, `journalCheckLotsTagValues`,
  `journalCheckLotsMethodCoherence`, `journalCalculateLots`,
  `journalAddOrCheckGainPostings`. Capital gains are not inferred or
  checked, lot subaccounts are not added, and lot-related errors (malformed
  `lots:` tags, missing lot cost, ambiguous selectors, dispose-before-acquire,
  insufficient lots, etc.) are not raised.

Rationale (2026-09): before this split, `--ignore-lots` skipped the
pre-balancing stages and blanked the balancer's lot-awareness too, which
made it *add* errors and misreadings rather than only removing them:
disposals with a written gain amount failed to balance (unbalanced by the
gain), transfers with a priced fee failed to balance (the fee's at-cost
value only cancels in split form), an acquire with an elided counterpart
and a `{cost}` balanced wrongly (the counterpart was mirrored as the lot
commodity instead of money), and amountless gain postings were inferred as
multi-commodity garbage. Only the pre-balancing stages can affect
balancedness, so running them always (leniently) and skipping only the
post-balancing stages gives the desired "silence errors, add none"
behaviour. Known accepted exceptions - entries old `--ignore-lots` loaded
that now error (identically to lots-on mode, being genuinely
inconsistent): a lot subaccount name whose basis contradicts an explicit
counterpart amount at a different price, and a gain entry that balanced
only without its inferred counterpart posting.

`--strict`/`-s` and `hledger check lots` both override `--ignore-lots`, restoring
full lot processing for that invocation.

The `journalCheckAcquireBasis` stage is gated separately: it runs only when the
user explicitly invokes `hledger check basis`, regardless of `--ignore-lots`,
`--strict`, or `hledger check lots`. See [Acquire basis check](#acquire-basis-check-opt-in) below.

The `--lots` general flag is a display-time toggle. It controls whether reports show

- per-lot subaccounts in the account tree, and
- the full detailed form of lot-related transactions (split postings, inferred cost
  basis annotations, synthetic balance-assertion placeholders, etc.)

When `--lots` is absent, reports show a collapsed view: lot subaccounts are hidden,
synthetic placeholder postings are dropped, and inferred gain amounts appear on the
base (parent) gain account rather than on per-lot detail accounts. Inferred gains are
visible in reports like `incomestatement` even without `--lots` — unless
`--ignore-lots` is in effect, in which case gains are not calculated from lots
(only user-written gain postings, and their generated balancing counterparts, appear).

In the journal, lot operations can be recorded

1. implicitly, with minimal notation and maximum inference;
2. partly explicitly, with any missing parts inferred;
3. or fully explicitly, requiring no inference.

A typical workflow is to use 1 primarily, or when processing/converting old journals;
and use `print` to convert to 3 when troubleshooting or reporting.

## Transacted cost and cost basis

- Transacted cost is the conversion rate used within a particular multi-commodity transaction.
  It is recorded with a @ or @@ annotation after the amount(s).

- Cost basis is the nominal acquisition cost of a lot,
  along with its acquisition date and perhaps a label.
  It is preserved (along with the lot's balance), throughout the lifetime of the lot, from acquisition through transfers to final disposal.
  It is recorded with hledger lot syntax (consolidated {} notation);
  we can also read ledger lot syntax (separate {}, [], () annotations).

A posting amount can have transacted cost, cost basis, both, or neither.
When displaying a posting with both, we show cost basis before transacted cost (like beancount).
The hledger manual has more detail.

## Lot names

A lot's cost basis also serves as the lot name. 

In hledger, a full lot name looks like {YYYY-MM-DD, "LABEL", COST} or {YYYY-MM-DD, COST}.
That is, two or three parts inside curly braces: 
- a date in strict ISO format
- an optional label in double quotes
- a single-commodity hledger amount
with a comma and space between them.
When parsing, spaces inside the braces and around the commas are optional and ignored.
This is similar to Beancount's lot syntax, except it requires DLC order (date, label, cost) and it supports hledger's flexible amount syntax.

Partial lot names are also used; these have some or all of the parts missing.
{} is a lot name/cost basis annotation with all parts missing.

Full lot names can be used, internally or explicitly in the journal, as subaccount names, to identify specific lots within a parent account.
Eg `assets:stocks:aaaa:{2026-02-10, "label", $50}`.
This means the label and the cost's commodity symbol may not contain double-quotes, colons, or semicolons.

When a lot subaccount is written explicitly in this way, it is equivalent to writing cost basis annotations after the posting amount.
(See also "Inferring cost basis from lot subaccount names" below.)
If it is written in both places, they should agree.

Lot subaccounts are ignored when checking account names, eg with `check accounts` (only the parent account needs to be declared).

## Parsing lot names

Full lot names can appear as the final part of account names, like `assets:stocks:{2026-01-01, $10}`.

When parsing, naive splitting on commas would fail because commas can appear inside:
- cost amounts as decimal separators (e.g. `€1,50`) or digit group separators (`$1,000,000.00`)
- quoted commodity symbols (e.g. `"an, odd, commodity" 1,5`)
- quoted labels (e.g. `"a, b, b"`)

Instead, parts are identified by **peeling known-format prefixes** in DLC order:

1. **Peel date**: if the first 10 characters match `YYYY-MM-DD` and are followed
   by end-of-string, comma, or whitespace, they are consumed as the date.
   The trailing comma separator (if any) and surrounding whitespace are stripped.

2. **Peel label**: if the remainder starts with `"`, scan to the next `"`.
   The quoted string is a label only if followed by a comma or end-of-string.
   If instead it is followed (after optional whitespace) by a digit, sign, or
   decimal mark, then the quoted string is a commodity symbol belonging to the
   cost amount, and it is left in place.

3. **Cost**: whatever remains is passed to the amount parser as a single string.

This approach handles all combinations of commas in dates, labels, commodity
symbols, and decimal amounts without ambiguity.

Examples:
- `{2026-01-15, "my, label", €1,50}` → date `2026-01-15`, label `my, label`, cost `€1,50`
- `{2026-01-15, "an, odd, commodity" 1,5}` → date `2026-01-15`, cost `"an, odd, commodity" 1,5` (no label; the quoted string is a commodity symbol)
- `{2026-01-15, "a, b", "an, odd, commodity" 1,5}` → date `2026-01-15`, label `a, b`, cost `"an, odd, commodity" 1,5`
- `{$100}` → cost `$100`
- `{}` → empty cost basis

## Lot ids

A lot's id is just the date and label parts.
Lot ids must be unique and ordered (per commodity), so if there are multiple lots with the same date,
labels are used to 1. disambiguate and 2. order them.
This is normally done by beginning the label with a time of day (HH:MM, or a more precise time as needed)
or an intra-day sequence number (NNNN, with enough leading zeros so that a day's lot ids sort nicely in numeric order — we'll assume four digits in total).
Labels are generated only when needed to satisfy uniqueness:
if there are multiple same-date, same-commodity acquisitions (across all accounts) with no labels,
hledger adds NNNN labels based on parse/processing order;
if such acquisitions do have user-provided labels, hledger checks that the resulting lot ids are unique
(across all accounts, to be safe) and reports an error otherwise.

Whether lot tracking is per-account or across-all-accounts depends on jurisdiction and time period.
This needs to be, and is, configurable, currently by the lots: tag's value.
Eg in the US, tax rules require that before tax year 2025, lots are tracked across all accounts,
but from tax year 2025, lots are tracked separately within each account.

## Lot selectors

A full or partial lot name/cost basis, when used in a posting with a negative amount,
selects an existing lot, rather than creating a new one.
So in this case we call it a "lot selector".

The terms "hledger lot syntax", "cost basis", "lot name", "lot selector" can sometimes be a bit interchangeable;
they all involve the same notation, which has different meanings depending on context.

A selector's cost is compared with a lot's stored cost by commodity and quantity,
accepting either an exact match or the stored cost's display-rounded value
(`lotCostsMatch` in Lots.hs). The latter is needed because an inferred cost can
have more decimal digits than are displayed (eg $10/3 renders as $3.33333333 in
the lot name): displayed lot names can thus always be written back in a journal
and still identify their lot, while stored costs keep full internal precision
for gain calculation (#2689). The same comparison is used when checking a
written lot subaccount or transfer destination annotation against the resolved
lot.

Because of the rounded-value acceptance, a cost-only selector (eg `{$3.33333333}`)
can in principle match two distinct lots whose costs differ only beyond the
displayed digits (they render identically). Date and label selectors remain
unambiguous - same-date lots always get distinct labels - so cost-only selectors
are the least robust form, and the manual recommends selecting by date (and
label) instead. Under SPECID a multi-match is an explicit ambiguity error;
under FIFO/LIFO/HIFO it silently consumes from the matching lots in method order.

## Cost basis precision

An inferred unit cost (eg from `3 ABC @@ $10`) is computed by Decimal division
and can carry up to 255 internal decimal places; the lot name displays at most
`defaultMaxDisplayPrecision` (8) digits, or more if the commodity's declared
style is wider (`widenLotCbCost`). Consequences:

- Within one journal, gains are computed from the full-precision stored cost:
  buy 3 ABC for $10, sell all at $4/unit, gain is $2 (to internal precision).

- Across a file boundary, only the displayed digits survive: `close --lots`
  (or copying `print --lots` output) serializes the basis as its rendered lot
  name, so re-reading creates a lot whose basis is exactly the displayed value.
  A 10/3 basis becomes exactly $3.33333333, and the same sale in the new file
  yields $2.00000001. This quantization is bounded (at most half an ULP of the
  displayed precision, per unit) and one-time: the requantized basis is a
  finite decimal and round-trips losslessly thereafter. Carrying the basis as
  an exact total cost (`{{...}}`) could avoid this for intact lots, but the
  `{{...}}` form currently has known bugs (see lots-dispose.test test 35) and
  cannot help partially-consumed lots (a slice of a repeating basis is again
  non-terminating).

- Changing a commodity's declared display precision changes how inferred costs
  render in lot names (widening beyond, or narrowing back across, the digits
  previously rendered). Since matching accepts only the exact stored value or
  the *current* rendering, lot names and selectors recorded under the old
  precision stop matching, producing "no lots matching" errors that list the
  account's actual lots. Recovery is mechanical: update the recorded names and
  selectors to the new rendering, taken from the error message or `print
  --lots`. Date/label selectors don't embed a cost and are unaffected.

## Data types

All fields are Maybe, so the same types serve for both definite and partial values:

```
data CostBasis = CostBasis { cbDate :: Maybe Day, cbLabel :: Maybe Text, cbCost :: Maybe Amount }
data LotId = LotId { lotDate :: Day, lotLabel :: Maybe Text }
```

A definite cost basis (used for a fully resolved lot) has all fields present except cbLabel which is only present when needed for uniqueness.
A partial cost basis (used as a lot selector or during inference) may have any fields missing.

## Lotful commodities

Commodities can be declared as lotful, by adding a "lots" tag to their declaration.
This signifies that their postings always involve a cost basis and lots, 
so these should be inferred if not written explicitly.

Lotfulness is a property of commodities only, not accounts: an account
"lots" tag cannot enable lot tracking. It can however *disable* it: the
special value NONE (case insensitive) opts the account and its subaccounts
out of lot tracking, eg for tax-sheltered accounts where cost basis is
irrelevant. Any other value sets the account's reduction method (see
below); a value is required (a valueless account lots: tag, or lots: NONE
on a commodity declaration, is an error, reported by
journalCheckLotsTagValues).

Precedence is by specificity: a posting's explicit cost basis annotation
beats the account opt-out (such postings are still lot-tracked), which
beats the commodity's lots tag; and the nearest account declaration wins,
so a subaccount can re-enable tracking with its own lots: method tag.
Opted-out postings are invisible to lot classification and counterpart
detection (`optedOut` in Lots.hs's classification, gain inference,
auto-split, the unclassified-posting error, and the method coherence
check all skip them). Consequences at the boundary: bare units moving
from a tracked account into an opted-out one classify as a (priceless)
disposal, leaving lot tracking like an in-kind donation; bare units
moving the other way fail with the unclassified-posting error, since
entering lot tracking requires a basis or price.

For tracking a commodity's lots in only a few accounts (the inverse
shape), the recommended style remains manual cost basis annotations with
no lots tag.

(In future, we may also recognise some common commodity symbols as lotful, even without the lots tag.)

## Inferring cost basis from transacted cost

In postings with a positive amount, involving a lotful commodity,
which have a transacted cost but no explicit cost basis annotation,
or an empty cost basis annotation (`{}`),
we infer a cost basis from the transacted cost.

## Inferring cost basis from lot subaccount names

When a posting's account name contains a lot subaccount (a final component starting with `{`),
the cost basis is parsed from the subaccount name and applied to the posting's amounts.
If the amount already has a cost basis annotation, the two are merged:
any `Nothing` fields are filled in from the other source,
and any fields present in both must agree (otherwise an error is reported).

This allows `print --lots` output (which has explicit lot subaccounts) to be re-read
without losing cost basis information, and allows users to write lot subaccounts
directly without a redundant `{}` annotation on the amount.

(journalInferBasisFromAccountNames, runs unconditionally before journalClassifyLotPostings)

## Lot postings

After inferring cost basis, we identify and classify lot postings.
A `_ptype` tag is added to each classified posting to record its type:
`acquire`, `dispose`, `transfer-from`, or `transfer-to`. (Realised gain
postings are tagged `gain` separately: user-written ones before balancing by
`transactionTagGainPostings`, generated ones by `journalAddOrCheckGainPostings`.)

(`journalClassifyLotPostings` → `transactionClassifyLotPostings`)

### Classification summary

In short: a lotful commodity entering an asset account is an **acquire**.
A lotful commodity leaving an asset account is a **dispose**.
A lotful commodity moving between asset accounts is a **transfer**.
The details below handle edge cases: bare postings without `{...}`,
equity transfers, partial transfers with fees, and cost source inference.

### Classification rules

Classification proceeds in several steps. 

**1. Same-account transfer pairs.**
Within each account, negative and positive unpriced postings with the same
commodity and exact absolute quantity are paired as transfer-from /
transfer-to. Priced postings are excluded (a priced posting is a deliberate
trade, eg a stock split's dispose/re-acquire postings; and lot transfers may
not be written with a transacted price).
When there are more of one sign than the other, the excess are left
unmatched and classified by the rules below.

**2. Postings with cost basis (`{...}`).**
These are classified regardless of account type:

- **Negative** → `dispose`, or `transfer-from` if a counterpart posting
  (same commodity and quantity, different account) exists, or if the
  commodity's unpriced quantities sum-match (see below).
- **Positive** → `acquire`, or `transfer-to` if a counterpart exists or
  the commodity's unpriced quantities sum-match.
- **Sum matching**: when transfer postings don't pair one to one (a split
  or consolidating transfer, eg `-10` vs `+5`/`+5`), a counterpart is
  recognised if the commodity's total unpriced outflow equals its total
  unpriced inflow, with the opposite side in some other account (#2692).
  This fallback applies only to unpriced postings (a priced posting is a
  deliberate trade) and not to auto-split fee fragments (which must remain
  disposals).
- **Equity transfer override**: if the posting has no transacted price
  (`@ ...`) and an equity counterpart posting (no cost basis) exists in
  the transaction, it is classified as transfer-from/to instead of
  dispose/acquire. This handles `close --clopen --lots` style equity
  transfers where lots move to/from equity in separate transactions.

**3. Bare postings in lotful commodities on asset accounts (no cost basis).**
These require an asset account type and a lotful commodity
(commodity `lots:` tag), and the account must not have opted out of lot
tracking with a `lots: NONE` tag. They are tried in this order:

- **Negative lotful** →
  `transfer-from` if a counterpart (same commodity, exact quantity,
  different account) exists, or if the posting has no transacted price
  and another asset account in the same transaction receives a positive
  lotful amount of the same commodity (transfer+fee pattern, where
  source qty > dest qty due to fees; a transacted price signals dispose
  intent, eg an explicit priced fee disposal written alongside a matched
  transfer pair).
  Otherwise `dispose` if the posting has a transacted price.

- **Positive lotful, no price, with transfer-from counterpart** →
  `transfer-to`. The counterpart can match by exact quantity or by
  commodity only (for transfer+fee patterns). This handles bare
  transfer-to postings in lotful commodities that don't repeat
  the `{...}` notation.

- **Positive (any), no cost basis, with cost-basis transfer-from counterpart** →
  `transfer-to`. The counterpart can match by exact quantity or by
  commodity only (for transfer+fee patterns). This handles the receiving
  side of transfers where the sending side has `{...}` but the receiving
  side doesn't.

- **Positive lotful with a plausible cost source** →
  `acquire`. A cost source is plausible when the posting has a transacted
  price (`@ ...`), or the transaction contains a different-commodity posting
  (allowing the balancer to infer a cost), or a transfer-from counterpart
  exists. Without any of these, no lot can be created and classification is
  skipped.

Virtual (parenthesised) postings are never classified as lot postings.

**4. Gain accounts.**
Postings in accounts with type `Gain` (and not otherwise classified) get
ptype `gain`.

### Unclassified lotful postings

With `--lots`, a real posting with a nonzero lotful commodity in an asset account
that was not classified (no `_ptype` tag) is an error.
This catches lotful postings that need lot tracking but weren't recognised.

Zero-amount lotful postings (e.g. for balance assertions like `0 AAPL = 100 AAPL`)
are exempt: no lot movement occurs, so no classification is needed.
This applies regardless of whether the amount was written explicitly or left implicit.

(`isUnclassifiedLotfulPosting` in Lots.hs)

### Counterpart detection

Transfer detection uses precomputed maps keyed by (commodity, |quantity|):

- `negCBAccts`: accounts with negative postings that have cost basis
  (any account type), or are bare lotful negatives on asset accounts.
  Non-asset bare lotful negatives (e.g. revenue) are excluded.
- `posCBAccts`: accounts with positive postings that have cost basis.
- `posNoCBAccts`: accounts with positive asset postings without cost basis.

A posting has a "counterpart" when the opposite-sign map contains a
different account for the same commodity and quantity. This requires exact
quantity matching for the primary check (`hasCounterpart`,
`hasTransferFromCounterpart`).

A commodity-only fallback (`hasTransferFromCommodityMatch`) checks
`negCBAccts` for any entry with the same commodity in a different account,
ignoring quantity. This is used by `shouldClassifyLotful` and
`shouldClassifyBareTransferTo` to detect transfer-to postings in
transfer+fee patterns where the destination receives less than the source
sends.

A sum-based fallback (`negSums`/`posSums`, `hasSumCounterpart`) handles
transfers whose postings don't pair one to one (#2692): per commodity, the
total unpriced negative quantity and total unpriced positive quantity are
accumulated (with the contributing accounts), using the same side criteria
as the maps above; a counterpart exists when the totals are equal and the
opposite side includes another account. Priced amounts are excluded (a
priced posting, eg a fee disposal `-0.02 A {$100} @ $100`, is a deliberate
trade), and so are auto-split fee dispose fragments (feesplit tag), which
would otherwise inflate the outflow total and defeat the match. This
fallback is used by `shouldClassifyWithCostBasis` only, for unpriced
non-feesplit postings; the bare paths already have the commodity-only
fallback.

### Main functions

- `journalClassifyLotPostings`: entry point, maps over transactions.
- `transactionClassifyLotPostings`: per-transaction classifier.
  - `sameAcctTransferSet`: precomputed set of same-account transfer pair indices.
  - `negCBAccts`, `posCBAccts`, `posNoCBAccts`: counterpart maps.
  - `hasCounterpart`, `hasTransferFromCounterpart`, `hasTransferFromCommodityMatch`: counterpart lookups.
  - `classifyAt`: per-posting dispatch.
  - `shouldClassify` → `shouldClassifyWithCostBasis`, `shouldClassifyNegativeLotful`,
    `shouldClassifyLotful`, `shouldClassifyBareTransferTo`, `shouldClassifyPositiveLotful`.
  - `amountsAreLotful`: checks for a `lots:` tag on the amounts' commodities.

## Inferring transacted cost from cost basis

In positive cost-basis postings which have no transacted cost annotation,
we infer a transacted cost from the cost basis (letting an acquire entry
with an elided cash amount balance at cost). This runs before transaction
balancing, so classification hasn't happened yet; transfer destinations -
which must not get a transacted cost - are recognised by shape. Inference
is skipped when:

- another account has an explicit negative amount of the same commodity
  and quantity (an exact transfer-from counterpart), or
- the commodity's unpriced negative and positive quantities sum to matching
  totals, with a negative in another account (a split or consolidating
  transfer group, possibly minus a fee; priced amounts are excluded on both
  sides) (#2692), or
- the transaction has an equity posting with no cost-basis amounts (an
  equity transfer, eg close --clopen --lots style opening balances).

(journalInferPostingsTransactedCost in Journal.hs)

## Lot posting effects

- An acquire posting creates a new lot, with a cost basis either specified
  or inferred from the transacted cost (or perhaps market price, in future).

- A transfer-from posting selects one or more lots to be transferred elsewhere,
  following some selection/reduction method. Either
  - it has a lot selector (a full or partial cost basis annotation),
    which must unambiguously select a single existing lot ("SPECID" method)
  - or it has no lot selector, in which case a default method is used ("FIFO" method), selecting one or more existing lots.

- A transfer-to posting mirrors a corresponding transfer-from posting in the same transaction,
  recreating its lot(s) under a new parent account.
  It doesn't need a lot annotation; if it has one, any specified fields
  (date, label, cost) must match the source lot.
  (Transfers must preserve the source lot's identity, and can't rename a lot.)
  Transfer postings (both from and to) must not have explicit transacted cost (@ or @@); this is an error.
  Transfer-from and transfer-to postings need not pair one to one: per commodity,
  one source posting can feed several destinations or several sources one
  destination, as long as the total from/to quantities are equal - a quantity
  mismatch is a load-time error (#2692). Each source posting selects its lots
  (from its own account, with its own selector), and the selected lots are
  distributed across the destination postings in sorted group order, splitting
  lots at destination boundaries; lot identity is preserved
  (`processTransferGroup` in Lots.hs).
  Formerly, a from>to quantity difference was consumed from the source silently (an
  implicit fee disposal); that is now handled only by the explicit fee auto-split -
  see "Auto-splitting lot transfer fees" below - which requires the fee recorded as
  non-asset posting(s) in the same commodity adding up to the exact fee quantity,
  and produces explicit dispose portion(s). Patterns auto-split doesn't detect
  (eg fee postings not summing to the missing quantity) are errors suggesting
  that form.

- An equity transfer is a variant of a lot transfer that happens in two parts across
  separate transactions (e.g. a closing transaction transfers lots into equity, and an
  opening transaction transfers them back out). In the closing transaction, transfer-from
  postings reduce lots from the lot state. In the opening transaction, transfer-to
  postings re-add the lots to the lot state, preserving their original cost basis.
  The equity postings do not track lots.

- A dispose posting selects one more lots to be disposed (sold), like a transfer-from posting.
  It must also have a transacted cost, either explicit or inferred from transaction balancing
  (or from market price, in future).
  When the dispose posting has no cost basis annotation but involves a lotful commodity,
  the cost basis is inferred from the selected lot, and the transacted cost
  (if inferred by the balancer as @@) is normalized to unit cost (@).

## Reduction methods

The reduction method, also known as booking method, is the order in which lots are "reduced" (disposed or transferred from).
It is configurable per account and per commodity via the `lots:` tag.
(And also per posting via the `lots:` tag on a posting comment ?)

The supported reduction methods are:
SPECID (specific identification via lot selector),
FIFO (oldest first),
LIFO (newest first),
HIFO (highest cost first),
and
AVERAGE (weighted average cost basis).
If not specified, FIFO is the default.
These are per-account: they select lots and enforce/validate their order only within the posting's account.

There are also variants which consider lots across all accounts: FIFOALL, LIFOALL, HIFOALL, AVERAGEALL.
These select lots within the posting's account, but they also validate that the selected lots
would be the ones chosen if all accounts' lots were merged into a single pool.
If not, an error is raised showing which lots on other accounts have higher priority.

AVERAGE/AVERAGEALL maintain a single running per-unit cost shared by every
lot in the pool. The running cost is updated on each acquisition by the
weighted-average formula
`((poolQty × poolCost) + (acqQty × acqCost)) / (poolQty + acqQty)`,
and every existing pool lot's stored cost basis is rewritten to the new
running cost. Disposal does not change the running cost: it just consumes
quantity from one or more pool lots at the shared cost. Lots are still
selected in FIFO order so the per-acquisition dates remain meaningful for
holding-period reporting (the disposal posting fragments preserve their
original acquisition dates).

The scope of a pool is per-account for AVERAGE and global (across all
accounts holding the commodity) for AVERAGEALL.

The global (*ALL) methods are only coherent when every account holding the
commodity uses them: a non-participating account's disposals would skip the
global validation, and (for AVERAGEALL) its acquisitions would not update
the global pool even as pool updates rewrite its lots' costs. So mixing a
global method with any different method for one commodity is rejected at
load time (`journalCheckLotsMethodCoherence`): for each lot-tracked
commodity, the method is resolved for every base account holding it, and if
any resolves to a *ALL method, all must resolve to the same method. Local
methods (FIFO, LIFO, HIFO, SPECID, AVERAGE) may be mixed per account
freely; an unused account's conflicting tag is harmless.

Under AVERAGE methods the lot subaccount name omits the cost component
(`{2026-01-15}` rather than `{2026-01-15, $50}`): the running cost would
otherwise change on every acquisition, making the subaccount unstable
across acquisitions.

`print` preserves the user-written cost annotation on acquire postings.
The pool's running cost is surfaced on disposal postings (where the user
wrote `{}` and the system fills in the lot's stored cost) and on
realised-gain calculations (e.g. via `bal -B`).

Transfers interact with AVERAGE pools like this:

- A transfer out of a pool carries the pooled cost, and (like disposal)
  does not change the remaining pool's running cost.
- A transfer into a pool re-averages it, exactly like an acquisition at the
  carried cost; all pool lots' stored costs, including the incoming lot's,
  are rewritten to the new average (`addTransferredLot` calls
  `updatePoolOnAcquire`). Under AVERAGEALL this is a no-op: the lot never
  leaves the global pool, so the carried cost equals the pool cost.
- Pooling is lossy: original lot identity (cost) cannot be reconstructed on
  transfer back out; only the date and label survive.
- The displayed transfer fragments keep the carried (source) cost on both
  sides, matching each other (the same convention as acquisitions, which
  display the user's literal cost); the destination's post-merge average
  lives in lot state and appears on later disposals. Fragment lot
  subaccount names follow each side's own method (costless under AVERAGE).
- A cost written in a transfer-to annotation into an AVERAGE account is not
  validated against the source lot's cost (the pool's running cost
  legitimately differs); date and label are still validated.

## Lot transactions

Lot transactions are transactions with lot postings.
If a transaction has multiple lot postings, we (mostly ?) require that they are all of similar type: all acquire, or all transfer, or all dispose.
So a lot transaction can be broadly classified as "acquire", "transfer", or "dispose".

## Transaction balancing

All transactions are balanced by the ordinary transaction-balancing rule —
sum postings at transacted cost (ignoring cost basis), sum must be zero,
infer at most one missing amount per commodity — with one refinement for
disposals: their realised gain postings (tagged `_ptype:gain`, see
"Disposal transactions" below) are set aside, contributing nothing to the
sum or to inferred amounts. This makes a disposal balance at cost basis:
since `q×B + q×(T−B) = q×T`, "the non-gain postings sum to zero at
transacted cost" is the same statement as "all postings, gain included,
sum to zero with the disposed units valued at basis"; and it can be
checked before lot matching has determined B. The gain amount itself is
checked after lot matching (`journalAddOrCheckGainPostings`), which closes
the loop. (Historical cost accounting: unrealised gains are not posted.)

Cost reports follow the same convention: `-B`/`--value=cost` converts an
amount with a cost basis to that basis (`amountCostBasis`), else to its
transacted cost, so a disposal converts to what the units cost and cost
reports balance; `--value=transacted` (`ToTransactedCost`) converts at
transacted cost only. Since collapsing lot detail (when `--lots` is off)
merges a multi-lot disposal's fragments into one amount with an unspecified
basis, the -B conversion is applied before collapsing, in
`journalTransform` (`maybeConvertToCostBasis`); the later per-report
conversion is then a no-op for those amounts.

When the balancer infers a conversion cost between two commodities, and
exactly one of them has classified lot postings — or, failing that, is
declared lotful (eg when its posting's amount comes from a balance
assignment and so was unknown at classification time) — the cost is
attached to that side, so lot postings get the transacted cost they need
for lot tracking (`costInferrerFor` in Balancing.hs).

However, when a lot-related commodity appears with both signs among the
postings (a transfer-like shape), the residual is analysed further:

- If the residual is exactly one posting's amount (a dispose posting
  alongside a matched transfer pair, eg a fee disposal written as its
  own posting with the fee paid in cash), the inferred cost is attached
  to that posting only, as a total (@@) cost, leaving the others
  unpriced - they form matched transfer pairs, which must stay unpriced
  for lot classification; only the odd one out needs the cost.
- Otherwise no cost is inferred: such a residual indicates a quantity
  mismatch (eg a fee deducted in kind but not recorded), and inferring a
  cost would attach it to both sides, mask the imbalance, and surface
  later as a confusing lot error. The entry instead fails the more
  fundamental balancedness check, which shows the residual along with a
  note explaining why no cost was inferred (since a user unaware of lot
  processing might expect this entry to balance).

## Disposal transactions

The realised gain/loss from a disposal is calculated as follows:
for each dispose posting in the entry whose amount has both 
a cost basis `B` and a transacted cost `T`, contribute `aquantity × (B − T)`.

### Gain postings

Each disposal transaction has a **gain** posting (its realised gain), usually
to a Gain-type account (default `revenues:gain`), carrying the negated gain.
There is no counter posting: the disposal balances at cost basis (see
"Transaction balancing" above), the disposed units leaving at their basis
and the gain making up the difference from the proceeds. (Until 2026-09 a
balancing `equity:unrealised-gain` posting was also generated, so that
disposals balanced at transacted cost; it was dropped, see #2731 and
DECISIONS.md, because without revaluation postings it left a permanent
phantom equity balance and broke the accounting equation.)

### Gain account type

The Gain account type can be declared explicitly via a `type:` tag:

```
account revenues:gain  ; type: G
```

It is also inferred from conventional English account names
(see the regex table under
[Account types](https://hledger.org/hledger.html#account-types) in the user manual).
For example `revenues:gain` and `income:capital-gains` are detected automatically.
(The UnrealisedGain/U type, eg `equity:unrealised-gain`, still exists for
users' own accounts, but hledger generates no postings to it.)

Declaring and using this account type is not strictly required,
but it can improve error checking in disposals,
it selects the account for inferred gain postings,
and it facilitates more precise querying.

### Disposal journal entries

Disposal transactions can be written in any of these styles. The user manual's
"Recording gains" section walks through each with examples and trade-offs.

Styles are listed in the same order as the manual, from implicit to explicit.

1. **No gain posting.**
  After lot matching, hledger computes the disposal gain
  and infers a realised gain posting for the transaction
  (`journalAddOrCheckGainPostings`).
  The inferred amounts are rounded to the entry's local precision for the gain commodity
  (or if that is 0, and the gain has non-zero cents, decimal precision 2.
  See "Gain precision" below).

2. **Only the gain posting written, not using a type:G account.**
  hledger identifies gain posting(s) heuristically: one or more postings 
  whose account type is not Asset, Liability, or Equity (or a subtype of these),
  which have not been classified as a lot movement by the lot classifier,
  and whose non-gain siblings sum to zero (or, in an unpriced sale, to a lot commodity
  net sold plus one other commodity net received, which cost inference will resolve;
  a net purchase with a cash fee is not treated as a disposal with a gain).
  When gain postings are detected, hledger tags them with `_ptype:gain`
  (`transactionTagGainPostings`, before balancing), and the balancer sets them aside.
  After lot matching, the transaction's gain amount is checked against
  the calculated gain at the entry's local precision; sub-last-place-unit differences
  are tolerated (see "Gain precision" below), but larger discrepancies
  raise an error.

  When the imbalance is multi-commodity (typically because the dispose posting lacks an `@`
  transacted price), the transaction balancer fills in a balancing `@` price from the
  non-gain postings; the gain check then proceeds as above.

  Virtual (parenthesised) postings are ignored throughout this gain
  inference, as they are by the transaction balancer and the lot
  classifier: they neither make an entry look like a disposal nor
  count in the residual sums.

3. **Only the gain posting written, using a type:G account.**
  hledger identifies the gain posting by the type:G account and tags it,
  as above. The gain amount is checked; or it may be omitted (at most one
  amountless gain posting per entry), in which case the balancer leaves the
  posting alone and `journalAddOrCheckGainPostings` fills in the calculated
  gain (less any other written gain amounts) after lot matching. In lenient
  (--ignore-lots) mode there is no lot matching, so amountless Gain-typed
  postings are not tagged and the balancer infers them as usual.

(A fourth style, with an explicit `equity:unrealised-gain` counter posting,
was supported until 2026-09; such entries now fail to balance.)

### Gain precision

Inferred gain amounts (case 1, and amountless gain postings in case 3) and the gain-validation
comparison (cases 2-3) operate at the **entry's local precision** for
the gain commodity (ie, the maximum precision seen among the
posting amounts in that commodity).

As a special case, if the local precision is 0 decimal places (or the commodity is absent),
and if the gain amount is not an integer, it is shown with 2 decimal places.

This tolerance (and non-accounting) of small imprecisions is similar to
how transaction balancing works. If you want more precision, write more
decimal places in the entry's amounts.

## Acquire basis check

`journalCheckAcquireBasis` enforces that every acquire posting has per-unit
cost basis equal to per-unit transacted cost. If `{B}` and `@T` are both
written on an acquire posting and `B ≠ T`, the check raises an error citing
the offending posting. This prevents typos in cost basis causing wrong gain
to be calculated later.

Real-world cases where basis legitimately differs from price paid (gifts
with carryover basis, NSO exercises, RSU vesting, wash-sale adjustments,
etc.) are best expressed by adding a separate income/equity/asset posting
that funds the difference.

The check uses strict Decimal equality, not the precision-tolerant
`mixedAmountLooksZero` comparison used by transaction balancing and the
recorded-gain check. Those tolerances are bounded within a single entry,
but a basis discrepancy persists in the lot store and amplifies at
disposal (gain = `(sale − basis) × qty`), and there is no downstream
"basis assertion" check that would surface accumulated drift. Strict
equality treats sub-precision inexactness as the same kind of error as
a typo.

When the per-unit basis would be a non-terminating decimal (eg
$50 / 7 = $7.142857...), record it cleanly via one of:

- `{}` — let hledger infer basis from the transacted cost (same precise
  division).
- `{{TotalCost}}` — record the total basis; hledger derives the
  per-unit value with the same precise division.
- An explicit `{$7.142857143}` at sufficient precision.

An explicit `{$7.14}` paired with `@@ $50` deliberately fails the check
— the rounded annotation forgets a per-unit fraction that would
compound across disposals.

Other PTA apps (hledger 1, Ledger, Beancount, rustledger, acc) accept entries
where `B ≠ T`, so this check is off by default to avoid interoperability
pain. It runs only when the user types `hledger check basis` (not in
default or `--strict` mode). See [DECISIONS.md](DECISIONS.md) for the
rationale.

## Balance assertions

A balance assertion on a dispose or transfer posting (eg `= 0 AAPL`) runs before `--lots` processing
(in `journalBalanceTransactions`), when the posting is still on the parent account — so it checks the
parent account's balance, as expected.

When `--lots` later splits that posting onto lot subaccounts, the assertion is removed from the lot
postings and re-attached to a new zero-amount `_generated-posting` on the original parent account,
with `bainclusive = True` (ie the `=*` syntax). This makes the assertion check the inclusive balance
of the parent plus all its lot subaccounts, which is the semantically correct interpretation when the
output is re-read later (eg after `print --lots -x`).

If the original posting's account is already an explicit lot subaccount (eg
`assets:stocks:{2026-01-15, $50}`), the assertion is left on the split posting unchanged, since it
already targets the right account.

`close --lots` does not generate balance assertions on lot subaccount postings in the
closing transaction (e.g. `assets:stocks:{2026-01-15, $50}`), because these assertions
would be invalid when the output is re-read: balance assertions run before lot calculation,
so the lot subaccounts would not yet have their expected balances. Non-lot-subaccount
postings (e.g. `assets:cash`) and opening transaction postings retain their assertions.

Also, `close` excludes accounts whose balance is zero once costs are stripped
(its normal non-`--show-costs` treatment), such as lot subaccounts emptied by
transfers. Without this it would emit spurious zero postings for them, whose lot
names duplicate the ids of the lots now held at the transfer destination,
making the output unparseable (#2689).

## Processing pipeline

Lot-related processing runs during journal finalising as a sequence of
stages. Errors (missing lot cost, ambiguous selectors, dispose before
acquire, invalid `lots:` tag values, etc.) are reported at load time.
Their excerpts show the entry as the user wrote it - postings reverted to
their original parse-time form, generated postings omitted - rather than
the processed in-memory entry, mentioning the problem posting's inferred
amount when it is not visible in the excerpt
(`transactionAsWritten` in Lots.hs, #2686).
For transparency about hledger's interpretation, the excerpt is followed
by a one-line summary of how the postings were classified, when they were:
`Postings were read as: transfer-from, transfer-to, unclassified; and
generated: dispose, balance-assertion.`
(`postingsReadAs` in Lots.hs). The classifications are listed in posting
order, matching the excerpt's lines; generated postings (omitted from the
excerpt) are named at the end. The excerpt shows what the user wrote;
this line shows how hledger read it, keeping the two clearly separate.
See [SPEC-finalising.md](SPEC-finalising.md) for how this sits in the
broader pipeline.

The post-balancing stages below are **gated by `checklots`** — they run when
none of `--ignore-lots` or `-I` is set, or when `--strict`/`-s` or `hledger
check lots` overrides them. The pre-balancing stages and the balancer's
lot-awareness always run, so lot entries balance the same in both modes;
with `--ignore-lots` the pre-balancing stages are lenient, skipping their
errors (see "Lots mode" above).

Lot classification runs **once, after transaction balancing**, when every
posting amount (including ones inferred from elided amounts or balance
assignments) is known: every entry shape then classifies identically to its
fully-explicit form (#2686, #2690, #2692). The few lot-related steps that must
run before balancing use *shape* checks (cost basis annotations, lotful
commodities, amount signs and prices) rather than classification tags.

Pre-balancing:

1. **journalInferBasisFromAccountNames** — parse cost basis from any lot subaccount
   names (`{...}` components) in posting account names.
2. **journalInferPostingsTransactedCost** — infer `@` from `{}` on acquire-shaped
   postings (positive, cost basis with a cost, no `@`), so eg an acquire with an
   elided cash amount balances at cost. Transfer destinations are recognised by
   shape and skipped: an explicit negative same-commodity same-quantity
   counterpart, or an equity posting with no cost-basis amounts (equity transfer).
3. **journalTagGainPostings** — in disposal transactions (recognised by shape:
   a negative lotful or cost-basis amount), tag user-written realised gain
   postings `_ptype:gain`, so the balancer sets them aside; error on an
   amountless one (unless lenient). Runs before auto postings, whose
   preliminary balancing needs the tags too. The per-transaction
   `transactionTagGainPostings` also runs inside the balancer
   (`balanceTransactionHelperMaybeSplittingLotFees`), for callers which
   balance single entries, like `hledger add`.

Balancing (`journalBalanceTransactions`): infers balance-assignment and elided
amounts. For lots journals it uses `balanceTransactionHelperMaybeSplittingLotFees`:
a transfer with a priced fee only balances at cost in split form, so the fee
auto-split is tried first, falling back to the unsplit form. Note the balancer
mechanically copies amounts (annotations included) into elided postings; a
posting whose amount was wholly inferred yet carries a cost basis annotation
has a *balancer-copied basis* — not user intent
(`hasBalancerCopiedBasis` in Lots.hs). When such a mirrored posting is a
nonzero, unpriced amount in a lot-tracking asset account, classification
reads it as the elided destination or source of a lot transfer
(`isMirroredTransferCandidate`). The same shapes arise from mistakes:
a sale missing its price (eg `stocks -5 AAPL {$50} / cash`) will be
interpreted as a transfer, until the user notices; an acquisition missing
its cost (eg `broker 10 AAPL {2026-01-01} / cash`) errors as a transfer
from a lot-less account.
Mirrored postings which can't be a transfer counterpart (priced, zero,
non-asset, or in a lots: NONE account) stay unclassified and invisible to
counterpart detection. After lot processing, `journalStripBalancerCopiedBases` removes
unclassified mirrored postings' annotations, so downstream code sees only
user-written or lot-machinery-derived cost bases. Bare inferred amounts
classify normally (eg an elided transfer destination for a bare source).

Post-balancing:

4. **journalClassifyLotPostings** — auto-split remaining (unpriced) transfer fees
   (`transactionAutoSplitFeeOutflows`), then tag postings as
   acquire/dispose/transfer-from/transfer-to/gain.
5. **journalCheckLotsTagValues** — validate `lots:` tag values on commodity/account
   declarations. On commodities an empty value is valid (lotful, default FIFO);
   on accounts a reduction method value or NONE is required.
6. **journalCheckLotsMethodCoherence** — reject a global (*ALL) reduction
   method mixed with any different method among the accounts holding a
   commodity (see Reduction methods).
7. **journalCalculateLots** — walk transactions in date order, evaluate lot selectors,
   apply reduction methods, add explicit lot subaccounts, infer cost basis for bare
   disposals, normalise transacted cost.
8. **journalCheckAcquireBasis** — *gated separately on `hledger check basis`*,
   not on `checklots`. Errors if any acquire posting has cost basis differing
   from its transacted cost (per-unit). Default mode skips this check; see
   [DECISIONS.md](DECISIONS.md) for the rationale.
9. **journalAddOrCheckGainPostings** — for disposals with no gain posting yet, add
   the gain posting sized at the disposal gain. Also validates that any
   user-written (tagged) gain amount matches the disposal gain — including in a
   non-disposal, eg a transfer, where the gain is zero.

The gated stages raise errors when the journal contains lot-related content that
can't be resolved (missing lot cost, ambiguous selectors, dispose before acquire,
malformed `lots:` tag values, etc.); `--ignore-lots` suppresses these by skipping
the gated stages entirely (and by making the always-on pre-balancing stages
lenient).

The `--lots` flag is a display toggle consumed in the report-loading layer
(`journalTransform` in `Hledger.Cli.Utils`). When absent, `journalCollapseLotDetail`
strips lot subaccount suffixes from account names, drops synthetic
`_lot-parent-assertion` postings, and merges runs of `_lotsplit-posting` fragments
(per-lot dispose/transfer splits sharing the same `poriginal`) back to a single
posting (with an unspecified `{}` basis when several lots were involved).
Lot-inferred cost basis annotations are kept on the amounts, so that `print`
can show them (see below). Posting amounts on other postings
are left alone; `print` relies on `transactionWithMostlyOriginalPostings` to revert
to `poriginal` when displaying non-explicit output.

See SPEC-finalising for more details of the implementation.

### Auto-splitting lot transfer fees

Before classification, hledger detects a common "transfer with fee"
pattern and rewrites it into explicit transfer + disposal postings.

If a transaction has an unpriced negative lotful asset posting (bare in a
lotful commodity, or carrying a cost basis annotation) whose absolute
quantity exceeds the unpriced positive quantity received by asset accounts
by some amount, and non-asset posting(s) (typically expenses) in the same
commodity account for that excess - either a single posting matching it
exactly, or otherwise all of the positive ones summing to it exactly -
the negative posting is split:

- a transfer portion with the matching positive quantity, and
- a dispose portion per fee counterpart, with that counterpart's quantity.
  If the fee counterpart has a transacted price (`@`/`@@`), its dispose
  portion carries it and a gain is calculated; otherwise the dispose portion
  is priceless - lots are still reduced, but no gain is calculated (as with
  any priceless bare disposal).

Any balance assertion on the original posting is kept only on the dispose
portion posted last, so it is still checked after the full original
quantity.

During lot calculation, the fee's dispose portion selects lots *before* the
transfer pair does (`processTransaction` handles fee-split disposes first):
the disposal method in effect thus applies to the full pre-transfer lot set -
under default FIFO the fee consumes the oldest lot - and the transfer carries
the remainder (#2692). Other disposes still run after transfers, so a lot
transferred in can be disposed in the same transaction.

Auto-splitting also works when the outflow amount is inferred by balancing
(eg from a balance assignment): after resolving a transaction's balance
assignments, the balancer applies the fee auto-split before checking
balancedness - a priced fee's split changes the transaction's at-cost value
sum (the dispose portion's cost is what makes the entry balance), and any
elided posting must infer the post-split residual. If the split form does
not balance, the unsplit form is used as before
(`balanceTransactionAndCheckAssertionsB` in Balancing.hs, #2686).

This lets natural journal entries like:

```
2026-03-09 transfer
    assets:custodial        -1 ETH
    assets:cold wallet   0.999601 ETH
    expenses:fees       0.000399 ETH @ $1,992.36
```

classify and balance as if the user had written:

```
2026-03-09 transfer
    assets:custodial                 -0.999601 ETH
    assets:custodial  -0.000399 ETH @ $1,992.36
    assets:cold wallet                0.999601 ETH
    expenses:fees     0.000399 ETH @ $1,992.36
```

(with the gain posting then generated as usual, or an amountless gain
posting filled in - this works here too, although the disposal is only
recognisable once the balance assignment has been resolved, because gain
postings are also tagged inside the balancer, after that point).

The original user posting is preserved via `poriginal` on the transfer portion
(p1), and the dispose portion (p2) is tagged `_feesplit-posting`. As a result:

- With an unpriced fee, plain `print` shows the user's original entry (the
  `_feesplit-posting`-tagged portion is hidden, and the remaining portion
  displays at the original quantity via `poriginal`).
- With a priced fee, plain `print` shows the split form: reverting would drop
  the priced dispose portion while keeping its generated gain postings,
  leaving an unbalanced entry.
- `print -x` shows the split form explicitly (both portions visible at their
  post-split quantities).
- `print --lots` also shows the split form for auto-split transactions, so
  that the output round-trips correctly (preserving the capital gain that
  would otherwise be lost if the dispose portion were hidden). Other
  transactions still display in their mostly-original form.
  For an *unpriced* fee, the printed dispose fragment carries an explicit lot
  reference and no price; on re-read, `processDisposePosting` accepts such a
  priceless disposal when the entry's non-asset postings receive the same
  commodity in the same total quantity as its priceless disposals (an in-kind
  outflow: a fee, a donation, etc - possibly split across several postings),
  so this form round-trips too (#2692). Priceless disposals whose units are
  not received by non-asset postings (eg a sale missing its price) are still
  errors.

### Per-lot disposal/transfer splits

A separate internal split happens when a single dispose or transfer posting
spans multiple lots: `processDisposePosting` / `processTransferGroup` emit one
fragment per matched lot, each carrying its lot subaccount. Multi-fragment
results are tagged `_lotsplit-posting` (single-lot results need no tag), and
each fragment's `poriginal` points at the user's unmodified original posting.

Display behaviour:

- Plain `print` collapses the fragments via `journalCollapseLotDetail` and
  reverts to `poriginal`, so the user sees their single original posting - but
  with the cost basis annotation inferred by lot processing added when they
  wrote none (`{$50}` on an acquire, `{2026-01-15, $50}` on a single-lot
  disposal or transfer, `{}` on a multi-lot disposal), so the printed entry
  is self-describing and re-reads without the commodity's `lots:` declaration
  under the default method. (With `--lots`, the subaccount name carries the
  basis, so amounts are shown without it.)
- `print --lots` keeps the fragments visible and renders each with its lot
  subaccount and per-lot quantity, but with the user's original cost basis
  annotations (achieved by `transactionWithMostlyOriginalPostings` scaling
  `poriginal`'s amount to the fragment's quantity).
- `print -x` keeps the fully inferred form (no revert).

## Examples

For end-to-end walkthroughs, see the user manual's "First lots example" and "Lot reporting example" sections.

A larger collection of example entries: <https://github.com/hledgerorg/hledger/blob/main/examples/lots/lots.journal>

## Roadmap

Possible future work, from design discussions (2026-08):

- **Per-account lot tracking opt-out.** Implemented 2026-08: an account
  `lots: NONE` tag opts the account and its subaccounts out of lot
  tracking, with precedence by specificity (see Lotful commodities).

- **Tax boundary declarations and checks.** Users could tag accounts as
  tax-sheltered (a jurisdiction-neutral, user-declared boundary, in the same
  spirit as account types). Then an opt-in check could flag identity-preserving
  lot transfers crossing the boundary, which usually should be recorded as a
  disposal at fair market value plus a new acquisition (write a transacted
  price on the outgoing posting to get that today). The same declaration could
  drive the lot-tracking opt-out above, and scope pooling (below).

- **AVERAGE round trip.** `print --lots` output for AVERAGE accounts is not
  re-readable: the costless lot subaccount names it emits (`{2026-01-15}`)
  are rejected on re-read ("lot subaccount name must contain a date and
  cost"). Either accept date-only lot subaccount names when the account's
  method is AVERAGE, or omit lot subaccounts from AVERAGE print output.
  (The AVERAGE-vs-transfers item previously here was implemented 2026-08:
  transfers in re-average the pool, transfers out carry the pooled cost;
  see "Reduction methods".)

- **Method coherence checks.** Implemented 2026-08 for the global (*ALL)
  methods: mixing one with a different method among the accounts holding a
  commodity is rejected at load time (see Reduction methods). Plain
  per-account AVERAGE mixed with other methods remains legal by design
  (independent pools); whether that is appropriate for the user's tax
  jurisdiction is, as elsewhere, the user's responsibility.

### Disposal

A minimal implicit disposal (user writes only dispose + proceeds):

```
2026-03-01 sell
    assets:stocks   -15 AAPL
    assets:cash      $900
```

or:

```
2026-03-01 sell
    assets:stocks   -15 AAPL @ $60
    assets:cash
```

Explanation:

1. The missing @ price (or missing cash amount) is inferred by the ordinary
   transaction balancer so the non-gain postings balance at transacted cost
   (any user-written gain posting having been set aside).
2. 15 AAPL are reduced from one or more existing lots, selected by
   `assets:stock`'s / `AAPL`'s / default (FIFO) reduction method.
3. `journalAddOrCheckGainPostings` computes the disposal gain
   (`aquantity × (B − T)` summed over non-acquire postings whose amounts
   carry both basis and transacted cost) and adds a realised-gain posting
   or checks the user-written one. The entry now balances at cost
   basis.
