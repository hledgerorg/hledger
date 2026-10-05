-- | The financial statement pages: /balancesheet, /balancesheetequity,
-- /incomestatement, and /cashflow, showing the reports of the commands
-- of the same names.

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
import Hledger.Cli.CliOptions
import Hledger.Cli.Commands.Balancesheet (balancesheetSpec)
import Hledger.Cli.Commands.Balancesheetequity (balancesheetequitySpec)
import Hledger.Cli.Commands.Cashflow (cashflowSpec)
import Hledger.Cli.Commands.Incomestatement (incomestatementSpec)
import Hledger.Cli.CompoundBalanceCommand
import Hledger.Utils.I18n (Translations, i18n, tr, trf)
import Hledger.Write.Spreadsheet qualified as Spr

import Hledger.Web.Import
import Hledger.Web.ReportPage
import Hledger.Web.WebOptions
import Hledger.Web.Widget.Common
  (accumulationLinks, amountLinks, calcLinks, columnsLinks, depthLinks,
   helplink, intervalLinks,
   listModeLinks, percentLinks, realLinks, removeDates, removeInacct, reportLinks,
   sortLinks, statusLinks, zeroBalanceLinks)

getBalancesheetR, getBalancesheetequityR, getIncomestatementR, getCashflowR :: Handler Html
-- TRANSLATORS: the browser tab titles of the statement pages.
getBalancesheetR       = statementPage BalancesheetR       (i18n "balance sheet - hledger-web")             balancesheetSpec
getBalancesheetequityR = statementPage BalancesheetequityR (i18n "balance sheet with equity - hledger-web") balancesheetequitySpec
getIncomestatementR    = statementPage IncomestatementR    (i18n "income statement - hledger-web")          incomestatementSpec
getCashflowR           = statementPage CashflowR           (i18n "cashflow statement - hledger-web")        cashflowSpec

