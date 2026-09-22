# Journal finalising

After parsing, a journal goes through a **finalisation** pipeline (`journalFinalise` in
`Hledger.Read.Common`) that infers missing information, checks validity, and enriches
postings with computed metadata.

("Finalising" is not easy to say, better suggestions welcome.)

## What gets inferred, and from what

Here are the main kinds of information that finalisation infers or computes, roughly in the order they happen.

Note: "cost" means @/@@ (AKA transacted cost); "cost basis" means {} (acquisition cost & info).

| What is inferred                                            | From what                                                 | Step                                     |
|-------------------------------------------------------------|-----------------------------------------------------------|------------------------------------------|
| Account types                                               | Account declarations, account names, parent accounts      | journalAddAccountTypes                   |
| Consistent posting amount styles                            | Posting amounts written in journal                        | journalStyleAmounts                      |
| Forecast transactions                                       | Periodic transaction rules + forecast period              | journalAddForecast                       |
| Posting tags inherited from accounts                        | Account declarations                                      | journalPostingsAddAccountTags            |
| Location of conversion equity postings and costful postings | @/@@ annotations + adjacent conversion account postings   | journalTagCostsAndEquityAndMaybeInferCosts(1st)         |
| Auto postings                                               | Auto posting rules + postings in journal                  | journalAddAutoPostings                   |
| Cost basis from lot subaccount names                        | Account names containing {…} subaccounts                  | journalInferBasisFromAccountNames        |
| Lot posting types                                           | Cost basis + amount sign + account type + lotful status + counterpostings | journalClassifyLotPostings               |
| Cost from cost basis                                        | Costless acquire postings with a cost basis               | journalInferPostingsTransactedCost       |
| Transaction-balancing amounts                               | Counterpostings (or their costs)                          | journalBalanceTransactions               |
| Transaction-balancing costs (on lotful or first posting)    | Costless two-commodity transactions                       | transactionInferBalancingCosts           |
| Balance assignment amounts                                  | Running account balances vs asserted balances             | journalBalanceTransactions               |
| Canonical commodity styles                                  | All posting amounts now present after balancing           | journalInferCommodityStyles              |
| Posting tags inherited from commodities                     | Commodity declarations                                    | journalPostingsAddCommodityTags          |
| Costs from equity postings (--infer-costs)                  | Equity conversion posting pairs                           | journalTagCostsAndEquityAndMaybeInferCosts(2nd)         |
| Equity postings from costs (--infer-equity)                 | Costful postings                                          | journalInferEquityFromCosts              |
| Market prices from costs                                    | Costful postings                                          | journalInferMarketPricesFromTransactions |
| Lot subaccounts, cost basis and cost for bare disposals      | Lot state tracking (applying FIFO etc.)                   | journalCalculateLots                     |

## Current pipeline sequence

