# DebConf ledgers

DebConf has done their accounting with Ledger since 2017.\
Eg: <https://salsa.debian.org/debconf-team/public/data/dc25/-/tree/main/budget>\
Here are some scripts and notes to help view them with hledger.

Each year has its own repo, and the repos are big.\
To clone just the accounting data for all years: `make`\
Or to clone just a few recent years: `make recent`

Some patches for hledger readability will be applied; those might need updating from time to time.\
To check hledger readability: `make hledger-check`\
To check ledger  readability: `make ledger-check`

For convenient reporting, a top-level .hledger file that also includes the foreign exchange rates is created for each year's repo.

The `hledger.conf` file sets a few non-essential defaults when you are in this directory.

Here are hledger's 
[manual](https://hledger.org/hledger.html)
and [other docs](https://hledger.org/doc.html).

## Report examples

Single year reports:

- `hledger -f 25.hledger is`
- `hledger -f 25.hledger is -V`
- `hledger -f 25.hledger is -VQSTt --drop 1`

The `all.hledger` file reads from all the downloaded repos' main journals:

- `hledger -f all.hledger is -1 -YTN`
- `hledger -f all.hledger is -1 -YT -X USD`

`make hledger-'HLEDGERARGS'` runs a hledger command on each repo's main journal:

- `make hledger-accounts`
- `make hledger-stats | grep 'Txns  '`
- `make hledger-'bs -2'`
- `make hledger-'is -2`

`make ledger-'LEDGERARGS'` does the same but with Ledger.

`make cmd-'CMD` runs a command in each repo.
