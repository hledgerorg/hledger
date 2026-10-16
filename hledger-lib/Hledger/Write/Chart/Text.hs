{- |
Draw a 'Chart' as text, for terminals.

Every chart is drawn as horizontal bars, one row per x position (or, for grouped series, per series per x position,
with the total as a mark on a row of its own),
with an aligned value column before the bars. Several series in a stacked panel are drawn as stacked segments,
positive values growing right from a zero axis and negative values growing left.
Lines are drawn as bars too, since text has no good way to draw lines.

The output is a list of styled lines, so that different frontends can apply the styles in their own way:
'styledLinesAsText' turns them into plain or ANSI-coloured text.
-}

{-# LANGUAGE CPP #-}
{-# LANGUAGE OverloadedStrings #-}

module Hledger.Write.Chart.Text (
  TextChartOpts(..),
  Style(..),
  StyledLine,
  chartAsStyledLines,
  styledLinesAsText,
  tests_Hledger_Write_Chart_Text,
) where

import Data.List (find)
#if !MIN_VERSION_base(4,20,0)
import Data.List (foldl')
#endif
import Data.Maybe (fromMaybe, isJust, isNothing)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Lazy qualified as TL
import Safe (atMay, maximumDef)
import System.Console.ANSI (Color(..), ColorIntensity(..))
import Text.DocLayout (realLength)

import Hledger.Data.Amount (nullamt, oneLineNoCostFmt, showAmountWith)
import Hledger.Data.Dates (showDate)
import Hledger.Data.Types (Amount(..), Quantity)
import Hledger.Utils.IO (color, faint')
import Hledger.Utils.Test
import Hledger.Utils.Text (fitText)
import Hledger.Write.Chart


-- | Options for drawing a text chart.
data TextChartOpts = TextChartOpts
  { tcWidth   :: Int   -- ^ the width to fill, in characters (eg the terminal width)
  , tcUnicode :: Bool  -- ^ use unicode block characters (otherwise ASCII)
  }

-- | How a piece of text should be shown.
data Style
  = StylePlain
  | StyleSeries Int  -- ^ the colour of the Nth ordinary series in a panel
  | StyleOther       -- ^ the colour of a series combining several items ("other")
  | StyleNegative    -- ^ a negative value
  deriving (Show, Eq)

-- | A line of text made of styled pieces.
type StyledLine = [(Style, Text)]

-- | Render styled lines as text, with ANSI colours or without.
styledLinesAsText :: Bool -> [StyledLine] -> TL.Text
styledLinesAsText usecolour = TL.fromChunks . concatMap (\l -> map piece l ++ ["\n"])
  where
    piece (st, t)
      | usecolour = case st of
          StylePlain    -> t
          StyleSeries n -> T.pack $ uncurry color (cyclicAt (Dull, Blue) seriesColours n) $ T.unpack t
          StyleOther    -> T.pack $ faint' $ T.unpack t
          StyleNegative -> T.pack $ color Dull Red $ T.unpack t
      | otherwise = t
    -- Avoiding red, used for negative values. Repeated after this many series (more than the usual series limit).
    seriesColours =
      [(Dull, Blue), (Dull, Yellow), (Dull, Magenta), (Dull, Cyan), (Dull, Green), (Vivid, Blue), (Vivid, Yellow), (Vivid, Magenta)]

-- | Draw a chart as styled lines of text: the title (if any), then each panel,
-- with a heading naming its commodity when there are several (and it has a commodity symbol),
-- and a legend when it has several series.
-- A chart with many dates (more than 'maxDateRows', eg a long register) is drawn with one row per period instead (see 'groupDates').
chartAsStyledLines :: TextChartOpts -> Chart -> [StyledLine]
chartAsStyledLines opts chart =
  titlelines ++ concatMap (\(i, p) -> [[] | i > 0] ++ panelLines opts chXAxis (length chPanels > 1) p) (zip [0 :: Int ..] chPanels)
  where
    Chart{chTitle, chXAxis, chPanels} = groupDates maxDateRows chart
    titlelines = if T.null chTitle then [] else [[(StylePlain, chTitle)], []]

-- | The most dates a text chart shows one row each for; beyond this, they are grouped into periods.
maxDateRows :: Int
maxDateRows = 50

-- | A row of a text chart: a label, an optional value, and the bar segments (style, fill character, quantity).
data Row = Row
  { rowLabel    :: Text
  , rowValue    :: Maybe Quantity
  , rowSegments :: [(Style, Char, Quantity)]
  , rowMark     :: Maybe Quantity  -- ^ a value to mark with a vertical line (eg a net total), instead of bar segments
  }

panelLines :: TextChartOpts -> XAxis -> Bool -> Panel -> [StyledLine]
panelLines TextChartOpts{tcWidth, tcUnicode} xaxis showheading Panel{pnUnit, pnBarLayout, pnSeries} =
  [[(StylePlain, acommodity pnUnit)] | showheading, not $ T.null $ acommodity pnUnit]
  ++ legend
  ++ map (trimEnd . rowLine) rows
  where
    -- The series drawn as bars: all but totals (shown as the value) and markers (not drawn in text).
    drawn = [s | s <- pnSeries, seRole s /= SeriesTotal, seMark s /= MarkMarker]
    mtotal = find ((== SeriesTotal) . seRole) pnSeries
    single = length drawn == 1
    styled = zipWith seriesStyle [0 ..] drawn
    -- With several grouped series, the total is drawn as a mark on a row of its own, after them.
    groupedtotal = case (pnBarLayout, drawn, mtotal) of
      (Grouped, _:_:_, Just t) -> Just t
      _                        -> Nothing
    seriesStyle i s = (if seRole s == SeriesOther then StyleOther else StyleSeries i, fillChar i, seriesValues s)
    mtotalvals = seriesValues <$> mtotal
    fillChar i
      | tcUnicode = if single then '█' else cyclicAt '█' "█▓▒░" i
      | otherwise = if single then '#' else cyclicAt '#' "#=+:" i

    xlabels = case xaxis of
      XCategories ls -> [T.replicate (2 * lbIndent l) " " <> lbShort l | l <- ls]
      XPeriods ps    -> map snd ps
      XDates ds      -> map showDate ds
    segmentsAt j sers = [(st, c, q) | (st, c, vals) <- sers, Just q <- [valueAt vals j], q /= 0]

    rows = case (pnBarLayout, drawn) of
      (Grouped, _:_:_) ->  -- several grouped series: a row for each series, with the x label on the first
        concat
          [ [ Row (if k == 0 then lbl else "") (valueAt vals j) (segmentsAt j [ser]) Nothing
            | (k, ser@(_, _, vals)) <- zip [0 :: Int ..] styled ]
            ++ [ Row "" (valueAt tvals j) [] (valueAt tvals j) | Just t <- [groupedtotal], let tvals = seriesValues t ]
          | (j, lbl) <- zip [0 ..] xlabels ]
      _ ->
        [ Row lbl rowval (segmentsAt j styled) Nothing
        | (j, lbl) <- zip [0 ..] xlabels
        , let rowval = case (mtotalvals, styled) of
                (Just tvals, _)     -> valueAt tvals j
                (_, [(_, _, vals)]) -> valueAt vals j
                _                   -> Nothing
        -- categories with no values at all (eg accounts without this commodity) are left out
        , not (isCategories && all (\(_, _, vals) -> isNothing $ valueAt vals j) styled)
        ]
    isCategories = case xaxis of XCategories _ -> True; _ -> False

    legend
      | length drawn > 1 = wrapLegend (
          [ [(st, T.singleton c), (StylePlain, " " <> lbFull (seLabel s))] | ((st, c, _), s) <- zip styled drawn ]
          ++ [ [(StylePlain, markchar), (StylePlain, " " <> lbFull (seLabel t))] | Just t <- [groupedtotal] ]
          ) ++ [[]]
      | otherwise = []
    -- Lay out legend items left to right, two spaces apart, starting a new line when the next item won't fit.
    wrapLegend = reverse . foldl' addItem []
      where
        addItem [] item = [item]
        addItem (l:ls) item
          | lineWidth l + 2 + lineWidth item <= tcWidth = (l ++ [(StylePlain, "  ")] ++ item) : ls
          | otherwise = item : l : ls
        lineWidth = sum . map (realLength . snd)

    -- Column widths and scale.
    showValue q = T.pack $ showAmountWith oneLineNoCostFmt pnUnit{aquantity = q}
    labelw = min (tcWidth `div` 3) $ maximumDef 0 $ map (realLength . rowLabel) rows
    valuew = maximumDef 0 [realLength (showValue q) | Row{rowValue = Just q} <- rows]
    hasvalues = any (isJust . rowValue) rows
    barw = max 10 $ tcWidth - (if labelw > 0 then labelw + 2 else 0) - (if hasvalues then valuew + 2 else 0)
    posTotal r = sum [q | (_, _, q) <- rowSegments r, q > 0] `max` maybe 0 (max 0) (rowMark r)
    negTotal r = sum [abs q | (_, _, q) <- rowSegments r, q < 0] `max` maybe 0 (abs . min 0) (rowMark r)
    maxpos = maximumDef 0 $ map posTotal rows
    maxneg = maximumDef 0 $ map negTotal rows
    hasaxis = maxneg > 0
    area = if hasaxis then barw - 1 else barw
    -- cells per unit of value, shared by both sides
    scale :: Double
    scale = if maxpos + maxneg == 0 then 0 else fromIntegral area / realToFrac (maxpos + maxneg)
    leftw
      | not hasaxis = 0
      | otherwise   = round (fromIntegral area * realToFrac maxneg / realToFrac (maxpos + maxneg) :: Double)
    rightw = area - leftw
    axischar = if tcUnicode then "│" else "|"
    markchar = if tcUnicode then "┃" else "!"

    -- the label column, value column and bars, separated by two spaces (columns with nothing in them are left out)
    rowLine r@Row{rowLabel, rowValue} =
      drop 1 $
      (if labelw > 0 then [(StylePlain, "  "), (StylePlain, fitText (Just labelw) (Just labelw) True True rowLabel)] else [])
      ++ (if hasvalues
          then [(StylePlain, "  "), (maybe StylePlain valueStyle rowValue, fitText (Just valuew) Nothing False False $ maybe "" showValue rowValue)]
          else [])
      ++ [(StylePlain, "  ")]
      ++ case rowMark r of
           Just q  -> markLine q
           Nothing -> (if hasaxis then negativeBar r ++ [(StylePlain, axischar)] else []) ++ positiveBar r
    valueStyle q = if q < 0 then StyleNegative else StylePlain

    -- A mark at a value's position: right of the axis if positive, left of it if negative.
    markLine q
      | q >= 0 =
          let p = max 1 $ min rightw $ cells 1 q
          in [(StylePlain, T.replicate leftw " "), (StylePlain, if hasaxis then axischar else ""), (StylePlain, T.replicate (p - 1) " "), (StylePlain, markchar)]
      | otherwise =
          let p = max 1 $ min leftw $ cells 1 (abs q)
          in [(StylePlain, T.replicate (leftw - p) " "), (StylePlain, markchar), (StylePlain, T.replicate (p - 1) " "), (StylePlain, axischar)]

    -- The positive segments, growing right from the axis.
    -- A single segment uses eighth-block characters for finer resolution (in unicode mode); several use whole cells.
    positiveBar Row{rowSegments} = case [(st, c, q) | (st, c, q) <- rowSegments, q > 0] of
      [(st, _, q)] | tcUnicode && single ->
        let eighths = min (rightw * 8) $ cells 8 q
        in [(st, T.replicate (eighths `div` 8) "█" <> partialBlock (eighths `mod` 8))]
      segs -> segmentPieces rightw segs
    -- The negative segments, growing left from the axis, first series nearest the axis.
    negativeBar Row{rowSegments} =
      let pieces = segmentPieces leftw [(st, c, abs q) | (st, c, q) <- rowSegments, q < 0]
          used = sum $ map (realLength . snd) pieces
      in (StylePlain, T.replicate (leftw - used) " ") : reverse pieces
    -- Segments as whole cells, rounding the cumulative boundaries so the total length is preserved, within a maximum width.
    segmentPieces maxw segs =
      let bounds = map (min maxw . cells 1) $ scanl1 (+) [q | (_, _, q) <- segs]
          widths = zipWith (-) bounds (0 : bounds)
      in [(st, T.replicate w (T.singleton c)) | ((st, c, _), w) <- zip segs widths, w > 0]
    cells :: Int -> Quantity -> Int
    cells perunit q = round (realToFrac q * scale * fromIntegral perunit)
    partialBlock n = fromMaybe "" $ ["", "▏", "▎", "▍", "▌", "▋", "▊", "▉"] `atMay` n

-- | The Nth item of a list, repeating the list as needed; or the default if the list is empty.
cyclicAt :: a -> [a] -> Int -> a
cyclicAt d xs n = if null xs then d else fromMaybe d $ xs `atMay` (n `mod` length xs)

-- | Remove trailing spaces from a styled line.
trimEnd :: StyledLine -> StyledLine
trimEnd = reverse . dropSpaces . reverse
  where
    dropSpaces ((st, t) : rest)
      | T.null (T.stripEnd t) = dropSpaces rest
      | otherwise = (st, T.stripEnd t) : rest
    dropSpaces [] = []

tests_Hledger_Write_Chart_Text :: TestTree
tests_Hledger_Write_Chart_Text = testGroup "Write.Chart.Text" [
   testCase "trimEnd" $ do
     trimEnd [(StylePlain, "a "), (StylePlain, "  ")] @?= [(StylePlain, "a")]
     trimEnd [] @?= []
  ,testCase "single series, scaled to the width" $ do
     let lbl t = ChartLabel t t 0
         chart = Chart "" (XCategories [lbl "a", lbl "b"])
                   [Panel nullamt Grouped [Series (lbl "s") SeriesItem MarkBar [Just 1, Just 2]]]
     map (T.concat . map snd) (chartAsStyledLines (TextChartOpts 20 True) chart)
       @?= ["a  1  ███████", "b  2  ██████████████"]
  ,testCase "mixed signs grow from an axis" $ do
     let lbl t = ChartLabel t t 0
         chart = Chart "" (XCategories [lbl "a", lbl "b"])
                   [Panel nullamt Grouped [Series (lbl "s") SeriesItem MarkBar [Just (-1), Just 2]]]
     map (T.concat . map snd) (chartAsStyledLines (TextChartOpts 21 False) chart)
       @?= ["a  -1  ####|", "b   2      |#########"]
  ]
