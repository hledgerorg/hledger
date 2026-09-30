# hledger-web style notes

The rules a change to the web UI's appearance is expected to follow, by
whoever makes it - person or coding agent. They are written down so that each
change does not have to re-derive them from the existing css.

Discussion of the overall direction is in
[#200](https://github.com/hledgerorg/hledger/issues/200).

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

## Light and dark

The pages follow the light or dark setting of the OS or browser
(`prefers-color-scheme`). There is no toggle of our own.

- **Every color is a custom property**, defined once in section 1 of
  `hledger.css`: the light value in `:root`, the dark one in the
  `prefers-color-scheme: dark` block below it. Rules use the properties, not
  literal colors (shadows aside, which are black in both), so a new color is a
  new property with both values.
- **Bootstrap and the browser's defaults are light only.** Section 9 restyles
  the parts of them these pages use, in the dark scheme only. Using another
  part of bootstrap (a component, or a state such as `:hover` or `.has-error`)
  may need a line there too.
- **The register chart takes its colors from the same properties.** flot draws
  on a canvas, out of reach of css, so `hledger.js` hands it the `--chart-*`
  values, and draws it again when the scheme changes, and for printing.
- **Printing is always light**, whatever the setting.
- **A new color keeps text readable**: at least 4.5:1 contrast with what is
  behind it (WCAG AA), in both schemes. `test/browser/color-scheme.spec.js`
  checks every page for this in the dark scheme.

## Javascript

- **No inline scripts.** Every page sends a Content-Security-Policy ([#2703])
  that allows scripts from hledger-web's own origin, plus the two small inline
  scripts in the layout templates, which carry the response's nonce. A
  `<script>` block added to a template without `nonce=#{nonce}` will not run,
  and the browser will say so in its console. Better not to add one at all:
  code goes in `static/hledger.js`, and whatever a page has to hand it goes in
  `data-` attributes (`chart.hamlet` and `registerChartInit` show the pattern).
- **No inline event handlers or `javascript:` urls**, for the same reason.
  hledger.js binds its handlers to hooks in the markup such as `data-toggle`.
- **Styles set from javascript are fine** as long as they go through the CSSOM
  (`element.style`, jquery's `.css()`), which the policy does not govern. Markup
  strings carrying `style=` attributes are not; flot's own legend was one, and
  is turned off in favor of one drawn by hledger.js.
- `test/browser/security.spec.js` fails on any policy violation, and
  `Hledger/Web/Test.hs` checks the header itself.

[#2703]: https://github.com/hledgerorg/hledger/issues/2703

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

Screenshots, before and after, of a journal with enough data to fill the page,
in the light scheme and the dark one. The browser tests (`test/browser`) can
check that markup and behavior survive, but they cannot judge how it looks.

## Known gaps

Deliberately not addressed yet, in rough order of appeal:

- **Bootstrap 3 itself.** It is the last large vendored asset besides jquery and
  flot, and it pulls in glyphicons (7 in use, ~148KB of fonts). Bootstrap 4
  dropped glyphicons, so any upgrade is also an icon migration. It has no dark
  scheme either, hence section 9 of `hledger.css`. Replacing it with plain
  modern css — the app has one layout — would remove more than it adds, but it
  is a project of its own.
- **`sidebarToggle` in `hledger.js`** spells out the responsive grid classes
  three times. It should move to css, or to one helper, whenever the grid is
  touched.
- **`.transactionsreport .posting td { border: none !important }`** fights any
  row-border work and should be reworked rather than layered on.
- **Charts.** flot is dated and needs jquery. Rethinking them is likely part of
  hledger 2.0, not a css change.
