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
  Series(..),
  SeriesRole(..),
  Mark(..),
  Colour(..),
  seriesColours,
  maxTints,
  mainAccountType,
  SeriesValues,
  seriesValues,
  valueAt,
  setChartScales,
  scaleSpans,
  chartAsCsv,
  tests_Hledger_Write_Chart,
) where

import Control.Applicative ((<|>))
import Data.Map qualified as M
import Data.List (find)
import Data.Maybe (fromMaybe)

import Data.Array (Array, bounds, inRange, listArray, (!))

import Data.Aeson (ToJSON)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Time (Day)
import GHC.Generics (Generic)

import Hledger.Data.Amount (AmountFormat(..), machineFmt, showAmountWith)
import Hledger.Data.Dates (showDate)
import Hledger.Data.Json ()
import Hledger.Data.AccountType (isAccountSubtypeOf)
import Hledger.Data.Types (AccountType(..), Amount(..), DateSpan(..), Quantity)
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
  { lbFull   :: Text                -- ^ the full name, eg a full account name; used in CSV/JSON and tooltips
  , lbShort  :: Text                -- ^ the name to display, eg a leaf account name in tree mode
  , lbIndent :: Int                 -- ^ indentation level to display it with (0 for none)
  , lbType   :: Maybe AccountType   -- ^ the account type, if this names an account (or accounts) of a known type;
                                    --   charts colour accounts by their main type (see 'seriesColours')
  } deriving (Show, Eq, Generic, ToJSON)

-- | One chart area with its own y axis, holding series of values in a single unit.
data Panel = Panel
  { pnUnit      :: Amount     -- ^ the unit of all values in this panel, as a template amount whose quantity is ignored:
                              --   its commodity symbol and display style are used to show values and axis ticks.
                              --   Eg a currency, @%@ (as produced by --percent), or no commodity with precision 0 for counts.
  , pnSeries    :: [Series]   -- ^ the series, in display order (legend order)
  , pnStackLabels :: [Text]   -- ^ names for the stacks, by stack number (see 'seStack'), if they have names;
                              --   eg a compound report's section titles. Text charts show them.
  , pnScale     :: Maybe Quantity  -- ^ a fixed scale, if one was requested: the amount spanned by the chart (see 'scaleSpans'),
                              --   so that charts with the same scale are drawn at the same size per amount.
                              --   Otherwise the chart is scaled to fit its values.
  } deriving (Show, Eq, Generic, ToJSON)

