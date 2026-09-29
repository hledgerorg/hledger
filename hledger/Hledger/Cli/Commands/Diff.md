## diff

Compare a particular account's transactions in two input files.
It shows any transactions to this account which are in one file but
not in the other.

```flags
Flags:
no command-specific flags
```

More precisely: for each posting affecting this account in either file,
this command looks for a corresponding posting in the other file which
posts the same amount to the same account (ignoring date, description,
etc).

Since it compares postings, not transactions, this also works when
multiple bank transactions have been combined into a single journal entry.

This command is useful eg if you have downloaded an account's
transactions from your bank (eg as CSV data): when hledger and your
bank disagree about the account balance, you can compare the bank data
with your journal to find out the cause.

Examples:

```cli
$ hledger diff -f $LEDGER_FILE -f bank.csv assets:bank:giro 
These transactions are in the first file only:

2014/01/01 Opening Balances
    assets:bank:giro              EUR ...
    ...
    equity:opening balances       EUR -...

These transactions are in the second file only:
```
