{-|

The @holdings@ command shows a report of investment holdings (lot-tracked assets).

Work in progress; see doc/SPEC-holdings.md.
Currently it shows the Date, Age, Units, Unit/Avg cost, Price, Cost,
Value, Weight, UGain, UGain%, RGain and XIRR columns, one row per
account (or lot subaccount, with --lots) and held commodity. In tree
mode, positions are grouped into account sections: a heading row per
account showing its subtree's totals, its positions beneath it named
by their commodity, and with --lots each position's lots beneath it.

The report computation (holdingsReport) is exported for reuse by other
UIs; the holdings command renders it in the usual output formats.

-}

{-# LANGUAGE MultiWayIf #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TemplateHaskell #-}

module Hledger.Cli.Commands.Holdings (
  holdingsmode
 ,holdings
 ,HoldingsReport(..)
 ,HoldingsReportOpts(..)
 ,HoldingsTotals(..)
 ,HoldingsLine(..)
 ,Holding(..)
 ,holdingsReport
 ,holdingsReportAsChart
 ,holdingsReportsAsChart
 ,showage
 ,showPercentWith
) where

import Control.Applicative ((<|>))
import Control.Monad (guard)
import Data.Aeson (Value, object, (.=))
import Data.Decimal (roundTo)
import Data.Default (def)
import Data.List.Extra (find, intercalate, intersperse, minimumBy, nubSort, nubSortOn, sortOn, transpose)
import Data.Map.Strict qualified as M
import Data.Set qualified as S
import Data.Maybe (fromMaybe, isJust, mapMaybe)
import Data.Ord (Down(..), comparing)
import Data.Text qualified as T
import Data.Text.Lazy qualified as TL
import Data.Time.Calendar (Day, addDays, diffDays)
import System.Console.CmdArgs.Explicit (flagNone, flagReq)
import Safe (headMay)
import Text.Printf (printf)

import Hledger
import Hledger.Cli.Chart (chartFlag, chartRequested, chartWidthFlag, writeChart)
import Hledger.Cli.CliOptions
import Hledger.Cli.Commands.Balance.Internal (addTotalBorders)
import Hledger.Cli.Commands.Print (roundFromRawOpts)
import Hledger.Cli.Utils (unsupportedOutputFormatError, warnIfLargeMultiPeriodReport, writeOutputLazyText)
import Hledger.Utils.I18n qualified as I18n
import Hledger.Write.Chart (Chart(..), ChartLabel(..), Mark(..), Panel(..), BarLayout(..), Series(..), SeriesRole(..), XAxis(..))
import Hledger.Write.Csv (CSV, printCSV, printTSV)
import Hledger.Write.Html (Html, htmlAsLazyText, titledTableHtml, toHtml)
import Hledger.Write.Ods (printFods)
import Hledger.Write.Spreadsheet (addHeaderBorders, headerCell)
import Hledger.Write.Spreadsheet qualified as Ods
import Numeric.RootFinding (RiddersParam(..), Root(..), Tolerance(..), ridders)
import System.IO qualified as IO
import Text.Blaze.Html5 ((!))
import Text.Blaze.Html5 qualified as H
import Text.Blaze.Html5.Attributes qualified as A
import Text.Tabular.AsciiWide

-- | Command line options for this command.
holdingsmode = hledgerCommandMode
  $(embedFileRelative "Hledger/Cli/Commands/Holdings.txt")
  (flattreeflags True ++
   [flagNone ["no-elide"] (setboolopt "no-elide") "in tree mode, don't squash boring parent accounts; in list mode, also show parent accounts (usually zero, hidden without -E)"
   ,flagNone ["full-names"] (setboolopt "full-names") "in tree mode, show full account names instead of indented leaf names"
   ,flagReq  ["drop"] (\s opts -> Right $ setopt "drop" s opts) "N" "omit N leading account name parts; in tree mode, remove the first N levels"
   ,flagNone ["sort-amount","S"] (setboolopt "sort-amount") "sort by value (or cost) instead of account name, largest first"
   ,flagNone ["no-total","N"] (setboolopt "no-total") "omit the final total row"
   ,flagReq ["round"] (\s opts -> Right $ setopt "round" s opts) "TYPE" $
     intercalate "\n"
     ["how much rounding or padding should be done when displaying amounts ?"
     ,"none - show original decimal digits"
     ,"soft - just add or remove decimal zeros"
     ,"       to match precision"
     ,"hard - round amounts to precision (default)"
     ,"all  - also round cost amounts to precision"
     ]
   ,chartFlag
   ,chartWidthFlag
   ,outputFormatFlag ["txt","csv","tsv","html","fods","json","svg"]
   ,outputFileFlag
   ,outputViewFlag])
  cligeneralflagsgroups1
  hiddenflags
  ([], Just $ argsFlag "[QUERY]")

-- | One holding: one commodity held in one displayed account (or lot
-- subaccount), with its report attributes. Each holding is one row of
-- the text/html/fods table and one record of the csv/tsv/json output.
-- A commodity fully disposed from a displayed account also gets a
-- holding, with zero units, so its realised gain stays visible.
data Holding = Holding {
   hAccount   :: AccountName
  ,hCommodity :: CommoditySymbol
  ,hDate      :: Maybe Day        -- ^ acquisition date, when the lots share one
  ,hAge       :: Maybe Integer    -- ^ days held at the report date
  ,hUnits     :: Amount           -- ^ units held, styled
  ,hUnitCost  :: Maybe Amount     -- ^ unit or average cost
  ,hPrice     :: [Amount]         -- ^ market price(s) at the valuation date (several if the lots' value commodities differ)
  ,hCost      :: [Amount]         -- ^ total cost basis (multiple amounts if cost commodities are mixed)
  ,hValue     :: [Amount]         -- ^ market value, when all lots are priced (multiple amounts if value commodities are mixed)
  ,hWeight    :: Maybe Quantity   -- ^ percentage of the portfolio's value, unrounded
  ,hUgain     :: [Amount]         -- ^ unrealised gain, when values and costs cover the same commodities
  ,hUgainPct  :: Maybe Quantity   -- ^ unrealised gain percent, unrounded
  ,hRgain     :: [Amount]         -- ^ realised gain, from disposals so far
  ,hXirr      :: Maybe Double     -- ^ annualised internal rate of return percent
  }

-- Machine-readable fields for the csv/tsv output: full account name, age
-- in days, bare units and rounded gain percent numbers, machine-format
-- amounts (no digit group marks).
holdingCsv :: Holding -> [T.Text]
holdingCsv h =
  [hAccount h
  ,hCommodity h
  ,maybe "" showDate (hDate h)
  ,maybe "" (T.pack . show) (hAge h)
  ,T.pack $ showAmountWith machineFmt{displayCommodity=False} (hUnits h)
  ,maybe "" showamt (hUnitCost h)
  ,showamts (hPrice h)
  ,T.pack $ showMixedAmountWith machineFmt $ mixed $ hCost h
  ,showamts (hValue h)
  ,maybe "" (T.pack . show . roundTo 1) (hWeight h)
  ,showamts (hUgain h)
  ,maybe "" (T.pack . show . roundTo 1) (hUgainPct h)
  ,showamts (hRgain h)
  ,maybe "" (T.pack . printf "%.1f") (hXirr h)
  ]
  where
    showamt  = T.pack . showAmountWith machineFmt
    showamts [] = ""
    showamts as = T.pack $ showMixedAmountWith machineFmt $ mixed as

-- | Machine-readable fields for a period's totals, in the csv/tsv output with a report interval: like 'holdingCsv'.
periodTotalsCsv :: Day -> (M.Map CommoditySymbol AmountStyle, HoldingsTotals) -> [T.Text]
periodTotalsCsv d (_, tot) =
  [showDate d
  ,showamts (htCost tot)
  ,maybe "" showamts (htValue tot)
  ,maybe "" showamts (htUgain tot)
  ,maybe "" (T.pack . show . roundTo 1) (htUgainPct tot)
  ,showamts (htRgain tot)
  ,maybe "" (T.pack . printf "%.1f") (htXirr tot)
  ]
  where
    showamts [] = ""
    showamts as = T.pack $ showMixedAmountWith machineFmt $ mixed as

-- | A period's totals, in the json output with a report interval: like 'holdingJson'.
periodTotalsJson :: Day -> (M.Map CommoditySymbol AmountStyle, HoldingsTotals) -> Value
periodTotalsJson d (_, tot) = object
  ["date"       .= d
  ,"totalcost"  .= showamts (htCost tot)
  ,"totalvalue" .= (showamts <$> htValue tot)
  ,"ugain"      .= (showamts <$> htUgain tot)
  ,"ugainpct"   .= (roundTo 1 <$> htUgainPct tot)
  ,"rgain"      .= mshowamts (htRgain tot)
  ,"xirr"       .= htXirr tot
  ]
  where
    showamts = T.pack . showMixedAmountWith machineFmt . mixed
    mshowamts as = case as of [] -> Nothing; _ -> Just $ showamts as

holdingJson :: Holding -> Value
holdingJson h = object
  ["account"   .= hAccount h
  ,"commodity" .= hCommodity h
  ,"date"      .= hDate h
  ,"age"       .= hAge h
  ,"units"     .= aquantity (hUnits h)
  ,"unitcost"   .= (showamt <$> hUnitCost h)
  ,"unitprice"  .= mshowamts (hPrice h)
  ,"totalcost"  .= showamts (hCost h)
  ,"totalvalue" .= mshowamts (hValue h)
  ,"weight"    .= (roundTo 1 <$> hWeight h)
  ,"ugain"     .= mshowamts (hUgain h)
  ,"ugainpct"  .= (roundTo 1 <$> hUgainPct h)
  ,"rgain"     .= mshowamts (hRgain h)
  ,"xirr"      .= hXirr h
  ]
  where
    showamt  = T.pack . showAmountWith machineFmt
    showamts = T.pack . showMixedAmountWith machineFmt . mixed
    mshowamts as = case as of [] -> Nothing; _ -> Just $ showamts as

-- | Show an age in days compactly: in days, or if a year or more,
-- in years with one decimal digit (approximating years as 365 days):
-- eg 44d, 1.1y.
showage :: Integer -> T.Text
showage d
  | d >= 365  = T.pack (show (roundTo 1 (fromIntegral d / 365))) <> "y"
  | otherwise = T.pack (show d) <> "d"

-- | Show a percentage (eg for the Weight, UGain% and XIRR columns) as a
-- "%" commodity amount, using the given styles' display style for the
-- "%" commodity (eg from a commodity directive or -c, or
-- holdingsReport's default): eg 64.3%.
showPercentWith :: M.Map CommoditySymbol AmountStyle -> Quantity -> T.Text
showPercentWith styles p =
  T.pack $ showAmountWith noCostFmt{displayZeroCommodity=True} $
  styleAmounts styles nullamt{acommodity="%", aquantity=p}

-- | Options for the holdings report, besides the usual ReportSpec.
data HoldingsReportOpts = HoldingsReportOpts {
   hroLots     :: Bool      -- ^ show each lot (one row per lot subaccount) rather than aggregating them per account, like --lots
  ,hroRounding :: Rounding  -- ^ how much rounding or padding to apply to displayed amounts, like --round
  }

-- | The grand totals of a holdings report, summed over its topmost
-- displayed rows (which include everything below them) - except RGain
-- and XIRR, which cover all the lots within the query and end date,
-- including fully disposed lots, commodities and accounts, which have
-- no row unless -E is used; so the totals are the same in list or tree
-- mode, with or without --lots or -E (#2769). Absent components
-- (Nothing or empty) are shown as blank cells.
-- Units, and the average cost per unit, are present only when the
-- holdings are all in one commodity (a multi-commodity total would
-- widen the column for everyone, and a multi-commodity average is
-- not meaningful); the average also needs a single cost commodity.
-- Value and gains are absent unless all holdings have a market price.
data HoldingsTotals = HoldingsTotals {
   htUnits    :: Maybe Amount    -- ^ total units held, when all in one commodity
  ,htAvgCost  :: Maybe Amount    -- ^ their average unit cost, when also in one cost commodity
  ,htCost     :: [Amount]        -- ^ total cost basis, per cost commodity
  ,htValue    :: Maybe [Amount]  -- ^ total market value, per value commodity
  ,htWeight   :: Maybe Quantity  -- ^ percent of the portfolio's value, unrounded
  ,htUgain    :: Maybe [Amount]  -- ^ total unrealised gain, when values and costs are comparable
  ,htUgainPct :: Maybe Quantity  -- ^ total unrealised gain percent, unrounded
  ,htRgain    :: [Amount]        -- ^ total realised gain, per cost commodity
  ,htXirr     :: Maybe Double    -- ^ the portfolio's annualised internal rate of return percent
  }

-- | One display line of the holdings report.
data HoldingsLine
  -- | An account heading row (tree mode): an account with subaccounts
  -- or several commodities, showing its subtree's totals.
  = HoldingsHeading {
      hlIndent  :: Int             -- ^ tree indent depth, 0 at top level
     ,hlAccount :: AccountName     -- ^ the full account name
     ,hlDisplay :: T.Text          -- ^ the name to display: the leaf name, or a squashed chain like b:c
     ,hlTotals  :: HoldingsTotals  -- ^ the account's subtree totals (see hrAccountTotals)
    }
  -- | A holding's line: a position, lot, or depth-clipped aggregate,
  -- one line per held commodity.
  | HoldingsPosition {
      hlIndent  :: Int          -- ^ tree indent depth, 0 at top level and in list mode
     ,hlAccount :: AccountName  -- ^ the account (or lot subaccount) the line belongs to
     ,hlDisplay :: T.Text       -- ^ the name to display: the account name (list mode, or a combined tree row), its commodity (a position under its account's heading), or a lot's name
     ,hlIsLot   :: Bool         -- ^ is this a lot subaccount's line ?
     ,hlHolding :: Holding
    }

-- | A computed holdings report: the display lines and totals shown by
-- the holdings command, renderable by any UI.
data HoldingsReport = HoldingsReport {
   hrDate            :: Day     -- ^ the date holdings are shown at: the day before the (exclusive) report end date if specified, otherwise today
  ,hrLines           :: [HoldingsLine]
     -- ^ the display lines in display order: flat holdings in list
     --   mode, or account sections in tree mode
  ,hrRows            :: [(PeriodicReportRow DisplayName MixedAmount, Holding)]
     -- ^ the holdings as flat records, for machine-readable output:
     --   each holding, paired with its report row (a row holding
     --   several commodities repeats on several lines)
  ,hrTotals          :: HoldingsTotals  -- ^ the grand totals row's components
  ,hrAccountTotals   :: AccountName -> HoldingsTotals
     -- ^ the totals of the lots at or under any one account, computed
     --   like the grand totals row (eg for an account heading row);
     --   Weight is relative to the whole portfolio's value
  ,hrUnitCostHeading :: T.Text  -- ^ what the unit cost column shows: "Unit cost", "Avg cost", or "Unit/Avg cost"
  ,hrStyles          :: M.Map CommoditySymbol AmountStyle
     -- ^ the journal's display styles with hroRounding applied, plus a
     --   style for the "%" commodity, for showing the percent columns
     --   (see showPercentWith)
  }

-- | Chart a holdings report: a bar for each holding (a commodity in an account, or a lot), in each of its commodities' panels
-- (see 'holdingsBarsChart'). Holdings are labelled by account (with --drop applied) and commodity, also in tree mode,
-- since account headings are not drawn.
holdingsReportAsChart :: ReportOpts -> T.Text -> HoldingsReport -> Chart
holdingsReportAsChart ropts title rpt =
  holdingsBarsChart ropts (hrStyles rpt) title (XCategories $ map label positions) [holdingBarParts h | (_, _, h) <- positions]
  where
    -- each holding's account, whether it is a lot, and the holding
    positions = [(a, islot, h) | HoldingsPosition{hlAccount = a, hlIsLot = islot, hlHolding = h} <- hrLines rpt]
    -- eg "assets:broker AAPL", or for a lot, "assets:broker AAPL {2024-01-10, $150}"
    label (acct, islot, h) = ChartLabel (name acct) (name $ accountNameDrop (drop_ ropts) acct) 0 Nothing True
      where
        name a
          | islot     = T.unwords [parentAccountName a, hCommodity h, accountLeafName a]
          | otherwise = a <> " " <> hCommodity h

-- | Chart holdings reports at the ends of some periods: a bar for each period, showing all the holdings then,
-- as their total cost basis and their net unrealised gain or loss (see 'holdingsBarsChart').
-- Periods are labelled by their end dates, the holdings' dates.
holdingsReportsAsChart :: ReportOpts -> T.Text -> [(DateSpan, HoldingsReport)] -> Chart
holdingsReportsAsChart ropts title rpts =
  holdingsBarsChart ropts (maybe M.empty (hrStyles . snd) $ headMay rpts) title (XPeriods [(spn, showDate $ hrDate r) | (spn, r) <- rpts])
    [ mconcat $ map (holdingBarParts . snd) $ hrRows r | (_, r) <- rpts ]

-- | A holding's amounts, for a bar in a holdings chart: its market value and cost basis, if it has a market price
-- (or if its value is not comparable with its cost basis, its value twice, as having no gain or loss);
-- and its cost basis, if it has no market price.
holdingBarParts :: Holding -> ([Amount], [Amount], [Amount])
holdingBarParts h
  | null (hValue h)       = ([], [], hCost h)
  | not (null $ hUgain h) = (hValue h, hCost h, [])
  | otherwise             = (hValue h, hValue h, [])

-- | A chart of holdings: a bar at each x position, in each commodity's panel, from the market value, cost basis
-- and cost basis without a market price, of one or more holdings there (see 'holdingBarParts').
-- Holdings with a market price are drawn as their cost basis and their unrealised gain, stacked, reaching their value;
-- or with an unrealised loss, as the part of their cost basis they are worth, and the part lost (hatched), reaching their cost basis.
-- Holdings without a market price are drawn as their cost basis, beyond those, in a muted colour.
-- The market values are the chart's total (marked when not the bar's end); graphical charts show the unrealised gain percents
-- instead (with these styles, for the % commodity), where there is a market price, since the axis shows the values.
holdingsBarsChart :: ReportOpts -> M.Map CommoditySymbol AmountStyle -> T.Text -> XAxis -> [([Amount], [Amount], [Amount])] -> Chart
holdingsBarsChart ReportOpts{translations_} styles title xaxis parts =
  Chart{chTitle = title, chXAxis = xaxis, chPanels = map panel commodities}
  where
    amts = concat [vs ++ ks ++ us | (vs, ks, us) <- parts]
    -- the commodities of the costs and values, most used first
    commodities = map fst $ sortOn (\(c, n) -> (Down n, c)) $ M.toList $ M.fromListWith (+) [(acommodity a, 1 :: Int) | a <- amts]
    tr = I18n.tr translations_
    panel c = Panel
      { pnUnit = maybe nullamt{acommodity = c} (\a -> a{aquantity = 0, acost = Nothing, acostbasis = Nothing}) $ find ((== c) . acommodity) amts
      , pnSeries = [ Series (ChartLabel name name 0 typ False) role mark vals 0 0
                   | ((name, typ, role, mark), vals) <- zip specs $ transpose [barValues vs ks us | (vs, ks, us) <- parts]
                   , any isJust vals || role == SeriesTotal ]  -- the values, even if none, so that a cost is not shown as one
      , pnGroupNames = []
      , pnScale = Nothing
      , pnLayout = Diverging
      , pnCounts = False
      , pnSummary = []
      , pnValueLabels = [gainPercent (quantityOf vs) (quantityOf ks) | (vs, ks, _) <- parts]
      }
      where
        -- eg +12.5%, -3.0%
        gainPercent mv mk = case (mv, mk) of
          (Just v, Just k) | k /= 0 -> let p = (v - k) / abs k * 100 in Just $ (if p > 0 then "+" else "") <> showPercentWith styles p
          _ -> Nothing
        specs =
          [ (tr "Cost", Just Asset, SeriesItem, MarkBar)
          , (tr "Unrealised gain", Just Revenue, SeriesItem, MarkBar)
          , (tr "Unrealised loss", Just Expense, SeriesShortfall, MarkBar)
          , (tr "No market price", Nothing, SeriesOther, MarkBar)
          , (tr "Value", Nothing, SeriesTotal, MarkMarker)
          ]
        -- A bar's values for those series, in this commodity: the value and cost basis, the smaller of them
        -- stacked with the difference, a gain or loss; then the cost basis without a market price.
        -- (Values and costs are of one sign, negative for a short position, whose gain is a smaller value.)
        barValues vs ks us = case (quantityOf vs, quantityOf ks) of
          (Just v, Just k) ->
            let (base, end) = if abs v <= abs k then (v, k) else (k, v)
                ugain = v - k
            in [Just base, nonzero (ugain > 0) (end - base), nonzero (ugain < 0) (end - base), quantityOf us, Just v]
          _ -> [Nothing, Nothing, Nothing, quantityOf us, Nothing]
        quantityOf as = case [aquantity a | a <- as, acommodity a == c] of
          [] -> Nothing
          qs -> Just $ sum qs
        nonzero ok q = if ok && q /= 0 then Just q else Nothing

-- | Compute the holdings report: the assets held in lot-tracked accounts
-- as of the report end date, one line per account (or per lot, with
-- hroLots) and held commodity, plus grand totals. In tree mode the
-- display lines are instead account sections (see holdingsTreeLines),
-- while the flat records (hrRows) keep the list-mode shape.
--
-- The journal must have its lot detail (lot subaccounts and synthetic
-- postings) uncollapsed, as the holdings command receives it
-- (see maybePrepareLotDetail); this report aggregates lots itself.
-- A --value=then valuation strategy is not supported; callers reject it.
holdingsReport :: HoldingsReportOpts -> ReportSpec -> Journal -> HoldingsReport
holdingsReport hro rspec@ReportSpec{_rsReportOpts=ropts'} j'
  | accountlistmode_ ropts' == ALTree = treeHoldingsReport hro rspec j'
  | otherwise                         = flatHoldingsReport hro rspec j'

-- | The tree-mode holdings report: the flat report, with its display
-- lines grouped into account sections. With hroLots, a second flat
-- report gives each position's lots, shown beneath it, and provides
-- the flat records and unit cost heading, as list mode would.
treeHoldingsReport :: HoldingsReportOpts -> ReportSpec -> Journal -> HoldingsReport
treeHoldingsReport hro rspec@ReportSpec{_rsReportOpts=ropts'} j' =
  prpt{ hrLines = holdingsTreeLines (drop_ ropts') (no_elide_ ropts') prpt mlrpt
      , hrRows  = hrRows mrpt
      , hrUnitCostHeading = hrUnitCostHeading mrpt
      }
  where
    flatrspec = rspec{_rsReportOpts = ropts'{accountlistmode_ = ALFlat}}
    prpt = flatHoldingsReport hro{hroLots = False} flatrspec j'
    mlrpt | hroLots hro = Just $ flatHoldingsReport hro{hroLots = True} flatrspec j'
          | otherwise   = Nothing
    mrpt = fromMaybe prpt mlrpt

-- | Group a flat holdings report's lines into account sections, as tree
-- mode displays them: an account with subaccounts or several
-- commodities is a heading line showing its subtree's totals, with its
-- own positions beneath it named by their commodity, then its
-- subaccounts; an account holding one commodity with no subaccounts is
-- a single combined line carrying its figures. Boring parents - those
-- with no positions of their own and a single child - are squashed into
-- their child like the balance reports' tree mode, unless no-elide is
-- set; only accounts with holdings exist here, so the squashing
-- considers holding rows alone (#2779). With a lots report given, each
-- position's lots are beneath it. Sibling accounts, the top level
-- included, keep the flat report's order, so with -S they are ordered
-- by their first (largest) row. --drop removes the first N levels: the
-- tree's roots are the accounts at level N+1 (a shallower account's
-- own positions, a rare case, show as top-level rows).
holdingsTreeLines :: Int -> Bool -> HoldingsReport -> Maybe HoldingsReport -> [HoldingsLine]
holdingsTreeLines dropn noelide prpt mlrpt =
    concatMap node $ sortOn ((`M.lookup` subtreeIxMap) . fst) $
      [(a, False) | a <- allaccts, accountNameLevel a == dropn + 1] ++
      [(a, True)  | dropn > 0, a <- M.keys posByAcct, accountNameLevel a <= dropn]
  where
    node (a, False) = treeNode 0 a
    node (a, True)  =
      concat [ HoldingsPosition 0 a (accountNameDrop dropn a) False h : lotLines 1 a h
             | h <- M.findWithDefault [] a posByAcct ]
    posByAcct = M.fromListWith (flip (++)) [(hAccount h, [h]) | (_, h) <- hrRows prpt]
    lotsByPos = case mlrpt of
      Nothing -> M.empty
      Just lr -> M.fromListWith (flip (++))
        [ ((lotBaseAccount a, hCommodity h), [h])
        | (_, h) <- hrRows lr, let a = hAccount h, isJust (lotSubaccountName a) ]
    -- each account's subtree's first flat row, ordering subtrees as the
    -- flat report's sort ordered their rows
    subtreeIxMap = M.fromListWith min
      [(a, ix) | (ix, (_, h)) <- zip [0 :: Int ..] (hrRows prpt), a <- expandAccountName (hAccount h)]
    allaccts = M.keys subtreeIxMap
    kidsMap = M.map (sortOn (`M.lookup` subtreeIxMap)) $ M.fromListWith (++)
      [(parentAccountName a, [a]) | a <- allaccts, accountNameLevel a > 1]
    kidsOf a = M.findWithDefault [] a kidsMap
    -- squash boring parents into their child
    elide disp acct
      | not noelide, M.notMember acct posByAcct, [c] <- kidsOf acct =
          elide (disp <> ":" <> accountLeafName c) c
      | otherwise = (disp, acct)
    treeNode d acct0 = case (M.findWithDefault [] acct posByAcct, kidsOf acct) of
      ([h], []) -> HoldingsPosition d acct disp False h : lotLines (d+1) acct h
      (own, kids) ->
        HoldingsHeading d acct disp (hrAccountTotals prpt acct) :
        concat [ HoldingsPosition (d+1) acct (hCommodity h) False h : lotLines (d+2) acct h
               | h <- own ] ++
        concatMap (treeNode (d+1)) kids
      where (disp, acct) = elide (accountLeafName acct0) acct0
    lotLines d acct h =
      [ HoldingsPosition d (hAccount lh) (fromMaybe (hAccount lh) $ lotSubaccountName $ hAccount lh) True lh
      | lh <- M.findWithDefault [] (acct, hCommodity h) lotsByPos ]

-- | The flat (list-mode) holdings report; also the building block of
-- the tree-mode report.
flatHoldingsReport :: HoldingsReportOpts -> ReportSpec -> Journal -> HoldingsReport
flatHoldingsReport HoldingsReportOpts{hroLots=showlots, hroRounding=rounding}
               rspec@ReportSpec{_rsQuery=q, _rsReportOpts=ropts} j =
  HoldingsReport
    { hrDate            = reportdate
    , hrLines           = displaylines
    , hrRows            = rowlines
    , hrTotals          = totals
    , hrAccountTotals   = accountTotals
    , hrUnitCostHeading = unitcostheading
    , hrStyles          = pctstyles
    }
  where
    -- The date this report shows holdings at: the day before the (exclusive)
    -- report end date if specified, otherwise today.
    mend = queryEndDate False q
    reportdate = maybe (_rsDay rspec) (addDays (-1)) mend

    -- The query used to select lot subaccount postings: the report query
    -- without its date terms (holdings are cumulative to the end date,
    -- added here) and depth terms (--depth only clips the displayed rows;
    -- the lots beneath still count).
    endq = And [filterQuery (\x -> not $ queryIsDateOrDate2 x || queryIsDepth x) q
               ,Date $ DateSpan Nothing (Exact <$> mend)]

    -- The postings contributing to each lot subaccount, keyed by account
    -- and commodity (so amounts in different commodities, not expected in
    -- a lot subaccount but possible, don't merge wrongly).
    lotpostings :: [((AccountName, CommoditySymbol), (Day, Amount))]
    lotpostings =
      [ ((paccount p, acommodity a), (postingDate p, a))
      | p <- journalPostings j
      , isJust $ lotSubaccountName $ paccount p
      , endq `matchesPosting` p
      , a <- amountsRaw $ pamount p
      ]

    -- The units held in each lot subaccount.
    lotmap :: M.Map (AccountName, CommoditySymbol) Amount
    lotmap = M.fromListWith (+) [(k, amountStripCost a) | (k, (_, a)) <- lotpostings]

    -- Each lot subaccount's cashflows in the cost commodity, for XIRR:
    -- each posting's transacted cost if any (so, proceeds when disposing),
    -- otherwise its cost basis value. Negative = money invested.
    flowmap :: M.Map (AccountName, CommoditySymbol) [(Day, Amount)]
    flowmap = M.fromListWith (++)
      [ (k, [(d, negate flowamt)])
      | (k, (d, a)) <- lotpostings
      , Just flowamt <- [case acost a of
          Just _  -> Just $ amountCost a
          Nothing -> multiplyAmount (aquantity a) <$> (cbCost =<< acostbasis a)]
      ]

    -- Each lot subaccount's realised gains, in the cost commodity: for each
    -- dispose posting with a transacted price and a cost basis, its cost
    -- basis minus its transacted cost. For a sale (negative) that is the
    -- proceeds minus the basis of the units sold; for a short cover
    -- (positive, in a liability account) it is the short-sale basis minus
    -- the cost of buying the units back.
    -- The gains get their commodity's display style, since the cost bases
    -- they are derived from can have more precision (eg from inferred
    -- per-unit costs).
    rgainmap :: M.Map (AccountName, CommoditySymbol) Amount
    rgainmap = M.map (styleAmounts styles) $ M.fromListWith (+)
      [ ((paccount p, acommodity a), basis - transacted)
      | p <- journalPostings j
      , isDisposePosting p
      , isJust $ lotSubaccountName $ paccount p
      , endq `matchesPosting` p
      , a <- amountsRaw $ pamount p
      , isJust $ acost a
      , isJust $ cbCost =<< acostbasis a
      , let basis = amountCostBasis a
            transacted = amountCost a
      , acommodity basis == acommodity transacted
      ]

    -- The current average unit cost of each AVERAGE/AVERAGEALL pool, as of
    -- the report end date, keyed by (base account, commodity). Computed
    -- from all of the pool's lot postings, whatever the query (see
    -- journalAveragePoolTotals). Used to fill in the cost missing from
    -- AVERAGE lots' costless subaccount names (see lotsUnder).
    poolavgmap :: M.Map (AccountName, CommoditySymbol) Amount
    poolavgmap = M.map (\(units, costtot) -> styleAmounts styles $ avgcost nullamt{aquantity=units} costtot)
                       (journalAveragePoolTotals j mend)

    -- The per-row lookups below (lotsOf, rgainsOf, flowsOf and the
    -- *Under forms) used to scan a whole per-lot map for every displayed
    -- row, making the report roughly O(rows × lots) (#2779). Instead,
    -- each map is indexed by account up front, in two groupings:
    --
    -- "under": a key's data appears under its account and every ancestor,
    -- answering "at or under this account" queries directly.
    --
    -- "own": a key's data appears under its owning row account - the
    -- deepest candidate row account at or above it, if any - answering
    -- "in this row's own scope" queries. This is what makes overlapping
    -- rows disjoint, eg when lots are held in both an account and its
    -- subaccount (each of which then gets its own row).
    --
    -- Each group keeps the map's ascending (account, commodity) key
    -- order, as the full scans produced.

    underIx :: M.Map (AccountName, CommoditySymbol) v -> M.Map AccountName [(CommoditySymbol, v)]
    underIx m = groupIx [(anc, (c, v)) | ((sub, c), v) <- M.toAscList m
                                       , anc <- sub : parentAccountNames sub]

    ownIx :: M.Map (AccountName, CommoditySymbol) v -> M.Map AccountName [(CommoditySymbol, v)]
    ownIx m = groupIx [(owner, (c, v)) | ((sub, c), v) <- M.toAscList m
                                       , Just owner <- [ownerOf sub]]

    -- Group an ascending association list by account, each group keeping
    -- the input order (fromListWith prepends, hence the reverse).
    groupIx :: [(AccountName, a)] -> M.Map AccountName [a]
    groupIx = M.fromListWith (++) . reverse . map (fmap (:[]))

    -- A lot subaccount's owning row account: the deepest candidate row
    -- account at or above it, if any.
    ownerOf :: AccountName -> Maybe AccountName
    ownerOf sub = find (`S.member` candaccset) (sub : parentAccountNames sub)
    candaccset = S.fromList candaccts

    ownFlowIx    = ownIx flowmap
    ownRgainIx   = ownIx rgainmap
    underFlowIx  = underIx flowmap
    underRgainIx = underIx rgainmap

    -- Narrow an indexed group to one held commodity, if specified.
    inComm :: Maybe CommoditySymbol -> [(CommoditySymbol, v)] -> [v]
    inComm mc kvs = [v | (c, v) <- kvs, maybe True (== c) mc]

    -- The cashflows of the lots in a row account's own scope.
    flowsOf :: AccountName -> Maybe CommoditySymbol -> [(Day, Amount)]
    flowsOf acct mc = concat $ inComm mc $ M.findWithDefault [] acct ownFlowIx

    -- The cashflows of the lots at or under an account.
    flowsUnder :: AccountName -> [(Day, Amount)]
    flowsUnder acct = concat $ map snd $ M.findWithDefault [] acct underFlowIx

    -- The realised gains of the lots at or under an account, optionally of one held commodity.
    rgainsUnder :: AccountName -> Maybe CommoditySymbol -> [Amount]
    rgainsUnder acct mc = inComm mc $ M.findWithDefault [] acct underRgainIx

    -- The realised gains of the lots in a row account's own scope.
    rgainsOf :: AccountName -> Maybe CommoditySymbol -> [Amount]
    rgainsOf acct mc = inComm mc $ M.findWithDefault [] acct ownRgainIx

    -- A lot subaccount's cost basis, parsed from its name
    -- (which by construction contains the acquisition date and unit cost).
    -- The cost gets its commodity's display style, including display
    -- precision (lot names can have more precision, eg from inferred
    -- per-unit costs), so derived amounts (Unit cost, Cost) are displayed
    -- with the standard display precision.
    lotBasis :: AccountName -> Maybe CostBasis
    lotBasis acct = do
      name <- lotSubaccountName acct
      cb <- either (const Nothing) Just $ parseLotName parseAmt name
      Just cb{cbCost = styleAmounts styles <$> cbCost cb}
      where parseAmt = either (const Nothing) Just . parseamount

    -- Amounts are displayed normalised to their commodity's display
    -- precision by default; hroRounding can choose another rounding strategy.
    styles = journalCommodityStylesWith rounding j

    priceoracle = journalPriceOracle (infer_prices_ ropts) j

    -- The valuation strategy requested with -V/-X/--value, if any.
    -- It selects the valuation date and/or the valuation commodity;
    -- --value=then is rejected above.
    mvalue = value_ ropts
    (valuationdate, mtargetcomm) = case mvalue of
      Nothing            -> (reportdate, Nothing)
      Just (AtEnd  mc)   -> (reportdate, mc)
      Just (AtNow  mc)   -> (_rsDay rspec, mc)
      Just (AtDate d mc) -> (d, mc)
      Just (AtThen mc)   -> (reportdate, mc)  -- not supported, rejected above

    -- The valuation target commodity for a lot: the commodity requested
    -- with -V/-X/--value if any, otherwise the lot's own cost commodity
    -- when known, otherwise none (the price oracle picks a default).
    lotValuationComm :: Maybe CostBasis -> Maybe CommoditySymbol
    lotValuationComm mcb = case mvalue of
      Nothing -> acommodity <$> (cbCost =<< mcb)
      Just _  -> mtargetcomm

    -- Value one lot at the valuation date: Just (unit price, total value)
    -- if it has a market price to its target commodity.
    lotValuation :: (Amount, Maybe CostBasis) -> Maybe (Amount, Amount)
    lotValuation (a, mcb) = do
      (pcomm, rate) <- priceoracle (valuationdate, acommodity a, lotValuationComm mcb)
      let mkamt n = styleAmounts styles $ amountSetFullPrecisionUpTo Nothing
                      nullamt{acommodity=pcomm, aquantity=n}
      Just (mkamt rate, mkamt (rate * aquantity a))

    -- Value some lots at the valuation date: Just (their distinct unit
    -- prices, their total value per value commodity) if every lot has a
    -- market price, otherwise Nothing. Each lot is valued separately in
    -- its own target commodity, so values (and their sums, like the
    -- totals row) don't depend on how lots are grouped into display rows
    -- (by --depth, --pivot, tree mode etc).
    lotsValuation :: [(Amount, Maybe CostBasis)] -> Maybe ([Amount], [Amount])
    lotsValuation lots = do
      pvs <- mapM lotValuation lots
      Just (nubSortOn (\a -> (acommodity a, aquantity a)) $ map fst pvs
           ,sumAmounts $ map snd pvs)

    -- The market value of the lots at or under an account, per value
    -- commodity, when they are all priced.
    mvalueUnder :: AccountName -> Maybe [Amount]
    mvalueUnder acct = snd <$> lotsValuation (lotsUnder acct)

    -- The market value of the lots in a row account's own scope, per
    -- value commodity, when they are all priced.
    mvalueOf :: AccountName -> Maybe [Amount]
    mvalueOf acct = snd <$> lotsValuation (lotsOf acct)

    -- How to convert cost amounts (Cost, Unit/Avg cost, RGain, and the
    -- cost side of UGain) for display when -V/-X/--value is in effect:
    -- convert to the requested commodity, or to the given fallback
    -- commodity (the row's or portfolio's value commodity), at the
    -- valuation date. Costs already in the target commodity, or with no
    -- target or no market price, are left unchanged.
    costValuerTo :: Maybe CommoditySymbol -> Amount -> Amount
    costValuerTo mfallback = case mvalue of
      Nothing -> id
      Just _ -> case mtargetcomm <|> mfallback of
        Nothing -> id
        -- styleAmounts is reapplied after conversion, since
        -- amountValueAtDate leaves full precision displayed
        Just tc -> \a -> if acommodity a == tc then a
                         else styleAmounts styles $
                              amountValueAtDate priceoracle styles (Just tc) valuationdate a

    rowCostValuer :: PeriodicReportRow DisplayName MixedAmount -> Amount -> Amount
    rowCostValuer r = costValuerTo mrowvaluecomm
      where
        mrowvaluecomm = case mvalueUnder (prrFullName r) of
          Just [v] -> Just $ acommodity v
          _        -> Nothing

    -- The annualised internal rate of return implied by dated cashflows
    -- (negative = money invested) up to the report date, as a percentage,
    -- calculated like roi's IRR. Nothing if it can not be solved.
    -- Note: this duplicates the solver setup and rate convention of
    -- Roi.hs's solveIRR/interestSum (not exported); keep them in sync,
    -- or extract a shared helper.
    xirrPct :: [(Day, Quantity)] -> Maybe Double
    xirrPct cf =
      case ridders (RiddersParam 100 (AbsTol 0.00001)) (0.000000000001, 10000) npv of
        Root rate -> Just $ (rate - 1) * 100
        _         -> Nothing
      where
        npv rate = sum [realToFrac n * rate ** (fromIntegral (diffDays reportdate t) / 365.25) | (t, n) <- cf]

    -- XIRR from cashflows plus a final value amount at the report date,
    -- when they are all in one commodity. Not for a short position, whose
    -- flows are a long position's with the signs reversed: the rate solving
    -- those is the same, so it would report a winning short as a loss. A
    -- short is recognised by a negative final value (units owed), or when
    -- closed, by money received rather than invested in the earliest flow.
    xirrOf :: [(Day, Amount)] -> Amount -> Maybe Double
    xirrOf flows finalv = do
      guard $ not $ null flows
      guard $ all ((== acommodity finalv) . acommodity . snd) flows
      let earliest = aquantity $ snd $ minimumBy (comparing fst) flows
          isshort = aquantity finalv < 0 || (aquantity finalv == 0 && earliest > 0)
      guard $ not isshort
      xirrPct $ (reportdate, aquantity finalv) : [(d, aquantity a) | (d, a) <- flows]

    -- The total value of the displayed holdings, per value commodity,
    -- when all are priced; and its commodity, when it has just one.
    mportfoliovalue :: Maybe [Amount]
    mportfoliovalue = do
      vs <- mapM (mvalueUnder . prrFullName) toprows
      Just $ sumAmounts $ concat vs
    mportvaluecomm = case mportfoliovalue of
      Just [v] -> Just $ acommodity v
      _        -> Nothing

    -- A value's percentage of the portfolio's total value, when both are
    -- single amounts in the same commodity.
    weightPct :: [Amount] -> Maybe Quantity
    weightPct val = do
      tot <- mportfoliovalue
      [t] <- Just tot
      [v] <- Just val
      guard $ acommodity v == acommodity t && aquantity t /= 0
      Just $ 100 * aquantity v / aquantity t

    -- The commodity display styles, plus a default style for the "%"
    -- commodity if none is declared or inferred: one decimal digit,
    -- and the % sign on the right with no space.
    pctstyles = M.union styles $ M.singleton "%" $
      amountstyle{ascommodityside=R, asprecision=Precision 1, asrounding=HardRounding}

    -- The unrealised gains implied by value and cost amounts: value minus
    -- cost per commodity, when they cover exactly the same (nonempty) set
    -- of commodities; otherwise Nothing.
    gainAmounts :: [Amount] -> [Amount] -> Maybe [Amount]
    gainAmounts vals costs = do
      guard $ not (null vs) && map acommodity vs == map acommodity cs
      Just $ zipWith gain1 vs cs
      where
        vs = sumAmounts vals
        cs = sumAmounts costs
        gain1 v c = styleAmounts styles $ amountSetFullPrecisionUpTo Nothing
                      nullamt{acommodity=acommodity v, aquantity=aquantity v - aquantity c}

    -- The percent gain, when the gains and the costs are single amounts
    -- in the same commodity and the cost is nonzero. Relative to the cost's
    -- magnitude, so a short position's gain (its cost being negative) keeps
    -- its sign.
    gainPct :: [Amount] -> [Amount] -> Maybe Quantity
    gainPct gains costs = do
      [g] <- Just gains
      [c] <- Just $ sumAmounts costs
      guard $ acommodity g == acommodity c && aquantity c /= 0
      Just $ 100 * aquantity g / abs (aquantity c)

    -- A row's units of lot-tracked commodities: the sum of the lots in
    -- its own scope, one amount per commodity. (Not the row's report
    -- balance: a depth-clipped or pivoted row could also aggregate
    -- same-commodity balances from non-lot-tracked accounts, which would
    -- make Units inconsistent with the lot-derived Cost and gain columns.)
    rowUnitAmounts :: PeriodicReportRow DisplayName MixedAmount -> [Amount]
    rowUnitAmounts r =
      filter (not . amountLooksZero) $ sumAmounts $
      map fst $ lotsOf $ prrFullName r

    -- The nonempty lots as (units, cost basis), keyed like lotmap.
    -- A lot's cost basis comes from its subaccount name, parsed once
    -- here; when the name has no cost part (AVERAGE lots' names omit it,
    -- staying stable across re-averaging), the pool's current average
    -- cost is filled in instead.
    lotbases :: M.Map (AccountName, CommoditySymbol) (Amount, Maybe CostBasis)
    lotbases = M.mapWithKey mklot $ M.filter (not . amountLooksZero) lotmap
      where
        mklot (sub, _) a = (a, addPoolAvg sub a <$> lotBasis sub)
        addPoolAvg sub a cb@CostBasis{cbCost=Nothing} =
          cb{cbCost = M.lookup (lotBaseAccount sub, acommodity a) poolavgmap}
        addPoolAvg _ _ cb = cb

    underLotIx = underIx lotbases
    ownLotIx   = ownIx lotbases

    -- The lots held at or under the given account, excluding empty ones.
    lotsUnder :: AccountName -> [(Amount, Maybe CostBasis)]
    lotsUnder acct = map snd $ M.findWithDefault [] acct underLotIx

    -- The lots in a row account's own scope, excluding empty ones.
    lotsOf :: AccountName -> [(Amount, Maybe CostBasis)]
    lotsOf acct = map snd $ M.findWithDefault [] acct ownLotIx

    -- Report rows come from a single-period, end-balances multiBalanceReport:
    -- on the lot-detailed journal with --lots (rows are lot subaccounts),
    -- on the collapsed journal otherwise (rows are the base accounts).
    -- Non-holding accounts are filtered out.
    -- Cost conversion and valuation (-B/-V/--value) are disabled:
    -- holdings does its own valuation, and units should stay units.
    mbr = multiBalanceReport rspec' j'
      where
        rspec' = rspec{_rsReportOpts=ropts{balanceaccum_=Historical, interval_=NoInterval
                                          ,conversionop_=Just NoConversionOp, value_=Nothing
                                          ,sort_amount_=False}}  -- -S sorts by value/cost below, not by units
        j' = if showlots then j else journalCollapseLotDetail j
    -- Candidate rows: those with lots at or beneath them; with -E/--empty,
    -- also those with realised gains at or beneath them (fully disposed
    -- accounts/lots, normally hidden).
    candidates = filter isholdingrow $ prRows mbr
      where
        isholdingrow r = not (null (lotsUnder acct))
                      || (empty_ ropts && hasRgainsUnder acct)
          where acct = prrFullName r
    candaccts = map prrFullName candidates

    -- Rows to display: the candidates, except those with nothing in
    -- their own scope (eg a base account row whose lots all appear in
    -- displayed lot subaccount rows). A row holding lots directly is
    -- kept even when a deeper row also displays; it shows just its own
    -- lots (see ownIx).
    rows = filter keeprow candidates
      where
        keeprow r = not (null (lotsOf acct))
                 || (empty_ ropts && hasRgainsOf acct)
          where acct = prrFullName r

    -- Are there nonzero realised gains at or under this account ?
    hasRgainsUnder :: AccountName -> Bool
    hasRgainsUnder acct = any (not . amountLooksZero) $ rgainsUnder acct Nothing

    -- Are there nonzero realised gains in this row account's own scope ?
    hasRgainsOf :: AccountName -> Bool
    hasRgainsOf acct = any (not . amountLooksZero) $ rgainsOf acct Nothing

    -- The topmost displayed rows: those not contained in another displayed
    -- row. Totals are computed from these, to avoid double counting.
    toprows = [ r | r <- rows
              , not $ any (`S.member` rowaccset) (parentAccountNames $ prrFullName r) ]
      where rowaccset = S.fromList $ map prrFullName rows

    -- The display order: by account name, or with -S by each row's Value
    -- (falling back to Cost), largest first. Sorting compares the keys
    -- along each row's chain of displayed ancestors, so an overlapping
    -- subaccount row sorts with its displayed parent (and tree mode's
    -- sections, which keep this order, get each level sorted). Ties (and
    -- rows mixing commodities, which are summed crudely) keep the
    -- account name order.
    sortedrows
      | not $ sort_amount_ ropts = rows
      | otherwise = sortOn keypath rows
      where
        keymap = M.fromList [(prrFullName r, Down $ rowSortKey r) | r <- rows]
        keypath r = mapMaybe (`M.lookup` keymap) $ reverse (parentAccountNames a) ++ [a]
          where a = prrFullName r
        rowSortKey r = case mvalueOf (prrFullName r) of
          Just val -> sumq val
          Nothing  -> sumq $ rowLotCosts r
          where sumq = sum . map aquantity

    -- The displayed table lines: each report row's holdings, one line per
    -- commodity, with the report row kept for rendering the account cell
    -- (repeated on each of its lines).
    rowlines :: [(PeriodicReportRow DisplayName MixedAmount, Holding)]
    rowlines = [(r, h) | r <- sortedrows, h <- rowHoldings r]

    -- One display line per report line.
    displaylines :: [HoldingsLine]
    displaylines =
      [ HoldingsPosition
          { hlIndent  = prrIndent r
          , hlAccount = prrFullName r
          , hlDisplay = prrDisplayName r
          , hlIsLot   = isJust $ lotSubaccountName $ prrFullName r
          , hlHolding = h }
      | (r, h) <- rowlines ]

    -- The cost column's heading matches what's shown: "Avg cost" on rows
    -- aggregating multiple lots (the default) or when the lots shown all
    -- belong to AVERAGE/AVERAGEALL pools (whose per-lot rows show the
    -- pool's average cost); "Unit cost" when each lot shows its own cost;
    -- "Unit/Avg cost" when both kinds of lot are shown.
    -- TRANSLATORS: the holdings table's cost column heading, translated where it is displayed.
    unitcostheading :: T.Text
    unitcostheading
      | not showlots || allavg = I18n.i18n "Avg cost"
      | anyavg = I18n.i18n "Unit/Avg cost"
      | otherwise = I18n.i18n "Unit cost"
      where
        avgs = [ fst (resolveReductionMethodForAccount j (lotBaseAccount sub) c)
                 `elem` [AVERAGE, AVERAGEALL]
               | (sub, c) <- M.keys lotmap ]
        allavg = not (null avgs) && and avgs
        anyavg = or avgs

    rowLotCosts r = [rowCostValuer r $ multiplyAmount (aquantity a) c
                    | (a, mcb) <- lotsOf $ prrFullName r, Just c <- [cbCost =<< mcb]]

    -- Sum amounts per commodity, keeping an empty list empty
    -- (unlike amounts . mixed, which would make it a single zero).
    sumAmounts :: [Amount] -> [Amount]
    sumAmounts [] = []
    sumAmounts as = amounts $ mixed as

    -- A report row's holdings, one per commodity, in the same order as its
    -- unit amounts. With -E/--empty, these are followed by a zero-units
    -- holding for each commodity no longer held at or under the row's
    -- account but with realised gains, keeping those visible (eg a
    -- commodity fully sold off); without -E such rows are hidden (their
    -- gains still count in the totals row).
    rowHoldings :: PeriodicReportRow DisplayName MixedAmount -> [Holding]
    rowHoldings r = map rec $ heldamts ++ rgainonlyamts
      where
        acct = prrFullName r
        heldamts = rowUnitAmounts r
        rgainonlyamts
          | not $ empty_ ropts = []
          | otherwise =
              [ nullamt{acommodity=c}
              | c <- nubSort [ c2 | (c2, g) <- M.findWithDefault [] acct ownRgainIx
                                  , not $ amountLooksZero g ]
              , c `notElem` map acommodity heldamts
              ]
        rec qa = Holding
          { hAccount   = acct
          , hCommodity = c
          , hDate      = mdate
          , hAge       = diffDays reportdate <$> mdate
          , hUnits     = styleAmounts styles qa
          , hUnitCost  = mucost
          , hCost      = sumAmounts ccosts
          , hPrice     = prices
          , hValue     = vals
          , hWeight    = weightPct vals
          , hUgain     = gains
          , hUgainPct  = gainPct gains ccosts
          , hRgain     = sumAmounts $ map (rowCostValuer r) $ rgainsOf acct (Just c)
          , hXirr      = mxirr
          }
          where
            c = acommodity qa
            clots = filter ((==c) . acommodity . fst) $ lotsOf acct
            dates = nubSort [cbDate =<< mcb | (_, mcb) <- clots]
            mdate = case dates of
              [Just dt] -> Just dt
              _         -> Nothing
            ccosts = [rowCostValuer r $ multiplyAmount (aquantity a) cb | (a, mcb) <- clots, Just cb <- [cbCost =<< mcb]]
            mucost = case (clots, ccosts) of
              ([(_, mcb)], _) -> rowCostValuer r <$> (cbCost =<< mcb)
              (_, _:_) | [totcost] <- amounts (mixed ccosts)
                       , not $ amountLooksZero qa
                       -> Just $ avgcost qa totcost
              _ -> Nothing
            -- The line's lots to value; a zero-units (rgain-only) line
            -- values a synthetic zero lot, so a market price and a zero
            -- value can still be shown.
            vlots = if null clots then [(qa, Nothing)] else clots
            (prices, vals) = fromMaybe ([], []) $ lotsValuation vlots
            gains = fromMaybe [] $ gainAmounts vals ccosts
            mxirr = do
              [v] <- Just vals
              xirrOf (flowsOf acct (Just c)) v

    -- The grand totals, summed over the topmost displayed rows; the
    -- RGain and XIRR components cover all the lots within the query and
    -- end date, whatever rows are displayed (#2769; see HoldingsTotals).
    totals :: HoldingsTotals
    totals = HoldingsTotals
      { htUnits    = case totunits of [u] -> Just u; _ -> Nothing
      , htAvgCost  = case (totunits, sumAmounts totcosts) of
          ([u], [c]) -> Just $ avgcost u c
          _          -> Nothing
      , htCost     = amounts $ mixed totcosts
      , htValue    = mportfoliovalue
      , htWeight   = weightPct =<< mportfoliovalue
      , htUgain    = mtotgains
      , htUgainPct = gainPct (fromMaybe [] mtotgains) totcosts
      , htRgain    = case map (costValuerTo mportvaluecomm) $ M.elems rgainmap of
          [] -> []
          rs -> amounts $ mixed rs
      , htXirr     = do
          totvalue <- mportfoliovalue
          [tv] <- Just totvalue
          xirrOf (concat $ M.elems flowmap) tv
      }
      where
        totunits = filter (not . amountLooksZero) $ sumAmounts $
                   concatMap (map fst . lotsUnder . prrFullName) toprows
        totcosts = [ rowCostValuer r $ multiplyAmount (aquantity a) c
                   | r <- toprows, (a, mcb) <- lotsUnder (prrFullName r), Just c <- [cbCost =<< mcb] ]
        mtotgains = mportfoliovalue >>= \totvalue -> gainAmounts totvalue totcosts

    -- The totals of the lots at or under one account, computed like the
    -- grand totals row: an account heading row's figures. Like those,
    -- RGain and XIRR cover all the subtree's lots within the query and
    -- end date, including fully disposed ones with no row (#2769), and
    -- Weight is relative to the whole portfolio's value.
    accountTotals :: AccountName -> HoldingsTotals
    accountTotals acct = HoldingsTotals
      { htUnits    = case units of [u] -> Just u; _ -> Nothing
      , htAvgCost  = case (units, sumAmounts costs) of
          ([u], [c]) -> Just $ avgcost u c
          _          -> Nothing
      , htCost     = sumAmounts costs
      , htValue    = msubvalue
      , htWeight   = weightPct =<< msubvalue
      , htUgain    = mgains
      , htUgainPct = gainPct (fromMaybe [] mgains) costs
      , htRgain    = sumAmounts $ map (costValuerTo msubvaluecomm) $ rgainsUnder acct Nothing
      , htXirr     = do
          [v] <- msubvalue
          xirrOf (flowsUnder acct) v
      }
      where
        units = filter (not . amountLooksZero) $ sumAmounts $ map fst $ lotsUnder acct
        costs = [ costValuerTo msubvaluecomm $ multiplyAmount (aquantity a) c
                | (a, mcb) <- lotsUnder acct, Just c <- [cbCost =<< mcb] ]
        msubvalue = mvalueUnder acct
        msubvaluecomm = case msubvalue of
          Just [v] -> Just $ acommodity v
          _        -> Nothing
        mgains = msubvalue >>= \subvalue -> gainAmounts subvalue costs

    -- An average cost: total cost / total units, shown like other amounts
    -- in the cost commodity's display precision - but with at least 2
    -- decimal digits when the division is inexact and the display
    -- precision is less, so eg an average of $56.666... is not shown as
    -- the misleading $57.
    avgcost qtya costa = amountSetPrecision (Precision p) avg
      where
        avg  = divideAmountAndUpdatePrecision (aquantity qtya) costa
        p = clamp pstyle (max 2 pstyle) pdiv
        clamp lo hi = max lo . min hi
        pdiv = case asprecision (astyle avg) of Precision n -> n; _ -> defaultMaxDisplayPrecision
        pstyle = case asprecision (astyle costa) of Precision n -> n; _ -> 2

-- | Show the holdings report: the assets held in lot-tracked accounts
-- as of the report end date, one row per account (or per lot, with --lots).
--
-- This command receives the journal with lot detail (lot subaccounts and
-- synthetic postings) uncollapsed, regardless of --lots
-- (see maybePrepareLotDetail); holdingsReport aggregates lots itself.
holdings :: CliOpts -> Journal -> IO ()
holdings opts@CliOpts{rawopts_=rawopts, reportspec_=rspec@ReportSpec{_rsReportOpts=ropts}} j = do
  warnIfLargeMultiPeriodReport rspec j
  if (case value_ ropts of Just (AtThen _) -> True; _ -> False)
  then error' "holdings: --value=then is not supported"
  else rounding `seq`  -- validate the --round value before any output
    if | chartRequested opts && periodic ->
           writeChart opts (Just $ (<>"\n") $ htmlAsLazyText $ titledTableHtml ptitle phtmltable) $ holdingsReportsAsChart ropts ptitle periodrpts
       | chartRequested opts ->
           writeChart opts (Just $ (<>"\n") $ htmlAsLazyText $ titledTableHtml title htmltable) $ holdingsReportAsChart ropts title rpt
       | periodic -> writeOutputLazyText opts $ case outputFormatFromOpts opts of
           "txt"  -> ptxtoutput
           "csv"  -> printCSV pcsvoutput
           "tsv"  -> printTSV pcsvoutput
           "html" -> (<>"\n") $ htmlAsLazyText $ titledTableHtml ptitle phtmltable
           "fods" -> printFods IO.localeEncoding $ M.singleton (tr "Holdings") ((1,0), pfodstable)
           "json" -> (<>"\n") $ toJsonText $ map (uncurry periodTotalsJson) ptotals
           fmt    -> error' $ unsupportedOutputFormatError fmt
       | otherwise -> writeOutputLazyText opts $ case outputFormatFromOpts opts of
           "txt"  -> txtoutput
           "csv"  -> printCSV csvoutput
           "tsv"  -> printTSV csvoutput
           "html" -> (<>"\n") $ htmlAsLazyText $ titledTableHtml title htmltable
           "fods" -> printFods IO.localeEncoding $ M.singleton (tr "Holdings") ((1,0), fodstable)
           "json" -> (<>"\n") $ toJsonText $ map holdingJson holdingrecords
           fmt    -> error' $ unsupportedOutputFormatError fmt
  where
    -- Amounts are displayed normalised to their commodity's display
    -- precision by default; --round can choose another rounding strategy.
    rounding = fromMaybe HardRounding $ roundFromRawOpts rawopts
    tr = I18n.tr (translations_ ropts)
    trf = I18n.trf (translations_ ropts)

    rpt = holdingsReport
      HoldingsReportOpts{hroLots = boolopt "lots" rawopts, hroRounding = rounding}
      rspec j
    rowlines = hrRows rpt
    reportdate = hrDate rpt

    -- With a report interval, the holdings at the end of each period (their totals, in a row per period),
    -- like the single-date report computed at each period's end. List/tree mode and --lots don't matter here.
    periodic = interval_ ropts /= NoInterval
    periodrpts :: [(DateSpan, HoldingsReport)]
    periodrpts =
      [ (spn, holdingsReport HoldingsReportOpts{hroLots = False, hroRounding = rounding} (rspecEndingAt e) j)
      | spn@(DateSpan _ (Just e)) <- maybeDayPartitionToDateSpans $ snd $ reportSpanBothDates j rspec ]
    rspecEndingAt e = rspec{ _rsQuery = And [filterQuery (not . queryIsDateOrDate2) (_rsQuery rspec), Date $ DateSpan Nothing (Just e)]
                           , _rsReportOpts = ropts{accountlistmode_ = ALFlat} }
    ptotals = [(hrDate r, (hrStyles r, hrTotals r)) | (_, r) <- periodrpts]
    -- TRANSLATORS: the title of the holdings report with a report interval; {dates} is a date range like 2026-01-31..2026-06-30.
    ptitle = effectiveTitle ropts $ case map fst ptotals of
      [] -> tr "Holdings at period ends"
      ds -> trf "Holdings at period ends, {dates}" [("dates", showDate (minimum ds) <> ".." <> showDate (maximum ds))]
    pcolheadings = [tr "Total cost", tr "Total value", tr "UGain", tr "UGain%", tr "RGain", tr "XIRR"]
    -- a period's cells: those of the totals row's cells which make sense over time
    -- (Units and Avg cost are shown only for a single commodity, and Weight is always 100%)
    periodcells (styles, tot) = [ps | (i, ps) <- zip [0 :: Int ..] (totalsCellParts styles tot), i `elem` [5, 6, 8, 9, 10, 11]]
    ptxtoutput =
      (case ptitle of
         "" -> ""
         t  -> TL.fromStrict t <> "\n\n")
      <>
      if null ptotals
      then TL.fromStrict (tr "(no holdings)") <> "\n"
      else renderTable def{tableBorders=False} (textCell TopLeft) (textCell TopRight) (textCell TopRight) $ Table
        (Group NoLine [Header $ showDate d | (d, _) <- ptotals])
        (Group NoLine $ map Header pcolheadings)
        [map (T.intercalate ", ") $ periodcells st | (_, st) <- ptotals]
    pcsvoutput :: CSV
    pcsvoutput = ["date","totalcost","totalvalue","ugain","ugainpct","rgain","xirr"] : map (uncurry periodTotalsCsv) ptotals
    -- spreadsheet-shaped tables for the html and fods output, like the text table
    pspreadsheetWith :: forall content. (T.Text -> content) -> (Bool -> [T.Text] -> content) -> [[Ods.Cell Ods.NumLines content]]
    pspreadsheetWith plain parts =
      addHeaderBorders [plain <$> (headerCell t){Ods.cellClass = Ods.Class cls} | (t, cls) <- zip (tr "Date" : pcolheadings) pcolclasses]
      : [ (Ods.defaultCell (plain $ showDate d)){Ods.cellType = Ods.TypeString, Ods.cellClass = Ods.Class "date"}
          : [ (Ods.defaultCell (parts isamount ps)){Ods.cellType = Ods.TypeMixedAmount, Ods.cellClass = Ods.Class cls}
            | (isamount, ps, cls) <- zip3 [True, True, True, False, True, False] (periodcells st) (drop 1 pcolclasses) ]
        | (d, st) <- ptotals ]
      where pcolclasses = ["date","totalcost","totalvalue","ugain","ugainpct","rgain","xirr"]
    phtmltable = pspreadsheetWith toHtml htmlParts
    pfodstable = pspreadsheetWith id (\_ -> T.intercalate ", " . filter (not . T.null))

    -- The default title can be customised or suppressed with --title.
    title = effectiveTitle ropts (trf "Holdings on {date}" [("date", showDate reportdate)])
    txtoutput =
      (case title of
         "" -> ""
         t  -> TL.fromStrict t <> "\n\n")
      <>
      if null rowlines
      then TL.fromStrict (tr "(no holdings)") <> "\n"
      else renderTable
        def{tableBorders=False}
        (textCell TopLeft)
        (textCell TopRight)
        (textCell TopRight)
        tbl

    tbl = maybe id addtotalrow (map (T.intercalate ", ") <$> mtotalrowparts) $ Table
      (Group NoLine $ map (Header . lineacct) displaylines)
      (Group NoLine $ map Header colheadings)
      (map (map (T.intercalate ", ") . linecells) displaylines)
      where
        addtotalrow totalrow tbl' = concatTables SingleLine tbl' $
          Table (Group NoLine [Header ""]) (Header []) [totalrow]
    -- TRANSLATORS: the holdings table's column headings. The cost heading is "Unit cost", "Avg cost", or "Unit/Avg cost".
    colheadings = [tr "Date", tr "Age", tr "Units", tr (hrUnitCostHeading rpt), tr "Unit price", tr "Total cost", tr "Total value", tr "Weight", tr "UGain", tr "UGain%", tr "RGain", tr "XIRR"]
    displaylines = hrLines rpt

    -- A display line's account cell: indented display names in tree
    -- mode, full (possibly dropped) account names otherwise.
    lineacct :: HoldingsLine -> T.Text
    lineacct l
      | accountlistmode_ ropts == ALTree && not (full_names_ ropts) =
          T.replicate (hlIndent l * 2) " " <> hlDisplay l
      | otherwise = accountNameDrop (drop_ ropts) (hlAccount l)

    -- A display line's data cells, each as a list of parts.
    linecells :: HoldingsLine -> [[T.Text]]
    linecells HoldingsHeading{hlTotals}   = totalsCellParts (hrStyles rpt) hlTotals
    linecells HoldingsPosition{hlHolding} = holdingCellParts hlHolding

    showpct = showPercentWith (hrStyles rpt)
    -- Show an XIRR percentage, like showpct: eg 12.3%.
    showxirr :: Double -> T.Text
    showxirr = showpct . realToFrac

    -- A holding's cells, each as a list of parts: possibly several in Cost
    -- and RGain (when cost commodities are mixed), at most one elsewhere.
    -- Units show a commodity symbol even when zero (for rgain-only rows).
    holdingCellParts :: Holding -> [[T.Text]]
    holdingCellParts h =
      [ [maybe "" showDate (hDate h)]
      , [maybe "" showage (hAge h)]
      , [T.pack $ showAmountWith noCostFmt{displayZeroCommodity=True} (hUnits h)]
      , [maybe "" showamt (hUnitCost h)]
      , map showamt $ hPrice h
      , map showamt $ hCost h
      , map showamtz $ hValue h
      , [maybe "" showpct (hWeight h)]
      , map showamtz $ hUgain h
      , [maybe "" showpct (hUgainPct h)]
      , map showamt $ hRgain h
      , [maybe "" showxirr (hXirr h)]
      ]
      where
        showamt  = T.pack . showAmountWith noCostFmt
        showamtz = T.pack . showAmountWith noCostFmt{displayZeroCommodity=True}

    -- A totals row's cells (the grand total, or an account heading row
    -- in tree mode), each as a list of parts like holdingCellParts.
    totalsCellParts :: M.Map CommoditySymbol AmountStyle -> HoldingsTotals -> [[T.Text]]
    totalsCellParts styles tot =
      [ []
      , []
      , maybe [] ((:[]) . showamt) (htUnits tot)
      , maybe [] ((:[]) . showamt) (htAvgCost tot)
      , []
      , map showamt (htCost tot)
      , maybe [] (map showamt) (htValue tot)
      , [maybe "" pct (htWeight tot)]
      , maybe [] (map showamtz) (htUgain tot)
      , [maybe "" pct (htUgainPct tot)]
      , map showamt (htRgain tot)
      , [maybe "" (pct . realToFrac) (htXirr tot)]
      ]
      where
        pct = showPercentWith styles
        showamt  = T.pack . showAmountWith noCostFmt
        showamtz = T.pack . showAmountWith noCostFmt{displayZeroCommodity=True}

    -- The grand totals row as cell parts, unless --no-total is in effect.
    mtotalrowparts :: Maybe [[T.Text]]
    mtotalrowparts
      | no_total_ ropts = Nothing
      | otherwise = Just $ totalsCellParts (hrStyles rpt) $ hrTotals rpt

    -- Spreadsheet-shaped tables for the html and fods output: like the
    -- text table, but with single-line cells, an Account column heading,
    -- and a Total: row heading. Parameterised on how to convert plain
    -- text, and a cell's list of (possibly amount) parts, to content.
    spreadsheetWith :: forall content. (T.Text -> content) -> (Bool -> [T.Text] -> content)
                    -> [[Ods.Cell Ods.NumLines content]]
    spreadsheetWith plain parts =
      addHeaderBorders (zipWith hcell colclasses (tr "Account" : colheadings))
      : [ zipWith3 bodycell [0..] (lineclasses l)
            (plain (acctcell l) : zipWith parts amountcols (linecells l))
        | l <- displaylines ]
      ++ maybe [] (\tot -> addTotalBorders
           [zipWith3 totalcell [0..] colclasses
              (plain (tr "Total:") : zipWith parts amountcols tot) :: [Ods.Cell () content]])
           mtotalrowparts
      where
        -- per-column css classes, so the html cells can be styled
        colclasses = ["account","date","age","units","unitcost","unitprice","totalcost","totalvalue","weight","ugain","ugainpct","rgain","xirr"]
        -- which of the other columns' cell parts are amounts
        amountcols = [False, False, True, True, True, True, True, False, True, False, True, False]
        hcell cls t = plain <$> (headerCell t){Ods.cellClass = Ods.Class cls}
        -- account heading rows get an extra class, so html can style them
        lineclasses HoldingsHeading{}  = "account acctheading" : drop 1 colclasses
        lineclasses HoldingsPosition{} = colclasses
        -- body cells are right-aligned, except the first two columns
        -- (Account and Date); headings are unaffected
        bodycell :: Ods.Lines border => Int -> T.Text -> content' -> Ods.Cell border content'
        bodycell i cls t = (Ods.defaultCell t)
          {Ods.cellType = if i < 2 then Ods.TypeString else Ods.TypeMixedAmount
          ,Ods.cellClass = Ods.Class cls}
        totalcell i cls = bodycell i (cls <> " coltotal")
        -- indent tree-mode account names with no-break spaces
        acctcell l = T.replicate (hlIndent l * 2) "\160" <> hlDisplay l

    -- Each commodity amount gets its own span with an "amount" class,
    -- so eg wrapping within amounts can be prevented with css.
    htmltable :: [[Ods.Cell Ods.NumLines Html]]
    htmltable = spreadsheetWith toHtml htmlParts
    htmlParts isamount parts =
      mconcat $ intersperse (toHtml (", "::T.Text)) $
      map (\p -> if isamount then (H.span ! A.class_ "amount") (toHtml p) else toHtml p) $
      filter (not . T.null) parts

    fodstable :: [[Ods.Cell Ods.NumLines T.Text]]
    fodstable = spreadsheetWith id (\_ -> T.intercalate ", " . filter (not . T.null))

    -- Machine-readable records for the csv/tsv/json output, one per
    -- displayed table line. No totals records.
    holdingrecords :: [Holding]
    holdingrecords = map snd rowlines

    csvoutput :: CSV
    csvoutput =
      ["account","commodity","date","age","units","unitcost","unitprice","totalcost","totalvalue","weight","ugain","ugainpct","rgain","xirr"]
      : map holdingCsv holdingrecords
