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
import Hledger.Data.Dates (showDateSpan, showDateSpanFull, showDateSpanForQuery, showDate)
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

-- | Drop the terms naming the register's account. A link names the
-- account it is for; a leftover term would come first and win.
removeInacct :: [Text] -> [Text]
removeInacct =
    filter (\term_ ->
        not $ Text.isPrefixOf "inacct:" term_ || Text.isPrefixOf "inacctonly:" term_)

-- | Restrict the query to the given period expression, if it is not
-- empty (the unbounded span), in place of any date terms it had.
replaceDate :: Text -> [Text] -> [Text]
replaceDate prd query = ["date:"<>prd | not $ Text.null prd] ++ removeDates query

-- | A column heading for the period, linking to the register for it.
-- The link's date term is the span as a period expression, which can
-- differ from the heading text: a query reads the end date of
-- 2025-01-15..2025-02-14 as exclusive, and reads no week names.
headerDateSpanCell ::
    PeriodTitles -> Maybe Text -> [Text] -> DateSpan -> Spr.Cell () Text
headerDateSpanCell ph base query spn =
    (headerCell $ renderPeriodHeading ph spn) {
        Spr.cellAnchor =
            composeAnchor base $ replaceDate (showDateSpanForQuery spn) (removeInacct query)
    }


-- | A cell showing a date or period, linking to the account's register
-- restricted to the given period expression.
dateQueryCell ::
    (Spr.Lines border) =>
    Maybe Text -> [Text] -> Text -> Text -> Text -> Spr.Cell border Text
dateQueryCell base query acct label dateTerm =
    (Spr.defaultCell label) {
        Spr.cellAnchor =
            composeAnchor base $ "inacct:"<>acct : replaceDate dateTerm (removeInacct query)
    }

dateCell ::
    (Spr.Lines border) =>
    Maybe Text -> [Text] -> Text -> Day -> Spr.Cell border Text
dateCell base query acct d = dateQueryCell base query acct (showDate d) (showDate d)

dateSpanCell ::
    (Spr.Lines border) =>
    PeriodTitles -> Maybe Text -> [Text] -> Text -> DateSpan -> Spr.Cell border Text
dateSpanCell ph base query acct spn =
    dateQueryCell base query acct (renderPeriodHeading ph spn) (showDateSpanForQuery spn)

-- | Render a DateSpan as a period heading according to the requested style.
renderPeriodHeading :: PeriodTitles -> DateSpan -> Text
renderPeriodHeading PTDates   = showDateSpanFull
renderPeriodHeading PTCompact = showDateSpan

setAccountAnchor ::
    Maybe Text -> [Text] -> Text -> Spr.Cell border text -> Spr.Cell border text
setAccountAnchor base query acct cell =
    cell {Spr.cellAnchor = composeAnchor base $ "inacct:"<>acct : removeInacct query}
