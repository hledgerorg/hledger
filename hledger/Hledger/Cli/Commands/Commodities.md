## commodities

(comm)

List the commodity symbols used or declared in the journal.

```flags
Flags:
     --used                 list commodities used in transactions
     --priced               list commodities appearing in P directives
     --declared             list commodities declared by commodity directives
     --undeclared           list commodities used or priced but not declared
     --unused               list commodities declared but not used or priced
     --find                 list the first commodity matched by the first
                            argument (a case-insensitive infix regexp)
     --directives           show as commodity directives (with their display
                            styles), for use in journals
```

Most of these flags can be combined.
With `--directives`, it shows valid commodity directives, declaring each commodity's
(declared or inferred) display style, which could be pasted into a journal file.
Some kinds of query argument are supported: `cur:`, `tag:`, and `date:`
(also `-b`/`-e`/`-p` report period options).

Providing a date query will affect which commodities are reported, as follows:

| Flag           | No date query                             | With a date query                              |
|----------------|-------------------------------------------|------------------------------------------------|
| (none)         | declared ∪ transacted ∪ priced            | (transacted ∪ priced) in the period            |
| `--used`       | transacted in the journal                 | transacted in the period                       |
| `--priced`     | appearing in any P directive              | appearing in a P directive in the period       |
| `--declared`   | declared with a `commodity` directive     | same                                           |
| `--undeclared` | (transacted ∪ priced) ∖ declared          | (transacted ∪ priced in the period) ∖ declared |
| `--unused`     | declared ∖ (transacted ∪ priced)          | same                                           |
| `--find`       | the first commodity matching the argument | same                                           |

Example:

```cli
$ hledger commodities
$
AAPL
EUR
```
