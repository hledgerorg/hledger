# SPEC: functions in CSV rules

CSV rules field assignment values can contain `%{...}` expressions,
which call built-in functions on CSV values:

```rules
description %{default(%payee, capitalize(%desc))}
account2    expenses:%{lower(default(%category, "misc"))}
comment     ref:%{replace(%memo, ".*ref#([0-9]+).*", "\1")}, month:%{substr(%date, 1, 7)}
amount1     %{negate(%amt)}
if amazon
 comment    %{join(", ", comment, "shop:amazon")}
```

User docs: hledger manual, CSV > Field assignment > Functions.
Code: `hledger-lib/Hledger/Read/RulesReader.hs` (`TemplateExpr`,
`templateexprp`, `templateFunctions`, `evalTemplateExpr`, `hledgerFieldValue`,
`checkFieldReferenceLoops`).
Tests: `hledger/test/csv.test` 88-99.

## Syntax

```
expr     = "%{" ws term ws "}" ;
term     = call | hfieldref | fieldref | matchref | string | number ;
call     = name ws "(" ws [ term { ws "," ws term } ] ws ")" ;
name     = lowercase letter, { lowercase letter | digit | "_" } ;
hfieldref = name ;                                               (a hledger field name)
fieldref = "%" fieldname [ "_" rownum ] | "%(" fieldname ")" ;   (as elsewhere in values)
matchref = "\" digits ;                                          (as elsewhere in values)
string   = '"' { char | '\"' | '\\' } '"' ;
number   = digits ;
```

- An expression can appear anywhere a field reference can in a field assignment value,
  in `if` blocks and `if` tables too. In an `if` table, the delimiter does not
  separate values when it is inside `%{...}`.
- Inside braces, CSV field references keep their `%`, and a bare name
  (not followed by `(`) is a hledger field: `date`, `date2`, `status`, `code`,
  `description`, `comment`, `amount`, `balance`, `currency`, and the
  numbered `accountN`, `commentN`, `amountN`, `balanceN`, `currencyN`.
  The `amount-in`/`amount-out` forms are excluded.
- In strings, `\"` and `\\` are escapes; any other backslash is kept as is.
- `%{` always begins an expression. (Before functions, it was literal text.)

## Evaluation

- All values are text. Field references give the field's value with outer
  whitespace removed; empty or missing fields give `""`.
- A hledger field name gives the text assigned to that field by the rules
  (with outer whitespace removed), not a converted or default value:
  `%{amount1}` is the assigned text, before sign handling, and is `""` if only
  `amount` was assigned; `%{account2}` is `""` when unassigned, not `expenses:unknown`.
  - In an assignment to the same field, it gives the value from the
    field's previous assignment, or `""` if there is none. Assignments are
    applied in the documented order: top-level ones (including those made by
    the `fields` list), then those in matched `if` blocks, each in file order.
    So a top-level assignment written after an `if` block still comes before it.
  - In an assignment to another field, it gives that field's final value, or `""`
    if it has no assignment. This doesn't depend on where the assignments are written.
- A bare `\N` argument is a match group of the enclosing `if` rule's matcher.
  `\N` inside a string is not interpolated, so in `replace`'s replacement it
  refers to `replace`'s own regex.
- The result of each expression has outer whitespace removed, like other
  interpolated values.
- `_ROWNUM` references work as in plain values, after `merge`.
- Functions never fail at runtime. Bad input gives text that may then fail
  later parsing (eg a non-numeric amount), with the usual conversion error.

## Functions

| function | result |
|---|---|
| `upper(s)`, `lower(s)` | case changed |
| `capitalize(s)`, `capitalise(s)` | each whitespace-separated word's first letter upper case, the rest lower case |
| `trim(s)` | outer whitespace removed |
| `negate(amt)` | sign flipped |
| `abs(amt)` | sign removed |
| `concat(s, ...)` | arguments joined |
| `join(sep, s, ...)` | the `s` arguments that are not empty or all whitespace, separated by `sep` |
| `default(s, ...)` | first argument that is not empty or all whitespace, or `""` |
| `replace(s, "re", repl)` | all case-insensitive matches of `re` replaced by `repl`, which can use `\N` for `re`'s groups |
| `substr(s, start, len)` | `len` characters (or all, if omitted) from 1-based position `start`; out-of-range positions are clamped |

`negate` and `abs` work on amount text without parsing the number (via
`simplifySign`): an optional commodity symbol before or after, and a sign
that is `-`, `+` or enclosing parentheses, before the number or after a
leading symbol (`-$5`, `$-5`, `USD -5`, `(5 USD)`, `$(5)`). Not supported:
a trailing sign (`5-`), or `(5) USD`.

## Checks when reading rules

Reported as rules file parse errors, with position and excerpt (same layout as
other rules parse errors; `hledger/test/errors/csvskipvalue.test` covers it):

- syntax errors: unterminated `%{`, string or argument list, unexpected text
- unknown function name (the message lists the known ones)
- wrong number of arguments
- `replace`: the regex must be a string literal and valid; a literal
  replacement's `\N` must not exceed the regex's group count (counted
  approximately: unescaped `(` outside bracket expressions)
