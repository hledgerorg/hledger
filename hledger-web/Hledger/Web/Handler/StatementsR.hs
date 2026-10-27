-- | The financial statement pages: /balancesheet, /incomestatement, and
-- /cashflow, showing the reports of the commands of the same names. The
-- balance sheet shows balancesheetequity's report with an equity=1
-- parameter; /balancesheetequity, its own page once, redirects there.

{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE OverloadedStrings #-}

module Hledger.Web.Handler.StatementsR (
  getBalancesheetR,
  getBalancesheetequityR,
  getIncomestatementR,
  getCashflowR,
) where

import Text.Blaze.Html5 ((!))
import Text.Blaze.Html5 qualified as H
import Text.Blaze.Html5.Attributes qualified as A
import Yesod qualified
import Data.Text qualified as T

import Hledger
import Hledger.Cli.Chart (compoundBalanceReportAsChart)
import Hledger.Cli.CliOptions
import Hledger.Cli.Commands.Balancesheet (balancesheetSpec)
import Hledger.Cli.Commands.Balancesheetequity (balancesheetequitySpec)
import Hledger.Cli.Commands.Cashflow (cashflowSpec)
import Hledger.Cli.Commands.Incomestatement (incomestatementSpec)
import Hledger.Cli.CompoundBalanceCommand
import Hledger.Utils.I18n (Translations, i18n, tr, trc, trf)
import Hledger.Write.Spreadsheet qualified as Spr

import Hledger.Web.Import
import Hledger.Web.Widget.AddForm (addModal)
import Hledger.Web.Paging (yearsRow)
import Hledger.Web.ReportPage
import Hledger.Web.WebOptions
import Hledger.Web.Widget.Chart (reportChart)
import Hledger.Web.Widget.Common
  (amountLinks, calcLinks, columnsLinks, commodityLinks, controlsToggle, optionsSummary,
   depthLinks, equityLinks, helplink,
   listModeLinks, lotsLinks, percentLinks, pricesLinks, realLinks,
   sortLinks, statusLinks, zeroBalanceLinks)

getBalancesheetR, getBalancesheetequityR, getIncomestatementR, getCashflowR :: Handler Html
-- TRANSLATORS: the browser tab titles of the statement pages.
getBalancesheetR = do
  equity <- (== Just "1") <$> lookupGetParam "equity"
  if equity
    then statementPage BalancesheetR (i18n "balance sheet with equity - hledger-web") balancesheetequitySpec (Just True)
    else statementPage BalancesheetR (i18n "balance sheet - hledger-web")             balancesheetSpec       (Just False)
getIncomestatementR = statementPage IncomestatementR (i18n "income statement - hledger-web")   incomestatementSpec Nothing
getCashflowR        = statementPage CashflowR        (i18n "cashflow statement - hledger-web") cashflowSpec        Nothing

-- | The balance sheet with equity, once a page of its own, is now the
-- balance sheet's equity=1; old links and bookmarks are sent there.
getBalancesheetequityR = do
  params <- reqGetParams <$> getRequest
  redirect (BalancesheetR, filter ((/= "equity") . fst) params ++ [("equity", "1")])

-- | A statement page: the command's report for the page's search and
-- period, with sidebar. The report's own accumulation mode applies
-- (ending balances for the balance sheets, changes for the others)
-- unless an accum parameter overrides it, which the heading then says,
-- as the command's does. On the balance sheet, an Equity row among the
-- controls says whether equity is shown, by the report given.
statementPage :: AppRoute -> Text -> CompoundBalanceCommandSpec -> Maybe Bool -> Handler Html
statementPage here tabtitle spec mequity = do
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
    setTitleI (HMsg tabtitle)
    case reportParams rspecOrig qparam q qopts hideEmpty params of
      Left err -> Yesod.toWidget $ do
        H.h2 $ H.toHtml $ withFilter $ effectiveTitle roptsOrig $ tr trs $ cbctitle spec NoInterval
        paramError trs err
      Right ReportParams{rpRopts, rpRspec, rpInterval, rpAccum, rpValue} -> do
        let accum = fromMaybe (cbcaccum spec) rpAccum
            override = mfilter (/= cbcaccum spec) rpAccum
            ropts = rpRopts{balanceaccum_ = accum}
            rspec = rpRspec{_rsReportOpts = ropts}
            styles = journalCommodityStylesWith HardRounding j
            cbrAsked = styleAmounts styles $ compoundBalanceReport rspec j (cbcqueries spec)
        -- Percentages can be impossible in the data (amounts in mixed
        -- commodities); probe the report for that error and show plain
        -- amounts with an explanation instead of an error page, keeping
        -- the url's percent state. See BalanceR.
        pctErr <- if percent_ ropts then liftIO $ reportProbe cbrAsked else pure Nothing
        let roptsR = if isJust pctErr then ropts{percent_ = False} else ropts
            rspecR = rspec{_rsReportOpts = roptsR}
            cbr0 | isJust pctErr = styleAmounts styles $ compoundBalanceReport rspecR j (cbcqueries spec)
                 | otherwise = cbrAsked
            cbr =
              applySubreportTitles ropts $
                cbr0{cbrTitle = effectiveTitle ropts $ compoundBalanceReportTitle spec rpRopts override cbr0}
            colspans = cbrDates cbr
            -- The chart, as the command's --chart draws it, of the report
            -- clipped at any depth limit the table folds at.
            chart = compoundBalanceReportAsChart (journalAccountType j) (compoundBalanceSectionTypes $ cbcqueries spec) roptsR $
              maybe cbr (\rs -> cbr{cbrSubreports = cbrSubreports $ styleAmounts styles $ compoundBalanceReport rs j (cbcqueries spec)})
                (chartReportSpec q rspecR)
            -- What links staying on this page keep: the period as given, the
            -- accumulation mode when it is not the report's own, and each
            -- report-shaping parameter that is not at its default.
            intervalParams = [("interval", w) | Just w <- [intervalPeriodExpr rpInterval]]
            accumParams = [("accum", accumWord accum) | accum /= cbcaccum spec]
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
            equityParams = [("equity", "1") | mequity == Just True]
            pageParams =
              dbg1 "statement pageParams" $
              equityParams ++ intervalParams ++ accumParams ++ valParams ++ listParams ++
              totalParams ++ avgParams ++ sortParams ++ pctParams ++ calcParams ++
              inferParams ++ date2Params ++ emptyParams ++ lotsParams ++ depthParams q
            qParams = [("q", qparam) | not (T.null qparam)]
            -- The figures' registers convert amounts as the report does. One
            -- showing them as recorded must say so when the register's
            -- default, the startup options', converts them.
            registerParams =
              [("value", "none") | amountModeOf ropts == Just AsRecorded, amountModeOf roptsOrig /= Just AsRecorded] ++
              removeAttributes ["accum", "value", "equity"] pageParams
            -- TRANSLATORS: the name of a depth 0 report's one row, all accounts in one.
            relink = map (map (labelAllAccounts (trc trs "accounts" "All") . addLinkParams registerParams))
            headinglink = urlrender here . headingParams rpInterval qparam params
            CompoundBalanceReportParts{cbrpLeadingHeaders, cbrpDataHeaders, cbrpSections, cbrpNetRows} =
              compoundBalanceReportAsSpreadsheetParts oneLineNoCostFmt "account" roptsR (cbcqueries spec) cbr
            -- The heading row with the classes the stylesheet aligns the
            -- columns by, and this page's column headings and links.
            withClass c cell = cell{Spr.cellClass = Spr.Class c}
            header =
              map (withClass "account") cbrpLeadingHeaders ++
              relinkDateHeaders trs (columnHeading ropts colspans) headinglink colspans (map (withClass "amount") cbrpDataHeaders)
            sections =
              [ (sectionTitle title prefix, body', relink subtotals)
              | (title, body, subtotals) <- cbrpSections
              , let (prefix, body') = stripShared (relink body) ]
            -- In flat mode each subreport's rows drop their shared account
            -- prefix and dim the remaining parent path (splitAccountNames).
            -- A single-component prefix is implied by the section title;
            -- a deeper one is named beside it, or it would show nowhere.
            stripShared body
              | accountlistmode_ ropts == ALTree = (Nothing, body)
              | otherwise = splitAccountNames body
            sectionTitle title prefix = mfilter (not . T.null) $ Just $ case prefix of
              Just p | T.any (== ':') p -> title <> " — " <> p
              _ -> title
            noRows = all (\(_, r, _) -> null $ prRows r) . cbrSubreports
            empty = noRows cbr
            -- An empty report with zero balances hidden may have them all: look again showing them.
            zerosHidden = hideEmpty && not (noRows $ compoundBalanceReport rspecR{_rsReportOpts = roptsR{empty_ = True}} j (cbcqueries spec))
        let isTree = accountlistmode_ ropts == ALTree
            mfold = fold_depth_ ropts
            -- No type row among the controls: the statements choose their
            -- own account types.
            -- The years the search matches in, ignoring all date
            -- narrowing, as a row of links among the controls; the year
            -- links rewrite the search's date narrowing themselves.
            yearsDays = map tdate $
              entriesReport rspecOrig{_rsQuery = filterQuery (\x -> not (queryIsDateOrDate2 x || queryIsDepth x)) q} j
            yearsNav = yearsRow trs here qparam today pageParams yearsDays
            controlRows = controlsToggle trs controlsOpen (optionsSummary trs deepest pageParams) $ \render -> foldMap ($ render) $
              [ equityLinks trs here (qParams ++ removeAttributes ["equity"] pageParams) shown | Just shown <- [mequity] ] ++
              [ accumulationLinks trs here (qParams ++ removeAttributes ["accum"] pageParams) (cbcaccum spec) accum
              , intervalLinks trs here (removeAttributes ["interval"] pageParams) qparam rpInterval
              , yearsNav
              , statusLinks trs here pageParams qparam
              , realLinks trs here pageParams qparam
              , commodityLinks trs here pageParams qparam commoditiesOpen
                  -- TRANSLATORS: the hint below the commodity filter row.
                  (tr trs "Shift-click selects several commodities.") j ] ++
              [ depthLinks trs here pageParams qparam deepest | deepest > 1 ] ++
              [ listModeLinks trs here (qParams ++ removeAttributes ["list"] pageParams) (accountlistmode_ roptsOrig) (accountlistmode_ ropts)
              , amountLinks trs here (qParams ++ removeAttributes ["value"] pageParams) (amountModeOf roptsOrig) (amountModeOf ropts)
              , pricesLinks trs here (qParams ++ removeAttributes ["infer"] pageParams) (infer_prices_ ropts)
              , zeroBalanceLinks trs here (qParams ++ removeAttributes ["empty"] pageParams) (empty_ roptsOrig) hideEmpty ] ++
              [ lotsLinks trs here (qParams ++ removeAttributes ["lots"] pageParams) lotsShown | jHasLots ] ++
              [ columnsLinks trs here (qParams ++ removeAttributes ["total", "avg"] pageParams) (row_total_ ropts) (average_ ropts)
              | rpInterval /= NoInterval ] ++
              [ sortLinks trs here (qParams ++ removeAttributes ["sort"] pageParams) (sort_amount_ ropts)
              , percentLinks trs here (qParams ++ removeAttributes ["pct"] pageParams) (percent_ ropts)
              , calcLinks trs here (qParams ++ removeAttributes ["calc"] pageParams) (balancecalc_ ropts) ]
        Yesod.toWidget controlRows
        Yesod.toWidget $ H.h2 $ H.toHtml $ withFilter $ cbrTitle cbr
        for_ pctErr $ Yesod.toWidget . pctError trs
        if empty
          then Yesod.toWidget $ emptyNotice trs zerosHidden (q == Any)
          else do
            reportChart trs (withFilter $ cbrTitle cbr) chart
            Yesod.toWidget $ reportTable isTree mfold [header] sections (relink cbrpNetRows)

-- | What an empty statement shows instead of a table: that its accounts
-- all have zero balances, which are hidden; or, for the whole journal,
-- that it has no accounts of the types the report shows, with a pointer
-- to how types are found; or, for a search or a period, that nothing
-- matched.
emptyNotice :: Translations -> Bool -> Bool -> HtmlUrl AppRoute
emptyNotice trs zerosHidden whole render =
  H.div ! A.class_ "alert alert-info" $
    if zerosHidden then H.toHtml $ tr trs "All the accounts this report shows have zero balances, which are hidden. Press z to show them."
    else if whole
      then do
        H.toHtml $ tr trs "No accounts of the types this report shows were found. Declare account types, or use hledger's standard top-level account names. "
        helplink "account-types" (tr trs "How hledger finds account types") render
      else H.toHtml $ tr trs "Nothing matches this search in this period."
