-- | /balance handlers.

{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE OverloadedStrings #-}

module Hledger.Web.Handler.BalanceR where

import Text.Blaze.Html5 ((!))
import Text.Blaze.Html5 qualified as H
import Text.Blaze.Html5.Attributes qualified as A
import Text.Megaparsec.Error (errorBundlePretty)
import Yesod qualified

import Hledger
import Hledger.Cli.CliOptions
import Hledger.Cli.Commands.Balance qualified as Balance
import Hledger.Query qualified as Query
import Data.Text qualified as T
import Hledger.Utils.I18n (tr, trf)

import Hledger.Web.Import
import Hledger.Web.WebOptions
import Hledger.Web.Widget.Common (balanceReportLinks)
import Hledger.Write.Html (formatRow)
import Hledger.Write.Spreadsheet (Cell, NumLines)


-- | The balance or multi-period balance view, with sidebar.
getBalanceR :: Handler Html
getBalanceR = do
  checkServerSideUiEnabled
  VD{j, q, qopts, qparam, opts, today, trs} <- getViewData
  require ViewPermission
  -- The period parameter is a period expression as for -p: an interval
  -- ("monthly"), a date span ("2024"), or both ("monthly in 2024").
  -- An empty one is no period at all, as from a search form with nothing in it.
  mperiod <- (>>= \p -> if T.null p then Nothing else Just p) <$> lookupGetParam "period"
  let withFilter t = if q /= Any then trf trs "{title}, filtered" [("title", t)] else t
      rspecOrig = reportspec_ $ cliopts_ opts
      roptsOrig = _rsReportOpts rspecOrig
      eperiod = case mperiod of
        -- No period: keep the interval the server was started with (-M, -p ...).
        Nothing -> Right (interval_ roptsOrig, nulldatespan)
        Just p  -> either (Left . errorBundlePretty) Right $ parsePeriodExpr today p

  defaultLayout $ do
    -- TRANSLATORS: the browser tab title of this page.
    setTitleI (HMsg "balance - hledger-web")

    case eperiod of
      -- No report links here: this page is a dead end until the navigation
      -- question (#2242) is settled, see the pull request.
      Left err -> Yesod.toWidget $ do
        H.h2 $ H.toHtml $ withFilter $ reportTitle roptsOrig $ tr trs "Balance report"
        H.div ! A.class_ "alert alert-danger" $ do
          H.toHtml $ tr trs "Could not parse the period expression:"
          H.pre $ H.toHtml err
      Right (ivl, spn) -> do
        let -- A date: search term can carry an interval too (eg
            -- date:monthly), and as on the command line it wins over the
            -- period; cf reportOptsToSpec.
            reportinterval = fromMaybe ivl $ intervalFromQueryOpts qopts
            -- The links in the report carry the search, and the period's
            -- date span as a date: term, so that a row's register link is
            -- restricted the same way the report is.
            spanterm = ["date:" <> showDateSpan spn | spn /= nulldatespan]
            ropts =
              roptsOrig {
                -- -E means the opposite in hledger-ui and hledger-web: hide
                -- zero items, which are shown by default. The sidebar beside
                -- this report already reads the flag that way (see App.hs).
                empty_ = not $ empty_ roptsOrig,
                balance_base_url_ = Just "",
                querystring_ = Query.words'' queryprefixes qparam ++ spanterm,
                interval_ = reportinterval
              }
            -- The period's date span restricts the report like a date:
            -- search term would; cf queryFromFlags.
            dateq
              | spn == nulldatespan = Any
              | date2_ ropts        = Date2 spn
              | otherwise           = Date spn
            -- Unlike the journal and register pages, keep any depth limit:
            -- the report reads it from the query, and it is how a balance
            -- report gets summarized (--depth at startup, or depth: in the search).
            rspec =
              rspecOrig {
                _rsQuery = simplifyQuery $ And [q, dateq],
                _rsReportOpts = ropts
              }
            -- The heading, and the report's rows in three parts, for the
            -- table's thead, tbody, and tfoot.
            (title, parts) = case reportinterval of
              NoInterval ->
                let (header, body, totals) =
                      Balance.balanceReportAsSpreadsheetParts oneLineNoCostFmt ropts $
                        styleAmounts (journalCommodityStylesWith HardRounding j) $
                          balanceReport rspec j
                in ( reportTitle ropts $ tr trs "Balance report"
                   , ([toList header], map toList body, map toList totals))
              _ ->
                let mbr = styleAmounts (journalCommodityStylesWith HardRounding j) $
                            multiBalanceReport rspec j
                in ( maybe (trimColon $ Balance.multiBalanceReportTitle ropts mbr) id (title_ ropts)
                   , Balance.multiBalanceReportAsSpreadsheetParts oneLineNoCostFmt ropts
                       (Balance.allCommoditiesFromPeriodicReport $ prRows mbr) mbr
                   )
        Yesod.toWidget $ H.h2 $ H.toHtml $ withFilter title
        Yesod.toWidget $ balanceReportLinks BalanceR trs qparam spn reportinterval
        Yesod.toWidget $ reportTable parts

-- | The heading for a report: --title if one was given, otherwise the
-- given default.
reportTitle :: ReportOpts -> Text -> Text
reportTitle ropts dflt = fromMaybe dflt $ title_ ropts

-- | Drop the trailing colon of a command line report title, which a heading
-- does not want. A translation of it may end in " :" or "\uff1a" instead,
-- so drop whichever is there.
trimColon :: Text -> Text
trimColon = T.dropWhileEnd (`elem` (":\65306 " :: String))

-- | A report's heading, body, and total rows as a table in the page's own
-- style, scrolling sideways within the page when it is wider (see
-- .report-table in hledger.css; bootstrap's .table-responsive does that
-- only on a phone).
reportTable ::
  ([[Cell NumLines Text]], [[Cell NumLines Text]], [[Cell NumLines Text]]) -> Html
reportTable (header, body, totals) =
  H.div ! A.class_ "table-responsive report-table" $
    H.table ! A.class_ "balancereport table table-condensed" $ do
      H.thead $ rows header
      H.tbody $ rows body
      H.tfoot $ rows totals
  where
    rows = traverse_ (formatRow . map (fmap H.toHtml))
