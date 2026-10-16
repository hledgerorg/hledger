{-|
Turning reports into charts ("Hledger.Write.Chart"), and the --chart option.

Each adapter here chooses a useful default chart for its report,
so that charts just work without configuration (see doc/PLAN-charts.md, "Smart defaults").
-}

{-# LANGUAGE CPP #-}
{-# LANGUAGE OverloadedStrings #-}

module Hledger.Cli.Chart (
  chartFlag,
  chartRequested,
  multiBalanceReportAsChart,
  balanceReportAsChart,
) where

import Data.List (find, intercalate, partition, sortOn, transpose)
#if !MIN_VERSION_base(4,20,0)
import Data.List (foldl')
#endif
import Data.Map qualified as M
import Data.Maybe (isJust, mapMaybe)
import Data.Ord (Down(..))
import Data.Set qualified as S
import Data.Text (Text)
import System.Console.CmdArgs.Explicit (Flag, flagOpt)

import Hledger
import Hledger.Cli.CliOptions (CliOpts(..))
import Hledger.Utils.I18n qualified as I18n
import Hledger.Write.Chart


-- | The chart kinds that --chart accepts. Only "auto" (choose the best chart for the report) so far.
chartKinds :: [String]
chartKinds = ["auto"]

-- | The --chart[=KIND] option, for commands that can show a chart.
chartFlag :: Flag RawOpts
chartFlag = flagOpt "auto" ["chart"] setchart "KIND"
  "show a chart instead of the report table (with txt output), or the chart's data (with csv, tsv or json output). KIND can be: auto (the default)."
  where
    setchart s opts
      | s `elem` chartKinds = Right $ setopt "chart" s opts
      | otherwise = Left $ "--chart's KIND should be one of: " ++ intercalate ", " chartKinds

-- | Was a chart requested, with --chart ?
chartRequested :: CliOpts -> Bool
chartRequested = isJust . maybestringopt "chart" . rawopts_

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
