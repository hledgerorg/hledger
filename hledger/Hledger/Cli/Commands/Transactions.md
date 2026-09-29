## transactions

(tx)

List transactions, one per line.

```flags
Flags:
  -m --match=DESC           fuzzy search for one recent transaction with
                            description closest to DESC
```

This command shows each transaction's first line only
(the date, status, code, description, and any same-line comment),
giving a compact overview of a journal, in the manner of `git log --oneline`.
You can add a query to select a subset of transactions.
(To see full journal entries, use the [`print`](#print) command.)

Example:
```cli
$ hledger transactions -f examples/sample.journal
2008-01-01 income
2008-06-01 gift
2008-06-02 save
2008-06-03 * eat & shop
2008-12-31 * pay off
```
