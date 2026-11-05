## files

List all input files used by the journal(s), in the order they were read.
With a REGEX argument, only file names matching the regular expression (case sensitive) are shown.

With `-t/--tree`, the files are shown as a tree: each included file is indented below the file that includes it,
and shown with its path relative to that file's directory (for a file included by name, the path as written in the include directive).
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
```
