## balance

(bal)

Show accounts with some kind of summed numeric data:
balance changes per period, end balances on period end dates, simple capital gains,
budget goal performance, etc.

```flags
Flags:
     --sum                  calculation mode: show sum of posting amounts
                            (default)
     --valuechange          calculation mode: show total change of value of
                            period-end historical balances (caused by deposits,
                            withdrawals, market price fluctuations)
     --gain                 calculation mode: show capital gain/loss
                            (historical balance value minus cost basis, or
                            transacted cost where there is none)
     --budget[=DESCPAT]     calculation mode: show sum of posting amounts
                            together with budget goals defined by periodic
                            transactions. With a DESCPAT argument (must be
                            separated by = not space),
                            use only periodic transactions with matching
                            description
                            (case insensitive substring match).
     --count                calculation mode: show the count of postings
     --change               accumulation mode: accumulate amounts from column
                            start to column end (in multicolumn reports,
                            default)
     --cumulative           accumulation mode: accumulate amounts from report
                            start (specified by e.g. -b/--begin) to column end
  -H --historical           accumulation mode: accumulate amounts from
                            journal start to column end (includes postings
                            before report start date)
  -l --flat                 list/tree mode: show accounts as a flat list
                            (default). Amounts exclude subaccount amounts,
                            except where the account is depth-clipped.
  -t --tree                 list/tree mode: show accounts as a tree. Amounts
                            include subaccount amounts.
     --drop=N               in list mode, omit N leading account name parts
     --declared             include non-parent declared accounts (best used
                            with -E)
  -A --average              show a row average column (in multicolumn
                            reports)
  -T --row-total            show a row total column (in multicolumn reports)
     --summary-only         display only row summaries (e.g. row total,
                            average) (in multicolumn reports)
  -N --no-total             omit the final total row
     --no-elide             in tree mode, don't squash boring parent
                            accounts; in list mode, also show parent accounts
                            (usually zero, hidden without -E)
     --full-names           in tree mode, show full account names instead of
                            indented leaf names
     --format=FORMATSTR     use this custom line format (in simple reports)
  -S --sort-amount          sort by amount instead of account code/name (in
                            flat mode). With multiple columns, sorts by the row
                            total, or by row average if that is displayed.
  -% --percent              express values in percentage of each column's
                            total
  -r --related              show the other accounts transacted with, instead
     --invert               display all amounts with reversed sign
     --transpose            switch rows and columns (use vertical time axis);
                            repeat to cancel
     --layout=ARG           how to lay out multi-commodity amounts and the
                            overall table:
                            'wide[,W]': commodities on same line, up to W wide
                            'tall'    : commodities on separate lines
                            'bare'    : commodity symbols in a separate column
                            'tidy'    : each data field in its own column
     --base-url=URLPREFIX   in html output, generate links to hledger-web,
                            with this prefix. (Usually the base url shown by
                            hledger-web; can also be relative.)
  -O --output-format=FMT    select the output format. Supported formats:
                            txt, html, csv, tsv, json, fods.
  -o --output-file=FILE     write output to FILE. A file extension matching
                            one of the above formats selects that format.
```

`balance` is one of hledger's oldest and most versatile commands,
for listing account balances, balance changes, values, value changes and more,
during one time period or many.
Generally it shows a table, with rows representing accounts, and columns representing periods. 

