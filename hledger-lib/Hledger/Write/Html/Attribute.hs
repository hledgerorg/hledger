{-# LANGUAGE OverloadedStrings #-}
{- |
Helpers and CSS styles for HTML output.
-}
module Hledger.Write.Html.Attribute (
    stylesheet,
    tableStylesheet,
    tableStyle,
    borderStyle,
    bold,
    alignright,
    alignleft,
    aligncenter,
    collapse,
    lpad,
    rpad,
    hpad,
    vpad,
    ) where

import Data.Text qualified as Text
import Data.Text (Text)


stylesheet :: [(Text,Text)] -> Text
stylesheet elstyles =
    Text.unlines $
        "" : [el<>" {"<>styles<>"}" | (el,styles) <- elstyles]

tableStylesheet :: Text
tableStylesheet = stylesheet tableStyle

tableStyle :: [(Text, Text)]
tableStyle =
  [("table", collapse),
   ("th, td", lpad),
   ("th.account, td.account", "padding-left:0;"),
   -- prevent wrapping within dates and individual amounts
   ("td.date, span.amount", "white-space:nowrap")]
  ++ borderStyle

-- | Rules for the border classes emitted by "Hledger.Write.Html",
-- one per side and line kind, eg @.border-top-double@. No color is given,
-- so the lines take the text color and stay visible on any background.
borderStyle :: [(Text, Text)]
borderStyle =
  [ ("." <> cls, side <> ":" <> line)
  | (side, sideCls) <- [("border-left","left"), ("border-right","right"),
                        ("border-top","top"), ("border-bottom","bottom")]
  , (line, lineCls) <- [("1px solid","single"), ("3px double","double")]
  , let cls = "border-" <> sideCls <> "-" <> lineCls
  ]

bold :: Text
bold = "font-weight:bold"

alignright, alignleft, aligncenter :: Text
alignright  = "text-align:right"
alignleft   = "text-align:left"
aligncenter = "text-align:center"

collapse :: Text
collapse = "border-collapse:collapse"

lpad, rpad, hpad, vpad :: Text
lpad = "padding-left:1em"
rpad = "padding-right:1em"
hpad = "padding-left:1em; padding-right:1em"
vpad = "padding-top:1em;  padding-bottom:1em"