```
journalFinalise
  -- Setup
  1.  journalSetLastReadTime
  2.  journalAddFile
  3.  journalReverse

  -- Account types and amount styles (pure, no errors)
  4.  journalAddAccountTypes            -- builds jaccounttypes map
  5.  journalStyleAmounts               -- infer preliminary commodity display styles, and apply to postings

  -- Generate forecast transactions
  6.  journalAddForecast                -- if --forecast, generate forecast transactions from periodic rules

  -- Account tags
  7.  journalPostingsAddAccountTags     -- propagate account tags to postings

  -- Pre-balancing cost/equity tagging
  8.  journalTagCostsAndEquityAndMaybeInferCosts(1st)  -- tag conversion equity postings + redundant costs (helps balancer ignore them)

  -- Lot cost basis and transacted cost inference, gain posting tagging (before balancing; always run,
  -- so lot entries balance the same with or without --ignore-lots;
  -- lenient with --ignore-lots: their errors are skipped, leaving the affected postings unchanged)
  9.  journalInferBasisFromAccountNames  -- if account name has a {…} lot subaccount, parse cost basis from it
  10. journalInferPostingsTransactedCost -- infer cost from cost basis of acquire postings
  11. journalTagGainPostings             -- in disposals, tag user-written gain postings _ptype:gain,
                                         -- so the balancer sets them aside (disposals balance at cost basis)

  -- Generate auto postings
  12. journalAddAutoPostings            -- if --auto, do transaction balancing (preliminary) to infer some missing amounts/costs,
                                        -- then apply auto posting rules. Calls journalBalanceTransactions.

  -- Transaction balancing (main)
  13. journalBalanceTransactionsAndDeferAssertions
                                        -- infer remaining balancing amounts, balancing costs, and balance assignment amounts;
                                        -- and check transactions balanced and (unless --ignore-assertions) balance assertions satisfied.
                                        -- A balance assertion failure is not raised here: the first one is recorded and
                                        -- re-raised only after the stages below have run without error, so lot errors
                                        -- (usually the more fundamental problem) are reported before assertion failures.
                                        -- Lot-aware in both modes (lotful commodities guide cost inference, lot fees are auto-split);
                                        -- with --ignore-lots (lenient_lots_), the lot quantity mismatch veto on
                                        -- balancing cost inference is skipped, so mismatched transfers load.

  -- Lot classification (default; skipped by --ignore-lots/-I; restored by --strict or `check lots`)
  14. journalClassifyLotPostings         -- tag lot postings as acquire/dispose/transfer-from/transfer-to

  -- Post-balancing enrichment
  15. journalInferCommodityStyles        -- infer canonical commodity styles, now with all amounts present
  16. journalPostingsAddCommodityTags    -- propagate commodity tags to postings
  17. journalTagCostsAndEquityAndMaybeInferCosts(2nd)   -- if --infer-costs, infer costs from equity conversion postings
  18. journalInferEquityFromCosts        -- if --infer-equity, infer equity conversion postings from costs
  19. journalInferMarketPricesFromTransactions  -- infer market prices from costs
  20. journalInferAliasPrices            -- inject 1:1 bridges for alias: tags on commodity directives
  21. journalRenumberAccountDeclarations  -- renumber account declarations for consistent ordering

  -- Lot calculation and checking (default; skipped by --ignore-lots/-I; restored by --strict or `check lots`)
  22. journalCheckLotsTagValues         -- validate lots: tag values on commodity/account declarations
  23. journalCheckLotsMethodCoherence   -- reject a global (*ALL) method mixed with other methods for one commodity
  24. journalCalculateLots              -- evaluate lot selectors, apply reduction methods,
                                        -- calculate lot balances, add explicit lot subaccounts,
                                        -- infer cost basis for bare disposals, normalize transacted cost
  25. journalCheckAcquireBasis         -- gated separately on `hledger check basis` (not on checklots);
                                       -- error if any acquire posting has cost basis ≠ transacted cost
  26. journalAddOrCheckGainPostings    -- for disposals with no gain posting, add the gain posting
                                       -- sized at the disposal gain; otherwise check any user-written
                                       -- gain amount against the disposal gain
  27. journalStripBalancerCopiedBases  -- always: remove balancer-copied basis annotations,
                                       -- kept until now as classification evidence

  28. (re-raise deferred assertion failure)  -- if step 13 recorded a balance assertion failure
                                       -- and no later stage errored, report it now
```

## Sequencing constraints

These are the known ordering requirements between steps.
An arrow A → B means "A must run before B".

### Hard constraints

- **journalAddAccountTypes → journalClassifyLotPostings**
  Classification looks up account types to identify Asset accounts.

- **journalPostingsAddAccountTags → journalClassifyLotPostings**
  Classification may need `lots:` tags inherited from account declarations (in `ptags`).

- **journalInferBasisFromAccountNames → journalClassifyLotPostings**
  Classification checks `acostbasis` to identify lot postings; cost basis inferred from account names must be present first.

- **journalTagCostsAndEquityAndMaybeInferCosts(1st) → journalBalanceTransactions**
  The balancer needs to know which costs are redundant (equity-paired) to ignore them.

- **journalTagGainPostings → journalAddAutoPostings**
  Auto postings do a preliminary balancing pass, which must set aside any
  user-written gain postings just as the main pass does.

- **journalInferPostingsTransactedCost → journalBalanceTransactions**
  The balancer needs transacted costs to correctly infer missing amounts
  (e.g., infer `-$500` for cash, not `-10 AAPL {$50}`).

- **journalBalanceTransactions → journalPostingsAddCommodityTags**
  Balancing may infer missing posting amounts, changing their commodity from `AUTO` to a
  real commodity. Commodity tag propagation should see the real commodity so it can
  add the right tags. (In practice this is a soft constraint: `journalInferPostingsCostBasis`
  reads `jdeclaredcommoditytags` directly rather than relying on commodity tags in `ptags`.)

- **journalClassifyLotPostings → journalCalculateLots**
  Lot calculation reads `_ptype` tags to identify acquire/dispose/transfer postings.

- **journalCalculateLots → journalCheckAcquireBasis**
  The check needs the cost basis populated by lot calculation (eg from a lot
  subaccount name) before comparing it to the transacted cost.

