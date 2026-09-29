## balancesheet

(bs)

Show the end balances in asset and liability accounts.
Amounts are shown with normal positive sign, as in conventional financial statements.

```flags
Flags:
     --sum                  calculation mode: show sum of posting amounts
                            (default)
     --valuechange          calculation mode: show total change of value of
                            period-end historical balances (caused by deposits,
                            withdrawals, market price fluctuations)
     --gain                 calculation mode: show unrealised capital
                            gain/loss (historical balance value minus cost
                            basis)
     --count                calculation mode: show the count of postings
     --change               accumulation mode: accumulate amounts from column
                            start to column end (in multicolumn reports)
     --cumulative           accumulation mode: accumulate amounts from report
                            start (specified by e.g. -b/--begin) to column end
  -H --historical           accumulation mode: accumulate amounts from
                            journal start to column end (includes postings
                            before report start date) (default)
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
  -S --sort-amount          sort by amount instead of account code/name
  -% --percent              express values in percentage of each column's
                            total
     --layout=ARG           how to show multi-commodity amounts:
                            'wide[,WIDTH]': all commodities on one line
                            'tall'        : each commodity on a new line
                            'bare'        : bare numbers, symbols in a column
     --base-url=URLPREFIX   in html output, generate hyperlinks to
                            hledger-web, with this prefix. (Usually the base
                            url shown by hledger-web; can also be relative.)
  -O --output-format=FMT    select the output format. Supported formats:
                            txt, html, csv, tsv, json.
  -o --output-file=FILE     write output to FILE. A file extension matching
                            one of the above formats selects that format.
```

This command displays a [balance sheet](https://en.wikipedia.org/wiki/Balance_sheet), 
showing historical ending balances of asset and liability accounts. 
(To see equity as well, use the [balancesheetequity](#balancesheetequity) command.)

Accounts declared with the `Asset`, `Cash` or `Liability` type are shown
(see [account types](https://hledger.org/hledger.html#account-types)).
Or if no such accounts are declared, it shows top-level accounts named
`asset` or `liability` (case insensitive, plurals allowed) and their subaccounts.

Example:

```cli
$ hledger balancesheet
Balance Sheet 2008-12-31

                    || 2008-12-31 
====================++============
 Assets             ||            
--------------------++------------
 assets:bank:saving ||         $1 
 assets:cash        ||        $-2 
--------------------++------------
                    ||        $-1 
====================++============
 Liabilities        ||            
--------------------++------------
 liabilities:debts  ||        $-1 
--------------------++------------
                    ||        $-1 
====================++============
 Net:               ||          0 
 ```

This command is a higher-level variant of the [`balance`](#balance) command,
and supports many of that command's features, such as multi-period reports.
It is similar to `hledger balance -H assets liabilities`,
but with smarter account detection, and liabilities displayed with
their sign flipped.

This command also supports the
[output destination](hledger.html#output-destination) and
[output format](hledger.html#output-format) options
The output formats supported are
`txt`, `csv`, `tsv`, `html`, and `json`.
