# Charts from reports - design notes and plan

Status, 2026-10-16: done for bal, bs, bse, cf, is, aregister, register and activity, as text, SVG, html (chart above the table)
and chart data (csv/tsv/json). Next: hledger-web and hledger-ui (phase 4), then extras (phase 5). Multiple outputs (phase 3) deferred.
This doc describes the current design, then the decisions and rejected alternatives behind it.

## Goal

Easy, ubiquitous charts from hledger's reports: each report gets a chart mode reusing its logic and data;
smart defaults always give a useful chart, no configuration needed; graphical (SVG) and terminal output;
the same chart work reused by the CLI, `-O html`, hledger-web and hledger-ui.
Non-goals for now: customisable charts, raster formats, interactive charts, pie charts.

Prior art it replaces or improves on: the old activity command (rows of `*`), bin/hledger-bar (a bash wrapper drawing `bal -O csv`),
hledger-web's flot register chart, and site/src/charts.md's "export CSV and chart it elsewhere" (to get a "built-in charts" lead at release).

## User interface

- `--chart[=KIND][,SCALE...]` shows a chart instead of the table (txt), above the table (html), or the chart's data (csv, tsv, json).
  Other formats (eg fods) give an error. The `svg` output format always shows a chart. `-O` keeps its existing meaning.
- KIND: `auto` (default), or for compound reports `grouped` or `diverging`. A kind that doesn't apply (eg grouped for bal) is ignored.
  It must come before any SCALE.
- SCALE: amounts, eg `5000` or `5000 USD`, fixing the scale so successive charts are comparable (see Fixed scale).
  Written without digit group marks, since commas separate the parts.
- `-w/--width N` sets a text chart's width (default: the terminal width).
- `activity` charts transaction counts per week (or other interval) as a single total; with `--postings`,
  it is a shortcut for `balance --count --chart`, weekly by default.

## Architecture

```
report  -->  adapter (Hledger.Cli.Chart; smart defaults)  -->  Chart (Hledger.Write.Chart)  -->  text   (Chart.Text)
                                                                                           -->  SVG    (Chart.Svg)
                                                                                           -->  data   (chartAsCsv, JSON)
```

