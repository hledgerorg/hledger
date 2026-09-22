## print

Show transactions' journal entries, or export journal data to another format.

```flags
Flags:
  -a --all                  show all details (--explicit --lots
                            --verbose-tags)
  -x --explicit             show all inferred info explicitly
     --verbose-tags         add tags indicating generated/modified data
     --invert               display all amounts with reversed sign
     --locations            add tags showing file paths and line numbers
     --export               reproduce the whole journal, with directives and
                            comments preserved and included files inlined
  -m --match=DESC           fuzzy search for one recent transaction with
                            description closest to DESC
     --new                  show only newer-dated transactions added in each
                            file since last run
     --round=TYPE           how much rounding or padding should be done when
                            displaying amounts ?
                            none - show original decimal digits,
                                   as in journal (default)
                            soft - just add or remove decimal zeros
                                   to match precision
                            hard - round posting amounts to precision
                                   (can unbalance transactions)
                            all  - also round cost amounts to precision
                                   (can unbalance transactions)
     --layout=hledger1|COL  how should posting amounts be aligned ?
                            hledger1 - right-align amounts, as in hledger 1
                            COL      - align decimal marks at column COL
                            (default: 53)
     --base-url=URLPREFIX   in html output, generate links to hledger-web,
                            with this prefix. (Usually the base url shown by
                            hledger-web; can also be relative.)
  -O --output-format=FMT    select the output format. Supported formats:
                            txt, ledger, beancount, csv, tsv, html, fods, json,
                            sql.
  -o --output-file=FILE     write output to FILE. A file extension matching
                            one of the above formats selects that format.
```

