{-# LANGUAGE OverloadedStrings #-}
{- |
HTML writing helpers using blaze-html, for hledger-web, whose pages are
blaze markup. CLI reports use "Hledger.Write.Html.Lucid", which has
evolved further than this module (amount spans, date classes, titles).
-}

module Hledger.Write.Html.Blaze (
    styledTableHtml,
    formatRow,
    formatCell,
    ) where

import Hledger.Write.Html.Attribute qualified as Attr
import Hledger.Write.Spreadsheet qualified as Spr
import Hledger.Write.Html.HtmlCommon (Lines, borderClasses)
import Hledger.Write.Spreadsheet (Type(..), Style(..), Emphasis(..), Cell(..))

import Text.Blaze.Html4.Transitional.Attributes qualified as HtmlAttr
import Text.Blaze.Html4.Transitional qualified as Html
import Data.Text qualified as Text
import Text.Blaze.Html4.Transitional (Html, toHtml, (!))
import Data.Foldable (traverse_)


-- | Export spreadsheet table data as HTML table.
-- This is derived from <https://hackage.haskell.org/package/classify-frog-0.2.4.3/src/src/Spreadsheet/Format.hs>
styledTableHtml :: (Lines border) => [[Cell border Html]] -> Html
styledTableHtml table = do
    Html.style $ toHtml $ Attr.tableStylesheet
    Html.table $ traverse_ formatRow table

formatRow:: (Lines border) => [Cell border Html] -> Html
formatRow = Html.tr . traverse_ formatCell

formatCell :: (Lines border) => Cell border Html -> Html
formatCell cell =
    let str = cellContent cell in
    let content =
            if Text.null $ cellAnchor cell
                then str
                else Html.a str !
                        HtmlAttr.href (Html.textValue (cellAnchor cell)) in
    -- Mark date cells with a "date" class, so eg wrapping within dates
    -- can be prevented with css; borders are classes too.
    let class_ =
            map (HtmlAttr.class_ . Html.textValue . Text.unwords) $
            filter (not . null) $
            [filter (not . Text.null) $
             Spr.textFromClass (cellClass cell) :
             ["date" | cellType cell == TypeDate] ++
             borderClasses cell] in
    let addSpan spanAttr n attrs =
            if n==1
                then attrs
                else spanAttr (Html.stringValue $ show n) : attrs in
    let span_ makeCell attrs =
            case Spr.cellSpan cell of
                Spr.NoSpan -> foldl (!) makeCell attrs
                Spr.Covered -> pure ()
                Spr.SpanHorizontal n ->
                    foldl (!) makeCell (addSpan HtmlAttr.colspan n attrs)
                Spr.SpanVertical n ->
                    foldl (!) makeCell (addSpan HtmlAttr.rowspan n attrs)
            in
    case cellStyle cell of
        Head -> span_ (Html.th content) class_
        Body emph ->
            let align =
                    case cellType cell of
                        TypeString -> []
                        TypeDate -> []
                        _ -> [HtmlAttr.align "right"]
                valign =
                    case Spr.cellSpan cell of
                        Spr.SpanVertical n ->
                            if n>1 then [HtmlAttr.valign "top"] else []
                        _ -> []
                withEmph =
                    case emph of
                        Item -> id
                        Total -> Html.b
            in  span_ (Html.td $ withEmph content) $
                align++valign++class_
