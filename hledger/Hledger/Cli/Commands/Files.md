## files

List all input files used by the journal(s), in the order they were read.
This includes the files used to read CSV data:
each CSV file is followed by its rules file and any rules files that includes,
and each rules file is followed by any rules files it includes and the data file it read (if any).
With a REGEX argument, only file names matching the regular expression (case sensitive) are shown.

To find the files, hledger reads them only as far as needed, without processing their data.
So this command works even when the journal has errors, such as unbalanced entries or failing balance assertions
(but not syntax errors), and it does not run `source` commands.
If an included file does not exist (or an include's glob pattern matches no files),
it is omitted from the list, with a warning; this is not an error.
(This helps tools which generate included files, and need to find them before they exist.)
If a rules file's `source` pattern matches several files, only the one it would read is shown.

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
  -O --output-format=FMT    select the output format. Supported formats:
                            txt, json.
  -o --output-file=FILE     write output to FILE. A file extension matching
                            one of the above formats selects that format.
```

With `-O json`, the files are listed as JSON, for use by other tools.
Each file is an object with these fields:
`path` (the file's path, or `-` for standard input),
`depth` (0 for a main file, 1 for a file it includes or uses, and so on),
`parent` (the path of the file that included or used this one, or null for a main file),
and `exists` (false for a missing included file, or an include's glob pattern which matched nothing).
`--tree` does not affect JSON output, and a REGEX argument selects just the matching files.

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

```cli
$ hledger -f main.journal files -O json checking
[
  {
    "depth": 1,
    "exists": true,
    "parent": "/home/user/finance/main.journal",
    "path": "/home/user/finance/checking.rules"
  },
  {
    "depth": 2,
    "exists": true,
    "parent": "/home/user/finance/checking.rules",
    "path": "/home/user/finance/data/checking.csv"
  }
]
```
