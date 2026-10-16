# Charts from reports - design notes and plan

Status: 2026-10-16. Interface and architecture agreed (see Decisions). Phase 1 done (chart model; bal adapters and chart data output; text renderer); phase 1b (SVG) next.

## Goal

Easy, ubiquitous chart output from hledger's reports:

- each report (added incrementally) gets a chart mode that reuses the report's logic and data
- it just works: smart defaults always produce a useful chart, no configuration needed
- graphical output (SVG first) that users can view easily
- character-based output that renders in any terminal, as the fastest, cheapest visual report
- the chart work is reused across the CLI, `-O html`, hledger-web and hledger-ui

Non-goals for now: customisable charts (colours, sizes, explicit chart types per series),
raster formats (PNG), interactive charts, pie charts.

## Prior work

- **activity** command: counts postings per interval, prints one row of `*` per period.
  Not auto-scaled, ASCII only, counts only.
- **hledger-bar** (bin/hledger-bar): bash wrapper around `bal -Ocsv --transpose -N -0 --layout=bare -M`.
  Horizontal bars, one row per period, `+`/`-` in green/red, manual scale (`-sSCALE`),
  single commodity only (user must add `cur:` or `-X`). Shows that "one row per period, bar to the right"
  is a good terminal layout, and that auto-scaling and multi-commodity handling are what's missing.
- **hledger-web register chart**: flot (jQuery) line chart of the account's running balance,
  one series per commodity, data passed as JSON in a data attribute (RegisterR.hs, templates/chart.hamlet, hledger.js).
  Has hover tooltips, click to jump to the transaction, drag-select to zoom (reloads with a date: query).
- **site/src/charts.md**: today's advice is "export CSV and chart it elsewhere", or Fava, or a long list of third-party tools
  (hledger-plot, hledger-lit, hledger-vega, sankey tools, ploterific, r-ledger, grafana). Built-in charts would become the first answer there.
- ROADMAP has listed "simple built in bar charts" / "simple console charts" since 2020 and 2023.

## Relevant existing structure

- Output format is chosen by `-O FMT`, or by `-o FILE`'s extension if it's in `outputFormats` (CliOptions.hs).
  Each command lists its supported formats in `outputFormatFlag [...]` and dispatches with a `case fmt of` (eg Balance.hs `balance`).
- Report data is already renderer-independent:
  `PeriodicReport` (dates, rows, totals; used by balance, budget) and `CompoundPeriodicReport` (bs, bse, is, cf),
  `BalanceReport` (single period), `PostingsReport` (register), `AccountTransactionsReport` (aregister).
- `Hledger.Write.Spreadsheet` is an intermediate table form shared by the csv/tsv/html/fods renderers and by hledger-web.
  A chart model would be the analogous intermediate form for charts.
- hledger-lib already depends on blaze-markup/blaze-html and colour; hledger has open-browser.
- `writeOutputLazyText` writes a command's single output to stdout (with pager) or to the -o file.
- Repeated `-o` options currently mean last one wins (`maybestringopt` takes the last).

## User interface

### Recommended

Treat a chart as a different *view* of the report, and the output format as how that view is *encoded*.

| Command                         | Result                                                        |
|---------------------------------|---------------------------------------------------------------|
| `hledger bal -M food`           | table, as now                                                 |
| `hledger bal -M food --chart`   | text chart in the terminal                                    |
| `hledger bal -M food -o f.svg`  | SVG chart (svg only makes sense as a chart, so `--chart` is implied) |
| `hledger bal -M food -O svg`    | SVG chart on stdout                                           |
| `hledger bal -M food --chart -o f.html` | HTML page with the chart (inline SVG) above the table  |
| `hledger bal -M food -o f.html` | HTML table, as now                                            |

So:

- `svg` becomes a new output format. Choosing it implies chart mode. This is your proposal, unchanged.
- `--chart` turns on chart mode for formats that can show either a table or a chart (txt, html).
  It's needed because `txt` is already the table.
  With formats that can't show a chart (csv, tsv, json, fods...) it's an error, at least initially.
- Define the flag as `--chart[=KIND]` from the start, with only `auto` (the default) implemented at first,
  so adding `bar`, `stack`, `line`, `hbar`... later changes nothing. (cmdargs optional values need `=`, as with `--forecast`.)
