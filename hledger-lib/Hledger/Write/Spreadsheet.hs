{- |
Rich data type to describe data in a table.
This is the basis for ODS and HTML export.
-}
module Hledger.Write.Spreadsheet (
    Type(..),
    Style(..),
    Emphasis(..),
    Cell(..),
    Class(Class), textFromClass,
    Span(..),
    Border(..),
    Lines(..),
    NumLines(..),
    noBorder,
    defaultCell,
    headerCell,
    emptyCell,
    transposeCell,
    transpose,
    horizontalSpan,
    addHeaderBorders,
    addRowSpanHeader,
    addRowSpanHeaderNE,
    rawTableContent,
    cellFromMixedAmount,
    cellsFromMixedAmount,
    cellFromAmount,
    integerCell,
    ) where

import Hledger.Data.Amount qualified as Amt
import Hledger.Data.Types (Amount, MixedAmount, acommodity)
import Hledger.Data.Amount (AmountFormat)

import Data.Foldable qualified as Fold
import Data.List.NonEmpty (NonEmpty((:|)))
import Data.List qualified as List
import Data.Maybe (isNothing)
import Data.Text qualified as Text
import Data.Text (Text)
import Text.WideString (WideBuilder)

import Prelude hiding (span)


data Type =
      TypeString
    | TypeInteger
    | TypeAmount !Amount
    | TypeMixedAmount
    | TypeDate
    deriving (Eq, Ord, Show)

data Style = Body Emphasis | Head
    deriving (Eq, Ord, Show)

data Emphasis = Item | Total
    deriving (Eq, Ord, Show)


class Lines border where noLine :: border
instance Lines () where noLine = ()
instance Lines NumLines where noLine = NoLine

{- |
The same as Tab.Properties, but has 'Eq' and 'Ord' instances.
We need those for storing 'NumLines' in 'Set's.
-}
data NumLines = NoLine | SingleLine | DoubleLine
    deriving (Eq, Ord, Show)

data Border lines =
    Border {
        borderLeft, borderRight,
        borderTop, borderBottom :: lines
    }
    deriving (Eq, Ord, Show)

instance Functor Border where
    fmap f (Border left right top bottom) =
        Border (f left) (f right) (f top) (f bottom)

instance Applicative Border where
    pure a = Border a a a a
    Border fLeft fRight fTop fBottom <*> Border left right top bottom =
        Border (fLeft left) (fRight right) (fTop top) (fBottom bottom)

instance Foldable Border where
    foldMap f (Border left right top bottom) =
        f left <> f right <> f top <> f bottom

noBorder :: (Lines border) => Border border
noBorder = pure noLine

transposeBorder :: Border lines -> Border lines
transposeBorder (Border left right top bottom) =
    Border top bottom left right


newtype Class = Class Text

textFromClass :: Class -> Text
textFromClass (Class cls) = cls


{- |
* 'NoSpan' means a single unmerged cell.

* 'Covered' is a cell if it is part of a horizontally or vertically merged cell.
  We maintain these cells although they are ignored in HTML output.
  In contrast to that, FODS can store covered cells
  and allows to access the hidden cell content via formulas.
  CSV does not support merged cells
  and thus simply writes the content of covered cells.
  Maintaining 'Covered' cells also simplifies transposing.

* @'SpanHorizontal' n@ denotes the first cell in a row
  that is part of a merged cell.
  The merged cell contains @n@ atomic cells, including the first one.
  That is @SpanHorizontal 1@ is actually like @NoSpan@.
  The content of this cell is shown as content of the merged cell.

* @'SpanVertical' n@ starts a vertically merged cell.

The writer functions expect consistent data,
that is, 'Covered' cells must actually be part of a merged cell
and merged cells must only cover 'Covered' cells.
-}
data Span =
      NoSpan
    | Covered
    | SpanHorizontal Int
    | SpanVertical Int
    deriving (Eq)

transposeSpan :: Span -> Span
transposeSpan span =
    case span of
        NoSpan -> NoSpan
        Covered -> Covered
        SpanHorizontal n -> SpanVertical n
        SpanVertical n -> SpanHorizontal n

data Cell border text =
    Cell {
        cellType :: Type,
        cellBorder :: Border border,
        cellStyle :: Style,
        cellSpan :: Span,
        cellAnchor :: Text,
        cellClass :: Class,
        -- | The cell content split into parts to be joined with ", ":
        -- individual amounts of a multi-commodity amount, for writers
        -- (eg HTML) that want to style each amount separately.
        -- Empty for other cells and writers; 'cellContent' is always complete.
        cellParts :: [text],
        cellContent :: text
    }

instance Functor (Cell border) where
    fmap f (Cell typ border style span anchor class_ parts content) =
        Cell typ border style span anchor class_ (map f parts) (f content)

