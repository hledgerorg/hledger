# Rules for detecting special postings

Here's an overview of ways hledger infers things based on certain configurations of postings.

## 1. journalClassifyLotPostings (Lots.hs)

Detects lot-related postings and tags them with _ptype. Classifications:

| Pattern                | Tag                                    | Conditions                                                                                                                                                                                                                                            |
|------------------------|----------------------------------------|-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| acquire                | _ptype:acquire                         | Positive amount + cost basis {}; OR positive lotful amount (commodity/account has lots: tag)                                                                                                                                                           |
| dispose                | _ptype:dispose                         | Negative amount + cost basis; OR negative lotful amount, with no opposite-sign counterpart in a different account                                                                                                                                      |
| transfer-from          | _ptype:transfer-from                   | Negative amount + cost basis (or lotful), AND a matching positive counterpart in a different account with same commodity and exact quantity; OR negative lotful amount with no transacted price and an equity counterpart posting (equity transfer)     |
| transfer-to            | _ptype:transfer-to                     | Positive amount + cost basis with matching negative counterpart; OR positive lotful amount with no @ cost and a matching transfer-from counterpart; OR bare positive asset posting with a matching transfer-from counterpart; OR positive lot posting with an equity counterpart (equity transfer, e.g. opening balances from close --clopen --lots) |
| gain                   | _ptype:gain                            | Posting to a Gain-type account                                                                                                                                                                                                                        |
| short position         | _ptype:acquire / dispose / transfer-from / transfer-to | In a Liability-typed account the signs above are reversed: a negative lotful or cost-basis amount is an acquire (a short sale), a positive one a dispose (a cover); with no price and an equity counterpart, transfer-from (positive) or transfer-to (negative). Liability postings are never transfer counterparts (see SPEC-lots "Short positions") |
| same-account transfer  | _ptype:transfer-from / transfer-to     | Within the same account, positive and negative postings with the same commodity and exact absolute quantity are paired as transfers                                                                                                                     |

Detection is per-transaction. Transfer detection uses precomputed maps keyed by (commodity, |quantity|) for O(n) matching.

---

## 2. journalTagCostsAndEquityAndMaybeInferCosts (Journal.hs → Transaction.hs)

Detects equity conversion postings and corresponding costful postings. Called twice in the pipeline (before balancing with addcosts=False to detect,
after with addcosts=True to add costs when --infer-costs).

| Pattern                                  | Tag                 | Conditions                                                                                                                                        |
|------------------------------------------|---------------------|---------------------------------------------------------------------------------------------------------------------------------------------------|
| conversion posting pair                  | _conversion-posting | Two adjacent postings to accounts declared as Conversion type (type V), each with a single-commodity amount and no cost                           |
| costful posting matching conversions     | _cost-posting       | A non-conversion posting whose amount matches -ca1 and whose cost matches ca2 (or vice versa), where ca1/ca2 are the conversion pair amounts      |
| costless posting matching conversions    | _cost-posting       | (When no costful match exists) A costless single-commodity posting whose amount matches -ca1 or -ca2; must be unambiguous (no other costless posting with the same amount) |

In addcosts=True mode, the matched costless posting also gets a TotalCost added.

The _cost-posting tag causes the balancer to strip costs from that posting (preventing double-counting with conversion postings).

---

## 3. journalInferEquityFromCosts (Journal.hs → Transaction.hs → Posting.hs)

Detects costful postings that lack corresponding equity conversion postings:

| Pattern                              | Action                                                                  | Conditions                                                                                                                                   |
|--------------------------------------|-------------------------------------------------------------------------|----------------------------------------------------------------------------------------------------------------------------------------------|
| costful posting without conversions  | Generates a pair of _conversion-posting + _generated-posting tagged postings | Posting has cost amounts (@ or @@) AND is NOT already tagged _cost-posting (i.e., not already matched to existing conversion postings)   |

For each cost amount, two conversion postings are generated under \<equityAcct\>:\<sorted-commodities\>: with amounts that offset the cost.
Their amounts are rounded to the entry's precision, except in an entry with an _imbalance-posting (see 4), where they keep the exact cost.

---

## 4. transactionMaybeAddImbalancePostings (Balancing.hs), with --infer-imbalance

Run on each transaction when the balancer has balanced it (in either of journalBalanceTransactionsHelper's passes; not in balanceSingleTransaction, so not by `add`).

| Pattern                              | Action                                                                  | Conditions                                                                                                                                   |
|--------------------------------------|-------------------------------------------------------------------------|----------------------------------------------------------------------------------------------------------------------------------------------|
| balanced entry with a tolerated imbalance | Generates _imbalance-posting + _generated-posting tagged postings to the imbalance account, one per commodity of the imbalance | The real postings' (or balanced virtual postings') sum at cost, as calculated by transactionCheckBalanced, would not display as zero (shown in full, or with 8 decimal places if a repeating decimal; see amountSetFullPrecisionUpTo), so leftovers of hledger's own division are ignored |

The imbalance account is chosen by journalAccountForType: the first account declared with type M/Imbalance, else the alphabetically first account inferred as M (eg equity:imbalance), else equity:imbalance.
The generated postings have amountless originals (like inferred amounts), so they don't influence commodity display precisions.
In pass 2 (entries with balance assignments) their amounts are also added to the running balances, so balance assertions see them.

---

## Summary of all hidden tags used

| Tag                  | Set by                                                                | Meaning                                                |
|----------------------|-----------------------------------------------------------------------|--------------------------------------------------------|
| _ptype:acquire       | journalClassifyLotPostings                                            | Lot acquisition                                        |
| _ptype:dispose       | journalClassifyLotPostings                                            | Lot disposal                                           |
| _ptype:transfer-from | journalClassifyLotPostings                                            | Lot transfer source                                    |
| _ptype:transfer-to   | journalClassifyLotPostings                                            | Lot transfer destination                               |
| _ptype:gain          | transactionTagGainPostings / journalAddOrCheckGainPostings            | Realised-gain posting in a disposal (user-written, or generated); set aside by the balancer |
| _cost-posting        | journalTagCostsAndEquityAndMaybeInferCosts / journalInferEquityFromCosts | Has (or could have) cost matching conversion postings |
| _conversion-posting  | journalTagCostsAndEquityAndMaybeInferCosts / journalInferEquityFromCosts | Equity conversion posting                             |
| _imbalance-posting   | transactionMaybeAddImbalancePostings (--infer-imbalance)              | Posting to the imbalance account showing a transaction's tolerated imbalance |
| _generated-posting   | journalInferEquityFromCosts / journalAddOrCheckGainPostings / transactionAutoSplitFeeOutflows / preserveParentAssertion / transactionMaybeAddImbalancePostings | Machine-generated posting                              |
| _feesplit-posting    | transactionAutoSplitFeeOutflows                                       | Fee fragment split off a lot transfer's sending posting; hidden by print unless --lots or priced |
| _lotsplit-posting    | processDisposePosting / processTransferGroup                          | Extra fragment of a posting split across several lots; merged back unless --lots |
| _lot-parent-assertion | preserveParentAssertion                                              | Zero-amount posting on the parent account, carrying a balance assertion moved from a posting split into lot subaccounts |
