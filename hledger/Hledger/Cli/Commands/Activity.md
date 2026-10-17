## activity

Show a bar chart of transaction counts per week, or other report interval.

```flags
Flags:
no command-specific flags
```

The activity command shows how many transactions there are in each week
(or with a [report interval](#report-intervals), each day, month, quarter etc.), as a bar chart.
Each transaction is one character, unless there are too many to fit, when the bars are scaled down.
With query arguments, it counts only the transactions which have at least one matched posting.

Or with `--postings`, it shows how many postings there are in each period,
with each account's postings stacked in its own colour.
With query arguments, it counts only the matched postings.
This is a shortcut for [`balance --count --chart`](#balance-charts), with a weekly interval by default,
so it can show charts in all the same ways: eg with `-1` or other depth limit to show less detail,
`-0` to show just the total count, without the accounts' detail,
`-S`/`--sort-amount` to show the accounts with most postings first.
(Transaction counts show just the total, since a transaction's postings can be in several accounts.)

`--txns` selects transaction counts explicitly; if both `--txns` and `--postings` are given, the last one wins.

Both kinds of chart can be shown in the usual ways, eg with `-w`/`--width` to set the width,
`-T`/`--total` and `-A`/`--average` to show the total count and the average count per period below the chart
(in graphical charts, the average is also drawn as a dashed line),
or `-o FILE.svg` (or `-O svg`) for a graphical chart.

Examples:
```cli
$ hledger activity -M -T -A -w 40
Transaction counts in 2008:

Jan  1  █
Feb  0
Mar  0
Apr  0
May  0
Jun  3  ███
Jul  0
Aug  0
Sep  0
Oct  0
Nov  0
Dec  1  █

Total 5, Average 0.4
```

```cli
$ hledger activity -M --postings -1 -w 40
Posting counts in 2008:

▓ assets  █ expenses  ░ income
▒ liabilities

Jan  2  ▓░
Feb  0
Mar  0
Apr  0
May  0
Jun  7  ▓▓▓▓██░
Jul  0
Aug  0
Sep  0
Oct  0
Nov  0
Dec  2  ▓▒
```