- Commands without chart support reject `--chart` and `-O svg` with the usual unsupported-format error.

Why a flag rather than more format names: a text chart needs some name other than `txt`, eg `-O chart` or `-O bars`,
and then `chart` would sit beside `svg` as if they were alternative encodings, when really one is "text chart" and the other "graphical chart".
A flag keeps formats meaning encodings, and gives variants a natural home (`--chart=line`).
It also works with html, which can show the table, the chart, or both.

### On sub-extensions (foo.line.svg)

Workable but I'd avoid it as the main mechanism:
dotted filenames are common (`expenses.2026.svg`, `report.v2.svg`), so we could only recognise a fixed set of kind names,
and then `foo.bar.svg` is ambiguous between "a file called foo.bar" and "a bar chart".
It also hides the option from `--help`. `--chart=KIND` is explicit and discoverable.
If wanted later, sub-extensions could be accepted as sugar for `--chart=KIND`, only for known kinds.

### Multiple outputs

Useful and independent of charts; worth doing once two or more formats per command exist.
Two options:

- **Repeatable `-o`** (recommended): `hledger bal -M food -o - -o food.svg` shows the table on stdout and writes a chart.
  Unambiguous, no quoting concerns. Changes current last-wins behaviour, which nobody should be relying on.
- **Comma-separated `-o`**: `-o -,food.svg`. More concise, but commas are legal in filenames;
  we'd need an escape or a "file exists" heuristic. Could be accepted as sugar later.

`-O` keeps its current, documented meaning: when given, it sets the format of every output,
overriding file extensions (`-o foo.txt -O csv` writes CSV).
Without `-O`, each output's format comes from its file extension, or is txt for stdout and for files with no recognised extension, as now.
So to write different formats at once, you'd omit `-O` and rely on the extensions.
`--chart` applies to the txt and html outputs.

Implementation: commands would provide a "render for format" function and a shared helper would call it once per output,
so the report is computed only once. Commands migrate incrementally; until then they reject more than one `-o`.

### Viewing graphical output easily

The friction with SVG is "write file, then open it". Options:

- Document `-o x.svg && open x.svg` (macOS), `xdg-open` (linux), `start` (windows).
- Later: a `--view`/`--open` flag that writes to a temp file and opens it with open-browser (already a dependency, used by hledger-web).
  This would make graphical charts nearly as quick as text ones.
- Inline terminal images (kitty, iTerm2, sixel) would be nice but need raster output; out of scope.

### Alternatives considered

- **A `chart` command wrapping other commands** (`hledger chart bal -M food`), like hledger-bar.
  Discoverable as one place, but duplicates each command's option handling and help, and doesn't reuse the per-command format dispatch.
  Could exist later as a thin alias for `CMD --chart`.
- **Charts in html output by default.** Attractive, but changes existing html output; keep it opt-in via `--chart` for now.
- **A sparkline column in tables** (`▁▂▃▅▇` per row, eg `bal -M --sparkline`).
  A cheap, compact visual for wide multi-period tables, complementary to charts. Easy to add once the text renderer exists.
- **Vega-Lite JSON output** (`-O vegalite`). Great for power users and could drive richer html/web charts,
  but needs JavaScript to render, so not the first format. We can generate it with aeson from the same chart model later.

## Architecture

```
report (existing)  -->  Chart (new, renderer-independent)  -->  text  (terminal, hledger-ui)
  per-command adapter                                      -->  SVG   (files, html output, hledger-web)
  holds the smart defaults                                 -->  later: Vega-Lite JSON, sparklines
```

- **Chart model** (hledger-lib, eg `Hledger.Write.Chart`), roughly:
  a title; one panel per commodity; each panel has an x axis (categories, or periods/dates),
  a unit (commodity symbol and display style, for tick labels), a list of named series of numbers, and a chart kind
  (bars, stacked bars, lines, horizontal bars).
  Values are converted to Double only here, for drawing; all report arithmetic stays exact.
- **Adapters** (hledger package, next to each command, like the existing `*AsSpreadsheet` functions):
  `multiBalanceReportAsChart :: ReportOpts -> MultiBalanceReport -> Chart` etc.
  This is where each report's smart defaults live. hledger-web and hledger-ui already depend on the hledger package, so they can use them.
