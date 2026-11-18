## files

List all input files used by the journal(s), in the order they were read.
This includes the files used to read CSV data:
each CSV file is followed by its rules file and any rules files that includes,
and each rules file is followed by any rules files it includes and the data file it read (if any).
With a REGEX argument, only file names matching the regular expression (case sensitive) are shown.

This lists only the files actually read: eg if a rules file's `source` pattern matches several files, only the one it read is shown.
And to find the files, hledger reads the journal as usual, so any `source` commands will be run.

With `-t/--tree`, the files are shown as a tree: each included file is indented below the file that includes it,
and shown with its path relative to that file's directory (for a file included by name, the path as written in the include directive).
The files used to read a CSV or rules file are shown one level below it, in the same way.
A file included more than once appears at each place it is included.
With a REGEX argument (which is matched against full paths), the files including a matched file are also shown.

```flags
Flags:
  -l --flat                 list/tree mode: show files as a flat list
                            (default)
  -t --tree                 list/tree mode: show files as a tree, indenting
                            included files below the file that includes them
```

Examples:

```cli
$ hledger -f main.journal files
/home/user/finance/main.journal
/home/user/finance/2024.journal
```

```cli
$ hledger -f main.journal files 2024
/home/user/finance/2024.journal
```

```cli
$ hledger -f main.journal files --tree
/home/user/finance/main.journal
  2024.journal
  2025.journal
    prices/2025.prices
  checking.rules
    common.rules
    data/checking.csv
```
