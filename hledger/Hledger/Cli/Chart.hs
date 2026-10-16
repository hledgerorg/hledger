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

import Data.List (find, intercalate, isPrefixOf, partition, sort, sortOn, transpose)
import Data.List.Extra (nubSort)
#if !MIN_VERSION_base(4,20,0)
import Data.List (foldl')
#endif
import Data.Map qualified as M
import Data.Maybe (fromMaybe, isJust, mapMaybe)
import Data.Ord (Down(..))
import Data.Set qualified as S
import Control.Applicative ((<|>))
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
import Hledger.Write.Chart.Svg (chartAsSvg, chartAsSvgWith)
import Hledger.Write.Chart.Text
import Hledger.Write.Csv (printCSV, printTSV)


-- | The chart kinds that --chart accepts. Only "auto" (choose the best chart for the report) so far.
chartKinds :: [String]
chartKinds = ["auto"]

-- | The --chart[=KIND] option, for commands that can show a chart.
chartFlag :: Flag RawOpts
chartFlag = flagOpt "auto" ["chart"] setchart "KIND"
  "show a chart instead of the report table (with txt output), a chart above the table (with html output), or the chart's data (with csv, tsv or json output). svg output always shows a chart. KIND can be: auto (the default)."
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
-- as text (txt), as an SVG image (svg), as the chart's data (csv, tsv, json),
-- or as an SVG image above the report's html, if that is provided (html).
-- Other formats give an error (before the chart is computed).
writeChart :: CliOpts -> Maybe TL.Text -> Chart -> IO ()
writeChart opts mreporthtml chart = do
  render <- case fmt of
    "txt"  -> return $ chartAsTextForOpts opts
    "svg"  -> return $ return . chartAsSvg
    "html" | Just reporthtml <- mreporthtml ->
      -- without the dark variant, since our html is always light
      return $ \c -> return $ chartAsSvgWith False c <> reporthtml
    "csv"  -> return $ return . printCSV . chartAsCsv
    "tsv"  -> return $ return . printTSV . chartAsCsv
    "json" -> return $ return . (<>"\n") . toJsonText
    _ | fmt `elem` outputFormats -> error' $ "--chart does not yet support " ++ fmt ++ " output; try txt, svg, html, csv, tsv or json"  -- PARTIAL:
      | otherwise -> error' $ unsupportedOutputFormatError fmt  -- PARTIAL:
  render chart >>= writeOutputLazyText opts
  where
    fmt = outputFormatFromOpts opts

-- | The most series to show in each section of a compound report chart: as many as can have distinct tints of a type's colour, and "other".
maxSectionSeries :: Int
maxSectionSeries = maxTints + 1

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
multiBalanceReportAsChart :: (AccountName -> Maybe AccountType) -> ReportOpts -> Text -> MultiBalanceReport -> Chart
multiBalanceReportAsChart accttype ropts@ReportOpts{balanceaccum_, accountlistmode_, no_total_, percent_, translations_} title
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
          , pnSeries    = series ++ total
          , pnStackLabels = []
          }
      where
        series = limitSeries maxSeries translations_ mark
          [ (accountLabel accttype $ prrName r, qs) | r <- rows', let qs = map (quantityIn c) (prrAmounts r), any (/= 0) qs ]
        total =
          [ Series (plainLabel $ I18n.tr translations_ "Total") SeriesTotal (if flow then MarkMarker else MarkLine)
              (map (Just . quantityIn c) $ prrAmounts totals) 0
          | length series > 1, not no_total_, not percent_ ]

-- | Chart a single-period balance report, as one bar per account (horizontal, since the accounts are categories).
-- There is one panel per commodity, most-used commodity first;
-- accounts with no amount in a panel's commodity have no value (a gap) there.
-- Unlike stacked charts, all rows are shown, with the report's indentation in tree mode.
balanceReportAsChart :: (AccountName -> Maybe AccountType) -> ReportOpts -> Text -> BalanceReport -> Chart
balanceReportAsChart accttype ReportOpts{translations_} title (items, _total) =
  Chart
    { chTitle  = title
    , chXAxis  = XCategories [ChartLabel full short indent (accttype full) | (full, short, indent, _) <- items]
    , chPanels = map panel $ commoditiesByUse cells
    }
  where
    cells = [ma | (_, _, _, ma) <- items]
    allamts = concatMap amountsRaw cells
    panel c = Panel
      { pnUnit      = unitAmount c allamts
      , pnSeries    = [Series (plainLabel $ I18n.tr translations_ "Balance") SeriesItem MarkBar
                        [ if any ((== c) . acommodity) (amountsRaw ma) then Just (quantityIn c ma) else Nothing
                        | (_, _, _, ma) <- items ] 0]
      , pnStackLabels = []
      }

-- | Chart a compound balance report (balancesheet, incomestatement, cashflow..): its sections' accounts, and the net total.
--
-- Amounts are shown as their contribution to the net total: positive for sections that add to it (eg revenues, assets),
-- negative for sections that subtract from it (eg expenses, liabilities). (The report's tables show both as positive.)
-- So bars above zero increase the net and bars below zero reduce it; eg a refund, which is a negative expense, is drawn above zero.
-- At each period, each section's accounts are stacked (positive amounts above zero, negative ones below),
-- and the sections are side by side (never stacked together).
-- The net total is a mark across them, or a line for end balances (eg balancesheet).
-- A single-period report is drawn the same way, with one period. With -1 (depth 1), each section is a single bar.
-- There is one panel per commodity, most-used commodity first. Each section has at most 'maxSectionSeries' series,
-- the smallest accounts being combined into an "other" series. In tree mode, each account's own amounts are charted.
-- The net total is omitted with -N, with --percent, and when there is only one section.
--
-- The second argument gives each section's account type, if known (eg from the report's query for it); accounts with no
-- type of their own get their section's, for colouring. An account shown as "..." (eg with depth 0) is labelled with its section's title.
compoundBalanceReportAsChart :: (AccountName -> Maybe AccountType) -> [Maybe AccountType] -> ReportOpts -> CompoundPeriodicReport DisplayName MixedAmount -> Chart
compoundBalanceReportAsChart accttype sectiontypes ropts@ReportOpts{balanceaccum_, accountlistmode_, no_total_, percent_, translations_}
  (CompoundPeriodicReport title spans subreports totals) =
  Chart
    { chTitle  = title
    , chXAxis  = XPeriods [(s, if length spans == 1 then "" else reportPeriodName ropts spans s) | s <- spans]  -- the title names a single period
    , chPanels = mapMaybe panel $ commoditiesByUse cells
    }
  where
    flow = balanceaccum_ == PerPeriod
    -- each section's sign (1 if it adds to the net total, -1 if it subtracts from it), and its account rows
    -- (in tree mode, with only their own amounts, so that nothing is counted twice)
    sections = [ ((t, sectype), if increasestotal then 1 else -1, if accountlistmode_ == ALTree then ownAmountRows (prRows r) else prRows r)
               | ((t, r, increasestotal), sectype) <- zip subreports (sectiontypes ++ repeat Nothing) ]
    -- an account's label, with its section's type if it has none, or its section's title if it's "..."
    sectionAccountLabel (t, sectype) r
      | lbFull l == "..." = ChartLabel t t 0 sectype
      | otherwise         = l{lbType = lbType l <|> sectype}
      where l = accountLabel accttype $ prrName r
    nettotals = prrAmounts totals
    showtotal = length subreports > 1 && not no_total_ && not percent_
    -- the table's "Net:" label, without the colon
    netlabel = T.dropWhileEnd (`elem` [':', '\xff1a']) $ I18n.tr translations_ "Net:"
    cells = concat [concatMap prrAmounts rows | (_, _, rows) <- sections] ++ nettotals
    allamts = concatMap amountsRaw cells
    panel c
      | null series = Nothing
      | otherwise = Just Panel
          { pnUnit   = unitAmount c allamts
          , pnSeries = series ++
              [ Series (plainLabel netlabel) SeriesTotal (if flow then MarkMarker else MarkLine) (map (Just . quantityIn c) nettotals) 0
              | showtotal ]
          , pnStackLabels = [t | (t, _, _) <- subreports]
          }
      where
        series = concat
          [ [ s{seStack = k} | s <- limitSeries maxSectionSeries translations_ MarkBar accts ]
          | (k, (section, sign, rows)) <- zip [0 ..] sections
          , let accts = [ (sectionAccountLabel section r, qs) | r <- rows, let qs = map ((* sign) . quantityIn c) (prrAmounts r), any (/= 0) qs ]
          ]

-- | Chart an account register (aregister): the balance after each transaction
-- (or the running total or average, as the report shows), as a line over time.
-- The arguments are the title, the account's name, and a function giving a transaction's date in the register.
-- There is one panel per commodity, most-used commodity first.
accountTransactionsReportAsChart :: (AccountName -> Maybe AccountType) -> Text -> AccountName -> (Transaction -> Day) -> AccountTransactionsReport -> Chart
accountTransactionsReportAsChart accttype title acct txndate items =
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
      , pnSeries    = [Series (ChartLabel acct acct 0 (accttype acct)) SeriesItem MarkLine (map (Just . quantityIn c) bals) 0]
      , pnStackLabels = []
      }

