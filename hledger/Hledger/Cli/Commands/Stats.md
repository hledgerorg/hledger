## stats

Show journal and performance statistics.

```flags
Flags:
  -q --oneline              show a single line of output
  -v --verbose              show more detailed output
  -o --output-file=FILE     write output to FILE.
```

The stats command shows summary information for the whole journal, or
a matched part of it. With a [reporting interval](#report-intervals),
it shows a report for each report period. 

It also shows some performance statistics:

- how long the program ran for
- the number of transactions processed per second
- the peak live memory in use by the program to do its work
- the peak allocated memory as seen by the program

By default, the output is reasonably discreet; 
it reveals the main file name, your activity level, and the speed of your machine.

With `-v/--verbose`, more details are shown:
the full paths of all files, and the names of the commodities you work with.

With `-q/--oneline`, only one line of output is shown, in a machine-friendly
tab-separated format: the program version, the main journal file name,
and the performance stats,

The run time of `stats` is similar to that of a balance report.

Example:

```cli
$ hledger stats -f examples/1ktxns-1kaccts.journal 
Main file           : .../1ktxns-1kaccts.journal
Included files      : 0
Txns span           : 2000-01-01 to 2002-09-27 (1000 days)
Last txn            : 2002-09-26 (7827 days ago)
Txns                : 1000 (1.0 per day)
Txns last 30 days   : 0 (0.0 per day)
Txns last 7 days    : 0 (0.0 per day)
Payees/descriptions : 1000
Accounts            : 1000 (depth 10)
Commodities         : 26
Base currency       : B
Market prices       : 1000
Runtime stats       : 0.12 s elapsed, 8266 txns/s, 4 MB live, 16 MB alloc
```

```cli
$ hledger stats -q -f examples/10ktxns-1kaccts.journal
1.50.99-g0835a2485-20251119, mac-aarch64	10ktxns-1kaccts.journal	0.66 s elapsed	15244 txns/s	28 MB live	86 MB alloc
```

This command supports
the [-o/--output-file](hledger.html#output-destination) option
(but not [-O/--output-format](hledger.html#output-format)).
