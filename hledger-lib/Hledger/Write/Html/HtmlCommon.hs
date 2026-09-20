{-# LANGUAGE OverloadedStrings #-}
{- |
Common definitions used by both Html.Blaze and Html.Lucid.
-}

module Hledger.Write.Html.HtmlCommon (
    Lines(..),
    borderClasses,
    ) where

import Data.Text (Text)

import           Hledger.Write.Spreadsheet (Cell(..))
import Hledger.Write.Spreadsheet qualified as Spr


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