-- | A statement page: the command's report for the page's search and
-- period, with sidebar. The report's own accumulation mode applies
-- (ending balances for the balance sheets, changes for the others)
-- unless an accum parameter overrides it, which the heading then says,
-- as the command's does.
statementPage :: AppRoute -> Text -> CompoundBalanceCommandSpec -> Handler Html
statementPage here tabtitle spec = do
  checkServerSideUiEnabled
  VD{j, q, qopts, qparam, opts, today, trs} <- getViewData
  require ViewPermission
  hideEmpty <- hideEmptyAccounts
  getparams <- reqGetParams <$> getRequest
  urlrender <- getUrlRenderParams
  let withFilter t = if q /= Any then trf trs "{title}, filtered" [("title", t)] else t
      rspecOrig = reportspec_ $ cliopts_ opts
      roptsOrig = _rsReportOpts rspecOrig
      menu = reportLinkItems reportMenu
      deepest = deepestDepth rspecOrig j

  defaultLayout $ do
    setTitleI (HMsg tabtitle)
    case reportParams today rspecOrig qparam q qopts hideEmpty (`lookup` getparams) of
      Left err -> Yesod.toWidget $ do
        H.h2 $ H.toHtml $ withFilter $ effectiveTitle roptsOrig $ tr trs $ cbctitle spec NoInterval
        paramError trs err
      Right ReportParams{rpRopts, rpRspec, rpSpan, rpInterval, rpPeriod, rpAccum, rpValue} -> do
        let accum = fromMaybe (cbcaccum spec) rpAccum
            override = mfilter (/= cbcaccum spec) rpAccum
            ropts = rpRopts{balanceaccum_ = accum}
            rspec = rpRspec{_rsReportOpts = ropts}
            cbr0 =
              styleAmounts (journalCommodityStylesWith HardRounding j) $
                compoundBalanceReport rspec j (cbcqueries spec)
            cbr =
              applySubreportTitles ropts $
                cbr0{cbrTitle = effectiveTitle ropts $ compoundBalanceReportTitle spec rpRopts override cbr0}
            colspans = cbrDates cbr
            -- What links staying on this page keep: the period as given, the
            -- accumulation mode when it is not the report's own, and each
            -- report-shaping parameter that is not at its default.
            periodParams = [("period", p) | Just p <- [rpPeriod]]
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
            pageParams =
              dbg1 "statement pageParams" $
              periodParams ++ accumParams ++ valParams ++ listParams ++
              totalParams ++ avgParams ++ sortParams ++ pctParams ++ calcParams ++
              inferParams ++ date2Params ++ emptyParams
            withoutKs ks = filter ((`notElem` ks) . fst)
            qParams = [("q", qparam) | not (T.null qparam)]
            -- Links to the other reports keep the search, minus any account
            -- term, which the reports ignore, and this page's parameters,
            -- apart from the accumulation mode, which each report defaults.
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
            headinglink spn = urlrender here $
              ("period", showDateSpanForQuery spn) :
              [("q", qt) | let qt = T.unwords $ removeDates qparam, not (T.null qt)] ++
              withoutKs ["period"] pageParams
            CompoundBalanceReportParts{cbrpLeadingHeaders, cbrpDataHeaders, cbrpSections, cbrpNetRows} =
              compoundBalanceReportAsSpreadsheetParts oneLineNoCostFmt "account" ropts (cbcqueries spec) cbr
            -- The heading row with the classes the stylesheet aligns the
            -- columns by, and this page's column headings and links.
            withClass c cell = cell{Spr.cellClass = Spr.Class c}
            header =
              map (withClass "account") cbrpLeadingHeaders ++
              relinkDateHeaders trs (columnHeading ropts colspans) headinglink colspans (map (withClass "amount") cbrpDataHeaders)
            sections = [(mfilter (not . T.null) (Just title), relink body, relink subtotals) | (title, body, subtotals) <- cbrpSections]
            noRows = all (\(_, r, _) -> null $ prRows r) . cbrSubreports
            empty = noRows cbr
            -- An empty report with zero balances hidden may have them all: look again showing them.
            zerosHidden = hideEmpty && not (noRows $ compoundBalanceReport rspec{_rsReportOpts = ropts{empty_ = True}} j (cbcqueries spec))
        let isTree = accountlistmode_ ropts == ALTree
            mfold = mfilter (const isTree) $ dsFlatDepth $ queryDepth q
            -- Every control the page responds to, one row of links each.
            -- No type row: the statements choose their own account types.
            controlRows render = foldMap ($ render) $
              [ reportLinks trs here menuParams menu
              , accumulationLinks trs here (qParams ++ withoutKs ["accum"] pageParams) (cbcaccum spec) accum
              , intervalLinks trs here (withoutKs ["period"] pageParams) qparam rpSpan rpInterval
              , statusLinks trs here pageParams qparam
              , realLinks trs here pageParams qparam ] ++
              [ depthLinks trs here pageParams qparam deepest | deepest > 1 ] ++
              [ listModeLinks trs here (qParams ++ withoutKs ["list"] pageParams) (accountlistmode_ roptsOrig) (accountlistmode_ ropts)
              , amountLinks trs here (qParams ++ withoutKs ["value"] pageParams) (amountModeOf roptsOrig) (amountModeOf ropts)
              , zeroBalanceLinks trs here (qParams ++ withoutKs ["empty"] pageParams) (empty_ roptsOrig) hideEmpty ] ++
              [ columnsLinks trs here (qParams ++ withoutKs ["total", "avg"] pageParams) (row_total_ ropts) (average_ ropts)
              | rpInterval /= NoInterval ] ++
              [ sortLinks trs here (qParams ++ withoutKs ["sort"] pageParams) (sort_amount_ ropts)
              , percentLinks trs here (qParams ++ withoutKs ["pct"] pageParams) (percent_ ropts)
              , calcLinks trs here (qParams ++ withoutKs ["calc"] pageParams) (balancecalc_ ropts) ]
        Yesod.toWidget $ H.h2 $ H.toHtml $ withFilter $ cbrTitle cbr
        Yesod.toWidget controlRows
        if empty
          then Yesod.toWidget $ emptyNotice trs zerosHidden (q == Any && rpSpan == nulldatespan)
          else Yesod.toWidget $ reportTable isTree mfold [header] sections (relink cbrpNetRows)

-- | What an empty statement shows instead of a table: that its accounts
-- all have zero balances, which are hidden; or, for the whole journal,
-- that it has no accounts of the types the report shows, with a pointer
-- to how types are found; or, for a search or a period, that nothing
-- matched.
emptyNotice :: Translations -> Bool -> Bool -> HtmlUrl AppRoute
emptyNotice trs zerosHidden whole render =
  H.div ! A.class_ "alert alert-info" $
    if zerosHidden then H.toHtml $ tr trs "All the accounts this report shows have zero balances, which are hidden. Press e to show them."
    else if whole
      then do
        H.toHtml $ tr trs "No accounts of the types this report shows were found. Declare account types, or use hledger's standard top-level account names. "
        helplink "account-types" (tr trs "How hledger finds account types") render
      else H.toHtml $ tr trs "Nothing matches this search in this period."
