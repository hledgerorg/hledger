# hledger-web style notes

The rules a change to the web UI's appearance is expected to follow, by
whoever makes it - person or coding agent. They are written down so that each
change does not have to re-derive them from the existing css.

Discussion of the overall direction is in
[#200](https://github.com/plaintextaccounting/hledger/issues/200).

## Constraints

- **No build step.** hledger-web builds with stack alone. Css and js are
  vendored under `static/` and served as-is; there is no preprocessor, bundler,
  or npm step in the build. A change that needs one is out of scope.
- **Nothing loads from a third party.** No CDNs, no web fonts fetched at
  runtime. Everything ships with the binary.
- **Server-rendered and static-first.** Pages are Hamlet templates; javascript
  is for the few things that genuinely need it. See `static/hledger.js`.

## Where style lives

- `static/hledger.css` is the only stylesheet we own. It is grouped into
  numbered sections; add to the section that fits rather than appending.
- **No `style=` attributes in templates.** Alignment, spacing and color belong
  in css, keyed off a class. The templates carry semantic classes
  (`.date`, `.description`, `.account`, `.amount`) — use those.
- Bootstrap 3 is still vendored and supplies the grid, forms, buttons and the
  offcanvas sidebar. Our stylesheet loads after it, so plain overrides work; no
  `!important` needed, and it should be treated as a smell.

## Tabular and monetary data

The journal, register and sidebar are tables of figures, and read like a ledger.

- **Amounts get tabular figures.** `font-feature-settings:"tnum"` plus
  `font-variant: tabular-nums`, so digits are the same width and stack
  place-by-place down the column. Right alignment already lines up the decimal
  points, so the effect is subtle; it is the right default for money either
  way. Applied to `.amount`, which `mixedAmountAsHtml` puts on both the cell
  and the amount spans inside it.
- **Amounts are right-aligned**, so decimal points line up. Text columns are
  left-aligned. Both come from css, not per-cell attributes.
- **Column headers label the data, they are not part of it**: small, uppercase,
  letter-spaced and muted, not bold black.
- **Rows are separated by one hairline**, with no zebra striping and no vertical
  rules. A row lights up faintly on hover to help the viewer when
  reading a wide row across to its amount.
- **Color carries meaning, never decoration.** Negative amounts are red
  (`.negative`); the rest of the table is near-monochrome.
- **Do not assume `.` is the decimal mark.** Amounts are formatted server-side
  by hledger and vary by journal and locale, so alignment must not depend on the
  separator.

## Reviewing an appearance change

Screenshots, before and after, of a journal with enough data to fill the page.
The browser tests (`test/browser`) can check that markup and behavior survive,
but they cannot judge how it looks.

## Known gaps

Deliberately not addressed yet, in rough order of appeal:

- **Bootstrap 3 itself.** It is the last large vendored asset besides jquery and
  flot, and it pulls in glyphicons (7 in use, ~148KB of fonts). Bootstrap 4
  dropped glyphicons, so any upgrade is also an icon migration. Replacing it
  with plain modern css — the app has one layout — would remove more than it
  adds, but it is a project of its own.
- **`sidebarToggle` in `hledger.js`** spells out the responsive grid classes
  three times. It should move to css, or to one helper, whenever the grid is
  touched.
- **`.transactionsreport .posting td { border: none !important }`** fights any
  row-border work and should be reworked rather than layered on.
- **Charts.** flot is dated and needs jquery. Rethinking them is likely part of
  hledger 2.0, not a css change.
- **A strict Content-Security-Policy**: #2703. The templates no longer carry
  `style=` attributes, so `style-src` can be strict too, once flot's legend,
  which it builds from inline styles, is dealt with.
