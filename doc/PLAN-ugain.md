# Plan: optional unrealised-gain (revaluation) postings

## Background

hledger records gains by the historical cost convention (see DECISIONS.md,
"Disposals balance at cost basis"): a disposal gets one realised gain
posting, and unrealised gains are not posted, only reported from market
prices (`holdings`, `--gain`, `-V` vs `-B`).

Earlier (until 2026-09) each disposal also received an
`equity:unrealised-gain` counter posting, intended as the second half of a
mark-to-market scheme in which revaluation postings (`Dr asset /
Cr equity:unrealised-gain`) would accrue unrealised gain as prices move,
and disposal would recycle the disposed lot's accumulated gain to realised.
The revaluation half was never implemented (commit 80b320acc chose not to
generate revaluation postings, to avoid synthetic noise), leaving the
counter posting as a plug that broke the accounting equation (#2731).

## The optional layer

Revaluation postings could still be offered, as an opt-in on top of
historical cost, giving a ledger trail of unrealised gains (inspectable in
`register`, attributable to periods in `is`/`bse`):

```journal
2026-03-01 revalue AAPL at $70          ; generated from a P directive
    equity:unrealised-gain            $-200    ; 10 AAPL x ($70 - $50)
    assets:stocks:revaluation          $200    ; or the lot subaccount itself

2026-03-01 sell some
    assets:stocks    -5 AAPL {$50} @ $70       ; balances at basis: -$250
    assets:cash       $350
    revenues:gain    $-100                     ; realised gain
    equity:unrealised-gain   $100              ; reverse the disposed lot's accumulated revaluation...
    assets:stocks:revaluation  $-100           ; ...and its asset-side write-up
```

Note the two conventions: crediting an equity reserve and recycling it at
disposal (through other comprehensive income), versus crediting
`revenues:unrealised gain` so it hits the income statement each period
(fair value through profit or loss, no recycling). The U account type
suits the former.

## Open design questions

1. Asset-side representation: `$` posted into the lot subaccount (makes
   `bal` show "5 AAPL, $200"), a parallel `assets:...:revaluation` account,
   or a market-value field in the lot model.
2. Trigger: each `P` directive, each transaction with a differing price,
   period boundaries, or on demand at report time.
3. Partial disposals and non-FIFO methods: which fraction of a lot's
   accumulated revaluation to reverse.
4. `-B`/cost reports: with revaluations in asset accounts, "cost" reports
   would show market carrying value unless revaluation accounts are
   excluded.

## Status

Parked. The common need (realised gain at disposal, unrealised gain as a
report) is covered without it. Revisit if users want a posting history of
paper gains, or a tax workflow requires period-end revaluation entries.