defaultCell :: (Lines border) => text -> Cell border text
defaultCell text =
    Cell {
        cellType = TypeString,
        cellBorder = noBorder,
        cellStyle = Body Item,
        cellSpan = NoSpan,
        cellAnchor = mempty,
        cellClass = Class mempty,
        cellParts = [],
        cellContent = text
    }

headerCell :: (Lines borders) => Text -> Cell borders Text
headerCell text = (defaultCell text) {cellStyle = Head}

emptyCell :: (Lines border, Monoid text) => Cell border text
emptyCell = defaultCell mempty

transposeCell :: Cell border text -> Cell border text
transposeCell cell =
    cell {
        cellBorder = transposeBorder $ cellBorder cell,
        cellSpan = transposeSpan $ cellSpan cell
    }

transpose :: [[Cell border text]] -> [[Cell border text]]
transpose = List.transpose . map (map transposeCell)


addHeaderBorders :: (Functor f) => f (Cell () text) -> f (Cell NumLines text)
addHeaderBorders =
    fmap (\c -> c {cellBorder = noBorder {borderBottom = DoubleLine}})

horizontalSpan ::
    (Lines border, Monoid text) =>
    [a] -> Cell border text -> [Cell border text]
horizontalSpan subCells cell =
    zipWith const
        (cell{cellSpan = SpanHorizontal $ length subCells}
            : repeat (emptyCell {cellSpan = Covered}))
        subCells

addRowSpanHeader ::
    Cell border text ->
    [[Cell border text]] -> [[Cell border text]]
addRowSpanHeader header = map Fold.toList . addRowSpanHeaderNE header

addRowSpanHeaderNE ::
    Cell border text ->
    [[Cell border text]] -> [NonEmpty (Cell border text)]
addRowSpanHeaderNE header rows =
    case rows of
        [] -> []
        [row] -> [header:|row]
        _ ->
            zipWith (:|)
                (header{cellSpan = SpanVertical (length rows)} :
                 repeat header{cellSpan = Covered})
                rows

rawTableContent :: (Functor f) => [f (Cell border text)] -> [f text]
rawTableContent = map (fmap cellContent)



-- | Add the "negative" class to a negative amount's cell, so that writers
-- with a stylesheet (HTML) can color it. A cell whose rendering rounds to
-- zero is not marked
markNegative :: Bool -> Class -> Class
markNegative False cls = cls
markNegative True (Class cls) =
    Class $ Text.unwords $ filter (not . Text.null) [cls, Text.pack "negative"]

cellFromMixedAmount ::
    (Lines border) =>
    AmountFormat -> (Class, MixedAmount) -> Cell border WideBuilder
cellFromMixedAmount bopts (cls, mixedAmt) =
    (defaultCell $ Amt.showMixedAmountB bopts mixedAmt) {
        cellClass =
          markNegative
            (Amt.isNegativeMixedAmount mixedAmt == Just True
             && not (Amt.mixedAmountLooksZero mixedAmt)) cls,
        cellType =
          case Amt.unifyMixedAmount mixedAmt of
            Just amt -> amountType bopts amt
            Nothing -> TypeMixedAmount,
        -- Individual amounts, for writers that style them separately (eg HTML).
        -- Only when they can be recovered exactly from the one-line rendering
        -- (padding to displayMinWidth is insignificant in those writers).
        cellParts =
          if Amt.displayOneLine bopts && isNothing (Amt.displayMaxWidth bopts)
            then map fst $ Amt.showMixedAmountOneLinePartsB bopts mixedAmt
            else []
    }

cellsFromMixedAmount ::
    (Lines border) =>
    AmountFormat -> (Class, MixedAmount) -> [Cell border WideBuilder]
cellsFromMixedAmount bopts (cls, mixedAmt) =
    map
        (\(str,amt) ->
            (defaultCell str) {
                cellClass =
                  markNegative
                    (Amt.isNegativeAmount amt && not (Amt.amountLooksZero amt)) cls,
                cellType = amountType bopts amt
            })
        (Amt.showMixedAmountLinesPartsB bopts mixedAmt)

cellFromAmount ::
    (Lines border) =>
    AmountFormat -> (Class, (wb, Amount)) -> Cell border wb
cellFromAmount bopts (cls, (str,amt)) =
    (defaultCell str) {
        cellClass =
          markNegative
            (Amt.isNegativeAmount amt && not (Amt.amountLooksZero amt)) cls,
        cellType = amountType bopts amt
    }

amountType :: AmountFormat -> Amount -> Type
amountType bopts amt =
    TypeAmount $
    if Amt.displayCommodity bopts
      then amt
      else amt {acommodity = Text.empty}


integerCell :: (Lines border) => Integer -> Cell border Text
integerCell k = (defaultCell $ Text.pack $ show k) {cellType = TypeInteger}
