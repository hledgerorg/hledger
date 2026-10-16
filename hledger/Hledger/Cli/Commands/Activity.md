## activity

Show a bar chart of posting counts per week, or other report interval.

```flags
Flags:
no command-specific flags
```

The activity command shows how many postings there are in each week
(or with a [report interval](#report-intervals), each day, month, quarter etc.), as a bar chart,
with each account's postings stacked in its own colour.
Each posting is one character, unless there are too many to fit, when the bars are scaled down.
With query arguments, it counts only the matched postings.

This is a shortcut for [`balance --count --chart`](#balance-charts), with a weekly interval by default,
so it can show charts in all the same ways: eg with `-w`/`--width` to set the width,
`-0` to show just the total count, without the accounts' detail,
`-S`/`--sort-amount` to show the accounts with most postings first,
or `-o FILE.svg` (or `-O svg`) for a graphical chart.

Examples:
```cli
$ hledger activity -M -0 -w 40
Posting counts in 2008:

Jan  2  ██
Feb  0
Mar  0
Apr  0
May  0
Jun  7  ███████
Jul  0
Aug  0
Sep  0
Oct  0
Nov  0
Dec  2  ██
```
