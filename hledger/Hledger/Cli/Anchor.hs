{-# LANGUAGE OverloadedStrings    #-}
{-# LANGUAGE QuasiQuotes          #-}
module Hledger.Cli.Anchor (
    setAccountAnchor,
    dateCell,
    dateSpanCell,
    headerDateSpanCell,
    renderPeriodHeading,
    ) where

import Data.Text qualified as Text
import Data.Text (Text)
import Data.Time (Day)
import Data.Maybe (fromMaybe)

import Text.URI qualified as Uri
import Text.URI.QQ qualified as UriQQ

import Hledger.Write.Spreadsheet qualified as Spr
import Hledger.Write.Spreadsheet (headerCell)
import Hledger.Utils.IO (error')
import Hledger.Utils.Text (quoteIfSpaced)
import Hledger.Data.Dates (showDateSpan, showDateSpanFull, showDate)
import Hledger.Data.Types (DateSpan)
import Hledger.Reports.ReportOptions (PeriodTitles(..))


registerQueryUrl :: [Text] -> Text
registerQueryUrl query =
    Uri.render $
    [UriQQ.uri|register|] {
        Uri.uriQuery =
            [Uri.QueryParam [UriQQ.queryKey|q|] $
             fromMaybe (error' "register URI query construction failed") $
             Uri.mkQueryValue $ Text.unwords $
             map quoteIfSpaced $ filter (not . Text.null) query]
    }

{- |
>>> composeAnchor Nothing ["date:2024"]
""
>>> composeAnchor (Just "") ["date:2024"]
"register?q=date:2024"
>>> composeAnchor (Just "/") ["date:2024"]
"/register?q=date:2024"
>>> composeAnchor (Just "foo") ["date:2024"]
"foo/register?q=date:2024"
>>> composeAnchor (Just "foo/") ["date:2024"]
"foo/register?q=date:2024"
-}
composeAnchor :: Maybe Text -> [Text] -> Text
composeAnchor Nothing _ = mempty
composeAnchor (Just baseUrl) query =
    baseUrl <>
    (if all (('/'==) . snd) $ Text.unsnoc baseUrl then "" else "/") <>
    registerQueryUrl query

-- cf. Web.Widget.Common
removeDates :: [Text] -> [Text]
removeDates =
    filter (\term_ ->
        not $ Text.isPrefixOf "date:" term_ || Text.isPrefixOf "date2:" term_)

replaceDate :: Text -> [Text] -> [Text]
replaceDate prd query = "date:"<>prd : removeDates query

headerDateSpanCell ::
    PeriodTitles -> Maybe Text -> [Text] -> DateSpan -> Spr.Cell () Text
headerDateSpanCell ph base query spn =
    let prd = renderPeriodHeading ph spn in
    (headerCell prd) {
        Spr.cellAnchor = composeAnchor base $ replaceDate prd query
    }


dateQueryCell ::
    (Spr.Lines border) =>
    Maybe Text -> [Text] -> Text -> Text -> Spr.Cell border Text
dateQueryCell base query acct dateTerm =
    (Spr.defaultCell dateTerm) {
        Spr.cellAnchor =
            composeAnchor base $ "inacct:"<>acct : replaceDate dateTerm query
    }

dateCell ::
    (Spr.Lines border) =>
    Maybe Text -> [Text] -> Text -> Day -> Spr.Cell border Text
dateCell base query acct = dateQueryCell base query acct . showDate

dateSpanCell ::
    (Spr.Lines border) =>
    PeriodTitles -> Maybe Text -> [Text] -> Text -> DateSpan -> Spr.Cell border Text
dateSpanCell ph base query acct = dateQueryCell base query acct . renderPeriodHeading ph

-- | Render a DateSpan as a period heading according to the requested style.
renderPeriodHeading :: PeriodTitles -> DateSpan -> Text
renderPeriodHeading PTDates   = showDateSpanFull
renderPeriodHeading PTCompact = showDateSpan

setAccountAnchor ::
    Maybe Text -> [Text] -> Text -> Spr.Cell border text -> Spr.Cell border text
setAccountAnchor base query acct cell =
    cell {Spr.cellAnchor = composeAnchor base $ "inacct:"<>acct : query}
