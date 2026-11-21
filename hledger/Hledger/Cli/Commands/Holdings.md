## holdings

Show a report of investment holdings.

```flags
Flags:
  -l --flat                 list/tree mode: show accounts as a flat list
                            (default). Amounts exclude subaccount amounts,
                            except where the account is depth-clipped.
  -t --tree                 list/tree mode: show accounts as a tree. Amounts
                            include subaccount amounts.
     --no-elide             in tree mode, don't squash boring parent
                            accounts; in list mode, also show parent accounts
                            (usually zero, hidden without -E)
     --full-names           in tree mode, show full account names instead of
                            indented leaf names
     --drop=N               omit N leading account name parts; in tree mode,
                            remove the first N levels
  -S --sort-amount          sort by value (or cost) instead of account name,
                            largest first
  -N --no-total             omit the final total row
     --change               show gains during the report period, or with a
                            report interval, during each period (default with a
                            start date and no interval)
     --cumulative           with a report interval, show gains from the
                            report start date to each period's end
  -H --historical           show gains since acquisition, ignoring the report
                            start date (default with a report interval)
     --round=TYPE           how much rounding or padding should be done when
                            displaying amounts ?
                            none - show original decimal digits
                            soft - just add or remove decimal zeros
                                   to match precision
                            hard - round amounts to precision (default)
                            all  - also round cost amounts to precision
     --chart[=SCALE]        show a chart: instead of the table (txt), above
                            it (html), or as data (csv, tsv, json). SCALE: the
                            amount that fills the chart (eg 1000 or 1000 USD;
                            one per commodity), for comparable charts.
  -w --width=N              with --chart: draw the chart N characters wide
                            (default: the terminal width)
  -O --output-format=FMT    select the output format. Supported formats:
                            txt, csv, tsv, html, fods, json, svg.
  -o --output-file=FILE     write output to FILE. A file extension matching
                            one of the above formats selects that format.
     --view                 write output to FILE, or to view.FMT in hledger's
                            cache directory, and open it in the system's
                            default viewer for its format (eg a web browser for
                            html). The default format is html.
```


