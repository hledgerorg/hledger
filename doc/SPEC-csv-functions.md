# SPEC: functions in CSV rules

CSV rules field assignment values can contain `%{...}` expressions,
which call built-in functions on CSV values:

```rules
description %{default(%payee, capitalize(%desc))}
account2    expenses:%{lower(default(%category, "misc"))}
comment     ref:%{replace(%memo, ".*ref#([0-9]+).*", "\1")}, month:%{substr(%date, 1, 7)}
amount1     %{negate(%amt)}
```

User docs: hledger manual, CSV > Field assignment > Functions.
Code: `hledger-lib/Hledger/Read/RulesReader.hs` (`TemplateExpr`,
`templateexprp`, `templateFunctions`, `evalTemplateExpr`).
Tests: `hledger/test/csv.test` 88-94.

## Syntax

```
expr     = "%{" ws term ws "}" ;
term     = call | fieldref | matchref | string | number ;
call     = name ws "(" ws [ term { ws "," ws term } ] ws ")" ;
name     = lowercase letter, { lowercase letter | digit | "_" } ;
fieldref = "%" fieldname [ "_" rownum ] | "%(" fieldname ")" ;   (as elsewhere in values)
matchref = "\" digits ;                                          (as elsewhere in values)
string   = '"' { char | '\"' | '\\' } '"' ;
number   = digits ;
```

- An expression can appear anywhere a field reference can in a field assignment value,
  in `if` blocks and `if` tables too. In an `if` table, the delimiter does not
  separate values when it is inside `%{...}`.
- Inside braces, field references keep their `%`. Bare words are not allowed
  (except function names), leaving them free for future keywords.
- In strings, `\"` and `\\` are escapes; any other backslash is kept as is.
- `%{` always begins an expression. (Before functions, it was literal text.)

## Evaluation

- All values are text. Field references give the field's value with outer
  whitespace removed; empty or missing fields give `""`.
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
- No arithmetic, date functions, or references to hledger fields already assigned.
