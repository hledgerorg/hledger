-- | /balance handlers.

{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE OverloadedStrings #-}

module Hledger.Web.Handler.BalanceR where

import Hledger
import Hledger.Cli.CliOptions
import Hledger.Write.Html.Blaze (styledTableHtml)
import Hledger.Web.Import
import Hledger.Web.WebOptions
import qualified Hledger.Cli.Commands.Balance as Balance
import qualified Hledger.Query as Query

import Text.Megaparsec.Error (errorBundlePretty)
import qualified Text.Blaze.Html4.Strict as Blaze
import qualified Data.Text as Text
import qualified Yesod


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
      rspec =
        rspecOrig {
          _rsQuery = filterQuery (not . queryIsDepth) q,
          _rsReportOpts = ropts
        }

  defaultLayout $ do
    mperiod <- lookupGetParam "period"
    case mperiod of
      Nothing -> do
        setTitle "balance - hledger-web"
        Yesod.toWidget .
          (Blaze.h2 (Blaze.toHtml title) >>) .
          styledTableHtml . map (map (fmap Blaze.toHtml)) .
          Balance.balanceReportAsSpreadsheet oneLineNoCostFmt ropts $
            balanceReport rspec j
      Just perStr -> do
        setTitle "multibalance - hledger-web"
        case parsePeriodExpr today perStr of
          Left msg -> Yesod.toWidget $ Text.pack $ errorBundlePretty msg
          Right (per_,_) ->
            Yesod.toWidget .
              (Blaze.h2 (Blaze.toHtml title) >>) .
              styledTableHtml . map (map (fmap Blaze.toHtml)) .
              snd . Balance.multiBalanceReportAsSpreadsheet ropts $
                let rspec' = rspec{_rsReportOpts = ropts{interval_ = per_}} in
                multiBalanceReport rspec' j