This command shows your lot-tracked assets (see [Lots and capital gains](#lots-and-capital-gains)), and their performance, as of the report end date.
An example:

```cli
$ hledger holdings -e 2023-04-02
Holdings on 2023-04-01

                           ||       Date   Age    Units  Avg cost  Unit price  Total cost  Total value  Weight        UGain   UGain%     RGain     XIRR 
===========================++===========================================================================================================================
 assets:investments:stocks || 2022-04-07  359d  10 INFY    2.00 ₹    100.00 ₹     20.00 ₹   1,000.00 ₹    6.4%     980.00 ₹  4900.0%            5252.4% 
 assets:investments:stocks ||                   73 LTTS    4.79 ₹    200.00 ₹    350.00 ₹  14,600.00 ₹   93.6%  14,250.00 ₹  4071.4%  140.00 ₹  4290.2% 
---------------------------++---------------------------------------------------------------------------------------------------------------------------
                           ||                                                    370.00 ₹  15,600.00 ₹  100.0%  15,230.00 ₹  4116.2%  140.00 ₹  4342.1% 
```

With `--lots`, the individual lots are shown:
```cli
$ hledger holdings --lots -e 2023-04-02
Holdings on 2023-04-01

                                                         ||       Date   Age    Units  Unit cost  Unit price  Total cost  Total value  Weight        UGain   UGain%     RGain     XIRR 
=========================================================++============================================================================================================================
 assets:investments:stocks:{2022-04-06, "0002", 10.00 ₹} || 2022-04-06  360d  13 LTTS    10.00 ₹    200.00 ₹    130.00 ₹   2,600.00 ₹   16.7%   2,470.00 ₹  1900.0%  140.00 ₹  3876.1% 
 assets:investments:stocks:{2022-04-07, 2.00 ₹}          || 2022-04-07  359d  10 INFY     2.00 ₹    100.00 ₹     20.00 ₹   1,000.00 ₹    6.4%     980.00 ₹  4900.0%            5252.4% 
 assets:investments:stocks:{2022-05-06, "0002", 11.00 ₹} || 2022-05-06  330d  20 LTTS    11.00 ₹    200.00 ₹    220.00 ₹   4,000.00 ₹   25.6%   3,780.00 ₹  1718.2%            5032.7% 
 assets:investments:stocks:{2022-06-06, "0002", 0.00 ₹}  || 2022-06-06  299d  40 LTTS          0    200.00 ₹           0   8,000.00 ₹   51.3%   8,000.00 ₹                             
---------------------------------------------------------++----------------------------------------------------------------------------------------------------------------------------
                                                         ||                                                     370.00 ₹  15,600.00 ₹  100.0%  15,230.00 ₹  4116.2%  140.00 ₹  4342.1% 
```

The columns show:

- each holding's acquisition date (or earlier basis date) and age
- the number of units held
- the unit cost basis (Unit cost; or Avg cost, the average unit cost of several lots, or for accounts using the AVERAGE method, the pool's running average on the report date)
- the unit market price on the report date (Unit price)
- the total cost basis (Total cost)
- the total market value (Total value)
- the percentage of the portfolio's total value (Weight).
  A holding with no market price has no Weight and isn't counted in that total, so the others' weights are a little overstated.
  No weights are shown if the holdings are valued in more than one commodity.
- the unrealised gain and gain percent (UGain, UGain%)
- the realised gain from disposals so far (RGain)
- and the annualised rate of return, as of the report end date (XIRR, calculated from the holding's dated cashflows and current value, like roi's IRR; it includes realised gains).
  Lots received without a transacted cost (eg transferred from another account) count as invested at their cost basis on their acquisition date.

Fully disposed commodities and accounts are not shown, unless you add `-E/--empty`.
(But the totals row's RGain and XIRR always include them.)

To see a commodity's performance, a market price should be declared for it (as of the report end date).
Market prices come from [P directives](#p-directive) or (with `--infer-market-prices`) from transacted prices, as usual. 
Each lot is valued in its cost commodity.
In a multi-currency portfolio, aggregated values may contain multiple currencies; use `-X COMM` for a single-currency view.

With `-V`, `-X COMM` or `--value` ([Valuation](#valuation)), holdings
are valued in the default or given valuation commodity instead, and the
cost columns are also converted to it (at the valuation date, so percent
gain is unaffected). Cashflows are not converted, however, so the XIRR
column is left blank for holdings whose cashflows are in a different commodity.
`--value=then` is not supported, and `-B/--cost` doesn't change the report (but see `balance:` below).

Amounts are displayed with their commodity's display precision.
`--round` can select another rounding strategy.
The percent columns (Weight, UGain%, XIRR) are shown with the display style configured for the `%` commodity (eg by `-c '0.00 %'`).

Query arguments and report flags like `--depth`, `-S/--sort-amount`, `--title` etc. work as usual.
[`balance:` and `change:`](#balance-and-change-queries) query terms test each line (one commodity in one account).
A line has two amounts, its units and its Total value, and the term's commodity symbol selects which is tested:

- `holdings balance:'>100'` - holdings of more than 100 units (with no symbol, units are tested)
- `holdings balance:'>100 AAPL'` - holdings of more than 100 AAPL
- `holdings balance:'>$1000'` - holdings worth more than $1000. Lines with no market price have no value, and don't match.
- `holdings -B balance:'>$1000'` - holdings which cost more than $1000 (with `-B`, Total cost is tested instead of Total value)

`change:` tests the line's change in units during the report period (so it needs a start date, eg `-b`),
or with the value's commodity symbol, the value of that change at the valuation date.
Unlike in other reports, `-V`/`-X` don't change which amount is tested; to test the value, write its commodity symbol.
But as in other reports, `-B` tests cost: the line's Total cost, or the cost of its change, instead of their value.
The totals and tree mode's account headings then cover just the lines shown.
But Weight is still each line's share of all the holdings, including the hidden ones
(so the total Weight shows what share the lines shown make up).

With `-t/--tree`, holdings are grouped into account sections:
an account with subaccounts or several commodities becomes a heading row,
showing its subtree's totals computed like the totals row,
with its own holdings beneath it named by their commodity;
an account holding one commodity with no subaccounts is a single combined row;
and with `--lots`, each holding's lots appear beneath it.
Boring parent accounts are squashed into their child as usual
(considering only accounts with holdings), unless `--no-elide` is used.

With `-O html`, an HTML table is produced instead.
With `-O fods`, a spreadsheet document readable by LibreOffice etc. is produced.
With `-O csv` or `-O tsv`, machine-readable output is produced:
one record per holding (or lot, with `--lots`), with full account names,
age in days, bare units and gain percent numbers, and no totals or
tree-mode heading records.
With `-O json`, a JSON array of holding objects is produced.
In both, the cost and value fields are named
`unitcost`, `unitprice`, `totalcost` and `totalvalue`.

### Gains during a period

Normally the gain columns show each holding's gains since it was acquired.
With a report start date (eg `-b`, `-p`, or `date:`), they show the gains during the report period instead,
and the report title says so (eg "gains in 2026-11"):

```cli
$ hledger holdings -p today           # today's gains
$ hledger holdings -p thisyear        # this year's gains so far
$ hledger holdings -b 2026-10-01      # gains since a date (until today)
$ hledger holdings -p 2026-q3         # gains in a past period (the report shows holdings at its end)
```

The units, cost, price, value and Weight columns are unchanged; they show holdings as of the report end date. But:

- UGain is the change in unrealised gain during the period:
  the unrealised gain at the end, minus that on the day before the start date.
  (Note that selling realises gains: UGain decreases and RGain increases.)
- UGain% is that as a percentage of the holding's value on the day before the start date, plus the net cost added since.
- RGain is the realised gain from disposals during the period.
- XIRR is the annualised rate of return for the period, counting the value on the day before the start date as invested then.
  For a short period this can be a very large number (or blank, when too large to calculate); UGain% shows the period's un-annualised gain.

The start date is the first day of the period, so gains are measured from the previous day's closing prices:
`-p today` shows today's gains (today's market prices compared with the latest ones before today),
and `-b yesterday` shows yesterday's and today's.
This way consecutive periods' gains add up, and a month's gains start from the previous month's last prices, as in a broker's statement.
If a market price is missing at the start or the end, the gains depending on it are left blank.
With `-E`, holdings fully disposed during the period are shown too.

A report start date before your first acquisition gives the same gains as no start date.
`-H/--historical` shows the gains since acquisition despite a start date.
(With a report interval, gains are since acquisition unless you ask otherwise; see below.)

### Holdings over time

With a [report interval](#report-intervals) (eg `-M`, `-Q`, `-Y`), holdings shows how your holdings changed:
their totals at the end of each period, each computed as on that date
(eg valued at its market prices).
When the holdings are all of one commodity (eg with a `cur:` query), their Units, Avg cost and Unit price are shown too.

The gain columns' period is selected as in other periodic reports ([accumulation mode](#accumulation-mode)):

- `-H/--historical` (the default): gains since acquisition, up to each period's end
- `--change`: gains during each period, as in a single-date report of that period ([above](#gains-during-a-period));
  these add up: the periods' UGain and RGain sum to those of the whole report period
- `--cumulative`: gains from the report start date up to each period's end.

With no end date, the periods continue up to today, even after your last transaction (since values change with market prices),
and the current period's row shows today's holdings, like the report without an interval.
List/tree mode and `--lots` make no difference to these totals, and are ignored.
With `-O csv`, `tsv` or `json`, there is one record per period end.

```cli
$ hledger holdings -M -e 2026-04-01
Holdings at period ends, 2026-01-31..2026-03-31

            ||  Units  Avg cost  Unit price  Total cost  Total value  UGain  UGain%  RGain     XIRR 
============++======================================================================================
 2026-01-31 || 10 AAA       $10         $12        $100         $120    $20   20.0%          820.5% 
 2026-02-28 ||  6 AAA       $10         $15         $60          $90    $30   50.0%    $20  1566.4% 
 2026-03-31 ||  6 AAA       $10          $9         $60          $54    $-6  -10.0%    $20   108.0% 
```

### Holdings charts

With `--chart`, holdings are shown as a chart: a bar for each holding (or lot, with `--lots`), labelled by account and commodity.
A holding's bar shows its cost basis, and its unrealised gain stacked on top, reaching its market value (which is shown);
or if it has lost value, the part of its cost basis it is still worth, and the part lost (hatched), reaching its cost basis.
Where a bar doesn't end at the market value, as when a holding has lost value, the value is also marked across it (`┃`);
graphical charts then mark the values across all the bars.
In graphical charts these are coloured like assets (blue), revenues (green) and expenses (red).
Each bar's unrealised gain percent is shown after its value, in green if positive or red if negative (in graphical charts, above the bar, since the axis shows the values).
A holding without a market price is shown as its cost basis, in grey.
There is a chart panel for each commodity the holdings are valued in; use `-X COMM` to see them all in one.
With a report interval, there is a bar for each period end instead, showing all the holdings then:
their total cost basis, and their net unrealised gain or loss.
With [SVG output](#svg-output) (eg `-o holdings.svg`, or `--view`) it is a graphical chart,
and with HTML output it is shown above the report's table. See [Charts](#charts) for more.

```cli
$ hledger holdings --chart -w 70
Holdings on 2024-12-31

USD
█ Cost  ▒ Unrealised gain  ╱ Unrealised loss  ▓ No market price
┃ Value

assets:broker AAPL  2,500.00 USD  +66.7%  █████████████████▒▒▒▒▒▒▒▒▒▒▒
assets:broker NEW                         ▓
assets:broker XYZ     450.00 USD  -40.0%  ████┃╱╱╱
```
