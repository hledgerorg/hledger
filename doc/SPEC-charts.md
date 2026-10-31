# SPEC: charts

Charts from reports: implemented for bal, bs, bse, cf, is, aregister, register and activity, as text, SVG, html (chart above the table)
and chart data (csv/tsv/json); with `--view` and `run`'s html pages for viewing them.
This doc describes the current design, then the decisions and rejected alternatives behind it, and possible future work.
(It was doc/PLAN-charts.md while being built.)

## Scope

Easy, ubiquitous charts from hledger's reports: each report gets a chart mode reusing its logic and data;
smart defaults always give a useful chart, no configuration needed; graphical (SVG) and terminal output;
the same chart work reused by the CLI, `-O html`, hledger-web and hledger-ui.
Non-goals for now: customisable charts, raster formats, pie charts, and interaction on the command line,
whose charts stay static; a page embedding a chart can add interaction through `SvgOptions`.

Prior art it replaces or improves on: the old activity command (rows of `*`), bin/hledger-bar (a bash wrapper drawing `bal -O csv`),
hledger-web's flot register chart, and site/src/charts.md's "export CSV and chart it elsewhere" (to get a "built-in charts" lead at release).

## User interface

- `--chart[=KIND][,SCALE...]` shows a chart instead of the table (txt), above the table, which is collapsed under Report details (html), or the chart's data (csv, tsv, json).
  Other formats (eg fods) give an error. The `svg` output format always shows a chart. `-O` keeps its existing meaning.
- KIND: `auto` (default), or for compound reports `grouped` or `diverging`. A kind that doesn't apply (eg grouped for bal) is ignored.
  It must come before any SCALE.