-- | Chart a postings report (register).
-- With a report interval, each account's amount in each period is drawn as stacked bars, with the period's total as a marker
-- (like a multi-period balance report; at most 'maxSeries' series, the smallest combined into "other").
-- Otherwise, the running total (or average) after each posting is drawn as a line over time;
-- and with postings to several accounts (and not --average), each account's own running total (from the report start) is drawn too,
-- in its account type's colour, with the overall running total in ink.
-- There is one panel per commodity, most-used commodity first.
--
-- The second argument gives the accounts' balances before the report period, if the running total includes them
-- (with --historical; see 'postingsReportStartBalances'), so that each account's running total starts from its balance.
postingsReportAsChart :: (AccountName -> Maybe AccountType) -> M.Map AccountName MixedAmount -> ReportOpts -> Text -> PostingsReport -> Chart
postingsReportAsChart accttype startbals ropts@ReportOpts{average_, translations_} title items
  | null periods =
      let totals = [t | (_, _, _, _, t) <- items]
          totalamts = concatMap amountsRaw totals
          totalseries c role = Series ((plainLabel $ I18n.tr translations_ "Total"){lbType = commontype}) role MarkLine (map (Just . quantityIn c) totals) 0
          -- with postings to several accounts (and not --average), each account's running total as a line, and the overall running total
          linespanel c
            | average_ || length (runningTotalAccounts c) < 2 = Panel (unitAmount c totalamts) [totalseries c SeriesItem] []
            | otherwise = Panel (unitAmount c totalamts) (accountRunningTotals c ++ [totalseries c SeriesTotal]) []
      in Chart
        { chTitle  = title
        , chXAxis  = XDates [postingDateOrDate2 (whichDate ropts) p | p <- postings]
        , chPanels = map linespanel $ commoditiesByUse totals
        }
  | otherwise =
      Chart
        { chTitle  = title
        , chXAxis  = XPeriods [(s, reportPeriodName ropts{balanceaccum_ = PerPeriod} spans s) | s <- spans]
        , chPanels = mapMaybe panel $ commoditiesByUse cells
        }
  where
    postings = [p | (_, _, _, p, _) <- items]
    -- Running totals (from the report start) of the postings' accounts in one commodity, as lines:
    -- for at most 'maxSeries' accounts, the largest by total absolute posting amount (in name order), and the rest combined as "other".
    -- (Only these are computed, since there can be many accounts and postings.)
    -- Each account starts from its balance before the report period, if any.
    accountRunningTotals c =
      [ Series (ChartLabel a a 0 (accttype a)) SeriesItem MarkLine (runningTotal (== a)) 0 | a <- kept ]
      ++ [ Series (plainLabel $ I18n.trn translations_ n "other ({n} account)" "other ({n} accounts)") SeriesOther MarkLine
             (runningTotal (`S.notMember` keptset)) 0
         | let n = length accts - length kept, n > 0 ]
      where
        sizes = accountSizes c
        accts = M.keys sizes
        kept | length accts <= maxSeries = accts
             | otherwise = sort $ take (maxSeries - 1) $ map fst $ sortOn (Down . snd) $ M.toList sizes
        keptset = S.fromList kept
        runningTotal match =
          map Just $ drop 1 $ scanl (+) (sum [startIn c a | a <- M.keys startbals, match a])
            [if match (paccount p) then quantityIn c (pamount p) else 0 | p <- postings]
    -- the accounts with postings, or a starting balance, in this commodity, with their total absolute amount (for ranking)
    accountSizes c = M.unionWith (+)
      (M.fromListWith (+) [(paccount p, abs $ quantityIn c $ pamount p) | p <- postings])
      (M.fromList [(a, abs q) | a <- M.keys startbals, let q = startIn c a, q /= 0])
    runningTotalAccounts c = M.keys $ accountSizes c
    startIn c a = maybe 0 (quantityIn c) $ M.lookup a startbals
    -- the main account type of all the postings' accounts, if they have one
    commontype = case nubSort [mainAccountType t | (_, _, _, p, _) <- items, Just t <- [accttype $ paccount p]] of
      [t] | all (isJust . accttype . paccount) [p | (_, _, _, p, _) <- items] -> Just t
      _ -> Nothing
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
      | otherwise = Just Panel{pnUnit = unitAmount c allamts, pnSeries = series ++ total, pnStackLabels = []}
      where
        series = limitSeries maxSeries translations_ MarkBar
          [ (ChartLabel a a 0 (accttype a), qs) | (a, amts) <- rows, let qs = map (quantityIn c) amts, any (/= 0) qs ]
        total =
          [ Series (plainLabel $ I18n.tr translations_ "Total") SeriesTotal MarkMarker
              (map (Just . sum) $ transpose [map (quantityIn c) amts | (_, amts) <- rows]) 0
          | length series > 1 ]

