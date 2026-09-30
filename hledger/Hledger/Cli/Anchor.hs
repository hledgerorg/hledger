{-# LANGUAGE OverloadedStrings    #-}
{-# LANGUAGE QuasiQuotes          #-}
{-|
Links from report cells to hledger-web's register: for hledger-web's own
report pages, and for HTML and FODS output with --base-url. A figure
links to the register that derives it, an account name to the account's
register, a period heading to the register for that period.
-}
module Hledger.Cli.Anchor (
    LinkOpts(..),
    defaultLinkOpts,
    linkParams,
    composeAnchor,
    composeAnchorWith,
    accountTerm,
    dateTerm,
    removeDates,
    removeInacct,
    withLink,
    setAccountAnchor,
    setAccountAnchorWith,
    dateCell,
    dateSpanCell,
    dateSpanCellWith,
    totalDateSpanCell,
    headerDateSpanCell,
    renderPeriodHeading,
    amountPhrase,
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
import Hledger.Data.Dates (showDateSpan, showDateSpanFull, showDateSpanForQuery, showDate, nulldatespan)
import Hledger.Data.Types (DateSpan(..))
import Hledger.Reports.ReportOptions (PeriodTitles(..), BalanceAccumulation(..))


-- | What a report's register links need to know about the report,
-- besides its query and the base url.
data LinkOpts = LinkOpts {
    loAccum        :: BalanceAccumulation,
      -- ^ With historical balances, the register starts from the balance
      --   before the period, so that it ends on the figure in the cell.
    loSpan         :: DateSpan,
      -- ^ The whole report span. A cumulative figure's register runs from its start.
    loDate2        :: Bool,
      -- ^ Does the report use secondary dates ? Then so must the register.
    loIncludesSubs :: Bool,
      -- ^ Does the row's figure include subaccounts (inacct:) or not (inacctonly:) ?
    loNegated      :: Bool
      -- ^ Are the figures shown with the opposite sign to the register's ?
}

defaultLinkOpts :: LinkOpts
defaultLinkOpts = LinkOpts PerPeriod nulldatespan False True False

-- | The query parameters a link carries besides q: the register's
-- accumulation mode, when it is not the register's default.
linkParams :: LinkOpts -> [(Text, Text)]
linkParams lo = [("accum", "historical") | loAccum lo == Historical]

-- | The span a figure's register covers: the period, or, for a
-- cumulative figure, the report's start to the period's end.
linkSpan :: LinkOpts -> DateSpan -> DateSpan
linkSpan lo spn@(DateSpan _ e) =
    case loAccum lo of
        Cumulative -> let DateSpan s _ = loSpan lo in DateSpan s e
        _          -> spn

-- | The query term naming the account a link is for.
accountTerm :: Bool -> Text -> Text
accountTerm includesSubs acct =
    (if includesSubs then "inacct:" else "inacctonly:") <> acct

-- | A date: term for the span (date2: for a report using secondary
-- dates), or none for the unbounded span.
dateTerm :: Bool -> DateSpan -> [Text]
dateTerm date2 spn =
    [(if date2 then "date2:" else "date:") <> t | let t = showDateSpanForQuery spn, not $ Text.null t]

registerQueryUrl :: [(Text, Text)] -> [Text] -> Text
registerQueryUrl params query =
    Uri.render $
    [UriQQ.uri|register|] {
        Uri.uriQuery =
            Uri.QueryParam [UriQQ.queryKey|q|]
                (queryValue $ Text.unwords $ map quoteIfSpaced $ filter (not . Text.null) query)
            : [Uri.QueryParam (queryKey k) (queryValue v) | (k, v) <- params]
    }
  where
    queryKey   = fromMaybe (error' "register URI query construction failed") . Uri.mkQueryKey
    queryValue = fromMaybe (error' "register URI query construction failed") . Uri.mkQueryValue

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
composeAnchor = composeAnchorWith []

{- | Like 'composeAnchor', with query parameters after q.

>>> composeAnchorWith [("accum","historical")] (Just "") ["date:2024"]
"register?q=date:2024&accum=historical"
-}
composeAnchorWith :: [(Text, Text)] -> Maybe Text -> [Text] -> Text
composeAnchorWith _ Nothing _ = mempty
composeAnchorWith params (Just baseUrl) query =
    baseUrl <>
    (if all (('/'==) . snd) $ Text.unsnoc baseUrl then "" else "/") <>
    registerQueryUrl params query

-- cf. Web.Widget.Common
removeDates :: [Text] -> [Text]
removeDates =
    filter (\term_ ->
        not $ Text.isPrefixOf "date:" term_ || Text.isPrefixOf "date2:" term_)

-- | Drop the terms naming an account for the register. A link names
-- the account it is for, and the register reads only the first such term.
removeInacct :: [Text] -> [Text]
removeInacct =
    filter (\term_ ->
        not $ Text.isPrefixOf "inacct:" term_ || Text.isPrefixOf "inacctonly:" term_)

-- | Give a cell a link and its title, unless the link is empty (no base url).
withLink :: Text -> Text -> Spr.Cell border text -> Spr.Cell border text
withLink anchor title cell
    | Text.null anchor = cell
    | otherwise        = cell {Spr.cellAnchor = anchor, Spr.cellTitle = title}

-- | The title of a link from a figure to the register that derives it,
-- with a note when the report shows figures with the opposite sign.
amountPhrase :: LinkOpts -> Bool -> Text
amountPhrase lo isTotal =
    (case (loAccum lo, isTotal) of
        (Historical, False) -> "Show the transactions behind this balance"
        (Historical, True)  -> "Show the transactions behind this total"
        (_,          False) -> "Show the transactions that make up this amount"
        (_,          True)  -> "Show the transactions that make up this total")
    <> (if loNegated lo then ", which the register shows with the opposite sign" else "")

-- | A column heading for the period, linking to the register for it.
-- The link's date term is the span as a period expression, which can
-- differ from the heading text: a query reads the end date of
-- 2025-01-15..2025-02-14 as exclusive, and reads no week names.
headerDateSpanCell ::
    Bool -> PeriodTitles -> Maybe Text -> [Text] -> DateSpan -> Spr.Cell () Text
headerDateSpanCell date2 ph base query spn =
    withLink
        (composeAnchor base $ dateTerm date2 spn ++ removeDates (removeInacct query))
        "Show the transactions in this period" $
    headerCell $ renderPeriodHeading ph spn

-- | A cell showing a period in an account's row, linking to the
-- account's register for that period.
dateSpanCellWith ::
    (Spr.Lines border) =>
    LinkOpts -> PeriodTitles -> Maybe Text -> [Text] -> Text -> DateSpan -> Spr.Cell border Text
dateSpanCellWith lo ph base query acct spn =
    withLink
        (composeAnchorWith (linkParams lo) base $
            accountTerm (loIncludesSubs lo) acct :
            dateTerm (loDate2 lo) (linkSpan lo spn) ++ removeDates (removeInacct query))
        "Show transactions affecting this account in this period" $
    Spr.defaultCell $ renderPeriodHeading ph spn

dateSpanCell ::
    (Spr.Lines border) =>
    PeriodTitles -> Maybe Text -> [Text] -> Text -> DateSpan -> Spr.Cell border Text
dateSpanCell = dateSpanCellWith defaultLinkOpts

-- | A cell showing a date in an account's row, linking to the account's
-- register for that day.
dateCell ::
    (Spr.Lines border) =>
    Maybe Text -> [Text] -> Text -> Day -> Spr.Cell border Text
dateCell base query acct d =
    withLink
        (composeAnchor base $
            accountTerm True acct : ("date:" <> showDate d) : removeDates (removeInacct query))
        "Show transactions affecting this account on this date" $
    Spr.defaultCell $ showDate d

-- | A cell for a period in a totals row, linking to the register of
-- everything in the report's query, restricted by the given terms (a
-- section's account types, say), for that period.
totalDateSpanCell ::
    (Spr.Lines border) =>
    LinkOpts -> PeriodTitles -> Maybe Text -> [Text] -> [Text] -> DateSpan -> Spr.Cell border Text
totalDateSpanCell lo ph base terms query spn =
    withLink
        (composeAnchorWith (linkParams lo) base $
            terms ++ dateTerm (loDate2 lo) (linkSpan lo spn) ++ removeDates (removeInacct query))
        (amountPhrase lo True) $
    Spr.defaultCell $ renderPeriodHeading ph spn

-- | Render a DateSpan as a period heading according to the requested style.
renderPeriodHeading :: PeriodTitles -> DateSpan -> Text
renderPeriodHeading PTDates   = showDateSpanFull
renderPeriodHeading PTCompact = showDateSpan

-- | Link an account's cell to the account's register, restricted to the
-- given query. The query says which dates; the link options say whether
-- subaccounts are included and how the register accumulates.
setAccountAnchorWith ::
    LinkOpts -> Maybe Text -> [Text] -> Text -> Spr.Cell border text -> Spr.Cell border text
setAccountAnchorWith lo base query acct =
    withLink
        (composeAnchorWith (linkParams lo) base $
            accountTerm (loIncludesSubs lo) acct : removeInacct query)
        (if loIncludesSubs lo
            then "Show transactions affecting this account and subaccounts"
            else "Show transactions affecting this account but not subaccounts")

setAccountAnchor ::
    Maybe Text -> [Text] -> Text -> Spr.Cell border text -> Spr.Cell border text
setAccountAnchor = setAccountAnchorWith defaultLinkOpts