Note there are some variants of the `balance` command with convenient defaults, which are simpler to use:
[`balancesheet`](#balancesheet),
[`balancesheetequity`](#balancesheetequity),
[`cashflow`](#cashflow) and
[`incomestatement`](#incomestatement). 
When you need more control, then use `balance`. 

### balance features

Here's a quick overview of the `balance` command's features,
followed by more detailed descriptions and examples.
Many of these work with the other balance-like commands as well (`bs`, `cf`, `is`..).

`balance` can show..

- accounts as a [list (`-l`) or a tree (`-t`)](#list-or-tree-mode)
- optionally depth-limited ([`-[1-9]`](#depth-limiting))
- sorted [by declaration order and name](#simple-balance-report),
  or [by amount](#sorting-by-amount)

..and their..

- balance changes (the default)
- or actual and planned balance changes ([`--budget`](#budget-report))
- or value of balance changes ([`-V`](#valuation-mode))
- or change of balance values ([`--valuechange`](#balance-report-modes))
- or capital gain/loss ([`--gain`](#balance-report-modes))
- or balance changes from sibling postings (`--related`/`-r`)
- or postings count ([`--count`](#balance-report-modes))

..in..

- one time period (the whole journal period by default)
- or multiple periods ([`-D`, `-W`, `-M`, `-Q`, `-Y`, `-p INTERVAL`](#report-intervals))

..either..

- per period (the default)
- or accumulated since report start date ([`--cumulative`](#accumulation-mode))
- or accumulated since account creation ([`--historical/-H`](#accumulation-mode))

..possibly converted to..

- cost ([`--value=cost[,COMM]`/`--cost`/`-B`](#valuation-mode))
- or market value, as of transaction dates ([`--value=then[,COMM]`](#valuation-mode))
- or at period ends ([`--value=end[,COMM]`](#valuation-mode))
- or now ([`--value=now`](#valuation-mode))
- or at some other date ([`--value=YYYY-MM-DD`](#valuation-mode))

..with..

- totals ([`-T`](#multi-period-balance-report)), 
  averages ([`-A`](#multi-period-balance-report)), 
  percentages ([`-%`](#percentages)), 
  inverted sign ([`--invert`](#sorting-by-amount))
- rows and columns swapped ([`--transpose`](#multi-period-balance-report))
- another field used as account name ([`--pivot`](#multi-period-balance-report))
- custom-formatted line items (single-period reports only) ([`--format`](#balance-report-line-format))
- commodities displayed on the same line or multiple lines ([`--layout`](#balance-report-layout))

This command supports the
[output destination](#output-destination) and
[output format](#output-format) options,
with output formats `txt`, `csv`, `tsv`, `json`, `html`, and `fods`.
In `txt` output in a colour-supporting terminal, negative amounts are shown in red.

### Simple balance report

With no arguments, `balance` shows a list of all accounts and their
change of balance - ie, the sum of posting amounts, both inflows and
outflows - during the entire period of the journal.
("Simple" here means just one column of numbers, covering a single period.
You can also have multi-period reports, described later.)

For real-world accounts, these numbers will normally be their end balance 
at the end of the journal period; more on this below.

Accounts are sorted by [declaration order](#account-directive)
if any, and then alphabetically by account name.
For instance 
(using [examples/sample.journal](https://github.com/hledgerorg/hledger/blob/main/examples/sample.journal)):

```cli
$ hledger -f examples/sample.journal bal
                  $1  assets:bank:saving
                 $-2  assets:cash
                  $1  expenses:food
                  $1  expenses:supplies
                 $-1  income:gifts
                 $-1  income:salary
                  $1  liabilities:debts
--------------------
                   0  
```

Accounts with a zero balance (and no non-zero subaccounts, in tree
mode - see below) are hidden by default. Use `-E/--empty` to show them
(revealing `assets:bank:checking` here):
 
```cli
$ hledger -f examples/sample.journal bal  -E
                   0  assets:bank:checking
                  $1  assets:bank:saving
                 $-2  assets:cash
                  $1  expenses:food
                  $1  expenses:supplies
                 $-1  income:gifts
                 $-1  income:salary
                  $1  liabilities:debts
--------------------
                   0  
```

The total of the amounts displayed is shown as the last line, unless `-N`/`--no-total` is used.

### Balance report line format

For single-period balance reports displayed in the terminal (only),
you can use `--format FMT` to customise the format and content of each
line. Eg:

```cli
$ hledger -f examples/sample.journal balance --format "%20(account) %12(total)"
              assets          $-1
         bank:saving           $1
                cash          $-2
            expenses           $2
                food           $1
            supplies           $1
              income          $-2
               gifts          $-1
              salary          $-1
   liabilities:debts           $1
---------------------------------
                                0
```

The FMT format string specifies the formatting applied to each account/balance pair.
It may contain any suitable text, with data fields interpolated like so:

`%[MIN][.MAX](FIELDNAME)`

- MIN pads with spaces to at least this width (optional)
- MAX truncates at this width (optional)
- FIELDNAME must be enclosed in parentheses, and can be one of:

    - `depth_spacer` - a number of spaces equal to the account's depth, or if MIN is specified, MIN * depth spaces.
    - `account`      - the account's name
    - `total`        - the account's balance/posted total, right justified

Also, FMT can begin with an optional prefix to control how
multi-commodity amounts are rendered:

- `%_` - render on multiple lines, bottom-aligned (the default)
- `%^` - render on multiple lines, top-aligned
- `%,` - render on one line, comma-separated

There are some quirks. Eg in one-line mode, `%(depth_spacer)` has no
effect, instead `%(account)` has indentation built in.
<!-- XXX retest:
Consistent column widths are not well enforced, causing ragged edges unless you set suitable widths.
Beware of specifying a maximum width; it will clip account names and amounts that are too wide, with no visible indication.
-->
Experimentation may be needed to get pleasing results.

Some example formats:

- `%(total)`         - the account's total
- `%-20.20(account)` - the account's name, left justified, padded to 20 characters and clipped at 20 characters
- `%,%-50(account)  %25(total)` - account name padded to 50 characters, total padded to 20 characters, with multiple commodities rendered on one line
- `%20(total)  %2(depth_spacer)%-(account)` - the default format for the single-column balance report. The total field keeps this 20-character width as a minimum, but widens automatically when displayed amounts need more room.

[valuation]: #valuation
[valuation date(s)]: #valuation-date
[valuation commodity]: #valuation-commodity

### Filtered balance report

You can show fewer accounts, a different time period, totals from
cleared transactions only, etc. by using [query](#queries)
arguments or [options](#report-start--end-date) to limit
the postings being matched. Eg:

```cli
$ hledger -f examples/sample.journal bal --cleared assets date:200806
                 $-2  assets:cash
--------------------
                 $-2  
```

### List or tree mode

By default, or with `-l/--flat`, accounts are shown as a flat list
with their full names visible, as in the examples above.

With `-t/--tree`, the account hierarchy is shown, with subaccounts'
"leaf" names indented below their parent:

```cli
$ hledger -f examples/sample.journal balance
                 $-1  assets
                  $1    bank:saving
                 $-2    cash
                  $2  expenses
                  $1    food
                  $1    supplies
                 $-2  income
                 $-1    gifts
                 $-1    salary
                  $1  liabilities:debts
--------------------
                   0
```

Notes:

- "Boring" accounts are combined with their subaccount for more
compact output, unless `--no-elide` is used. Boring accounts have no
balance of their own and just one subaccount (eg `assets:bank` and
`liabilities` above).

- All balances shown are "inclusive", ie including the balances from
all subaccounts. Note this means some repetition in the output, which
requires explanation when sharing reports with
non-plaintextaccounting-users. A tree mode report's final total is the
sum of the top-level balances shown, not of all the balances shown.

- Each group of sibling accounts (ie, under a common parent) is sorted separately.

In list mode, `--no-elide` shows parent accounts as well, with their
exclusive balances. These are zero unless the parent has postings of
its own, so `-E/--empty` is usually also needed to make them visible.
Together, these flags guarantee a complete table of all posted-to
accounts and their parents, with full names:

```cli
$ hledger -f examples/sample.journal balance --no-elide -E
                   0  assets
                   0  assets:bank
                   0  assets:bank:checking
                  $1  assets:bank:saving
                 $-2  assets:cash
                   0  expenses
                  $1  expenses:food
                  $1  expenses:supplies
                   0  income
                 $-1  income:gifts
                 $-1  income:salary
                   0  liabilities
                  $1  liabilities:debts
--------------------
                   0
```

This can be useful eg when exporting to a spreadsheet which will look
up balances by account name.

In tree mode, `--full-names` writes each account's full name instead of
indenting leaf names, while keeping tree mode's inclusive balances.
So `--tree --no-elide --full-names -E` shows the same complete table as
above, but with inclusive balances:

```cli
$ hledger -f examples/sample.journal balance --tree --no-elide --full-names -E
                 $-1  assets
                  $1  assets:bank
                   0  assets:bank:checking
                  $1  assets:bank:saving
                 $-2  assets:cash
                  $2  expenses
                  $1  expenses:food
                  $1  expenses:supplies
                 $-2  income
                 $-1  income:gifts
                 $-1  income:salary
                  $1  liabilities
                  $1  liabilities:debts
--------------------
                   0
```

Note that in this variant, parent and subaccount balances overlap, so
(as in any tree mode report) the rows sum to more than the final total.

### Depth limiting

With a `depth:NUM` query, or `--depth NUM` option, or just `-NUM` (eg: `-3`)
balance reports will show accounts only to the specified depth,
hiding the deeper subaccounts. 
This can be useful for getting an overview without too much detail.

Account balances at the depth limit always include the balances from
any deeper subaccounts (even in list mode). 
Eg, limiting to depth 1:

```cli
$ hledger -f examples/sample.journal balance -1
                 $-1  assets
                  $2  expenses
                 $-2  income
                  $1  liabilities
--------------------
                   0  
```

### Dropping top-level accounts

You can also hide one or more top-level account name parts, using `--drop NUM`.
This can be useful for hiding repetitive top-level account names:

```cli
$ hledger -f examples/sample.journal bal expenses --drop 1
                  $1  food
                  $1  supplies
--------------------
                  $2  
```

<a name="multicolumn-balance-report"></a>

### Showing declared accounts

With `--declared`, 
accounts which have been declared with an [account directive](#account-directive)
will be included in the balance report, even if they have no transactions.
(Since they will have a zero balance, you will also need `-E/--empty` to see them.)

More precisely, *leaf* declared accounts (with no subaccounts) will be included,
since those are usually the more useful in reports.

The idea of this is to be able to see a useful "complete" balance report,
even when you don't have transactions in all of your declared accounts yet.

### Sorting by amount

With `-S/--sort-amount`, accounts with the largest (most positive) balances are shown first.
Eg: `hledger bal expenses -MAS` shows your biggest averaged monthly expenses first.
When more than one commodity is present, they will be sorted by the alphabetically earliest
commodity first, and then by subsequent commodities (if an amount is missing a commodity, it
is treated as 0).

Revenues and liability balances are typically negative, however, so `-S` shows these in reverse order.
To work around this, you can add `--invert` to flip the signs.
Or you could use one of the higher-level balance reports (`bs`, `is`..), which flip the sign automatically
(eg: `hledger is -MAS`).

<a name="tree-mode"></a>

### Percentages

With `-%/--percent`, balance reports show each account's value
expressed as a percentage of the (column) total.

Note it is not useful to calculate percentages if the amounts in a
column have mixed signs. In this case, make a separate report for each
sign, eg:

```cli
$ hledger bal -% amt:`>0`
$ hledger bal -% amt:`<0`
```

Similarly, if the amounts in a column have mixed commodities, convert
them to one commodity with `-B`, `-V`, `-X` or `--value`, or make a
separate report for each commodity:

```cli
$ hledger bal -% cur:\\$
$ hledger bal -% cur:€
```

### Multi-period balance report

With a [report interval](#report-intervals) (set by the `-D/--daily`,
`-W/--weekly`, `-M/--monthly`, `-Q/--quarterly`, `-Y/--yearly`, or
`-p/--period` flag), `balance` shows a tabular report, with columns
representing successive time periods (and a title):

```cli
$ hledger -f examples/sample.journal bal --quarterly income expenses -E
Balance changes in 2008:

                   ||  2008q1  2008q2  2008q3  2008q4 
===================++=================================
 expenses:food     ||       0      $1       0       0 
 expenses:supplies ||       0      $1       0       0 
 income:gifts      ||       0     $-1       0       0 
 income:salary     ||     $-1       0       0       0 
-------------------++---------------------------------
                   ||     $-1      $1       0       0 

```

Notes:

- The report's start/end dates will be expanded, if necessary, to fully
encompass the displayed subperiods (so that the first and last
subperiods have the same duration as the others).
- Leading and trailing periods (columns) containing all zeroes are not
shown, unless `-E/--empty` is used.
- Accounts (rows) containing all zeroes are not shown, unless
`-E/--empty` is used.
- Amounts with many commodities are shown in abbreviated form, unless
`--no-elide` is used.
- Average and/or total columns can be added with the `-A/--average` and
`-T/--row-total` flags.
- The `--transpose` flag can be used to exchange rows and columns.
  Repeating it reverses its effect (an even number of `--transpose` flags has no effect).
- The `--pivot FIELD` option causes a different transaction field to be used as
  "account name". See [PIVOTING](#pivoting).
- The `--summary-only` flag (`--summary` also works) hides all but the Total and Average columns
  (those should be enabled with `--row-total` and `-A/--average`).

     
Multi-period reports with many periods can be too wide for easy viewing in the terminal.
Here are some ways to handle that:

- Hide the totals row with `-N/--no-total`
- Filter to a single currency with `cur:`
- Convert to a single currency with `-V [--infer-market-price]`
- Use a more compact layout like `--layout=bare`
- Maximize the terminal window
- Reduce the terminal's font size
- View with a pager like less, eg: `hledger bal -D --color=yes | less -RS`
- Output as CSV and use a CSV viewer like 
  [visidata] (`hledger bal -D -O csv | vd -f csv`),
  Emacs' [csv-mode] (`M-x csv-mode, C-c C-a`), 
  or a spreadsheet (`hledger bal -D -o a.csv && open a.csv`)
- Output as HTML and view with a browser: `hledger bal -D -o a.html && open a.html`

[csv-mode]: https://elpa.gnu.org/packages/csv-mode.html
[visidata]: https://www.visidata.org

### Balance change, end balance

It's important to be clear on the meaning of the numbers shown in
balance reports. Here is some terminology we use:

A ***balance change*** is the net amount added to, or removed from, an account during some period.

An ***end balance*** is the amount accumulated in an account as of some date
(and some time, but hledger doesn't store that; assume end of day in your timezone).
It is the sum of previous balance changes.

We call it a ***historical end balance*** if it includes all balance changes since the account was created.
For a real world account, this means it will match the "historical record",
eg the balances reported in your bank statements or bank web UI. (If they are correct!)

In general, balance changes are what you want to see when reviewing
revenues and expenses, and historical end balances are what you want
to see when reviewing or reconciling asset, liability and equity accounts.

`balance` shows balance changes by default.
To see accurate historical end balances:

1. Initialise account starting balances with an "opening balances"
   transaction (a transfer from equity to the account),
   unless the journal covers the account's full lifetime.

2. Include all of of the account's prior postings in the report,
   by not specifying a [report start date](#report-start--end-date),
   or by using the `-H/--historical` flag.
   (`-H` causes report start date to be ignored when summing postings.)

### Balance report modes

The balance command is quite flexible; here is the full detail on how to control what it reports.
If the following seems complicated, don't worry - this is for advanced reporting,
and it does take time and experimentation to get familiar with all the report modes.

There are three important option groups:

`hledger balance [CALCULATIONMODE] [ACCUMULATIONMODE] [VALUATIONMODE] ...`

#### Calculation mode

The basic calculation to perform for each table cell.
It is one of:

- `--sum` : sum the posting amounts (**default**)
- `--budget` : sum the amounts, but also show the budget goal amount (for each account/period)
- `--valuechange` : show the change in period-end historical balance values
  (caused by deposits, withdrawals, and/or market price fluctuations)
- `--gain` : show capital gain/loss for each account: the current valued balance
  minus the net of postings' transacted costs (acquisition costs minus disposal
  proceeds). For accounts where nothing has been sold this equals the unrealised
  gain; once disposals exist the figure also includes realised gain on the
  disposed units, so it is best read as "total gain since inception".
  To track realised gain separately, use lot notation (see [Lot reporting](#lot-reporting)).
- `--count` : show the count of postings

#### Accumulation mode

How amounts should accumulate across a report's subperiods/columns.
Another way to say it: which time period's postings should contribute to each cell's calculation.
It is one of:

- `--change` : calculate with postings from column start to column end, ie "just this column".
  Typically used to see revenues/expenses.
  (**default for balance, cashflow, incomestatement**)

- `--cumulative` : calculate with postings from report start to column end, ie "previous columns plus this column".
  Typically used to show changes accumulated since the report's start date.
  Not often used.

- `--historical/-H` : calculate with postings from journal start to column end,
  ie "all postings from before report start date until this column's end".
  Typically used to see historical end balances of assets/liabilities/equity.
  (**default for balancesheet, balancesheetequity**)

#### Valuation mode

Which kind of value or cost conversion should be applied, if any, before displaying the report.
See [Cost reporting](#cost-reporting) and [Value reporting](#value-reporting) for more about conversions.

A valuation (or cost) mode can be selected with the --value option:

- no conversion               : don't convert to cost or value (**default**)
- `--value=cost[,COMM]`       : convert amounts to cost (then optionally to some other commodity)
- `--value=then[,COMM]`       : convert amounts to market value on transaction dates
- `--value=end[,COMM]`        : convert amounts to market value on period end date(s)\
                                (**default with `--valuechange`, `--gain`**)
- `--value=now[,COMM]`        : convert amounts to market value on today's date
- `--value=YYYY-MM-DD[,COMM]` : convert amounts to market value on another date

or with the legacy -B/-V/-X options, which are equivalent and easier to type:

- `-B`/`--cost`               : like --value=cost
- `-V`/`--market`             : like --value=end
- `-X COMM`/`--exchange COMM` : like --value=end,COMM

Note that --value can also convert to cost, as a convenience;
but actually --cost and --value are independent options, and could be used together.

#### Combining balance report modes

Most combinations of these modes produce reasonable reports.
The following restrictions are applied:

- `--valuechange` implies `--value=end`
- `--valuechange` makes `--change` the default when used with the `balancesheet`/`balancesheetequity` commands
- `--cumulative` or `--historical` disables `--row-total/-T`

For reference, here is what the combinations of accumulation and valuation show:

| Valuation:><br> Accumulation:v | no valuation                                                     | `--value= then`                                                    | `--value= end`                                              | `--value= YYYY-MM-DD /now`                            |
|--------------------------------|------------------------------------------------------------------|--------------------------------------------------------------------|-------------------------------------------------------------|-------------------------------------------------------|
| `--change`                     | change in period                                                 | sum of posting-date market values in period                        | period-end value of change in period                        | DATE-value of change in period                        |
| `--cumulative`                 | change from report start to period end                           | sum of posting-date market values from report start to period end  | period-end value of change from report start to period end  | DATE-value of change from report start to period end  |
| `--historical /-H`             | change from journal start to period end (historical end balance) | sum of posting-date market values from journal start to period end | period-end value of change from journal start to period end | DATE-value of change from journal start to period end |

### Budget report

The `balance --budget` report is like a regular balance report, but with two main differences:

- Budget goals and performance percentages are also shown, in brackets
- Accounts which don't have budget goals are hidden by default.

This is useful for comparing planned and actual income, expenses, time usage, etc.

[Periodic transaction rules](hledger.html#periodic-transactions) are used to define budget goals.
For example, here's a periodic rule defining monthly goals for bus travel and food expenses:

```journal
;; Budget
~ monthly
  (expenses:bus)              $30
  (expenses:food)            $400
```

After recording some actual expenses,
```journal
;; Two months worth of expenses
2017-11-01
  income                   $-1950
  expenses:bus                $35
  expenses:food:groceries    $310
  expenses:food:dining        $42
  expenses:movies             $38
  assets:bank:checking

2017-12-01
  income                   $-2100
  expenses:bus                $53
  expenses:food:groceries    $380
  expenses:food:dining        $32
  expenses:gifts             $100
  assets:bank:checking
```

we can see a budget report like this:

```cli
$ hledger bal -M --budget
Budget performance in 2017-11-01..2017-12-31:

               ||                  Nov                   Dec 
===============++============================================
 <unbudgeted>  || $-425                 $-565                
 expenses      ||  $425 [ 99% of $430]   $565 [131% of $430] 
 expenses:bus  ||   $35 [117% of  $30]    $53 [177% of  $30] 
 expenses:food ||  $352 [ 88% of $400]   $412 [103% of $400] 
---------------++--------------------------------------------
               ||     0 [  0% of $430]      0 [  0% of $430] 
```

This is "goal-based budgeting"; you define goals for accounts and periods,
often recurring, and hledger shows performance relative to the goals. 
This contrasts with "envelope budgeting", which is more detailed and strict -
useful when cash is tight, but also quite a bit more work.
<https://plaintextaccounting.org/Budgeting> has more on this topic.

#### Using the budget report

Historically this report has been confusing and fragile.
hledger's version should be relatively robust and intuitive, but you may still find surprises.
Here are more notes to help with learning and troubleshooting.

- In the above example, `expenses:bus` and `expenses:food` are shown
  because they have budget goals during the report period.
  
- Their parent `expenses` is also shown, with budget goals aggregated from the children.
   
- The subaccounts `expenses:food:groceries` and `expenses:food:dining`
  are not shown since they have no budget goal of their own,
  but they contribute to `expenses:food`'s actual amount.

- Unbudgeted accounts `expenses:movies` and `expenses:gifts` are also not shown,
  but they contribute to `expenses`'s actual amount.

- The other unbudgeted accounts `income` and `assets:bank:checking` are grouped as `<unbudgeted>`.

- `--depth` or `depth:` can be used to limit report depth in the usual way
  (but will not reveal unbudgeted subaccounts).

- Amounts are always inclusive of subaccounts (even in `-l/--list` mode).

- Numbers displayed in a --budget report will not always agree with the totals,
  because of hidden unbudgeted accounts; this is normal.
  `-E/--empty` can be used to reveal the hidden accounts.

- In the periodic rules used for setting budget goals,
  unbalanced postings are convenient.
  
- You can filter budget reports with the usual queries, eg to focus on particular accounts.
  It's common to restrict them to just expenses.
  (The `<unbudgeted>` account is occasionally hard to exclude; this is because of date surprises, discussed below.)

- Only the account, account type, depth, date and commodity parts of the query
  are applied to the budget goals; the other parts
  (`status:`/`-U`/`-P`/`-C`, `code:`, `desc:`, `payee:`, `note:`, `tag:`, `real:`, `amt:`)
  select actual transactions and postings only.
  So eg `--budget --cleared` compares your cleared spending against the full budget goals.

- When you have multiple currencies, you may want to convert them to
  one (`-X COMM --infer-market-prices`) and/or show just one at a time
  (`cur:COMM`).  If you do need to show multiple currencies at once,
  `--layout bare` can be helpful.

- You can "roll over" amounts (actual and budgeted) to the next period with `--cumulative`.

See also: <https://hledger.org/budgeting.html>.


#### Budget date surprises

With small data, or when starting out,
some of the generated [budget goal transaction dates](hledger.md#period-expressions)
might fall outside the [report periods](hledger.md#report-start--end-date).
Eg with the following journal and report, the first period appears to have no `expenses:food` budget.
(Also the `<unbudgeted>` account should be excluded by the `expenses` query, but isn't.):

```journal
~ monthly in 2020
  (expenses:food)  $500

2020-01-15
  expenses:food    $400
  assets:checking
```

```cli
$ hledger bal --budget expenses
Budget performance in 2020-01-15:

               ||         2020-01-15 
===============++====================
 <unbudgeted>  || $400               
 expenses:food ||    0 [ 0% of $500] 
---------------++--------------------
               || $400 [80% of $500] 
```


In this case, the budget goal transactions are generated on first
days of of month (this can be seen with 
`hledger print --forecast tag:generated expenses`).
Whereas the report period defaults to just the 15th day of january
(this can be seen from the report table's column headings).

To fix this kind of thing, be more explicit about the report period (and/or the periodic rules' dates).
In this case, adding `-b 2020` does the trick.

#### Selecting budget goals

By default, the budget report uses all available periodic transaction rules to generate goals.
This includes rules with a different report interval from your report. 
Eg if you have daily, weekly and monthly periodic rules,
all of these will contribute to the goals in a monthly budget report.

You can select a subset of periodic rules by providing an argument to the `--budget` flag.
`--budget=DESCPAT` will match all periodic rules whose description contains DESCPAT, 
a case-insensitive substring (not a regular expression or query).
This means you can give your periodic rules descriptions
(remember that [two spaces are needed](#two-spaces-between-period-expression-and-description) between period expression and description),
and then select from multiple budgets defined in your journal.

#### Budgeting vs forecasting

`--forecast` and `--budget` both use the periodic transaction rules in the journal to generate temporary transactions for reporting purposes.
However they are separate features - though you can use both at the same time if you want.
Here are some differences between them:

| --forecast | --budget |
|------------|----------|
| is a general option; it enables forecasting with all reports | is a balance command option; it selects the balance report's budget mode |
| generates visible transactions which appear in reports | generates invisible transactions which produce goal amounts |
| generates forecast transactions from after the last regular transaction, to the end of the report period; or with an argument `--forecast=PERIODEXPR` generates them throughout the specified period, both optionally restricted by periods specified in the periodic transaction rules | generates budget goal transactions throughout the report period, optionally restricted by periods specified in the periodic transaction rules |
| uses all periodic rules | uses all periodic rules; or with an argument `--budget=DESCPAT` uses just the rules matched by DESCPAT |

### Balance report layout

The `--layout` option affects how `balance` and the other balance-like commands show multi-commodity amounts and commodity symbols.
It can improve readability, for humans and/or machines (other software).
It has four possible values:

- `--layout=wide[,WIDTH]`: commodities are shown on a single line, optionally elided to WIDTH
- `--layout=tall`: each commodity is shown on a separate line
- `--layout=bare`: commodity symbols are in their own column, amounts are bare numbers
- `--layout=barewide`: commodities are shown on a single line, all in separate columns, amounts are bare numbers
- `--layout=tidy`: data is normalised to easily-consumed "tidy" form, with one row per data value.
  (This one is currently supported only by the `balance` command.)

Here are the `--layout` modes supported by each [output format](#output-format)
Only CSV output supports all of them:

| -        | txt | csv | html | json | sql |
|----------|-----|-----|------|------|-----|
| wide     | Y   | Y   | Y    |      |     |
| tall     | Y   | Y   | Y    |      |     |
| bare     | Y   | Y   | Y    |      |     |
| barewide | Y   | Y   | Y    |      |     |
| tidy     |     | Y   |      |      |     |

Choice of layouts for budget reports is more restricted:

| -        | txt | csv | html | json | sql |
|----------|-----|-----|------|------|-----|
| wide     | Y   | Y   | Y    |      |     |
| tall     | Y   |     |      |      |     |
| bare     | Y   | Y   | Y    |      |     |
| barewide |     | Y   | Y    |      |     |
| tidy     |     |     |      |      |     |

Examples:

#### Wide layout
With many commodities, reports can be very wide:
```cli
$ hledger -f examples/bcexample.journal bal assets:us:etrade -3 -T -Y --layout=wide
Balance changes in 2012-01-01..2014-12-31:

                  ||                                          2012                                                     2013                                             2014                                                      Total 
==================++====================================================================================================================================================================================================================
 Assets:US:ETrade || 10.00 ITOT, 337.18 USD, 12.00 VEA, 106.00 VHT  70.00 GLD, 18.00 ITOT, -98.12 USD, 10.00 VEA, 18.00 VHT  -11.00 ITOT, 4881.44 USD, 14.00 VEA, 170.00 VHT  70.00 GLD, 17.00 ITOT, 5120.50 USD, 36.00 VEA, 294.00 VHT 
------------------++--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
                  || 10.00 ITOT, 337.18 USD, 12.00 VEA, 106.00 VHT  70.00 GLD, 18.00 ITOT, -98.12 USD, 10.00 VEA, 18.00 VHT  -11.00 ITOT, 4881.44 USD, 14.00 VEA, 170.00 VHT  70.00 GLD, 17.00 ITOT, 5120.50 USD, 36.00 VEA, 294.00 VHT 
```

A width limit reduces the width, but some commodities will be hidden:
```cli  
$ hledger -f examples/bcexample.journal bal assets:us:etrade -3 -T -Y --layout=wide,32
Balance changes in 2012-01-01..2014-12-31:

                  ||                             2012                             2013                   2014                            Total 
==================++===========================================================================================================================
 Assets:US:ETrade || 10.00 ITOT, 337.18 USD, 2 more..  70.00 GLD, 18.00 ITOT, 3 more..  -11.00 ITOT, 3 more..  70.00 GLD, 17.00 ITOT, 3 more.. 
------------------++---------------------------------------------------------------------------------------------------------------------------
                  || 10.00 ITOT, 337.18 USD, 2 more..  70.00 GLD, 18.00 ITOT, 3 more..  -11.00 ITOT, 3 more..  70.00 GLD, 17.00 ITOT, 3 more.. 
```

#### Tall layout
Each commodity gets a new line (may be different in each column), and account names are repeated:
```cli
$ hledger -f examples/bcexample.journal bal assets:us:etrade -3 -T -Y --layout=tall
Balance changes in 2012-01-01..2014-12-31:

                  ||       2012        2013         2014        Total 
==================++==================================================
 Assets:US:ETrade || 10.00 ITOT   70.00 GLD  -11.00 ITOT    70.00 GLD 
 Assets:US:ETrade || 337.18 USD  18.00 ITOT  4881.44 USD   17.00 ITOT 
 Assets:US:ETrade ||  12.00 VEA  -98.12 USD    14.00 VEA  5120.50 USD 
 Assets:US:ETrade || 106.00 VHT   10.00 VEA   170.00 VHT    36.00 VEA 
 Assets:US:ETrade ||              18.00 VHT                294.00 VHT 
------------------++--------------------------------------------------
                  || 10.00 ITOT   70.00 GLD  -11.00 ITOT    70.00 GLD 
                  || 337.18 USD  18.00 ITOT  4881.44 USD   17.00 ITOT 
                  ||  12.00 VEA  -98.12 USD    14.00 VEA  5120.50 USD 
                  || 106.00 VHT   10.00 VEA   170.00 VHT    36.00 VEA 
                  ||              18.00 VHT                294.00 VHT 
```

#### Bare layout
Commodity symbols are kept in one column, each commodity has its own row,
amounts are bare numbers, account names are repeated:
```cli
$ hledger -f examples/bcexample.journal bal assets:us:etrade -3 -T -Y --layout=bare
Balance changes in 2012-01-01..2014-12-31:

                  || Commodity    2012    2013     2014    Total 
==================++=============================================
 Assets:US:ETrade || GLD             0   70.00        0    70.00 
 Assets:US:ETrade || ITOT        10.00   18.00   -11.00    17.00 
 Assets:US:ETrade || USD        337.18  -98.12  4881.44  5120.50 
 Assets:US:ETrade || VEA         12.00   10.00    14.00    36.00 
 Assets:US:ETrade || VHT        106.00   18.00   170.00   294.00 
------------------++---------------------------------------------
                  || GLD             0   70.00        0    70.00 
                  || ITOT        10.00   18.00   -11.00    17.00 
                  || USD        337.18  -98.12  4881.44  5120.50 
                  || VEA         12.00   10.00    14.00    36.00 
                  || VHT        106.00   18.00   170.00   294.00 
```

Bare layout also affects [CSV output](#output-format),
which is useful for producing data that is easier to consume, eg for making charts:
```cli
$ hledger -f examples/bcexample.journal bal assets:us:etrade -3 -O csv --layout=bare
"account","commodity","balance"
"Assets:US:ETrade","GLD","70.00"
"Assets:US:ETrade","ITOT","17.00"
"Assets:US:ETrade","USD","5120.50"
"Assets:US:ETrade","VEA","36.00"
"Assets:US:ETrade","VHT","294.00"
"Total:","GLD","70.00"
"Total:","ITOT","17.00"
"Total:","USD","5120.50"
"Total:","VEA","36.00"
"Total:","VHT","294.00"
```

Bare layout will sometimes display an extra row for the no-symbol commodity,
because of zero amounts (hledger treats zeroes as commodity-less, usually).
This can break `hledger-bar` confusingly (workaround: add a `cur:` query to exclude
the no-symbol row).

#### Barewide layout
Commodity symbols are spread in the table headers,
each commodity has its own column,
all column groups share the same set of commodities
even if in one commodity column all values are zero.
For consistency you may think of layout `bare` as `baretall`.
```cli
$ hledger -f examples/bcexample.journal bal assets:us:etrade -3 -T -Y --layout=barewide
Balance changes in 2012-01-01..2014-12-31:

                  || 2012 (GLD)  2012 (ITOT)  2012 (USD)  2012 (VEA)  2012 (VHT)  2013 (GLD)  2013 (ITOT)  2013 (USD)  2013 (VEA)  2013 (VHT)  2014 (GLD)  2014 (ITOT)  2014 (USD)  2014 (VEA)  2014 (VHT)    Total (GLD)    Total (ITOT)    Total (USD)    Total (VEA)    Total (VHT) 
==================++===================================================================================================================================================================================================================================================================
 Assets:US:ETrade ||          0        10.00      337.18       12.00      106.00       70.00        18.00      -98.12       10.00       18.00           0       -11.00     4881.44       14.00      170.00          70.00           17.00        5120.50          36.00         294.00 
------------------++-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
                  ||          0        10.00      337.18       12.00      106.00       70.00        18.00      -98.12       10.00       18.00           0       -11.00     4881.44       14.00      170.00          70.00           17.00        5120.50          36.00         294.00 
```

Barewide layout is very useful for [FODS and CSV output](#output-format),
since you can easily use LibreOffice's `VLOOKUP` function
for accessing numbers in a table with mixed commodities.

#### Tidy layout
This produces normalised "tidy data" (see <https://cran.r-project.org/web/packages/tidyr/vignettes/tidy-data.html>)
where every variable has its own column and each row represents a single data point.
This is the easiest kind of data for other software to consume:

```cli
$ hledger -f examples/bcexample.journal bal assets:us:etrade -3 -Y -O csv --layout=tidy
"account","period","start_date","end_date","commodity","value"
"Assets:US:ETrade","2012","2012-01-01","2012-12-31","GLD","0"
"Assets:US:ETrade","2012","2012-01-01","2012-12-31","ITOT","10.00"
"Assets:US:ETrade","2012","2012-01-01","2012-12-31","USD","337.18"
"Assets:US:ETrade","2012","2012-01-01","2012-12-31","VEA","12.00"
"Assets:US:ETrade","2012","2012-01-01","2012-12-31","VHT","106.00"
"Assets:US:ETrade","2013","2013-01-01","2013-12-31","GLD","70.00"
"Assets:US:ETrade","2013","2013-01-01","2013-12-31","ITOT","18.00"
"Assets:US:ETrade","2013","2013-01-01","2013-12-31","USD","-98.12"
"Assets:US:ETrade","2013","2013-01-01","2013-12-31","VEA","10.00"
"Assets:US:ETrade","2013","2013-01-01","2013-12-31","VHT","18.00"
"Assets:US:ETrade","2014","2014-01-01","2014-12-31","GLD","0"
"Assets:US:ETrade","2014","2014-01-01","2014-12-31","ITOT","-11.00"
"Assets:US:ETrade","2014","2014-01-01","2014-12-31","USD","4881.44"
"Assets:US:ETrade","2014","2014-01-01","2014-12-31","VEA","14.00"
"Assets:US:ETrade","2014","2014-01-01","2014-12-31","VHT","170.00"
```

### Balance report output

As noted in [Output format](#output-format),
if you choose HTML output (by using `-O html` or `-o somefile.html`),
you can create a `hledger.css` file in the same directory to customise the report's appearance.

The HTML and [FODS] output formats can generate hyperlinks to `hledger-web` register views:
an account name links to the account's transactions, a period heading to the period's transactions,
and, in the default layout, a figure to the transactions it is made of, in a register whose final
balance is that figure (a historical balance report asks the register for its historical mode).
The two can differ when a transaction's postings have dates of their own, since the report counts
such a posting in its own period while the register shows its whole transaction.
Each link says where it leads in its title, which browsers show on hover.
E.g. if your `hledger-web` server is reachable at `http://localhost:5000`
then you might run the `balance` command with the extra option `--base-url=http://localhost:5000`.
You can also produce relative links, like `--base-url="some/path"` or `--base-url=""`.)


### Some useful balance reports

Some frequently used `balance` options/reports are:

- `bal -M revenues expenses`\
  Show revenues/expenses in each month.
  Also available as the [`incomestatement`](#incomestatement) command.
  <!-- `bal --monthly --sum --change revenues expenses` -->
  
- `bal -M -H assets liabilities`\
  Show historical asset/liability balances at each month end.
  Also available as the [`balancesheet`](#balancesheet) command.
  <!-- `bal --monthly --sum --historical assets liabilities` -->

- `bal -M -H assets liabilities equity`\
  Show historical asset/liability/equity balances at each month end.
  Also available as the [`balancesheetequity`](#balancesheetequity) command.
  <!-- `bal --monthly --sum --historical assets liabilities equity` -->

- `bal -M assets not:receivable`\
  Show changes to liquid assets in each month.
  Also available as the [`cashflow`](#cashflow) command.
  <!-- `bal --monthly --sum --change assets not:receivable` -->

Also:

- `bal -M expenses -2 -SA`\
  Show monthly expenses summarised to depth 2 and sorted by average amount.

- `bal -M --budget expenses`\
  Show monthly expenses and budget goals.

- `bal -M --valuechange investments`\
  Show monthly change in market value of investment assets.

- `bal investments --valuechange -D date:lastweek amt:'>1000' -STA [--invert]`\
  Show top gainers [or losers] last week

[FODS]: https://en.wikipedia.org/wiki/OpenDocument
