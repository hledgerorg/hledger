{- |
A renderer-independent description of a chart, made from a report.

This is to charts what "Hledger.Write.Spreadsheet" is to tables:
each chart-capable report has an adapter that turns its report data into a 'Chart',
choosing a useful default chart for that report (see doc/SPEC-charts.md, "Smart defaults"),
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
  Colouring(..),
  chartColouring,
  stableSlots,
  stableSlotsFavouringFirst,
  seriesSize,
  maxTints,
  mainAccountType,
  SeriesValues,
  isContra,
  isHatched,
  totalIsBarEnd,
  totalsAreBarEnds,
  seriesValues,
  valueAt,
  setChartScales,
  setChartLayout,
  scaleSpans,
  chartAsCsv,
  tests_Hledger_Write_Chart,
) where

import Control.Applicative ((<|>))
import Data.Bits (shiftR, xor)
import Data.Char (ord)
import Data.List (find, nub, sortOn, transpose)
#if !MIN_VERSION_base(4,20,0)
import Data.List (foldl')
#endif
import Data.Map qualified as M
import Data.Maybe (catMaybes, fromMaybe, isJust, isNothing, listToMaybe)
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
  , pnValueLabels :: [Maybe Text]  -- ^ text to show at each x position (or none there), eg a holding's gain percent:
                                   --   in graphical charts instead of its value (which the axis shows), in text charts after it
                                   --   (in the negative style if it begins with -, in the revenue colour if with +).
                                   --   If empty, the values are shown as usual
  } deriving (Show, Eq, Generic, ToJSON)

-- | A value summarising a panel's values over the whole x axis, such as their total or their average.
data Summary = Summary
  { suKind  :: SummaryKind
  , suLabel :: Text    -- ^ its name, as the report's table would show it (eg "Total", "Average")
  , suValue :: Amount  -- ^ its value, with its own display style (eg an average of counts has a decimal place)
  } deriving (Show, Eq, Generic, ToJSON)

data SummaryKind
  = SummaryTotal    -- ^ the total of all x positions' values
  | SummaryAverage  -- ^ the average per x position, which SVG charts also draw as a line across the plot (with a legend entry)
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
  | SeriesShortfall  -- ^ an amount missing from what the bar stands for, eg the part of a holding's cost basis lost (beyond its value):
                     --   drawn hatched, in its place in the stack
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

-- | Is this value of the series drawn hatched ? Contra amounts are, and shortfalls (see 'SeriesShortfall').
isHatched :: Series -> Quantity -> Bool
isHatched s q = seRole s == SeriesShortfall || isContra s q

