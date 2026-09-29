-- | Text.Tabular.AsciiArt from tabular-0.2.2.7, modified to treat
-- wide characters as double width.

{-# LANGUAGE OverloadedStrings #-}

module Text.Tabular.AsciiWide
( module Text.Tabular

, TableOpts(..)
, render
, renderTable
, renderTableB
, renderTableByRowsB
, renderRow
, renderRowB
, renderColumns

, Cell(..)
, Align(..)
, emptyCell
, textCell
, textsCell
, cellWidth
, concatTables
) where

import Data.Bifunctor (bimap)
import Data.Maybe (fromMaybe)
import Data.Default (Default(..))
import Data.List (intersperse, transpose)
import Data.Semigroup (stimesMonoid)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Lazy qualified as TL
import Data.Text.Lazy.Builder (Builder, fromString, fromText, singleton, toLazyText)
import Safe (maximumMay)
import Text.Tabular
import Text.WideString (WideBuilder(..), wbFromText)


-- | The options to use for rendering a table.
data TableOpts = TableOpts
  { prettyTable  :: Bool  -- ^ Pretty tables
  , tableBorders :: Bool  -- ^ Whether to display the outer borders
  , borderSpaces :: Bool  -- ^ Whether to display spaces around bars
  } deriving (Show)

instance Default TableOpts where
  def = TableOpts { prettyTable  = False
                  , tableBorders = True
                  , borderSpaces = True
                  }

-- | Cell contents along an alignment
data Cell = Cell Align [WideBuilder]

-- | How to align text in a cell
data Align = TopRight | BottomRight | BottomLeft | TopLeft
  deriving (Show)

emptyCell :: Cell
emptyCell = Cell TopRight []

-- | Create a single-line cell from the given contents with its natural width.
textCell :: Align -> Text -> Cell
textCell a x = Cell a . map wbFromText $ if T.null x then [""] else T.lines x

-- | Create a multi-line cell from the given contents with its natural width.
textsCell :: Align -> [Text] -> Cell
textsCell a = Cell a . fmap wbFromText

-- | Return the width of a Cell.
cellWidth :: Cell -> Int
cellWidth (Cell _ xs) = fromMaybe 0 . maximumMay $ map wbWidth xs


-- | Render a table according to common options, for backwards compatibility
render :: Show a => Bool -> (rh -> Text) -> (ch -> Text) -> (a -> Text) -> Table rh ch a -> TL.Text
render pretty fr fc f = renderTable def{prettyTable=pretty} (cell . fr) (cell . fc) (cell . f)
  where cell = textCell TopRight

-- | Render a table according to various cell specifications>
renderTable :: Show a =>
               TableOpts       -- ^ Options controlling Table rendering
            -> (rh -> Cell)  -- ^ Rendering function for row headers
            -> (ch -> Cell)  -- ^ Rendering function for column headers
            -> (a -> Cell)   -- ^ Function determining the string and width of a cell
            -> Table rh ch a
            -> TL.Text
renderTable topts fr fc f = toLazyText . renderTableB topts fr fc f

-- | A version of renderTable which returns the underlying Builder.
renderTableB :: Show a =>
                TableOpts       -- ^ Options controlling Table rendering
             -> (rh -> Cell)  -- ^ Rendering function for row headers
             -> (ch -> Cell)  -- ^ Rendering function for column headers
             -> (a -> Cell)   -- ^ Function determining the string and width of a cell
             -> Table rh ch a
             -> Builder
renderTableB topts fr fc f = renderTableByRowsB topts (fmap fc) $ bimap fr (fmap f)

-- | A version of renderTable that operates on rows (including the 'row' of
-- column headers) and returns the underlying Builder.
renderTableByRowsB :: Show a =>
                TableOpts      -- ^ Options controlling Table rendering
             -> ([ch] -> [Cell])     -- ^ Rendering function for column headers
             -> ((rh, [a]) -> (Cell, [Cell])) -- ^ Rendering function for row and row header
             -> Table rh ch a
             -> Builder
renderTableByRowsB topts@TableOpts{prettyTable=pretty, tableBorders=borders} fc f (Table rh ch cells) =
   unlinesB . addBorders $
     renderColumns topts sizes ch2
     : bar VM DoubleLine   -- +======================================+
     : renderRs (renderR <$> zipHeader [] cellContents rowHeaders)
 where
  renderR :: ([Cell], Cell) -> Builder
  renderR (cs,h) = renderColumns topts sizes $ Group DoubleLine
                     [ Header h
                     , fst <$> zipHeader emptyCell cs colHeaders
                     ]

  rows         = unzip . fmap f $ zip (headerContents rh) cells
  rowHeaders   = fst <$> zipHeader emptyCell (fst rows) rh
  colHeaders   = fst <$> zipHeader emptyCell (fc $ headerContents ch) ch
  cellContents = snd rows

  -- ch2 and cell2 include the row and column labels
  ch2 = Group DoubleLine [Header emptyCell, colHeaders]
  cells2 = headerContents ch2 : zipWith (:) (headerContents rowHeaders) cellContents

  -- maximum width for each column
  sizes = map (fromMaybe 0 . maximumMay . map cellWidth) $ transpose cells2
  renderRs =
    concatMap (either (renderHLine VM borders pretty sizes ch2) (:[])) .
    flattenHeader

  -- borders and bars
  addBorders xs = if borders then bar VT SingleLine : xs ++ [bar VB SingleLine] else xs
  bar vpos prop = mconcat $ renderHLine vpos borders pretty sizes ch2 prop
  unlinesB = foldMap (<> singleton '\n')

-- | Render a single row according to cell specifications.
renderRow :: TableOpts -> Header Cell -> TL.Text
renderRow topts = toLazyText . renderRowB topts

-- | A version of renderRow which returns the underlying Builder.
renderRowB:: TableOpts -> Header Cell -> Builder
renderRowB topts h = renderColumns topts ws h where ws = map cellWidth $ headerContents h

verticalBar :: Bool -> Char
verticalBar pretty = if pretty then '│' else '|'

leftBar :: Bool -> Bool -> Builder
leftBar pretty True  = fromString $ verticalBar pretty : " "
leftBar pretty False = singleton $ verticalBar pretty

rightBar :: Bool -> Bool -> Builder
rightBar pretty True  = fromString $ ' ' : [verticalBar pretty]
rightBar pretty False = singleton $ verticalBar pretty

midBar :: Bool -> Bool -> Builder
midBar pretty True  = fromString $ ' ' : verticalBar pretty : " "
midBar pretty False = singleton $ verticalBar pretty

doubleMidBar :: Bool -> Bool -> Builder
doubleMidBar pretty True  = fromText $ if pretty then " ║ " else " || "
doubleMidBar pretty False = fromText $ if pretty then "║" else "||"

-- | We stop rendering on the shortest list!
renderColumns :: TableOpts  -- ^ rendering options for the table
              -> [Int]      -- ^ max width for each column
              -> Header Cell
              -> Builder
renderColumns TableOpts{prettyTable=pretty, tableBorders=borders, borderSpaces=spaces} is h =
    mconcat . intersperse "\n"                   -- Put each line on its own line
    . map (addBorders . mconcat) . transpose     -- Change to a list of lines and add borders
    . map (either hsep padCell) . flattenHeader  -- We now have a matrix of strings
    . zipHeader 0 is $ padRow <$> h  -- Pad cell height and add width marker
  where
    -- Pad each cell to have the appropriate width
    padCell (w, Cell TopLeft     ls) = map (\x -> wbBuilder x <> fromText (T.replicate (w - wbWidth x) " ")) ls
    padCell (w, Cell BottomLeft  ls) = map (\x -> wbBuilder x <> fromText (T.replicate (w - wbWidth x) " ")) ls
    padCell (w, Cell TopRight    ls) = map (\x -> fromText (T.replicate (w - wbWidth x) " ") <> wbBuilder x) ls
    padCell (w, Cell BottomRight ls) = map (\x -> fromText (T.replicate (w - wbWidth x) " ") <> wbBuilder x) ls


    -- Pad each cell to have the same number of lines
    padRow (Cell TopLeft     ls) = Cell TopLeft     $ ls ++ replicate (nLines - length ls) mempty
    padRow (Cell TopRight    ls) = Cell TopRight    $ ls ++ replicate (nLines - length ls) mempty
    padRow (Cell BottomLeft  ls) = Cell BottomLeft  $ replicate (nLines - length ls) mempty ++ ls
    padRow (Cell BottomRight ls) = Cell BottomRight $ replicate (nLines - length ls) mempty ++ ls

    hsep :: Properties -> [Builder]
    hsep NoLine     = replicate nLines $ if spaces then "  " else ""
    hsep SingleLine = replicate nLines $ midBar pretty spaces
    hsep DoubleLine = replicate nLines $ doubleMidBar pretty spaces

    addBorders xs | borders   = leftBar pretty spaces <> xs <> rightBar pretty spaces
                  | spaces    = fromText " " <> xs <> fromText " "
                  | otherwise = xs

    nLines = fromMaybe 0 . maximumMay . map (\(Cell _ ls) -> length ls) $ headerContents h

renderHLine :: VPos
            -> Bool  -- ^ show outer borders
            -> Bool -- ^ pretty
            -> [Int] -- ^ width specifications
            -> Header a
            -> Properties
            -> [Builder]
renderHLine _ _ _ _ _ NoLine = []
renderHLine vpos borders pretty w h prop = [renderHLine' vpos borders pretty prop w h]

renderHLine' :: VPos -> Bool -> Bool -> Properties -> [Int] -> Header a -> Builder
renderHLine' vpos borders pretty prop is hdr = addBorders $ sep <> coreLine <> sep
 where
  addBorders xs   = if borders then edge HL <> xs <> edge HR else xs
  edge hpos       = boxchar vpos hpos SingleLine prop pretty
  coreLine        = foldMap helper $ flattenHeader $ zipHeader 0 is hdr
  helper          = either vsep dashes
  dashes (i,_)    = stimesMonoid i sep
  sep             = boxchar vpos HM NoLine prop pretty
  vsep v          = case v of
                      NoLine -> sep <> sep
                      _      -> sep <> cross v prop <> sep
  cross v h       = boxchar vpos HM v h pretty

data VPos = VT | VM | VB -- top middle bottom
data HPos = HL | HM | HR -- left middle right

boxchar :: VPos -> HPos -> Properties -> Properties -> Bool -> Builder
boxchar vpos hpos vert horiz = lineart u d l r
  where
    u = case vpos of
          VT -> NoLine
          _  -> vert
    d = case vpos of
          VB -> NoLine
          _  -> vert
    l = case hpos of
          HL -> NoLine
          _  -> horiz
    r = case hpos of
          HR -> NoLine
          _  -> horiz

pick :: Text -> Text -> Bool -> Builder
pick x _ True  = fromText x
pick _ x False = fromText x

lineart :: Properties -> Properties -> Properties -> Properties -> Bool -> Builder
--      up         down       left      right
lineart SingleLine SingleLine SingleLine SingleLine = pick "┼" "+"
lineart SingleLine SingleLine SingleLine NoLine     = pick "┤" "+"
lineart SingleLine SingleLine NoLine     SingleLine = pick "├" "+"
lineart SingleLine NoLine     SingleLine SingleLine = pick "┴" "+"
lineart NoLine     SingleLine SingleLine SingleLine = pick "┬" "+"
lineart SingleLine NoLine     NoLine     SingleLine = pick "└" "+"
lineart SingleLine NoLine     SingleLine NoLine     = pick "┘" "+"
lineart NoLine     SingleLine SingleLine NoLine     = pick "┐" "+"
lineart NoLine     SingleLine NoLine     SingleLine = pick "┌" "+"
lineart SingleLine SingleLine NoLine     NoLine     = pick "│" "|"
lineart NoLine     NoLine     SingleLine SingleLine = pick "─" "-"

lineart DoubleLine DoubleLine DoubleLine DoubleLine = pick "╬" "++"
lineart DoubleLine DoubleLine DoubleLine NoLine     = pick "╣" "++"
lineart DoubleLine DoubleLine NoLine     DoubleLine = pick "╠" "++"
lineart DoubleLine NoLine     DoubleLine DoubleLine = pick "╩" "++"
lineart NoLine     DoubleLine DoubleLine DoubleLine = pick "╦" "++"
lineart DoubleLine NoLine     NoLine     DoubleLine = pick "╚" "++"
lineart DoubleLine NoLine     DoubleLine NoLine     = pick "╝" "++"
lineart NoLine     DoubleLine DoubleLine NoLine     = pick "╗" "++"
lineart NoLine     DoubleLine NoLine     DoubleLine = pick "╔" "++"
lineart DoubleLine DoubleLine NoLine     NoLine     = pick "║" "||"
lineart NoLine     NoLine     DoubleLine DoubleLine = pick "═" "="

lineart DoubleLine NoLine     NoLine     SingleLine = pick "╙" "++"
lineart DoubleLine NoLine     SingleLine NoLine     = pick "╜" "++"
lineart NoLine     DoubleLine SingleLine NoLine     = pick "╖" "++"
lineart NoLine     DoubleLine NoLine     SingleLine = pick "╓" "++"

lineart SingleLine NoLine     NoLine     DoubleLine = pick "╘" "+"
lineart SingleLine NoLine     DoubleLine NoLine     = pick "╛" "+"
lineart NoLine     SingleLine DoubleLine NoLine     = pick "╕" "+"
lineart NoLine     SingleLine NoLine     DoubleLine = pick "╒" "+"

lineart DoubleLine DoubleLine SingleLine NoLine     = pick "╢" "++"
lineart DoubleLine DoubleLine NoLine     SingleLine = pick "╟" "++"
lineart DoubleLine NoLine     SingleLine SingleLine = pick "╨" "++"
lineart NoLine     DoubleLine SingleLine SingleLine = pick "╥" "++"

lineart SingleLine SingleLine DoubleLine NoLine     = pick "╡" "+"
lineart SingleLine SingleLine NoLine     DoubleLine = pick "╞" "+"
lineart SingleLine NoLine     DoubleLine DoubleLine = pick "╧" "+"
lineart NoLine     SingleLine DoubleLine DoubleLine = pick "╤" "+"

lineart SingleLine SingleLine DoubleLine DoubleLine = pick "╪" "+"
lineart DoubleLine DoubleLine SingleLine SingleLine = pick "╫" "++"

lineart _          _          _          _          = const mempty


-- | Add the second table below the first, discarding its column headings.
concatTables :: Properties -> Table rh ch a -> Table rh ch2 a -> Table rh ch a
concatTables prop (Table hLeft hTop dat) (Table hLeft' _ dat') =
    Table (Group prop [hLeft, hLeft']) hTop (dat ++ dat')
