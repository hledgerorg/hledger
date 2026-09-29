# ERRORS

hledger produces a variety of error messages in different situations.
They are intended first for humans and secondly for parsing by tools
like [flycheck-hledger][].
Here we collect examples of these errors, which are listed below
for reference, and also tested as part of our test suite.
This document is the README in the [hledger/test/errors/][] directory,
and also published as Developer docs > [ERRORS][] on hledger.org.

Each error has 

- a name (similar to [hledger check][] names when applicable)
- an executable script in this directory which reproduces the error (like `balanced.j`)
- which usually can also be used as a data file for manual testing (`hledger -f balanced.j check`)
- sometimes supplementary data files (like `csvdateparse.csv.rules`)
- a shelltestrunner test (like `balanced.test`)

## What belongs here

These tests are about how errors are presented.
Each one tests an entire error message: the first line with its file position,
the excerpt, and the explanation.
This is the layout that tools like flycheck-hledger rely on,
and elsewhere it is mostly not tested.

We want one example of each distinct kind of error message, not every error.
Errors built by the same code, with the same layout, share one example.
For example, there are dozens of lot errors,
but they come in a few shapes (an error at a posting, an error at a whole transaction, ..),
and one example of each is enough.

Whether a given input produces a given error is a separate concern.
That's tested along with the feature, in the regular functional tests
(`check-*.test`, `journal/*.test`, `csv.test` etc.),
usually by matching just a key phrase of the message.

So when adding a new kind of error message, or changing an error's layout,
also add or update an example here.

## Procedures

These use the `hledger` in `$PATH`. To use your latest build, run them from inside the
hledger repo with `stack exec -- make ...` (and `-C hledger/test/errors` if needed).

To update this readme with the latest error messages, run `make readme`.

To test all of these error messages with hledger, run `make test`.
Requires shelltestrunner, the latest version is best.
They are also run as part of the functional tests (`just functest`).

To add a new error example:

- add an executable script reproducing the error, following the existing ones
- add a row for it in the table below
- run `make tests` to draft a test for it (only scripts with no `.test` file are affected)
- review and edit the draft; it matches just the first 300 characters,
  and wording-sensitive lines can be loosened with `.*`
- run `make readme`

The existing tests have been adjusted by hand in this way,
so don't regenerate them; edit them directly when an error message changes.

To test these errors with flycheck-hledger,
customize `flycheck-hledger-*` in Emacs to enable all appropriate checks,
then open the data files to see how flycheck handles them.
`C-c ! l` opens a pane for easy viewing.

<!-- Use absolute urls here, this page can be viewed on github or hledger.org. -->
[hledger/test/errors/]:  https://github.com/hledgerorg/hledger/tree/main/hledger/test/errors
[ERRORS]:                https://hledger.org/ERRORS.html
[hledger check]:         https://hledger.org/hledger.html#check
[flycheck-hledger-home]: https://github.com/DamienCassou/flycheck-hledger
[flycheck-hledger-10]:   https://github.com/DamienCassou/flycheck-hledger/pull/10
[flycheck-hledger]:      https://hledger.org/emacs.html#flycheck-hledger


## Error improvement

