{-|
This is the root of the @hledger-lib@ package and the @Hledger.*@ module hierarchy.
hledger-lib is the core engine used by various hledger UIs and tools,
providing the main data types, file format parsers, reporting logic, and utilities.

SPDX-License-Identifier: GPL-3.0-or-later
Copyright (c) 2007-2025 (each year in this range) Simon Michael <simon@joyful.com> and contributors.

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY;
without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
See the GNU General Public License for more details.
You should have received a copy of the GNU General Public License along with this program.
If not, see <https://www.gnu.org/licenses/>.

-}

module Hledger (
  -- $DOCS
  module X
 ,tests_Hledger
)
where

import           Hledger.Data    as X
import           Hledger.Read    as X
import           Hledger.Reports as X
import           Hledger.Query   as X
import           Hledger.Utils   as X
import           Hledger.Write.Html (tests_Hledger_Write_Html)

tests_Hledger = testGroup "Hledger" [
   tests_Data
  ,tests_Query
  ,tests_Read
  ,tests_Reports
  ,tests_Utils
  ,tests_Hledger_Write_Html
  ]


{- $DOCS

This is also the starting point for hledger's code docs,
aimed at hledger developers and PTA implementors (and curious users).
These are embedded in hledger's source code as Haddock comments and can be viewed
in your code editor,
or in a web browser (eg with @make haddock@),
or (for released versions) on Hackage, eg [hledger-lib:Hledger](https://hackage.haskell.org/package/hledger-lib/docs/Hledger.html).
See also:

- hledger:Hledger.Cli
- hledger-ui:Hledger.UI
- hledger-web:Hledger.Web
- [The README files](https://github.com/search?q=repo%3Asimonmichael%2Fhledger+path%3A**%2FREADME*&type=code&ref=advsearch)
- [The high-level developer docs](https://hledger.org/dev.html)

The rest of this page discusses some general topics.
Together with the hledger manual it describes and provides a functional specification
for hledger and hledger-like apps.
The current code and tests generally conform to this, hopefully.

== Jargon

In addition to the terminology defined in the hledger manual,
eg at [Journal](https://hledger.org/dev/hledger.html#journal):

Here are some words with particular meanings in the context of hledger:

- __/Decimal/__ is a decimal number representation provided by
  the Decimal package, used by hledger for storing numeric quantities.

- __/Normalised decimal/__ A Decimal which has no trailing decimal zeros.
  This can be ensured by the @normaliseDecimal@ function.

- __/Amount/__ ('Amount') is hledger's representation of numeric amounts
  which have a decimal quantity,
  a commodity symbol ('CommoditySymbol'),
  and a display style ('AmountStyle') and display precision ('Precision').
  and optionally a cost in another commodity.

- __/Style/__, __/Amount style/__ An amount's display style, such its decimal mark and symbol placement.
  Represented by "CommodityStyle". (That also stores display precision,
  though it is sometimes convenient to speak of style and precision separately.)

- __/Commodity style/__ The standard display style inferred or specified for a particular commodity.
  Normally all amounts in that commodity are displayed with that style.

- __/Precision/__ In hledger docs, "precision" means the number of decimal digits,
  ie digits to the right of the decimal mark.

- __/Journal precision/__ The number of decimal digits written for an amount
  in the journal file (or in other input data).

- __/Decimal precision/__ The number of decimal digits stored in an Amount's internal Decimal number.
  After parsing, this will be the same as the journal precision; it can increase during amount calculations.

- __/Display precision/__ The preferred number of decimal digits to show in output
  (except by @print@-like reports, which show journal precision by default).

- __/MixedAmount/__ ('MixedAmount') is hledger's representation of a
  multi-commodity amount; it is a set of zero or more Amounts in
  different commodities and costs (stored as a map for efficiency).

- __/amount/__ means either a single-commodity Amount or a multi-commodity MixedAmount,
  depending on context. There are various sources and kinds of amount:

- __/Posting amount/__ An amount being posted (moved from or to) an account.

- __/Cost amount/__ The (cost in a different commodity) associated with a posting amount.
  Eg the purchase cost when buying, or the sale price when selling.
  Cost is recorded in the journal immediately following the posting amount, expressed as a unit or total cost.

- __/Unit cost/__ The cost per unit of the posting amount. Written as @\@ UNITCOST@.

- __/Total cost/__ The total cost the posting amount. Written as @\@\@ TOTALCOST@.

- __/Amount cost/__ A posting amount converted to its cost's commodity. Shown by @hledger print -B@.

    > 2023-01-01
    >    (a)   2 A @ 2 B   ; <- the amount cost is 4 B

    > 2023-01-01
    >    (a)   2 A @@ 2 B   ; <- the amount cost is 2 B

- __/Cost/__ can mean any of the four above depending on context.

- __/Balance assertion \/ assignment amount/__
  An amount written after the posting amount and cost,
  following @=@ or @==@ or @=*@ or @==*@,
  representing a balance assertion
  (or when the posting amount is omitted, a balance assignment).

- __/Balance assertion \/ assignment cost/__
  The unit or total cost of the balance assertion\/assignment amount, if any.
  Written after it in the usual way.

- __/Price/__, __/Market price/__
  A conversion rate\/exchange rate from a particular commodity to another as of a particular date.
  These usually fluctuate over time, and are recorded by @P@ price directives.
  Shown by @hledger prices@.

- __/Price amount/__ The amount written in a @P@ price directive,
  which specifies the destination commodity and the per-unit conversion rate.

- __/Cost vs price/__
  Both of these words are quite slippery in english.
  To simplify, we always say
  "cost" for a conversion rate used in a particular transaction (posting), and
  "price" for conversion rates prevailing in the environment.

- __/Value/__
  Any amount converted to some other commodity using a market price on a certain date.
  Shown by any hledger report when the @-V@, @-X@ or @--value@ option is used.

- __/Real postings/__ Normal account postings, required to balance to zero.

- __/Virtual postings/__ Account postings which are exempt from the normal balance-to-zero requirement.
  Written with parentheses around the account name.
  Can be excluded from reports with the @--real@ flag.

- __/Balanced virtual postings/__ Account postings which are required to balance to zero,
  but separately from the real postings.
  Written with square brackets around the account name.
  Can be excluded from reports with the @--real@ flag.

- __/Transaction balancing/__ The process of inferring amounts and/or costs to balance a transaction,
  both in its real and its balanced virtual postings.

- __/Balancing amount/__ An amount that is inferred to balance a transaction with a missing amount. Shown by @hledger print -x@.

    > 2023-01-01
    >    a   1
    >    b        ; <- a balancing amount of -1 is inferred

- __/Balancing cost/__ A cost that is inferred to balance a transaction involving two commodities. Shown by @hledger print -x@.

    > 2023-01-01
    >    a   1 A  ; <- a balancing cost of @@ 2 B is inferred
    >    b  -2 B

== Precision

As mentioned in Jargon:
"precision" in hledger means the number of digits to the right of the decimal mark.
And, amounts have several precisions we can talk about:

__/Journal precision/__ is the number of decimal digits recorded in the
journal file \/ input data. We accept up to 255 decimal digits there.

__/Decimal precision/__ is the number of decimal digits stored internally in each Decimal value. Decimal supports up to 255 decimal digits.
In amounts just parsed from the journal, this will be the same as their journal precision.
During calculations, amounts' decimal precision may increase, and will not decrease.

__/Display precision/__ is the preferred number of decimal digits to show in report output.
It is represented by 'AmountPrecision', which is currently part of the 'AmountStyle' stored within each Amount.
In amounts just parsed from the journal, this will be the same as the journal and decimal precisions;
later it gets standardised for each commodity's amounts.
When display precision is less than the decimal precision, fewer, rounded decimal digits are displayed ("rounding").
When display precision is greater than the decimal precision, additional decimal zeros are displayed ("padding").

Basically, hledger amounts have two main precisions we care about at runtime:
their internal decimal precision, used for calculation, and their display precision, used for rendering.

== Rounding

__/Internal rounding/__ means rounding (or padding) internal Decimal numbers,
using @amountSetInternalPrecision@ (which uses @Data.Decimal.roundTo@).
Internal rounding loses information so we don't do this much.

__/Display rounding/__ means applying a target display precision to an existing amount.
This can be done more or less forcefully, determined by a "display rounding strategy" ('Rounding').
Currently this too is stored within each Amount's AmountStyle, for convenience,
(though semantically speaking it is not part of the amount).

The rounding strategies are:

- none - leave the amount's display precision unchanged
- soft - add or remove trailing decimal zeros to approximate the target precision, but don't remove significant digits
- hard - use the exact target precision, possibly rounding and hiding significant digits
- all  - do hard rounding of both the main amount and its cost amount (costs are normally not display-rounded).

Broadly, here is when display rounding happens:

1. After reading a journal, when standard commodity styles are applied,
  display precisions are kept unchanged; no rounding is done at this stage (since 1.31).

2. While balancing each transaction,
  its amounts are temporarily hard-rounded to the standard commodity display precisions,
  to provide some configurable tolerance in the balancing calculations.
  (We plan to change this to use transaction-local standard precisions,
  inferred from the transaction's journal precisions only, like Ledger.)

3. Just before output, reports do display rounding according to their needs (since 1.31).
  Most reports do hard display rounding.
  @print@ and other print-like commands do no rounding by default,
  or optionally one of the other rounding strategies.

=== Precision and style handling

hledger supports user-specified precisions from 0 to 255 for each
commodity, and tries to propagate these consistently and intuitively
through all the various processing steps.

This gets rather complicated, so we keep a summary of the current
precision and style behaviours here.
This doc should always be kept synced with code.

In Decimal number calculations:

- the result is normalised, meaning any trailing decimal zeros are trimmed.
  So the result 's precision can be larger
  (1 / 2, both with precision 0, is 0.5, with precision 1)
  or smaller
  (2.0 / 1.0, both with precision 1, is normalised to 2, with precision 0).

In amount calculations:

- When amounts are summed (or subtracted), the result has the maximum
  of their decimal precisions, the maximum of their display precisions,
  and the display style of the second amount.

- When an amount is multiplied (or divided) by a pure number,
  the result's decimal precision is that of the decimal result, normalised.
  The display precision and style is kept unchanged.

- When an amount is converted to cost, the new amount's decimal precision
  is that of the cost amount (if it's a total cost),
  or of the cost amount multiplied by the quantity and normalised (if it's a unit cost).
  Its display precision is kept unchanged.
  Its display style is that of the cost amount.

- When an amount is converted to value, the new amount's decimal precision
  is that of the price amount multiplied by the quantity and normalised.
  Its display precision is set to match the decimal precision,
  or to a fallback precision (8) if the decimal appears to be infinite.
  Its display style is its commodity's standard display style.
  If no standard style is known for the commodity (eg because it does not appear in the journal),
  it is given the fallback display style (symbol on the left unspaced, period as decimal mark,
  precision limited to a maximum of 8 digits).

In a run of hledger:

__1. Input__

__1.1. Parsing__

- Each parsed amount initially has decimal precision, display precision,
  and display style set according to how it was written in the journal.

__1.2. Standard styling__

- After all amounts are parsed,
  standard display styles and display precisions are inferred for each commodity
  from its amounts, directives like @commodity@ and @D@, and -c\/--commodity options
  (in 'journalInferCommodityStyles'),
  and these are applied to all amounts and their costs for consistent display
  (in 'journalStyleAmounts').
  No amount display precisions are changed at this stage.

__1.3. Transaction balancing__

- When amounts are summed, the result has the maximum of their
  decimal precisions and the maximum of their display precisions.

- A balancing amount without a cost will have the same precisions as
  the amount (or sum) it is balancing.

- A balancing amount which has a cost will be converted to cost; see
  "When an amount is converted to cost" above.

- When inferring a balancing cost:

    - The "from amount" is the sum of postings in the first-appearing commodity.

    - The "to amount" is the sum of postings in the second-appearing commodity. See "When amounts are summed" above.

    - If the from amount comes from a single posting, it is given a total cost.
      The cost's decimal precision will be that of the to amount divided by the from quantity, normalised. 
      Its display precision and style will be that of the to amount.

    - If the from amount comes from multiple postings, they all are given a unit cost.
      The cost's decimal precision will be that of the to amount divided by the from quantity, normalised. 
      Its display precision will be the sum of the from and to amounts' display precisions, or 2, whichever is greater.
      Its display style will be that of the to amount.

- An amount inferred from a balance assignment will have the same precisions as the balance assignment amount.

__1.4. Determining market prices__

If needed, for a value report:

- Any @P@ price directives form the __/declared prices/__.
  Like posting amounts, their price amounts have been standard-styled
  but their precisions have not yet been changed.

- If the @--infer-market-prices@ flag is used, additional price
  directives are generated from any journal postings with costs
  (in 'amountPriceDirectiveFromCost').
  When the cost was a unit cost, the price amount will have the same precisions.
  When the cost was a total cost,

    - The total cost is divided by the amount quantity to get a unit cost.
    - Its decimal precision becomes that of the decimal result, normalised.
    - Its display precision is set to match the new decimal precision;
      unless the decimal appears to be infinite (because it uses all the 255 digits allowed),
      in which case it is given a smaller fallback display precision (8 decimal digits).

    These plus the declared prices are the __/forward prices/__.

- Additional market prices are generated (as 'MarketPrice' this time, not 'PriceDirective')
  by reversing the forward prices (in 'marketPriceReverse').
  Any new prices generated in this way are the __/reverse prices/__.
  Their decimal precision will be that of (1 \/ the decimal quantity), normalised.
  (They don't have a display precision.)
  These plus the forward prices are the __/direct prices/__
  (giving direct conversion rates from one commodity to another).

And later, if needed:

- For each requested value conversion from commodity A to commodity B,
  if an appropriate price is not found in the direct prices, we try to calculate a __/chained price/__,
  combining two or more direct prices that form a path from A to B.
  The resulting price's decimal precision will be the product of the chained prices, normalised,
  then padded back up to the maximum of their decimal precisions
  (undoing the normalising, because later we will choose the value amount's display precision
   based on the value's decimal precision).

__2. Calculating reports__

- Amounts may be converted to cost (-B), summed, averaged, converted
  to velue (-V\/-X\/--value), etc.  Precisions and styles are affected
  as described in "In amount calculations" above.

__3. Output__

- print-like reports: amounts are displayed with their current display precisions.
  Or with --round, they can be soft- or hard-rounded/padded to the standard commodity precisions.
 
- All other reports: amounts are displayed hard rounded/padded to the standard commodity precisions.

- In the roi report: if there is no standard display precision for the valuation commodity,
  it is limited to a maximum of 8 digits.

== Exports of this module:
-}