-- | A named sequence of values, one per x position.
data Series = Series
  { seLabel  :: ChartLabel
  , seRole   :: SeriesRole
  , seMark   :: Mark
  , seValues :: [Maybe Quantity]  -- ^ one value per x position; Nothing means no value there (a gap, not zero)
  , seStack  :: Int               -- ^ which stack this series' bars belong to. At each x position, bars of the same stack
                                  --   are stacked (positive values above zero, negative values below), and stacks are drawn
                                  --   side by side, in order. Eg 0 for all series in a balance chart; a section's number
                                  --   in a compound report chart, so that its accounts are stacked but sections are not.
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

-- | The main account type (asset, liability, equity, revenue or expense) of an account type, which is one of those or a subtype of one.
mainAccountType :: AccountType -> AccountType
mainAccountType t = fromMaybe t $ find (t `isAccountSubtypeOf`) [Asset, Liability, Equity, Revenue, Expense]

-- | How a series (or a bar) is coloured, in a renderer-independent way.
data Colour
  = TypeColour AccountType Int  -- ^ the conventional hue of this main account type, in its Nth tint (to distinguish several of that type)
  | IndexColour Int             -- ^ the Nth categorical colour, for series with no account type
  | NeutralColour               -- ^ a neutral colour, for a chart's only series when it has no account type
  | OtherColour                 -- ^ a muted colour, for a series combining several items
  | TotalColour                 -- ^ the ink (text) colour, for a total
  deriving (Show, Eq)

-- | How many tints of a type's colour renderers provide, to distinguish several accounts of one type.
maxTints :: Int
maxTints = 4

-- | Colours for a panel's series, in order: accounts of a known type get their main type's hue,
-- tinted differently for each of that type in the panel (the tints repeat after 'maxTints');
-- other ordinary series get categorical colours in order, or a neutral colour if there's only one series.
-- If all the accounts are of one type (so the type's colour tells nothing) and there are more of them than tints
-- (so they would not all be distinguishable), they get categorical colours instead.
seriesColours :: [Series] -> [Colour]
seriesColours series
  | M.size typecounts == 1 && any (> maxTints) (M.elems typecounts) = go M.empty 0 [s{seLabel = (seLabel s){lbType = Nothing}} | s <- series]
  | otherwise = go M.empty 0 series
  where
    typecounts = M.fromListWith (+) [(t, 1 :: Int) | s <- series, seRole s == SeriesItem, Just t <- [mainAccountType <$> lbType (seLabel s)]]
    onlyone = length [s | s <- series, seRole s /= SeriesTotal] == 1
    go :: M.Map AccountType Int -> Int -> [Series] -> [Colour]
    go _ _ [] = []
    go tints n (s:ss) = case (seRole s, mainAccountType <$> lbType (seLabel s)) of
      (SeriesTotal, _) -> TotalColour : go tints n ss
      (SeriesOther, _) -> OtherColour : go tints n ss
      (_, Just t)      -> let k = M.findWithDefault 0 t tints in TypeColour t k : go (M.insert t (k + 1) tints) n ss
      (_, Nothing)
        | onlyone      -> NeutralColour : go tints n ss
        | otherwise    -> IndexColour n : go tints (n + 1) ss

-- | A series' values, indexed by x position, for fast lookup by renderers.
type SeriesValues = Array Int (Maybe Quantity)

seriesValues :: Series -> SeriesValues
seriesValues Series{seValues} = listArray (0, length seValues - 1) seValues

-- | The value at this x position, if there is one.
valueAt :: SeriesValues -> Int -> Maybe Quantity
valueAt a j = if inRange (bounds a) j then a ! j else Nothing

-- | Give each panel a fixed scale (see 'pnScale'): the absolute quantity of the scale amount in the panel's commodity,
-- or else of the one with no commodity symbol. When several are in the same commodity, the last one is used.
setChartScales :: [Amount] -> Chart -> Chart
setChartScales scales chart = chart{chPanels = map setscale $ chPanels chart}
  where
    setscale p = p{pnScale = lookup (acommodity $ pnUnit p) byc <|> lookup "" byc <|> pnScale p}
    byc = reverse [(acommodity a, abs $ aquantity a) | a <- scales]

-- | With a fixed scale (the amount that a chart spans), and the largest positive and (absolute) negative extents of the values,
-- how much of the scale is given to each direction: (above or right of zero, below or left of zero).
-- Negative values get the room they need and positive values the rest (all of it if there are no negative values;
-- if there are only negative values, they get all of it).
-- If the values don't fit, both directions are shrunk in proportion, and the values beyond them will be clipped.
scaleSpans :: (Ord a, Fractional a) => a -> a -> a -> (a, a)
scaleSpans scale maxpos maxneg
  | maxpos <= 0 && maxneg > 0  = (0, scale)
  | maxpos + maxneg <= scale   = (scale - maxneg, maxneg)
  | otherwise                  = (scale - neg, neg)
  where neg = maxneg * scale / (maxpos + maxneg)

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
   testCase "scaleSpans" $ do
     scaleSpans 100 80 0 @?= (100 :: Quantity, 0)
     scaleSpans 100 0 30 @?= (0, 100)
     scaleSpans 100 50 30 @?= (70, 30)
     scaleSpans 100 150 50 @?= (75, 25)
     scaleSpans 100 0 0 @?= (100, 0)
  ,testCase "seriesColours" $ do
     let ser t = Series (ChartLabel "" "" 0 t) SeriesItem MarkBar [] 0
     seriesColours [ser (Just Expense), ser (Just Cash), ser Nothing, ser (Just Expense), ser Nothing]
       @?= [TypeColour Expense 0, TypeColour Asset 0, IndexColour 0, TypeColour Expense 1, IndexColour 1]
     -- more series of one type than tints: all get categorical colours
     seriesColours (replicate (maxTints + 1) (ser (Just Revenue)))
       @?= map IndexColour [0 .. maxTints]
     -- but with several types, the type colours are kept, and the tints repeat
     seriesColours (ser (Just Asset) : replicate (maxTints + 1) (ser (Just Revenue)))
       @?= TypeColour Asset 0 : [TypeColour Revenue k | k <- [0 .. maxTints]]
     -- a single series with no type gets a neutral colour
     seriesColours [ser Nothing] @?= [NeutralColour]
  ]
