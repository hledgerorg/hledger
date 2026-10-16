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
  chartAsCsv,
) where

import Data.Aeson (ToJSON)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Time (Day)
import GHC.Generics (Generic)

import Hledger.Data.Amount (AmountFormat(..), machineFmt, showAmountWith)
import Hledger.Data.Dates (showDate)
import Hledger.Data.Json ()
import Hledger.Data.Types (Amount(..), DateSpan, Quantity)
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
