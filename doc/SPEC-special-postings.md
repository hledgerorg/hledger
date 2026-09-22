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
| _generated-posting   | journalInferEquityFromCosts / journalAddOrCheckGainPostings           | Machine-generated posting                              |
