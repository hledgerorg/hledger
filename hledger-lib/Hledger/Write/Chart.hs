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

{-# LANGUAGE CPP #-}
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
  Summary(..),
  SummaryKind(..),
  Colour(..),
  seriesColours,
  stableSlots,
  seriesSize,
  maxTints,
  mainAccountType,
  SeriesValues,
  isContra,
  seriesValues,
  valueAt,
  setChartScales,
  setChartLayout,
  scaleSpans,
  chartAsCsv,
  tests_Hledger_Write_Chart,
) where

import Control.Applicative ((<|>))
import Data.Bits (xor)
import Data.Char (ord)
import Data.List (find, nub, sortOn)
#if !MIN_VERSION_base(4,20,0)
import Data.List (foldl')
#endif
import Data.Map qualified as M
import Data.Maybe (catMaybes, fromMaybe, isJust, listToMaybe)
import Data.Ord (Down(..))
import Data.Set qualified as S
import Data.Word (Word32)

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
  , lbAccount :: Bool               -- ^ does this name an account (or accounts) ? Otherwise it's something else, eg a total.
  } deriving (Show, Eq, Generic, ToJSON)

-- | One chart area with its own y axis, holding series of values in a single unit.
data Panel = Panel
  { pnUnit      :: Amount     -- ^ the unit of all values in this panel, as a template amount whose quantity is ignored:
                              --   its commodity symbol and display style are used to show values and axis ticks.
                              --   Eg a currency, @%@ (as produced by --percent), or no commodity with precision 0 for counts.
  , pnSeries    :: [Series]   -- ^ the series, in display order (legend order)
  , pnGroupNames :: [Text]    -- ^ names for the groups of series, by group number (see 'seGroup'), if they have names;
                              --   eg a compound report's section titles. Text charts show them.
  , pnScale     :: Maybe Quantity  -- ^ a fixed scale, if one was requested: the amount spanned by the chart (see 'scaleSpans'),
                              --   so that charts with the same scale are drawn at the same size per amount.
                              --   Otherwise the chart is scaled to fit its values.
  , pnLayout    :: BarLayout  -- ^ how to draw bars of several groups
  , pnCounts    :: Bool       -- ^ are the values counts of whole things (eg postings) ? Then text charts draw at most one cell per unit,
                              --   so that small counts are not magnified (unless a fixed scale is set).
  , pnSummary   :: [Summary]  -- ^ values summarising the whole chart, shown below it (eg with -T and -A, the total and the average per period)
  } deriving (Show, Eq, Generic, ToJSON)

-- | A value summarising a panel's values over the whole x axis, such as their total or their average.
data Summary = Summary
  { suKind  :: SummaryKind
  , suLabel :: Text    -- ^ its name, as the report's table would show it (eg "Total", "Average")
  , suValue :: Amount  -- ^ its value, with its own display style (eg an average of counts has a decimal place)
  } deriving (Show, Eq, Generic, ToJSON)

data SummaryKind
  = SummaryTotal    -- ^ the total of all x positions' values
  | SummaryAverage  -- ^ the average per x position, which SVG charts also draw as a line across the plot
  deriving (Show, Eq, Generic, ToJSON)