- **Model** (`Hledger.Write.Chart`): a title, an x axis (categories, periods or dates), and one panel per commodity.
  A panel has a unit (an amount template, for display styles), series, group names, an optional fixed scale, a bar layout,
  a counts flag, and summary values (eg total, average; each with its own display style). A series has a label (with account type, and whether it's an account), a role (item, other, total),
  a mark (bar, line, marker), values, a group (eg a compound report's section) and a usual sign (for contra amounts).
  Values stay exact (Quantity) until renderers convert them for drawing.
- **Adapters** (hledger package, so hledger-web/ui can use them): multiBalanceReportAsChart, balanceReportAsChart,
  compoundBalanceReportAsChart, accountTransactionsReportAsChart, postingsReportAsChart. `writeChart` dispatches on format,
  applying `--chart`'s SCALE (`setChartScales`) and KIND (`setChartLayout`) first.
- **Colours** (`seriesColours`, `stableSlots`; exact values in `Chart.Palette`, shared by SVG and truecolor text).
- **Text renderer**: returns styled lines (so hledger-ui could draw them with brick); `styledLinesAsText` makes plain or ANSI text.
- **SVG renderer**: hand-written with blaze-svg (whose `Svg` is blaze `Markup`, so it embeds in our html).

## Smart defaults

- **Flows as bars, stocks as lines** (lines are bars in text). Time along the x axis in SVG; categories (single-period reports)
  as vertical bars, or horizontal beyond 30. Text charts are always horizontal bars, a row per x position.
- **One panel per commodity**, those in most report cells first; a warning above 8 panels suggests `-X` or `cur:`.
- **At most 8 series** (5 per compound section): the largest by absolute total, the rest combined into "other (N accounts)",
  per account type (each type keeps its largest account; several "other" series are named by their accounts' common parent),
  so eg a small liability isn't hidden among assets (`chooseSeries`).
- **No double counting**: in tree mode, each account's own amounts are charted.
- **Respects report options** (query, depth, period, interval, valuation, `--invert`, sorting, `-N`, `--title`, `--percent`);
  table-only options are ignored.
- **Mixed signs**: positive segments stack above (right of) zero, negative below; nothing is silently flipped (except grouped compound charts, below).
- **Nets and totals**: a thin ink line mark across bars (1.5px in SVG; `┃` in text), or an ink line with lines.
  Not for counts in one stack (eg activity), where it would be just the top of the stack.
- **Row total and average** (`-T`, `-A`), for changes per period: the net total's total and average per period, on a summary line
  below the chart (eg `Total 11, Average 0.9`; labels are the table's column headings); the average also as a dashed line in SVG;
  `rowtotal` and `average` records in chart data. Not drawn as bars, since a total would be off the scale.
  Averages of counts have one decimal place (counts themselves are whole numbers, ignoring the journal's no-commodity style).

Per report:

| Report | Chart |
|--------|-------|
| `bal` multi-period | stacked bars per period with a total mark; with `-H`/`--cumulative`, lines (SVG) |
| `bal` single period | a bar per account, coloured by type |
| `is`, `cf` (changes) | grouped layout by default |
| `bs`, `bse` (end balances) | diverging layout by default, net as a line |
| `aregister` | the balance after each transaction, a stepped line on a time scale |
| `register` | each account's running total as a line (with -H, from its start balance), plus the overall total; with an interval, stacked bars per period |
| `activity` | transaction counts as a single total (counting each transaction once per depth-clipped account, at depth 0); with `--postings`, as `bal --count` |
| `bal --count` | posting counts by account, at most one text cell per posting |

Text register charts have a row per posting (or transaction); a report interval gives a row per period.

## Compound reports

Each section's accounts are charted, in one of two layouts (`pnLayout`, chosen by the adapter, or `--chart=KIND`):

- **grouped** (default for changes, eg `is`): each section's accounts stacked in their own bar, sections side by side, so sizes can be compared.
  Amounts are normal-signed as in the tables (`setChartLayout` re-signs the data, so chart data matches).
  Text: a row per section (named, with its total) and a net row with only a mark.
- **diverging** (default for end balances, eg `bs`): all accounts stacked in one bar, as contributions to the net
  (sections that subtract from it, like expenses and liabilities, negated). Text: one row per period with the net,
  each side's section totals at that end of the bar (as the tables show them), a header naming the sections, and the net marked over the bar.

Contra amounts (opposite to their section's usual sign, eg a refund, accumulated depreciation) are drawn nearest the axis,
hatched in their account's colour (`╱`/`/` in text), with a "contra" legend entry. Compound charts only:
`bal` shows raw amounts, in its table too, so it doesn't mark them.
Sections take an account type from their query, which their accounts inherit if they have none; "..." rows are labelled with the section.

## Colours

- Accounts of several types: conventional type hues (assets blue, liabilities amber, equity violet, revenues green, expenses red),
  with up to 4 tints per type. Accounts all of one type, or untyped: 8 categorical colours (the type hue would tell nothing).
  "other" is grey, totals ink; a lone series that isn't an account (eg a total, or "..." for all accounts) is cyan, a hue no account type uses.
- Chosen by account name, not position or count (`stableSlots`): each name has a hashed order of preference, names choose largest first.
  So -S changes nothing, and removing the largest account (drilling down) disturbs only accounts it had displaced. Text fill characters likewise.
- Palette: the dataviz skill's validated reference palette; type hues validated on the pairs that co-occur (green/red is in the CVD warn band,
  so legends and positions matter). Tints mix with white/black ([0, 0.4, -0.3, 0.65]).
- Text: exact colours with `COLORTERM=truecolor` (dark variants when the background is known dark), else basic ANSI colours.
  Negative values stay ANSI red, like other output.

## Fixed scale

SCALE is the amount a chart spans (`pnScale`), per commodity (a bare number for the rest). `scaleSpans` divides it:
negatives get what they need, positives the rest, both shrunk proportionally if they don't fit; so the amount per cell is the same in every chart.
Bars beyond it are clipped: `▸`/`◂` (`>`/`<`) in text; in SVG a small ink triangle beyond the edge and an unrounded end.
SVG lines are clipped with a clipPath; ticks are the nice ticks within the exact range.
Count charts (`pnCounts`) instead cap text at one cell per unit when no SCALE is given.

## Rendering details

- Text: value column before the bars; eighth blocks for single-segment bars, whole cells (rounded cumulatively) for stacked ones;
  fill characters `█▓▒░` (`#=+:` in ASCII, chosen from the locale encoding); legend wrapped, listing only visible series; trailing spaces trimmed.
- SVG: self-contained, deterministic (one-decimal coordinates, one element per line, for golden tests), system fonts, literal colours in CSS
  (librsvg doesn't support `var()`), a `prefers-color-scheme` dark variant (omitted when embedded in html, which is light).
  Ticks by d3's 1-2-5 rule. Tooltips as `<title>` (marks wrapped in `<g>`, as blaze-svg leaf elements can't have children).
  Bars at most 24px, 4px rounded ends, 2px gaps; lines 2px, thinned to 4 points per pixel column (a 100k-posting register: 286s to 44s).
- Tests: shelltest; SVG goldens are separate files compared with diff, since shelltest treats lines starting with `<` as input.

## Decisions and rejected alternatives

- A `--chart` flag plus an `svg` format, rather than chart formats (`-O chart`), a `chart` command wrapping others, or sub-extensions (`foo.line.svg`):
  formats stay encodings, variants get a home in KIND, and html can show both.
- Hand-written renderers with blaze-svg, rather than Chart (cairo or the heavy diagrams stack), chart-svg (heavy, not in older snapshots)
  or hvega (needs JS; possible later for `-O vegalite`). Nothing suitable existed for terminal bar charts.
- Text charts first; chart data via csv first, as a way to review what charts show before rendering.
- Compound charts: first section totals, side by side; then accounts; then signed contributions in one diverging bar, which halves the space
  and shows the net as a difference; grouped restored as an option and made the default for changes, normal-signed so heights compare.
- Net marks: dots, then extra bars, then line marks, thinned; a white surface ring around them was removed.
- Colours: by position at first; then by name, with count-based rules (tints for up to 4 accounts of one type, neutral for a lone series)
  removed, since they repainted accounts as others were removed.
- Fixed scale as a per-direction maximum was tried first: one small negative value halved the resolution, defeating comparison.
  KIND and SCALE in any order was allowed at first, then KIND first, as less surprising.
- One cell per unit for all charts was rejected: amounts' units are arbitrary (eg 0.5 BTC would be half a cell). Counts only.
- Automatic date grouping of long text register charts (by day/week/.. to fit 50 rows) was dropped as unpredictable.
- activity was reimplemented on `balance --count --chart` rather than removed; its old `*` output and daily default are gone.
- Repeatable `-o` (several outputs, eg table on stdout plus an SVG file) is deferred: useful independently of charts,
  and better than comma-separated `-o` (commas are legal in file names).
- A `--view`/`--open` flag (temp file, open-browser) could make SVG nearly as quick as text; inline terminal images need raster output.

## Next

- Phase 4: SVG charts on hledger-web's report pages (could eventually replace the flot register chart); a chart toggle in hledger-ui.
- Phase 5: more KINDs (eg line, hbar); budget (goal marks), prices, roi, holdings; a sparkline column for tables; `--view`; Vega-Lite.
- Loose ends: dark-mode SVG unchecked in a browser; Commands/*.md flags blocks need `./Shake cmddocs`;
  new strings untranslated ("contra" and "No data" are hard-coded in the renderers); charts.md at release.
- Open: whether html output should include the chart by default, once proven.
