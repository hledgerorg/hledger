{- |
HTML writing helpers, using blaze-html, whose markup type is also the one
hledger-web's pages are made of.

They render "Hledger.Write.Spreadsheet" tables as HTML tables: the CLI's
@-O html@ output uses 'styledTableHtml' and 'titledTableHtml', and
hledger-web's report pages use 'formatRow' inside their own table markup.
blaze's text renderer writes everything on one line, so for human readability
we inject raw newlines between elements (see 'nl').
-}

{-# LANGUAGE OverloadedStrings #-}

module Hledger.Write.Html (
  Html,
  toHtml,
  Lines(..),
  borderClasses,
  formatCell,
  formatRow,
  formatTitle,
  htmlAsText,
  htmlAsLazyText,
  nl,
  styledTableHtml,
  titledTableHtml,
  tests_Hledger_Write_Html
  ) where

import Control.Monad (unless)
import Data.Foldable (traverse_)
import Data.List (intersperse)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Lazy qualified as TL
import Text.Blaze.Html5 (Html, toHtml, (!))
import Text.Blaze.Html5 qualified as H
import Text.Blaze.Html5.Attributes qualified as A
import Text.Blaze.Html.Renderer.Text (renderHtml)

import Hledger.Data.Amount (nullamt)
import Hledger.Utils.Test
import Hledger.Write.Html.Attribute qualified as Attr
import Hledger.Write.Spreadsheet (Type(..), Style(..), Emphasis(..), Cell(..))
import Hledger.Write.Spreadsheet qualified as Spr


htmlAsText :: Html -> Text
htmlAsText = TL.toStrict . renderHtml

htmlAsLazyText :: Html -> TL.Text
htmlAsLazyText = renderHtml

-- | A literal newline, to make the HTML output more human-readable.
-- Emit it only between elements, never inside cell content,
-- so it doesn't affect rendering.
nl :: Html
nl = H.preEscapedToHtml ("\n" :: Text)

-- | Export spreadsheet table data as HTML table.
-- This is derived from <https://hackage.haskell.org/package/classify-frog-0.2.4.3/src/src/Spreadsheet/Format.hs>
styledTableHtml :: (Lines border) => [[Cell border Html]] -> Html
styledTableHtml = titledTableHtml Text.empty

-- | Like 'styledTableHtml', but with the given report title, if non-empty,
-- as a heading above the table.
titledTableHtml :: (Lines border) => Text -> [[Cell border Html]] -> Html
titledTableHtml title table = do
    -- the builtin styles, then the optional user stylesheet so it can override them
    H.style $ H.preEscapedToHtml Attr.tableStylesheet
    nl
    H.link ! A.rel "stylesheet" ! A.href "hledger.css"
    nl
    unless (Text.null title) $ formatTitle title
    H.table $ nl <> traverse_ formatRow table

formatRow :: (Lines border) => [Cell border Html] -> Html
formatRow row = H.tr (traverse_ formatCell row) <> nl

-- | Render a report title as an HTML heading.
formatTitle :: Text -> Html
formatTitle title = (H.h3 ! A.class_ "report-title") (toHtml title) <> nl

formatCell :: (Lines border) => Cell border Html -> Html
formatCell cell =
    -- Wrap amounts in <span class="amount">, one per amount,
    -- so eg wrapping within amounts can be prevented with css.
    let amountSpan = H.span ! A.class_ "amount" in
    let str =
            case cellParts cell of
                [] -> case cellType cell of
                    TypeAmount _ -> amountSpan $ cellContent cell
                    _            -> cellContent cell
                parts ->
                    mconcat $ intersperse (toHtml (", "::Text)) $
                    map amountSpan parts in
    let content =
            if Text.null $ cellAnchor cell
                then str
                else (H.a ! A.href (H.textValue $ cellAnchor cell)) str in
    -- Mark date cells with a "date" class, so eg wrapping within dates
    -- can be prevented with css; borders are classes too.
    let class_ =
            map (A.class_ . H.textValue . Text.unwords) $
            filter (not . null) $
            [filter (not . Text.null) $
             Spr.textFromClass (cellClass cell) :
             ["date" | cellType cell == TypeDate] ++
             borderClasses cell] in
    let addSpan spanAttr n attrs =
            if n==1
                then attrs
                else spanAttr (H.stringValue $ show n) : attrs in
    let span_ makeCell attrs cont =
            case Spr.cellSpan cell of
                Spr.NoSpan -> foldl (!) makeCell attrs cont
                Spr.Covered -> pure ()
                Spr.SpanHorizontal n ->
                    foldl (!) makeCell (addSpan A.colspan n attrs) cont
                Spr.SpanVertical n ->
                    foldl (!) makeCell (addSpan A.rowspan n attrs) cont
            in
    case cellStyle cell of
        Head -> span_ H.th class_ content
        Body emph ->
            let align =
                    case cellType cell of
                        TypeString -> []
                        TypeDate -> []
                        _ -> [H.customAttribute "align" "right"]
                valign =
                    case Spr.cellSpan cell of
                        Spr.SpanVertical n ->
                            if n>1
                                then [H.customAttribute "valign" "top"]
                                else []
                        _ -> []
                withEmph =
                    case emph of
                        Item -> id
                        Total -> H.b
            in  span_ H.td (align++valign++class_) $
                withEmph content


-- | The CSS classes marking a cell's borders, eg @border-top-double@.
-- Borders are expressed as classes rather than inline styles so that the
-- HTML can be served under a Content Security Policy which forbids inline
-- styles; the matching rules are in "Hledger.Write.Html.Attribute".
borderClasses :: Lines border => Cell border text -> [Text]
borderClasses cell =
    [ "border-" <> side <> "-" <> cls
    | (side, access) <-
        [ ("left",   Spr.borderLeft)
        , ("right",  Spr.borderRight)
        , ("top",    Spr.borderTop)
        , ("bottom", Spr.borderBottom)
        ]
    , Just cls <- [borderClass $ access $ cellBorder cell]
    ]

class (Spr.Lines border) => Lines border where
    -- | The class suffix naming this kind of border line, if it is drawn.
    borderClass :: border -> Maybe Text

instance Lines () where
    borderClass () = Nothing

instance Lines Spr.NumLines where
    borderClass prop =
        case prop of
            Spr.NoLine -> Nothing
            Spr.SingleLine -> Just "single"
            Spr.DoubleLine -> Just "double"


tests_Hledger_Write_Html = testGroup "Write.Html" [

   testCase "formatCell" $ do
    let cell = htmlAsText . formatCell . fmap toHtml
        str  = Spr.defaultCell :: Text -> Cell Spr.NumLines Text
    cell (str "a") @?= "<td>a</td>"
    cell (str "a<b>&\"c\"") @?= "<td>a&lt;b&gt;&amp;&quot;c&quot;</td>"
    cell (Spr.headerCell "h") @?= "<th>h</th>"
    cell (str "2026-01-01") {cellType = TypeDate} @?= "<td class=\"date\">2026-01-01</td>"
    -- an amount is wrapped in a span; a multi-commodity amount gets one span per amount
    cell (str "$1") {cellType = TypeAmount nullamt, cellClass = Spr.Class "amount"}
      @?= "<td align=\"right\" class=\"amount\"><span class=\"amount\">$1</span></td>"
    cell (str "$1, 2 €") {cellType = TypeMixedAmount, cellParts = ["$1", "2 €"]}
      @?= "<td align=\"right\"><span class=\"amount\">$1</span>, <span class=\"amount\">2 €</span></td>"
    -- links, totals, borders
    cell (str "a") {cellAnchor = "register?q=a&b"} @?= "<td><a href=\"register?q=a&amp;b\">a</a></td>"
    cell (str "Total:") {cellStyle = Body Total, cellBorder = Spr.noBorder {Spr.borderTop = Spr.DoubleLine}}
      @?= "<td class=\"border-top-double\"><b>Total:</b></td>"
    cell (Spr.headerCell "h" :: Cell Spr.NumLines Text) {cellClass = Spr.Class "account", cellBorder = Spr.noBorder {Spr.borderBottom = Spr.SingleLine}}
      @?= "<th class=\"account border-bottom-single\">h</th>"
    -- merged cells: a span of 1 is not written, covered cells are not written at all
    cell (str "a") {cellSpan = Spr.SpanHorizontal 2} @?= "<td colspan=\"2\">a</td>"
    cell (str "a") {cellSpan = Spr.SpanHorizontal 1} @?= "<td>a</td>"
    cell (str "a") {cellSpan = Spr.SpanVertical 2} @?= "<td rowspan=\"2\" valign=\"top\">a</td>"
    cell (str "a") {cellSpan = Spr.Covered} @?= ""

  ,testCase "formatRow" $
    htmlAsText (formatRow $ map (fmap toHtml) [Spr.defaultCell "a", Spr.defaultCell "b" :: Cell () Text])
      @?= "<tr><td>a</td><td>b</td></tr>\n"

  ,testCase "titledTableHtml" $ do
    let html = htmlAsText $ titledTableHtml "T & U" [map (fmap toHtml) [Spr.headerCell "h" :: Cell () Text]]
    Text.isPrefixOf "<style>\ntable {" html @?= True
    Text.isSuffixOf "</style>\n<link rel=\"stylesheet\" href=\"hledger.css\">\n<h3 class=\"report-title\">T &amp; U</h3>\n<table>\n<tr><th>h</th></tr>\n</table>" html @?= True

  ]
