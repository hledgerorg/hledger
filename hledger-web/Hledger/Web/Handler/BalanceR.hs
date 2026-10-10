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
import Hledger.Web.Widget.Common
  (accumulationLinks, amountLinks, calcLinks, columnsLinks, depthLinks,
   intervalLinks, listModeLinks,
   percentLinks, realLinks, removeDates, removeInacct, reportLinks, sortLinks, statusLinks,
   typeLinks, zeroBalanceLinks)


-- | The balance or multi-period balance view, with sidebar.
getBalanceR :: Handler Html
getBalanceR = do
  checkServerSideUiEnabled
  VD{j, q, qopts, qparam, opts, today, trs} <- getViewData
  require ViewPermission
  hideEmpty <- hideEmptyAccounts
  getparams <- reqGetParams <$> getRequest
  urlrender <- getUrlRenderParams
  let withFilter t = if q /= Any then trf trs "{title}, filtered" [("title", t)] else t
      rspecOrig = reportspec_ $ cliopts_ opts
      roptsOrig = _rsReportOpts rspecOrig
      deepest = deepestDepth rspecOrig j

  defaultLayout $ do
    -- TRANSLATORS: the browser tab title of this page.
    setTitleI (HMsg "balance - hledger-web")
    case reportParams today rspecOrig qparam q qopts hideEmpty (`lookup` getparams) of
      Left err -> Yesod.toWidget $ do
        H.h2 $ H.toHtml $ withFilter $ reportTitle roptsOrig $ tr trs "Balance report"
        paramError trs err
      Right ReportParams{rpRopts, rpRspec, rpSpan, rpInterval, rpPeriod, rpAccum, rpValue} -> do
        let -- The page shows balance changes unless another mode was asked for.
            accum = fromMaybe PerPeriod rpAccum
            ropts = rpRopts{balanceaccum_ = accum}
            rspec = rpRspec{_rsReportOpts = ropts}
            styles = journalCommodityStylesWith HardRounding j
            mbr = styleAmounts styles $ multiBalanceReport rspec j
            colspans = prDates mbr
            -- What links staying on this page keep: the period as given, and each
            -- report-shaping parameter that is not at its default.
            periodParams = [("period", p) | Just p <- [rpPeriod]]
            accumParams = [("accum", accumWord accum) | accum /= PerPeriod]
            valParams = valueParams roptsOrig rpValue
            listParams  = [("list", listWord (accountlistmode_ ropts)) | accountlistmode_ ropts /= accountlistmode_ roptsOrig]
            totalParams = [("total", "1") | row_total_ ropts]
            avgParams   = [("avg", "1") | average_ ropts]
            sortParams  = [("sort", "amount") | sort_amount_ ropts]
            pctParams   = [("pct", "1") | percent_ ropts]
            calcParams  = [("calc", w) | Just w <- [calcWord $ balancecalc_ ropts]]
            inferParams = [("infer", "1") | infer_prices_ ropts, not (infer_prices_ roptsOrig)]
            date2Params = [("date2", "1") | date2_ ropts, not (date2_ roptsOrig)]
            emptyParams = [("empty", if hideEmpty then "0" else "1") | hideEmpty /= empty_ roptsOrig]
            pageParams =
              dbg1 "balance pageParams" $
              periodParams ++ accumParams ++ valParams ++ listParams ++
              totalParams ++ avgParams ++ sortParams ++ pctParams ++ calcParams ++
              inferParams ++ date2Params ++ emptyParams
            withoutKs ks = filter ((`notElem` ks) . fst)
            qParams = [("q", qparam) | not (T.null qparam)]
            -- links to the other reports keep the search, minus any account
            -- term, which the reports ignore, and this page's parameters,
            -- apart from the accumulation mode, which each report defaults
            menuParams = [("q", qt) | let qt = T.unwords $ removeInacct qparam, not (T.null qt)] ++ withoutKs ["accum"] pageParams
            -- The figures' registers convert amounts as the report does. One
            -- showing them as recorded must say so when the register's
            -- default, the startup options', converts them.
            registerParams =
              [("value", "none") | amountModeOf ropts == Just AsRecorded, amountModeOf roptsOrig /= Just AsRecorded] ++
              inferParams ++ date2Params ++ emptyParams
            relink = map (map (addLinkParams registerParams))
            -- A column heading opens this report for that column's period,
            -- in place of any date terms in the search, which the column
            -- narrows anyway.
            headinglink spn = urlrender BalanceR $
              ("period", showDateSpanForQuery spn) :
              [("q", qt) | let qt = T.unwords $ removeDates qparam, not (T.null qt)] ++
              withoutKs ["period"] pageParams
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
                in (reportTitle ropts dflt, [toList h], relink $ map toList b, relink $ map toList t)
              _ ->
                let (h, b, t) = Balance.multiBalanceReportAsSpreadsheetParts oneLineNoCostFmt ropts mbr
                in ( reportTitle ropts $ trimColon $ Balance.multiBalanceReportTitle ropts mbr
                   , map (relinkDateHeaders trs (columnHeading ropts colspans) headinglink colspans) h, relink b, relink t)
        let isTree = accountlistmode_ ropts == ALTree
            mfold = mfilter (const isTree) $ dsFlatDepth $ queryDepth q
            -- Every control the page responds to, one row of links each.
            controlRows render = foldMap ($ render) $
              [ reportLinks trs BalanceR menuParams $ reportLinkItems reportMenu
              , accumulationLinks trs BalanceR (qParams ++ withoutKs ["accum"] pageParams) PerPeriod accum
              , intervalLinks trs BalanceR (withoutKs ["period"] pageParams) qparam rpSpan rpInterval
              , statusLinks trs BalanceR pageParams qparam
              , realLinks trs BalanceR pageParams qparam
              , typeLinks trs BalanceR pageParams qparam ] ++
              [ depthLinks trs BalanceR pageParams qparam deepest | deepest > 1 ] ++
              [ listModeLinks trs BalanceR (qParams ++ withoutKs ["list"] pageParams) (accountlistmode_ roptsOrig) (accountlistmode_ ropts)
              , amountLinks trs BalanceR (qParams ++ withoutKs ["value"] pageParams) (amountModeOf roptsOrig) (amountModeOf ropts)
              , zeroBalanceLinks trs BalanceR (qParams ++ withoutKs ["empty"] pageParams) (empty_ roptsOrig) hideEmpty ] ++
              [ columnsLinks trs BalanceR (qParams ++ withoutKs ["total", "avg"] pageParams) (row_total_ ropts) (average_ ropts)
              | rpInterval /= NoInterval ] ++
              [ sortLinks trs BalanceR (qParams ++ withoutKs ["sort"] pageParams) (sort_amount_ ropts)
              , percentLinks trs BalanceR (qParams ++ withoutKs ["pct"] pageParams) (percent_ ropts)
              , calcLinks trs BalanceR (qParams ++ withoutKs ["calc"] pageParams) (balancecalc_ ropts) ]
        Yesod.toWidget $ H.h2 $ H.toHtml $ withFilter title
        Yesod.toWidget controlRows
        Yesod.toWidget $ reportTable isTree mfold header [(Nothing, body, [])] totals

-- | The heading for a report: --title if one was given, otherwise the
-- given default.
reportTitle :: ReportOpts -> Text -> Text
reportTitle ropts dflt = fromMaybe dflt $ title_ ropts

-- | Drop the trailing colon of a command line report title, which a heading
-- does not want. A translation of it may end in " :" or "：" instead,
-- so drop whichever is there.
trimColon :: Text -> Text
trimColon = T.dropWhileEnd (`elem` (":\65306 " :: String))
