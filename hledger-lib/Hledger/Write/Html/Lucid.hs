{-# LANGUAGE OverloadedStrings #-}
{- |
HTML writing helpers using lucid.
-}

module Hledger.Write.Html.Lucid (
    Html,
    L.toHtml,
    styledTableHtml,
    titledTableHtml,
    formatRow,
    formatCell,
    formatTitle,
    nl,
    ) where

import           Control.Monad (unless)
import           Data.Foldable (traverse_)
import           Data.List (intersperse)
import Data.Text qualified as Text
import Lucid.Base qualified as L
import Lucid qualified as L

import Hledger.Write.Html.Attribute qualified as Attr
import           Hledger.Write.Html.HtmlCommon
import           Hledger.Write.Spreadsheet (Type(..), Style(..), Emphasis(..), Cell(..))
import Hledger.Write.Spreadsheet qualified as Spr


type Html = L.Html ()

-- | A literal newline, to make the HTML output more human-readable.
-- Emit it only between elements, never inside cell content,
-- so it doesn't affect rendering.
nl :: Html
nl = L.toHtmlRaw ("\n"::Text.Text)

-- | Export spreadsheet table data as HTML table.
-- This is derived from <https://hackage.haskell.org/package/classify-frog-0.2.4.3/src/src/Spreadsheet/Format.hs>
styledTableHtml :: (Lines border) => [[Cell border Html]] -> Html
styledTableHtml = titledTableHtml Text.empty

-- | Like 'styledTableHtml', but with the given report title, if non-empty,
-- as a heading above the table.
titledTableHtml :: (Lines border) => Text.Text -> [[Cell border Html]] -> Html
titledTableHtml title table = do
    -- the builtin styles, then the optional user stylesheet so it can override them
    L.style_ Attr.tableStylesheet
    nl
    L.link_ [L.rel_ "stylesheet", L.href_ "hledger.css"]
    nl
    unless (Text.null title) $ formatTitle title
    L.table_ $ nl <> traverse_ formatRow table

formatRow:: (Lines border) => [Cell border Html] -> Html
formatRow row = L.tr_ (traverse_ formatCell row) <> nl

-- | Render a report title as an HTML heading.
formatTitle :: Text.Text -> Html
formatTitle title = L.h3_ [L.class_ "report-title"] (L.toHtml title) <> nl

formatCell :: (Lines border) => Cell border Html -> Html
formatCell cell =
    -- Wrap amounts in <span class="amount">, one per amount,
    -- so eg wrapping within amounts can be prevented with css.
    let amountSpan = L.span_ [L.class_ "amount"] in
    let str =
            case cellParts cell of
                [] -> case cellType cell of
                    TypeAmount _ -> amountSpan $ cellContent cell
                    _            -> cellContent cell
                parts ->
                    mconcat $ intersperse (L.toHtml (", "::Text.Text)) $
                    map amountSpan parts in
    let content =
            if Text.null $ cellAnchor cell
                then str
                else L.a_ [L.href_ $ cellAnchor cell] str in
    -- Mark date cells with a "date" class, so eg wrapping within dates
    -- can be prevented with css; borders are classes too.
    let class_ =
            map (L.class_ . Text.unwords) $
            filter (not . null) $
            [filter (not . Text.null) $
             Spr.textFromClass (cellClass cell) :
             ["date" | cellType cell == TypeDate] ++
             borderClasses cell] in
    let addSpan spanAttr n attrs =
            if n==1
                then attrs
                else spanAttr (Text.pack $ show n) : attrs in
    let span_ makeCell attrs cont =
            case Spr.cellSpan cell of
                Spr.NoSpan -> makeCell attrs cont
                Spr.Covered -> pure ()
                Spr.SpanHorizontal n ->
                    makeCell (addSpan L.colspan_ n attrs) cont
                Spr.SpanVertical n ->
                    makeCell (addSpan L.rowspan_ n attrs) cont
            in
    case cellStyle cell of
        Head -> span_ L.th_ class_ content
        Body emph ->
            let align =
                    case cellType cell of
                        TypeString -> []
                        TypeDate -> []
                        _ -> [L.makeAttribute "align" "right"]
                valign =
                    case Spr.cellSpan cell of
                        Spr.SpanVertical n ->
                            if n>1
                                then [L.makeAttribute "valign" "top"]
                                else []
                        _ -> []
                withEmph =
                    case emph of
                        Item -> id
                        Total -> L.b_
            in  span_ L.td_ (align++valign++class_) $
                withEmph content

