## init

Create starter files for a new hledger setup, or add missing ones to an existing setup.

```flags
Flags:
     --dry-run             just show the files that would be created
```

With no argument, or a directory argument, `init` writes a standard set of files in that directory
(the current directory by default), creating it if needed:

- `main.journal` - the main journal file, with a few example transactions
- `accounts.journal`, `commodities.journal`, `payees.journal` - declarations, included by main.journal
- `data/` - downloaded CSV files go here, with `data/getdata`, a starter script for [get](#get)
- `prices/` - market prices go here, with `prices/getprices`, a starter script for [get](#get)
- `rules/` - CSV rules files go here
- an example CSV file and rules file

With a journal file argument (a path ending with `.journal`, `.j`, `.hledger` or `.ledger`),
you'll get a more minimal setup - just that one file, with optional declarations commented out.

Files that already exist are never changed; they are skipped, with a warning.
So you can run `init` again to add missing files.
After writing the files, it suggests some next steps.

These files and other examples can also be seen in the hledger repo's
[examples/file-layouts](https://github.com/hledgerorg/hledger/tree/main/examples/file-layouts) directory.

Examples:
```cli
$ hledger init --dry-run       # show what would be created in the current directory
$ hledger init ~/finance       # create a standard setup in ~/finance
$ hledger init 2026.journal    # create a single journal file
```
