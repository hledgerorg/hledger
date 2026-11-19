## init

Create starter files for a new hledger setup, or add missing ones to an existing setup.

```flags
Flags:
     --layout=LAYOUT       which file layout to write: simple, default, years
                           (default: default)
     --dry-run             just show the files that would be created
```

With no argument, or a directory argument, `init` writes a set of files in that directory
(the current directory by default), creating it if needed.
Which files depends on the layout chosen with `--layout`:

**default** (the default):

- `main.journal` - the main journal file, with a few example transactions
- `accounts.journal`, `commodities.journal`, `payees.journal` - declarations, included by main.journal
- `data/` - downloaded CSV files go here, with `data/getdata`, a starter script for [get](#get)
- `prices/` - market prices go here, with `prices/getprices`, a starter script for [get](#get)
- `rules/` - CSV rules files go here
- an example CSV file and rules file

**simple**:

- `main.journal` - just one file, with optional declarations commented out.

**years**:

Like default, but with a journal file for each year, which is good when you have a lot of data.

- `YEAR.journal` (eg `2026.journal`) - this year's journal, for day to day use, with a few example transactions.
  It includes the declaration files.
- `all.journal` - includes all the year journals, for reports across several years
- the same declaration files, directories and examples as default

The year journal is named for the current year.
In a later year, you can run `hledger init --layout years` again to add that year's journal
(then replace its example transactions with that year's opening balances, eg from [close](#close)).

With a journal file argument (a path ending with `.journal`, `.j`, `.hledger` or `.ledger`),
you'll get a more minimal setup - just that one file, with the simple layout's content.

Files that already exist are never changed; they are skipped, with a warning.
So you can run `init` again to add missing files.
After writing the files, it suggests some next steps.

These files and other examples can also be seen in the hledger repo's
[examples/file-layouts](https://github.com/hledgerorg/hledger/tree/main/examples/file-layouts) directory.

Examples:
```cli
$ hledger init --dry-run       # show what would be created in the current directory
$ hledger init ~/finance       # create a standard setup in ~/finance
$ hledger init --layout years ~/finance  # create a setup with a journal per year in ~/finance
$ hledger init 2026.journal    # create a single journal file
```