- **Renderers** (hledger-lib):
  - `chartAsSvg`: a small hand-written SVG renderer (axes, nice ticks, bars, lines, legend, panels).
  - `chartAsText`: returns styled lines (a list of styled text segments) rather than raw ANSI,
    so the CLI can render ANSI colour and hledger-ui can render brick attributes from the same output.
- **Reused helpers**: period column headings (same labels as the table), amount styles for tick labels, report titles, terminal width, colour detection.

### SVG renderer details

- Hand-written, not a charting library.
  Haskell `Chart` needs cairo (C) or diagrams (very heavy dependency tree); hvega needs JS to render.
  A focused renderer for four chart kinds is perhaps 600-900 lines, with full control and no new heavy deps.
  Build the markup with blaze-svg (see Libraries below): its `Svg` type is blaze's `Markup`, the same type as our `Html`,
  so the chart embeds directly in `-O html` output and hledger-web pages.
- Deterministic output (fixed coordinate rounding), so shelltest golden files work.
- Self-contained file: embedded `<style>` with a `prefers-color-scheme: dark` variant, system font stack, no external resources.
- Accessible and slightly interactive without JS: `role="img"`, `<title>`/`<desc>`,
  a `<title>` on each bar/point giving period, account and amount (shown as a tooltip by browsers).
- Colour-blind-safe categorical palette of about 8 colours; positive/negative not signalled by colour alone.
- Text width can't be measured without fonts; estimate from character count, and right-align labels against the axis.

### Text renderer details

- Horizontal bars, one row per period (or per account for single-period reports), as in hledger-bar and activity.
  This scales to many periods (they just scroll) and keeps labels readable.
- Auto-scaled to the terminal width (or `--width`, for tests), with eighth-block characters (`▏▎▍▌▋▊▉█`) for 8x finer resolution.
  ASCII fallback (`#`, `-`) when the output encoding isn't UTF-8.
- Values printed at the end of each bar, using the commodity's display style.
- Negative values: bars grow left from a zero axis, when any value is negative.
- Several series: stacked segments in distinct colours, plus distinct fill characters (`█▓▒░`) so it still reads without colour,
  and a one-line legend. Segments are whole cells, rounded so the total length is preserved (largest remainder);
  only a single-series bar uses eighth blocks.
- Width comes from `available_width_` (terminal size or COLUMNS), as for other reports.
  `--width` is currently a register-only flag; chart-capable commands need it too, so tests can fix the width.
- No text line charts initially (braille plots are font-dependent and hard to read); stocks are shown as bars of the balance at each period end.

## Smart defaults

General rules:

- **Flows as bars, stocks as lines.** Period changes (`bal` default, `is`, `cf`) are bars;
  end balances (`--historical`, `--cumulative`, `bs`, `bse`, aregister) are lines in SVG, bars in text.
- **Time goes along the x axis** in SVG (vertical bars); categories (accounts in a single-period report) use horizontal bars.
- **One panel per commodity.** Multi-commodity reports produce several small charts in one output, sharing the x axis,
  largest commodity first. Users can reduce this with `-X`, `-B` or `cur:` as usual, but needn't.
- **At most ~8 series.** Pick the largest by total absolute amount, keep the report's ordering among them,
  and combine the rest into "other (N accounts)".
- **No double counting.** In tree mode, stacked charts use only rows with no displayed subaccounts.
  Non-stacked charts can show all rows, with indented labels.
- **Respect report options**: query, depth, period, interval, valuation, `--invert`, sorting, `-N` (hide total), `--title`, `--percent`.
  `--percent` naturally gives a 100% stacked chart. Options that only shape the table are ignored: `--transpose`, `--layout`, `-T`, `-A`, `--pretty`.
- **Mixed signs.** Stacked bars stack positive segments above zero and negative ones below (left of the axis, in text),
  so `bal -M type:rx` works without `--invert`. Series are never silently flipped.
- **Degenerate cases still produce output**: an empty report gives a chart saying "no data"; all-zero data gives a flat axis, not an error.
- Large numbers of periods: SVG bars get thinner, and past some count (a few hundred) become an area/line.
  Text gets long, like the table; the existing large-report warning applies.