The print command displays full journal entries (transactions) 
from the journal file, sorted by date
(or with `--date2`, by [secondary date](#secondary-dates)).
(For a compact one-line-per-transaction overview, see the [`transactions`](#transactions) command.)

By default, directives and inter-transaction comments are not shown
(except for comment lines immediately preceding a transaction, which are shown with it),
and entries are sorted by date. So the default print output is somewhat lossy.
To reproduce the whole journal, including directives and comments, use `--export` (see below).

Eg:

```cli
$ hledger print -f examples/sample.journal date:200806
2008/06/01 gift
    assets:bank:checking            $1
    income:gifts                   $-1

2008/06/02 save
    assets:bank:saving              $1
    assets:bank:checking           $-1

2008/06/03 * eat & shop
    expenses:food                $1
    expenses:supplies            $1
    assets:cash                 $-2

```

### print explicitness

Normally, whether posting amounts are implicit or explicit is preserved.
For example, when an amount is omitted in the journal, it will not appear in the output.
Similarly, if a conversion cost is implied but not written, it will not appear in the output.

You can use the `-x`/`--explicit` flag to force explicit display of all amounts and costs.
This can be useful for troubleshooting or for making your journal more readable and
robust against data entry errors.
`-x` is also implied by using any of `-B`,`-V`,`-X`,`--value`.

The `-x`/`--explicit` flag will cause any postings with a multi-commodity amount
(which can arise when a multi-commodity transaction has an implicit amount)
to be split into multiple single-commodity postings, 
keeping the output parseable.

To see more details — not just inferred amounts and costs, 
but also lot subaccounts and postings,
and the hidden tags that hledger adds to classify things —
use `-a`/`--all`, which is equivalent to `--explicit --lots --verbose-tags`.


### print layout

By default, `print` aligns posting amounts so that their decimal mark is at column 53 (or would be if they had a decimal mark).
If needed, it will shift a transaction's amounts further to the right to ensure at least 2 spaces between account names and amounts.
Also, any balance assertion/assignment operators (`=`, `=*` etc.) are aligned to the right of the posting amounts;
and the assertion/assignment amounts will be aligned by their decimal marks.

You can customise this with `--layout`:

- `--layout=COL`      — sets a different target column for posting amounts' decimal mark
- `--layout=hledger1` — use hledger 1 layout (right-aligned posting amounts in each transaction).

If you want to change the default, put something like this in `~/.hledger.conf`:
```
[print]
--layout=hledger1
```

Other print-like commands (close, import, rewrite, add) also accept `--layout`.

### print amount style

Amounts will be displayed mostly in their [commodity's display style](#commodity-display-style),
with standardised symbol placement, decimal mark, and digit group marks.
This does not apply to their decimal digits;
`print` normally shows the same decimal digits that are recorded in each journal entry.

You can override the decimal precisions with `print`'s special `--round` option.
`--round` tries to show amounts with their commodities' standard decimal precisions, increasingly strongly:

- `--round=none` show amounts with original precisions (default)
- `--round=soft` add/remove decimal zeros in amounts (except costs)
- `--round=hard` round amounts (except costs), possibly hiding significant digits
- `--round=all`  round all amounts and costs

`soft` is good for non-lossy cleanup, displaying more consistent decimals where possible, without making entries unbalanced.

`hard` or `all` can be good for stronger cleanup, when decimal rounding is wanted. 
Note rounding can produce unbalanced journal entries, perhaps requiring manual fixup.


### print parseability

Usually, print's output is a valid [hledger journal](#journal), 
which you can pipe into a second hledger command for further processing.
This is sometimes convenient for rewriting journal entries:

```cli
# Make today's shopping entry explicit. (-f - means read from standard input.)
$ hledger print date:today desc:shop | hledger -f- print -x
```

or for achieving certain kinds of query:

```cli
# Show running total of food expenses paid from cash.
$ hledger print assets:cash | hledger -f- reg expenses:food
```

But here are some things which can cause print's output to become unparseable:

- `--round` (see above) can disrupt transaction balancing.
- [Account aliases](#alias-directive) or [pivoting](#pivoting) can disrupt account names, balance assertions, or balance assignments.
- [Value reporting](#value-reporting) also can disrupt balance assertions or balance assignments.
- [Auto postings](#auto-postings) can generate too many amountless postings.
- [`--infer-costs or --infer-equity`](#equity-conversion-postings) can generate too-complex redundant costs.
- Because print always shows transactions in date order, balance assertions involving non-date-ordered transactions
  (and same-day postings) could be disrupted.

Also, printing a subset of journal entries can disrupt validation of balance assertions or lot entries.
And print does not reproduce directives (unless `--export` is used).
Lot entries are printed with their inferred cost basis annotations, so they can still be read
without the commodity's `lots:` declaration when the default cost basis method is used;
but with other methods, or `lots: NONE` accounts, the missing declarations will change how they are read.
(`--export` output keeps lot entries as written, since it reproduces the declarations.)
To suppress errors from these, we often use the `-I` flag (short for `--ignore-assertions --ignore-lots`.
So any time you are reading from standard input with `-f-`, consider adding `-I` also.

### print export mode

With `--export`, print reproduces the whole journal in its original order,
with directives, top-level comment lines and `comment` blocks preserved verbatim,
and with each transaction shown as print normally shows it
(so `-x`, `--round`, `--layout` etc. still apply).
Blank lines are normalised: there is one blank line between transactions,
and between groups of directive or comment lines.
The output can be read by hledger as an equivalent journal,
so this is the mode to use when reformatting or regenerating a journal file.
Some details:

- Included files are inlined at the position of their `include` directive, and the `include` line itself is dropped.
  If you want to preserve a multi-file structure rather than flattening it, currently the best way is:
  comment out the `include` directives (they will be preserved as comments),
  export each file individually, then uncomment the `include` directives in the exported main file.
  (A file which depends on directives in its parent file, such as `Y` or `decimal-mark`,
  might need those added temporarily while it is exported.)
- `apply account`, `alias` and their `end` directives are dropped, since their effect is already applied to the account names shown.
  (An `account` declaration inside an `apply account` block is reproduced as written, without the parent account prefix.)
- Directives which hledger ignores (for compatibility with Ledger) are not exported.
- By default, periodic transaction rules (`~`) and auto posting rules (`=`) are exported as directives.
  With `--forecast` and/or `--auto`, the generated transactions (at the end of the output) and postings
  are exported instead, and the rules are not. In other words, these flags materialise the rules.
  Postings generated by `--infer-equity` are exported too.
  (In Beancount output, these rules are never exported, only whatever has been generated.)
- A query still selects which transactions are shown, but all directives and comments are kept.
- Transactions from non-journal files (eg an included CSV file) are added at the end.
- The `txt` (default), `ledger` and `beancount` output formats are supported.
  With `-O ledger`, transactions use Ledger's lot syntax, and directives which hledger accepts
  but Ledger does not (`decimal-mark`, a one-line `commodity` directive with an amount,
  a periodic transaction rule with a description, an auto posting rule with `*N` amount multipliers)
  are commented out, with an explanatory comment. Other hledger-specific syntax may remain;
  see [Ledger output](#ledger-output).
  With `-O beancount`, Beancount `option`, `commodity`, `open` and `price` directives are generated
  from the journal's declarations and data, other directives (which have no Beancount equivalent) are dropped,
  and comments are converted to Beancount comments; see [Beancount output](#beancount-output).
  Note for both Ledger and Beancount, manual fixups may still be required in some cases; but the export will be a good start.

### print, other features

With `-B`/`--cost`, amounts with [costs](https://hledger.org/hledger.html#costs)
are shown converted to cost.

With `--invert`, posting amounts are shown with their sign flipped.
It could be useful if you have accidentally recorded some transactions with the wrong signs.

With `--new`, print shows only transactions it has not seen on a previous run.
This uses the same deduplication system as the [`import`](#import) command.
(See import's docs for details.)

With `-m DESC`/`--match=DESC`, print shows one recent transaction
whose description is most similar to DESC.
DESC should contain at least two characters.
If there is no similar-enough match, 
no transaction will be shown and the program exit code will be non-zero.

With `--locations`, print adds the source file and line number to every transaction, as a tag.

### print output format

This command also supports the
[output destination](hledger.html#output-destination) and
[output format](hledger.html#output-format) options
The output formats supported are
`txt`, `ledger`, `beancount`, `csv`, `tsv`, `html`, `fods`, `json` and `sql`.

The `ledger` format is currently the same as `txt` except it renders amounts' cost basis
using Ledger's lot syntax (`[DATE] (LABEL) {COST}`)
instead of hledger's (`{DATE, "LABEL", COST}`).

The `beancount` format tries to produce Beancount-compatible output, as follows:

- Transaction and postings with unmarked status are converted to cleared (`*`) status.
- Transactions' payee and note are backslash-escaped and double-quote-escaped and wrapped in double quotes.
- Transaction and posting tags are converted to Beancount metadata lines.
- Commodity symbols are converted to upper case, and a small number of currency symbols
  like `$` are converted to the corresponding currency names.
- Account name parts are capitalised and unsupported characters are replaced with `-`.
  The first part must be one of Assets, Liabilities, Equity, Income or Expenses;
  if it is not, but the account's [type](#account-types) is known (declared or inferred),
  the corresponding one of those is prepended; otherwise an error is raised.
  (Or, use `--alias` options to bring your accounts into compliance.)
- Balance assignments are converted to explicit amounts.
- Virtual and balanced virtual postings are dropped.

By default only transactions are shown.
With `--export`, the directives Beancount needs are also generated:
options (a commented-out tolerance option, and `operating_currency` for the currencies used in costs),
a `commodity` directive for each declared commodity,
an `open` directive for each declared or used account (on the account's earliest posting date, or the earliest transaction date),
and `price` directives. Account and commodity tags become metadata on those directives,
and an account's `lots:` tag becomes the Beancount booking method.
Other hledger directives are dropped, and top-level comments are converted to Beancount comments.

Here's an example of print's CSV output:

```cli
$ hledger print -Ocsv
"txnidx","date","date2","status","code","description","comment","account","amount","commodity","debit","credit","posting-status","posting-comment"
"1","2008/01/01","","","","income","","assets:bank:checking","1","$","1","","",""
"1","2008/01/01","","","","income","","income:salary","-1","$","","1","",""
"2","2008/06/01","","","","gift","","assets:bank:checking","1","$","1","","",""
"2","2008/06/01","","","","gift","","income:gifts","-1","$","","1","",""
"3","2008/06/02","","","","save","","assets:bank:saving","1","$","1","","",""
"3","2008/06/02","","","","save","","assets:bank:checking","-1","$","","1","",""
"4","2008/06/03","","*","","eat & shop","","expenses:food","1","$","1","","",""
"4","2008/06/03","","*","","eat & shop","","expenses:supplies","1","$","1","","",""
"4","2008/06/03","","*","","eat & shop","","assets:cash","-2","$","","2","",""
"5","2008/12/31","","*","","pay off","","liabilities:debts","1","$","1","","",""
"5","2008/12/31","","*","","pay off","","assets:bank:checking","-1","$","","1","",""
```

- There is one CSV record per posting, with the parent transaction's fields repeated.
- The "txnidx" (transaction index) field shows which postings belong to the same transaction.
  (This number might change if transactions are reordered within the file,
  files are parsed/included in a different order, etc.)
- The amount is separated into "commodity" (the symbol) and "amount" (numeric quantity) fields.
- The numeric amount is repeated in either the "debit" or "credit" column, for convenience.
  (Those names are not accurate in the accounting sense; it just puts zero or greater amounts
  under debit and negative amounts under credit.)
