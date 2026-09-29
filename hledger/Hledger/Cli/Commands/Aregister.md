## aregister

(areg)

Show the transactions and running balances in one account,
with one entry per transaction.

```flags
Flags:
     --txn-dates            filter strictly by transaction date, not posting
                            date. Warning: this can show a wrong running
                            balance.
     --no-elide             don't show only 2 commodities per amount
     --cumulative           accumulation mode: show running total from report
                            start date
  -H --historical           accumulation mode: show historical running
                            total/balance (includes postings before report
                            start date) (default)
  -A --average              show running average of transaction amounts
                            instead of balance (implies --empty and, unless -H
                            is used, --cumulative)
  -r --related              show the other accounts in each transaction
                            (default)
     --matched              show the matched accounts (this account or its
                            subaccounts) instead
     --invert               display all amounts with reversed sign
     --drop=N               omit N leading account name parts
     --heading=YN           show heading row above table: yes (default) or no
  -w --width=N              set output width (default: terminal width). -wN,M
                            sets description width as well.
     --align-all            guarantee alignment across all lines (slower)
  -O --output-format=FMT    select the output format. Supported formats:
                            txt, html, csv, tsv, json.
  -o --output-file=FILE     write output to FILE. A file extension matching
                            one of the above formats selects that format.
```

`aregister` shows the overall transactions affecting a particular account (and
any subaccounts). Each report line represents one transaction in this account.
Transactions before the report start date are included in the running balance
(`--historical` mode is the default).
You can suppress this behaviour using the `--cumulative` option.

This is a more "real world", bank-like view than the [`register`](#register) 
command (which shows individual postings, possibly from multiple accounts,
not necessarily in historical mode). 
As a quick rule of thumb:

- `aregister` is best when reconciling real-world asset/liability accounts
- `register` is best when reviewing individual revenues/expenses.

Note this command's non-standard, and required, first argument; it specifies the account whose register will be shown.
You can write the account's name, or (to save typing) a case-insensitive infix regular expression matching the name,
which selects the alphabetically first matched account.
(For example, if you have `assets:personal checking` and `assets:business checking`,
`hledger areg checking` would select `assets:business checking`.)

Transactions involving subaccounts of this account will also be shown.
`aregister` ignores depth limits, so its final total will always match 
a historical balance report with similar arguments.

Any additional arguments are standard [query arguments](#queries), which will limit the transactions shown.
Note some queries will disturb the running balance, causing it to be different from the account's real-world running balance.

An example: this shows the transactions and historical running balance
during july, in the first account whose name contains "checking":

```cli
$ hledger areg checking date:jul
```

Each `aregister` line item shows:

- the transaction's date (or the relevant posting's date if different, see below)
- the names of all the other account(s) involved in this transaction (probably abbreviated)
- the total change to this account's balance from this transaction
- the account's historical running balance after this transaction.

The account column normally shows the other accounts in each transaction
(this is also selectable with `-r/--related`).
With `--matched`, it shows the matched accounts instead:
this account, or the subaccounts of it that were posted to.
This is useful when the account has subaccounts, eg:

```cli
$ hledger areg expenses --matched
```

shows which expense categories each transaction touched.
Any additional query arguments also narrow the matched accounts shown.
The amounts and running balance are the same in both modes.

Transactions making a net change of zero are not shown by default;
add the `-E/--empty` flag to show them.

The `-A/--average` flag shows the running average change per transaction,
instead of the running balance, so the last number shown is the average
for the whole report period. It implies `--empty`, since zero-change transactions
also affect the average. Unlike aregister's other reports, it is not
historical by default; add `-H` to include the transactions before the report
start date in the average. Like [`register -A`](#register), it works best
with a single commodity.

For performance reasons, column widths are chosen based on the first 1000 lines;
this means unusually wide values in later lines can cause visual discontinuities
as column widths are adjusted. If you want to ensure perfect alignment, 
at the cost of more time and memory, use the `--align-all` flag.

By default, `aregister` shows a heading above the data.
However, when reporting in a language different from English,
it is easier to omit this heading and prepend your own one.
For this purpose, use the `--heading=no` option.

This command also supports the
[output destination](hledger.html#output-destination) and
[output format](hledger.html#output-format) options.
The output formats supported are `txt`, `csv`, `tsv`, `html`, `fods` and `json`.

### aregister and posting dates

aregister always shows one entry (and one date and amount) per
transaction. (With a single commodity, this means line = one transaction.
But multi-commodity amounts will be shown with one line per commodity.)
But sometimes transactions have postings with different dates.  Also,
not all of a transaction's postings may be within the report period.
To resolve this, aregister shows the earliest of the transaction's
date and posting dates that is in-period, and the sum of the in-period
postings.  In other words it will show a combined line item with just
the earliest date, and the running balance will (temporarily, until
the transaction's last posting) be inaccurate. Use `register -H` if
you need to see the individual postings.

There is also a `--txn-dates` flag, which filters strictly by
transaction date, ignoring posting dates. This too can cause an
inaccurate running balance.

