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
`--cost` or `--value` flags (see [VALUATION](https://hledger.org/hledger.html#valuation)).

Note, in some cases this report can fail, for these reasons:

- Error (NotBracketed): No solution for Internal Rate of Return (IRR).
  Possible causes: IRR is huge (>1000000%), balance of investment becomes negative at some point in time.
- Error (SearchFailed): Failed to find solution for Internal Rate of Return (IRR).
  Either search does not converge to a solution, or converges too slowly.
- Error (NotBracketed): Cannot compute window IRR.
  Possible cause: investment balance becomes negative within that window.
- Error (SearchFailed): Window IRR search did not converge.

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

If your journal records [lots](#lot-reporting), each disposal transaction has a
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

hledger computes TWR using the BAI (Bank Administration Institute)
Linked IRR method. The reporting period is divided into windows at
each date where the portfolio has a known, externally-established
valuation - these are dates of price directives or of manual balance
updates recorded via `--pnl` transactions. Within each window, if no
cash flows occurred, the return is simply the ratio of ending to
starting value. If cash flows occurred within a window, the window's
return is found by solving for the rate that reconciles the starting
value, the ending value, and the timing of those flows. All window
returns are then multiplied together (geometrically chained) to give
the TWR for the full period.

The accuracy of TWR depends on how many valuation dates you have
recorded. More valuation dates mean finer windows and more precise
results.

**In short:** TWR tells you how good the investment was; IRR tells you
how good your experience of the investment was.

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