- `substr`: `start` and `len` must be number literals, `start` at least 1
- unknown hledger field name (the message suggests `%NAME` for a CSV field,
  and lists the hledger fields); a function name without parentheses
- hledger field references forming a loop, where a field's value depends on
  itself through other fields (`checkFieldReferenceLoops`, at the end of
  `rulesp`). All assignments are considered, whether or not they could apply
  to the same record, so a loop through mutually exclusive `if` blocks is
  also rejected. It is reported at the last-written assignment in the loop.
  (Evaluation also stops at a loop, giving `""`, so it can't hang if this check misses one.)

Syntax errors inside `%{...}` are converted to "fancy" errors (`region` in
`templateexprp`). Since megaparsec 9.8, when both branches of
`try p <|> q` fail with plain errors, the error at q's start wins, so a deep
error in a value would otherwise be reported as a confusing "unexpected
space" from `fieldassignmentp`'s other branch. Fancy errors are still merged
by offset.

## Design choices

- **`%{...}`** extends the existing `%` interpolation, and was previously unused.
  Rejected: `%name(args)` (already means a field reference then text),
  `%(fn args)` (clashes with `%(field)`; a no-argument function and a
  field of the same name would be indistinguishable), `${...}` (`$` is common
  in amount values).
- **Function calls, not pipes** (`%{desc | upper}`): more familiar to the
  spreadsheet and SQL users who prepare CSV, and they nest. Pipes could be
  added later inside braces as sugar.
- **Resembles SQL and spreadsheet formulas**: `upper`, `lower`, `trim`,
  `abs`, `concat`, `substr(s, start, len)` (1-based, as in SQL `SUBSTR`),
  `replace` (like SQL `REGEXP_REPLACE` and Sheets `REGEXREPLACE`).
  `capitalize` is named as in Python/Jinja but works per word, like spreadsheet `PROPER`.
  `default` is named as in Jinja/Liquid; it is SQL's `COALESCE`.
- **Text to transform first**: as in SQL and spreadsheet functions (and method calls),
  unlike Python's `re.sub` or PHP's `preg_replace`. Consistent across all
  functions, and would read naturally with pipes.
- **`replace` is case-insensitive** and replaces every match, like CSV
  rules matchers (most regex replace functions are case-sensitive by default).
  Backreferences are `\N`, as in hledger's other match groups (Sheets and JavaScript use `$N`).
- **`capitalize` splits words only at whitespace**, so it doesn't produce
  `Mcdonald'S` like spreadsheet `PROPER` and Python's `title()` do.
- **Text-based amounts**: `negate` and `abs` don't depend on `decimal-mark`
  or digit group settings, matching how `-%amt` already works.
- **Bare names are hledger fields**: CSV fields keep `%` inside braces, so
  `%{comment}` can only mean the hledger field, whereas a plain `%comment`
  is the CSV field named `comment` (often present, since naming CSV fields
  after hledger fields is how a `fields` list assigns them).
  Function names and hledger field names don't overlap; keep it that way,
  except perhaps deliberately (a future `date()` function), since a forgotten
  `(...)` would then silently give a field value. `skip`, `end` and `merge`
  are excluded, keeping them free as future keywords. Rejected: a sigil
  for hledger fields inside braces (`%{@comment}`): one more thing to learn.
- **Final values, except for the field's own name**: references are like
  spreadsheet cell references, independent of position, matching how a
  field's value is otherwise determined (the last assignment wins). The field's
  own name means its previous value, since its final value would be circular;
  this is what allows appending (as in `x = x + 1`).
  Rejected: the value so far at this point in the rules (changes when rules
  are reordered or moved to an included file).
- **`join` takes the separator first**, unlike the other functions' text-first
  order, as in SQL `CONCAT_WS` and Sheets `TEXTJOIN`, which also take a
  variable number of texts. It skips empty parts like `TEXTJOIN` with
  ignore-empty, so optional parts don't produce stray separators.
  It treats all-whitespace parts as empty, like `default`, so it is not quite
  `concat` with a separator: `concat(%a, " ", %b)` keeps the space.
- **Checks when reading rules, not while converting**, so mistakes are
  reported once, with a position, before any conversion.

## Limitations and possible extensions

- Templates are stored as text and re-parsed for every record in
  `renderTemplate`. Parsing them once when reading the rules could speed up
  conversion.
- Expressions are not allowed in matchers (`if %{lower(%desc)} amazon`).
- Results have no size limit or warning. Output size is linear in the CSV
  data, except that nesting `replace` multiplies it at each level, and
  `replace` with a field as the replacement can give output the size of
  one field times the other. (Rules are not Turing complete: expressions
  have no loops, recursion or state, and always terminate.
  `replace` takes linear time.)
- References to other hledger fields are evaluated again each time they are
  used (not cached per record), so rules where many fields each refer
  several times to the next can take time exponential in the length of the chain.
- Expressions in matchers would be harder now: which `if` blocks match
  could depend on hledger field values, which depend on which blocks match.
- No arithmetic or date functions.
- No shorthand for appending (eg `comment+ shop:amazon` for
  `comment %{join(", ", comment, "shop:amazon")}`); it would need a
  separator per field (`, ` for comments, a space for descriptions) and has
  no place in `if` tables. Possible later if the full form proves too wordy.
