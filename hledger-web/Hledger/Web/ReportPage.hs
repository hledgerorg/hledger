{-|
What hledger-web's report pages share: resolving their parameters
against the startup options, and rendering a report's cells as the
page's table.
-}

{-# LANGUAGE LambdaCase        #-}
{-# LANGUAGE NamedFieldPuns    #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards   #-}

module Hledger.Web.ReportPage (
  ReportParams(..),
  ReportParamError(..),
  reportParams,
  paramError,
  columnHeading,
  headingParams,
  linksRow,
  reportLinks,
  intervalLinks,
  accumulationLinks,
  relinkDateHeaders,
  reportTable,
) where

import Control.Monad (mfilter, unless)
import Data.Foldable (for_, traverse_)
import Data.Maybe (fromMaybe, listToMaybe)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Time.Calendar (Day)
import Data.Set qualified as Set
import Text.Blaze.Html5 ((!), (!?))
import Text.Blaze.Html5 qualified as H
import Text.Blaze.Html5.Attributes qualified as A
import Text.Megaparsec.Error (errorBundlePretty)
import Yesod (HtmlUrl)

import Hledger.Utils.I18n (Translations, tr, trc)
import Hledger
import Hledger.Cli.Anchor (dateTerm, renderPeriodHeading)
import Hledger.Web.Widget.Common (removeDates)
import Hledger.Query qualified as Query
import Hledger.Write.Html (Html, formatCell, nl)
import Hledger.Write.Spreadsheet (Cell(..), NumLines)

-- | A report page's parameters, resolved.
data ReportParams = ReportParams {
    rpRopts    :: ReportOpts,
      -- ^ The startup report options with the page's search, period, interval,
      --   and zero-item setting applied, and links made relative. The
      --   accumulation mode is left for the page to set.
    rpRspec    :: ReportSpec,
      -- ^ The startup report spec with those options and the page's query.
    rpSpan     :: DateSpan,
      -- ^ The period parameter's date span, or the unbounded span.
    rpInterval :: Interval,
      -- ^ The reporting interval: from a date: search term, else the period
      --   parameter, else startup.
    rpPeriod   :: Maybe Text,
      -- ^ The period parameter as given, for links that keep it.
    rpAccum    :: Maybe BalanceAccumulation
      -- ^ The accum parameter, if one was given.
}

-- | A parameter the page cannot use, with what was given.
data ReportParamError = BadPeriod String | BadAccum Text

-- | Resolve a report page's parameters: today's date, the startup report
-- spec, the search parameter and its parsed query and options, whether
-- zero items are hidden, and the period and accum parameters.
--
-- The period parameter is a period expression as for -p: an interval
-- ("monthly"), a date span ("2024"), or both ("monthly in 2024"). An
-- empty one is no period at all, as from a search form with nothing in
-- it; then the startup interval applies. A date: search term can carry
-- an interval too (date:monthly), and as on the command line it wins
-- over the period; cf reportOptsToSpec. The period's date span restricts
-- the report like a date: search term would, and the report's links
-- carry it, so that a row's register is restricted the same way.
reportParams ::
  Day -> ReportSpec -> Text -> Query -> [QueryOpt] -> Bool -> [(Text, Text)] ->
  Either ReportParamError ReportParams
reportParams today rspecOrig qparam q qopts hideEmpty params = do
  let roptsOrig = _rsReportOpts rspecOrig
      rpPeriod = mfilter (not . T.null) $ lookup "period" params
  (ivl, rpSpan) <- case rpPeriod of
    Nothing -> Right (interval_ roptsOrig, nulldatespan)
    Just p  -> either (Left . BadPeriod . errorBundlePretty) Right $ parsePeriodExpr today p
  rpAccum <- parseAccum $ lookup "accum" params
  let rpInterval = fromMaybe ivl $ intervalFromQueryOpts qopts
      rpRopts =
        roptsOrig {
          -- -E means the opposite in hledger-ui and hledger-web: hide
          -- zero items, which are shown by default, as the sidebar does.
          empty_ = not hideEmpty,
          balance_base_url_ = Just "",
          querystring_ = filter (not . T.null) (Query.words'' queryprefixes qparam) ++ dateTerm (date2_ roptsOrig) rpSpan,
          interval_ = rpInterval
        }
      -- cf queryFromFlags
      dateq
        | rpSpan == nulldatespan = Any
        | date2_ rpRopts         = Date2 rpSpan
        | otherwise              = Date rpSpan
      -- Unlike the journal and register pages, keep any depth limit:
      -- the report reads it from the query, and it is how a balance
      -- report gets summarized (--depth at startup, or depth: in the search).
      rpRspec =
        rspecOrig {
          _rsQuery = simplifyQuery $ And [q, dateq],
          _rsReportOpts = rpRopts
        }
  Right ReportParams{..}


-- | A row of links above a report: a label, then each link's label,
-- title, target, and whether it is the one being shown.
-- Each label and title is a whole phrase, not a word slotted into a
-- sentence: an adjective that fits one language's sentence does not fit
-- another's, so a translation cannot be assembled from parts.
linksRow :: Text -> [(Text, Text, (r, [(Text, Text)]), Bool)] -> HtmlUrl r
linksRow rowlabel items renderUrl = do
    H.p ! A.class_ "report-links" $ do
      H.toHtml rowlabel
      for_ items $ \(label, title, link, current) -> do
        H.a !? (current, A.class_ "current")
            ! A.href (H.toValue $ uncurry renderUrl link)
            ! A.title (H.toValue title) $
          H.toHtml label


-- | Links to the report pages, given as route, label, and title,
-- keeping the given parameters; the page being shown is marked.
reportLinks :: Eq r => Translations -> r -> [(Text, Text)] -> [(r, Text, Text)] -> HtmlUrl r
reportLinks trs here kept menu =
  -- TRANSLATORS: the label before a page's report links.
  linksRow (tr trs "Report:") [ (tr trs label, tr trs title, (route, kept), route == here) | (route, label, title) <- menu ]


-- | Links to the same report page for each reporting interval, keeping
-- the search, the period's date span, and the given parameters; the
-- interval being shown is marked.
intervalLinks :: Translations -> r -> [(Text, Text)] -> Text -> DateSpan -> Interval -> HtmlUrl r
intervalLinks trs route kept qparam spn current =
  -- TRANSLATORS: the label before a report's interval links.
  linksRow (tr trs "Interval:")
    [ (label, title, link mword, ivl == current) | (label, title, mword, ivl) <- intervals ]
  where
    -- TRANSLATORS: the interval links above a report: each link's text, and its tooltip.
    intervals :: [(Text, Text, Maybe Text, Interval)]
    intervals =
      [ (trc trs "interval" "None", tr trs "Show one column for the whole period", Nothing,          NoInterval)
      , (tr trs "Yearly",    tr trs "Show a column per year",               Just "yearly",    Years 1)
      , (tr trs "Quarterly", tr trs "Show a column per quarter",            Just "quarterly", Quarters 1)
      , (tr trs "Monthly",   tr trs "Show a column per month",              Just "monthly",   Months 1)
      , (tr trs "Weekly",    tr trs "Show a column per week",               Just "weekly",    Weeks 1)
      , (tr trs "Daily",     tr trs "Show a column per day",                Just "daily",     Days 1)
      ]
    -- Each link keeps the period's date span, so that changing the
    -- interval does not silently widen the report to the whole journal.
    -- "monthly 2025-01-01..2025-12-31" is a period expression like any other.
    spantext = if spn == nulldatespan then "" else showDateSpanForQuery spn
    periodparam mword = case (mword, spantext) of
      (Nothing,   "") -> []
      (Nothing,   sp) -> [("period", sp)]
      (Just w,    "") -> [("period", w)]
      (Just w,    sp) -> [("period", w <> " " <> sp)]
    link mword =
      (route, periodparam mword ++ [("q", qparam) | not (T.null qparam)] ++ kept)

-- | Links to the same report page showing balance changes or ending
-- balances, keeping the given parameters; the one being shown is marked.
accumulationLinks :: Translations -> r -> [(Text, Text)] -> BalanceAccumulation -> HtmlUrl r
accumulationLinks trs route kept current =
  -- TRANSLATORS: the label before a report's accumulation mode links, and the links' text and tooltips.
  linksRow (tr trs "Show:")
    [ (tr trs "Balance changes", tr trs "Show how much each balance changed in each period",
        (route, kept), current /= Historical)
    , (tr trs "Ending balances", tr trs "Show each balance at the end of each period, including everything before it",
        (route, kept ++ [("accum", "historical")]), current == Historical)
    ]

-- | The accum parameter: "historical" for ending balances, "change" for
-- balance changes, or none for the page's default.
parseAccum :: Maybe Text -> Either ReportParamError (Maybe BalanceAccumulation)
parseAccum = \case
  Nothing           -> Right Nothing
  Just ""           -> Right Nothing
  Just "historical" -> Right $ Just Historical
  Just "change"     -> Right $ Just PerPeriod
  Just other        -> Left $ BadAccum other

-- | Explain a parameter the page could not use.
paramError :: Translations -> ReportParamError -> Html
paramError trs = \case
  BadPeriod err ->
    H.div ! A.class_ "alert alert-danger" $ do
      H.toHtml $ tr trs "Could not parse the period expression:"
      H.pre $ H.toHtml err
  BadAccum v ->
    H.div ! A.class_ "alert alert-danger" $ do
      H.toHtml $ tr trs "Unknown balance accumulation mode:"
      H.pre $ H.toHtml v

-- | A column's heading: its period, or for ending balances the period's
-- end date, which is what an ending balance is at.
columnHeading :: ReportOpts -> [DateSpan] -> DateSpan -> Text
columnHeading ropts colspans spn =
  case balanceaccum_ ropts of
    Historical -> reportPeriodName ropts{balanceaccum_ = Historical} colspans spn
    _          -> renderPeriodHeading (period_titles_ ropts) spn

-- A column heading opens this report for that column's period,
-- in place of any date terms in the search, which the column narrows anyway.
headingParams :: Text -> [(Text, Text)] -> DateSpan -> [(Text, Text)]
headingParams qparam params spn =
  [("q", T.unwords qt) |
      let qt = dateTerm False spn ++ removeDates qparam,
      not (null qt)] ++
  removeAttributes ["q", "period"] params

removeAttributes :: [Text] -> [(Text, Text)] -> [(Text, Text)]
removeAttributes attrs =
  let attrSet = Set.fromList attrs
  in filter (flip Set.notMember attrSet . fst)

-- | Give a report's heading row this page's column headings and links:
-- the cells that link (the columns' periods) get the given heading text
-- and link for their span.
relinkDateHeaders ::
  Translations -> (DateSpan -> Text) -> (DateSpan -> Text) -> [DateSpan] -> [Cell NumLines Text] -> [Cell NumLines Text]
relinkDateHeaders trs heading link = go
  where
    go (spn:spns) (c:cs)
      | not (T.null $ cellAnchor c) =
          c {cellContent = heading spn, cellAnchor = link spn, cellTitle = tr trs "Show this report for this period"} : go spns cs
    go spns (c:cs) = c : go spns cs
    go _ [] = []

-- | A report as a table in the page's own style: the heading rows, then
-- a table section per report section (a titled row, its rows, then its
-- subtotal rows), then the total rows as the table's footer. It scrolls
-- sideways within the page when it is wider (see .report-table in
-- hledger.css; bootstrap's .table-responsive does that only on a phone).
reportTable ::
  [[Cell NumLines Text]] -> [(Maybe Text, [[Cell NumLines Text]], [[Cell NumLines Text]])] -> [[Cell NumLines Text]] -> Html
reportTable header sections footer =
  H.div ! A.class_ "table-responsive report-table" $
    H.table ! A.class_ "balancereport table table-condensed" $ do
      H.thead $ rows Nothing header
      traverse_ section sections
      unless (null footer) $ H.tfoot $ rows Nothing footer
  where
    ncols = maybe 1 length $ listToMaybe header
    section (mtitle, body, subtotals) =
      H.tbody $ do
        for_ mtitle $ \t ->
          H.tr ! A.class_ "section" $
            H.th ! A.colspan (H.toValue ncols) ! H.customAttribute "scope" "rowgroup" $ H.toHtml t
        rows Nothing body
        rows (Just "subtotal") subtotals
    rows mcls = traverse_ $ \r ->
      maybe id (\cls -> (! A.class_ cls)) mcls H.tr (traverse_ (formatCell . fmap H.toHtml) r) <> nl
