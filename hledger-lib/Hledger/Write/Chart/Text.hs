{- |
Draw a 'Chart' as text, for terminals.

Every chart is drawn as horizontal bars, one row per x position (or, with several stacks, one row per stack per x position,
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
  ColourMode(..),
  StyledLine,
  chartAsStyledLines,
  styledLinesAsText,
  tests_Hledger_Write_Chart_Text,
) where

import Data.List (find, nub)
#if !MIN_VERSION_base(4,20,0)
import Data.List (foldl')
#endif
import Data.Maybe (fromMaybe, isJust, isNothing, mapMaybe)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Lazy qualified as TL
import Safe (atMay, maximumDef)
import Data.Colour.SRGB (sRGB24read)
import System.Console.ANSI (Color(..), ColorIntensity(..), ConsoleLayer(..), SGR(..), setSGRCode)
import Text.DocLayout (realLength)

import Hledger.Data.Amount (nullamt, oneLineNoCostFmt, showAmountWith)
import Hledger.Data.Dates (showDate)
import Hledger.Data.Types (AccountType(..), Amount(..), Quantity)
import Hledger.Utils.IO (color, faint')
import Hledger.Utils.Test
import Hledger.Utils.Text (fitText)
import Hledger.Write.Chart
import Hledger.Write.Chart.Palette (colourHex)


-- | Options for drawing a text chart.
data TextChartOpts = TextChartOpts
  { tcWidth   :: Int   -- ^ the width to fill, in characters (eg the terminal width)
  , tcUnicode :: Bool  -- ^ use unicode block characters (otherwise ASCII)
  }

-- | How a piece of text should be shown.
data Style
  = StylePlain
  | StyleSeries Int  -- ^ the colour of the Nth ordinary series in a panel
  | StyleType AccountType Int  -- ^ the colour of a main account type, in its Nth variant
  | StyleOther       -- ^ the colour of a series combining several items ("other")
  | StyleNegative    -- ^ a negative value
  deriving (Show, Eq)

-- | A line of text made of styled pieces.
type StyledLine = [(Style, Text)]

-- | How to colour a text chart.
data ColourMode
  = NoColour
  | BasicColour     -- ^ with the terminal's basic ANSI colours (whose exact shades depend on its colour theme)
  | RgbColour Bool  -- ^ with exact 24-bit colours, the same as SVG charts'; their variants for a dark background if true
  deriving (Show, Eq)

-- | Render styled lines as text, with ANSI colours or without.
styledLinesAsText :: ColourMode -> [StyledLine] -> TL.Text
styledLinesAsText mode = TL.fromChunks . concatMap (\l -> map piece l ++ ["\n"])
  where
    piece (st, t) = case mode of
      NoColour -> t
      BasicColour -> case st of
        StylePlain    -> t
        StyleSeries n -> T.pack $ uncurry color (cyclicAt (Dull, Blue) indexColours n) $ T.unpack t
        StyleType at n -> T.pack $ color (if even n then Dull else Vivid) (typeColour at) $ T.unpack t
        StyleOther    -> T.pack $ faint' $ T.unpack t
        StyleNegative -> negative t
      RgbColour dark -> case st of
        StylePlain    -> t
        StyleSeries n -> rgb (colourHex dark $ IndexColour n) t
        StyleType at n -> rgb (colourHex dark $ TypeColour at n) t
        StyleOther    -> rgb (colourHex dark OtherColour) t
        StyleNegative -> negative t
    -- negative values are red, as elsewhere in hledger's output
    negative t = T.pack $ color Dull Red $ T.unpack t
    rgb hex t = T.pack (setSGRCode [SetRGBColor Foreground $ sRGB24read $ T.unpack hex]) <> t <> T.pack (setSGRCode [])
    -- Conventional colours for the main account types, in the terminal's palette.
    typeColour at = case at of
      Asset     -> Blue
      Liability -> Yellow
      Equity    -> Magenta
      Revenue   -> Green
      Expense   -> Red
      _         -> Magenta
    -- For series of no account type. Avoiding red, used for negative values. Repeated after this many series (more than the usual series limit).
    indexColours =
      [(Dull, Blue), (Dull, Yellow), (Dull, Magenta), (Dull, Cyan), (Dull, Green), (Vivid, Blue), (Vivid, Yellow), (Vivid, Magenta)]

-- | Draw a chart as styled lines of text: the title (if any), then each panel,
-- with a heading naming its commodity when there are several (and it has a commodity symbol),
-- and a legend when it has several series (listing those that are visible: a series too small to fill a character cell is not).
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
  , rowSubLabel :: Text            -- ^ a second label, eg the name of the stack this row shows (empty for none)
  , rowValue    :: Maybe Quantity
  , rowSegments :: [(Style, Char, Quantity)]
  , rowMark     :: Maybe Quantity  -- ^ a value to mark with a vertical line (eg a net total), instead of bar segments
  }

panelLines :: TextChartOpts -> XAxis -> Bool -> Panel -> [StyledLine]
panelLines TextChartOpts{tcWidth, tcUnicode} xaxis showheading Panel{pnUnit, pnSeries, pnStackLabels, pnScale} =
  [[(StylePlain, acommodity pnUnit)] | showheading, not $ T.null $ acommodity pnUnit]
  ++ legend
  ++ map trimEnd rowlines
  where
    -- The series drawn as bars: all but totals (shown as the value) and markers (not drawn in text).
    drawn = [s | s <- pnSeries, seRole s /= SeriesTotal, seMark s /= MarkMarker]
    mtotal = find ((== SeriesTotal) . seRole) pnSeries
    single = length drawn == 1
    styled = zipWith3 seriesStyle [0 ..] (seriesColours drawn) drawn
    -- The stacks, in order (see 'seStack'). With several, each x position has a row for each stack,
    -- and the total is drawn as a mark on a row of its own, after them.
    -- each stack's name (if it has one) and series
    stacks = [ (fromMaybe "" $ pnStackLabels `atMay` k, [st | (st, s) <- zip styled drawn, seStack s == k]) | k <- nub $ map seStack drawn ]
    severalstacks = length stacks > 1
    marktotal = if severalstacks then mtotal else Nothing
    seriesStyle i colour s = (colourStyle colour, fillChar i, seriesValues s)
    colourStyle colour = case colour of
      TypeColour at k -> StyleType at k
      IndexColour k   -> StyleSeries k
      NeutralColour   -> StylePlain
      OtherColour     -> StyleOther
      TotalColour     -> StylePlain
    -- in a chart of categories (eg accounts) with a single series, each category's bar has its own account type's colour, if known
    categoryStyle j st = case (xaxis, single) of
      (XCategories ls, True) | Just l <- ls `atMay` j, Just at <- lbType l -> StyleType (mainAccountType at) 0
      _ -> st
    mtotalvals = seriesValues <$> mtotal
    fillChar i
      | tcUnicode = if single then '█' else cyclicAt '█' "█▓▒░" i
      | otherwise = if single then '#' else cyclicAt '#' "#=+:" i

    xlabels = case xaxis of
      XCategories ls -> [T.replicate (2 * lbIndent l) " " <> lbShort l | l <- ls]
      XPeriods ps    -> map snd ps
      XDates ds      -> map showDate ds
    segmentsAt j sers = [(categoryStyle j st, c, q) | (st, c, vals) <- sers, Just q <- [valueAt vals j], q /= 0]

    rows
      | severalstacks =  -- a row for each stack, showing its sum, with the x label on the first; then the total's mark
        concat
          [ [ Row (if k == 0 then lbl else "") name (stackSum j stk) (segmentsAt j stk) Nothing
            | (k, (name, stk)) <- zip [0 :: Int ..] stacks ]
            ++ [ Row "" (lbShort $ seLabel t) (valueAt tvals j) [] (valueAt tvals j) | Just t <- [marktotal], let tvals = seriesValues t ]
          | (j, lbl) <- zip [0 ..] xlabels ]
      | otherwise =
        [ Row lbl "" rowval (segmentsAt j styled) Nothing
        | (j, lbl) <- zip [0 ..] xlabels
        , let rowval = case (mtotalvals, styled) of
                (Just tvals, _)     -> valueAt tvals j
                (_, [(_, _, vals)]) -> valueAt vals j
                _                   -> Nothing
        -- categories with no values at all (eg accounts without this commodity) are left out
        , not (isCategories && all (\(_, _, vals) -> isNothing $ valueAt vals j) styled)
        ]
    isCategories = case xaxis of XCategories _ -> True; _ -> False
    stackSum j stk = case mapMaybe (\(_, _, vals) -> valueAt vals j) stk of
      [] -> Nothing
      qs -> Just $ sum qs

    rowlines = map rowLine rows
    -- the styles of the bar segments actually drawn (a series too small to show at this scale has none)
    drawnstyles = nub [st | l <- rowlines, (st, t) <- l, st /= StylePlain, not $ T.null $ T.strip t]
    -- a legend for the series, omitting any not drawn
    legend
      | length drawn > 1 = wrapLegend (
          [ [(st, T.singleton c), (StylePlain, " " <> lbFull (seLabel s))] | ((st, c, _), s) <- zip styled drawn, st `elem` drawnstyles ]
          ++ [ [(StylePlain, markchar), (StylePlain, " " <> lbFull (seLabel t))] | Just t <- [marktotal] ]
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
    sublabelw = min (tcWidth `div` 4) $ maximumDef 0 $ map (realLength . rowSubLabel) rows
    valuew = maximumDef 0 [realLength (showValue q) | Row{rowValue = Just q} <- rows]
    hasvalues = any (isJust . rowValue) rows
    barw = max 10 $ tcWidth - (if labelw > 0 then labelw + 2 else 0) - (if sublabelw > 0 then sublabelw + 2 else 0) - (if hasvalues then valuew + 2 else 0)
    posTotal r = sum [q | (_, _, q) <- rowSegments r, q > 0] `max` maybe 0 (max 0) (rowMark r)
    negTotal r = sum [abs q | (_, _, q) <- rowSegments r, q < 0] `max` maybe 0 (abs . min 0) (rowMark r)
    maxpos = maximumDef 0 $ map posTotal rows
    maxneg = maximumDef 0 $ map negTotal rows
    hasaxis = maxneg > 0
    -- the amounts that fill each side: the largest there, or the parts of a fixed scale
    (posspan, negspan) = case pnScale of
      Just s | s > 0 -> scaleSpans s maxpos maxneg
      _              -> (maxpos, maxneg)
    area = if hasaxis then barw - 1 else barw
    -- cells per unit of value, shared by both sides
    scale :: Double
    scale = if posspan + negspan == 0 then 0 else fromIntegral area / realToFrac (posspan + negspan)
    leftw
      | not hasaxis = 0
      | otherwise   = round (fromIntegral area * realToFrac negspan / realToFrac (posspan + negspan) :: Double)
    rightw = area - leftw
    axischar = if tcUnicode then "│" else "|"
    markchar = if tcUnicode then "┃" else "!"
    -- marks for bars clipped at the right or left edge (beyond a fixed scale's span on that side)
    clippedRight q = isJust pnScale && q > posspan
    clippedLeft q  = isJust pnScale && q > negspan
    clipright = if tcUnicode then "▸" else ">"
    clipleft  = if tcUnicode then "◂" else "<"

    -- the label column, value column and bars, separated by two spaces (columns with nothing in them are left out)
    rowLine r@Row{rowLabel, rowSubLabel, rowValue} =
      drop 1 $
      (if labelw > 0 then [(StylePlain, "  "), (StylePlain, fitText (Just labelw) (Just labelw) True True rowLabel)] else [])
      ++ (if sublabelw > 0 then [(StylePlain, "  "), (StylePlain, fitText (Just sublabelw) (Just sublabelw) True True rowSubLabel)] else [])
      ++ (if hasvalues
          then [(StylePlain, "  "), (maybe StylePlain valueStyle rowValue, fitText (Just valuew) Nothing False False $ maybe "" showValue rowValue)]
          else [])
      ++ [(StylePlain, "  ")]
      ++ case rowMark r of
           Just q  -> markLine q
           Nothing -> (if hasaxis then negativeBar r ++ [(StylePlain, axischar)] else []) ++ positiveBar r
    valueStyle q = if q < 0 then StyleNegative else StylePlain

    -- A mark at a value's position: right of the axis if positive, left of it if negative (or a clipped mark at the edge, if beyond it).
    markLine q
      | q >= 0 =
          let p = max 1 $ min rightw $ cells 1 q
          in [(StylePlain, T.replicate leftw " "), (StylePlain, if hasaxis then axischar else ""), (StylePlain, T.replicate (p - 1) " "), (StylePlain, if clippedRight q then clipright else markchar)]
      | otherwise =
          let p = max 1 $ min leftw $ cells 1 (abs q)
          in [(StylePlain, T.replicate (leftw - p) " "), (StylePlain, if clippedLeft (abs q) then clipleft else markchar), (StylePlain, T.replicate (p - 1) " "), (StylePlain, axischar)]

    -- The positive segments, growing right from the axis.
    -- A single segment uses eighth-block characters for finer resolution (in unicode mode); several use whole cells.
    positiveBar Row{rowSegments} = case [(st, c, q) | (st, c, q) <- rowSegments, q > 0] of
      [(st, c, q)] | tcUnicode && c == '█' && length rowSegments == 1 ->
        let eighths = cells 8 q
        in if clippedRight q
           then [(st, T.replicate (rightw - 1) "█" <> clipright)]
           else let e = min (rightw * 8) eighths in [(st, T.replicate (e `div` 8) "█" <> partialBlock (e `mod` 8))]
      segs -> segmentPieces rightw clippedRight (\t -> T.dropEnd 1 t <> clipright) segs
    -- The negative segments, growing left from the axis, first series nearest the axis.
    negativeBar Row{rowSegments} =
      let pieces = segmentPieces leftw clippedLeft (\t -> clipleft <> T.drop 1 t) [(st, c, abs q) | (st, c, q) <- rowSegments, q < 0]
          used = sum $ map (realLength . snd) pieces
      in (StylePlain, T.replicate (leftw - used) " ") : reverse pieces
    -- Segments as whole cells, rounding the cumulative boundaries so the total length is preserved, within a maximum width.
    -- If their total is clipped (by the given test), the outermost cell is replaced by a clip mark (with the given function).
    segmentPieces maxw clipped clip segs =
      let bounds = map (min maxw . cells 1) $ scanl1 (+) [q | (_, _, q) <- segs]
          widths = zipWith (-) bounds (0 : bounds)
          pieces = [(st, T.replicate w (T.singleton c)) | ((st, c, _), w) <- zip segs widths, w > 0]
      in case (reverse pieces, clipped $ sum [q | (_, _, q) <- segs]) of
           ((st, t) : rest, True) -> reverse ((st, clip t) : rest)
           _ -> pieces
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
     let lbl t = ChartLabel t t 0 Nothing
         chart = Chart "" (XCategories [lbl "a", lbl "b"])
                   [Panel nullamt [Series (lbl "s") SeriesItem MarkBar [Just 1, Just 2] 0] [] Nothing]
     map (T.concat . map snd) (chartAsStyledLines (TextChartOpts 20 True) chart)
       @?= ["a  1  ███████", "b  2  ██████████████"]
  ,testCase "mixed signs grow from an axis" $ do
     let lbl t = ChartLabel t t 0 Nothing
         chart = Chart "" (XCategories [lbl "a", lbl "b"])
                   [Panel nullamt [Series (lbl "s") SeriesItem MarkBar [Just (-1), Just 2] 0] [] Nothing]
     map (T.concat . map snd) (chartAsStyledLines (TextChartOpts 21 False) chart)
       @?= ["a  -1  ####|", "b   2      |#########"]
  ]