Work is ongoing to make our error messages more consistent and more useful
([#1436](https://github.com/hledgerorg/hledger/issues/1436),
[#1885](https://github.com/hledgerorg/hledger/pull/1885), 
[#1886](https://github.com/hledgerorg/hledger/pull/1886)..).
This is a big project, and your help is welcome; every bit of progress
counts, and this is a fast way to help users.

- [x] ~~phase 1: update flycheck to detect journal errors of current hledger release (and keep a branch updated to detect errors of latest hledger main)~~
- [x] ~~phase 2: survey/document current journal errors & status~~
- [x] ~~phase 3: pick a new standard format~~
- [x] ~~phase 4: implement standard format for all~~
- [x] ~~phase 5: implement accurate lines for all~~
- [x] ~~phase 6: implement accurate columns for all  [where possible; we currently do not save the position of every part of the transaction, so most errors do not report columns]~~
- [x] ~~phase 7: implement useful highlighted excerpts for all  [we show imperfect but useful highlighted regions]~~
- [x] ~~phase 8: implement accurate flycheck region for all  [flycheck-detected regions are imperfect but useful]~~
- [x] ~~phase 9: do likewise for timeclock errors~~
- [x] ~~phase 10: do likewise for timedot errors~~
- [ ] phase 11: do likewise for csv errors
- [ ] phase 12: do likewise for other command line errors
- [x] ~~phase 13: decide/add error ids/explanations/web pages ? not needed~~
- [ ] phase 14: support Language Server Protocol & Visual Code

## Standard error format

Here is our current preferred layout for error messages. 
It is similar to the parse error messages we get from megaparsec
(since it's easier to follow that than change it):
```
hledger: Error: FILE:LOCATION:
EXCERPT
EXPLANATION
```

Notes:

- line 1 includes "hledger" (dropping this would require some effort), the word "Error", and the error position
- FILE is the file path
- LOCATION is `LINE[-ENDLINE][:COLUMN[-ENDCOLUMN]]`
- EXCERPT is a short visual snippet whenever possible, with the error region highlighted, line numbers, and colour when supported. 
  This section must be easy for flycheck to ignore. (All lines begin with a space or a digit.)
  When there is more than one excerpt, they are separated by an empty line.
- EXPLANATION briefly explains the problem, and suggests remedies if possible.
  It can be dynamic, showing context-sensitive info. (ShellCheck's summaries are static.)
- this layout is based on megaparsec's. For comparison, rustc puts summary on line 1 and location on line 2:
  ```
  Error[ID]: SUMMARY
  at FILE:LOCATION
  EXCERPT
  [DETAILS]
  ```
- try 
  <https://github.com/mesabloo/diagnose>,
  <https://hackage.haskell.org/package/errata>,
  <https://hackage.haskell.org/package/chapelure> later ?

## Limitations

Here are some current limitations of hledger's error messages:

- We report only one error at a time. You have to fix (or bypass) the current error to see any others.

- We currently don't save perfect position information when parsing,
  so we sometimes report only line number(s), without column number(s).

- For the same reason, the excerpts we show in error messages are not the original data.
  Instead we show a synthetic rendering that is similar enough to be explanatory.
  The columns marked with ^ in such an excerpt are columns in the rendered text,
  which can differ from the source file; so they are not included in the error's position,
  which (except for parse errors) shows only the line number(s).


## Error messages

Here is the current status as of
hledger (see version below) and flycheck-hledger 1.1.0.
Click error names to see an example. The table headings mean:

- std format - the error message follows our standard error format
- line       - correct line numbers are reported
- column     - the error's column(s) are identified: in the position (FILE:LINE:COL) for parse errors,
               otherwise just by the ^ marks in the excerpt (see Limitations)
- excerpt    - a useful excerpt is shown, ideally with the error highlighted (✓✓)
- flycheck   - the current flycheck release (or a PR branch) recognises the error and highlights a useful region

| error name                                            | std format | line | column | excerpt | flycheck |
|-------------------------------------------------------|------------|------|--------|---------|----------|
| [accounts](#accounts)                                 | ✓          | ✓    | ✓      | ✓✓      | ✓        |
| [assertions](#assertions)                             | ✓          | ✓    | ✓      | ✓✓      | ✓        |
| [autobalanced](#autobalanced)                         | ✓          | ✓    | -      | ✓       | ✓        |
| [balanced](#balanced)                                 | ✓          | ✓    | -      | ✓       | ✓        |
| [basis](#basis)                                       | ✓          | ✓    | ✓      | ✓✓      | ✓        |
| [commodities](#commodities)                           | ✓          | ✓    | ✓      | ✓✓      | ✓        |
| [lots-gain](#lots-gain)                               | ✓          | ✓    | -      | ✓       | ✓        |
| [lots-name](#lots-name)                               | ✓          | ✓    | ✓      | ✓✓      | ✓        |
| [lots-tag](#lots-tag)                                 | ✓          | ✓    | -      | ✓       | ✓        |
| [lots](#lots)                                         | ✓          | ✓    | -      | ✓       | ✓        |
| [ordereddates](#ordereddates)                         | ✓          | ✓    | ✓      | ✓✓      | ✓        |
| [parseable](#parseable)                               | ✓          | ✓    | ✓      | ✓✓      | ✓        |
| [parseable-dates](#parseable-dates)                   | ✓          | ✓    | ✓      | ✓✓      | ✓        |
| [parseable-regexps](#parseable-regexps)               | ✓          | ✓    | ✓      | ✓✓      | ✓        |
| [payees](#payees)                                     | ✓          | ✓    | ✓      | ✓✓      | ✓        |
| [recentassertions](#recentassertions)                 | ✓          | ✓    | ✓      | ✓✓      | ✓        |
| [tags](#tags)                                         | ✓          | ✓    | -      | ✓       | ✓        |
| [uniqueleafnames](#uniqueleafnames)                   | ✓          | ✓    | ✓      | ✓✓      | ✓        |
| [tcclockouttime](#tcclockouttime)                     | ✓          | ✓    | ✓      | ✓✓      | ✓        |
| [tcorderedactions](#tcorderedactions)                 | ✓          | ✓    | ✓      | ✓✓      | ✓        |
| [tdquantity](#tdquantity)                             | ✓          | ✓    | ✓      | ✓✓      | ✓        |
| [csvamountonenonzero](#csvamountonenonzero)           | ✓          | ✓    | -      | ✓       | ✓        |
| [csvamountparse](#csvamountparse)                     | ✓          | ✓    | -      | ✓       | ✓        |
| [csvbalanceparse](#csvbalanceparse)                   | ✓          | ✓    | -      | ✓       | ✓        |
| [csvbalancetypeparse](#csvbalancetypeparse)           | ✓          | ✓    | ✓      | ✓✓      | ✓        |
| [csvdateformat](#csvdateformat)                       | ✓          | ✓    | -      | ✓       | ✓        |
| [csvdateparse](#csvdateparse)                         | ✓          | ✓    | -      | ✓       | ✓        |
| [csvdaterule](#csvdaterule)                           |            |      |        |         |          |
| [csvdecimalmarkparse](#csvdecimalmarkparse)           | ✓          | ✓    | ✓      | ✓✓      | ✓        |
| [csvifblocknomatchers](#csvifblocknomatchers)         |            | ✓    | ✓      | ✓       | ✓        |
| [csvifblocknonempty](#csvifblocknonempty)             |            | ✓    | ✓      | ✓       | ✓        |
| [csviftablefieldnames](#csviftablefieldnames)         |            | ✓    | ✓      | ✓✓      | ✓        |
| [csviftablenonempty](#csviftablenonempty)             |            | ✓    | ✓      | ✓       | ✓        |
| [csviftablevaluecount](#csviftablevaluecount)         |            | ✓    | ✓      | ✓       | ✓        |
| [csvskipvalue](#csvskipvalue)                         | ✓          | ✓    | ✓      | ✓✓      | ✓        |
| [csvstatusparse](#csvstatusparse)                     | ✓          | ✓    | -      | ✓       | ✓        |
| [csvtwofields](#csvtwofields)                         | ✓          | ✓    | -      | ✓       | ✓        |
| [csvstdinrules](#csvstdinrules)                       |            |      |        |         |          |


<!-- GENERATED: -->
hledger 1.99-g50c8a6303-20260923 error messages:

### accounts
```
hledger: Error: /path/to/accounts.j:4:
  | 2022-01-01
4 |     (ß)                                            1
  |      ^

Strict account checking is enabled, and
account "ß" has not been declared.
Consider adding an account directive. Examples:

account ß
```


### assertions
```
hledger: Error: /path/to/assertions.j:4:8:
  | 2022-01-01
4 |     a                                              0 = 1
  |                                                      ^^^

Balance assertion failed in a
In commodity "" at this point, excluding subaccounts, ignoring costs,
the asserted balance is:        1
but the calculated balance is:  0
(difference: 1)
To troubleshoot, check this account's running balance with assertions disabled, eg:
hledger reg -E --ignore-assertions '2022-01-02'a$ cur:'' -e
```


### autobalanced
```
hledger: Error: /path/to/autobalanced.j:3-4:
3 | 2022-01-01
  |     a                                              1

This transaction is unbalanced.
The real postings' sum should be 0 but is 1
  1  =  1
```


### balanced
```
hledger: Error: /path/to/balanced.j:5-7:
5 | 2022-01-01
  |     a                                              1 A
  |     b                                             -1 B

This multi-commodity transaction is unbalanced.
Automatic commodity conversion is disabled by strict mode or the balanced check.
The real postings' sum should be 0 but is 1 A, -1 B
  1 A  +  -1 B  =  1 A, -1 B
```


### basis
```
hledger: Error: /path/to/basis.j:4:
  | 2022-01-01 buy
4 |     assets:stocks                                 10 AAPL {$60} @ $50
  |     ^^^^^^^^^^^^^
  |     assets:checking

This acquire posting's cost basis ($60) differs from its transacted cost ($50).
Options:
  - drop {} or {{}} so basis is inferred from the transacted cost
  - drop @ or @@ so transacted cost is inferred from the basis
  - use {{TotalCost}} or write the per-unit basis at higher precision
  - if the difference is real (gift, NSO, RSU, etc.), fund it via a separate posting
```


### commodities
```
hledger: Error: /path/to/commodities.j:6:
  | 2022-01-01
6 |     (a)                                          A 1
  |                                                  ^^^

Strict commodity checking is enabled, and
commodity "A" has not been declared.
Consider adding a commodity directive. Examples:

commodity A1000.00
commodity 1.000,00 A
```


### lots-gain
```
hledger: Error: /path/to/lots-gain.j:7:
7 | 2022-02-01 sell
  |     assets:stocks                                -10 AAPL {$50} @ $55
  |     assets:checking                             $550
  |     revenues:gains                             $-999

This disposal's realised gain amount is wrong.
  written:    $-999
  calculated: $-50

Postings were read as: dispose, unclassified, gain.
```


### lots-name
```
hledger: Error: /path/to/lots-name.j:4:
  | 2022-01-01 buy
4 |     assets:stocks:{not a lot}                     10 AAPL
  |     ^^^^^^^^^^^^^^^^^^^^^^^^^
  |     assets:checking                            $-500

invalid lot name: not a lot

A final account name part enclosed in { } must be a valid lot subaccount name.
Please adjust the account name, or use --ignore-lots/-I.
```


### lots-tag
```
hledger: Error: /path/to/lots-tag.j:3:
3 | commodity AAPL  ; lots: BADMETHOD

unrecognised lots: tag value "BADMETHOD".
Use FIFO, LIFO, HIFO, AVERAGE, SPECID, FIFOALL, LIFOALL, HIFOALL, AVERAGEALL, or nothing (meaning FIFO)
```


### lots
```
hledger: Error: /path/to/lots.j:8:
  | 2022-02-01 sell
8 |     assets:stocks                                -15 AAPL {$50} @ $55
  |     assets:checking                             $825

Insufficient lots for commodity AAPL in account assets:stocks: need 15 but only 10 available
Lots matching {$50}:
  {2022-01-01, $50}  10
  Total: 10 AAPL

Postings were read as: dispose, unclassified.
```


### ordereddates
```
hledger: Error: /path/to/ordereddates.j:10:
7 | 2022-01-02 p
  |     (a)                                            1

10 | 2022-01-01 p
   | ^^^^^^^^^^
   |     (a)                                            1

Ordered dates checking is enabled, and this transaction's
date (2022-01-01) is out of order with the previous transaction.
Consider moving this entry into date order, or adjusting its date.
```


### parseable-dates
```
hledger: Error: /path/to/parseable-dates.j:3:1:
  |
3 | 2022/1/32
  | ^^^^^^^^^

This is not a valid date, please fix it.
```


### parseable-regexps
```
hledger: Error: /path/to/parseable-regexps.j:3:8:
  |
3 | alias /(/ = a
  |        ^

This regular expression is invalid or unsupported, please correct it: (
```


### parseable
```
hledger: Error: /path/to/parseable.j:3:2:
  |
3 | 1
  |  ^
unexpected newline
expecting date separator or digit
```


### payees
```
hledger: Error: /path/to/payees.j:6:
6 | 2022-01-01 p
  |            ^
  |     (a)                                          A 1

Strict payee checking is enabled, and
payee "p" has not been declared.
Consider adding a payee directive. Examples:

payee p
```


### recentassertions
```
hledger: Error: /path/to/recentassertions.j:18:
   | 2022-01-09 bad1
18 |     a                                              0
   |     ^

The recentassertions check is enabled, so accounts with balance assertions
must have a recent one, not more than 7 days older than their latest posting.
In account: a
the last assertion was on 2022-01-01, 8 days before this latest posting.
Consider adding a new balance assertion to the above posting. Eg:

    a                                              0 = BALANCE
```


### tags
```
hledger: Error: /path/to/tags.j:3:
3 | 2022-01-01  ; atag:
  |     (a)                                            1

Strict tag checking is enabled, and
tag "atag" has not been declared.
Consider adding a tag directive. Examples:

tag atag
```


### uniqueleafnames
```
hledger: Error: /path/to/uniqueleafnames.j:12:
  | 2022-01-01 p
9 |     (a:c)                                          1

   | 2022-01-01 p
12 |     (b:c)                                          1
   |        ^

Checking for unique account leaf names is enabled, and
account leaf name "c" is not unique.
It appears in these account names, which are used in 2 places:
a:c
b:c

Consider changing these account names so their last parts are different.
```


### tcclockouttime
```
hledger: Error: /path/to/tcclockouttime.timeclock:5:1:
4 | i 2022-01-01 00:01:00 a
5 | o 2022-01-01 00:00:00
  | ^

This clockout is earlier than its clockin, on line 4.
```


### tcorderedactions
```
hledger: Error: /path/to/tcorderedactions.timeclock:8:1:
7 | i 2022-01-01 00:00:00 a
8 | i 2022-01-01 00:01:00 a
  | ^

This clockin overlaps the session in the same account which began on line 7.
Overlapping sessions with the same account name are not supported.
```


### tdquantity
```
hledger: Error: /path/to/tdquantity.timedot:4:6:
  |
4 | a  1.x
  |      ^
unexpected 'x'
expecting "mo", ';', 'd', 'h', 'm', 's', 'w', 'y', end of input, exponent, newline, or space
```


### csvamountonenonzero
```
hledger: Error: /path/to/csvamountonenonzero.csv:5:
5 | 2022-01-03,1,2

Multiple non-zero amounts were assigned for an amount field, for posting 1.
record: 2022-01-03,1,2
  %1   2022-01-03
  %2   1
  %3   2
rule "amount-in %2" assigned value "1"       (/path/to/csvamountonenonzero.csv.rules:3)
rule "amount-out %3" assigned value "2"      (/path/to/csvamountonenonzero.csv.rules:4)

Please ensure just one non-zero amount is assigned, perhaps with an if rule.
See also: https://hledger.org/hledger.html#setting-amounts
(hledger manual -> CSV format -> Tips -> Setting amounts)
```


### csvamountparse
```
hledger: Error: /path/to/csvamountparse.csv:5:
5 | 2022-01-03,badamount

could not parse "badamount" as an amount
record: 2022-01-03,badamount
  %1   2022-01-03
  %2   badamount
hledger field assignment rules:
  amount:      %2                            (/path/to/csvamountparse.csv.rules:3)
  date:        %1                            (/path/to/csvamountparse.csv.rules:2)

the parse error is:      1:10:
  |
1 | badamount
  |          ^
unexpected end of input
expecting '+', '-', or number

you may need to change your amount*, balance*, or currency* rules, or add or change your skip rule
```


### csvbalanceparse
```
hledger: Error: /path/to/csvbalanceparse.csv:3:
3 | 2022-01-03,badbalance

could not parse "badbalance" as balance1 amount
record: 2022-01-03,badbalance
  %1   2022-01-03
  %2   badbalance
hledger field assignment rules:
  balance:     %2                            (/path/to/csvbalanceparse.csv.rules:3)
  date:        %1                            (/path/to/csvbalanceparse.csv.rules:2)

the parse error is:      1:11:
  |
1 | badbalance
  |           ^
unexpected end of input
expecting '+', '-', or number
```


### csvbalancetypeparse
```
hledger: Error: /path/to/csvbalancetypeparse.csv.rules:4:14:
  |
4 | balance-type badtype
  |              ^
balance-type "badtype" is invalid. Use =, ==, =* or ==*.
```


### csvdateformat
```
hledger: Error: /path/to/csvdateformat.csv:4:
4 | a,b

could not parse "a" as a date using date format "YYYY/M/D", "YYYY-M-D" or "YYYY.M.D"
record: a,b
  %1   a
  %2   b
the date rule is:   %1                       (/path/to/csvdateformat.csv.rules:2)
the date-format is: unspecified
you may need to change your date rule, add a date-format rule, or change your skip rule
for m/d/y or d/m/y dates, use date-format %-m/%-d/%Y or date-format %-d/%-m/%Y
```


### csvdateparse
```
hledger: Error: /path/to/csvdateparse.csv:4:
4 | baddate,b

could not parse "baddate" as a date using date format "%Y-%m-%d"
record: baddate,b
  %1   baddate
  %2   b
the date rule is:   %1                       (/path/to/csvdateparse.csv.rules:2)
the date-format is: %Y-%m-%d
you may need to change your date rule, change your date-format rule, or change your skip rule
for m/d/y or d/m/y dates, use date-format %-m/%-d/%Y or date-format %-d/%-m/%Y
```


### csvdaterule
```
hledger: Error: /path/to/csvdaterule.csv.rules:
Please specify (at top level) the date field. Eg: date %1
```


### csvdecimalmarkparse
```
hledger: Error: /path/to/csvdecimalmarkparse.csv.rules:4:14:
  |
4 | decimal-mark badmark
  |              ^
decimal-mark's argument should be "." or "," (not "badmark")
```


### csvifblocknomatchers
```
hledger: Error: /path/to/csvifblocknomatchers.csv.rules:3:1:
  |
3 | # a comment, not a matcher
  | ^
start of conditional block found, but no matchers afterward
(matchers should be on the same line as "if", or on the following lines.
Note: a line beginning with a comment character (# or ;) is a comment;
to match a leading comment character, escape it, eg \#)
```


### csvifblocknonempty
```
hledger: Error: /path/to/csvifblocknonempty.csv.rules:2:1:
  |
2 | if foo
  | ^
start of conditional block found, but no assignment rules afterward
(assignment rules in a conditional block should be indented)
```


### csviftablefieldnames
```
hledger: Error: /path/to/csviftablefieldnames.csv.rules:2:9:
  |
2 | if,date,nosuchfield,description
  |         ^^^^^^^^^^^^
unexpected "nosuchfield,"
expecting "account1", "account10", "account11", "account12", "account13", "account14", "account15", "account16", "account17", "account18", or other valid values (697 more)
```


### csviftablenonempty
```
hledger: Error: /path/to/csviftablenonempty.csv.rules:2:1:
  |
2 | if,date,description,comment
  | ^
start of conditional table found, but no assignment rules afterward
```


### csviftablevaluecount
```
hledger: Error: /path/to/csviftablevaluecount.csv.rules:4:1:
  |
4 | one,val1
  | ^
line of conditional table should have 2 values, but this one has only 1
```


### csvskipvalue
```
hledger: Error: /path/to/csvskipvalue.csv.rules:2:6:
  |
2 | skip badval
  |      ^
skip's argument should be a number of lines, or nothing (not "badval")
```


### csvstatusparse
```
hledger: Error: /path/to/csvstatusparse.csv:7:
7 | 2022-01-04,badstatus

could not parse status value "badstatus" (should be *, ! or empty)
the parse error is:      1:1:
  |
1 | badstatus
  | ^
unexpected 'b'
expecting '!', '*', or end of input
```


### csvtwofields
```
hledger: Error: /path/to/csvtwofields.csv:4:
4 | b

This CSV record has less than two fields.
Perhaps the separator is wrong (it can be set with a separator rule).
```


### csvstdinrules
```
hledger: Error: please use --rules when reading CSV from stdin
```

