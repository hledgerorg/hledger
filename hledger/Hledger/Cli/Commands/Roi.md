## roi

Show the money-weighted (IRR) and time-weighted (TWR) rate of return
on your investments.

```flags
Flags:
     --cashflow                 show all amounts that were used to compute
                                returns
     --investment=QUERY         query to select your investment transactions
     --profit-loss=QUERY --pnl  query to select profit-and-loss or
                                appreciation/valuation transactions (optional)
```

At a minimum, you need to supply a query (which could be just an
account name) to select your investment(s) with `--inv`.

An optional second query to identify your profit and loss transactions
could be given with `--pnl`. If your investment's value changes are
captured solely through price directives (rather than manual P&L
journal entries), or if you do not need TWR, you can simply omit
`--pnl`, and no transactions will be classed as profit and loss in
this case.

This command will compute and display the internal rate of return
(IRR, also known as money-weighted rate of return) and time-weighted
rate of return (TWR) for your investments for the time period
requested. IRR is always annualized due to the way it is computed, but
TWR is reported both as a rate over the chosen reporting period and as
an annual rate.

Price directives will be taken into account if you supply appropriate
`--cost` or `--value` flags (see [Value reporting](https://hledger.org/hledger.html#value-reporting)).

Note, in some cases this report can fail, for these reasons:

- Error (NotBracketed): No solution for Internal Rate of Return (IRR).
  Possible causes: IRR is huge (>1000000%), balance of investment becomes negative at some point in time.
- Error (SearchFailed): Failed to find solution for Internal Rate of Return (IRR).
  Either search does not converge to a solution, or converges too slowly.
- Error: Cannot compute the time-weighted return for DATES (PART): the investment's value at the start (...) plus
  deposits (...) is negative.
  Possible cause: the balance of the investment becomes negative, eg more is sold than is held (a short position).
- Error: Could not value the investment on DATE: no market price ... is known for COMMODITY on or before that date.
  A holding has no market price, and none of the investment's transactions on or before that date records a price
  for buying or selling it. Add a P directive for it, or record the price of its purchase.

Examples:

- Using roi to compute total return of investment in stocks:
  <https://github.com/hledgerorg/hledger/blob/main/examples/investing/roi-unrealised.ledger>

- Cookbook > Return on Investment: 
  <https://hledger.org/roi.html>

### Spaces and special characters in `--inv` and `--pnl`

Note that `--inv` and `--pnl`'s argument is a query, and queries could have several space-separated terms (see [QUERIES](https://hledger.org/hledger.html#queries)).

To indicate that all search terms form single command-line argument, you will need to put them in quotes (see [Special characters](https://hledger.org/hledger.html#special-characters)):

```cli
$ hledger roi --inv 'term1 term2 term3 ...'
```

If any query terms contain spaces themselves, you will need an extra level of nested quoting, eg:

```cli
$ hledger roi --inv="'Assets:Test 1' cur:USD" --pnl="'Equity:Unrealized Profit and Loss'"
```

### Semantics of `--inv` and `--pnl`

Query supplied to `--inv` has to match all transactions that are
related to your investment. Transactions not matching `--inv` will be
ignored.

In these transactions, ROI will consider postings that match `--inv` to
be "investment postings" and other postings (not matching `--inv`)
will be sorted into two categories: "cash flow" and "profit and loss",
as ROI needs to know which part of the investment value is your
contributions and which is due to the return on investment.


- "Cash flow" is depositing or withdrawing money, buying or selling
assets, or otherwise converting between your investment commodity and
any other commodity. Example:

    ```journal
    2019-01-01 Investing in Snake Oil
      assets:cash          -$100
      investment:snake oil

    2020-01-01 Selling my Snake Oil
      assets:cash           $10
      investment:snake oil  = 0
    ```

- "Profit and loss" is change in the value of your investment:

    ```journal
    2019-06-01 Snake Oil falls in value
      investment:snake oil  = $57
      equity:unrealized profit or loss
    ```

All non-investment postings are assumed to be "cash flow", unless they
match `--pnl` query. Changes in value of your investment due to
"profit and loss" postings will be considered as part of your
investment return.

The amount of each cash flow is measured from the investment's
perspective: it is the cost of the transaction's investment postings,
minus any profit and loss in that transaction. Its date is the date of
those investment postings, even if the money's posting has a different
date (eg a settlement date). This means that other postings in the same
transaction, such as fees, don't change the amount of the cash flow.

In this example, the investment receives $100, so without `--pnl` the
cash flow is a $100 deposit, and the $1 fee is not part of the
investment at all. With `--pnl expenses`, the fee counts as part of the
investment's return instead: the cash flow is a $101 deposit, of which
$1 is immediately lost (shown as profit/loss of -$1):

```journal
2019-01-01 Buying Snake Oil, with a fee
  assets:cash          -$101
  expenses:fees           $1
  investment:snake oil  $100
```

Example: if you use `--inv snake --pnl equity:unrealized`, then
postings in the example below would be classifed as:

```journal
2019-01-01 Snake Oil #1
  assets:cash          -$100   ; cash flow posting
  investment:snake oil         ; investment posting

2019-03-01 Snake Oil #2
  equity:unrealized pnl  -$100 ; profit and loss posting
  snake oil                    ; investment posting

2019-07-01 Snake Oil #3
  equity:unrealized pnl        ; profit and loss posting
  cash          -$100          ; cash flow posting
  snake oil     $50            ; investment posting
```

### Using roi with lots

If your journal records [lots](#lots-and-capital-gains), each disposal transaction has a
realised gain posting, by default to `revenues:gain`. Make sure `--pnl`
matches that account, eg `--pnl revenues:gain`, so realised gains are
counted as profit rather than as cash flows out of the investment.

### IRR and TWR explained

"ROI" stands for "return on investment". Traditionally this was
computed as a difference between current value of investment and its
initial value, expressed in percentage of the initial value.

However, this approach is only practical in simple cases, where the
investment receives no in-flows or out-flows of money and the rate of
growth is fixed over time. For more complex scenarios you need
different ways to compute rate of return, and this command implements
two of them: IRR and TWR.

**Internal rate of return (IRR)**, also called money-weighted rate of
return, answers the question: *what single constant annual interest
rate, applied to your actual sequence of deposits and withdrawals,
would produce exactly the ending balance you have?*

IRR is inherently personal. If you deposited a large sum right before
a bad period, your IRR is dragged down - not because the investment
was poorly managed, but because your timing was bad. Conversely,
investing heavily just before a rally makes your IRR look great. This
is what makes IRR "money-weighted": periods when more of your money is
at stake contribute more to the result.

In technical terms, IRR uses the same approach as computation of net
present value, and tries to find a discount rate that makes the net
present value of all the cash flows of your investment add up to zero.
The implementation in hledger produces results that match the `=XIRR`
formula in Excel.

**Time-weighted rate of return (TWR)** strips out the effect of your
deposit and withdrawal timing, measuring the investment's own
performance rather than your experience of it.

hledger computes TWR from the value of your investment at the end of
each day: its balance at the end of the day, valued (with `--value`)
using the prices in effect on that day. The order of transactions and
prices within a day doesn't matter.

- The days between two days with cash flows form one stretch, which
  starts at the end of the earlier cash flow day and ends at the end of
  the day before the later one. Its return is the ratio of the
  investment's values at those two moments. For example, with cash
  flows on March 1 and March 10, the stretch is March 2 to 9, and its
  return is (value at the end of March 9) / (value at the end of March
  1) - 1. (March 10 itself is a day with cash flows, handled as below.)
- A day with cash flows is split in two parts:
  1. The day's price changes: the return of the holdings carried over
     from the previous day, from their value at the previous day's prices
     to their value at this day's prices. (This part is skipped if no
     prices changed.)
  2. The cash flows, as if all of the day's trades were made at the
     day's closing prices. Its return is (value at the end of the day -
     withdrawals) / (value after part 1 + deposits) - 1, with withdrawals
     negative. That is, the day's deposits count as invested during this
     part, as if made at its start, and its withdrawals count as still
     invested during it, as if made at its end. So any difference between
     the prices you traded at and the closing prices shows up in this
     part's return.
- Times when nothing is invested earn nothing. That includes a day on
  which something arrives in an empty investment only as profit and loss
  (eg a stock grant, booked to an account matched by `--pnl`): there is
  nothing to compute a return on, so that day's return is 0%.
- A holding which has no market price is valued at the price of the
  investment's latest purchase or sale of it, on or before that day (as
  `--infer-market-prices` would do, but only from the investment's own
  transactions, and only while no market price is known). If there are
  several on a day, the last one recorded is used. Like any price, it
  applies to the whole holding on that day, including what was held
  before the trade, so a trade at a new price can show up in `--cashflow`
  output as a "prices" row, before its cash flows. And a trade recorded
  at zero cost (eg a gift, recorded with `@ $0`) gives a price of 0, so
  such a holding is worth nothing until a market price is known; add a
  P directive for it.

All these returns are then multiplied together (geometrically chained)
to give the TWR for the full period. In multi-period reports, each
period begins with the value the previous one ended with, so the
periods' returns chain to the total.

Use `--value=then` for TWR, so that each day is valued with the prices
of that day. With `--value=end`, `--value=now` or `--value=DATE`, all
the values in a period use the same prices, so its TWR only reflects
recorded profit and loss and the differences between the prices you
traded at and those prices. With `--value=end`, each period is also
valued with its own end's prices, so the periods' returns don't chain
to the total.

TWR can only be as good as the values your journal gives for each day.
If you record changes in value only occasionally (with `--pnl`
transactions, or with sparse price directives), the growth since the
previous record is attributed to the day you record it, and so is
counted on whatever was invested on that day. If you made a large
deposit or withdrawal in between, that can make TWR quite different from
what it would be if the growth had been spread out. So record a
valuation around large deposits and withdrawals (professional
performance standards require this too), or use price directives, or
`--infer-market-prices` if your transactions record their prices.

**In short:** TWR tells you how good the investment was; IRR tells you
how good your experience of the investment was.

### Checking the results

`--cashflow` shows everything that IRR and TWR are computed from, so
that you can check them against your journal, against other hledger
reports, or in a spreadsheet:

- **IRR cash flows**: one row per cash flow, with the transaction's
  description, the cost of its investment postings, and its profit or
  loss, between the investment's value at the start and its value at
  the end (dated the day after the period's last day, since it is the
  value at the end of that day). Amounts are from your point of view:
  what you put in is negative, what you take out or still have is
  positive. The dates and amounts can be given to Excel's `=XIRR` as
  they are.

- **TWR returns**: one row for each stretch without cash flows, and for
  each day with cash flows, a row for its price changes (if any) and a
  row for its cash flows. Each row's Value (begin) is the previous
  row's Value (end), and each row's return is

  (Value (end) - Withdrawals) / (Value (begin) + Deposits) - 1

  where withdrawals are negative. The Cumulative column chains the
  returns by multiplication: each row's (1 + Cumulative) is the
  previous row's (1 + Cumulative) times (1 + Return). Its last row is
  the period's TWR.

The values can be checked with `hledger balance`: the value at the end
of a day D is the investment's historical balance at the end of that
day, valued then. For example, with `--value=then,$`:

```cli
$ hledger balance --historical --value=end,$ -e D+1 INVESTMENTQUERY
```

(where `D+1` is the day after D). Holdings which have no market price
are the exception, as `roi` values them at the price of their latest
purchase or sale.

**When each matters**

Use IRR when you want to know your actual personal return - what you
earned on your money, accounting for when you chose to move it. It is
the right measure when evaluating your own deposit and withdrawal
timing decisions.

Use TWR when you want to evaluate the investment vehicle itself,
independent of your deposit timing. It is the right measure when
comparing two funds or strategies, or when asking whether you would
have been better off elsewhere. TWR is the standard that professional
investment managers use to report fund performance, precisely because
it removes the distortion caused by investor cash flows.

References:

* [Explanation of rate of return](https://www.investopedia.com/terms/r/rateofreturn.asp)
* [Explanation of IRR](https://www.investopedia.com/terms/i/irr.asp)
* [Explanation of TWR](https://www.investopedia.com/terms/t/time-weightedror.asp)
* [IRR vs TWR](https://smartasset.com/investing/time-weighted-return)
* [Examples of computing IRR and TWR and discussion of the limitations of both metrics](https://blog.commonwealth.com/measuring-portfolio-performance-twr-vs.-irr)
