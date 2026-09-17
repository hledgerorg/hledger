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

import Hledger.Utils.I18n (trc)
import Hledger
import Hledger.Cli.Anchor (setAccountAnchor, dateSpanCell, headerDateSpanCell, renderPeriodHeading)
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
    opts@ReportOpts{summary_only_, average_}
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
      [trc (translations_ opts) "column heading" "Commodity" | layout_ opts == LayoutBare]
      ++
      case layout_ opts of
          LayoutBareWide ->
              liftA2 (\s c -> T.concat [s, " (", c, ")"])
                  spanNames allCommodities
          _ -> spanNames
    spanNames =
        (guard (not summary_only_) >>
            map (reportPeriodName opts spans) spans)
        ++ ["  " <> trc (translations_ opts) "column heading" "Total" | multiBalanceHasTotalsColumn opts]
        ++ [trc (translations_ opts) "column heading" "Average" | average_]
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
      LayoutWide width -> [fmap (cellFromMixedAmount bopts{displayMaxWidth=width}) clsamts]
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
    clsamts = (if not summary_only_ then classified else []) ++
                [(rowTotalClass rc, rowtot) |
                    multiBalanceHasTotalsColumn ropts && not (null as)] ++
                [(rowAverageClass rc, rowavg) | average_ && not (null as)]
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
    (allHeaders, concatMap fullRowAsTexts items, addTotalBorders totalrows)
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
      (if not summary_only_ then map (amountHeader . headerDateSpanCell period_titles_ balance_base_url_ querystring_) colspans  else [] )++
      [hCell (rowTotalClass Value) "total" | multiBalanceHasTotalsColumn opts] ++
      [hCell (rowAverageClass Value) "average" | average_]
    fullRowAsTexts row =
        addRowSpanHeader anchorCell $
        rowAsText Value (dateSpanCell period_titles_ balance_base_url_ querystring_ acctName) row
      where acctName = prrFullName row
            anchorCell =
              setAccountAnchor balance_base_url_ querystring_ acctName $
              accountCell $ renderPeriodicAcct opts nbsp row
    totalrows =
      if no_total_
        then []
        else addRowSpanHeader (accountCell totalRowHeadingSpreadsheet) $
                rowAsText Total (simpleDateSpanCell period_titles_) tr
    rowAsText rc dsCell =
        map (map (fmap wbToText)) .
        multiBalanceRowAsCellBuilders fmt opts colspans allCommodities rc dsCell

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
