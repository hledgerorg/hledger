{-# LANGUAGE OverloadedStrings    #-}
{-# LANGUAGE NamedFieldPuns       #-}
{-# LANGUAGE RecordWildCards      #-}

module Hledger.Cli.Commands.Balance.Internal where

import Control.Monad (guard)
import Data.List (transpose)
import Data.Set qualified as S
import Data.Text (Text)
import Data.Text qualified as T
import Data.Time (addDays)
import Text.Tabular.AsciiWide (Header(..), Properties(..), Table(..), concatTables)

import Hledger
import Hledger.Cli.Anchor (LinkOpts(..), dateTerm, removeDates, withLink, setAccountAnchorWith,
  dateSpanCellWith, totalDateSpanCell, headerDateSpanCell, renderPeriodHeading, amountPhrase)
import Hledger.Write.Spreadsheet (rawTableContent, headerCell,
            addHeaderBorders, addRowSpanHeader,
            cellFromMixedAmount, cellsFromMixedAmount)
import Hledger.Write.Spreadsheet qualified as Ods



-- Rendering

accountClass :: Ods.Class
accountClass = Ods.Class "account"

data RowClass = Value | Total
    deriving (Eq, Ord, Enum, Bounded, Show)

amountClass :: RowClass -> Ods.Class
amountClass rc =
    Ods.Class $
    case rc of Value -> "amount"; Total -> "amount coltotal"

rowTotalClass :: RowClass -> Ods.Class
rowTotalClass rc =
    Ods.Class $
    case rc of Value -> "amount rowtotal"; Total -> "amount coltotal"

rowAverageClass :: RowClass -> Ods.Class
rowAverageClass rc =
    Ods.Class $
    case rc of Value -> "amount rowaverage"; Total -> "amount colaverage"

-- What to show as heading for the totals row in balance reports ?
-- Currently nothing in terminal, Total: in HTML, FODS and xSV output.
totalRowHeadingText        :: Text
totalRowHeadingSpreadsheet :: Text
totalRowHeadingBudgetText  :: Text
totalRowHeadingBudgetCsv   :: Text

totalRowHeadingText        = ""
totalRowHeadingSpreadsheet = "Total:"
totalRowHeadingBudgetText  = ""
totalRowHeadingBudgetCsv   = "Total:"


headerWithoutBorders :: [Ods.Cell () text] -> [Ods.Cell Ods.NumLines text]
headerWithoutBorders = map (\c -> c {Ods.cellBorder = Ods.noBorder})

simpleDateSpanCell :: PeriodTitles -> DateSpan -> Ods.Cell Ods.NumLines Text
simpleDateSpanCell ph = Ods.defaultCell . renderPeriodHeading ph

-- | Do this report's figures link to registers? Only when they are
-- sums of postings, which is what a register shows.
figuresLink :: ReportOpts -> Bool
figuresLink ropts = balancecalc_ ropts == CalcChange && not (percent_ ropts)

-- | The register link options of a report's rows: its accumulation
-- mode, the span its columns cover, and whether it shows figures with
-- the sign opposite to the register's (as the compound reports' negated
-- sections do).
reportLinkOpts :: ReportOpts -> [DateSpan] -> LinkOpts
reportLinkOpts ropts colspans = LinkOpts {
    loAccum        = balanceaccum_ ropts,
    loSpan         = spansSpan colspans,
    loDate2        = date2_ ropts,
    loIncludesSubs = True,
    loNegated      = normalbalance_ ropts == Just NormallyNegative
}

-- | The link options of one account's row: whether its figures include
-- the subaccounts. In tree mode every row does. In list mode a row
-- excludes them only when some of them have rows of their own; a
-- depth-clipped row, or a parent whose children are not shown, sums them.
rowLinkOpts :: ReportOpts -> [DateSpan] -> S.Set AccountName -> AccountName -> LinkOpts
rowLinkOpts ropts colspans shownParents acct =
    (reportLinkOpts ropts colspans) {
        loIncludesSubs = tree_ ropts || acct `S.notMember` shownParents
    }

-- | The accounts that have a subaccount among the given rows.
shownParentsOf :: [AccountName] -> S.Set AccountName
shownParentsOf = S.fromList . concatMap parentAccountNames

addTotalBorders ::
    (Functor f) =>
    [f (Ods.Cell border text)] -> [f (Ods.Cell Ods.NumLines text)]
addTotalBorders =
    zipWith
        (\border ->
            fmap (\c -> c {
                    Ods.cellStyle = Ods.Body Ods.Total,
                    Ods.cellBorder = Ods.noBorder {Ods.borderTop = border}}))
        (Ods.DoubleLine : repeat Ods.NoLine)


nbsp :: Text
nbsp = "\160"


renderBalanceAcct ::
    ReportOpts -> Text -> (AccountName, AccountName, Int) -> Text
renderBalanceAcct opts space (fullName, displayName, dep) =
  if accountlistmode_ opts == ALTree && not (full_names_ opts)
    then T.replicate (dep*2) space <> displayName
    else accountNameDrop (drop_ opts) fullName

-- FIXME. Have to check explicitly for which to render here, since
-- budgetReport sets accountlistmode to ALTree. Find a principled way to do
-- this.
renderPeriodicAcct ::
    ReportOpts -> Text -> PeriodicReportRow DisplayName a -> Text
renderPeriodicAcct opts space row =
    renderBalanceAcct opts space
        (prrFullName row, prrDisplayName row, prrIndent row)



multiBalanceHasTotalsColumn :: ReportOpts -> Bool
multiBalanceHasTotalsColumn ropts =
    row_total_ ropts && balanceaccum_ ropts `notElem` [Cumulative, Historical]


multiBalanceReportAsPartTable ::
    ReportOpts -> [CommoditySymbol] -> MultiBalanceReport ->
    Table T.Text T.Text WideBuilder
multiBalanceReportAsPartTable
    opts@ReportOpts{summary_only_, average_, balanceaccum_}
    allCommodities
    (PeriodicReport spans items tr) =
   maybetranspose $
   addtotalrow $
   Table
     (Group multiColumnTableInterRowBorder    $ map Header $ concat accts)
     (Group multiColumnTableInterColumnBorder $ map Header colheadings)
     (concat rows)
  where
    colheadings =
      ["Commodity" | layout_ opts == LayoutBare]
      ++
      case layout_ opts of
          LayoutBareWide ->
              liftA2 (\s c -> T.concat [s, " (", c, ")"])
                  spanNames allCommodities
          _ -> spanNames
    spanNames =
        (guard (not summary_only_) >>
            map (reportPeriodName (period_titles_ opts) balanceaccum_ spans) spans)
        ++ ["  Total" | multiBalanceHasTotalsColumn opts]
        ++ ["Average" | average_]
    (accts, rows) = unzip $ fmap fullRowAsTexts items'
      where
        isLeaf rs row = not $ any (\r -> T.isPrefixOf (displayFull (prrName row) <> ":") (displayFull (prrName r))) rs
        items' = if transpose_ opts && tree_ opts
                 then filter (isLeaf items) items
                 else items
        fullRowAsTexts row = (replicate (length rs) (renderacct row), rs)
          where
            rs = multiBalanceRowAsText opts allCommodities row
            renderacct row' = renderPeriodicAcct opts " " row'
    addtotalrow
      | no_total_ opts = id
      | otherwise =
        let totalrows = multiBalanceRowAsText opts allCommodities tr
            rowhdrs = Group NoLine $ map Header $ totalRowHeadingText : replicate (length totalrows - 1) ""
            colhdrs = Header [] -- unused, concatTables will discard
        in (flip (concatTables SingleLine) $ Table rowhdrs colhdrs totalrows)
    maybetranspose | transpose_ opts = \(Table rh ch vals) -> Table ch rh (transpose vals)
                   | otherwise       = id
    multiColumnTableInterRowBorder    = NoLine
    multiColumnTableInterColumnBorder = if pretty_ opts then SingleLine else NoLine


multiBalanceRowAsText ::
    ReportOpts -> [CommoditySymbol] -> PeriodicReportRow a MixedAmount -> [[WideBuilder]]
multiBalanceRowAsText opts allCommodities =
    rawTableContent .
    multiBalanceRowAsCellBuilders oneLineNoCostFmt{displayColour=color_ opts}
        opts [] allCommodities
        Value (simpleDateSpanCell $ period_titles_ opts)

multiBalanceRowAsCellBuilders ::
    AmountFormat -> ReportOpts -> [DateSpan] -> [CommoditySymbol] ->
    RowClass -> (DateSpan -> Ods.Cell Ods.NumLines Text) ->
    PeriodicReportRow a MixedAmount ->
    [[Ods.Cell Ods.NumLines WideBuilder]]
multiBalanceRowAsCellBuilders bopts ropts@ReportOpts{..} colspans allCommodities
      rc renderDateSpanCell (PeriodicReportRow _acct as rowtot rowavg) =
    case layout_ of
      LayoutWide width ->
          [zipWith linkFigure spanclsamts $
            map (cellFromMixedAmount bopts{displayMaxWidth=width}) clsamts]
      LayoutTall       -> paddedTranspose Ods.emptyCell
                           . map (cellsFromMixedAmount bopts{displayMaxWidth=Nothing})
                           $ clsamts
      LayoutBare       -> zipWith (:) (map wbCell cs)  -- add symbols
                           . transpose                         -- each row becomes a list of Text quantities
                           . map (cellsFromMixedAmount (setDisplayCommodityBare cs bopts))
                           $ clsamts
      LayoutBareWide   -> [concatMap (cellsFromMixedAmount (setDisplayCommodityBare allCommodities bopts))
                            $ clsamts]
      LayoutTidy       -> concat
                           . zipWith (map . addDateColumns) colspans
                           . map ( zipWith (\c a -> [wbCell c, a]) cs
                                  . cellsFromMixedAmount (setDisplayCommodityBare cs bopts))
                           $ classified
                                 -- Do not include totals column or average for tidy output, as this
                                 -- complicates the data representation and can be easily calculated
  where
    wbCell = Ods.defaultCell . wbFromText
    wbDate content = (wbCell content) {Ods.cellType = Ods.TypeDate}
    cs = if all mixedAmountLooksZero allamts then [""] else S.toList $ foldMap maCommodities allamts
    classified = map ((,) (amountClass rc)) as
    allamts = map snd clsamts
    clsamts = map snd spanclsamts
    -- Each figure with its class, and the span it covers: a column's, the
    -- whole report's for a row total, none for an average. The text
    -- renderer passes no spans.
    spanclsamts =
        (if not summary_only_ then zip (map Just colspans ++ repeat Nothing) classified else []) ++
        [(Just (spansSpan colspans) <* guard (not $ null colspans), (rowTotalClass rc, rowtot)) |
            multiBalanceHasTotalsColumn ropts && not (null as)] ++
        [(Nothing, (rowAverageClass rc, rowavg)) | average_ && not (null as)]
    -- In the wide layout each figure links to the register it is derived
    -- from, through the row's date span cell for the span it covers. A
    -- figure that looks zero has an empty register, and a figure that is
    -- not a sum of postings has none, so neither links. A totals row's
    -- date span cell carries its own title.
    linkFigure (Just spn, (_, amt)) c
      | figuresLink ropts && not (mixedAmountLooksZero amt) =
          let dsCell = renderDateSpanCell spn in
          withLink (Ods.cellAnchor dsCell)
              (if rc == Total then Ods.cellTitle dsCell
               else amountPhrase (reportLinkOpts ropts colspans) False) c
    linkFigure _ c = c
    addDateColumns spn@(DateSpan s e) remCols =
        (wbFromText <$> renderDateSpanCell spn) :
        wbDate (maybe "" showEFDate s) :
        wbDate (maybe "" (showEFDate . modifyEFDay (addDays (-1))) e) :
        remCols

    paddedTranspose :: a -> [[a]] -> [[a]]
    paddedTranspose _ [] = [[]]
    paddedTranspose n as1 = take (maximum . map length $ as1) . trans $ as1
        where
          trans ([] : xss)  = (n : map h xss) :  trans ([n] : map t xss)
          trans ((x : xs) : xss) = (x : map h xss) : trans (m xs : map t xss)
          trans [] = []
          h (x:_) = x
          h [] = n
          t (_:xs) = xs
          t [] = [n]
          m (x:xs) = x:xs
          m [] = [n]

-- | Render the Spreadsheet table rows (CSV, ODS, HTML) for a MultiBalanceReport.
-- Returns the heading rows, 0 or more body rows, and the totals row if enabled.
balanceSubReportAsSpreadsheetParts ::
    AmountFormat -> ReportOpts ->
    [CommoditySymbol] -> MultiBalanceReport ->
    ([[Ods.Cell Ods.NumLines Text]],
     [[Ods.Cell Ods.NumLines Text]],
     [[Ods.Cell Ods.NumLines Text]])
balanceSubReportAsSpreadsheetParts fmt opts@ReportOpts{..}
  allCommodities (PeriodicReport colspans items tr) =
    (allHeaders, concatMap fullRowAsTexts items, totalrows)
  where
    accountCell label = (Ods.defaultCell label) {Ods.cellClass = accountClass}
    hCell cls label = (headerCell label) {Ods.cellClass = cls}
    allHeaders =
      case layout_ of
      LayoutBareWide ->
          [headerWithoutBorders $
              Ods.emptyCell :
              concatMap (Ods.horizontalSpan allCommodities) dateHeaders,
           headers]
      _ -> [headers]
    headers =
      addHeaderBorders $
      hCell accountClass "account" :
      case layout_ of
      LayoutTidy -> map headerCell tidyColumnLabels
      LayoutBareWide -> dateHeaders >> map headerCell allCommodities
      LayoutBare -> headerCell "commodity" : dateHeaders
      _          -> dateHeaders
    -- The headings over columns of figures are marked as such, so that a
    -- stylesheet can align them with the figures below (cf amountClass).
    amountHeader c = c{Ods.cellClass = amountClass Value}
    dateHeaders =
      (if not summary_only_ then map (amountHeader . headerDateSpanCell date2_ period_titles_ balance_base_url_ querystring_) colspans  else [] )++
      [hCell (rowTotalClass Value) "total" | multiBalanceHasTotalsColumn opts] ++
      [hCell (rowAverageClass Value) "average" | average_]
    shownParents = shownParentsOf $ map prrFullName items
    -- An account's link covers the span its row sums: the columns', which
    -- can be wider than the span asked for. When none was asked for, the
    -- register is left unrestricted, as the report is.
    rowquery =
        [t | requestedSpan, t <- dateTerm date2_ $ spansSpan colspans] ++ removeDates querystring_
      where
        requestedSpan = period_ /= PeriodAll || any isDateTerm querystring_
        isDateTerm t = "date:" `T.isPrefixOf` t || "date2:" `T.isPrefixOf` t
    fullRowAsTexts row =
        addRowSpanHeader anchorCell $
        map (map (fmap wbToText)) $
        multiBalanceRowAsCellBuilders fmt opts colspans allCommodities Value
            (dateSpanCellWith lo period_titles_ balance_base_url_ querystring_ acctName) row
      where acctName = prrFullName row
            lo = rowLinkOpts opts colspans shownParents acctName
            anchorCell =
              setAccountAnchorWith lo balance_base_url_ rowquery acctName $
              accountCell $ renderPeriodicAcct opts nbsp row
    totalrows =
      if no_total_
        then []
        else multiBalanceTotalsRows fmt opts (reportLinkOpts opts colspans) []
                allCommodities colspans totalRowHeadingSpreadsheet tr

-- | The totals row of a multi-column report, as one or more rows of
-- spreadsheet cells: the label, then a total per column, each linking
-- to the register of everything in the report's query, plus the given
-- terms, for that column.
multiBalanceTotalsRows ::
    AmountFormat -> ReportOpts -> LinkOpts -> [Text] -> [CommoditySymbol] -> [DateSpan] ->
    Text -> PeriodicReportRow a MixedAmount -> [[Ods.Cell Ods.NumLines Text]]
multiBalanceTotalsRows fmt opts@ReportOpts{..} lo extraquery allCommodities colspans label row =
    addTotalBorders $
    addRowSpanHeader ((Ods.defaultCell label) {Ods.cellClass = accountClass}) $
    map (map (fmap wbToText)) $
    multiBalanceRowAsCellBuilders fmt opts colspans allCommodities Total
        (totalDateSpanCell lo period_titles_ balance_base_url_ extraquery querystring_)
        row

tidyColumnLabels :: [Text]
tidyColumnLabels =
    ["period", "start_date", "end_date", "commodity", "value"]



-- | All commodities appearing in these report rows, sorted.
-- Used as the commodity column order for LayoutBareWide; it must cover
-- every row rendered, see 'setDisplayCommodityBare'.
allCommoditiesFromPeriodicReport ::
    [PeriodicReportRow a MixedAmount] -> [CommoditySymbol]
allCommoditiesFromPeriodicReport =
    S.toAscList . foldMap (foldMap maCommodities . prrAmounts)

-- | Adjust an amount format for bare layouts, which show commodity symbols
-- in their own column(s): hide the symbols and show amounts in the given
-- commodity order.
--
-- Caution: the order list must include every commodity that will be
-- rendered with this format. 'orderedAmounts' renders exactly one amount
-- per listed commodity, so an amount whose commodity is missing from the
-- list is silently dropped (a listed commodity with no amount shows as zero).
-- For LayoutBareWide the list is the whole report's commodities, gathered by
-- 'allCommoditiesFromPeriodicReport' or 'allCommoditiesFromSubreports';
-- for LayoutBare and LayoutTidy it is the row's own commodities.
setDisplayCommodityBare :: [CommoditySymbol] -> AmountFormat -> AmountFormat
setDisplayCommodityBare cs fmt =
    fmt{
        displayCommodity = False,
        displayCommodityOrder = Just cs,
        displayMinWidth = Nothing
    }
