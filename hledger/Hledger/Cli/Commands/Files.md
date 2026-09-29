## files

List all input files used by the journal(s). With a REGEX argument,
only file names matching the regular expression (case sensitive) are shown.

```flags
Flags:
no command-specific flags
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
