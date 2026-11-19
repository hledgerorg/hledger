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
Which files depends on the layout chosen with `--layout`.
Note, these are just to help you get started; you can always change the file layout to suit your needs.

**simple**:

Just one file. Good if you want simplicity and manual data entry.

- `main.journal` - the journal file, with optional declarations

**default** (the default):

Declarations are kept separate; subdirectories and starter scripts for data-fetching are provided.
This is a good maintainable layout that hledger commands understand well.

- `main.journal` - the main journal file, with a few example transactions
- `accounts.journal`, `commodities.journal`, `payees.journal` - declarations
- `data/` - downloaded CSV files go here, with `data/getdata`, a starter script for [get](#get)
- `prices/` - market prices go here, with `prices/getprices`, a starter script for [get](#get)
- `rules/` - CSV rules files go here
- an example CSV file and rules file

**years**:

Like default, but each year has its own journal file.
This gives you a choice of loading all years or one year at a time (see [close](#close)).
It makes life a little more complicated, but
it is worthwhile if you have enough data that a single file becomes slow on your machine;
or if you want to compartmentalise the data for other reasons.

- `YEAR.journal` (eg `2026.journal`) - this year's journal, with a few example transactions.
- `all.journal` - includes all the year journals, for multi-year reports
- the same declaration files, directories and examples as default

With a journal file argument (a path ending with `.journal`, `.j`, `.hledger` or `.ledger`),
you'll get the simple layout, written to that file.

Files that already exist are never changed; they are skipped, with a warning.
So you can run `init` again to add missing files.
After writing the files, it suggests some next steps.

These and other file layouts can also be seen in the hledger repo's
[examples/file-layouts](https://github.com/hledgerorg/hledger/tree/main/examples/file-layouts) directory.

Examples:
```cli
$ hledger init --dry-run       # show what would be created in the current directory
$ hledger init ~/finance       # create a standard setup in ~/finance
$ hledger init --layout years ~/finance  # create a setup with a journal per year in ~/finance
$ hledger init 2026.journal    # create a single journal file
```
