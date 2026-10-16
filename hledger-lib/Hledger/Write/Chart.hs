{- |
A renderer-independent description of a chart, made from a report.

This is to charts what "Hledger.Write.Spreadsheet" is to tables:
each chart-capable report has an adapter that turns its report data into a 'Chart',
choosing a useful default chart for that report (see doc/PLAN-charts.md, "Smart defaults"),
and renderers turn a 'Chart' into text, SVG, CSV or JSON.

The model carries the report's own display information
(period headings, account display names, commodity display styles, the report title)
so that every renderer labels things exactly as the report's table would.
Signs are already as the report shows them (eg normal-balance flipping done by bs/is/cf).

Values are kept exact here ('Quantity'); renderers convert them to Double only for drawing.
-}

{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE OverloadedStrings #-}

module Hledger.Write.Chart (
  Chart(..),
  XAxis(..),
  ChartLabel(..),
  Panel(..),
  BarLayout(..),
  Series(..),
  SeriesRole(..),
  Mark(..),
  SeriesValues,
  seriesValues,
  valueAt,
  groupDates,
  chartAsCsv,
  tests_Hledger_Write_Chart,
) where

import Data.Function (on)
import Data.List (find, groupBy)
import Data.Maybe (fromMaybe, listToMaybe, mapMaybe)
import Data.Time (addDays, addGregorianMonthsClip, fromGregorian, toGregorian)
import Data.Time.Calendar.WeekDate (toWeekDate)

import Data.Array (Array, bounds, inRange, listArray, (!))

import Data.Aeson (ToJSON)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Time (Day)
import GHC.Generics (Generic)

import Hledger.Data.Amount (AmountFormat(..), machineFmt, nullamt, showAmountWith)
import Hledger.Data.Dates (showDate, showDateSpan)
import Hledger.Data.Json ()
import Hledger.Data.Types (Amount(..), DateSpan(..), EFDay(..), Quantity)
import Hledger.Utils.Test
import Hledger.Write.Csv (CSV)


-- | A chart: a title, an x axis, and one or more panels drawn against that x axis.
-- Typically there is one panel per commodity.
-- A chart with no panels, or whose panels have no series, has no data; renderers should say so, not fail.
data Chart = Chart
  { chTitle  :: Text     -- ^ the report's title, as its table would show it (may be empty)
  , chXAxis  :: XAxis    -- ^ the x positions, shared by all panels
  , chPanels :: [Panel]  -- ^ the panels, in display order (eg largest commodity first)
  } deriving (Show, Eq, Generic, ToJSON)

-- | The x positions of a chart: what each value in a series corresponds to.
-- Every series in the chart has one value per x position (renderers must not assume this, and should ignore extras).
--
-- Renderers choose orientation from this: periods and dates are drawn along a horizontal time axis in SVG,
-- categories as horizontal bars. Text charts always draw one row per x position.
data XAxis
  = XCategories [ChartLabel]     -- ^ unordered categories, eg the accounts of a single-period balance report
  | XPeriods [(DateSpan, Text)]  -- ^ consecutive report periods, each with its heading as the report's table shows it
  | XDates [Day]                 -- ^ individual dates, possibly irregular and repeated, eg one per transaction in a register
  deriving (Show, Eq, Generic, ToJSON)

-- | A name for a category or a series.
-- For accounts this comes from the report's display name, so it follows the report's tree/flat mode and depth.
data ChartLabel = ChartLabel
  { lbFull   :: Text  -- ^ the full name, eg a full account name; used in CSV/JSON and tooltips
  , lbShort  :: Text  -- ^ the name to display, eg a leaf account name in tree mode
  , lbIndent :: Int   -- ^ indentation level to display it with (0 for none)
  } deriving (Show, Eq, Generic, ToJSON)

-- | One chart area with its own y axis, holding series of values in a single unit.
data Panel = Panel
  { pnUnit      :: Amount     -- ^ the unit of all values in this panel, as a template amount whose quantity is ignored:
                              --   its commodity symbol and display style are used to show values and axis ticks.
                              --   Eg a currency, @%@ (as produced by --percent), or no commodity with precision 0 for counts.
  , pnBarLayout :: BarLayout  -- ^ how this panel's bar series are arranged when there are several
  , pnSeries    :: [Series]   -- ^ the series, in display order (legend order)
  } deriving (Show, Eq, Generic, ToJSON)

-- | How several bar series in a panel are arranged at each x position.
data BarLayout
  = Stacked  -- ^ on top of one another; positive values stack above zero, negative values below
  | Grouped  -- ^ side by side
  deriving (Show, Eq, Generic, ToJSON)

-- | A named sequence of values, one per x position.
data Series = Series
  { seLabel  :: ChartLabel
  , seRole   :: SeriesRole
  , seMark   :: Mark
  , seValues :: [Maybe Quantity]  -- ^ one value per x position; Nothing means no value there (a gap, not zero)
  } deriving (Show, Eq, Generic, ToJSON)

-- | What a series represents, which renderers may show differently (eg a muted colour for 'SeriesOther').
data SeriesRole
  = SeriesItem   -- ^ an ordinary series, eg one account
  | SeriesOther  -- ^ several items combined, eg "other (5 accounts)", to limit the number of series
  | SeriesTotal  -- ^ a total of other series, eg the net total of stacked bars, or net worth
  deriving (Show, Eq, Generic, ToJSON)

-- | How a series is drawn.
data Mark
  = MarkBar     -- ^ a bar from zero to the value
  | MarkLine    -- ^ a line joining the values (in text charts, drawn as bars)
  | MarkMarker  -- ^ a marker at the value, not joined, eg a net total over stacked bars, or a budget goal
  deriving (Show, Eq, Generic, ToJSON)

-- | A series' values, indexed by x position, for fast lookup by renderers.
type SeriesValues = Array Int (Maybe Quantity)

seriesValues :: Series -> SeriesValues
seriesValues Series{seValues} = listArray (0, length seValues - 1) seValues

-- | The value at this x position, if there is one.
valueAt :: SeriesValues -> Int -> Maybe Quantity
valueAt a j = if inRange (bounds a) j then a ! j else Nothing

-- | If a chart's x axis has more than this many dates, group them into periods:
-- days, weeks, months, quarters or years, the shortest giving at most this many periods
-- (or years, if none does), labelled with hledger's usual period names. Each period shows a line's last value in it (eg an end balance),
-- or the sum of a bar's or marker's values. Other charts are returned unchanged.
-- Useful for drawing a long register as text, one row per period.
groupDates :: Int -> Chart -> Chart
groupDates maxn chart@Chart{chXAxis = XDates ds, chPanels}
  | length ds > maxn =
      let grouping = fromMaybe lastgrouping $ find ((<= maxn) . length . groupsBy) groupings
          groups = groupsBy grouping
      in chart
        { chXAxis  = XPeriods [ (spn, showDateSpan spn)
                              | g <- groups, (_, d) <- take 1 g, let (start, end) = grouping d, let spn = DateSpan (Just $ Exact start) (Just $ Exact end) ]
        , chPanels = [ p{pnSeries = map (regroup groups) (pnSeries p)} | p <- chPanels ]
        }
  where
    indexed = zip [0 :: Int ..] ds
    groupsBy grouping = groupBy ((==) `on` (fst . grouping . snd)) indexed
    regroup groups s@Series{seMark} =
      let vals = seriesValues s
          combine = case seMark of
            MarkLine -> listToMaybe . reverse
            _        -> \qs -> if null qs then Nothing else Just (sum qs)
      in s{seValues = [ combine $ mapMaybe (valueAt vals . fst) g | g <- groups ]}
    -- each grouping gives a date's period: its start date and end date (exclusive)
    groupings = [byday, byweek, bymonth, byquarter, byyear]
    lastgrouping = byyear
    byday d = (d, addDays 1 d)
    byweek d = let (_, _, wd) = toWeekDate d; s = addDays (fromIntegral $ 1 - wd) d in (s, addDays 7 s)
    bymonth d = let (y, m, _) = toGregorian d in (fromGregorian y m 1, addGregorianMonthsClip 1 $ fromGregorian y m 1)
    byquarter d = let (y, m, _) = toGregorian d; s = fromGregorian y (3 * ((m - 1) `div` 3) + 1) 1 in (s, addGregorianMonthsClip 3 s)
    byyear d = let (y, _, _) = toGregorian d in (fromGregorian y 1 1, fromGregorian (y + 1) 1 1)
groupDates _ chart = chart

-- | Render a chart's data as CSV (or TSV) records, in long ("tidy") form: one record per value,
-- with a header record. This shows exactly what the chart shows, after any combining of series,
-- and can be charted with other tools.
--
-- Values are shown with the panel unit's display precision, without commodity symbol or digit group marks.
-- A gap (no value) is shown as an empty field.
chartAsCsv :: Chart -> CSV
chartAsCsv Chart{chXAxis, chPanels} =
  ["commodity", "series", "role", "mark", "x", "value"]
  : [ [acommodity pnUnit, lbFull (seLabel s), roleName (seRole s), markName (seMark s), x, maybe "" (showValue pnUnit) mq]
    | Panel{pnUnit, pnSeries} <- chPanels
    , s <- pnSeries
    , (x, mq) <- zip xlabels (seValues s)
    ]
  where
    xlabels = case chXAxis of
      XCategories ls -> map lbFull ls
      XPeriods ps    -> map snd ps
      XDates ds      -> map showDate ds
    showValue unit q = T.pack $ showAmountWith machineFmt{displayCommodity=False} unit{aquantity=q}
    roleName r = case r of
      SeriesItem  -> "item"
      SeriesOther -> "other"
      SeriesTotal -> "total"
    markName m = case m of
      MarkBar    -> "bar"
      MarkLine   -> "line"
      MarkMarker -> "marker"

tests_Hledger_Write_Chart :: TestTree
tests_Hledger_Write_Chart = testGroup "Write.Chart" [
   testCase "groupDates" $ do
     let lbl t = ChartLabel t t 0
         chart = Chart "" (XDates [fromGregorian 2024 1 5, fromGregorian 2024 1 20, fromGregorian 2024 2 3])
                   [Panel nullamt Grouped
                     [ Series (lbl "balance") SeriesItem MarkLine [Just 1, Just 2, Just 3]
                     , Series (lbl "change") SeriesItem MarkBar [Just 1, Just 1, Nothing] ]]
         Chart{chXAxis, chPanels} = groupDates 2 chart
     case chXAxis of
       XPeriods ps -> map snd ps @?= ["2024-01", "2024-02"]
       _           -> assertFailure "expected periods"
     map seValues (concatMap pnSeries chPanels) @?= [[Just 2, Just 3], [Just 2, Nothing]]
     groupDates 3 chart @?= chart
  ]
