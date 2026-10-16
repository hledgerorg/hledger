{-|
Turning reports into charts ("Hledger.Write.Chart"), and the --chart option.

Each adapter here chooses a useful default chart for its report,
so that charts just work without configuration (see doc/PLAN-charts.md, "Smart defaults").
-}

{-# LANGUAGE CPP #-}
{-# LANGUAGE OverloadedStrings #-}

module Hledger.Cli.Chart (
  chartFlag,
  chartWidthFlag,
  chartRequested,
  chartAsTextForOpts,
  writeChart,
  multiBalanceReportAsChart,
  balanceReportAsChart,
  compoundBalanceReportAsChart,
  accountTransactionsReportAsChart,
  postingsReportAsChart,
) where

import Data.List (find, intercalate, isPrefixOf, partition, sortOn, transpose)
import Data.List.Extra (nubSort)
#if !MIN_VERSION_base(4,20,0)
import Data.List (foldl')
#endif
import Data.Map qualified as M
import Data.Maybe (fromMaybe, isJust, mapMaybe)
import Data.Ord (Down(..))
import Data.Set qualified as S
import Control.Monad (when)
import Data.Char (toUpper)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Lazy qualified as TL
import Data.Time (Day)
import GHC.IO.Encoding (getLocaleEncoding, textEncodingName)
import Safe (readMay)
import System.Console.CmdArgs.Explicit (Flag, flagOpt, flagReq)
import Text.Printf (printf)

import Hledger
import Hledger.Cli.CliOptions (CliOpts(..), outputFormatFromOpts, outputFormats)
import Hledger.Cli.Utils (unsupportedOutputFormatError, writeOutputLazyText)
import Hledger.Utils.I18n qualified as I18n
import Hledger.Write.Chart
import Hledger.Write.Chart.Svg (chartAsSvg)
import Hledger.Write.Chart.Text
import Hledger.Write.Csv (printCSV, printTSV)


-- | The chart kinds that --chart accepts. Only "auto" (choose the best chart for the report) so far.
chartKinds :: [String]
chartKinds = ["auto"]

-- | The --chart[=KIND] option, for commands that can show a chart.
chartFlag :: Flag RawOpts
chartFlag = flagOpt "auto" ["chart"] setchart "KIND"
  "show a chart instead of the report table (with txt output), or the chart's data (with csv, tsv or json output). svg output always shows a chart. KIND can be: auto (the default)."
  where
    setchart s opts
      | s `elem` chartKinds = Right $ setopt "chart" s opts
      | otherwise = Left $ "--chart's KIND should be one of: " ++ intercalate ", " chartKinds

-- | Was a chart requested, with --chart or an output format that can only show charts (svg) ?
chartRequested :: CliOpts -> Bool
chartRequested opts = isJust (maybestringopt "chart" $ rawopts_ opts) || outputFormatFromOpts opts == "svg"

-- | The --width option, for commands that can show a chart.
chartWidthFlag :: Flag RawOpts
chartWidthFlag = flagReq ["width","w"] setwidth "N"
  "with --chart: draw the chart N characters wide (default: the terminal width)"
  where
    setwidth s opts = case readMay s :: Maybe Int of
      Just n | n > 0 -> Right $ setopt "width" s opts
      _              -> Left "--width should be a positive whole number"

-- | Draw a chart as text, as the command line options say:
-- --width characters wide or the terminal width, with ANSI colour if enabled,
-- and with unicode block characters if the system's text encoding is UTF-8 (otherwise ASCII).
-- Also warns if the chart has many panels (one per commodity).
chartAsTextForOpts :: CliOpts -> Chart -> IO TL.Text
chartAsTextForOpts CliOpts{width_, available_width_, reportspec_} chart = do
  unicode <- ("UTF-8" `isPrefixOf`) . map toUpper . textEncodingName <$> getLocaleEncoding
  let npanels = length $ chPanels chart
  when (npanels > maxPanels) $ warnIO $ printf
    ("this chart has %d panels, one per commodity. To show fewer, convert to one commodity (eg -X USD)\n"
    <> "or select some (eg cur:USD).")
    npanels
  return $ styledLinesAsText (color_ $ _rsReportOpts reportspec_) $ chartAsStyledLines (TextChartOpts width unicode) chart
  where
    width = fromMaybe available_width_ (width_ >>= readMay)
    maxPanels = 8 :: Int

-- | Write a chart in the output format and to the destination selected by the command line options:
-- as text (txt), as an SVG image (svg), or as the chart's data (csv, tsv, json).
-- Other formats give an error (before the chart is computed).
writeChart :: CliOpts -> Chart -> IO ()
writeChart opts chart = do
  render <- case fmt of
    "txt"  -> return $ chartAsTextForOpts opts
    "svg"  -> return $ return . chartAsSvg
    "csv"  -> return $ return . printCSV . chartAsCsv
    "tsv"  -> return $ return . printTSV . chartAsCsv
    "json" -> return $ return . (<>"\n") . toJsonText
    _ | fmt `elem` outputFormats -> error' $ "--chart does not yet support " ++ fmt ++ " output; try txt, svg, csv, tsv or json"  -- PARTIAL:
      | otherwise -> error' $ unsupportedOutputFormatError fmt  -- PARTIAL:
  render chart >>= writeOutputLazyText opts
  where
    fmt = outputFormatFromOpts opts

-- | The most series to show in one panel. Beyond this, the smallest series are combined into one "other" series.
maxSeries :: Int
maxSeries = 8

-- | Chart a multi-period balance report.
--
-- Period changes (flows) are drawn as stacked bars, with the net total as a marker;
-- end balances (stocks, with --cumulative or --historical) as lines, with the total as a line.
-- There is one panel per commodity, most-used commodity first.
-- In tree mode, each account's own amounts are charted, excluding its displayed subaccounts', so nothing is counted twice.
-- The total is omitted with -N, with --percent (where it is always 100), and when there is only one series.
multiBalanceReportAsChart :: ReportOpts -> Text -> MultiBalanceReport -> Chart
multiBalanceReportAsChart ropts@ReportOpts{balanceaccum_, accountlistmode_, no_total_, percent_, translations_} title
  (PeriodicReport spans rows totals) =
  Chart
    { chTitle  = title
    , chXAxis  = XPeriods [(s, reportPeriodName ropts spans s) | s <- spans]
    , chPanels = mapMaybe panel $ commoditiesByUse cells
    }
  where
    flow = balanceaccum_ == PerPeriod
    mark = if flow then MarkBar else MarkLine
    rows' = if accountlistmode_ == ALTree then ownAmountRows rows else rows
    cells = concatMap prrAmounts rows
    allamts = concatMap amountsRaw cells
    panel c
      | null series = Nothing
      | otherwise = Just Panel
          { pnUnit      = unitAmount c allamts
          , pnBarLayout = Stacked
          , pnSeries    = series ++ total
          }
      where
        series = limitSeries translations_ mark
          [ (accountLabel $ prrName r, qs) | r <- rows', let qs = map (quantityIn c) (prrAmounts r), any (/= 0) qs ]
        total =
          [ Series (plainLabel $ I18n.tr translations_ "Total") SeriesTotal (if flow then MarkMarker else MarkLine)
              (map (Just . quantityIn c) $ prrAmounts totals)
          | length series > 1, not no_total_, not percent_ ]

-- | Chart a single-period balance report, as one bar per account (horizontal, since the accounts are categories).
-- There is one panel per commodity, most-used commodity first;
-- accounts with no amount in a panel's commodity have no value (a gap) there.
-- Unlike stacked charts, all rows are shown, with the report's indentation in tree mode.
balanceReportAsChart :: ReportOpts -> Text -> BalanceReport -> Chart
balanceReportAsChart ReportOpts{translations_} title (items, _total) =
  Chart
    { chTitle  = title
    , chXAxis  = XCategories [ChartLabel full short indent | (full, short, indent, _) <- items]
    , chPanels = map panel $ commoditiesByUse cells
    }
  where
    cells = [ma | (_, _, _, ma) <- items]
    allamts = concatMap amountsRaw cells
    panel c = Panel
      { pnUnit      = unitAmount c allamts
      , pnBarLayout = Grouped
      , pnSeries    = [Series (plainLabel $ I18n.tr translations_ "Balance") SeriesItem MarkBar
                        [ if any ((== c) . acommodity) (amountsRaw ma) then Just (quantityIn c ma) else Nothing
                        | (_, _, _, ma) <- items ]]
      }

-- | Chart a compound balance report (balancesheet, incomestatement, cashflow..), showing the sections' totals and the net total.
--
-- Section amounts are normally positive in these reports (eg both revenues and expenses), so they are not stacked:
-- period changes (flows) are drawn as side-by-side bars, with the net total as a marker;
-- end balances (stocks, eg balancesheet) as lines, with the net total as a line.
-- A single-period report is drawn as one bar per section, and one for the net total.
-- There is one panel per commodity, most-used commodity first.
-- The net total is omitted with -N, with --percent, and when there is only one section.
compoundBalanceReportAsChart :: ReportOpts -> CompoundPeriodicReport DisplayName MixedAmount -> Chart
compoundBalanceReportAsChart ropts@ReportOpts{balanceaccum_, no_total_, percent_, translations_}
  (CompoundPeriodicReport title spans subreports totals) =
  Chart
    { chTitle  = title
    , chXAxis  = if singleperiod
                 then XCategories $ map (plainLabel . fst) sections ++ [plainLabel netlabel | showtotal]
                 else XPeriods [(s, reportPeriodName ropts spans s) | s <- spans]
    , chPanels = mapMaybe panel $ commoditiesByUse cells
    }
  where
    singleperiod = length spans == 1
    flow = balanceaccum_ == PerPeriod
    sections = [(t, prrAmounts $ prTotals r) | (t, r, _) <- subreports]
    nettotals = prrAmounts totals
    showtotal = length subreports > 1 && not no_total_ && not percent_
    -- the table's "Net:" label, without the colon
    netlabel = T.dropWhileEnd (`elem` [':', '\xff1a']) $ I18n.tr translations_ "Net:"
    cells = concatMap snd sections ++ nettotals
    allamts = concatMap amountsRaw cells
    panel c
      | singleperiod = Just $ mkpanel
          [Series (plainLabel $ I18n.tr translations_ "Balance") SeriesItem MarkBar
            [ if any ((== c) . acommodity) (concatMap amountsRaw amts) then Just (sum $ map (quantityIn c) amts) else Nothing
            | amts <- map snd sections ++ [nettotals | showtotal] ]]
      | null series = Nothing
      | otherwise = Just $ mkpanel $ series ++
          [ Series (plainLabel netlabel) SeriesTotal (if flow then MarkMarker else MarkLine) (map (Just . quantityIn c) nettotals)
          | showtotal ]
      where
        mkpanel ss = Panel{pnUnit = unitAmount c allamts, pnBarLayout = Grouped, pnSeries = ss}
        series =
          [ Series (plainLabel t) SeriesItem (if flow then MarkBar else MarkLine) qs
          | (t, amts) <- sections, let qs = map (Just . quantityIn c) amts, any (maybe False (/= 0)) qs ]

-- | Chart an account register (aregister): the balance after each transaction
-- (or the running total or average, as the report shows), as a line over time.
-- The arguments are the title, the account's name, and a function giving a transaction's date in the register.
-- There is one panel per commodity, most-used commodity first.
accountTransactionsReportAsChart :: Text -> Text -> (Transaction -> Day) -> AccountTransactionsReport -> Chart
accountTransactionsReportAsChart title acct txndate items =
  Chart
    { chTitle  = title
    , chXAxis  = XDates [txndate t | (t, _, _, _, _, _) <- items]
    , chPanels = map panel $ commoditiesByUse bals
    }
  where
    bals = [b | (_, _, _, _, _, b) <- items]
    allamts = concatMap amountsRaw bals
    panel c = Panel
      { pnUnit      = unitAmount c allamts
      , pnBarLayout = Grouped
      , pnSeries    = [Series (plainLabel acct) SeriesItem MarkLine (map (Just . quantityIn c) bals)]
      }

-- | Chart a postings report (register).
-- With a report interval, each account's amount in each period is drawn as stacked bars, with the period's total as a marker
-- (like a multi-period balance report; at most 'maxSeries' series, the smallest combined into "other").
-- Otherwise, the running total (or average) after each posting is drawn as a line over time.
-- There is one panel per commodity, most-used commodity first.
postingsReportAsChart :: ReportOpts -> Text -> PostingsReport -> Chart
postingsReportAsChart ropts@ReportOpts{translations_} title items
  | null periods =
      let totals = [t | (_, _, _, _, t) <- items]
          totalamts = concatMap amountsRaw totals
      in Chart
        { chTitle  = title
        , chXAxis  = XDates [postingDateOrDate2 (whichDate ropts) p | (_, _, _, p, _) <- items]
        , chPanels =
            [ Panel (unitAmount c totalamts) Grouped
                [Series (plainLabel $ I18n.tr translations_ "Total") SeriesItem MarkLine (map (Just . quantityIn c) totals)]
            | c <- commoditiesByUse totals ]
        }
  | otherwise =
      Chart
        { chTitle  = title
        , chXAxis  = XPeriods [(s, reportPeriodName ropts{balanceaccum_ = PerPeriod} spans s) | s <- spans]
        , chPanels = mapMaybe panel $ commoditiesByUse cells
        }
  where
    periods = nubSort [prd | (_, Just prd, _, _, _) <- items]
    spans = map periodAsDateSpan periods
    -- each account's amount in each period
    acctamts :: M.Map AccountName (M.Map Period MixedAmount)
    acctamts = M.fromListWith (M.unionWith (<>)) [(paccount p, M.singleton prd (pamount p)) | (_, Just prd, _, p, _) <- items]
    rows = [(a, [M.findWithDefault nullmixedamt prd m | prd <- periods]) | (a, m) <- M.toList acctamts]
    cells = concatMap snd rows
    allamts = concatMap amountsRaw cells
    panel c
      | null series = Nothing
      | otherwise = Just Panel{pnUnit = unitAmount c allamts, pnBarLayout = Stacked, pnSeries = series ++ total}
      where
        series = limitSeries translations_ MarkBar
          [ (plainLabel a, qs) | (a, amts) <- rows, let qs = map (quantityIn c) amts, any (/= 0) qs ]
        total =
          [ Series (plainLabel $ I18n.tr translations_ "Total") SeriesTotal MarkMarker
              (map (Just . sum) $ transpose [map (quantityIn c) amts | (_, amts) <- rows])
          | length series > 1 ]

-- Helpers

-- | Keep at most 'maxSeries' series. If there are more, keep the largest (by total absolute value) in their original order,
-- and combine the rest into a final "other" series.
limitSeries :: I18n.Translations -> Mark -> [(ChartLabel, [Quantity])] -> [Series]
limitSeries t mark items
  | length items <= maxSeries = map item items
  | otherwise = map (item . snd) kept ++ [other]
  where
    item (l, qs) = Series l SeriesItem mark (map Just qs)
    numbered = zip [0 :: Int ..] items
    largest = S.fromList $ take (maxSeries - 1) $ map fst $ sortOn (Down . sum . map abs . snd . snd) numbered
    (kept, rest) = partition ((`S.member` largest) . fst) numbered
    n = length rest
    other = Series
      (plainLabel $ I18n.trn t n "other ({n} account)" "other ({n} accounts)")
      SeriesOther mark
      (map (Just . sum) $ transpose $ map (snd . snd) rest)

-- | In tree mode, a parent account's row includes the amounts of its displayed subaccounts' rows.
-- Subtract those, leaving each row with only its own amounts.
ownAmountRows :: [MultiBalanceReportRow] -> [MultiBalanceReportRow]
ownAmountRows rows = map own rows
  where
    fullname = displayFull . prrName
    names = S.fromList $ map fullname rows
    displayedParent r = find (`S.member` names) $ parentAccountNames $ fullname r
    children = M.fromListWith (++) [(p, [r]) | r <- rows, Just p <- [displayedParent r]]
    own r = case M.lookup (fullname r) children of
      Nothing -> r
      Just cs -> r{prrAmounts = foldl' (zipWith maMinus) (prrAmounts r) (map prrAmounts cs)}

-- | The commodities with non-zero quantities in these report cells,
-- those in the most cells first, then alphabetically.
-- (Cells are counted, not amounts, since a cell can hold several amounts of one commodity with different costs.)
commoditiesByUse :: [MixedAmount] -> [CommoditySymbol]
commoditiesByUse cells =
  map fst $ sortOn (\(c, n) -> (Down n, c)) $ M.toList $
  M.fromListWith (+) [(c, 1 :: Int) | ma <- cells, c <- S.toList $ maCommodities ma, quantityIn c ma /= 0]

-- | A unit for values in this commodity: an amount of it from the list (for its display style),
-- with zero quantity and no cost.
unitAmount :: CommoditySymbol -> [Amount] -> Amount
unitAmount c as = case find ((== c) . acommodity) as of
  Just a  -> a{aquantity = 0, acost = Nothing, acostbasis = Nothing}
  Nothing -> nullamt{acommodity = c}

-- | The total quantity of this commodity in a mixed amount, ignoring costs.
quantityIn :: CommoditySymbol -> MixedAmount -> Quantity
quantityIn c ma = sum [aquantity a | a <- amountsRaw ma, acommodity a == c]

accountLabel :: DisplayName -> ChartLabel
accountLabel DisplayName{displayFull, displayName, displayIndent} = ChartLabel displayFull displayName displayIndent

plainLabel :: Text -> ChartLabel
plainLabel t = ChartLabel t t 0