-- | Is this total, at every x position, just the end of these series' stacked bars (the sum of their positive values, or of their negative ones) ?
-- Then marking it would add nothing; otherwise (eg with values of both signs, or a total that isn't their sum) it is worth marking.
totalIsBarEnd :: [Series] -> Series -> Bool
totalIsBarEnd bars total = and $ totalsAreBarEnds bars total

-- | The same, at each x position (true where there is no total).
totalsAreBarEnds :: [Series] -> Series -> [Bool]
totalsAreBarEnds bars total =
  [ maybe True (\t -> t == sum (filter (> 0) qs) || t == sum (filter (< 0) qs)) mt
  | (mt, qs) <- zip (seValues total) (map catMaybes (transpose (map seValues bars)) ++ repeat []) ]

-- | The main account type (asset, liability, equity, revenue or expense) of an account type, which is one of those or a subtype of one.
mainAccountType :: AccountType -> AccountType
mainAccountType t = fromMaybe t $ find (t `isAccountSubtypeOf`) [Asset, Liability, Equity, Revenue, Expense]

-- | How a series (or a bar) is coloured, in a renderer-independent way.
data Colour
  = TypeColour AccountType Int  -- ^ the conventional hue of this main account type, in its Nth tint (to distinguish several of that type)
  | IndexColour Int             -- ^ the Nth categorical colour, for series with no account type
  | LoneColour                  -- ^ a hue that no account type uses, for a chart's only series when it is not an account,
                                --   or for an account of unknown type in a chart with one account per panel
  | NeutralColour               -- ^ a neutral colour, eg for the contra amounts legend swatch
  | OtherColour (Maybe AccountType)  -- ^ a muted colour, for a series combining several items: grey, tinged with their main account type's hue if any
  | TotalColour                 -- ^ the ink (text) colour, for a total
  deriving (Show, Eq)

-- | How many tints of a type's colour renderers provide, to distinguish several accounts of one type.
maxTints :: Int
maxTints = 4

-- | How many categorical colours renderers provide (see 'IndexColour').
categoricalColours :: Int
categoricalColours = 8

-- | How a chart's accounts are coloured (decided for the whole chart, so that colours mean the same in all of its panels).
data Colouring
  = ByName  -- ^ in distinct colours chosen by name, to tell them apart: when they are all of one type (whose hue would tell nothing), or of unknown type
  | ByType  -- ^ by main account type (in tints chosen by name): when they are of several types
  | Single  -- ^ by type, or if unknown in the lone colour: when each panel shows just one account, so there is nothing to tell apart
  deriving (Show, Eq)

-- | How this chart's accounts should be coloured: considering all of its panels, so that eg in a balance sheet,
-- a commodity's panel with just one asset account shows it in the assets' hue, like the other panels.
chartColouring :: Chart -> Colouring
chartColouring Chart{chPanels}
  | all ((<= 1) . length . filter ((/= SeriesTotal) . seRole) . pnSeries) chPanels = Single
  | S.size (S.fromList [mainAccountType t | p <- chPanels, s <- pnSeries p, seRole s `elem` [SeriesItem, SeriesShortfall], Just t <- [lbType $ seLabel s]]) > 1 = ByType
  | otherwise = ByName

-- | Colours for a panel's series, in order, for the chart's colouring (see 'chartColouring').
-- Coloured by type, each account of known type gets its main type's hue, in one of several tints
-- (repeating when there are more than 'maxTints' of a type). Otherwise, and accounts of unknown type, get categorical colours;
-- except that a lone series which is not an account (eg a total, or "..." for all accounts), or a lone account of unknown type
-- in a chart of single accounts, gets a hue that no account type uses.
--
-- The tints and categorical colours are chosen by the series' names, not their positions or number (see 'stableSlots'),
-- so that an account keeps its colour in other charts: eg after removing other accounts (even down to just one), or sorting differently.
-- A series of known type which is not an account (eg a holding's cost or gain) has its type's first tint,
-- so that its colour doesn't depend on its name (which may be translated).
seriesColours :: Colouring -> [Series] -> [Colour]
seriesColours colouring series = zipWith colour series' slots
  where
    series'
      | colouring == ByName = [s{seLabel = (seLabel s){lbType = Nothing}} | s <- series]
      | otherwise           = series
    typeOf s = mainAccountType <$> lbType (seLabel s)
    onlyone = length [s | s <- series, seRole s /= SeriesTotal] == 1
    -- each series' slot among the other ordinary series of its type (or with no type)
    slots = [ fromMaybe 0 $ M.lookup i slotmap | i <- [0 .. length series' - 1] ]
    slotmap = M.fromList $ concat
      [ zip is $ slotsfor t [(lbFull $ seLabel s, seriesSize s) | s <- ss]
      | t <- nub $ map (typeOf . snd) named
      , let (is, ss) = unzip [(i, s) | (i, s) <- named, typeOf s == t] ]
    -- the ordinary series which choose tints or categorical colours by name: accounts, and series of unknown type
    named = [(i, s) | (i, s) <- zip [0 :: Int ..] series', seRole s == SeriesItem, lbAccount (seLabel s) || isNothing (typeOf s)]
    -- a type's tints are chosen favouring the first, most saturated ones (the paler ones look washed out),
    -- so that they are used mainly when several accounts of the type need telling apart; categorical colours, without bias
    slotsfor t = if isJust t then stableSlotsFavouringFirst 0.5 maxTints else stableSlots categoricalColours
    colour s k = case (seRole s, typeOf s) of
      (SeriesTotal, _) -> TotalColour
      (SeriesOther, t) -> OtherColour t
      (_, Just t)
        | lbAccount (seLabel s) -> TypeColour t k
        | otherwise             -> TypeColour t 0
      (_, Nothing)
        | onlyone && (colouring == Single || not (lbAccount $ seLabel s)) -> LoneColour
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
stableSlots = stableSlotsFavouringFirst 0

-- | Like 'stableSlots', but with each name's preferences biased towards the first slots, by this much
-- (0: not at all; 1: fully, so that every name has the same order of preference).
-- Eg with 0.5, the last of 4 slots is never a name's first choice, and the first is its first choice most often.
stableSlotsFavouringFirst :: Ord a => Double -> Int -> [(Text, a)] -> [Int]
stableSlotsFavouringFirst bias n items
  | n <= 0    = map (const 0) items
  | otherwise = [ fromMaybe 0 $ M.lookup i assigned | i <- [0 .. length items - 1] ]
  where
    assigned = snd $ foldl' place (S.empty, M.empty) $ sortOn (\(i, (nm, size)) -> (Down size, nm, i)) $ zip [0 :: Int ..] items
    place (used, m) (i, (nm, _)) =
      let prefs = preferences nm
          slot = fromMaybe (fromMaybe 0 $ listToMaybe prefs) $ find (`S.notMember` used) prefs
      in (S.insert slot used, M.insert i slot m)
    -- a name's slots, in its order of preference
    -- (by the slot's position, if biased, plus a pseudo-random fraction from the name)
    preferences nm = sortOn (\k -> bias * fromIntegral k + fromIntegral (hash (nm <> "/" <> T.pack (show k))) / 2 ^ (32 :: Int)) [0 .. n - 1]
    -- a simple, stable hash: FNV-1a (32 bit), with murmur3's finaliser to mix in the last characters well
    -- (which here are the slot number; without it, names had only a few dozen orders of preference)
    hash :: Text -> Word32
    hash = fmix32 . T.foldl' (\h c -> (h `xor` fromIntegral (ord c)) * 16777619) 2166136261
    fmix32 h0 =
      let h1 = (h0 `xor` (h0 `shiftR` 16)) * 0x85ebca6b
          h2 = (h1 `xor` (h1 `shiftR` 13)) * 0xc2b2ae35
      in h2 `xor` (h2 `shiftR` 16)

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
      SeriesShortfall -> "shortfall"
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
  ,testCase "totalIsBarEnd" $ do
     let ser vs = Series (ChartLabel "s" "s" 0 Nothing True) SeriesItem MarkBar vs 0 0
     totalIsBarEnd [ser [Just 1, Just 2], ser [Just 3, Nothing]] (ser [Just 4, Just 2]) @?= True     -- the positive sums
     totalIsBarEnd [ser [Just (-1)], ser [Just (-3)]] (ser [Just (-4)]) @?= True                     -- the negative sum
     totalIsBarEnd [ser [Just 5], ser [Just (-3)]] (ser [Just 2]) @?= False                          -- values of both signs
     totalIsBarEnd [ser [Just 450], ser [Just 300]] (ser [Just 450]) @?= False                       -- a value within the bar
     totalsAreBarEnds [ser [Just 450, Just 450], ser [Just 300, Just 50]] (ser [Just 750, Just 450]) @?= [True, False]
     totalsAreBarEnds [ser [Just 1, Just 1]] (ser [Nothing, Just 2]) @?= [True, False]               -- no total, a total beyond the bar
  ,testCase "seriesColours" $ do
     let ser n t = Series (ChartLabel n n 0 t True) SeriesItem MarkBar [Just 1] 0 0
         tints cs = [k | TypeColour _ k <- cs]
     -- in a chart coloured by type, accounts get their types' hues, in different tints; untyped series get categorical colours
     let cs = seriesColours ByType [ser "e1" (Just Expense), ser "a" (Just Cash), ser "u1" Nothing, ser "e2" (Just Expense), ser "u2" Nothing]
     length [c | c@(TypeColour Asset _) <- cs] @?= 1
     length (nub $ tints [c | c@(TypeColour Expense _) <- cs]) @?= 2
     length (nub [k | IndexColour k <- cs]) @?= 2
     -- colours follow the accounts, not their positions
     seriesColours ByType [ser "e2" (Just Expense), ser "e1" (Just Expense)] @?= reverse (seriesColours ByType [ser "e1" (Just Expense), ser "e2" (Just Expense)])
     -- otherwise (eg when all accounts are of one type) accounts get categorical colours, all different
     let rs = seriesColours ByName [ser (T.pack $ show i) (Just Revenue) | i <- [0 .. maxTints]]
     length (nub [k | IndexColour k <- rs]) @?= maxTints + 1
     -- and keep them when fewer are shown, down to one
     seriesColours ByName (take 1 [ser (T.pack $ show i) (Just Revenue) | i <- [0 .. maxTints]]) @?= take 1 rs
     -- typed series which are not accounts (eg a holding's cost, gain and loss) get their types' first tints, whatever their names
     let nonacct n t = (ser n (Just t)){seLabel = ChartLabel n n 0 (Just t) False}
     seriesColours ByType [nonacct n t | (n, t) <- [("Kosten", Asset), ("Gewinn", Revenue), ("Verlust", Expense)]]
       @?= [TypeColour Asset 0, TypeColour Revenue 0, TypeColour Expense 0]
     -- a lone series which is not an account gets the lone colour; others and totals get theirs
     seriesColours ByName [(ser "u" Nothing){seLabel = ChartLabel "u" "u" 0 Nothing False}] @?= [LoneColour]
     seriesColours ByName [(ser "o" Nothing){seRole = SeriesOther}, (ser "t" Nothing){seRole = SeriesTotal}]
       @?= [OtherColour Nothing, TotalColour]
     -- in a chart of single accounts, a lone account has its type's hue, or if unknown the lone colour
     seriesColours Single [ser "e" (Just Expense)] @?= map (TypeColour Expense) (stableSlotsFavouringFirst 0.5 maxTints [("e", 1 :: Quantity)])
     seriesColours Single [ser "u" Nothing] @?= [LoneColour]
  ,testCase "stableSlots" $ do
     let items = [("a", 3), ("b", 2), ("c", 1)] :: [(Text, Int)]
         slots = stableSlots 8 items
     length (nub slots) @?= 3                       -- different slots, while there are enough
     stableSlots 8 (reverse items) @?= reverse slots  -- positions don't matter
     all (`elem` [0 .. 7]) slots @?= True
     length (nub $ stableSlots 2 items) @?= 2         -- more items than slots: they share them
     stableSlots 0 items @?= [0, 0, 0]
  ]
