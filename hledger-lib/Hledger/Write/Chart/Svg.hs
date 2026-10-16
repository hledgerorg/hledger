{- |
Draw a 'Chart' as SVG, a self-contained graphical file viewable in web browsers and many image viewers.

Charts over time (periods or dates) are drawn with time along the x axis:
bar series as vertical bars (stacked, with a 2px gap between segments), line series as 2px lines,
and totals as ringed dots (with bars) or an ink-coloured line (with lines).
Charts of categories (eg the accounts of a single-period report) are drawn as horizontal bars,
with labels on the left and an aligned value column on the right.
There is one panel per commodity, one above the other, and a legend when a panel has several series.
Each mark has a tooltip (an SVG title) giving its x label, series and value.

The SVG includes its own styles, with a colour-blind-safe palette and a dark-mode variant
(used when the viewer prefers a dark colour scheme). Text widths are estimated, since fonts are not known.
Coordinates are rounded to one decimal place, so the output is deterministic.
-}

{-# LANGUAGE OverloadedStrings #-}

module Hledger.Write.Chart.Svg (
  chartAsSvg,
  chartSvgMarkup,
  tests_Hledger_Write_Chart_Svg,
) where

import Control.Monad (forM_, unless, when)
import Data.List (find)
import Data.Decimal (realFracToDecimal)
import Data.Maybe (catMaybes, fromMaybe, isNothing)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Lazy qualified as TL
import Safe (atMay, maximumDef, minimumDef)
import Text.Blaze ((!?), customAttribute, toValue)
import Text.Blaze.Svg.Renderer.Text (renderSvg)
import Text.Blaze.Svg11 ((!), Svg)
import Text.Blaze.Svg11 qualified as S
import Text.Blaze.Svg11.Attributes qualified as A
import Text.DocLayout (realLength)
import Text.Printf (printf)

import Hledger.Data.Amount (oneLineNoCostFmt, showAmountWith)
import Hledger.Data.Dates (showDate)
import Hledger.Data.Types (Amount(..), AmountPrecision(..), AmountStyle(..), Quantity)
import Hledger.Utils.Test
import Hledger.Write.Chart


-- | Render a chart as a complete SVG document.
chartAsSvg :: Chart -> TL.Text
chartAsSvg = (<> "\n") . TL.replace "><" ">\n<" . renderSvg . chartSvgMarkup  -- one element per line, for readability

-- | A chart as SVG markup, which can also be embedded in HTML.
chartSvgMarkup :: Chart -> Svg
chartSvgMarkup Chart{chTitle, chXAxis, chPanels} =
  S.svg
    ! customAttribute "xmlns" "http://www.w3.org/2000/svg"
    ! A.class_ "hledger-chart"
    ! A.width (toValue $ num chartWidth)
    ! A.height (toValue $ num totalheight)
    ! A.viewbox (toValue $ "0 0 " <> num chartWidth <> " " <> num totalheight)
    ! customAttribute "role" "img"
    !? (not $ T.null chTitle, customAttribute "aria-label" (toValue chTitle))
    $ do
      unless (T.null chTitle) $ S.title (S.toMarkup chTitle)
      S.style (S.toMarkup stylesheet)
      S.rect ! A.class_ "bg" ! A.width "100%" ! A.height "100%"
      unless (T.null chTitle) $
        S.text_ ! A.class_ "title" ! A.x (toValue $ num pad) ! A.y (toValue $ num (pad + 14)) $ S.toMarkup chTitle
      sequence_ panelmarkups
  where
    titleheight = if T.null chTitle then 0 else 32
    showheadings = length chPanels > 1
    (totalheight, panelmarkups) = foldl stackPanel (pad + titleheight, []) chPanels
    stackPanel (top, ms) p =
      let (h, m) = panelSvg chXAxis showheadings top p
      in (top + h + panelGap, ms ++ [m])

-- Layout constants, in pixels.
chartWidth, pad, panelGap, charWidth, legendRowHeight, plotHeight, rowHeight :: Double
chartWidth      = 760
pad             = 16
panelGap        = 16
charWidth       = 7    -- estimated average width of a character in the 12px system sans font
legendRowHeight = 20
plotHeight      = 220  -- height of a vertical-bar or line plot
rowHeight       = 22   -- height of a row in a horizontal bar chart

-- | Estimated rendered width of some text.
textWidth :: Text -> Double
textWidth t = fromIntegral (realLength t) * charWidth

-- | A series to draw, with its CSS class and the values it draws.
data DrawSeries = DrawSeries
  { dsClass  :: Text
  , dsSeries :: Series
  , dsValues :: SeriesValues
  }

-- | Draw one panel with its top at the given y; return its height and markup.
panelSvg :: XAxis -> Bool -> Double -> Panel -> (Double, Svg)
panelSvg xaxis showheading top Panel{pnUnit, pnSeries} =
  (headingh + legendh + bodyh, do
    when (headingh > 0) $
      S.text_ ! A.class_ "heading" ! A.x (toValue $ num pad) ! A.y (toValue $ num (top + 14)) $ S.toMarkup (acommodity pnUnit)
    legendm
    bodym)
  where
    headingh = if showheading && not (T.null $ acommodity pnUnit) then 24 else 0
    -- The series drawn as marks: items and "other" (bars or lines), and the total (dots or a line). Other markers are not drawn yet.
    items = [s | s <- pnSeries, seRole s /= SeriesTotal, seMark s /= MarkMarker]
    mtotal = find ((== SeriesTotal) . seRole) pnSeries
    drawn = zipWith classify [0 :: Int ..] items
    classify i s = DrawSeries (if seRole s == SeriesOther then "other" else "s" <> T.pack (show (i `mod` 8))) s (seriesValues s)
    (legendh, legendm) = legendSvg (top + headingh) [(dsClass d, seMark (dsSeries d), lbFull $ seLabel $ dsSeries d) | d <- drawn]
                           (if length items > 1 then mtotal else Nothing)
    (bodyh, bodym) = case xaxis of
      XCategories ls -> categoriesSvg (top + headingh + legendh) pnUnit drawn mtotal ls
      XPeriods ps    -> timeSvg (top + headingh + legendh) pnUnit drawn mtotal (map snd ps)
      XDates ds      -> timeSvg (top + headingh + legendh) pnUnit drawn mtotal (map showDate ds)

-- | A legend: a swatch and label for each series, flowing left to right, when there are several series.
legendSvg :: Double -> [(Text, Mark, Text)] -> Maybe Series -> (Double, Svg)
legendSvg top entries mtotal
  | length entries < 2 = (0, mempty)
  | otherwise = (fromIntegral (length rows) * legendRowHeight + 8, mapM_ drawRow (zip [0 ..] rows))
  where
    allentries = entries ++ [("total", if any (\(_, mk, _) -> mk == MarkLine) entries then MarkLine else MarkMarker, lbFull (seLabel t)) | Just t <- [mtotal]]
    itemWidth (_, _, lbl) = 18 + textWidth lbl + 16
    rows = reverse $ map reverse $ foldl place [] allentries
    place [] e = [[e]]
    place (r:rs) e
      | sum (map itemWidth r) + itemWidth e <= chartWidth - 2 * pad = (e : r) : rs
      | otherwise = [e] : r : rs
    drawRow :: (Int, [(Text, Mark, Text)]) -> Svg
    drawRow (i, row) = do
      let y = top + fromIntegral i * legendRowHeight + 10
          xs = scanl (+) pad (map itemWidth row)
      forM_ (zip xs row) $ \(x, (cls, mk, lbl)) -> do
        case mk of
          MarkLine   -> S.line ! A.class_ ("line " <> toValue cls) ! A.x1 (toValue $ num x) ! A.x2 (toValue $ num (x + 12))
                          ! A.y1 (toValue $ num y) ! A.y2 (toValue $ num y)
          MarkMarker -> S.circle ! A.class_ ("dot " <> toValue cls) ! A.cx (toValue $ num (x + 6)) ! A.cy (toValue $ num y) ! A.r "4"
          MarkBar    -> S.rect ! A.class_ ("fill " <> toValue cls) ! A.x (toValue $ num x) ! A.y (toValue $ num (y - 5))
                          ! A.width "10" ! A.height "10" ! A.rx "2"
        S.text_ ! A.class_ "label" ! A.x (toValue $ num (x + 18)) ! A.y (toValue $ num (y + 4)) $ S.toMarkup lbl

-- | Draw series over time (periods or dates, evenly spaced), with the given x labels: vertical stacked bars, lines and total dots.
timeSvg :: Double -> Amount -> [DrawSeries] -> Maybe Series -> [Text] -> (Double, Svg)
timeSvg top unit drawn mtotal xlabels = (plotHeight + 28, do
    -- gridlines and y tick labels
    forM_ ticks $ \t -> do
      S.line ! A.class_ (if t == 0 then "axis" else "grid")
        ! A.x1 (toValue $ num plotleft) ! A.x2 (toValue $ num plotright) ! A.y1 (toValue $ num (yof t)) ! A.y2 (toValue $ num (yof t))
      S.text_ ! A.class_ "tick" ! A.x (toValue $ num (plotleft - 8)) ! A.y (toValue $ num (yof t + 4)) ! A.textAnchor "end" $ S.toMarkup (ticklabel t)
    -- x labels, thinned to avoid overlap
    forM_ (zip [0 :: Int ..] xlabels) $ \(j, lbl) ->
      when (j `mod` labelevery == 0) $
        S.text_ ! A.class_ "tick" ! A.x (toValue $ num (xcenter j)) ! A.y (toValue $ num (plotbottom + 18)) ! A.textAnchor "middle" $ S.toMarkup lbl
    -- bars
    forM_ (zip [0 ..] xlabels) $ \(j, lbl) -> do
      stack lbl j [(d, q) | d <- bars, Just q <- [valueAt (dsValues d) j], q > 0] 1
      stack lbl j [(d, q) | d <- bars, Just q <- [valueAt (dsValues d) j], q < 0] (-1)
    -- lines
    forM_ lines_ $ \d -> lineSvg (dsClass d) (dsSeries d)
    -- the total, as a line (when the other series are lines) or as dots
    forM_ mtotal $ \t ->
      if null bars then lineSvg "total" t
      else let tvals = seriesValues t in
        forM_ (zip [0 ..] xlabels) $ \(j, lbl) -> forM_ (valueAt tvals j) $ \q -> when (hasbars j) $ withTooltip (tooltip lbl t q) $
        S.circle ! A.class_ "dot total" ! A.cx (toValue $ num (xcenter j)) ! A.cy (toValue $ num (yof $ toD q)) ! A.r "4"
  )
  where
    n = length xlabels
    bars   = [d | d <- drawn, seMark (dsSeries d) == MarkBar]
    lines_ = [d | d <- drawn, seMark (dsSeries d) == MarkLine]
    stackedsums sign = [sum [toD q | d <- bars, Just q <- [valueAt (dsValues d) j], signum q == sign] | j <- [0 .. n - 1]]
    hasbars j = any (\d -> maybe False (/= 0) $ valueAt (dsValues d) j) bars
    pointvalues = [toD q | s <- map dsSeries lines_ ++ maybe [] pure mtotal, Just q <- seValues s]
    datamax = maximumDef 0 (stackedsums 1 ++ pointvalues)
    datamin = minimumDef 0 (stackedsums (-1) ++ pointvalues)
    (lo, hi, ticks, tickdecimals) = niceScale (min 0 datamin) (max 0 datamax)
    ticklabel t = showValue (withPrecision tickdecimals unit) (tickQuantity tickdecimals t)
    plotleft = pad + maximumDef 0 (map (textWidth . ticklabel) ticks) + 12
    plotright = chartWidth - pad
    plottop = top + 6
    plotbottom = plottop + plotHeight
    yof v = plottop + plotHeight * (hi - v) / (hi - lo)
    band = (plotright - plotleft) / fromIntegral (max 1 n)
    xcenter j = plotleft + band * (fromIntegral j + 0.5)
    barwidth = if band >= 4 then min 24 (band * 0.7) else max 1 (band * 0.9)
    labelevery = max 1 $ ceiling ((maximumDef 0 (map textWidth xlabels) + 12) / band) :: Int
    -- one direction of a stacked bar: segments from the baseline outward, 2px apart, the outermost with a rounded end
    stack :: Text -> Int -> [(DrawSeries, Quantity)] -> Double -> Svg
    stack lbl j segs sign = do
      let cums = scanl1 (+) (map (toD . snd) segs)
          starts = 0 : cums
          lastk = length segs - 1
      forM_ (zip3 [0 :: Int ..] segs (zip starts cums)) $ \(k, (d, q), (c0, c1)) -> do
        let gap = if k > 0 && abs (yof c1 - yof c0) >= 4 then 2 else 0  -- no gap for tiny segments, which it would hide
            ybase = yof c0 - sign * gap   -- the end nearer the baseline, after the gap
            yend = yof c1
            len = (ybase - yend) * sign   -- positive when there is something to draw
            x = xcenter j - barwidth / 2
        when (len > 0.5) $ withTooltip (tooltip lbl (dsSeries d) q) $
          S.path ! A.class_ ("fill " <> toValue (dsClass d))
            ! A.d (toValue $ barPath True x ybase barwidth (-sign * len) (k == lastk))
    lineSvg :: Text -> Series -> Svg
    lineSvg cls s = do
      -- runs of consecutive values, so that gaps break the line
      let pts = [ fmap (\q -> (j, xcenter j, yof (toD q), q)) (valueAt vals j) | let vals = seriesValues s, j <- [0 .. n - 1] ]
      forM_ (runs pts) $ \run ->
        S.polyline ! A.class_ ("line " <> toValue cls)
          ! A.points (toValue $ T.unwords [num x <> "," <> num y | (_, x, y, _) <- run])
      -- invisible larger targets, for tooltips (only when there are not too many points)
      when (n <= 400) $ forM_ (catMaybes pts) $ \(j, x, y, q) -> withTooltip (tooltip (fromMaybe "" $ xlabels `atMay` j) s q) $
        S.circle ! A.class_ "hit" ! A.cx (toValue $ num x) ! A.cy (toValue $ num y) ! A.r "6"
    tooltip :: Text -> Series -> Quantity -> Text
    tooltip lbl s q = T.intercalate " · " (filter (not . T.null) [lbl, lbFull (seLabel s), showValue unit q])

-- | Draw series of categories as horizontal bars (stacked if several), with labels and a value column.
categoriesSvg :: Double -> Amount -> [DrawSeries] -> Maybe Series -> [ChartLabel] -> (Double, Svg)
categoriesSvg top unit drawn mtotal labels = (fromIntegral (length rows) * rowHeight + 28, do
    -- gridlines and x tick labels
    forM_ ticks $ \t -> do
      S.line ! A.class_ (if t == 0 then "axis" else "grid")
        ! A.x1 (toValue $ num (xof t)) ! A.x2 (toValue $ num (xof t)) ! A.y1 (toValue $ num plottop) ! A.y2 (toValue $ num plotbottom)
      S.text_ ! A.class_ "tick" ! A.x (toValue $ num (xof t)) ! A.y (toValue $ num (plotbottom + 18)) ! A.textAnchor "middle" $ S.toMarkup (ticklabel t)
    forM_ (zip [0 :: Int ..] rows) $ \(i, (lbl, j)) -> do
      let ymid = plottop + rowHeight * (fromIntegral i + 0.5)
      S.text_ ! A.class_ "label" ! A.x (toValue $ num (pad + 12 * fromIntegral (lbIndent lbl))) ! A.y (toValue $ num (ymid + 4))
        $ S.toMarkup (lbShort lbl)
      forM_ (rowValue j) $ \q ->
        S.text_ ! A.class_ "value" ! A.x (toValue $ num (chartWidth - pad)) ! A.y (toValue $ num (ymid + 4)) ! A.textAnchor "end"
          $ S.toMarkup (showValue unit q)
      stack lbl ymid [(d, q) | d <- drawn, Just q <- [valueAt (dsValues d) j], q > 0] 1
      stack lbl ymid [(d, q) | d <- drawn, Just q <- [valueAt (dsValues d) j], q < 0] (-1)
  )
  where
    -- categories with no values at all (eg accounts without this commodity) are left out
    rows = [(l, j) | (j, l) <- zip [0 ..] labels, not $ all (isNothing . flip valueAt j . dsValues) drawn]
    mtotalvals = seriesValues <$> mtotal
    rowValue j = case (mtotal, drawn) of
      (Just _, _) -> mtotalvals >>= flip valueAt j
      (_, [d])    -> valueAt (dsValues d) j
      _           -> Nothing
    stackedsums sign = [sum [toD q | d <- drawn, Just q <- [valueAt (dsValues d) j], signum q == sign] | (_, j) <- rows]
    (lo, hi, ticks, tickdecimals) = niceScale (minimumDef 0 $ map negate $ stackedsums (-1)) (maximumDef 0 $ stackedsums 1)
    ticklabel t = showValue (withPrecision tickdecimals unit) (tickQuantity tickdecimals t)
    labelwidth = min (chartWidth * 0.4) $ maximumDef 0 [12 * fromIntegral (lbIndent l) + textWidth (lbShort l) | (l, _) <- rows]
    valuewidth = maximumDef 0 [textWidth (showValue unit q) | (_, j) <- rows, Just q <- [rowValue j]]
    -- leave room for half of a tick label at each end
    edge = maximumDef 0 (map (textWidth . ticklabel) ticks) / 2
    plotleft = pad + max labelwidth edge + 12
    plotright = chartWidth - pad - max valuewidth edge - 16
    plottop = top + 4
    plotbottom = plottop + rowHeight * fromIntegral (length rows)
    xof v = plotleft + (plotright - plotleft) * (v - lo) / (hi - lo)
    thickness = 12
    stack :: ChartLabel -> Double -> [(DrawSeries, Quantity)] -> Double -> Svg
    stack lbl ymid segs sign = do
      let cums = scanl1 (+) (map (toD . snd) segs)
          starts = 0 : cums
          lastk = length segs - 1
      forM_ (zip3 [0 :: Int ..] segs (zip starts cums)) $ \(k, (d, q), (c0, c1)) -> do
        let gap = if k > 0 && abs (xof (sign * c1) - xof (sign * c0)) >= 4 then 2 else 0  -- no gap for tiny segments, which it would hide
            xbase = xof (sign * c0) + sign * gap
            len = (xof (sign * c1) - xbase) * sign
        when (len > 0.5) $ withTooltip (T.intercalate " · " [lbFull lbl, lbFull (seLabel $ dsSeries d), showValue unit q]) $
          S.path ! A.class_ ("fill " <> toValue (dsClass d))
            ! A.d (toValue $ barPath False xbase (ymid - thickness / 2) thickness (sign * len) (k == lastk))

-- | Give some markup a tooltip, by grouping it with an SVG title.
withTooltip :: Text -> Svg -> Svg
withTooltip t m = S.g $ S.title (S.toMarkup t) >> m

-- | An SVG path for a bar (segment) growing from a base line, with its far end rounded (radius up to 4px) if requested.
-- Vertical: base line at y=b, from x=a with the given width, growing by len pixels (negative is upward, since y grows downward).
-- Horizontal: base line at x=a, from y=b with the given thickness, growing by len pixels (positive is rightward).
barPath :: Bool -> Double -> Double -> Double -> Double -> Bool -> Text
barPath vertical a b size len rounded
  | vertical =
      let e = b + len in T.unwords
      [ "M", num a, num b
      , "V", num (e - sgn * r)
      , "Q", num a, num e, num (a + r), num e
      , "H", num (a + size - r)
      , "Q", num (a + size), num e, num (a + size), num (e - sgn * r)
      , "V", num b, "Z" ]
  | otherwise =
      let e = a + len in T.unwords
      [ "M", num a, num b
      , "H", num (e - sgn * r)
      , "Q", num e, num b, num e, num (b + r)
      , "V", num (b + size - r)
      , "Q", num e, num (b + size), num (e - sgn * r), num (b + size)
      , "H", num a, "Z" ]
  where
    sgn = if len < 0 then -1 else 1
    r = if rounded then minimum [4, size / 2, abs len] else 0

-- | A "nice" linear scale covering the given range (which should include 0):
-- its low and high ends, its ticks (about 5, at multiples of 1, 2 or 5 times a power of ten),
-- and the number of decimal places needed to show the ticks.
niceScale :: Double -> Double -> (Double, Double, [Double], Int)
niceScale lo0 hi0 = (lo, hi, ticks, decimals)
  where
    (a, b) = if hi0 - lo0 <= 0 then (lo0, lo0 + 1) else (lo0, hi0)
    -- choose the 1, 2 or 5 times a power of ten nearest the step that would give 5 intervals (as d3 does)
    rawstep = (b - a) / 5
    magnitude = 10 ** fromIntegral (floor (logBase 10 rawstep) :: Int)
    err = rawstep / magnitude
    step | err >= sqrt 50 = 10 * magnitude
         | err >= sqrt 10 = 5 * magnitude
         | err >= sqrt 2  = 2 * magnitude
         | otherwise      = magnitude
    kmin = floor (a / step) :: Integer
    kmax = ceiling (b / step) :: Integer
    ticks = [fromIntegral k * step | k <- [kmin .. kmax]]
    lo = fromIntegral kmin * step
    hi = fromIntegral kmax * step
    decimals = max 0 $ negate (floor (logBase 10 step + 1e-9) :: Int)

-- | The value of a tick, as a quantity with the given number of decimal places.
tickQuantity :: Int -> Double -> Quantity
tickQuantity decimals = realFracToDecimal (fromIntegral decimals)

-- | Show a quantity as an amount in the given unit (commodity and style).
showValue :: Amount -> Quantity -> Text
showValue unit q = T.pack $ showAmountWith oneLineNoCostFmt unit{aquantity = q}

-- | The unit with its display precision set to this many decimal places.
withPrecision :: Int -> Amount -> Amount
withPrecision d unit = unit{astyle = (astyle unit){asprecision = Precision (fromIntegral d)}}

toD :: Quantity -> Double
toD = realToFrac

-- | A coordinate for SVG, rounded to one decimal place, without a trailing ".0".
num :: Double -> Text
num x
  | r == 0    = "0"
  | otherwise = let t = T.pack (printf "%.1f" r) in fromMaybe t (T.stripSuffix ".0" t)
  where r = fromIntegral (round (x * 10) :: Integer) / 10 :: Double

-- | The runs of consecutive Just values in a list.
runs :: [Maybe a] -> [[a]]
runs ms = case dropWhile isNothing ms of
  [] -> []
  rest -> let (run, more) = span (not . isNothing) rest in catMaybes run : runs more

-- | The chart's styles: a colour-blind-safe categorical palette (8 slots) and chart chrome colours,
-- with a dark variant used when the viewer prefers a dark colour scheme.
-- Colours are written literally in each rule (rather than as CSS custom properties),
-- since some SVG renderers (eg librsvg, used by many image viewers) don't support those.
stylesheet :: Text
stylesheet = T.unlines $
  [ ".hledger-chart{font-family:system-ui,-apple-system,\"Segoe UI\",sans-serif;font-size:12px}"
  , ".hledger-chart .title{font-size:14px;font-weight:600}"
  , ".hledger-chart .heading{font-size:13px;font-weight:600}"
  , ".hledger-chart .value,.hledger-chart .tick{font-variant-numeric:tabular-nums}"
  , ".hledger-chart .grid,.hledger-chart .axis{stroke-width:1}"
  , ".hledger-chart .line{fill:none;stroke-width:2;stroke-linejoin:round;stroke-linecap:round}"
  , ".hledger-chart .dot.total{stroke-width:2}"
  , ".hledger-chart .hit{fill:transparent}"
  ]
  ++ colourRules lightcolours
  ++ ["@media (prefers-color-scheme:dark){"] ++ colourRules darkcolours ++ ["}"]
  where
    colourRules cs =
      [ ".hledger-chart " <> sel <> "{" <> prop <> ":" <> colour <> "}"
      | (sel, prop, role) <- rules, Just colour <- [lookup role cs] ]
    rules =
      [ (".bg", "fill", "surface"), (".title", "fill", "ink"), (".heading", "fill", "ink")
      , (".label", "fill", "ink2"), (".value", "fill", "ink2"), (".tick", "fill", "muted")
      , (".grid", "stroke", "grid"), (".axis", "stroke", "axis")
      , (".fill.other", "fill", "muted"), (".line.other", "stroke", "muted"), (".line.total", "stroke", "ink")
      , (".dot.total", "fill", "ink"), (".dot.total", "stroke", "surface")
      ]
      ++ concat [ [(".fill." <> c, "fill", c), (".line." <> c, "stroke", c)] | c <- map (("s" <>) . T.pack . show) [0 :: Int .. 7] ]
    lightcolours :: [(Text, Text)]
    lightcolours =
      [ ("surface", "#fcfcfb"), ("ink", "#0b0b0b"), ("ink2", "#52514e"), ("muted", "#898781"), ("grid", "#e1e0d9"), ("axis", "#c3c2b7")
      , ("s0", "#2a78d6"), ("s1", "#eb6834"), ("s2", "#1baf7a"), ("s3", "#eda100"), ("s4", "#e87ba4"), ("s5", "#008300"), ("s6", "#4a3aa7"), ("s7", "#e34948") ]
    darkcolours =
      [ ("surface", "#1a1a19"), ("ink", "#ffffff"), ("ink2", "#c3c2b7"), ("muted", "#898781"), ("grid", "#2c2c2a"), ("axis", "#383835")
      , ("s0", "#3987e5"), ("s1", "#d95926"), ("s2", "#199e70"), ("s3", "#c98500"), ("s4", "#d55181"), ("s5", "#008300"), ("s6", "#9085e9"), ("s7", "#e66767") ]

tests_Hledger_Write_Chart_Svg :: TestTree
tests_Hledger_Write_Chart_Svg = testGroup "Write.Chart.Svg" [
   testCase "num" $ do
     map num [0, -0.04, 1, 1.26, -3.14159, 760] @?= ["0", "0", "1", "1.3", "-3.1", "760"]
  ,testCase "niceScale" $ do
     niceScale 0 87 @?= (0, 100, [0, 20, 40, 60, 80, 100], 0)
     niceScale (-15) 100 @?= (-20, 100, [-20, 0, 20, 40, 60, 80, 100], 0)
     niceScale 0 0 @?= (0, 1, [0, 0.2, 0.4, 0.6000000000000001, 0.8, 1], 1)
     niceScale 0 7.3 @?= (0, 8, [0, 2, 4, 6, 8], 0)
  ,testCase "barPath" $ do
     barPath True 10 100 20 (-50) True @?= "M 10 100 V 54 Q 10 50 14 50 H 26 Q 30 50 30 54 V 100 Z"
     barPath False 10 5 12 (-30) False @?= "M 10 5 H -20 Q -20 5 -20 5 V 17 Q -20 17 -20 17 H 10 Z"
  ]
