{- |
Draw a 'Chart' as text, for terminals.

Every chart is drawn as horizontal bars, one row per x position,
with an aligned value column before the bars. Several series are drawn as stacked segments,
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

import Data.List (find, nub, sortOn)
#if !MIN_VERSION_base(4,20,0)
import Data.List (foldl')
#endif
import Data.Maybe (fromMaybe, isJust, isNothing)
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
  | StyleLone        -- ^ the colour of a chart's only series, when it is not an account
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
        StyleLone     -> T.pack $ color Dull Cyan $ T.unpack t
        StyleNegative -> negative t
      RgbColour dark -> case st of
        StylePlain    -> t
        StyleSeries n -> rgb (colourHex dark $ IndexColour n) t
        StyleType at n -> rgb (colourHex dark $ TypeColour at n) t
        StyleOther    -> rgb (colourHex dark OtherColour) t
        StyleLone     -> rgb (colourHex dark LoneColour) t
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
-- A chart of dates (eg a register) has a row per date, however many there are.
-- A chart with no panels (nothing to show, eg in an empty period) says so.
chartAsStyledLines :: TextChartOpts -> Chart -> [StyledLine]
chartAsStyledLines opts Chart{chTitle, chXAxis, chPanels} =
  titlelines ++ [[(StylePlain, "No data")] | null chPanels] ++ concatMap (\(i, p) -> [[] | i > 0] ++ panelLines opts chXAxis (length chPanels > 1) p) (zip [0 :: Int ..] chPanels)
  where
    titlelines = if T.null chTitle then [] else [[(StylePlain, chTitle)], []]

-- | A row of a text chart: a label, an optional value, and the bar segments (style, fill character, quantity).
data Row = Row
  { rowLabel    :: Text
  , rowSubLabel :: Text            -- ^ a second label, eg the name of the group this row shows (empty for none)
  , rowValue    :: Maybe Quantity
  , rowSegments :: [(Style, Char, Quantity)]
  , rowMark     :: Maybe Quantity  -- ^ a value to mark with a vertical line, over the bar segments if any (eg a net total)
  , rowSides    :: (Maybe Quantity, Maybe Quantity)  -- ^ in a diverging chart, the totals of the series usually right and left of the axis
  }

panelLines :: TextChartOpts -> XAxis -> Bool -> Panel -> [StyledLine]
panelLines TextChartOpts{tcWidth, tcUnicode} xaxis showheading Panel{pnUnit, pnSeries, pnGroupNames, pnScale, pnLayout, pnCounts, pnSummary} =
  [[(StylePlain, acommodity pnUnit)] | showheading, not $ T.null $ acommodity pnUnit]
  ++ legend
  ++ [trimEnd headerline | diverging, not $ all T.null [posname, negname, netname]]
  ++ map trimEnd rowlines
  ++ (if null pnSummary then [] else [[], [(StylePlain, summaryline)]])
  where
    -- the summary values, eg "Total 11, Average 0.9"
    summaryline = T.intercalate ", " [suLabel su <> " " <> T.pack (showAmountWith oneLineNoCostFmt $ suValue su) | su <- pnSummary]
    -- The series drawn as bars: all but totals (shown as the value) and markers (not drawn in text).
    drawn = [s | s <- pnSeries, seRole s /= SeriesTotal, seMark s /= MarkMarker]
    mtotal = find ((== SeriesTotal) . seRole) pnSeries
    single = length drawn == 1
    -- each series' style, fill character (chosen by its name, like its colour, so that it stays the same in other charts) and values
    styled = zipWith3 seriesStyle (stableSlots (length fillchars) [(lbFull $ seLabel s, seriesSize s) | s <- drawn]) (seriesColours drawn) drawn
    styledseries = zip styled drawn
    -- The groups of series (see 'seGroup'), in order, and each group's name and usual sign (if its series have one; otherwise 1).
    groups = nub $ map seGroup drawn
    groupName k = fromMaybe "" $ pnGroupNames `atMay` k
    groupSign k = fromMaybe 1 $ find (/= 0) [seSign s | s <- drawn, seGroup s == k]
    -- With the grouped layout and several groups (even if only one has series drawn here), each x position has a row for each group (named, showing its total),
    -- and the total is marked on a row of its own, after them.
    grouped = pnLayout == Grouped && length pnGroupNames > 1
    -- Otherwise, a chart with series with usual signs (see 'seSign'), and a total (eg of a compound report), is diverging:
    -- each row shows the totals of each side's groups at that end of the bar (with their names in a header line),
    -- and the total as a mark over the bar.
    -- In any chart, contra amounts (of the opposite sign to their series' usual sign) are drawn nearest the axis, with a hatched fill character.
    diverging = not grouped && isJust mtotal && any ((/= 0) . seSign) drawn
    marktotal = if diverging || grouped then mtotal else Nothing
    seriesStyle i colour s = (colourStyle colour, fillChar i, seriesValues s)
    colourStyle colour = case colour of
      TypeColour at k -> StyleType at k
      IndexColour k   -> StyleSeries k
      LoneColour      -> StyleLone
      NeutralColour   -> StylePlain
      OtherColour     -> StyleOther
      TotalColour     -> StylePlain
    -- in a chart of categories (eg accounts) with a single series, each category's bar has its own account type's colour, if known
    categoryStyle j st = case (xaxis, single) of
      (XCategories ls, True) | Just l <- ls `atMay` j, Just at <- lbType l -> StyleType (mainAccountType at) 0
      _ -> st
    mtotalvals = seriesValues <$> mtotal
    fillchars = if tcUnicode then "█▓▒░" else "#=+:"
    fillChar i = if single then cyclicAt ' ' fillchars 0 else cyclicAt ' ' fillchars i

    xlabels = case xaxis of
      XCategories ls -> [T.replicate (2 * lbIndent l) " " <> lbShort l | l <- ls]
      XPeriods ps    -> map snd ps
      XDates ds      -> map showDate ds
    segmentsAt j sers = map snd $ sortOn (not . fst)
      [ (contra, (categoryStyle j st, if contra then contrachar else c, q))
      | ((st, c, vals), s) <- sers, Just q <- [valueAt vals j], q /= 0, let contra = isContra s q ]
    contrachar = if tcUnicode then '╱' else '/'

    rows
      | grouped =
        concat
          [ [ Row (if i == 0 then lbl else "") (groupName k) (groupTotal j k) (segmentsAt j [ss | ss@(_, s) <- styledseries, seGroup s == k]) Nothing (Nothing, Nothing)
            | (i, k) <- zip [0 :: Int ..] groups ]
            ++ [ Row "" (lbShort $ seLabel t) (valueAt tvals j) [] (valueAt tvals j) (Nothing, Nothing) | Just t <- [marktotal], let tvals = seriesValues t ]
          | (j, lbl) <- zip [0 ..] xlabels ]
      | otherwise =
      [ Row lbl "" rowval (segmentsAt j styledseries) (if isJust marktotal then rowval else Nothing) (sideTotal j 1, sideTotal j (-1))
      | (j, lbl) <- zip [0 ..] xlabels
      , let rowval = case (mtotalvals, styled) of
              (Just tvals, _)     -> valueAt tvals j
              (_, [(_, _, vals)]) -> valueAt vals j
              _                   -> Nothing
      -- categories with no values at all (eg accounts without this commodity) are left out
      , not (isCategories && all (\(_, _, vals) -> isNothing $ valueAt vals j) styled)
      ]
    isCategories = case xaxis of XCategories _ -> True; _ -> False

    rowlines = map rowLine rows
    -- the styles of the bar segments actually drawn (a series too small to show at this scale has none)
    drawnstyles = nub [st | l <- rowlines, (st, t) <- l, st /= StylePlain, not $ T.null $ T.strip t]
    -- a legend for the series, omitting any not drawn
    legend
      | length drawn > 1 = wrapLegend (
          [ [(st, T.singleton c), (StylePlain, " " <> lbFull (seLabel s))] | ((st, c, _), s) <- zip styled drawn, st `elem` drawnstyles ]
          ++ [ [(StylePlain, markchar), (StylePlain, " " <> lbFull (seLabel t))] | Just t <- [marktotal] ]
          ++ [ [(StylePlain, T.singleton contrachar), (StylePlain, " contra")]
             | any (any (T.any (== contrachar) . snd)) rowlines ]
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
    -- In a diverging chart, the totals of each side's series (eg a compound report's sections), shown at that end of the bar.
    -- They are shown with their usual sign as positive, like the report's tables (eg expenses as positive),
    -- and include contra amounts (eg a refund counts in expenses, though it is drawn on the other side).
    sideTotal j sign = signedTotal sign j [s | s <- drawn, seSign s == sign]
    -- the same for a group's series (shown in the grouped layout)
    groupTotal j k = signedTotal (groupSign k) j [s | s <- drawn, seGroup s == k]
    signedTotal sign j sers = case [q | s <- sers, Just q <- [valueAt (seriesValues s) j]] of
      [] -> Nothing
      qs -> Just $ fromIntegral sign * sum qs
    posSum = fst . rowSides
    negSum = snd . rowSides
    negsumw = if diverging then maximumDef 0 (realLength negname : [realLength (showValue q) | Just q <- map negSum rows]) else 0
    possumw = if diverging then maximumDef 0 (realLength posname : [realLength (showValue q) | Just q <- map posSum rows]) else 0
    -- In a diverging chart, a header line names the total and the side totals' columns (eg the sections on each side).
    sideName sign = T.intercalate ", " $ filter (not . T.null) [groupName k | k <- groups, groupSign k == sign]
    (posname, negname) = (sideName 1, sideName (-1))
    netname = if hasvalues then maybe "" (lbShort . seLabel) mtotal else ""
    headerline = drop 1 $
      (if labelw > 0 then [(StylePlain, "  "), (StylePlain, T.replicate labelw " ")] else [])
      ++ (if hasvalues then [(StylePlain, "  "), (StylePlain, fitText (Just valuew) Nothing False False netname)] else [])
      ++ [(StylePlain, "  ")]
      ++ (if negsumw > 0 then [(StylePlain, fitText (Just negsumw) Nothing False False negname), (StylePlain, " ")] else [])
      ++ (if possumw > 0 then [(StylePlain, T.replicate barw " "), (StylePlain, " "), (StylePlain, posname)] else [])
    barw = max 10 $ tcWidth - (if labelw > 0 then labelw + 2 else 0) - (if sublabelw > 0 then sublabelw + 2 else 0) - (if hasvalues then valuew + 2 else 0)
                  - (if negsumw > 0 then negsumw + 1 else 0) - (if possumw > 0 then possumw + 1 else 0)
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
    -- cells per unit of value, shared by both sides: enough for the values to fill the area
    -- (but for counts, at most one cell per unit, unless the scale is fixed)
    scale :: Double
    scale
      | posspan + negspan == 0       = 0
      | pnCounts && isNothing pnScale = min 1 fillscale
      | otherwise                    = fillscale
      where fillscale = fromIntegral area / realToFrac (posspan + negspan)
    leftw
      | not hasaxis = 0
      | otherwise   = round (scale * realToFrac negspan)
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
      ++ (if negsumw > 0 then [(maybe StylePlain valueStyle (negSum r), fitText (Just negsumw) Nothing False False $ maybe "" showValue (negSum r)), (StylePlain, " ")] else [])
      ++ (if possumw > 0 then padTo barw bars ++ [(StylePlain, " "), (maybe StylePlain valueStyle (posSum r), maybe "" showValue (posSum r))] else bars)
      where
        bars = maybe id overlayMark (rowMark r) $ (if hasaxis then negativeBar r ++ [(StylePlain, axischar)] else []) ++ positiveBar r
    -- Pad a styled line with spaces to a width.
    padTo w l = l ++ [(StylePlain, T.replicate (w - sum (map (realLength . snd) l)) " ")]
    -- Draw a mark over the bar at a value's position (on the axis if zero).
    overlayMark q = overlayAt col (StylePlain, markchar)
      where
        col | q > 0     = leftw + (if hasaxis then 1 else 0) + max 1 (min rightw $ cells 1 q) - 1
            | q < 0     = leftw - max 1 (min leftw $ cells 1 (abs q))
            | otherwise = if hasaxis then leftw else 0
    valueStyle q = if q < 0 then StyleNegative else StylePlain

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

-- | Replace the character at a column of a styled line (of single-width characters) with some styled text,
-- padding the line with spaces if it is shorter.
overlayAt :: Int -> (Style, Text) -> StyledLine -> StyledLine
overlayAt i new = go 0
  where
    go col [] = [(StylePlain, T.replicate (i - col) " "), new]
    go col ((st, t) : rest)
      | i < col + n = [(st, T.take (i - col) t) | i > col] ++ [new] ++ [(st, T.drop (i - col + 1) t) | i - col + 1 < n] ++ rest
      | otherwise   = (st, t) : go (col + n) rest
      where n = T.length t

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
     let lbl t = ChartLabel t t 0 Nothing True
         chart = Chart "" (XCategories [lbl "a", lbl "b"])
                   [Panel nullamt [Series (lbl "s") SeriesItem MarkBar [Just 1, Just 2] 0 0] [] Nothing Diverging False []]
     map (T.concat . map snd) (chartAsStyledLines (TextChartOpts 20 True) chart)
       @?= ["a  1  ███████", "b  2  ██████████████"]
  ,testCase "mixed signs grow from an axis" $ do
     let lbl t = ChartLabel t t 0 Nothing True
         chart = Chart "" (XCategories [lbl "a", lbl "b"])
                   [Panel nullamt [Series (lbl "s") SeriesItem MarkBar [Just (-1), Just 2] 0 0] [] Nothing Diverging False []]
     map (T.concat . map snd) (chartAsStyledLines (TextChartOpts 21 False) chart)
       @?= ["a  -1  ####|", "b   2      |#########"]
  ]
