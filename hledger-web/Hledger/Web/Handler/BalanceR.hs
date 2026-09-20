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
import Hledger.Web.Import
import Hledger.Web.WebOptions
import Hledger.Write.Html.Blaze (formatRow)
import Hledger.Write.Spreadsheet (Cell, NumLines)


-- | The balance or multi-period balance view, with sidebar.
getBalanceR :: Handler Html
getBalanceR = do
  checkServerSideUiEnabled
  VD{j, q, qparam, opts, today} <- getViewData
  require ViewPermission
  -- The period parameter is a period expression as for -p: an interval
  -- ("monthly"), a date span ("2024"), or both ("monthly in 2024").
  -- An empty one is no period at all, as from a search form with nothing in it.
  mperiod <- (>>= \p -> if p == "" then Nothing else Just p) <$> lookupGetParam "period"
  let title :: Text
      title = "Balance Report" <> if q /= Any then ", filtered" else ""
      rspecOrig = reportspec_ $ cliopts_ opts
      roptsOrig = _rsReportOpts rspecOrig
      eperiod = case mperiod of
        -- No period: keep the interval the server was started with (-M, -p ...).
        Nothing -> Right (interval_ roptsOrig, nulldatespan)
        Just p  -> either (Left . errorBundlePretty) Right $ parsePeriodExpr today p

  defaultLayout $ do
    setTitle "balance - hledger-web"
    case eperiod of
      Left err -> Yesod.toWidget $
        H.div ! A.class_ "alert alert-danger" $ do
          "Could not parse the period expression:"
          H.pre $ H.toHtml err
      Right (ivl, spn) -> Yesod.toWidget $ do
        let -- The links in the report carry the search, and the period's
            -- date span as a date: term, so that a row's register link is
            -- restricted the same way the report is.
            spanterm = ["date:" <> showDateSpan spn | spn /= nulldatespan]
            ropts =
              roptsOrig {
                balance_base_url_ = Just "",
                querystring_ = Query.words'' queryprefixes qparam ++ spanterm,
                interval_ = ivl
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
        H.h2 $ H.toHtml title
        reportTable $ case ivl of
          NoInterval ->
            let (header, body, totals) =
                  Balance.balanceReportAsSpreadsheetParts oneLineNoCostFmt ropts $
                    balanceReport rspec j
            in ([toList header], map toList body, map toList totals)
          _ ->
            let mbr = multiBalanceReport rspec j
            in Balance.multiBalanceReportAsSpreadsheetParts oneLineNoCostFmt ropts
                 (Balance.allCommoditiesFromPeriodicReport $ prRows mbr) mbr

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
