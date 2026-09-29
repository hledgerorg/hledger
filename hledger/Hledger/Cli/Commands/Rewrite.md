## rewrite

Print all transactions, adding auto postings to some of them.
For now the only rewrite available is adding new postings, like print --auto.

```flags
Flags:
     --add-posting='ACCT  AMTEXPR'  add a posting to ACCT, which may be
                                    parenthesised. AMTEXPR is either a literal
                                    amount, or *N which means the transaction's
                                    first matched amount multiplied by N (a
                                    decimal number). Two spaces separate ACCT
                                    and AMTEXPR.
     --diff                         generate diff suitable as an input for
                                    patch tool
     --verbose-tags                 add tags indicating generated/modified
                                    data
     --layout=hledger1|COL          how should posting amounts be aligned ?
                                    hledger1 - right-align amounts, as in
                                    hledger 1
                                    COL      - align decimal marks at column
                                    COL (default: 53)
```

This is a start at a generic rewriter of transaction entries.
It reads the default journal and prints the transactions, like print,
but adds one or more specified postings to any transactions matching QUERY.
The posting amounts can be fixed, or a multiplier of the existing transaction's first posting amount. 

Examples:
```cli
$ hledger-rewrite.hs ^income --add-posting '(liabilities:tax)  *.33  ; income tax' --add-posting '(reserve:gifts)  $100'
$ hledger-rewrite.hs expenses:gifts --add-posting '(reserve:gifts)  *-1"'
$ hledger-rewrite.hs -f rewrites.hledger
```
rewrites.hledger may consist of entries like:
```journal
= ^income amt:<0 date:2017
  (liabilities:tax)  *0.33  ; tax on income
  (reserve:grocery)  *0.25  ; reserve 25% for grocery
  (reserve:)  *0.25  ; reserve 25% for grocery
```
Note the single quotes to protect the dollar sign from bash, 
and the two spaces between account and amount.

More:

```cli
$ hledger rewrite [QUERY]        --add-posting "ACCT  AMTEXPR" ...
$ hledger rewrite ^income        --add-posting '(liabilities:tax)  *.33'
$ hledger rewrite expenses:gifts --add-posting '(budget:gifts)  *-1"'
$ hledger rewrite ^income        --add-posting '(budget:foreign currency)  *0.25 JPY; diversify'
```

Argument for `--add-posting` option is a usual posting of transaction with an
exception for amount specification. More precisely, you can use `'*'` (star
symbol) before the amount to indicate that that this is a factor for an
amount of original matched posting.  If the amount includes a commodity name,
the new posting amount will be in the new commodity; otherwise, it will be in
the matched posting amount's commodity.

### Re-write rules in a file

During the run this tool will execute so called
["Automated Transactions"](http://ledger-cli.org/3.0/doc/ledger3.html#Automated-Transactions)
found in any journal it process. I.e instead of specifying this operations in
command line you can put them in a journal file.

```cli
$ rewrite-rules.journal
```

Make contents look like this:

```journal
= ^income
    (liabilities:tax)  *.33

= expenses:gifts
    budget:gifts  *-1
    assets:budget  *1
```

Note that `'='` (equality symbol) that is used instead of date in transactions
you usually write. It indicates the query by which you want to match the
posting to add new ones.

```cli
$ hledger rewrite -f input.journal -f rewrite-rules.journal > rewritten-tidy-output.journal
```

This is something similar to the commands pipeline:

```cli
$ hledger rewrite -f input.journal '^income' --add-posting '(liabilities:tax)  *.33' \
  | hledger rewrite -f - expenses:gifts      --add-posting 'budget:gifts  *-1'       \
                                                --add-posting 'assets:budget  *1'       \
  > rewritten-tidy-output.journal
```

It is important to understand that relative order of such entries in journal is
important. You can re-use result of previously added postings.

### Diff output format

To use this tool for batch modification of your journal files you may find
useful output in form of unified diff.

```cli
$ hledger rewrite --diff -f examples/sample.journal '^income' --add-posting '(liabilities:tax)  *.33'
```

Output might look like:

```
--- /tmp/examples/sample.journal
+++ /tmp/examples/sample.journal
@@ -28,13 +28,15 @@
 ; declare commodities:
 ; commodity $
 
-2008/01/01 income
-    assets:bank:checking  $1
+2008-01-01 income
+    assets:bank:checking                          $1
     income:salary
+    (liabilities:tax)                             $0
 
-2008/06/01 gift
-    assets:bank:checking  $1
+2008-06-01 gift
+    assets:bank:checking                          $1
     income:gifts
+    (liabilities:tax)                             $0
 
 2008/06/02 save
     assets:bank:saving  $1
```

If you'll pass this through `patch` tool you'll get transactions containing the
posting that matches your query be updated. Note that multiple files might be
update according to list of input files specified via `--file` options and
`include` directives inside of these files.

Changed transactions are re-rendered in `print`'s standard format, so the diff
shows any reformatting as well as the postings you added: amounts are realigned,
and dates are written with `-` separators. Transactions you didn't change are
left exactly as they are. `--layout` selects the amount alignment, so choosing
one which matches your journal will keep the diff small. Here is the example
above again, with `--layout=26` to match this journal's own alignment:

```
@@ -28,13 +28,15 @@
 ; declare commodities:
 ; commodity $
 
-2008/01/01 income
+2008-01-01 income
     assets:bank:checking  $1
     income:salary
+    (liabilities:tax)     $0
 
-2008/06/01 gift
+2008-06-01 gift
     assets:bank:checking  $1
     income:gifts
+    (liabilities:tax)     $0
 
 2008/06/02 save
     assets:bank:saving  $1
```

Only transactions which exist as journal entries in a file can be patched
this way. Transactions read from other data formats, such as CSV or timeclock,
and transactions generated by a periodic transaction rule, have no journal
entry of their own; these are left out of the diff, and reported on stderr.
To rewrite those, convert them to journal entries first, eg with
[`hledger print`](#print) or [`hledger import`](#import).

Be careful. Whole transaction being re-formatted in a style of output from
`hledger print`.

See also: 

https://github.com/hledgerorg/hledger/issues/99

### rewrite vs. print --auto

This command predates print --auto, and currently does much the same thing,
but with these differences:

- with multiple files, rewrite lets rules in any file affect all other files.
  print --auto uses standard directive scoping; rules affect only child files.

- rewrite's query limits which transactions can be rewritten; all are printed.
  print --auto's query limits which transactions are printed.

- rewrite applies rules specified on command line or in the journal.
  print --auto applies rules specified in the journal.