- SCALE: amounts, eg `5000` or `5000 USD`, fixing the scale so successive charts are comparable (see Fixed scale).
  Commas separate the parts, so a comma between digits (a decimal comma or digit group mark) is an error.
  Amounts are read with the chart panels' commodity styles (`parseamountWithStyles`), so an ambiguous `10.000 EUR`
  is ten thousand when EUR has a decimal comma.
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
  a counts flag, summary values (eg total, average; each with its own display style), and optional value labels
  (text shown at each x position, eg holdings' gain percents: in graphical charts instead of its value, in text charts in a column after it). A series has a label (with account type, and whether it's an account), a role (item, other, total, shortfall),
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
  Not for bars in one stack (not grouped side by side) whose total is just the end of the bar at every x position (`totalIsBarEnd`),
  ie the sum of its positive or negative values: eg activity's counts, or time logged; there it is shown only as the value.
  So it is marked with values of both signs, or a total that isn't the bars' sum (eg holdings' value, with a loss shown beyond it).
  Nor in SVG charts over time whose bars are narrower than about 24px (periods narrower than 32px, the chart's width divided by their number;
  eg monthly over 20 years, even on a 2400px page),
  where the marks, wider than the bars, would run into each other and hide them; the legend then doesn't list the total either.
  In category (single-period) charts too. Over a single period, a total that would be a line (eg a balance sheet's net) is marked across the bars instead.
- **Row total and average** (`-T`, `-A`), for changes per period: the net total's total and average per period, on a summary line
  below the chart (eg `Total 11, Average 0.9`; labels are the table's column headings); the average also as a dashed line in SVG, with a legend entry (shown even for a single series);
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
| `holdings` | a bar per holding (or lot), in each commodity's panel: cost basis plus unrealised gain (asset and revenue colours), reaching the value; with a loss, the part of the cost it is worth plus the part lost (a shortfall series: expense colour, hatched, in its place at the end of the stack), reaching the cost; without a market price, the cost, as an "other" series. The values are the total (shown as values in text; marked, when some holding has a loss, since its value is not its bar's end). Each bar's gain percent (value labels) follows its value in text; SVG shows it instead of the value, since the axis shows the values; tooltips have both. Labelled by account and commodity (and lot), also in tree mode, since headings aren't drawn. With a report interval, a bar per period end (labelled by date), for all the holdings then: their cost basis and net gain or loss |

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

How hues, shades and fill characters are chosen (`chartColouring`, `seriesColours`, `stableSlots`; exact values in `Chart.Palette`).

1. **What hue means is decided once per chart** (`chartColouring`, over all its panels, so a hue means the same in each):

   | the chart's accounts | colouring | hue tells you |
   |---|---|---|
   | of several main types | by type | the type: assets blue, liabilities amber, equity violet, revenues green, expenses red (untyped accounts: categorical) |
   | all of one type, or untyped | by name | which account: 8 distinct categorical hues |
   | one per panel | single | the type, or cyan if untyped (nothing needs telling apart) |

   In a single-period chart with one series, each category's bar has its own account type's hue.
2. **Roles override that**: totals and net are ink; a lone series that isn't an account (eg activity's counts) is cyan, a hue no type uses;
   "other" series are grey, or when coloured by type, a greyed version of their type's hue (60% grey), so that several (one per type)
   can be told apart; contra amounts are hatched (`╱`/`/` in text), drawn nearest the axis, with a neutral hatched legend swatch;
   shortfall series (eg holdings' unrealised loss, beyond the value) are hatched in their colour, in their place in the stack,
   with a hatched legend swatch of their own.
3. **Shades within a type**: 4 tints, ordered most visible first: base, darker, lighter, palest (mixed with white/black by [0, -0.3, 0.4, 0.65]);
   on dark backgrounds, where a darker shade sinks into the surface, base, lighter, darker, palest ([0, 0.4, -0.3, 0.65]).
   Preferences favour the first (`stableSlotsFavouringFirst 0.5`), so pale shades appear mainly when several accounts of a type share a panel.
   (Darker first was considered: deeper but less vivid, unvalidated, and poorly visible on dark backgrounds.)
4. **Fill characters** (text only; SVG uses solid fills with 2px gaps): `█ ▓ ▒ ░` (`# = + :` in ASCII), best looking first.
   Chosen among the series in the same bar (each section's, in the grouped layout); a series alone in its bar gets █.
   Accounts choose first, favouring the first characters; then "other" series, favouring the last (they're grey, so texture matters less,
   and ░ separates them from the coloured segments).
5. **Stability**: categorical hues, shades and fill characters are all chosen by name (`stableSlots`): each name has an order of preference
   for the slots (from a hash, FNV-1a with murmur3's finaliser), and names choose largest first (ties by name), each taking its first free slot.
   So position doesn't matter (`-S` changes nothing), and adding or removing small accounts, or removing the largest (drilling down),
   disturbs few others. Biased preferences (shades, fill characters) make the first slots likelier but stay name-based.
   Series of known type that aren't accounts (eg holdings' Cost, Unrealised gain/loss) always take their type's base shade,
   so their colours don't depend on their (translatable) names.
   With `-S`, accounts are drawn largest first, so bars read `█ ▓ ▒ ░`, most saturated first; otherwise they're drawn in name order.
   Costs: slots repeat when more are needed (8 hues, 4 shades, 4 characters); a chart-wide decision can change all colours when the
   chart's mix of types changes (eg adding a liability to an assets chart); a single account's colour changes when a second one joins it.
6. **Precedence**: role (total, other, lone), then the chart's colouring, then the type's hue, then the name-chosen slot.
7. **Rendering**: SVG and truecolor text (`COLORTERM=truecolor`) use the same exact colours, with variants for dark backgrounds
   (SVG via `prefers-color-scheme`, omitted when embedded in html; text when the background is known to be dark).
   Basic ANSI colours otherwise: type hues as the terminal's blue, yellow, magenta, green, red, shades alternating dull/vivid;
   categorical hues as 8 basic colours (avoiding red, which marks negative values); "other" faint; lone cyan.
   Negative values stay ANSI red, like other output.
8. **Palette**: the dataviz skill's validated reference palette; type hues validated on the pairs that co-occur
   (green/red is in the CVD warn band, so legends and positions matter).

## Fixed scale

SCALE is the amount a chart spans (`pnScale`), per commodity (a bare number for the rest). `scaleSpans` divides it:
negatives get what they need, positives the rest, both shrunk proportionally if they don't fit; so the amount per cell is the same in every chart.
Bars beyond it are clipped: `▸`/`◂` (`>`/`<`) in text; in SVG a small ink triangle beyond the edge and an unrounded end.
SVG lines are clipped with a clipPath; ticks are the nice ticks within the exact range.
Count charts (`pnCounts`) instead cap text at one cell per unit when no SCALE is given.

## Rendering details

- Text: value column before the bars; eighth blocks for single-segment bars, whole cells (rounded cumulatively) for stacked ones;
  fill characters `█▓▒░` (`#=+:` in ASCII, chosen from the locale encoding); legend wrapped, listing only visible series; trailing spaces trimmed.
- Legends list the series when there are several, or when one is an "other" series, whose muted colour needs explaining.
- SVG: self-contained, deterministic (one-decimal coordinates, one element per line, for golden tests), system fonts, literal colours in CSS
  (librsvg doesn't support `var()`), a `prefers-color-scheme` dark variant (omitted when embedded in html, which is light).
  Ticks by d3's 1-2-5 rule. Tooltips as `<title>` (marks wrapped in `<g>`, as blaze-svg leaf elements can't have children);
  a line's points have invisible 12px targets for them (by date, only where the line changes), or beyond 400, the last point
  in each 4px column has one; a step line's flat stretches have no points inside them.
  880px wide (shrinking to fit narrower pages), 14px text (estimated widths per kind of character, measured in Chrome with SF Pro);
  bars at most 56px (64px for single-period columns), 2px gaps between segments, and 3px rounded ends
  (each stack is clipped to one rounded outline, so the end is the same however thin its outermost segment); lines 3px, thinned to 4 points per pixel column
  (a 100k-posting register: 286s to 44s), a lone point (eg a single period's, or one transaction's) drawn as a 12px dash. The unit is shown only on the outermost y tick. x labels are thinned to an even stride
  that leaves room for all of them, after the end ones are moved inward.
- Embedded SVG (`SvgOptions`, for pages like hledger-web's): without its styles, for a page that supplies `chartStylesheet` itself
  (eg when its Content-Security-Policy allows no inline styles); at another width than 880px, eg as wide as the page shows it;
  with plots of another height than 260px, and about one y tick per 50px;
  with links on lines' tooltip targets, one per x position (eg to a register's rows), left out of the tab order;
  with each date plot's scale (`data-` attributes on a transparent rectangle under it), for a page's script to select dates by dragging;
  shaded as of today: the future, and the past below zero (tinted with the expenses' red), with the zero line red.
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
- Colouring by type or by name was decided per panel at first; then for the whole chart, since a commodity's panel with one asset account
  (eg in bcexample's bs) got a categorical colour while the USD panel's assets were blue. A lone account got a categorical colour too,
  which looked arbitrary; hence the "single" colouring. Always using type hues was rejected: 4 tints (2 shades in basic ANSI)
  can't tell apart a one-type chart's accounts.
- Single-period charts keep type hues even when all accounts are of one type: each account is its own bar, labelled on the axis,
  so colour isn't needed to identify it, and stays free to show the type (as in mixed-type single-period charts).
  Colouring each bar by name would add colour that encodes nothing; in multi-period charts accounts are unlabelled stacked segments,
  so there colour (with the legend) is what identifies them.
- The name hash was plain FNV-1a at first: its last character (the slot number) was poorly mixed, giving only a few dozen orders of
  preference, so colours collided more often than chance; murmur3's finaliser fixed that.
- Tints and fill characters were chosen without bias at first; the pale tints looked washed out, and the stippled characters
  untidy, when chosen for a lone or large account. Fill characters were chosen once per panel, leaving an `is` chart's expenses
  bar with stippled characters while █ went unused there, and the large "other" series took the dense ones first.
  ░ ranked above ▒ was tried and dropped. Assigning fill characters by position (always `█ ▓ ▒ ░` from the left) was considered:
  tidier without `-S`, but an account's character would no longer follow it between charts.
- "other" was always plain grey; with several (one per type), SVG couldn't tell them apart, hence the type-tinged greys.
- Fixed scale as a per-direction maximum was tried first: one small negative value halved the resolution, defeating comparison.
  KIND and SCALE in any order was allowed at first, then KIND first, as less surprising.
- One cell per unit for all charts was rejected: amounts' units are arbitrary (eg 0.5 BTC would be half a cell). Counts only.
- To make separate text charts comparable more often, a nice amount per cell (1, 2, 2.5 or 5 × 10ⁿ, the smallest that fits) with a
  `1 cell = 500 USD` note was tried and dropped (2026-10): charts matched only when their maxima happened to round to the same step,
  bars lost up to half the width, and panels of different commodities got different lengths, suggesting they were comparable.
  Filling the width says each panel is scaled to itself; `--chart=SCALE` is the way to compare. A shared scale across
  commodity panels was also rejected: amounts in different commodities aren't comparable (and with -V/-X there is one panel).
- A narrower block (`▉`) for count charts, leaving a gap after each cell so they could be counted, was tried and dropped:
  terminals draw block characters differently (Ghostty and Terminal draw them filling the cell, but tile the shaded fills `▓▒░` seamlessly;
  VS Code with `customGlyphs` off uses the font's glyphs, with gaps around every block), so the gaps were an inconsistent cue.
  Shorter (`▇`) or square (`■`) characters vary similarly. A text note of the scale (eg "One character per transaction") would be reliable.
- SVG sizes were at first small (12px text, bars at most 24px wide, 760px), leaving much empty space; enlarged to look friendlier (2026-10).
  Switching to horizontal bars whenever category names don't fit below vertical bars was tried and rejected:
  a consistent bar direction is better. Names are angled instead (as before), with room made for the first one.
- Automatic date grouping of long text register charts (by day/week/.. to fit 50 rows) was dropped as unpredictable.
- activity was reimplemented on `balance --count --chart` rather than removed; its old `*` output and daily default are gone.
- Repeatable `-o` (several outputs, eg table on stdout plus an SVG file) is deferred: useful independently of charts,
  and better than comma-separated `-o` (commas are legal in file names).
- `--view` (not `--open`, which `close` has) writes the output to the `-o` file or `view.FMT` in hledger's XDG cache directory, html by default,
  and opens it with the system's default viewer (reusing openBrowserOn's launchers), only warning if that fails.
  Not a shared temp directory: on Linux, `/tmp` files were readable by other users, and a predictable path invited symlink tricks.
  Not next to the journal, which may be a git repo or synced folder. Inline terminal images would need raster output.
- `run -O html`/`-o FILE.html`/`--view` collects the commands' outputs into one page (a folding section per command, headed by its
  command line; echo lines as headings), by giving each command a part file in the cache directory and reading it back;
  so several charts can be viewed at once, as in the chartsdemo page, without a tab per report.
- hledger-web: the register's chart, and each report page's (balance, the statements, holdings), drawn by the CLI's adapters
  between the page's heading and its table, without their titles (the heading names them), styled by /chart.css,
  as wide as the page's main column (the chartwidth cookie). In tree mode the page folds its table at the depth limit,
  but a chart can't fold, so it is drawn from the report clipped there, as on the command line.
  With several commodities, a legend of radio buttons chooses the one shown, with no javascript (Widget.Chart.chartLegend,
  shared with the register): each panel is drawn as a chart of its own, coloured as in the whole chart (chartPanelsSvgMarkupWith),
  so its colours match the CLI's stacked panels. The choice is not remembered across pages.
  The c and d keys hide the chart and the table (the report's data), remembered in the showchart and showtable
  cookies, named with the server's port like the other UI cookies, which the server reads to render the next page the same way.

## Possible future work

- html: include the chart by default ?
- truecolor/SVG categorical colours include red (`#e34948`, the palette's 8th slot) and orange/amber/green/blue,
  so in a single-type chart (eg `bal type:A -M --chart`) an account can look like an expense, or another type.
  Basic ANSI categorical colours avoid red; should the truecolor ones too (and avoid the type hues generally) ?
- hledger-ui integration, a chart toggle ?
- repeatable `-o`, for several outputs at once (see Decisions)
- update hledger-bar doc, charts page
- improve/publish charts demo
    - use it in docs
    - explore this style of report, make it available to users
- png output
- clickable chart ? Lines' points can link, for embedding (`SvgOptions`); bars can't yet.
- more charts (budget (goal marks), prices)
- holdings over time: perhaps returns per period (time-weighted, reusing roi's TWR code) as a second chart kind;
  value and cost as lines with the gap shaded (needs area fills); a per-holding table (a value column per period end)
- roi --chart (TWR per period as bars, IRR on the summary line) was designed and deferred (2026-10): holdings with intervals
  would show the same in the more maintained command. Its remaining value is for investments without lot tracking
  (roi works on any queried accounts); worth doing if users ask.
- more kinds of chart (line, hbar, pie); a sparkline column for tables ? Vega-Lite.
- a default fixed scale, if users ask: a `--chart-scale=SCALE` option that sets the scale without enabling charts,
  for per-command config file sections (eg `[incomestatement]`; an env var was considered, but the config file is per command).
  Users would name their main currencies (a bare number would also fix shares' scales). Caveat: one scale can't suit
  several intervals (`is -Y` bars are ~12× `is -M`'s); scaling a per-day amount by period length would work for changes, not balances.
  Meanwhile, a shell alias does it (eg `alias ism='hledger is -M --chart=8000USD'`).
