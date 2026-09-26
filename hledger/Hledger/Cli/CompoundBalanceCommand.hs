{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards   #-}
{-# LANGUAGE LambdaCase #-}
{-|

Common helpers for making multi-section balance report commands
like balancesheet, cashflow, and incomestatement.

-}

module Hledger.Cli.CompoundBalanceCommand (
  CompoundBalanceCommandSpec(..)
 ,compoundBalanceCommandMode
 ,compoundBalanceCommand
 ,compoundBalanceReportTitle
 ,applySubreportTitles
 ,CompoundBalanceReportParts(..)
 ,compoundBalanceReportAsSpreadsheetParts
 ,allCommoditiesFromSubreports
) where

import Control.Monad (guard, unless, void)
import Data.Bifunctor (second)
import Data.Foldable (traverse_)
import Data.List.NonEmpty (NonEmpty((:|)))
import Data.Maybe (fromMaybe, mapMaybe, maybeToList)
import Safe (atMay)
import Data.Map qualified as Map
import Data.Set qualified as Set
import Data.List qualified as List
import Data.List.NonEmpty qualified as NonEmpty
import Data.Text qualified as T
import Data.Text.Lazy qualified as TL
import Data.Text.Lazy.Builder qualified as TB
import Data.Time.Calendar (Day, addDays)
import System.Console.CmdArgs.Explicit as C (Mode, flagNone, flagReq)
import System.IO qualified as IO
import Text.Blaze.Html5 ((!), preEscapedToHtml)
import Text.Blaze.Html5 qualified as H
import Text.Blaze.Html5.Attributes qualified as A
import Text.Tabular.AsciiWide as Tabular hiding (render)

import Hledger
import Hledger.Cli.Anchor (LinkOpts(..), headerDateSpanCell)
import Hledger.Cli.Commands.Balance
import Hledger.Cli.CliOptions
import Hledger.Cli.Utils (unsupportedOutputFormatError, writeOutputLazyText)
import Hledger.Cli.Commands.Balance.Internal
import Hledger.Write.Csv (CSV, printCSV, printTSV)
import Hledger.Write.Html (formatRow, formatTitle, htmlAsLazyText, nl, Html, toHtml)
import Hledger.Write.Html.Attribute (stylesheet, tableStyle)
import Hledger.Write.Ods (printFods)
import Hledger.Write.Spreadsheet qualified as Spr

-- | Description of a compound balance report command,
-- from which we generate the command's cmdargs mode and IO action.
-- A compound balance report command shows one or more sections/subreports,
-- each with its own title and subtotals row, in a certain order,
-- plus a grand totals row if there's more than one section.
-- Examples are the balancesheet, cashflow and incomestatement commands.
--
-- Compound balance reports do sign normalisation: they show all account balances
-- as normally positive, unlike the ordinary BalanceReport and most hledger commands
-- which show income/liability/equity balances as normally negative.
-- Each subreport specifies the normal sign of its amounts, and whether
-- it should be added to or subtracted from the grand total.
--
data CompoundBalanceCommandSpec = CompoundBalanceCommandSpec {
  cbcdoc      :: CommandHelpStr,                  -- ^ the command's name(s) and documentation
  cbctitle    :: String,                          -- ^ overall report title
  cbcqueries  :: [CBCSubreportSpec DisplayName],  -- ^ subreport details
  cbcaccum    :: BalanceAccumulation              -- ^ how to accumulate balances (per-period, cumulative, historical)
                                                  --   (overrides command line flags)
}

-- | Generate a cmdargs option-parsing mode from a compound balance command
-- specification.
compoundBalanceCommandMode :: CompoundBalanceCommandSpec -> Mode RawOpts
compoundBalanceCommandMode CompoundBalanceCommandSpec{..} =
  hledgerCommandMode
   cbcdoc
   -- keep roughly consistent order with Balance.hs. XXX refactor
   (
    -- https://hledger.org/dev/hledger.html#calculation-mode :
    [flagNone ["sum"] (setboolopt "sum")
      (calcprefix ++ "show sum of posting amounts (default)")
    ,flagNone ["valuechange"] (setboolopt "valuechange")
      (calcprefix ++ "show total change of value of period-end historical balances (caused by deposits, withdrawals, market price fluctuations)")
    ,flagNone ["gain"] (setboolopt "gain")
      (calcprefix ++ "show unrealised capital gain/loss (historical balance value minus cost basis)")
  -- currently not supported by compound balance commands:
  --  ,flagNone ["budget"] (setboolopt "budget")
  --     (calcprefix ++ "show sum of posting amounts compared to budget goals defined by periodic transactions")
   ,flagNone ["count"] (setboolopt "count") (calcprefix ++ "show the count of postings")

    -- https://hledger.org/dev/hledger.html#accumulation-mode :
   ,flagNone ["change"] (setboolopt "change")
      (accumprefix ++ "accumulate amounts from column start to column end (in multicolumn reports)" ++ defaultMarker PerPeriod)
    ,flagNone ["cumulative"] (setboolopt "cumulative")
      (accumprefix ++ "accumulate amounts from report start (specified by e.g. -b/--begin) to column end" ++ defaultMarker Cumulative)
    ,flagNone ["historical","H"] (setboolopt "historical")
      (accumprefix ++ "accumulate amounts from journal start to column end (includes postings before report start date)" ++ defaultMarker Historical)
    ]

    ++ flattreeflags True ++
    [flagReq  ["drop"] (\s opts -> Right $ setopt "drop" s opts) "N" "in list mode, omit N leading account name parts"
    ,flagNone ["declared"] (setboolopt "declared") "include non-parent declared accounts (best used with -E)"
    ,flagNone ["average","A"] (setboolopt "average") "show a row average column (in multicolumn reports)"
    ,flagNone ["row-total","T"] (setboolopt "row-total") "show a row total column (in multicolumn reports)"
    ,flagNone ["summary-only"] (setboolopt "summary-only") "display only row summaries (e.g. row total, average) (in multicolumn reports)"
    ,flagNone ["no-total","N"] (setboolopt "no-total") "omit the final total row"
    ,flagNone ["no-elide"] (setboolopt "no-elide") "in tree mode, don't squash boring parent accounts; in list mode, also show parent accounts (usually zero, hidden without -E)"
    ,flagNone ["full-names"] (setboolopt "full-names") "in tree mode, show full account names instead of indented leaf names"
    ,flagReq  ["format"] (\s opts -> Right $ setopt "format" s opts) "FORMATSTR" "use this custom line format (in simple reports)"
    ,flagNone ["sort-amount","S"] (setboolopt "sort-amount") "sort by amount instead of account code/name"
    ,flagNone ["percent", "%"] (setboolopt "percent") "express values in percentage of each column's total"
    ,flagReq  ["layout"] (\s opts -> Right $ setopt "layout" s opts) "ARG"
      (unlines
        ["how to show multi-commodity amounts:"
        ,"'wide[,WIDTH]': all commodities on one line"
        ,"'tall'        : each commodity on a new line"
        ,"'bare'        : bare numbers, symbols in a column"
        ])
    ,flagReq  ["base-url"] (\s opts -> Right $ setopt "base-url" s opts) "URLPREFIX" "in html output, generate hyperlinks to hledger-web, with this prefix. (Usually the base url shown by hledger-web; can also be relative.)"

    ,outputFormatFlag ["txt","html","csv","tsv","json"]
    ,outputFileFlag

    ])
    cligeneralflagsgroups1
    (hiddenflags ++
      [ flagNone ["commodity-column"] (setboolopt "commodity-column")
        "show commodity symbols in a separate column, amounts as bare numbers, one row per commodity"
      ])
    ([], Just $ argsFlag "[QUERY]")
 where
  calcprefix = "calculation mode: "
  accumprefix = "accumulation mode: "
  defaultMarker :: BalanceAccumulation -> String
  defaultMarker bacc | bacc == cbcaccum = " (default)"
                     | otherwise        = ""

-- | Generate a runnable command from a compound balance command specification.
compoundBalanceCommand :: CompoundBalanceCommandSpec -> (CliOpts -> Journal -> IO ())
compoundBalanceCommand spec@CompoundBalanceCommandSpec{..} opts@CliOpts{reportspec_=rspec, rawopts_=rawopts} j = do
    writeOutputLazyText opts $ render $ styleAmounts styles cbr
  where
    styles = journalCommodityStylesWith HardRounding j
    ropts = _rsReportOpts rspec
    -- use the default balance type for this report, unless the user overrides
    mbalanceAccumulationOverride = balanceAccumulationOverride rawopts
    balanceaccumulation = fromMaybe cbcaccum mbalanceAccumulationOverride
    -- Set balance type in the report options.
    ropts' = ropts{balanceaccum_=balanceaccumulation}

    -- make a CompoundBalanceReport. The default heading is the auto-generated
    -- title; --title=TEXT overrides it (and =empty suppresses).
    -- --subreport-titles=A|B|... overrides per-subreport titles.
    cbr' = compoundBalanceReport rspec{_rsReportOpts=ropts'} j cbcqueries
    cbr  = applySubreportTitles ropts' $
           cbr'{cbrTitle = effectiveTitle ropts' $ compoundBalanceReportTitle spec ropts mbalanceAccumulationOverride cbr'}

    -- render appropriately
    render = case outputFormatFromOpts opts of
      "txt"  -> compoundBalanceReportAsText ropts'
      "csv"  -> printCSV . compoundBalanceReportAsCsv ropts' cbcqueries
      "tsv"  -> printTSV . compoundBalanceReportAsCsv ropts' cbcqueries
      "html" -> (<>"\n") . htmlAsLazyText . compoundBalanceReportAsHtml ropts' cbcqueries
      "fods" -> printFods IO.localeEncoding .
                fmap (second NonEmpty.toList) . uncurry Map.singleton .
                compoundBalanceReportAsSpreadsheet
                    oneLineNoCostFmt "Account" (Just "") ropts' cbcqueries
      "json" -> toJsonText
      x      -> error' $ unsupportedOutputFormatError x

-- | The title of a compound balance report: the interval and report
-- name, the dates, a note when the accumulation mode was overridden or
-- the calculation is not the plain one, and the valuation. The report
-- options are the command line's, with any accumulation override given
-- separately, since the title says which it was.
compoundBalanceReportTitle ::
  CompoundBalanceCommandSpec -> ReportOpts -> Maybe BalanceAccumulation -> CompoundPeriodicReport a b -> T.Text
compoundBalanceReportTitle CompoundBalanceCommandSpec{cbctitle=cbctitle, cbcaccum=cbcaccum} ReportOpts{..} mbalanceAccumulationOverride cbr =
     maybe "" (<>" ") mintervalstr
  <> T.pack cbctitle
  <> " "
  <> titledatestr
  <> maybe "" (" "<>) mtitleclarification
  <> valuationdesc
  where
    balanceaccumulation = fromMaybe cbcaccum mbalanceAccumulationOverride

    -- XXX #1078 the title of ending balance reports
    -- (Historical) should mention the end date(s) shown as
    -- column heading(s) (not the date span of the transactions).
    -- Also the dates should not be simplified (it should show
    -- "2008/01/01-2008/12/31", not "2008").
    titledatestr = case balanceaccumulation of
        Historical -> showEndDates enddates
        _          -> showDateSpan columnsspan
      where
        enddates = map (addDays (-1)) . mapMaybe spanEnd $ cbrDates cbr  -- these spans will always have a definite end date
        -- the span the columns cover: the requested span, widened to whole intervals
        columnsspan = spansSpan $ cbrDates cbr

    mintervalstr = showInterval interval_

    -- when user overrides, add an indication to the report title
    -- Do we need to deal with overridden BalanceCalculation?
    mtitleclarification = case (balancecalc_, balanceaccumulation, mbalanceAccumulationOverride) of
        (CalcValueChange, PerPeriod,  _              ) -> Just "(Period-End Value Changes)"
        (CalcValueChange, Cumulative, _              ) -> Just "(Cumulative Period-End Value Changes)"
        (CalcGain,        PerPeriod,  _              ) -> Just "(Incremental Gain)"
        (CalcGain,        Cumulative, _              ) -> Just "(Cumulative Gain)"
        (CalcGain,        Historical, _              ) -> Just "(Historical Gain)"
        (_,               _,          Just PerPeriod ) -> Just "(Balance Changes)"
        (_,               _,          Just Cumulative) -> Just "(Cumulative Ending Balances)"
        (_,               _,          Just Historical) -> Just "(Historical Ending Balances)"
        _                                              -> Nothing

    valuationdesc =
      (case conversionop_ of
           Just ToCost -> ", converted to cost"
           _           -> "")
      <> (case value_ of
           Just (AtThen _mc)       -> ", valued at posting date"
           Just (AtEnd _mc) | changingValuation -> ""
           Just (AtEnd _mc)        -> ", valued at period ends"
           Just (AtNow _mc)        -> ", current value"
           Just (AtDate today _mc) -> ", valued at " <> showDate today
           Nothing                 -> "")

    changingValuation = case (balancecalc_, balanceaccum_) of
        (CalcValueChange, PerPeriod)  -> True
        (CalcValueChange, Cumulative) -> True
        _                             -> False

-- | Apply --subreport-titles overrides to a compound report's subreports.
-- A `|`-separated argument overrides the corresponding subreport titles, in
-- order; subreports beyond the supplied list keep their default title. An
-- explicit empty argument suppresses all default subreport titles.
applySubreportTitles :: ReportOpts -> CompoundPeriodicReport a b -> CompoundPeriodicReport a b
applySubreportTitles ropts cbr@CompoundPeriodicReport{cbrSubreports=subs} =
  case subreport_titles_ ropts of
    Nothing -> cbr
    Just s
      | T.null s  -> cbr{cbrSubreports = map (\(_,r,b) -> ("", r, b)) subs}
      | otherwise ->
          let custom = T.splitOn "|" s
              replace i (old,r,b) = (fromMaybe old (atMay custom i), r, b)
          in  cbr{cbrSubreports = zipWith replace [0..] subs}

-- | Show a simplified description of an Interval.
showInterval :: Interval -> Maybe T.Text
showInterval = \case
  NoInterval -> Nothing
  Days 1     -> Just "Daily"
  Weeks 1    -> Just "Weekly"
  Weeks 2    -> Just "Biweekly"
  Months 1   -> Just "Monthly"
  Months 2   -> Just "Bimonthly"
  Months 3   -> Just "Quarterly"
  Months 6   -> Just "Half-yearly"
  Months 12  -> Just "Yearly"
  Quarters 1 -> Just "Quarterly"
  Quarters 2 -> Just "Half-yearly"
  Years 1    -> Just "Yearly"
  Years 2    -> Just "Biannual"
  _          -> Just "Periodic"

-- | Summarise one or more (inclusive) end dates, in a way that's
-- visually different from showDateSpan, suggesting discrete end dates
-- rather than a continuous span.
showEndDates :: [Day] -> T.Text
showEndDates es = case es of
  -- cf showPeriod
  (e:_:_) -> showDate e <> ".." <> showDate (last es)
  [e]     -> showDate e
  []      -> ""

-- | Render a compound balance report as plain text suitable for console output.
{- Eg:
Balance Sheet

             ||  2017/12/31    Total  Average
=============++===============================
 Assets      ||
-------------++-------------------------------
 assets:b    ||           1        1        1
-------------++-------------------------------
             ||           1        1        1
=============++===============================
 Liabilities ||
-------------++-------------------------------
-------------++-------------------------------
             ||
=============++===============================
 Total       ||           1        1        1

-}
compoundBalanceReportAsText :: ReportOpts -> CompoundPeriodicReport DisplayName MixedAmount -> TL.Text
compoundBalanceReportAsText ropts (CompoundPeriodicReport title _colspans subreports totalsrow) =
  TB.toLazyText $
    titleBuilder <>
    multiBalanceReportTableAsText ropts bigtablewithtotalsrow
  where
    titleBuilder | T.null title = mempty
                 | otherwise    = TB.fromText title <> TB.fromText "\n\n"
    bigtable =
      case map (subreportAsTable ropts) subreports of
        []   -> Tabular.empty
        r:rs -> List.foldl' (concatTables tableInterSubreportBorder) r rs
    bigtablewithtotalsrow =
      if no_total_ ropts || length subreports == 1
      then bigtable
      else concatTables tableGrandTotalsTopBorder bigtable totalstable
        where
          -- Append the report's grand column totals at the bottom of the table.
          -- Note "row" is confusingly overloaded here; *Report rows, Table rows,
          -- and visually apparent table rows are all distinct.
          -- With multiple currencies, in some layout modes, the column totals (a single report row)
          -- occupy multiple lines, which currently we put into multiple table rows,
          -- for convenience I guess, borderless so they look like a single visual row.
          --
          -- multiBalanceRowAsText gets a matrix of each line of each column total rendered as text
          -- (actually as WideBuilders), in line-major-order:
          --  [
          --   [COL1LINE1, COL2LINE1]
          --   [COL1LINE2, COL2LINE2]
          --  ]
          coltotalslines = multiBalanceRowAsText ropts allCommodities totalsrow
          totalstable = Table
            (Group NoLine $ map Header $ "Net:" : replicate (length coltotalslines - 1) "")  -- row headers
            (Header [])     -- column headers, concatTables will discard these
            coltotalslines  -- cell values         

    allCommodities = allCommoditiesFromSubreports subreports

    -- | Convert a named multi balance report to a table suitable for
    -- concatenating with others to make a compound balance report table.
    -- An empty subreport title is omitted entirely (no title row above the data).
    subreportAsTable ropts1 (title1, r, _) = tablewithtitle
      where
        Table lefthdrs tophdrs cells =
            multiBalanceReportAsPartTable ropts1 allCommodities r
        tablewithtitle
          | T.null title1 = Table lefthdrs tophdrs cells
          | otherwise     = Table
              (Group tableSubreportTitleBottomBorder [Header title1, lefthdrs])  -- row headers
              tophdrs       -- column headers
              ([]:cells)    -- cell values

    tableSubreportTitleBottomBorder = SingleLine
    tableInterSubreportBorder       = DoubleLine
    tableGrandTotalsTopBorder       = DoubleLine

-- | Render a compound balance report as CSV.
-- Subreports' CSV is concatenated, with the headings rows replaced by a
-- subreport title row, and an overall title row, one headings row, and an
-- optional overall totals row is added.
compoundBalanceReportAsCsv ::
  ReportOpts -> [CBCSubreportSpec DisplayName] -> CompoundPeriodicReport DisplayName MixedAmount -> CSV
compoundBalanceReportAsCsv ropts specs cbr =
    let spreadsheet =
            snd $ snd $
            compoundBalanceReportAsSpreadsheet
                machineFmt "Account" Nothing ropts specs cbr
        title = cbrTitle cbr
        titleRows | T.null title = []
                  | otherwise =
                      [Spr.horizontalSpan (NonEmpty.head spreadsheet)
                         (Spr.headerCell title)]
    in  Spr.rawTableContent $
        titleRows ++ NonEmpty.toList spreadsheet

-- | Render a compound balance report as HTML.
compoundBalanceReportAsHtml ::
  ReportOpts -> [CBCSubreportSpec DisplayName] -> CompoundPeriodicReport DisplayName MixedAmount -> Html
compoundBalanceReportAsHtml ropts specs cbr =
  let (title, (_fixed, cells)) =
          compoundBalanceReportAsSpreadsheet
              oneLineNoCostFmt "" (Just nbsp) ropts specs cbr
  in do
    -- the builtin styles, then the optional user stylesheet so it can override them
    H.style $ preEscapedToHtml $ stylesheet $
      tableStyle ++ [
      ("td:nth-child(1)", "white-space:nowrap"),
      ("tr:nth-child(odd) td", "background-color:#eee")
      ]
    nl
    H.link ! A.rel "stylesheet" ! A.href "hledger.css"
    nl
    unless (T.null title) $ formatTitle title
    -- Do not use `styledTableHtml` here since that leads to nested `<table>`s.
    H.table $ nl <> (traverse_ formatRow $ fmap (map (fmap toHtml)) cells)

-- | Render a compound balance report as Spreadsheet: the heading row,
-- then each section's title row, body rows, totals rows, and a blank row
-- for whitespace if wanted, then the net total rows.
compoundBalanceReportAsSpreadsheet ::
  AmountFormat -> T.Text -> Maybe T.Text ->
  ReportOpts -> [CBCSubreportSpec DisplayName] -> CompoundPeriodicReport DisplayName MixedAmount ->
  (T.Text, ((Int, Int), NonEmpty [Spr.Cell Spr.NumLines T.Text]))
compoundBalanceReportAsSpreadsheet fmt accountLabel maybeBlank ropts specs cbr =
  let
    CompoundBalanceReportParts{..} = compoundBalanceReportAsSpreadsheetParts fmt accountLabel ropts specs cbr
    dataHeaders = map Spr.cellContent cbrpDataHeaders
    headerrow =
      cbrpLeadingHeaders ++
      concatMap (Spr.horizontalSpan subColumns) cbrpDataHeaders

    blankrow =
      fmap (Spr.horizontalSpan headerrow . Spr.defaultCell) maybeBlank
    subColumns =
        case layout_ ropts of
            LayoutBareWide -> void allCommodities
            _ -> [()]
    allCommodities = allCommoditiesFromSubreports $ cbrSubreports cbr

    sectionrows (subreporttitle, bodyrows, totalsrows) =
      let
        accountCell =
            (Spr.defaultCell subreporttitle) {
                Spr.cellStyle = Spr.Body Spr.Total,
                Spr.cellClass = accountClass
            }
        titleRows
          | T.null subreporttitle = []
          | otherwise =
              [case layout_ ropts of
                  LayoutBareWide ->
                      accountCell :
                      map Spr.headerCell (dataHeaders >> allCommodities)
                  _ -> Spr.horizontalSpan headerrow accountCell]
      in
        titleRows ++
        bodyrows ++
        totalsrows ++
        maybeToList blankrow

  in  (cbrTitle cbr,
        ((1, multiBalanceReportNumHeaderColumns $ layout_ ropts),
            headerrow :| concatMap sectionrows cbrpSections ++ cbrpNetRows))

-- | The parts of a compound balance report as spreadsheet cells, to be
-- laid out as one table, or as a table with sections as hledger-web does.
data CompoundBalanceReportParts = CompoundBalanceReportParts {
    cbrpLeadingHeaders :: [Spr.Cell Spr.NumLines T.Text],
      -- ^ The heading row's first cell(s): the account column's, and the
      --   tidy and bare layouts' extra columns'.
    cbrpDataHeaders    :: [Spr.Cell Spr.NumLines T.Text],
      -- ^ Then a heading per data column: each period, linking to the
      --   register for it, then the row total and average when shown.
      --   In the bare-wide layout each of these spans the commodity columns.
    cbrpSections       :: [(T.Text, [[Spr.Cell Spr.NumLines T.Text]], [[Spr.Cell Spr.NumLines T.Text]])],
      -- ^ Each section's title, body rows, and totals rows.
    cbrpNetRows        :: [[Spr.Cell Spr.NumLines T.Text]]
      -- ^ The net total rows; none when there is one section or no totals.
}

-- | Render a compound balance report's parts as spreadsheet cells. The
-- subreport specs it was made from say how each section's figures link:
-- a section is rendered with its own report options, so that its links
-- say when its figures are negated, and its totals link to the registers
-- of its account types.
compoundBalanceReportAsSpreadsheetParts ::
  AmountFormat -> T.Text ->
  ReportOpts -> [CBCSubreportSpec DisplayName] -> CompoundPeriodicReport DisplayName MixedAmount ->
  CompoundBalanceReportParts
compoundBalanceReportAsSpreadsheetParts fmt accountLabel ropts specs cbr =
  CompoundBalanceReportParts {
    cbrpLeadingHeaders = leadingHeaders,
    cbrpDataHeaders = dataHeaderCells,
    cbrpSections = zipWith section specs subreports,
    cbrpNetRows = netrows
  }
  where
    CompoundPeriodicReport _ colspans subreports totalrow = cbr
    leadingHeaders =
      Spr.headerCell accountLabel :
      case layout_ ropts of
          LayoutTidy -> map Spr.headerCell tidyColumnLabels
          LayoutBare -> [Spr.headerCell "Commodity"]
          _ -> []
    -- A period heading links to the register for that period; its text
    -- is the period's end date in a historical report.
    dataHeaderCells =
      (guard (layout_ ropts /= LayoutTidy) >>) $
      [ (headerDateSpanCell (date2_ ropts) (period_titles_ ropts) (balance_base_url_ ropts) (querystring_ ropts) spn) {
          Spr.cellBorder = Spr.noBorder,
          Spr.cellContent = reportPeriodName (period_titles_ ropts) (balanceaccum_ ropts) colspans spn
        }
      | not (summary_only_ ropts), spn <- colspans ] ++
      (guard (multiBalanceHasTotalsColumn ropts) >> [Spr.headerCell "Total"]) ++
      (guard (average_ ropts) >> [Spr.headerCell "Average"])
    allCommodities = allCommoditiesFromSubreports subreports

    -- The account type codes a section is selected by, which its totals'
    -- registers need; a section not selected by type gets no such links.
    typeCodes q = case q of
      Type ts -> Just $ T.concat $ map (T.pack . show) ts
      _       -> Nothing
    typeTerm = fmap ("type:" <>) . typeCodes
    -- Is a section shown with its figures negated, as normally negative
    -- accounts are ?
    negated spec = normalbalance_ (cbcsubreportoptions spec ropts) == Just NormallyNegative
    unlinked = map (map (\c -> c {Spr.cellAnchor = mempty, Spr.cellTitle = mempty}))
    linkedWhen mterm rows = maybe (unlinked rows) (const rows) mterm

    -- A section's rows link with its type term as well, so that their
    -- registers exclude a subaccount of another type, as the figures do.
    section spec (subreporttitle, mbr, _increasestotal) = (subreporttitle, bodyrows, totalsrows)
      where
        sropts = cbcsubreportoptions spec ropts
        sectionterm = typeTerm $ cbcsubreportquery spec
        (_, bodyrows, _) =
          balanceSubReportAsSpreadsheetParts fmt
            sropts{no_total_ = True, querystring_ = maybeToList sectionterm ++ querystring_ sropts}
            allCommodities mbr
        totalsrows
          | no_total_ ropts = []
          | otherwise =
              linkedWhen sectionterm $
              multiBalanceTotalsRows fmt sropts (reportLinkOpts sropts (prDates mbr)) (maybeToList sectionterm)
                  allCommodities (prDates mbr) totalRowHeadingSpreadsheet (prTotals mbr)

    -- The net total's register is that of all the sections' account
    -- types. It shows the net with the opposite sign when a section's
    -- negation is not undone by subtracting it, as an income statement's
    -- revenues are added negated.
    netterm = fmap (("type:" <>) . T.concat) $ traverse (typeCodes . cbcsubreportquery) specs
    netnegated = any (\spec -> negated spec /= not (cbcsubreportincreasestotal spec)) specs
    netrows =
      if no_total_ ropts || length subreports == 1 then []
      else
        linkedWhen netterm $
        multiBalanceTotalsRows fmt ropts (reportLinkOpts ropts colspans){loNegated = netnegated}
            (maybeToList netterm) allCommodities colspans "Net:" totalrow

-- | All commodities appearing in any of these subreports, sorted.
-- Used as the commodity column order for LayoutBareWide across the whole
-- compound report; it must cover every row rendered, including the totals
-- row, see 'setDisplayCommodityBare' in "Hledger.Cli.Commands.Balance.Internal".
allCommoditiesFromSubreports ::
    [(text, PeriodicReport a MixedAmount, bool)] -> [CommoditySymbol]
allCommoditiesFromSubreports =
    Set.toAscList .
    foldMap (\(_,mbr,_) ->
                foldMap (foldMap maCommodities . prrAmounts) $ prRows mbr)