-- Helpers

-- | Keep at most this many series (in stack 0). If there are more, keep the largest (by total absolute value) in their original order,
-- and combine the rest into a final "other" series.
limitSeries :: Int -> I18n.Translations -> Mark -> [(ChartLabel, [Quantity])] -> [Series]
limitSeries maxn t mark items
  | length items <= maxn = map item items
  | otherwise = map (item . snd) kept ++ [other]
  where
    item (l, qs) = Series l SeriesItem mark (map Just qs) 0
    numbered = zip [0 :: Int ..] items
    largest = S.fromList $ take (maxn - 1) $ map fst $ sortOn (Down . sum . map abs . snd . snd) numbered
    (kept, rest) = partition ((`S.member` largest) . fst) numbered
    n = length rest
    other = Series
      (plainLabel $ I18n.trn t n "other ({n} account)" "other ({n} accounts)")
      SeriesOther mark
      (map (Just . sum) $ transpose $ map (snd . snd) rest)
      0

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

accountLabel :: (AccountName -> Maybe AccountType) -> DisplayName -> ChartLabel
accountLabel accttype DisplayName{displayFull, displayName, displayIndent} = ChartLabel displayFull displayName displayIndent (accttype displayFull)

plainLabel :: Text -> ChartLabel
plainLabel t = ChartLabel t t 0 Nothing
