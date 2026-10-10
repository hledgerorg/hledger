-- | /balance handlers.

{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE OverloadedStrings #-}

module Hledger.Web.Handler.BalanceR where

import Text.Blaze.Html5 qualified as H
import Yesod qualified

import Hledger
import Hledger.Cli.CliOptions
import Hledger.Cli.Commands.Balance qualified as Balance
import Data.Text qualified as T
import Hledger.Utils.I18n (tr, trf)

import Hledger.Web.Import
import Hledger.Web.ReportPage
import Hledger.Web.WebOptions
import Hledger.Web.Widget.Common (accumulationLinks, intervalLinks, removeInacct, reportLinks)


-- | The balance or multi-period balance view, with sidebar.
getBalanceR :: Handler Html
getBalanceR = do
  checkServerSideUiEnabled
  VD{j, q, qopts, qparam, opts, today, trs} <- getViewData
  require ViewPermission
  params <- reqGetParams <$> getRequest
  hideEmpty <- hideEmptyAccounts
  urlrender <- getUrlRenderParams
  let withFilter t = if q /= Any then trf trs "{title}, filtered" [("title", t)] else t
      rspecOrig = reportspec_ $ cliopts_ opts
      roptsOrig = _rsReportOpts rspecOrig

  defaultLayout $ do
    -- TRANSLATORS: the browser tab title of this page.
    setTitleI (HMsg "balance - hledger-web")
    case reportParams today rspecOrig qparam q qopts hideEmpty params of
      Left err -> Yesod.toWidget $ do
        H.h2 $ H.toHtml $ withFilter $ reportTitle roptsOrig $ tr trs "Balance report"
        paramError trs err
      Right ReportParams{rpRopts, rpRspec, rpSpan, rpInterval, rpPeriod, rpAccum} -> do
        let -- The page shows balance changes unless asked for ending balances.
            accum = fromMaybe PerPeriod rpAccum
            ropts = rpRopts{balanceaccum_ = accum}
            rspec = rpRspec{_rsReportOpts = ropts}
            styles = journalCommodityStylesWith HardRounding j
            mbr = styleAmounts styles $ multiBalanceReport rspec j
            colspans = prDates mbr
            -- What links staying on this page keep: the period as given,
            -- and the mode when it is not the default.
            periodParams = [("period", p) | Just p <- [rpPeriod]]
            accumParams = [("accum", "historical") | accum == Historical]
            qParams = [("q", qparam) | not (T.null qparam)]
            -- links to the other reports keep the search, minus any account
            -- term, which the reports ignore, and the period as given
            menuParams = periodParams ++ [("q", qt) | let qt = T.unwords $ removeInacct qparam, not (T.null qt)]
            headinglink = urlrender BalanceR . headingParams qparam params
            -- The heading, and the report's rows in three parts, for the
            -- table's thead, tbody, and tfoot.
            (title, header, body, totals) = case rpInterval of
              NoInterval ->
                let (h, b, t) =
                      Balance.balanceReportAsSpreadsheetParts oneLineNoCostFmt ropts $
                        styleAmounts styles $ balanceReport rspec j
                    -- The plain page has its own name; one narrowed to a
                    -- period, or showing ending balances, says so like the
                    -- multi-period page does.
                    dflt | rpSpan == nulldatespan && accum == PerPeriod = tr trs "Balance report"
                         | otherwise = trimColon $ Balance.multiBalanceReportTitle ropts mbr
                in (reportTitle ropts dflt, [toList h], map toList b, map toList t)
              _ ->
                let (h, b, t) = Balance.multiBalanceReportAsSpreadsheetParts oneLineNoCostFmt ropts mbr
                in ( reportTitle ropts $ trimColon $ Balance.multiBalanceReportTitle ropts mbr
                   , map (relinkDateHeaders trs (columnHeading ropts colspans) headinglink colspans) h, b, t)
        Yesod.toWidget $ H.h2 $ H.toHtml $ withFilter title
        Yesod.toWidget $ reportLinks trs BalanceR menuParams $ reportLinkItems reportMenu
        Yesod.toWidget $ accumulationLinks trs BalanceR (periodParams ++ qParams) accum
        Yesod.toWidget $ intervalLinks trs BalanceR accumParams qparam rpSpan rpInterval
        Yesod.toWidget $ reportTable header [(Nothing, body, [])] totals

-- | The heading for a report: --title if one was given, otherwise the
-- given default.
reportTitle :: ReportOpts -> Text -> Text
reportTitle ropts dflt = fromMaybe dflt $ title_ ropts

-- | Drop the trailing colon of a command line report title, which a heading
-- does not want. A translation of it may end in " :" or "：" instead,
-- so drop whichever is there.
trimColon :: Text -> Text
trimColon = T.dropWhileEnd (`elem` (":\65306 " :: String))
