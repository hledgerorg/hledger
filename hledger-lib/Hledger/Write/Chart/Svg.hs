{- |
Draw a 'Chart' as SVG, a self-contained graphical file viewable in web browsers and many image viewers.

Charts over time (periods or dates) are drawn with time along the x axis:
bar series as vertical bars (stacked, with a 2px gap between segments), line series as 2px lines,
and totals as ink-coloured line marks across each period's bars, or as an ink-coloured line.
Charts of categories (eg the accounts of a single-period report) are drawn as horizontal bars,
with labels on the left and an aligned value column on the right.
There is one panel per commodity, one above the other, and a legend when a panel has several series.
Each mark has a tooltip (an SVG title) giving its x label, series and value.

The SVG includes its own styles, with a colour-blind-safe palette and a dark-mode variant
(used when the viewer prefers a dark colour scheme). Text widths are estimated, since fonts are not known.
Coordinates are rounded to one decimal place, so the output is deterministic.
-}

{-# LANGUAGE CPP #-}
{-# LANGUAGE OverloadedStrings #-}

module Hledger.Write.Chart.Svg (
  chartAsSvg,
  chartAsSvgWith,
  chartSvgMarkup,
  tests_Hledger_Write_Chart_Svg,
) where

import Control.Monad (forM_, unless, when)
import Data.Function (on)
import Data.List (find, groupBy, nub)
#if !MIN_VERSION_base(4,20,0)
import Data.List (foldl')
#endif
import Data.Map qualified as M
import Data.Array qualified as Arr
import Data.Decimal (realFracToDecimal)
import Data.Maybe (catMaybes, fromMaybe, isJust, isNothing)
import Data.Time (Day, addDays, diffDays, fromGregorian, toGregorian)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Lazy qualified as TL
import Safe (atMay, headMay, lastMay, maximumDef, minimumDef)
import Text.Blaze ((!?), customAttribute, toValue)
import Text.Blaze.Svg.Renderer.Text (renderSvg)
import Text.Blaze.Svg11 ((!), Svg)
import Text.Blaze.Svg11 qualified as S
import Text.Blaze.Svg11.Attributes qualified as A
import Text.DocLayout (realLength)
import Text.Printf (printf)

import Hledger.Data.Amount (oneLineNoCostFmt, showAmountWith)
import Hledger.Data.Dates (showDate)
import Hledger.Data.Types (AccountType(..), Amount(..), AmountPrecision(..), AmountStyle(..), Quantity)
import Hledger.Utils.Test
import Hledger.Write.Chart
import Hledger.Write.Chart.Palette (colourHex)


-- | Render a chart as a complete SVG document, with a dark variant for viewers preferring a dark colour scheme.
chartAsSvg :: Chart -> TL.Text
chartAsSvg = chartAsSvgWith True

-- | Render a chart as SVG, with or without the dark variant
-- (eg without, when embedding it in a page that is always light).
-- It has one element per line, for readability.
chartAsSvgWith :: Bool -> Chart -> TL.Text
chartAsSvgWith dark = (<> "\n") . TL.replace "><" ">\n<" . renderSvg . chartSvgMarkup dark

-- | A chart as SVG markup, which can also be embedded in HTML; with or without the dark variant.
chartSvgMarkup :: Bool -> Chart -> Svg
chartSvgMarkup dark Chart{chTitle, chXAxis, chPanels} =
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
      S.style (S.toMarkup $ stylesheet dark)
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
panelSvg xaxis showheading top Panel{pnUnit, pnSeries, pnScale} =
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
    drawn = zipWith (\c s -> DrawSeries (colourClass c) s (seriesValues s)) (seriesColours items) items
    (legendh, legendm) = legendSvg (top + headingh) [(dsClass d, seMark (dsSeries d), lbFull $ seLabel $ dsSeries d) | d <- drawn]
                           (if length items > 1 then mtotal else Nothing)
    (bodyh, bodym) = case xaxis of
      XCategories ls -> categoriesSvg (top + headingh + legendh) pnScale pnUnit drawn mtotal ls
      XPeriods ps    -> timeSvg (top + headingh + legendh) pnScale pnUnit drawn mtotal (EvenScale $ map snd ps)
      XDates ds      -> timeSvg (top + headingh + legendh) pnScale pnUnit drawn mtotal (DateScale ds)

-- | A legend: a swatch and label for each series, flowing left to right, when there are several series.
legendSvg :: Double -> [(Text, Mark, Text)] -> Maybe Series -> (Double, Svg)
legendSvg top entries mtotal
  | length entries < 2 = (0, mempty)
  | otherwise = (fromIntegral (length rows) * legendRowHeight + 8, mapM_ drawRow (zip [0 ..] rows))
  where
    allentries = entries ++ [("total", if seMark t == MarkLine || all (\(_, mk, _) -> mk == MarkLine) entries then MarkLine else MarkMarker, lbFull (seLabel t)) | Just t <- [mtotal]]
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
          MarkMarker -> S.line ! A.class_ ("mark " <> toValue cls) ! A.x1 (toValue $ num x) ! A.x2 (toValue $ num (x + 12))
                          ! A.y1 (toValue $ num y) ! A.y2 (toValue $ num y)
          MarkBar    -> S.rect ! A.class_ ("fill " <> toValue cls) ! A.x (toValue $ num x) ! A.y (toValue $ num (y - 5))
                          ! A.width "10" ! A.height "10" ! A.rx "2"
        S.text_ ! A.class_ "label" ! A.x (toValue $ num (x + 18)) ! A.y (toValue $ num (y + 4)) $ S.toMarkup lbl

-- | How x positions are placed along a time axis: evenly, with these labels (eg report periods),
-- or by date, on a time scale (eg a register's transactions; lines are then drawn as steps).
data XScale = EvenScale [Text] | DateScale [Day]

-- | Draw series over time, along the given x scale:
-- vertical bars (in stacks, side by side), lines, and total marks or lines.
timeSvg :: Double -> Maybe Quantity -> Amount -> [DrawSeries] -> Maybe Series -> XScale -> (Double, Svg)
timeSvg top mscale unit drawn mtotal xscale = (plotHeight + 28, do
    -- gridlines and y tick labels
    forM_ ticks $ \t -> do
      S.line ! A.class_ (if t == 0 then "axis" else "grid")
        ! A.x1 (toValue $ num plotleft) ! A.x2 (toValue $ num plotright) ! A.y1 (toValue $ num (yof t)) ! A.y2 (toValue $ num (yof t))
      S.text_ ! A.class_ "tick" ! A.x (toValue $ num (plotleft - 8)) ! A.y (toValue $ num (yof t + 4)) ! A.textAnchor "end" $ S.toMarkup (ticklabel t)
    -- x labels: periods' labels, thinned to avoid overlap; or ticks at calendar boundaries
    case xscale of
      EvenScale _ -> forM_ (zip [0 :: Int ..] xlabels) $ \(j, lbl) ->
        when (j `mod` labelevery == 0) $ xlabel (xcenter j) lbl
      DateScale _ -> forM_ (dateTicks d0 d1) $ \(d, lbl) -> xlabel (xofday d) lbl
    -- bars: the stacks side by side (2px apart), each with its positive segments stacked upward and negative ones downward
    forM_ (zip [0 ..] xlabels) $ \(j, lbl) ->
      forM_ (zip [0 :: Int ..] stacks) $ \(k, stk) -> do
        let x = xcenter j - groupwidth / 2 + fromIntegral k * (barwidth + 2)
        stack lbl x [(d, q) | d <- stk, Just q <- [valueAt (dsValues d) j], q > 0] 1
        stack lbl x [(d, q) | d <- stk, Just q <- [valueAt (dsValues d) j], q < 0] (-1)
    -- with a fixed scale, lines are clipped at the plot's edges
    when (isJust mscale) $ S.defs $ S.clippath ! A.id_ (toValue clipid) $
      S.rect ! A.x (toValue $ num plotleft) ! A.y (toValue $ num plottop) ! A.width (toValue $ num (plotright - plotleft)) ! A.height (toValue $ num plotHeight)
    let clipLines = if isJust mscale then S.g ! A.clipPath (toValue $ "url(#" <> clipid <> ")") else id
    -- lines
    clipLines $ forM_ lines_ $ \d -> lineSvg (dsClass d) (dsSeries d)
    -- the total: as a line, or as a mark (a thin horizontal line) across each period's bars
    forM_ mtotal $ \t ->
      if seMark t == MarkLine || null bars then clipLines $ lineSvg "total" t
      else let tvals = seriesValues t in
        forM_ (zip [0 ..] xlabels) $ \(j, lbl) -> forM_ (valueAt tvals j) $ \q -> when (hasbars j) $ withTooltip (tooltip lbl t q) $ do
          let y = toValue $ num (yof $ toD q)
              halfw = groupwidth / 2 + 4
              x1 = toValue $ num (xcenter j - halfw)
              x2 = toValue $ num (xcenter j + halfw)
          S.line ! A.class_ "mark total" ! A.x1 x1 ! A.x2 x2 ! A.y1 y ! A.y2 y
  )
  where
    xlabels = case xscale of
      EvenScale ls -> ls
      DateScale ds -> map showDate ds
    n = length xlabels
    -- an x axis label centred at x, but kept within the chart
    xlabel x lbl =
      let halfw = textWidth lbl / 2
          x' = max (pad + halfw) $ min (chartWidth - pad - halfw) x
      in S.text_ ! A.class_ "tick" ! A.x (toValue $ num x') ! A.y (toValue $ num (plotbottom + 18)) ! A.textAnchor "middle" $ S.toMarkup lbl
    -- the date scale, if any: its dates (as an array, for fast lookup), first and last dates, and a date's x position (inset a little from the plot's edges)
    datearray = case xscale of
      DateScale ds -> Just $ Arr.listArray (0, length ds - 1) ds
      EvenScale _  -> Nothing
    (d0, d1) = case xscale of
      DateScale ds@(d:_) -> (minimumDef d ds, maximumDef d ds)
      _                  -> (fromGregorian 2000 1 1, fromGregorian 2000 1 1)
    xofday d = plotleft + 8 + (plotright - plotleft - 16) * fromIntegral (diffDays d d0) / fromIntegral (max 1 (diffDays d1 d0))
    bars   = [d | d <- drawn, seMark (dsSeries d) == MarkBar]
    lines_ = [d | d <- drawn, seMark (dsSeries d) == MarkLine]
    -- the bar series in stacks, in order (see 'seStack')
    stacks = [ [d | d <- bars, seStack (dsSeries d) == k] | k <- nub $ map (seStack . dsSeries) bars ]
    -- the extent of the bars in each direction: each stack's sum, at each x position
    stackedsums sign = [ sum [toD q | d <- stk, Just q <- [valueAt (dsValues d) j], signum q == sign] | j <- [0 .. n - 1], stk <- stacks ]
    hasbars j = any (\d -> maybe False (/= 0) $ valueAt (dsValues d) j) bars
    pointvalues = [toD q | s <- map dsSeries lines_ ++ maybe [] pure mtotal, Just q <- seValues s]
    datamax = maximumDef 0 (stackedsums 1 ++ pointvalues)
    datamin = minimumDef 0 (stackedsums (-1) ++ pointvalues)
    (lo, hi, ticks, tickdecimals) = panelScale mscale (min 0 datamin) (max 0 datamax)
    ticklabel t = showValue (withPrecision tickdecimals unit) (tickQuantity tickdecimals t)
    plotleft = pad + maximumDef 0 (map (textWidth . ticklabel) ticks) + 12
    plotright = chartWidth - pad
    plottop = top + 6
    plotbottom = plottop + plotHeight
    -- a value's y position, within the plot (for bars and marks), or anywhere (for lines, which are clipped)
    yof = clamp plottop plotbottom . yofline
    yofline v = plottop + plotHeight * (hi - v) / (hi - lo)
    -- an id for the plot's clipping path, unique within the chart
    clipid = "hledger-chart-clip-" <> num top
    band = (plotright - plotleft) / fromIntegral (max 1 n)
    xcenter j = case datearray of
      Just a | Arr.inRange (Arr.bounds a) j -> xofday (a Arr.! j)
      _ -> plotleft + band * (fromIntegral j + 0.5)
    nbars = max 1 $ length stacks
    -- each bar's width, and the width of a group of side-by-side bars (2px apart)
    barwidth
      | band < 4  = max 1 (band * 0.9 / fromIntegral nbars)
      | otherwise = max 1 $ min 24 ((band * 0.8 - 2 * fromIntegral (nbars - 1)) / fromIntegral nbars)
    groupwidth = fromIntegral nbars * barwidth + 2 * fromIntegral (nbars - 1)
    labelevery = max 1 $ ceiling ((maximumDef 0 (map textWidth xlabels) + 12) / band) :: Int
    stack :: Text -> Double -> [(DrawSeries, Quantity)] -> Double -> Svg
    stack lbl x segs = vstack (lo, hi) yof x barwidth [(d, q, tooltip lbl (dsSeries d) q) | (d, q) <- segs]
    lineSvg :: Text -> Series -> Svg
    lineSvg cls s = do
      -- runs of consecutive values, so that gaps break the line
      let pts = [ fmap (\q -> (j, xcenter j, yofline (toD q), q)) (valueAt vals j) | let vals = seriesValues s, j <- [0 .. n - 1] ]
      forM_ (runs pts) $ \run ->
        S.polyline ! A.class_ ("line " <> toValue cls)
          ! A.points (toValue $ T.unwords [num x <> "," <> num y | (x, y) <- thinPoints $ (if isJust datearray then steps else id) [(x, y) | (_, x, y, _) <- run]])
      -- invisible larger targets, for tooltips (only when there are not too many points)
      when (n <= 400) $ forM_ (catMaybes pts) $ \(j, x, y, q) -> withTooltip (tooltip (fromMaybe "" $ xlabels `atMay` j) s q) $
        S.circle ! A.class_ "hit" ! A.cx (toValue $ num x) ! A.cy (toValue $ num y) ! A.r "6"
    tooltip :: Text -> Series -> Quantity -> Text
    tooltip lbl s q = T.intercalate " · " (filter (not . T.null) [lbl, lbFull (seLabel s), showValue unit q])

-- | Draw series of categories as horizontal bars (stacked if several), with labels and a value column.
-- | Draw series of categories (eg accounts): as vertical bars, or as horizontal bars when there are more than 'maxColumns' categories.
-- Categories with no values at all (eg accounts without this commodity) are left out.
-- With a single series, each category's bar has its own account type's colour, if known.
categoriesSvg :: Double -> Maybe Quantity -> Amount -> [DrawSeries] -> Maybe Series -> [ChartLabel] -> (Double, Svg)
categoriesSvg top mscale unit drawn mtotal labels
  | length rows <= maxColumns = columnsSvg top mscale unit rows rowValue
  | otherwise                 = barsSvg top mscale unit rows rowValue
  where
    rows = [ (l, j, [(categoryColoured l d, q) | d <- drawn, Just q <- [valueAt (dsValues d) j]])
           | (j, l) <- zip [0 ..] labels, not $ all (isNothing . flip valueAt j . dsValues) drawn ]
    categoryColoured lbl d = case (drawn, lbType lbl) of
      ([_], Just at) -> d{dsClass = colourClass $ TypeColour (mainAccountType at) 0}
      _              -> d
    mtotalvals = seriesValues <$> mtotal
    -- the value to show for each category: the total's, or the single series'
    rowValue j = case (mtotal, drawn) of
      (Just _, _) -> mtotalvals >>= flip valueAt j
      (_, [d])    -> valueAt (dsValues d) j
      _           -> Nothing

-- | The most categories to draw as vertical bars; beyond this, they are drawn as horizontal bars (rows), which can show many more names.
maxColumns :: Int
maxColumns = 30

-- | Draw categories as vertical bars (stacked if several series), with their names below (angled if they don't fit),
-- and their values above the bars (when they fit).
columnsSvg :: Double -> Maybe Quantity -> Amount -> [(ChartLabel, Int, [(DrawSeries, Quantity)])] -> (Int -> Maybe Quantity) -> (Double, Svg)
columnsSvg top mscale unit rows rowValue = (plotHeight + 22 + negroom + labelheight, do
    -- gridlines and y tick labels
    forM_ ticks $ \t -> do
      S.line ! A.class_ (if t == 0 then "axis" else "grid")
        ! A.x1 (toValue $ num plotleft) ! A.x2 (toValue $ num plotright) ! A.y1 (toValue $ num (yof t)) ! A.y2 (toValue $ num (yof t))
      S.text_ ! A.class_ "tick" ! A.x (toValue $ num (plotleft - 8)) ! A.y (toValue $ num (yof t + 4)) ! A.textAnchor "end" $ S.toMarkup (ticklabel t)
    forM_ (zip [0 :: Int ..] rows) $ \(i, (lbl, j, segs)) -> do
      let x = xcenter i
          name = shortName lbl
          ly = plotbottom + negroom + 16
      -- the category's name, below; angled (reading upward to the bar) if the names don't fit
      if angled
      then S.text_ ! A.class_ "label" ! A.x (toValue $ num (x + 4)) ! A.y (toValue $ num ly) ! A.textAnchor "end"
             ! A.transform (toValue $ "rotate(-45 " <> num (x + 4) <> " " <> num ly <> ")") $ S.toMarkup name
      else S.text_ ! A.class_ "label" ! A.x (toValue $ num x) ! A.y (toValue $ num ly) ! A.textAnchor "middle" $ S.toMarkup name
      -- the bar
      let tip d q = T.intercalate " · " $ nub [lbFull lbl, lbFull (seLabel $ dsSeries d), showValue unit q]
          bx = x - barwidth / 2
      vstack (lo, hi) yof bx barwidth [(d, q, tip d q) | (d, q) <- segs, q > 0] 1
      vstack (lo, hi) yof bx barwidth [(d, q, tip d q) | (d, q) <- segs, q < 0] (-1)
      -- the value, above the bar (or below, if negative), if it fits
      forM_ (rowValue j) $ \q -> do
        let v = showValue unit q
            pos = sum [toD a | (_, a) <- segs, a > 0]
            neg = sum [toD a | (_, a) <- segs, a < 0]
            cliproom = if pos > hi || neg < lo then 6 else 0  -- room for a clip mark
            vy = if q >= 0 then yof pos - 6 - cliproom else yof neg + 14 + cliproom
        when (textWidth v <= band - 2) $
          S.text_ ! A.class_ "value" ! A.x (toValue $ num x) ! A.y (toValue $ num vy) ! A.textAnchor "middle" $ S.toMarkup v
  )
  where
    n = length rows
    stackedsums sign = [sum [toD q | (_, q) <- segs, signum q == sign] | (_, _, segs) <- rows]
    (lo, hi, ticks, tickdecimals) = panelScale mscale (minimumDef 0 $ stackedsums (-1)) (maximumDef 0 $ stackedsums 1)
    ticklabel t = showValue (withPrecision tickdecimals unit) (tickQuantity tickdecimals t)
    plotleft = pad + maximumDef 0 (map (textWidth . ticklabel) ticks) + 12
    plotright = chartWidth - pad
    plottop = top + 20  -- leaving room for values above the bars
    plotbottom = plottop + plotHeight
    yof v = plottop + plotHeight * (hi - clamp lo hi v) / (hi - lo)
    band = (plotright - plotleft) / fromIntegral (max 1 n)
    xcenter i = plotleft + band * (fromIntegral i + 0.5)
    barwidth = max 1 $ min 24 (band * 0.7)
    -- names: full account names (since there's no indentation), shortened if very long
    shortName l = let t = lbFull l in if T.length t > 30 then T.take 29 t <> "…" else t
    namewidth = maximumDef 0 [textWidth (shortName l) | (l, _, _) <- rows]
    angled = namewidth > band - 4
    labelheight = if angled then namewidth * 0.71 + 16 else 24
    -- room below the plot for the values of negative bars, which may reach its bottom
    negroom = if any (any ((< 0) . snd) . (\(_, _, segs) -> segs)) rows then (if isJust mscale then 22 else 16) else 0

-- | Draw categories as horizontal bars (rows; stacked if several series), with their names on the left (indented as in the report)
-- and an aligned value column on the right.
barsSvg :: Double -> Maybe Quantity -> Amount -> [(ChartLabel, Int, [(DrawSeries, Quantity)])] -> (Int -> Maybe Quantity) -> (Double, Svg)
barsSvg top mscale unit rows rowValue = (fromIntegral (length rows) * rowHeight + 28, do
    -- gridlines and x tick labels (labels thinned to avoid overlap, always including zero)
    forM_ ticks $ \t -> do
      S.line ! A.class_ (if t == 0 then "axis" else "grid")
        ! A.x1 (toValue $ num (xof t)) ! A.x2 (toValue $ num (xof t)) ! A.y1 (toValue $ num plottop) ! A.y2 (toValue $ num plotbottom)
      when (round (t / tickstep) `mod` labelevery == (0 :: Integer)) $
        S.text_ ! A.class_ "tick" ! A.x (toValue $ num (xof t)) ! A.y (toValue $ num (plotbottom + 18)) ! A.textAnchor "middle" $ S.toMarkup (ticklabel t)
    forM_ (zip [0 :: Int ..] rows) $ \(i, (lbl, j, segs)) -> do
      let ymid = plottop + rowHeight * (fromIntegral i + 0.5)
      S.text_ ! A.class_ "label" ! A.x (toValue $ num (pad + 12 * fromIntegral (lbIndent lbl))) ! A.y (toValue $ num (ymid + 4))
        $ S.toMarkup (lbShort lbl)
      forM_ (rowValue j) $ \q ->
        S.text_ ! A.class_ "value" ! A.x (toValue $ num (chartWidth - pad)) ! A.y (toValue $ num (ymid + 4)) ! A.textAnchor "end"
          $ S.toMarkup (showValue unit q)
      stack lbl ymid [(d, q) | (d, q) <- segs, q > 0] 1
      stack lbl ymid [(d, q) | (d, q) <- segs, q < 0] (-1)
  )
  where
    stackedsums sign = [sum [toD q | (_, q) <- segs, signum q == sign] | (_, _, segs) <- rows]
    (lo, hi, ticks, tickdecimals) = panelScale mscale (minimumDef 0 $ stackedsums (-1)) (maximumDef 0 $ stackedsums 1)
    ticklabel t = showValue (withPrecision tickdecimals unit) (tickQuantity tickdecimals t)
    labelwidth = min (chartWidth * 0.4) $ maximumDef 0 [12 * fromIntegral (lbIndent l) + textWidth (lbShort l) | (l, _, _) <- rows]
    valuewidth = maximumDef 0 [textWidth (showValue unit q) | (_, j, _) <- rows, Just q <- [rowValue j]]
    -- leave room for half of a tick label at each end
    edge = maximumDef 0 (map (textWidth . ticklabel) ticks) / 2
    plotleft = pad + max labelwidth edge + 12
    plotright = chartWidth - pad - max valuewidth edge - 16
    plottop = top + 4
    plotbottom = plottop + rowHeight * fromIntegral (length rows)
    xof v = plotleft + (plotright - plotleft) * (clamp lo hi v - lo) / (hi - lo)
    tickstep = case ticks of t1:t2:_ -> t2 - t1; _ -> 1
    labelevery = max 1 $ ceiling ((maximumDef 0 (map (textWidth . ticklabel) ticks) + 12) / max 1 (xof tickstep - xof 0)) :: Integer
    thickness = 12
    stack :: ChartLabel -> Double -> [(DrawSeries, Quantity)] -> Double -> Svg
    stack lbl ymid segs sign = do
      let cums = scanl1 (+) (map (toD . snd) segs)
          starts = 0 : cums
          lastk = length segs - 1
          clipped = any (\c -> c > hi || c < lo) (lastMay cums)
      forM_ (zip3 [0 :: Int ..] segs (zip starts cums)) $ \(k, (d, q), (c0, c1)) -> do
        let gap = if k > 0 && abs (xof c1 - xof c0) >= 4 then 2 else 0  -- no gap for tiny segments, which it would hide
            xbase = xof c0 + sign * gap   -- the end nearer the axis, after the gap (the sums are negative for negative segments)
            len = (xof c1 - xbase) * sign
        when (len > 0.5) $ withTooltip (T.intercalate " · " [lbFull lbl, lbFull (seLabel $ dsSeries d), showValue unit q]) $
          S.path ! A.class_ ("fill " <> toValue (dsClass d))
            ! A.d (toValue $ barPath False xbase (ymid - thickness / 2) thickness (sign * len) (k == lastk && not clipped))
      -- a bar clipped by a fixed scale has a small triangle beyond its end
      when clipped $ clipMark False (xof $ if sign > 0 then hi else lo) ymid thickness sign

-- | One direction of a vertical stacked bar, with its left edge at x and the given width, on a y scale:
-- segments (each with its series, value and tooltip) from zero outward (up if sign is 1, down if -1),
-- 2px apart (except tiny ones, which a gap would hide), the outermost with a rounded end.
-- If the bar extends beyond the y scale's range (lo, hi), it is clipped, with a small triangle beyond its end instead.
vstack :: (Double, Double) -> (Double -> Double) -> Double -> Double -> [(DrawSeries, Quantity, Text)] -> Double -> Svg
vstack (lo, hi) yof x width segs sign = do
  let cums = scanl1 (+) [toD q | (_, q, _) <- segs]
      starts = 0 : cums
      lastk = length segs - 1
      clipped = any (\c -> c > hi || c < lo) (lastMay cums)
  forM_ (zip3 [0 :: Int ..] segs (zip starts cums)) $ \(k, (d, _, tip), (c0, c1)) -> do
    let gap = if k > 0 && abs (yof c1 - yof c0) >= 4 then 2 else 0
        ybase = yof c0 - sign * gap   -- the end nearer zero, after the gap
        len = (ybase - yof c1) * sign  -- positive when there is something to draw
    when (len > 0.5) $ withTooltip tip $
      S.path ! A.class_ ("fill " <> toValue (dsClass d))
        ! A.d (toValue $ barPath True x ybase width (-sign * len) (k == lastk && not clipped))
  when clipped $ clipMark True (yof $ if sign > 0 then hi else lo) (x + width / 2) width sign

-- | A small triangle pointing outward from the edge of a plot, marking a bar that was clipped there:
-- for a vertical bar (at y position edge, centred on x position mid) or a horizontal one (at x position edge, centred on y position mid).
-- sign is the direction in which the bar grows (1: up or right, -1: down or left).
clipMark :: Bool -> Double -> Double -> Double -> Double -> Svg
clipMark vertical edge mid barsize sign =
  S.polygon ! A.class_ "clip" ! A.points (toValue $ T.unwords [num a <> "," <> num b | (a, b) <- map orient pts])
  where
    w = max 6 $ min 10 barsize
    -- the points as (position across the bar, distance outward from the edge)
    pts = [(mid - w / 2, 0), (mid + w / 2, 0), (mid, w / 2)]
    orient (across, out)
      | vertical  = (across, edge - sign * out)
      | otherwise = (edge + sign * out, across)

-- | The points of a step line through these points: each value holds until the next point's x position.
steps :: [(Double, Double)] -> [(Double, Double)]
steps ps = take 1 ps ++ concat (zipWith (\(_, py) (x, y) -> [(x, py), (x, y)]) ps (drop 1 ps))

-- | Reduce a line's points to at most four per pixel column (the first, lowest, highest and last, in their original order),
-- which draws the same line, but keeps the SVG small when there are many more points than pixels (eg a long register).
thinPoints :: [(Double, Double)] -> [(Double, Double)]
thinPoints = concatMap thin . groupBy ((==) `on` (column . fst))
  where
    column :: Double -> Integer
    column = round
    thin ps
      | length ps <= 4 = ps
      | otherwise = M.elems $ M.fromList $ catMaybes [headMay indexed, extreme (<), extreme (>), lastMay indexed]
      where
        indexed = zip [0 :: Int ..] ps
        -- the first point whose y is better than all others' by this comparison
        extreme better = foldl' (\acc p -> case acc of
                                   Just (_, (_, y')) | not (snd (snd p) `better` y') -> acc
                                   _ -> Just p) Nothing indexed

-- | Up to 8 ticks for a date axis from the first to the last date, at calendar boundaries
-- (every 1, 2, 7 or 14 days, every 1, 2, 3 or 6 months, or every 1, 2, 5, 10.. years), with labels.
dateTicks :: Day -> Day -> [(Day, Text)]
dateTicks d0 d1 = fromMaybe [] $ find ((<= 8) . length) candidates
  where
    (y0, _, _) = toGregorian d0
    (y1, _, _) = toGregorian d1
    candidates = [dayticks k | k <- [1, 2, 7, 14]] ++ [monthticks k | k <- [1, 2, 3, 6]] ++ [yearticks k | k <- [1, 2, 5, 10, 20, 50, 100, 1000]]
    inrange d = d >= d0 && d <= d1
    dayticks k = [(d, showDate d) | d <- takeWhile (<= d1) $ iterate (addDays k) d0]
    monthticks k = [ (d, T.pack $ printf "%04d-%02d" y m)
                   | y <- [y0 .. y1], m <- [1 .. 12], (m - 1) `mod` k == 0, let d = fromGregorian y m 1, inrange d ]
    yearticks k = [ (d, T.pack $ show y) | y <- [y0 .. y1], y `mod` k == 0, let d = fromGregorian y 1 1, inrange d ]

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

-- | The scale for a panel's values, given their range (which should include 0): a nice scale covering it ('niceScale'),
-- or with a fixed scale, exactly the range it spans ('scaleSpans'), with the nice scale's ticks that are within it.
panelScale :: Maybe Quantity -> Double -> Double -> (Double, Double, [Double], Int)
panelScale mscale datamin datamax = case mscale of
  Just s | s > 0 ->
    let (hi, neg) = scaleSpans (toD s) (max 0 datamax) (abs $ min 0 datamin)
        lo = negate neg
        (_, _, ticks, decimals) = niceScale lo hi
        eps = (hi - lo) * 1e-9
    in (lo, hi, filter (\t -> t >= lo - eps && t <= hi + eps) ticks, decimals)
  _ -> niceScale datamin datamax

-- | Limit a value to a range.
clamp :: Double -> Double -> Double -> Double
clamp lo hi = max lo . min hi

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

-- | The CSS class for a colour. (The rules are in 'stylesheet'.)
colourClass :: Colour -> Text
colourClass c = case c of
  TypeColour at k -> "t" <> typeCode (mainAccountType at) <> T.pack (show (k `mod` maxTints))
  IndexColour k   -> "s" <> T.pack (show (k `mod` 8))
  NeutralColour   -> "neutral"
  OtherColour     -> "other"
  TotalColour     -> "total"

-- | A short code for each main account type, for CSS class names.
typeCode :: AccountType -> Text
typeCode at = case at of
  Asset     -> "a"
  Liability -> "l"
  Equity    -> "e"
  Revenue   -> "r"
  Expense   -> "x"
  _         -> "e"

-- | The chart's styles: a colour-blind-safe categorical palette (8 slots) and chart chrome colours,
-- with a dark variant used when the viewer prefers a dark colour scheme.
-- Colours are written literally in each rule (rather than as CSS custom properties),
-- since some SVG renderers (eg librsvg, used by many image viewers) don't support those.
stylesheet :: Bool -> Text
stylesheet dark = T.unlines $
  [ ".hledger-chart{font-family:system-ui,-apple-system,\"Segoe UI\",sans-serif;font-size:12px}"
  , ".hledger-chart .title{font-size:14px;font-weight:600}"
  , ".hledger-chart .heading{font-size:13px;font-weight:600}"
  , ".hledger-chart .value,.hledger-chart .tick{font-variant-numeric:tabular-nums}"
  , ".hledger-chart .grid,.hledger-chart .axis{stroke-width:1}"
  , ".hledger-chart .line{fill:none;stroke-width:2;stroke-linejoin:round;stroke-linecap:round}"
  , ".hledger-chart .mark{stroke-width:1.5}"
  , ".hledger-chart .hit{fill:transparent}"
  ]
  ++ colourRules False lightcolours
  ++ (if dark then ["@media (prefers-color-scheme:dark){"] ++ colourRules True darkcolours ++ ["}"] else [])
  where
    -- the chart chrome's colours, and the series' colours (from "Hledger.Write.Chart.Palette")
    colourRules isdark cs =
      [ ".hledger-chart " <> sel <> "{" <> prop <> ":" <> colour <> "}"
      | (sel, prop, role) <- rules, Just colour <- [lookup role cs] ]
      ++ concat [ [ ".hledger-chart .fill." <> cls <> "{fill:" <> hex <> "}", ".hledger-chart .line." <> cls <> "{stroke:" <> hex <> "}" ]
                | c <- seriescolours, let cls = colourClass c, let hex = colourHex isdark c ]
    seriescolours =
      [TypeColour at k | at <- [Asset, Liability, Equity, Revenue, Expense], k <- [0 .. maxTints - 1]]
      ++ map IndexColour [0 .. 7] ++ [OtherColour, NeutralColour]
    rules =
      [ (".bg", "fill", "surface"), (".title", "fill", "ink"), (".heading", "fill", "ink")
      , (".label", "fill", "ink2"), (".value", "fill", "ink2"), (".tick", "fill", "muted")
      , (".grid", "stroke", "grid"), (".axis", "stroke", "axis")
      , (".line.total", "stroke", "ink"), (".mark.total", "stroke", "ink"), (".clip", "fill", "ink")
      ]
    lightcolours :: [(Text, Text)]
    lightcolours =
      [ ("surface", "#fcfcfb"), ("ink", "#0b0b0b"), ("ink2", "#52514e"), ("muted", "#898781"), ("grid", "#e1e0d9"), ("axis", "#c3c2b7") ]
    darkcolours =
      [ ("surface", "#1a1a19"), ("ink", "#ffffff"), ("ink2", "#c3c2b7"), ("muted", "#898781"), ("grid", "#2c2c2a"), ("axis", "#383835") ]

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
