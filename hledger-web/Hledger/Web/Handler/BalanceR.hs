-- | /balance handlers.

{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE OverloadedStrings #-}

module Hledger.Web.Handler.BalanceR where

import Data.Text qualified as Text
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
  let title :: Text
      title = "Balance Report" <> if q /= Any then ", filtered" else ""
      rspecOrig = reportspec_ $ cliopts_ opts
      ropts =
        (_rsReportOpts rspecOrig) {
          balance_base_url_ = Just "",
          querystring_ = Query.words'' queryprefixes qparam
        }
      -- Unlike the journal and register pages, keep any depth limit:
      -- the report reads it from the query, and it is how a balance
      -- report gets summarized (--depth at startup, or depth: in the search).
      rspec =
        rspecOrig {
          _rsQuery = q,
          _rsReportOpts = ropts
        }

  defaultLayout $ do
    mperiod <- lookupGetParam "period"
    case mperiod of
      Nothing -> do
        setTitle "balance - hledger-web"
        Yesod.toWidget $ do
          H.h2 $ H.toHtml title
          let (header, body, totals) =
                Balance.balanceReportAsSpreadsheetParts oneLineNoCostFmt ropts $
                  balanceReport rspec j
          reportTable ([toList header], map toList body, map toList totals)
      Just perStr -> do
        setTitle "multibalance - hledger-web"
        case parsePeriodExpr today perStr of
          Left msg -> Yesod.toWidget $ Text.pack $ errorBundlePretty msg
          Right (per_,_) ->
            Yesod.toWidget $ do
              H.h2 $ H.toHtml title
              let rspec' = rspec{_rsReportOpts = ropts{interval_ = per_}}
                  mbr = multiBalanceReport rspec' j
              reportTable $
                Balance.multiBalanceReportAsSpreadsheetParts oneLineNoCostFmt ropts
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