- **journalCheckAcquireBasis → journalAddOrCheckGainPostings**
  When an acquire posting has B ≠ T, we want the structural error to surface
  before any gain-specific diagnostic (the gain amount would be
  meaningless given the imbalance).

### Design decisions

- **Acquisitions on lotful commodities are detected without explicit `{}`.**
  Classification identifies positive lotful postings as acquire even without cost basis
  annotation, symmetrically with bare dispose detection. Cost basis is inferred from
  transacted cost (explicit or balancer-inferred) at lot calculation time.

- **Balancer-inferred costs prefer the lotful posting.**
  When `transactionInferBalancingCosts` infers a cost for a two-commodity transaction,
  it attaches the cost to the posting whose commodity is in `lotful_commodities_`
  (from `BalancingOpts`), if exactly one of the two is lotful. Otherwise it uses
  the first commodity in posting order. This ensures bare lotful postings get
  a transacted cost for lot calculation regardless of posting order.

- **Classification before balancing resolves the poriginal conflict.**
  Since `_ptype` tags are added before the balancer sets `poriginal`, the tags are
  naturally preserved in `poriginal` and visible in `print --verbose-tags` output.

## Key fields on Amount

These fields are central to the inference pipeline:

- **acost** — transacted cost (`@ $50` or `@@ $500`). Used by balancer, equity tagging.
  Sources: parsed from journal, inferred by balancer,
  inferred from equity postings (--infer-costs),
  inferred from cost basis.

- **acostbasis** — lot cost basis (`{$50}` or `{2024-01-15, "lot1", $50}`).
  Sources: parsed from journal (explicit `{}` required for lot tracking);
  also set by `journalCalculateLots` for bare disposals on lotful commodities.
  Used by lot posting classification and lot calculation.

These two fields are sometimes both present on the same amount (both explicit, or one inferred).
`journalInferPostingsTransactedCost` and `transactionInferBalancingCosts` may infer
`acost` from `acostbasis` or from counterpostings, so in later steps you cannot assume
that the presence of `acost` means the user wrote `@ $X`.

## Key fields on Posting

- **ptags** — all tags (user-written + inherited from account/commodity + hidden computed tags).
  Tags are added by: account tag propagation, commodity tag propagation, equity tagging,
  lot classification (`_ptype`), auto posting generation (`_generated-posting`).

- **poriginal** — snapshot of the posting before amount/cost inference, used by `print`
  to show journal entries close to how they were written. Set by: `transactionInferBalancingCosts`,
  `transactionInferBalancingAmount`, balance assignment processing,
  `postingInferTransactedCost`, `processDisposePosting` (bare disposals).
  Since classification runs before these steps,
  `_ptype` tags are naturally included in `poriginal`.

## Conditional steps

Several steps only run with specific flags:

| Step                                   | Enabled when                                                    |
|----------------------------------------|-----------------------------------------------------------------|
| journalAddForecast                     | `--forecast`                                                    |
| journalAddAutoPostings                 | `--auto`                                                        |
| journalTagCostsAndEquity (2nd)         | `--infer-costs`                                                 |
| journalInferEquityFromCosts            | `--infer-equity`                                                |
| journalInferBasisFromAccountNames      | always; lenient (skips its errors) with `--ignore-lots`/`-I`, unless restored by `--strict` or `hledger check lots` |
| journalTagGainPostings                 | always; lenient, as above                                       |
| journalClassifyLotPostings             | default; skipped by `--ignore-lots`/`-I`; restored by `--strict` or `hledger check lots` |
| journalCheckLotsTagValues              | same                                                            |
| journalCheckLotsMethodCoherence        | same                                                            |
| journalCalculateLots                   | same                                                            |
| journalCheckAcquireBasis               | only when `hledger check basis` is requested                    |
| journalAddOrCheckGainPostings          | same as the other gated lot stages above                        |

The gated lot stages share a single `checklots` condition, mirroring
the `checkassertions` mechanism:

```haskell
checklots = not ignore_lots_ || strict_ || checking "lots"
```

where `checking "lots"` peeks at `progArgs` for a literal `check lots` invocation.
When `checklots` is off, the pre-balancing lot stages run in lenient mode
(skipping their errors) rather than being skipped, and the transaction balancer
relaxes its lot quantity mismatch veto (`lenient_lots_` in BalancingOpts),
so that --ignore-lots silences lot errors without introducing new ones
(see SPEC-lots.md "Lots mode").

The `--lots` flag is a separate display-time toggle that controls whether reports
show the full lot detail or a collapsed view (via `journalCollapseLotDetail` in the
report-loading layer); it does not gate any pipeline step.