-- | How to draw the bars of a panel whose series are in several groups (eg a compound report's sections).
data BarLayout
  = Diverging  -- ^ all groups stacked in one bar at each x position, positive values above (or right of) zero and negative ones below
  | Grouped    -- ^ each group stacked in its own bar, the groups' bars side by side (in text, a row per group), with the total marked separately;
               --   values are shown with their usual sign as positive (see 'setChartLayout')
  deriving (Show, Eq, Generic, ToJSON)

-- | A named sequence of values, one per x position.
data Series = Series
  { seLabel  :: ChartLabel
  , seRole   :: SeriesRole
  , seMark   :: Mark
  , seValues :: [Maybe Quantity]  -- ^ one value per x position; Nothing means no value there (a gap, not zero).
                                  --   At each x position, bar series' values are stacked: positive values above zero, negative values below.
  , seGroup  :: Int               -- ^ which group this series belongs to (eg its section, in a compound report chart; otherwise 0).
                                  --   Groups are stacked together, or drawn side by side, as the panel's 'pnLayout' says.
  , seSign   :: Int               -- ^ the usual sign of this series' values, if it has one (1 or -1; otherwise 0).
                                  --   Values of the opposite sign are contra amounts, which renderers may show distinctly;
                                  --   eg a refund (negative expense) in a compound report chart.
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

-- | Is this value of the series a contra amount (of the opposite sign to the series' usual sign) ?
isContra :: Series -> Quantity -> Bool
isContra s q = seSign s /= 0 && q /= 0 && signum q /= fromIntegral (seSign s)

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

-- | How many categorical colours renderers provide (see 'IndexColour').
categoricalColours :: Int
categoricalColours = 8

-- | Colours for a panel's series, in order. When the panel's accounts are of several known types, each gets its main type's hue,
-- in one of several tints (repeating when there are more than 'maxTints' of a type). Otherwise (when their types are all the same,
-- so the type's hue would tell nothing, or unknown) they get categorical colours.
-- A lone series which is not an account (eg a total) gets a neutral colour.
--
-- The tints and categorical colours are chosen by the series' names, not their positions or number (see 'stableSlots'),
-- so that an account keeps its colour in other charts: eg after removing other accounts (even down to just one), or sorting differently.
seriesColours :: [Series] -> [Colour]
seriesColours series = zipWith colour series' slots
  where
    series'
      | M.size typecounts <= 1 = [s{seLabel = (seLabel s){lbType = Nothing}} | s <- series]
      | otherwise = series
    typecounts = M.fromListWith (+) [(t, 1 :: Int) | s <- series, seRole s == SeriesItem, Just t <- [typeOf s]]
    typeOf s = mainAccountType <$> lbType (seLabel s)
    onlyone = length [s | s <- series, seRole s /= SeriesTotal] == 1
    -- each series' slot among the other ordinary series of its type (or with no type)
    slots = [ fromMaybe 0 $ M.lookup i slotmap | i <- [0 .. length series' - 1] ]
    slotmap = M.fromList $ concat
      [ zip is $ stableSlots (if isJust t then maxTints else categoricalColours) [(lbFull $ seLabel s, seriesSize s) | s <- ss]
      | t <- nub $ map typeOf ordinary
      , let (is, ss) = unzip [(i, s) | (i, s) <- zip [0 :: Int ..] series', seRole s == SeriesItem, typeOf s == t] ]
    ordinary = [s | s <- series', seRole s == SeriesItem]
    colour s k = case (seRole s, typeOf s) of
      (SeriesTotal, _) -> TotalColour
      (SeriesOther, _) -> OtherColour
      (_, Just t)      -> TypeColour t k
      (_, Nothing)
        | onlyone && not (lbAccount $ seLabel s) -> NeutralColour
        | otherwise    -> IndexColour k

-- | A series' size, for ranking: the sum of its absolute values.
seriesSize :: Series -> Quantity
seriesSize = sum . map abs . catMaybes . seValues

-- | Give each of these names one of n slots (0 to n-1), chosen by the name rather than its position,
-- so that a name tends to get the same slot in other lists: eg a colour that stays with an account in successive charts.
-- Each name has its own order of preference for the slots (from a hash of it), and gets the first one still free.
-- The names choose in order of their sizes (largest first; then by name), so that adding or removing small items
-- (or removing the largest) disturbs few others; positions don't matter.
-- When there are more names than slots, some slots are shared.
stableSlots :: Ord a => Int -> [(Text, a)] -> [Int]
stableSlots n items
  | n <= 0    = map (const 0) items
  | otherwise = [ fromMaybe 0 $ M.lookup i assigned | i <- [0 .. length items - 1] ]
  where
    assigned = snd $ foldl' place (S.empty, M.empty) $ sortOn (\(i, (nm, size)) -> (Down size, nm, i)) $ zip [0 :: Int ..] items
    place (used, m) (i, (nm, _)) =
      let prefs = preferences nm
          slot = fromMaybe (fromMaybe 0 $ listToMaybe prefs) $ find (`S.notMember` used) prefs
      in (S.insert slot used, M.insert i slot m)
    -- a name's slots, in its order of preference
    preferences nm = sortOn (\k -> fnv1a (nm <> "/" <> T.pack (show k))) [0 .. n - 1]
    -- a simple, stable hash (FNV-1a, 32 bit)
    fnv1a :: Text -> Word32
    fnv1a = T.foldl' (\h c -> (h `xor` fromIntegral (ord c)) * 16777619) 2166136261

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

-- | Set the bar layout of every panel to this one, if given (otherwise keeping each panel's own), and prepare the panels for it.
-- This should be applied before drawing a chart, or showing its data.
-- The grouped layout is for comparing the groups' sizes, so its series are shown with their usual sign as positive
-- (eg expenses as well as revenues upward, like a compound report's tables), and their contra amounts as negative.
-- (Applying this again does nothing more, since those series' usual sign is then positive.)
setChartLayout :: Maybe BarLayout -> Chart -> Chart
setChartLayout ml chart = chart{chPanels = map setlayout $ chPanels chart}
  where
    setlayout p = let l = fromMaybe (pnLayout p) ml in p{pnLayout = l, pnSeries = map (resign l) (pnSeries p)}
    resign Grouped s | seSign s /= 0 = s{seValues = map (fmap (* fromIntegral (seSign s))) (seValues s), seSign = 1}
    resign _ s = s

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
-- Each panel's summary values (see 'pnSummary') follow its series, with role "rowtotal" or "average", and no mark or x.
chartAsCsv :: Chart -> CSV
chartAsCsv Chart{chXAxis, chPanels} =
  ["commodity", "series", "role", "mark", "x", "value"]
  : concat
    [ [ [acommodity pnUnit, lbFull (seLabel s), roleName (seRole s), markName (seMark s), x, maybe "" (showValue pnUnit) mq]
      | s <- pnSeries
      , (x, mq) <- zip xlabels (seValues s)
      ]
      ++ [ [acommodity pnUnit, suLabel, summaryName suKind, "", "", showValue suValue (aquantity suValue)] | Summary{suKind, suLabel, suValue} <- pnSummary ]
    | Panel{pnUnit, pnSeries, pnSummary} <- chPanels
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
    summaryName k = case k of
      SummaryTotal   -> "rowtotal"
      SummaryAverage -> "average"

tests_Hledger_Write_Chart :: TestTree
tests_Hledger_Write_Chart = testGroup "Write.Chart" [
   testCase "scaleSpans" $ do
     scaleSpans 100 80 0 @?= (100 :: Quantity, 0)
     scaleSpans 100 0 30 @?= (0, 100)
     scaleSpans 100 50 30 @?= (70, 30)
     scaleSpans 100 150 50 @?= (75, 25)
     scaleSpans 100 0 0 @?= (100, 0)
  ,testCase "seriesColours" $ do
     let ser n t = Series (ChartLabel n n 0 t True) SeriesItem MarkBar [Just 1] 0 0
         tints cs = [k | TypeColour _ k <- cs]
     -- accounts of several types get their types' hues, in different tints; untyped series get categorical colours
     let cs = seriesColours [ser "e1" (Just Expense), ser "a" (Just Cash), ser "u1" Nothing, ser "e2" (Just Expense), ser "u2" Nothing]
     length [c | c@(TypeColour Asset _) <- cs] @?= 1
     length (nub $ tints [c | c@(TypeColour Expense _) <- cs]) @?= 2
     length (nub [k | IndexColour k <- cs]) @?= 2
     -- colours follow the accounts, not their positions
     seriesColours [ser "e2" (Just Expense), ser "e1" (Just Expense)] @?= reverse (seriesColours [ser "e1" (Just Expense), ser "e2" (Just Expense)])
     -- accounts all of one type get categorical colours, all different
     let rs = seriesColours [ser (T.pack $ show i) (Just Revenue) | i <- [0 .. maxTints]]
     length (nub [k | IndexColour k <- rs]) @?= maxTints + 1
     -- and keep them when fewer are shown, down to one
     seriesColours (take 1 [ser (T.pack $ show i) (Just Revenue) | i <- [0 .. maxTints]]) @?= take 1 rs
     -- a lone series which is not an account gets a neutral colour; others and totals get theirs
     seriesColours [(ser "u" Nothing){seLabel = ChartLabel "u" "u" 0 Nothing False}] @?= [NeutralColour]
     seriesColours [(ser "o" Nothing){seRole = SeriesOther}, (ser "t" Nothing){seRole = SeriesTotal}]
       @?= [OtherColour, TotalColour]
  ,testCase "stableSlots" $ do
     let items = [("a", 3), ("b", 2), ("c", 1)] :: [(Text, Int)]
         slots = stableSlots 8 items
     length (nub slots) @?= 3                       -- different slots, while there are enough
     stableSlots 8 (reverse items) @?= reverse slots  -- positions don't matter
     all (`elem` [0 .. 7]) slots @?= True
     length (nub $ stableSlots 2 items) @?= 2         -- more items than slots: they share them
     stableSlots 0 items @?= [0, 0, 0]
  ]
