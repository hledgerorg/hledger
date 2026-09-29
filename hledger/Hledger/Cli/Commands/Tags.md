## tags

List the tag names used or declared in the journal, or their values.
<!-- This section has the same name as Journal > Tags; 
     if changing their relative order, all #tags[-1] links need to be updated -->

```flags
Flags:
     --used                 list tags used
     --declared             list tags declared
     --undeclared           list tags used but not declared
     --unused               list tags declared but not used
     --find                 list the first tag whose name is matched by the
                            first argument (a case-insensitive infix regexp)
     --values               list tag values instead of tag names
     --parsed               show them in the order they were parsed (mostly),
                            including duplicates
     --directives           show tag names as tag directives, for use in
                            journals
```

This command lists tag names -
all of them by default,
or just the ones which have been used on transactions/postings/accounts,
or declared with `tag` directives,
or used but not declared,
or declared but not used,
or just the first one matched by a pattern (with `--find`, returning a non-zero exit code if it fails).

Note this command's non-standard first argument:
it is a case-insensitive infix regular expression for matching tag names, which limits the tags shown.
Any additional arguments are standard [query arguments](#queries), which limit the transactions, postings, or accounts providing tags.

With `--values`, the tags' unique non-empty values are listed instead.

With `-E`/`--empty`, blank/empty values are also shown.

With `--parsed`, tags or values are shown in the order they were parsed, with duplicates included.
(Except, tags from account declarations are always shown first.)

With `--directives`, tag names are shown as valid tag directives, which could be pasted into a journal file.

Remember that accounts also acquire tags from their parents;
postings also acquire tags from their account and transaction;
and transactions also acquire tags from their postings.

Examples:

```cli
$ hledger tags
broker
receipt
trip
```

```cli
$ hledger tags --values
acme
paris
```
