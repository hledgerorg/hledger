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
import Hledger.Utils.I18n (tr, trc, trf)

import Hledger.Web.Import
import Hledger.Web.Widget.AddForm (addModal)
import Hledger.Web.Paging (yearsRow)
import Hledger.Web.ReportPage as Report
import Hledger.Web.WebOptions
import Hledger.Web.Widget.Common qualified as Report
import Hledger.Web.Widget.Common (controlsToggle, optionsSummary)


-- | The balance or multi-period balance view, with sidebar.
getBalanceR :: Handler Html
getBalanceR = do
  checkServerSideUiEnabled
  VD{perms, j, jHasLots, lotsShown, q, qopts, qparam, opts, today, trs, hideEmpty, controlsOpen, commoditiesOpen} <- getViewData
  require ViewPermission
  params <- reqGetParams <$> getRequest
  urlrender <- getUrlRenderParams
  -- the title names the dates, and the depth limit is an option, not a filter
  let dateless = filterQuery (\x -> not (queryIsDateOrDate2 x || queryIsDepth x))
      withFilter t = if dateless q /= Any then trf trs "{title}, filtered" [("title", t)] else t
      rspecOrig = reportspec_ $ cliopts_ opts
      roptsOrig = _rsReportOpts rspecOrig
      deepest = deepestDepth j

  defaultLayout $ do
    -- the add form, which the a key opens
    when (AddPermission `elem` perms) $ addModal AddR j today
    -- TRANSLATORS: the browser tab title of this page.
    setTitleI (HMsg "balance - hledger-web")
    case reportParams rspecOrig qparam q qopts hideEmpty params of
      Left err -> Yesod.toWidget $ do
        H.h2 $ H.toHtml $ withFilter $ reportTitle roptsOrig $ tr trs "All accounts"
        paramError trs err
      Right ReportParams{rpRopts, rpRspec, rpInterval, rpAccum, rpValue} -> do
        let -- The page shows balance changes unless another mode was asked for.
            accum = fromMaybe PerPeriod rpAccum
            ropts = rpRopts{balanceaccum_ = accum}
            rspec = rpRspec{_rsReportOpts = ropts}
            styles = journalCommodityStylesWith HardRounding j
            mbrAsked = styleAmounts styles $ multiBalanceReport rspec j
        -- Percentages divide each amount by its column's total, which
        -- needs them in one commodity; whether they are is in the data,
        -- so the report, not reportParams, raises the error. Probe for
        -- it, and show plain amounts with an explanation instead of an
        -- error page. Only the report falls back: the links and the
        -- Numbers row keep the url's percent state.
        pctErr <- if percent_ ropts then liftIO $ reportProbe mbrAsked else pure Nothing
        let roptsR = if isJust pctErr then ropts{percent_ = False} else ropts
            rspecR = rspec{_rsReportOpts = roptsR}
            mbr | isJust pctErr = styleAmounts styles $ multiBalanceReport rspecR j
                | otherwise = mbrAsked
            colspans = prDates mbr
            -- What links staying on this page keep: the period as given, and each
            -- report-shaping parameter that is not at its default.
            intervalParams = [("interval", w) | Just w <- [intervalPeriodExpr rpInterval]]
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
            lotsParams  = [("lots", "1") | lotsShown]
            pageParams =
              dbg1 "balance pageParams" $
              intervalParams ++ accumParams ++ valParams ++ listParams ++
              totalParams ++ avgParams ++ sortParams ++ pctParams ++ calcParams ++
              inferParams ++ date2Params ++ emptyParams ++ lotsParams ++ depthParams q
            qParams = [("q", qparam) | not (T.null qparam)]
            -- The figures' registers convert amounts as the report does. One
            -- showing them as recorded must say so when the register's
            -- default, the startup options', converts them. The sticky
            -- report state travels along too; the link rewrites only the
            -- search's dates.
            registerParams =
              [("value", "none") | amountModeOf ropts == Just AsRecorded, amountModeOf roptsOrig /= Just AsRecorded] ++
              removeAttributes ["accum", "value"] pageParams
            -- TRANSLATORS: the name of a depth 0 report's one row, all accounts in one.
            relink = map (map (labelAllAccounts (trc trs "accounts" "All") . addLinkParams registerParams))
            headinglink = urlrender BalanceR . headingParams rpInterval qparam params
            -- The heading, and the report's rows in three parts, for the
            -- table's thead, tbody, and tfoot.
            (title, header, body, totals) = case rpInterval of
              NoInterval ->
                let (h, b, t) =
                      Balance.balanceReportAsSpreadsheetParts oneLineNoCostFmt roptsR $
                        styleAmounts styles $ balanceReport rspecR j
                    -- The plain page has its own name; one narrowed to a
                    -- period, or showing ending balances, says so like the
                    -- multi-period page does.
                    dflt | queryDateSpan (date2_ ropts) (_rsQuery rspec) == nulldatespan && accum == PerPeriod = tr trs "All accounts"
                         | otherwise = trimColon $ Balance.multiBalanceReportTitle roptsR mbr
                in (reportTitle ropts dflt, [toList h], relink $ map toList b, relink $ map toList t)
              _ ->
                let (h, b, t) = Balance.multiBalanceReportAsSpreadsheetParts oneLineNoCostFmt roptsR mbr
                in ( reportTitle ropts $ trimColon $ Balance.multiBalanceReportTitle roptsR mbr
                   , map (relinkDateHeaders trs (columnHeading ropts colspans) headinglink colspans) h, relink b, relink t)
        let isTree = accountlistmode_ ropts == ALTree
            mfold = fold_depth_ ropts
            -- In flat mode the account names' shared prefix is shown once,
            -- as a group heading, and each row shows only the rest, its
            -- remaining parent path dimmed (see splitAccountNames).
            (acctsPrefix, body')
              | isTree = (Nothing, body)
              | otherwise = splitAccountNames body
            -- The years the search matches in, ignoring all date
            -- narrowing, as a row of links among the controls; the year
            -- links rewrite the search's date narrowing themselves.
            yearsDays = map tdate $
              entriesReport rspecOrig{_rsQuery = filterQuery (\x -> not (queryIsDateOrDate2 x || queryIsDepth x)) q} j
            yearsNav = yearsRow trs BalanceR qparam today pageParams yearsDays
            controlRows = controlsToggle trs controlsOpen (optionsSummary trs deepest pageParams) $ \render -> foldMap ($ render) $
              [ Report.accumulationLinks trs BalanceR (qParams ++ removeAttributes ["accum"] pageParams) PerPeriod accum
              , Report.intervalLinks trs BalanceR (removeAttributes ["interval"] pageParams) qparam rpInterval
              , yearsNav
              , Report.statusLinks trs BalanceR pageParams qparam
              , Report.realLinks trs BalanceR pageParams qparam
              , Report.typeLinks trs BalanceR pageParams qparam
              -- TRANSLATORS: the hint below the account type filter row.
              , Report.controlsHint $ tr trs "Shift-click selects several types."
              , Report.commodityLinks trs BalanceR pageParams qparam commoditiesOpen
                  -- TRANSLATORS: the hint below the commodity filter row.
                  (tr trs "Shift-click selects several commodities.") j ] ++
              [ Report.depthLinks trs BalanceR pageParams qparam deepest | deepest > 1 ] ++
              [ Report.listModeLinks trs BalanceR (qParams ++ removeAttributes ["list"] pageParams) (accountlistmode_ roptsOrig) (accountlistmode_ ropts)
              , Report.amountLinks trs BalanceR (qParams ++ removeAttributes ["value"] pageParams) (amountModeOf roptsOrig) (amountModeOf ropts)
              , Report.pricesLinks trs BalanceR (qParams ++ removeAttributes ["infer"] pageParams) (infer_prices_ ropts)
              , Report.zeroBalanceLinks trs BalanceR (qParams ++ removeAttributes ["empty"] pageParams) (empty_ roptsOrig) hideEmpty ] ++
              [ Report.lotsLinks trs BalanceR (qParams ++ removeAttributes ["lots"] pageParams) lotsShown | jHasLots ] ++
              [ Report.columnsLinks trs BalanceR (qParams ++ removeAttributes ["total", "avg"] pageParams) (row_total_ ropts) (average_ ropts)
              | rpInterval /= NoInterval ] ++
              [ Report.sortLinks trs BalanceR (qParams ++ removeAttributes ["sort"] pageParams) (sort_amount_ ropts)
              , Report.percentLinks trs BalanceR (qParams ++ removeAttributes ["pct"] pageParams) (percent_ ropts)
              , Report.calcLinks trs BalanceR (qParams ++ removeAttributes ["calc"] pageParams) (balancecalc_ ropts) ]
        Yesod.toWidget controlRows
        Yesod.toWidget $ H.h2 $ H.toHtml $ withFilter title
        for_ pctErr $ Yesod.toWidget . pctError trs
        Yesod.toWidget $ reportTable isTree mfold header [(acctsPrefix, body', [])] totals

-- | The heading for a report: --title if one was given, otherwise the
-- given default.
reportTitle :: ReportOpts -> Text -> Text
reportTitle ropts dflt = fromMaybe dflt $ title_ ropts

-- | Drop the trailing colon of a command line report title, which a heading
-- does not want. A translation of it may end in " :" or "：" instead,
-- so drop whichever is there.
trimColon :: Text -> Text
trimColon = T.dropWhileEnd (`elem` (":\65306 " :: String))