Per report (first column is the suggested order of work):

| # | Report | Default chart |
|---|--------|---------------|
| 1 | `bal` multi-period, changes | bars per period; one account: plain bars; several: stacked bars with a net total marker |
| 1 | `bal` multi-period, `-H`/`--cumulative` | lines, one per account (text: bars of the end balance) |
| 1 | `bal` single period | horizontal bars, one per account |
| 2 | `is` | per period: revenues and expenses side by side (both positive, thanks to normal-balance signs), net income marker or line |
| 2 | `bs`, `bse` | per period: assets and liabilities lines, net worth line; single period: horizontal bars of section subtotals |
| 2 | `cf` | per period: net cash change bars |
| 2 | `aregister` | running balance line (stepped), one per commodity; this is hledger-web's register chart |
| 3 | `register` | running total line; with an interval, period amount bars |
| 3 | `activity` | counts per period, as now, gaining auto-scaling and SVG (keep its current text output unless we decide otherwise) |
| 4 | `bal --budget` | actual bars with the goal as a marker per period |
| 4 | `prices` | price lines over time, one panel per commodity pair |
| 4 | `roi`, `holdings` | later: return per period bars; holdings value horizontal bars |

Commands with no chart (print, accounts, stats, etc.) reject chart mode.

## Reuse across interfaces

- **CLI**: text and SVG, as above.
- **`-O html --chart`**: inline SVG above the table, in one self-contained file. No JavaScript, works offline.
- **hledger-web**: could render the same SVG server-side on the balance, bs, is, cf and register pages.
  That's cheap new charts for every report page, and could eventually remove the flot/jQuery chart code.
  Hover tooltips and click-to-transaction work with SVG `<title>` and `<a>`.
  Drag-to-zoom would need a little JS on top of the SVG, or could be dropped.
  Suggest leaving the existing register chart alone until the SVG charts are proven.
- **hledger-ui**: the text renderer's styled lines can be drawn with brick, eg a toggle that shows a chart in the register screen.

## Libraries

Surveyed 2026-10-15 (Stackage nightly 2026-09-01 / LTS 24 unless noted; we also build with LTS 22 and 23 for GHC 9.6/9.8).

| Package | Status | Verdict |
|---------|--------|---------|
| blaze-svg 0.3.7 | in Stackage; deps: base, blaze-markup, mtl; last upload 2023, bounds current (base <4.23) | **Use** for SVG markup. Tiny, same `Markup` type as our html output. |
| hvega 0.12.0.7 | in Stackage; deps: aeson, text, unordered-containers; maintained | **Later**, for `-O vegalite` export from the chart model. Needs JS to render, so not a first format. |
| chart-svg 0.8.3.3 | pure-Haskell SVG charts, active (Aug 2026), but only in LTS 24+; pulls in numhask, harpie, cubicbezier, flatparse, markup-parse, formatn, Color, and both lens and optics-core; API has churned (0.4 to 0.8 in a few years) | No. Heavy for our needs, not in our older snapshots, and we'd fight its styling. |
| Chart 1.9.5 + Chart-diagrams | in Stackage; core is a pure model (has bars, lines, a SparkLine module) but rendering needs diagrams-lib/-svg/-core/-postscript and SVGFonts | No. The diagrams stack is a very long build and a big surface for breakage. Chart-cairo needs C. |
| plot-light | blaze-svg based, last upload 2018 | No, unmaintained. |
| svg-builder | used by diagrams-svg, last upload 2018, not in Stackage | No; blaze-svg covers it. |
| asciichart 1.0.2 | terminal line charts, base+array only, 2020, not in Stackage | No; we want bars, and a line renderer is a few dozen lines if ever wanted. |
| unicode (Data.Char.Block) | block characters, maintained | Not worth a dependency; the eight block characters are a literal. |

Nothing found for terminal bar charts; that part is small and ours. So: hand-written renderers, one tiny new dependency (blaze-svg), hvega optional later.

## Plan

Phases, each a separately useful, committable step:

1. **Foundation, with balance, text only.** In this order, with review stops:
   1. **Chart model types** (`Hledger.Write.Chart`), with haddocks, and nothing else. **Stop for review**: everything downstream depends on these,
      and reworking them later is the expensive failure.
   2. `bal` adapters (multi-period changes, `-H`/cumulative, single period) and `--chart[=KIND]` with `auto`;
      `--chart` with csv/tsv/json emitting the chart data. **Stop for review** of that data on examples/sample.journal,
      examples/bcexample.journal and a large generated journal, before any renderer exists.
   3. Text renderer; `--width` for bal.
   Functional tests: chart data via csv (tests the adapters), text golden files at a fixed width (tests the renderer); unit tests for scaling.
   Docs: output format section, balance docs, charts.md lead paragraph.
1b. **SVG.** SVG renderer on the same model; `svg` output format; tests with small fixtures.
2. **More reports and html.** is, bs, bse, cf, aregister, register; `--chart` with html output (chart above the table).
3. **Multiple outputs** (deferred). Repeatable `-o`, shared multi-output helper, migrate the main report commands.
4. **Interfaces.** hledger-web SVG charts on report pages; hledger-ui chart toggle.
5. **Variants and extras.** `--chart=KIND`; budget, prices, roi, holdings; sparkline column; `--view`; Vega-Lite export.


## Working notes

- Design is settled here; implementation phases are expected to run with Opus. The review stops above are the points where
  design judgment matters most; if one stalls on a design question, that is a reason to switch models for that decision only.
- Follow the project's usual practice: show each step's plan and discuss before starting; pre-commit checklist before every commit.

## Review notes

2026-10-15, second pass over the original brief and this plan:

- The brief's priorities (ubiquity, zero configuration, reuse across interfaces) all point at the same thing: invest in the
  model and the adapters' defaults, keep renderers dumb. The plan does that. The one structural choice to get right early is
  that the model carries *display* information from the report (period headings, commodity display styles, the report title,
  normal-balance sign convention) so every renderer labels things exactly as the table would.
- Charts in hledger-ui and hledger-web depend on the adapters, which live in the hledger package. Both already depend on it, so that's fine.
- The biggest risk is not rendering but choosing good defaults for messy real data: many commodities, deep trees, mixed signs,
  hundreds of periods, long account names. Test with examples/bcexample.journal and a large generated journal from the start, not just sample.journal.
- The "chart data as csv" decision is also a design aid: we can review what a chart will show before any renderer exists.
- Consider making `bal --chart` able to replace hledger-bar fully (it shows numbers always, auto-scales, handles commodities),
  so the script can later be retired without loss.

## Decisions

2026-10-15:

- Interface: the `--chart` flag plus the `svg` output format, as above. `-O` keeps its current meaning.
- Text charts first, then SVG.
- `--chart` with csv/tsv/json output emits the chart's data (the series after top-N and "other" aggregation), not the normal report.
  So the chart model needs a tabular rendering too; this doubles as a way to inspect what a chart shows.
- Deferred: repeatable `-o` (multiple outputs); reimplementing activity on the new renderer; hledger-bar's future.
- register/aregister text charts without an interval: try both one row per transaction and an automatic interval when we get there.

2026-10-16, after reviewing chart data on sample, bcexample and large generated journals:

- Panels are ordered by the number of non-zero report cells in each commodity (cells, not amounts, since a cell can hold several cost-keyed amounts of one commodity).
- No cap on the number of panels; instead, visual outputs (text, SVG) warn on stderr above a threshold, suggesting `-X` or `cur:`. To do in step 3.
- Chart data CSV is long ("tidy") form: commodity, series, role, mark, x, value.
- The net-total marker is kept even when all series have one sign.

2026-10-16, text renderer (step 3), after confirming mockups:

- Value column before the bars; stacked segments for several series (stocks too, in text); legend wrapped left to right; heading per commodity panel (omitted for no commodity).
- Fill characters cycle after four series (█▓▒░); colour distinguishes more. A limitation without colour.
- ASCII fallback is chosen from GHC's locale encoding; on macOS this reports UTF-8 even with LANG=C, so it is exercised only by a unit test.
- The many-panels warning (more than 8) is issued for text output only.

## Open questions

- Chart variant names for `--chart=KIND`, when needed.
- Whether `--chart` should become the default for html output, once proven.
